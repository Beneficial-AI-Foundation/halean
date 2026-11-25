#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["pyyaml", "probatio==0.13.0"]
# ///
"""Check that tools/drift.py sees changes to what a mapped function uses,
not only to the function itself (review item D1).

The review changed `MAX_LENGTH_STATE_STATE` (const.py) from 255 to 100 and
removed the `_` rules from the entity-id regex (core.py `_OBJECT_ID`) in a
copy of upstream; `drift.py compare` then reported every mapped function
identical. This script copies the upstream files the manifest's entries and
their dependencies live in, makes each change in turn and requires the
entries that read the changed definition to differ, as "dependencies
changed" (their own syntax trees are untouched).

Needs the upstream checkout (README, "What is translated").

  uv run tests/drift_deps.py
"""

from __future__ import annotations

import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("drift", ROOT / "tools" / "drift.py")
drift = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drift)

CHANGES = [
    # (file, old text, new text, entries that must differ)
    ("const.py", "MAX_LENGTH_STATE_STATE: Final = 255", "MAX_LENGTH_STATE_STATE: Final = 100",
     {"core.py::validate_state", "core.py::StateMachine.async_set_internal"}),
    ("core.py", '_OBJECT_ID = r"(?!_)[\\da-z_]+(?<!_)"', '_OBJECT_ID = r"[\\da-z_]+"',
     {"core.py::valid_entity_id", "core.py::valid_domain"}),
]


def tracked_files(data: dict, mapped: set[str]) -> set[str]:
    """Every upstream file the entries and the dependency search read (the
    modules imports pass through included)."""
    drift._MODULES.clear()
    files = set()
    for e in data["entries"]:
        ref = e["python"]
        if ref.startswith(drift.PROBATIO_PREFIX):
            continue
        files.add(ref.partition("::")[0])
        drift.deps_of(ref, drift.UPSTREAM, mapped)
    up = drift.UPSTREAM.resolve()
    files |= {p.resolve().relative_to(up).as_posix() for p in drift._MODULES
              if p.resolve().is_relative_to(up)}
    # packages, so relative imports resolve the same way
    for f in list(files):
        for parent in Path(f).parents:
            init = parent / "__init__.py"
            if (drift.UPSTREAM / init).is_file():
                files.add(init.as_posix())
    return files


def differing(data: dict, mapped: set[str], base: Path) -> dict[str, str]:
    drift._MODULES.clear()
    entries = [e for e in data["entries"] if not e["python"].startswith(drift.PROBATIO_PREFIX)]
    return {e["python"]: st for e in entries
            if (st := drift.entry_status(e, base, mapped)) is not None}


def main() -> int:
    data = drift.load()
    mapped = drift.mapped_refs(data)
    files = tracked_files(data, mapped)
    failures = 0
    for file, old, new, expect in CHANGES:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / "homeassistant"
            for f in files:
                (base / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(drift.UPSTREAM / f, base / f)
            same = differing(data, mapped, base)
            assert same == {}, f"the unchanged copy should match: {same}"
            text = (base / file).read_text()
            assert old in text, f"{file} no longer has {old!r}; update this test"
            (base / file).write_text(text.replace(old, new, 1))
            got = differing(data, mapped, base)
            missed = {r for r in expect if got.get(r) != "dependencies changed"}
            print(f"{file}: {old!r} -> {new!r}: {len(got)} entries differ")
            for r in sorted(got):
                print(f"    {r}  ({got[r]})")
            if missed:
                failures += 1
                print(f"  FAIL: not reported as dependencies changed: {sorted(missed)}")
    print("ok" if not failures else f"{failures} change(s) not detected")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
