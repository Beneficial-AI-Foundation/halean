"""Seeded random generator of service-schema cases in the shipped YAML format.

    gen_random.py --seed N --schemas S --data D --out FILE.yaml [--warm]

Each case registers one service with a random schema spec drawn from the
supported subset (README line 335, left column; format in
HALean/Core/ServicesJson.lean) and makes D blocking calls with an echo handler.
Data are drawn half from an edge-case pool and half "aimed" at the schema
(members of an In, keys of a nested mapping, near-miss spellings).

Not generated, because the harness cannot carry them through JSON/YAML:
NaN and infinities (json.dumps writes `NaN`, which the engine's parser
refuses: README line 350), ints of more than 4300 digits (json.dumps raises),
non-string dict keys, lone surrogates.
Spec text is printable ASCII only (the decoder refuses anything else).

With --data above 50 a case crosses probatio's CompilePolicy.AUTO threshold
(the schema switches to generated code after 50 validations, README line 645).
"""
from __future__ import annotations

import argparse
import random

import yaml

TYPES = ["int", "float", "str", "bool", "object", "list", "dict", "timedelta", "any"]
CV = ["string", "boolean", "entity_id", "entity_ids", "color_hex", "slug", "positive_int",
      "positive_float", "small_float", "byte", "port", "ensure_list", "comp_entity_ids",
      "time_period", "time_period_str", "time_period_seconds", "time_period_dict",
      "positive_time_period", "positive_time_period_dict"]
KEYS = ["a", "b", "c", "name", "mode", "brightness", "entity_id", "color", "colour", "rgb_color",
        "odd key", "x.y", "with-dash", "_u", "9lives", "hours", "minutes", "seconds", "days",
        "milliseconds", "effect", "effects", "transition", "Mode", ""]
GROUPS = ["g", "grp", "color", "a b", "x.y"]
WORDS = ["heat", "cool", "auto", "off", "on", "heat_cool", "dry", "fan_only", "colorloop", "random",
         "none", "all", "a", "b", "ab", "abc", "abd", "Auto", "AUTO", "x", "", " ", "1", "true", "light",
         "switch", "it's", 'say "hi"', "a\\b", "tab\tx", "nl\n"]
NUMS = [0, 1, -1, 2, 3, 5, 10, 100, 255, 256, 65535, 65536, 0.0, -0.0, 0.5, 1.0, 1.5, 2.5, -2.5, 1e16,
        1e-5, 0.1, 1e22, 9007199254740993, 2 ** 63, 2 ** 64, 10 ** 30, -10 ** 30, 123456.789, 1e-7,
        5e-324, 1.7976931348623157e308, 9999999999999998.0, 1e15, 0.0001, 0.00001]
INT_STRS = ["0", "1", "-1", "+1", " 1", "1 ", " 12 ", "1_0", "1__0", "_1", "1_", "01", "007", "1.0", "1.5",
            "1e3", "1E3", "0x10", "0b1", "0o7", "", " ", "-", "+", "--1", "+-1", "1 0", "255", "256", "65535",
            "65536", "70000", "-0", "nan", "NaN", "inf", "-inf", "Infinity", "infinity", "+inf", "-nan",
            ".5", "5.", ".", "1.", "1e", "e1", "1e+5", "1e-5", "1e400", "1e-400", "1_0.5", "1._5", "1e1_0",
            "\t1\n", "1\r", "9" * 30, "1" + "0" * 400, "9" * 4300, "9" * 4301, "0" * 4301, "1,5", "1.5.2",
            "１２", "١٢٣", "1\x0b", "\x1f1", "1\xa0", "²", "1e16", "1e22", "0.1", "-0.0", "123456789.123456789"]
BOOL_STRS = ["true", "True", "TRUE", " true ", "false", "False", "yes", "Yes", "no", "on", "ON", "off",
             "enable", "disable", "enabled", "1", "0", " 1", "2", "y", "n", "t", "", " ", "tRuE", "on ",
             "\ton\n", "ｏｎ", "ON\xa0", "İ", "disable\x0c", "enable\x1c", "none", "null"]
