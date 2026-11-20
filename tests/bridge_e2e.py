#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["websockets>=13", "pyyaml"]
# ///
"""End-to-end test of bridge.py against a fake Home Assistant WebSocket server.

Checks the full loop: auth, get_states, subscribe, a state_changed event,
the engine's call_service reaching "HA", and a fire_event after the result.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parent.parent
AUTOMATIONS = [
    {
        "id": "motion",
        "triggers": [{"trigger": "state", "entity_id": "binary_sensor.motion", "to": "on"}],
        "actions": [
            {"action": "light.turn_on", "target": {"entity_id": "light.hall"}},
            {"event": "light_done"},
        ],
    }
]
STATE_OFF = {"entity_id": "binary_sensor.motion", "state": "off", "attributes": {},
             "last_changed": "2026-01-01T00:00:00+00:00"}


async def main() -> int:
    got: dict[str, asyncio.Future] = {
        k: asyncio.get_running_loop().create_future() for k in ("call_service", "fire_event")
    }

    async def handler(ws):
        try:
            await serve_one(ws)
        except websockets.ConnectionClosed:
            pass  # the bridge is terminated at the end of the test

    async def serve_one(ws):
        await ws.send(json.dumps({"type": "auth_required"}))
        assert json.loads(await ws.recv())["access_token"] == "test-token"
        await ws.send(json.dumps({"type": "auth_ok"}))
        async for raw in ws:
            msg = json.loads(raw)
            if msg["type"] == "get_states":
                await ws.send(json.dumps({"id": msg["id"], "type": "result", "success": True,
                                          "result": [STATE_OFF]}))
            elif msg["type"] == "get_config":
                await ws.send(json.dumps({"id": msg["id"], "type": "result", "success": True,
                                          "result": {"latitude": 52.37, "longitude": 4.89,
                                                     "elevation": 0}}))
            elif msg["type"] == "subscribe_events":
                sub = msg["id"]
                await ws.send(json.dumps({"id": sub, "type": "result", "success": True}))
                await asyncio.sleep(0.3)
                on = {**STATE_OFF, "state": "on", "last_changed": "2026-01-01T00:00:05+00:00"}
                await ws.send(json.dumps({"id": sub, "type": "event", "event": {
                    "event_type": "state_changed",
                    "data": {"entity_id": "binary_sensor.motion", "old_state": STATE_OFF,
                             "new_state": on}}}))
            elif msg["type"] in got:
                await ws.send(json.dumps({"id": msg["id"], "type": "result", "success": True,
                                          "result": {}}))
                if not got[msg["type"]].done():
                    got[msg["type"]].set_result(msg)

    tmp = Path(os.environ.get("TMPDIR", "/tmp")) / "halean_e2e_automations.json"
    tmp.write_text(json.dumps(AUTOMATIONS))
    async with websockets.serve(handler, "127.0.0.1", 0) as server:
        port = server.sockets[0].getsockname()[1]
        env = {**os.environ, "HA_URL": f"ws://127.0.0.1:{port}", "HA_TOKEN": "test-token"}
        bridge = await asyncio.create_subprocess_exec(
            "uv", "run", str(ROOT / "bridge" / "bridge.py"), str(tmp), env=env)
        try:
            call = await asyncio.wait_for(got["call_service"], 60)
            event = await asyncio.wait_for(got["fire_event"], 10)
        finally:
            bridge.terminate()
            await bridge.wait()
    ok = (call["domain"], call["service"], call["target"]) == ("light", "turn_on", {"entity_id": "light.hall"}) \
        and event["event_type"] == "light_done"
    print("PASS bridge end-to-end" if ok else f"FAIL: {call} {event}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
