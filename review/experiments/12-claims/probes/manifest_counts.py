"""Counts behind README numbers: manifest entries and statuses, files, demo automations, test cases per directory."""
import yaml, collections, glob, os
os.chdir("/home/user/halean")
m = yaml.safe_load(open("manifest.yaml")); es = m["entries"]
print("entries", len(es)); print(collections.Counter(e["status"] for e in es))
print("unique python refs", len({e["python"] for e in es}))
files = sorted({e["python"].partition("::")[0] for e in es}); print(len(files), "files")
for f in files: print(" ", f, sum(1 for e in es if e["python"].startswith(f + "::")))
print("demo automations", len(yaml.safe_load(open("demo/automations.yaml"))))
for g in ["tests/templates", "tests/core/states", "tests/core/services", "tests/core/events", "tests/core/hass", "tests/helpers"]:
    n = 0
    for f in sorted(glob.glob(g + "/*.yaml")):
        c = yaml.safe_load(open(f)); n += len(c); print("  ", f, len(c))
    print(g, n)
print("tests/scenarios", len(glob.glob("tests/scenarios/*.yaml")), "files; tests/script_scenarios", len(glob.glob("tests/script_scenarios/*.yaml")), "files")
