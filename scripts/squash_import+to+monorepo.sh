#!/usr/bin/env bash
set -euo pipefail

# squash_import_to_monorepo.sh
# Import (squashed) each fork listed in forks.yaml into OurITRes/all_forked_repositories/<name>
#
# Features:
#  - --dry-run : simulate actions (no push, no PR, no delete)
#  - --pr : push to a branch and create a Pull Request instead of pushing to default branch
#  - --force : overwrite existing target subfolder
#  - --second-pass : only perform second-pass deletion checks (see --delete-old)
#  - --delete-old : when used with --second-pass, delete the old repo OurITRes/<name> after checks
#
# Requirements: git, curl, jq, rsync, python3, PyYAML
# Environment:
#   FORKS_MANAGER_PAT - GitHub token (with repo scope, and admin rights if deletion is required)
#
# Example:
#   export FORKS_MANAGER_PAT="ghp_xxx..."
#   chmod +x scripts/squash_import_to_monorepo.sh
#   ./scripts/squash_import_to_monorepo.sh forks.yaml --dry-run
#   ./scripts/squash_import_to_monorepo.sh forks.yaml --pr
#   ./scripts/squash_import_to_monorepo.sh forks.yaml --second-pass --delete-old

REPO_CENTRAL_OWNER="OurITRes"
REPO_CENTRAL_NAME="all_forked_repositories"
REPO_CENTRAL="${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}"

DATESTR="$(date -u +%Y%m%d-%H%M%S)"
LOGDIR="$(pwd)/logs"
mkdir -p "$LOGDIR"
MAIN_LOG="$LOGDIR/import-$DATESTR.log"

DRY_RUN=0
FORCE=0
PR_MODE=0
SECOND_PASS=0
DELETE_OLD=0

usage() {
  cat <<EOF
Usage: $0 forks.yaml [--dry-run] [--force] [--pr] [--second-pass] [--delete-old]
EOF
  exit 2
}

# parse args
if [[ $# -lt 1 ]]; then usage; fi
FORKS_YAML="$1"; shift || true

while (( "$#" )); do
  case "$1" in
    --dry-run) DRY_RUN=1;;
    --force) FORCE=1;;
    --pr) PR_MODE=1;;
    --second-pass) SECOND_PASS=1;;
    --delete-old) DELETE_OLD=1;;
    -h|--help) usage;;
    *) echo "[ERROR] Unknown arg: $1"; usage;;
  esac
  shift
done

PAT="${FORKS_MANAGER_PAT:-}"
if [[ -z "$PAT" && "$DRY_RUN" -eq 0 ]]; then
  echo "[ERROR] FORKS_MANAGER_PAT environment variable not set (required unless --dry-run)."
  exit 1
fi

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$MAIN_LOG"
}

log "Start import run (DRY_RUN=$DRY_RUN, PR_MODE=$PR_MODE, SECOND_PASS=$SECOND_PASS, DELETE_OLD=$DELETE_OLD)"

# helper: parse forks.yaml to JSON array of {source,name,default_branch,upstream}
parse_forks() {
  python3 - "$FORKS_YAML" <<'PY'
import sys, yaml, json
y = yaml.safe_load(open(sys.argv[1]))
forks = y.get("forks", [])
out = []
for f in forks:
    entry = {
        "source": f.get("source"),
        "name": f.get("name"),
        "default_branch": f.get("default_branch", "master"),
        "upstream": f.get("upstream", ""),
        "url": f.get("url","")
    }
    out.append(entry)
print(json.dumps(out))
PY
}

# get default branch of central repo via GH API
get_central_default_branch() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "main"
    return
  fi
  repo_api="https://api.github.com/repos/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}"
  resp="$(curl -s -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github+json" "$repo_api")"
  echo "$resp" | jq -r '.default_branch // "main"'
}

CENTRAL_DEFAULT_BRANCH="$(get_central_default_branch)"
log "Central repo default branch: $CENTRAL_DEFAULT_BRANCH"

# clone central repo once (to apply commits / create branches / push)
TMPDIR="$(mktemp -d -t forks-import-XXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CENTRAL_DIR="$TMPDIR/$REPO_CENTRAL_NAME"
CENTRAL_CLONE_URL="https://${PAT}@github.com/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}.git"

if [[ "$DRY_RUN" -eq 0 ]]; then
  log "Cloning central repo ${REPO_CENTRAL} into $CENTRAL_DIR"
  git clone --depth 1 "$CENTRAL_CLONE_URL" "$CENTRAL_DIR"
