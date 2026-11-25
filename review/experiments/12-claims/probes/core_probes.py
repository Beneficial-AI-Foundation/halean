"""JSON-line probes of the built core executables for README claims (states, registry, schemas, bus,
core, helpers). Prints every input line and the reply. Read the verdicts in CLAIMS-README.md."""
import json, subprocess, os
BIN = os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")
T = 1763656245123456
def run(exe, title, lines):
    print(f"\n### {title}   [{exe}]")
    raw = "\n".join(l if isinstance(l, str) else json.dumps(l) for l in lines) + "\n"
    out = subprocess.run([f"{BIN}/{exe}"], input=raw, capture_output=True, text=True).stdout.splitlines()
    for l, o in zip(lines, out):
        s = l if isinstance(l, str) else json.dumps(l)
        print("  >", s if len(s) < 260 else s[:120] + f" ...({len(s)} chars)")
        print("  <", o if len(o) < 700 else o[:700] + " ...")
    if len(out) != len(lines): print("  !! replies:", len(out), "inputs:", len(lines))

S = "halean-core-states"
run(S, "S1 README:288 equal attributes keep the old object ({a: 1} stays when {a: 1.0} is set)", [
    {"op": "set", "entity_id": "light.a", "state": "on", "attributes": {"a": 1}, "now": T},
    '{"op": "set", "entity_id": "light.a", "state": "on", "attributes": {"a": 1.0}, "now": %d}' % (T + 10**6),
    {"op": "get", "entity_id": "light.a"}])
run(S, "S2 README:288 set_internal: over-long state -> unknown; async_set: error", [
    {"op": "set_internal", "entity_id": "light.b", "state": "x" * 256, "now": T},
    {"op": "get", "entity_id": "light.b"},
    {"op": "set", "entity_id": "light.c", "state": "x" * 256, "now": T}])
run(S, "S3 README:288 (right) non-ASCII entity ids and domain filters rejected", [
    {"op": "set", "entity_id": "light.é", "state": "on", "now": T},
    {"op": "entity_ids", "domain_filter": "É"}])
run(S, "S4 README:294 attribute dicts print with sorted keys", [
    '{"op": "set", "entity_id": "light.d", "state": "on", "attributes": {"b": 1, "a": 2}, "now": %d}' % T,
    {"op": "get", "entity_id": "light.d"}])
run(S, "S5 README:295 a JSON float without fraction or exponent sign (1e16) reads as an int", [
    '{"op": "set", "entity_id": "light.e", "state": "on", "attributes": {"x": 1e16, "y": 1.0e16, "z": 1e+16}, "now": %d}' % T,
    {"op": "get", "entity_id": "light.e"},
    '{"op": "set", "entity_id": "light.e", "state": "on", "attributes": {"x": 10000000000000000, "y": 1.0e16, "z": 1e+16}, "now": %d}' % (T + 1)])
run(S, "S6 README:288 lower-cased id, get with lower-case retry, str filter lower-cased, iterable not", [
    {"op": "set", "entity_id": "Light.F", "state": "on", "now": T},
    {"op": "get", "entity_id": "LIGHT.F"},
    {"op": "entity_ids", "domain_filter": "LIGHT"},
    {"op": "entity_ids", "domain_filter": ["LIGHT"]}])

V = "halean-core-services"
def reg(value, **kw): return {"op": "register", "domain": "t", "service": "v", "handler": {"echo": True}, "supports_response": "only",
                              "schema": {"fields": [{"key": "a", "value": value, **kw}]}, "now": 0}
def call(a): return {"op": "call", "domain": "t", "service": "v", "blocking": True, "return_response": True, "data": {"a": a}, "now": 0}
run(V, "V1 README:335 Coerce(int): the 4300-digit limit", [reg({"coerce": "int"}), call("1" * 4300), call("1" * 4301)])
run(V, "V2 README:335 In: the 40-member cap and 'did you mean'", [
    reg({"in": list(range(45))}), call(99),
    reg({"in": ["apple", "banana"]}), call("appel")])
run(V, "V3 README:335 (right) rejected specs: msg=, Match, cv.percentage, cv.time, cv.url, cv.icon, Coerce(bool)", [
    reg({"range": {"min": 0}, "msg": "m"}), reg({"match": "^a"}), reg({"cv": "matches_regex", "regex": "^a"}),
    reg({"cv": "percentage"}), reg({"cv": "time"}), reg({"cv": "url"}), reg({"cv": "template"}), reg({"cv": "date"}),
    reg({"coerce": "bool"}), reg({"cv": "icon"}), call("mdi:lamp"), call("lamp")])
