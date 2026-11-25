#!/usr/bin/env python
"""Probes of halean-helpers for statements in manifest notes (helper area).
Output: logs-manifest/probe-helpers.log"""
import json, subprocess
BIN = "/home/user/halean/.lake/build/bin/halean-helpers"
N = 1763656245000000
def setup(domain, config, restore=(), now=N): return {"op": "setup", "domain": domain, "config": config, "restore": list(restore), "now": now}
def call(domain, service, data, now=N): return {"op": "call", "domain": domain, "service": service, "data": data, "now": now}
G = [
 ("M-342", "input_number min >= max: message with swapped bounds", [setup("input_number", {"n": {"min": 5, "max": 1}})]),
 ("M-346", "input_number restore: in range, out of range, not a number", [setup("input_number", {"a": {"min": 0, "max": 10}, "b": {"min": 0, "max": 10}, "c": {"min": 2, "max": 10}},
     [["input_number.a", "7.5", {}], ["input_number.b", "11", {}], ["input_number.c", "abc", {}]])]),
 ("M-354/M-355", "input_select: initial checked before duplicates are removed; duplicates removed with a warning",
  [setup("input_select", {"s": {"options": ["a", "b", "a"], "initial": "a"}}), {"op": "reset"}, setup("input_select", {"t": {"options": ["a", "b"], "initial": "z"}})]),
 ("M-370/M-371", "input_text: swapped bounds message; a pattern outside the subset is refused", [setup("input_text", {"t": {"min": 5, "max": 1}}), {"op": "reset"},
     setup("input_text", {"p": {"pattern": "a+?"}}), {"op": "reset"}, setup("input_text", {"q": {"pattern": "(?i)a"}})]),
 ("M-374/M-376/M-377", "input_text: restore 'unknown' of allowed length; set_value wrong length: warning, no write; initial not matching: ValueError",
  [setup("input_text", {"t": {"min": 0, "max": 10}, "u": {"min": 0, "max": 3}}, [["input_text.t", "unknown", {}], ["input_text.u", "toolong", {}]]),
   call("input_text", "set_value", {"entity_id": "input_text.t", "value": "x" * 11}),
   {"op": "reset"}, setup("input_text", {"v": {"pattern": "[0-9]+", "initial": "abc"}})]),
 ("M-383/M-386", "counter: initial outside min/max is not clamped; a last state int() cannot read",
  [setup("counter", {"c": {"initial": 50, "maximum": 10}}), {"op": "reset"},
   setup("counter", {"d": {"restore": True}}, [["counter.d", "abc", {}]]), {"op": "reset"}, setup("counter", {"e": {}}, [["counter.e", " 7 ", {}]])]),
 ("M-391/M-393", "timer: duration formatting, exact microseconds", [setup("timer", {"t": {"duration": "25:01:01"}, "u": {"duration": 0.0000005}, "v": {"duration": {"days": 1, "milliseconds": 1}}})]),
 ("M-394", "timer restore: idle; paused; active; unavailable", [setup("timer", {"t": {"restore": True}}, [["timer.t", "idle", {"last_transition": "finished"}]]), {"op": "reset"},
     setup("timer", {"t": {"restore": True}}, [["timer.t", "paused", {"remaining": "0:00:05"}]]), {"op": "reset"},
     setup("timer", {"t": {"restore": True}}, [["timer.t", "unavailable", {}]]), {"op": "reset"},
     setup("timer", {"t": {}}, [["timer.t", "paused", {"remaining": "0:00:05"}]])]),
 ("M-402/M-335", "timer: every write fires state_changed (force_update); the finish runs at the first clock at or after the end",
  [setup("timer", {"t": {"duration": 5}}), call("timer", "start", {"entity_id": "timer.t"}), call("timer", "start", {"entity_id": "timer.t"}, N + 1_000_000),
   {"op": "tick", "now": N + 5_999_999}, {"op": "tick", "now": N + 6_000_000}]),
 ("M-327/M-329/M-330", "entity service on several targets: order given; every entity runs; first error raised",
  [setup("input_number", {"a": {"min": 0, "max": 10}, "b": {"min": 0, "max": 100}, "c": {"min": 0, "max": 10}}),
   call("input_number", "set_value", {"entity_id": ["input_number.c", "input_number.b", "input_number.a"], "value": 50})]),
 ("M-328", "device/area targets unsupported; missing entity not logged", [setup("input_boolean", {"a": None}),
   call("input_boolean", "turn_on", {"area_id": "kitchen"}), call("input_boolean", "turn_on", {"entity_id": "input_boolean.nope"})]),
 ("M-324", "schema_with_slug_keys: first bad key raises; value errors collected in key order", [setup("input_boolean", {"Bad Key": None, "also bad": None}), {"op": "reset"},
   setup("input_boolean", {"b": {"initial": "zz"}, "a": {"icon": "noc"}})]),
 ("M-325/M-326", "Remove('metadata'): a dict is dropped, another value is an extra key", [setup("input_boolean", {"a": None}),
   call("input_boolean", "turn_on", {"entity_id": "input_boolean.a", "metadata": {"x": 1}}), call("input_boolean", "turn_off", {"entity_id": "input_boolean.a", "metadata": 5})]),
 ("M-336", "no reload service", [setup("input_boolean", {"a": None}), call("input_boolean", "reload", {})]),
 ("M-338", "input_boolean: restore when no initial", [setup("input_boolean", {"a": None, "b": {"initial": False}}, [["input_boolean.a", "on", {}], ["input_boolean.b", "on", {}]])]),
 ("M-331", "input_number state formatting f'{v:.15}'", [setup("input_number", {"a": {"min": 0, "max": 1e18, "initial": 0.30000000000000004}, "b": {"min": 0, "max": 1e18, "initial": 1e16}, "c": {"min": 0, "max": 1e18, "initial": 123456789012345678}})]),
]
log = open(__file__.rsplit("/", 2)[0] + "/logs-manifest/probe-helpers.log", "w")
def out(s):
    print(s); print(s, file=log)
for mid, what, lines in G:
    lines = [{"op": "reset"}] + lines
    r = subprocess.run([BIN], input="".join(json.dumps(l) + "\n" for l in lines), capture_output=True, text=True, timeout=60)
    out(f"=== {mid}: {what}")
    for l, rep in list(zip(lines, r.stdout.splitlines()))[1:]:
        if l["op"] == "reset": continue
        out("  > " + json.dumps(l)[:300]); out("  < " + (rep if len(rep) < 800 else rep[:800] + "…"))
    if r.stderr.strip(): out("  stderr: " + r.stderr.strip()[:300])
