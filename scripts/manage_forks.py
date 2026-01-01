#!/usr/bin/env python3
"""
Gérer readme_forks.json et génération automatique du tableau dans README.md.

Usages possibles :
  # Ajoute une entrée à readme_forks.json
  python scripts/manage_forks.py add owner/repo --source OurITRes/Repo --subtree path/to/subtree --local-branch main

  # Supprime une entrée par upstream ou source    
  python scripts/manage_forks.py remove owner/repo-or-source

  # Liste les entrées présentes    
  python scripts/manage_forks.py list

  # Génère le tableau dans README.md    
  python scripts/manage_forks.py generate

  # Scanne le workspace pour détecter les subtrees non référencés et ajoute des stubs    
  python scripts/manage_forks.py scan
      
  # Tente de détecter et renseigner les upstreams manquants à partir des fichiers UPSTREAM.md, UPSTREAM_LICENSE, README.md
  python scripts/manage_forks.py verify-upstreams

  # Met à jour les informations de licence upstream via l'API GitHub    
  python scripts/manage_forks.py update-licenses

  # Supprime les entrées dont le subtree_path est un sous-dossier d'un autre subtree déjà référencé    
  python scripts/manage_forks.py clean-faux-positifs
      
Le script lit/écrit readme_forks.json (à la racine) et met à jour README.md (à la racine).
Pour des requêtes GitHub plus permissives, exportez GITHUB_TOKEN.
"""
import os
import sys
import json
import argparse
import requests
from datetime import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
README_FORKS_JSON = os.path.join(ROOT, 'readme_forks.json')
README_MD = os.path.join(ROOT, 'README.md')

MARKER_START = '<!-- FORKS_TABLE_START -->'
MARKER_END = '<!-- FORKS_TABLE_END -->'

GITHUB_API = 'https://api.github.com'


def load_readme_forks():
    if not os.path.exists(README_FORKS_JSON):
        return []
    with open(README_FORKS_JSON, 'r', encoding='utf-8') as f:
        return json.load(f)


