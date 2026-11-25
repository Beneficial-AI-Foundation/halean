"""HA-only runner (review addition, not part of the shipped harness).

For operations HALean answers `unsupported`, the shipped harness skips HA. To
classify such a refusal we need HA's own answer. This file runs every case of
`cases/refused/*.yaml` on the real `hass` only, with the shipped `Runner`
(imported unchanged from the harness copy `test_core.py`), and also asks the
engine, and prints both per operation. It asserts nothing about equality.

Run: /opt/havenv/bin/python -m pytest harness/test_core_ha_only.py -p no:cacheprovider -q -s
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import subprocess
from datetime import timedelta
from pathlib import Path

import pytest
import yaml

from homeassistant import runner as ha_runner
from homeassistant.helpers.translation import async_load_integrations

from test_core import EPOCH, HA_ULID, NOW, Renamer, Runner, _Records

DIR = Path(__file__).resolve().parent.parent / "cases" / "refused"
CASES = [c for f in sorted(DIR.glob("*.yaml")) for c in yaml.safe_load(f.read_text()) or []]
ENGINE = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")) / "halean-core"


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_ha_only(hass, freezer, case) -> None:
    await async_load_integrations(hass, {"homeassistant"})
    await hass.async_block_till_done()
    proc = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def engine(msg: dict) -> dict:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    engine({"op": "init", "listeners": [[k, v] for k, v in hass.bus.async_listeners().items()], "now": 0})
    runner = Runner(hass)
    records = _Records(runner.trace)
    ha_logger = logging.getLogger("homeassistant")
    ha_logger.addHandler(records)
    loop = asyncio.get_running_loop()
    test_handler = loop.get_exception_handler()
    loop.set_exception_handler(ha_runner._async_loop_exception_handler)
    rename = Renamer(HA_ULID)
    now = case.get("now", NOW)
    print(f"\n=== {case['name']}")
    try:
        for i, op in enumerate(case["ops"]):
            now = op.get("now", now)
            show = op.pop("show", False)
            lean = engine({**op, "now": now})
            if not case.get("manual") and "unsupported" not in lean:
                settle = engine({"op": "block_till_done", "now": now})
                if "unsupported" in settle:
                    lean = settle
            freezer.move_to(EPOCH + timedelta(microseconds=now))
            runner.trace.clear()
            result = await runner.op(op)
            if not case.get("manual"):
                await hass.async_block_till_done()
            ha = rename({"result": result, "trace": list(runner.trace)})
            if show or "unsupported" in lean:
                print(f"op {i} {json.dumps(op)[:160]}")
                print(f"  HA:     {json.dumps(ha)[:1500]}")
                print(f"  HALean: {json.dumps(lean)[:600]}")
    finally:
        loop.set_exception_handler(test_handler)
        ha_logger.removeHandler(records)
        proc.stdin.close()
        proc.wait()
