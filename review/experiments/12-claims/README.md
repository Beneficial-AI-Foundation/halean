# 12-claims: audit of the claims in the repository `README.md`

Reviewed commit f638a37. Result: `CLAIMS-README.md` (count table, one row per claim, details for every claim that is not `correct`).

Nothing in the repository was modified. Throwaway copies were made under `/tmp/claude-0/halean-copies/12-claims-*` and removed.
No `lake build` was run; all probes use the shipped binaries in `/home/user/halean/.lake/build/bin`.

## Rerun

```bash
review/experiments/12-claims/probes/rerun_all.sh      # every probe, rewrites logs/ and CLAIMS-README.md, about 3 minutes
/opt/havenv/bin/python -B review/experiments/12-claims/probes/build_claims.py   # only rebuild CLAIMS-README.md
```

The claim rows, verdicts and the "Not correct" texts live in `probes/build_claims.py`; `CLAIMS-README.md` is generated from it.

## Files

| File | What it does | Log |
|---|---|---|
| `probes/build_claims.py` | the claim list; writes `CLAIMS-README.md` | |
| `probes/rerun_all.sh` | runs everything below | |
| `probes/test_probe_templates.py` (+ `pytest.ini`) | 39 templates on real HA (`Template.async_render`) and on `halean-template`; each row states what the README says should happen | `logs/probe-templates.jsonl`, `logs/probe-templates.summary` |
| `probes/probe_automation_load.py` | 42 automation configs sent to `halean-automation` in one `init`; which are `unsupported` | `logs/probe-automation-load.log` |
| `probes/probe_script_load.py` | 13 script configs sent to `halean-script`; two `turn_on` calls | `logs/probe-script-load.log` |
| `probes/core_probes.py` | 29 groups of JSON lines for `halean-core-states`, `-services`, `-events`, `halean-core`, `halean-helpers` | `logs/core-probes.log` |
| `probes/float_probe.sh` | how `halean-core-states` reads JSON floats in exponent notation | `logs/float-probe.log` |
| `probes/core_event_limit.sh` | the 10,000-events limit in `halean-core` | `logs/core-event-limit.log` |
| `probes/ha_direct.py` | values from real HA, probatio and CPython (no running `hass`) | `logs/ha-direct.log` |
| `probes/test_probe_ha_misc.py` | real HA: `repeat` limit; `max_exceeded` accepted | `logs/probe-ha-misc.log` |
| `probes/harness/test_differential.py` | copy of the shipped `tests/differential/test_differential.py`. Three lines changed: the import path of `run_scenarios`, the scenario directory (`probes/scenarios/`), the manifest path. Comparison logic unchanged | `logs/harness-own-scenarios-run1.log`, `run2` |
| `probes/scenarios/kept_behaviours.yaml`, `supported_sample.yaml` | new scenarios in the shipped format, run through real HA and the engine | same |
| `probes/scenarios-engine-only/repeat_limit.yaml`, `known_gaps.yaml` | scenarios run on the engine only (`engine_scenario.py`). `repeat_limit` cannot be observed by the shipped harness: `logs/harness-repeat-limit-not-observable.log` is the failing run with that file placed in `scenarios/` | `logs/engine-*.log` |
| `probes/engine_scenario.py` | prints the engine's commands per step of a scenario | `logs/engine-*.log` |
| `probes/sparse_check.sh` | copies exactly the paths of the README sparse-checkout command and runs `drift.py compare` against the copy | `logs/sparse-check.log` |
| `probes/sparse_history.py` | the same question for earlier commits | `logs/sparse-history.log` |
| `probes/drift_hash_probe.py` | does the drift hash ignore comments, docstrings, blank lines; does it see a code change | `logs/drift-hash-probe.log` |
| `probes/drift_constant_probe.sh` | does `drift.py` see a changed module-level constant | `logs/drift-constant-probe.log` |
| `probes/names_check.py` | every Lean name and file the README cites: exists, and in the file the README names | `logs/names-check.log` |
| `probes/manifest_counts.py`, `manifest_node_kinds.py` | counts behind the README numbers | `logs/manifest-counts.log`, `logs/manifest-node-kinds.log` |
| `probes/demo_automations_load.py` | the seven demo automations load | `logs/demo-automations-load.log` |
| `probes/structure_checks.sh`, `small_checks.sh` | small greps and counts cited in the table | `logs/structure-checks.log`, `logs/small-checks.log` |
| (shipped) `tools/drift.py check` | run on the reviewed tree | `logs/drift-check.log` |
| (shipped) `tests/differential`, run with `-v` | names of all cases with PASSED/SKIPPED | `logs/differential-verbose.log` |

## Limits

* Not run: Docker (`demo/`, `tests/live/`); the two shipped live runs are in `02-shipped-tests/logs/`.
* Not fetched: the GitHub release page, PyPI. Three claims are marked `not checked` for that reason.
* Theorem names: existence and file only. Their content is audited in `10-theorems`.
* The mutation claims at README lines 115-116 and 410-413 are out of scope.
* For table cells that list many features, the row says how many were checked.
* Probes are deterministic. The template probe and the two new scenarios were each run twice with the same result.
