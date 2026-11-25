"""Differential test for the Template service: render every case in
tests/templates/*.yaml with Home Assistant's own `Template.async_render`
(or `condition.async_template`) and with `halean-template`, and require the
same result type and `repr()`, or an error from both.

Cases marked `unsupported: true` must be rejected by HALean at load time.
Cases marked `render_info: true` also compare what the render read
(`async_render_to_info`: entities, domains, all states).

Run:  uv run tests/differential/run.py -k templates
"""

from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
import yaml

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError, TemplateError
from homeassistant.helpers import condition
from homeassistant.helpers.template import Template
from homeassistant.util import dt as dt_util
from freezegun.api import FrozenDateTimeFactory

import os

# REVIEW COPY: only the case directory and the engine path differ from the shipped file.
HERE = Path(__file__).resolve().parent.parent
CASES = [c for f in sorted((HERE / "cases").glob("*.yaml"))
         for c in yaml.safe_load(f.read_text()) or []]
ENGINE = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")) / "halean-template"
# The clock for every case: millisecond precision, like the engine's clock.
# The test instance of HA runs in US/Pacific.
NOW = datetime(2026, 11, 20, 16, 30, 45, 123000, tzinfo=UTC)
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)


def _us(d: datetime) -> int:
    return (d - EPOCH) // timedelta(microseconds=1)


def _typename(v) -> str:
    for kls in (bool, int, float, str, type(None), tuple, list, dict, set):
        if isinstance(v, kls):
            return kls.__name__
    return type(v).__name__


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


def _case_id(c: dict) -> str:
    return c.get("name") or c["template"][:40]


@pytest.mark.parametrize("case", CASES, ids=[_case_id(c) for c in CASES])
async def test_template(hass: HomeAssistant, freezer: FrozenDateTimeFactory, engine,
                        case: dict) -> None:
    freezer.move_to(datetime.fromisoformat(case["now"]) if "now" in case else NOW)
    states = []
    for s in case.get("states", []):
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
        st = hass.states.get(s["entity_id"])
        states.append({**s, "last_changed_us": _us(st.last_changed),
                       "last_updated_us": _us(st.last_updated)})
    variables = case.get("variables")
    parse = case.get("parse_result", True)
    is_cond = case.get("condition", False)

    lean = engine({"template": case["template"], "states": states,
                   "variables": variables or {}, "parse_result": parse, "condition": is_cond,
                   "info": bool(case.get("render_info")),
                   "now": _us(dt_util.utcnow()) // 1000,
                   "tz": int(dt_util.now().utcoffset().total_seconds())})
    if case.get("unsupported"):
        assert "unsupported" in lean, f"HALean should reject this template, got {lean}"
        return
    assert "unsupported" not in lean, f"HALean rejected a supported template: {lean['unsupported']}"

    tpl = Template(case["template"], hass)
    try:
        if is_cond:
            r = condition.async_template(hass, tpl, variables)
        else:
            r = tpl.async_render(variables, parse_result=parse)
        ha = {"ok": True, "type": _typename(r), "repr": repr(r)}
    except (TemplateError, HomeAssistantError) as err:
        ha = {"ok": False, "error": str(err)}

    if case.get("render_info"):
        # what the render read must match too (template triggers depend on it)
        info = tpl.async_render_to_info(variables)
        want = {"entities": sorted(info.entities), "domains": sorted(info.domains),
                "domains_lifecycle": sorted(info.domains_lifecycle),
                "all_states": info.all_states, "all_states_lifecycle": info.all_states_lifecycle}
        assert lean.pop("info") == want, f"render info differs: HA {want}"
    lean.pop("info", None)

    if case.get("expect_error_in_halean_only"):
        # HA can print it, HALean refuses at render time instead of guessing
        assert ha["ok"] and not lean["ok"], f"HA: {ha}\nHALean: {lean}"
        return
    if ha["ok"]:
        assert lean == ha, f"HA: {ha}\nHALean: {lean}"
    else:
        assert not lean["ok"], f"HA raised {ha['error']!r}, HALean returned {lean}"
