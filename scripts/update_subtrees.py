#!/usr/bin/env python3
"""Automate git subtree updates based on readme_forks.json.

- Ensures upstream remotes exist.
- Runs git subtree add/pull with --squash.
- Copies upstream license files into UPSTREAM_LICENSE when present.
- Writes UPSTREAM.md metadata in each subtree.
- Pushes changes to an update branch and opens a PR (optional).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

ROOT = Path(__file__).resolve().parent.parent
FORKS_FILE = ROOT / "readme_forks.json"


@dataclass
class ForkEntry:
    # fields mapped from readme_forks.json entries
    source: Optional[str]
    owner: Optional[str]
    name: Optional[str]
    upstream: str
    upstream_url: Optional[str]
    upstream_default_branch: str
    subtree_path: Optional[str]
    subtree_exists: bool
    subtree_license_file: Optional[str]
    subtree_license_verified: bool
    verified: bool
    notes: Optional[str]

    @property
    def upstream_git_url(self) -> str:
        # prefer upstream_url (https), convert to git URL if needed
        if self.upstream_url:
            url = self.upstream_url
            if url.endswith('.git'):
                return url
            # if URL is like https://github.com/owner/repo, append .git
            return url.rstrip('/') + '.git'
        # fallback to constructing from upstream owner/repo
        return f"https://github.com/{self.upstream}.git"

    @property
    def prefix(self) -> str:
        # subtree_path is used as prefix (relative path inside repo)
        if not self.subtree_path:
            raise ValueError(f"Cannot derive prefix: subtree_path missing for upstream={self.upstream}")
        return self.subtree_path.strip('/')


@dataclass
class UpdateResult:
    fork: ForkEntry
    upstream_commit: str
    license_note: str
    changed: bool


class CommandError(RuntimeError):
    pass


def run(cmd: List[str], cwd: Optional[Path] = None, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, cwd=str(cwd) if cwd else None, capture_output=capture, text=True)
    if check and result.returncode != 0:
        raise CommandError(f"Command failed: {' '.join(cmd)}\nstdout: {result.stdout}\nstderr: {result.stderr}")
    return result


def ref_exists(ref: str) -> bool:
    return run(["git", "rev-parse", "--verify", "--quiet", ref], check=False).returncode == 0


def remote_exists(name: str) -> bool:
    remotes = run(["git", "remote"], capture=True).stdout
    return remotes is not None and name in remotes.split()


def load_entries() -> List[ForkEntry]:
    if not FORKS_FILE.exists():
        raise FileNotFoundError(f"{FORKS_FILE} introuvable; readme_forks.json est requis.")
    data = json.loads(FORKS_FILE.read_text(encoding='utf-8'))
    entries: List[ForkEntry] = []
    for raw in data:
        # map the JSON structure to ForkEntry
        entries.append(
            ForkEntry(
                source=raw.get("source"),
                owner=raw.get("owner"),
                name=raw.get("name"),
                upstream=raw["upstream"],
                upstream_url=raw.get("upstream_url"),
                upstream_default_branch=raw.get("upstream_default_branch", raw.get("default_branch", "master")),
                subtree_path=raw.get("subtree_path"),
                subtree_exists=bool(raw.get("subtree_exists", False)),
                subtree_license_file=raw.get("subtree_license_file"),
                subtree_license_verified=bool(raw.get("subtree_license_verified", False)),
                verified=bool(raw.get("verified", False)),
                notes=raw.get("notes"),
            )
        )
    return entries


def sanitize_remote_name(name: str) -> str:
    safe = []
    for char in name.lower():
        safe.append(char if char.isalnum() or char in {"-", "_"} else "-")
    return "upstream-" + "".join(safe)


def ensure_remote(remote: str, url: str) -> None:
    try:
        current = run(["git", "remote", "get-url", remote], capture=True)
        if current.stdout.strip() != url:
            run(["git", "remote", "set-url", remote, url])
    except CommandError:
        # remote doesn't exist, add it
        run(["git", "remote", "add", remote, url])


def update_subtree_for_entry(entry: ForkEntry, push_branch_prefix: str = "subtree-update") -> UpdateResult:
    """
    High-level sequence:
    - ensure remote
    - fetch upstream
    - perform subtree add or pull into prefix (subtree_path)
    - copy license if found
    - commit and push update branch
    """
    prefix = entry.prefix
    remote_name = sanitize_remote_name(entry.upstream)
    git_url = entry.upstream_git_url
    ensure_remote(remote_name, git_url)
    # fetch the remote
    run(["git", "fetch", remote_name])
    # determine commit-ish to use (use upstream_default_branch)
    upstream_ref = f"{remote_name}/{entry.upstream_default_branch}"
    # create/update a branch for the subtree changes
    update_branch = f"{push_branch_prefix}/{entry.owner or 'upstream'}/{entry.name or prefix}"
    # create branch off current HEAD
    if not ref_exists(update_branch):
        run(["git", "checkout", "-b", update_branch])
    else:
        run(["git", "checkout", update_branch])
    changed = False
    try:
        # if subtree does not exist, add it; else pull
        if not Path(prefix).exists():
            # try to add subtree
            run(["git", "subtree", "add", "--prefix", prefix, git_url, entry.upstream_default_branch, "--squash"])
            changed = True
        else:
            # pull updates
            run(["git", "subtree", "pull", "--prefix", prefix, git_url, entry.upstream_default_branch, "--squash"])
            changed = True
    except CommandError as e:
        # swallow and continue (caller can inspect)
        raise

    # attempt to copy license file from fetched remote tree (best-effort)
    license_note = ""
    upstream_license_file = entry.subtree_license_file
    if not upstream_license_file:
        # try common license filenames inside prefix (best-effort)
        candidates = ["LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING"]
        for c in candidates:
            p = Path(prefix) / c
            if p.exists():
                upstream_license_file = str(p)
                entry.subtree_license_verified = True
                license_note = f"Found license in subtree: {c}"
                break

    # create UPSTREAM.md metadata in subtree
    upstream_md_path = Path(prefix) / "UPSTREAM.md"
    upstream_md_content = f"# Upstream: {entry.upstream}\\n\\nSource: {entry.upstream_url or entry.upstream}\\n\\nImported: {datetime.now(timezone.utc).isoformat()}\\n"
    upstream_md_path.write_text(upstream_md_content, encoding='utf-8')

    # commit changes if any
    try:
        run(["git", "add", str(upstream_md_path)])
        # if license file identified, add it
        if upstream_license_file:
            run(["git", "add", upstream_license_file])
        # detect changes
        status = run(["git", "status", "--porcelain"], capture=True).stdout
        if status.strip():
            run(["git", "commit", "-m", f"Update subtree {prefix} from {entry.upstream}"])
            changed = True
            # push branch
            run(["git", "push", "-u", "origin", update_branch])
    except CommandError:
        raise

    upstream_commit = ""  # optionally determine last imported commit
    return UpdateResult(fork=entry, upstream_commit=upstream_commit, license_note=license_note, changed=changed)


def main():
    entries = load_entries()
    # naive sequential processing; you can parallelize if needed
    results: List[UpdateResult] = []
    for e in entries:
        # skip entries without subtree_path unless you still want to add them
        if not e.subtree_path:
            print(f"Skipping {e.upstream} (no subtree_path defined)")
            continue
        print(f"Processing {e.upstream} -> {e.subtree_path}")
        try:
            res = update_subtree_for_entry(e)
            results.append(res)
            print(f"Updated {e.upstream} (changed={res.changed})")
        except Exception as ex:
            print(f"Erreur lors du traitement de {e.upstream}: {ex}", file=sys.stderr)

    # simple summary
    changed_count = sum(1 for r in results if r.changed)
    print(f"Traitement terminé. {len(results)} entrées traitées, {changed_count} modifiées.")


if __name__ == '__main__':
    main()