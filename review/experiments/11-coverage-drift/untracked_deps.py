"""What do mapped upstream functions read that tools/drift.py does not hash?
For every non-probatio manifest entry: names the function's AST loads that are
(a) module-level functions/classes of the same file that are not mapped (directly or as an enclosing mapped class),
(b) module-level assignments of the same file (constants, regexes, schemas),
(c) names imported from homeassistant.const.
Usage: /opt/havenv/bin/python review/experiments/11-coverage-drift/untracked_deps.py > logs/untracked-deps.log
"""
import ast, sys, yaml, collections
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
UP = ROOT / "upstream/ha-core/homeassistant"
man = yaml.safe_load((ROOT / "manifest.yaml").read_text())
entries = [e["python"] for e in man["entries"] if not e["python"].startswith("probatio:")]
mapped = set(entries)
def find(tree, qual):
    scope, node = tree.body, None
    for part in qual.split("."):
        node = next((n for n in scope if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == part), None)
        if node is None: return None
        scope = node.body
    return node
trees = {}
tot = collections.Counter(); ex = collections.defaultdict(set); per_entry = {}
for ref in entries:
    path, _, qual = ref.partition("::")
    tree = trees.setdefault(path, ast.parse((UP / path).read_text()))
    node = find(tree, qual)
    if node is None: print("NOT FOUND", ref); continue
    funcs = {n.name for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))}
    consts = set()
    for n in tree.body:
        tg = n.targets if isinstance(n, ast.Assign) else [n.target] if isinstance(n, ast.AnnAssign) else []
        for t in tg:
            if isinstance(t, ast.Name): consts.add(t.id)
    from_const = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.ImportFrom) and n.module and n.module.endswith("const"):
            from_const |= {a.asname or a.name for a in n.names}
    loads = {n.id for n in ast.walk(node) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    cls = qual.split(".")[0] if "." in qual else None
    uf = {x for x in loads & funcs if f"{path}::{x}" not in mapped and x != cls and x != qual
          and not any(m.startswith(f"{path}::{x}.") for m in mapped)}
    uc = loads & consts; ui = loads & from_const
    # self.method calls on the same class that are unmapped
    um = set()
    if cls:
        cnode = find(tree, cls)
        meths = {m.name for m in cnode.body if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))}
        for n in ast.walk(node):
            if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in ("self", "cls") and n.attr in meths \
               and f"{path}::{cls}.{n.attr}" not in mapped and f"{path}::{cls}" not in mapped:
                um.add(f"{cls}.{n.attr}")
    per_entry[ref] = (uf, um, uc, ui)
    for k, s in (("unmapped same-file functions/classes", uf), ("unmapped methods of the same class (self.x)", um),
                 ("module-level assignments (constants)", uc), ("names imported from const modules", ui)):
        if s: tot[k] += 1
        for x in s: ex[k].add(f"{path}::{x}")
print(f"mapped HA functions analysed: {len(entries)}")
any_dep = sum(1 for v in per_entry.values() if any(v))
print(f"entries that read at least one thing drift.py does not hash: {any_dep}")
for k in ("unmapped same-file functions/classes", "unmapped methods of the same class (self.x)",
          "module-level assignments (constants)", "names imported from const modules"):
    print(f"\n{k}: {tot[k]} entries, {len(ex[k])} distinct names")
    for x in sorted(ex[k])[:400]: print("   ", x)