run(V, "V4 README:339 names lowercased; async_services_for_domain does not lowercase; supports_response KeyError", [
    {"op": "register", "domain": "Test", "service": "Hello", "handler": {"return": None}, "now": 0},
    {"op": "list", "now": 0}, {"op": "list_domain", "domain": "Test", "now": 0}, {"op": "list_domain", "domain": "test", "now": 0},
    {"op": "has", "domain": "TEST", "service": "HELLO", "now": 0},
    {"op": "supports_response", "domain": "nope", "service": "x", "now": 0}])
run(V, "V5 README:339 (right) non-ASCII names, other handler exceptions, non-dict data", [
    {"op": "register", "domain": "tést", "service": "x", "handler": {"return": None}, "now": 0},
    {"op": "register", "domain": "t", "service": "k", "handler": {"raise": "KeyError", "message": "m"}, "now": 0},
    {"op": "register", "domain": "t", "service": "ok", "handler": {"return": None}, "now": 0},
    {"op": "call", "domain": "t", "service": "ok", "data": [1], "blocking": True, "now": 0}])
run(V, "V6 README:350 NaN / Infinity in the input JSON", [
    '{"op": "call", "domain": "t", "service": "ok", "data": {"x": NaN}, "blocking": true, "now": 0}',
    '{"op": "call", "domain": "t", "service": "ok", "data": {"x": Infinity}, "blocking": true, "now": 0}'])
run(V, "V7 README:339 return_response rules", [
    {"op": "register", "domain": "t", "service": "none", "handler": {"return": None}, "now": 0},
    {"op": "register", "domain": "t", "service": "only", "handler": {"return": {"a": 1}}, "supports_response": "only", "now": 0},
    {"op": "call", "domain": "t", "service": "none", "blocking": True, "return_response": True, "now": 0},
    {"op": "call", "domain": "t", "service": "only", "blocking": True, "now": 0},
    {"op": "call", "domain": "t", "service": "only", "blocking": False, "return_response": True, "now": 0},
    {"op": "call", "domain": "t", "service": "gone", "blocking": True, "now": 0}])

E = "halean-core-events"
run(E, "E1 README:470 event type length in code points (64 ok, 65 raises), also non-ASCII", [
    {"op": "listen", "now": 0, "id": "a", "event_type": "*"},
    {"op": "fire", "now": 1, "event_type": "x" * 64}, {"op": "fire", "now": 2, "event_type": "x" * 65},
    {"op": "fire", "now": 3, "event_type": "é" * 64}])
run(E, "E2 README:470 MATCH_ALL twice for an event of type '*'; never for state_reported", [
    {"op": "listen", "now": 0, "id": "a", "event_type": "*"},
    {"op": "fire", "now": 1, "event_type": "*"}, {"op": "fire", "now": 2, "event_type": "state_reported", "data": {"a": 1}},
    {"op": "fire", "now": 3, "event_type": "homeassistant_close"}])
run(E, "E3 README:470 (right) non-object event data; listen_once with a filter; run_immediately", [
    {"op": "fire", "now": 1, "event_type": "x", "data": [1]},
    {"op": "listen_once", "now": 1, "id": "o", "event_type": "x", "filter": True},
    {"op": "listen", "now": 1, "id": "r", "event_type": "x", "run_immediately": True}])
run(E, "E4 README:470 double removal is logged and leaves an empty list behind", [
    {"op": "listen", "now": 0, "id": "a", "event_type": "x"}, {"op": "unsub", "now": 1, "id": "a"},
    {"op": "unsub", "now": 2, "id": "a"}, {"op": "listeners", "now": 3}])

C = "halean-core"
loop_handler = {"do": [{"call": {"id": "n", "domain": "t", "service": "rec", "blocking": True}}], "return": None}
run(C, "C1 README:429 (right) service calls nested deeper than 32 are rejected", [
    {"op": "register", "domain": "t", "service": "rec", "handler": loop_handler, "now": 0},
    {"op": "call", "domain": "t", "service": "rec", "blocking": True, "now": 1}])
