"""README template claims, probed on real HA (Template.async_render) and on halean-template.
Each row: (id, README line, template, expectation, states, variables)
  expectation: same        HA and HALean give the same type and repr (or both raise)
               halean_err  HA renders, HALean gives a render error (documented gap)
               unsupported HALean rejects at load ({"unsupported": ...})
               value:<repr> same, and the repr is exactly this
Output: logs/probe-templates.jsonl (one line per row) ; the test fails if the expectation does not hold."""
import json, os, subprocess
from datetime import UTC, datetime, timedelta
from pathlib import Path
import pytest
from homeassistant.exceptions import HomeAssistantError, TemplateError
from homeassistant.helpers.template import Template
from homeassistant.util import dt as dt_util

BIN = Path(os.environ.get("HALEAN_BIN", "/home/user/halean/.lake/build/bin"))
LOG = Path(__file__).resolve().parent.parent / "logs" / "probe-templates.jsonl"
NOW = datetime(2026, 11, 20, 16, 30, 45, 123000, tzinfo=UTC)
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
L = [{"entity_id": "light.b", "state": "on", "attributes": {"brightness": 10}},
     {"entity_id": "light.a", "state": "off", "attributes": {"friendly_name": "A"}},
     {"entity_id": "sensor.t", "state": "21.5", "attributes": {}}]
ROWS = [
 ("T1", 239, "{{ 0.1 + 0.2 }}", "value:0.30000000000000004", [], {}),
 ("T2", 240, "{{ round(2.675, 2) }}", "unsupported", [], {}),  # no `round` global in HA: HA raises UndefinedError, HALean rejects at load
 ("T2b", 240, "{{ 2.675 | round(2) }}", "value:2.67", [], {}),
 ("T3", 240, "{{ 1 == 1.0 == True }}", "value:True", [], {}),
 ("T4", 241, "{{ '42' }}", "value:42", [], {}),
 ("T5", 241, "{{ '[1, 2]' }}", "value:[1, 2]", [], {}),
 ("T6", 242, "{{ '007' }}", "value:'007'", [], {}),
 ("T7", 246, "{% for x in [1,2,3,4] if x != 2 %}{% if x == 4 %}{% break %}{% endif %}{{ loop.index }}:{{ x }} {% else %}none{% endfor %}", "same", [], {}),
 ("T8", 246, "{% set ns = namespace(n=0) %}{% for x in [1,2] %}{% set ns.n = ns.n + x %}{% endfor %}{{ ns.n }}", "value:3", [], {}),
 ("T9", 246, "{% set a, b = 1, 2 %}{{ b }}{# c #}  {{- a }}", "value:21", [], {}),
 ("T10", 246, "{{ 1 < 2 < 3 > 2 }} {{ 'a' if false else 'b' }} {{ [1,2,3,4][1:3] }}", "same", [], {}),
 ("T11", 246, "{{ states.light | map(attribute='entity_id') | list }}", "value:['light.b', 'light.a']", L, {}),
 ("T11b", 246, "{{ states | map(attribute='entity_id') | list }}", "same", L, {}),
 ("T12", 246, "{{ is_state('light.b','on') }} {{ state_attr('light.b','brightness') }} {{ is_state_attr('light.b','brightness',10) }} {{ has_value('sensor.t') }}", "same", L, {}),
 ("T13", 246, "{{ float('x', 1.5) }} {{ int('12') }} {{ bool('yes') }} {{ is_number('1e3') }} {{ iif(1, 'a', 'b') }} {{ dict(a=1) }}", "same", [], {}),
 ("T14", 246, "{{ [3,1,2] | sort(reverse=true) }} {{ ['b','A'] | sort(case_sensitive=true) }} {{ [1,1,2] | unique | list }} {{ max(1, 5, 3) }} {{ [4,2] | min }}", "same", [], {}),
 ("T15", 246, "{{ now().isoformat() }} {{ utcnow().year }} {{ today_at('10:00').hour }} {{ (now() + timedelta(hours=1)).hour }}", "same", [], {}),
 ("T16", 246, "{{ strptime('2026-01-02 03:04', '%Y-%m-%d %H:%M').isoformat() }} {{ as_timestamp('2026-01-02T03:04:05+00:00') }} {{ 1700000000 | timestamp_custom('%H:%M', false) }}", "same", [], {}),
 ("T17", 246, "{{ 'a,b' .split(',') }} {{ ' x '.strip() }} {{ 'abc'.startswith('a') }} {{ 'abc'.replace('b','x') }}", "same", [], {}),
 ("T18", 246, "{% macro m() %}x{% endmacro %}{{ m() }}", "unsupported", [], {}),
 ("T19", 246, "{% include 'x' %}", "unsupported", [], {}),
 ("T20", 246, "{% raw %}{{ x }}{% endraw %}", "unsupported", [], {}),
 ("T21", 246, "{{ 'abc' | regex_replace('b', 'x') }}", "unsupported", [], {}),
 ("T22", 246, "{{ distance('zone.home') }}", "unsupported", [], {}),
 ("T23", 246, "{{ 1 is odd }} {{ 'x' is match('x') }}", "unsupported", [], {}),
 ("T24", 248, "{{ states.light.b.last_reported }}", "halean_err", L, {}),
 ("T25", 248, "{{ now().tzinfo }}", "halean_err", [], {}),
 ("T26", 249, "{{ now().strftime('%Z') }}", "halean_err", [], {}),
 ("T27", 249, "{{ strptime('Mon Jan  2 03:04:05 2026', '%c').year }}", "halean_err", [], {}),
 ("T28", 250, "{{ [1, 2] | map('int') }}", "halean_err", [], {}),
 ("T29", 252, "{{ 'É' | lower }}", "halean_err", [], {}),
 ("T29b", 252, "{{ 'é' | upper }}", "halean_err", [], {}),
 ("T30", 253, "{{ ['é', 'B'] | sort }}", "halean_err", [], {}),
 ("T31", 255, "{{ [1.0, float('nan'), 0.5] | sort }}", "halean_err", [], {}),
 ("T32", 246, "{{ expand('group.g') | map(attribute='entity_id') | list }}", "same",
   L + [{"entity_id": "group.g", "state": "on", "attributes": {"entity_id": ["light.b", "light.a"]}}], {}),
 ("T33", 659, "{{ expand('light.grp') | map(attribute='entity_id') | list }}", "halean_err",
   L + [{"entity_id": "light.grp", "state": "on", "attributes": {"entity_id": ["light.b", "light.a"]}}], {}),
 ("T34", 655, "{{ d }}", "DIFF", [], {"d": {"b": 1, "a": 2}}),
 ("T35", 246, "{{ relative_time(now() - timedelta(minutes=5)) }} {{ as_timedelta('1:02:03').total_seconds() }} {{ now() is datetime }}", "same", [], {}),
 ("T36", 246, "{{ [{'a': 1}, {'a': 2}] | selectattr('a', 'eq', 2) | list }} {{ [1,2,3] | reject('odd') | list }} {{ [1,2] | sum }} {{ 'ab' | reverse }} {{ [1,2] | join('-') }}", "same", [], {}),
]

