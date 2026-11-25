#!/usr/bin/env python
"""Which translated entries resolve (find_node: first match by name) to an @overload stub
instead of the implementation? Recomputes the drift hash of the stub and of the last
definition with that name, and compares both with the manifest hash.
Output: logs-manifest/overload-stubs.log"""
import ast, hashlib, importlib.util, json, sys
from pathlib import Path
ROOT = Path('/home/user/halean'); sys.path.insert(0, str(ROOT / 'tools')); sys.dont_write_bytecode = True
import yaml
UP = ROOT / 'upstream/ha-core/homeassistant'
PROB = Path(importlib.util.find_spec('probatio').origin).parent
def strip(node):
    for n in ast.walk(node):
        body = getattr(n, 'body', None)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)) and body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], 'value', None), ast.Constant) and isinstance(body[0].value.value, str):
            n.body = body[1:] or [ast.Pass()]
    return node
def h(node): return hashlib.sha256(ast.dump(strip(node), include_attributes=False).encode()).hexdigest()[:16]
def all_nodes(tree, qual):
    scope = tree.body; parts = qual.split('.')
    for p in parts[:-1]:
        node = next(n for n in scope if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == p)
        scope = node.body
    return [n for n in scope if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and n.name == parts[-1]]
out = open(Path(__file__).resolve().parent.parent / 'logs-manifest/overload-stubs.log', 'w')
def p(*a): print(*a); print(*a, file=out)
data = yaml.safe_load(open(ROOT / 'manifest.yaml')); n = 0; missing = 0; stale = 0
for i, e in enumerate(data['entries'], 1):
    ref = e['python']; base = UP
    if ref.startswith('probatio:'): ref = ref[9:]; base = PROB
    path, _, qual = ref.partition('::')
    f = base / path
    if not f.exists(): missing += 1; continue
    nodes = all_nodes(ast.parse(f.read_text()), qual)
    if not nodes: missing += 1; continue
    first = nodes[0]
    if h(ast.parse(ast.unparse(first)).body[0]) != e['hash']: stale += 1
    if e['status'] != 'translated': continue
    decos = [ast.unparse(d) for d in getattr(first, 'decorator_list', [])]
    if len(nodes) > 1:
        n += 1
        p(f"M-{i} {e['python']}: {len(nodes)} definitions with this name; find_node takes the first, line {first.lineno}-{first.end_lineno}, decorators {decos}")
        p(f"    manifest hash {e['hash']}; hash of first (line {first.lineno}) {h(first)}; hash of last (line {nodes[-1].lineno}-{nodes[-1].end_lineno}, the implementation) {h(nodes[-1])}")
p(f"translated entries that resolve to the first of several same-named definitions: {n}")
p(f"all 402 entries: missing refs {missing}, hash differs from manifest {stale}")