ENTITY_STRS = ["light.kitchen", "Light.Kitchen", "LIGHT.KITCHEN", "light.kitchen ", " light.kitchen",
               "light.kitchen\n", "light.kitchen\n\n", "light.", ".kitchen", "light", "light.a.b", "light.a_b",
               "light._a", "light.a_", "_light.a", "light_.a", "light.a__b", "li__ght.a", "l__.a", "light.1",
               "1.1", "light.kit chen", "light.kitchen,switch.x", "light.kitchen, switch.x",
               " light.kitchen , Switch.X ", "light.kitchen,", ",", ",light.a", "light.a,,switch.b", "all",
               "ALL", "All", "none", "NONE", " all", "all ", "light.é", "light.ａ", "light.١", "light.a\x0b",
               "switch.x", "sensor.temp_1", "light.a-b", "light.A_B", "light.all", "", " ", "light.a\tb",
               "light.kitchen\r", "group.all_lights", "a.b", "a.b,c.d,e.f", "light.x\n,light.y"]
COLOR_STRS = ["#ff00ff", "#FF00FF", "#Ff00fF", "#ff00ff\n", "#ff00ff\n\n", "\n#ff00ff", "#ff00f", "#ff00fff",
              "ff00ff", "#gg0000", "# ff00f", "#ff00ff ", " #ff00ff", "#000000", "#12345G", "#１２３４５６",
              "##ff00f", "#ff 0ff", "#-12345", "#+12345", "#0x1234", "#ſaſaſa", "#ffﬀff"]
SLUG_STRS = ["abc", "abc_def", "Abc", "a b", "a-b", "a__b", "_a", "a_", "a.b", "1", "1,2", "1,234", "a,b",
             "1, 2", "it's", "a'b", "'a'", "''", "a''b", "", " ", "-", "_", "__", "a_b_c", "a--b", "a - b",
             "A_B", "a_1", "1_a", "a&b", "a&amp;b", "&amp;", "&#65;", "&#x41;", "a;b", "a&;b", "&a", "a;&",
             "é", "straße", "a\tb", "a\nb", "a\n", "x" * 60, "a,1", "1,a", ",1", "1,", "1,,2", "1,2,3",
             "12,345,678", "a1,2b", "unknown", "a!b", "a@b#c", "(a)", "a/b", "a\\b", "a\"b", "a`b", "a_-_b",
             "-a-", "_a_", "a\x00b", "a\x7fb", "~", "a+b", "a=b", "100%", "<b>", "&lt;b&gt;", "5.0", "1e5",
             "True", "None", "a_b-", "0", "a'-'b", "'-a", "a-'", "1'2", "1,'2", "'1,2'", "1',2"]
TIME_STRS = ["1:30", "01:30", "01:30:15", "1:30:15.5", "-1:30", "+1:30", "-00:00:01", "0:0", "0:0:0", "00:00",
             "24:00", "23:59:59.999999", "100:00:00", "1:60", "1:99:99", "1:-30", "-1:-30", "--1:30", "+-1:30",
             "-+1:30", " 1:30", "1:30 ", "1 :30", "1: 30", " -1:30", "- 1:30", "1:2:3:4", "1", ":", "::",
             ":30", "1:", "1::", ":1:", "a:b", "1:b", "1:30:x", "1.5:30", "1:30.5", "1:30:1e2", "1:30:1_0",
             "1_0:30", "1:3_0", "1:30:.5", "1:30:5.", "1:30:-5", "1:30:+5", "1:30: 5 ", "1:30:nan",
             "1:30:inf", "1:30:-inf", "1:30:1e400", "99999999999:00", "9999999999999999999:00",
             "0:99999999999999", "0:0:1e15", "0:0:1e16", "0:0:0.0000005", "0:0:0.0000015",
             "0:0:0.0000025", "0:0:0.9999995", "0:0:59.9999999", "0:0:1.0000005", "-0:0:0.0000005",
             "0:0:0.1", "0:0:0.000001", "0:0:1e-7", "0:0:2.5e-6", "0:0:86399.9999995", "١:٣٠", "1:30\n",
             "\t1:30", "01:30:15.123456789", "0:0:0.5000005", "-0:0:0.0000015", "2399999976:00",
             "23999999976:0:0", "-23999999976:0:0", "0:" + "9" * 4301, "9" * 4301 + ":0", "0:0:" + "9" * 400,
             "5", "5.5", "-5", "1e3", "1e15", "1e16", "86399999999999", "86400000000000", "0.0000005",
             "1.0000005", "nan", "inf", "-inf", "", " ", "1e400", "abc", " 7 ", "1_0", "0x1"]
