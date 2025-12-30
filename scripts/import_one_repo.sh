#!/usr/bin/env bash
set -euo pipefail

# import_one_repo.sh <owner/repo> <mode: dry-run|real> [migrate_path]
# Robust import script using GitHub App installation token (or fallback)

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

# token preference: prefer installation token (workflow), then FORKS_MANAGER_PAT, then GITHUB_TOKEN
TOKEN="${INSTALLATION_TOKEN:-${FORKS_MANAGER_PAT:-${GITHUB_TOKEN:-}}}"
# sanitize token: remove CR/LF and surrounding whitespace/quotes
TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n' | sed -E 's/^[[:space:]\"]+//; s/[[:space:]\"]+$//')"

if [[ -z "$TOKEN" && "$MODE" != "dry-run" ]]; then
  echo "[ERROR] No token available (set INSTALLATION_TOKEN / FORKS_MANAGER_PAT or run in Actions with GITHUB_TOKEN)" | tee -a "$LOGFILE"
  exit 1
fi

echo "=== Importing $REPO_FULL mode=$MODE at $DATESTR ===" | tee -a "$LOGFILE"

owner="$(echo "$REPO_FULL" | cut -d/ -f1)"
name="$(echo "$REPO_FULL" | cut -d/ -f2)"

# --- get migrate_to using a small temporary python helper to avoid heredoc/subshell parsing issues ---
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
  # if migrate_to is URL extract path after all_forked_repositories/
  if [[ "$migrate_to" =~ ^https?:// ]]; then
    dest_rel="$(echo "$migrate_to" | sed -E 's#.*\/all_forked_repositories\/(.*)#\1#')"
  else
    dest_rel="$migrate_to"
  fi
else
  dest_rel="$name"
fi

# sanitize dest_rel (remove accidental quotes/spaces and leading/trailing slashes)
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

# Step 2: remove .git
echo "[STEP 2] prepare working tree (no .git)" | tee -a "$LOGFILE"
if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would remove .git and copy files" | tee -a "$LOGFILE"
else
  rm -rf "$TMPDIR/src/.git"
fi

# Step 3: copy into central repo path and create import branch/PR
echo "[STEP 3] prepare central repo and sync" | tee -a "$LOGFILE"

if [[ "$MODE" == "dry-run" ]]; then
  echo "DRY_RUN: would init central repo and copy files to $dest_rel" | tee -a "$LOGFILE"
  echo "DRY_RUN: would create branch import/${name}-${DATESTR} and open PR" | tee -a "$LOGFILE"
else
    # --- prepare and authenticate for central repo operations ---
  # create and initialize central working dir
  mkdir -p "$TMPDIR/central"
  pushd "$TMPDIR/central" >/dev/null

  git init >>"$LOGFILE" 2>&1
  git remote add origin "https://github.com/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}.git" >>"$LOGFILE" 2>&1 || true

  # Prevent interactive credential prompting
  export GIT_TERMINAL_PROMPT=0

  # sanitize token again (just in case)
  TOKEN="$(printf '%s' "${TOKEN:-}" | tr -d '\r\n' | sed -E 's/^[[:space:]\"]+//; s/[[:space:]\"]+$//')"

  # Create temporary ~/.netrc for robust auth (used as reliable fallback by git)
  NETRC_FILE="${HOME}/.netrc"
  umask 177
  printf "machine github.com\n  login x-access-token\n  password %s\n" "${TOKEN}" > "$NETRC_FILE"
  chmod 600 "$NETRC_FILE"
  echo "[DEBUG] Created temporary netrc at $NETRC_FILE" >>"$LOGFILE"

  # Try fetch with Authorization header (preferred). If it fails, netrc will allow fallback.
  set +e
  # --- DEBUG: enable verbose git/curl traces (temporary) ---
  export GIT_TRACE=1
  export GIT_CURL_VERBOSE=1
  export GIT_TRACE_PACKET=1
  export GIT_TRACE_PERFORMANCE=1
  # also ensure no interactive prompt
  export GIT_TERMINAL_PROMPT=0
  # --- end DEBUG ---
  git -c http.extraHeader="Authorization: Bearer ${TOKEN}" fetch --depth=1 origin main >>"$LOGFILE" 2>&1
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "Fetch main failed (rc=$rc), trying to fetch origin HEAD (netrc fallback may be used)..." | tee -a "$LOGFILE"
    git -c http.extraHeader="Authorization: Bearer ${TOKEN}" fetch --depth=1 origin >>"$LOGFILE" 2>&1 || true
  fi
  set -e

  # Ensure a local branch exists to commit onto and set committer identity before commit
  # Prefer origin/main, else origin/master, else create an empty main
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    git checkout -b main origin/main >>"$LOGFILE" 2>&1 || true
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    git checkout -b main origin/master >>"$LOGFILE" 2>&1 || true
  else
    # no remote branch available -> create initial empty main
    git commit --allow-empty -m "Initialize central repo for imports" >>"$LOGFILE" 2>&1 || true
    git branch -M main >>"$LOGFILE" 2>&1 || true
  fi

  # configure committer BEFORE making changes
  git config user.name "Forks Manager (automation)"
  git config user.email "noreply@ouritres.local"

  # ensure parent dirs exist inside central repo and filesystem-level refs dir exists
  mkdir -p "$(dirname "$dest_rel")"
  mkdir -p "$dest_rel"
  # ensure git remote refs dir exists to avoid "unable to create directory" races
  mkdir -p .git/refs/remotes/origin || true

  # sync working tree into destination
  rsync -a --exclude='.git' --delete "$TMPDIR/src"/ "$dest_rel"/ >>"$LOGFILE" 2>&1

  git add --all "$dest_rel" >>"$LOGFILE" 2>&1 || true

  if git diff --staged --quiet; then
    echo "No changes to import for $REPO_FULL -> $dest_rel" | tee -a "$LOGFILE"
  else
    branch="import/${name}-${DATESTR}"
    git commit -m "Import ${REPO_FULL} (squashed) into /${dest_rel}" >>"$LOGFILE" 2>&1
    git checkout -b "$branch" >>"$LOGFILE" 2>&1

    # push using Authorization header first, fallback to netrc if needed
    set +e
    git -c http.extraHeader="Authorization: Bearer ${TOKEN}" push origin "$branch" >>"$LOGFILE" 2>&1
    PUSH_RC=$?
    set -e

    if [[ $PUSH_RC -ne 0 ]]; then
      echo "Push with http.extraHeader failed (rc=$PUSH_RC). Trying netrc fallback..." | tee -a "$LOGFILE"
      # Try push again (netrc in place)
      if ! git push origin "$branch" >>"$LOGFILE" 2>&1; then
        echo "Fallback push failed as well. See $LOGFILE for details." | tee -a "$LOGFILE"
        # cleanup netrc and abort
        rm -f "$NETRC_FILE" || true
        popd >/dev/null
        exit 1
      fi
    fi

    # create PR via API using the same token
    title="Import ${REPO_FULL} (squashed) -> /${dest_rel}"
    body="Automated import of ${REPO_FULL} into ${REPO_CENTRAL}/${dest_rel} (squashed)."
    api="https://api.github.com/repos/${REPO_CENTRAL_OWNER}/${REPO_CENTRAL_NAME}/pulls"
    payload=$(jq -n --arg t "$title" --arg b "$body" --arg head "${REPO_CENTRAL_OWNER}:$branch" --arg base "main" '{title:$t, body:$b, head:$head, base:$base}')
    curl -s -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" -d "$payload" "$api" >>"$LOGFILE" 2>&1
    echo "Pushed and created PR for $REPO_FULL -> $dest_rel (see logs)" | tee -a "$LOGFILE"
  fi

  # cleanup netrc
  rm -f "$NETRC_FILE" || true

  popd >/dev/null
fi

echo "Done. Log: $LOGFILE"
if [[ -s "$LOGFILE" ]]; then
  tail -n +1 "$LOGFILE"
fi
rm -rf "$TMPDIR"