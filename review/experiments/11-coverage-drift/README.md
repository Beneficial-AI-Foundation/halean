# 11-coverage-drift

Rerun, from the repository root (after `lake build HALean` and after `review/experiments/10-theorems` is filled):

```bash
python3 review/experiments/11-coverage-drift/coverage.py > review/experiments/11-coverage-drift/logs/coverage.txt
review/experiments/11-coverage-drift/drift_blindspots.sh          # logs/drift-blindspots.log, patches/M*.patch
/opt/havenv/bin/python review/experiments/11-coverage-drift/untracked_deps.py > review/experiments/11-coverage-drift/logs/untracked-deps.log
lake env lean review/experiments/11-coverage-drift/ManifestNames.lean > review/experiments/11-coverage-drift/logs/manifest-names.log
```

* `coverage.py`: code lines (no blank lines, no comments), theorems, `partial` definitions per area, theorem classes
  (from `review/experiments/10-theorems/class/*.tsv`), and the share of implementation definitions that class-C/O
  theorems cover. Definitions are in its docstring.
* `drift_blindspots.sh`: copies `tools/`, `manifest.yaml` and `upstream/` to a throwaway directory, applies one edit
  to the upstream copy at a time, runs `tools/drift.py check`, records exit code and STALE lines, reverts.
  M01 and M02 are controls (a mapped function body; a comment).
* `untracked_deps.py`: for every mapped HA function, the names its body reads that drift.py does not hash
  (unmapped functions of the same file, unmapped methods of its class, module-level assignments, names imported
  from `const`).
* `ManifestNames.lean`: checks that each Lean name listed in `manifest.yaml` is a declaration of the built library.
* `logs/drift-check-pristine.log`, `logs/drift-coverage.log`, `logs/drift-compare-installed.log`: `drift.py check`,
  `coverage` and `compare --against <installed homeassistant>` on the unmodified tree.
