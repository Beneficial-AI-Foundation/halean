#!/usr/bin/env bash
# Small read-only checks cited from CLAIMS-README.md. Writes logs/small-checks.log.
cd /home/user/halean
{
echo "## README:66 ELAN_HOME path"; ls -d /Volumes/MacStorage/AppData/elan 2>&1; echo "elan here: $(ls -d $HOME/.elan/bin 2>&1)"
echo "## README:188,502 websocket_api commands of the installed HA (none registers a service)"
grep -rn "websocket_command" -A3 /opt/havenv/lib/python3.14/site-packages/homeassistant/components/websocket_api/commands.py | grep -o '"type"): "[a-z_/]*"' | sed 's/"type"): //' | tr '\n' ' '; echo
grep -n '"mqtt/subscribe"' /opt/havenv/lib/python3.14/site-packages/homeassistant/components/mqtt/__init__.py; grep -n '"webhook/handle"' /opt/havenv/lib/python3.14/site-packages/homeassistant/components/webhook/__init__.py
echo "## README:327 validator names of the Supported cell (line 335): occurrences in tests/core/services/*.yaml"
for k in "required:" "exclusive" "inclusive" "default" "all:" "any:" "in:" "not_in" "range" "clamp" "length" "coerce: int" "coerce: float" "coerce: str" "lower" "upper" "ensure_list" "port" "at_least_one" "cv: string" "cv: boolean" "cv: positive_int" "cv: positive_float" "cv: small_float" "cv: byte" "cv: port" "cv: ensure_list" "cv: entity_id\b" "cv: entity_ids" "cv: comp_entity_ids" "cv: entity_domain" "cv: color_hex" "cv: slug" "cv: time_period\b" "cv: time_period_str" "cv: time_period_seconds" "cv: time_period_dict" "cv: positive_time_period\b" "cv: positive_time_period_dict" "odd key" "x.y" "rows" "color" "group"; do printf '  %-32s %s\n' "$k" "$(cat tests/core/services/*.yaml | grep -c -- "$k")"; done
echo "## README:411 cases in tests/core/hass that use sleep (the '15 async cases')"
/opt/havenv/bin/python -B -c "
import yaml, glob, json
n = 0
for f in sorted(glob.glob('tests/core/hass/*.yaml')):
    names = [c['name'] for c in yaml.safe_load(open(f)) if '\"sleep\"' in json.dumps(c)]
    n += len(names); print(' ', f, len(names), names)
print('  total', n)"
echo "## README:257 condition steps nested inside if/repeat/sequence/choose/parallel in tests/scenarios (file, automation id, enclosing action)"
/opt/havenv/bin/python -B -c "
import yaml, glob
def walk(actions, ctx, out, f, aid):
    for a in actions if isinstance(actions, list) else [actions]:
        if not isinstance(a, dict): continue
        if 'condition' in a and ctx: out.add((f, aid, ctx))
        for k in ('then', 'else'):
            if k in a: walk(a[k], 'if', out, f, aid)
        if 'sequence' in a and 'repeat' not in a and 'choose' not in a: walk(a['sequence'], 'sequence', out, f, aid)
        if 'default' in a: walk(a['default'], 'choose-default', out, f, aid)
        for o in a.get('choose', []) or []: walk(o.get('sequence', []), 'choose', out, f, aid)
        if isinstance(a.get('repeat'), dict): walk(a['repeat'].get('sequence', []), 'repeat', out, f, aid)
        if 'parallel' in a: walk(a['parallel'], 'parallel', out, f, aid)
out = set()
for f in sorted(glob.glob('tests/scenarios/*.yaml')):
    for a in yaml.safe_load(open(f))['automations']:
        walk(a.get('actions') or a.get('action') or [], '', out, f, a.get('id'))
for o in sorted(out): print(' ', o)"
echo "  scenario files with 'enabled':  $(grep -l enabled tests/scenarios/*.yaml | tr '\n' ' ')"
echo "  scenario files with 'while:':   $(grep -l 'while:' tests/scenarios/*.yaml | tr '\n' ' ')"
echo "  scenario files with 'not_from': $(grep -l 'not_from' tests/scenarios/*.yaml | tr '\n' ' ')"
echo "  files under tests/ with 10000 as a number of its own: $(grep -rlw '10000' tests --include=*.yaml --include=*.py | tr '\n' ' ')"
echo "## README:61 files that mention schema.json (outside review/, .lake/, upstream/)"
grep -rn "schema.json" --include=*.py --include=*.lean --include=*.yml --include=*.sh --include=*.toml --include=Dockerfile . 2>/dev/null | grep -v "^./review\|^./.lake\|^./upstream" | cut -c1-140
echo "## README:235 max_exceeded in HALean/Automation"; grep -rn "max_exceeded" HALean/Automation || echo "  no occurrence"
} > review/experiments/12-claims/logs/small-checks.log 2>&1
