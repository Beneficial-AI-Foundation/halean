"""Differential test for the state machine: apply every operation sequence in
tests/core/states/*.yaml to Home Assistant's own `hass.states` and to
`halean-core-states`, and require the same results and the same fired events
(`state_changed` / `state_reported`: event type, data, context, time fired,
origin), in order, compared with their Python types (`1` is not `1.0`).

States are compared as `State._as_dict` computed afresh (see
`test_as_dict_cache_is_stale_after_report` for why not the cached `as_dict()`).
Context ids that a case does not supply are random ULIDs upstream; both sides
name them `ulid:<n>` in the order they first appear, and the test checks that
each HA ULID encodes the operation's clock.

An operation marked `unsupported: true` must be rejected by HALean; HA does
not run it.

Run:  uv run tests/differential/run.py -k states
"""

from __future__ import annotations

import json
import os
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
import yaml
from freezegun.api import FrozenDateTimeFactory

from homeassistant.const import EVENT_STATE_CHANGED, EVENT_STATE_REPORTED
from homeassistant.core import Context, Event, HomeAssistant, State, callback
from homeassistant.exceptions import HomeAssistantError

ROOT = Path(__file__).resolve().parent.parent.parent
CASE_DIR = Path(os.environ.get("HALEAN_CASES", Path(__file__).resolve().parent.parent / "cases" / "states"))
CASES = [c for f in sorted(CASE_DIR.glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")) / "halean-core-states"
T0 = "2026-11-20T16:30:45.123456+00:00"
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def _us(d: datetime) -> int:
    return (d - EPOCH) // timedelta(microseconds=1)


def _ulid_ms(ulid: str) -> int:
    n = 0
    for ch in ulid[:10]:
        n = n * 32 + CROCKFORD.index(ch)
    return n


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


def _state_dict(s: State) -> dict:
    """`State._as_dict`, computed afresh (bypassing the property's cache)."""
    return json.loads(json.dumps(State._as_dict.wrapped(s)))


def _event(e: Event) -> dict:
    data = dict(e.data)
    for k in ("old_state", "new_state"):
        if k in data:
            data[k] = None if data[k] is None else _state_dict(data[k])
    for k in ("last_reported", "old_last_reported"):
        if k in data:
            data[k] = data[k].isoformat()
    return {"event_type": e.event_type, "data": data, "context": e.context._as_dict,
            "time_fired": e.time_fired.isoformat(), "origin": e.origin.value}


def _typed(x):
    """Compare with Python types: bool, int and float are told apart."""
    if isinstance(x, dict):
        return {k: _typed(v) for k, v in x.items()}
    if isinstance(x, list):
        return [_typed(v) for v in x]
    if isinstance(x, (bool, int, float)):
        return (type(x).__name__, x)
    return x


class Renamer:
    """Name HA's random context ids `ulid:<n>` in order of first appearance."""

    def __init__(self, supplied: set[str]) -> None:
        self.supplied = supplied
        self.names: dict[str, str] = {}

    def name(self, cid: str, now_us: int) -> str:
        if cid in self.supplied:
            return cid
        if cid not in self.names:
            # ulid_at_time(timestamp): the first 48 bits are the time in ms
            assert abs(_ulid_ms(cid) - now_us // 1000) <= 1, f"ULID {cid} is not from the op's clock"
            self.names[cid] = f"ulid:{len(self.names)}"
        return self.names[cid]

    def walk(self, x, now_us: int):
        if isinstance(x, dict):
            if set(x) == {"id", "parent_id", "user_id"}:
                return {**x, "id": self.name(x["id"], now_us)}
            out = {k: self.walk(v, now_us) for k, v in x.items()}
            if set(x) >= {"s", "a", "c", "lc"} and isinstance(x["c"], str):  # compressed state
                out["c"] = self.name(x["c"], now_us)
            return out
        if isinstance(x, list):
            return [self.walk(v, now_us) for v in x]
        return x


def _ctx(c: dict | None) -> Context | None:
    if not c:
        return None
    return Context(id=c["id"], user_id=c.get("user_id"), parent_id=c.get("parent_id"))



def _run_ha(hass: HomeAssistant, op: dict, now_us: int):
    """Apply one operation to HA's state machine; return its result."""
    sm = hass.states
    kind = op["op"]
    ts = now_us / 1e6
    if kind == "set":
        return sm.async_set(op["entity_id"], op["state"], op.get("attributes"),
                            op.get("force_update", False), _ctx(op.get("context")), timestamp=ts)
    if kind == "set_internal":
        return sm.async_set_internal(op["entity_id"], op["state"], op.get("attributes"),
                                     op.get("force_update", False), _ctx(op.get("context")), None, ts)
    if kind == "remove":
        return sm.async_remove(op["entity_id"], _ctx(op.get("context")))
    if kind == "get":
        s = sm.get(op["entity_id"])
        return None if s is None else _state_dict(s)
    if kind == "inspect":
        s = sm.get(op["entity_id"])
        if s is None:
            return None
        return {"name": s.name, "domain": s.domain, "object_id": s.object_id,
                "last_changed_timestamp": s.last_changed_timestamp,
                "last_updated_timestamp": s.last_updated_timestamp,
                "last_reported_timestamp": s.last_reported_timestamp,
                "compressed": json.loads(json.dumps(s.as_compressed_state))}
    if kind == "is_state":
        return sm.is_state(op["entity_id"], op["state"])
    if kind == "entity_ids":
        return sm.async_entity_ids(op.get("domain_filter"))
    if kind == "entity_ids_count":
        return sm.async_entity_ids_count(op.get("domain_filter"))
    if kind == "all":
        return [_state_dict(s) for s in sm.async_all(op.get("domain_filter"))]
    if kind == "reserve":
        return sm.async_reserve(op["entity_id"])
    if kind == "available":
        return sm.async_available(op["entity_id"])
    raise ValueError(f"unknown op {kind}")


def _supplied_ids(case: dict) -> set[str]:
    return {op["context"]["id"] for op in case["ops"] if op.get("context")}


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_states(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine, case: dict) -> None:
    assert hass.states.async_entity_ids() == []
    assert engine({"op": "reset"}) == {"result": None, "events": []}
    fired: list[dict] = []

    @callback
    def listener(event: Event) -> None:
        fired.append(_event(event))  # snapshot now: a reported state is mutated later

    hass.bus.async_listen(EVENT_STATE_CHANGED, listener)
    # state_reported listeners must have a filter (EventBus.async_listen)
    hass.bus.async_listen(EVENT_STATE_REPORTED, listener, callback(lambda data: True))
    renamer = Renamer(_supplied_ids(case))
    now = datetime.fromisoformat(T0)

    for i, op in enumerate(case["ops"]):
        if "now" in op:
            now = datetime.fromisoformat(op["now"])
        now_us = _us(now)
        msg = {k: v for k, v in op.items() if k not in ("unsupported", "expect")} | {"now": now_us}
        lean = engine(msg)
        where = f"op {i}: {op}"
        if op.get("unsupported"):
            assert "unsupported" in lean, f"{where}\nHALean should reject this, got {lean}"
            continue
        assert "unsupported" not in lean, f"{where}\nHALean rejected it: {lean['unsupported']}"

        freezer.move_to(now)
        fired.clear()
        try:
            ha = {"result": _run_ha(hass, op, now_us), "events": list(fired)}
        except HomeAssistantError as err:
            ha = {"error": {"type": type(err).__name__, "message": str(err)}, "events": list(fired)}
        ha = renamer.walk(json.loads(json.dumps(ha)), now_us)
        if "expect" in op:  # documents the upstream behaviour the case is about
            assert _typed(ha.get("result", ha.get("error"))) == _typed(op["expect"]), f"{where}\nHA: {ha}"
        assert _typed(lean) == _typed(ha), f"{where}\nHA:     {ha}\nHALean: {lean}"


async def test_as_dict_cache_is_stale_after_report(hass: HomeAssistant) -> None:
    """Upstream quirk the model does not reproduce: `as_dict()` is cached, and
    a report (same state and attributes) mutates `last_reported` without
    clearing that cache. HALean's `State.asDict` is always the fresh value."""
    hass.states.async_set("light.a", "on", {}, timestamp=1763656245.0)
    s = hass.states.get("light.a")
    before = s.as_dict()["last_reported"]
    hass.states.async_set("light.a", "on", {}, timestamp=1763656246.0)
    assert s.last_reported.isoformat() == "2025-11-20T16:30:46+00:00"
    assert s.as_dict()["last_reported"] == before == "2025-11-20T16:30:45+00:00"
    assert State._as_dict.wrapped(s)["last_reported"] == "2025-11-20T16:30:46+00:00"
