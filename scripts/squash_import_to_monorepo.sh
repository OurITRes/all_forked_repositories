#!/usr/bin/env bash
set -euo pipefail

# squash_import_to_monorepo.sh
# Import (squashed) each fork listed in forks.yaml into OurITRes/all_forked_repositories/<path>
# This version respects `migrate_to` field in forks.yaml:
#  - if migrate_to is a URL under the all_forked_repositories repo, the path after
#    .../all_forked_repositories/ is used as the destination folder (can contain subfolders).
#  - if migrate_to is a relative path (no scheme), it is used as-is.
#  - otherwise fallback to using the repository name.
#
# See previous script for full usage and flags (--dry-run, --pr, --force, --second-pass, --delete-old).
#
# Requirements: git, curl, jq, rsync, python3, PyYAML

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

# Prefer FORKS_MANAGER_PAT if set, otherwise fallback to GITHUB_TOKEN (useful in Actions)
PAT="${FORKS_MANAGER_PAT:-${GITHUB_TOKEN:-}}"
if [[ -z "$PAT" && "$DRY_RUN" -eq 0 ]]; then
  echo "[ERROR] FORKS_MANAGER_PAT env var not set and GITHUB_TOKEN not available (required unless --dry-run)."
  exit 1
fi

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$MAIN_LOG"
}

log "Start import run (DRY_RUN=$DRY_RUN, PR_MODE=$PR_MODE, SECOND_PASS=$SECOND_PASS, DELETE_OLD=$DELETE_OLD)"

# parse forks.yaml and include migrate_to
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
        "url": f.get("url",""),
        "migrate_to": f.get("migrate_to","")
    }
    out.append(entry)
print(json.dumps(out))
PY
}