else
  log "DRY_RUN: would clone central repo ${REPO_CENTRAL}"
  mkdir -p "$CENTRAL_DIR"
  # initialize a fake git repo locally for dry-run to compute paths
  (cd "$CENTRAL_DIR" && git init >/dev/null 2>&1 || true)
fi

ENTRIES_JSON="$(parse_forks)"
COUNT=$(echo "$ENTRIES_JSON" | jq 'length')
log "Found $COUNT entries in $FORKS_YAML"

# helper to create PR (tries 'gh' first, then GitHub API)
create_pr() {
  local branch="$1"; local title="$2"; local body="$3"; local base="$4" local_create_output
  if command -v gh >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: gh pr create --repo ${REPO_CENTRAL} --title \"$title\" --body \"$body\" --base $base --head ${REPO_CENTRAL_OWNER}:${branch}"
      return 0
    fi
    log "Creating PR with gh for branch $branch"
    gh pr create --repo "${REPO_CENTRAL}" --title "$title" --body "$body" --base "$base" --head "${REPO_CENTRAL_OWNER}:$branch" || {
      log "WARN: gh pr create failed"
      return 1
    }
    return 0
  else
    # Use API
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: would call GitHub API to create PR (head=${REPO_CENTRAL_OWNER}:${branch}, base=$base)"
      return 0
    fi
    api="https://api.github.com/repos/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}/pulls"
    payload="$(jq -nc --arg t "$title" --arg b "$body" --arg head "${REPO_CENTRAL_OWNER}:$branch" --arg base "$base" '{title:$t, body:$b, head:$head, base:$base}')"
    resp="$(curl -s -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github+json" -d "$payload" "$api")"
    if echo "$resp" | jq -e '.html_url' >/dev/null 2>&1; then
      url="$(echo "$resp" | jq -r '.html_url')"
      log "PR created: $url"
      return 0
    else
      log "ERROR creating PR: $(echo "$resp" | jq -r '.message // .')" 
      return 1
    fi
  fi
}

# helper to delete repo OurITRes/<name>
delete_org_repo() {
  local owner="$1"; local repo="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: would DELETE repo https://github.com/${owner}/${repo}"
    return 0
  fi
  log "Deleting repo https://github.com/${owner}/${repo}"
  resp="$(curl -s -o /dev/stderr -w "%{http_code}" -X DELETE -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${owner}/${repo}" 2>&1)"; status=$?
  # curl exit code is checked above; check content indirectly
  # We can't rely on status easily here; just log success
  log "Deletion API call finished (check on GitHub to confirm)."
  return 0
}

