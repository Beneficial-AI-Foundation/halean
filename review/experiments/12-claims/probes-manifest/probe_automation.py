#!/usr/bin/env python
"""Probes of halean-automation for statements in manifest notes (automation area).
Each probe: one init (automations, states) and a list of further inputs. Prints every reply.
Output: logs-manifest/probe-automation.log"""
import json, subprocess, sys
sys.path.insert(0, "/home/user/halean/bridge"); sys.dont_write_bytecode = True
from protocol import protocol_automations
BIN = "/home/user/halean/.lake/build/bin/halean-automation"
T0 = 1_700_000_000_000  # 2023-11-14 22:13:20 UTC
EV = [{"trigger": "event", "event_type": "go"}]
def st(eid, state, attrs=None, lc=T0 - 60_000):
    return {"entity_id": eid, "state": state, "attributes": attrs or {}, "last_changed": lc}
def sc(eid, old, new, now):
    return {"type": "state_changed", "entity_id": eid, "old_state": old, "new_state": new, "now": now, "tz": 0}
def ev(t, now, data=None):
    return {"type": "event", "event_type": t, "data": data or {}, "now": now, "tz": 0}
def tick(now): return {"type": "tick", "now": now, "tz": 0}
SAY = lambda m: [{"action": "x.say", "data": {"m": m}}]
P = []
def probe(mid, what, autos, states=(), inputs=()):
    P.append((mid, what, autos, list(states), list(inputs)))

probe("M-33", "state trigger with a templated for: loads and fires after the rendered period (note: 'templated for rejected')",
      [{"id": "a", "triggers": [{"trigger": "state", "entity_id": "sensor.x", "to": "on", "for": "{{ 2 }}"}], "actions": SAY("{{ trigger.for }}")}],
      [st("sensor.x", "off")], [sc("sensor.x", st("sensor.x", "off"), st("sensor.x", "on", lc=T0 + 1000), T0 + 1000), tick(T0 + 2500), tick(T0 + 3000)])
probe("M-33", "state trigger with explicit null 'to': not match-all (attribute-only change does not fire), state change fires",
      [{"id": "a", "triggers": [{"trigger": "state", "entity_id": "sensor.x", "to": None}], "actions": SAY("fired")}],
      [st("sensor.x", "off", {"k": 1})],
      [sc("sensor.x", st("sensor.x", "off", {"k": 1}), st("sensor.x", "off", {"k": 2}), T0 + 1000),
       sc("sensor.x", st("sensor.x", "off", {"k": 2}), st("sensor.x", "on", {"k": 2}), T0 + 2000)])
probe("M-33", "control: state trigger without from/to (match-all): attribute-only change fires",
      [{"id": "a", "triggers": [{"trigger": "state", "entity_id": "sensor.x"}], "actions": SAY("fired")}],
      [st("sensor.x", "off", {"k": 1})],
      [sc("sensor.x", st("sensor.x", "off", {"k": 1}), st("sensor.x", "off", {"k": 2}), T0 + 1000)])
probe("M-87", "template trigger using a trigger_variable and a templated for (note: 'static for only; trigger_variables unsupported')",
      [{"id": "a", "trigger_variables": {"lim": 5}, "triggers": [{"trigger": "template", "value_template": "{{ states('sensor.x')|int(0) > lim }}", "for": "{{ 1 }}"}], "actions": SAY("{{ trigger.for }}")}],
      [st("sensor.x", "1")], [sc("sensor.x", st("sensor.x", "1"), st("sensor.x", "9", lc=T0 + 1000), T0 + 1000), tick(T0 + 2000)])
probe("M-87", "template trigger using an undefined variable: refused at load",
      [{"id": "a", "triggers": [{"trigger": "template", "value_template": "{{ foo }}"}], "actions": []}])
probe("M-34", "numeric_state value_template sees state and trigger.{platform,entity_id,below,above,attribute}",
      [{"id": "a", "triggers": [{"trigger": "numeric_state", "entity_id": "sensor.x", "above": 3,
        "value_template": "{{ state.state|float + (1 if trigger.platform == 'numeric_state' and trigger.entity_id == 'sensor.x' and trigger.above == 3 and trigger.below is none and trigger.attribute is none else -100) }}"}], "actions": SAY("{{ trigger.to_state.state }}")}],
      [st("sensor.x", "1")], [sc("sensor.x", st("sensor.x", "1"), st("sensor.x", "2.5"), T0 + 1000)])
