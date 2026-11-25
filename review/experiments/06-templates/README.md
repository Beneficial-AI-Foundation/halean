# 06-templates: the template engine (`HALean/Template/`, driver `Exe/Template.lean`)

Independent faithfulness review of HALean's Jinja evaluator against Home Assistant 2026.10.4 (Jinja2 3.1.6,
CPython 3.14). Question: inside the subset README lines 237-255 call supported, does HALean give the same result
(type and `repr()` after `_parse_result`), raise when HA raises, and record the same `RenderInfo`; and does it answer
`unsupported` for everything else? Result: `FINDINGS.md`. Reading comparison: `side-by-side.md`.

Nothing outside this directory was modified. Patches were built and tested in
`/tmp/claude-0/halean-copies/06-templates-1` (deleted afterwards).

## Files

| path | what |
|---|---|
| `FINDINGS.md` | the result (assembled by `make_findings.py` from the logs, plus `FINDINGS.tail.md`) |
| `side-by-side.md` | upstream vs Lean for the 64 manifest entries of the area, and the Jinja2 / CPython code reimplemented without a manifest entry |
| `cases/01_syntax.yaml` … `08_extra.yaml` | 1249 hand-written cases in the shipped format, one behaviour per case, unique `name`s. Cases that both HA and HALean refuse are marked `unsupported: true` (the shipped harness has no other way to pass them) |
| `gen/batch_only.yaml` | 4 cases on which HA raises an exception that is not a `TemplateError`; the shipped harness would crash on them |
| `gen/gen_templates.py` | seeded random template generator (grammar over the supported subset) |
| `gen/seeds.txt` | the seeds used (101, 102); `gen/random-seed101.jsonl`, `gen/random-seed102.jsonl` are the generated cases (3000 each) |
| `harness/test_templates.py` | copy of `tests/differential/test_templates.py`; only the case directory (`../cases`) and the engine path (`HALEAN_BIN`) differ (`diff` it against the shipped file) |
| `harness/test_batch.py` | batch mode (not shipped): same inputs to both engines, one JSON line per case with both results, `verdict` = the shipped pass/fail rule, `cat` = extra classification. It removes a case's states afterwards, reads the engine with a 20 s timeout, and records non-`TemplateError` exceptions of HA as `ha_crash`. The comparison rule itself is unchanged; the file's docstring lists it |
| `harness/test_names.py` | compares the Lean `GLOBALS` / `FILTERS` / `TESTS` lists with HA's environment (`logs/names.log`) |
| `harness/pytest.ini` | copy of the shipped one |
| `run_batch.sh`, `run_all.sh` | drivers (below) |
| `show.py` | prints the non-matching records of a batch output |
| `classify.py` | assigns every failing case to a root cause `TPL-n` (hand-written cases by name, random cases by rules) and reports unclassified ones |
| `make_findings.py` | builds `FINDINGS.md`; asserts that both runs agree and that nothing is unclassified |
| `logs/run1-*`, `logs/run2-*` | the two full runs: `-hand-pytest.log` (harness copy, per-case assertions), `-hand-batch.jsonl` (+ `.summary.log`, `.classified.log`), `-random-seed{101,102}.jsonl` (+ `.summary.log`, `.classified.log`) |
| `logs/huge-exponent.log` | timing of `'1e<N>' \| float` on the shipped engine (TPL-47) |
| `logs/names.log`, `logs/driver-output.log` | output of `test_names.py`; console output of the final runs |
| `patches/TPL-*.patch` | one patch per root cause that has a small fix (22 files); `patches/ALL.patch` is all of them |
| `patches/all-patches-*.log`, `*.jsonl` | tests of the patched copy: shipped template tests, whole shipped differential suite, both scenario scripts, the review cases (`-hand-pytest.log`, `-hand-batch.jsonl`, `-random-seed*.jsonl`, `-classified.log`, `-before-after.log`), and `spec-build-with-all-patches.log` (the `*Spec` proof modules that stop compiling) |

## How to rerun

```sh
cd /home/user/halean/review/experiments/06-templates

# both full runs (about 3 minutes each): hand-written cases through the harness copy and the batch harness,
# then 3000 random cases per seed of gen/seeds.txt
./run_all.sh run1
./run_all.sh run2
for f in logs/run[12]-*.jsonl; do python3 classify.py $f > ${f%.jsonl}.classified.log; done

# one case file, with both results printed
./run_batch.sh /tmp/out.jsonl $PWD/cases/06_states.yaml && python3 show.py /tmp/out.jsonl

# the harness copy alone (shipped assertions)
cd harness && /opt/havenv/bin/python -m pytest test_templates.py -p no:cacheprovider -q

# another seed / count
python3 gen/gen_templates.py 7 1000 /tmp/r7.jsonl && ./run_batch.sh /tmp/r7.out.jsonl /tmp/r7.jsonl && python3 classify.py /tmp/r7.out.jsonl

# FINDINGS.md from the logs
python3 make_findings.py > FINDINGS.md
```

Patches (throwaway copy only, never in `/home/user/halean`):

```sh
cp -a /home/user/halean /tmp/claude-0/halean-copies/06-templates-1 && cd /tmp/claude-0/halean-copies/06-templates-1
git apply /home/user/halean/review/experiments/06-templates/patches/ALL.patch
export PATH=$HOME/.elan/bin:$PATH && lake build halean-template halean-automation halean-script
/opt/havenv/bin/python -m pytest tests/differential -p no:cacheprovider -q
/opt/havenv/bin/python tests/run_scenarios.py; /opt/havenv/bin/python tests/run_script_scenarios.py
# the review cases against the patched engine
cd /home/user/halean/review/experiments/06-templates
HALEAN_BIN=/tmp/claude-0/halean-copies/06-templates-1/.lake/build/bin ./run_batch.sh $PWD/patches/x.jsonl $PWD/cases/06_states.yaml
```

## Random generator

`gen/gen_templates.py SEED COUNT OUT.jsonl`. One expression generator per value kind (number, string, bool, list,
dict, datetime, timedelta, misc), each with a 7 % chance of producing another kind, so error paths are reached.
Literals come from edge-case pools (large ints, floats that print with exponents, numeric-looking strings, entity ids
in wrong case). Statements: output, `if`/`elif`/`else`, `for` (filter, `else`, `loop.*`, `break`/`continue`), `set`,
a `namespace` accumulator, whitespace-control fragments. Each case has 0-5 random states (with attributes, one
group), sometimes variables, in 35 % of cases a random `now` in 2026-2027 (millisecond precision, because the
harness sends milliseconds), and one of `parse_result: false` (10 %), `condition: true` (7 %), `render_info: true`
(28 %). `strptime` data is produced by Python's own `strftime` for the same format. Exponents, repetition counts
and ranges are kept small so that no case is slow in either engine.
