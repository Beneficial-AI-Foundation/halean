#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["websockets>=13", "pyyaml"]
# ///
"""Live end-to-end test: the real bridge + Lean engine driving a real Home
Assistant release (the one pinned in manifest.yaml) in a throwaway Docker
container, on its real clock.

It never touches any other Home Assistant: the container is named
`halean-e2e`, listens on port 18123, keeps its config in tests/live/.run/
(recreated on every run) and is removed at the end.

  uv run tests/live/docker_e2e.py [--image ghcr.io/home-assistant/home-assistant:<tag>] [--keep]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import websockets
import yaml

ROOT = Path(__file__).resolve().parents[2]
RUN_DIR = Path(__file__).resolve().parent / ".run"
NAME, PORT = "halean-e2e", 18123
BASE = f"http://127.0.0.1:{PORT}"
WS_URL = f"ws://127.0.0.1:{PORT}/api/websocket"

CONFIGURATION = """
homeassistant:
  name: HALean e2e
  time_zone: UTC
  unit_system: metric
http:
input_boolean:
  a:
  b:
  c:
  d:
"""

# Automations run by the Lean engine through the bridge (HA itself has none).
AUTOMATIONS = [
    {"id": "copy_a_to_b", "alias": "copy a to b",
     "triggers": [{"trigger": "state", "entity_id": "input_boolean.a", "to": "on"}],
     "actions": [{"action": "input_boolean.turn_on", "target": {"entity_id": "input_boolean.b"}},
                 {"event": "halean_done", "event_data": {"step": "copy"}}]},
    {"id": "error_then_continue", "alias": "error then continue",
     "triggers": [{"trigger": "state", "entity_id": "input_boolean.c", "to": "on"}],
     "actions": [{"action": "nope.missing_service", "continue_on_error": True},
                 {"action": "input_boolean.turn_off", "target": {"entity_id": "input_boolean.a"}}]},
    {"id": "held_for_2s", "alias": "held for 2s",
     "triggers": [{"trigger": "state", "entity_id": "input_boolean.c", "to": "on", "for": {"seconds": 2}}],
     "actions": [{"action": "input_boolean.turn_on", "target": {"entity_id": "input_boolean.d"}}]},
]


def pinned_image() -> str:
    """The Home Assistant release the translation is pinned to (manifest.yaml)."""
    tag = yaml.safe_load((ROOT / "manifest.yaml").read_text())["upstream"].get("tag")
    if not tag:
        raise SystemExit("manifest.yaml has no upstream tag; pass --image")
    return f"ghcr.io/home-assistant/home-assistant:{tag}"


def sh(*args: str, check: bool = True) -> str:
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout.strip()


def http(method: str, path: str, data: dict | None = None, form: bool = False) -> dict:
    body = None
    headers = {}
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read() or b"{}")


def start_container(image: str) -> None:
    sh("docker", "rm", "-f", NAME, check=False)
    if RUN_DIR.exists():
        shutil.rmtree(RUN_DIR)
    (RUN_DIR / "config").mkdir(parents=True)
    (RUN_DIR / "config" / "configuration.yaml").write_text(CONFIGURATION)
    sh("docker", "run", "-d", "--name", NAME, "-p", f"127.0.0.1:{PORT}:8123",
       "-v", f"{RUN_DIR / 'config'}:/config", image)
    for _ in range(120):
        try:
            http("GET", "/api/onboarding")
            return
        except Exception:
            time.sleep(1)
    raise SystemExit("Home Assistant did not start:\n" + sh("docker", "logs", "--tail", "40", NAME))


def onboard() -> str:
    """Create the owner user of this throwaway instance and return an access token."""
    client_id = f"{BASE}/"
    password = secrets.token_urlsafe(24)  # never printed; dies with the container
    code = http("POST", "/api/onboarding/users", {
        "client_id": client_id, "name": "halean", "username": "halean",
        "password": password, "language": "en"})["auth_code"]
    tok = http("POST", "/auth/token", {"grant_type": "authorization_code", "code": code,
                                       "client_id": client_id}, form=True)
    return tok["access_token"]


class Client:
    """Minimal HA WebSocket client for driving and observing the test."""

    def __init__(self, ws) -> None:
        self.ws, self.next_id = ws, 1
        self.pending: dict[int, asyncio.Future] = {}
        self.events: asyncio.Queue = asyncio.Queue()

    async def call(self, payload: dict) -> dict:
        i, self.next_id = self.next_id, self.next_id + 1
        fut = asyncio.get_running_loop().create_future()
        self.pending[i] = fut
        await self.ws.send(json.dumps({"id": i, **payload}))
        return await fut

    async def reader(self) -> None:
        async for raw in self.ws:
            m = json.loads(raw)
            if m.get("type") == "result" and m["id"] in self.pending:
                self.pending.pop(m["id"]).set_result(m)
            elif m.get("type") == "event":
                await self.events.put(m["event"])

    async def state(self, eid: str) -> str:
        states = (await self.call({"type": "get_states"}))["result"]
        return next(s["state"] for s in states if s["entity_id"] == eid)

    async def wait_state(self, eid: str, want: str, timeout: float) -> float:
        t0 = time.monotonic()
        while time.monotonic() - t0 < timeout:
            if await self.state(eid) == want:
                return time.monotonic() - t0
            await asyncio.sleep(0.1)
        raise AssertionError(f"{eid} did not become {want} within {timeout}s")


async def run_test(token: str) -> list[str]:
    results = []
    auto_file = RUN_DIR / "automations.json"
    auto_file.write_text(json.dumps(AUTOMATIONS))
    env = {**os.environ, "HA_URL": WS_URL, "HA_TOKEN": token}
    log = open(RUN_DIR / "bridge.log", "w")
    bridge = subprocess.Popen(["uv", "run", str(ROOT / "bridge" / "bridge.py"), str(auto_file)],
                              env=env, stdout=log, stderr=subprocess.STDOUT)
    try:
        async with websockets.connect(WS_URL) as ws:
            await ws.recv()
            await ws.send(json.dumps({"type": "auth", "access_token": token}))
            assert json.loads(await ws.recv())["type"] == "auth_ok"
            c = Client(ws)
            reader = asyncio.create_task(c.reader())
            await c.call({"type": "subscribe_events", "event_type": "halean_done"})
            await asyncio.sleep(6)  # let the bridge start and subscribe

            async def turn(service: str, eid: str) -> None:
                r = await c.call({"type": "call_service", "domain": "input_boolean",
                                  "service": service, "target": {"entity_id": eid}})
                assert r["success"], r

            # 1. state trigger -> service call -> event action
            await turn("turn_on", "input_boolean.a")
            dt = await c.wait_state("input_boolean.b", "on", 10)
            ev = await asyncio.wait_for(c.events.get(), 5)
            assert ev["data"] == {"step": "copy"}, ev
            results.append(f"PASS state trigger -> input_boolean.b on in {dt:.2f}s, event fired")

            # 2. failing service with continue_on_error, then the next action runs
            await turn("turn_on", "input_boolean.c")
            dt = await c.wait_state("input_boolean.a", "off", 10)
            results.append(f"PASS continue_on_error past a missing service -> a off in {dt:.2f}s")

            # 3. `for: 2s` on the real clock (timer driven by the bridge's ticks)
            assert await c.state("input_boolean.d") == "off"
            await asyncio.sleep(1.0)
            assert await c.state("input_boolean.d") == "off", "fired before 2s"
            dt = await c.wait_state("input_boolean.d", "on", 5)
            results.append(f"PASS for: 2s fired after ~{1.0 + dt:.1f}s (not before 1s)")
            reader.cancel()
    finally:
        bridge.terminate()
        bridge.wait(10)
        log.close()
    return results


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--image", help="default: the release pinned in manifest.yaml")
    p.add_argument("--keep", action="store_true", help="leave the container running afterwards")
    args = p.parse_args()

    if not (ROOT / ".lake" / "build" / "bin" / "halean-automation").exists():
        raise SystemExit("build the engine first: lake build")
    start_container(args.image or pinned_image())
    try:
        token = onboard()
        version = sh("docker", "exec", NAME, "python3", "-c",
                     "import homeassistant.const as c; print(c.__version__)")
        print(f"Home Assistant {version} in container {NAME}")
        results = asyncio.run(run_test(token))
        print("\n".join(results))
        print(f"\n{len(results)}/3 live checks passed")
        return 0 if len(results) == 3 else 1
    except Exception as e:
        print(f"FAIL: {e}\n--- bridge log ---")
        print((RUN_DIR / "bridge.log").read_text() if (RUN_DIR / "bridge.log").exists() else "")
        return 1
    finally:
        if not args.keep:
            sh("docker", "rm", "-f", NAME, check=False)


if __name__ == "__main__":
    sys.exit(main())
