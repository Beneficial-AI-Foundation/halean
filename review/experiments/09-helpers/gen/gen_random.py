#!/usr/bin/env python3
"""Seeded random case generator for the helper entities (shipped YAML format of
tests/helpers/*.yaml: steps `setup` (+ `restore`), `call` (+ `data`), `advance`).

  gen_random.py --seed N --out DIR [--per-helper K] [--patterns P] [--include-known]

Writes DIR/rnd_<helper>.yaml (K cases per helper, six helpers, and K cases
`mixed` with two or three domains set up together) and
DIR/rnd_pattern.yaml (P cases: one random regex of the documented subset of
HALean/Helpers/Pattern.lean, as the `pattern` of an input_text, and random
strings sent with input_text.set_value; HA matches them with Python's re).

By default the generator avoids the inputs of the root causes that already have
a hand-written reproducer in ../cases (so that a run shows what is new):
  * `entity_id: all` with more than one helper domain set up        (HLP-1)
  * -0.0 / 0.0 in input_number                                      (HLP-2)
  * states longer than 255 characters                               (HLP-3)
  * `$` followed by a quantifier, `{m}` with nothing before it,
    a class escape before `-` in a set, `]-x` at the start of a set (HLP-5..8)
  * \\x1c-\\x1f against \\s; non-ASCII against \\d \\w \\s           (HLP-9, HLP-10)
  * Unicode digits in restored states                               (HLP-11, HLP-12)
  * timers whose end leaves datetime's range                        (HLP-13)
  * non-string last_transition in a restored timer                  (HLP-14)
  * input_select duplicates with an empty name                      (HLP-15)
  * an empty slug key                                               (HLP-16)
  * non-finite JSON floats (the driver cannot read them)            (HLP-18)
  * a clock exactly on a whole second (advance 0.876544 from 16:30:45.123456)
    when a timer is started with a zero duration: a harness artefact, see
    FINDINGS.md "Notes on the harness"
  * what the README documents as refused: non-ASCII text read by a
    text-handling validator, timedelta overflow, restoring a paused/active
    timer, a counter last state int() cannot read, regex features outside the
    subset.
`--include-known` turns the avoidance off.
"""
from __future__ import annotations

import argparse
import random
import re
from pathlib import Path

import yaml

KNOWN = False  # set by --include-known


def pick(r, xs):
    return xs[r.randrange(len(xs))]


def maybe(r, p):
    return r.random() < p


# ---------------------------------------------------------------- shared

NAMES = ["Name", "", 42, "A b", "x_y", None]
ICONS = ["mdi:a", "mdi:timer-outline", "x:y", "nocolon", 5]


def common_cfg(r, cfg, bad):
    if maybe(r, 0.25):
        n = pick(r, NAMES)
        if n is None:
            bad.append("name")
        cfg["name"] = n
    if maybe(r, 0.2):
        i = pick(r, ICONS)
        if i in ("nocolon", 5):
            bad.append("icon")
        cfg["icon"] = i
    if maybe(r, 0.05):
        cfg["bogus"] = 1
        bad.append("extra")


def target(r, domain, ids, allow_all=True):
    """An entity_id value. Lists are only used by callers for services that
    cannot raise (HA runs a list in set order)."""
    x = r.random()
    eid = f"{domain}.{pick(r, ids)}"
    if x < 0.80:
        return eid
    if x < 0.85:
        return [eid]
    if x < 0.90 and allow_all:
        return "all"
    if x < 0.93:
        return f"{domain}.missing"
    if x < 0.96:
        return eid.upper()
    if x < 0.98:
        return "none"
    return []


def bad_call(r, domain, service, ids):
    """A call the entity service schema refuses."""
    x = r.randrange(5)
    eid = f"{domain}.{pick(r, ids)}"
    if x == 0:
        return {"call": f"{domain}.{service}", "data": {}}
    if x == 1:
        return {"call": f"{domain}.{service}", "data": {"entity_id": eid, "bogus": 1}}
    if x == 2:
        return {"call": f"{domain}.{service}", "data": {"entity_id": "not an id"}}
    if x == 3:
        return {"call": f"{domain}.nosuch", "data": {"entity_id": eid}}
    return {"call": f"{domain}.{service}", "data": {"entity_id": None}}


def slug_ids(r, n):
    pool = ["a", "b", "c", "x1", "long_name", "z9_q"]
    r.shuffle(pool)
    return pool[:n]


# ---------------------------------------------------------------- input_boolean

