#!/usr/bin/env python3
"""
Gérer readme_forks.json et génération automatique du tableau dans README.md.

Usage:
  python scripts/manage_forks.py add owner/repo --source OurITRes/Repo --subtree path/to/subtree --local-branch main
  python scripts/manage_forks.py remove owner/repo-or-source
  python scripts/manage_forks.py list
  python scripts/manage_forks.py generate

Le script lit/écrit readme_forks.json (à la racine) et met à jour README.md (à la racine).
Pour des requêtes GitHub plus permissives, exporte GITHUB_TOKEN.
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
    lines.append("| Source | Upstream | Subtree path | Upstream license | Subtree exists | Verified | Notes |")
    lines.append("| ------ | -------- | ------------ | ---------------- | -------------: | :------: | ----- |")
    for e in entries:
        source = e.get('source') or f"{e.get('owner')}/{e.get('name')}"
        upstream = e.get('upstream_url') or (f"https://github.com/{e.get('upstream')}") if e.get('upstream') else ''
        upstream_md = f"[{e.get('upstream')}]({upstream})" if upstream else (e.get('upstream') or '')
        subtree = e.get('subtree_path') or ''
        upstream_license = e.get('upstream_license_name') or ''
        subtree_exists = '✅' if e.get('subtree_exists') else '❌'
        verified = '✅' if e.get('verified') else ''
        notes = (e.get('notes') or '').replace('\n', ' ')
        lines.append(f"| {source} | {upstream_md} | {subtree} | {upstream_license} | {subtree_exists} | {verified} | {notes} |")
    return "\n".join(lines)


def cmd_generate(_args):
    entries = load_readme_forks()
    table = generate_readme_table(entries)
    if not os.path.exists(README_MD):
        print("README.md introuvable, génération annulée.")
        return
    with open(README_MD, 'r', encoding='utf-8') as f:
        content = f.read()
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
    args = parser.parse_args()
    if args.cmd == 'add':
        cmd_add(args)
    elif args.cmd == 'remove':
        cmd_remove(args)
    elif args.cmd == 'list':
        cmd_list(args)
    elif args.cmd == 'generate':
        cmd_generate(args)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
    