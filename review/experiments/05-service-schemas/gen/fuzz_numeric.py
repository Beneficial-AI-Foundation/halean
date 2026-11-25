"""Fast tool (not the verdict): numeric fuzz of the time-period validators, float repr and Coerce.
Usage: fuzz_numeric.py SEED. Prints one summary line per validator; DIFF lines show HA and HALean answers."""
import sys, random, struct, string
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from explore import *
eng=Engine()
r=random.Random(int(sys.argv[1]))
def run(name, v, datas, show=6):
    global eng
    spec={"fields":[{"key":"k","value":v}]}; schema=make_schema(spec); first=True; bad=0; uns=0
    for x in datas:
        d={"k":x}; ha=ha_validate(schema,d)
        try: le=lean_validate(eng,spec,d,reg=first); first=False
        except RuntimeError: le=("DIED",); eng=Engine(); first=True
        if le[0].startswith("unsupported"): uns+=1; continue
        if ha!=le:
            bad+=1
            if bad<=show: print("  DIFF",name,repr(x)[:120],"|",repr(ha)[:160],"|",repr(le)[:160])
    print(f"{name}: {len(datas)} data, {bad} differ, {uns} unsupported")
def rf():
    k=r.random()
    if k<0.3: return r.uniform(-100,100)
    if k<0.5: return r.randint(-10**6,10**6)/10**r.randint(0,9)
    if k<0.7: return r.randint(0,2000001)*0.5e-6*r.choice([1,-1]) + r.randint(-1000,1000)
    if k<0.8: return float(r.randint(-10**12,10**12))+r.random()
    if k<0.9: return r.uniform(-1,1)*10**r.randint(-12,13)
    return struct.unpack('d',struct.pack('Q',r.getrandbits(64)&0x7fffffffffffffff))[0]*0+r.uniform(0,8.6e13)
import math
fl=[x for x in (rf() for _ in range(6000)) if math.isfinite(x)]
run("time_period_seconds float", {"cv":"time_period_seconds"}, fl)
run("time_period_seconds str", {"cv":"time_period_seconds"}, [repr(x) for x in fl[:2000]])
run("time_period", {"cv":"time_period"}, fl[:1500]+[int(x) for x in fl[:500]])
units=["days","hours","minutes","seconds","milliseconds"]
ds=[]
for _ in range(6000):
    d={}
    for u in r.sample(units, r.randint(1,5)): d[u]=r.choice([rf(), rf(), r.randint(-50,50), str(round(rf(),r.randint(0,8)))])
    ds.append(d)
run("time_period_dict", {"cv":"time_period_dict"}, ds)
run("positive_time_period_dict", {"cv":"positive_time_period_dict"}, ds[:2000])
ss=[]
for _ in range(5000):
    h=r.choice([str(r.randint(0,99)), f"{r.randint(0,23):02d}", str(r.randint(-5,5)), " 1", "1_0"]); m=r.choice([str(r.randint(0,99)), f"{r.randint(0,59):02d}", "-3"])
    s=f"{h}:{m}"
    if r.random()<0.7: s+=":"+r.choice([repr(abs(rf())), f"{r.uniform(0,60):.{r.randint(0,9)}f}", str(r.randint(0,99)), "1e-7", ".5"])
    ss.append(r.choice(["","-","+"])+s)
run("time_period_str", {"cv":"time_period_str"}, ss)
run("positive_time_period", {"cv":"positive_time_period"}, ss[:2000]+fl[:1000])
# floats repr / coerce
fs=[struct.unpack('d',struct.pack('Q',r.getrandbits(64)))[0] for _ in range(8000)]
fs=[x for x in fs if math.isfinite(x)]
run("float type repr", "float", fs)
run("coerce float from repr str", {"coerce":"float"}, [repr(x) for x in fs[:3000]]+[f"{r.randint(0,10**r.randint(1,25))}e{r.randint(-340,310)}" for _ in range(3000)]+[f"{r.random()*10**r.randint(-5,25):.{r.randint(0,25)}f}" for _ in range(2000)])
run("coerce int from float", {"coerce":"int"}, fs[:3000])
run("coerce str from float", {"coerce":"str"}, fs[:2000]+[x for x in (r.uniform(-1,1)*10**r.randint(-8,20) for _ in range(3000))])
run("range float", {"range":{"min":0.1,"max":2**53,"max_included":False}}, [r.choice([0.1,0.1000000000000000055,2**53,2**53+1,2**53-1,float(2**53),9007199254740993,0.09999999999999999,0.10000000000000002])for _ in range(50)])
run("in mixed", {"in":[1,2.5,2**53,True,0,"a"]}, [1.0,True,False,0.0,-0.0,2**53+1,float(2**53),2.5,"A",None,[1],9007199254740993,1.0000000000000002])