probe("M-8", "time condition, after: a timestamp sensor whose state only ciso8601 parses (date only). Note: 'raise unsupported'",
      [{"id": "a", "triggers": EV, "conditions": [{"condition": "time", "after": "sensor.ts"}], "actions": SAY("ran")}],
      [st("sensor.ts", "2023-11-14", {"device_class": "timestamp"})], [ev("go", T0 + 1000)])
probe("M-8", "time condition, after: a timestamp sensor with an aware ISO time; tz offset +3600 from the shell",
      [{"id": "a", "triggers": EV, "conditions": [{"condition": "time", "after": "sensor.ts"}], "actions": SAY("ran")}],
      [st("sensor.ts", "2023-11-14T22:30:00+00:00", {"device_class": "timestamp"})],
      [dict(ev("go", T0 + 1000), tz=0), dict(ev("go", T0 + 2000), tz=3600), dict(ev("go", T0 + 20 * 60_000), tz=0)])
probe("M-8", "time condition, before: a time entity read with strptime %H:%M:%S; bad text gives False (before) ",
      [{"id": "a", "triggers": EV, "conditions": [{"condition": "time", "before": "time.t"}], "actions": SAY("ran")}],
      [st("time.t", "23:00:00")], [ev("go", T0 + 1000), sc("time.t", st("time.t", "23:00:00"), st("time.t", "23:00"), T0 + 2000), ev("go", T0 + 3000)])
