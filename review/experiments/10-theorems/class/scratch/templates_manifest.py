import yaml,re,collections
m=yaml.safe_load(open('manifest.yaml'))
impl={'HALean.Template.'+x for x in 'Syntax Value Render Time DateParse ParseTime PyInt Regex CvBoolean'.split()}
defs={}
for l in open('review/experiments/10-theorems/logs/defs.tsv'):
    f=l.rstrip('\n').split('\t'); defs.setdefault(f[2],[]).append((f[0],f[1]))
decl=set()
for l in open('review/experiments/10-theorems/logs/decls.tsv'):
    f=l.split('\t'); decl.add(f[1] if len(f)>1 else '')
thm={l.split('\t')[1] for l in open('review/experiments/10-theorems/logs/theorems.tsv')}
cnt=collections.Counter(); tot=0
for e in m['entries']:
    ls=e.get('lean') or []
    mine=[n for n in ls if any(mod in impl for k,mod in defs.get(n,[]))]
    if not mine: continue
    tot+=1; cnt[e['status']]+=1
    notes=e.get('notes') or ''
    if e['status']=='proven' or re.search(r'theorem|proved|proven|_iff|Spec',notes):
        print('##',e['python'],'|',e['status'],'|',ls,[defs.get(n) for n in ls],'\n   ',notes)
print(tot,cnt)
print('=====')
short={t.split('.')[-1]:t for t in thm}
allshort=set(short)
for e in m['entries']:
    ls=e.get('lean') or []
    mine=[n for n in ls if any(mod in impl for k,mod in defs.get(n,[]))]
    notes=e.get('notes') or ''
    ids=set(re.findall(r'[A-Za-z_][A-Za-z0-9_?.\']*',notes))
    hit=[i for i in ids if i in allshort or i.split('.')[-1] in allshort]
    tm=[i for i in hit if short.get(i.split('.')[-1],'').startswith('HALean.Template.')]
    if (mine and hit) or tm:
        print('@@',e['python'],'|',e['status'],'|',ls,'| hits',hit,'\n   ',notes)
