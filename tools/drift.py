#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pyyaml", "probatio==0.13.0"]
# ///
"""Track which upstream Home Assistant functions the Lean engine translates.

manifest.yaml maps each Python function (``path::Qual.name``) to the Lean
definitions that translate it, with a hash of the function's AST (``hash``)
and a hash of the module-level constants and unmapped helpers it uses,
followed through imports inside the package (``deps``). After you pull
upstream, ``check`` lists the translations whose function or dependencies
changed. It cannot see everything that changes a function's behaviour:
methods reached through ``self`` or an object, other classes' methods, and
code outside the package (the standard library, other libraries) are not
followed, so a clean ``check`` is evidence, not proof, that nothing moved.

  uv run tools/drift.py check      # report stale / missing entries (exit 1 if any)
  uv run tools/drift.py update     # re-hash everything and record the upstream commit
  uv run tools/drift.py update --only 'helpers/script.py::Script.async_run'
  uv run tools/drift.py coverage   # functions in tracked files that are not mapped
  uv run tools/drift.py compare --against <site-packages>/homeassistant

Entries written ``probatio:<path>::<Qual.name>`` map functions of probatio
(the validation library HA's schemas use, pinned in ``upstream.probatio``):
they are hashed against the probatio package this script runs with, which is
pinned to the same version above.

The hashes ignore docstrings, comments, formatting and line numbers, so only
real code changes mark an entry stale.
"""

from __future__ import annotations

import argparse
import ast
import copy
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "manifest.yaml"
UPSTREAM = ROOT / "upstream" / "ha-core" / "homeassistant"