def gen_input_boolean(r, i):
    ids = slug_ids(r, r.randint(1, 3))
    cfg, restore = {}, []
    for k in ids:
        x = r.random()
        if x < 0.3:
            cfg[k] = None
        else:
            c = {}
            if maybe(r, 0.6):
                c["initial"] = pick(r, [True, False, "on", "off", "yes", "no", 1, 0, "TRUE", "enable",
                                        "disable", "y", "n", "maybe", 2, 1.0, None, " on ", "On", "1", "0", ""])
            common_cfg(r, c, [])
            cfg[k] = c
        if maybe(r, 0.4):
            restore.append([f"input_boolean.{k}", pick(r, ["on", "off", "ON", "unknown", "unavailable", "1"]), {}])
    if maybe(r, 0.05):
        cfg[pick(r, ["Bad", "a b", "a-b", "__x"])] = None
    steps = [{"setup": {"input_boolean": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(4, 10)):
        s = pick(r, ["turn_on", "turn_off", "toggle"])
        if maybe(r, 0.1):
            steps.append(bad_call(r, "input_boolean", s, ids))
            continue
        t = target(r, "input_boolean", ids)
        if maybe(r, 0.1) and len(ids) > 1:
            t = [f"input_boolean.{k}" for k in ids]
        steps.append({"call": f"input_boolean.{s}", "data": {"entity_id": t}})
    return {"name": f"rnd_input_boolean_{i}", "steps": steps}


# ---------------------------------------------------------------- input_number

NUMS = [0, 1, -1, 0.1, 0.2, 0.3, 0.5, 1.5, 2, 3, 7, 10, 100, 255, 1000, 0.001, 1e-5, 1e-7, 1e-9, 5e-10,
        123456.789, 1e15, 1e16, 1.1e16, 123456789012345678, 1e21, 1e22, 1e100, -0.1, -2.5, -100, -1e16,
        0.30000000000000004, 1 / 3, 2 / 3, 9.999999999999999, 99999999999999.98, 0.1 + 0.7, 4.35, 2.675,
        1e-4, 9.5e-5, 0.000123456789012345678, 1.7976931348623157e308, 5e-324, 2.2250738585072014e-308]
NUM_STRS = ["5", " 2.5 ", "1e3", "-7", "+3", ".5", "5.", "1_0", "abc", "", "0x10", "1e400", "-1e400",
            "nan", "inf", "-inf", "Infinity", "1,5", "１２", "1 0", "--1", "1e", "0b1", "1__0", "_1", "NaN"]


def num(r, strings=0.15):
    if maybe(r, strings):
        s = pick(r, NUM_STRS)
        if not KNOWN and not s.isascii():
            s = "5"
        return s
    v = pick(r, NUMS)
    if maybe(r, 0.3):
        v = -v
    if maybe(r, 0.1):
        v = v + pick(r, NUMS)
    if maybe(r, 0.05):
        v = pick(r, [True, False, None, [1], {"a": 1}])
    if not KNOWN and isinstance(v, float) and v == 0:
        v = 0  # -0.0: HLP-2
    return v


def no_zero(v):
    """Avoid ±0.0 as a value (HLP-2) unless --include-known."""
    if KNOWN:
        return v
    try:
        if not isinstance(v, (list, dict)) and v is not None and float(v) == 0:
            return 1
    except (ValueError, TypeError, OverflowError):
        pass
    return v


def gen_input_number(r, i):
    ids = slug_ids(r, r.randint(1, 2))
    cfg, restore = {}, []
    for k in ids:
        c = {}
        lo = num(r, 0.1)
        hi = num(r, 0.1)
        try:
            if maybe(r, 0.75) and float(lo) > float(hi):
                lo, hi = hi, lo
        except (ValueError, TypeError, OverflowError):
            pass
        if not KNOWN:
            # a zero bound makes increment/decrement reach ±0.0 (HLP-2)
            lo, hi = no_zero(lo), no_zero(hi)
            try:
                if float(lo) > float(hi):
                    lo, hi = hi, lo
            except (ValueError, TypeError, OverflowError):
                pass
        if maybe(r, 0.95):
            c["min"] = lo
        if maybe(r, 0.95):
            c["max"] = hi
        if maybe(r, 0.5):
            c["step"] = pick(r, [1, 0.1, 0.5, 2, 3, 1e-9, 9e-10, 0, -1, "0.25", 1e16, 1e-7, 0.3, 7, "x", None, 1e300])
        if maybe(r, 0.35):
            try:
                a, b = float(lo), float(hi)
                c["initial"] = no_zero(pick(r, [lo, hi, (a + b) / 2, a + (b - a) / 3, num(r)]))
            except (ValueError, TypeError, OverflowError):
                c["initial"] = no_zero(num(r))
        if maybe(r, 0.2):
            c["mode"] = pick(r, ["box", "slider", "auto", "Box", 1])
        if maybe(r, 0.2):
            c["unit_of_measurement"] = pick(r, ["kg", "", 5, "%"])
        common_cfg(r, c, [])
        cfg[k] = c
        if maybe(r, 0.4):
            st = pick(r, ["5", "0.5", "1e2", "unknown", "unavailable", "abc", " 7 ", "-3", "1_0", "nan", "inf",
                          "100", "1", "2.50", "+4", ".5e1", ""])
            restore.append([f"input_number.{k}", st, {}])
    steps = [{"setup": {"input_number": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(5, 14)):
        x = r.random()
        if x < 0.08:
            steps.append(bad_call(r, "input_number", pick(r, ["increment", "set_value"]), ids))
        elif x < 0.5:
            c = cfg[ids[0]]
            v = num(r)
            if maybe(r, 0.6):
                try:
                    a, b = float(c.get("min")), float(c.get("max"))
                    v = pick(r, [a, b, a + (b - a) * r.random(), b + 1e-9, a - 1e-9, (a + b) / 2])
                except (ValueError, TypeError, OverflowError):
                    pass
            v = no_zero(v)
            if isinstance(v, float) and (v != v or v in (float("inf"), float("-inf"))):
                v = str(v)  # the JSON driver cannot read non-finite floats (HLP-18)
            d = {"entity_id": target(r, "input_number", ids, allow_all=False), "value": v}
            if maybe(r, 0.03):
                del d["value"]
            steps.append({"call": "input_number.set_value", "data": d})
        else:
            steps.append({"call": "input_number." + pick(r, ["increment", "decrement"]),
                          "data": {"entity_id": target(r, "input_number", ids)}})
    return {"name": f"rnd_input_number_{i}", "steps": steps}


# ---------------------------------------------------------------- input_select

OPTS = ["a", "b", "c", "d", "A", "a b", "b, c", "it's", "", " ", "unknown", "é", 1, 2.5, True, "1", "True", "None"]


def opt_list(r):
    n = r.randint(0, 5) if maybe(r, 0.15) else r.randint(1, 5)
    xs = [pick(r, OPTS) for _ in range(n)]
    if maybe(r, 0.7):
        seen, ys = set(), []
        for x in xs:
            if str(x) not in seen:
                seen.add(str(x))
                ys.append(x)
        xs = ys
    if maybe(r, 0.04):
        xs.append(pick(r, [None, ["n"], {"k": 1}]))
    if maybe(r, 0.05):
        return pick(r, ["single", 7, None])
    return xs


def gen_input_select(r, i):
    ids = slug_ids(r, r.randint(1, 2))
    cfg, restore = {}, []
    for k in ids:
        c = {}
        o = opt_list(r)
        if maybe(r, 0.95):
            c["options"] = o
        if maybe(r, 0.3):
            c["initial"] = pick(r, o) if isinstance(o, list) and o and maybe(r, 0.8) else pick(r, OPTS)
        common_cfg(r, c, [])
        if not KNOWN and c.get("name") == "":
            c["name"] = "N"  # HLP-15
        cfg[k] = c
        if maybe(r, 0.4):
            restore.append([f"input_select.{k}", str(pick(r, OPTS + ["unknown", "unavailable"])), {}])
    steps = [{"setup": {"input_select": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(5, 14)):
        x = r.random()
        eid = target(r, "input_select", ids, allow_all=False)
        if x < 0.08:
            steps.append(bad_call(r, "input_select", pick(r, ["select_next", "select_option"]), ids))
        elif x < 0.3:
            d = {"entity_id": eid, "option": pick(r, OPTS)}
            if maybe(r, 0.05):
                d["option"] = pick(r, [None, ["a"], {"a": 1}])
            if maybe(r, 0.03):
                del d["option"]
            steps.append({"call": "input_select.select_option", "data": d})
        elif x < 0.6:
            d = {"entity_id": eid}
            if maybe(r, 0.6):
                d["cycle"] = pick(r, [True, False, False, "yes", 0, None, 1])
            steps.append({"call": "input_select." + pick(r, ["select_next", "select_previous"]), "data": d})
        elif x < 0.75:
            steps.append({"call": "input_select." + pick(r, ["select_first", "select_last"]), "data": {"entity_id": eid}})
        else:
            d = {"entity_id": eid, "options": opt_list(r)}
            if maybe(r, 0.03):
                del d["options"]
            steps.append({"call": "input_select.set_options", "data": d})
    return {"name": f"rnd_input_select_{i}", "steps": steps}


# ---------------------------------------------------------------- input_text

TEXTS = ["", "a", "ab", "abc", "hello world", "12", "x" * 10, "y" * 100, "z" * 101, "w" * 255, "v" * 256,
         "é", "日本語", "😀", "a\nb", " lead", "trail ", "unknown", "A1-b2", "12:34", 12, 1.5, True, None,
         ["a"], "tab\t", "0", "-", "q" * 50]
IT_PATTERNS = ["[a-z]+", "[a-z]+$", "[0-9]{2}:[0-9]{2}$", "a|b", "(ab)+$", ".*", ".+", "x?y*z", "[^0-9]*$", "",
               "[A-Z][a-z0-9-]*$", "..$", "(a|b|c){2,3}$", "hello", "\\d+$", "\\w+$", "[a-z ]+$", "(?:[a-z]+ ?)+$"]


def text(r):
    t = pick(r, TEXTS)
    if maybe(r, 0.2):
        t = "".join(pick(r, "abcxyz019 -_:") for _ in range(r.randint(0, 12)))
    return t


def gen_input_text(r, i):
    ids = slug_ids(r, r.randint(1, 2))
    cfg, restore = {}, []
    for k in ids:
        x = r.random()
        if x < 0.15:
            cfg[k] = pick(r, [None, {}, None, 0, ""])
        else:
            c = {}
            if maybe(r, 0.4):
                c["min"] = pick(r, [0, 1, 2, 3, 5, 10, 100, 255, 256, -1, "2", 1.9, True, "x", None])
            if maybe(r, 0.4):
                c["max"] = pick(r, [1, 2, 3, 5, 10, 100, 255, 256, 0, "4", 3.7, False, "x", None])
            if maybe(r, 0.35):
                c["initial"] = text(r)
            if maybe(r, 0.3):
                c["pattern"] = pick(r, IT_PATTERNS)
            if maybe(r, 0.2):
                c["mode"] = pick(r, ["text", "password", "Text", "secret", 0])
            if maybe(r, 0.15):
                c["unit_of_measurement"] = pick(r, ["u", "", 3])
            common_cfg(r, c, [])
            cfg[k] = c
        if maybe(r, 0.4):
            t = text(r)
            restore.append([f"input_text.{k}", t if isinstance(t, str) else str(t), {}])
    if not KNOWN:
        # non-ASCII against \d \w \s is refused for set_value only; avoid it in initial/restore (HLP-10)
        def uses_class(c):
            return isinstance(c, dict) and "\\" in str(c.get("pattern", ""))
        for k in ids:
            if uses_class(cfg[k]):
                if isinstance(cfg[k].get("initial"), str) and not cfg[k]["initial"].isascii():
                    cfg[k]["initial"] = "abc"
                restore = [x for x in restore if not (x[0] == f"input_text.{k}" and not x[1].isascii())]
    steps = [{"setup": {"input_text": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(5, 12)):
        if maybe(r, 0.08):
            steps.append(bad_call(r, "input_text", "set_value", ids))
            continue
        k = pick(r, ids)
        v = text(r)
        if not KNOWN and isinstance(v, str) and not v.isascii() and isinstance(cfg[k], dict) \
                and "\\" in str(cfg[k].get("pattern", "")):
            v = "ascii"  # documented refusal (README line 558)
        d = {"entity_id": f"input_text.{k}", "value": v}
        if maybe(r, 0.03):
            del d["value"]
        steps.append({"call": "input_text.set_value", "data": d})
    return {"name": f"rnd_input_text_{i}", "steps": steps}


# ---------------------------------------------------------------- counter

INTS = [0, 1, -1, 2, 3, 5, 7, 10, -10, 100, 99, -3, 12, 1000000, 2 ** 31, 2 ** 63, -2 ** 63 - 1, 10 ** 30]
INT_ODD = ["5", " 7 ", "-2", "+4", "1_0", "5.5", "abc", "", 2.9, -2.9, 1e3, True, False, None, "0x1f", "1e3",
           [1], "٣", 1e22, "inf", "nan", " ", "0005", "5 ", "-0"]


def cint(r, odd=0.2):
    if maybe(r, odd):
        v = pick(r, INT_ODD)
        if not KNOWN and isinstance(v, str) and not v.isascii():
            v = "3"
        return v
    return pick(r, INTS) * (1 if maybe(r, 0.8) else -1)


def gen_counter(r, i):
    ids = slug_ids(r, r.randint(1, 2))
    cfg, restore = {}, []
    for k in ids:
        if maybe(r, 0.1):
            cfg[k] = pick(r, [None, {}])
        else:
            c = {}
            if maybe(r, 0.5):
                c["initial"] = cint(r)
            if maybe(r, 0.5):
                c["step"] = pick(r, [1, 2, 3, 5, 10, 0, -1, "2", 2.5, None, 7, 100, True, "x"])
            if maybe(r, 0.4):
                c["minimum"] = pick(r, [None, 0, -5, 3, 10, "1", -100, 2.5, "x"])
            if maybe(r, 0.4):
                c["maximum"] = pick(r, [None, 0, 5, 10, 20, "9", 100, -3, 7.9, "x"])
            if maybe(r, 0.3):
                c["restore"] = pick(r, [True, False, "yes", "no", 0, 1, "x", None])
            common_cfg(r, c, [])
            cfg[k] = c
        if maybe(r, 0.4):
            # only strings Python's int() reads: the others are a documented refusal
            st = pick(r, ["5", "0", "-7", "42", " 12 ", "+3", "1_000", "100", "-100", "007", "99999999999999999999"])
            restore.append([f"counter.{k}", st, {"initial": 3, "step": 9}])
    steps = [{"setup": {"counter": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(5, 14)):
        x = r.random()
        if x < 0.08:
            steps.append(bad_call(r, "counter", pick(r, ["increment", "set_value"]), ids))
        elif x < 0.4:
            d = {"entity_id": target(r, "counter", ids, allow_all=False), "value": cint(r)}
            if maybe(r, 0.03):
                del d["value"]
            steps.append({"call": "counter.set_value", "data": d})
        else:
            t = target(r, "counter", ids)
            if maybe(r, 0.1) and len(ids) > 1:
                t = [f"counter.{k}" for k in ids]
            steps.append({"call": "counter." + pick(r, ["increment", "decrement", "reset", "increment"]),
                          "data": {"entity_id": t}})
    return {"name": f"rnd_counter_{i}", "steps": steps}


# ---------------------------------------------------------------- timer

DURS = [0, 1, 2, 5, 10, 30, 60, 90, 3600, 86400, 90000, 0.5, 1.5, 2.25, 0.999999, 1.000001, 59.9999995,
        "0:00:05", "00:05", "0:01:00", "1:00:00", "25:00:00", "0:00:00.5", "00:00:10.250", "100:00:00",
        "0:0:7", "+0:00:03", {"seconds": 5}, {"minutes": 1}, {"hours": 1, "seconds": 1},
        {"days": 1}, {"milliseconds": 1500}, {"seconds": 2.5}, {"minutes": 0.5, "seconds": 0.5},
        {"hours": 100}, {"weeks": 2}, {"seconds": "5"}, {"days": 0}]
DURS_NEG = [-1, -5, -0.5, -3600, "-0:00:05", "-1:00:00", "-0:00:00.5", {"seconds": -5}, -90, "-00:02"]
DURS_BAD = ["soon", "1:2:3:4", "", ":", "1:60", "0:00:60", "24:00", "a:b", [5], {}, {"secs": 5}, True, None,
            "5", " 5", "0:5:5:5", "1:-2:3", "0:00:0x1", {"seconds": "x"}, "1.5", "1e2", "0:1e1"]


def dur(r, neg=0.12, bad=0.08):
    x = r.random()
    if x < bad:
        return pick(r, DURS_BAD)
    if x < bad + neg:
        return pick(r, DURS_NEG)
    return pick(r, DURS)


def gen_timer(r, i):
    ids = slug_ids(r, 1 if maybe(r, 0.8) else 2)
    cfg, restore = {}, []
    for k in ids:
        if maybe(r, 0.1):
            cfg[k] = pick(r, [None, {}])
        else:
            c = {}
            if maybe(r, 0.8):
                c["duration"] = dur(r)
            if maybe(r, 0.3):
                c["restore"] = pick(r, [True, False, True, "yes", "x", None])
            common_cfg(r, c, [])
            cfg[k] = c
        if maybe(r, 0.3):
            attrs = {"duration": "0:00:10"}
            if maybe(r, 0.7):
                attrs["last_transition"] = pick(r, ["finished", "cancelled", "started", "weird"])
            restore.append([f"timer.{k}", "idle", attrs])
    steps = [{"setup": {"timer": cfg}}]
    if restore:
        steps[0]["restore"] = restore
    for _ in range(r.randint(6, 16)):
        x = r.random()
        t = target(r, "timer", ids)
        if x < 0.06:
            steps.append(bad_call(r, "timer", pick(r, ["start", "pause", "change"]), ids))
        elif x < 0.30:
            d = {"entity_id": t}
            if maybe(r, 0.5):
                d["duration"] = dur(r)
            steps.append({"call": "timer.start", "data": d})
        elif x < 0.40:
            steps.append({"call": "timer.pause", "data": {"entity_id": t}})
        elif x < 0.47:
            steps.append({"call": "timer.cancel", "data": {"entity_id": t}})
        elif x < 0.54:
            steps.append({"call": "timer.finish", "data": {"entity_id": t}})
        elif x < 0.72:
            d = {"entity_id": f"timer.{pick(r, ids)}"}
            if maybe(r, 0.9):
                d["duration"] = dur(r, neg=0.4)
            steps.append({"call": "timer.change", "data": d})
        else:
            steps.append({"advance": pick(r, [0, 1, 1, 2, 3, 4, 5, 5, 10, 29, 30, 31, 59, 60, 61, 0.5, 0.876543,
                                              0.876544 if KNOWN else 0.876546, 0.876545, 1.5, 0.000001, 3600, 86400, 100000])})
    return {"name": f"rnd_timer_{i}", "steps": steps}


# ---------------------------------------------------------------- regex × strings

ALPHA = "abc1 -_"
ESC_CLASSES = ["\\d", "\\D", "\\w", "\\W", "\\s", "\\S"]
ESC_LITS = ["\\.", "\\*", "\\+", "\\?", "\\(", "\\)", "\\[", "\\]", "\\{", "\\}", "\\|", "\\^", "\\$", "\\\\",
            "\\-", "\\/", "\\n", "\\t"]
LIT_OF = {"\\n": "\n", "\\t": "\t"}


class Node:
    """A regex AST node with its source text and a sampler of (mostly) matching strings."""

    def __init__(self, src, sample):
        self.src, self.sample = src, sample


def rx_class(r):
    neg = maybe(r, 0.25)
    items, members = [], []
    n = r.randint(1, 3)
    for j in range(n):
        x = r.random()
        if x < 0.35:
            c = pick(r, "abc1_ ")
            items.append(c)
            members.append(c)
        elif x < 0.65:
            lo, hi = pick(r, [("a", "c"), ("0", "9"), ("a", "z"), ("A", "Z"), ("b", "b"), (" ", "/"), ("1", "b")])
            items.append(f"{lo}-{hi}")
            members.append(lo)
            members.append(hi)
        elif x < 0.8:
            e = pick(r, ESC_CLASSES[:1] + ESC_CLASSES[2:3] + ESC_CLASSES[4:5] + ESC_CLASSES)
            if not KNOWN and j < n - 1:
                e = "x"  # a class escape followed by another item could be followed by '-' (HLP-7)
            items.append(e)
            members.append({"\\d": "1", "\\w": "a", "\\s": " ", "\\D": "a", "\\W": "-", "\\S": "b", "x": "x"}[e])
        elif x < 0.9:
            e = pick(r, ["\\]", "\\-", "\\\\", "\\.", "\\^", "\\n"])
            items.append(e)
            members.append(LIT_OF.get(e, e[1]))
        else:
            c = pick(r, ".$*+?()|{}^") if j > 0 else pick(r, ".$*+?()|{}")
            items.append(c)
            members.append(c)
    if maybe(r, 0.1):
        items.append("-")
        members.append("-")
    if maybe(r, 0.08):
        items.insert(0, "]")
        members.append("]")
        if not KNOWN and len(items) > 1 and items[1].startswith("-"):
            items.pop(1)  # `]-x` at the start of a set (HLP-8)
    if not KNOWN:
        # no literal '-' right after a class escape (HLP-7)
        for a, b in zip(items, items[1:]):
            if a in ESC_CLASSES and b.startswith("-"):
                items.remove(b)
                break
    src = "[" + ("^" if neg else "") + "".join(items) + "]"
    if neg:
        return Node(src, lambda: pick(r, "abc1 -_xZ9."))
    return Node(src, lambda: pick(r, members))


def rx_atom(r, depth):
    x = r.random()
    if x < 0.40:
        c = pick(r, ALPHA)
        return Node(c, lambda: c)
    if x < 0.50:
        return Node(".", lambda: pick(r, ALPHA + "\n"))
    if x < 0.65:
        return rx_class(r)
    if x < 0.75:
        e = pick(r, ESC_CLASSES)
        return Node(e, lambda: pick(r, {"\\d": "0159", "\\D": "ab -", "\\w": "ab1_", "\\W": " -.",
                                         "\\s": " \t\n", "\\S": "ab1-"}[e]))
    if x < 0.82:
        e = pick(r, ESC_LITS)
        return Node(e, lambda: LIT_OF.get(e, e[1]))
    if x < 0.85:
        c = pick(r, "{}],:=<>!#")  # literal outside a set, when nothing makes them special
        if not KNOWN and c == "{":
            c = "}"  # `{` where a repeat could start (HLP-6)
        return Node(c, lambda: c)
    if depth <= 0:
        c = pick(r, ALPHA)
        return Node(c, lambda: c)
    inner = rx_alt(r, depth - 1)
    opener = "(?:" if maybe(r, 0.4) else "("
    return Node(opener + inner.src + ")", inner.sample)


def rx_quant(r, depth):
    a = rx_atom(r, depth)
    x = r.random()
    if x < 0.55:
        return a
    if x < 0.65:
        return Node(a.src + "*", lambda: "".join(a.sample() for _ in range(r.randint(0, 3))))
    if x < 0.75:
        return Node(a.src + "+", lambda: "".join(a.sample() for _ in range(r.randint(1, 3))))
    if x < 0.85:
        return Node(a.src + "?", lambda: a.sample() if maybe(r, 0.5) else "")
    lo = r.randint(0, 2)
    hi = lo + r.randint(0, 2)
    form = pick(r, ["{%d}" % lo, "{%d,}" % lo, "{,%d}" % hi, "{%d,%d}" % (lo, hi), "{0%d}" % lo])
    return Node(a.src + form, lambda: "".join(a.sample() for _ in range(r.randint(lo, max(lo, hi)))))


def rx_seq(r, depth):
    n = r.randint(0, 4) if maybe(r, 0.1) else r.randint(1, 4)
    parts = [rx_quant(r, depth) for _ in range(n)]
    return Node("".join(p.src for p in parts), lambda: "".join(p.sample() for p in parts))


def rx_alt(r, depth):
    n = 1 if maybe(r, 0.65) else r.randint(2, 3)
    alts = [rx_seq(r, depth) for _ in range(n)]
    return Node("|".join(a.src for a in alts), lambda: pick(r, alts).sample())


def rx_top(r):
    for _ in range(200):
        n = rx_alt(r, 2)
        src = n.src
        if maybe(r, 0.3):
            src = "^" + src
        if maybe(r, 0.6):
            src = src + "$"
        elif maybe(r, 0.05):
            src = src + "$" + pick(r, ["\\n", "a", ""])
        try:
            re.compile(src)
        except re.error:
            continue  # HA does not add such an entity; covered by hand-written cases
        if len(src) <= 60:
            return src, n.sample
    return "a", lambda: "a"


def mutate(r, s):
    if not s:
        return pick(r, ALPHA)
    k = r.randrange(len(s))
    x = r.random()
    if x < 0.35:
        return s[:k] + s[k + 1:]
    if x < 0.7:
        return s[:k] + pick(r, ALPHA + "\n.Z") + s[k + 1:]
    return s[:k] + pick(r, ALPHA + "\n") + s[k:]


def gen_pattern(r, i):
    src, sample = rx_top(r)
    steps = [{"setup": {"input_text": {"p": {"pattern": src, "max": 255}}}}]
    seen = set()
    for _ in range(40):
        if len(seen) >= 8:
            break
        x = r.random()
        s = sample()
        if x < 0.35:
            s = mutate(r, s)
        elif x < 0.45:
            s = s + pick(r, ["\n", "x", "\n\n", " "])
        elif x < 0.55:
            s = "".join(pick(r, ALPHA + "\n.") for _ in range(r.randint(0, 6)))
        if len(s) > 255 or s in seen:
            continue
        if not KNOWN and any(0x1c <= ord(c) <= 0x1f for c in s):
            continue
        seen.add(s)
        steps.append({"call": "input_text.set_value", "data": {"entity_id": "input_text.p", "value": s}})
    return {"name": f"rnd_pattern_{i}", "steps": steps}


# ---------------------------------------------------------------- several domains

def gen_mixed(r, i):
    """Two or three domains set up together; explicit entity ids of any domain
    in the calls (an entity of another domain is ignored by HA)."""
    doms = ["input_boolean", "counter", "timer", "input_number", "input_select", "input_text"]
    r.shuffle(doms)
    doms = doms[:r.randint(2, 3)]
    mini = {"input_boolean": lambda: pick(r, [None, {"initial": True}]),
            "counter": lambda: pick(r, [None, {"initial": 5, "step": 2}, {"minimum": 0, "maximum": 3}]),
            "timer": lambda: pick(r, [None, {"duration": 10}]),
            "input_number": lambda: {"min": 1, "max": 10, "step": pick(r, [1, 2.5])},
            "input_select": lambda: {"options": ["a", "b", "c"]},
            "input_text": lambda: pick(r, [None, {"initial": "t", "max": 5}])}
    svcs = {"input_boolean": [("turn_on", {}), ("turn_off", {}), ("toggle", {})],
            "counter": [("increment", {}), ("decrement", {}), ("reset", {}), ("set_value", {"value": 2})],
            "timer": [("start", {}), ("pause", {}), ("cancel", {}), ("finish", {}), ("start", {"duration": 3})],
            "input_number": [("increment", {}), ("decrement", {}), ("set_value", {"value": 4})],
            "input_select": [("select_next", {}), ("select_previous", {}), ("select_first", {}), ("select_last", {}),
                             ("select_option", {"option": "b"}), ("set_options", {"options": ["x", "b"]})],
            "input_text": [("set_value", {"value": "new"})]}
    steps, ents = [], []
    for d in doms:
        ids = slug_ids(r, r.randint(1, 2))
        steps.append({"setup": {d: {k: mini[d]() for k in ids}}})
        ents += [f"{d}.{k}" for k in ids]
    for _ in range(r.randint(5, 12)):
        if maybe(r, 0.2):
            steps.append({"advance": pick(r, [1, 2, 5, 10])})
            continue
        d = pick(r, doms)
        svc, extra = pick(r, svcs[d])
        x = r.random()
        own = [e for e in ents if e.startswith(d + ".")]
        if x < 0.5:
            t = pick(r, own)
        elif x < 0.7:
            t = pick(r, ents)
        elif x < 0.85:
            t = [pick(r, own), pick(r, [e for e in ents if not e.startswith(d + ".")])]
        elif KNOWN or len(doms) == 1:
            t = "all"
        else:
            t = pick(r, own)
        steps.append({"call": f"{d}.{svc}", "data": {"entity_id": t, **extra}})
    return {"name": f"rnd_mixed_{i}", "steps": steps}


def finite(v):
    """Non-finite floats as strings: the JSON-lines driver cannot read NaN/Infinity (HLP-18)."""
    if isinstance(v, float) and (v != v or v in (float("inf"), float("-inf"))):
        return str(v)
    if isinstance(v, dict):
        return {k: finite(x) for k, x in v.items()}
    if isinstance(v, list):
        return [finite(x) for x in v]
    return v


# ---------------------------------------------------------------- main

GENS = {"input_boolean": gen_input_boolean, "input_number": gen_input_number, "input_select": gen_input_select,
        "input_text": gen_input_text, "counter": gen_counter, "timer": gen_timer, "mixed": gen_mixed}


def main():
    global KNOWN
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-helper", type=int, default=80)
    ap.add_argument("--patterns", type=int, default=250)
    ap.add_argument("--include-known", action="store_true")
    a = ap.parse_args()
    KNOWN = a.include_known
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, g in GENS.items():
        r = random.Random(f"{a.seed}-{name}")
        cases = [g(r, f"s{a.seed}_{i}") for i in range(a.per_helper)]
        if not KNOWN:
            cases = finite(cases)
        (out / f"rnd_{name}.yaml").write_text(yaml.safe_dump(cases, sort_keys=False, allow_unicode=True, width=10000))
        total += len(cases)
    r = random.Random(f"{a.seed}-pattern")
    cases = [gen_pattern(r, f"s{a.seed}_{i}") for i in range(a.patterns)]
    (out / "rnd_pattern.yaml").write_text(yaml.safe_dump(cases, sort_keys=False, allow_unicode=True, width=10000))
    total += len(cases)
    print(f"seed {a.seed}: {total} cases in {out}")


if __name__ == "__main__":
    main()
