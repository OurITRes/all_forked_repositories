#!/usr/bin/env python3
"""
Generate a simple forks.json from forks.yaml
Usage: python3 scripts/generate_forks_json.py forks.yaml out/forks.json
"""
import sys, json, yaml
if len(sys.argv) < 3:
    print("Usage: generate_forks_json.py forks.yaml out.json", file=sys.stderr)
    sys.exit(2)
src = sys.argv[1]
dst = sys.argv[2]
with open(src) as f:
    y = yaml.safe_load(f)
forks = y.get("forks", [])
out = []
for f in forks:
    out.append({
        "source": f.get("source"),
        "owner": f.get("owner"),
        "name": f.get("name"),
        "default_branch": f.get("default_branch","master"),
        "upstream": f.get("upstream",""),
        "migrate_to": f.get("migrate_to",""),
        "url": f.get("url","")
    })
with open(dst, "w") as f:
    json.dump(out, f, indent=2)
print(f"Wrote {len(out)} entries to {dst}")