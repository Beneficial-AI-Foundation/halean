"""Check class/*.tsv against logs/theorems.tsv and print class counts per module with proof lengths.
Usage: python3 review/experiments/10-theorems/classify_summary.py > logs/classification-summary.txt"""
import collections
from pathlib import Path
T = Path(__file__).resolve().parent
thms = {(l.split('\t')[0], l.split('\t')[1]): l.rstrip('\n').split('\t') for l in (T/'logs/theorems.tsv').read_text().splitlines()}
cls = {}; dup = []; bad = []
for f in sorted((T/'class').glob('*.tsv')):
    for l in f.read_text().splitlines():
        p = l.split('\t')
        if len(p) < 3: bad.append((f.name, l[:60])); continue
        n, c = (p[0].strip(), p[1].strip()), p[2].strip()
        if c not in 'COEH' or len(c) != 1: bad.append((f.name, l[:60])); continue
        if n in cls: dup.append(n)
        cls[n] = c
print('theorems:', len(thms), ' classified:', len(set(cls) & set(thms)), ' unknown names in class files:', sorted(set(cls) - set(thms))[:10],
      ' unclassified:', sorted(set(thms) - set(cls))[:10], ' duplicates:', len(dup), ' malformed lines:', bad[:5])
per = collections.defaultdict(collections.Counter); pl = collections.defaultdict(list)
for n, t in thms.items():
    c = cls.get(n, '?'); per[t[0]][c] += 1; pl[c].append(int(t[5]))
print('\nmodule\tC\tO\tE\tH\ttotal')
tot = collections.Counter()
for m in sorted(per):
    print(m, *(per[m][c] for c in 'COEH'), sum(per[m].values()), sep='\t'); tot.update(per[m])
print('TOTAL', *(tot[c] for c in 'COEH'), sum(tot.values()), sep='\t')
print('\nclass\ttheorems\tproof lines total\tmedian\tmean\tmax\t1-line proofs')
for c in 'COEH':
    x = sorted(pl[c]); print(c, len(x), sum(x), x[len(x)//2], f'{sum(x)/len(x):.1f}', x[-1], sum(1 for v in x if v <= 1), sep='\t')
x = sorted(sum(pl.values(), [])); print('all', len(x), sum(x), x[len(x)//2], f'{sum(x)/len(x):.1f}', x[-1], sum(1 for v in x if v <= 1), sep='\t')