UNI_STRS = ["é", "ÉCOLE", "ß", "İ", "ǅ", "Σ", "ς", "\xa0", "​", "\x85", " ", "😀", "ＡＢ", "Ω", "K",
            "a\x0bb", "a\x0cb", "\x1c", "\x1f", "\x00", "\x7f", "\x1b[0m"]


def scalar(r: random.Random):
    k = r.random()
    if k < 0.08:
        return None
    if k < 0.18:
        return r.choice([True, False])
    if k < 0.45:
        return r.choice(NUMS + [r.randint(-5, 300), r.randint(-10 ** 6, 10 ** 6), round(r.uniform(-3, 300), r.randint(0, 6)),
                                r.uniform(-1e-6, 1e-6), r.uniform(-1e20, 1e20)])
    if k < 0.96:
        return r.choice(r.choice([WORDS, INT_STRS, BOOL_STRS, ENTITY_STRS, COLOR_STRS, SLUG_STRS, TIME_STRS, KEYS]))
    return r.choice(UNI_STRS)


def value(r: random.Random, depth: int = 0):
    k = r.random()
    if depth >= 2 or k < 0.72:
        return scalar(r)
    if k < 0.86:
        return [value(r, depth + 1) for _ in range(r.choice([0, 1, 1, 2, 3]))]
    return {r.choice(KEYS + WORDS): value(r, depth + 1) for _ in range(r.choice([0, 1, 1, 2, 3]))}


def spec_scalar(r: random.Random):
    """A scalar that may appear in a spec: printable ASCII text, finite numbers."""
    k = r.random()
    if k < 0.08:
        return None
    if k < 0.18:
        return r.choice([True, False])
    if k < 0.45:
        return r.choice(NUMS + [r.randint(-5, 300), round(r.uniform(-3, 300), r.randint(0, 3))])
    return r.choice([w for w in WORDS + KEYS + ["light.kitchen", "1:30", "#ff00ff", "1.0", "True", "None"]
                     if all(32 <= ord(c) < 127 for c in w)])


def num(r: random.Random):
    return r.choice([0, 1, -1, 5, 10, 100, 255, 0.0, 0.5, 1.0, 1.5, -2.5, 1e16, 1e-5, 2 ** 53, 10 ** 30, 1e22,
                     r.randint(-10, 300), round(r.uniform(-5, 300), 2)])


def bounds(r: random.Random, flags: bool) -> dict:
    out = {}
    if r.random() < 0.75:
        out["min"] = num(r)
    if r.random() < 0.75:
        out["max"] = num(r)
    if r.random() < 0.1:
        out[r.choice(["min", "max"])] = None
    if flags:
        if r.random() < 0.3:
            out["min_included"] = r.choice([True, False])
        if r.random() < 0.3:
            out["max_included"] = r.choice([True, False])
    return out


def members(r: random.Random) -> list:
    k = r.random()
    if k < 0.45:
        pool = [w for w in WORDS if all(32 <= ord(c) < 127 for c in w)]
        return r.sample(pool, r.randint(0, 7))
    if k < 0.6:
        return [r.choice(NUMS + [True, False]) for _ in range(r.randint(1, 6))]
    if k < 0.7:
        n = r.choice([39, 40, 41, 45])
        return r.sample(range(-20, 200), n) if r.random() < 0.5 else [f"opt{i}" for i in r.sample(range(100), n)]
    return [spec_scalar(r) for _ in range(r.randint(0, 6))]


