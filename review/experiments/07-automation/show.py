"""Print the per-step differences of dumped results: show.py <dumpdir> [name ...]"""
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
names = sys.argv[2:] or sorted(p.stem for p in d.glob("*.json"))
def streams(items):
    out = {"automation_triggered": [], "call_service": [], "fire_event": []}
    for k, *rest in items: out[k].append(rest)
    return out
for n in names:
    r = json.loads((d / f"{n}.json").read_text())
    diffs = [(i, h, e) for i, (h, e) in enumerate(zip(r["ha"], r["engine"])) if streams(h) != streams(e)]
    if not diffs: continue
    print(f"== {n}")
    for i, h, e in diffs:
        print(f"  step {i}\n    HA:     {h}\n    engine: {e}")
    oth = [c for cs in r["engine_other"] for c in cs if c.get("type") == "unsupported" or c.get("level") in ("error", "warning")]
    for c in oth[:4]: print("    engine:", json.dumps(c)[:300])
    for l in [l for l in r.get("ha_log", []) if "asyncio" not in l.split(":")[0]][:3]: print("    ha_log:", l[:400])
