"""Step 5: Lean code lines, theorems and partial definitions per area, and the share of implementation code
that substantive theorems (class C or O) cover.

Inputs: the Lean sources; review/experiments/10-theorems/logs/{theorems,defs}.tsv; class/*.tsv (if present).
Definitions:
  code line      = a line that is not blank after comments are removed.
  implementation = a file with no theorem (every theorem lives in a *Spec*/Proofs/EngineBound file; checked below).
  direct cover   = a source def (kinds def/opaque/instance, not `partial`) whose name occurs in the statement of at
                   least one theorem classed C or O. Share = code lines of such defs / code lines of all
                   implementation defs (def + partial + opaque + instance; types excluded from both).
  'are or call a partial def' = partial defs plus defs whose body reaches a partial def through calls.
  C-only direct  = the same as direct cover, counting only class-C theorems (statements that determine a result).
  reach cover    = defs reachable from those statements through the call graph of non-partial defs (upper bound:
                   a callee is only constrained through its caller's theorem). Partial defs are never counted as
                   covered: the kernel sees them as opaque constants, so no theorem can depend on their bodies.
Usage: python3 review/experiments/11-coverage-drift/coverage.py > logs/coverage.txt
"""
import re, sys, collections, importlib.util
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]; T = ROOT / 'review/experiments/10-theorems'
spec = importlib.util.spec_from_file_location('inv', T / 'inventory.py')
src = (T / 'inventory.py').read_text().split("thms = []; defs = []")[0]
ns = {'__file__': str(T / 'inventory.py')}; exec(src, ns); strip_comments = ns['strip_comments']

AREAS = [
 ('Core: state machine', ['Core/State.lean', 'Core/StateMachine.lean', 'Core/Types.lean'], ['Core/StateMachineSpec.lean', 'Core/StateSpec.lean', 'Core/StateSpec2.lean', 'Core/TypesSpec.lean', 'Core/Proofs.lean']),
 ('Core: event bus', ['Core/EventBus.lean'], ['Core/EventBusProofs.lean', 'Core/EventBusSpec2.lean']),
 ('Core: service registry', ['Core/ServiceRegistry.lean'], ['Core/ServiceRegistryProofs.lean', 'Core/ServiceRegistrySpec.lean']),
 ('Core: joined core', ['Core/Hass.lean'], ['Core/HassProofs.lean', 'Core/HassSchedProofs.lean', 'Core/HassSpec.lean']),
 ('Service schemas', ['Core/Probatio.lean', 'Core/ConfigValidation.lean', 'Core/Schema.lean', 'Core/ServicesJson.lean', 'Core/PyJson.lean'],
                     ['Core/ProbatioProofs.lean', 'Core/ProbatioSpec.lean', 'Core/ConfigValidationSpec.lean', 'Core/SchemaSpec.lean', 'Core/ServicesJsonSpec.lean', 'Core/PyJsonSpec.lean']),
 ('Templates', None, None), ('Automation engine', None, None), ('Scripts', None, None), ('Helpers', None, None),
]
DIRS = {'Templates': 'Template', 'Automation engine': 'Automation', 'Scripts': 'Script', 'Helpers': 'Helpers'}
def is_proof(name): return bool(re.search(r'(Spec\d*|Proofs|Bound)\.lean$', name))
def cl(path): return sum(1 for l in strip_comments(path.read_text()).split('\n') if l.strip())
def raw(path): return path.read_text().count('\n')

thms = [l.rstrip('\n').split('\t') for l in (T / 'logs/theorems.tsv').read_text().splitlines()]
defs = [l.rstrip('\n').split('\t') for l in (T / 'logs/defs.tsv').read_text().splitlines()]
cls = {}
for f in sorted((T / 'class').glob('*.tsv')):
    for l in f.read_text().splitlines():
        p = l.split('\t')
        if len(p) >= 3 and p[2].strip() in ('C', 'O', 'E', 'H'): cls[(p[0].strip(), p[1].strip())] = p[2].strip()
have_cls = bool(cls)
all_files = sorted((ROOT / 'HALean').rglob('*.lean'))
assigned = set(); rows = []
thm_files = {t[2] for t in thms}
impl_with_thm = [f for f in thm_files if not is_proof(f)]
print('theorems found in non-Spec/Proofs files:', impl_with_thm or 'none')
proof_with_defs = collections.Counter(d[3] for d in defs if is_proof(d[3]) and d[0] in ('def', 'partial'))
print('definitions inside Spec/Proofs files (specification helpers), count:', sum(proof_with_defs.values()))

# call graph over source defs
kind = {d[2]: d[0] for d in defs}; dfile = {d[2]: d[3] for d in defs}; dlines = {d[2]: int(d[6]) for d in defs}
uses = {d[2]: set(d[7].split()) if len(d) > 7 else set() for d in defs}
sub = [t for t in thms if cls.get((t[0], t[1])) in ('C', 'O')]
direct = set()
for t in sub:
    for c in (t[8].split() if len(t) > 8 else []):
        if kind.get(c) in ('def', 'opaque', 'instance'): direct.add(c)
