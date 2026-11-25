#!/opt/havenv/bin/python
"""Seeded random scenario generator for the automation engine (review area 07).

    gen_scenarios.py --seed N --count K --out DIR [--engine PATH]

Writes K scenarios `r<seed>_<i>.yaml` in the shipped format (automations, states,
steps). Each scenario has 1-3 random automations from the subset README.md lists
as supported (random triggers, optional conditions, a small random action tree
whose service calls / events carry distinct names and data as markers) and a
random input stream (state changes over a small entity/value pool, ticks, events,
service results including errors).

`expect` blocks are not written: the differential harness compares HA with the
engine directly. The engine binary is only used while generating, to find out
which service calls are open, so that `service_result` steps answer calls that
exist (the shipped harness indexes its list of futures with `call_id`).

Things the generator avoids on purpose, because the shipped harness cannot
compare them (see FINDINGS.md, "Notes on the harness"):
  * actions firing events that are also trigger events (the engine does not feed
    its own events back; HA does),
  * fractional delays / timeouts (the harness fires HA timers up to 0.5 s early),
  * more than one time-driven trigger per scenario (HA's order among timers due
    in the same second is the heap order of the event loop),
  * time patterns that match the second the scenario starts at (AUT-9),
  * `wait.remaining` after a wait was woken (documented in README.md),
  * templated service names (the harness registers only static names).
"""
from __future__ import annotations

import argparse
import json
import random
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path("/home/user/halean")
sys.path.insert(0, str(REPO / "tests"))
sys.path.insert(0, str(REPO / "bridge"))
import run_scenarios  # noqa: E402

SENSORS = ["sensor.s1", "sensor.s2"]
LIGHTS = ["light.l1", "light.l2"]
BOOLS = ["input_boolean.b1"]
NUM_VALUES = ["1", "4", "8", "12", "20", "unknown", "unavailable", "abc", "7.5"]
ONOFF = ["on", "off", "unavailable"]
EVENTS = ["e1", "e2", "e3"]
T0_SEC = 20  # T0 is 22:13:20 UTC


