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
from pytest_homeassistant_custom_component.common import (
    async_fire_mqtt_message,
    async_fire_time_changed,
)

from homeassistant.const import MATCH_ALL
from homeassistant.core import Context, HomeAssistant, ServiceCall, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.setup import async_setup_component

# --- review harness copy: only the case directory and the engine path differ from the
# --- shipped tests/differential/test_differential.py (plus an optional result dump, see README.md)
import json  # noqa: E402
import os  # noqa: E402

_REPO = Path("/home/user/halean")
sys.path.insert(0, str(_REPO / "tests"))
import run_scenarios  # noqa: E402
from run_scenarios import LOCATION, T0, engine_outputs  # noqa: E402

# (b) engine path: HALEAN_BIN overrides the directory holding halean-automation
run_scenarios.ENGINE = Path(os.environ.get("HALEAN_BIN", str(_REPO / ".lake" / "build" / "bin"))) / "halean-automation"
# (a) case directories: AUT_CASES is a colon-separated list (default: ../cases)
_CASE_DIRS = [Path(d) for d in os.environ.get(
    "AUT_CASES", str(Path(__file__).resolve().parent.parent / "cases")).split(":") if d]
SCENARIOS = sorted(p for d in _CASE_DIRS for p in d.glob("*.yaml"))
# optional: AUT_DUMP=<dir> writes both results per case as JSON (does not change the verdict)
_DUMP = os.environ.get("AUT_DUMP")
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


def _inputs(path: Path) -> set[str]:
    """The inputs a scenario sends that need more of HA than the bus."""
    sc = yaml.safe_load(path.read_text())
    return {st["send"]["type"] for st in sc["steps"] if "send" in st} & {"mqtt", "webhook"}


PLAIN = [p for p in SCENARIOS if not _inputs(p)]
MQTT = [p for p in SCENARIOS if "mqtt" in _inputs(p)]
WEBHOOK = [p for p in SCENARIOS if "webhook" in _inputs(p)]


@pytest.mark.parametrize("path", PLAIN, ids=[p.stem for p in PLAIN])
async def test_scenario(hass: HomeAssistant, freezer: FrozenDateTimeFactory, path: Path) -> None:
    await _run(hass, freezer, path)


@pytest.mark.parametrize("path", MQTT, ids=[p.stem for p in MQTT])
async def test_scenario_mqtt(hass: HomeAssistant, freezer: FrozenDateTimeFactory,
                             mqtt_mock, path: Path) -> None:
    """MQTT messages go through HA's MQTT client (`async_fire_mqtt_message`)."""
    await _run(hass, freezer, path)


@pytest.mark.parametrize("path", WEBHOOK, ids=[p.stem for p in WEBHOOK])
async def test_scenario_webhook(hass: HomeAssistant, freezer: FrozenDateTimeFactory,
                                hass_client_no_auth, path: Path) -> None:
    """Webhook requests are HTTP requests to HA's `/api/webhook/<id>`."""
    assert await async_setup_component(hass, "webhook", {})
    await _run(hass, freezer, path, client=await hass_client_no_auth())


async def _send_webhook(hass: HomeAssistant, client, msg: dict) -> None:
    """The raw request; `local: false` makes HA see a non-local address."""
    from unittest.mock import patch

    from homeassistant.components import webhook

    url = f"/api/webhook/{msg['webhook_id']}"
    if msg.get("query"):
        url += f"?{msg['query']}"
    local = msg.get("local", True)
    with patch.object(webhook.network_util, "is_local", wraps=None,
                      side_effect=lambda ip: local):
        resp = await client.request(msg.get("method", "POST"), url,
                                    headers=msg.get("headers") or {},
                                    data=msg.get("body", "").encode("utf-8"))
        await resp.read()


async def _run(hass: HomeAssistant, freezer: FrozenDateTimeFactory, path: Path,
               client=None) -> None:
    sc = yaml.safe_load(path.read_text())
    if not sc.get("differential", True):
        pytest.skip(sc.get("differential_reason", "engine-only scenario"))

    await hass.config.async_set_time_zone("UTC")
    loc = sc.get("location", LOCATION)
    hass.config.latitude = loc["latitude"]
    hass.config.longitude = loc["longitude"]
    hass.config.elevation = loc["elevation"]
    freezer.move_to(T0_DT)

    services: set[tuple[str, str]] = set()
    events: set[str] = set()
    automations = copy.deepcopy(sc["automations"])
    for a in automations:
        _walk_actions(a.get("actions") or a.get("action"), services, events)

    observed: list[tuple] = []
    futures: list[asyncio.Future] = []
    ha_log: list[str] = []  # review: HA's warnings/errors, for the dump only
    if _DUMP:
        import logging

        class _H(logging.Handler):
            def emit(self, record):  # noqa: ANN001
                ha_log.append(f"{record.levelname} {record.name}: {record.getMessage()}"[:600])

        _h = _H(level=logging.WARNING)
        logging.getLogger().addHandler(_h)
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
            elif msg["type"] == "mqtt":
                async_fire_mqtt_message(hass, msg["topic"], msg.get("payload", ""),
                                        msg.get("qos", 0), msg.get("retain", False))
            elif msg["type"] == "webhook":
                await _send_webhook(hass, client, msg)
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

    if _DUMP:
        logging.getLogger().removeHandler(_h)
    raw_engine = engine_outputs(sc)
    engine = [_normalise_engine(c) for c in raw_engine]
    if _DUMP:
        Path(_DUMP).mkdir(parents=True, exist_ok=True)
        (Path(_DUMP) / f"{path.stem}.json").write_text(json.dumps({
            "ha": per_step, "engine": engine, "ha_log": ha_log,
            "engine_other": [[c for c in cs if c["type"] not in ("automation_triggered", "call_service", "fire_event")]
                             for cs in raw_engine]}, default=str, indent=1))
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

    manifest = yaml.safe_load((_REPO / "manifest.yaml").read_text())
    tag = manifest["upstream"].get("tag")
    assert tag == __version__, (
        f"harness runs Home Assistant {__version__} but manifest.yaml is pinned to {tag}; "
        "bump pytest-homeassistant-custom-component in tests/differential/run.py")
    import jinja2

    pinned = manifest["upstream"].get("jinja2")
    assert pinned == jinja2.__version__, (
        f"harness runs Jinja2 {jinja2.__version__} but manifest.yaml says {pinned}; "
        "re-check the template evaluator against the new Jinja2 and update the pin")
