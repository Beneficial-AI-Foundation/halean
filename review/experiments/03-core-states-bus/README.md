# 03-core-states-bus: state machine and event bus

Area: is `HALean/Core/StateMachine.lean`, `State.lean` (driver `Exe/CoreStates.lean`) and
`HALean/Core/EventBus.lean` (driver `Exe/CoreEvents.lean`) faithful to `State`, `StateMachine`,
`EventBus`, `Event`, `Context` in `homeassistant/core.py` at HA 2026.10.4?

Result: `FINDINGS.md`. Reading comparison: `side-by-side.md`.

## Rerun

```sh
cd /home/user/halean/review/experiments/03-core-states-bus
./run.sh run1 1001 2001          # hand cases + 400 random state sequences + 300 random bus sequences
./run.sh run2 1001 2001          # same seeds again (reproduction)
./run.sh run3 1002 2002          # other seeds
```

`run.sh <label> <states-seed> <events-seed> [states-count] [events-count]` regenerates
`cases/states/lengths.yaml` and the random cases (`gen/out/<kind>_<seed>/rand.yaml`), then runs,
with `/opt/havenv/bin/python -m pytest -p no:cacheprovider -q --tb=short -rfE`:

| step | log |
|---|---|
| hand-written state cases (`cases/states/*.yaml`) | `logs/<label>-states-hand.log` |
| hand-written bus cases (`cases/events/*.yaml`) | `logs/<label>-events-hand.log` |
| the same state cases with the recording variant | `logs/<label>-states-record.log`, `logs/<label>-states-record.jsonl` |
| random state sequences | `logs/<label>-states-rand-s<seed>.log` |
| random bus sequences | `logs/<label>-events-rand-s<seed>.log` |
| checksums of the generated files | `logs/<label>-generated.sha256` |

The engine binaries come from `$HALEAN_BIN` (default `/home/user/halean/.lake/build/bin`). To run
against a patched copy: `HALEAN_BIN=/tmp/claude-0/halean-copies/<copy>/.lake/build/bin ./run.sh ...`.

A single case: `cd harness && /opt/havenv/bin/python -m pytest test_states.py -p no:cacheprovider -q -k <name>`.

## Files

* `cases/states/*.yaml`: hand-written state-machine cases, shipped format (`tests/core/states`).
  `lengths.yaml` is written by `gen/make_length_cases.py` (strings of exactly 255 / 256 characters;
  deterministic, no seed). Cases named in `FINDINGS.md` are the reproducers.
* `cases/events/*.yaml`: hand-written bus cases, shipped format (`tests/core/events`).
* `gen/gen_states.py`, `gen/gen_events.py`: seeded random generators (`SEED COUNT OUT.yaml [--known]`).
  Without `--known` the pools leave out the inputs behind the divergences already found (floats
  that print without a fraction, `-0.0` as a state, dict states with unsorted keys, non-printable
  non-ASCII characters inside list states, Unicode-digit ids for `set_internal`, non-bool
  `force_update`; for the bus: event types HA's own listeners handle, the `1e23` / `10**23` pair),
  so that a failing random sequence points at something new. Each of those inputs has a
  hand-written reproducer. Seeds used: states 1001, 1002; events 2001, 2002.
* `gen/stats.py`: counts what a generated file exercises (events fired, errors, deliveries, logs),
  measured on HALean alone. Output in `logs/gen-stats.txt`.
* `gen/out/`: the generated case files of the runs.
* `harness/test_states.py`, `harness/test_events.py`: copies of `tests/differential/test_states.py`
  and `test_events.py`. Changed lines (see `logs/harness-diff.txt`): the case directory
  (`../cases/<kind>`, or `$HALEAN_CASES` so the same copy can read the generated files) and the
  engine path (`$HALEAN_BIN`). The comparison logic is unchanged.
* `harness/test_states_record.py`: a recording variant, not the verdict. It runs HA for every
  operation, also for those HALean answers `unsupported` (the shipped harness stops there), and
  writes both answers to a JSONL file with a per-operation verdict that applies the shipped
  assertion semantics (`pass`, `diff`, `refused`, `not-refused`). Used to get HA's answer for
  refused operations. Once HALean has refused an operation the two sides are out of step, so
  only the first non-`pass` operation of a case is meaningful.
* `harness/pytest.ini`: copy of `tests/differential/pytest.ini`.
* `logs/`: run logs; `logs/patch-*.log`: tests of the patches.
* `patches/*.patch`: patches (made in `/tmp/claude-0/halean-copies/03-core-states-bus-1`).
* `side-by-side.md`, `FINDINGS.md`.

## How refusals are treated

The shipped harness fails a case when HALean answers `unsupported` for an operation not marked
`unsupported: true`, and for marked operations it requires the refusal and does not run HA. The
random generator marks the operations the README documents as outside the subset (non-ASCII
entity ids and domain filters) with `unsupported: true`, as the shipped `non_ascii_rejected` case
does. The hand-written `id_non_ascii_*`, `attr_nan_is_not_json` and `attr_infinity_is_not_json`
cases are deliberately not marked: they fail in the harness copy with "HALean rejected it", and
the recording variant supplies HA's answer. They are classified `Refuses`, documented.