class Gen:
    def __init__(self, rnd: random.Random):
        self.r = rnd
        self.marker = 0
        self.time_trigger_used = False
        self.varn = 0

    # ---- helpers
    def pick(self, xs):
        return self.r.choice(xs)

    def chance(self, p):
        return self.r.random() < p

    def entity(self):
        return self.pick(SENSORS + LIGHTS + BOOLS)

    def values_for(self, eid):
        return NUM_VALUES if eid.startswith("sensor.") else ONOFF

    def next_marker(self):
        self.marker += 1
        return self.marker

    # ---- templates
    def bool_template(self, in_run: bool):
        opts = [
            "{{ is_state('light.l1', 'on') }}",
            "{{ is_state('light.l2', 'off') }}",
            "{{ states('sensor.s1') | int(0) > %d }}" % self.pick([3, 7, 10]),
            "{{ states('sensor.s2') | float(0) < %d }}" % self.pick([5, 9, 15]),
            "{{ is_state('input_boolean.b1', 'on') and is_state('light.l1', 'on') }}",
            "{{ states('sensor.s1') == states('sensor.s2') }}",
            "{{ states('sensor.s1') | int > 5 }}",  # raises for non-numeric states
        ]
        if in_run:
            opts += [
                "{{ trigger.platform == 'event' }}",
                "{{ trigger.id == '0' }}",
                "{{ trigger.platform in ['state', 'numeric_state'] }}",
            ]
        return self.pick(opts)

    def value_template(self):
        return self.pick([
            "{{ trigger.platform }}", "{{ trigger.id }}", "{{ states('sensor.s1') }}",
            "{{ states('light.l1') }}", "{{ trigger.idx }}", "{{ this.attributes.current }}",
            "{{ states('sensor.s2') | int(0) + 1 }}", "{{ trigger.description }}",
            "{{ now().second }}", "{{ [states('light.l1'), states('light.l2')] }}",
        ])

    # ---- triggers
    def period(self):
        return self.pick([1, 2, 3, "00:00:02", {"seconds": 2}, "{{ 2 }}", {"seconds": "{{ 1 + 1 }}"}])

    def trigger(self, in_wait=False):
        kinds = ["state", "state", "numeric_state", "template", "event", "event"]
        if not in_wait and not self.time_trigger_used:
            kinds += ["time_pattern", "time"]
        k = self.pick(kinds)
        t: dict = {"trigger": k}
        if k == "state":
            eid = self.entity()
            t["entity_id"] = eid if self.chance(0.8) else [eid, self.entity()]
            vals = self.values_for(eid)
            for key in self.r.sample(["from", "to"], k=self.pick([0, 1, 1, 2])):
                neg = self.chance(0.25)
                v = self.pick(vals) if self.chance(0.7) else self.r.sample(vals, 2)
                t[("not_" + key) if neg else key] = v
            if self.chance(0.15):
                t["attribute"] = "lvl"
                for key in ("from", "to", "not_from", "not_to"):
                    if key in t:
                        t[key] = self.pick([1, 2, 3])
            if self.chance(0.25):
                t["for"] = self.period()
        elif k == "numeric_state":
            t["entity_id"] = self.pick(SENSORS)
            lo, hi = self.pick([(3, None), (None, 10), (3, 10), (6, 15)])
            if lo is not None:
                t["above"] = lo
            if hi is not None:
                t["below"] = hi if self.chance(0.8) else "sensor.s2"
            if self.chance(0.15):
                t["value_template"] = "{{ state.state | float(0) * 2 }}"
            if self.chance(0.25):
                t["for"] = self.period()
        elif k == "template":
            t["value_template"] = self.bool_template(False)
            if self.chance(0.25):
                t["for"] = self.period()
        elif k == "event":
            t["event_type"] = self.pick(EVENTS)
            if self.chance(0.35):
                t["event_data"] = {"k": self.pick([1, "a", True])}
        elif k == "time_pattern":
            self.time_trigger_used = True
            t["seconds"] = self.pick(["/3", "/7", "/9", 23, "26", 31])
        elif k == "time":
            self.time_trigger_used = True
            t["at"] = "22:13:%02d" % self.pick([23, 26, 29, 33])
        if not in_wait and self.chance(0.2):
            t["id"] = self.pick(["alpha", "beta"])
        return t

    # ---- conditions
    def condition(self, in_run=True, depth=0):
        kinds = ["state", "numeric_state", "template", "template", "time"]
        if in_run:
            kinds.append("trigger")
        if depth < 2:
            kinds += ["and", "or", "not"]
        k = self.pick(kinds)
        if k == "state":
            eid = self.entity() if self.chance(0.92) else "light.gone"
            vals = self.values_for(eid)
            c = {"condition": "state", "entity_id": eid,
                 "state": self.pick(vals) if self.chance(0.7) else self.r.sample(vals, 2)}
            if self.chance(0.15):
                c["for"] = self.pick([2, "00:00:03", {"seconds": 1}])
            if self.chance(0.1):
                c = {"condition": "state", "entity_id": [eid, self.entity()], "state": "on", "match": "any"}
        elif k == "numeric_state":
            c = {"condition": "numeric_state", "entity_id": self.pick(SENSORS)}
            if self.chance(0.6):
                c["above"] = self.pick([3, 6, "sensor.s2"])
            if self.chance(0.6) or "above" not in c:
                c["below"] = self.pick([9, 15])
        elif k == "template":
            t = self.bool_template(in_run)
            c = t if self.chance(0.5) else {"condition": "template", "value_template": t}
        elif k == "time":
            c = {"condition": "time"}
            if self.chance(0.6):
                c["after"] = self.pick(["22:13:25", "22:00", "23:00:00"])
            if self.chance(0.6) or "after" not in c:
                c["before"] = self.pick(["22:13:30", "06:00", "22:14"])
            if self.chance(0.2):
                c["weekday"] = self.pick([["tue"], ["wed", "mon"], "tue"])
        elif k == "trigger":
            c = {"condition": "trigger", "id": self.pick(["0", "1", "alpha", ["beta", "0"]])}
        else:
            subs = [self.condition(in_run, depth + 1) for _ in range(self.pick([1, 2, 2, 3]))]
            c = {"condition": k, "conditions": subs} if self.chance(0.6) else {k: subs}
        if isinstance(c, dict) and self.chance(0.06):
            c["enabled"] = False
        return c

    def conditions(self, in_run=True):
        return [self.condition(in_run) for _ in range(self.pick([1, 1, 2]))]

    # ---- actions
    def marker_event(self):
        n = self.next_marker()
        a: dict = {"event": f"m_{n}"}
        if self.chance(0.6):
            a["event_data"] = {"n": n, "v": self.value_template()}
            if self.varn and self.chance(0.5):
                a["event_data"]["var"] = "{{ v%d | default('undef') }}" % self.r.randint(1, self.varn)
        return a

    def marker_service(self):
        n = self.next_marker()
        a: dict = {"action": f"test.s{n}"}
        if self.chance(0.7):
            a["data"] = {"n": n, "v": self.value_template()}
        if self.chance(0.3):
            a["target"] = {"entity_id": self.pick(["light.l1", ["light.l1", "light.l2"], "{{ trigger.entity_id | default('light.l2', true) }}"])}
        if self.chance(0.2):
            a["continue_on_error"] = True
        if self.chance(0.15):
            self.varn += 1
            a["response_variable"] = f"v{self.varn}"
        return a

    def action(self, depth):
        simple = ["event", "event", "service", "service", "delay", "variables", "condition"]
        nested = ["choose", "if", "repeat", "sequence", "parallel", "wait_template", "wait_for_trigger", "stop"]
        k = self.pick(simple + (nested if depth < 3 else []))
        if k == "event":
            a = self.marker_event()
        elif k == "service":
            a = self.marker_service()
        elif k == "delay":
            a = {"delay": self.pick([1, 2, "00:00:02", {"seconds": 1}, "{{ 1 }}", 0, {"seconds": "{{ 2 }}"}])}
        elif k == "variables":
            self.varn += 1
            name = f"v{self.r.randint(1, self.varn)}"
            a = {"variables": {name: self.pick([
                1, "x", "{{ (%s | default(0) | int(0)) + 1 }}" % name, "{{ states('sensor.s1') }}",
                "{{ repeat.index if repeat is defined else -1 }}", ["a", "{{ 1 + 1 }}"]])}}
        elif k == "condition":
            c = self.condition(True)
            a = c if isinstance(c, dict) and "condition" in c else {"condition": "template", "value_template": self.bool_template(True)}
        elif k == "choose":
            a = {"choose": [{"conditions": self.conditions(), "sequence": self.sequence(depth + 1)}
                            for _ in range(self.pick([1, 2]))]}
            if self.chance(0.5):
                a["default"] = self.sequence(depth + 1)
        elif k == "if":
            a = {"if": self.conditions(), "then": self.sequence(depth + 1)}
            if self.chance(0.5):
                a["else"] = self.sequence(depth + 1)
        elif k == "repeat":
            kind = self.pick(["count", "count", "for_each", "while", "until"])
            body = self.sequence(depth + 1)
            if kind == "count":
                rep = {"count": self.pick([0, 1, 2, 3, "{{ 2 }}", "{{ states('sensor.s1') | int(0) // 4 }}"])}
            elif kind == "for_each":
                rep = {"for_each": self.pick([["a", "b"], [], "{{ ['x', 1] }}", "{{ states('light.l1') }}", [{"k": 1}, None]])}
            elif kind == "while":
                rep = {"while": [self.condition(True), "{{ repeat.index <= %d }}" % self.pick([1, 2, 3])]}
            else:
                rep = {"until": [self.pick(["{{ repeat.index >= %d }}" % self.pick([1, 2, 3]), self.condition(True)]),
                                 ] if self.chance(0.6) else ["{{ repeat.index >= 2 }}"]}
                if not any(isinstance(c, str) and "repeat.index" in c for c in rep["until"]):
                    # make sure the loop ends: until (cond) or index >= 3
                    rep["until"] = [{"condition": "or", "conditions": [rep["until"][0], "{{ repeat.index >= 3 }}"]}]
            rep["sequence"] = body
            a = {"repeat": rep}
        elif k == "sequence":
            a = {"sequence": self.sequence(depth + 1)}
        elif k == "parallel":
            branches = []
            for _ in range(self.pick([2, 2, 3])):
                branches.append({"sequence": self.sequence(depth + 1)} if self.chance(0.7) else self.marker_event())
            a = {"parallel": branches}
        elif k == "wait_template":
            a = {"wait_template": self.bool_template(True)}
            if self.chance(0.7):
                a["timeout"] = self.pick([0, 1, 2, "00:00:03", {"seconds": 2}, "{{ 2 }}"])
                if self.chance(0.4):
                    a["continue_on_timeout"] = False
        elif k == "wait_for_trigger":
            a = {"wait_for_trigger": [self.trigger(in_wait=True) for _ in range(self.pick([1, 1, 2]))]}
            if self.chance(0.7):
                a["timeout"] = self.pick([0, 1, 2, 3, {"seconds": 2}])
                if self.chance(0.4):
                    a["continue_on_timeout"] = False
        else:  # stop
            a = {"stop": "s"}
            if self.chance(0.3):
                a["error"] = True
        if k in ("choose", "if", "repeat", "sequence", "parallel") and self.chance(0.15):
            a["continue_on_error"] = True
        if isinstance(a, dict) and self.chance(0.04):
            a["enabled"] = False
        return a

    def sequence(self, depth):
        n = self.pick([1, 1, 2, 2, 3]) if depth else self.pick([2, 3, 4, 5])
        seq = [self.action(depth) for _ in range(n)]
        # after a wait step, show the wait variable (never `remaining` after a wake-up)
        out = []
        for a in seq:
            out.append(a)
            if isinstance(a, dict) and ("wait_template" in a or "wait_for_trigger" in a) and self.chance(0.6):
                n = self.next_marker()
                data = {"n": n, "completed": "{{ wait.completed }}"}
                if "wait_for_trigger" in a:
                    data["trig"] = "{{ wait.trigger.platform if wait.trigger else 'none' }}"
                out.append({"event": f"m_{n}", "event_data": data})
        return out

    def automation(self, i):
        self.varn = 0
        a: dict = {"alias": f"a{i}", "id": f"id{i}"}
        mode = self.pick(["single", "single", "restart", "queued", "parallel"])
        if mode != "single":
            a["mode"] = mode
            if mode in ("queued", "parallel") and self.chance(0.5):
                a["max"] = self.pick([2, 3])
        if self.chance(0.25):
            a["variables"] = {"v1": self.pick([0, "{{ states('sensor.s2') }}", "{{ trigger.platform }}"])}
            self.varn = 1
        a["triggers"] = [self.trigger() for _ in range(self.pick([1, 1, 2, 3]))]
        if self.chance(0.4):
            a["conditions"] = self.conditions()
        a["actions"] = self.sequence(0)
        return a

    # ---- scenario
    def scenario(self):
        self.marker = 0
        self.time_trigger_used = False
        autos = [self.automation(i) for i in range(self.pick([1, 1, 2, 2, 3]))]
        states = []
        for eid in SENSORS + LIGHTS + BOOLS:
            if self.chance(0.9):
                s = {"entity_id": eid, "state": self.pick(self.values_for(eid))}
                if self.chance(0.3):
                    s["attributes"] = {"lvl": self.pick([1, 2, 3])}
                states.append(s)
        return {"automations": autos, "states": states, "steps": []}

    def input_step(self, at, open_calls):
        kinds = ["set"] * 5 + ["event"] * 3 + ["tick"] * 2
        if open_calls:
            kinds += ["result"] * 5
        k = self.pick(kinds)
        if k == "set":
            eid = self.entity()
            st = {"at": at, "set": [eid, self.pick(self.values_for(eid))]}
            if self.chance(0.3):
                st["attributes"] = {"lvl": self.pick([1, 2, 3])}
            return st
        if k == "event":
            msg = {"type": "event", "event_type": self.pick(EVENTS)}
            if self.chance(0.5):
                msg["data"] = {"k": self.pick([1, "a", True, 2])}
            return {"at": at, "send": msg}
        if k == "tick":
            return {"at": at, "send": {"type": "event", "event_type": "tick"}}
        cid = self.pick(open_calls)
        msg = {"type": "service_result", "call_id": cid, "ok": True}
        r = self.r.random()
        if r < 0.25:
            msg.update(ok=False, error_kind=self.pick(["ha_error", "ha_error", "other", "invalid"]))
        elif r < 0.5:
            msg["response"] = {"value": self.pick([1, "x", [1, 2]])}
        return {"at": at, "send": msg}


