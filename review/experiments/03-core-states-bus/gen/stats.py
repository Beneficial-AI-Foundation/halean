"""Coverage statistics of a generated case file, measured on HALean alone:
  python gen/stats.py states|events FILE.yaml
Prints how many operations there are and how many produced events / errors / refusals
(states) or deliveries / logs / errors (events), to show the sequences are not trivial."""
import collections
import json
import os
import subprocess
import sys
from datetime import UTC, datetime, timedelta

import yaml

kind, path = sys.argv[1], sys.argv[2]
BIN = os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")
cases = yaml.safe_load(open(path))
c = collections.Counter()
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
for case in cases:
    exe = "halean-core-states" if kind == "states" else "halean-core-events"
    p = subprocess.Popen([f"{BIN}/{exe}"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    now = 1795710645123456
    for op in case["ops"]:
        c["ops"] += 1
        c["op:" + op["op"]] += 1
        if kind == "states":
            if "now" in op:
                now = (datetime.fromisoformat(op["now"]) - EPOCH) // timedelta(microseconds=1)
            msg = {k: v for k, v in op.items() if k not in ("unsupported", "expect")} | {"now": now}
        else:
            now = op.get("now", now)
            msg = {**op, "now": now}
        p.stdin.write(json.dumps(msg) + "\n")
        p.stdin.flush()
        r = json.loads(p.stdout.readline())
        if "unsupported" in r:
            c["unsupported"] += 1
        elif kind == "states":
            if "error" in r:
                c["error:" + r["error"]["type"]] += 1
            for e in r.get("events", []):
                c["event:" + e["event_type"]] += 1
        else:
            if "error" in r["result"]:
                c["error:" + r["result"]["error"]] += 1
            c["deliveries"] += len(r["deliveries"])
            c["ops_with_deliveries"] += bool(r["deliveries"])
            c["max_deliveries_one_op"] = max(c["max_deliveries_one_op"], len(r["deliveries"]))
            for l in r["logs"]:
                c["log:" + l] += 1
    p.stdin.close()
    p.wait()
print(f"{path}: {len(cases)} cases")
for k in sorted(c):
    print(f"  {k}: {c[k]}")
