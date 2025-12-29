#!/usr/bin/env python3
# scripts/get_installation_id.py
# Reads JSON list of installations from stdin and prints installation id for given org login (case-insensitive)
# Usage: cat installations.json | python3 scripts/get_installation_id.py ouritres

import sys, json

if len(sys.argv) < 2:
    print("", end="")
    sys.exit(0)

target = sys.argv[1].lower()
data = json.load(sys.stdin)
for it in data:
    acct = it.get("account", {})
    if acct.get("login", "").lower() == target:
        print(it.get("id"))
        sys.exit(0)
# not found -> print empty
print("", end="")