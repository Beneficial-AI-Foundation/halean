"""Differential test for the service registry: run every case in
tests/core/services/*.yaml on Home Assistant's own `hass.services`
(`homeassistant.core.ServiceRegistry`) and on `halean-core-services`, and
require, for every operation, the same

  * result (`repr()` of a call's response) or exception (class, `str()`,
    error kind, translation key and placeholders),
  * events fired on the bus (`service_registered`, `service_removed`,
    `call_service`: type, `repr()` of the data, time fired, context),
  * log records of `homeassistant.core` at warning level and above.

Handlers and schemas are built from the same specs on both sides. The clock is
frozen; operation i runs at t0 + i seconds. Contexts created by HA draw a
random ULID; those ids are compared structurally (written `new`).

Run:  uv run tests/differential/run.py -k services
"""

from __future__ import annotations

import copy
import json
import logging
import re
import subprocess
from datetime import UTC, datetime, timedelta
from importlib.metadata import version
from pathlib import Path

import probatio
import pytest
import yaml
from freezegun.api import FrozenDateTimeFactory

from homeassistant.core import Context, HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers.translation import async_load_integrations

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = [c for f in sorted((ROOT / "tests" / "core" / "services").glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-core-services"
T0 = datetime(2026, 11, 20, 16, 30, 45, tzinfo=UTC)
EVENTS = {"service_registered", "service_removed", "call_service"}
ULID = re.compile(r"\b[0-9A-HJKMNP-TV-Z]{26}\b")

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


def _fresh(s: str) -> str:
    """HA's random context ids (ULIDs) compare as `new`."""
    return ULID.sub("new", s)


def make_handler(spec: dict):
    if "raise" in spec:
        async def handler(call: ServiceCall):
            raise EXCEPTIONS[spec["raise"]](spec.get("message", ""))
    elif spec.get("echo"):
        async def handler(call: ServiceCall):
            return {"domain": call.domain, "service": call.service, "data": dict(call.data),
                    "return_response": call.return_response, "context_id": call.context.id}
    else:
        async def handler(call: ServiceCall):
            return copy.deepcopy(spec["return"])
    return handler


def make_schema(spec: dict | None):
    if spec is None:
        return None
    fields = {}
    for f in spec["fields"]:
        marker = probatio.Required if f.get("required") else probatio.Optional
        kw = {"default": copy.deepcopy(f["default"])} if "default" in f else {}
        fields[marker(f["key"], **kw)] = TYPES[f["type"]]
    return probatio.Schema(fields, extra=EXTRA[spec.get("extra", "prevent")])


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


def services_list(svcs: dict) -> list:
    return [[s, svc.supports_response.value, svc.schema is not None] for s, svc in svcs.items()]


async def run_ha(hass: HomeAssistant, op: dict, baseline: set[str]):
    """Run one operation on hass.services; return the result (JSON-able)."""
    services = hass.services
    kind = op["op"]
    if kind == "register":
        services.async_register(op["domain"], op["service"], make_handler(op["handler"]),
                                make_schema(op.get("schema")),
                                SupportsResponse(op.get("supports_response", "none")))
        return None
    if kind == "remove":
        services.async_remove(op["domain"], op["service"])
        return None
    if kind == "has":
        return services.has_service(op["domain"], op["service"])
    if kind == "supports_response":
        return services.supports_response(op["domain"], op["service"]).value
    if kind == "list":
        return [[d, services_list(svcs)] for d, svcs in services.async_services().items()
                if d not in baseline]
    if kind == "list_domain":
        return services_list(services.async_services_for_domain(op["domain"]))
    if kind == "call":
        ctx = op.get("context")
        context = Context(id=ctx["id"], user_id=ctx.get("user_id"),
                          parent_id=ctx.get("parent_id")) if ctx else None
        r = await services.async_call(
            op["domain"], op["service"], copy.deepcopy(op.get("data")),
            op.get("blocking", False), context, copy.deepcopy(op.get("target")),
            op.get("return_response", False))
        return _fresh(repr(r))
    raise AssertionError(f"unknown op {kind}")


class _Records(logging.Handler):
    def __init__(self) -> None:
        super().__init__(logging.WARNING)
        self.records: list[logging.LogRecord] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)


def _log_dict(r: logging.LogRecord) -> dict:
    out = {"level": r.levelname.lower(), "message": _fresh(r.getMessage())}
    if r.exc_info and r.exc_info[1] is not None:
        out["exception"] = f"{type(r.exc_info[1]).__name__}: {r.exc_info[1]}"
    return out


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


def test_probatio_matches_pin() -> None:
    """Schemas are validated by probatio; the model follows the pinned version."""
    manifest = yaml.safe_load((ROOT / "manifest.yaml").read_text())
    assert manifest["upstream"].get("probatio") == version("probatio"), (
        f"harness runs probatio {version('probatio')} but manifest.yaml says "
        f"{manifest['upstream'].get('probatio')}; re-check HALean/Core/Probatio.lean")


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
async def test_services(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine,
                        case: dict) -> None:
    # the exception messages come from the homeassistant integration's strings
    await async_load_integrations(hass, {"homeassistant"})
    baseline = set(hass.services.async_services())

    # a fresh registry in the engine: remove what earlier cases left behind
    # (the engine process is shared by every case)
    engine_reset(engine)

    fired: list = []

    def on_event(event) -> None:
        if event.event_type in EVENTS:
            fired.append(event)

    for et in EVENTS:
        hass.bus.async_listen(et, on_event)
    records = _Records()
    core_logger = logging.getLogger("homeassistant.core")
    core_logger.addHandler(records)
    try:
        for i, op in enumerate(case["ops"]):
            now = T0 + timedelta(seconds=i)
            freezer.move_to(now)
            msg = {k: v for k, v in op.items() if k != "unsupported"}
            lean = engine({**msg, "now": int(now.timestamp() * 1000)})
            if op.get("unsupported"):
                assert "unsupported" in lean, f"op {i}: HALean should reject {op}, got {lean}"
                continue
            assert "unsupported" not in lean, f"op {i}: HALean rejected {op}: {lean}"
            assert op.get("domain", "x").lower() not in baseline

            fired.clear()
            records.records.clear()
            try:
                result = await run_ha(hass, op, baseline)
                ha: dict = {"ok": True, "result": result}
            except Exception as err:  # noqa: BLE001
                ha = {"ok": False, "error": error_dict(err)}
            await hass.async_block_till_done()
            ha["events"] = [
                {"event_type": e.event_type, "data": _fresh(repr(e.data)),
                 "time_fired": round(e.time_fired_timestamp * 1000),
                 "context": {"id": _fresh(e.context.id), "user_id": e.context.user_id,
                             "parent_id": e.context.parent_id}}
                for e in fired]
            ha["logs"] = [_log_dict(r) for r in records.records]
            assert lean == ha, f"op {i}: {op}\n  HA:     {ha}\n  HALean: {lean}"
    finally:
        core_logger.removeHandler(records)


def engine_reset(engine) -> None:
    listed = engine({"op": "list", "now": 0})["result"]
    for domain, services in listed:
        for service, *_ in services:
            engine({"op": "remove", "domain": domain, "service": service, "now": 0})
    assert engine({"op": "list", "now": 0})["result"] == []
