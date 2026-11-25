"""Seeded random operation sequences for the event bus, in the shipped YAML case format.

  python gen/gen_events.py SEED COUNT OUT.yaml [--known]

Listeners fire, listen, listen once, unsubscribe and raise during dispatch (nested up to three
levels). Event types that HA's own listeners handle in the test fixture are left out unless
--known is given (they are behind BUS-1), as are the float/int pairs behind BUS-2.
"""
import random
import sys

import yaml

T64 = "0123456789" * 6 + "0123"
T65 = T64 + "4"
TYPES = ["x", "x", "x", "y", "y", "z", "*", "state_reported", "", T64, T65, "X", "😀"]
KNOWN_TYPES = ["logging_changed", "homeassistant_close"]
IDS = [f"l{i}" for i in range(8)]
DATA = [None, None, {}, {"k": 1}, {"k": 1.0}, {"k": True}, {"k": "1"}, {"k": None}, {"j": 2},
        {"k": [1], "j": {}}, {"k": 0}, {"k": False}, {"k": [True]}, {"k": {"a": 1}}, {"k": 2, "j": 2},
        {"k": 0.1}, {"k": 2**60}]
KNOWN_DATA = [{"k": 10**23}, {"k": 1e23}]
FILTERS = [True, False, {"eq": {"k": 1}}, {"eq": {"k": True}}, {"eq": {"k": None}}, {"has": "k"},
           {"has": "j"}, {"raise": True}, {"eq": {"k": 0}}, {"eq": {"k": [1.0]}}, {"eq": {"k": {"a": True}}},
           {"eq": {}}, {"eq": {"k": 2, "j": 2.0}}, {"eq": {"k": 0.1}}, {"eq": {"k": 1152921504606846976}}]
KNOWN_FILTERS = [{"eq": {"k": 1e23}}, {"eq": {"k": 10**23}}]
CONTEXTS = [{"id": "c1"}, {"id": "c2", "user_id": "u1"}, {"id": "c3", "parent_id": "p1"},
            {"id": "c4", "user_id": "", "parent_id": None}]
RAISES = ["HomeAssistantError", "ValueError", "RuntimeError", "TypeError", "KeyError"]
NOW0 = 1795710645123456
TIMES = [0, 1, 999, 1000, 1700000000000000, 1700000000000001, 1795710645999999, 1795710645001000,
         1795710645000999, 4102444800000001, 946684800123000, 1795710645123456, 10413792000000003]
STEPS = [0, 0, 0, 1, 544, 1000, 876544, 1000000, 59000000, 3600000001]


class Gen:
    def __init__(self, rng: random.Random, known: bool) -> None:
        self.rng = rng
        self.types = TYPES + (KNOWN_TYPES if known else [])
        self.data = DATA + (KNOWN_DATA if known else [])
        self.filters = FILTERS + (KNOWN_FILTERS if known else [])

    def fire(self, nested: bool) -> dict:
        rng = self.rng
        f: dict = {"event_type": rng.choice(self.types)}
        d = rng.choice(self.data)
        if d is not None or rng.random() < 0.3:
            f["data"] = d
        r = rng.random()
        if r < 0.2:
            f["context"] = rng.choice(CONTEXTS)
        elif r < 0.4 and nested:
            f["context"] = "inherit"
        if rng.random() < 0.2:
            f["origin"] = rng.choice(["remote", "local"])
        if rng.random() < 0.2:
            f["time_fired"] = rng.choice(TIMES)
        return f

    def listen(self, depth: int) -> dict:
        rng = self.rng
        spec: dict = {"id": rng.choice(IDS), "event_type": rng.choice(self.types)}
        if rng.random() < 0.35:
            spec["filter"] = rng.choice(self.filters)
            if rng.random() < 0.08:
                spec["filter_callback"] = False
        if rng.random() < 0.03:
            spec["run_immediately"] = rng.choice([True, False, None])
        if depth > 0 and rng.random() < 0.6:
            spec["react"] = [self.reaction(depth - 1) for _ in range(rng.randint(1, 3))]
            if rng.random() < 0.8:
                spec["react_times"] = rng.choice([0, 1, 1, 1, 2, 2, 3])
        return spec

    def reaction(self, depth: int) -> dict:
        rng = self.rng
        r = rng.random()
        if r < 0.45:
            return {"fire": self.fire(True)}
        if r < 0.62:
            return {"listen": self.listen(depth)}
        if r < 0.72:
            return {"listen_once": self.listen(depth)}
        if r < 0.9:
            return {"unsub": rng.choice(IDS)}
        return {"raise": rng.choice(RAISES)}

    def case(self, name: str) -> dict:
        rng = self.rng
        now = rng.choice([NOW0, NOW0, 1795710645000000, 946684800000001, 1795710645999999])
        ops = []
        for _ in range(rng.randint(8, 28)):
            r = rng.random()
            if r < 0.3:
                op = {"op": "listen", **self.listen(3)}
            elif r < 0.42:
                op = {"op": "listen_once", **self.listen(3)}
            elif r < 0.55:
                op = {"op": "unsub", "id": rng.choice(IDS)}
            elif r < 0.93:
                op = {"op": "fire", **self.fire(False)}
            else:
                op = {"op": "listeners"}
            if rng.random() < 0.4:
                now += rng.choice(STEPS)
                op["now"] = now
            ops.append(op)
        ops.append({"op": "listeners"})
        return {"name": name, "ops": ops}


def main() -> None:
    seed, count, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    known = "--known" in sys.argv
    g = Gen(random.Random(seed), known)
    cases = [g.case(f"rand_events_s{seed}{'k' if known else ''}_{i}") for i in range(count)]
    with open(out, "w") as f:
        f.write(f"# gen_events.py seed={seed} count={count} known={known}\n")
        yaml.safe_dump(cases, f, allow_unicode=True, sort_keys=False, width=100000)


main()
