# FINDINGS: state machine (`ST`) and event bus (`BUS`)

Reviewed: `HALean/Core/State.lean`, `StateMachine.lean`, `EventBus.lean`, drivers `Exe/CoreStates.lean`,
`Exe/CoreEvents.lean`, at HALean commit `f638a37`, against HA 2026.10.4 `homeassistant/core.py`.

Short answer: for ASCII ids, finite JSON values and floats below 1e16 the two models agree with HA
on every hand-written case and on every random sequence. The differences found are at the JSON
boundary (numbers, key order, surrogates), in `repr` of unusual characters, and in two driver
details. Three findings give a wrong answer without an error and are not in the README (ST-2,
ST-10, BUS-2). Two are driver or test-tooling faults (ST-6, BUS-1).

(This file was saved by the lead reviewer from the area reviewer's hand-back text. Where the text
held invisible characters, they are written here as escapes; the case files under `cases/` are the
exact inputs.)

## Counts

| what | number | log |
|---|---|---|
| new hand-written state cases | 94 | `logs/run1-states-hand.log` (last line `24 failed, 71 passed`: 94 cases + the harness file's own `test_as_dict_cache_is_stale_after_report`) |
| new hand-written bus cases | 45 | `logs/run1-events-hand.log` (last line `3 failed, 42 passed`) |
| random state sequences per run | 400 | `logs/run1-states-rand-s1001.log` (`401 passed`: 400 + the same extra test); operations per file in `logs/gen-stats.txt` (8265 for seed 1001, 8433 for seed 1002) |
| random bus sequences per run | 300 | `logs/run1-events-rand-s2001.log` (`300 passed`); `logs/gen-stats.txt` (5799 operations, 356186 deliveries for seed 2001) |
| runs | 3 | `logs/run1-summary.txt`, `logs/run2-summary.txt` (same seeds 1001 / 2001; generated files identical, `logs/run1-generated.sha256` = `logs/run2-generated.sha256`), `logs/run3-summary.txt` (seeds 1002 / 2002) |
| hand-written cases that diverge | 27 (24 state, 3 bus), the same 27 in all three runs | `logs/run{1,2,3}-states-hand.log`, `logs/run{1,2,3}-events-hand.log` (`FAILED` lines) |
| random sequences that diverge | 0 of 700 in each run | `logs/run{1,2}-states-rand-s1001.log`, `logs/run3-states-rand-s1002.log`, `logs/run{1,2}-events-rand-s2001.log`, `logs/run3-events-rand-s2002.log` |

The random pools leave out the inputs behind the divergences below once each had a hand-written
reproducer (see `README.md`); that is why the random runs are clean. Operations HALean documents
as refused (non-ASCII ids and filters) are generated with `unsupported: true` (195 such operations
for seed 1001, 228 for seed 1002, `logs/gen-stats.txt`); HALean refused all of them.

The 27 divergent cases by root cause: ST-1: 5, ST-2: 1, ST-3: 2, ST-4: 1, ST-5: 2, ST-6: 1, ST-7: 2,
ST-8: 2, ST-9: 6, ST-10: 2 state + 1 bus, BUS-1: 1, BUS-2: 1.

## Divergences

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| ST-1 | `cases/states/str_of_state.yaml::state_float_large_integral`, `::state_float_huge`; `cases/states/attributes.yaml::attr_float_1e23_vs_int`, `::attr_float_2pow60_vs_int`, `::attr_float_1e16_keeps_type` | state `1e+16`; state `1.5e+300`; `{a: 1e23}` ≠ `{a: 10**23}` (state_changed); `{a: 2**60}` == `{a: 1.152921504606847e+18}` (state_reported); attribute stays a float | state `10000000000000000`; `InvalidStateError` "length 301"; state_reported; state_changed; attribute is an int | Silent (Refuses with an HA error class for floats ≥ 1e255) | Partly. Line 294-295: "a JSON float written without a fraction or exponent sign (`1e16`) reads as an int." The effect also holds with a fraction and an exponent sign (`1.5e+300`), and the consequences (wrong `str()`, `InvalidStateError`, wrong attribute equality in both directions) are not listed. | No. The float/int distinction is lost in Lean's `Json.parse`; a fix needs a number reader of its own in the driver. |
| ST-2 | `cases/states/str_of_state.yaml::state_float_negative_zero` | state `-0.0` | state `0.0` | Silent | No | No (the sign of zero is lost in `JsonNumber`; same reason as ST-1). |
| ST-3 | `cases/states/entity_ids.yaml::id_set_internal_unicode_digit`, `::id_set_internal_fullwidth_digit_domain` | `async_set_internal("sensor.x١", …)` creates the entity | `InvalidEntityFormatError` (an HA error class, not `unsupported`) | Refuses | The refusal yes, line 288: "non-ASCII entity ids and domain filters (`str.lower()` and `\d` are Unicode-aware)" in the "Rejected (`unsupported`)" column. The answer is not `unsupported`, so a harness cannot tell it from HA's own error. | `patches/ST-3.patch` (driver answers `unsupported`); shipped tests pass, `logs/patch-shipped-tests.log`; reproducers after the patch in `logs/patch-reproducers.log`. |
| ST-4 | `cases/states/str_of_state.yaml::state_dict_repr_key_order` | state `{'b': 1, 'a': 2}` | state `{'a': 2, 'b': 1}` | Silent (Order) | Yes. Line 294: "attribute dicts print with sorted keys"; line 653: "Lean's JSON objects are sorted by key." | No (the driver's JSON reader sorts keys). |
| ST-5 | `cases/states/str_of_state.yaml::state_repr_non_ascii_non_printable`, `::state_repr_nbsp_and_private_use` | state `['​']` (escaped, 10 characters) | state with the raw character U+200B (5 characters) | Silent | Only in another section. Line 348-349 (service registry): "`repr()` of strings with non-printable non-ASCII characters (Python escapes them, HALean does not)". Not in the state machine section. | No (needs CPython's `str.isprintable` table). |
| ST-6 | `cases/states/attributes.yaml::force_update_truthy_non_bool` | `force_update=1` forces: state_changed | read as `false`: state_reported | Tooling (driver `Exe/CoreStates.lean:111`) | No | `patches/ST-6.patch`; shipped tests pass, `logs/patch-shipped-tests.log`; reproducer passes, `logs/patch-reproducers.log`. |
| ST-7 | `cases/states/time_context.yaml::time_just_after_2pow33_seconds`, `::time_year_2300_float_resolution` | `last_updated` `2242-03-16T12:56:32.000002+00:00` for the clock 12:56:32.000001 | `2242-03-16T12:56:32.000001+00:00` | Silent | Yes. Line 290-291: "timestamps are whole microseconds (`timestamp = us / 1e6`, which the harness passes explicitly)". The date from which this matters (2^33 s, 2242-03-16) is not stated. | No. |
| ST-8 | `cases/states/attributes.yaml::attr_nan_is_not_json`, `::attr_infinity_is_not_json` | accepted, attribute `NaN` / `Infinity` | `unsupported` ("offset 68: unexpected input") | Refuses, documented | Yes. Line 288: "non-JSON attribute values"; line 350: "`NaN`/`Infinity` in the input JSON." | No. |
| ST-9 | `cases/states/entity_ids.yaml::id_non_ascii_set`, `::id_non_ascii_get`, `::id_non_ascii_is_state`, `::id_non_ascii_available`, `::id_non_ascii_remove`, `::id_non_ascii_domain_filter_str` | entity created (`sensor.x١` is a valid id) / `None` / `False` / `True` / `False` / `[]` | `unsupported` | Refuses, documented | Yes. Line 288 (quoted under ST-3). | No. |
| ST-10 | `cases/states/str_of_state.yaml::state_lone_surrogate`, `::attr_lone_surrogates_differ`; `cases/events/types_data_filters.yaml::event_type_lone_surrogates` | state `a\ud800b`; `is_state(…, "a\udfffb")` false; a listener on `"\ud800"` does not get an event of type `"\udfff"` | state `a�b`; `is_state` true; the listener gets the event | Silent | No | No (a Lean `String` cannot hold a lone surrogate; the driver would have to refuse such input). |
| BUS-1 | `cases/events/types_data_filters.yaml::system_listener_event_then_generated_context` | context `ulid@1795710645123#0` | context `ulid@1795710645123#1` | Tooling (symbolic numbering in model/driver vs harness) | No. Line 473-474 says only: "listeners that HA already had when the model starts (`init`) receive events but are opaque (they do nothing)". | `patches/BUS-1.patch` (driver renumbers by first appearance); shipped tests pass, `logs/patch-shipped-tests.log`; reproducer passes, `logs/patch-reproducers.log`; random bus run against the patched driver in `logs/patched-events-rand-s2001.log`. |
| BUS-2 | `cases/events/types_data_filters.yaml::filter_eq_float_1e23_vs_int` | filter `data["k"] == 1e23` with `k = 10**23`: false, no delivery | `Filter.eq` passes, one delivery | Silent | No | No (same cause as ST-1: `1e+23` and `100000000000000000000000` are the same `JsonNumber`). |

## Details

Outputs are copied from `logs/run1-states-record.jsonl` (state machine; the recording variant, fields
`ha` / `lean`, shortened to the state and the event type) and from `logs/run1-events-hand.log`. The
same lines are in the run2 and run3 logs. The clock is `2026-11-20T16:30:45.123456Z` unless given.

### ST-1: a float of 1e16 or more is read as an int

```yaml
- {op: set, entity_id: sensor.a, state: 1.0e+16}          # state_float_large_integral
- {op: set, entity_id: sensor.a, state: 1.5e+300}         # state_float_huge
- {op: set, entity_id: s.a, state: x, attributes: {a: 100000000000000000000000}}   # attr_float_1e23_vs_int
- {op: set, entity_id: s.a, state: x, attributes: {a: 1.0e+23}}
- {op: set, entity_id: s.a, state: x, attributes: {a: 1152921504606846976}}        # attr_float_2pow60_vs_int
- {op: set, entity_id: s.a, state: x, attributes: {a: 1.152921504606847e+18}}
```

```
state_float_large_integral op0   HA   state_changed, state "1e+16"
                                 LEAN state_changed, state "10000000000000000"
state_float_huge op0             HA   state_changed, state "1.5e+300"
                                 LEAN {"error": {"message": "Invalid state with length 301. State max length is 255 characters.", "type": "InvalidStateError"}}
attr_float_1e23_vs_int op1       HA   state_changed, attributes {"a": 1e+23}
                                 LEAN state_reported, attributes {"a": 100000000000000000000000}
attr_float_2pow60_vs_int op1     HA   state_reported, attributes {"a": 1152921504606846976}
                                 LEAN state_changed, attributes {"a": 1152921504606847000}
attr_float_1e16_keeps_type op0   HA   attributes {"a": 1e+16}      LEAN attributes {"a": 10000000000000000}
```

Root cause: the harness sends `json.dumps(1e16)` = `1e+16`. Lean's `Json.parse` stores a number as
mantissa and decimal exponent, so `1e+16` and `10000000000000000` are the same value.
`Value.ofJson` (`HALean/Template/Value.lean:419-424`) makes an int of every number whose exponent
is 0. `asyncSet` (`HALean/Core/StateMachine.lean:231-241`) then prints all digits where upstream
`str(new_state)` (`core.py:2410`) gives `repr(float)`, and `validateState` (`:223`) raises once
there are more than 255 digits. `attrsEq` (`:172`) compares an int where upstream
`old_state.attributes == attributes` (`core.py:2458`) compares a float: Python says
`1e23 != 10**23` and `2.0**60 == 2**60`; HALean says the opposite in both cases. Every float with
`abs(x) >= 1e16` is affected (below that, `repr` has a fraction digit; case `state_float_reprs`
passes with `9999999999999998.0` and `1e15`).

### ST-2: `-0.0` as a state

```yaml
- {op: set, entity_id: sensor.a, state: -0.0}
- {op: is_state, entity_id: sensor.a, state: "-0.0"}
```
```
op0  HA   state_changed, state "-0.0"      LEAN state_changed, state "0.0"
op1  HA   true                             LEAN false
```
Root cause: `JsonNumber` has an integer mantissa; `-0.0` parses to mantissa 0. Upstream
`str(-0.0)` is `'-0.0'` (`core.py:2410`). As an attribute value the difference is not visible to the
harness (`-0.0 == 0.0`; case `attr_negative_zero` passes).

### ST-3: `async_set_internal` with a Unicode digit in the id

```yaml
- {op: set_internal, entity_id: "sensor.x١", state: "1"}     # U+0661 ARABIC-INDIC DIGIT ONE
- {op: entity_ids}
```
```
op0  HA   state_changed, new_state.entity_id "sensor.x١"
     LEAN {"error": {"message": "Invalid entity id encountered: sensor.x١. Format should be <domain>.<object_id>", "type": "InvalidEntityFormatError"}}
op1  HA   ["sensor.x١"]      LEAN []
```
Root cause: `VALID_ENTITY_ID` uses `\d` (`core.py:179-183`), which matches Unicode decimal digits.
`isSlugChar` (`HALean/Core/State.lean:48`) uses `Char.isDigit` (ASCII). The comment at `State.lean:45`
says callers reject non-ASCII ids; `asyncSetInternal` (`StateMachine.lean:188`) has no `checkAscii`
and the driver's `set_internal` branch (`Exe/CoreStates.lean:117-119`) has none either, so the
model answers with HA's error class. Through `set` the same id is answered `unsupported` (ST-9).
An id with a non-ASCII letter (`sensor.é`) is invalid on both sides (case
`id_set_internal_non_ascii_letter` passes unpatched).

Patch `patches/ST-3.patch`: the driver answers `unsupported` for a non-ASCII id in `set_internal`.
After the patch the two reproducers and `id_set_internal_non_ascii_letter` are refused
(`logs/patch-reproducers.log`: "HALean rejected it: non-ASCII entity_id (Python's \d is
Unicode-aware)"). This turns a wrong answer into the documented refusal; it does not make HALean
accept the id.

### ST-4: a dict state prints with sorted keys

```yaml
- {op: set, entity_id: sensor.a, state: {b: 1, a: 2}}
```
```
HA   state "{'b': 1, 'a': 2}"      LEAN state "{'a': 2, 'b': 1}"
```
Root cause: Lean's `Json.obj` is a tree ordered by key; `Value.ofJson` (`Template/Value.lean:427`)
lists it in that order. Upstream `str(dict)` keeps insertion order (`core.py:2410`).

### ST-5: `repr` of non-printable non-ASCII characters inside a list or dict state

Inputs (exact bytes in `cases/states/str_of_state.yaml`): a list state holding U+200B; a list state
holding U+00A0, U+00AD, U+E000, U+2028, U+0080, U+009F.

```
HA   state "['\\u200b']"       LEAN state with the raw one character U+200B between the quotes
HA   state "['\\xa0', '\\xad', '\\ue000', '\\u2028', '\\x80', '\\x9f']"
LEAN state with the six raw characters between the quotes
```
Root cause: `strRepr` (used by `pyRepr`, `HALean/Template/Value.lean:239-245`) escapes ASCII control
characters only. CPython's `repr` escapes every character for which `str.isprintable()` is false.
The state gets a different text and a different length (so the 255 limit is hit at different
inputs). ASCII control characters and printable non-ASCII text agree (cases
`state_repr_quotes_and_escapes`, `state_repr_non_ascii_printable`).

### ST-6: `force_update` that is not a JSON bool

```yaml
- {op: set, entity_id: s.a, state: x}
- {op: set, entity_id: s.a, state: x, force_update: 1, now: "2026-11-20T16:31:00+00:00"}
```
```
op1  HA   state_changed (last_updated 2026-11-20T16:31:00+00:00)
     LEAN state_reported (last_updated 2026-11-20T16:30:45.123456+00:00)
```
Root cause: `Exe/CoreStates.lean:111` `match … with | .ok (.bool b) => b | _ => false`. Upstream uses
the truth value (`same_state = old_state.state == new_state and not force_update`, `core.py:2457`).
The driver neither applies the truth value nor refuses the input. The model itself takes a `Bool`.
Patch `patches/ST-6.patch` uses `truthy (Value.ofJson v)`.

### ST-7: instants after 2242-03-16 (2^33 seconds)

```yaml
- {op: set, entity_id: s.a, state: x, now: "2242-03-16T12:56:32.000001+00:00", context: {id: c1}}
```
```
HA   last_updated "2242-03-16T12:56:32.000002+00:00"
LEAN last_updated "2242-03-16T12:56:32.000001+00:00"
```
Root cause: upstream takes a float `timestamp` and derives the datetime from it
(`now = dt_util.utc_from_timestamp(timestamp)`, `core.py:2472`). From 2^33 s on, doubles are 1.9 µs
apart, so `us / 1e6` no longer identifies a whole microsecond. `asyncSetInternal` uses the integer
µs as given (`StateMachine.lean:201`, `State.lean:163`). The bus model does go through the float
(`EventBus.lean:116-131`), and the bus cases with the same instants pass (`time_fired_rounding`,
`now_rounding`), so the two HALean models treat such instants differently. One second
earlier both sides agree (case `time_just_before_2pow33_seconds` passes). No HA call receives the
value "…32.000001" itself; the difference is in how the model's clock input maps to HA's float.

### ST-8: `NaN` / `Infinity` attribute values (documented refusal)

```yaml
- {op: set, entity_id: s.a, state: x, attributes: {a: .nan}}
```
```
HA   state_changed, attributes {"a": NaN}
LEAN {"unsupported": "offset 68: unexpected input"}
```
The line does not parse (`Exe/CoreStates.lean:153`, `Json.parse`). The harness copy treats it as the
shipped harness does: the case fails with "HALean rejected it"; with `unsupported: true` it would
pass and HA would not be run.

### ST-9: non-ASCII ids and `str` domain filters (documented refusal)

```
id_non_ascii_set op0               {"op": "set", "entity_id": "sensor.x١", "state": "1"}
     HA   state_changed, entity created      LEAN {"unsupported": "non-ASCII entity_id (Python's str.lower() is Unicode-aware): sensor.x١"}
id_non_ascii_get op0               HA null     LEAN unsupported
id_non_ascii_is_state op0          HA false    LEAN unsupported
id_non_ascii_available op0         HA true     LEAN unsupported
id_non_ascii_remove op0            HA false    LEAN unsupported
id_non_ascii_domain_filter_str op0 HA []       LEAN {"unsupported": "non-ASCII domain (Python's str.lower() is Unicode-aware): é"}
```
`checkAscii` (`StateMachine.lean:108`) in `asyncSet`, `get`, `asyncRemove`, `asyncAvailable`,
`asyncEntityIds`/`Count`/`asyncAll` with a `str` filter. A list filter and `async_reserve` are not
checked and agree with HA (case `id_non_ascii_domain_filter_list_and_reserve` passes).

### ST-10: lone surrogates become U+FFFD

```yaml
- {op: set, entity_id: s.a, state: "a\ud800b"}                 # state_lone_surrogate
- {op: is_state, entity_id: s.a, state: "a\udfffb"}
- {op: is_state, entity_id: s.a, state: "a�b"}
- {op: set, entity_id: s.a, state: "a\udfffb", now: "2026-11-20T16:31:00+00:00"}
```
```
op0  HA   state_changed, state "a\ud800b"     LEAN state_changed, state "a�b"
op1  HA   false                               LEAN true
op2  HA   false                               LEAN true
op3  HA   state_changed                       LEAN state_reported
```
Bus (`event_type_lone_surrogates`, `logs/run1-events-hand.log`): listen on `"\ud800"`, fire `"\udfff"`:
```
E   Failed: op 1 fire: deliveries differ
E   HA:     (0, [])
E   HALean: (1, [{'event': {'context': {'id': 'ulid@1795710645123#0', 'parent_id': None, 'user_id': None}, 'data': {}, 'event_type': '�', 'origin': 'LOCAL', 'time_fired': '2026-11-26T16:30:45.123456+00:00'}, 'listener': 'hi'}])
```
Root cause: Python strings can hold a lone surrogate (`json.loads('"\\ud800"')` works, and
`json.dumps` writes it back as `\ud800`). A Lean `String` cannot; `Json.parse` in both drivers
(`Exe/CoreStates.lean:153`, `Exe/CoreEvents.lean:147`) substitutes U+FFFD, so different surrogates
become equal. The drivers do not refuse the input. Surrogate pairs (astral characters) are read
correctly (cases `length_counts_code_points_astral`, `event_type_astral_64_and_65`).

### BUS-1: numbering of generated contexts after an event only HA's own listeners saw

```yaml
- {op: fire, event_type: logging_changed}     # one listener, installed by EventBus.__init__
- {op: listen, id: a, event_type: x}
- {op: fire, event_type: x}
```
```
E   Failed: op 2 fire: deliveries differ
E   HA:     (0, {'listener': 'a', 'event': {'event_type': 'x', 'data': {}, 'origin': 'LOCAL', 'time_fired': '2026-11-26T16:30:45.123456+00:00', 'context': {'id': 'ulid@1795710645123#0', 'parent_id': None, 'user_id': None}}})
E   HALean: (0, {'event': {'context': {'id': 'ulid@1795710645123#1', 'parent_id': None, 'user_id': None}, 'data': {}, 'event_type': 'x', 'origin': 'LOCAL', 'time_fired': '2026-11-26T16:30:45.123456+00:00'}, 'listener': 'a'})
```
Root cause: `makeEvent` (`HALean/Core/EventBus.lean:419-425`) counts every generated context
(`genCount`), also for an event that reached only an opaque `system` job (`runJob`, `:379`, records
nothing). The harness numbers HA's random ULIDs in order of first appearance in a delivery
(`tests/differential/test_events.py`, `Runner._ctx_id`). The event, its time and the dispatch are the
same on both sides; only the symbolic name differs. Upstream itself is `core.py:1384-1385`.
Patch `patches/BUS-1.patch`: the driver renames generated ids by first appearance (ids that start
with `ulid@`; a context id supplied by a case that starts with `ulid@` would be renamed too).

### BUS-2: `Filter.eq` compares decimal text, not floats

```yaml
- {op: listen, id: f23, event_type: x, filter: {eq: {k: 1.0e+23}}}
- {op: fire, event_type: x, data: {k: 100000000000000000000000}}
```
```
E   Failed: op 1 fire: deliveries differ
E   HA:     (0, [])
E   HALean: (1, [{'event': {'context': {'id': 'ulid@1795710645123#0', 'parent_id': None, 'user_id': None}, 'data': {'k': 100000000000000000000000}, 'event_type': 'x', 'origin': 'LOCAL', 'time_fired': '2026-11-26T16:30:45.123456+00:00'}, 'listener': 'f23'}])
```
Root cause: `pyEq.numEq` (`HALean/Core/EventBus.lean:403-404`) compares `JsonNumber`s as exact
decimals. The filter value `1e+23` is 10^23 as a decimal; the Python float `1e23` is
99999999999999991611392, so `10**23 == 1e23` is false in Python. The doc comment at `:387` says
"Python's `==` on JSON values". Affects float/int pairs from 1e16 up where the float is not the
exact integer its shortest `repr` spells. Below 1e16 the comparison agrees with Python (case
`filter_eq_numbers` passes, including `9007199254740993` vs `9007199254740992.0`).

## Reading findings without a reproducer

* R-1. `Event.__init__` resolves `time_fired_timestamp or time.time()` when the `Event` is built,
  which is at the first listener that runs (`core.py:1383`, `1668-1675`). HALean resolves it when
  the fire is made (`mkQueued`, `EventBus.lean:319`). For a top-level fire the two read the clock
  at different moments on a live system. The harness freezes the clock for the whole operation,
  so both read the same value. Cannot be driven: the clock is a single input per operation.
* R-2. `async_remove` fires with `time_fired=None` (`core.py:2333-2337`), so the event time is
  `time.time()` at event creation, not a timestamp of the removal. `asyncRemove`
  (`StateMachine.lean:143`) uses `now`. Same reason as R-1.
* R-3. Attribute key order. HA keeps the order of the mapping it was given; HALean's `Json.obj` is
  key-sorted, so `State.asDict` lists attributes sorted. The state harness compares dicts with
  `==`, which ignores order. README line 294 lists it ("attribute dicts print with sorted keys").
  Its visible form through `str()` of a dict state is ST-4.
* R-4. `str(int)` of more than 4300 digits raises `ValueError` in CPython (`core.py:2410`);
  `pyRepr` prints any int. YAML and JSON readers in Python raise on such a literal first, so the
  harness cannot send one.
* R-5. `State.new` reports a failed `split_entity_id` as `InvalidEntityFormatError`
  (`State.lean:145-146`); upstream raises `ValueError` (`core.py:176`). Unreachable from the state
  machine: a new id is validated first and an existing key has passed validation.
* R-6. `valid_domain` (`State.lean:86`) is not called by any `halean-core-states` operation. Read
  only: same ASCII-digit restriction as `valid_entity_id`, otherwise no difference found.
* R-7. `State.__init__` converts a non-`str` state with `str()` (`core.py:1928`);
  `asyncSetInternal` takes a `String`, and the driver refuses a non-string `state` for
  `set_internal` (`Exe/CoreStates.lean:118`, `getStr`). HA would accept it. Not listed in the README
  table; the driver header documents it ("`state` must be a string").
* R-8. `EventBus.async_fire` on a thread other than the loop's reports a non-thread-safe operation
  (`core.py:1580-1583`). Not modelled (README lists the thread-safe wrappers as not modelled).
* R-9. ST-6 reachability: the claim that a non-bool `force_update` can reach `async_set` rests on
  the REST API passing the JSON value through. That path (`components/api`) was not read at the
  pinned release in this review; the harness call `async_set(..., force_update=1)` is what was run.

## Notes on the harness

* The bus harness compares with plain `==` (`if ha != lean`), so `1`, `1.0` and `True` in event
  data are the same to it; the state harness compares typed values (`_typed`). The bus driver
  prints with `Json.compress`, which writes `1.0` as `1`; the harness cannot see that.
* Neither harness sees dict key order (attributes, event data, `as_dict`).
* An operation marked `unsupported: true` is never run on HA. The harness checks that HALean
  refuses it, not that HA would have answered, nor what. The shipped `non_ascii_rejected` case
  marks `get light.küche`; HA answers `None` for such a `get` (ST-9).
* The state harness catches only `HomeAssistantError`. An input for which HA raises another
  exception errors the test instead of being compared. HALean answers `unsupported` for a
  non-mapping `attributes`; such inputs cannot be classified through the harness.
* The clock is frozen per operation. Anything that depends on when inside an operation the clock
  is read is invisible (R-1, R-2).
* Generated context ids: the state harness checks on the HA side that the ULID encodes the
  operation's millisecond; HALean's `ulid:<n>` carries no time, so the model makes no statement
  about it. The bus model does (`ulid@<ms>#<n>`).
* The state harness uses `State._as_dict.wrapped(s)`, bypassing the cache; what a caller of
  `as_dict()` gets after a report is covered only by the shipped
  `test_as_dict_cache_is_stale_after_report`.
* `Renamer.walk` (state harness) treats every dict whose keys are exactly `id`, `parent_id`,
  `user_id` as a context, also inside attributes; an attribute value of that shape would hit the
  ULID assertion. `_ctx` maps an empty context mapping to "no context" while the driver refuses
  it. No case here uses either.
* The bus harness starts the model from HA's listener table (`init`), but what HA's own
  listeners do when they get an event is outside the model. Only `logging_changed` and
  `homeassistant_close` are fired in the hand-written cases; the random pools avoid such types.
* The bus harness reads three kinds of `homeassistant.core` error records. Other records and
  other loggers are ignored.
* Listener scripts cover five exception classes and four filter kinds; a filter cannot fire,
  listen or unsubscribe.
