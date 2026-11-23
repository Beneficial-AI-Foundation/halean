#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pyyaml"]
# ///
"""Run tests/script_scenarios/*.yaml through halean-script.

A scenario has `scripts` (the content of scripts.yaml), initial `states`
and `steps`. Each step happens `at` seconds after t0 and is one of:

  call: <service>        call script.<service> from outside (blocking, like
    data: {...}          the UI or an automation); `return_response` asks
    return_response: b   for the response
  set: [entity, state]   a state change (`attributes` optional)
  event: {event_type, data}
  result: n              the n-th service call HALean made to HA (0-based)
    ok / error_kind / response   completes (as `service_result`)
  reload: {...}          script.reload with this new scripts.yaml
  (nothing else)         just let the clock run

Observations per step (what tests/differential/test_scripts.py compares
with real Home Assistant):
  * call_service  (domain, service, data merged with target)
  * fire_event    (event_type, data): `event:` actions and script_started
  * call_done     (call number, ok, response or error kind) of `call` steps
  * the script entities' states after the step (state and the attributes
    last_triggered, mode, current, max, icon, friendly_name, restored)

Run alone, every scenario is checked against its own expectations:
`expect_unsupported` (object ids rejected at load) and, per step,
`expect` (a subset of the step's observations).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bridge"))
from protocol import protocol_scripts  # noqa: E402

ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-script"
SCENARIOS = sorted((ROOT / "tests" / "script_scenarios").glob("*.yaml"))
T0 = 1_700_000_000_000  # 2023-11-14T22:13:20Z, as in run_scenarios.py
ATTRS = ("last_triggered", "mode", "current", "max", "icon", "friendly_name", "restored")
_ID_KEYS = ("entity_id", "device_id", "area_id", "floor_id", "label_id")


def norm_data(d: dict) -> dict:
    """HA's service schema turns `entity_id: x` into `[x]`; do the same."""
    return {k: ([v] if k in _ID_KEYS and isinstance(v, str) else v) for k, v in d.items()}


def state(eid: str, st: str, attrs: dict | None = None, changed: int = T0) -> dict:
    return {"entity_id": eid, "state": st, "attributes": attrs or {}, "last_changed": changed}


def lean_run(sc: dict) -> tuple[list[str], list[dict]]:
    """Run a scenario through halean-script. Returns the object ids rejected at
    load and one observation dict per input (index 0 is init)."""
    tz = sc.get("tz", 0)
    current = {s["entity_id"]: state(s["entity_id"], s["state"], s.get("attributes"))
               for s in sc.get("states", [])}
    proc = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    ha_calls: list[int] = []  # engine call ids of calls made to HA, in order
    entity_states: dict[str, tuple] = {}
    unsupported: list[str] = []
    calls = 0

    def send(msg: dict) -> dict:
        assert proc.stdin and proc.stdout
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        out = json.loads(proc.stdout.readline())
        assert out.get("type") == "batch", out
        obs: dict = {"call_service": [], "fire_event": [], "call_done": [], "logs": []}
        for c in out["cmds"]:
            t = c["type"]
            if t == "call_service":
                ha_calls.append(c["call_id"])
                obs["call_service"].append(
                    [c["domain"], c["service"], norm_data({**c["target"], **c["data"]})])
            elif t == "fire_event":
                obs["fire_event"].append([c["event_type"], c["data"]])
            elif t == "call_done":
                obs["call_done"].append(
                    [c["call_id"], True, c.get("response")] if c["ok"]
                    else [c["call_id"], False, c["error_kind"]])
            elif t == "set_state":
                entity_states[c["entity_id"]] = (
                    c["state"], {k: c["attributes"][k] for k in ATTRS if k in c["attributes"]})
            elif t == "unsupported":
                unsupported.append(c["id"])
            elif t == "log":
                obs["logs"].append([c["level"], c["message"]])
        obs["states"] = {k: list(v) for k, v in sorted(entity_states.items())}
        return obs

    observations = [send({"type": "init", "now": T0, "tz": tz,
                          "scripts": protocol_scripts(sc["scripts"]),
                          "states": list(current.values())})]
    for st in sc["steps"]:
        now = T0 + int(st["at"] * 1000)
        if "call" in st:
            msg = {"type": "call", "call_id": calls, "service": st["call"],
                   "data": st.get("data", {}), "return_response": st.get("return_response", False)}
            calls += 1
        elif "set" in st:
            eid, val = st["set"]
            old = current.get(eid)
            changed = now if old is None or old["state"] != val else old["last_changed"]
            new = state(eid, val, st.get("attributes", {}), changed)
            msg = {"type": "state_changed", "entity_id": eid, "old_state": old, "new_state": new}
            current[eid] = new
        elif "event" in st:
            msg = {"type": "event", "event_type": st["event"]["event_type"],
                   "data": st["event"].get("data", {})}
        elif "result" in st:
            msg = {"type": "service_result", "call_id": ha_calls[st["result"]],
                   "ok": st.get("ok", True)}
            for k in ("error_kind", "response"):
                if k in st:
                    msg[k] = st[k]
        elif "reload" in st:
            msg = {"type": "reload", "scripts": protocol_scripts(st["reload"])}
        else:
            msg = {"type": "tick"}
        msg.update(now=now, tz=tz)
        observations.append(send(msg))
    assert proc.stdin
    proc.stdin.close()
    proc.wait()
    return unsupported, observations


def subset(want, got) -> bool:
    if isinstance(want, dict):
        return isinstance(got, dict) and all(k in got and subset(v, got[k]) for k, v in want.items())
    if isinstance(want, list) and isinstance(got, list):
        return len(want) == len(got) and all(subset(w, g) for w, g in zip(want, got))
    return want == got


def check(path: Path) -> list[str]:
    sc = yaml.safe_load(path.read_text())
    unsupported, obs = lean_run(sc)
    fails = []
    if sorted(unsupported) != sorted(sc.get("expect_unsupported", [])):
        fails.append(f"  unsupported: want {sc.get('expect_unsupported', [])}, got {unsupported}")
    for i, (st, o) in enumerate(zip(sc["steps"], obs[1:])):
        if "expect" in st and not subset(st["expect"], o):
            fails.append(f"  step {i + 1} (at={st['at']})\n    want: {json.dumps(st['expect'])}\n"
                         f"    got:  {json.dumps({k: v for k, v in o.items() if k != 'logs'})}")
    return fails


def main() -> int:
    bad = 0
    for f in SCENARIOS:
        fails = check(f)
        print(f"{'PASS' if not fails else 'FAIL'}  {f.stem}")
        for msg in fails:
            print(msg)
        bad += bool(fails)
    print(f"\n{len(SCENARIOS) - bad}/{len(SCENARIOS)} script scenarios passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
