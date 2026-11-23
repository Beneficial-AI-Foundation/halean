"""Differential test for the joined core: run every case in tests/core/hass/*.yaml
on a real in-process `hass` (its own `hass.states`, `hass.bus` and
`hass.services`, wired together as upstream) and on `halean-core`, and require
the same result and the same ordered trace for every operation.

A case is a list of operations (`set`, `remove`, `get`, `fire`, `listen`,
`listen_once`, `unsub`, `listeners`, `register`, `remove_service`, `has`,
`call`), each optionally with a clock reading `now` (µs since the epoch; it
carries over). Listeners and service handlers are scripted with the same
actions (fire, listen, unsub, raise, set, remove, call, register,
remove_service), so a listener on `state_changed` can set another state and a
handler can set states, fire events and call other services:

* a listener is a `@callback`: it records the event (`Event.as_dict()`, states
  as `State._as_dict` computed afresh) and runs its `react` script, up to
  `react_times` receipts; a service call in it runs in a task
  (`hass.async_create_task`, which starts eagerly) that records the outcome;
* a listener with `async: true` is an `async def`: `async_run_hass_job` runs
  it as an eager task, so it records the event and runs its script up to its
  first real suspension inside the dispatch; its service calls are awaited
  inline (errors propagate unless `catch`); an exception ends the task and is
  logged when the task is finalized (`Error doing job: Task exception was
  never retrieved`, by HA's own loop exception handler, installed here as
  `homeassistant.runner` installs it);
* a handler is an `async def`: it runs its `do` script (awaiting nested
  calls, whose errors propagate unless `catch`), then returns `return`
  (default `None`), echoes the call, or raises;
* in a coroutine, `sleep: 0` is `await asyncio.sleep(0)` and `wait: <id>`
  awaits the future `<id>` (made with `loop.create_future()` on first use);
  `resolve: <id>` (a script action or an operation) is `set_result(None)`.

After every operation the harness awaits `hass.async_block_till_done()`, and
the model runs its `block_till_done` (the trace of both is the operation's),
unless the case says `manual: true`: then only the explicit `sleep`
(`await asyncio.sleep(0)`) and `block_till_done` operations, and a blocking
call whose handler suspends, let the event loop run. A case must end with no
task left (checked with a final `block_till_done`).

The trace interleaves, in the order they happen: deliveries, the outcome of
each scripted service call, and `homeassistant.core` log records (warning and
above; the bus's job reprs are dropped). Contexts HA creates have random ULIDs;
on both sides they are renamed `ctx#<n>` in order of first appearance.

Run:  uv run tests/differential/run.py -k core
"""

from __future__ import annotations

import asyncio
import copy
import json
import logging
import re
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import probatio
import pytest
import yaml
from freezegun.api import FrozenDateTimeFactory

