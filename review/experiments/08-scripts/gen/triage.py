#!/opt/havenv/bin/python
"""Triage a pytest log of the harness copy.

    triage.py <pytest-log> <case-dir> [-v]

For every failed case: the first step where HA and HALean differ, which
observation keys differ there, and a signature guessed from HALean's own
logs and outputs up to that step (the harness drops HALean's `logs`; this
script runs halean-script again to get them). Signatures:

  turn_on-not-started  HALean logged "turning on a script that does not start"
                       at or before the first differing step (README gap)
  call-to-ha:script.*  HALean sent a call_service for a script.* service to HA
  reload-window        the first difference is in a reload step
  ha-indexerror        the HA side had fewer service calls than HALean (IndexError)
  other                none of the above; printed with -v
"""

from __future__ import annotations

import ast
import re
import sys
from collections import Counter
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "harness"))
from run_script_scenarios import lean_run  # noqa: E402


def parse(log: str) -> dict[str, list[tuple[str, dict, dict]] | str]:
    """case id -> list of (label, ha, lean), or an error string."""
    out: dict = {}
    blocks = re.split(r"^_{3,} test_script_scenario\[(.+?)\] _{3,}$", log, flags=re.M)
    for name, body in zip(blocks[1::2], blocks[2::2]):
        if "HA and HALean disagree" not in body:
            m = re.search(r"^E +(\w+(?:Error|Exception)[^\n]*)", body, flags=re.M)
            out[name] = m.group(1) if m else "unknown failure"
            continue
        diffs = []
        for m in re.finditer(r"^E +(init|step at=[\d.]+)\nE +HA: +(\{.*\})\nE +HALean: +(\{.*\})$", body, flags=re.M):
            diffs.append((m.group(1), ast.literal_eval(m.group(2)), ast.literal_eval(m.group(3))))
        out[name] = diffs
    return out


def signature(sc: dict, diffs) -> tuple[str, tuple | None]:
    """The signature of one failed case and its first differing step."""
    _, obs = lean_run(sc)
    labels = ["init"] + [f"step at={s['at']}" for s in sc["steps"]]
    if isinstance(diffs, str):
        return ("ha-indexerror" if diffs.startswith("IndexError") else f"error:{diffs[:60]}"), None
    if not diffs:
        return "error:unparsed", None
    first = diffs[0]
    # index of the first differing step (labels repeat; take the first whose lean obs matches)
    idx = next(i for i, (lab, o) in enumerate(zip(labels, obs))
               if lab == first[0] and {k: v for k, v in o.items() if k != "logs"}
               | {"call_done": sorted(o["call_done"], key=lambda c: c[0])} == first[2])
    upto = obs[: idx + 1]
    logs = [m for o in upto for _, m in o["logs"]]
    keys = [k for k in first[1] if first[1][k] != first[2][k]]
    if any("turning on a script that does not start" in m for m in logs):
        return "turn_on-not-started", first
    if any(c[0] == "script" for o in upto for c in o["call_service"]):
        return "call-to-ha:script.*", first
    if idx > 0 and "reload" in sc["steps"][idx - 1]:
        return "reload-window", first
    return "other:" + "+".join(keys), first


def main() -> None:
    log = Path(sys.argv[1]).read_text()
    cases = Path(sys.argv[2])
    verbose = "-v" in sys.argv
    res = parse(log)
    sigs: Counter = Counter()
    for name, diffs in sorted(res.items()):
        sc = yaml.safe_load((cases / f"{name}.yaml").read_text())
        sig, first = signature(sc, diffs)
        sigs[sig] += 1
        print(f"{name}: {sig}")
        if verbose and first and sig.startswith("other"):
            print(f"   {first[0]}")
            for k in first[1]:
                if first[1][k] != first[2][k]:
                    print(f"     {k}\n       HA:     {first[1][k]}\n       HALean: {first[2][k]}")
    print("\nsignatures:")
    for s, n in sigs.most_common():
        print(f"  {n:4d}  {s}")
    print(f"  {len(res):4d}  failed cases in total")


if __name__ == "__main__":
    main()