def _strip_docstrings(node: ast.AST) -> ast.AST:
    for n in ast.walk(node):
        body = getattr(n, "body", None)
        if (
            isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module))
            and body
            and isinstance(body[0], ast.Expr)
            and isinstance(getattr(body[0], "value", None), ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            n.body = body[1:] or [ast.Pass()]
    return node


def find_node(tree: ast.Module, qualname: str) -> ast.AST | None:
    """Find a module-level function, class or method by dotted qualname."""
    scope: list[ast.stmt] = tree.body
    node: ast.AST | None = None
    for part in qualname.split("."):
        node = next(
            (
                n
                for n in scope
                if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
                and n.name == part
            ),
            None,
        )
        if node is None:
            return None
        scope = node.body  # type: ignore[attr-defined]
    return node


PROBATIO_PREFIX = "probatio:"


def probatio_dir() -> Path:
    spec = importlib.util.find_spec("probatio")
    assert spec is not None and spec.origin is not None, "probatio is not installed"
    return Path(spec.origin).parent


def hash_ref(ref: str, base: Path = UPSTREAM) -> str | None:
    """Hash ``path::Qual.name`` relative to a homeassistant/ package dir
    (``probatio:path::Qual.name``: relative to the probatio package)."""
    if ref.startswith(PROBATIO_PREFIX):
        ref, base = ref.removeprefix(PROBATIO_PREFIX), probatio_dir()
    path, _, qual = ref.partition("::")
    file = base / path
    if not file.exists():
        return None
    node = find_node(ast.parse(file.read_text()), qual)
    if node is None:
        return None
    dump = ast.dump(_strip_docstrings(node), include_attributes=False)
    return hashlib.sha256(dump.encode()).hexdigest()[:16]


# --- what a mapped function uses -------------------------------------------
#
# The hash of a function alone misses changes to the module-level constants
# and unmapped helpers it reads: `MAX_LENGTH_STATE_STATE` (const.py) or the
# `VALID_ENTITY_ID` regex change what `valid_entity_id` and
# `StateMachine.async_set` do without touching their syntax trees. `deps`
# hashes those definitions too: every module-level name a mapped function
# refers to (`NAME`, `module.NAME`, `Class.NAME`), resolved through relative
# and package imports to its defining module, followed transitively through
# constants and unmapped functions. Mapped functions are left out (they have
# their own entry); for a class only its class-level statements (enum
# members, class constants), not its methods, are included. Names from
# outside the package (the standard library, other libraries) are not
# followed.

_MODULES: dict[Path, dict[str, object]] = {}
# package modules an import names that are not on disk: in a sparse checkout
# that leaves them out, `deps` would silently differ
MISSING_FILES: set[str] = set()


def _module_path(base: Path, pkg: str, current: Path, module: str | None,
                 level: int) -> Path | None:
    """Where the module of `from <level dots><module> import ...` (or an
    absolute `pkg.x.y`) would be, without suffix; None outside the package."""
    if level:
        d = current.parent
        for _ in range(level - 1):
            d = d.parent
        parts = module.split(".") if module else []
    else:
        if not module or not (module == pkg or module.startswith(pkg + ".")):
            return None
        d = base
        parts = module.split(".")[1:]
    return d.joinpath(*parts) if parts else d


def _module_file(target: Path | None) -> Path | None:
    """The file of a module path: `x.py` or `x/__init__.py`."""
    if target is None:
        return None
    if target.with_suffix(".py").is_file():
        return target.with_suffix(".py")
    if (target / "__init__.py").is_file():
        return target / "__init__.py"
    return None


def _defs(file: Path, base: Path, pkg: str) -> dict[str, object]:
    """Module-level names of `file`: an AST node, ("import", file, name, path)
    for a name imported from a package module (`path`: where it would be if
    it is a submodule), ("module", file) for a module, or ("missing", path)
    for a package module that is not on disk."""
    if file in _MODULES:
        return _MODULES[file]
    out: dict[str, object] = {}
    _MODULES[file] = out
    tree = ast.parse(file.read_text())
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            out[n.name] = n
        elif isinstance(n, ast.Assign):
            for t in n.targets:
                for nm in ast.walk(t):
                    if isinstance(nm, ast.Name):
                        out[nm.id] = n
        elif isinstance(n, (ast.AnnAssign, ast.AugAssign)) and isinstance(n.target, ast.Name):
            out[n.target.id] = n
        elif isinstance(n, ast.ImportFrom):
            where = _module_path(base, pkg, file, n.module, n.level)
            if where is None:
                continue
            src = _module_file(where)
            for a in n.names:
                local = a.asname or a.name
                # `from . import util` / `from .x import submodule`: a module
                sub_where = where / a.name
                sub = _module_file(sub_where)
                if sub is not None:
                    out[local] = ("module", sub)
                elif src is not None:
                    out[local] = ("import", src, a.name, sub_where)
                else:
                    out[local] = ("missing", where)
        elif isinstance(n, ast.Import):
            for a in n.names:
                where = _module_path(base, pkg, file, a.name, 0)
                if where is None or not a.asname:
                    continue
                src = _module_file(where)
                out[a.asname] = ("module", src) if src is not None else ("missing", where)
    return out


def _missing(base: Path, where: Path) -> None:
    MISSING_FILES.add(where.relative_to(base).as_posix())


def _resolve(target: object, tfile: Path, base: Path, pkg: str) -> tuple[object, Path]:
    """Follow ("import", ...) entries to the definition they name."""
    for _ in range(40):
        if not (isinstance(target, tuple) and target[0] == "import"):
            break
        _, tfile, tname, sub_where = target
        defs = _defs(tfile, base, pkg)
        if tname not in defs and tfile.name == "__init__.py":
            # not defined in the package: a submodule that is not on disk
            _missing(base, sub_where)
        target = defs.get(tname)
    if isinstance(target, tuple) and target[0] == "missing":
        _missing(base, target[1])
        return None, tfile
    return target, tfile


def _refs(node: ast.AST) -> list[tuple[str, str | None]]:
    """Names read in `node`, outside type annotations: (`NAME`, None) and
    (`NAME`, attr) for `NAME.attr`."""
    out: list[tuple[str, str | None]] = []
    todo = [node]
    while todo:
        n = todo.pop()
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name):
            out.append((n.value.id, n.attr))
            continue
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load):
            out.append((n.id, None))
        for field, value in ast.iter_fields(n):
            if field in ("annotation", "returns"):
                continue
            if isinstance(value, ast.AST):
                todo.append(value)
            elif isinstance(value, list):
                todo += [v for v in value if isinstance(v, ast.AST)]
    return out


def _class_attr(node: ast.ClassDef, attr: str) -> list[ast.stmt]:
    """The class-level statements that bind `attr` (an enum member, a class
    constant)."""
    out = []
    for s in node.body:
        if isinstance(s, ast.Assign):
            names = {t.id for tg in s.targets for t in ast.walk(tg) if isinstance(t, ast.Name)}
        elif isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name):
            names = {s.target.id}
        else:
            continue
        if attr in names:
            out.append(s)
    return out