directC = set()
for t in thms:
    if cls.get((t[0], t[1])) == 'C':
        for c in (t[8].split() if len(t) > 8 else []):
            if kind.get(c) in ('def', 'opaque', 'instance'): directC.add(c)
reach = set(direct); stack = list(direct)
while stack:
    x = stack.pop()
    for y in uses.get(x, ()):
        if y not in reach and kind.get(y) in ('def', 'instance'): reach.add(y); stack.append(y)

# defs whose value depends (transitively) on a partial def: proofs about them stop at the opaque call
dep_partial = {n for n, k in kind.items() if k == 'partial'}
changed = True
while changed:
    changed = False
    for n, u in uses.items():
        if n not in dep_partial and kind.get(n) in ('def', 'instance') and u & dep_partial:
            dep_partial.add(n); changed = True

hdr = ['area', 'impl files', 'impl code lines', 'proof files', 'proof code lines', 'theorems', 'partial defs', 'code lines in partial defs',
       'def code lines', 'lines in defs that are or call a partial def', 'C', 'O', 'E', 'H', 'direct cover lines', 'direct cover %', 'reach cover lines', 'reach cover %', 'C-only direct lines', 'C-only direct %']
tot = collections.Counter()
for name, impl, proof in AREAS:
    if impl is None:
        d = DIRS[name]; fs = sorted((ROOT / 'HALean' / d).glob('*.lean'))
        impl = [f'{d}/{f.name}' for f in fs if not is_proof(f.name)]; proof = [f'{d}/{f.name}' for f in fs if is_proof(f.name)]
    assigned |= {f'HALean/{x}' for x in impl + proof}
    I = {f'HALean/{x}' for x in impl}; P = {f'HALean/{x}' for x in proof}
    icl = sum(cl(ROOT / f) for f in I); pcl = sum(cl(ROOT / f) for f in P)
    ath = [t for t in thms if t[2] in P | I]
    adefs = [d for d in defs if d[3] in I and d[0] in ('def', 'partial', 'opaque', 'instance')]
    npart = sum(1 for d in adefs if d[0] == 'partial'); lpart = sum(int(d[6]) for d in adefs if d[0] == 'partial')
    ldef = sum(int(d[6]) for d in adefs)
    cc = collections.Counter(cls.get((t[0], t[1]), '?') for t in ath)
    dc = sum(int(d[6]) for d in adefs if d[2] in direct); rc = sum(int(d[6]) for d in adefs if d[2] in reach)
    ldp = sum(int(d[6]) for d in adefs if d[2] in dep_partial)
    row = [name, len(I), icl, len(P), pcl, len(ath), npart, lpart, ldef, ldp, cc['C'], cc['O'], cc['E'], cc['H'], dc, f'{100*dc/ldef:.1f}', rc, f'{100*rc/ldef:.1f}', sum(int(d[6]) for d in adefs if d[2] in directC), f"{100*sum(int(d[6]) for d in adefs if d[2] in directC)/ldef:.1f}"]
    rows.append(row)
    for k, v in zip(hdr[1:], row[1:]):
        if isinstance(v, int): tot[k] += v
rest = [str(f.relative_to(ROOT)) for f in all_files if str(f.relative_to(ROOT)) not in assigned]
print('files not assigned to an area (umbrella modules):', rest, 'code lines:', sum(cl(ROOT / f) for f in rest))
exe = sorted((ROOT / 'Exe').glob('*.lean'))
print('Exe/ drivers:', len(exe), 'files,', sum(cl(f) for f in exe), 'code lines, theorems: 0, partial defs:',
      sum(len(re.findall(r'^\s*(?:private |protected )?partial def', strip_comments(f.read_text()), re.M)) for f in exe))
print('raw lines HALean/:', sum(raw(f) for f in all_files), ' code lines HALean/:', sum(cl(f) for f in all_files))
print('classification available:', have_cls, ' classified theorems:', len(cls), 'of', len(thms), '\n')
print('\t'.join(hdr))
for r in rows: print('\t'.join(map(str, r)))
t = ['TOTAL'] + [tot[k] if k in tot else '' for k in hdr[1:]]
ld = tot['def code lines']
t[hdr.index('direct cover %')] = f"{100*tot['direct cover lines']/ld:.1f}"; t[hdr.index('reach cover %')] = f"{100*tot['reach cover lines']/ld:.1f}"
t[hdr.index('C-only direct %')] = f"{100*tot['C-only direct lines']/ld:.1f}"
print('\t'.join(map(str, t)))
print('\nproof length per class (code lines): class, theorems, total, median, max')
for c in 'COEH?':
    pl = sorted(int(x[5]) for x in thms if cls.get((x[0], x[1]), '?') == c)
    if pl: print(c, len(pl), sum(pl), pl[len(pl)//2], pl[-1], sep='\t')
