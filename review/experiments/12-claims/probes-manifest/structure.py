#!/usr/bin/env python
"""Structure facts for every `translated` manifest entry.
Writes logs-manifest/structure.tsv, logs-manifest/structure.json and logs-manifest/structure-summary.log."""
import ast, csv, importlib.util, json, sys, collections, re
from pathlib import Path
import yaml
ROOT = Path('/home/user/halean')
HERE = Path(__file__).resolve().parent
LOGS = HERE.parent / 'logs-manifest'
UP = ROOT / 'upstream/ha-core/homeassistant'
PROB = Path(importlib.util.find_spec('probatio').origin).parent

def find_node(tree, qualname):  # same logic as tools/drift.py
    scope = tree.body; node = None
    for part in qualname.split('.'):
        node = next((n for n in scope if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == part), None)
        if node is None: return None
        scope = node.body
    return node

defs = {}
for row in csv.reader(open(ROOT / 'review/experiments/10-theorems/logs/defs.tsv'), delimiter='\t'):
    kind, mod, name, file, l0, l1 = row[:6]
    defs.setdefault(name, (kind, file, l0, l1))

# independent existence check: grep declarations in the Lean sources
decl_re = re.compile(r'^\s*(?:@\[[^\]]*\]\s*)*(?:private\s+|protected\s+|noncomputable\s+|unsafe\s+)*(partial\s+)?(def|abbrev|structure|inductive|instance|theorem|opaque|class)\s+([^\s:({\[]+)')
src = {}
for f in sorted((ROOT / 'HALean').rglob('*.lean')):
    ns = []
    for i, line in enumerate(f.read_text().splitlines(), 1):
        m = re.match(r'^namespace\s+(\S+)', line)
        if m: ns.append(m.group(1)); continue
        m = re.match(r'^end\s+(\S+)', line)
        if m and ns and ns[-1] == m.group(1): ns.pop(); continue
        m = decl_re.match(line)
        if m:
            full = '.'.join(ns + [m.group(3)])
            src.setdefault(full, (('partial ' if m.group(1) else '') + m.group(2), str(f.relative_to(ROOT)), i))

data = yaml.safe_load(open(ROOT / 'manifest.yaml'))
trees = {}
out = []; summary = collections.Counter(); shared = collections.defaultdict(list)
for idx, e in enumerate(data['entries'], 1):
    if e['status'] != 'translated': continue
    ref = e['python']; r = ref; base = UP
    if r.startswith('probatio:'): r = r[len('probatio:'):]; base = PROB
    path, _, qual = r.partition('::')
    f = base / path
    node = None
    if f.exists():
        if f not in trees: trees[f] = ast.parse(f.read_text())
        node = find_node(trees[f], qual)
    kind = type(node).__name__ if node is not None else 'MISSING'
    summary['py:' + kind] += 1
    leans = []
    for n in e['lean']:
        d = defs.get(n); s = src.get(n)
        if s is None:
            # try private/sub-namespace: search by last components
            pass
        lk = (d[0] if d else None); loc = (f'{d[1]}:{d[2]}' if d else (f'{s[1]}:{s[2]}' if s else None))
        if d is None and s is None: lk = 'MISSING'
        elif d is None: lk = 'src-only:' + s[0]
        leans.append({'name': n, 'kind': lk, 'loc': loc, 'src': s[0] if s else None})
        summary['lean:' + str(lk)] += 1
        shared[n].append(idx)
    out.append({'id': idx, 'python': ref, 'pyfile': str(f.relative_to(ROOT)) if base == UP else str(f), 'pykind': kind,
                'pyline': getattr(node, 'lineno', None), 'pyend': getattr(node, 'end_lineno', None),
                'lean': leans, 'notes': e.get('notes'), 'hash': e['hash']})
json.dump(out, open(LOGS / 'structure.json', 'w'), indent=1)
with open(LOGS / 'structure.tsv', 'w') as fh:
    for o in out:
        fh.write('\t'.join([f"M-{o['id']}", o['python'], o['pykind'], f"{o['pyfile']}:{o['pyline']}-{o['pyend']}",
                 '; '.join(f"{l['name']} [{l['kind']}] {l['loc']}" for l in o['lean']), 'notes' if o['notes'] else '-']) + '\n')
with open(LOGS / 'structure-summary.log', 'w') as fh:
    def p(*a):
        print(*a); print(*a, file=fh)
    p('translated entries:', len(out))
    p('with notes:', sum(1 for o in out if o['notes']), 'without:', sum(1 for o in out if not o['notes']))
    for k, v in sorted(summary.items()): p(k, v)
    names = {l['name']: l for o in out for l in o['lean']}
    p('distinct lean names in translated entries:', len(names))
    kc = collections.Counter(l['kind'] for l in names.values())
    p('distinct lean names by kind:', dict(kc))
    p('entries with a MISSING lean name:')
    for o in out:
        m = [l['name'] for l in o['lean'] if l['kind'] == 'MISSING']
        if m: p(f"  M-{o['id']} {o['python']}: {m}")
    p('entries with a partial def:')
    for o in out:
        m = [l['name'] for l in o['lean'] if l['kind'] and 'partial' in l['kind']]
        if m: p(f"  M-{o['id']} {o['python']}: {m}")
    p('entries mapping a class:')
    for o in out:
        if o['pykind'] == 'ClassDef': p(f"  M-{o['id']} {o['python']}")
    p('lean names shared by >=4 translated entries:')
    for n, ids in sorted(shared.items(), key=lambda x: -len(x[1])):
        if len(ids) >= 4: p(f"  {n}: {len(ids)} entries: {', '.join('M-%d' % i for i in ids)}")
    p('entries per upstream file:')
    for k, v in collections.Counter(o['python'].split('::')[0] for o in out).most_common(): p(f'  {v:4d} {k}')
