"""Differential test for the Template service: render every case in
tests/templates/cases.yaml with Home Assistant's own `Template.async_render`
(or `condition.async_template`) and with `halean-template`, and require the
same result type and `repr()`, or an error from both.

Cases marked `unsupported: true` must be rejected by HALean at load time.

Run:  uv run tests/differential/run.py -k templates
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest
import yaml

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError, TemplateError
from homeassistant.helpers import condition
from homeassistant.helpers.template import Template

ROOT = Path(__file__).resolve().parent.parent.parent
CASES = yaml.safe_load((ROOT / "tests" / "templates" / "cases.yaml").read_text())
ENGINE = ROOT / ".lake" / "build" / "bin" / "halean-template"


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
async def test_template(hass: HomeAssistant, engine, case: dict) -> None:
    for s in case.get("states", []):
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
    variables = case.get("variables")
    parse = case.get("parse_result", True)
    is_cond = case.get("condition", False)

    lean = engine({"template": case["template"], "states": case.get("states", []),
                   "variables": variables or {}, "parse_result": parse, "condition": is_cond})
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

    if case.get("expect_error_in_halean_only"):
        # HA can print it, HALean refuses at render time instead of guessing
        assert ha["ok"] and not lean["ok"], f"HA: {ha}\nHALean: {lean}"
        return
    if ha["ok"]:
        assert lean == ha, f"HA: {ha}\nHALean: {lean}"
    else:
        assert not lean["ok"], f"HA raised {ha['error']!r}, HALean returned {lean}"
