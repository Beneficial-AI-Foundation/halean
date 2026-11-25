"""Build the bug list table and its counts from bugs.tsv (ID, area, bug, kind, patched).
Usage: python3 review/data/build_buglist.py   -> review/data/buglist.md, review/data/buglist-counts.txt"""
import collections
from pathlib import Path
D = Path(__file__).resolve().parent
rows = [l.split('\t') for l in (D / 'bugs.tsv').read_text().splitlines() if l.strip()]
assert all(len(r) == 5 for r in rows), [r[0] for r in rows if len(r) != 5]
assert len({r[0] for r in rows}) == len(rows)
kinds = ['Silent', 'Accepts', 'Refuses', 'Order', 'Tooling']
assert all(r[3] in kinds for r in rows) and all(r[4] in ('yes', 'partial', 'no') for r in rows)
md = ['| ID | Area | Bug | Kind | Patched |', '|---|---|---|---|---|']
md += [f"| {i} | {a} | {b.replace('|', chr(92) + '|')} | {k} | {p} |" for i, a, b, k, p in rows]
(D / 'buglist.md').write_text('\n'.join(md) + '\n')
areas = list(dict.fromkeys(r[1] for r in rows))
out = [f'bugs: {len(rows)}', '', 'area\t' + '\t'.join(kinds) + '\ttotal\tpatched yes\tpartial\tno']
for a in areas:
    rs = [r for r in rows if r[1] == a]; c = collections.Counter(r[3] for r in rs); p = collections.Counter(r[4] for r in rs)
    out.append('\t'.join([a] + [str(c[k]) for k in kinds] + [str(len(rs)), str(p['yes']), str(p['partial']), str(p['no'])]))
c = collections.Counter(r[3] for r in rows); p = collections.Counter(r[4] for r in rows)
out.append('\t'.join(['ALL'] + [str(c[k]) for k in kinds] + [str(len(rows)), str(p['yes']), str(p['partial']), str(p['no'])]))
(D / 'buglist-counts.txt').write_text('\n'.join(out) + '\n'); print('\n'.join(out))
