#!/usr/bin/env python3
"""
Gestion simple des forks et génération automatique du tableau dans README.md.

Usage:
  python scripts/manage_forks.py add owner/repo --subdir path/to/subdir
  python scripts/manage_forks.py remove owner/repo
  python scripts/manage_forks.py list
  python scripts/manage_forks.py generate

Le script met à jour forks.json (à la racine) et README.md (à la racine).
Pour des requêtes GitHub plus permissives, exporte GITHUB_TOKEN.
"""
import os
import sys
import json
import argparse
import requests
from datetime import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
FORKS_JSON = os.path.join(ROOT, 'readme_forks.json')
README_MD = os.path.join(ROOT, 'README.md')

MARKER_START = '<!-- FORKS_TABLE_START -->'
MARKER_END = '<!-- FORKS_TABLE_END -->'

GITHUB_API = 'https://api.github.com'

def load_forks():
    if not os.path.exists(FORKS_JSON):
        return []
    with open(FORKS_JSON, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_forks(data):
    with open(FORKS_JSON, 'w', encoding='utf-8') as f:
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
    # License best-effort
    license_obj = repo_data.get('license') or {}
    license_name = license_obj.get('name') or license_obj.get('spdx_id') or None
    license_api_url = license_obj.get('url')  # API url, may be None
    license_html = None
    if license_api_url:
        # Try to resolve license API to a nicer HTML if possible
        # license_api_url looks like https://api.github.com/licenses/{key}
        # We can use the license key to point to choosealicense or use repo html + /blob/.../LICENSE (best-effort)
        try:
            lic = github_get(license_api_url.replace(GITHUB_API, '')) if license_api_url.startswith(GITHUB_API) else None
            if lic and lic.get('upstream_url'):
                license_html = lic.get('upstream_url')
        except Exception:
            license_html = None
    # fallback: try to point at the repo's LICENSE file
    if not license_html:
        default_branch = repo_data.get('default_branch') or 'main'
        license_html = f'{repo_data.get("html_url")}/blob/{default_branch}/LICENSE'
    return {
        'upstream': repo_data.get('upstream'),
        'upstream_url': repo_data.get('upstream_url'),
        'upstream_description': repo_data.get('upstream_description') or '',
        'upstream_license_name': license_name or '',
        'license_url': license_html
    }

def add_fork(args):
    fullname = args.repo
    subdir = args.subdir
    forks = load_forks()
    if any(f.get('upstream', '').lower() == fullname.lower() for f in forks):
        print(f'{fullname} existe déjà dans {FORKS_JSON}')
        return
    info = None
    try:
        info = fetch_repo_info(fullname)
    except Exception as e:
        print('Erreur en interrogeant GitHub:', e)
        sys.exit(1)
    if not info:
        print(f'Impossible de récupérer les infos pour {fullname}')
        sys.exit(1)
    entry = {
        'upstream': info['upstream'],
        'repo_url': info['upstream_url'],
        'upstream_description': info['upstream_description'],
        'upstream_license_name': info['upstream_license_name'],
        'license_url': info['license_url'],
        'subtree_path': subdir or f'./{fullname.split("/",1)[1]}',
        'added_at': datetime.utcnow().isoformat() + 'Z'
    }
    forks.append(entry)
    save_forks(forks)
    print(f'Ajouté: {fullname}')
    generate_readme()  # update README after add

def remove_fork(args):
    fullname = args.repo
    forks = load_forks()
    new = [f for f in forks if f.get('upstream','').lower() != fullname.lower()]
    if len(new) == len(forks):
        print(f'{fullname} non trouvé dans {FORKS_JSON}')
        return
    save_forks(new)
    print(f'Supprimé: {fullname}')
    generate_readme()  # update README after remove

def list_forks(_args):
    forks = load_forks()
    if not forks:
        print('Aucun fork enregistré.')
        return
    for f in forks:
        print(f"- {f.get('upstream')} -> subdir: {f.get('subtree_path')}")

def generate_readme():
    forks = load_forks()
    # Generate markdown table
    lines = []
    lines.append('| Nom | Description | Licence |')
    lines.append('|---|---|---|')
    for f in sorted(forks, key=lambda x: x.get('upstream','').lower()):
        name = f.get('upstream')
        sub = f.get('subtree_path') or './'
        # Make relative link to subdir as requested
        name_link = f'[{name}]({sub})'
        desc = (f.get('upstream_description') or '').replace('\n',' ').strip()
        lic_name = f.get('upstream_license_name') or 'Unknown'
        lic_url = f.get('license_url')
        if lic_url:
            lic = f'[{lic_name}]({lic_url})'
        else:
            lic = lic_name
        lines.append(f'| {name_link} | {desc} | {lic} |')
    table_md = '\n'.join(lines) + '\n'

    # Read README.md (create if absent)
    if not os.path.exists(README_MD):
        base = '# Repositories forked\n\n'
    else:
        with open(README_MD, 'r', encoding='utf-8') as f:
            base = f.read()

    if MARKER_START in base and MARKER_END in base:
        before = base.split(MARKER_START,1)[0]
        after = base.split(MARKER_END,1)[1]
        new_content = before + MARKER_START + '\n\n' + table_md + '\n' + MARKER_END + after
    else:
        # Append markers at end
        new_content = base.rstrip() + '\n\n' + MARKER_START + '\n\n' + table_md + '\n' + MARKER_END + '\n'

    with open(README_MD, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('README.md mis à jour.')

def generate_cmd(_args):
    generate_readme()

def main():
    parser = argparse.ArgumentParser(description='Gérer forks et générer README')
    sub = parser.add_subparsers(dest='cmd')

    p_add = sub.add_parser('add', help='Ajouter un fork (owner/repo)')
    p_add.add_argument('repo', help='owner/repo (ex: octocat/Hello-World)')
    p_add.add_argument('--subdir', help='chemin relatif vers le sous-répertoire dans ce repo (ex: Games/Hello-World)')

    p_remove = sub.add_parser('remove', help='Retirer un fork')
    p_remove.add_argument('repo', help='owner/repo')

    p_list = sub.add_parser('list', help='Lister les forks enregistrés')

    p_gen = sub.add_parser('generate', help='Générer le tableau et mettre à jour README.md')

    args = parser.parse_args()
    if args.cmd == 'add':
        add_fork(args)
    elif args.cmd == 'remove':
        remove_fork(args)
    elif args.cmd == 'list':
        list_forks(args)
    elif args.cmd == 'generate':
        generate_cmd(args)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
