"""Shaping automations for the engine protocol (no dependencies, so the
test runners can import it too)."""

from __future__ import annotations

import json

_NESTED_SCRIPTS = ("then", "else", "sequence", "default", "parallel")


def _pairs(mapping):
    return [[k, v] for k, v in mapping.items()] if isinstance(mapping, dict) else mapping


def _order_actions(actions):
    for a in actions if isinstance(actions, list) else [actions]:
        if not isinstance(a, dict):
            continue
        if isinstance(a.get("variables"), dict):
            a["variables"] = _pairs(a["variables"])
        for key in _NESTED_SCRIPTS:
            if key in a:
                _order_actions(a[key])
        for opt in a.get("choose", []) or []:
            if isinstance(opt, dict):
                _order_actions(opt.get("sequence"))
        if isinstance(a.get("repeat"), dict):
            _order_actions(a["repeat"].get("sequence"))


def protocol_automations(automations: list) -> list:
    """Automations as the engine protocol expects them.

    JSON objects are unordered once parsed in Lean, but `variables` are
    rendered in the order they are written. So `variables` and
    `trigger_variables` mappings are sent as ordered [key, value] lists.
    """
    out = json.loads(json.dumps(automations))  # deep copy
    for auto in out:
        if not isinstance(auto, dict):
            continue
        for key in ("variables", "trigger_variables"):
            if key in auto:
                auto[key] = _pairs(auto[key])
        _order_actions(auto.get("actions", auto.get("action")))
    return out
