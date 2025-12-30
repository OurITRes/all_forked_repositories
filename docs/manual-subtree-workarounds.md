# Manual subtree workarounds for oversized blobs or partial archives

When an upstream repository contains blobs larger than GitHub's 100 MB limit
(for example the `SysAdmin-Tools` case) or you only have access to a partial
archive/zip, follow this documented workaround to keep the monorepo in sync
while respecting size limits and traceability requirements.

## Clean a large upstream before importing

1. **Clone the upstream to a temporary location**

   (example for `SysAdmin-Tools`):

   ```bash
   git clone https://github.com/chrisdee/Tools /tmp/sysadmin-tools-upstream
   cd /tmp/sysadmin-tools-upstream
   ```

2. **Remove the oversized blobs**

    with [`git filter-repo`](https://github.com/newren/git-filter-repo) or
    another filtering tool:

    ```bash
    git filter-repo  \
     --path SharePoint/soapUI/soapUI-x32-4.5.1.exe --invert-paths \
     --path WebServices/soapUI/soapUI-x32-4.5.1.exe --invert-paths
    ```

    *Adjust the paths to match the blocking files reported by the automation.*

3. **Import the cleaned history as a subtree**

   in the monorepo:

   ```bash
   cd /path/to/all_forked_repositories
   git remote add upstream-sysadmin-tools /tmp/sysadmin-tools-upstream || true
   git fetch upstream-sysadmin-tools master
   git subtree add \
     --prefix=tools/SysAdmin-Tools upstream-sysadmin-tools master \
     --squash
   ```

4. **Document the import**

   in `tools/SysAdmin-Tools/UPSTREAM.md` (URL, default branch, latest upstream
   commit, license summary, date imported) and store the license text or summary
    in `tools/SysAdmin-Tools/UPSTREAM_LICENSE`.

## Import from a partial archive (no history)

If only a zip/tarball is available or you intentionally skip history:

1. Extract the archive directly into the target subtree directory
   (e.g. `tools/SysAdmin-Tools/`).
2. Run `git add` on the extracted files and commit.
3. Fill out `UPSTREAM.md` and `UPSTREAM_LICENSE` to record the source URL,
   default branch, commit/hash of the archive if known, license summary,
   and the import date.

## Notes

- These steps mirror the automated guidance referenced in previous summaries.
  The automation will continue to skip upstreams with oversized blobs to avoid
  push failures, but this document shows where and how to perform the manual
  workaround when you need the content anyway.
- Keep the filtered clone (or archive) around until the import is
  reviewed/merged so you can re-run the steps if needed.
