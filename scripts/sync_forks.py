#!/usr/bin/env python3
"""
Simple sync script (uses forks.yaml)
Usage: python3 scripts/sync_forks.py dry-run|real
- For each fork: fetch upstream, create branch import-sync/<name>-YYYYMMDD, create PR with changes if any
Requires PyYAML, git, curl
"""
import os,sys,subprocess,datetime,yaml

mode = sys.argv[1] if len(sys.argv)>1 else "dry-run"
PAT = os.environ.get("FORKS_MANAGER_PAT") or os.environ.get("GITHUB_TOKEN")
ROOT = os.getcwd()
LOGDIR = os.path.join(ROOT,"logs")
os.makedirs(LOGDIR,exist_ok=True)
now = datetime.datetime.utcnow().strftime("%Y%m%d")
with open("forks.yaml") as f:
    cfg = yaml.safe_load(f)
for entry in cfg.get("forks",[]):
    src = entry.get("source")
    name = entry.get("name")
    upstream = entry.get("upstream")
    default_branch = entry.get("default_branch","master")
    logf = os.path.join(LOGDIR, f"sync-{name}-{now}.log")
    print(f"Syncing {src} from upstream {upstream} -> log {logf}")
    with open(logf,"a") as L:
        L.write(f"Sync run for {name} mode={mode}\n")
        if mode=="dry-run":
            L.write("DRY RUN: would fetch upstream and create PR if changes\n")
            continue
        # clone fork, add upstream, fetch, merge upstream/default_branch, push branch and create PR
        tmp = f"/tmp/sync-{name}"
        try:
            subprocess.run(["rm","-rf",tmp])
            subprocess.check_call(["git","clone","--depth","1",f"https://github.com/{src}.git",tmp], stdout=L, stderr=L)
            subprocess.check_call(["git","-C",tmp,"remote","add","upstream",f"https://github.com/{upstream}.git"], stdout=L, stderr=L)
            subprocess.check_call(["git","-C",tmp,"fetch","upstream"], stdout=L, stderr=L)
            subprocess.check_call(["git","-C",tmp,"checkout","-B",default_branch,f"origin/{default_branch}"], stdout=L, stderr=L)
            # merge upstream
            try:
                subprocess.check_call(["git","-C",tmp,"merge",f"upstream/{default_branch}","--no-edit"], stdout=L, stderr=L)
            except subprocess.CalledProcessError:
                # create sync branch and push
                branch = f"sync/upstream-{now}"
                subprocess.check_call(["git","-C",tmp,"checkout","-B",branch], stdout=L, stderr=L)
                subprocess.check_call(["git","-C",tmp,"push","-u","origin",branch], stdout=L, stderr=L)
                # create PR
                title = f"Sync from upstream/{default_branch}"
                body = "Automated sync from upstream"
                api = f"https://api.github.com/repos/{src}/pulls"
                payload = {"title":title,"body":body,"head":branch,"base":default_branch}
                import json, requests
                headers = {"Authorization":f"token {PAT}","Accept":"application/vnd.github+json"}
                r = requests.post(api, headers=headers, data=json.dumps(payload))
                L.write(f"PR create status: {r.status_code} {r.text}\n")
            finally:
                subprocess.run(["rm","-rf",tmp])
        except Exception as e:
            L.write(f"Error: {e}\n")
            subprocess.run(["rm","-rf",tmp])