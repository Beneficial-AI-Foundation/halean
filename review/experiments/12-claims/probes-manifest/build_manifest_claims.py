#!/usr/bin/env python
"""Writes ../CLAIMS-MANIFEST-TRANSLATED.md from logs-manifest/structure.json (structure.py) and verdicts.py.
Every count in the document is computed here from the table rows."""
import json, collections, sys
from pathlib import Path
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from verdicts import E, NC
D = json.load(open(HERE.parent / 'logs-manifest/structure.json'))
VERDICTS = ['correct', 'correct for the wrong reason', 'overstated', 'false', 'stale']
READ_UP = {"helpers/condition.py", "components/homeassistant/triggers/homeassistant.py", "components/tag/trigger.py",
           "components/mqtt/trigger.py", "components/mqtt/util.py", "components/mqtt/models.py", "components/mqtt/client.py",
           "components/webhook/trigger.py", "components/webhook/__init__.py"}
def method(o):
    py = o['python']; path = py.split('::')[0]; qual = py.split('::')[1]
    leanfiles = [l['loc'].split(':')[0] for l in o['lean'] if l['loc']]
    first = leanfiles[0] if leanfiles else ''
    if 'HALean/Automation/' in first or path.startswith('components/automation'):
        if path in READ_UP or (path == 'helpers/script.py' and (qual.startswith('_ScriptRun.') or qual.startswith('_QueuedScriptRun.')) and qual != '_ScriptRun.async_stop'):
            return 'read: Lean and upstream'
        if path.startswith('components/script') or path in ('helpers/entity.py', 'helpers/restore_state.py'):
            return 'read: Lean; upstream by sbs 08'
        return 'read: Lean; upstream by sbs 07'
    if 'HALean/Script/' in first: return 'read: Lean; upstream by sbs 08'
    if 'HALean/Helpers/' in first: return 'sbs 09'
    if 'HALean/Template/' in first: return 'sbs 06'
    if 'HALean/Core/' in first:
        if py.startswith('probatio:') or path == 'helpers/config_validation.py': return 'sbs 05'
        if any(x in first for x in ('ServiceRegistry', 'Hass.lean', 'ServicesJson')): return 'sbs 04'
        return 'sbs 03'
    return 'sbs 07'
def short(n): return n.replace('HALean.', '')
def up(o):
    f = o['pyfile'].replace('upstream/ha-core/homeassistant/', 'up:').replace('/opt/havenv/lib/python3.14/site-packages/', 'site-packages/')
    return f"{f}:{o['pyline']}-{o['pyend']}"
rows = []
for o in D:
    i = o['id']
    v = NC[i][0] if i in NC else 'correct'
    assert v in VERDICTS, v
    names = []
    for l in o['lean']:
        tag = ' (missing)' if l['kind'] == 'MISSING' else (' (partial)' if l['kind'] == 'partial' else '')
        names.append(f"`{short(l['name'])}`{tag}")
    loc = next((l['loc'] for l in o['lean'] if l['loc']), 'no declaration')
    ev = f"{up(o)}; {loc}; {method(o)}"
    if o['pykind'] == 'ClassDef': ev += '; a class'
    if i in NC: ev += f". {NC[i][1]}. See below"
    elif i in E: ev += '. ' + E[i][0].upper() + E[i][1:]
    elif o['notes'] and '(probatio 0.13.0)' in o['notes']:
        ev += '. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry)' + ('' if o['notes'].strip() == '(probatio 0.13.0)' else '; the other clause by the sbs 05 row of this function')
    elif o['notes']: ev += '. Note: by the comparison row named here'
    rows.append({'id': i, 'python': o['python'], 'names': ', '.join(names), 'verdict': v, 'evidence': ev, 'notes': bool(o['notes']), 'o': o})
