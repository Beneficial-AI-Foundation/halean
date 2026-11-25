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


def protocol_scripts(scripts: dict | None) -> list:
    """scripts.yaml (`object_id: config`) as the script service expects it:
    ordered [object_id, config] pairs, with `variables` mappings (the
    script's and those of `variables` actions) as ordered [key, value] lists."""
    out = []
    for key, cfg in json.loads(json.dumps(scripts or {})).items():  # deep copy
        if isinstance(cfg, dict):
            if isinstance(cfg.get("variables"), dict):
                cfg["variables"] = _pairs(cfg["variables"])
            _order_actions(cfg.get("sequence"))
        out.append([key, cfg])
    return out


_POST_METHODS = {"PATCH", "POST", "PUT", "TRACE", "DELETE"}


def _content_type(raw: str | None) -> tuple[str, dict]:
    """aiohttp's `parse_content_type` (`HeaderParser(EnsureOctetStream,
    policy=HTTP)`): the lower-cased media type, `application/octet-stream`
    when missing or malformed, and the parameters."""
    if raw is None:
        return "application/octet-stream", {}
    from email.message import EmailMessage
    from email.parser import HeaderParser
    from email.policy import HTTP

    class _EnsureOctetStream(EmailMessage):
        def get_content_type(self) -> str:
            ctype = self.get("content-type", "").lower().partition(";")[0].strip()
            return ctype if ctype.count("/") == 1 else "application/octet-stream"

    msg = HeaderParser(_EnsureOctetStream, policy=HTTP).parsestr(f"Content-Type: {raw}")
    return msg.get_content_type(), dict(msg.get_params(())[1:])


def webhook_input(webhook_id: str, method: str = "POST", headers: dict | None = None,
                  body: str = "", query: str = "", local: bool = True) -> dict:
    """A request to /api/webhook/<webhook_id> as the engine's `webhook` input:
    what `_handle_webhook` reads from aiohttp's `Request` (`text()`, `post()`,
    `query`), computed the way aiohttp does for a body sent as UTF-8.

    `query` is split with `urllib.parse.parse_qsl` (yarl's parser agrees on
    ordinary query strings). Multipart bodies are not supported."""
    from urllib.parse import parse_qsl

    hdrs = {k.lower(): v for k, v in (headers or {}).items()}
    raw_ct = hdrs.get("content-type")
    ctype, params = _content_type(raw_ct)
    charset = params.get("charset") or "utf-8"
    raw = body.encode("utf-8")
    data: list = []
    # `Request.post()`
    if method in _POST_METHODS and ctype in ("", "application/x-www-form-urlencoded",
                                             "multipart/form-data"):
        if ctype == "multipart/form-data":
            raise NotImplementedError("multipart webhook bodies are not supported")
        if raw:
            text = raw.rstrip().decode(charset)
            data = [list(p) for p in parse_qsl(text, keep_blank_values=True, encoding=charset)]
    return {"type": "webhook", "webhook_id": webhook_id, "method": method,
            "content_type": raw_ct, "body": raw.decode(charset),  # `Request.text()`
            "data": data, "query": [list(p) for p in parse_qsl(query, keep_blank_values=True)],
            "local": local}
