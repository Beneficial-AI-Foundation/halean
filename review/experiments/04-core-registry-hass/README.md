# 04 — service registry and joined core

Area: `HALean/Core/ServiceRegistry.lean` (driver `Exe/CoreServices.lean`, shipped harness
`tests/differential/test_services.py`) and `HALean/Core/Hass.lean` (driver `Exe/Core.lean`, shipped harness
`tests/differential/test_core.py`). Question: is the Lean translation faithful to `homeassistant/core.py`
(`ServiceRegistry`, `ServiceCall`, `async_run_hass_job`, `async_create_task`, `async_block_till_done`, the wiring of
bus, state machine and registry) and to asyncio's scheduling as far as the model claims, at HA 2026.10.4?

Result: `FINDINGS.md`. Reading comparison: `side-by-side.md`.

## Rerun

```
cd /home/user/halean/review/experiments/04-core-registry-hass
./run_all.sh 1        # generates the random cases, runs everything, writes logs/run1-*.log
./run_all.sh 2        # second run (regenerates from the same seeds), logs/run2-*.log
```

`run_all.sh <n>` does, in order:

1. `gen/gen_core.py --seed 101` and `--seed 202` (400 cases each) into `gen/out-run<n>/core/`,
   `gen/gen_services.py --seed 11` and `--seed 22` (400 cases each) into `gen/out-run<n>/services/`.
2. `pytest harness/test_services.py` on `cases/services/` → `logs/run<n>-hand-services.log`.
3. `pytest harness/test_core.py` on `cases/hass/` → `logs/run<n>-hand-core.log`.
4. the same two harness files with `HALEAN_CASES=gen/out-run<n>/services` and `.../core`
   → `logs/run<n>-random-services.log`, `logs/run<n>-random-core.log`.
5. `pytest harness/test_core_ha_only.py -s` on `cases/refused/` → `logs/run<n>-ha-only-refused.log`.

Single commands:

```
/opt/havenv/bin/python -m pytest harness/test_core.py -p no:cacheprovider -q --timeout 120
HALEAN_CASES=gen/out-run1/core /opt/havenv/bin/python -m pytest harness/test_core.py -p no:cacheprovider -q
HALEAN_BIN=/tmp/claude-0/halean-copies/<copy>/.lake/build/bin /opt/havenv/bin/python -m pytest harness/test_services.py -p no:cacheprovider -q -k brace
```

## Files

| path | what |
|---|---|
| `harness/test_services.py`, `harness/test_core.py` | Copies of the shipped harness files. Changes: (a) the case directory (`cases/services`, `cases/hass`; `HALEAN_CASES` overrides it), (b) the engine path (`HALEAN_BIN`, default `/home/user/halean/.lake/build/bin`), and `ROOT` is the fixed repository path (the copy lives elsewhere; `test_services.py` reads `manifest.yaml` from it). The comparison logic is unchanged (`diff` against `tests/differential/` shows only these lines). |
| `harness/schema_spec.py`, `harness/pytest.ini` | unchanged copies |
| `harness/test_core_ha_only.py` | Review addition. Runs `cases/refused/*.yaml` on HA only (with the shipped `Runner`), asks the engine too, prints both. It asserts nothing. Used to get HA's answer for operations HALean answers `unsupported` (the shipped harness skips HA for those). |
| `cases/services/registry_review.yaml` | 42 hand-written registry cases |
| `cases/hass/*.yaml` | 63 hand-written joined-core cases (`nested_calls`, `registry_midcall`, `tasks`, `refusals`, `depth_chain`) |
| `cases/refused/refused.yaml` | 8 cases for the HA-only runner |
| `gen/gen_core.py`, `gen/gen_services.py` | seeded random generators (docstrings explain the design). Seeds: core 101, 202; services 11, 22. |
| `gen/coverage.py` | replays generated core cases on the engine alone and counts trace entries by kind (`logs/run1-random-core-coverage.log`) |
| `gen/out-run1/`, `gen/out-run2/` | the generated case files and their `*.summary.json` (counts, and how many operations the engine refused, per reason) |
| `logs/` | every run log |
| `patches/REG-1.patch`, `REG-2.patch`, `REG-3.patch`, `HASS-1.patch` + `*.test.log` | patches tested in a throwaway copy (`/tmp/claude-0/halean-copies/04-core-registry-hass-1`, deleted afterwards), with the shipped suites `test_services.py`, `test_core.py`, `test_events.py`, `test_states.py` and the reproducers. `patches/HASS-1-cases/depth.yaml`: the refused call chains without `unsupported: true`, used for the HASS-1 patch. |
| `mutations/M1..M3-*.patch` + `*.test_core.log`, `M0-unmutated-baseline.test_core.log` | the three README scheduler claims |
| `side-by-side.md` | reading comparison |
| `FINDINGS.md` | result |

## Notes on the generators

Both generators run each candidate case through the engine before writing it (pre-screen). An operation the
engine answers `unsupported` gets `unsupported: true`, which makes the shipped harness skip it on HA as well. For
the core, a case is also cut where the model's `block_till_done` cannot return (HA would hang there). The reasons
are counted in `gen/out-run<n>/*/*.summary.json`. The pre-screen takes nothing else from the engine. It means a
generated file depends on the engine binary as well as on the seed; `run_all.sh` regenerates on every run and
`logs/run2-gen-diff.log` records that run 2 produced the same files as run 1.

To reproduce a patch or mutation: `cp -a /home/user/halean /tmp/claude-0/halean-copies/<name>`, `git apply <patch>` there,
`lake build halean-core halean-core-services`, then
`/opt/havenv/bin/python -m pytest tests/differential/test_core.py -p no:cacheprovider -q` in the copy (mutations), or the four
shipped suites plus `HALEAN_BIN=<copy>/.lake/build/bin pytest harness/... -k <reproducer>` (patches).

`gen_core.py` keeps cases finite by ranking event types and services: a script only fires events and calls
services of a higher rank than the one it is attached to. An engine answer that takes longer than 20 s drops the
candidate (saved in `random_core_<seed>.engine_timeout.yaml` if it happens; it did not happen in the two runs).