unknown = [i for i in list(NC) + list(E) if i not in {r['id'] for r in rows}]
assert not unknown, unknown
W = []
def w(s=''): W.append(s)
cnt = collections.Counter((r['verdict'], r['notes']) for r in rows)
w('# Claims in `manifest.yaml`: the 349 `translated` entries')
w()
w('Reviewed commit f638a37. Scope: every entry with `status: translated`. The 53 `proven` entries are another reviewer\'s.')
w('`M-<n>` is the position of the entry in `manifest.yaml` (1 to 402), so the ids of the two reviews do not collide.')
w('Paths: `up:` is `upstream/ha-core/homeassistant/`; `logs-manifest/` is `review/experiments/12-claims/logs-manifest/`;')
w('`sbs NN` is `review/experiments/NN-*/side-by-side.md`; finding ids (`AUT-6`, `TPL-18`, ...) are those of `review/experiments/NN-*/FINDINGS.md`')
w('(`SCR-n` ids are in `08-scripts/side-by-side.md`; that directory had no `FINDINGS.md` when this was written).')
w()
w('## What was checked, and how')
w()
w('* (a) Structure, by script (`probes-manifest/structure.py`, `overload_stubs.py`): every `python:` ref resolves with the drift tool\'s `find_node` logic')
w('  (0 missing, 0 stale: `logs-manifest/overload-stubs.log`, `logs-manifest/drift-check.log`); every `lean:` name was looked up in')
w('  `10-theorems/logs/defs.tsv` and in the Lean sources.')
w('* (b) Notes: each note was checked against the Lean source lines cited or, where the evidence column says `sbs NN`, against that reviewer\'s comparison row. Where a note states a concrete behaviour, a probe of a shipped executable')
w('  or of real Python was run (`logs-manifest/probe-*.log`, `py-direct.log`, `probe-ha.log`). The evidence column says which.')
w('* (c) Status: `translated` was judged against the upstream function body.')
w()
w('How the evidence column reads: `upstream lines; first Lean declaration; method`. Methods:')
w('`read: Lean and upstream` = both sides read for this review; `read: Lean; upstream by sbs NN` = the Lean file was read here, the upstream side is taken from')
w('that reviewer\'s comparison row; `sbs NN` = both sides taken from that comparison, plus the probes named.')
w()
w('Verdict rules used:')
w()
w('* `stale`: true of an earlier commit (a Lean name since removed; a note about behaviour since changed). The commit is named.')
w('* `false`: a statement in the note is contradicted by the code or by a probe.')
w('* `overstated`: the note states a behaviour that holds only for part of the inputs (a probe or a finding of an area review shows the rest),')
w('  or the Lean definition covers a part of the upstream function and the note does not say so.')
w('* `correct for the wrong reason`: the entry checks out, but its hash watches an `@overload` stub, not the implementation.')
w('* `correct`: none of the above. A divergence found by an area review does not by itself change `correct`;')
w('  it does when it concerns the very thing the note asserts. Such findings are cited in the evidence column either way.')
w()
w('Limits. `HALean/Automation/{Condition,Config,Script,Engine}.lean` and `HALean/Script/{Entity,Service}.lean` were read in full; `HALean/Template/Render.lean`,')
w('`HALean/Core/Hass.lean` and the helper files were read only at the lines cited. For entries without a note in the template, core, schema and helper areas the')
w('verdict rests on the structure checks and on the area reviewer\'s comparison row. M-167 (vincenty) and M-50 (paho matcher) were not compared with the libraries themselves.')
w('Probes are deterministic; `probes-manifest/rerun_manifest.sh` runs each twice and compares (`logs-manifest/two-runs.log`).')
w()
w('## Counts')
w()
w('| verdict | with notes | without notes | total |')
w('|---|---|---|---|')
for v in VERDICTS:
    a, b = cnt[(v, True)], cnt[(v, False)]
    w(f'| {v} | {a} | {b} | {a + b} |')
