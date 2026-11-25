"""Group the failing cases of a dump directory by a rough signature: triage.py <dumpdir>"""
import json, sys, pathlib, collections
d = pathlib.Path(sys.argv[1])
def streams(items):
    out = {"automation_triggered": [], "call_service": [], "fire_event": []}
    for k, *rest in items: out[k].append(rest)
    return out
groups = collections.defaultdict(list)
for p in sorted(d.glob("*.json")):
    r = json.loads(p.read_text())
    diffs = [(i, h, e) for i, (h, e) in enumerate(zip(r["ha"], r["engine"])) if streams(h) != streams(e)]
    if not diffs: continue
    uns = [c["reason"] for cs in r["engine_other"] for c in cs if c.get("type") == "unsupported"]
    halog = [l for l in r["ha_log"] if "has been disabled" in l]
    i, h, e = diffs[0]
    sh, se = streams(h), streams(e)
    if uns: sig = "engine unsupported: " + uns[0][:60]
    elif halog: sig = "HA disabled: " + halog[0].split("disabled:")[1][:60]
    else:
        kinds = [k for k in sh if sh[k] != se[k]]
        sig = "first diff in " + "+".join(kinds) + (" (HA more)" if sum(map(len, sh.values())) > sum(map(len, se.values())) else " (engine more)" if sum(map(len, sh.values())) < sum(map(len, se.values())) else " (same count)")
    groups[sig].append((p.stem, i))
for sig, xs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    print(f"{len(xs):4d}  {sig}\n        " + " ".join(f"{n}@{i}" for n, i in xs[:12]))
