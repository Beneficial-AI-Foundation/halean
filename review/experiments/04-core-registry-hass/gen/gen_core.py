#!/usr/bin/env python3
"""Seeded random generator of joined-core cases (format of tests/core/hass/*.yaml).

    python gen_core.py --seed 101 --count 400 --out DIR [--engine PATH]

Writes DIR/random_core_<seed>.yaml and DIR/random_core_<seed>.summary.json.

How the cases stay finite on both sides
---------------------------------------
* Every event type and every service has a rank. A script attached to rank r
  (a listener's `react` on an event of rank r, a handler's `do` for a service
  of rank r) only fires events and calls services of a higher rank. `set` /
  `remove` (which fire `state_changed`), `call` (which fires `call_service`)
  and `register` / `remove_service` (which fire `service_registered` /
  `service_removed`) are only generated below the rank of the event they fire.
  So no script can trigger itself, directly or through another script.
* The match-all listener `m` is passive (it only records).
* A coroutine may `wait` on a future. Whether a case can finish then depends on
  who resolves it. The generator does not decide that by itself: it runs the
  candidate case through the `halean-core` engine first (pre-screen):
    - an operation the engine answers `unsupported` gets `unsupported: true`
      (the shipped harness then skips it on HA as well); the reason is counted
      in the summary file, per reason;
    - if the `block_till_done` after an operation (or the final one of a
      `manual` case) is `unsupported` (HA would hang, or log in set order),
      the case is cut before that point.
  The pre-screen never looks at HA and never changes an answer; it only removes
  what the model itself says it cannot run. It does mean the generated file
  depends on the engine binary as well as on the seed.
"""
from __future__ import annotations

import argparse
import json
import random
import subprocess
from pathlib import Path

import yaml

NOW = 1795710645123456
EXC = ["HomeAssistantError", "ServiceValidationError", "Invalid", "ValueError", "RuntimeError"]
ENTITIES = ["sensor.a", "sensor.b", "light.c"]
FUTURES = ["f0", "f1", "f2"]
TERMINAL = ["t0", "t1"]
EVENTS = ["e0", "e1", "e2", "e3"]
SERVICES = ["s0", "s1", "s2"]
SPECIAL = ["state_changed", "call_service", "service_registered"]


