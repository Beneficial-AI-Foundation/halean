"""Print what halean-automation outputs for each step of a scenario file (shipped format), with
repeated identical commands folded into a count. Usage: engine_scenario.py <scenario.yaml> [--logs]"""
import sys, json, itertools
sys.dont_write_bytecode = True
sys.path.insert(0, "/home/user/halean/tests")
import yaml
from run_scenarios import engine_outputs
sc = yaml.safe_load(open(sys.argv[1]))
labels = ["init"] + [f"at={s['at']} {json.dumps(s.get('send') or s.get('set'))[:90]}" for s in sc["steps"]]
for label, cmds in zip(labels, engine_outputs(sc)):
    print(label)
    keep = [c for c in cmds if "--logs" in sys.argv or c["type"] != "log"]
    for c, grp in itertools.groupby(keep, key=lambda c: json.dumps({k: v for k, v in c.items() if k not in ("call_id", "run_id")}, sort_keys=True)):
        n = len(list(grp)); print(f"   {'x' + str(n) + ' ' if n > 1 else ''}{c[:300]}")