probe("M-6", "state condition: for without state; for with attribute; for with an input entity state",
      [{"id": "nostate", "triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "for": 5}], "actions": []},
       {"id": "attr", "triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "state": "1", "attribute": "a", "for": 5}], "actions": []},
       {"id": "input", "triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "state": "input_text.t", "for": 5}], "actions": []}])
probe("M-5", "state condition with templated for, rendered at check time from a run variable",
      [{"id": "a", "variables": {"secs": 30}, "triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "state": "on", "for": {"seconds": "{{ secs }}"}}], "actions": SAY("ran")},
       {"id": "b", "variables": {"secs": 90}, "triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "state": "on", "for": {"seconds": "{{ secs }}"}}], "actions": SAY("ran")}],
      [st("light.x", "on")], [ev("go", T0 + 1000)])
probe("M-12", "condition enabled: word, limited template, platform condition",
      [{"id": "word_off", "triggers": EV, "conditions": [{"condition": "template", "value_template": "{{ false }}", "enabled": "off"}], "actions": SAY("ran")},
       {"id": "tmpl_false", "triggers": EV, "conditions": [{"condition": "template", "value_template": "{{ false }}", "enabled": "{{ 1 == 2 }}"}], "actions": SAY("ran")},
       {"id": "tmpl_states", "triggers": EV, "conditions": [{"condition": "template", "value_template": "{{ false }}", "enabled": "{{ states('a.b') }}"}], "actions": SAY("ran")},
       {"id": "platform", "triggers": EV, "conditions": [{"condition": "light.is_on", "target": {"entity_id": "light.x"}}], "actions": SAY("ran")}],
      [], [ev("go", T0 + 1000)])
probe("M-16", "action enabled: template false drops the step; template that fails to render is refused at load",
      [{"id": "drop", "triggers": EV, "actions": [{"action": "x.one", "enabled": "{{ false }}"}, {"action": "x.two"}]},
       {"id": "fail", "triggers": EV, "actions": [{"action": "x.one", "enabled": "{{ 1 / 0 }}"}]}],
      [], [ev("go", T0 + 1000)])
probe("M-23", "stop with a response_variable that is not defined",
      [{"id": "a", "triggers": EV, "actions": [{"stop": "s", "response_variable": "nope"}, {"action": "x.after"}]}], [], [ev("go", T0 + 1000)])
probe("M-25", "event action: event_data then event_data_template merged; a failing one is logged and left out",
      [{"id": "a", "triggers": EV, "actions": [{"event": "e1", "event_data": {"a": 1, "b": 1}, "event_data_template": {"b": "{{ 2 }}"}},
                                               {"event": "e2", "event_data": {"a": "{{ 1/0 }}"}, "event_data_template": {"b": 2}}]}], [], [ev("go", T0 + 1000)])
probe("M-26", "templated delay rendered when the step runs; an error aborts the run",
      [{"id": "a", "variables": {"d": 2}, "triggers": EV, "actions": [{"delay": "{{ d }}"}, {"action": "x.after"}]},
       {"id": "b", "triggers": EV, "actions": [{"delay": "{{ 'abc' }}"}, {"action": "x.never"}]}], [], [ev("go", T0 + 1000), tick(T0 + 2999), tick(T0 + 3000)])
probe("M-96", "variables action whose template fails, with continue_on_error: true",
      [{"id": "a", "triggers": EV, "actions": [{"variables": {"v": "{{ 1/0 }}"}, "continue_on_error": True}, {"action": "x.after"}]}], [], [ev("go", T0 + 1000)])
probe("M-22", "repeat: templated count, for_each, while, until; repeat is undefined after the loop is refused/absent",
      [{"id": "a", "variables": {"n": 2}, "triggers": EV, "actions": [
          {"repeat": {"count": "{{ n }}", "sequence": SAY("c{{ repeat.index }}{{ repeat.last }}")}},
          {"repeat": {"for_each": ["p", "q"], "sequence": SAY("f{{ repeat.item }}")}},
          {"repeat": {"while": "{{ repeat.index < 3 }}", "sequence": SAY("w{{ repeat.index }}")}},
          {"repeat": {"until": "{{ repeat.index >= 2 }}", "sequence": SAY("u{{ repeat.index }}")}}]}], [], [ev("go", T0 + 1000)]
      + [{"type": "service_result", "call_id": i, "ok": True, "now": T0 + 1000 + i, "tz": 0} for i in range(0, 10)])
probe("M-142/M-144/M-145", "automation names and entity ids: no alias -> 'automation <n>'; collisions get _2; ids in config order (seen through this.entity_id)",
      [{"triggers": EV, "actions": SAY("{{ this.entity_id }}|{{ this.attributes.friendly_name }}")},
       {"alias": "Automation 0", "triggers": EV, "actions": SAY("{{ this.entity_id }}|{{ this.attributes.friendly_name }}")},
       {"alias": "taken", "triggers": EV, "actions": SAY("{{ this.entity_id }}|{{ this.attributes.friendly_name }}")}],
      [st("automation.taken", "on")], [ev("go", T0 + 1000)])
probe("M-143", "slugify: non-ASCII alias makes `this` a load error",
      [{"alias": "Küche", "triggers": EV, "actions": SAY("{{ this.state }}")}, {"alias": "Küche", "triggers": EV, "actions": SAY("x")}])
probe("M-38", "homeassistant start fires once on homeassistant_started; shutdown refused",
      [{"id": "start", "triggers": [{"trigger": "homeassistant", "event": "start"}], "actions": SAY("started")},
       {"id": "shutdown", "triggers": [{"trigger": "homeassistant", "event": "shutdown"}], "actions": []}],
      [], [ev("homeassistant_started", T0 + 1000), ev("homeassistant_started", T0 + 2000)])
probe("M-39", "tag trigger: tag_id and device_id sets",
      [{"id": "a", "triggers": [{"trigger": "tag", "tag_id": ["t1", "t2"], "device_id": "d1"}], "actions": SAY("{{ trigger.event.data.tag_id }}")}],
      [], [ev("tag_scanned", T0 + 1000, {"tag_id": "t2", "device_id": "d1"}), ev("tag_scanned", T0 + 2000, {"tag_id": "t2", "device_id": "d9"}), ev("tag_scanned", T0 + 3000, {"tag_id": "t3", "device_id": "d1"})])
probe("M-37", "event trigger: templated type and data with trigger_variables; 1 == 1.0 == True; nested mapping; nested list refused; context refused",
      [{"id": "a", "trigger_variables": {"t": "go2", "n": 1}, "triggers": [{"trigger": "event", "event_type": "{{ t }}", "event_data": {"k": "{{ n }}", "sub": {"x": 1}}}], "actions": SAY("fired")},
       {"id": "list", "triggers": [{"trigger": "event", "event_type": "e", "event_data": {"a": {"b": [1]}}}], "actions": []},
       {"id": "ctx", "triggers": [{"trigger": "event", "event_type": "e", "context": {"user_id": "u"}}], "actions": []}],
      [], [ev("go2", T0 + 1000, {"k": True, "sub": {"x": 1.0, "y": 2}}), ev("go2", T0 + 2000, {"k": 2, "sub": {"x": 1}}), ev("go2", T0 + 3000, {"k": 1, "sub": 5})])
probe("M-35", "time trigger: templated at with trigger_variables; at reading the clock refused; at rendering to a non-time refused; in wait_for_trigger refused",
      [{"id": "ok", "trigger_variables": {"h": "22:13:25"}, "triggers": [{"trigger": "time", "at": "{{ h }}"}], "actions": SAY("{{ trigger.now }}")},
       {"id": "clock", "triggers": [{"trigger": "time", "at": "{{ now() }}"}], "actions": []},
       {"id": "bad", "triggers": [{"trigger": "time", "at": "{{ 'zz' }}"}], "actions": []},
       {"id": "wait", "triggers": EV, "actions": [{"wait_for_trigger": [{"trigger": "time", "at": "{{ '10:00' }}"}]}]}],
      [], [tick(T0 + 5000)])
probe("M-35", "time trigger on an input_datetime with a missing attribute: logged at attach",
      [{"id": "a", "triggers": [{"trigger": "time", "at": "input_datetime.d"}], "actions": SAY("x")}],
      [st("input_datetime.d", "10:00:00", {"has_date": False})])
probe("M-112", "time trigger: trigger.now is 500 ms into the second, fired at the whole-second tick",
      [{"id": "a", "triggers": [{"trigger": "time_pattern", "seconds": "/5"}], "actions": SAY("{{ trigger.now }}")}], [], [tick(T0 + 5000)])
probe("M-40..M-50", "mqtt: templated topic with trigger_variables; payload rendered with value=None; qos from the message; retained filter; $ topics; simple before wildcard",
      [{"id": "wild", "triggers": [{"trigger": "mqtt", "topic": "+/b"}], "actions": SAY("wild {{ trigger.topic }} qos={{ trigger.qos }}")},
       {"id": "simple", "trigger_variables": {"t": "a/b"}, "triggers": [{"trigger": "mqtt", "topic": "{{ t }}", "payload": "{{ 'x' if value is none else 'y' }}", "qos": 2}], "actions": SAY("simple {{ trigger.payload }} qos={{ trigger.qos }}")},
       {"id": "hash", "triggers": [{"trigger": "mqtt", "topic": "#"}], "actions": SAY("hash {{ trigger.topic }}")},
       {"id": "vt", "triggers": [{"trigger": "mqtt", "topic": "j/t", "payload": "7", "value_template": "{{ value_json.n }}"}], "actions": SAY("vt {{ trigger.payload_json.n }}")},
       {"id": "bytes", "triggers": [{"trigger": "mqtt", "topic": "z", "payload": "b'x'"}], "actions": []},
       {"id": "latin", "triggers": [{"trigger": "mqtt", "topic": "z", "encoding": "latin-1"}], "actions": []},
       {"id": "badtopic", "triggers": [{"trigger": "mqtt", "topic": "a+/b"}], "actions": []},
       {"id": "badtmpltopic", "trigger_variables": {"t": "a/#/b"}, "triggers": [{"trigger": "mqtt", "topic": "{{ t }}"}], "actions": []},
       {"id": "qos3", "triggers": [{"trigger": "mqtt", "topic": "z", "qos": 3}], "actions": []}],
      [], [{"type": "mqtt", "topic": "a/b", "payload": "x", "qos": 1, "retain": True, "now": T0 + 1000, "tz": 0},
           {"type": "mqtt", "topic": "a/b", "payload": "x", "qos": 1, "retain": True, "now": T0 + 2000, "tz": 0},
           {"type": "mqtt", "topic": "$SYS/b", "payload": "x", "qos": 0, "now": T0 + 3000, "tz": 0},
           {"type": "mqtt", "topic": "j/t", "payload": "{\"n\": 7}", "qos": 0, "now": T0 + 4000, "tz": 0},
           {"type": "mqtt", "topic": "j/t", "payload": "not json", "qos": 0, "now": T0 + 5000, "tz": 0}])
WH = lambda **k: dict({"type": "webhook", "webhook_id": "hook", "method": "POST", "now": T0 + 1000, "tz": 0}, **k)
probe("M-51..M-54", "webhook: first trigger's methods/local_only count; json vs form; MultiDict first value; iteration is a render error; HEAD ignored; unknown id; bad JSON",
      [{"id": "first", "triggers": [{"trigger": "webhook", "webhook_id": "hook", "allowed_methods": ["POST"], "local_only": True}], "actions": SAY("first {{ trigger.json.a if trigger.json is defined else trigger.data.a }} q={{ trigger.query.q }}")},
       {"id": "second", "triggers": [{"trigger": "webhook", "webhook_id": "hook", "allowed_methods": ["GET"], "local_only": False}], "actions": SAY("second")},
       {"id": "iter", "triggers": [{"trigger": "webhook", "webhook_id": "hook2"}], "actions": SAY("{{ trigger.data | list }}")},
       {"id": "printit", "triggers": [{"trigger": "webhook", "webhook_id": "hook3"}], "actions": SAY("{{ trigger.data }}")},
       {"id": "meth", "triggers": [{"trigger": "webhook", "webhook_id": "hook4"}], "actions": SAY("{{ trigger.data.get('a') }}")}],
      [], [WH(content_type="application/json", body="{\"a\": 5}", query=[["q", "1"], ["q", "2"]]),
           WH(data=[["a", "x"], ["a", "y"]], now=T0 + 2000),
           WH(method="GET", now=T0 + 3000), WH(method="HEAD", now=T0 + 4000), WH(local=False, now=T0 + 5000),
           WH(webhook_id="nope", now=T0 + 6000), WH(content_type="text/json", body="{bad", now=T0 + 7000),
           WH(webhook_id="hook2", data=[["a", "x"]], now=T0 + 8000), WH(webhook_id="hook3", data=[["a", "x"]], now=T0 + 9000),
           WH(webhook_id="hook4", data=[["a", "x"]], now=T0 + 10000)])
probe("M-55", "automation variables rendered before conditions (error stops the trigger); conditions before mode; this.attributes.current",
      [{"id": "varerr", "variables": {"v": "{{ 1/0 }}"}, "triggers": EV, "conditions": [], "actions": SAY("never")},
       {"id": "condvar", "variables": {"v": 3}, "triggers": EV, "conditions": "{{ v == 3 }}", "actions": SAY("cur={{ this.attributes.current }}")}],
      [], [ev("go", T0 + 1000)])
probe("M-93/M-97", "trigger_variables: limited render at load; key named this skipped; uses of states refused; variables see trigger_variables",
      [{"id": "a", "trigger_variables": {"a": 1, "b": "{{ a + 1 }}"}, "variables": {"c": "{{ b + 1 }}", "a": 10}, "triggers": EV, "actions": SAY("{{ a }} {{ b }} {{ c }}")},
       {"id": "st", "trigger_variables": {"x": "{{ states('a.b') }}"}, "triggers": EV, "actions": []},
       {"id": "this", "trigger_variables": {"x": "{{ this.state }}"}, "triggers": EV, "actions": []}],
      [], [ev("go", T0 + 1000)])
probe("M-80", "service call: templated name; data then data_template; whole-template target; own entity_id last; target entity_id csv lower-cased",
      [{"id": "a", "variables": {"svc": "Light.Turn_On"}, "triggers": EV, "actions": [
          {"action": "{{ svc }}", "data": {"a": 1, "b": 1}, "data_template": {"b": "{{ 2 }}"}, "target": {"entity_id": "{{ 'Light.A, light.b' }}"}},
          {"action": "x.y", "target": "{{ {'entity_id': 'light.c', 'area_id': 'k'} }}", "entity_id": "Light.Own"},
          {"action": "{{ 'nodot' }}"}]}], [],
      [ev("go", T0 + 1000), {"type": "service_result", "call_id": 0, "ok": True, "now": T0 + 1001, "tz": 0}, {"type": "service_result", "call_id": 1, "ok": True, "now": T0 + 1002, "tz": 0}])
probe("M-81/M-82", "cv.service: upper case lower-cased; bad format refused; service and action together refused",
      [{"id": "up", "triggers": EV, "actions": [{"action": "Light.TURN_on"}]},
       {"id": "bad", "triggers": EV, "actions": [{"action": "light"}]},
       {"id": "both", "triggers": EV, "actions": [{"action": "a.b", "service": "a.b"}]},
       {"id": "old", "triggers": EV, "actions": [{"service": "a.c"}]}], [], [ev("go", T0 + 1000)])
probe("M-149/M-154", "wait_template: wait.remaining None without timeout; with a timeout it is an error to use after a wake-up; 0.0 after a timeout",
      [{"id": "no_to", "triggers": EV, "actions": [{"wait_template": "{{ is_state('sensor.x', 'on') }}"}] + SAY("{{ wait.completed }} {{ wait.remaining }}")},
       {"id": "to", "triggers": EV, "actions": [{"wait_template": "{{ is_state('sensor.x', 'on') }}", "timeout": 60}] + SAY("{{ wait.completed }} {{ wait.remaining }}")},
       {"id": "to2", "triggers": EV, "actions": [{"wait_template": "{{ is_state('sensor.y', 'on') }}", "timeout": 2}] + SAY("{{ wait.completed }} {{ wait.remaining }}")}],
      [st("sensor.x", "off"), st("sensor.y", "off")], [ev("go", T0 + 1000), sc("sensor.x", st("sensor.x", "off"), st("sensor.x", "on"), T0 + 2000), tick(T0 + 3000)])
probe("M-156", "wait_for_trigger: trigger templates see variables without wait; two triggers in one round: the later overwrites wait.trigger",
      [{"id": "a", "triggers": EV, "actions": [{"wait_for_trigger": [{"trigger": "event", "event_type": "w", "id": "first"}, {"trigger": "event", "event_type": "w", "id": "second"}]}] + SAY("{{ wait.trigger.id }}")}],
      [], [ev("go", T0 + 1000), ev("w", T0 + 2000)])
probe("M-158/M-159", "parallel: all branches run to the end; first raising branch re-raises; disabled branch dropped",
      [{"id": "a", "triggers": EV, "actions": [{"parallel": [{"sequence": [{"stop": "s1", "error": True}]}, {"sequence": SAY("b2"), "enabled": False}, SAY("b3")[0]]}, {"action": "x.after"}]}],
      [], [ev("go", T0 + 1000), {"type": "service_result", "call_id": 0, "ok": True, "now": T0 + 1001, "tz": 0}])
probe("M-171/M-173", "sun trigger: offset as given; fires at the first whole-second tick at or after the event",
      [{"id": "a", "triggers": [{"trigger": "sun", "event": "sunset", "offset": "-00:30:00"}], "actions": SAY("{{ trigger.event }} {{ trigger.offset }}")}],
      [], [tick(T0 + 86_400_000)])
probe("M-164", "zone condition with a non-numeric coordinate",
      [{"id": "a", "triggers": EV, "conditions": [{"condition": "zone", "entity_id": "person.a", "zone": "zone.home"}], "actions": SAY("ran")}],
      [st("zone.home", "0", {"latitude": 1.0, "longitude": 1.0, "radius": 100}), st("person.a", "home", {"latitude": "abc", "longitude": 1.0})], [ev("go", T0 + 1000)])

log = open(__file__.rsplit("/", 2)[0] + "/logs-manifest/probe-automation.log", "w")
def out(*a):
    print(*a); print(*a, file=log)
for mid, what, autos, states, inputs in P:
    init = {"type": "init", "now": T0, "tz": 0, "automations": protocol_automations(autos), "states": states,
            "location": {"latitude": 32.87336, "longitude": -117.22743, "elevation": 0}}
    lines = [init] + inputs
    r = subprocess.run([BIN], input="".join(json.dumps(l) + "\n" for l in lines), capture_output=True, text=True, timeout=60)
    out(f"=== {mid}: {what}")
    replies = r.stdout.splitlines()
    for l, rep in zip(lines, replies):
        tag = l["type"] + (":" + l.get("event_type", l.get("entity_id", l.get("topic", l.get("webhook_id", "")))) if l["type"] != "init" else "")
        try: cmds = json.loads(rep).get("cmds", rep)
        except Exception: cmds = rep
        out(f"  > {tag} @+{l['now'] - T0}")
        if isinstance(cmds, list):
            for c in cmds: out("      " + json.dumps(c, ensure_ascii=False, sort_keys=True))
        else: out("      " + str(cmds))
    if r.stderr.strip(): out("  stderr:", r.stderr.strip()[:300])
    if len(replies) != len(lines): out(f"  !! {len(lines)} inputs, {len(replies)} replies")
