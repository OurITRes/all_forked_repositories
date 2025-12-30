#!/usr/bin/env python3
"""Automate git subtree updates based on forks.json.

- Ensures upstream remotes exist.
- Runs git subtree add/pull with --squash.
- Copies upstream license files into UPSTREAM_LICENSE when present.
- Writes UPSTREAM.md metadata in each subtree.
- Pushes changes to an update branch and opens a PR.
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
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
FORKS_FILE = ROOT / "forks.json"


@dataclass
class ForkEntry:
    name: str
    upstream: str
    default_branch: str
    migrate_to: str

    @property
    def upstream_url(self) -> str:
        return f"https://github.com/{self.upstream}.git"

    @property
    def prefix(self) -> str:
        parsed = urlparse(self.migrate_to)
        parts = [p for p in parsed.path.split("/") if p]
        try:
            base_index = parts.index("all_forked_repositories")
            prefix_parts = parts[base_index + 1 :]
        except ValueError:
            prefix_parts = parts
        if not prefix_parts:
            raise ValueError(f"Cannot derive prefix from migrate_to={self.migrate_to}")
        return "/".join(prefix_parts)


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


def load_entries() -> List[ForkEntry]:
    data = json.loads(FORKS_FILE.read_text())
    entries: List[ForkEntry] = []
    for raw in data:
        entries.append(
            ForkEntry(
                name=raw["name"],
                upstream=raw["upstream"],
                default_branch=raw.get("default_branch", "master"),
                migrate_to=raw["migrate_to"],
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
        run(["git", "remote", "add", remote, url])


def fetch_remote(remote: str, branch: str) -> str:
    try:
        run(["git", "fetch", remote, branch])
    except CommandError as exc:
        raise CommandError(f"Failed to fetch {remote}/{branch}: {exc}")
    tip = run(["git", "rev-parse", f"{remote}/{branch}"], capture=True).stdout.strip()
    return tip


def default_branch() -> str:
    try:
        result = run(["git", "symbolic-ref", "refs/remotes/origin/HEAD"], capture=True)
        ref = result.stdout.strip().split("/")
        return ref[-1]
    except CommandError:
        return os.environ.get("DEFAULT_BRANCH", "main")


def subtree_action(prefix: str, remote: str, branch: str, exists: bool) -> None:
    cmd = ["git", "subtree", "pull" if exists else "add", "--prefix", prefix, remote, branch, "--squash"]
    run(cmd)


def status_for_prefix(prefix: str) -> bool:
    try:
        res = run(["git", "status", "--porcelain", "--", prefix], capture=True)
    except CommandError:
        return False
    return bool(res.stdout.strip())


def find_license(prefix: Path) -> Optional[Path]:
    candidates = {"license", "license.txt", "license.md", "copying", "copyright"}
    if not prefix.exists():
        return None
    for child in prefix.iterdir():
        if child.is_file() and child.name.lower() in candidates:
            return child
    return None


def copy_license(prefix: Path, license_path: Optional[Path]) -> str:
    target = prefix / "UPSTREAM_LICENSE"
    if license_path and license_path.exists():
        target.write_text(license_path.read_text())
        return f"License synced from {license_path.name} to {target.name}"
    else:
        target.unlink(missing_ok=True)
        return "No license file found in upstream; UPSTREAM_LICENSE not created"


def write_metadata(prefix: Path, entry: ForkEntry, upstream_commit: str, license_note: str) -> None:
    prefix.mkdir(parents=True, exist_ok=True)
    metadata = prefix / "UPSTREAM.md"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S %Z")
    lines = [
        "# Upstream metadata",
        "",
        f"- Upstream repository: https://github.com/{entry.upstream}",
        f"- Upstream branch: {entry.default_branch}",
        f"- Latest upstream commit: {upstream_commit}",
        f"- Imported at: {now}",
        f"- License: {license_note}",
    ]
    metadata.write_text("\n".join(lines) + "\n")


def create_issue(repo: str, token: str, title: str, body: str) -> None:
    import urllib.request

    payload = json.dumps({"title": title, "body": body}).encode()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/issues",
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "subtree-sync-script",
        },
    )
    with urllib.request.urlopen(req) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"Failed to create issue: {resp.status} {resp.read()}")


def create_pr(repo: str, token: str, head: str, base: str, updates: List[UpdateResult]) -> None:
    import urllib.request

    changes = "\n".join(
        [f"- {res.fork.name} ({res.fork.prefix}): {res.upstream_commit} [{res.license_note}]" for res in updates]
    )
    body = f"Automated subtree updates performed.\n\n{changes}\n"
    payload = json.dumps(
        {
            "title": "chore: sync upstream subtrees",
            "body": body,
            "head": head,
            "base": base,
        }
    ).encode()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/pulls",
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "subtree-sync-script",
        },
    )
    with urllib.request.urlopen(req) as resp:
        if resp.status >= 300:
            raise RuntimeError(f"Failed to create PR: {resp.status} {resp.read()}")


def process_entry(entry: ForkEntry) -> UpdateResult:
    remote = sanitize_remote_name(entry.name)
    prefix = entry.prefix
    ensure_remote(remote, entry.upstream_url)
    upstream_commit = fetch_remote(remote, entry.default_branch)

    prefix_path = ROOT / prefix
    subtree_exists = prefix_path.exists()

    subtree_action(prefix, remote, entry.default_branch, subtree_exists)

    license_file = find_license(prefix_path)
    license_note = copy_license(prefix_path, license_file)
    write_metadata(prefix_path, entry, upstream_commit, license_note)

    changed = status_for_prefix(prefix)
    return UpdateResult(fork=entry, upstream_commit=upstream_commit, license_note=license_note, changed=changed)


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY", "OurITRes/all_forked_repositories")
    updates: List[UpdateResult] = []

    branch_base = default_branch()
    update_branch = f"auto/subtree-sync-{datetime.now(timezone.utc).strftime('%Y%m%d')}"
    run(["git", "checkout", "-B", update_branch, f"origin/{branch_base}"])

    for entry in load_entries():
        print(f"Processing {entry.name} -> {entry.prefix}")
        try:
            result = process_entry(entry)
            if result.changed:
                updates.append(result)
        except Exception as exc:  # noqa: BLE001
            error_msg = f"Failed to update {entry.name}: {exc}"
            print(error_msg)
            if token:
                title = f"Upstream sync failed for {entry.name}"
                body = f"Automatic subtree update failed for {entry.name}.\n\nError: {exc}\n"
                try:
                    create_issue(repo, token, title, body)
                except Exception as issue_exc:  # noqa: BLE001
                    print(f"Failed to create issue for {entry.name}: {issue_exc}")

    if not updates:
        print("No updates detected.")
        return 0

    run(["git", "status"])
    run(["git", "add", "."])
    run(["git", "commit", "-m", "chore: sync upstream subtrees"])
    run(["git", "push", "--set-upstream", "origin", update_branch])

    if token:
        try:
            create_pr(repo, token, update_branch, branch_base, updates)
        except Exception as exc:  # noqa: BLE001
            print(f"Failed to open PR: {exc}")
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
 