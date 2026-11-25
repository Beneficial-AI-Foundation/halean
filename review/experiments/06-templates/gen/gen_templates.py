#!/usr/bin/env python3
"""Seeded random template generator for the supported subset (README lines 237-255).

usage: gen_templates.py SEED COUNT OUT.jsonl

Each line is one case in the shipped format (as JSON): name, template, and optionally states, variables,
now, parse_result, condition, render_info.  The grammar is typed loosely: an expression generator per
value kind (number, string, bool, list, dict, datetime, timedelta), with a small probability of picking
another kind so that error paths (TypeError, UndefinedError, ...) are exercised too.  Literals come from
edge-case pools.  Exponents, repetition counts and ranges are kept small so that no template is slow or
large in either engine.
"""
import json
import random
import sys
from datetime import datetime, timedelta, timezone

INTS = ["0", "1", "2", "3", "7", "10", "12", "60", "100", "255", "1000", "86400", "2147483648",
        "1000000000000000000", "10000000000000000000000000", "-1", "-2", "-7"]
FLOATS = ["0.0", "0.1", "0.5", "1.5", "2.5", "3.5", "2.675", "1.005", "0.125", "1e16", "1e-5", "1e22",
          "123456.789", "3.0", "99.99", "1e-7", "0.30000000000000004", "1.7976931348623157e308", "5e-324",
          "-0.5", "-2.5", "-0.0", "4.35", "1e15", "9007199254740993.0"]
STRS = ["", "a", "abc", "Hello World", " pad ", "12", "3.5", "-7", "1e3", "nan", "inf", "on", "off",
        "unknown", "unavailable", "true", "None", "[1, 2]", "sensor.a", "light.b", "a,b,c", "it's",
        "x_y z", "007", "1_000", "0.50", "+5", " 42 ", "TRUE", "yes", "0", "1", "A-b c", "foo bar baz",
        "12:30", "2026-11-20T10:00:00+00:00", "2026-07-04 12:00:00", "1:02:03", "P1DT2H", "90", "é",
        "sensor.missing", "{'a': 1}", "(1, 2)", "1,5", ".5", "5.", "--1", "0x10", "1e400"]
ENTITIES = ["sensor.a", "sensor.b", "sensor.c", "light.a", "light.b", "switch.c", "binary_sensor.d", "group.g"]
STATES = ["on", "off", "unknown", "unavailable", "21.5", "0", "-3", "42", "home", "1e3", "", "19.26", "100", "7"]
STRFTIME = ["%Y", "%m", "%d", "%H", "%M", "%S", "%y", "%j", "%a", "%A", "%b", "%B", "%p", "%I", "%f", "%z",
            "%w", "%u", "%e", "%F", "%T", "%R", "%D", "%%", "%-d", "%-H", "%-m", "%-I", "%-M", "%-S", "%-j"]
