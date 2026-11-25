# 08-scripts: scripts as entities

Area: `HALean/Script/*.lean` (`Config`, `Entity`, `Service`, `Protocol`) and the engine functions they
drive (`startScript`, `callLocal`, `stopRun` in `HALean/Automation/Engine.lean`), executable
`halean-script`. Reference: HA's `script` integration (`components/script/`, `helpers/script.py`).
Conventions: `review/CONVENTIONS.md`. Result: `FINDINGS.md`. Reading comparison: `side-by-side.md`.

## Rerun

```sh
cd /home/user/halean/review/experiments/08-scripts

# one full run against the unpatched build: hand-written cases, config matrix, random cases
./run_all.sh 1 101 202          # logs/run1-*.log ; ./run_all.sh 2 101 202 for the second run

# single pieces
/opt/havenv/bin/python -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=short            # cases/*.yaml
HALEAN_CASES=gen/out/seed101 /opt/havenv/bin/python -m pytest harness/test_scripts.py -p no:cacheprovider -q --tb=short
/opt/havenv/bin/python -m pytest harness/test_config_matrix.py -p no:cacheprovider -q --tb=short -s   # config/matrix.yaml
harness/show.sh h54 h85                                    # verdict and HA / HALean lines of some cases
/opt/havenv/bin/python gen/gen_scripts.py 101 300 gen/out/seed101     # regenerate the random cases of a seed
/opt/havenv/bin/python gen/triage.py logs/run1-random-seed101.log gen/out/seed101 -v   # signatures of the failures

# a patch: throwaway copy, rebuild, shipped suites, then this review's cases against the patched build
cp -a /home/user/halean /tmp/claude-0/halean-copies/08-scripts-2
COPY=/tmp/claude-0/halean-copies/08-scripts-2 patches/test_patch.sh SCR-1          # -> patches/SCR-1-tests.log
COPY=/tmp/claude-0/halean-copies/08-scripts-2 patches/test_patch.sh SCR-5 SCR-4    # SCR-5 needs SCR-4 first
```

`HALEAN_BIN` selects the directory with `halean-script` (default `/home/user/halean/.lake/build/bin`),
`HALEAN_CASES` the case directory (default `cases/`).

## Files

| Path | What |
|---|---|
| `cases/h*.yaml` | 87 hand-written scenarios in the shipped format (`tests/run_script_scenarios.py`), one behaviour each. No `expect:` keys: the differential harness compares HA with HALean. |
| `config/matrix.yaml` | 110 single-script configs for the load-time comparison. `expect:` is the verdict this review found with the unpatched build (absent = `agree`). |
| `gen/gen_scripts.py` | Seeded random generator (`<seed> <count> <outdir>`). Seeds used: 101 and 202, 300 scenarios each. |
| `gen/out/seed101/`, `gen/out/seed202/` | The generated scenarios (kept, so the runs can be repeated without the generator). |
| `gen/triage.py` | Reads a pytest log of the harness copy; per failed case the first differing step and a signature. |
| `gen/minimise.py` | Greedy one-deletion minimiser for a failing scenario (helper; reproducers in `cases/` were then rewritten by hand). |
| `harness/test_scripts.py`, `harness/run_script_scenarios.py`, `harness/pytest.ini` | The harness copy. Changes: the case directory (`HALEAN_CASES`), the engine directory (`HALEAN_BIN`), and where `bridge/protocol.py` and the copied runner are imported from. Comparison logic unchanged (`diff` against `tests/differential/test_scripts.py` and `tests/run_script_scenarios.py` shows only those lines). |
| `harness/test_config_matrix.py` | New, not a copy: loads each matrix entry alone into HA and into `halean-script` and compares "loaded / not loaded" and the first state. The shipped harness cannot do this (it asserts that HALean rejects nothing). |
| `harness/show.sh` | Runs named cases and prints the verdict with the HA / HALean lines. |
| `run_all.sh` | One full run; writes `logs/run<n>-*.log`. |
| `logs/run1-*`, `logs/run2-*` | The two full runs: `-hand.log`, `-matrix.log`, `-random-seed<seed>.log` (pytest output with both sides for every differing step), `-random-seed<seed>-triage.txt`. |
| `logs/perf-recursion.log`, `perf/*.yaml` | Timing of an exponential self-recursion (see `side-by-side.md`, section 9). |
| `patches/SCR-<n>.patch` | Patches against the reviewed commit. `patches/SCR-<n>-tests.log`: rebuild, shipped suites and this review's cases with that patch alone (SCR-5 on top of SCR-4). `patches/all-patches-lake-build.log`: `lake build` of the whole library with all five patches. `patches/test_patch.sh`: the script that made the logs. |
| `side-by-side.md` | Upstream function, Lean definition, difference, for every manifest entry of the area. |
| `FINDINGS.md` | The result. |

## Notes

* A pytest "error" (not "failed") in the logs is a teardown error of the HA test plugin: a script that was
  started with `turn_on` ended with an exception nobody awaited ("Task exception was never retrieved").
  The comparison of that case ran and passed or failed on its own; the counts in `FINDINGS.md` use
  "failed" only.
* Throwaway copies used: `/tmp/claude-0/halean-copies/08-scripts-1` (all patches, committed one by one)
  and `08-scripts-2` (one patch at a time for the test logs).
* While reproducing a generator hang at about 16:22-16:24 (machine clock) I ran `pkill -f halean-script`
  twice. That pattern is not limited to my own processes: a `halean-script` process of another reviewer
  that was running at that moment was killed with it. The generator's watchdog now only kills its own
  child (`pkill -P <pid>`).
