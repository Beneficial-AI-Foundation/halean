# 05-service-schemas

Faithfulness review of HALean's service schemas: the probatio model (`HALean/Core/Probatio.lean`), the `cv.*`
validators (`HALean/Core/ConfigValidation.lean`), the spec decoder and evaluator (`HALean/Core/Schema.lean`,
`ServicesJson.lean`, `PyJson.lean`) and the helpers they call (`Automation/Slugify.lean`, `Automation/TimePeriod.lean`,
`Template/PyInt.lean`, `Template/CvBoolean.lean`, `Template/Value.lean`).
Reference: probatio 0.13.0 and Home Assistant 2026.10.4 in `/opt/havenv`. Reviewed commit `f638a377`.

The result is in `FINDINGS.md`. The reading comparison is in `side-by-side.md`.

## Rerun

```
cd /home/user/halean/review/experiments/05-service-schemas
./run_all.sh 1 101 102 103      # run number, seed A, seed B, seed of the long cases
./run_all.sh 2 101 102 103      # the same seeds again: every divergence must come back
./run_all.sh 3 201 202 203      # other seeds
```

One run takes about 4 minutes. It writes, for run `N`:

| log | what |
|---|---|
| `logs/runN-hand.log`, `.jsonl` | `cases/*.yaml` in record mode |
| `logs/runN-hand-strict.log` | `cases/*.yaml` with the shipped assertions unchanged (no record mode) |
| `logs/runN-crash-sch1.log`, `-sch1b.log` | `cases_crash/sch1/`, `cases_crash/sch1b/` (the engine process dies) |
| `logs/runN-gen.log` | the generator's seeds and counts |
| `logs/runN-random-a.log`, `-b.log`, `-warm.log`, `.jsonl` | the random cases (`gen/out/runN/...`) |
| `logs/runN-classify.log` | every recorded operation sorted by root cause; `UNCLASSIFIED` must not appear |
| `logs/runN-summary.log` | the last line of each pytest run and the classification |

Fast tools (no hass instance, real probatio called directly; used to search, not for the verdict):

```
cd gen
/opt/havenv/bin/python fuzz.py --seed 1 --schemas 600 --data 10      # gen_random cases, probatio vs engine
/opt/havenv/bin/python fuzz_numeric.py 1     # time periods, float repr, Coerce on random numbers
/opt/havenv/bin/python fuzz_text.py 1        # random ASCII text on every text-reading validator
/opt/havenv/bin/python fuzz_messages.py 1    # In "did you mean", unknown keys, error paths
/opt/havenv/bin/python fuzz_codegen.py 11 2500   # Python only: interpreted probatio vs its generated code
/opt/havenv/bin/python explore.py ../cases/numbers.yaml   # one case file
```

Their logs are `logs/fuzz-*.log` (`fuzz-numeric-seed1`, `fuzz-text-seed1`, `fuzz-messages-seed1`,
`fuzz-random-seed2`, `fuzz-random-seed3`, `fuzz-codegen-seed11`, `fuzz-codegen-seed12`).

Other logs: `logs/case-counts.log` (cases and data points per file), `logs/sch1-explore.log` (HA's answers for the
two crash cases), `logs/sch1-timing.log` (`gen/sch1_timing.py`), `logs/sch1-raw-json.log` (the engine fed a JSON
number with a 10-digit exponent), `logs/icon-check.log` (`gen/icon_check.py`).

`logs/runN-classify.log` and the classification part of `logs/runN-summary.log` were written again after the runs
with the final `gen/classify.py` (the first version sorted two SCH-2 records of run 3 as unclassified; the `.jsonl`
records themselves are untouched). Regenerate them with
`python gen/classify.py logs/runN-hand.jsonl logs/runN-crash-sch1.jsonl logs/runN-crash-sch1b.jsonl logs/runN-random-a.jsonl logs/runN-random-b.jsonl logs/runN-random-warm.jsonl`;
`logs/runN-classify-random.log` is the same over the three random files only.

