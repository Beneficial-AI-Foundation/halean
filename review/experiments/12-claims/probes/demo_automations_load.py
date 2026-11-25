"""README:41-42 "All seven in demo/automations.yaml run in the Lean engine": load them, count `unsupported`."""
import json, subprocess, sys, yaml
sys.path.insert(0, "/home/user/halean/bridge")
from protocol import protocol_automations
autos = yaml.safe_load(open("/home/user/halean/demo/automations.yaml"))
msg = {"type": "init", "now": 1_700_000_000_000, "tz": 0, "automations": protocol_automations(autos), "states": []}
r = json.loads(subprocess.run(["/home/user/halean/.lake/build/bin/halean-automation"], input=json.dumps(msg) + "\n", capture_output=True, text=True).stdout.splitlines()[0])
print("demo/automations.yaml:", len(autos), "automations; unsupported at load:", [c for c in r["cmds"] if c["type"] == "unsupported"])
