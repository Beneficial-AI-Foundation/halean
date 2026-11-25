# 07-automation: the automation engine

Area: `HALean/Automation/*.lean` (config decoding, conditions, triggers, run modes, the action executor) and the
driver `Exe/Automation.lean` (`halean-automation`), compared with Home Assistant 2026.10.4 running in-process.
Question: inside the subset README.md lists as supported (lines 229-235), does `halean-automation` give the same
`automation_triggered` sequence, service calls and fired events as HA, and does it answer `unsupported` for what is
outside the subset? The answer is in `FINDINGS.md`.

## Files

| Path | What |
|---|---|
| `FINDINGS.md` | Result: counts, divergence table, details, reading findings, harness notes, mutation checks. |
| `side-by-side.md` | Reading comparison, upstream file:line against Lean file:line. |
| `cases/*.yaml` | Hand-written scenarios in the shipped format (no `expect` blocks: HA is the oracle). One behaviour per file; the first comment line says which. |
| `gen/gen_scenarios.py` | Seeded random scenario generator (`--seed`, `--count`, `--profile default|modes`). Seeds used: 101, 202 (default, 300 each), 303 (modes, 200). |
| `gen/reduce.py` | Greedy shrinker for a diverging scenario (a helper; results were finished by hand). |
| `gen/out/<run>-s<seed>/` | The random scenarios of each run (regenerated per run; identical between runs, see `logs/gen-determinism.txt`). |
| `harness/test_differential.py` | Copy of `tests/differential/test_differential.py`. Changes are listed below. `harness/pytest.ini` is the shipped one. |
| `run.sh`, `run_all.sh` | One harness run / a full run (cases + the three random sets). |
| `show.py`, `triage.py` | Print the differing steps of dumped results / group failing cases by a rough signature. |
| `logs/` | `run1-*`, `run2-*`: the two full runs. `runN-dump/<set>/<case>.json`: both results per case. `scratch-*`: exploratory runs. |
| `patches/AUT-<n>.patch` | One patch per ID that has one (cumulative, in the order of `patches/apply_patches.py`). `patches/all-patches.*`: build log and shipped-suite logs of the patched copy; `patches/patched-*`: this experiment's cases and random sets against the patched engine. |
| `mutations/` | The mutation patches, build logs and shipped-suite logs. |

## Changes to the harness copy

Only these (see `diff tests/differential/test_differential.py review/experiments/07-automation/harness/test_differential.py`):

1. Case directory: `AUT_CASES` (colon-separated directories, default `../cases`).
2. Engine path: `HALEAN_BIN` (default `/home/user/halean/.lake/build/bin`), by setting `run_scenarios.ENGINE`.
3. Optional dump (`AUT_DUMP=<dir>`): both per-step results, the engine's other commands (`unsupported`, logs) and HA's
   warnings/errors are written as JSON. This does not change the verdict.
4. A `service_result` step whose `call_id` HA never issued: the shipped code raises `IndexError` there (HA made fewer
   calls than the scenario answers). The copy records it and still fails the test, after the comparison, with
   `IndexError in the shipped harness: HA never made call(s) [...]`. The comparison (`_streams`, `_normalise_engine`,
   the assertion) is unchanged, so pass/fail is the shipped verdict.
5. `test_harness_matches_pin` reads `manifest.yaml` from the repository root (path only).

## How to rerun

```bash
cd /home/user/halean/review/experiments/07-automation
./run_all.sh run1          # cases/ + random seeds 101, 202, 303 against the shipped binaries
./run_all.sh run2
# one set, another engine build, with dumps:
HALEAN_BIN=/tmp/claude-0/halean-copies/07-automation-p/.lake/build/bin \
  AUT_CASES=$PWD/cases AUT_DUMP=/tmp/claude-0/aut-scratch/dump ./run.sh mylabel
/opt/havenv/bin/python show.py /tmp/claude-0/aut-scratch/dump [case ...]
# random scenarios only:
/opt/havenv/bin/python gen/gen_scenarios.py --seed 101 --count 300 --out /tmp/claude-0/aut-scratch/g101
```

Patches and mutations (throwaway copies only):

```bash
cp -a /home/user/halean /tmp/claude-0/halean-copies/07-automation-p
python3 patches/apply_patches.py          # edits and commits each patch in that copy, rewrites patches/AUT-*.patch
(cd /tmp/claude-0/halean-copies/07-automation-p && lake build halean-automation halean-script)
# shipped suites in the copy: tests/run_scenarios.py, tests/run_script_scenarios.py,
# pytest tests/differential/test_differential.py and test_scripts.py  (logs: patches/all-patches.shipped.*.log)
```

A scenario passes when HA and the engine agree; a scenario listed in `FINDINGS.md` fails on purpose (it is the
reproducer). `logs/runN-failing.txt` lists the failing test ids of a run.
