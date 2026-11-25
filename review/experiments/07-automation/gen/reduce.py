#!/opt/havenv/bin/python
"""Shrink a diverging scenario (a helper for minimising random cases by hand).

    reduce.py <scenario.yaml> <out.yaml> [--rounds N]

Greedy delta debugging over the YAML tree. One round writes every candidate
(one list element or one mapping key removed, a block replaced by its body, the
steps cut after the first differing step) into a scratch directory, runs the
harness copy over all of them in one pytest call with AUT_DUMP, and keeps the
first candidate that still diverges without HA disabling an automation and
without the engine answering `unsupported` (unless the original did). The
result still has to be read and finished by hand.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent.parent
SCRATCH = Path("/tmp/claude-0/aut-scratch")
BODY_KEYS = ("then", "else", "sequence", "default")


def streams(items):
    out = {"automation_triggered": [], "call_service": [], "fire_event": []}
    for k, *rest in items:
        out[k].append(rest)
    return out


def run_batch(cands: list[dict]) -> list[dict | None]:
    d = Path(tempfile.mkdtemp(dir=SCRATCH))
    for i, sc in enumerate(cands):
        (d / f"c{i:04d}.yaml").write_text(yaml.safe_dump(sc, sort_keys=False))
    env = dict(os.environ, AUT_CASES=str(d), AUT_DUMP=str(d / "dump"))
    subprocess.run(["/opt/havenv/bin/python", "-m", "pytest", ".", "-p", "no:cacheprovider", "-q", "--deselect",
                    "test_differential.py::test_harness_matches_pin"],
                   cwd=HERE / "harness", env=env, capture_output=True, text=True)
    res = []
    for i in range(len(cands)):
        f = d / "dump" / f"c{i:04d}.json"
        res.append(json.loads(f.read_text()) if f.exists() else None)
    shutil.rmtree(d)
    return res


def verdict(r: dict | None) -> tuple[bool, bool, int]:
    """(diverges, tainted, first differing step)"""
    if r is None:
        return False, True, -1
    diffs = [i for i, (h, e) in enumerate(zip(r["ha"], r["engine"])) if streams(h) != streams(e)]
    taint = any("has been disabled" in l or "Invalid config" in l for l in r["ha_log"]) or any(
        c.get("type") == "unsupported" for cs in r["engine_other"] for c in cs)
    return bool(diffs), taint, (diffs[0] if diffs else -1)


def paths(node, path=()):
    """Every (path, kind) edit site below `node`."""
    if isinstance(node, list):
        for i, x in enumerate(node):
            yield path + (i,), "del"
            yield from paths(x, path + (i,))
    elif isinstance(node, dict):
        for k, v in node.items():
            yield path + (k,), "del"
            if k in BODY_KEYS and isinstance(v, list):
                yield path + (k,), "hoist"
            yield from paths(v, path + (k,))


def get(node, path):
    for p in path:
        node = node[p]
    return node


def apply(sc: dict, path, kind) -> dict | None:
    sc = copy.deepcopy(sc)
    try:
        parent = get(sc, path[:-1])
        if kind == "del":
            del parent[path[-1]]
        else:  # hoist: replace the action holding this body by the body
            body = parent[path[-1]]
            holder_list = get(sc, path[:-2])
            idx = path[-2]
            if not isinstance(holder_list, list):
                return None
            holder_list[idx:idx + 1] = body
    except (KeyError, IndexError, TypeError):
        return None
    if not sc.get("automations") or not sc.get("steps"):
        return None
    return sc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--rounds", type=int, default=60)
    args = ap.parse_args()
    sc = yaml.safe_load(args.src.read_text())
    (r0,) = run_batch([sc])
    div, taint0, first = verdict(r0)
    if not div:
        print("the scenario does not diverge")
        return 1
    # cut the steps after the first differing one (step index 0 is init)
    if first >= 1:
        sc["steps"] = sc["steps"][:first]
    for rnd in range(args.rounds):
        sites = [(("automations",) + p, k) for p, k in paths(sc["automations"])]
        sites += [(("steps", i), "del") for i in range(len(sc["steps"]))]
        sites += [(("states", i), "del") for i in range(len(sc.get("states", [])))]
        # larger removals first
        sites.sort(key=lambda s: len(s[0]))
        cands = [(s, c) for s in sites if (c := apply(sc, *s)) is not None]
        res = run_batch([c for _, c in cands])
        ok_sites = []
        for (site, _cand), r in zip(cands, res):
            d, t, _ = verdict(r)
            if d and (taint0 or not t):
                ok_sites.append(site)
        if not ok_sites:
            break
        # apply every removal that worked alone, deepest / last index first so that the
        # paths of the others stay valid; fall back to halves, then to the first one
        def combine(sites):
            cur = sc
            for site in sorted(sites, key=lambda s: tuple(str(x).rjust(6, "0") if isinstance(x, int) else x for x in s[0]), reverse=True):
                nxt = apply(cur, *site)
                if nxt is not None:
                    cur = nxt
            return cur
        tries = [ok_sites, ok_sites[: max(1, len(ok_sites) // 2)], ok_sites[: max(1, len(ok_sites) // 4)], ok_sites[:1]]
        res2 = run_batch([combine(t) for t in tries])
        for t, r in zip(tries, res2):
            d, tnt, _ = verdict(r)
            if d and (taint0 or not tnt):
                sc = combine(t)
                print(f"round {rnd}: applied {len(t)} of {len(ok_sites)} removals", flush=True)
                break
        else:
            break
    args.out.write_text(yaml.safe_dump(sc, sort_keys=False, default_flow_style=None, width=200))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
