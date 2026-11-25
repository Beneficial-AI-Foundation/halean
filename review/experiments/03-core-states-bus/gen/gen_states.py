"""Seeded random operation sequences for the state machine, in the shipped YAML case format.

  python gen/gen_states.py SEED COUNT OUT.yaml [--known]

Values come from pools rich in edge cases. Operations HALean documents as outside its subset
(non-ASCII ids / domain filters) are emitted with `unsupported: true`, as the shipped cases do.
Without --known the pools leave out the inputs behind divergences already reported in
FINDINGS.md (ST-1 .. ST-7), so that a failing sequence points at something new; with --known
they are included.
"""
import random
import sys
from datetime import UTC, datetime, timedelta

import yaml

S255 = "0123456789" * 25 + "01234"
S256 = S255 + "5"
VALID_IDS = ["light.a", "light.b", "sensor.a", "sensor.b_c", "switch.x1", "a.b", "light.a\n", "sensor.t_1"]
CASED_IDS = ["Light.A", "LIGHT.B", "sensor.A", "SENSOR.B_C", "Switch.X1", "LIGHT.A\n"]
INVALID_IDS = ["light", "light.", "light._a", "li__ght.a", ".a", "light.a.b", "", "light.a ", "light.a_",
               "_light.a", "light.a__b", "light-a.b", "light.a\n\n"]
NON_ASCII_IDS = ["light.é", "sensor.ü_1", "LIGHT.É"]
STATES = ["on", "off", "", "unknown", "unavailable", "ON", 1, 1.0, 0, True, False, None, 2.5, -1, "1", "1.0",
          "True", "None", [1, 2], {"a": 1}, S255, S256, "é", "😀😀😀", 21.5, 1e-7, 10**20, ["it's", 'q"'],
          [], {}, [None, True, 1.5, "x"], " ", "0", 0.0, 1e15, "[1, 2]", -2.5e-5, 123456789.25]
STR_STATES = [s for s in STATES if isinstance(s, str)]
ATTRS = [None, {}, {"a": 1}, {"a": 1.0}, {"a": True}, {"a": "1"}, {"a": [1, 2]}, {"a": [1.0, 2]},
         {"a": {"b": None}}, {"a": {"b": 0}}, {"friendly_name": "X"}, {"friendly_name": ""},
         {"friendly_name": 0}, {"a": 1, "b": 2}, {"b": 2, "a": 1}, {"a": None}, {"a": 0}, {"a": False},
         {"a": 0.0}, {"x": "é"}, {"a": 2**60}, {"a": 2**53 + 1}, {"a": 9007199254740992.0}, {"a": 2**53},
         {"friendly_name": [0]}, {"friendly_name": "Küche", "unit": "°C"}, {"a": [], "b": {}}, {"a": ""},
         {"a": [[1]]}, {"a": [[True]]}, {"a": 0.1}, {"a": 0.1, "b": None}, {"A": 1}, {"": 0}]
KNOWN_STATES = [1e16, -0.0, 1.5e300, {"b": 1, "a": 2}, ["​"], 1e22]
KNOWN_ATTRS = [{"a": 1e16}, {"a": 1e23}, {"a": 10**23}, {"a": 10**16}, {"a": -0.0}]
KNOWN_INTERNAL_IDS = ["sensor.x١", "１.a"]
CONTEXTS = [{"id": "c1"}, {"id": "c2", "user_id": "u1"}, {"id": "c3", "parent_id": "p1"},
            {"id": "c4", "user_id": "u", "parent_id": "p"}, {"id": "c1", "user_id": "other"},
            {"id": "c5", "user_id": ""}, {"id": "c6", "user_id": None, "parent_id": None}]
FILTERS = [None, "light", "LIGHT", "sensor", "Sensor", ["light"], ["LIGHT"], ["sensor", "light"],
           ["light", "light"], "", [], "nope", ["nope", "a"], "a", "switch", ["switch", "", "sensor"]]
NON_ASCII_FILTERS = ["é", "LÏGHT"]
STEPS = [0, 0, 1, 1, 999, 1000, 500_000, 1_000_000, 1_000_000, 60_000_000, 3_600_000_000, 999_999, 1_000_001]
T0 = datetime(2026, 11, 20, 16, 30, 45, 123456, tzinfo=UTC)
STARTS = [T0, datetime(2026, 11, 20, 16, 30, 45, tzinfo=UTC), datetime(2001, 9, 9, 1, 46, 40, tzinfo=UTC),
          datetime(2038, 1, 19, 3, 14, 7, 999999, tzinfo=UTC), datetime(2100, 2, 28, 23, 59, 59, 999999, tzinfo=UTC),
          datetime(2026, 12, 31, 23, 59, 59, 999998, tzinfo=UTC), datetime(2024, 2, 29, 0, 0, 0, 1, tzinfo=UTC)]


