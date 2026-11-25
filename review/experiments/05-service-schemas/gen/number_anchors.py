"""Give the `&c` / `*c` anchors of a hand-written case file a number per case
(PyYAML refuses a duplicate anchor in one document). Usage: number_anchors.py FILE..."""
import re, sys
for path in sys.argv[1:]:
    out, n = [], 0
    for line in open(path):
        if line.startswith("- name:"):
            n += 1
        line = re.sub(r"&c\d* ", f"&c{n} ", line)
        line = re.sub(r"\*c\d*,", f"*c{n},", line)
        line = re.sub(r"\*c\d*\}", f"*c{n}}}", line)
        out.append(line)
    open(path, "w").write("".join(out))
