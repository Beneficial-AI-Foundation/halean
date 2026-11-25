"""Fast exploration tool (not the verdict): validate data with the real
probatio schema built by the harness's schema_spec.make_schema and with
halean-core-services (register + blocking call with an echo handler), and print
where the two differ. The verdict runs are made with harness/test_services.py.

Usage: explore.py <cases.yaml> [...]   (shipped YAML format; only register/call ops are used)
"""
from __future__ import annotations
import copy, json, os, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "harness"))
import probatio, yaml
from schema_spec import make_schema

BIN = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin")) / "halean-core-services"


class Engine:
    def __init__(self):
        self.p = subprocess.Popen([str(BIN)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def ask(self, msg):
        self.p.stdin.write(json.dumps(msg) + "\n"); self.p.stdin.flush()
        line = self.p.stdout.readline()
        if not line:
            raise RuntimeError(f"engine died on {msg}")
        return json.loads(line)


def ha_validate(schema, data):
    try:
        out = schema(copy.deepcopy(data))
        return ("ok", repr(dict(out)))
    except probatio.Invalid as e:
        return ("err", type(e).__name__, str(e))
    except Exception as e:  # noqa: BLE001
        return ("err", type(e).__name__, str(e))


def lean_validate(eng, spec, data, reg=True):
    if reg:
        r = eng.ask({"op": "register", "domain": "t", "service": "s", "handler": {"echo": True},
                     "supports_response": "only", "schema": spec, "now": 0})
        if "unsupported" in r:
            return ("unsupported-schema", r["unsupported"])
    r = eng.ask({"op": "call", "domain": "t", "service": "s", "blocking": True, "return_response": True,
                 "data": data, "context": {"id": "C"}, "now": 0})
    if "unsupported" in r:
        return ("unsupported", r["unsupported"])
    if r.get("type") == "error":
        return ("engine-error", r["message"])
    if r["ok"]:
        pre = "{'domain': 't', 'service': 's', 'data': "
        suf = ", 'return_response': True, 'context_id': 'C'}"
        s = r["result"]
        assert s.startswith(pre) and s.endswith(suf), s
        return ("ok", s[len(pre):-len(suf)])
    e = r["error"]
    return ("err", e["exception"], e["message"])


def compare(eng, spec, datas):
    """Yield (data, ha, lean) for every datum; register once."""
    schema = make_schema(spec)
    first = True
    for d in datas:
        ha = ha_validate(schema, d)
        le = lean_validate(eng, spec, d, reg=first)
        first = False
        yield d, ha, le


if __name__ == "__main__":
    eng = Engine()
    n = bad = 0
    for f in sys.argv[1:]:
        for case in yaml.safe_load(open(f)) or []:
            spec = None
            for op in case["ops"]:
                if op["op"] == "register":
                    spec = op.get("schema"); schema = make_schema(spec); first = True
                elif op["op"] == "call":
                    d = dict(op.get("data") or {}); d.update(op.get("target") or {})
                    ha = ha_validate(schema, d); le = lean_validate(eng, spec, d, reg=first); first = False
                    n += 1
                    if ha != le:
                        bad += 1
                        print(f"{case['name']}: data={d!r}\n   HA   {ha}\n   Lean {le}")
    print(f"{n} calls, {bad} differ")
