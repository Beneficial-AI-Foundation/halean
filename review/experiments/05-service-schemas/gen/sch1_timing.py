"""SCH-1: time halean-core-services on Coerce(float) of "1e<N>" for growing N (HA answers inf at once)."""
import sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from explore import Engine, ha_validate, lean_validate, make_schema
spec = {"fields": [{"key": "f", "value": {"coerce": "float"}}]}
schema = make_schema(spec); eng = Engine(); first = True
for text in ["1e400", "1e1000000", "1e10000000", "1e100000000", "1e400000000", "1e-400", "1e-100000000", "0e100000000"]:
    t = time.time(); ha = ha_validate(schema, {"f": text}); th = time.time() - t
    t = time.time()
    try:
        le = lean_validate(eng, spec, {"f": text}, reg=first); first = False
    except RuntimeError:
        le = ("ENGINE DIED",); eng = Engine(); first = True
    print(f"{text:>14}  HA {ha} in {th:.4f}s   HALean {le} in {time.time() - t:.2f}s", flush=True)
