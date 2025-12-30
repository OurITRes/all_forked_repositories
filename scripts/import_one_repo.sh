#!/usr/bin/env bash
set -euo pipefail

# import_one_repo.sh <owner/repo> <mode: dry-run|real> [migrate_path]
# Implementation that uses GitHub REST API to create blobs/tree/commit/ref and a PR.
# Advantages: no git auth issues on the runner, robust in CI.

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

# Cleanup handler
cleanup() {
  rm -rf "${TMPDIR:-}" || true
}
trap cleanup EXIT

# Select token (prefer installation token provided by workflow)
TOKEN="${INSTALLATION_TOKEN:-${FORKS_MANAGER_PAT:-${GITHUB_TOKEN:-}}}"
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n' | sed -E 's/^[[:space:]\"]+//; s/[[:space:]\"]+$//')"

if [[ -z "$TOKEN" && "$MODE" != "dry-run" ]]; then
  echo "[ERROR] No token available (set INSTALLATION_TOKEN/FORKS_MANAGER_PAT or run in Actions with GITHUB_TOKEN)" | tee -a "$LOGFILE"
  exit 1
fi

echo "=== Importing $REPO_FULL mode=$MODE at $DATESTR ===" | tee -a "$LOGFILE"

owner="$(echo "$REPO_FULL" | cut -d/ -f1)"
name="$(echo "$REPO_FULL" | cut -d/ -f2)"

# Get migrate_to from forks.yaml (if present) via small python helper
GETPY="$(mktemp -t get_migrate_XXXX.py)"
cat > "$GETPY" <<'PY'
import yaml, sys
repo_full = sys.argv[1]
name = sys.argv[2]
try:
    y = yaml.safe_load(open('forks.yaml'))
except Exception:
    print('', end='')
    sys.exit(0)
for f in y.get('forks', []):
    if f.get('source') == repo_full or f.get('name') == name or f.get('repo') == repo_full:
        print(f.get('migrate_to') or '')
        sys.exit(0)
print('', end='')
PY
migrate_to="$(python3 "$GETPY" "$REPO_FULL" "$name" 2>/dev/null || true)"
rm -f "$GETPY" || true

if [[ -n "$MIGRATE_OVERRIDE" ]]; then
  dest_rel="$MIGRATE_OVERRIDE"
elif [[ -n "$migrate_to" ]]; then
  if [[ "$migrate_to" =~ ^https?:// ]]; then
    dest_rel="$(echo "$migrate_to" | sed -E 's#.*\/all_forked_repositories\/(.*)#\1#')"
  else
    dest_rel="$migrate_to"
  fi
else
  dest_rel="$name"
fi
dest_rel="$(echo "$dest_rel" | sed -E 's/^[[:space:]\"]+//; s/[[:space:]\"]+$//; s#^/##; s#/$##')"

echo "Destination relative path in monorepo: $dest_rel" | tee -a "$LOGFILE"

SRC_CLONE_URL="https://github.com/${REPO_FULL}.git"

# Step 1: clone source (shallow)
echo "[STEP 1] clone source $SRC_CLONE_URL" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would git clone --depth 1 $SRC_CLONE_URL $TMPDIR/src" | tee -a "$LOGFILE"
else
  git clone --depth 1 "$SRC_CLONE_URL" "$TMPDIR/src" >>"$LOGFILE" 2>&1
fi

# Step 2: strip .git
echo "[STEP 2] prepare working tree (no .git)" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would remove .git and prepare files" | tee -a "$LOGFILE"
else
  rm -rf "$TMPDIR/src/.git"
fi

# If dry-run, stop here (we already validated clone)
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN completed." | tee -a "$LOGFILE"
  exit 0
fi

# Now create blobs and tree entries using GitHub API
API_BASE="https://api.github.com"
REPO_API="$API_BASE/repos/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}"
AUTH_HDR="Authorization: Bearer ${TOKEN}"
CONTENT_TYPE_HDR="Accept: application/vnd.github+json"

echo "[STEP 3] creating blobs for files under $TMPDIR/src ..." | tee -a "$LOGFILE"

ENTRIES_FILE="$TMPDIR/tree_entries.jsonl"
: > "$ENTRIES_FILE"

set -e
# iterate files
cd "$TMPDIR/src" || exit 1
find . -type f -print0 | while IFS= read -r -d '' file; do
  rel="${file#./}"
  # determine mode (executable)
  if [[ -x "$file" ]]; then
    mode="100755"
  else
    mode="100644"
  fi

  # create a temporary payload file that contains the JSON for the blob
  PAYLOAD_FILE="$(mktemp "$TMPDIR/blob_payload_XXXX.json")"
  # write JSON header, append base64 content (without newlines), then footer
  printf '%s' '{"content":"' > "$PAYLOAD_FILE"
  # use base64 -w0 on Linux; if not supported, fallback to tr to remove newlines
  if base64 --wrap=0 /dev/null >/dev/null 2>&1; then
    base64 -w0 "$file" >> "$PAYLOAD_FILE"
  else
    base64 "$file" | tr -d '\n' >> "$PAYLOAD_FILE"
  fi
  printf '%s' '","encoding":"base64"}' >> "$PAYLOAD_FILE"

  # send payload reading from file (avoids Arg list too long)
  resp="$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" --data-binary @"$PAYLOAD_FILE" "$REPO_API/git/blobs")"
  rm -f "$PAYLOAD_FILE" || true

  blob_sha="$(echo "$resp" | jq -r .sha)"
  if [[ -z "$blob_sha" || "$blob_sha" == "null" ]]; then
    echo "ERROR: failed to create blob for $file. Response: $resp" | tee -a "$LOGFILE"
    exit 1
  fi

  dst_path="${dest_rel}/${rel}"
  entry_json=$(jq -n --arg path "$dst_path" --arg mode "$mode" --arg type "blob" --arg sha "$blob_sha" \
    '{path:$path, mode:$mode, type:$type, sha:$sha}')
  printf '%s\n' "$entry_json" >> "$ENTRIES_FILE"

  echo "Created blob $blob_sha for $file -> $dst_path" | tee -a "$LOGFILE"
done

cd - >/dev/null  || true

# Build tree payload: a JSON object {"tree":[...entries...]}
TREE_PAYLOAD="$TMPDIR/tree_payload.json"
jq -s '{tree: .}' "$ENTRIES_FILE" > "$TREE_PAYLOAD"

echo "[STEP 4] determine base branch and parent commit" | tee -a "$LOGFILE"
# get default_branch of central repo
repo_info=$(curl -s -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" "$REPO_API")
default_branch=$(echo "$repo_info" | jq -r .default_branch)
if [[ -z "$default_branch" || "$default_branch" == "null" ]]; then
  default_branch="main"
fi
echo "Default branch: $default_branch" | tee -a "$LOGFILE"

# get parent commit sha (if exists)
ref_resp=$(curl -s -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" "$REPO_API/git/ref/heads/$default_branch")
parent_sha=$(echo "$ref_resp" | jq -r '.object.sha // empty')
if [[ -n "$parent_sha" ]]; then
  echo "Parent commit SHA: $parent_sha" | tee -a "$LOGFILE"
else
  echo "No parent commit (empty repo or no default branch head)." | tee -a "$LOGFILE"
fi

echo "[STEP 5] build tree payload from entries" | tee -a "$LOGFILE"
# ENTires file is newline JSON objects; use jq -s to build {"tree": [ ... ]}
if [[ ! -s "$ENTRIES_FILE" ]]; then
  echo "ERROR: no tree entries found in $ENTRIES_FILE" | tee -a "$LOGFILE"
  exit 1
fi
jq -s '{tree: .}' "$ENTRIES_FILE" > "$TREE_PAYLOAD"

echo "[STEP 6] create tree on GitHub" | tee -a "$LOGFILE"
tree_resp=$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" -d @"$TREE_PAYLOAD" "$REPO_API/git/trees")
tree_sha=$(echo "$tree_resp" | jq -r .sha)
if [[ -z "$tree_sha" || "$tree_sha" == "null" ]]; then
  echo "ERROR: failed to create tree. Response: $tree_resp" | tee -a "$LOGFILE"
  exit 1
fi
echo "Created tree: $tree_sha" | tee -a "$LOGFILE"

echo "[STEP 7] create commit" | tee -a "$LOGFILE"
if [[ -n "$parent_sha" ]]; then
  commit_payload=$(jq -n --arg msg "Import ${REPO_FULL} (squashed) into /${dest_rel}" --arg tree "$tree_sha" --arg parent "$parent_sha" \
    '{message:$msg, tree:$tree, parents:[$parent]}')
else
  commit_payload=$(jq -n --arg msg "Import ${REPO_FULL} (squashed) into /${dest_rel}" --arg tree "$tree_sha" \
    '{message:$msg, tree:$tree}')
fi

commit_resp=$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" -d "$commit_payload" "$REPO_API/git/commits")
commit_sha=$(echo "$commit_resp" | jq -r .sha)
if [[ -z "$commit_sha" || "$commit_sha" == "null" ]]; then
  echo "ERROR: failed to create commit. Response: $commit_resp" | tee -a "$LOGFILE"
  exit 1
fi
echo "Created commit: $commit_sha" | tee -a "$LOGFILE"

# create a unique branch name and create the ref
branch="import/${name}-${DATESTR}"
create_ref_payload=$(jq -n --arg ref "refs/heads/$branch" --arg sha "$commit_sha" '{ref:$ref, sha:$sha}')
ref_resp=$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" -d "$create_ref_payload" "$REPO_API/git/refs")
# check for error
ref_message=$(echo "$ref_resp" | jq -r .message // empty)
if [[ -n "$ref_message" && "$ref_message" != "null" ]]; then
  echo "Warning creating ref: $ref_message" | tee -a "$LOGFILE"
  # try alternative branch name
  suffix=$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n')
  branch="import/${name}-${DATESTR}-${suffix}"
  create_ref_payload=$(jq -n --arg ref "refs/heads/$branch" --arg sha "$commit_sha" '{ref:$ref, sha:$sha}')
  ref_resp=$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" -d "$create_ref_payload" "$REPO_API/git/refs")
  ref_message=$(echo "$ref_resp" | jq -r .message // empty)
  if [[ -n "$ref_message" && "$ref_message" != "null" ]]; then
    echo "ERROR: could not create branch ref. Response: $ref_resp" | tee -a "$LOGFILE"
    exit 1
  fi
fi
echo "Created branch: $branch" | tee -a "$LOGFILE"

echo "[STEP 8] create Pull Request" | tee -a "$LOGFILE"
pr_title="Import ${REPO_FULL} -> /${dest_rel}"
pr_body="Automated import of ${REPO_FULL} into ${REPO_CENTRAL_OWNER}/${dest_rel} (squashed)."
pr_payload=$(jq -n --arg title "$pr_title" --arg body "$pr_body" --arg head "${REPO_CENTRAL_OWNER}:$branch" --arg base "$default_branch" \
  '{title:$title, body:$body, head:$head, base:$base}')
pr_resp=$(curl -s -X POST -H "$AUTH_HDR" -H "$CONTENT_TYPE_HDR" -d "$pr_payload" "$REPO_API/pulls")
pr_url=$(echo "$pr_resp" | jq -r .html_url // empty)
pr_number=$(echo "$pr_resp" | jq -r .number // empty)
if [[ -z "$pr_url" || "$pr_url" == "null" ]]; then
  echo "ERROR: PR creation failed. Response: $pr_resp" | tee -a "$LOGFILE"
  exit 1
fi

echo "PR created: $pr_url (#${pr_number})" | tee -a "$LOGFILE"
echo "Done. Log: $LOGFILE" | tee -a "$LOGFILE"
# print final lines of the log for quick feedback
tail -n 200 "$LOGFILE" || true