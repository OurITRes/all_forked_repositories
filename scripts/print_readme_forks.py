#!/usr/bin/env python3
import json
import os
import sys

PATH = os.path.join(os.path.dirname(__file__), '..', 'readme_forks.json')
PATH = os.path.abspath(PATH)

if not os.path.exists(PATH):
    print('readme_forks.json introuvable:', PATH)
    sys.exit(1)

with open(PATH, encoding='utf-8') as f:
    data = json.load(f)

for e in data:
    source = e.get('source') or f"{e.get('owner','')}/{e.get('name','')}".strip('/')
    upstream = e.get('upstream', '')
    subtree = e.get('subtree_path', '')
    verified = bool(e.get('verified', False))
    print(f"- {source} -> upstream: {upstream} subtree: {subtree} verified: {verified}")