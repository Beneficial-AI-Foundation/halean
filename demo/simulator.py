"""Plays the people in the demo house so the Lean engine has something to do.

It only does what a person could do from the dashboard: walk through the
hallway, nudge the room temperature, switch a light on, press a button. It
never touches the devices the automations control on their behalf, except
the living room light a person switches on now and then.

The room cools while the heater is off and warms while it is on, so the
heater automations (Lean) keep the temperature cycling between 19 and 22 °C.

Turn it off from the dashboard: "Random activity simulator".
"""

from __future__ import annotations

import asyncio
import itertools
import json
import os
import random
import time
from pathlib import Path

import websockets

WS = os.environ.get("HA_URL", "ws://homeassistant:8123/api/websocket")
TOKEN_FILE = Path("/shared/token")


class HA:
    def __init__(self, ws) -> None:
        self.ws = ws
        self.ids = itertools.count(1)

    async def request(self, payload: dict) -> dict:
        i = next(self.ids)
        await self.ws.send(json.dumps({"id": i, **payload}))
        while True:  # no subscriptions, so only results arrive
            msg = json.loads(await self.ws.recv())
            if msg.get("id") == i:
                return msg

    async def states(self) -> dict[str, str]:
        res = await self.request({"type": "get_states"})
        return {s["entity_id"]: s["state"] for s in res["result"]}

    async def call(self, domain: str, service: str, entity_id: str, **data) -> None:
        await self.request({"type": "call_service", "domain": domain, "service": service,
                            "service_data": data, "target": {"entity_id": entity_id}})


async def run() -> None:
    while not TOKEN_FILE.exists():
        await asyncio.sleep(2)
    async with websockets.connect(WS) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN_FILE.read_text().strip()}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        ha = HA(ws)
        print("simulator running", flush=True)

        motion_until = 0.0
        next_motion = time.time() + 5
        next_temp = time.time() + 4
        next_person = time.time() + random.uniform(60, 120)
        while True:
            await asyncio.sleep(1)
            st = await ha.states()
            if st.get("input_boolean.simulator") != "on":
                continue
            now = time.time()

            # someone walks through the hallway for a few seconds
            if motion_until and now >= motion_until:
                await ha.call("input_boolean", "turn_off", "input_boolean.hallway_motion_raw")
                motion_until = 0.0
                next_motion = now + random.uniform(20, 45)
            elif not motion_until and now >= next_motion:
                await ha.call("input_boolean", "turn_on", "input_boolean.hallway_motion_raw")
                motion_until = now + random.uniform(3, 8)

            # the room cools, or warms while the heater runs
            if now >= next_temp:
                next_temp = now + 4
                try:
                    t = float(st.get("input_number.living_room_temperature_raw", "20"))
                except ValueError:
                    t = 20.0
                step = 0.5 if st.get("switch.heater") == "on" else -0.5
                if random.random() < 0.2:
                    step = -step
                t = min(26.0, max(14.0, t + step))
                await ha.call("input_number", "set_value",
                              "input_number.living_room_temperature_raw", value=t)

            # now and then a person does something
            if now >= next_person:
                next_person = now + random.uniform(60, 120)
                choice = random.choice(["light", "party", "good_night"])
                if choice == "light":
                    await ha.call("light", "turn_on", "light.living_room_light")
                else:
                    await ha.call("input_button", "press", f"input_button.{choice}")
                print(f"person: {choice}", flush=True)


if __name__ == "__main__":
    asyncio.run(run())
