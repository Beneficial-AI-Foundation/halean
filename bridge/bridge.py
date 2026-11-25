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
  uv run bridge/bridge.py path/to/automations.yaml [--scripts scripts.yaml] [--dry-run]
                          [--status-entity input_text.x]

--status-entity makes the engine's activity visible inside HA: the entity's
value is set to each run the engine starts (numbered), and to warnings, so
its history in the logbook is a feed of what the engine did. This is display
only; it never feeds back into the engine's decisions.

Automations the engine does not support are reported and left to HA. For the
ones it runs, turn the HA copy off (automation.turn_off) so they don't run twice.

MQTT triggers are fed through HA's MQTT connection: the bridge subscribes with
`mqtt/subscribe` (needs an admin token). Webhook triggers cannot be fed: HA
receives the HTTP request itself and its WebSocket API does not pass it on, so
automations with webhook triggers should stay in HA (the bridge warns).

--scripts runs scripts.yaml in the same engine (halean-script): the engine's
automations then call these scripts, not HA's. HA's WebSocket API cannot
register services, so HA itself (the UI, its own automations) cannot call
them; remove the scripts HALean runs from HA's scripts.yaml. Their entity
states (on/off, last_triggered, current, ...) are written to HA over its REST
API (POST /api/states/<entity_id> at HA_REST_URL, by default HA_URL's host),
so they show up in HA as plain states.
"""

from __future__ import annotations

import argparse
import asyncio
import itertools
import json
import logging
import os
import time
import urllib.parse
import urllib.request
from datetime import UTC, datetime, timedelta
from pathlib import Path

import websockets

from protocol import protocol_automations, protocol_scripts
import yaml

ROOT = Path(__file__).resolve().parent.parent


def _default_exe(name: str) -> Path:
    """bin/ of a release download, else the lake build output of a checkout."""
    for d in (ROOT / "bin", ROOT / ".lake" / "build" / "bin"):
        for p in (d / name, d / f"{name}.exe"):
            if p.exists():
                return p
    return ROOT / ".lake" / "build" / "bin" / name


ENGINE = Path(os.environ.get("HALEAN_ENGINE") or _default_exe("halean-automation"))
# automations and scripts in one engine (--scripts)
SCRIPT_ENGINE = Path(os.environ.get("HALEAN_SCRIPT_ENGINE") or _default_exe("halean-script"))
_LOG = logging.getLogger("halean.bridge")

# HA WebSocket error codes -> engine ErrKind (see HALean/Automation/Script.lean
# `ErrKind`). `invalid` stands for script.py's CONFIGURATION_ERRORS, which
# `continue_on_error` never swallows: probatio.Invalid (`invalid_format`) and
# ServiceNotFound (`not_found`: the called service does not exist).
ERROR_KIND = {
    "invalid_format": "invalid",
    "not_found": "invalid",
    "home_assistant_error": "ha_error",
    "service_validation_error": "ha_error",
    "unauthorized": "ha_error",
}

# Configuration errors HA reports with another code, told apart by the
# translation key: `_async_step_call_service` raises probatio.Invalid before
# calling a service whose response support doesn't match the step (the
# WebSocket API reports the same mismatch with the first two keys), and a
# ServiceNotFound raised by a service the called one calls is reported as
# `home_assistant_error` / `child_service_not_found`; in a script run it is
# still a ServiceNotFound.
INVALID_TRANSLATION_KEYS = {"service_does_not_support_response", "service_lacks_response_request",
                            "child_service_not_found"}


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

    def __init__(self, path: Path = ENGINE) -> None:
        self.path = path
        self.proc: asyncio.subprocess.Process | None = None
        self.lock = asyncio.Lock()

    async def start(self) -> None:
        self.proc = await asyncio.create_subprocess_exec(
            str(self.path), stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE
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
        # ids of our `mqtt/subscribe` subscriptions
        self.mqtt_ids: set[int] = set()

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
                _LOG.warning("%s stays in HA: %s", c["id"], c["reason"])
            elif kind == "set_state":
                # a script entity the engine owns (--scripts)
                if self.dry_run:
                    _LOG.info("[dry-run] set_state %s %s", c["entity_id"], c["state"])
                else:
                    asyncio.create_task(self.set_state(c))
            elif kind == "call_done":
                pass  # answers to `call` inputs, which the bridge does not send

    async def set_state(self, c: dict) -> None:
        """Write a state over HA's REST API (the WebSocket API cannot)."""
        base = os.environ.get("HA_REST_URL")  # default: HA_URL's host, over http(s)
        if not base:
            u = urllib.parse.urlsplit(os.environ["HA_URL"])
            base = f"{'https' if u.scheme == 'wss' else 'http'}://{u.netloc}"
        url = f"{base.rstrip('/')}/api/states/{urllib.parse.quote(c['entity_id'])}"
        body = json.dumps({"state": c["state"], "attributes": c["attributes"]}).encode()
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "Authorization": f"Bearer {os.environ['HA_TOKEN']}", "Content-Type": "application/json"})
        try:
            await asyncio.to_thread(lambda: urllib.request.urlopen(req, timeout=10).read())
        except Exception as err:  # display only: never feeds back into the engine
            _LOG.warning("could not write %s: %s", c["entity_id"], err)

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

    async def subscribe_mqtt(self, filters: list[tuple[str, int]]) -> None:
        """`mqtt/subscribe` (admin only): HA forwards every message on these
        filters, retained ones included, which the engine dispatches to its
        mqtt triggers."""
        for topic, qos in filters:
            msg_id = next(self.ids)
            self.mqtt_ids.add(msg_id)
            fut = asyncio.get_running_loop().create_future()
            self.pending[msg_id] = fut
            await self.ws.send(json.dumps({"id": msg_id, "type": "mqtt/subscribe",
                                           "topic": topic, "qos": qos}))
            res = await fut
            if not res.get("success"):
                self.mqtt_ids.discard(msg_id)
                _LOG.error("mqtt/subscribe %s failed (is the MQTT integration set up?): %s",
                           topic, res.get("error"))

    async def reader(self) -> None:
        async for raw in self.ws:
            msg = json.loads(raw)
            if msg.get("type") == "result" and msg.get("id") in self.pending:
                self.pending.pop(msg["id"]).set_result(msg)
            elif msg.get("type") == "event" and msg.get("id") in self.mqtt_ids:
                m = msg["event"]
                out = {"type": "mqtt", "topic": m["topic"], "payload": m["payload"],
                       "qos": m.get("qos", 0), "retain": m.get("retain", False), **now_fields()}
                await self.handle_cmds(await self.engine.send(out))
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