from homeassistant import runner as ha_runner
from homeassistant.core import Context, EventOrigin, HomeAssistant, State, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers.translation import async_load_integrations

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = [c for f in sorted((ROOT / "tests" / "core" / "hass").glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-core"
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
# 2026-11-26 16:30:45.123456 UTC
NOW = 1795710645123456
HA_ULID = re.compile(r"\b[0-9A-HJKMNP-TV-Z]{26}\b")
LEAN_ULID = re.compile(r"ulid@\d+#\d+")

EXCEPTIONS = {
    "HomeAssistantError": HomeAssistantError,
    "ServiceValidationError": ServiceValidationError,
    "Invalid": probatio.Invalid,
    "ValueError": ValueError,
    "RuntimeError": RuntimeError,
}
TYPES = {"int": int, "float": float, "str": str, "bool": bool, "any": object}
EXTRA = {"prevent": probatio.PREVENT_EXTRA, "allow": probatio.ALLOW_EXTRA,
         "remove": probatio.REMOVE_EXTRA}


def error_kind(err: BaseException) -> str:
    """protocol/schema.json `error_kind`."""
    if isinstance(err, probatio.Invalid):
        return "invalid"
    if isinstance(err, HomeAssistantError):
        return "ha_error"
    return "other"


def error_dict(err: BaseException) -> dict:
    out = {"exception": type(err).__name__, "error_kind": error_kind(err), "message": str(err)}
    if isinstance(err, HomeAssistantError) and err.translation_key:
        out |= {"translation_domain": err.translation_domain,
                "translation_key": err.translation_key,
                "translation_placeholders": err.translation_placeholders or {}}
    return out


def make_schema(spec: dict | None):
    if spec is None:
        return None
    fields = {}
    for f in spec["fields"]:
        marker = probatio.Required if f.get("required") else probatio.Optional
        kw = {"default": copy.deepcopy(f["default"])} if "default" in f else {}
        fields[marker(f["key"], **kw)] = TYPES[f["type"]]
    return probatio.Schema(fields, extra=EXTRA[spec.get("extra", "prevent")])


def jsonable(x):
    """Event data as JSON: states as `State._as_dict` (fresh), datetimes as
    `isoformat()`."""
    if isinstance(x, State):
        return json.loads(json.dumps(State._as_dict.wrapped(x)))
    if isinstance(x, datetime):
        return x.isoformat()
    if isinstance(x, dict) or hasattr(x, "items"):
        return {k: jsonable(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [jsonable(v) for v in x]
    return x


class Renamer:
    """Rename random context ids `ctx#<n>` in order of first appearance."""

    def __init__(self, pattern: re.Pattern) -> None:
        self.pattern = pattern
        self.names: dict[str, str] = {}

    def __call__(self, obj):
        def sub(m: re.Match) -> str:
            return self.names.setdefault(m.group(0), f"ctx#{len(self.names)}")
        return json.loads(self.pattern.sub(sub, json.dumps(obj, sort_keys=True)))


class Runner:
    """Drives the real `hass` with the case's scripted listeners and handlers."""

    def __init__(self, hass: HomeAssistant) -> None:
        self.hass = hass
        self.trace: list[dict] = []
        self.handles: dict[str, object] = {}
        self.futures: dict[str, asyncio.Future] = {}

    def future(self, fid: str) -> asyncio.Future:
        if fid not in self.futures:
            self.futures[fid] = self.hass.loop.create_future()
        return self.futures[fid]

    # --- arguments -------------------------------------------------------

    @staticmethod
    def _context(c, inherited: Context | None = None) -> Context | None:
        if c == "inherit":
            return inherited
        if c is None:
            return None
        return Context(id=c["id"], user_id=c.get("user_id"), parent_id=c.get("parent_id"))

    def _filter(self, f):
        def flt(data) -> bool:
            if isinstance(f, bool):
                return f
            if "eq" in f:
                return all(k in data and data[k] == v for k, v in f["eq"].items())
            if "has" in f:
                return f["has"] in data
            raise ValueError("filter")

        return callback(flt)

    # --- listeners and handlers -------------------------------------------

    def listen(self, spec: dict, once: bool) -> None:
        lid, react, times = spec["id"], spec.get("react") or [], spec.get("react_times")
        count = 0

        if spec.get("async"):
            async def listener(event) -> None:
                nonlocal count
                count += 1
                self.trace.append({"delivery": lid, "event": jsonable(event.as_dict())})
                if times is None or count <= times:
                    await self.run_async(react, event.context)
        else:
            @callback
            def listener(event) -> None:
                nonlocal count
                count += 1
                self.trace.append({"delivery": lid, "event": jsonable(event.as_dict())})
                if times is None or count <= times:
                    for a in react:
                        self.act(a, event.context, in_listener=True)

        kwargs = {}
        if spec.get("filter") is not None:
            kwargs["event_filter"] = self._filter(spec["filter"])
        bus = self.hass.bus
        self.handles[lid] = (bus.async_listen_once if once else bus.async_listen)(
            spec["event_type"], listener, **kwargs)

    def make_handler(self, spec: dict):
        body = spec.get("do") or []

        async def handler(call):
            await self.run_async(body, call.context)
            if "raise" in spec:
                raise EXCEPTIONS[spec["raise"]](spec.get("message", ""))
            if spec.get("echo"):
                return {"domain": call.domain, "service": call.service, "data": dict(call.data),
                        "return_response": call.return_response, "context_id": call.context.id}
            return copy.deepcopy(spec.get("return"))

        return handler

    async def run_async(self, actions: list, inherited: Context | None) -> None:
        """A coroutine's script: service calls are awaited inline, and it may
        suspend."""
        for a in actions:
            if "call" in a:
                c = a["call"]
                await self.call(c, self._context(c.get("context"), inherited), c.get("catch", False))
            elif "sleep" in a:
                await asyncio.sleep(a["sleep"])
            elif "wait" in a:
                await self.future(a["wait"])
            else:
                self.act(a, inherited, in_listener=False)

    async def call(self, c: dict, ctx: Context | None, caught: bool):
        try:
            r = await self.hass.services.async_call(
                c["domain"], c["service"], copy.deepcopy(c.get("data")), c.get("blocking", False),
                ctx, copy.deepcopy(c.get("target")), c.get("return_response", False))
        except Exception as err:  # noqa: BLE001
            self.trace.append({"call": c["id"], "error": error_dict(err)})
            if not caught:
                raise
            return
        self.trace.append({"call": c["id"], "ok": repr(r)})

    def register(self, r: dict) -> None:
        self.hass.services.async_register(
            r["domain"], r["service"], self.make_handler(r["handler"]),
            make_schema(r.get("schema")), SupportsResponse(r.get("supports_response", "none")))

    def fire(self, f: dict, inherited: Context | None) -> None:
        self.hass.bus.async_fire(
            f["event_type"], f.get("data"),
            EventOrigin.remote if f.get("origin") == "remote" else EventOrigin.local,
            self._context(f.get("context"), inherited))

    def act(self, a: dict, inherited: Context | None, in_listener: bool) -> None:
        """One action of a script (a service call only in a listener; a handler
        awaits its calls itself)."""
        hass = self.hass
        if "fire" in a:
            self.fire(a["fire"], inherited)
        elif "listen" in a:
            self.listen(a["listen"], False)
        elif "listen_once" in a:
            self.listen(a["listen_once"], True)
        elif "unsub" in a:
            self.handles[a["unsub"]]()
        elif "raise" in a:
            raise EXCEPTIONS[a["raise"]](a.get("message", ""))
        elif "set" in a:
            s = a["set"]
            hass.states.async_set(s["entity_id"], s["state"], s.get("attributes"),
                                  s.get("force_update", False),
                                  self._context(s.get("context"), inherited))
        elif "remove" in a:
            r = a["remove"]
            hass.states.async_remove(r["entity_id"], self._context(r.get("context"), inherited))
        elif "call" in a:
            assert in_listener
            c = a["call"]
            hass.async_create_task(self.call(c, self._context(c.get("context"), inherited), True))
        elif "register" in a:
            self.register(a["register"])
        elif "remove_service" in a:
            r = a["remove_service"]
            hass.services.async_remove(r["domain"], r["service"])
        elif "resolve" in a:
            self.future(a["resolve"]).set_result(None)
        else:
            raise AssertionError(f"unknown action {a}")

    # --- top-level operations ---------------------------------------------

    async def op(self, op: dict) -> dict:
        hass = self.hass
        kind = op["op"]
        res = None
        try:
            if kind == "set":
                self.act({"set": op}, None, False)
            elif kind == "remove":
                res = hass.states.async_remove(op["entity_id"], self._context(op.get("context")))
            elif kind == "get":
                s = hass.states.get(op["entity_id"])
                res = None if s is None else jsonable(s)
            elif kind == "fire":
                self.fire(op, None)
            elif kind in ("listen", "listen_once"):
                self.listen(op, kind == "listen_once")
            elif kind == "unsub":
                self.handles[op["id"]]()
            elif kind == "listeners":
                res = [[k, v] for k, v in hass.bus.async_listeners().items()]
            elif kind == "register":
                self.register(op)
            elif kind == "remove_service":
                hass.services.async_remove(op["domain"], op["service"])
            elif kind == "has":
                res = hass.services.has_service(op["domain"], op["service"])
            elif kind == "call":
                r = await hass.services.async_call(
                    op["domain"], op["service"], copy.deepcopy(op.get("data")),
                    op.get("blocking", False), self._context(op.get("context")),
                    copy.deepcopy(op.get("target")), op.get("return_response", False))
                res = repr(r)
            elif kind == "resolve":
                self.act({"resolve": op["id"]}, None, False)
            elif kind == "sleep":
                await asyncio.sleep(0)
            elif kind == "block_till_done":
                await hass.async_block_till_done()
            else:
                raise AssertionError(f"unknown op {kind}")
        except Exception as err:  # noqa: BLE001
            return {"error": error_dict(err)}
        return {"ok": res}


class _Records(logging.Handler):
    """`homeassistant.core` and `homeassistant` records (warning and above),
    into the trace."""

    def __init__(self, trace: list) -> None:
        super().__init__(logging.WARNING)
        self.trace = trace

    def emit(self, r: logging.LogRecord) -> None:
        if r.name not in ("homeassistant", "homeassistant.core"):
            return
        msg = str(r.msg)
        if msg.startswith("Error running job"):
            message = "Error running job"
        elif msg.startswith("Error doing job"):
            # `_async_loop_exception_handler`: the context's message (the
            # task's repr and, in debug mode, its creation stack dropped)
            message = f"Error doing job: {r.args[0]}"
        elif msg.startswith("Unable to remove unknown job listener"):
            message = "Unable to remove unknown job listener"
        else:
            message = r.getMessage()
        out = {"level": r.levelname.lower(), "message": message}
        if r.exc_info and r.exc_info[1] is not None:
            out["exception"] = f"{type(r.exc_info[1]).__name__}: {r.exc_info[1]}"
        self.trace.append({"log": out})


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


def _diff(i: int, op: dict, ha: dict, lean: dict) -> str:
    if ha["result"] != lean["result"]:
        return f"op {i} {op['op']}: result differs\nHA:     {ha['result']}\nHALean: {lean['result']}"
    ht, lt = ha["trace"], lean["trace"]
    for j, (a, b) in enumerate(zip(ht, lt)):
        if a != b:
            return f"op {i} {op['op']}: trace entry {j} differs\nHA:     {a}\nHALean: {b}"
    return (f"op {i} {op['op']}: trace lengths differ ({len(ht)} vs {len(lt)})\n"
            f"HA:     {ht[len(lt):]}\nHALean: {lt[len(ht):]}")


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_core(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine,
                    case: dict) -> None:
    # the exception messages come from the homeassistant integration's strings
    await async_load_integrations(hass, {"homeassistant"})
    await hass.async_block_till_done()
    assert hass.states.async_entity_ids() == []
    baseline = set(hass.services.async_services())
    # the listeners HA already has; the model starts from the same table
    base = [[k, v] for k, v in hass.bus.async_listeners().items()]
    init = engine({"op": "init", "listeners": base, "now": 0})
    assert init["result"] == {"ok": None}, init

    now = case.get("now", NOW)
    if case.get("engine_only"):
        # rejections HA cannot show (it would never return): the model only
        for i, op in enumerate(case["ops"]):
            now = op.get("now", now)
            msg = {k: v for k, v in op.items() if k not in ("unsupported", "expect")}
            lean = engine({**msg, "now": now})
            assert ("unsupported" in lean) == bool(op.get("unsupported")), f"op {i} {op}: {lean}"
        return

    runner = Runner(hass)
    records = _Records(runner.trace)
    ha_logger = logging.getLogger("homeassistant")
    ha_logger.addHandler(records)
    # HA's own loop exception handler (`homeassistant.runner.configure_event_loop`)
    loop = asyncio.get_running_loop()
    test_handler = loop.get_exception_handler()
    loop.set_exception_handler(ha_runner._async_loop_exception_handler)
    rename_ha, rename_lean = Renamer(HA_ULID), Renamer(LEAN_ULID)
    manual = case.get("manual", False)
    ops = case["ops"] + ([{"op": "block_till_done"}] if manual else [])
    try:
        for i, op in enumerate(ops):
            now = op.get("now", now)
            msg = {k: v for k, v in op.items() if k not in ("unsupported", "expect")}
            lean = engine({**msg, "now": now})
            if op.get("unsupported"):
                assert "unsupported" in lean, f"op {i}: HALean should reject {op}, got {lean}"
                continue
            assert "unsupported" not in lean, f"op {i}: HALean rejected {op}: {lean['unsupported']}"
            if not manual:
                settle = engine({"op": "block_till_done", "now": now})
                # HA would never return from `async_block_till_done`
                assert "unsupported" not in settle, \
                    f"op {i}: HALean rejected the block_till_done after {op}: {settle['unsupported']}"
                lean["trace"] += settle["trace"]
            assert op.get("domain", "x").lower() not in baseline

            freezer.move_to(EPOCH + timedelta(microseconds=now))
            runner.trace.clear()
            result = await runner.op(op)
            if not manual:
                await hass.async_block_till_done()
            ha = rename_ha({"result": result, "trace": list(runner.trace)})
            lean = rename_lean(lean)
            if ha != lean:
                pytest.fail(_diff(i, op, ha, lean))
            if "expect" in op:
                # the case's own expectation, to keep the cases honest
                exp = op["expect"]
                if "deliveries" in exp:
                    got = [f"{t['delivery']}:{t['event']['event_type']}"
                           if ":" in "".join(exp["deliveries"]) else t["delivery"]
                           for t in ha["trace"] if "delivery" in t]
                    assert got == exp["deliveries"], f"op {i}: deliveries {got}"
                if "result" in exp:
                    assert ha["result"] == exp["result"], f"op {i}: result {ha['result']}"
                if "calls" in exp:
                    got = [t["call"] + (":ok" if "ok" in t else ":error")
                           for t in ha["trace"] if "call" in t]
                    assert got == exp["calls"], f"op {i}: calls {got}"
        assert not hass._tasks, f"tasks left: {hass._tasks}"
    finally:
        loop.set_exception_handler(test_handler)
        ha_logger.removeHandler(records)