def save_readme_forks(data):
    with open(README_FORKS_JSON, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def github_get(path):
    token = os.environ.get('GITHUB_TOKEN')
    headers = {'Accept': 'application/vnd.github.v3+json'}
    if token:
        headers['Authorization'] = f'token {token}'
    resp = requests.get(f'{GITHUB_API}{path}', headers=headers)
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


def fetch_repo_info(fullname):
    owner_repo = fullname.strip()
    if '/' not in owner_repo:
        raise ValueError('format attendu owner/repo')
    owner, repo = owner_repo.split('/', 1)
    repo_data = github_get(f'/repos/{owner}/{repo}')
    if not repo_data:
        return None
    license_obj = repo_data.get('license') or {}
    license_name = license_obj.get('name') or license_obj.get('spdx_id') or None
    license_api_url = license_obj.get('url')
    license_html = None
    if license_api_url:
        try:
            lic = github_get(license_api_url.replace(GITHUB_API, '')) if license_api_url.startswith(GITHUB_API) else None
            if lic and lic.get('html_url'):
                license_html = lic.get('html_url')
        except Exception:
            license_html = None
    if not license_html:
        default_branch = repo_data.get('default_branch') or 'main'
        license_html = f'{repo_data.get("html_url")}/blob/{default_branch}/LICENSE'
    return {
        'full_name': repo_data.get('full_name'),
        'html_url': repo_data.get('html_url'),
        'description': repo_data.get('description') or '',
        'license_name': license_name or '',
        'license_html': license_html,
        'forks_count': repo_data.get('forks_count', 0),
        'stargazers_count': repo_data.get('stargazers_count', 0),
        'default_branch': repo_data.get('default_branch') or 'master',
        'updated_at': repo_data.get('updated_at'),
        'owner': owner,
        'name': repo,
    }


def build_entry_from_upstream(upstream_fullname, source=None, subtree=None, local_branch=None):
    info = fetch_repo_info(upstream_fullname)
    if not info:
        return None
    owner = source.split('/', 1)[0] if source and '/' in source else (info['owner'] if source is None else source)
    name = source.split('/', 1)[1] if source and '/' in source else info['name']
    entry = {
        'source': source or f"{owner}/{name}",
        'owner': owner,
        'name': name,
        'local_default_branch': local_branch or 'master',
        'upstream': upstream_fullname,
        'upstream_url': info['html_url'],
        'upstream_default_branch': info['default_branch'],
        'upstream_description': info['description'],
        'upstream_license_name': info['license_name'] or None,
        'upstream_license_url': info['license_html'] or None,
        'subtree_path': subtree or None,
        'subtree_exists': bool(subtree),
        'subtree_license_file': None,
        'subtree_license_verified': False,
        'verified': False,
        'notes': '',
        'added_at': datetime.utcnow().isoformat() + 'Z',
    }
    return entry


def cmd_add(args):
    data = load_readme_forks()
    # avoid duplicates by upstream or source
    def exists_match(e):
        return (e.get('upstream') == args.repo) or (args.source and e.get('source') == args.source)
    if any(exists_match(e) for e in data):
        print(f"{args.repo} ou {args.source} déjà présent.")
        return
    entry = build_entry_from_upstream(args.repo, source=args.source, subtree=args.subtree, local_branch=args.local_branch)
    if not entry:
        print(f"Impossible de récupérer les infos pour {args.repo}")
        return
    data.append(entry)
    save_readme_forks(data)
    print(f"Ajouté: {entry['source']} -> {entry['upstream']}")


def cmd_remove(args):
    data = load_readme_forks()
    new = [e for e in data if not (e.get('upstream') == args.target or e.get('source') == args.target or f"{e.get('owner')}/{e.get('name')}" == args.target)]
    if len(new) == len(data):
        print(f"{args.target} non trouvé.")
        return
    save_readme_forks(new)
    print(f"Supprimé: {args.target}")


def generate_readme_table(entries):
    lines = []
    lines.append("| Name | Upstream | Upstream license | Subtree exists | Verified | Notes |")
    lines.append("| ---- | -------- | ---------------- | -------------: | :------: | ----- |")
    # Sort entries by name (case-insensitive)
    entries_sorted = sorted(entries, key=lambda e: (e.get('name') or '').lower())
    for e in entries_sorted:
        name = e.get('name') or ''
        subtree = e.get('subtree_path') or ''
        # If subtree path exists, make the name a link to the subtree
        if subtree:
            subtree_url = f"https://github.com/OurITRes/all_forked_repositories/tree/main/{subtree}"
            name_md = f"[{name}]({subtree_url})"
        else:
            name_md = name
        upstream = e.get('upstream_url') or (f"https://github.com/{e.get('upstream')}") if e.get('upstream') else ''
        upstream_md = f"[{e.get('upstream')}]({upstream})" if upstream else (e.get('upstream') or '')
        upstream_license = e.get('upstream_license_name') or ''
        subtree_exists = '✅' if e.get('subtree_exists') else '❌'
        verified = '✅' if e.get('verified') else ''
        notes = (e.get('notes') or '').replace('\n', ' ')
        lines.append(f"| {name_md} | {upstream_md} | {upstream_license} | {subtree_exists} | {verified} | {notes} |")
    return "\n".join(lines)


def cmd_generate(_args):
    entries = load_readme_forks()
    table = generate_readme_table(entries)
    if not os.path.exists(README_MD):
        print("README.md introuvable, génération annulée.")
        return
    content = None
    for enc in ('utf-8', 'utf-8-sig', 'latin-1'):
        try:
            with open(README_MD, 'r', encoding=enc) as f:
                content = f.read()
            break
        except UnicodeDecodeError:
            continue
    if content is None:
        print("Impossible de lire README.md avec les encodages courants (utf-8, utf-8-sig, latin-1). Veuillez convertir le fichier en UTF-8.")
        return
    start = content.find(MARKER_START)
    end = content.find(MARKER_END)
    if start == -1 or end == -1 or end < start:
        print("Marqueurs non trouvés dans README.md; insère la table à la fin.")
        new_content = content + "\n\n" + MARKER_START + "\n" + table + "\n" + MARKER_END + "\n"
    else:
        new_content = content[:start + len(MARKER_START)] + "\n\n" + table + "\n\n" + content[end:]
    with open(README_MD, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("README.md mis à jour.")


def cmd_list(_args):
    data = load_readme_forks()
    for e in data:
        source = e.get('source') or f"{e.get('owner','')}/{e.get('name','')}".strip('/')
        upstream = e.get('upstream', '')
        subtree = e.get('subtree_path', '')
        verified = bool(e.get('verified', False))
        print(f"- {source} -> upstream: {upstream} subtree: {subtree} verified: {verified}")


def main():
    parser = argparse.ArgumentParser(description="Gérer readme_forks.json et générer le tableau README")
    sub = parser.add_subparsers(dest='cmd')
    p_add = sub.add_parser('add')
    p_add.add_argument('repo', help='upstream owner/repo (ex: someuser/somerepo)')
    p_add.add_argument('--source', help='source local owner/name (ex: OurITRes/Repo)')
    p_add.add_argument('--subtree', help='chemin du subtree (ex: tools/python/Repo)')
    p_add.add_argument('--local-branch', dest='local_branch', help='branche locale par défaut (ex: main)')
    p_remove = sub.add_parser('remove')
    p_remove.add_argument('target', help='upstream owner/repo ou source à supprimer')
    sub.add_parser('list')
    sub.add_parser('generate')
    sub.add_parser('scan')
    sub.add_parser('verify-upstreams')
    sub.add_parser('update-licenses')
    sub.add_parser('clean-faux-positifs')
    args = parser.parse_args()
    if args.cmd == 'add':
        cmd_add(args)
    elif args.cmd == 'remove':
        cmd_remove(args)
    elif args.cmd == 'list':
        cmd_list(args)
    elif args.cmd == 'generate':
        cmd_generate(args)
    elif args.cmd == 'scan':
        cmd_scan()
    elif args.cmd == 'verify-upstreams':
        cmd_verify_upstreams()
    elif args.cmd == 'update-licenses':
        cmd_update_licenses()
    elif args.cmd == 'clean-faux-positifs':
        cmd_clean_faux_positifs()
    else:
        parser.print_help()

def cmd_clean_faux_positifs():
    """
    Remove entries whose subtree_path is a subfolder of another subtree_path already referenced.
    """
    data = load_readme_forks()
    all_subtrees = set(e.get('subtree_path') for e in data if e.get('subtree_path'))
    # Only keep entries whose subtree_path is not a subfolder of another subtree_path
    def is_subfolder(path):
        for ks in all_subtrees:
            if ks and ks != path and path.startswith(ks + '/'):
                return True
        return False
    cleaned = [e for e in data if not (e.get('subtree_path') and is_subfolder(e.get('subtree_path')))]
    removed = len(data) - len(cleaned)
    if removed:
        save_readme_forks(cleaned)
        print(f"{removed} faux positifs supprimés de readme_forks.json.")
    else:
        print("Aucun faux positif à supprimer.")
def cmd_update_licenses():
    """
    For all entries with an upstream, update upstream_license_name and upstream_license_url using the GitHub API.
    """
    data = load_readme_forks()
    updated = 0
    for entry in data:
        upstream = entry.get('upstream')
        if not upstream:
            continue
        info = fetch_repo_info(upstream)
        if not info:
            continue
        changed = False
        if entry.get('upstream_license_name') != info['license_name']:
            entry['upstream_license_name'] = info['license_name']
            changed = True
        if entry.get('upstream_license_url') != info['license_html']:
            entry['upstream_license_url'] = info['license_html']
            changed = True
        if changed:
            updated += 1
            print(f"Updated license for {entry.get('name')}: {info['license_name']} ({info['license_html']})")
    if updated:
        save_readme_forks(data)
        print(f"{updated} licenses updated in readme_forks.json.")
    else:
        print("No licenses needed updating.")
def cmd_verify_upstreams():
    """
    For all entries with missing upstream, try to guess/check upstream from UPSTREAM.md, UPSTREAM_LICENSE, or README.md in the subtree folder.
    Update readme_forks.json if found.
    """
    import re
    data = load_readme_forks()
    updated = 0
    for entry in data:
        if entry.get('upstream'):
            continue
        subtree = entry.get('subtree_path')
        if not subtree:
            continue
        abs_path = os.path.join(ROOT, *subtree.split('/'))
        upstream = None
        upstream_url = None
        upstream_note = ''
        for marker in ('UPSTREAM.md', 'UPSTREAM_LICENSE', 'README.md'):
            marker_path = os.path.join(abs_path, marker)
            if os.path.isfile(marker_path):
                try:
                    with open(marker_path, encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                    match = re.search(r'https://github.com/([\w\-]+)/([\w\-\.]+)', content)
                    if match:
                        upstream = f"{match.group(1)}/{match.group(2)}"
                        upstream_url = f"https://github.com/{upstream}"
                        upstream_note = f"Upstream detected from {marker}"
                        break
                except Exception as ex:
                    upstream_note = f"Error reading {marker}: {ex}"
            for marker in ('UPSTREAM.md', 'UPSTREAM_LICENSE', 'README.md', 'LICENSE', 'LICENSE.txt', 'UPSTREAM_LICENSE.txt', 'license.md', 'LICENSE.md'):
                marker_path = os.path.join(abs_path, marker)
                if os.path.isfile(marker_path):
                    try:
                        with open(marker_path, encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                        match = re.search(r'https://github.com/([\w\-]+)/([\w\-\.]+)', content)
                        if match:
                            upstream = f"{match.group(1)}/{match.group(2)}"
                            upstream_url = f"https://github.com/{upstream}"
                            upstream_note = f"Upstream detected from {marker}"
                            break
                    except Exception as ex:
                        upstream_note = f"Error reading {marker}: {ex}"
        if upstream:
            entry['upstream'] = upstream
            entry['upstream_url'] = upstream_url
            notes = entry.get('notes', '')
            if notes:
                notes += f"; {upstream_note}"
            else:
                notes = upstream_note
            entry['notes'] = notes
            updated += 1
            print(f"Updated {entry.get('name')} ({subtree}): {upstream}")
    if updated:
        save_readme_forks(data)
        print(f"{updated} entries updated in readme_forks.json.")
    else:
        print("No missing upstreams could be detected.")
def cmd_scan():
    """
    Scan workspace for folders that are not present in readme_forks.json as subtree_path.
    Print missing subtrees.
    """
    import fnmatch
    data = load_readme_forks()
    known_subtrees = set(e.get('subtree_path') for e in data if e.get('subtree_path'))
    # Helper: check if a path is a subfolder of any known subtree
    def is_subfolder_of_known(path):
        for ks in known_subtrees:
            if ks and (path == ks or path.startswith(ks + '/')):
                return True
        return False
    # Folders to ignore
    ignore = {'.git', '__pycache__', '.vscode', '.idea', '.github', 'node_modules', '.venv', 'env', 'venv', '.mypy_cache'}
    found_subtrees = set()
    for root, dirs, files in os.walk(ROOT):
        # Remove ignored dirs in-place
        dirs[:] = [d for d in dirs if d not in ignore and not d.startswith('.')]
        rel_root = os.path.relpath(root, ROOT)
        rel_root_norm = rel_root.replace('\\', '/')
        if rel_root == '.' or rel_root.startswith('scripts'):
            continue
        # Ignore subfolders of already referenced subtrees
        if is_subfolder_of_known(rel_root_norm):
            continue
        # Heuristic: consider as subtree if contains UPSTREAM.md, UPSTREAM_LICENSE, README.md, or .git
        subtree_candidate = False
        for marker in ('UPSTREAM.md', 'UPSTREAM_LICENSE', 'README.md', '.git'):
            if marker in files or marker in dirs:
                subtree_candidate = True
                break
        if subtree_candidate:
            found_subtrees.add(rel_root_norm)
    missing = sorted(found_subtrees - known_subtrees)
    if not missing:
        print("Aucun dossier manquant détecté (tous les subtrees sont référencés dans readme_forks.json).")
        return
    print("Ajout automatique de stubs pour les subtrees absents :")
    data = load_readme_forks()
    for m in missing:
        # Guess name from last part of path
        name = m.split('/')[-1]
        abs_path = os.path.join(ROOT, *m.split('/'))
        upstream = None
        upstream_url = None
        upstream_note = ''
        # Try to detect upstream from UPSTREAM.md or UPSTREAM_LICENSE
        for marker in ('UPSTREAM.md', 'UPSTREAM_LICENSE'):
            marker_path = os.path.join(abs_path, marker)
            if os.path.isfile(marker_path):
                try:
                    with open(marker_path, encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                    # Look for a GitHub URL
                    import re
                    match = re.search(r'https://github.com/([\w\-]+)/([\w\-\.]+)', content)
                    if match:
                        upstream = f"{match.group(1)}/{match.group(2)}"
                        upstream_url = f"https://github.com/{upstream}"
                        upstream_note = f"Upstream detected from {marker}"
                        break
                except Exception as ex:
                    upstream_note = f"Error reading {marker}: {ex}"
        if not upstream:
            upstream_note = "No upstream detected"
        # Try to detect default branch
        local_default_branch = 'main'
        for branch_file in ['main', 'master']:
            branch_path = os.path.join(abs_path, branch_file)
            if os.path.isdir(branch_path) or os.path.isfile(branch_path):
                local_default_branch = branch_file
                break
        # Add marker info to notes
        notes = ["Stub auto-ajouté par scan"]
        if upstream_note:
            notes.append(upstream_note)
        for marker in ('README.md', 'UPSTREAM.md', 'UPSTREAM_LICENSE'):
            if os.path.isfile(os.path.join(abs_path, marker)):
                notes.append(f"{marker} present")
            for marker in ('README.md', 'UPSTREAM.md', 'UPSTREAM_LICENSE', 'LICENSE', 'LICENSE.txt', 'UPSTREAM_LICENSE.txt', 'license.md', 'LICENSE.md'):
                if os.path.isfile(os.path.join(abs_path, marker)):
                    notes.append(f"{marker} present")
        entry = {
            'source': name,
            'owner': 'OurITRes',
            'name': name,
            'local_default_branch': local_default_branch,
            'upstream': upstream,
            'upstream_url': upstream_url,
            'upstream_default_branch': None,
            'upstream_description': '',
            'upstream_license_name': None,
            'upstream_license_url': None,
            'subtree_path': m,
            'subtree_exists': True,
            'subtree_license_file': None,
            'subtree_license_verified': False,
            'verified': False,
            'notes': "; ".join(notes),
            'added_at': datetime.utcnow().isoformat() + 'Z',
        }
        data.append(entry)
        print(f"- {m} (ajouté)")
    save_readme_forks(data)
    print(f"{len(missing)} stubs ajoutés à readme_forks.json.")

if __name__ == '__main__':
    main()
    