tn = sum(1 for r in rows if r['notes']); tw = len(rows) - tn
w(f'| all | {tn} | {tw} | {len(rows)} |')
w()
w('## All entries')
w()
w('| id | python ref | lean names | verdict | evidence |')
w('|---|---|---|---|---|')
for r in rows:
    w(f"| M-{r['id']} | `{r['python']}` | {r['names']} | {r['verdict']} | {r['evidence'].replace('|', '\\|')} |")
w()
w('## Not correct')
w()
for v in VERDICTS[1:][::-1]:
    sel = [r for r in rows if r['verdict'] == v]
    w(f'### {v} ({len(sel)})')
    w()
    for r in sel:
        o = r['o']
        w(f"**M-{r['id']}** `{r['python']}` → {r['names']}")
        w()
        if o['notes']: w(f"Note: \"{o['notes']}\"")
        else: w('No note.')
        w()
        w(NC[r['id']][2])
        w()
# structure facts
w('## Entry-level structure facts')
w()
names = {}
shared = collections.defaultdict(list)
for r in rows:
    for l in r['o']['lean']:
        names[l['name']] = l; shared[l['name']].append(r['id'])
kinds = collections.Counter(l['kind'] for l in names.values())
pykinds = collections.Counter(r['o']['pykind'] for r in rows)
classes = [r for r in rows if r['o']['pykind'] == 'ClassDef']
partial_names = sorted(n for n, l in names.items() if l['kind'] == 'partial')
partial_entries = [r for r in rows if any(l['kind'] == 'partial' for l in r['o']['lean'])]
missing_names = sorted(n for n, l in names.items() if l['kind'] == 'MISSING')
missing_entries = [r for r in rows if any(l['kind'] == 'MISSING' for l in r['o']['lean'])]
stubs = [r for r in rows if r['o']['pyend'] is not None and r['id'] in (76, 107, 239, 305)]
w(f"All numbers are over the {len(rows)} `translated` entries (`logs-manifest/structure-summary.log`, `structure.tsv`).")
w()
w(f"* Upstream node kinds: {pykinds['FunctionDef']} `def`, {pykinds['AsyncFunctionDef']} `async def`, {pykinds['ClassDef']} classes. No ref is missing.")
w(f"* Entries that map a class, not a function ({len(classes)}): " + ', '.join(f"M-{r['id']} `{r['python'].split('::')[1]}`" for r in classes) + '.')
w(f"* The entries name {sum(len(r['o']['lean']) for r in rows)} Lean names, {len(names)} distinct: " + ', '.join(f"{v} {k}" for k, v in sorted(kinds.items(), key=lambda x: -x[1])).replace('MISSING', 'missing') + '.')
w(f"* `partial def`: {len(partial_names)} distinct names in {len(partial_entries)} entries: " + ', '.join(f"`{short(n)}` ({len(shared[n])})" for n in sorted(partial_names, key=lambda n: -len(shared[n]))) + '.')
w('  Entries: ' + ', '.join(f"M-{r['id']}" for r in partial_entries) + '.')
w(f"* Missing Lean names: {len(missing_names)} distinct names in {len(missing_entries)} entries, all removed by commit bf053c0 and still present as fields of the structure `Handlers` and as `...H` definitions:")
for n in missing_names:
    w(f"  * `{short(n)}`: " + ', '.join(f"M-{i}" for i in shared[n]))
import yaml
_all = yaml.safe_load(open('/home/user/halean/manifest.yaml'))['entries']
_prov = [(i, e) for i, e in enumerate(_all, 1) if e['status'] == 'proven' and set(missing_names) & set(e['lean'])]
w('  These are the same six names as in `11-coverage-drift/logs/manifest-names.log`. Outside this scope, ' + str(len(_prov)) + ' `proven` ' + ('entry carries' if len(_prov) == 1 else 'entries carry') + ' one of them: '
  + ', '.join(f"M-{i} `{e['python']}` (" + ', '.join('`' + short(n) + '`' for n in e['lean'] if n in missing_names) + ')' for i, e in _prov) + '.')
