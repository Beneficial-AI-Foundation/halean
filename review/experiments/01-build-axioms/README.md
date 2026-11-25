# 01-build-axioms

Rerun, from the repository root:

```bash
review/experiments/01-build-axioms/build.sh                                   # needs root (cgroup v1); logs/build-*.log, logs/memcap.txt
lake env lean review/experiments/01-build-axioms/AxiomAudit.lean              # logs/axioms.tsv, logs/axioms-summary.txt
review/experiments/01-build-axioms/grep_audit.sh > review/experiments/01-build-axioms/logs/grep-audit.txt
```

* `build.sh`: puts itself in a cgroup-v1 memory group limited to 16 GiB, then runs `lake build HALean` and
  `lake build` of the nine executables. `logs/memcap.txt` records the limit, the peak usage and the limit-hit count.
* `AxiomAudit.lean`: walks every theorem of every `HALean.*` module in the compiled environment (source-written and
  compiler-generated), computes its axioms (memoised walk over all constants it uses), and tabulates them.
  `logs/axioms.tsv`: `module, theorem, source|generated, axioms`. `source` = has a declaration range and a
  non-internal name. This count (1,964) includes 21 Prop-valued structure fields and instance lemmas; the theorems
  written with the `theorem` keyword are 1,943 (`review/experiments/10-theorems/logs/inventory-summary.txt`).
* `grep_audit.sh`: text search for `sorry`, `admit`, `native_decide`, `axiom`, `implemented_by`, `extern`, `unsafe`,
  `opaque`, and `partial def` counts per file.
* `logs/toolchain.txt`: the Lean and Lake versions used. The toolchain was taken from the GitHub release
  `lean-4.36.0-linux.tar.zst` and linked with `elan toolchain link` (releases.lean-lang.org is not reachable here).
