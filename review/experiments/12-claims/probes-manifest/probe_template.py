#!/usr/bin/env python
"""Probes of halean-template for statements in manifest notes (template area).
Output: logs-manifest/probe-template.log"""
import json, subprocess
BIN = "/home/user/halean/.lake/build/bin/halean-template"
NOW = 1_700_000_000_000
S = [{"entity_id": "sensor.a", "state": "1", "attributes": {"k": 1}, "last_changed_us": NOW * 1000, "last_updated_us": NOW * 1000},
     {"entity_id": "sensor.b", "state": "2", "attributes": {}},
     {"entity_id": "group.g", "state": "on", "attributes": {"entity_id": ["sensor.b", "sensor.a"]}},
     {"entity_id": "light.lg", "state": "unavailable", "attributes": {}},
     {"entity_id": "light.withids", "state": "on", "attributes": {"entity_id": ["sensor.a"]}},
     {"entity_id": "zone.home", "state": "1", "attributes": {"persons": ["sensor.b"]}}]
P = [
 ("M-56", "is_static on the unstripped text; source stripped", "  42  ", {}),
 ("M-56", "static text with a brace-free body keeps inner spaces", " a  b ", {}),
 ("M-57", "output stripped", "{{ '  x  ' }}", {}),
 ("M-57", "MAX_TEMPLATE_OUTPUT (256 KiB) enforced", "{{ 'x' * 262145 }}", {}),
 ("M-57", "control: 262144 characters pass", "{{ ('x' * 262144) | length }}", {}),
 ("M-58", "fast numeric path", "{{ '0012' }}", {}),
 ("M-59", "literal_eval: tuple", "(1, 'a', None, True)", {}),
 ("M-59", "literal_eval: set becomes a list", "{{ '{1, 2}' }}", {}),
 ("M-59", "literal_eval: bytes stay a string", "{{ \"b'ab'\" }}", {}),
 ("M-59", "literal_eval: dict", "{{ \"{'a': [1, 2.5]}\" }}", {}),
 ("M-63", "states() with rounded", "{{ states('sensor.a', rounded=True) }}", {}),
 ("M-63", "states() with with_unit", "{{ states('sensor.a', with_unit=True) }}", {}),
 ("M-65", "state.last_changed", "{{ states.sensor.a.last_changed }}", {}),
 ("M-65", "state.last_updated", "{{ states.sensor.a.last_updated }}", {}),
 ("M-65", "state.last_changed of a state sent without timestamps", "{{ states.sensor.b.last_changed }}", {}),
 ("M-65", "state.context", "{{ states.sensor.a.context }}", {}),
 ("M-65", "state.last_reported", "{{ states.sensor.a.last_reported }}", {}),
 ("M-72", "int with base 16", "{{ 'ff' | int(0, 16) }}", {}),
 ("M-72", "int base 10 explicit", "{{ '12' | int(0, 10) }}", {}),
 ("M-74", "round half cases on the binary value", "{{ [2.675 | round(2), 0.5 | round, 1.5 | round, 2.5 | round(0, 'half')] }}", {}),
 ("M-98", "now() uses the engine clock", "{{ now() }}", {}),
 ("M-101", "as_timestamp of a naive datetime string", "{{ as_timestamp('2023-11-14 22:13:20') }}", {}),
 ("M-101", "as_timestamp of an aware datetime string", "{{ as_timestamp('2023-11-14T22:13:20+00:00') }}", {}),
 ("M-104", "timestamp_custom with %Z", "{{ 0 | timestamp_custom('%Z') }}", {}),
 ("M-104", "timestamp_custom with an unlisted directive %E", "{{ 0 | timestamp_custom('%Ey') }}", {}),
 ("M-104", "timestamp_custom default format (TPL-22)", "{{ 0 | timestamp_custom }}", {}),
 ("M-107", "parse through as_datetime: regex form", "{{ as_datetime('2023-11-14 22:13:20+01:00') }}", {}),
 ("M-107", "parse through as_datetime: ciso8601-only form (date only)", "{{ as_datetime('2023-11-14') }}", {}),
 ("M-107", "parse through as_datetime: ciso8601-only form (basic format)", "{{ as_datetime('20231114T221320') }}", {}),
 ("M-107", "parse through as_datetime: T24:00:00 (TPL-23)", "{{ as_datetime('2023-11-14T24:00:00') }}", {}),
 ("M-103", "as_local uses the current offset (tz=3600)", "{{ as_local(as_datetime('2023-07-01T12:00:00+00:00')) }}", {"tz": 3600}),
 ("M-125", "expand: stack order, group members", "{{ expand('group.g', 'sensor.b') | map(attribute='entity_id') | list }}", {}),
 ("M-125", "expand: zone persons", "{{ expand('zone.home') | map(attribute='entity_id') | list }}", {}),
 ("M-125", "expand: non-group entity with an entity_id attribute", "{{ expand('light.withids') | map(attribute='entity_id') | list }}", {}),
 ("M-125", "expand: unavailable non-group entity returned as is", "{{ expand('light.lg') | map(attribute='entity_id') | list }}", {}),
 ("M-126", "expand uses the lower-case retry", "{{ expand('SENSOR.A') | map(attribute='entity_id') | list }}", {}),
 ("M-126", "states() does not use the lower-case retry (TPL-6)", "{{ states('SENSOR.A') }}", {}),
 ("M-127", "strptime with %Z", "{{ strptime('2023 UTC', '%Y %Z') }}", {}),
 ("M-127", "strptime with a locale directive %c", "{{ strptime('x', '%c') }}", {}),
 ("M-127", "strptime with non-ASCII input", "{{ strptime('２０２３', '%Y') }}", {}),
 ("M-127", "strptime plain", "{{ strptime('2023-11-14 05', '%Y-%m-%d %H') }}", {}),
 ("M-135", "as_timedelta: standard, ISO 8601, PostgreSQL forms", "{{ [as_timedelta('1 02:03:04'), as_timedelta('P1DT2H'), as_timedelta('3 days 04:05:06'), as_timedelta('x')] }}", {}),
 ("M-115", "iterated states do not collect entities (info)", "{% for s in states.sensor %}{{ s.state }}{% endfor %}", {"info": True}),
 ("M-115", "a state reached through states.sensor.a collects (info)", "{{ states.sensor.a.state }}", {"info": True}),
 ("M-78", "condition mode: 'TRUE' counts, 1 does not", "{{ 'TRUE' }}", {"condition": True}),
 ("M-78", "condition mode: 1 is not 'true'", "{{ 1 }}", {"condition": True}),
]
log = open(__file__.rsplit("/", 2)[0] + "/logs-manifest/probe-template.log", "w")
lines = [dict({"template": t, "states": S, "now": NOW, "tz": 0}, **extra) for _, _, t, extra in P]
r = subprocess.run([BIN], input="".join(json.dumps(l) + "\n" for l in lines), capture_output=True, text=True, timeout=120)
for (mid, what, t, extra), rep in zip(P, r.stdout.splitlines()):
    rep = rep if len(rep) < 300 else rep[:300] + "…"
    s = f"{mid} | {what} | {t if len(t) < 100 else t[:100] + '…'} {extra or ''}\n    -> {rep}"
    print(s); print(s, file=log)
if r.stderr.strip(): print("stderr:", r.stderr[:300]); print("stderr:", r.stderr[:300], file=log)
