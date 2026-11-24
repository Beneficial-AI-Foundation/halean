#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["websockets>=13", "pyyaml"]
# ///
"""End-to-end test of bridge.py against a fake Home Assistant WebSocket server.

Checks the full loop: auth, get_states, subscribe, a state_changed event,
the engine's call_service reaching "HA", and a fire_event after the result.
With --scripts (second run): the automation calls a script that HALean runs,
the script's call reaches "HA", and the script entity's states are written
over the REST API (a tiny fake HTTP server).
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
# second run: the automation calls script.lights, which HALean runs
AUTOMATIONS_SCRIPTS = [
    {
        "id": "motion",
        "triggers": [{"trigger": "state", "entity_id": "binary_sensor.motion", "to": "on"}],
        "actions": [{"action": "script.lights"}, {"event": "light_done"}],
    }
]
SCRIPTS = {"lights": {"sequence": [{"action": "light.turn_on", "target": {"entity_id": "light.hall"}}]}}
STATE_OFF = {"entity_id": "binary_sensor.motion", "state": "off", "attributes": {},
             "last_changed": "2026-01-01T00:00:00+00:00"}


async def run(with_scripts: bool) -> bool:
    loop = asyncio.get_running_loop()
    got: dict[str, asyncio.Future] = {
        k: loop.create_future() for k in ("call_service", "fire_event")
    }
    posted: list[tuple[str, dict]] = []  # REST state writes

    async def rest(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        head = (await reader.readuntil(b"\r\n\r\n")).decode()
        lines = head.split("\r\n")
        path = lines[0].split()[1]
        hdrs = {k.lower(): v.strip() for k, _, v in (l.partition(":") for l in lines[1:] if l)}
        body = await reader.readexactly(int(hdrs.get("content-length", "0")))
        if hdrs.get("authorization") == "Bearer test-token":
            posted.append((path, json.loads(body)))
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        await writer.drain()
        writer.close()

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
                # with scripts, script_started is fired too: wait for light_done
                if not got[msg["type"]].done() and msg.get("event_type") != "script_started":
                    got[msg["type"]].set_result(msg)

    tmpdir = Path(os.environ.get("TMPDIR", "/tmp"))
    tmp = tmpdir / "halean_e2e_automations.json"
    tmp.write_text(json.dumps(AUTOMATIONS_SCRIPTS if with_scripts else AUTOMATIONS))
    args = [str(tmp)]
    if with_scripts:
        sc = tmpdir / "halean_e2e_scripts.json"
        sc.write_text(json.dumps(SCRIPTS))
        args += ["--scripts", str(sc)]
    http = await asyncio.start_server(rest, "127.0.0.1", 0)
    async with http, websockets.serve(handler, "127.0.0.1", 0) as server:
        port = server.sockets[0].getsockname()[1]
        rest_port = http.sockets[0].getsockname()[1]
        env = {**os.environ, "HA_URL": f"ws://127.0.0.1:{port}", "HA_TOKEN": "test-token",
               "HA_REST_URL": f"http://127.0.0.1:{rest_port}"}
        bridge = await asyncio.create_subprocess_exec(
            "uv", "run", str(ROOT / "bridge" / "bridge.py"), *args, env=env)
        try:
            call = await asyncio.wait_for(got["call_service"], 60)
            event = await asyncio.wait_for(got["fire_event"], 10)
            await asyncio.sleep(0.5)  # let the last state write land
        finally:
            bridge.terminate()
            await bridge.wait()
    ok = (call["domain"], call["service"], call["target"]) == ("light", "turn_on", {"entity_id": "light.hall"}) \
        and event["event_type"] == "light_done"
    if with_scripts:
        # off at load, on while running, off again; written with the bearer token
        seq = [(p, b["state"]) for p, b in posted]
        ok = ok and seq[:1] == [("/api/states/script.lights", "off")] \
            and ("/api/states/script.lights", "on") in seq and seq[-1] == ("/api/states/script.lights", "off")
    name = "bridge end-to-end" + (" with scripts" if with_scripts else "")
    print(f"PASS {name}" if ok else f"FAIL {name}: {call} {event} {posted}")
    return ok


async def main() -> int:
    ok = await run(False)
    ok = await run(True) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
