# 09-helpers: helper entities

Area: `HALean/Helpers/*.lean` (`input_boolean`, `input_number`, `input_select`, `input_text` with the
regex subset of `Pattern.lean`, `counter`, `timer`), driver `Exe/Helpers.lean` (`halean-helpers`),
shipped harness `tests/differential/test_helpers.py`, shipped cases `tests/helpers/*.yaml`.

Question: for what README lines 518-575 list as supported, does `halean-helpers` give the same config
errors, call errors, `state_changed` and `timer.*` events, warnings and states as Home Assistant
2026.10.4 after every step? Result: `FINDINGS.md`.

## Files

| file | what it is |
|---|---|
| `FINDINGS.md` | the result (counts, divergence table, details, reading findings, harness notes) |
| `side-by-side.md` | upstream function / Lean definition / difference, for every `manifest.yaml` entry mapped to `HALean.Helpers.*` |
| `harness/test_helpers.py` | copy of the shipped harness. Two changes only: the case directory (env `HELPERS_CASES`, default `cases/`) and the engine directory (env `HALEAN_BIN`, default `/home/user/halean/.lake/build/bin`). Comparison logic unchanged. `harness/pytest.ini` is the shipped one. |
| `cases/*.yaml` | hand-written cases in the shipped format (names `hw_*`). A step with `unsupported: true` is a refusal the README documents. |
| `cases/divergent.tsv` | hand-written case → ID of the root cause it reproduces (read by `gen/classify.py`) |
| `gen/gen_random.py` | seeded random generator (configs, restore caches, call/tick sequences per helper; several domains together; random regexes of the documented subset × random strings). Seeds used: 101 and 202. |
| `gen/seed-101/`, `gen/seed-202/` | the generated cases of the runs (their sha256 sums are in `logs/run*-gen-seed*.txt`) |
| `gen/triage.py` | prints, for a pytest log, the failed step with HA's and HALean's result |
| `gen/classify.py` | one line per failed case with the root cause (rules in its docstring) and a total |
| `gen/stub/halean-helpers` | proxy engine: forwards to the real engine and replaces a refusal by an empty answer, so the harness prints what HA does where HALean refuses. Used only for `logs/ha-only-refused.log` and `logs/ha-only-documented-refusals.log`. |
| `gen/nomark/` | copy of `cases/` without the `unsupported: true` marks (made by a one-line script; used with the proxy for `logs/ha-only-documented-refusals.log`) |
| `gen/artefacts/*.yaml` | two cases that are harness artefacts, not HALean divergences (see `FINDINGS.md`, last two sections), with their logs `logs/artefact-*.log` |
| `run_all.sh` | one full run (hand-written + one random seed) |
| `logs/` | `run<N>-handwritten.log`, `run<N>-random-seed<S>.log` (pytest output), `*.classified.txt` (from `gen/classify.py`), `*.triage.txt` (from `gen/triage.py`), `run<N>-gen-seed<S>.txt` (generator output and sha256 of the generated files), `ha-only-refused.log`, `ha-only-documented-refusals.log`, `artefact-run<N>.log`, `shipped-cases-through-copy.log` |
| `patches/HLP-<n>.patch` | patch for one root cause (`git diff` of the throwaway copy) |
| `patches/HLP-<n>.build.log`, `.repro.log`, `.shipped.log` | rebuild of `halean-helpers` in the copy, the reproducers with the patched engine, the shipped `tests/differential/test_helpers.py` run in the copy |
| `patches/ALL.*` | all patches together: build, all hand-written cases, shipped test, random seed 202 |
| `patches/test_patch.sh`, `patches/rebuild_all.sh` | how the patch logs were made |

## Rerun

```sh
cd /home/user/halean/review/experiments/09-helpers

# one full run: hand-written cases + random cases of a seed (about 2 minutes)
./run_all.sh 1 101      # logs/run1-*
./run_all.sh 2 101      # same inputs again (sha256 in logs/run2-gen-seed101.txt equal to run 1)
./run_all.sh 3 202      # new random cases

# by hand
/opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q            # cases/
HELPERS_CASES=gen/seed-202 /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q
python3 gen/triage.py logs/run1-handwritten.log 800       # HA / HALean per failed case
python3 gen/classify.py logs/run1-handwritten.log         # root cause per failed case

# the shipped cases through the harness copy (must pass: the copy compares as the shipped file)
HELPERS_CASES=/home/user/halean/tests/helpers /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q

# HA's result where halean-helpers refuses
HALEAN_BIN=$PWD/gen/stub /opt/havenv/bin/python -m pytest harness/test_helpers.py -p no:cacheprovider -q -k "<case>"

# patches (throwaway copy; never in /home/user/halean)
cp -a /home/user/halean /tmp/claude-0/halean-copies/09-helpers-1
patches/rebuild_all.sh /tmp/claude-0/halean-copies/09-helpers-1
```

The generator avoids, by default, the inputs of the root causes that have a hand-written reproducer
(list in its docstring), so a random run shows what is new. `--include-known` turns that off.

## Conventions used in the logs

A failed pytest case is a divergent case. The assertion message has the step, HA's result (`HA:`) and
`halean-helpers`' result (`HALean:`), or `HALean rejected it: <reason>` for a refusal. The verdict is
the shipped assertion.
