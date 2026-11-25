"""For every commit that touched manifest.yaml or README.md: manifest files outside the sparse set of that commit's README.
Prints a line only when the answer changes."""
import subprocess, re, yaml
def sh(*a): return subprocess.run(a, capture_output=True, text=True, cwd="/home/user/halean").stdout
prev = None
for c in reversed(sh("git", "log", "--format=%h %ad", "--date=short", "--", "manifest.yaml", "README.md").splitlines()):
    h = c.split()[0]
    readme = sh("git", "show", f"{h}:README.md"); man = sh("git", "show", f"{h}:manifest.yaml")
    m = re.search(r"sparse-checkout set --no-cone(.*?)```", readme, re.S)
    if not m or not man: continue
    pats = [p[len("/homeassistant/"):] for p in re.findall(r"/homeassistant/\S+", m.group(1))]
    files = sorted({e["python"].partition("::")[0] for e in yaml.safe_load(man)["entries"] if not e["python"].startswith("probatio:")})
    miss = [f for f in files if not any(f == p or (p.endswith("/") and f.startswith(p)) for p in pats)]
    if miss != prev: print(c, "outside:", miss)
    prev = miss
