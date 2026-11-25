"""Load-time comparison (not in the shipped harness, which asserts that HALean
rejects nothing): each entry of ../config/matrix.yaml is one `object_id:
config` pair, loaded alone into HA's `script` integration and into
halean-script.

HA side: the state of `script.<object_id>` after setup: absent (the object id
was refused), `unavailable` (the config failed validation) or `off` (valid).
HALean side: `unsupported` (rejected at load) or the `set_state` it wrote.

Verdict per entry:
  agree     both load it (same state and attributes), or neither does
  Accepts   HALean loads what HA refuses
  Refuses   HALean rejects what HA loads
  Silent    both load it, with different state or attributes
An entry may carry `expect: <verdict>` (what the review found); the test fails
when the verdict is anything else, and prints both sides.
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from homeassistant.core import HomeAssistant
from homeassistant.setup import async_setup_component

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_script_scenarios import ATTRS, ENGINE, T0  # noqa: E402
from protocol import protocol_scripts  # noqa: E402

MATRIX = yaml.safe_load((Path(__file__).resolve().parent.parent / "config" / "matrix.yaml").read_text())


def lean_load(key: str, cfg) -> tuple[str, object]:
    msg = {"type": "init", "now": T0, "tz": 0, "scripts": protocol_scripts({key: cfg}), "states": []}
    p = subprocess.run([str(ENGINE)], input=json.dumps(msg) + "\n", capture_output=True, text=True)
    out = json.loads(p.stdout.splitlines()[0])
    if out.get("type") != "batch":
        return "rejected", out
    for c in out["cmds"]:
        if c["type"] == "unsupported":
            return "rejected", c["reason"]
    for c in out["cmds"]:
        if c["type"] == "set_state":
            return "loaded", [c["entity_id"], c["state"], {k: c["attributes"][k] for k in ATTRS if k in c["attributes"]}]
    return "rejected", "no set_state"


@pytest.mark.parametrize("entry", MATRIX, ids=[e["name"] for e in MATRIX])
async def test_config(hass: HomeAssistant, entry: dict) -> None:
    key, cfg = entry["key"], entry["config"]
    await hass.config.async_set_time_zone("UTC")
    ok = await async_setup_component(hass, "script", {"script": {key: copy.deepcopy(cfg)}})
    await hass.async_block_till_done()
    states = hass.states.async_all("script") if ok else []
    if states and states[0].state != "unavailable":
        s = states[0]
        ha = ("loaded", [s.entity_id, s.state, {k: s.attributes[k] for k in ATTRS if k in s.attributes}])
    else:
        ha = ("rejected", "setup failed" if not ok else "unavailable entity" if states else "no entity")
    lean = lean_load(str(key), cfg)
    if ha[0] == lean[0] == "loaded":
        verdict = "agree" if ha[1] == lean[1] else "Silent"
    elif ha[0] == lean[0]:
        verdict = "agree"
    else:
        verdict = "Accepts" if lean[0] == "loaded" else "Refuses"
    print(f"MATRIX {entry['name']}: {verdict}\n    HA:     {ha}\n    HALean: {lean}")
    assert verdict == entry.get("expect", "agree"), f"{verdict}\n    HA:     {ha}\n    HALean: {lean}"