class Gen:
    def __init__(self, rng: random.Random) -> None:
        self.rng = rng
        items = EVENTS + SERVICES + SPECIAL
        rng.shuffle(items)
        self.rank = {x: i for i, x in enumerate(items)}
        self.rank["service_removed"] = self.rank["service_registered"]
        for t in TERMINAL:
            self.rank[t] = 1000
        self.n = 0
        self.listener_ids: list[str] = []

    def uid(self, p: str) -> str:
        self.n += 1
        return f"{p}{self.n}"

    def case_name(self, s: str) -> str:
        return self.rng.choice([s, s, s, s.upper(), s.capitalize()])

    def ctx(self, in_script: bool):
        r = self.rng.random()
        if r < 0.45:
            return None
        if in_script and r < 0.8:
            return "inherit"
        c = {"id": self.uid("ctx-")}
        if self.rng.random() < 0.3:
            c["user_id"] = "user-1"
        if self.rng.random() < 0.2:
            c["parent_id"] = "parent-1"
        return c

    def data(self):
        r = self.rng.random()
        if r < 0.5:
            return None
        if r < 0.6:
            return {}
        d = {}
        for k in self.rng.sample(["n", "k", "name", "list", "nested"], self.rng.randint(1, 3)):
            d[k] = self.rng.choice([1, 0, -3, 2.5, True, None, "x", "It's", [1, "a"], {"z": 1, "a": [2]}])
        return d

    def higher_events(self, r: int) -> list[str]:
        return [e for e in EVENTS if self.rank[e] > r] + TERMINAL

    def higher_services(self, r: int) -> list[str]:
        return [s for s in SERVICES if self.rank[s] > r]

    # ---- actions -----------------------------------------------------------

    def fire(self, r: int, in_script: bool) -> dict:
        f = {"event_type": self.rng.choice(self.higher_events(r))}
        d = self.data()
        if d is not None:
            f["data"] = d
        c = self.ctx(in_script)
        if c is not None:
            f["context"] = c
        if self.rng.random() < 0.1:
            f["origin"] = "remote"
        return f

    def set_(self, in_script: bool) -> dict:
        s = {"entity_id": self.rng.choice(ENTITIES), "state": self.rng.choice(["on", "off", "1", "2"])}
        if self.rng.random() < 0.3:
            s["attributes"] = {"a": self.rng.randint(0, 2)}
        if self.rng.random() < 0.2:
            s["force_update"] = True
        c = self.ctx(in_script)
        if c is not None:
            s["context"] = c
        return s

    def call(self, r: int, in_script: bool, coroutine: bool) -> dict:
        svcs = self.higher_services(r)
        if svcs and self.rng.random() < 0.9:
            svc = self.rng.choice(svcs)
        else:
            svc = "missing"
        c = {"domain": self.case_name("test"), "service": self.case_name(svc)}
        if in_script:
            c = {"id": self.uid("c"), **c}
        d = self.data()
        if d is not None:
            c["data"] = d
        if self.rng.random() < 0.15:
            c["target"] = self.rng.choice([{}, {"entity_id": ["light.c"]}, {"n": 9, "area_id": "k"}])
        if self.rng.random() < 0.6:
            c["blocking"] = True
        if self.rng.random() < 0.3:
            c["return_response"] = True
        cx = self.ctx(in_script)
        if cx is not None:
            c["context"] = cx
        if in_script and coroutine and self.rng.random() < 0.6:
            c["catch"] = True
        return c

    def handler(self, svc: str) -> dict:
        h: dict = {}
        body = self.script(self.rank[svc], True)
        if body:
            h["do"] = body
        r = self.rng.random()
        if r < 0.3:
            h["return"] = self.rng.choice([{"v": 1}, {"b": 2, "a": [1, 2.0]}, {}, None, [1], "s", 3, 1.5, False])
        elif r < 0.5:
            h["echo"] = True
        elif r < 0.65:
            h["raise"] = self.rng.choice(EXC)
            if self.rng.random() < 0.8:
                h["message"] = self.rng.choice(["boom", "it's bad", "x."])
        return h

    def register(self, svc: str) -> dict:
        reg = {"domain": self.case_name("test"), "service": self.case_name(svc), "handler": self.handler(svc)}
        r = self.rng.random()
        if r < 0.35:
            reg["supports_response"] = "optional"
        elif r < 0.5:
            reg["supports_response"] = "only"
        elif r < 0.55:
            reg["supports_response"] = "none"
        if self.rng.random() < 0.12:
            reg["schema"] = self.rng.choice([
                {"fields": [{"key": "n", "type": "int"}], "extra": "allow"},
                {"fields": [{"key": "n", "value": {"coerce": "int"}, "default": 7}], "extra": "remove"},
                {"fields": [{"key": "k", "type": "str", "required": True}]},
            ])
        return reg

    def listen(self, event_type: str, lid: str | None = None) -> dict:
        is_async = self.rng.random() < 0.5
        lid = lid or (self.rng.choice(self.listener_ids) if self.listener_ids and self.rng.random() < 0.08
                      else self.uid("l"))
        if lid not in self.listener_ids:
            self.listener_ids.append(lid)
        spec: dict = {"id": lid, "event_type": event_type}
        if is_async:
            spec["async"] = True
        react = self.script(self.rank[event_type], is_async)
        if react:
            spec["react"] = react
        if self.rng.random() < 0.15:
            spec["react_times"] = self.rng.randint(0, 2)
        return spec

    def script(self, r: int, coroutine: bool, depth: int = 0) -> list:
        out = []
        for _ in range(self.rng.choice([0, 1, 1, 2, 2, 3, 3, 4])):
            a = self.action(r, coroutine, depth)
            if a is not None:
                out.append(a)
        return out

    def action(self, r: int, coroutine: bool, depth: int):
        rng = self.rng
        x = rng.random()
        if x < 0.24:
            return {"fire": self.fire(r, True)}
        if x < 0.40:
            if r < self.rank["call_service"]:
                return {"call": self.call(r, True, coroutine)}
            return {"fire": self.fire(r, True)}
        if x < 0.50:
            if r < self.rank["state_changed"]:
                if rng.random() < 0.85:
                    return {"set": self.set_(True)}
                return {"remove": {"entity_id": rng.choice(ENTITIES)}}
            return None
        if x < 0.56:
            if r < self.rank["service_registered"] and depth < 1:
                svcs = self.higher_services(r)
                if svcs:
                    if rng.random() < 0.6:
                        return {"register": self.register(rng.choice(svcs))}
                    return {"remove_service": {"domain": self.case_name("test"),
                                               "service": self.case_name(rng.choice(svcs + ["missing"]))}}
            return None
        if x < 0.62:
            if depth < 1:
                et = rng.choice(self.higher_events(r))
                key = "listen_once" if rng.random() < 0.3 else "listen"
                spec = self.listen(et)
                if key == "listen_once":
                    spec.pop("filter", None)
                return {key: spec}
            return None
        if x < 0.67:
            if self.listener_ids:
                return {"unsub": rng.choice(self.listener_ids + ["nope"])}
            return None
        if x < 0.73:
            a = {"raise": rng.choice(EXC)}
            if rng.random() < 0.8:
                a["message"] = rng.choice(["bad", "worse", ""])
            return a
        if x < 0.79:
            return {"resolve": rng.choice(FUTURES)}
        if coroutine:
            if x < 0.93:
                return {"sleep": 0}
            return {"wait": rng.choice(FUTURES)}
        return None

    # ---- top-level operations ------------------------------------------------

    def op(self, manual: bool) -> dict:
        rng = self.rng
        x = rng.random()
        if x < 0.24:
            et = rng.choice(EVENTS + EVENTS + SPECIAL + ["service_removed"] + TERMINAL)
            once = rng.random() < 0.2
            spec = self.listen(et)
            if not once and rng.random() < 0.12:
                spec["filter"] = rng.choice([True, False, {"has": "k"}, {"eq": {"n": 1}}])
            return {"op": "listen_once" if once else "listen", **spec}
        if x < 0.40:
            return {"op": "register", **self.register(rng.choice(SERVICES))}
        if x < 0.60:
            return {"op": "fire", **self.fire(-1, False)}
        if x < 0.76:
            return {"op": "call", **self.call(-1, False, False)}
        if x < 0.83:
            return {"op": "set", **self.set_(False)}
        if x < 0.85:
            return {"op": "remove", "entity_id": rng.choice(ENTITIES)}
        if x < 0.88:
            return {"op": "remove_service", "domain": self.case_name("test"),
                    "service": self.case_name(rng.choice(SERVICES))}
        if x < 0.91:
            if self.listener_ids:
                return {"op": "unsub", "id": rng.choice(self.listener_ids)}
            return {"op": "listeners"}
        if x < 0.95:
            return {"op": "resolve", "id": rng.choice(FUTURES)}
        if x < 0.97:
            return rng.choice([{"op": "listeners"}, {"op": "has", "domain": "Test", "service": rng.choice(SERVICES)},
                               {"op": "get", "entity_id": rng.choice(ENTITIES)}])
        if manual:
            return {"op": rng.choice(["sleep", "sleep", "block_till_done"])}
        return {"op": "fire", **self.fire(-1, False)}

    def case(self, name: str) -> dict:
        rng = self.rng
        manual = rng.random() < 0.5
        ops: list[dict] = [{"op": "listen", "id": "m", "event_type": "*"}]
        now = NOW
        for _ in range(rng.randint(6, 16)):
            o = self.op(manual)
            if manual and rng.random() < 0.25:
                ops.append(o)
                o = {"op": rng.choice(["sleep", "sleep", "block_till_done"])}
            if rng.random() < 0.2:
                now += rng.choice([1, 1000, 1500000, 60000000])
                o["now"] = now
            ops.append(o)
        c = {"name": name, "ops": ops}
        if manual:
            c = {"name": name, "manual": True, "ops": ops}
        return c


