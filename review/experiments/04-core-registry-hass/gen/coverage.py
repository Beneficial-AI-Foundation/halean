#!/usr/bin/env python3
"""What the generated core cases exercise: replays them on the engine alone and
counts trace entries by kind.  python coverage.py DIR [engine]"""
import json, subprocess, sys
from collections import Counter
from pathlib import Path
import yaml

NOW = 1795710645123456
engine = sys.argv[2] if len(sys.argv) > 2 else "/home/user/halean/.lake/build/bin/halean-core"
c = Counter()
for f in sorted(Path(sys.argv[1]).glob("*.yaml")):
    for case in yaml.safe_load(f.read_text()):
        p = subprocess.Popen([engine], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        def ask(m):
            p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
            return json.loads(p.stdout.readline())
        ask({"op": "init", "listeners": [], "now": 0})
        now = NOW
        manual = case.get("manual", False)
        c["cases"] += 1
        ops = case["ops"] + ([{"op": "block_till_done"}] if manual else [])
        for op in ops:
            now = op.get("now", now)
            outs = [ask({**{k: v for k, v in op.items() if k != "unsupported"}, "now": now})]
            if "unsupported" in outs[0]:
                c["operations answered unsupported"] += 1
                continue
            c["operations"] += 1
            if not manual:
                outs.append(ask({"op": "block_till_done", "now": now}))
            if "error" in outs[0]["result"]:
                c["operation results that are exceptions: " + outs[0]["result"]["error"]["exception"]] += 1
            for o in outs:
                for t in o["trace"]:
                    if "delivery" in t:
                        c["deliveries"] += 1
                    elif "call" in t:
                        c["scripted call outcomes: " + ("ok" if "ok" in t else t["error"]["exception"])] += 1
                    elif "log" in t:
                        c["log: " + t["log"]["message"].split(":")[0][:45] + (" / Task exception was never retrieved" if "never retrieved" in t["log"]["message"] else "")] += 1
        p.stdin.close(); p.wait()
for k, v in sorted(c.items()):
    print(f"{v:8d}  {k}")
