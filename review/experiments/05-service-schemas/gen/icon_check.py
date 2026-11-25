"""cv.icon: the decoder accepts {"cv": "icon"} (ServicesJson.lean:122) but the harness builder's CV set
(schema_spec.py:24) does not, so the shipped harness cannot test it. Here the name is added to the
builder's set in memory and both sides validate the same data (fast tool, not the harness)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from explore import Engine, ha_validate, lean_validate, make_schema
import schema_spec
schema_spec.CV.add("icon")
spec = {"fields": [{"key": "k", "value": {"cv": "icon"}}]}
schema = make_schema(spec); eng = Engine(); first = True; n = bad = 0
for x in ["mdi:x", "x", ":", "", "a:b:c", 1, 1.5, None, True, ["a:b"], ["ab"], {"a": 1}, {}, "é:x", "mdi:\x1f"]:
    ha = ha_validate(schema, {"k": x}); le = lean_validate(eng, spec, {"k": x}, reg=first); first = False
    n += 1; bad += ha != le
    print("SAME" if ha == le else "DIFF", repr(x), "| HA", ha, "| HALean", le)
print(f"{n} data, {bad} differ")