def validator(r: random.Random, depth: int = 0):
    k = r.random()
    leafy = depth >= 3
    if k < 0.14:
        return r.choice(TYPES)
    if k < 0.16:
        return {"type": r.choice(TYPES)}
    if k < 0.22:
        return {"literal": spec_scalar(r)}
    if k < 0.34:
        return {"in": members(r)}
    if k < 0.38:
        return {"not_in": members(r)}
    if k < 0.45:
        return {"range": bounds(r, True)}
    if k < 0.48:
        return {"clamp": bounds(r, False)}
    if k < 0.52:
        out = {}
        if r.random() < 0.7:
            out["min"] = r.choice([0, 1, 2, 3, -1, 5])
        if r.random() < 0.7:
            out["max"] = r.choice([0, 1, 2, 3, -1, 5, 10])
        return {"length": out}
    if k < 0.58:
        return {"coerce": r.choice(["int", "float", "str"])}
    if k < 0.62:
        return {r.choice(["lower", "upper", "ensure_list", "port"]): None}
    if k < 0.64:
        return {"at_least_one": r.sample(KEYS, r.randint(1, 3))}
    if k < 0.80 or leafy:
        if r.random() < 0.12:
            dom = r.choice(["light", "switch", ["light", "switch"], ["light"], [], "all", "light.x", ""])
            return {"cv": "entity_domain", "domain": dom}
        return {"cv": r.choice(CV)}
    if k < 0.86:
        return {"dict": fields(r, depth + 1)}
    if k < 0.91:
        return {"list": [validator(r, depth + 1) for _ in range(r.choice([0, 1, 1, 1, 2, 2, 3]))]}
    if k < 0.96:
        return {"all": [validator(r, depth + 1) for _ in range(r.choice([0, 1, 2, 2, 3]))]}
    return {"any": [validator(r, depth + 1) for _ in range(r.choice([0, 1, 2, 2, 3]))]}


def fields(r: random.Random, depth: int = 0) -> list:
    n = r.choice([1, 1, 2, 2, 3, 4]) if depth else r.choice([1, 2, 2, 3, 3, 4, 5])
    keys = r.sample(KEYS, n)
    group = r.choice(GROUPS)
    out = []
    for key in keys:
        f = {"key": key}
        v = validator(r, depth)
        if isinstance(v, str) and r.random() < 0.7:
            f["type"] = v
        else:
            f["value"] = v
        m = r.random()
        if m < 0.2:
            f["required"] = True
        elif m < 0.3:
            f["exclusive"] = group if r.random() < 0.8 else r.choice(GROUPS)
            if r.random() < 0.4:
                f["group_required"] = r.choice([True, False])
        elif m < 0.4:
            f["inclusive"] = group if r.random() < 0.8 else r.choice(GROUPS)
        if r.random() < 0.2:
            f["default"] = aimed(r, v, depth) if r.random() < 0.6 else value(r, 1)
        out.append(f)
    return out


def near(r: random.Random, s: str) -> str:
    """A near miss of a string (for "did you mean")."""
    if not s:
        return r.choice(["", "a", " "])
    i = r.randrange(len(s))
    k = r.random()
    if k < 0.25:
        return s[:i] + s[i + 1:]
    if k < 0.5:
        return s[:i] + r.choice("abcxyz_ 1") + s[i:]
    if k < 0.7:
        return s[:i] + r.choice("abcxyz_1") + s[i + 1:]
    if k < 0.8:
        return s.upper()
    if k < 0.9:
        return s + s
    return s[::-1]


