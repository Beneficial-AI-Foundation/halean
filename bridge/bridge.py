#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pyyaml", "websockets>=13"]
# ///
"""Thin, unverified I/O shell between Home Assistant and the Lean engine.

  HA (WebSocket API) --state_changed / events--> bridge --JSON lines--> halean
  HA <--call_service / fire_event---------------- bridge <--batches----- halean

Everything that decides *what* to do lives in the Lean engine. This file only
moves messages, stamps them with the current time and translates errors.

Usage:
  export HA_URL=ws://homeassistant.local:8123/api/websocket
  export HA_TOKEN=<long-lived access token>
  uv run bridge/bridge.py path/to/automations.yaml [--dry-run] [--status-entity input_text.x]

--status-entity makes the engine's activity visible inside HA: the entity's
value is set to each run the engine starts (numbered), and to warnings, so
its history in the logbook is a feed of what the engine did. This is display
only; it never feeds back into the engine's decisions.

Automations the engine does not support are reported and left to HA. For the
ones it runs, turn the HA copy off (automation.turn_off) so they don't run twice.
"""

from __future__ import annotations

import argparse
import asyncio
import itertools
import json
import logging
import os
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path

import websockets

from protocol import protocol_automations
import yaml

ROOT = Path(__file__).resolve().parent.parent
ENGINE = Path(os.environ.get("HALEAN_ENGINE", ROOT / ".lake" / "build" / "bin" / "halean-automation"))
_LOG = logging.getLogger("halean.bridge")

# HA WebSocket error codes -> engine ErrKind (see HALean/Script.lean `ErrKind`)
ERROR_KIND = {
    "invalid_format": "invalid",
    "not_found": "ha_error",
    "home_assistant_error": "ha_error",
    "service_validation_error": "ha_error",
    "unauthorized": "ha_error",
}

# `_async_step_call_service` raises vol.Invalid (a configuration error) before
# calling a service whose response support doesn't match the step; over the
# WebSocket API HA reports the same mismatch with these translation keys.
INVALID_TRANSLATION_KEYS = {"service_does_not_support_response", "service_lacks_response_request"}


def now_fields() -> dict:
    t = time.time()
    off = datetime.now().astimezone().utcoffset()
    return {"now": int(t * 1000), "tz": int(off.total_seconds()) if off else 0}


def iso_ms(value: str | None) -> int:
    if not value:
        return 0
    return int(datetime.fromisoformat(value).timestamp() * 1000)


_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)


def iso_us(value: str | None) -> int | None:
    """Exact microseconds since the epoch (templates print them)."""
    if not value:
        return None
    return (datetime.fromisoformat(value) - _EPOCH) // timedelta(microseconds=1)


def to_engine_state(s: dict | None) -> dict | None:
    if s is None:
        return None
    return {
        "entity_id": s["entity_id"],
        "state": s["state"],
        "attributes": s.get("attributes", {}),
        "last_changed": iso_ms(s.get("last_changed")),
        "last_changed_us": iso_us(s.get("last_changed")),
        "last_updated_us": iso_us(s.get("last_updated")),
    }


class Engine:
    """The Lean process. One request line in, one batch line out."""

    def __init__(self) -> None:
        self.proc: asyncio.subprocess.Process | None = None
        self.lock = asyncio.Lock()

    async def start(self) -> None:
        self.proc = await asyncio.create_subprocess_exec(
            str(ENGINE), stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE
        )

    async def send(self, msg: dict) -> list[dict]:
        assert self.proc and self.proc.stdin and self.proc.stdout
        async with self.lock:
            self.proc.stdin.write((json.dumps(msg) + "\n").encode())
            await self.proc.stdin.drain()
            line = await self.proc.stdout.readline()
        if not line:
            raise RuntimeError("engine exited")
        out = json.loads(line)
        if out.get("type") == "error":
            _LOG.error("engine rejected input: %s", out["message"])
            return []
        return out["cmds"]


