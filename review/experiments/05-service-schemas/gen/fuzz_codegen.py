"""Python only: the interpreted probatio engine (a fresh schema) against the generated code
(the same schema after 60 validations) on random specs and data. Usage: fuzz_codegen.py SEED SCHEMAS."""
import sys, random, collections, json, copy, re
H=__import__('os').path.dirname(__import__('os').path.abspath(__file__)); sys.path.insert(0,H); sys.path.insert(0,H+'/../harness')
import gen_random, probatio
from schema_spec import make_schema
from explore import ha_validate
seed=int(sys.argv[1]); N=int(sys.argv[2])
r=random.Random(seed); sigs=collections.defaultdict(list); n=0
for i in range(N):
    c=gen_random.case(r,i,8,seed); spec=c["ops"][0]["schema"]
    # no cv.* objects here: they are process-wide and warm up on their own
    try:
        cold=make_schema(spec); warm=make_schema(spec)
    except Exception as e: continue
    for _ in range(60):
        try: warm({})
        except Exception: pass
    for op in c["ops"][1:]:
        d=op["data"]; n+=1
        a=ha_validate(make_schema(spec),d); b=ha_validate(warm,d)
        if a!=b:
            sig=f"{a[0]}:{a[1] if a[0]=='err' else ''} / {b[0]}:{b[1] if b[0]=='err' else ''}"
            if a[0]==b[0]=='err' and a[1]==b[1]: sig="MSG "+re.sub(r"[0-9]+","N",a[2])[:45]+" / "+re.sub(r"[0-9]+","N",b[2])[:45]
            sigs[sig].append((spec,d,a,b))
print(n,"pairs",sum(map(len,sigs.values())),"differ")
def cut(x):
    s=x if isinstance(x,str) else json.dumps(x); return s if len(s)<500 else s[:330]+" ... "+s[-120:]
for sig,items in sorted(sigs.items(), key=lambda kv:-len(kv[1])):
    print(f"\n== {len(items)} x {sig}")
    for spec,d,a,b in sorted(items,key=lambda it:len(json.dumps(it[0]))+len(json.dumps(it[1])))[:2]:
        print("  spec",cut(spec)); print("  data",cut(d)); print("  cold",cut(repr(a))); print("  warm",cut(repr(b)))
