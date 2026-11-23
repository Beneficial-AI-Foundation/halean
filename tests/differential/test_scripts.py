"""Differential test for scripts: replay every scenario in
tests/script_scenarios/ through a real Home Assistant (the `script`
integration, in-process) and through halean-script, and require identical
observable behaviour after every step:

  * service calls to HA (domain, service, data merged with target), in order,
  * events fired (`event:` actions and `script_started`), in order,
  * the outcome of each outside call of a script service (`call` steps:
    the response, or the kind of exception raised),
  * the state of every script entity (state, and the attributes
    last_triggered, mode, current, max, icon, friendly_name, restored).

Outside calls are made like the UI or an automation makes them:
`hass.services.async_call("script", ..., blocking=True)`, as a task, so the
scenario goes on while the script runs. The clock is frozen and advanced one
second at a time, like the bridge's ticks; service handlers block until the
scenario reports their result (`result:` steps).

Run:  uv run tests/differential/run.py -k scripts
"""

from __future__ import annotations

import asyncio
import copy
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
import voluptuous as vol
import yaml
from freezegun.api import FrozenDateTimeFactory
from pytest_homeassistant_custom_component.common import async_fire_time_changed

from homeassistant.const import MATCH_ALL
from homeassistant.core import Context, HomeAssistant, ServiceCall, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.script import CONFIGURATION_ERRORS
from homeassistant.setup import async_setup_component

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from run_script_scenarios import ATTRS, SCENARIOS, T0, lean_run, norm_data  # noqa: E402

T0_DT = datetime.fromtimestamp(T0 / 1000, UTC)


def _walk(actions, services: set, events: set) -> None:
    """Collect the services (other than script.*) and event types a sequence uses."""
    if isinstance(actions, dict):
        actions = [actions]
    for a in actions or []:
        if not isinstance(a, dict):
            continue
        svc = a.get("action") or a.get("service")
        if isinstance(svc, str) and "." in svc and not svc.startswith("script."):
            services.add(tuple(svc.split(".", 1)))
        if isinstance(a.get("event"), str):
            events.add(a["event"])
        for key in ("then", "else", "sequence", "default", "parallel"):
            if isinstance(a.get(key), (list, dict)):
                _walk(a[key], services, events)
        for opt in a.get("choose", []) or []:
            _walk(opt.get("sequence"), services, events)
        if isinstance(a.get("repeat"), dict):
            _walk(a["repeat"].get("sequence"), services, events)


def _error_kind(exc: BaseException) -> str:
    if isinstance(exc, asyncio.CancelledError):
        return "cancelled"
    if isinstance(exc, CONFIGURATION_ERRORS):
        return "invalid"
    if isinstance(exc, HomeAssistantError):
        return "ha_error"
    return "other"


def _attr(v):
    return v.isoformat() if isinstance(v, datetime) else v


async def _settle() -> None:
    """Let eager tasks and callbacks run (blocked runs never finish, so
    `async_block_till_done` cannot be used)."""
    for _ in range(50):
        await asyncio.sleep(0)


@pytest.fixture
def expected_lingering_timers() -> bool:
    return True


@pytest.fixture
def expected_lingering_tasks() -> bool:
    """Calls of scripts that are still running when a scenario ends."""
    return True


