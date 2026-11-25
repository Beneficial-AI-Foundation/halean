#!/usr/bin/env python3
"""classify.py <pytest log> : one line per failed case with the root cause it shows.
Rules (checked on the HA / HALean results printed by the harness assertion):
  HLP-21  only the order of `outs` differs, in an `advance` step (timers finishing in one tick)
  HLP-4   only `logs` differ and HA's extra logs are the input_select duplicate warning, config invalid
  REFUSED HALean answered `unsupported` (the reason is printed)
  OTHER   anything else (to be read by hand)
A hand-written case listed in ../cases/divergent.tsv gets the ID written there.
"""
import ast, collections, os, re, sys
KNOWN = {}
_tsv = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cases", "divergent.tsv")
for _l in open(_tsv):
    if _l.strip() and not _l.startswith("#"):
        _n, _i = _l.split()
        KNOWN[_n] = _i
name = step = ha = lean = None
rows = []
def flush():
    global name, step, ha, lean
    if name and step is not None:
        kind = "OTHER"
        if isinstance(lean, str):
            kind = "REFUSED: " + lean[:110]
        elif ha is not None and lean is not None:
            diff = [k for k in set(ha) | set(lean) if ha.get(k) != lean.get(k)]
            if diff == ["outs"] and sorted(ha["outs"]) == sorted(lean["outs"]) and "advance" in step:
                kind = "HLP-21"
            elif diff == ["logs"] and ha.get("ok") is False and not lean["logs"] and all("had duplicated options" in l[1] for l in ha["logs"]):
                kind = "HLP-4"
            else:
                kind = "OTHER diff=" + ",".join(sorted(diff))
        if name in KNOWN:
            kind = KNOWN[name] + " (cases/divergent.tsv)"
        rows.append((name, kind, step[:100]))
    step = ha = lean = None
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"_+ test_helpers\[(.*)\] _+$", line)
    if m:
        flush(); name = m.group(1); continue
    if not line.startswith("E  "): continue
    t = line[1:].strip()
    if t.startswith("AssertionError: step"): step = t[len("AssertionError: "):]
    elif t.startswith("HA:"):
        try: ha = ast.literal_eval(t[3:].strip())
        except Exception: ha = None
    elif t.startswith("HALean:"):
        try: lean = ast.literal_eval(t[7:].strip())
        except Exception: lean = None
    elif t.startswith("HALean rejected it:"): lean = t[len("HALean rejected it:"):].strip()
flush()
for r in rows: print("%-45s %-22s %s" % r)
c = collections.Counter(k.split(":")[0].split(" ")[0] for _, k, _ in rows)
c = dict(sorted(c.items(), key=lambda kv: (len(kv[0]), kv[0])))
print("TOTAL failed cases:", len(rows), dict(c))
