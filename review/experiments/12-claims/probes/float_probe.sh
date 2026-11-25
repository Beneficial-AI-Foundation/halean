#!/usr/bin/env bash
# README:294-295 "a JSON float written without a fraction or exponent sign (1e16) reads as an int".
# Each attribute below is a float for Python's json.loads. The reply shows how halean-core-states reads it
# (a float prints with '.' or 'e', an int without).
printf '%s\n' '{"op": "set", "entity_id": "light.e", "state": "on", "attributes": {"a_1e16": 1e16, "b_1.0e16": 1.0e16, "c_1e+16": 1e+16, "d_1.5e3": 1.5e3, "e_1.0": 1.0, "f_2.5e-1": 2.5e-1, "g_1e22": 1e22, "h_1.5e+16": 1.5e+16}, "now": 1763656245123456}' '{"op": "get", "entity_id": "light.e"}' \
 | /home/user/halean/.lake/build/bin/halean-core-states | tail -1
/opt/havenv/bin/python -c "
import json
print('python json.loads types:', {k: type(v).__name__ for k, v in json.loads('{\"a_1e16\": 1e16, \"b_1.0e16\": 1.0e16, \"c_1e+16\": 1e+16, \"d_1.5e3\": 1.5e3, \"e_1.0\": 1.0, \"f_2.5e-1\": 2.5e-1, \"g_1e22\": 1e22, \"h_1.5e+16\": 1.5e+16}').items()})
print('python json.dumps(1e16) =', json.dumps(1e16), '; json.dumps(1.5e16) =', json.dumps(1.5e16), '; json.dumps(1e15) =', json.dumps(1e15))"
