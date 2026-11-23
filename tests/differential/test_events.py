"""Differential test for the event bus: run every case in tests/core/events/*.yaml
on Home Assistant's own `hass.bus` and on `halean-core-events`, and require the
same result, deliveries and logged errors for every operation.

A case is a list of operations (`listen`, `listen_once`, `unsub`, `fire`,
`listeners`), each optionally with a clock reading `now` (µs since the epoch;
it carries over to later operations). Listeners are scripted: each records
every event it receives (`Event.as_dict()`) and runs its `react` list on
receipt (fire an event, listen, unsubscribe, raise), up to `react_times`
receipts. Every listener and filter is a `@callback`, so HA runs them inside
the dispatch; `hass.async_block_till_done()` after each operation is the step
boundary.

Contexts that HA creates itself have random ULIDs. They are compared
structurally: the millisecond timestamp in the ULID, and which events share
one (`ulid@<ms>#<n>`, numbered in order of appearance).

Run:  uv run tests/differential/run.py -k events
"""

from __future__ import annotations

import json
import logging
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
import yaml
from freezegun.api import FrozenDateTimeFactory

from homeassistant.core import Context, EventOrigin, HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = [c for f in sorted((ROOT / "tests" / "core" / "events").glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-core-events"
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
# 2026-11-26 16:30:45.123456 UTC
NOW = 1795710645123456
CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
EXCEPTIONS = {"HomeAssistantError": HomeAssistantError, "ValueError": ValueError,
              "RuntimeError": RuntimeError, "TypeError": TypeError, "KeyError": KeyError}


def _ts(us: int) -> float:
    """`time.time()` at a clock reading of `us` µs (as freezegun computes it)."""
    return us // 1_000_000 + (us % 1_000_000) / 1_000_000.0


def _ulid_ms(ulid: str) -> int:
    n = 0
    for ch in ulid[:10]:
        n = n * 32 + CROCKFORD.index(ch)
    return n


@pytest.fixture
def engine():
    proc = subprocess.Popen([str(ENGINE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def ask(msg: dict) -> dict:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    yield ask
    proc.stdin.close()
    proc.wait()


class Runner:
    """Drives the real `hass.bus` with the case's scripted listeners."""

    def __init__(self, hass: HomeAssistant, known_ids: set[str]) -> None:
        self.hass = hass
        self.deliveries: list[dict] = []
        self.handles: dict[str, object] = {}
        self.known_ids = known_ids
        self.generated: dict[str, str] = {}

    def _ctx_id(self, cid: str) -> str:
        if cid in self.known_ids:
            return cid
        if cid not in self.generated:
            self.generated[cid] = f"ulid@{_ulid_ms(cid)}#{len(self.generated)}"
        return self.generated[cid]

    def _record(self, lid: str, event) -> None:
        d = event.as_dict()
        ctx = dict(d["context"])
        ctx["id"] = self._ctx_id(ctx["id"])
        self.deliveries.append({"listener": lid, "event": {
            "event_type": d["event_type"], "data": dict(d["data"]), "origin": d["origin"],
            "time_fired": d["time_fired"], "context": ctx}})

    @staticmethod
    def _context(c) -> Context | None:
        if c is None:
            return None
        return Context(id=c["id"], user_id=c.get("user_id"), parent_id=c.get("parent_id"))

    def fire(self, f: dict, event=None) -> None:
        ctx = event.context if f.get("context") == "inherit" else self._context(f.get("context"))
        tf = f.get("time_fired")
        self.hass.bus.async_fire(
            f["event_type"], f.get("data"),
            EventOrigin.remote if f.get("origin") == "remote" else EventOrigin.local,
            ctx, None if tf is None else _ts(tf))

    def _filter(self, spec: dict):
        f = spec["filter"]

        def flt(data) -> bool:
            if isinstance(f, bool):
                return f
            if "eq" in f:
                return all(k in data and data[k] == v for k, v in f["eq"].items())
            if "has" in f:
                return f["has"] in data
            raise ValueError("filter")

        return callback(flt) if spec.get("filter_callback", True) else flt

    def listen(self, spec: dict, once: bool) -> None:
        lid, react, times = spec["id"], spec.get("react") or [], spec.get("react_times")
        count = 0

        @callback
        def listener(event) -> None:
            nonlocal count
            count += 1
            self._record(lid, event)
            if times is None or count <= times:
                for r in react:
                    self.react(r, event)

        kwargs = {}
        if "run_immediately" in spec:
            kwargs["run_immediately"] = spec["run_immediately"]
        if spec.get("filter") is not None:
            kwargs["event_filter"] = self._filter(spec)
        bus = self.hass.bus
        remove = (bus.async_listen_once if once else bus.async_listen)(
            spec["event_type"], listener, **kwargs)
        self.handles[lid] = remove

    def react(self, r: dict, event) -> None:
        if "fire" in r:
            self.fire(r["fire"], event)
        elif "listen" in r:
            self.listen(r["listen"], False)
        elif "listen_once" in r:
            self.listen(r["listen_once"], True)
        elif "unsub" in r:
            self.handles[r["unsub"]]()
        elif "raise" in r:
            raise EXCEPTIONS[r["raise"]]("reaction")

    def op(self, op: dict) -> dict:
        kind = op["op"]
        try:
            if kind == "listen":
                self.listen(op, False)
            elif kind == "listen_once":
                self.listen(op, True)
            elif kind == "unsub":
                self.handles[op["id"]]()
            elif kind == "fire":
                self.fire(op)
            elif kind == "listeners":
                return {"listeners": [[k, v] for k, v in self.hass.bus.async_listeners().items()]}
        except Exception as err:  # noqa: BLE001
            return {"error": type(err).__name__}
        return {"ok": True}


def _logs(records: list[logging.LogRecord]) -> list[str]:
    out = []
    for r in records:
        if r.name != "homeassistant.core" or r.levelno < logging.ERROR:
            continue
        exc = type(r.exc_info[1]).__name__ if r.exc_info and r.exc_info[1] else None
        if r.msg == "Error in event filter":
            out.append(f"Error in event filter: {exc}")
        elif str(r.msg).startswith("Error running job"):
            out.append(f"Error running job: {exc}")
        elif str(r.msg).startswith("Unable to remove unknown job listener"):
            out.append("Unable to remove unknown job listener")
    return out


def _known_ids(x, acc: set[str]) -> set[str]:
    if isinstance(x, dict):
        c = x.get("context")
        if isinstance(c, dict) and "id" in c:
            acc.add(c["id"])
        for v in x.values():
            _known_ids(v, acc)
    elif isinstance(x, list):
        for v in x:
            _known_ids(v, acc)
    return acc


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_events(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine,
                      caplog: pytest.LogCaptureFixture, case: dict) -> None:
    await hass.async_block_till_done()
    # the listeners HA already has; the model starts from the same table
    base = [[k, v] for k, v in hass.bus.async_listeners().items()]
    init = engine({"op": "init", "listeners": base})
    assert init["result"] == {"ok": True}, init

    runner = Runner(hass, _known_ids(case["ops"], set()))
    now = case.get("now", NOW)
    for i, op in enumerate(case["ops"]):
        now = op.get("now", now)
        freezer.move_to(EPOCH + timedelta(microseconds=now))
        lean = engine({**op, "now": now})
        assert "unsupported" not in lean, f"op {i}: HALean rejected {op}: {lean['unsupported']}"

        caplog.clear()
        runner.deliveries.clear()
        result = runner.op(op)
        await hass.async_block_till_done()
        ha = {"result": result, "deliveries": list(runner.deliveries), "logs": _logs(caplog.records)}

        if ha != lean:
            for key in ("result", "logs", "deliveries"):
                if ha[key] != lean[key]:
                    hk, lk = ha[key], lean[key]
                    if key == "deliveries" and len(hk) == len(lk):
                        j = next(n for n, (a, b) in enumerate(zip(hk, lk)) if a != b)
                        hk, lk = (j, hk[j]), (j, lk[j])
                    elif key == "deliveries":
                        hk, lk = (len(hk), hk[:8]), (len(lk), lk[:8])
                    pytest.fail(f"op {i} {op['op']}: {key} differ\nHA:     {hk}\nHALean: {lk}")
        if "expect" in op:
            # the case's own expectation, to keep the cases honest
            exp = op["expect"]
            got = [d["listener"] for d in ha["deliveries"]] if "deliveries" in exp else None
            if "deliveries" in exp:
                assert got == exp["deliveries"], f"op {i}: deliveries {got}"
            if "result" in exp:
                assert ha["result"] == exp["result"], f"op {i}: result {ha['result']}"
            if "logs" in exp:
                assert ha["logs"] == exp["logs"], f"op {i}: logs {ha['logs']}"
