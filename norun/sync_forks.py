#!/usr/bin/env python3
"""
Simple sync script:
- Reads forks.yaml
- For each fork:
  - clones the fork (shallow clone)
  - adds upstream remote if missing
  - fetches upstream/default_branch
  - merges (or rebases) upstream/default_branch into fork's default_branch
  - pushes back to fork (or pushes to a sync branch and opens a PR)
Requirements: PyYAML, git available on PATH, gh (optional) for PR creation.
"""
import os
import sys
import subprocess
import tempfile
import shutil
import yaml

# Config
FORKS_YAML = os.path.join(os.path.dirname(__file__), '..', 'forks.yaml')
PAT_ENV = "FORKS_MANAGER_PAT"  # expected in environment for auth
GIT_AUTHOR_NAME = "Forks Manager"
GIT_AUTHOR_EMAIL = "noreply@example.com"  # change if desired

def run(cmd, cwd=None, check=True):
    print("+", " ".join(cmd))
    return subprocess.run(cmd, cwd=cwd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def get_pat():
    pat = os.environ.get(PAT_ENV)
    if not pat:
        print(f"[ERROR] Please set environment variable {PAT_ENV} (PAT with repo scope).")
        sys.exit(1)
    return pat

def clone_repo(repo_full, workdir):
    # clone with https using PAT for authentication
    pat = get_pat()
    url = f"https://{pat}@github.com/{repo_full}.git"
    target = os.path.join(workdir, repo_full.replace('/', '_'))
    run(["git", "clone", "--depth", "1", url, target])
    return target

def add_upstream(cwd, upstream_full):
    # add upstream remote if not exists
    remotes = run(["git", "remote"], cwd=cwd).stdout.split()
    if "upstream" not in remotes:
        run(["git", "remote", "add", "upstream", f"https://github.com/{upstream_full}.git"], cwd=cwd)
    else:
        run(["git", "remote", "set-url", "upstream", f"https://github.com/{upstream_full}.git"], cwd=cwd)

def fetch_all(cwd):
    run(["git", "fetch", "origin"], cwd=cwd)
    run(["git", "fetch", "upstream"], cwd=cwd)

def checkout_branch(cwd, branch):
    # ensure branch exists locally tracking origin/branch
    branches = run(["git", "branch", "--show-current"], cwd=cwd).stdout.strip()
    run(["git", "checkout", "-B", branch, f"origin/{branch}"], cwd=cwd)

def perform_sync(cwd, branch, strategy, repo_full, create_pr):
    fetch_all(cwd)
    checkout_branch(cwd, branch)
    # merge or rebase upstream/branch into current branch
    if strategy == "merge":
        try:
            run(["git", "merge", f"upstream/{branch}", "--no-edit"], cwd=cwd)
        except subprocess.CalledProcessError as e:
            print(f"[WARN] Merge produced conflicts or failed for {repo_full}: {e.stderr}")
            if create_pr:
                print("[INFO] Will create a sync branch and open a PR for manual resolution.")
            else:
                print("[ERROR] Cannot auto-merge; skipping push. Consider create_pr=true.")
                return False
    elif strategy == "rebase":
        try:
            run(["git", "rebase", f"upstream/{branch}"], cwd=cwd)
        except subprocess.CalledProcessError as e:
            print(f"[WARN] Rebase failed for {repo_full}: {e.stderr}")
            if create_pr:
                print("[INFO] Will create a sync branch and open a PR for manual resolution.")
            else:
                print("[ERROR] Cannot auto-rebase; skipping push. Consider create_pr=true.")
                return False
    else:
        print(f"[ERROR] Unknown strategy {strategy}")
        return False

    if create_pr:
        # push to a new branch like sync/upstream-YYYYMMDD and open PR via gh
        import datetime
        branch_name = f"sync/upstream-{datetime.datetime.utcnow().strftime('%Y%m%d')}"
        run(["git", "checkout", "-B", branch_name], cwd=cwd)
        try:
            run(["git", "push", "-u", "origin", branch_name], cwd=cwd)
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to push sync branch for {repo_full}: {e.stderr}")
            return False
        # Create PR using gh CLI if available
        try:
            run(["gh", "pr", "create", "--title", f"Sync from upstream/{branch}", "--body", "Automated sync from upstream.", "--base", branch, "--head", branch_name], cwd=cwd)
        except Exception as e:
            print(f"[WARN] Could not create PR via gh: {e}. You can create a PR manually from branch {branch_name}")
    else:
        # push directly to default branch
        try:
            run(["git", "push", "origin", branch], cwd=cwd)
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to push changes for {repo_full}: {e.stderr}")
            return False
    return True

def main():
    # read forks.yaml
    root = os.path.dirname(os.path.dirname(__file__))
    yaml_path = os.path.join(root, "forks.yaml")
    if not os.path.exists(yaml_path):
        print(f"[ERROR] {yaml_path} not found.")
        sys.exit(1)
    with open(yaml_path, "r") as f:
        cfg = yaml.safe_load(f)

    forks = cfg.get("forks", [])
    if not forks:
        print("[INFO] No forks listed in forks.yaml")
        return

    tmp = tempfile.mkdtemp(prefix="forks-sync-")
    print("[INFO] working in", tmp)
    try:
        for entry in forks:
            repo_full = entry["repo"]
            upstream = entry.get("upstream")
            branch = entry.get("default_branch", "main")
            strategy = entry.get("sync_strategy", "merge")
            create_pr = bool(entry.get("create_pr", False))

            print(f"\n=== Syncing {repo_full} from {upstream} ({branch}) strategy={strategy} create_pr={create_pr} ===")
            try:
                repo_dir = clone_repo(repo_full, tmp)
                add_upstream(repo_dir, upstream)
                # set git author to avoid prompts (optional)
                run(["git", "config", "user.name", GIT_AUTHOR_NAME], cwd=repo_dir)
                run(["git", "config", "user.email", GIT_AUTHOR_EMAIL], cwd=repo_dir)
                ok = perform_sync(repo_dir, branch, strategy, repo_full, create_pr)
                if ok:
                    print(f"[OK] Synced {repo_full}")
                else:
                    print(f"[SKIP] {repo_full} needs manual attention")
            except subprocess.CalledProcessError as e:
                print(f"[ERROR] Command failed for {repo_full}: {e.stderr}")
            except Exception as e:
                print(f"[ERROR] Unexpected for {repo_full}: {e}")
    finally:
        print("[INFO] cleaning up")
        shutil.rmtree(tmp)

if __name__ == "__main__":
    main()