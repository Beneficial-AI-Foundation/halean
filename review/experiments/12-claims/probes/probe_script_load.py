"""README:492 "Rejected at load, stays in HA" for scripts: one init to halean-script; which object ids come back
`unsupported`. Also README:510: turn_on of a script that does not start fails the call with a log."""
import json, subprocess, sys
sys.dont_write_bytecode = True; sys.path.insert(0, "/home/user/halean/bridge")
from protocol import protocol_scripts
S = {
 "fine": ("L", {"alias": "Fine", "icon": "mdi:x", "description": "d", "fields": {"level": {"default": 5}}, "variables": {"v": "{{ level }}"},
                "mode": "queued", "max": 2, "max_exceeded": "silent", "sequence": [{"action": "light.turn_on", "data": {"b": "{{ level }}"}}]}),
 "invalid_extra_key": ("U", {"trigger": [], "sequence": []}),
 "blueprint": ("U", {"use_blueprint": {"path": "x.yaml"}}),
 "reload_action": ("U", {"sequence": [{"action": "script.reload"}]}),
 "device_target": ("U", {"sequence": [{"action": "script.turn_on", "target": {"device_id": "abc"}}]}),
 "area_target": ("U", {"sequence": [{"action": "script.turn_off", "target": {"area_id": "abc"}}]}),
 "wait_on_script_entity": ("U", {"sequence": [{"wait_template": "{{ is_state('script.fine', 'off') }}"}]}),
 "trigger_condition": ("U", {"sequence": [{"condition": "trigger", "id": "x"}]}),
 "last_action": ("U", {"sequence": [{"event": "x", "event_data": {"a": "{{ state_attr('script.fine', 'last_action') }}"}}]}),
 "undeclared_name": ("U", {"sequence": [{"event": "x", "event_data": {"a": "{{ brightness }}"}}]}),
 "action_defined_variable": ("L",  # README:492 lists action-defined variables among the allowed names
                              {"sequence": [{"variables": {"q": 1}}, {"event": "x", "event_data": {"a": "{{ q }}"}}]}),
 "calls_fine": ("L", {"sequence": [{"action": "script.fine", "data": {"level": 3}}, {"action": "script.turn_on", "target": {"entity_id": "script.fine"}}]}),
 "single_waits": ("L", {"mode": "single", "sequence": [{"delay": 5}]}),
}
T0 = 1_700_000_000_000
lines = [{"type": "init", "now": T0, "tz": 0, "automations": [], "states": [],
          "scripts": protocol_scripts({k: v[1] for k, v in S.items()})},
         {"type": "call", "call_id": 1, "service": "turn_on", "data": {"entity_id": "script.single_waits"}, "now": T0 + 1000, "tz": 0},
         {"type": "call", "call_id": 2, "service": "turn_on", "data": {"entity_id": "script.single_waits"}, "now": T0 + 2000, "tz": 0}]
out = subprocess.run(["/home/user/halean/.lake/build/bin/halean-script"], input="\n".join(map(json.dumps, lines)) + "\n",
                     capture_output=True, text=True).stdout.splitlines()
r = json.loads(out[0]); uns = {c["id"]: c["reason"] for c in r.get("cmds", []) if c["type"] == "unsupported"}
bad = 0
for k, (want, _) in S.items():
    got = "U" if k in uns else "L"; bad += got != want
    print(f"{'OK  ' if got == want else 'DIFF'} {k}: README says {'rejected' if want == 'U' else 'loads'}; engine: {'unsupported: ' + uns[k] if k in uns else 'loaded'}")
print("not as README says:", bad)
for o in out[1:]:
    print("call reply:", json.dumps([c for c in json.loads(o).get("cmds", []) if c["type"] in ("call_done", "log")])[:500])