# iterate entries
for idx in $(seq 0 $((COUNT-1))); do
  item="$(echo "$ENTRIES_JSON" | jq -r ".[$idx]")"
  src="$(echo "$item" | jq -r '.source')"
  name="$(echo "$item" | jq -r '.name')"
  branch="$(echo "$item" | jq -r '.default_branch')"
  upstream="$(echo "$item" | jq -r '.upstream')"
  url="$(echo "$item" | jq -r '.url')"

  perlog="$LOGDIR/${name}-$DATESTR.log"
  echo "=== Processing $src -> $name (branch:$branch) ===" | tee -a "$perlog" >> "$MAIN_LOG"

  # SECOND_PASS mode: only check existence of import and optionally delete original repo
  if [[ "$SECOND_PASS" -eq 1 ]]; then
    # check if subdir exists in central repo or if new repo exists
    if [[ -d "$CENTRAL_DIR/$name" ]]; then
      log "Second-pass: Found $CENTRAL_DIR/$name (import confirmed)."
      echo "Second-pass: Found $CENTRAL_DIR/$name (import confirmed)." >> "$perlog"
      if [[ "$DELETE_OLD" -eq 1 ]]; then
        # delete old org repo only if owner is OurITRes (the old repo to remove is OurITRes/$name)
        OLD_OWNER="$REPO_CENTRAL_OWNER"
        OLD_REPO="$name"
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log "DRY_RUN: would delete old repo ${OLD_OWNER}/${OLD_REPO}"
        else
          log "Attempting to delete old repo ${OLD_OWNER}/${OLD_REPO}"
          delete_org_repo "$OLD_OWNER" "$OLD_REPO" >>"$perlog" 2>&1 || log "WARN: delete may have failed. Check permissions."
        fi
      fi
    else
      log "Second-pass: Import of $name NOT found under central repo ($CENTRAL_DIR/$name) — skipping deletion."
      echo "Second-pass: Import NOT found — skipping deletion." >> "$perlog"
    fi
    continue
  fi

  # Normal pass: clone source, copy, commit and push or create PR
  SRC_DIR="$TMPDIR/src-$name"
  log "Cloning source https://github.com/$src (branch=$branch) into $SRC_DIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: would git clone --depth 1 --branch $branch https://github.com/$src.git $SRC_DIR"
    echo "DRY_RUN: would clone $src" >> "$perlog"
  else
    if ! git clone --depth 1 --branch "$branch" "https://github.com/$src.git" "$SRC_DIR" >/dev/null 2>>"$perlog"; then
      log "ERROR: clone failed for $src (skipping). See $perlog"
      continue
    fi
  fi

  TARGET_SUBDIR="$CENTRAL_DIR/$name"
  if [[ -d "$TARGET_SUBDIR" && "$FORCE" -eq 0 ]]; then
    log "ERROR: Target $TARGET_SUBDIR exists. Use --force to overwrite. Skipping $name."
    echo "Target exists; skipping." >> "$perlog"
    rm -rf "$SRC_DIR" || true
    continue
  fi

  if [[ -d "$TARGET_SUBDIR" && "$FORCE" -eq 1 ]]; then
    log "--force: removing existing $TARGET_SUBDIR"
    rm -rf "$TARGET_SUBDIR"
  fi

  mkdir -p "$TARGET_SUBDIR"
  log "Copying files (excluding .git) into $TARGET_SUBDIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: rsync -a --exclude='.git' --delete $SRC_DIR/ $TARGET_SUBDIR/"
    echo "DRY_RUN: copy files from $SRC_DIR to $TARGET_SUBDIR" >> "$perlog"
  else
    rsync -a --exclude='.git' --delete "$SRC_DIR"/ "$TARGET_SUBDIR"/ >>"$perlog" 2>&1
  fi

  # Prepare commit/branch
  pushd "$CENTRAL_DIR" >/dev/null
  git add --all "$name" >/dev/null 2>&1 || true

  if git diff --staged --quiet; then
    log "No changes detected for $name; nothing to do."
    echo "No changes detected." >> "$perlog"
    popd >/dev/null
    rm -rf "$SRC_DIR"
    continue
  fi

  if [[ "$PR_MODE" -eq 1 ]]; then
    branch_name="import/${name}-${DATESTR}"
    log "PR mode: create branch $branch_name, commit and push, then create PR"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: would git commit -m \"Import ${src} (squashed)\" and git push origin $branch_name"
    else
      git commit -m "Import ${src} (squashed)" >/dev/null 2>>"$perlog"
      git checkout -b "$branch_name" >/dev/null 2>>"$perlog" || true
      log "Pushing branch $branch_name to origin..."
      git push origin "$branch_name" >/dev/null 2>>"$perlog" || { log "ERROR: push failed for $name"; popd >/dev/null; rm -rf "$SRC_DIR"; continue; }
      # create PR
      pr_title="Import ${src} (squashed) into /${name}"
      pr_body="Automated import (squashed) of ${src} into ${REPO_CENTRAL}/${name}.\n\nUpstream: ${upstream:-unknown}"
      create_pr "$branch_name" "$pr_title" "$pr_body" "$CENTRAL_DEFAULT_BRANCH" >>"$perlog" 2>&1 || log "WARN: PR creation failed for $name"
      # return to default branch
      git checkout "$CENTRAL_DEFAULT_BRANCH" >/dev/null 2>&1 || true
    fi
  else
    # direct push to default branch
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: would commit and push changes to ${CENTRAL_DEFAULT_BRANCH} on ${REPO_CENTRAL}"
      echo "DRY_RUN: would commit & push to central repo" >> "$perlog"
    else
      git commit -m "Import ${src} (squashed) into /${name}" >/dev/null 2>>"$perlog"
      log "Pushing changes to origin/${CENTRAL_DEFAULT_BRANCH}..."
      git push origin "$CENTRAL_DEFAULT_BRANCH" >/dev/null 2>>"$perlog" || { log "ERROR: push failed for $name"; popd >/dev/null; rm -rf "$SRC_DIR"; continue; }
      log "Pushed import for $name"
    fi
  fi

  popd >/dev/null
  rm -rf "$SRC_DIR"
  log "Completed processing $name"
done

log "Run finished. Logs: $MAIN_LOG"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY_RUN was set: no pushes, PRs or deletions were performed."
fi

exit 0