"""Demo container entrypoint: get an access token for the demo Home Assistant,
then hand over to the bridge.

On the very first start the HA instance is fresh, so this onboards it: it
creates the `demo` user with a random password (written to .run/login.txt next to docker-compose.yml
on the host, never printed), finishes the remaining onboarding steps and
creates a long-lived access token (.run/token) for the bridge and the
simulator. Later starts just reuse the token.

  python demo/setup.py [--then-bridge]
"""

from __future__ import annotations

import asyncio
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import websockets

HTTP = os.environ.get("HA_HTTP", "http://homeassistant:8123")
WS = os.environ.get("HA_URL", "ws://homeassistant:8123/api/websocket")
PORT = os.environ.get("DEMO_PORT", "8124")
SHARED = Path("/shared")
TOKEN_FILE = SHARED / "token"
STATUS_ENTITY = "input_text.halean_status"
# The browser-facing address doubles as the OAuth client id.
CLIENT_ID = f"http://localhost:{PORT}/"


def http(method: str, path: str, data: dict | None = None, token: str | None = None,
         form: bool = False) -> dict | list:
    headers = {}
    body = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(HTTP + path, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
    return json.loads(raw) if raw else {}


def onboarding_steps() -> list:
    """The onboarding steps; HA removes the endpoint (404) once it is done."""
    try:
        return http("GET", "/api/onboarding")  # type: ignore[return-value]
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return [{"step": s, "done": True}
                    for s in ("user", "core_config", "analytics", "integration")]
        raise


def wait_for_ha() -> list:
    print(f"waiting for Home Assistant at {HTTP} ...", flush=True)
    for _ in range(600):
        try:
            return onboarding_steps()
        except Exception:
            time.sleep(1)
    raise SystemExit("Home Assistant did not come up")


async def long_lived_token(access_token: str) -> str:
    async with websockets.connect(WS) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": access_token}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        await ws.send(json.dumps({"id": 1, "type": "auth/long_lived_access_token",
                                  "client_name": "HALean bridge", "lifespan": 3650}))
        res = json.loads(await ws.recv())
        if not res.get("success"):
            raise SystemExit(f"could not create a token: {res}")
        return res["result"]


def onboard_user() -> str:
    password = secrets.token_urlsafe(9)
    code = http("POST", "/api/onboarding/users", {
        "client_id": CLIENT_ID, "name": "Demo", "username": "demo",
        "password": password, "language": "en"})["auth_code"]  # type: ignore[index]
    tok = http("POST", "/auth/token", {"grant_type": "authorization_code", "code": code,
                                       "client_id": CLIENT_ID}, form=True)
    access = tok["access_token"]  # type: ignore[index]
    # The integration step needs a login session token, not a long-lived one.
    finish_onboarding(onboarding_steps(), access)
    token = asyncio.run(long_lived_token(access))
    SHARED.mkdir(parents=True, exist_ok=True)
    (SHARED / "login.txt").write_text(
        f"HALean demo\n  URL:      http://localhost:{PORT}/halean-demo\n"
        f"  username: demo\n  password: {password}\n")
    TOKEN_FILE.write_text(token)
    print("onboarded the demo instance; login details are in .run/login.txt next to docker-compose.yml", flush=True)
    return token


def finish_onboarding(steps: list, token: str) -> None:
    done = {s["step"] for s in steps if s.get("done")}
    if "core_config" not in done:
        http("POST", "/api/onboarding/core_config", {}, token)
    if "analytics" not in done:
        http("POST", "/api/onboarding/analytics", {}, token)
    if "integration" not in done:
        try:
            http("POST", "/api/onboarding/integration",
                 {"client_id": CLIENT_ID, "redirect_uri": f"{CLIENT_ID}?auth_callback=1"}, token)
        except urllib.error.HTTPError as e:
            # HA marks the step done before it checks the token kind, so a
            # long-lived token gets 403 here but still completes onboarding.
            if e.code != 403:
                raise


def main() -> None:
    steps = wait_for_ha()
    user_done = any(s["step"] == "user" and s.get("done") for s in steps)
    if not user_done:
        token = onboard_user()
    elif TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text().strip()
    else:
        raise SystemExit("HA is already onboarded but .run/token is missing.\n"
                         "Start over with:  docker compose down -v && docker compose up -d")
    try:
        http("GET", "/api/", token=token)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"the saved token is not accepted ({e.code}). Start over with:\n"
                         "  docker compose down -v && docker compose up -d")
    finish_onboarding(onboarding_steps(), token)
    if "--then-bridge" in sys.argv:
        os.environ["HA_TOKEN"] = token
        os.execvp(sys.executable, [sys.executable, "bridge/bridge.py", "demo/automations.yaml",
                                   "--status-entity", STATUS_ENTITY])


if __name__ == "__main__":
    main()