def deps_of(ref: str, base: Path, mapped: set[str]) -> dict[str, str] | None:
    """`path::NAME` -> AST dump of every definition the mapped function uses
    (see above), or None when the function is not found."""
    pkg = "homeassistant"
    if ref.startswith(PROBATIO_PREFIX):
        ref, base, pkg = ref.removeprefix(PROBATIO_PREFIX), probatio_dir(), "probatio"
    path, _, qual = ref.partition("::")
    file = base / path
    if not file.exists():
        return None
    node = find_node(ast.parse(file.read_text()), qual)
    if node is None:
        return None
    prefix = PROBATIO_PREFIX if pkg == "probatio" else ""
    found: dict[str, str] = {}
    seen: set[tuple[Path, str, str | None]] = set()
    work: list[tuple[Path, ast.AST]] = [(file, node)]
    while work:
        f, n = work.pop()
        defs = _defs(f, base, pkg)
        for name, attr in _refs(n):
            # follow imports to the defining module
            target, tfile = _resolve(defs.get(name), f, base, pkg)
            tattr = attr
            if isinstance(target, tuple) and target[0] == "module":
                if attr is None:
                    continue
                tfile = target[1]
                target, tfile = _resolve(_defs(tfile, base, pkg).get(attr), tfile, base, pkg)
                tattr = None
            if not isinstance(target, ast.AST):
                continue
            rel = tfile.relative_to(base).as_posix()
            if isinstance(target, ast.ClassDef):
                # `Cls.ATTR`: the class-level binding; a bare class (a call,
                # an isinstance check) adds nothing, its methods are mapped
                # on their own or not followed
                if tattr is None or (tfile, target.name, tattr) in seen:
                    continue
                seen.add((tfile, target.name, tattr))
                for s in _class_attr(target, tattr):
                    found[f"{prefix}{rel}::{target.name}.{tattr}"] = ast.dump(
                        s, include_attributes=False)
                    work.append((tfile, s))
                continue
            label = getattr(target, "name", None) or name
            if isinstance(target, (ast.FunctionDef, ast.AsyncFunctionDef)) and \
                    f"{prefix}{rel}::{label}" in mapped:
                continue
            key = (tfile, label, None)
            if key in seen or target is node:
                continue
            seen.add(key)
            found[f"{prefix}{rel}::{label}"] = ast.dump(
                _strip_docstrings(copy.deepcopy(target)), include_attributes=False)
            work.append((tfile, target))
    return found


def deps_hash(ref: str, base: Path, mapped: set[str]) -> str | None:
    """Hash of `deps_of`; None when the function uses nothing tracked (or is
    missing)."""
    deps = deps_of(ref, base, mapped)
    if not deps:
        return None
    blob = "\n".join(f"{k}\n{v}" for k, v in sorted(deps.items()))
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def upstream_commit() -> str:
    return subprocess.check_output(
        ["git", "-C", str(UPSTREAM.parent), "rev-parse", "HEAD"], text=True
    ).strip()


def upstream_tag() -> str | None:
    r = subprocess.run(["git", "-C", str(UPSTREAM.parent), "describe", "--tags", "--exact-match"],
                       capture_output=True, text=True)
    return r.stdout.strip() or None


def load() -> dict:
    return yaml.safe_load(MANIFEST.read_text())


def save(data: dict) -> None:
    MANIFEST.write_text(yaml.safe_dump(data, sort_keys=False, width=100, allow_unicode=True))


def mapped_refs(data: dict) -> set[str]:
    return {e["python"] for e in data["entries"]}


def entry_status(entry: dict, base: Path, mapped: set[str]) -> str | None:
    """None when the function and its dependencies are as recorded;
    otherwise "missing", "changed" or "dependencies changed"."""
    current = hash_ref(entry["python"], base)
    if current is None:
        return "missing"
    if current != entry.get("hash"):
        return "changed"
    if deps_hash(entry["python"], base, mapped) != entry.get("deps"):
        return "dependencies changed"
    return None


