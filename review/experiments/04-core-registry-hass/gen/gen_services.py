#!/usr/bin/env python3
"""Seeded random generator of service-registry cases (format of tests/core/services/*.yaml).

    python gen_services.py --seed 11 --count 400 --out DIR [--engine PATH]

Writes DIR/random_services_<seed>.yaml and DIR/random_services_<seed>.summary.json.

Each case is a sequence of register / remove / has / supports_response / list /
list_domain / call operations over a small pool of mixed-case names, with
random handler specs, `supports_response` values, schemas (plain types,
Coerce, In, defaults, required keys, the three extra policies), data, targets
and contexts. Like gen_core.py, the candidate is run through the engine first
and an operation it answers `unsupported` is marked `unsupported: true`
(counted per reason in the summary); nothing else is taken from the engine.
"""
from __future__ import annotations

import argparse
import json
import random
import subprocess
from pathlib import Path

import yaml

DOMAINS = ["test_a", "test_b", "Test_A", "TEST_B", "test c", "test_a"]
SERVICES = ["one", "Two", "THREE", "four.x", "one", "two"]
EXC = ["HomeAssistantError", "ServiceValidationError", "Invalid", "ValueError", "RuntimeError"]
VALUES = [1, 0, -3, 2.5, 0.1, 1.0e16, -0.0, True, False, None, "x", "", "It's", 'say "hi"', "7", "1.5",
          [1, "a"], [], {"z": 1, "a": [2]}, {}, [[1], {"k": None}], 12345678901234567890]
SCHEMAS = [
    {"fields": [{"key": "n", "type": "int"}]},
    {"fields": [{"key": "n", "type": "int"}], "extra": "allow"},
    {"fields": [{"key": "n", "value": {"coerce": "int"}, "default": 7}], "extra": "remove"},
    {"fields": [{"key": "k", "type": "str", "required": True}, {"key": "n", "type": "float"}]},
    {"fields": [{"key": "mode", "value": {"in": ["a", "b", 1]}, "default": "a"}, {"key": "flag", "type": "bool"}],
     "extra": "allow"},
    {"fields": []},
    {"fields": [{"key": "name", "value": {"all": ["str", {"length": {"min": 1, "max": 3}}]}},
                {"key": "list", "value": {"list": ["int"]}}]},
    {"fields": [{"key": "s", "value": {"coerce": "str"}}, {"key": "f", "value": {"coerce": "float"}}],
     "extra": "remove"},
]
KEYS = ["n", "k", "name", "list", "mode", "flag", "s", "f", "entity_id", "other"]


def gen_dict(rng: random.Random):
    r = rng.random()
    if r < 0.3:
        return None
    if r < 0.38:
        return {}
    return {k: rng.choice(VALUES) for k in rng.sample(KEYS, rng.randint(1, 4))}


def gen_op(rng: random.Random) -> dict:
    x = rng.random()
    d, s = rng.choice(DOMAINS), rng.choice(SERVICES)
    if rng.random() < 0.15:
        d = rng.choice([d.upper(), d.lower(), d.swapcase()])
    if rng.random() < 0.15:
        s = rng.choice([s.upper(), s.lower(), s.swapcase(), "missing"])
    if x < 0.28:
        r = rng.random()
        if r < 0.4:
            h = {"return": rng.choice([{"v": 1}, {"b": 2, "a": [1, 2.0]}, {}, None, [1], "s", 3, 1.5, False,
                                         {"n": {"m": [None, True]}}])}
        elif r < 0.75:
            h = {"echo": True}
        else:
            h = {"raise": rng.choice(EXC)}
            if rng.random() < 0.85:
                h["message"] = rng.choice(["boom", "it's bad", "x.", "", "a {domain} b"])
        op = {"op": "register", "domain": d, "service": s, "handler": h}
        r = rng.random()
        if r < 0.4:
            op["supports_response"] = "optional"
        elif r < 0.6:
            op["supports_response"] = "only"
        elif r < 0.65:
            op["supports_response"] = "none"
        if rng.random() < 0.35:
            op["schema"] = rng.choice(SCHEMAS)
        return op
    if x < 0.36:
        return {"op": "remove", "domain": d, "service": s}
    if x < 0.41:
        return {"op": "has", "domain": d, "service": s}
    if x < 0.46:
        return {"op": "supports_response", "domain": d, "service": s}
    if x < 0.50:
        return {"op": "list"}
    if x < 0.54:
        return {"op": "list_domain", "domain": d}
    op = {"op": "call", "domain": d, "service": s}
    data = gen_dict(rng)
    if data is not None:
        op["data"] = data
    if rng.random() < 0.3:
        t = gen_dict(rng)
        if t is not None:
            op["target"] = t
    if rng.random() < 0.6:
        op["blocking"] = True
    if rng.random() < 0.4:
        op["return_response"] = True
    r = rng.random()
    if r < 0.3:
        c = {"id": f"ctx-{rng.randint(1, 99)}"}
        if rng.random() < 0.4:
            c["user_id"] = rng.choice(["user-1", None])
        if rng.random() < 0.3:
            c["parent_id"] = "parent-1"
        op["context"] = c
    return op


def prescreen(case: dict, engine_path: str, reasons: dict) -> None:
    p = subprocess.Popen([engine_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    for i, op in enumerate(case["ops"]):
        p.stdin.write(json.dumps({**op, "now": 1795192245000 + 1000 * i}) + "\n")
        p.stdin.flush()
        out = json.loads(p.stdout.readline())
        if "unsupported" in out:
            op["unsupported"] = True
            reasons[out["unsupported"]] = reasons.get(out["unsupported"], 0) + 1
    p.stdin.close()
    p.wait()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--count", type=int, default=400)
    ap.add_argument("--out", required=True)
    ap.add_argument("--engine", default="/home/user/halean/.lake/build/bin/halean-core-services")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    cases, reasons = [], {}
    for i in range(a.count):
        ops = [gen_op(rng) for _ in range(rng.randint(8, 20))]
        # start with two registrations so calls usually find something
        ops[0] = {"op": "register", "domain": "test_a", "service": "one", "handler": {"echo": True},
                  "supports_response": "optional"}
        case = {"name": f"rs{a.seed}_{i + 1}", "ops": ops}
        prescreen(case, a.engine, reasons)
        cases.append(case)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"random_services_{a.seed}.yaml").write_text(
        f"# generated by gen_services.py --seed {a.seed} --count {a.count}\n"
        + yaml.safe_dump(cases, default_flow_style=None, width=250, sort_keys=False))
    summary = {"seed": a.seed, "cases": len(cases), "operations": sum(len(c["ops"]) for c in cases),
               "operations_marked_unsupported": sum(1 for c in cases for o in c["ops"] if o.get("unsupported")),
               "engine_reasons (unsupported operations)": dict(sorted(reasons.items(), key=lambda kv: -kv[1]))}
    (out / f"random_services_{a.seed}.summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
