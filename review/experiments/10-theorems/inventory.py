"""Join logs/decls.tsv (from Inventory.lean) with the source text.
Writes logs/theorems.tsv and logs/defs.tsv and prints totals.
theorems.tsv: module, name, file, start, end, proof_lines, stmt_lines, has_docstring, HALean constants in the statement
defs.tsv:     kind, module, name, file, start, end, code_lines, constants used in type+value
Line counts exclude blank lines and comments. proof_lines = code lines after the statement's top-level `:=`
(or from the first `|` alternative for pattern-matching proofs).
Usage: python3 review/experiments/10-theorems/inventory.py
"""
import re, sys, collections
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]; E = Path(__file__).resolve().parent

def strip_comments(text):
    """Replace comments with spaces (keeping newlines); string literals kept."""
    out = []; i = 0; n = len(text); depth = 0; in_str = False
    while i < n:
        c = text[i]
        if depth == 0 and in_str:
            out.append(c)
            if c == '\\' and i + 1 < n: out.append(text[i+1]); i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if text.startswith('/-', i):
            depth += 1; out.append('  '); i += 2; continue
        if depth > 0:
            if text.startswith('-/', i): depth -= 1; out.append('  '); i += 2; continue
            out.append('\n' if c == '\n' else ' '); i += 1; continue
        if text.startswith('--', i):
            j = text.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j; continue
        if c == '"': in_str = True
        out.append(c); i += 1
    return ''.join(out)

files = {}
def load(module):
    if module not in files:
        p = ROOT / (module.replace('.', '/') + '.lean')
        raw = p.read_text(); files[module] = (p, raw.split('\n'), strip_comments(raw).split('\n'))
    return files[module]

def code_lines(lines): return sum(1 for l in lines if l.strip())

KW_T = re.compile(r'^\s*(?:@\[[^\]]*\]\s*)*(?:(?:private|protected)\s+)*(theorem|lemma)\s+(\S+)')
KW_D = re.compile(r'^\s*(?:@\[[^\]]*\]\s*)*(?:(?:private|protected|noncomputable|unsafe|partial|scoped|local)\s+)*(def|abbrev|instance|structure|inductive|class|opaque)\b\s*(\S*)')

def split_proof(lines):
    """index of the first proof line and the column: top-level := outside brackets."""
    depth = 0
    for li, l in enumerate(lines):
        j = 0
        if li > 0 and depth == 0 and l.lstrip().startswith('|'): return li, 0
        while j < len(l):
            ch = l[j]
            if ch in '([{⟨': depth += 1
            elif ch in ')]}⟩': depth -= 1
            elif depth == 0 and l.startswith(':=', j): return li, j + 2
            j += 1
    return len(lines), 0

thms = []; defs = []
for row in (E / 'logs/decls.tsv').read_text().splitlines():
    kind, module, name, s, e, ty, *val = row.split('\t'); s = int(s); e = int(e); val = val[0] if val else ''
    p, raw, code = load(module)
    short = name.split('.')[-1]
    seg = code[s-1:e]
    if kind == 'theorem':
        k = next((i for i, l in enumerate(seg) if (m := KW_T.match(l)) and m.group(2).split('.')[-1].rstrip(':') == short), None)
        if k is None: continue          # structure field of Prop type, derived instance lemma, ...
        body = seg[k:]
        li, col = split_proof(body)
        stmt = body[:li] + ([body[li][:col]] if li < len(body) else [])
        proof = ([body[li][col:]] if li < len(body) else []) + body[li+1:]
        doc = any('/--' in l for l in raw[max(0, s-1):s-1+k+1])
        thms.append((module, name, str(p.relative_to(ROOT)), s + k, e, code_lines(proof), code_lines(stmt), int(doc), ty))
    else:
        k = next((i for i, l in enumerate(seg) if KW_D.match(l)), None)
        if k is None: continue          # structure fields, constructors, derived code
        m = KW_D.match(seg[k])
        if kind in ('def', 'partial', 'opaque') and m.group(2).split('.')[-1].rstrip(':') != short and m.group(1) not in ('instance',):
            continue                    # a field/projection inside a structure span
        if kind in ('def',) and m.group(1) in ('structure', 'inductive', 'class'): continue
        srckind = 'partial' if (kind in ('def','partial') and re.search(r'\bpartial\b', seg[k])) else kind
        defs.append((srckind if m.group(1) != 'instance' else 'instance', module, name, str(p.relative_to(ROOT)), s + k, e, code_lines(seg[k:]), (ty + ' ' + val).strip()))
(E / 'logs/theorems.tsv').write_text(''.join('\t'.join(map(str, t)) + '\n' for t in sorted(thms)))
(E / 'logs/defs.tsv').write_text(''.join('\t'.join(map(str, t)) + '\n' for t in sorted(defs)))
print('source theorems:', len(thms)); print('source definitions by kind:', dict(collections.Counter(d[0] for d in defs)))
pl = sorted(t[5] for t in thms)
print('proof lines: total', sum(pl), 'median', pl[len(pl)//2], 'max', pl[-1], '; 1-line proofs', sum(1 for x in pl if x <= 1), '; >=20 lines', sum(1 for x in pl if x >= 20))