def cmd_check(_: argparse.Namespace) -> int:
    data = load()
    mapped = mapped_refs(data)
    stale, missing = [], []
    for entry in data["entries"]:
        st = entry_status(entry, UPSTREAM, mapped)
        if st == "missing":
            missing.append(entry)
        elif st is not None:
            stale.append((entry, st))
    head = upstream_commit()
    tag = data["upstream"].get("tag")
    print(f"manifest commit: {data['upstream']['commit'][:12]}{f' ({tag})' if tag else ''}"
          f"   upstream HEAD: {head[:12]}")
    print(f"{len(data['entries'])} entries, {len(stale)} stale, {len(missing)} missing\n")
    for e, why in stale:
        print(f"STALE   {e['python']}  ({why})\n        -> {', '.join(e['lean'])}")
    for e in missing:
        print(f"MISSING {e['python']}  (renamed or removed upstream)\n        -> {', '.join(e['lean'])}")
    if MISSING_FILES:
        print("\nModules that mapped functions import are not in the checkout, so their"
              " dependencies cannot be hashed (add them to the sparse checkout):")
        for f in sorted(MISSING_FILES):
            print(f"    homeassistant/{f}")
        return 1
    if stale or missing:
        old = data["upstream"]["commit"]
        print(f"\nSee what changed:  git -C upstream/ha-core diff {old[:12]} HEAD -- <file>")
    return 1 if stale or missing else 0


def cmd_update(args: argparse.Namespace) -> int:
    data = load()
    mapped = mapped_refs(data)
    for entry in data["entries"]:
        if args.only and entry["python"] not in args.only:
            continue
        h = hash_ref(entry["python"])
        if h is None:
            print(f"cannot find {entry['python']}", file=sys.stderr)
            return 1
        entry["hash"] = h
        if d := deps_hash(entry["python"], UPSTREAM, mapped):
            entry["deps"] = d
        else:
            entry.pop("deps", None)
    if not args.only:
        data["upstream"]["commit"] = upstream_commit()
        if tag := upstream_tag():
            data["upstream"]["tag"] = tag
        else:
            data["upstream"].pop("tag", None)
    save(data)
    print("manifest updated")
    return 0


def cmd_coverage(_: argparse.Namespace) -> int:
    data = load()
    mapped = {e["python"] for e in data["entries"]}
    files = sorted({e["python"].partition("::")[0] for e in data["entries"]
                    if not e["python"].startswith(PROBATIO_PREFIX)})
    for path in files:
        if not (UPSTREAM / path).is_file():
            print(f"{path}: not in the upstream checkout (see README, sparse checkout)")
            continue
        tree = ast.parse((UPSTREAM / path).read_text())
        names: list[str] = []
        for n in tree.body:
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
                names.append(n.name)
            elif isinstance(n, ast.ClassDef):
                names += [
                    f"{n.name}.{m.name}"
                    for m in n.body
                    if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))
                ]
        unmapped = [q for q in names if f"{path}::{q}" not in mapped]
        print(f"{path}: {len(names) - len(unmapped)}/{len(names)} mapped")
        for q in unmapped:
            print(f"    - {q}")
    return 0


def cmd_compare(args: argparse.Namespace) -> int:
    """Which mapped functions differ in another HA tree (e.g. the release the
    differential tests run against)?"""
    other = Path(args.against).resolve()
    data = load()
    mapped = mapped_refs(data)
    entries = [e for e in data["entries"] if not e["python"].startswith(PROBATIO_PREFIX)]
    differ = [(e, st) for e in entries if (st := entry_status(e, other, mapped)) is not None]
    print(f"{len(entries) - len(differ)}/{len(entries)} mapped functions identical "
          f"(with their dependencies) in {other}")
    for e, why in differ:
        print(f"DIFFERS {e['python']}  ({why})")
    for f in sorted(MISSING_FILES):
        print(f"NOT FOUND (imported by a mapped function or its dependencies) {f}")
    return 1 if differ or MISSING_FILES else 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check").set_defaults(fn=cmd_check)
    u = sub.add_parser("update")
    u.add_argument("--only", nargs="*", help="python refs to re-hash (after re-translating them)")
    u.set_defaults(fn=cmd_update)
    sub.add_parser("coverage").set_defaults(fn=cmd_coverage)
    c = sub.add_parser("compare", help="compare mapped functions with another homeassistant/ dir")
    c.add_argument("--against", required=True)
    c.set_defaults(fn=cmd_compare)
    args = p.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
