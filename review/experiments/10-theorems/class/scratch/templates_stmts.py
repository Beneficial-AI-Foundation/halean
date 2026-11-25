import sys,re
mods=sys.argv[1:]
rows=[l.rstrip('\n').split('\t') for l in open('review/experiments/10-theorems/logs/theorems.tsv')]
for r in rows:
    if r[0].split('.')[-1] not in mods: continue
    lines=open(r[2]).read().split('\n')
    s,e=int(r[3]),int(r[4])
    # docstring: look back
    j=s-2; doc=[]
    if j>=0 and lines[j].rstrip().endswith('-/'):
        k=j
        while k>=0 and '/--' not in lines[k]: k-=1
        doc=lines[k:j+1]
    out=[]
    for i in range(s-1,e):
        out.append(lines[i])
        if re.search(r':=\s*(by)?\s*$',lines[i]) or re.search(r':=\s*by\s',lines[i]) or re.search(r':= ',lines[i]): break
        if i>s-1 and re.match(r'\s+\|',lines[i]): out.pop(); break
    print(f"### {r[0].split('.')[-1]} {r[1].replace('HALean.Template.','')} L{s}-{e} doc={r[7]}")
    if doc: print(' '.join(x.strip() for x in doc))
    print('\n'.join(x[:400] for x in out))