STRPTIME = ["%Y", "%m", "%d", "%H", "%M", "%S", "%y", "%j", "%a", "%A", "%b", "%B", "%f", "%z", "%I %p"]


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.vars = []      # names bound in the template so far
        self.states = []
        self.variables = {}

    def pick(self, xs):
        return self.r.choice(xs)

    def chance(self, p):
        return self.r.random() < p

    def q(self, s):
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"

    # ---- literals ----------------------------------------------------------
    def lit_num(self):
        return self.pick(INTS) if self.chance(0.55) else self.pick(FLOATS)

    def lit_str(self):
        return self.q(self.pick(STRS))

    def entity(self):
        if self.states and self.chance(0.8):
            return self.pick(self.states)["entity_id"]
        return self.pick(ENTITIES + ["sensor.nope", "Sensor.A", "bad", "light.B"])

    # ---- typed expressions ---------------------------------------------------
    def any(self, d):
        return self.pick([self.num, self.str, self.bool, self.list, self.dict, self.dt, self.td, self.misc])(d)

    def maybe(self, f, d):
        return self.any(d) if self.chance(0.07) else f(d)

    def num(self, d):
        if d <= 0:
            return self.lit_num()
        c = self.r.randrange(22)
        a = lambda: self.maybe(self.num, d - 1)
        if c < 5:
            return self.lit_num()
        if c < 9:
            return f"({a()} {self.pick(['+', '-', '*', '/', '//', '%'])} {a()})"
        if c == 9:
            return f"({a()} ** {self.pick(['2', '3', '0', '-1', '0.5', '-2', '1.5'])})"
        if c == 10:
            return f"(-{a()})"
        if c == 11:
            return f"({self.maybe(self.str, d - 1)} | {self.pick(['int', 'int(0)', 'int(default=-1)', 'float', 'float(0)', 'float(default=none)'])})"
        if c == 12:
            p = self.pick(["", "(1)", "(2)", "(0)", "(-1)", "(3)", "(1, 'floor')", "(1, 'ceil')", "(0, 'half')",
                           "(2, 'common')", "(0, 'ceil')", "(0, 'floor')", "(default=0)", "(2, default=0)"])
            return f"({a()} | round{p})"
        if c == 13:
            return f"({a()} | abs)"
        if c == 14:
            return f"({self.maybe(self.list, d - 1)} | {self.pick(['length', 'sum', 'min', 'max', 'first', 'last', 'count'])})"
        if c == 15:
            return f"({self.maybe(self.str, d - 1)} | length)"
        if c == 16:
            return f"(states({self.q(self.entity())}) | {self.pick(['float(0)', 'int(0)', 'float', 'int', 'round(1, default=0)'])})"
        if c == 17:
            return f"({self.maybe(self.td, d - 1)}.total_seconds())"
        if c == 18:
            return f"{self.pick(['int', 'float'])}({self.any(d - 1)}, {self.pick(['0', 'none', '-1.5'])})"
        if c == 19:
            return f"({a()} if {self.bool(d - 1)} else {a()})"
        if c == 20:
            return f"{self.pick(['min', 'max'])}({a()}, {a()})"
        return self.var_or(self.lit_num)

    def str(self, d):
        if d <= 0:
            return self.lit_str()
        c = self.r.randrange(22)
        a = lambda: self.maybe(self.str, d - 1)
        if c < 5:
            return self.lit_str()
        if c == 5:
            return f"({self.any(d - 1)} ~ {self.any(d - 1)})"
        if c == 6:
            return f"({a()} | {self.pick(['lower', 'upper', 'title', 'capitalize', 'trim', 'string'])})"
        if c == 7:
            return f"({a()} | replace({self.lit_str()}, {self.lit_str()}{self.pick(['', ', 1', ', 2'])}))"
        if c == 8:
            return f"({self.maybe(self.list, d - 1)} | join({self.pick(['', self.q(', '), self.q('-')])}))"
        if c == 9:
            return f"states({self.q(self.entity())})"
        if c == 10:
            dom, obj = self.pick([s["entity_id"] for s in self.states] or ["sensor.zz"]).split(".")
            return f"states.{dom}.{obj}.{self.pick(['state', 'name', 'entity_id', 'domain', 'object_id'])}"
        if c == 11:
            return f"({a()}.{self.pick(['lower()', 'upper()', 'strip()', 'title()', 'capitalize()', 'lstrip()', 'rstrip()'])})"
        if c == 12:
            return f"({a()}[{self.pick(['0', '-1', '1:', ':2', '::-1', '1:-1', '::2', '5', '-9:'])}])"
        if c == 13:
            return f"({a()} + {a()})"
        if c == 14:
            return f"({a()} * {self.pick(['0', '1', '2', '3', '-1'])})"
        if c == 15:
            return f"({self.any(d - 1)} | string)"
        if c == 16:
            return f"({self.maybe(self.dt, d - 1)}.{self.pick(['isoformat()', 'strftime(' + self.q(self.fmt()) + ')'])})"
        if c == 17:
            return f"({self.maybe(self.num, d - 1)} | {self.pick(['timestamp_local', 'timestamp_utc', 'timestamp_custom(' + self.q(self.fmt()) + ')', 'timestamp_custom(' + self.q(self.fmt()) + ', false)', 'timestamp_utc(default=none)'])})"
        if c == 18:
            x = self.pick(["relative_time(%s)", "time_since(%s)", "time_since(%s, 2)", "time_until(%s)",
                           "time_until(%s, 3)", "time_since(%s, 0)", "time_until(%s, 0)"])
            return x % f"({self.dt(0)} {self.pick(['+', '-'])} {self.td(1)})"
        if c == 19:
            return f"({self.maybe(self.td, d - 1)} | timedelta_string{self.pick(['', '(2)', '(0)', '(3)'])})"
        if c == 20:
            return f"({a()} if {self.bool(d - 1)} else {a()})"
        return self.var_or(self.lit_str)

    def bool(self, d):
        if d <= 0:
            return self.pick(["true", "false"])
        c = self.r.randrange(20)
        if c < 2:
            return self.pick(["true", "false", "none"])
        if c < 5:
            f = self.pick([self.num, self.str, self.num])
            return f"({self.maybe(f, d - 1)} {self.pick(['==', '!=', '<', '<=', '>', '>='])} {self.maybe(f, d - 1)})"
        if c == 5:
            return f"({self.any(d - 1)} {self.pick(['in', 'not in'])} {self.pick([self.list, self.str, self.dict])(d - 1)})"
        if c == 6:
            return f"({self.bool(d - 1)} {self.pick(['and', 'or'])} {self.any(d - 1)})"
        if c == 7:
            return f"(not {self.any(d - 1)})"
        if c == 8:
            t = self.pick(["defined", "none", "number", "string", "integer", "float", "boolean", "mapping",
                           "sequence", "iterable", "even", "odd", "true", "false", "is_number", "datetime",
                           "divisibleby 3", "eq 1", "ne 'a'", "gt 2", "ge 2.5", "lt 'b'", "le 0", "in [1, 'a', none]"])
            return f"({self.any(d - 1)} is {self.pick(['', 'not '])}{t})"
        if c == 9:
            return f"is_state({self.q(self.entity())}, {self.pick([self.q(self.pick(STATES)), '[' + self.q('on') + ', ' + self.q('home') + ']'])})"
        if c == 10:
            return f"has_value({self.q(self.entity())})"
        if c == 11:
            return f"({self.any(d - 1)} | {self.pick(['bool(none)', 'bool(false)', 'is_number', 'bool(default=true)'])})"
        if c == 12:
            return f"({self.q(self.entity())} is {self.pick(['has_value', 'is_state(' + self.q(self.pick(STATES)) + ')'])})"
        if c == 13:
            return f"({self.maybe(self.str, d - 1)}.{self.pick(['startswith', 'endswith'])}({self.lit_str()}))"
        if c == 14:
            return f"({self.dt(d - 1)} {self.pick(['<', '>', '==', '<=', '>=', '!='])} {self.dt(d - 1)})"
        if c == 15:
            return f"({self.td(d - 1)} {self.pick(['<', '>', '==', '!='])} {self.td(d - 1)})"
        if c == 16:
            return f"is_state_attr({self.q(self.entity())}, {self.q(self.pick(['b', 'unit', 'friendly_name', 'x']))}, {self.any(0)})"
        if c == 17:
            return f"({self.num(d - 1)} < {self.num(d - 1)} {self.pick(['<', '<=', '==', '>'])} {self.num(d - 1)})"
        if c == 18:
            return f"iif({self.any(d - 1)})"
        return self.var_or(lambda: "true")

    def list(self, d):
        if d <= 0:
            return self.pick(["[]", "[1, 2, 3]", "['b', 'A', 'c']", "[3, 1.5, 2]", "[none, 1]", "(1, 2)", "range(4)",
                              "[1, 'a']", "['12', '3.5', 'x']", "[true, false]", "[[1, 2], [0]]", "'abc'"])
        c = self.r.randrange(20)
        a = lambda: self.maybe(self.list, d - 1)
        if c < 3:
            f = self.pick([self.num, self.str, self.any, self.bool])
            xs = ", ".join(f(d - 1) for _ in range(self.r.randrange(0, 4)))
            return f"[{xs}]"
        if c == 3:
            f = self.pick([self.num, self.str])
            xs = ", ".join(f(d - 1) for _ in range(self.r.randrange(1, 4)))
            return f"({xs},)"
        if c == 4:
            return self.pick(["range(%d)" % self.r.randrange(0, 6), "range(1, %d)" % self.r.randrange(0, 7),
                              "range(10, 0, -%d)" % self.r.randrange(1, 4)])
        if c == 5:
            p = self.pick(["", "(reverse=true)", "(true)", "(case_sensitive=true)", "(false, true)"])
            return f"({a()} | sort{p})"
        if c == 6:
            return f"({a()} | {self.pick(['unique', 'reverse', 'select', 'reject'])} | list)"
        if c == 7:
            m = self.pick(["map('int', 0)", "map('float', 0)", "map('string')", "map('upper')", "map('abs')",
                           "map('round', 1, default=0)", "map('default', 0, true)", "map('length')", "map('int')",
                           "map('bool', none)", "map('is_number')", "map('trim')", "map('title')", "map('lower')"])
            return f"({a()} | {m} | list)"
        if c == 8:
            t = self.pick(["select('number')", "select('string')", "reject('none')", "select('gt', 1)",
                           "select('in', [1, 'a', 2.5])", "reject('eq', 'a')", "select('defined')", "select('odd')",
                           "reject('even')", "select('ge', 'b')", "select('is_number')", "reject('string')"])
            return f"({a()} | {t} | list)"
        if c == 9:
            return f"({self.maybe(self.str, d - 1)}.split({self.pick(['', self.q(','), self.q(' '), self.q(' ') + ', 1', self.q('-')])}))"
        if c == 10:
            return f"({a()}[{self.pick(['1:', ':2', '::-1', '::2', '-2:', '1:-1', ':-1', '5:'])}])"
        if c == 11:
            return f"({a()} + {a()})"
        if c == 12:
            return f"({self.maybe(self.dict, d - 1)}.{self.pick(['keys()', 'values()', 'items()'])} | list)"
        if c == 13:
            dom = self.pick(["sensor", "light", "switch", "binary_sensor", "zz"])
            attr = self.pick(["state", "entity_id", "name", "domain", "object_id", "attributes.b"])
            flt = self.pick(["", " | selectattr('state', 'eq', 'on')", " | rejectattr('state', 'in', ['unknown', 'unavailable'])",
                             " | selectattr('attributes.b', 'defined')"])
            return f"(states.{dom}{flt} | map(attribute='{attr}') | list)"
        if c == 14:
            return f"(states{self.pick(['', ' | selectattr(' + self.q('domain') + ', ' + self.q('eq') + ', ' + self.q('light') + ')'])} | map(attribute='entity_id') | list)"
        if c == 15:
            ds = ", ".join("{'a': %s, 'b': %s}" % (self.num(0), self.lit_str()) for _ in range(self.r.randrange(1, 4)))
            f = self.pick(["map(attribute='a')", "map(attribute='b')", "selectattr('a')", "selectattr('a', 'gt', 1)",
                           "rejectattr('b', 'eq', 'a')", "sort(attribute='a')", "sort(attribute='b', reverse=true)",
                           "map(attribute='c', default=0)", "unique(attribute='a')", "sort(attribute='a,b')",
                           "selectattr('c', 'defined')", "map(attribute='c')"])
            return f"([{ds}] | {f} | list)"
        if c == 16:
            return f"(expand({self.q(self.entity())}, {self.q(self.entity())}) | map(attribute='entity_id') | list)"
        if c == 17:
            return f"({self.maybe(self.str, d - 1)} | list)"
        if c == 18:
            return f"({a()} * {self.pick(['0', '1', '2'])})"
        return self.var_or(lambda: "[1, 2]")

    def dict(self, d):
        if d <= 0:
            return self.pick(["{}", "{'a': 1}", "{'b': 2, 'a': [1]}", "{1: 'x', 'k': none}"])
        c = self.r.randrange(6)
        if c < 3:
            ks = self.r.sample(["'a'", "'b'", "'c'", "1", "'k k'", "none", "2.5", "true"], self.r.randrange(0, 4))
            return "{" + ", ".join(f"{k}: {self.any(d - 1)}" for k in ks) + "}"
        if c == 3:
            return "dict(" + ", ".join(f"{k}={self.any(d - 1)}" for k in self.r.sample(["a", "b", "c"], self.r.randrange(0, 3))) + ")"
        if c == 4:
            dom, obj = self.pick([s["entity_id"] for s in self.states] or ["sensor.zz"]).split(".")
            return f"states.{dom}.{obj}.attributes"
        return self.var_or(lambda: "{'a': 1}")

    def fmt(self):
        return self.pick(["", " ", "-", ":", "/"]).join(self.pick(STRFTIME) for _ in range(self.r.randrange(1, 4)))

    def dt(self, d):
        c = self.r.randrange(16 if d > 0 else 6)
        if c < 2:
            return "now()"
        if c < 4:
            return "utcnow()"
        if c == 4:
            return "today_at(%s)" % self.pick(["", "'07:30'", "'23:59:59'", "'00:00'", "'12:00'", "'7:5'", "'24:00'"])
        if c == 5:
            return "as_datetime(%s)" % self.q(self.pick(["2026-11-20T10:00:00+00:00", "2026-11-20 10:00:00", "2026-12-25T08:15:30.5-08:00",
                                                          "2026-01-02 03:04", "2025-02-28T23:59:59Z", "1700000000", "1700000000.123456",
                                                          "nope", "2026-11-20T10:00:00+05:30", "2026-13-01 00:00:00"]))
        if c < 9:
            return f"({self.dt(d - 1)} {self.pick(['+', '-'])} {self.maybe(self.td, d - 1)})"
        if c == 9:
            k = self.pick(["hour=0", "minute=0, second=0, microsecond=0", "day=1", "hour=23, minute=59", "second=30",
                           "microsecond=999999", "month=12, day=31", "year=2030", "day=31", "hour=24"])
            return f"({self.dt(d - 1)}.replace({k}))"
        if c == 10:
            return f"as_local({self.dt(d - 1)})"
        if c == 11:
            return f"as_datetime({self.maybe(self.num, d - 1)})"
        if c == 12:
            ent = self.pick([s["entity_id"] for s in self.states] or ["sensor.zz"])
            dom, obj = ent.split(".")
            return f"states.{dom}.{obj}.{self.pick(['last_changed', 'last_updated'])}"
        if c == 13:
            # strptime with data that Python's own strftime made for the same format
            fmt = self.pick([" ", "-", "T", ":", "/", " x "]).join(self.r.sample(STRPTIME, self.r.randrange(1, 5)))
            t = datetime(self.r.randrange(1971, 2100), self.r.randrange(1, 13), self.r.randrange(1, 29), self.r.randrange(24),
                         self.r.randrange(60), self.r.randrange(60), self.r.randrange(1000000),
                         tzinfo=timezone(timedelta(minutes=self.pick([0, 60, -480, 330, -210]))))
            data = t.strftime(fmt)
            if self.chance(0.15):
                data = self.pick([data.lower(), data.upper(), data + " ", " " + data, data[:-1], data.replace(" ", "  ")])
            return f"strptime({self.q(data)}, {self.q(fmt)}{self.pick(['', ', none'])})"
        if c == 14:
            return f"({self.dt(d - 1)} if {self.bool(d - 1)} else {self.dt(d - 1)})"
        return f"as_datetime({self.maybe(self.str, d - 1)}, none)"

    def td(self, d):
        c = self.r.randrange(14 if d > 0 else 5)
        if c < 5:
            ks = self.r.sample(["days", "seconds", "microseconds", "milliseconds", "minutes", "hours", "weeks"], self.r.randrange(0, 4))
            return "timedelta(" + ", ".join(f"{k}={self.pick(['0', '1', '2', '-1', '30', '90', '1.5', '0.1', '-2.5', '1000', '45', '23', '59', '0.0000005', '3600', '86399', '400'])}" for k in ks) + ")"
        if c == 5:
            return f"({self.td(d - 1)} {self.pick(['+', '-'])} {self.td(d - 1)})"
        if c == 6:
            return f"({self.td(d - 1)} {self.pick(['*', '/', '//'])} {self.pick(['2', '3', '-1', '0.5', '1.5', '7', '0', '2.5', '1000000'])})"
        if c == 7:
            return f"({self.dt(d - 1)} - {self.dt(d - 1)})"
        if c == 8:
            return f"(-{self.td(d - 1)})"
        if c == 9:
            return f"({self.td(d - 1)} | abs)"
        if c == 10:
            return "as_timedelta(%s)" % self.q(self.pick(["1:02:03", "3 days, 4:05:06", "-1 day, 0:00:01", "90", "1.5", "0:00:01,250",
                                                           "-0:30", "P1DT2H3M4.5S", "-PT90M", "P1.5D", "3 days 04:05:06", "nope", "",
                                                           "1 day -01:00:00", "PT0.000001S", "100:00:00", "00:00:00.1234567", "2 days",
                                                           "1 day", "-5", "+P1D", "P1W", "10:61", "0:0:0", ":30", "1:", "1.", ",5"]))
        if c == 11:
            return f"({self.td(d - 1)} % {self.td(0)})"
        if c == 12:
            return f"({self.pick(['2', '0.5', '-3'])} * {self.td(d - 1)})"
        return f"as_timedelta({self.maybe(self.str, d - 1)})"

    def misc(self, d):
        c = self.r.randrange(10)
        if c == 0:
            return "none"
        if c == 1:
            return f"state_attr({self.q(self.entity())}, {self.q(self.pick(['b', 'unit', 'friendly_name', 'x', 'xs']))})"
        if c == 2:
            return f"({self.any(max(d - 1, 0))} | default({self.any(0)}{self.pick(['', ', true'])}))"
        if c == 3:
            return f"({self.any(max(d - 1, 0))} | iif({self.any(0)}, {self.any(0)}))"
        if c == 4:
            return f"({self.maybe(self.dict, max(d - 1, 0))}{self.pick(['.a', '[' + self.q('b') + ']', '.get(' + self.q('a') + ', 0)', '.zz', '[1]'])})"
        if c == 5:
            return f"({self.maybe(self.list, max(d - 1, 0))}[{self.pick(['0', '-1', '1', '9'])}])"
        if c == 6 and self.variables:
            k = self.pick(sorted(self.variables))
            return self.pick([k, k + ".id", k + ".missing", k + "[0]", k + ".xs"])
        if c == 7:
            return f"as_timestamp({self.pick([self.dt, self.str])(max(d - 1, 0))}{self.pick(['', ', none', ', 0'])})"
        if c == 8:
            ent = self.pick([s["entity_id"] for s in self.states] or ["sensor.zz"])
            return f"states[{self.q(ent)}]{self.pick(['.state', '.attributes.b', '.name', '.attributes'])}"
        return f"({self.any(max(d - 1, 0))} if {self.bool(max(d - 1, 0))})"

    def var_or(self, f):
        if self.vars and self.chance(0.7):
            return self.pick(self.vars)
        return f()

    # ---- statements --------------------------------------------------------
    def block(self, d):
        c = self.r.randrange(10)
        if c < 5 or d <= 0:
            return "{{ " + self.any(self.r.randrange(1, 4)) + " }}"
        if c == 5:
            s = "{% if " + self.bool(2) + " %}" + self.block(d - 1)
            if self.chance(0.4):
                s += "{% elif " + self.any(1) + " %}" + self.block(d - 1)
            if self.chance(0.6):
                s += "{% else %}" + self.block(d - 1)
            return s + "{% endif %}"
        if c == 6:
            v = "i%d" % len(self.vars)
            it = self.list(2)
            cond = (" if " + self.pick([f"{v} is number", f"{v} is string", f"{v} is not none", f"{v} != 1", "loop is undefined"])) if self.chance(0.3) else ""
            self.vars.append(v)
            body = self.pick(["{{ loop.index }}:", "{{ loop.index0 }}{{ loop.first }}{{ loop.last }}", "{{ loop.revindex }}/{{ loop.length }} ",
                              "", "{{ loop.previtem | default('-') }}>", "{% if loop.last %}.{% endif %}"]) + "{{ " + v + " }}"
            if self.chance(0.3):
                body += "{% if " + self.bool(1) + " %}{% " + self.pick(["break", "continue"]) + " %}{% endif %}"
            if self.chance(0.4):
                body += self.block(d - 1)
            body += self.pick(["", ",", " "])
            self.vars.remove(v)
            els = ("{% else %}" + self.pick(["empty", "{{ 0 }}"])) if self.chance(0.3) else ""
            return "{% for " + v + " in " + it + cond + " %}" + body + els + "{% endfor %}"
        if c == 7:
            v = "v%d" % len(self.vars)
            s = "{% set " + v + " = " + self.any(2) + " %}"
            self.vars.append(v)
            return s + self.block(d - 1)
        if c == 8:
            f = self.pick([("0", self.num, "ns.t + {x}"), ("''", self.str, "ns.t ~ {x}"), ("[]", self.any, "ns.t + [{x}]")])
            return ("{% set ns = namespace(t=" + f[0] + ") %}{% for n in " + self.list(1) + " %}{% set ns.t = "
                    + f[2].format(x=self.pick(["n", f[1](1)])) + " %}{% endfor %}{{ ns.t }}")
        return self.pick(["text ", " ", "-", "x={{ 1 }} ", "{# c #}", "\n"]) + self.block(d - 1) + self.pick(["", " ", " tail", "{{- '' }}", "{%- if true -%} {%- endif %}"])

    def case(self, name):
        self.vars = []
        self.states = []
        self.variables = {}
        for eid in self.r.sample(ENTITIES, self.r.randrange(0, 6)):
            st = {"entity_id": eid, "state": self.pick(STATES)}
            if eid == "group.g":
                st["attributes"] = {"entity_id": self.r.sample(ENTITIES[:7] + ["sensor.nope"], self.r.randrange(0, 4))}
            elif self.chance(0.5):
                attrs = {}
                for k, vs in (("b", [5, 2.5, "x", None, True, [1, 2]]), ("unit", ["W", "°C"]), ("friendly_name", ["My Thing", "", "A b"]),
                              ("xs", [[3, 1, 2], []])):
                    if self.chance(0.4):
                        attrs[k] = self.pick(vs)
                st["attributes"] = dict(sorted(attrs.items()))   # sorted: attribute order is a documented gap
            self.states.append(st)
        if self.chance(0.3):
            self.variables = {"trigger": self.pick([{"id": "t1", "xs": [1, 2]}, {"id": 5}, {"platform": "state", "id": "0", "xs": []}])}
            if self.chance(0.3):
                self.variables["x"] = self.pick([5, 2.5, "s", None, True, [1, "a"], {"a": 1}])
                self.vars.append("x")
        tpl = "".join(self.block(2) for _ in range(self.r.randrange(1, 3)))
        c = {"name": name, "template": tpl}
        if self.states:
            c["states"] = self.states
        if self.variables:
            c["variables"] = self.variables
        if self.chance(0.35):
            # a random instant in 2026-2027, millisecond precision (the harness sends milliseconds)
            t = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(milliseconds=self.r.randrange(2 * 365 * 86400 * 1000))
            c["now"] = t.isoformat()
        r = self.r.random()
        if r < 0.1:
            c["parse_result"] = False
        elif r < 0.17:
            c["condition"] = True
        elif r < 0.45:
            c["render_info"] = True
        return c


def main():
    seed, count, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    g = Gen(seed)
    with open(out, "w") as f:
        for i in range(count):
            f.write(json.dumps(g.case(f"r{seed}_{i}"), ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
