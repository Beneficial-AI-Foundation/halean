# 12-claims, part 2: the `translated` entries of `manifest.yaml`

Reviewed commit f638a37. Result: `CLAIMS-MANIFEST-TRANSLATED.md` (count table, one row per entry for all 349 `translated`
entries, details for every entry that is not `correct`, structure facts). The 53 `proven` entries are not covered here.

Nothing outside `review/experiments/12-claims/` was modified. No `lake build` was run and no copy of the repository was made;
all probes use the shipped binaries in `/home/user/halean/.lake/build/bin` and the Python of `/opt/havenv`.

## Rerun

```bash
review/experiments/12-claims/probes-manifest/rerun_manifest.sh     # everything, about 20 s; rewrites logs-manifest/ and the .md
/opt/havenv/bin/python -B review/experiments/12-claims/probes-manifest/build_manifest_claims.py   # only rebuild the .md
```

`rerun_manifest.sh` runs every probe twice, keeps the first set of logs in `logs-manifest/run1/`, compares the two sets
(`logs-manifest/two-runs.log`) and rebuilds the document. Verdicts, reasons and the "Not correct" texts live in
`probes-manifest/verdicts.py`; the counts in the document are computed by `build_manifest_claims.py` from the table rows.

## Files

| File (`probes-manifest/`) | What it does | Log (`logs-manifest/`) |
|---|---|---|
| `structure.py` | for each `translated` entry: resolves the upstream ref with the drift tool's `find_node` logic, looks up every `lean:` name in `10-theorems/logs/defs.tsv` and in the Lean sources, kinds, shared names | `structure.json`, `structure.tsv`, `structure-summary.log` |
| `overload_stubs.py` | all 402 refs: missing, hash equal to the manifest; which `translated` refs resolve to the first of several same-named definitions | `overload-stubs.log` |
| (shipped) `tools/drift.py check` | run on the reviewed tree | `drift-check.log` |
| `history_and_names.sh` | `git log -S` for the six missing Lean names and for note phrases; existence of the theorems, tests and definitions that notes cite; every entry that carries a missing name | `git-history.log`, `names-in-notes.log` |
| `probe_automation.py` | 37 scenarios for `halean-automation` (one `init` and further inputs each), named after the entries they check | `probe-automation.log` |
| `probe_template.py` | 46 templates for `halean-template` | `probe-template.log` |
| `probe_core.py` | 9 groups of lines for `halean-core`, `-states`, `-events`, `-services` | `probe-core.log` |
| `probe_helpers.py` | 16 groups of lines for `halean-helpers` | `probe-helpers.log` |
| `py_direct.py` | values from real HA, probatio and CPython without a running `hass` | `py-direct.log` |
| `test_probe_ha.py` (+ `pytest.ini`) | three tests on real HA with the `hass` fixture (M-17, M-8, M-65) | `probe-ha.log`, `probe-ha.pytest.log` |
| `probe_extra.sh` | the engine side of M-17 and the static-target probe of M-80 (engine and HA's schema) | `probe-m17-engine.log`, `probe-m80-static-target.log` |
| `verdicts.py` | verdict, reason and detail per non-correct entry; extra evidence per checked note | |
| `build_manifest_claims.py` | writes `../CLAIMS-MANIFEST-TRANSLATED.md` | `verdicts.json`, `verdict-counts.log` |

Logs of the first part of this experiment that are cited: `logs/core-probes.log` (groups V4, E1).

## Limits

* Read in full for this review: `HALean/Automation/{Condition,Config,Script,Engine}.lean`, `HALean/Script/{Entity,Service}.lean`, and the upstream
  functions of `helpers/condition.py`, `helpers/script.py` (`_ScriptRun`, `_QueuedScriptRun`), the homeassistant, tag, mqtt and webhook triggers.
  Other files were read at the lines the document cites. Where the evidence column says `sbs NN`, the comparison of that area reviewer
  (`review/experiments/NN-*/side-by-side.md`) is the source for the rest.
* `08-scripts` had no `FINDINGS.md` when this was written; `SCR-n` ids are quoted from its `side-by-side.md`.
* Not compared with the libraries themselves: M-50 (paho's matcher; paho is not in the venv), M-167 (vincenty at a 100 m radius).
* The probes are deterministic. Two runs gave identical logs (`logs-manifest/two-runs.log`).
