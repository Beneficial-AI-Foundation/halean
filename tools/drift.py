#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pyyaml", "probatio==0.13.0"]
# ///
"""Track which upstream Home Assistant functions the Lean engine translates.

manifest.yaml maps each Python function (``path::Qual.name``) to the Lean
definitions that translate it, with a hash of the function's AST. After you
pull upstream, ``check`` tells you exactly which translations may be stale.

  uv run tools/drift.py check      # report stale / missing entries (exit 1 if any)
  uv run tools/drift.py update     # re-hash everything and record the upstream commit
  uv run tools/drift.py update --only 'helpers/script.py::Script.async_run'
  uv run tools/drift.py coverage   # functions in tracked files that are not mapped
  uv run tools/drift.py compare --against <site-packages>/homeassistant

Entries written ``probatio:<path>::<Qual.name>`` map functions of probatio
(the validation library HA's schemas use, pinned in ``upstream.probatio``):
they are hashed against the probatio package this script runs with, which is
pinned to the same version above.

The hash ignores docstrings, comments, formatting and line numbers, so only
real code changes mark an entry stale.
"""

from __future__ import annotations

import argparse
import ast
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


def cmd_check(_: argparse.Namespace) -> int:
    data = load()
    stale, missing = [], []
    for entry in data["entries"]:
        current = hash_ref(entry["python"])
        if current is None:
            missing.append(entry)
        elif current != entry.get("hash"):
            stale.append(entry)
    head = upstream_commit()
    tag = data["upstream"].get("tag")
    print(f"manifest commit: {data['upstream']['commit'][:12]}{f' ({tag})' if tag else ''}"
          f"   upstream HEAD: {head[:12]}")
    print(f"{len(data['entries'])} entries, {len(stale)} stale, {len(missing)} missing\n")
    for e in stale:
        print(f"STALE   {e['python']}\n        -> {', '.join(e['lean'])}")
    for e in missing:
        print(f"MISSING {e['python']}  (renamed or removed upstream)\n        -> {', '.join(e['lean'])}")
    if stale or missing:
        old = data["upstream"]["commit"]
        print(f"\nSee what changed:  git -C upstream/ha-core diff {old[:12]} HEAD -- <file>")
    return 1 if stale or missing else 0


def cmd_update(args: argparse.Namespace) -> int:
    data = load()
    for entry in data["entries"]:
        if args.only and entry["python"] not in args.only:
            continue
        h = hash_ref(entry["python"])
        if h is None:
            print(f"cannot find {entry['python']}", file=sys.stderr)
            return 1
        entry["hash"] = h
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
    entries = [e for e in data["entries"] if not e["python"].startswith(PROBATIO_PREFIX)]
    data = {"entries": entries}
    differ = [e for e in entries if hash_ref(e["python"], other) != e.get("hash")]
    print(f"{len(data['entries']) - len(differ)}/{len(data['entries'])} mapped functions identical in {other}")
    for e in differ:
        print(f"DIFFERS {e['python']}" + ("  (missing)" if hash_ref(e["python"], other) is None else ""))
    return 1 if differ else 0


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