# Helper: compute relative destination path inside central repo from migrate_to field
# Rules:
# - If migrate_to is empty -> fallback to name
# - If migrate_to looks like a URL that contains "/all_forked_repositories/" -> extract the path after that
# - Else if migrate_to looks like an absolute URL but not the central repo -> fallback to name
# - Else if migrate_to is a relative path (no scheme) -> use it directly
compute_dest_path() {
  local migrate_to="$1"
  local default_name="$2"
  if [[ -z "$migrate_to" || "$migrate_to" == "null" ]]; then
    echo "$default_name"
    return
  fi

  # If begins with http or https, try to extract path after /all_forked_repositories/
  if [[ "$migrate_to" =~ ^https?:// ]]; then
    # strip trailing slash
    local m=$(echo "$migrate_to" | sed 's#/$##')
    # attempt to find ".../all_forked_repositories/"
    if echo "$m" | grep -q "/${REPO_CENTRAL_NAME}/"; then
      # extract part after /all_forked_repositories/
      local path_after=$(echo "$m" | sed -E "s#.*\/${REPO_CENTRAL_NAME}\/(.*)#\1#")
      # if empty fallback to default_name
      if [[ -z "$path_after" ]]; then
        echo "$default_name"
      else
        # sanitize: remove leading/trailing slashes
        echo "$path_after" | sed 's#^/*##; s#/*$##'
      fi
      return
    else
      # URL not pointing into the central repo: fallback to default
      echo "$default_name"
      return
    fi
  fi

  # Otherwise treat as a relative path (sanitize)
  echo "$migrate_to" | sed 's#^/*##; s#/*$##'
}

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

TMPDIR="$(mktemp -d -t forks-import-XXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CENTRAL_DIR="$TMPDIR/$REPO_CENTRAL_NAME"
CENTRAL_CLONE_URL="https://${PAT}@github.com/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}.git"

if [[ "$DRY_RUN" -eq 0 ]]; then
  log "Cloning central repo ${REPO_CENTRAL} into $CENTRAL_DIR"
  git clone --depth 1 "$CENTRAL_CLONE_URL" "$CENTRAL_DIR"
  git -C "$CENTRAL_DIR" config user.name "Forks Manager (automation)"
  git -C "$CENTRAL_DIR" config user.email "noreply@ouritres.local"
else
  log "DRY_RUN: would clone central repo ${REPO_CENTRAL}"
  mkdir -p "$CENTRAL_DIR"
  (cd "$CENTRAL_DIR" && git init >/dev/null 2>&1 || true)
fi

ENTRIES_JSON="$(parse_forks)"
COUNT=$(echo "$ENTRIES_JSON" | jq 'length')
log "Found $COUNT entries in $FORKS_YAML"

create_pr() {
  local branch="$1"; local title="$2"; local body="$3"; local base="$4"
  if command -v gh >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: gh pr create --repo ${REPO_CENTRAL} --title \"$title\" --body \"$body\" --base $base --head ${REPO_CENTRAL_OWNER}:$branch"
      return 0
    fi
    gh pr create --repo "${REPO_CENTRAL}" --title "$title" --body "$body" --base "$base" --head "${REPO_CENTRAL_OWNER}:$branch" || {
      log "WARN: gh pr create failed"
      return 1
    }
    return 0
  else
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

delete_org_repo() {
  local owner="$1"; local repo="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: would DELETE repo https://github.com/${owner}/${repo}"
    return 0
  fi
  log "Deleting repo https://github.com/${owner}/${repo}"
  resp="$(curl -s -o /dev/stderr -w "%{http_code}" -X DELETE -H "Authorization: token ${PAT}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${owner}/${repo}" 2>&1)"
  log "Deletion API call finished (check on GitHub to confirm)."
  return 0
}

for idx in $(seq 0 $((COUNT-1))); do
  item="$(echo "$ENTRIES_JSON" | jq -r ".[$idx]")"
  src="$(echo "$item" | jq -r '.source')"
  name="$(echo "$item" | jq -r '.name')"
  branch="$(echo "$item" | jq -r '.default_branch')"
  upstream="$(echo "$item" | jq -r '.upstream')"
  url="$(echo "$item" | jq -r '.url')"
  migrate_to="$(echo "$item" | jq -r '.migrate_to')"

  perlog="$LOGDIR/${name}-$DATESTR.log"
  echo "=== Processing $src -> $name (branch:$branch) ===" | tee -a "$perlog" >> "$MAIN_LOG"

  if [[ "$SECOND_PASS" -eq 1 ]]; then
    # in second-pass we check for existence under central repo at the computed path
    dest_path="$(compute_dest_path "$migrate_to" "$name")"
    TARGET_SUBDIR="$CENTRAL_DIR/$dest_path"
    if [[ -d "$TARGET_SUBDIR" ]]; then
      log "Second-pass: Found $TARGET_SUBDIR (import confirmed)."
      echo "Second-pass: Found $TARGET_SUBDIR (import confirmed)." >> "$perlog"
      if [[ "$DELETE_OLD" -eq 1 ]]; then
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
      log "Second-pass: Import of $name NOT found under central repo ($TARGET_SUBDIR) — skipping deletion."
      echo "Second-pass: Import NOT found — skipping deletion." >> "$perlog"
    fi
    continue
  fi

  SRC_DIR="$TMPDIR/src-$name"
  log "Cloning source https://github.com/$src (branch=$branch) into $SRC_DIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: git clone --depth 1 --branch $branch https://github.com/$src.git $SRC_DIR"
    echo "DRY_RUN: would clone $src" >> "$perlog"
  else
    if ! git clone --depth 1 --branch "$branch" "https://github.com/$src.git" "$SRC_DIR" >>"$perlog" 2>&1; then
      log "ERROR: clone failed for $src (skipping). See $perlog"
      continue
    fi
  fi

  dest_path="$(compute_dest_path "$migrate_to" "$name")"
  TARGET_SUBDIR="$CENTRAL_DIR/$dest_path"

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

  # ensure parent directories exist
  mkdir -p "$(dirname "$TARGET_SUBDIR")"
  mkdir -p "$TARGET_SUBDIR"

  log "Copying files (excluding .git) into $TARGET_SUBDIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY_RUN: rsync -a --exclude='.git' --delete $SRC_DIR/ $TARGET_SUBDIR/"
    echo "DRY_RUN: copy files from $SRC_DIR to $TARGET_SUBDIR" >> "$perlog"
  else
    rsync -a --exclude='.git' --delete "$SRC_DIR"/ "$TARGET_SUBDIR"/ >>"$perlog" 2>&1
  fi

  # commit path relative to repo
  rel_path="$(python3 - <<PY
import os, json, sys
migrate = json.loads('''$migrate_to''') if '''$migrate_to''' != 'null' else ''
# compute same dest_path logic as bash compute_dest_path for safe relative path
s = "$migrate_to"
if s == "" or s == "null":
    print("$name")
else:
    import re
    if s.startswith("http://") or s.startswith("https://"):
        m = re.search(r"/${REPO_CENTRAL_NAME}/(.*)$", s)
        if m:
            print(m.group(1).strip('/'))
        else:
            print("$name")
    else:
        print(s.strip('/'))
PY
)"

  # fallback if python produced nothing
  if [[ -z "$rel_path" ]]; then
    rel_path="$name"
  fi

  pushd "$CENTRAL_DIR" >/dev/null
  git add --all -- "$rel_path" >>"$perlog" 2>&1 || true

  if git diff --staged --quiet; then
    log "No changes detected for $name at $rel_path; nothing to do."
    echo "No changes detected." >> "$perlog"
    popd >/dev/null
    rm -rf "$SRC_DIR"
    continue
  fi

  if [[ "$PR_MODE" -eq 1 ]]; then
    branch_name="import/${name}-${DATESTR}"
    log "PR mode: create branch ${branch_name}, commit and push, then create PR"

    git -C "$CENTRAL_DIR" config --get user.name >>"$perlog" 2>&1 || true
    git -C "$CENTRAL_DIR" config --get user.email >>"$perlog" 2>&1 || true
    git -C "$CENTRAL_DIR" status --untracked-files=all >>"$perlog" 2>&1 || true
    git -C "$CENTRAL_DIR" diff --staged >>"$perlog" 2>&1 || true

    git -C "$CENTRAL_DIR" branch -D "$branch_name" >/dev/null 2>&1 || true

    if ! git -C "$CENTRAL_DIR" commit -m "Import ${src} (squashed) into /${rel_path}" >>"$perlog" 2>&1; then
      log "ERROR: git commit failed for $name, check $perlog"
      tail -n 200 "$perlog" || true
      popd >/dev/null
      rm -rf "$SRC_DIR"
      continue
    fi

    if ! git -C "$CENTRAL_DIR" checkout -b "$branch_name" >>"$perlog" 2>&1; then
      log "ERROR: git checkout -b ${branch_name} failed for $name (voir $perlog)"
      tail -n 200 "$perlog" || true
      popd >/dev/null
      rm -rf "$SRC_DIR"
      continue
    fi

    log "Pushing branch $branch_name to origin..."
    if ! git -C "$CENTRAL_DIR" push origin "$branch_name" >>"$perlog" 2>&1; then
      log "ERROR: git push failed for $name (check $perlog for exact error)"
      tail -n 200 "$perlog" || true
      popd >/dev/null
      rm -rf "$SRC_DIR"
      continue
    fi

    pr_title="Import ${src} (squashed) into /${rel_path}"
    pr_body="Automated import (squashed) of ${src} into ${REPO_CENTRAL}/${rel_path}.\n\nUpstream: ${upstream:-unknown}"
    create_pr "$branch_name" "$pr_title" "$pr_body" "$CENTRAL_DEFAULT_BRANCH" >>"$perlog" 2>&1 || log "WARN: PR creation failed for $name"

    git -C "$CENTRAL_DIR" checkout "$CENTRAL_DEFAULT_BRANCH" >/dev/null 2>&1 || true

  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY_RUN: would commit and push changes to ${CENTRAL_DEFAULT_BRANCH} on ${REPO_CENTRAL}"
      echo "DRY_RUN: would commit & push to central repo" >> "$perlog"
    else
      if ! git -C "$CENTRAL_DIR" commit -m "Import ${src} (squashed) into /${rel_path}" >>"$perlog" 2>&1; then
        log "ERROR: git commit failed for $name (check $perlog)"
        tail -n 200 "$perlog" || true
        popd >/dev/null
        rm -rf "$SRC_DIR"
        continue
      fi
      log "Pushing changes to origin/${CENTRAL_DEFAULT_BRANCH}..."
      if ! git -C "$CENTRAL_DIR" push origin "$CENTRAL_DEFAULT_BRANCH" >>"$perlog" 2>&1; then
        log "ERROR: push failed for $name (check $perlog for cause)"
        tail -n 200 "$perlog" || true
        popd >/dev/null
        rm -rf "$SRC_DIR"
        continue
      fi
      log "Pushed import for $name"
    fi
  fi

  popd >/dev/null
  rm -rf "$SRC_DIR"
  log "Completed processing $name -> $rel_path"
done

log "Run finished. Logs: $MAIN_LOG"
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY_RUN was set: no pushes, PRs or deletions were performed."
fi

exit 0