w(f"* Refs that resolve to the first of several same-named definitions, an `@overload` stub ({len(stubs)}): " + ', '.join(f"M-{r['id']}" for r in stubs) + ' (`logs-manifest/overload-stubs.log`). The drift hash of these entries does not change when the implementation changes.')
w('* Lean names shared by four or more entries (the hash of each of these upstream functions points at one large Lean definition):')
for n, ids in sorted(shared.items(), key=lambda x: -len(x[1])):
    if len(ids) >= 4:
        l = names[n]
        w(f"  * `{short(n)}` ({l['kind']}, {l['loc']}): {len(ids)} entries: " + ', '.join(f"M-{i}" for i in ids))
w('* Entries whose Lean name does the job only in a loose sense (the name is a wider or a different definition; the note, where there is one, says what part is meant):')
loose = [(54, 'the webhook dispatcher stands for `async_register`'), (112, 'a constant stands for `async_track_utc_time_change`'),
         (126, 'the template copy `hassStatesGet` is used by `expand` only; every other template lookup is exact (TPL-6)'),
         (141, '`thisValue` stands for `capability_attributes`'), (145, 'see Not correct'), (175, 'the input decoder stands for `get_astral_observer`'),
         (190, '`State.expire` is the identity on the model'), (263, '`writeEntity` and `runsOf` stand for the property `Script.runs`'),
         (266, '`reloadScripts` holds the one branch of `__async_remove_impl` a script entity takes'),
         (268, '`reloadScripts` keeps `last_triggered` of a removed entity'), (274, 'see Not correct')]
for i, why in loose:
    r = next(r for r in rows if r['id'] == i)
    w(f"  * M-{i} `{r['python']}` → {r['names']}: {why}.")
w()
w('## Differences found here that no area `FINDINGS.md` lists')
w()
w('Each reproduced on two runs (`logs-manifest/two-runs.log`).')
w()
w('| entry | input | HA | HALean | logs |')
w('|---|---|---|---|---|')
w('| M-17 | a call to a service that does not exist, `continue_on_error: true`, then an `event` action; the shell reports the error as the bridge does (`ha_error`, `bridge/bridge.py:81`) | the run ends with ServiceNotFound, no event | the run goes on and fires the event | `logs-manifest/probe-ha.log` [M-17], `logs-manifest/probe-m17-engine.log` |')
w('| M-8 | time condition `after: sensor.ts`, state `2023-11-14`, `device_class: timestamp` | condition true, the action runs | condition false, debug log only | `logs-manifest/probe-ha.log` [M-8], `logs-manifest/probe-automation.log` [M-8] |')
w('| M-80 | action with the static `target: {entity_id: "Light.A, light.b"}`; and with `entity_id: "not an id"` | `[\'light.a\', \'light.b\']`; the second is rejected at load | sent as written; the second loads | `logs-manifest/probe-m80-static-target.log` |')
w()
(HERE.parent / 'CLAIMS-MANIFEST-TRANSLATED.md').write_text('\n'.join(W) + '\n')
# machine-readable copy and the summary the final message quotes
json.dump([{k: r[k] for k in ('id', 'python', 'verdict', 'notes')} for r in rows], open(HERE.parent / 'logs-manifest/verdicts.json', 'w'), indent=0)
with open(HERE.parent / 'logs-manifest/verdict-counts.log', 'w') as f:
    for v in VERDICTS: print(f"{v}: with notes {cnt[(v, True)]}, without {cnt[(v, False)]}, total {cnt[(v, True)] + cnt[(v, False)]}", file=f)
    print(f"all: with notes {tn}, without {tw}, total {len(rows)}", file=f)
    for r in rows:
        if r['verdict'] != 'correct': print(f"M-{r['id']} [{r['verdict']}] {NC[r['id']][1]}", file=f)
print(open(HERE.parent / 'logs-manifest/verdict-counts.log').read())
