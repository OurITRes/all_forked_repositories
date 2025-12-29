#!/usr/bin/env bash
set -euo pipefail

# import_one_repo.sh <owner/repo> <mode: dry-run|real> [migrate_path]
# Improved: ensures destination parent directories are created inside central repo.

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 owner/repo <dry-run|real> [migrate_path]" >&2
  exit 2
fi

REPO_FULL="$1"
MODE="$2"
MIGRATE_OVERRIDE="${3:-}"
REPO_CENTRAL_OWNER="OurITRes"
REPO_CENTRAL_NAME="all_forked_repositories"
ROOT_DIR="$(pwd)"
TMPDIR="$(mktemp -d -t import-XXXX)"
LOGDIR="${ROOT_DIR}/logs"
mkdir -p "$LOGDIR"
DATESTR="$(date -u +%Y%m%d-%H%M%S)"
LOGFILE="$LOGDIR/${REPO_FULL//\//_}-$DATESTR.log"

# token preference: prefer installation token (FORKS_MANAGER_PAT) if set in env, else GITHUB_TOKEN
TOKEN="${FORKS_MANAGER_PAT:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" && "$MODE" != "dry-run" ]]; then
  echo "[ERROR] No token available (set FORKS_MANAGER_PAT or run in Actions where GITHUB_TOKEN exists)" | tee -a "$LOGFILE"
  exit 1
fi

echo "=== Importing $REPO_FULL mode=$MODE at $DATESTR ===" | tee -a "$LOGFILE"
owner="$(echo "$REPO_FULL" | cut -d/ -f1)"
name="$(echo "$REPO_FULL" | cut -d/ -f2)"

# parse forks.yaml to find migrate_to/default_branch if available
migrate_to="$(python3 - <<PY
import yaml,sys
y=yaml.safe_load(open('forks.yaml'))
for f in y.get('forks',[]):
    if f.get('source') == "$REPO_FULL" or f.get('name') == "$name" or f.get('repo') == "$REPO_FULL":
        print(f.get('migrate_to') or '')
        sys.exit(0)
print('', end='')
PY
)"

if [[ -n "$MIGRATE_OVERRIDE" ]]; then
  dest_rel="$MIGRATE_OVERRIDE"
elif [[ -n "$migrate_to" ]]; then
  # if migrate_to is URL extract path after all_forked_repositories/
  if [[ "$migrate_to" =~ ^https?:// ]]; then
    dest_rel="$(echo "$migrate_to" | sed -E 's#.*\/all_forked_repositories\/(.*)#\1#')"
  else
    dest_rel="$migrate_to"
  fi
else
  dest_rel="$name"
fi
dest_rel="$(echo "$dest_rel" | sed 's#^/*##; s#/*$##')"
echo "Destination relative path in monorepo: $dest_rel" | tee -a "$LOGFILE"

CENTRAL_CLONE_URL="https://${TOKEN}@github.com/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}.git"
SRC_CLONE_URL="https://github.com/${REPO_FULL}.git"

# Step 1: clone source (shallow)
echo "[STEP 1] clone source $SRC_CLONE_URL" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would git clone --depth 1 $SRC_CLONE_URL $TMPDIR/src" | tee -a "$LOGFILE"
else
  git clone --depth 1 "$SRC_CLONE_URL" "$TMPDIR/src" >>"$LOGFILE" 2>&1
fi

# Step 2: remove .git
echo "[STEP 2] prepare working tree (no .git)" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would remove .git and copy files" | tee -a "$LOGFILE"
else
  rm -rf "$TMPDIR/src/.git"
fi

# Step 3: clone central repo, copy into dest_rel, commit to branch, push & create PR (or just commit for dry-run)
echo "[STEP 3] copy into central repo path and create import branch/PR" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would clone central repo $CENTRAL_CLONE_URL and copy files to $dest_rel" | tee -a "$LOGFILE"
  echo "DRY_RUN: would create branch import/${name}-${DATESTR} and open PR" | tee -a "$LOGFILE"
else
  git clone --depth 1 "$CENTRAL_CLONE_URL" "$TMPDIR/central" >>"$LOGFILE" 2>&1
  git -C "$TMPDIR/central" config user.name "Forks Manager (automation)"
  git -C "$TMPDIR/central" config user.email "noreply@ouritres.local"

  # create parent dirs and ensure target exists
  mkdir -p "$TMPDIR/central/$(dirname "$dest_rel")"
  mkdir -p "$TMPDIR/central/$dest_rel"

  # rsync working tree into the destination path inside central repo
  rsync -a --exclude='.git' --delete "$TMPDIR/src"/ "$TMPDIR/central/$dest_rel"/ >>"$LOGFILE" 2>&1

  git -C "$TMPDIR/central" add --all "$dest_rel" >>"$LOGFILE" 2>&1 || true
  if git -C "$TMPDIR/central" diff --staged --quiet; then
    echo "No changes to import for $REPO_FULL -> $dest_rel" | tee -a "$LOGFILE"
  else
    branch="import/${name}-${DATESTR}"
    git -C "$TMPDIR/central" commit -m "Import ${REPO_FULL} (squashed) into /${dest_rel}" >>"$LOGFILE" 2>&1
    git -C "$TMPDIR/central" checkout -b "$branch" >>"$LOGFILE" 2>&1
    git -C "$TMPDIR/central" push origin "$branch" >>"$LOGFILE" 2>&1
    # create PR via API
    title="Import ${REPO_FULL} (squashed) -> /${dest_rel}"
    body="Automated import of ${REPO_FULL} into ${REPO_CENTRAL}/${dest_rel} (squashed)."
    api="https://api.github.com/repos/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}/pulls"
    payload=$(jq -n --arg t "$title" --arg b "$body" --arg head "${REPO_CENTRAL_OWNER}:$branch" --arg base "main" '{title:$t, body:$b, head:$head, base:$base}')
    curl -s -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github+json" -d "$payload" "$api" >>"$LOGFILE" 2>&1
    echo "Pushed and created PR for $REPO_FULL -> $dest_rel (see logs)" | tee -a "$LOGFILE"
  fi
fi

echo "Done. Log: $LOGFILE"
if [[ -s "$LOGFILE" ]]; then
  cat "$LOGFILE"
fi
rm -rf "$TMPDIR"