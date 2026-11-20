#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pyyaml"]
# ///
"""Run tests/scenarios/*.yaml through the engine binary.

Each scenario has `automations`, initial `states`, and `steps`. A step sends
one input (`at` seconds after t0 plus the message) and lists the commands it
expects, in order. Only call_service / fire_event / automation_triggered are
compared unless a step sets `logs: true`; expected dicts match as subsets.

These encode upstream behaviour as read from the Python source. They are
regression tests for the Lean engine, not yet differential tests against a
running Home Assistant (see README, "Next steps").
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bridge"))
from protocol import protocol_automations  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-automation"
T0 = 1_700_000_000_000  # 2023-11-14T22:13:20Z, a Tuesday


def subset(want, got) -> bool:
    if isinstance(want, dict):
        return isinstance(got, dict) and all(k in got and subset(v, got[k]) for k, v in want.items())
    return want == got


def state(eid: str, st: str, attrs: dict | None = None, changed: int = T0) -> dict:
    return {"entity_id": eid, "state": st, "attributes": attrs or {}, "last_changed": changed}


def engine_outputs(sc: dict) -> list[list[dict]]:
    """Run a parsed scenario through the engine; one command list per input
    (index 0 is init, then one per step)."""
    lines, _, _ = build(sc)
    proc = subprocess.run([str(ENGINE)], input="\n".join(json.dumps(l) for l in lines) + "\n",
                          capture_output=True, text=True, check=True)
    return [json.loads(l).get("cmds", []) for l in proc.stdout.splitlines()]


def run(path: Path) -> list[str]:
    sc = yaml.safe_load(path.read_text())
    _, expects, logs = build(sc)
    outs = [{"cmds": c} for c in engine_outputs(sc)]
    return compare(sc, expects, logs, outs)


def build(sc: dict) -> tuple[list[dict], list, list[bool]]:
    tz = sc.get("tz", 0)
    current = {s["entity_id"]: state(s["entity_id"], s["state"], s.get("attributes"))
               for s in sc.get("states", [])}
    lines = [{"type": "init", "now": T0, "tz": tz, "automations": protocol_automations(sc["automations"]),
              "states": list(current.values())}]
    expects = [sc.get("expect_init", [])]
    logs = [False]
    for st in sc["steps"]:
        now = T0 + int(st["at"] * 1000)
        if "set" in st:  # shorthand for a state change
            eid, val = st["set"]
            attrs = st.get("attributes", {})
            old = current.get(eid)
            changed = now if old is None or old["state"] != val else old["last_changed"]
            new = state(eid, val, attrs, changed)
            msg = {"type": "state_changed", "entity_id": eid, "old_state": old, "new_state": new}
            current[eid] = new
        else:
            msg = dict(st["send"])
        msg.update(now=now, tz=tz)
        lines.append(msg)
        expects.append(st.get("expect", []))
        logs.append(st.get("logs", False))
    return lines, expects, logs


def compare(sc: dict, expects: list, logs: list[bool], outs: list[dict]) -> list[str]:
    failures = []
    for i, (want, out, keep_logs) in enumerate(zip(expects, outs, logs)):
        got = [c for c in out.get("cmds", [])
               if keep_logs or c["type"] not in ("log",)]
        if want == "any":
            continue
        if len(got) != len(want) or not all(subset(w, g) for w, g in zip(want, got)):
            label = "init" if i == 0 else f"step {i} (at={sc['steps'][i-1]['at']})"
            failures.append(f"  {label}\n    want: {json.dumps(want)}\n    got:  {json.dumps(got)}")
    return failures


def main() -> int:
    files = sorted((ROOT / "tests" / "scenarios").glob("*.yaml"))
    bad = 0
    for f in files:
        fails = run(f)
        print(f"{'PASS' if not fails else 'FAIL'}  {f.stem}")
        for msg in fails:
            print(msg)
        bad += bool(fails)
    print(f"\n{len(files) - bad}/{len(files)} scenarios passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
