"""Does drift.py's hash ignore docstrings, comments and formatting, and see a code change?
Uses a throwaway copy of one upstream file; imports tools/drift.py read-only."""
import sys, shutil, pathlib, importlib.util
spec = importlib.util.spec_from_file_location("drift", "/home/user/halean/tools/drift.py")
drift = importlib.util.module_from_spec(spec); sys.dont_write_bytecode = True; spec.loader.exec_module(drift)
tmp = pathlib.Path("/tmp/claude-0/halean-copies/12-claims-drift/homeassistant/util"); tmp.mkdir(parents=True, exist_ok=True)
src = drift.UPSTREAM / "util" / "location.py"
ref = "util/location.py::distance"
base = tmp.parent
def h(text):
    (tmp / "location.py").write_text(text); return drift.hash_ref(ref, base)
orig = src.read_text()
h0 = h(orig)
print("original           ", h0, "== upstream:", h0 == drift.hash_ref(ref))
lines = orig.splitlines(keepends=True)
i = next(k for k, l in enumerate(lines) if l.startswith("def distance("))
j = next(k for k in range(i, len(lines)) if lines[k].rstrip().endswith(":"))  # end of signature
with_comment = "".join(lines[: j + 1] + ["    # a new comment\n"] + lines[j + 1 :])
print("comment added      ", h(with_comment), "same:", h(with_comment) == h0)
d = orig.index('"""', orig.index("def distance(")) + 3
doc_changed = orig[:d] + "CHANGED " + orig[d:]
print("docstring changed  ", h(doc_changed), "same:", h(doc_changed) == h0, "(text differs:", doc_changed != orig, ")")
blank = orig.replace("def distance(", "\n\n\ndef distance(")
print("blank lines added  ", h(blank), "same:", h(blank) == h0)
code = "".join(lines[: j + 1]) + "".join(lines[j + 1 :]).replace("1000", "1001", 1) if "1000" in "".join(lines[j+1:]) else None
k = next(k for k in range(j + 1, len(lines)) if "return" in lines[k])
code = "".join(lines[:k] + [lines[k].replace("return ", "return 0 or ", 1)] + lines[k + 1 :])
print("code changed       ", h(code), "same:", h(code) == h0)
shutil.rmtree(tmp.parent.parent)
