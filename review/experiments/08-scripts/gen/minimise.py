#!/opt/havenv/bin/python
"""Greedy minimiser for a failing scenario (a helper; the result is checked and
rewritten by hand before it goes to cases/).

    minimise.py <scenario.yaml> <out.yaml> [<signature-prefix>]

Each round writes every one-deletion candidate (a step, an action, a script,
an optional key) to a scratch directory, runs the harness copy over all of
them at once, and keeps the first candidate that still fails with "HA and
HALean disagree" and a signature starting with the prefix (default "other").
"""

from __future__ import annotations

import copy
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from triage import parse, signature  # noqa: E402

NEST = ("then", "else", "sequence", "default", "parallel")


def seqs(actions: list, out: list) -> None:
    """Every action list below `actions` (the lists themselves, to edit in place)."""
    out.append(actions)
    for a in actions:
        if not isinstance(a, dict):
            continue
        for k in NEST:
            if isinstance(a.get(k), list):
                seqs(a[k], out)
        if isinstance(a.get("repeat"), dict):
            seqs(a["repeat"]["sequence"], out)


def all_seqs(sc: dict) -> list[list]:
    out: list = []
    for cfg in sc["scripts"].values():
        seqs(cfg["sequence"], out)
    for st in sc["steps"]:
        for cfg in (st.get("reload") or {}).values():
            seqs(cfg["sequence"], out)
    return out


def candidates(sc: dict):
    for i in reversed(range(len(sc["steps"]))):
        c = copy.deepcopy(sc)
        del c["steps"][i]
        yield c
    for name in list(sc["scripts"]):
        if len(sc["scripts"]) > 1:
            c = copy.deepcopy(sc)
            del c["scripts"][name]
            yield c
    n = len(all_seqs(sc))
    for si in range(n):
        for ai in range(len(all_seqs(sc)[si])):
            c = copy.deepcopy(sc)
            s = all_seqs(c)[si]
            a = s[ai]
            del s[ai]
            yield c
            # replace a block by its body
            if isinstance(a, dict):
                for k in ("then", "sequence"):
                    if isinstance(a.get(k), list):
                        c = copy.deepcopy(sc)
                        s = all_seqs(c)[si]
                        s[ai:ai + 1] = copy.deepcopy(a[k])
                        yield c
                for k in ("response_variable", "continue_on_error", "data"):
                    if k in a:
                        c = copy.deepcopy(sc)
                        del all_seqs(c)[si][ai][k]
                        yield c
    for name, cfg in sc["scripts"].items():
        for k in ("alias", "icon", "variables", "max"):
            if k in cfg:
                c = copy.deepcopy(sc)
                del c["scripts"][name][k]
                yield c
        if cfg.get("mode") not in (None, "single"):
            c = copy.deepcopy(sc)
            del c["scripts"][name]["mode"]
            c["scripts"][name].pop("max", None)
            yield c
    for i, st in enumerate(sc["steps"]):
        for k in ("return_response", "response", "variables"):
            if k in st:
                c = copy.deepcopy(sc)
                del c["steps"][i][k]
                yield c
        if "call" in st and "data" in st and st["call"] not in ("turn_on", "turn_off", "toggle"):
            c = copy.deepcopy(sc)
            del c["steps"][i]["data"]
            yield c


def run(cands: list[dict], prefix: str) -> dict | None:
    """The first candidate that still fails with a wanted signature. pytest
    stops at the first failure (--maxfail=1); a failure with another
    signature is skipped and the rest is run again."""
    start = 0
    while start < len(cands):
        tmp = Path(tempfile.mkdtemp(prefix="min-", dir=os.environ.get("MIN_TMP")))
        try:
            for i in range(start, len(cands)):
                (tmp / f"c{i:04d}.yaml").write_text(yaml.safe_dump(cands[i], sort_keys=False, width=200))
            p = subprocess.run(
                ["/opt/havenv/bin/python", "-m", "pytest", str(HERE.parent / "harness" / "test_scripts.py"),
                 "-p", "no:cacheprovider", "-q", "--tb=short", "--maxfail=1"],
                env={**os.environ, "HALEAN_CASES": str(tmp)}, capture_output=True, text=True)
            res = parse(p.stdout)
            if not res:
                return None
            name = sorted(res)[0]
            i = int(name[1:])
            d = res[name]
            if not isinstance(d, str):
                try:
                    sig, _ = signature(cands[i], d)
                except Exception:  # noqa: BLE001
                    sig = ""
                if sig.startswith(prefix):
                    return cands[i]
            start = i + 1
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return None


def main() -> None:
    sc = yaml.safe_load(Path(sys.argv[1]).read_text())
    prefix = sys.argv[3] if len(sys.argv) > 3 else "other"
    while True:
        cands = list(candidates(sc))
        nxt = run(cands, prefix)
        if nxt is None:
            break
        sc = nxt
        # written after every round, so an interrupted run still leaves its best result
        Path(sys.argv[2]).write_text(yaml.safe_dump(sc, sort_keys=False, width=200))
        print(f"  {len(sc['steps'])} steps, {len(sc['scripts'])} scripts, "
              f"{sum(len(s) for s in all_seqs(sc))} actions", flush=True)
    Path(sys.argv[2]).write_text(yaml.safe_dump(sc, sort_keys=False, width=200))


if __name__ == "__main__":
    main()