def aimed(r: random.Random, v, depth: int = 0):
    """Data aimed at a validator: mostly values it accepts or nearly accepts."""
    if r.random() < 0.15 or depth > 4:
        return value(r, 1)
    if isinstance(v, str):
        v = {"type": v}
    (name, arg), *_ = v.items()
    if name == "type":
        return {"int": lambda: r.choice([0, 1, -5, True, 1.0, "1", 10 ** 30]),
                "float": lambda: r.choice([0, 1, 1.5, True, "1.5", 10 ** 400, 2 ** 53 + 1, -0.0]),
                "str": lambda: r.choice(WORDS + [1, None]),
                "bool": lambda: r.choice([True, False, 1, 0, "true"]),
                "list": lambda: r.choice([[], [1], {}, "a", None]),
                "dict": lambda: r.choice([{}, {"a": 1}, [], "a", None]),
                "timedelta": lambda: r.choice([1, "1:00", {"hours": 1}]),
                }.get(arg, lambda: value(r, 1))()
    if name == "literal":
        return r.choice([arg, arg, value(r, 2), near(r, arg) if isinstance(arg, str) else arg,
                         float(arg) if isinstance(arg, int) and abs(arg) < 2 ** 53 else arg,
                         int(arg) if isinstance(arg, float) and abs(arg) < 1e15 else arg])
    if name in ("in", "not_in"):
        if arg and r.random() < 0.85:
            m = r.choice(arg)
            if isinstance(m, str):
                return r.choice([m, near(r, m), near(r, m), near(r, near(r, m))])
            if isinstance(m, bool):
                return r.choice([m, int(m), float(m)])
            if isinstance(m, int) and abs(m) < 2 ** 53:
                return r.choice([m, float(m), m + 1, str(m), bool(m) if m in (0, 1) else m])
            if isinstance(m, float) and abs(m) < 1e15:
                return r.choice([m, int(m), m + 0.5, str(m)])
            return m
        return scalar(r)
    if name in ("range", "clamp"):
        bs = [b for b in (arg.get("min"), arg.get("max")) if b is not None]
        c = [0, 1, True, False, None, "5", [], 1.5, 10 ** 400, -10 ** 400, 5e-324]
        for b in bs:
            c += [b, b, b + 1, b - 1, b + 0.5, b - 0.5, float(b) if abs(b) < 1e300 else b]
            if isinstance(b, float) and abs(b) < 1e15:
                c.append(int(b))
        return r.choice(c)
    if name == "length":
        n = r.choice([0, 1, 2, 3, 5, 6, 10, 11])
        return r.choice(["x" * n, [1] * n, {str(i): i for i in range(n)}, n, None, True, 1.5])
    if name == "coerce":
        return r.choice(INT_STRS + NUMS + [True, False, None, [], {}, [1], "x", 10 ** 400, -10 ** 400, 2 ** 1024, 2 ** 1024 - 1])
    if name in ("lower", "upper"):
        return r.choice(WORDS + UNI_STRS + [1, 1.5, None, True, ["A"], {"A": "B"}, 1e16])
    if name == "ensure_list":
        return value(r, 0)
    if name == "port":
        return r.choice([0, 1, 80, 65535, 65536, -1, "80", " 80 ", "8_0", 80.0, 80.5, True, False, None, "http",
                         1e5, 1.0, "65535", "65536", "0", [], 8.0e1, "80.0", 2 ** 64, 65535.0, 65535.5, 0.5, 1e400 if False else 1e300, "+80"])
    if name == "at_least_one":
        ks = arg + KEYS[:3]
        return r.choice([{k: 1 for k in r.sample(ks, r.randint(0, min(3, len(ks))))}, [], "a", None, {}, 1])
    if name == "cv":
        return aimed_cv(r, arg)
    if name == "dict":
        return aimed_dict(r, arg, depth + 1)
    if name == "list":
        if r.random() < 0.1:
            return value(r, 1)
        return [aimed(r, r.choice(arg), depth + 1) if arg else value(r, 2) for _ in range(r.choice([0, 1, 1, 2, 3]))]
    if name in ("all", "any"):
        return aimed(r, r.choice(arg), depth + 1) if arg else value(r, 1)
    return value(r, 1)


