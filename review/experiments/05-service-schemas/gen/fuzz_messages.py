"""Fast tool (not the verdict): In "did you mean" (difflib), unknown-key suggestions, path rendering.
Usage: fuzz_messages.py SEED. Each summary is [data points, differ, unsupported]."""
import sys, random, collections, re, string
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from explore import *
eng=Engine(); r=random.Random(int(sys.argv[1]))
def runspec(name, spec, datas, show=5):
    global eng
    schema=make_schema(spec); first=True; bad=0; uns=collections.Counter()
    for d in datas:
        ha=ha_validate(schema,d)
        try: le=lean_validate(eng,spec,d,reg=first); first=False
        except RuntimeError: le=("DIED",); eng=Engine(); first=True
        if le[0].startswith("unsupported"): uns[le[1][:50]]+=1; continue
        if ha!=le:
            bad+=1
            if bad<=show: print("  DIFF",name,repr(d)[:300],"|",repr(ha)[:400],"|",repr(le)[:400])
    return len(datas),bad,sum(uns.values())
def rs(alpha,n): return "".join(r.choice(alpha) for _ in range(n))
tot=[0,0,0]
# In with did-you-mean: random pools of similar words
for it in range(400):
    alpha=r.choice(["ab","abc","abcd_","abcdefgh","aA_ "])
    pool=list({rs(alpha,r.randint(1,r.choice([4,8,14]))) for _ in range(r.randint(1,12))})
    datas=[{"k":rs(alpha,r.randint(0,r.choice([4,8,14])))} for _ in range(40)]+[{"k":p[:-1]} for p in pool]+[{"k":p+"a"} for p in pool]+[{"k":p[::-1]} for p in pool]+[{"k":p.upper()} for p in pool]
    a=runspec("in",{"fields":[{"key":"k","value":{"in":pool}}]},datas); tot=[x+y for x,y in zip(tot,a)]
print("in did-you-mean:",tot)
# long strings (autojunk at len(b) >= 200; b is the data value here)
tot=[0,0,0]
for it in range(60):
    alpha=r.choice(["ab","abcdefghij","abcdefghijklmnopqrstuvwxyz0123456789"])
    base=rs(alpha,r.choice([150,199,200,201,260,400]))
    pool=[base, base[:100]+"X"+base[100:], base[::-1], base[5:], rs(alpha,len(base))]
    datas=[]
    for _ in range(12):
        s=list(r.choice(pool))
        for _ in range(r.randint(1,30)): s[r.randrange(len(s))]=r.choice(alpha)
        if r.random()<0.5: del s[r.randrange(len(s)):][:r.randint(0,40)]
        datas.append({"k":"".join(s)})
    a=runspec("in-long",{"fields":[{"key":"k","value":{"in":pool}}]},datas); tot=[x+y for x,y in zip(tot,a)]
print("in long strings:",tot)
# extra keys: did you mean among schema keys
tot=[0,0,0]
for it in range(300):
    alpha=r.choice(["ab","abc_","abcdef","aA-. <>'"])
    keys=list({rs(alpha,r.randint(1,r.choice([4,8,12]))) for _ in range(r.randint(1,8))})
    spec={"fields":[{"key":k,"type":"object"} for k in keys]}
    datas=[{rs(alpha,r.randint(0,10)):1} for _ in range(30)]+[{k[:-1]:1,k+"x":2} for k in keys]+[{k[::-1]:1} for k in keys]
    a=runspec("extra",spec,datas); tot=[x+y for x,y in zip(tot,a)]
print("extra keys:",tot)
# path rendering of odd keys
keys=["a","a-b","-a","9a","a9","_","__a__","a.b","a b","","<a>","<a b>","<>","<a","a>","<<a>>","<a-b>","<9>","a\n","a'b",'a"b',"a'\"b","a\\b","\t","x"*500,"x"*501,"x"*497,"x"*498,"x"*499,"<"+"x"*498+">","<"+"x"*499+">","'"*250+'"'*250, "a\x00", "A_Z-0"]
a=runspec("paths",{"fields":[{"key":"n","value":{"dict":[{"key":"m","value":{"list":[{"dict":[{"key":"z","type":"int"}]}]}}]}}]},[{k:1} for k in keys]+[{"n":{k:1}} for k in keys]+[{"n":{"m":[{},{k:1}]}} for k in keys]+[{"n":{"m":[{"z":"s"}]*3}}]); print("paths:",a)
