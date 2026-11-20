"""Differential test: replay every scenario through a real Home Assistant and
through the Lean engine, and require identical observable behaviour.

Observable behaviour per input step, in order:
  * automation_triggered  (by automation id)
  * call_service          (domain, service, merged target+data)
  * fire_event            (event_type, data) for events fired by `event:` actions

HA runs in-process (pytest-homeassistant-custom-component) with a frozen clock
that is advanced one second at a time, like the bridge's ticks. Service handlers
block on a future until the scenario sends `service_result`, which reproduces
the engine's blocking-call protocol exactly.

Run:  uv run tests/differential/run.py
"""

from __future__ import annotations

import asyncio
import copy
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
import voluptuous as vol
import yaml
from freezegun.api import FrozenDateTimeFactory
from pytest_homeassistant_custom_component.common import async_fire_time_changed

from homeassistant.const import MATCH_ALL
from homeassistant.core import Context, HomeAssistant, ServiceCall, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.setup import async_setup_component

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from run_scenarios import T0, engine_outputs  # noqa: E402

SCENARIOS = sorted((Path(__file__).resolve().parent.parent / "scenarios").glob("*.yaml"))
T0_DT = datetime.fromtimestamp(T0 / 1000, UTC)


def _walk_actions(actions, services: set, events: set) -> None:
    for a in actions or []:
        if not isinstance(a, dict):
            continue
        svc = a.get("action") or a.get("service")
        if isinstance(svc, str) and "." in svc:
            services.add(tuple(svc.split(".", 1)))
        if "event" in a and isinstance(a["event"], str):
            events.add(a["event"])
        for key in ("then", "else", "sequence", "default"):
            if isinstance(a.get(key), list):
                _walk_actions(a[key], services, events)
        # parallel branches: single actions or `sequence:` mappings
        par = a.get("parallel")
        if par is not None:
            _walk_actions(par if isinstance(par, list) else [par], services, events)
        for opt in a.get("choose", []) or []:
            _walk_actions(opt.get("sequence"), services, events)
        if isinstance(a.get("repeat"), dict):
            _walk_actions(a["repeat"].get("sequence"), services, events)


_ID_KEYS = ("entity_id", "device_id", "area_id", "floor_id", "label_id")


def _norm_data(d: dict) -> dict:
    """HA's service schema turns `entity_id: x` into `[x]`; do the same."""
    return {k: ([v] if k in _ID_KEYS and isinstance(v, str) else v) for k, v in d.items()}


def _streams(items: list[tuple]) -> dict[str, list]:
    """Split one step's observations into three ordered streams.

    HA queues an event fired while another event is being dispatched
    (core.py `async_fire_internal`), so bus events can be delivered after
    service calls that ran later. Order is therefore compared within each
    stream, not across them."""
    out: dict[str, list] = {"automation_triggered": [], "call_service": [], "fire_event": []}
    for kind, *rest in items:
        out[kind].append(tuple(rest))
    return out


def _normalise_engine(cmds: list[dict]) -> list[tuple]:
    out = []
    for c in cmds:
        if c["type"] == "automation_triggered":
            out.append(("automation_triggered", c["name"]))
        elif c["type"] == "call_service":
            out.append(("call_service", c["domain"], c["service"],
                        _norm_data({**c["target"], **c["data"]})))
        elif c["type"] == "fire_event":
            out.append(("fire_event", c["event_type"], c["data"]))
    return out


async def _settle() -> None:
    """Let eager tasks and callbacks run. Runs blocked on a service future
    never finish, so `async_block_till_done` cannot be used here."""
    for _ in range(50):
        await asyncio.sleep(0)


@pytest.fixture
def expected_lingering_timers() -> bool:
    """Trigger timers (time_pattern, for:) are still scheduled when a scenario ends."""
    return True