Patched engine (`patches/`): the three patches were applied together in a copy of the repository
(`/tmp/claude-0/halean-copies/05-service-schemas-1`, deleted afterwards), built there, and tested there:

```
cp -a /home/user/halean /tmp/claude-0/halean-copies/05-service-schemas-1 && cd /tmp/claude-0/halean-copies/05-service-schemas-1
git apply /home/user/halean/review/experiments/05-service-schemas/patches/all-patches.patch
export PATH=$HOME/.elan/bin:$PATH
lake build halean-automation halean-template halean-sun-grid halean-core-states halean-core-services halean-core-events halean-core halean-script halean-helpers
lake build HALean                      # the library with its proofs
/opt/havenv/bin/python -m pytest tests/differential -p no:cacheprovider -q
/opt/havenv/bin/python tests/run_scenarios.py; /opt/havenv/bin/python tests/run_script_scenarios.py
/home/user/halean/review/experiments/05-service-schemas/patches/test_patches.sh "$PWD"   # the reproducers on the patched engine
```

Logs in `patches/`: `build-all-patches.log` (first build of three executables), `build-all-exes-all-patches.log`,
`build-library-all-patches.log` (failed: theorem `pyIter_error`), `-2.log` (failed: the restated theorem needed a
witness), `-3.log` (passes), `shipped-tests-all-patches.log` (services, core, helpers: 128 passed),
`shipped-differential-all-patches.log` (all of `tests/differential`: 611 passed, 6 skipped),
`shipped-scenarios-all-patches.log`, `shipped-script-scenarios-all-patches.log`, `patched-*.log` / `.jsonl`
(the hand-written and crash cases on the patched engine), `patched-classify.log`.

## Files

* `cases/numbers.yaml`, `structure.yaml`, `cv.yaml`: hand-written cases that agree with HA.
* `cases/documented_refusals.yaml`: operations HALean refuses and the README lists (`unsupported: true`, the shipped marker).
* `cases/divergences.yaml`: one or more reproducers per divergence, plus `hw_sch3_control`.
* `cases_crash/sch1/`, `cases_crash/sch1b/`: reproducers that kill the engine process. They are separate
  directories because the shipped harness shares one engine process between all cases of a run.
* `gen/gen_random.py`: the seeded generator (random schema specs from the supported subset, random data from an
  edge-case pool, half of them aimed at the schema). `gen/out/runN/`: what it wrote for run `N`.
* `gen/classify.py`: sorts the recorded operations by root cause.
* `gen/number_anchors.py`: numbers the YAML anchors of a hand-written file (PyYAML refuses duplicate anchors).
* `gen/explore.py`, `fuzz*.py`, `sch1_timing.py`, `icon_check.py`: the fast tools.
* `harness/test_services.py`, `schema_spec.py`, `pytest.ini`: the harness copy.
* `patches/SCH-1.patch`, `SCH-4.patch`, `SCH-6.patch`, `all-patches.patch` and their build and test logs.
* `run_all.sh`: one full run.

## Changes to the harness copy

`harness/schema_spec.py` and `pytest.ini` are unchanged copies. `harness/test_services.py` differs from
`tests/differential/test_services.py` in three places (`diff` them to see):

1. The case directory is `cases/` of this experiment, or `SCH_CASES`.
2. The engine directory is `HALEAN_BIN` (default `/home/user/halean/.lake/build/bin`).
3. Record mode, only when `SCH_RECORD=<file>` is set: an operation whose two answers differ, or that HALean answers
   with `unsupported` without the `unsupported: true` marker, is appended to the file with both answers and the case
   goes on with the next operation. At the end the case fails if any operation was recorded. The comparison itself
   (`lean == ha` on result, exception, events and logs) is the shipped one, and the verdict per case is the shipped
   verdict: a case fails exactly when the shipped assertions would have failed at some operation.
   Without `SCH_RECORD` the file behaves as shipped (`logs/runN-hand-strict.log`).

A YAML note: PyYAML reads `1e3`, `1:30`, `on`, `off` differently from what they look like. Every string in the
hand-written cases is quoted where that matters, and floats are written with a dot (`1.0e+16`).