@pytest.fixture(scope="module")
def engine():
    proc = subprocess.Popen([str(BIN / "halean-template")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def ask(msg):
        proc.stdin.write(json.dumps(msg) + "\n"); proc.stdin.flush()
        return json.loads(proc.stdout.readline())
    yield ask
    proc.stdin.close(); proc.wait()

def _typename(v):
    for kls in (bool, int, float, str, type(None), tuple, list, dict, set):
        if isinstance(v, kls):
            return kls.__name__
    return type(v).__name__

def setup_module(_m):
    LOG.write_text("")

@pytest.mark.parametrize("row", ROWS, ids=[r[0] for r in ROWS])
async def test_probe(hass, freezer, engine, row):
    cid, line, tpl_s, expect, states_in, variables = row
    freezer.move_to(NOW)
    states = []
    for s in states_in:
        hass.states.async_set(s["entity_id"], s["state"], s.get("attributes", {}))
        st = hass.states.get(s["entity_id"])
        us = lambda d: (d - EPOCH) // timedelta(microseconds=1)
        states.append({**s, "last_changed_us": us(st.last_changed), "last_updated_us": us(st.last_updated)})
    lean = engine({"template": tpl_s, "states": states, "variables": variables, "parse_result": True,
                   "condition": False, "info": False, "now": ((dt_util.utcnow() - EPOCH) // timedelta(microseconds=1)) // 1000,
                   "tz": int(dt_util.now().utcoffset().total_seconds())})
    try:
        r = Template(tpl_s, hass).async_render(variables, parse_result=True)
        ha = {"ok": True, "type": _typename(r), "repr": repr(r)}
    except (TemplateError, HomeAssistantError) as err:
        ha = {"ok": False, "error": str(err)[:200]}
    if expect == "unsupported":
        holds = "unsupported" in lean
    elif expect == "halean_err":
        holds = ha["ok"] and lean.get("ok") is False
    elif expect == "DIFF":
        holds = ha["ok"] and lean.get("ok") and lean != ha
    elif expect == "same":
        holds = (lean == ha) if ha["ok"] else lean.get("ok") is False
    else:
        holds = lean == ha and ha.get("repr") == expect[len("value:"):]
    with LOG.open("a") as f:
        f.write(json.dumps({"id": cid, "readme_line": line, "template": tpl_s, "expect": expect, "holds": holds,
                            "ha": ha, "halean": lean}, ensure_ascii=False) + "\n")
    assert holds, f"HA: {ha}\nHALean: {lean}"
