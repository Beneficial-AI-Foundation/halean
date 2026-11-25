"""README:746 "402 upstream functions": the AST node kind each manifest entry resolves to."""
import ast, yaml, importlib.util, collections
spec = importlib.util.spec_from_file_location("drift", "/home/user/halean/tools/drift.py"); d = importlib.util.module_from_spec(spec); spec.loader.exec_module(d)
m = yaml.safe_load(open("/home/user/halean/manifest.yaml")); kinds = collections.Counter(); classes = []
for e in m["entries"]:
    ref = e["python"]; base = d.UPSTREAM
    if ref.startswith("probatio:"): ref, base = ref[9:], d.probatio_dir()
    path, _, qual = ref.partition("::"); node = d.find_node(ast.parse((base / path).read_text()), qual)
    k = type(node).__name__; kinds[k] += 1
    if k == "ClassDef": classes.append(e["python"])
print("manifest entries by AST node kind:", dict(kinds)); print("class entries:", classes)