class Engine:
    def __init__(self, path: str) -> None:
        self.p = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        assert self.ask({"op": "init", "listeners": [], "now": 0})["result"] == {"ok": None}

    def ask(self, msg: dict) -> dict:
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def close(self) -> None:
        self.p.stdin.close()
        self.p.wait()


MAX_TRACE = 300


def prescreen(case: dict, engine_path: str, reasons: dict) -> dict | None:
    """Mark what the model rejects; cut the case where its block_till_done
    cannot return. Returns None if fewer than 4 operations are left."""
    manual = case.get("manual", False)
    ops = [dict(o) for o in case["ops"]]
    while len(ops) >= 4:
        eng = Engine(engine_path)
        now = NOW
        cut = None
        local: list[str] = []
        for i, op in enumerate(ops):
            op.pop("unsupported", None)
            now = op.get("now", now)
            lean = eng.ask({**op, "now": now})
            if "unsupported" in lean:
                op["unsupported"] = True
                local.append(lean["unsupported"])
                continue
            size = len(lean["trace"])
            if not manual:
                settle = eng.ask({"op": "block_till_done", "now": now})
                if "unsupported" in settle:
                    cut = (i, "cut: " + settle["unsupported"])
                    break
                size += len(settle["trace"])
            if size > MAX_TRACE:
                cut = (i, "cut: trace longer than %d" % MAX_TRACE)
                break
        if cut is None and manual:
            final = eng.ask({"op": "block_till_done", "now": now})
            if "unsupported" in final:
                cut = (len(ops) - 1, "cut: " + final["unsupported"])
        eng.close()
        if cut is None:
            for r in local:
                reasons[r] = reasons.get(r, 0) + 1
            out = {"name": case["name"]}
            if manual:
                out["manual"] = True
            out["ops"] = ops
            return out
        reasons[cut[1]] = reasons.get(cut[1], 0) + 1
        ops = ops[:cut[0]]
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--count", type=int, default=400)
    ap.add_argument("--out", required=True)
    ap.add_argument("--engine", default="/home/user/halean/.lake/build/bin/halean-core")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    cases, reasons, dropped, tried = [], {}, 0, 0
    while len(cases) < a.count:
        tried += 1
        c = Gen(rng).case(f"r{a.seed}_{tried}")
        c = prescreen(c, a.engine, reasons)
        if c is None:
            dropped += 1
            continue
        cases.append(c)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"random_core_{a.seed}.yaml").write_text(
        f"# generated by gen_core.py --seed {a.seed} --count {a.count}\n"
        + yaml.safe_dump(cases, default_flow_style=None, width=250, sort_keys=False))
    n_ops = sum(len(c["ops"]) for c in cases)
    n_uns = sum(1 for c in cases for o in c["ops"] if o.get("unsupported"))
    summary = {"seed": a.seed, "cases": len(cases), "candidates": tried, "dropped": dropped,
               "manual_cases": sum(1 for c in cases if c.get("manual")),
               "operations": n_ops, "operations_marked_unsupported": n_uns,
               "engine_reasons (unsupported operations and cuts)": dict(sorted(reasons.items(), key=lambda kv: -kv[1]))}
    (out / f"random_core_{a.seed}.summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