class Bridge:
    def __init__(self, ws, engine: Engine, dry_run: bool, status_entity: str | None = None) -> None:
        self.ws = ws
        self.status_entity = status_entity
        self.runs = 0
        self.engine = engine
        self.dry_run = dry_run
        self.ids = itertools.count(1)
        self.pending: dict[int, asyncio.Future] = {}

    async def request(self, payload: dict) -> dict:
        msg_id = next(self.ids)
        fut = asyncio.get_running_loop().create_future()
        self.pending[msg_id] = fut
        await self.ws.send(json.dumps({"id": msg_id, **payload}))
        return await fut

    def announce(self, status: str) -> None:
        """Show engine activity in HA via the status entity. Fire and forget."""
        if not self.status_entity or self.dry_run:
            return
        asyncio.create_task(self.request({"type": "call_service",
            "domain": self.status_entity.split(".")[0], "service": "set_value",
            "service_data": {"value": status[:255]},
            "target": {"entity_id": self.status_entity}}))

    async def handle_cmds(self, cmds: list[dict]) -> None:
        for c in cmds:
            kind = c["type"]
            if kind == "call_service":
                asyncio.create_task(self.call_service(c))
            elif kind == "fire_event":
                if self.dry_run:
                    _LOG.info("[dry-run] fire_event %s %s", c["event_type"], c["data"])
                else:
                    # a task, not an await: this may run inside reader(), which
                    # is the coroutine that resolves the request's result
                    asyncio.create_task(self.request({"type": "fire_event",
                        "event_type": c["event_type"], "event_data": c["data"]}))
            elif kind == "log":
                level = getattr(logging, c["level"].upper(), logging.INFO)
                _LOG.log(level, "%s", c["message"])
                if level >= logging.WARNING:
                    self.announce(f"{c['level']}: {c['message']}")
            elif kind == "automation_triggered":
                _LOG.info("triggered %s (%s)", c["name"], c["source"])
                self.runs += 1
                self.announce(f"#{self.runs} {c['name']}")
            elif kind == "unsupported":
                _LOG.warning("automation %s stays in HA: %s", c["id"], c["reason"])

    async def call_service(self, c: dict) -> None:
        """Blocking service call; report the outcome back to the engine."""
        if self.dry_run:
            _LOG.info("[dry-run] %s.%s target=%s data=%s", c["domain"], c["service"],
                      c["target"], c["data"])
            res = {"success": True}
        else:
            req = {"type": "call_service", "domain": c["domain"], "service": c["service"],
                   "service_data": c["data"], "target": c["target"]}
            if c.get("return_response"):
                req["return_response"] = True
            res = await self.request(req)
        msg = {"type": "service_result", "call_id": c["call_id"], "ok": res.get("success", False),
               **now_fields()}
        if msg["ok"]:
            if c.get("return_response"):
                msg["response"] = (res.get("result") or {}).get("response")
        else:
            err = res.get("error", {})
            msg["error_kind"] = ("invalid" if err.get("translation_key") in INVALID_TRANSLATION_KEYS
                                 else ERROR_KIND.get(err.get("code", ""), "other"))
            msg["message"] = err.get("message", "")
        await self.handle_cmds(await self.engine.send(msg))

    async def reader(self) -> None:
        async for raw in self.ws:
            msg = json.loads(raw)
            if msg.get("type") == "result" and msg.get("id") in self.pending:
                self.pending.pop(msg["id"]).set_result(msg)
            elif msg.get("type") == "event":
                ev = msg["event"]
                if ev["event_type"] == "state_changed":
                    d = ev["data"]
                    out = {"type": "state_changed", "entity_id": d["entity_id"],
                           "old_state": to_engine_state(d.get("old_state")),
                           "new_state": to_engine_state(d.get("new_state")), **now_fields()}
                else:
                    out = {"type": "event", "event_type": ev["event_type"],
                           "data": ev.get("data", {}), **now_fields()}
                await self.handle_cmds(await self.engine.send(out))

    async def ticker(self) -> None:
        while True:
            await asyncio.sleep(1 - (time.time() % 1) + 0.005)  # just after each second
            await self.handle_cmds(await self.engine.send({"type": "tick", **now_fields()}))


async def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("automations", type=Path, help="automations.yaml (or a JSON list)")
    p.add_argument("--dry-run", action="store_true", help="log service calls instead of sending them")
    p.add_argument("--status-entity", help="input_text entity that shows engine activity in HA")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    automations = yaml.safe_load(args.automations.read_text()) or []
    engine = Engine()
    await engine.start()

    async with websockets.connect(os.environ["HA_URL"], max_size=None) as ws:
        json.loads(await ws.recv())  # auth_required
        await ws.send(json.dumps({"type": "auth", "access_token": os.environ["HA_TOKEN"]}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            raise SystemExit(f"authentication failed: {auth}")

        bridge = Bridge(ws, engine, args.dry_run, args.status_entity)
        reader = asyncio.create_task(bridge.reader())
        states = (await bridge.request({"type": "get_states"}))["result"]
        config = (await bridge.request({"type": "get_config"})).get("result") or {}
        await bridge.handle_cmds(await engine.send({
            "type": "init", "automations": protocol_automations(automations),
            "states": [to_engine_state(s) for s in states], **now_fields(),
            # HA's location, for the sun trigger
            "location": {k: config.get(k) for k in ("latitude", "longitude", "elevation")}}))
        await bridge.request({"type": "subscribe_events"})  # all events
        _LOG.info("engine running %d automations", len(automations))
        bridge.announce(f"engine started with {len(automations)} automations")
        await asyncio.gather(reader, bridge.ticker())


if __name__ == "__main__":
    asyncio.run(main())