@pytest.mark.parametrize("path", SCENARIOS, ids=[p.stem for p in SCENARIOS])
async def test_script_scenario(hass: HomeAssistant, freezer: FrozenDateTimeFactory, path: Path) -> None:
    sc = yaml.safe_load(path.read_text())
    if not sc.get("differential", True):
        pytest.skip(sc.get("differential_reason", "engine-only scenario"))

    await hass.config.async_set_time_zone("UTC")
    freezer.move_to(T0_DT)

    services: set[tuple[str, str]] = set()
    events: set[str] = {"script_started"}
    configs = [sc["scripts"]] + [st["reload"] for st in sc["steps"] if "reload" in st]
    for scripts in configs:
        for cfg in (scripts or {}).values():
            _walk(cfg.get("sequence"), services, events)

    observed: dict[str, list] = {"call_service": [], "fire_event": [], "call_done": []}
    futures: list[asyncio.Future] = []
    input_ctx = Context()

    async def handler(call: ServiceCall):
        observed["call_service"].append([call.domain, call.service, norm_data(dict(call.data))])
        fut = hass.loop.create_future()
        futures.append(fut)
        return await fut

    for domain, service in services:
        hass.services.async_register(domain, service, handler,
                                     supports_response=SupportsResponse.OPTIONAL)

    @callback
    def on_event(event) -> None:
        if event.event_type in events and event.context is not input_ctx:
            observed["fire_event"].append([event.event_type, dict(event.data)])

    hass.bus.async_listen(MATCH_ALL, on_event)

    for s in sc.get("states", []):
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
    await _settle()

    assert await async_setup_component(hass, "script", {"script": copy.deepcopy(sc["scripts"])})
    await _settle()

    def snapshot() -> dict:
        obs = {k: list(v) for k, v in observed.items()}
        for v in observed.values():
            v.clear()
        obs["states"] = {
            s.entity_id: [s.state, {k: _attr(s.attributes[k]) for k in ATTRS if k in s.attributes}]
            for s in sorted(hass.states.async_all("script"), key=lambda s: s.entity_id)}
        return obs

    per_step = [snapshot()]
    tasks: list[asyncio.Task] = []
    current = T0_DT
    for st in sc["steps"]:
        target = T0_DT + timedelta(seconds=st["at"])
        while current + timedelta(seconds=1) <= target:
            current += timedelta(seconds=1)
            freezer.move_to(current)
            async_fire_time_changed(hass, current)
            await _settle()
        if current != target:
            current = target
            freezer.move_to(current)
            async_fire_time_changed(hass, current)
            await _settle()

        if "call" in st:
            idx = len(tasks)
            rr = st.get("return_response", False)
            task = hass.async_create_task(hass.services.async_call(
                "script", st["call"], copy.deepcopy(st.get("data", {})), blocking=True,
                return_response=rr))

            def done(t: asyncio.Task, idx: int = idx) -> None:
                if t.cancelled():
                    observed["call_done"].append([idx, False, "cancelled"])
                elif (exc := t.exception()) is not None:
                    observed["call_done"].append([idx, False, _error_kind(exc)])
                else:
                    observed["call_done"].append([idx, True, t.result()])

            task.add_done_callback(done)
            tasks.append(task)
        elif "set" in st:
            eid, val = st["set"]
            hass.states.async_set(eid, val, st.get("attributes", {}), context=input_ctx)
        elif "event" in st:
            hass.bus.async_fire(st["event"]["event_type"], st["event"].get("data", {}),
                                context=input_ctx)
        elif "result" in st:
            fut = futures[st["result"]]
            if not fut.done():
                if st.get("ok", True):
                    fut.set_result(st.get("response"))
                else:
                    kind = st.get("error_kind", "other")
                    fut.set_exception(
                        HomeAssistantError("failed") if kind == "ha_error"
                        else vol.Invalid("invalid") if kind == "invalid"
                        else RuntimeError("other"))
        elif "reload" in st:
            with patch("homeassistant.config.async_hass_config_yaml",
                       AsyncMock(return_value={"script": copy.deepcopy(st["reload"])})):
                await hass.services.async_call("script", "reload", blocking=True)
        await _settle()
        per_step.append(snapshot())

    # release anything still blocked so HA can shut down cleanly
    for fut in futures:
        if not fut.done():
            fut.set_result(None)
    await _settle()
    for t in tasks:
        if not t.done():
            t.cancel()
    await _settle()

    unsupported, lean = lean_run(sc)
    assert not unsupported, f"HALean rejected {unsupported}; mark the scenario differential: false"
    labels = ["init"] + [f"step at={s['at']}" for s in sc["steps"]]
    diffs = []
    for label, ha, en in zip(labels, per_step, lean):
        en = {k: v for k, v in en.items() if k != "logs"}
        # outside calls that end in the same step are separate tasks: the
        # order they finish in is asyncio scheduling, which is not modelled
        for obs in (ha, en):
            obs["call_done"] = sorted(obs["call_done"], key=lambda c: c[0])
        if ha != en:
            diffs.append(f"{label}\n    HA:     {ha}\n    HALean: {en}")
    assert not diffs, "HA and HALean disagree:\n  " + "\n  ".join(diffs)