@pytest.mark.parametrize("path", SCENARIOS, ids=[p.stem for p in SCENARIOS])
async def test_scenario(hass: HomeAssistant, freezer: FrozenDateTimeFactory, path: Path) -> None:
    sc = yaml.safe_load(path.read_text())
    if not sc.get("differential", True):
        pytest.skip(sc.get("differential_reason", "engine-only scenario"))

    await hass.config.async_set_time_zone("UTC")
    freezer.move_to(T0_DT)

    services: set[tuple[str, str]] = set()
    events: set[str] = set()
    automations = copy.deepcopy(sc["automations"])
    for a in automations:
        _walk_actions(a.get("actions") or a.get("action"), services, events)

    observed: list[tuple] = []
    futures: list[asyncio.Future] = []
    input_ctx = Context()

    async def handler(call: ServiceCall) -> None:
        observed.append(("call_service", call.domain, call.service, _norm_data(dict(call.data))))
        fut = hass.loop.create_future()
        futures.append(fut)
        return await fut  # the scenario's response; raises if it reports a failure

    # services answer with response data when asked (SupportsResponse.OPTIONAL)
    for domain, service in services:
        hass.services.async_register(domain, service, handler,
                                     supports_response=SupportsResponse.OPTIONAL)

    @callback
    def on_event(event) -> None:
        if event.event_type == "automation_triggered":
            observed.append(("automation_triggered", event.data.get("name")))
        elif event.event_type in events and event.context is not input_ctx:
            observed.append(("fire_event", event.event_type, dict(event.data)))

    hass.bus.async_listen(MATCH_ALL, on_event)

    for s in sc.get("states", []):
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
    await _settle()

    assert await async_setup_component(hass, "automation", {"automation": automations})
    await _settle()

    per_step: list[list[tuple]] = [list(observed)]
    observed.clear()
    current = T0_DT
    for st in sc["steps"]:
        target = T0_DT + timedelta(seconds=st["at"])
        # advance one second at a time, like the bridge's ticks
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

        if "set" in st:
            eid, val = st["set"]
            hass.states.async_set(eid, val, st.get("attributes", {}), context=input_ctx)
        else:
            msg = st["send"]
            if msg["type"] == "event":
                hass.bus.async_fire(msg["event_type"], msg.get("data", {}), context=input_ctx)
            elif msg["type"] == "service_result":
                fut = futures[msg["call_id"]]
                if fut.done():
                    pass  # the run was stopped (restart) and its call cancelled
                elif msg.get("ok"):
                    fut.set_result(msg.get("response"))
                else:
                    kind = msg.get("error_kind", "other")
                    fut.set_exception(
                        HomeAssistantError("failed") if kind == "ha_error"
                        else vol.Invalid("invalid") if kind == "invalid"
                        else RuntimeError("other"))
        await _settle()
        per_step.append(list(observed))
        observed.clear()

    # release anything still blocked so HA can shut down cleanly
    for fut in futures:
        if not fut.done():
            fut.set_result(None)
    await _settle()

    engine = [_normalise_engine(c) for c in engine_outputs(sc)]
    labels = ["init"] + [f"step at={s['at']}" for s in sc["steps"]]
    diffs = [
        f"{label}\n    HA:     {ha}\n    engine: {en}"
        for label, ha, en in zip(labels, per_step, engine)
        if _streams(ha) != _streams(en)
    ]
    assert not diffs, "HA and the Lean engine disagree:\n  " + "\n  ".join(diffs)


def test_harness_matches_pin() -> None:
    """The harness must run the same release the translation is pinned to."""
    from homeassistant.const import __version__

    manifest = yaml.safe_load((Path(__file__).resolve().parents[2] / "manifest.yaml").read_text())
    tag = manifest["upstream"].get("tag")
    assert tag == __version__, (
        f"harness runs Home Assistant {__version__} but manifest.yaml is pinned to {tag}; "
        "bump pytest-homeassistant-custom-component in tests/differential/run.py")
    import jinja2

    pinned = manifest["upstream"].get("jinja2")
    assert pinned == jinja2.__version__, (
        f"harness runs Jinja2 {jinja2.__version__} but manifest.yaml says {pinned}; "
        "re-check the template evaluator against the new Jinja2 and update the pin")
