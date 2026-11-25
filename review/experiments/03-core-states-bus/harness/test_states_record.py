"""Recording variant of the harness copy (not the verdict; see README).

For every operation of every case it runs HALean and HA (HA also when HALean answers
`unsupported`, which the shipped harness never does) and appends one JSON line per operation to
$RECORD_OUT: {"case", "i", "op", "ha", "lean", "verdict"}. `verdict` applies the shipped
assertion semantics: "pass", "diff" (both answered, results differ), "refused" (HALean answered
`unsupported` and the op is not marked `unsupported: true`), "not-refused" (marked, but HALean
answered). HA exceptions that are not HomeAssistantError are recorded as {"raised": class}; the
shipped harness would error on them.
"""
import json
import os
from datetime import datetime

import pytest
from freezegun.api import FrozenDateTimeFactory

from homeassistant.const import EVENT_STATE_CHANGED, EVENT_STATE_REPORTED
from homeassistant.core import Event, HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError

import test_states as T

engine = T.engine
OUT = os.environ.get("RECORD_OUT", "record-states.jsonl")
ONLY = set(filter(None, os.environ.get("RECORD_ONLY", "").split(",")))
CASES = [c for c in T.CASES if not ONLY or c["name"] in ONLY]


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_record(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine, case: dict) -> None:
    assert engine({"op": "reset"}) == {"result": None, "events": []}
    fired: list[dict] = []

    @callback
    def listener(event: Event) -> None:
        fired.append(T._event(event))

    hass.bus.async_listen(EVENT_STATE_CHANGED, listener)
    hass.bus.async_listen(EVENT_STATE_REPORTED, listener, callback(lambda data: True))
    renamer = T.Renamer(T._supplied_ids(case))
    now = datetime.fromisoformat(T.T0)
    bad = 0
    with open(OUT, "a") as out:
        for i, op in enumerate(case["ops"]):
            if "now" in op:
                now = datetime.fromisoformat(op["now"])
            now_us = T._us(now)
            msg = {k: v for k, v in op.items() if k not in ("unsupported", "expect")} | {"now": now_us}
            lean = engine(msg)
            freezer.move_to(now)
            fired.clear()
            try:
                ha = {"result": T._run_ha(hass, op, now_us), "events": list(fired)}
            except HomeAssistantError as err:
                ha = {"error": {"type": type(err).__name__, "message": str(err)}, "events": list(fired)}
            except Exception as err:  # noqa: BLE001
                ha = {"raised": type(err).__name__, "message": str(err)}
            try:
                ha = renamer.walk(json.loads(json.dumps(ha)), now_us)
            except AssertionError as err:
                ha = {"harness": str(err)}
            if "unsupported" in lean:
                verdict = "pass" if op.get("unsupported") else "refused"
            elif op.get("unsupported"):
                verdict = "not-refused"
            else:
                verdict = "pass" if T._typed(lean) == T._typed(ha) else "diff"
            bad += verdict != "pass"
            out.write(json.dumps({"case": case["name"], "i": i, "op": op, "ha": ha, "lean": lean,
                                  "verdict": verdict}, default=str) + "\n")
    assert bad == 0, f"{bad} operation(s) not 'pass'"
