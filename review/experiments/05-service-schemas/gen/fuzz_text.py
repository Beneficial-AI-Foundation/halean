"""Fast tool (not the verdict): random ASCII text against the text-reading validators.
Usage: fuzz_text.py SEED."""
import sys, random, collections, re, string
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from explore import *
eng=Engine(); r=random.Random(int(sys.argv[1]))
def runspec(name, spec, datas, show=6):
    global eng
    schema=make_schema(spec); first=True; bad=0; uns=collections.Counter()
    for d in datas:
        ha=ha_validate(schema,d)
        try: le=lean_validate(eng,spec,d,reg=first); first=False
        except RuntimeError: le=("DIED",); eng=Engine(); first=True
        if le[0].startswith("unsupported"): uns[le[1][:50]]+=1; continue
        if ha!=le:
            bad+=1
            if bad<=show: print("  DIFF",name,repr(d)[:200],"|",repr(ha)[:260],"|",repr(le)[:260])
    print(f"{name}: {len(datas)} data, {bad} differ, unsupported {dict(uns)}")
def run(name,v,xs,show=6): runspec(name,{"fields":[{"key":"k","value":v}]},[{"k":x} for x in xs],show)
ASCII=[chr(i) for i in range(32,127)]
def rs(alpha, n=None):
    return "".join(r.choice(alpha) for _ in range(n if n is not None else r.randint(0,12)))
slugalpha="aaabbcAB01239__--  ''',,..&;#x!@/\\\"\t\n"
run("slug", {"cv":"slug"}, [rs(slugalpha) for _ in range(20000)]+[rs(ASCII+["\n","\t","\r","\x00","\x7f","\x1b"]) for _ in range(10000)])
entalpha="aabbzZ019__..  ,,\n-"
run("entity_id", {"cv":"entity_id"}, [rs(entalpha) for _ in range(15000)]+[rs("ab_.",r.randint(1,7)) for _ in range(5000)])
run("entity_ids", {"cv":"entity_ids"}, [rs(entalpha,r.randint(0,20)) for _ in range(10000)]+[[rs("ab_.A\n ",r.randint(1,7)) for _ in range(r.randint(0,3))] for _ in range(5000)])
run("comp_entity_ids", {"cv":"comp_entity_ids"}, [rs("alnoeALNOE ,._\n",r.randint(0,8)) for _ in range(10000)]+[[rs("ab_.A",r.randint(1,7)) for _ in range(r.randint(0,3))] for _ in range(2000)])
run("entity_domain one", {"cv":"entity_domain","domain":"a"}, [rs("ab_.A, \n",r.randint(0,9)) for _ in range(10000)])
run("entity_domain many", {"cv":"entity_domain","domain":["a","b_a","a\n"]}, [rs("ab_.A, \n",r.randint(0,9)) for _ in range(10000)])
run("color_hex", {"cv":"color_hex"}, [rs("#0123456789abcdefABCDEFgG \n",r.randint(5,9)) for _ in range(15000)]+["#"+rs("0123456789abcdefABCDEF",6)+s for s in ["","\n","\n\n"," ","\r","\r\n"]]+[123456,1.5,None,True,[],["#123456"]])
run("boolean", {"cv":"boolean"}, [rs("truefalsynoONEabld01 \t\n",r.randint(0,8)) for _ in range(15000)]+[" "*a+w+"\n"*b for a in range(2) for b in range(2) for w in ["1","TRUE","Yes","oN","Enable","0","FALSE","nO","OFF","Disable","enabled",""]])
run("string", {"cv":"string"}, [rs(ASCII) for _ in range(500)])
run("lower", {"lower":None}, [rs(ASCII+["\n","\t"]) for _ in range(3000)]+[[rs(ASCII)],{rs(ASCII):rs(ASCII)},{"A":[1.5,None,True,"X'y"]}])
run("upper", {"upper":None}, [rs(ASCII+["\n","\t"]) for _ in range(3000)]+[[rs(ASCII)],{rs(ASCII):rs(ASCII)},{"a":[1.5,None,True,"x'Y\"z"]}])
run("coerce str", {"coerce":"str"}, [[rs(ASCII+["\n","\t","\x00","\x7f","\x1f"])] for _ in range(3000)])
run("coerce int", {"coerce":"int"}, [rs("0123456789_+- \t\n.e",r.randint(0,7)) for _ in range(20000)])
run("coerce float", {"coerce":"float"}, [rs("0123456789_+- \t\n.eEinfa",r.randint(0,8)) for _ in range(30000)])
run("port", {"port":None}, [rs("0123456789_+- .",r.randint(0,7)) for _ in range(5000)]+[r.uniform(-10,70000) for _ in range(500)]+[float(r.randint(-10,70000)) for _ in range(500)]+list(range(-3,4))+[65534,65535,65536])
run("time_period_str ascii", {"cv":"time_period_str"}, [rs("0123456789:::+-. _e\n",r.randint(0,10)) for _ in range(30000)])
run("time_period ascii", {"cv":"time_period"}, [rs("0123456789::+-. _e",r.randint(0,10)) for _ in range(20000)])