def _triggers(node, platform: str) -> list[dict]:
    """Every trigger config of a platform in automations or scripts
    (wait_for_trigger too)."""
    found = []
    if isinstance(node, dict):
        if (node.get("trigger") or node.get("platform")) == platform:
            found.append(node)
        for v in node.values():
            found += _triggers(v, platform)
    elif isinstance(node, list):
        for v in node:
            found += _triggers(v, platform)
    return found


def mqtt_filters(automations, scripts) -> list[tuple[str, int]]:
    """What the bridge subscribes to when there are mqtt triggers: `#`, plus
    `<level>/#` for each `$` top level a trigger names (`#` does not match
    topics starting with `$`), at the highest qos a trigger asks for."""
    trigs = _triggers([automations, scripts], "mqtt")
    if not trigs:
        return []
    qos = max(int(t.get("qos", 0)) if str(t.get("qos", 0)).strip().isdigit() else 0
              for t in trigs)
    dollar = sorted({str(t["topic"]).split("/")[0] for t in trigs
                     if str(t.get("topic", "")).startswith("$")})
    return [("#", qos)] + [(f"{level}/#", qos) for level in dollar]


async def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("automations", type=Path, help="automations.yaml (or a JSON list)")
    p.add_argument("--scripts", type=Path, help="scripts.yaml to run in the same engine")
    p.add_argument("--dry-run", action="store_true", help="log service calls instead of sending them")
    p.add_argument("--status-entity", help="input_text entity that shows engine activity in HA")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    automations = yaml.safe_load(args.automations.read_text()) or []
    scripts = (yaml.safe_load(args.scripts.read_text()) or {}) if args.scripts else None
    engine = Engine(SCRIPT_ENGINE if scripts is not None else ENGINE)
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
        init = {"type": "init", "automations": protocol_automations(automations),
                "states": [to_engine_state(s) for s in states], **now_fields(),
                # HA's location, for the sun trigger
                "location": {k: config.get(k) for k in ("latitude", "longitude", "elevation")}}
        if scripts is not None:
            init["scripts"] = protocol_scripts(scripts)
        await bridge.handle_cmds(await engine.send(init))
        await bridge.request({"type": "subscribe_events"})  # all events
        if filters := mqtt_filters(automations, scripts):
            await bridge.subscribe_mqtt(filters)
        # HA's WebSocket API has no way to receive webhook requests (only to
        # send one, `webhook/handle`), so webhook triggers never fire here
        for a in automations:
            if isinstance(a, dict) and _triggers(a, "webhook"):
                _LOG.warning("%s has a webhook trigger, which the bridge cannot feed: keep it in HA",
                             a.get("id", a.get("alias", "?")))
        _LOG.info("engine running %d automations%s", len(automations),
                  f" and {len(scripts)} scripts" if scripts is not None else "")
        bridge.announce(f"engine started with {len(automations)} automations")
        await asyncio.gather(reader, bridge.ticker())


if __name__ == "__main__":
    asyncio.run(main())
