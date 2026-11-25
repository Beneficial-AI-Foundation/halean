"""README "Rejected at load, stays in HA" claims (lines 229-235, 749-765): send one init with these
automations to halean-automation and print, per automation id, whether the reply has an `unsupported`
command for it (and the reason). `want` is what the README says: U = rejected at load, L = loads."""
import json, subprocess, sys
sys.path.insert(0, "/home/user/halean/bridge"); sys.dont_write_bytecode = True
from protocol import protocol_automations
EV = [{"trigger": "event", "event_type": "go"}]
A = [
 ("L", "control_state", 231, {"triggers": [{"trigger": "state", "entity_id": "sensor.x", "to": "on"}], "actions": [{"action": "a.b"}]}),
 ("U", "this_in_trigger_template", 231, {"triggers": [{"trigger": "template", "value_template": "{{ this.state == 'on' }}"}], "actions": []}),
 ("U", "sun_dawn", 231, {"triggers": [{"trigger": "sun", "event": "dawn"}], "actions": []}),
 ("U", "sun_elevation_numeric_attr_is_supported_control", 231, {"triggers": [{"trigger": "sun", "event": "noon"}], "actions": []}),
 ("U", "zone_entered_new_style", 231, {"triggers": [{"trigger": "zone.entered", "target": {"entity_id": "zone.home"}}], "actions": []}),
 ("U", "ha_shutdown", 231, {"triggers": [{"trigger": "homeassistant", "event": "shutdown"}], "actions": []}),
 ("L", "ha_start", 231, {"triggers": [{"trigger": "homeassistant", "event": "start"}], "actions": []}),
 ("U", "device_trigger", 231, {"triggers": [{"trigger": "device", "device_id": "abc", "domain": "light", "type": "turned_on", "entity_id": "light.x"}], "actions": []}),
 ("U", "mqtt_encoding_other", 231, {"triggers": [{"trigger": "mqtt", "topic": "a/b", "encoding": "latin-1"}], "actions": []}),
 ("U", "mqtt_encoding_empty", 231, {"triggers": [{"trigger": "mqtt", "topic": "a/b", "encoding": ""}], "actions": []}),
 ("U", "mqtt_payload_bytes_literal", 231, {"triggers": [{"trigger": "mqtt", "topic": "a/b", "payload": "b'x'"}], "actions": []}),
 ("U", "mqtt_topic_templated_in_wait", 231, {"triggers": EV, "actions": [{"wait_for_trigger": [{"trigger": "mqtt", "topic": "{{ 'a/b' }}"}]}]}),
 ("U", "event_context", 231, {"triggers": [{"trigger": "event", "event_type": "go", "context": {"user_id": "u"}}], "actions": []}),
 ("U", "event_data_nested_list", 231, {"triggers": [{"trigger": "event", "event_type": "go", "event_data": {"a": {"b": [1, 2]}}}], "actions": []}),
 ("L", "event_data_nested_dict", 231, {"triggers": [{"trigger": "event", "event_type": "go", "event_data": {"a": {"b": 1}}}], "actions": []}),
 ("U", "time_at_reads_states", 231, {"triggers": [{"trigger": "time", "at": "{{ states('input_text.t') }}"}], "actions": []}),
 ("U", "webhook_id_reads_states", 231, {"triggers": [{"trigger": "webhook", "webhook_id": "{{ states('input_text.t') }}"}], "actions": []}),
 ("U", "webhook_templated_in_wait", 231, {"triggers": EV, "actions": [{"wait_for_trigger": [{"trigger": "webhook", "webhook_id": "{{ 'x' }}"}]}]}),
 ("U", "platform_condition_device", 232, {"triggers": EV, "conditions": [{"condition": "device", "device_id": "abc", "domain": "light", "type": "is_on", "entity_id": "light.x"}], "actions": []}),
 ("U", "platform_condition_new_style", 232, {"triggers": EV, "conditions": [{"condition": "light.is_on", "target": {"entity_id": "light.x"}}], "actions": []}),
 ("U", "state_condition_for_with_attribute", 232, {"triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "attribute": "a", "state": "1", "for": "00:00:05"}], "actions": []}),
 ("U", "state_condition_for_with_input_state", 232, {"triggers": EV, "conditions": [{"condition": "state", "entity_id": "light.x", "state": "input_select.s", "for": "00:00:05"}], "actions": []}),
 ("U", "this_non_ascii_alias", 233, {"alias": "Küche", "triggers": EV, "actions": [{"action": "a.b", "data": {"m": "{{ this.state }}"}}]}),
 ("U", "this_html_entity_alias", 233, {"alias": "a &amp; b", "triggers": EV, "actions": [{"action": "a.b", "data": {"m": "{{ this.state }}"}}]}),
 ("U", "trigger_variables_use_states", 233, {"trigger_variables": {"x": "{{ states('sensor.x') }}"}, "triggers": EV, "actions": []}),
 ("U", "trigger_variables_use_this", 233, {"trigger_variables": {"x": "{{ this.state }}"}, "triggers": EV, "actions": []}),
 ("U", "trigger_variables_use_now", 233, {"trigger_variables": {"x": "{{ now() }}"}, "triggers": EV, "actions": []}),
 ("U", "variables_on_wait_trigger", 233, {"triggers": EV, "actions": [{"wait_for_trigger": [{"trigger": "event", "event_type": "x", "variables": {"v": 1}}]}]}),
 ("U", "device_action", 234, {"triggers": EV, "actions": [{"device_id": "abc", "domain": "light", "type": "turn_on", "entity_id": "light.x"}]}),
 ("U", "scene_action", 234, {"triggers": EV, "actions": [{"scene": "scene.movie"}]}),
 ("U", "max_exceeded_warning", 235, {"mode": "queued", "max": 2, "max_exceeded": "warning", "triggers": EV, "actions": []}),
 ("U", "max_exceeded_silent", 235, {"mode": "queued", "max": 2, "max_exceeded": "silent", "triggers": EV, "actions": []}),
 ("U", "max_exceeded_error", 235, {"mode": "queued", "max": 2, "max_exceeded": "error", "triggers": EV, "actions": []}),
 ("L", "mode_queued_max", 235, {"mode": "queued", "max": 2, "triggers": EV, "actions": []}),
 ("U", "calendar_trigger", 750, {"triggers": [{"trigger": "calendar", "entity_id": "calendar.x", "event": "start"}], "actions": []}),
 ("U", "persistent_notification_trigger", 750, {"triggers": [{"trigger": "persistent_notification"}], "actions": []}),
 ("U", "conversation_trigger", 750, {"triggers": [{"trigger": "conversation", "command": "hello"}], "actions": []}),
 ("L", "tag_trigger", 231, {"triggers": [{"trigger": "tag", "tag_id": "t1"}], "actions": []}),
 ("L", "time_pattern", 231, {"triggers": [{"trigger": "time_pattern", "seconds": "/5"}], "actions": []}),
 ("L", "numeric_state", 231, {"triggers": [{"trigger": "numeric_state", "entity_id": "sensor.x", "above": 3, "for": "00:00:02"}], "actions": []}),
 ("L", "zone_legacy", 231, {"triggers": [{"trigger": "zone", "entity_id": "person.a", "zone": "zone.home", "event": "enter"}], "actions": []}),
 ("L", "actions_all", 234, {"triggers": EV, "actions": [
     {"choose": [{"conditions": "{{ true }}", "sequence": [{"delay": "{{ 1 }}"}]}], "default": [{"stop": "x", "error": False}]},
     {"if": [{"condition": "template", "value_template": "{{ true }}"}], "then": [{"event": "e", "event_data": {"a": 1}}], "else": []},
     {"repeat": {"for_each": [1, 2], "sequence": [{"variables": {"v": "{{ repeat.item }}"}}]}},
     {"parallel": [{"action": "a.b"}, {"sequence": [{"wait_template": "{{ true }}", "timeout": 3, "continue_on_timeout": False}]}]},
     {"action": "a.c", "response_variable": "r", "continue_on_error": True, "enabled": "yes"}]}),
]
autos = [{"id": name, **cfg} for _, name, _, cfg in A]
msg = {"type": "init", "now": 1_700_000_000_000, "tz": 0, "automations": protocol_automations(autos), "states": [],
       "location": {"latitude": 32.87336, "longitude": -117.22743, "elevation": 0}}
out = subprocess.run(["/home/user/halean/.lake/build/bin/halean-automation"], input=json.dumps(msg) + "\n",
                     capture_output=True, text=True, check=True).stdout
reply = json.loads(out.splitlines()[0])
uns = {c["id"]: c["reason"] for c in reply.get("cmds", []) if c["type"] == "unsupported"}
if reply.get("type") == "error": print("ENGINE ERROR", reply)
bad = 0
for want, name, line, _ in A:
    got = "U" if name in uns else "L"
    bad += got != want
    print(f"{'OK  ' if got == want else 'DIFF'} README:{line} {name}: README says {'rejected' if want == 'U' else 'loads'}, engine: "
          f"{'unsupported: ' + uns[name] if name in uns else 'loaded'}")
print("rows:", len(A), "not as README says:", bad)