def gen_case(rng: random.Random, n: int, known: bool) -> dict:
    states = STATES + (KNOWN_STATES if known else [])
    attrs = ATTRS + (KNOWN_ATTRS if known else [])
    now = rng.choice(STARTS)
    ops = []
    used: list[str] = []

    def eid(kind: str) -> tuple[str, bool]:
        r = rng.random()
        if kind == "internal":
            if known and r < 0.08:
                return rng.choice(KNOWN_INTERNAL_IDS), False
            pool = VALID_IDS * 4 + CASED_IDS + INVALID_IDS
            return rng.choice(pool), False
        if r < 0.03:
            return rng.choice(NON_ASCII_IDS), kind != "reserve"
        if used and r < 0.55:
            e = rng.choice(used)
            if rng.random() < 0.2:
                e = e.upper()
            return e, False
        return rng.choice(VALID_IDS * 4 + CASED_IDS * 2 + INVALID_IDS), False

    for _ in range(rng.randint(8, 30)):
        r = rng.random()
        if rng.random() < 0.6:
            step = rng.choice(STEPS)
            now = now + timedelta(microseconds=-step if rng.random() < 0.05 else step)
        op: dict
        if r < 0.45:
            e, uns = eid("set")
            op = {"op": "set", "entity_id": e, "state": rng.choice(states)}
            if rng.random() < 0.7:
                op["attributes"] = rng.choice(attrs)
            if rng.random() < 0.2:
                op["force_update"] = rng.random() < 0.75
            if rng.random() < 0.3:
                op["context"] = rng.choice(CONTEXTS)
            if not uns:
                used.append(e.lower())
        elif r < 0.55:
            e, uns = eid("internal")
            op = {"op": "set_internal", "entity_id": e, "state": rng.choice(STR_STATES),
                  "attributes": rng.choice(attrs)}
            if rng.random() < 0.2:
                op["force_update"] = True
            if rng.random() < 0.3:
                op["context"] = rng.choice(CONTEXTS)
            used.append(e)
        elif r < 0.65:
            e, uns = eid("remove")
            op = {"op": "remove", "entity_id": e}
            if rng.random() < 0.3:
                op["context"] = rng.choice(CONTEXTS)
        elif r < 0.73:
            e, uns = eid("get")
            op = {"op": "get", "entity_id": e}
        elif r < 0.79:
            e, uns = eid("inspect")
            op = {"op": "inspect", "entity_id": e}
        elif r < 0.83:
            e, uns = eid("is_state")
            op = {"op": "is_state", "entity_id": e, "state": rng.choice(STR_STATES + ["1", "True", "None", "[1, 2]", "{'a': 1}", "2.5"])}
        elif r < 0.91:
            f = rng.choice(FILTERS)
            uns = False
            if rng.random() < 0.04:
                f, uns = rng.choice(NON_ASCII_FILTERS), True
            op = {"op": rng.choice(["entity_ids", "entity_ids_count", "all"])}
            if f is not None or rng.random() < 0.5:
                op["domain_filter"] = f
        elif r < 0.95:
            e, uns = eid("reserve")
            uns = False
            op = {"op": "reserve", "entity_id": e}
        else:
            e, uns = eid("available")
            op = {"op": "available", "entity_id": e}
        op["now"] = now.isoformat()
        if uns:
            op["unsupported"] = True
        ops.append(op)
    ops.append({"op": "all", "now": now.isoformat()})
    ops.append({"op": "entity_ids", "now": now.isoformat()})
    return {"name": f"rand_states_{n}", "ops": ops}


def main() -> None:
    seed, count, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    known = "--known" in sys.argv
    rng = random.Random(seed)
    cases = [gen_case(rng, i, known) for i in range(count)]
    for c in cases:
        c["name"] = f"rand_states_s{seed}{'k' if known else ''}_{c['name'].rsplit('_', 1)[1]}"
    with open(out, "w") as f:
        f.write(f"# gen_states.py seed={seed} count={count} known={known}\n")
        yaml.safe_dump(cases, f, allow_unicode=True, sort_keys=False, width=100000)


main()