def aimed_cv(r: random.Random, name: str):
    if name in ("string",):
        return r.choice(WORDS + UNI_STRS + NUMS + [None, True, False, [], {}, ["a"], {"a": 1}])
    if name == "boolean":
        return r.choice(BOOL_STRS * 2 + [True, False, 0, 1, 2, -1, 0.0, -0.0, 0.5, 1e-320, None, [], {}, [True], 10 ** 30])
    if name in ("entity_id",):
        return r.choice(ENTITY_STRS * 3 + [None, 1, 1.5, True, [], {}, ["light.a"]])
    if name in ("entity_ids", "comp_entity_ids", "entity_domain"):
        k = r.random()
        if k < 0.45:
            return r.choice(ENTITY_STRS)
        if k < 0.8:
            return [r.choice(ENTITY_STRS + [None, 1, 1.5, True, ["light.a"], {}]) for _ in range(r.choice([0, 1, 1, 2, 3]))]
        if k < 0.9:
            return {r.choice(ENTITY_STRS): r.choice([1, None]) for _ in range(r.choice([0, 1, 2]))}
        return r.choice([None, 1, 1.5, True, False, 0])
    if name == "color_hex":
        return r.choice(COLOR_STRS * 3 + [None, 1, 123456, 1.5, True, [], {}, ["#ff00ff"]])
    if name == "slug":
        return r.choice(SLUG_STRS * 4 + [None, 1, 1.5, True, False, [], {}, ["a"], {"a": 1}, 1e16, -1, 10 ** 30, 0.0, -0.0, 1e-5])
    if name in ("positive_int", "byte", "port"):
        return r.choice(INT_STRS + NUMS + [True, False, None, [], {}, -0.5, -1e-320, 255.9, 256.0, -0.9, 65535.9])
    if name in ("positive_float", "small_float"):
        return r.choice(INT_STRS + NUMS + [True, False, None, [], {}, -0.5, -1e-320, 1.0000000000000002, 0.9999999999999999, 10 ** 400, -10 ** 400])
    if name == "ensure_list":
        return value(r, 0)
    if name == "time_period_dict" or name == "positive_time_period_dict" or (name.endswith("time_period") and r.random() < 0.3):
        units = ["days", "hours", "minutes", "seconds", "milliseconds"]
        k = r.random()
        if k < 0.1:
            return r.choice([{}, [], None, "x", 1, {"weeks": 1}, {"second": 1}, {"hours": 1, "x": 2}, {"Hours": 1}])
        d = {}
        for u in r.sample(units, r.randint(1, 3)):
            d[u] = r.choice([0, 1, -1, 1.5, 0.5, "1", "1.5", " 2 ", "x", None, True, 1e-7, 0.0000005, 0.0000015,
                             2.5, 1e9, 1e15, 999999999, 1000000000, -999999999, -1000000000, "1e3", "nan", "inf",
                             1e300, 10 ** 400, 0.1, 0.7, 1 / 3, 86399.9999995, [], 59.9999999, 0.001, 0.0005, 0.0015,
                             0.0025, -0.0005, 1e-3, 123456.789, "1_0", "é"])
        if r.random() < 0.1:
            d[r.choice(["weeks", "second", "x", "microseconds"])] = 1
        return d
    # time_period, time_period_str, time_period_seconds, positive_time_period
    return r.choice(TIME_STRS * 3 + NUMS + [True, False, None, [], {}, -1, -0.0000005, 0.0000005, 1.0000005,
                                             86399.9999995, 1e15, 1e16, -1e15, 86399999999999, 86400000000000,
                                             8.64e13, 8.6399999999999e13, 10 ** 400, -10 ** 400, 1e300, 0.1, 2.5e-6,
                                             1.5e-6, 3.5e-6, 0.5e-6, 1e-7, 123456789.123456789, 5e-324])


def aimed_dict(r: random.Random, fs: list, depth: int):
    if r.random() < 0.06:
        return value(r, 1)
    d = {}
    order = list(fs)
    if r.random() < 0.3:
        r.shuffle(order)
    for f in order:
        p = 0.9 if f.get("required") else 0.6
        if r.random() < p:
            d[f["key"]] = aimed(r, f.get("value", f.get("type")), depth)
    k = r.random()
    if k < 0.12 and fs:
        d[near(r, r.choice(fs)["key"])] = scalar(r)
    elif k < 0.2:
        d[r.choice(KEYS + UNI_STRS[:6])] = scalar(r)
    return d


def case(r: random.Random, idx: int, ndata: int, seed: int) -> dict:
    fs = fields(r, 0)
    spec = {"fields": fs}
    e = r.random()
    if e < 0.2:
        spec["extra"] = "allow"
    elif e < 0.35:
        spec["extra"] = "remove"
    elif e < 0.45:
        spec["extra"] = "prevent"
    call = {"op": "call", "domain": "rnd", "service": "s", "blocking": True, "return_response": True}
    ops = [{"op": "register", "domain": "rnd", "service": "s", "handler": {"echo": True},
            "supports_response": "only", "schema": spec}]
    for _ in range(ndata):
        d = aimed_dict(r, fs, 0)
        ops.append({**call, "data": d if isinstance(d, dict) else {}})
    return {"name": f"rnd_{seed}_{idx}", "ops": ops}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--schemas", type=int, default=400)
    ap.add_argument("--data", type=int, default=12)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    r = random.Random(a.seed)
    cases = [case(r, i, a.data, a.seed) for i in range(a.schemas)]
    text = yaml.safe_dump(cases, default_flow_style=None, allow_unicode=False, width=200, sort_keys=False)
    back = yaml.safe_load(text)
    assert repr(back) == repr(cases), "YAML does not round-trip the generated cases"
    with open(a.out, "w") as fh:
        fh.write(text)
    print(f"seed {a.seed}: {len(cases)} schemas, {sum(len(c['ops']) - 1 for c in cases)} schema/data pairs -> {a.out}")


if __name__ == "__main__":
    main()