run(C, "C2 README:429 (right) futures resolved twice; sleep with a delay; time_fired on a scripted fire; event type > 64", [
    {"op": "resolve", "id": "f", "now": 0}, {"op": "resolve", "id": "f", "now": 1},
    {"op": "listen", "id": "l", "event_type": "x", "async": True, "react": [{"sleep": 1}], "now": 2},
    {"op": "listen", "id": "m", "event_type": "y", "react": [{"fire": {"event_type": "z", "time_fired": 5}}], "now": 3},
    {"op": "fire", "event_type": "y", "now": 4},
    {"op": "fire", "event_type": "x" * 65, "now": 5},
    {"op": "listen", "id": "cb", "event_type": "w", "react": [{"sleep": 0}], "now": 6},
    {"op": "fire", "event_type": "w", "now": 7}])
run(C, "C3 README:429 the 10,000-events limit raises HomeAssistantError in the firing script", [
    {"op": "listen", "id": "l", "event_type": "x", "react": [{"fire": {"event_type": "x"}}], "now": 0},
    {"op": "fire", "event_type": "x", "now": 1}])
run(C, "C4 README:429 (right) more than 100,000 handles per operation (endless rescheduling)", [
    {"op": "listen", "id": "a", "event_type": "x", "async": True, "react": [{"sleep": 0}, {"fire": {"event_type": "x"}}], "now": 0},
    {"op": "fire", "event_type": "x", "now": 1}, {"op": "block_till_done", "now": 2}])

H = "halean-helpers"
def setup(domain, cfg, restore=None): return {"op": "setup", "domain": domain, "config": cfg, "restore": restore or [], "now": T}
def hcall(svc, data): d, s = svc.split("."); return {"op": "call", "domain": d, "service": s, "data": data, "now": T}
run(H, "H1 README:552 counter: step 0 allowed, set_value -> ZeroDivisionError; off-step ValueError", [
    {"op": "reset"}, setup("counter", {"z": {"step": 0}, "s": {"step": 2, "maximum": 10}}),
    hcall("counter.set_value", {"entity_id": "counter.z", "value": 3}),
    hcall("counter.set_value", {"entity_id": "counter.s", "value": 3}),
    hcall("counter.set_value", {"entity_id": "counter.s", "value": 12})])
run(H, "H2 README:553 timer duration '-0:00:05'", [
    {"op": "reset"}, setup("timer", {"t": {"duration": "-0:00:05"}})])
run(H, "H3 README:551 input_text: lazy quantifier pattern refused; non-matching value stored then ValueError", [
    {"op": "reset"}, setup("input_text", {"lazy": {"pattern": "a+?"}}),
    {"op": "reset"}, setup("input_text", {"p": {"pattern": "[0-9]+", "initial": "1"}}),
    hcall("input_text.set_value", {"entity_id": "input_text.p", "value": "abc"}),
    hcall("input_text.set_value", {"entity_id": "input_text.p", "value": "x" * 300})])
run(H, "H4 README:550 input_select: duplicate options removed with a warning; set_options duplicates refused", [
    {"op": "reset"}, setup("input_select", {"s": {"options": ["a", "b", "a"]}}),
    hcall("input_select.set_options", {"entity_id": "input_select.s", "options": ["x", "x"]}),
    hcall("input_select.select_option", {"entity_id": "input_select.s", "option": "zzz"})])
run(H, "H5 README:549 input_number: set_value outside the range", [
    {"op": "reset"}, setup("input_number", {"n": {"min": 0, "max": 10}}),
    hcall("input_number.set_value", {"entity_id": "input_number.n", "value": 11})])
run(H, "H6 README:548/574/575 reload, device targets, input_datetime", [
    {"op": "reset"}, setup("input_boolean", {"b": None}),
    hcall("input_boolean.reload", {}), hcall("input_boolean.turn_on", {"device_id": "abc"}),
    hcall("input_boolean.turn_on", {"area_id": "abc"}),
    setup("input_datetime", {"d": {"has_date": True}})])
run(H, "H7 README:548 input_boolean restore: on when no initial; README:571 several entities in the order given", [
    {"op": "reset"}, setup("input_boolean", {"r": None, "i": {"initial": False}, "a": None},
                           [["input_boolean.r", "on", {}], ["input_boolean.i", "on", {}]]),
    hcall("input_boolean.toggle", {"entity_id": ["input_boolean.r", "input_boolean.a", "input_boolean.i"]})])
run(H, "H8 README:553 restoring a paused or active timer is refused", [
    {"op": "reset"}, setup("timer", {"t": {"duration": 10, "restore": True}},
                           [["timer.t", "paused", {"duration": "0:00:10", "remaining": "0:00:05"}]])])
