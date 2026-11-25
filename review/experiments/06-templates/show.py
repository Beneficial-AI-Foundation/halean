#!/usr/bin/env python3
"""Print the non-matching records of a batch output file. usage: show.py out.jsonl [cat ...]"""
import json, sys
cats = set(sys.argv[2:])
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r["cat"] == "same" or (cats and r["cat"] not in cats):
        continue
    ha = r["ha"]; le = r["lean"]
    h = f'{ha["type"]} {ha["repr"]}' if ha.get("ok") else "ERR " + ha["error"][:90]
    l = ("UNSUP " + le["unsupported"][:80]) if "unsupported" in le else (f'{le["type"]} {le["repr"]}' if le.get("ok") else "ERR " + le["error"][:80])
    print(f'[{r["cat"]}] {r["name"]}: {r["template"][:100]!r}\n     HA: {h}\n   Lean: {l}' + (f'\n   HAinfo: {r.get("ha_info")}\n   Leaninfo: {le.get("info")}' if r["cat"]=="info" else ""))
