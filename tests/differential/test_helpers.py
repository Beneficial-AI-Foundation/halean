"""Differential test for the helper integrations (`input_boolean`,
`input_number`, `input_select`, `input_text`, `counter`, `timer`): run every
case in tests/helpers/*.yaml on a real Home Assistant (the integrations set
up with `async_setup_component` from YAML config) and on `halean-helpers`,
and require after every step the same

  * config validation outcome (`str()` of `CONFIG_SCHEMA`'s `MultipleInvalid`,
    and `async_setup_component` failing), or the same entities set up,
  * service call outcome (exception class and `str()`, or none),
  * `state_changed` events of helper entities (entity id, state, `repr()` of
    the attributes) and `timer.*` events (type, `repr()` of the data), in
    order,
  * warnings logged by the helper integrations,
  * states of every helper entity (state, `repr()` of the attributes).

A step is one of
  `setup: {<domain>: <config>}` (optional `restore: [[entity_id, state,
  attributes], ...]`, the restore cache), `call: <domain>.<service>` with
  `data:`, and `advance: <seconds>` (move the frozen clock and fire the time
  changed event, which runs the timers' callbacks). A step marked
  `unsupported: true` must be rejected by HALean; HA does not run it (so it
  should be the last one).

A call that names several entities runs them in HA's `set` order, which is
random per process: for those, the observed events are compared as sorted
lists.

Run:  uv run tests/differential/run.py -k helpers
"""

from __future__ import annotations

import asyncio
import enum
import importlib
import json
import logging
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import probatio
import pytest
import yaml
from freezegun.api import FrozenDateTimeFactory
from pytest_homeassistant_custom_component.common import (
    async_fire_time_changed_exact,
    mock_restore_cache,
)

from homeassistant.const import EVENT_STATE_CHANGED, MATCH_ALL
from homeassistant.core import Event, HomeAssistant, State, callback
from homeassistant.setup import async_setup_component

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = [c for f in sorted((ROOT / "tests" / "helpers").glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-helpers"
DOMAINS = ("input_boolean", "input_number", "input_select", "input_text", "counter", "timer")
T0 = datetime(2026, 11, 20, 16, 30, 45, 123456, tzinfo=UTC)
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)


def _us(d: datetime) -> int:
    return (d - EPOCH) // timedelta(microseconds=1)


@pytest.fixture(scope="module")
def engine():
    proc = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def ask(msg: dict) -> dict:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    yield ask
    proc.stdin.close()
    proc.wait()


@pytest.fixture
def expected_lingering_timers() -> bool:
    """Timers still running when a case ends."""
    return True


def _plain(v):
    if isinstance(v, enum.Enum):
        return v.value
    if isinstance(v, dict):
        return {_plain(k): _plain(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_plain(x) for x in v]
    return v


def _attrs(attrs) -> str:
    return repr({str(k): _plain(v) for k, v in attrs.items()})


def _is_helper(entity_id: str) -> bool:
    return entity_id.split(".", 1)[0] in DOMAINS


def _states(hass: HomeAssistant) -> list:
    return sorted([s.entity_id, s.state, _attrs(s.attributes)]
                  for s in hass.states.async_all(list(DOMAINS)))


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_helpers(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine, caplog,
                       case: dict) -> None:
    await hass.config.async_set_time_zone("UTC")
    now = T0
    freezer.move_to(now)
    assert "unsupported" not in engine({"op": "reset"})
    outs: list = []

    @callback
    def listener(event: Event) -> None:
        if event.event_type == EVENT_STATE_CHANGED:
            new = event.data["new_state"]
            if new is not None and _is_helper(new.entity_id):
                outs.append(["state_changed", new.entity_id, new.state, _attrs(new.attributes)])
        elif event.event_type.startswith("timer."):
            outs.append(["event", event.event_type, repr(_plain(dict(event.data)))])

    hass.bus.async_listen(MATCH_ALL, listener)
    caplog.set_level(logging.WARNING)

    def warnings() -> list:
        return [["warning", r.getMessage()] for r in caplog.records
                if r.levelno == logging.WARNING
                and r.name in {f"homeassistant.components.{d}" for d in DOMAINS}]

    for i, step in enumerate(case["steps"]):
        where = f"step {i}: {step}"
        outs.clear()
        caplog.clear()
        sort_outs = False
        if "setup" in step:
            ((domain, cfg),) = step["setup"].items()
            msg = {"op": "setup", "domain": domain, "config": cfg, "now": _us(now),
                   "restore": step.get("restore", [])}
        elif "call" in step:
            domain, service = step["call"].split(".", 1)
            data = step.get("data", {})
            msg = {"op": "call", "domain": domain, "service": service, "data": data, "now": _us(now)}
            eids = data.get("entity_id")
            sort_outs = isinstance(eids, list) and len(eids) > 1 or eids == "all"
        elif "advance" in step:
            now = now + timedelta(seconds=step["advance"])
            msg = {"op": "tick", "now": _us(now)}
        else:
            raise ValueError(f"unknown step {step}")

        lean = engine(msg)
        if step.get("unsupported"):
            assert "unsupported" in lean, f"{where}\nHALean should reject this, got {lean}"
            break
        assert "unsupported" not in lean, f"{where}\nHALean rejected it: {lean['unsupported']}"

        ha: dict = {}
        if "setup" in step:
            if step.get("restore"):
                mock_restore_cache(hass, [State(e, s, a) for e, s, a in step["restore"]])
            module = importlib.import_module(f"homeassistant.components.{domain}")
            try:
                module.CONFIG_SCHEMA({domain: cfg})
                ha["ok"] = True
            except probatio.Invalid as err:
                ha["ok"] = False
                ha["error"] = str(err)
            caplog.clear()  # what that validation logged is logged again by the setup
            ok = await async_setup_component(hass, domain, {domain: cfg})
            await hass.async_block_till_done()
            assert ok == ha["ok"], f"{where}\nasync_setup_component returned {ok}"
        elif "call" in step:
            try:
                await hass.services.async_call(domain, service, data, blocking=True)
                ha["error"] = None
            except Exception as err:  # noqa: BLE001
                ha["error"] = {"type": type(err).__name__, "message": str(err)}
            # a timer that ends now (zero duration) has its callback in the
            # loop's ready queue: let the loop run it, as it would at once
            for _ in range(5):
                await asyncio.sleep(0)
            await hass.async_block_till_done()
        else:
            freezer.move_to(now)
            async_fire_time_changed_exact(hass, now)
            await hass.async_block_till_done()

        ha["outs"] = list(outs)
        ha["logs"] = warnings()
        ha["states"] = _states(hass)
        lean["states"] = sorted(lean["states"])
        lean["logs"] = [l for l in lean["logs"] if l[0] == "warning"]
        if sort_outs:
            ha["outs"] = sorted(ha["outs"])
            lean["outs"] = sorted(lean["outs"])
        if "expect_error" in step:  # documents the upstream behaviour the step is about
            assert ha.get("error") == step["expect_error"], f"{where}\nHA: {ha.get('error')}"
        assert lean == ha, f"{where}\nHA:     {ha}\nHALean: {lean}"