def open_calls(sc) -> list[int]:
    """Call ids the engine has issued and the scenario has not answered yet."""
    outs = run_scenarios.engine_outputs(sc)
    issued = [c["call_id"] for cmds in outs for c in cmds if c["type"] == "call_service"]
    answered = {s["send"]["call_id"] for s in sc["steps"] if "send" in s and s["send"]["type"] == "service_result"}
    return [c for c in issued if c not in answered]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--count", type=int, default=300)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--engine", type=Path, default=REPO / ".lake/build/bin/halean-automation")
    args = ap.parse_args()
    run_scenarios.ENGINE = args.engine
    args.out.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(args.seed)
    for i in range(args.count):
        g = Gen(random.Random(rnd.getrandbits(64)))
        sc = g.scenario()
        at = 0
        for _ in range(g.pick([12, 16, 20, 24])):
            at += g.pick([0, 1, 1, 1, 2, 3])
            try:
                pending = open_calls(sc)
            except subprocess.CalledProcessError:
                pending = []
            sc["steps"].append(g.input_step(at, pending))
        header = f"# random scenario, seed {args.seed}, index {i} (gen/gen_scenarios.py)\n"
        (args.out / f"r{args.seed}_{i:03d}.yaml").write_text(
            header + yaml.safe_dump(sc, sort_keys=False, default_flow_style=None, width=200))
    print(f"wrote {args.count} scenarios to {args.out} (seed {args.seed})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
