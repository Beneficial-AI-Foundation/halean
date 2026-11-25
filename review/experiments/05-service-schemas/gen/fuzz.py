"""Fast triage runner (not the verdict): generate cases with gen_random and
compare real probatio (fresh schema per case, as the harness builds it) with
halean-core-services directly, without a hass instance. Prints one line per
difference, grouped by a coarse signature.  fuzz.py --seed N --schemas S --data D
"""
from __future__ import annotations
import argparse, collections, json, random, sys
import explore, gen_random
from explore import Engine, ha_validate, lean_validate, make_schema

ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=1); ap.add_argument("--schemas", type=int, default=500)
ap.add_argument("--data", type=int, default=12); ap.add_argument("--show", type=int, default=3)
ap.add_argument("--out"); ap.add_argument("--skip-unsupported", action="store_true")
a = ap.parse_args()
r = random.Random(a.seed)
eng = Engine()
sigs = collections.defaultdict(list); n = 0
for i in range(a.schemas):
    c = gen_random.case(r, i, a.data, a.seed)
    spec = c["ops"][0]["schema"]
    try:
        schema = make_schema(spec)
    except Exception as e:  # noqa: BLE001
        sigs[f"BUILD {type(e).__name__}: {str(e)[:60]}"].append((spec, None, None, None)); continue
    first = True
    for op in c["ops"][1:]:
        d = op["data"]; n += 1
        ha = ha_validate(schema, d)
        try:
            le = lean_validate(eng, spec, d, reg=first); first = False
        except RuntimeError:
            le = ("ENGINE DIED",); eng = Engine(); first = True
        if ha == le:
            continue
        if le[0].startswith("unsupported"):
            if a.skip_unsupported: continue
            sig = f"UNSUP[{le[1][:70]}] ha={ha[0]}"
        elif ha[0] != le[0]:
            sig = f"{ha[0]}:{ha[1][:40] if ha[0]=='err' else ''} / {le[0]}:{le[1][:40] if le[0]=='err' else ''}"
        elif ha[0] == "err":
            import re
            sig = "MSG " + re.sub(r"[0-9]+", "N", ha[2])[:50] + " / " + re.sub(r"[0-9]+", "N", le[2])[:50]
        else:
            sig = "VALUE"
        sigs[sig].append((spec, d, ha, le))
def cut(x):
    s = x if isinstance(x, str) else json.dumps(x)
    return s if len(s) < 600 else s[:400] + " ... " + s[-150:]
print(f"seed {a.seed}: {n} pairs, {sum(len(v) for v in sigs.values())} differ")
for sig, items in sorted(sigs.items(), key=lambda kv: -len(kv[1])):
    print(f"\n== {len(items)} x {sig}")
    for spec, d, ha, le in sorted(items, key=lambda it: len(json.dumps(it[0])) + len(json.dumps(it[1])))[:a.show]:
        print("  spec", cut(spec)); print("  data", cut(d)); print("  HA  ", cut(repr(ha))); print("  Lean", cut(repr(le)))
