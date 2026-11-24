"""Build real probatio schemas from the YAML schema specs the service tests
share with HALean (`HALean/Core/ServicesJson.lean` documents the format).

A spec is `{fields: [<field>, ...], extra: prevent|allow|remove}`; a field is
`{key, type}` or `{key, value: <validator>}` with `required`, `default`,
`exclusive` (+ `group_required`) or `inclusive`. Validators are built from
the real probatio classes and HA's `config_validation` objects, so a `cv.*`
name here is the very object HA's own schemas use.
"""

from __future__ import annotations

import copy
from datetime import timedelta

import probatio

import homeassistant.helpers.config_validation as cv

TYPES = {"int": int, "float": float, "str": str, "bool": bool, "any": object,
         "object": object, "list": list, "dict": dict, "timedelta": timedelta}
EXTRA = {"prevent": probatio.PREVENT_EXTRA, "allow": probatio.ALLOW_EXTRA,
         "remove": probatio.REMOVE_EXTRA}
CV = {"string", "boolean", "entity_id", "entity_ids", "color_hex", "slug", "positive_int",
      "positive_float", "small_float", "byte", "port", "ensure_list", "comp_entity_ids",
      "time_period", "time_period_str", "time_period_seconds", "time_period_dict",
      "positive_time_period", "positive_time_period_dict"}


def make_validator(spec):
    if isinstance(spec, str):
        return TYPES[spec]
    (name, arg), *_ = spec.items()
    match name:
        case "type":
            return make_validator(arg)
        case "literal":
            return arg
        case "dict":
            return make_fields(arg)
        case "list":
            return [make_validator(v) for v in arg]
        case "all":
            return probatio.All(*(make_validator(v) for v in arg))
        case "any":
            return probatio.Any(*(make_validator(v) for v in arg))
        case "in":
            return probatio.In(list(arg))
        case "not_in":
            return probatio.NotIn(list(arg))
        case "range":
            return probatio.Range(**arg)
        case "clamp":
            return probatio.Clamp(**arg)
        case "length":
            return probatio.Length(**arg)
        case "coerce":
            return probatio.Coerce({"int": int, "float": float, "str": str}[arg])
        case "lower":
            return probatio.Lower
        case "upper":
            return probatio.Upper
        case "ensure_list":
            return probatio.EnsureList()
        case "port":
            return probatio.Port()
        case "at_least_one":
            return probatio.AtLeastOne(*arg)
        case "cv":
            if arg == "entity_domain":
                return cv.entity_domain(spec["domain"])
            assert arg in CV, arg
            return getattr(cv, arg)
    raise AssertionError(f"unknown validator {spec}")


def make_fields(fields: list) -> dict:
    out = {}
    for f in fields:
        kw = {"default": copy.deepcopy(f["default"])} if "default" in f else {}
        if "exclusive" in f:
            key = probatio.Exclusive(f["key"], f["exclusive"],
                                     required=f.get("group_required", False), **kw)
        elif "inclusive" in f:
            key = probatio.Inclusive(f["key"], f["inclusive"], **kw)
        elif f.get("required"):
            key = probatio.Required(f["key"], **kw)
        else:
            key = probatio.Optional(f["key"], **kw)
        out[key] = make_validator(f["type"] if "type" in f else f["value"])
    return out


def make_schema(spec: dict | None):
    if spec is None:
        return None
    return probatio.Schema(make_fields(spec["fields"]), extra=EXTRA[spec.get("extra", "prevent")])
