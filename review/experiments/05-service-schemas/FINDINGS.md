# Findings: service schemas (area 05)

Question: for every validator the README (line 335, left column) lists as "Supported (exact)", does HALean give the
same result `repr()` or the same exception class and `str()` as real probatio 0.13.0 / Home Assistant 2026.10.4?

Answer: yes for every case and fuzz input that stays inside the documented subset and is validated by probatio's
interpreted engine, with six exceptions (SCH-1 to SCH-6 below). Two of them change what a caller sees for
plain input: SCH-1 (the engine process dies on a number text with a huge exponent) and SCH-3 (after a schema's 50th
validation real probatio raises `OverflowError` where HALean and a cold probatio schema say "expected float").

## Counts

| what | number | log |
|---|---|---|
| new hand-written cases | 32 cases, 547 data points (call operations), 26 of them marked `unsupported: true` | `logs/case-counts.log` |
| hand-written cases run by the harness | 30 in `cases/` (31 tests with the shipped pin test: "7 failed, 24 passed"), 1 + 1 in `cases_crash/` ("1 failed, 1 passed" each, with the pin test) | `logs/run1-hand.log`, `logs/run1-hand-strict.log`, `logs/run1-crash-sch1.log`, `logs/run1-crash-sch1b.log` |
| random cases per run | 2,060 schemas, 28,200 schema/data pairs (12,000 + 12,000 + 4,200; the last 60 schemas get 70 calls each) | `logs/run1-gen.log`, `logs/run2-gen.log`, `logs/run3-gen.log` |
| runs | 3: run 1 and run 2 with seeds 101, 102, 103; run 3 with seeds 201, 202, 203. Run 1 and run 2 recorded the same operations (same counts per root cause, same `TOTAL` line) | `logs/run1-summary.log`, `logs/run2-summary.log`, `logs/run3-summary.log` |
| hand-written cases that diverge | 9: 7 in `cases/divergences.yaml` (8 operations) and the 2 crash cases, in each of the 3 runs | `logs/runN-hand.log` ("7 failed"), `logs/runN-classify.log` (first line), `logs/runN-crash-sch1.log`, `logs/runN-crash-sch1b.log` |
| random cases that diverge | run 1 and run 2: 66 cases (78 operations); run 3: 62 cases (71 operations) | `logs/runN-classify-random.log`, `TOTAL` line |
| random operations HALean refuses and the README lists | run 1 and run 2: 1,403; run 3: 1,333 | `logs/runN-classify-random.log`, `TOTAL` line |
| recorded operations not sorted into a root cause | 0 in every run | `logs/runN-classify.log` (no `UNCLASSIFIED` line) |
| distinct root causes | 6 | table below |

Random operations by root cause (`logs/run1-classify-random.log`, equal to `logs/run2-classify-random.log`; `logs/run3-classify-random.log`):

| root cause | run 1 = run 2 (a + b + warm) | run 3 |
|---|---|---|
| SCH-2 | 15 + 11 + 3 = 29 | 13 + 17 + 6 = 36 |
| SCH-3 | 17 + 15 + 6 = 38 | 13 + 14 + 3 = 30 |
| SCH-5 | 7 + 4 + 0 = 11 | 2 + 2 + 1 = 5 |
| documented: text that is not printable ASCII | 402 + 444 + 119 = 965 | 432 + 427 + 121 = 980 |
| documented: `timedelta` overflow / NaN | 155 + 150 + 92 = 397 | 170 + 131 + 31 = 332 |
| documented: slugify of text with an HTML entity | 5 + 4 + 32 = 41 | 6 + 12 + 3 = 21 |

SCH-1, SCH-4 and SCH-6 do not appear in the random harness runs: the generator writes no 10-digit exponent and no
empty `at_least_one`, and `All(time_period, entity_ids)` is rare. SCH-1 and SCH-6 were found by reading and by hand
probes; SCH-4 by the fast fuzz during the search (scratch run, no log kept). All three are reproduced by their
hand-written cases in all three runs.

Fast-tool runs (real probatio called directly, no hass instance; used to search, not part of the verdict):

| tool | pairs | answers that differ | log |
|---|---|---|---|
| `fuzz_numeric.py 1` | 50,058 | 0 | `logs/fuzz-numeric-seed1.log` |
| `fuzz_text.py 1` | 242,576 | 0 | `logs/fuzz-text-seed1.log` |
| `fuzz_messages.py 1` | 38,757 | 0 | `logs/fuzz-messages-seed1.log` |
| `fuzz.py --seed 2`, `--seed 3` | 15,000 each | 17 and 21 `VALUE` (SCH-2), 10 and 21 `int too large to convert to float` (SCH-3) | `logs/fuzz-random-seed2.log`, `logs/fuzz-random-seed3.log` |
| `fuzz_codegen.py 11 2500`, `12 2500` (Python only: interpreted probatio against its generated code) | 20,000 each | 13 and 7, all `MultipleInvalid` against `OverflowError` (SCH-3) | `logs/fuzz-codegen-seed11.log`, `logs/fuzz-codegen-seed12.log` |

## Divergences

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| SCH-1 | `cases_crash/sch1/sch1.yaml::hw_sch1_coerce_float_huge_exponent`, `cases_crash/sch1b/sch1b.yaml::hw_sch1_time_period_zero_huge_exponent` | `{'f': inf}`; `{'t': datetime.timedelta(0)}` | the process dies: `INTERNAL PANIC: Nat.pow exponent is too big` | Refuses (crash) | no | yes: `patches/SCH-1.patch`; both cases pass (`patches/patched-cases_crash-sch1.log`, `patches/patched-cases_crash-sch1b.log`); shipped tests pass (`patches/shipped-differential-all-patches.log`: 611 passed, 6 skipped; `patches/shipped-scenarios-all-patches.log`: 60/60; `patches/shipped-script-scenarios-all-patches.log`: 11/11) |
| SCH-2 | `cases/divergences.yaml::hw_sch2_repr_non_printable`, `::hw_sch2_path_non_printable_key`, `::hw_sch2_event_repr` | `'a\xa0b'`; `not a valid option at '['\u200b']'` (escaped) | the same with the raw character | Silent | yes (348-349) | no (needs Unicode category tables) |
| SCH-3 | `cases/divergences.yaml::hw_sch3_coerce_float_after_50_validations` (control: `::hw_sch3_control`) | `OverflowError: int too large to convert to float` (`error_kind` `other`) | `MultipleInvalid: expected float at 'f'` (`error_kind` `invalid`) | Silent | in part (648-652: the generated code is not translated and "is meant to behave like the interpreted engine") | no (needs a validation counter per schema object; the counter of `cv.time_period_dict` is process-wide) |
| SCH-4 | `cases/divergences.yaml::hw_sch4_timedelta_not_iterable` | `TypeError: 'datetime.timedelta' object is not iterable` | `TypeError: 'timedelta' object is not iterable` | Silent | no | yes: `patches/SCH-4.patch` (also restates theorem `pyIter_error`); the case passes (`patches/patched-cases.log`); shipped tests pass (same three logs as SCH-1) |
| SCH-5 | `cases/divergences.yaml::hw_sch5_slug_ampersand_semicolon` | `MultipleInvalid: invalid slug a;& (try a) at 'sl'` | `unsupported: util.slugify of this text (HTML entities) is not modelled` | Refuses | in part (335: "`util.slugify` of text with HTML entities"; this text has none) | no (`slugify?` is the subject of proofs in `SlugifySpec.lean`, `Automation/ConfigSpec.lean`, `Script/ConfigSpec.lean`) |
| SCH-6 | `cases/divergences.yaml::hw_sch6_at_least_one_no_keys` | `SchemaError: needs at least one key` when the schema is built | the service is registered | Accepts | no | yes: `patches/SCH-6.patch`; HALean then answers `unsupported` at `register` (`patches/patched-classify.log`); shipped tests pass (same three logs as SCH-1) |

The three patches were applied together in one copy and tested together. Build logs:
`patches/build-all-exes-all-patches.log` (all nine executables), `patches/build-library-all-patches-3.log` (the whole
library with its proofs, 198 jobs). The first library build failed in `ConfigValidationSpec.lean`
(`patches/build-library-all-patches.log`): theorem `pyIter_error` states the message that SCH-4 corrects, so
`SCH-4.patch` restates it. `patches/all-patches.patch` is the three together. The copy was deleted afterwards.

## Details

### SCH-1: a number text with a huge exponent kills the engine

Reproducer (`cases_crash/sch1/sch1.yaml`):

```yaml
- {op: register, domain: hw, service: v, handler: {echo: true}, supports_response: only,
   schema: {fields: [{key: f, value: {coerce: float}}]}}
- {op: call, domain: hw, service: v, blocking: true, return_response: true, data: {f: "1e9999999999"}}
```

HA (`logs/sch1-explore.log`): `('ok', "{'f': inf}")`; for `cv.time_period` on `"0e9999999999"`: `('ok', "{'t': datetime.timedelta(0)}")`.

HALean (`logs/run1-crash-sch1.log:79`, `logs/run2-crash-sch1.log:79`, `logs/run3-crash-sch1.log:79`):
`INTERNAL PANIC: Nat.pow exponent is too big`. The harness then fails with
`json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)` (line 71 of the same logs), because the
process wrote nothing.

Root cause: `parseFloatStr`, `HALean/Template/Value.lean:187-192`. It builds the exact rational:
`m * 10 ^ exp.toNat` (line 189) or `10 ^ (-exp).toNat` (line 192). The guard on line 191
(`exp < -400 && m < 10 ^ 400`) covers negative exponents with a short mantissa only; a zero mantissa also computes the
power. CPython's `float()` returns `inf` or `0.0` at once.
Below the panic limit the time grows with the exponent (`logs/sch1-timing.log`): `"1e100000000"` 9.71 s,
`"1e400000000"` 35.22 s, `"0e100000000"` 2.98 s; HA answers each in under a millisecond.
Every caller is affected: `Coerce(float)` (`Probatio.lean:559`), `cv.positive_float`, `cv.small_float`,
`cv.time_period_str` (`ConfigValidation.lean:157`), `cv.time_period_seconds`, `cv.time_period_dict`, and the driver's
JSON parser (`PyJson.lean:118`): the JSON number `1e9999999999` kills it too (`logs/sch1-raw-json.log`; Python's
`json.loads` reads `inf`, `orjson.loads` raises `JSONDecodeError`).
README: nothing on exponents. Line 350 lists only "`NaN`/`Infinity` in the input JSON".

Patch (`patches/SCH-1.patch`): `0.0` for a zero mantissa, `inf` when `digits(m) - 1 + exp >= 310`, `0.0` when
`digits(m) + exp <= -400`, before any power is computed.

### SCH-2: `repr()` of non-printable non-ASCII characters

Reproducer (`cases/divergences.yaml::hw_sch2_repr_non_printable`): schema `{s: str}`, data `{s: "a\u00a0b"}` (U+00A0).

`logs/run1-hand.jsonl` (operation 1 of the case), the same in `logs/run2-hand.jsonl` and `logs/run3-hand.jsonl`:

```
HA     {'domain': 'hw', 'service': 'v', 'data': {'s': 'a\xa0b'}, 'return_response': True, 'context_id': 'new'}
HALean {'domain': 'hw', 'service': 'v', 'data': {'s': 'a<U+00A0>b'}, 'return_response': True, 'context_id': 'new'}
```

(`<U+00A0>` stands for the raw character.) The same root cause changes an error message
(`::hw_sch2_path_non_printable_key`, data `{"\u200b": 1}`):

```
HA     MultipleInvalid: not a valid option at '['\u200b']'       (the six ASCII characters)
HALean MultipleInvalid: not a valid option at '['<U+200B>']'     (the raw character)
```

and the `call_service` event of a call whose result is equal (`::hw_sch2_event_repr`: `cv.boolean` returns `True` for
`"TRUE\u00a0"` on both sides; the event's data are `'TRUE\xa0'` in HA and the raw character in HALean).

Root cause: `strRepr`, `HALean/Template/Value.lean:215-226`, escapes ASCII control characters and `\x7f` only.
CPython's `repr(str)` escapes every character for which `str.isprintable()` is false.
README lines 348-349: "`repr()` of strings with non-printable non-ASCII characters (Python escapes them, HALean does
not)". Documented. It is listed here because HALean reports no error, and because it also reaches probatio's
messages through `render_path` (`Probatio.lean:188-189`), which the README sentence does not say.

### SCH-3: `Coerce(float)` of a huge int after the schema's 50th validation

Reproducer (`cases/divergences.yaml::hw_sch3_coerce_float_after_50_validations`): schema `{f: Coerce(float)}`,
50 calls with `{f: 1}` to `{f: 50}`, then one call with `{f: 10**400}` (the number is written out in the file).

`logs/run1-hand.jsonl` (operation 51), the same in run 2 and run 3:

```
HA     {"exception": "OverflowError", "error_kind": "other", "message": "int too large to convert to float"}
HALean {"exception": "MultipleInvalid", "error_kind": "invalid", "message": "expected float at 'f'"}
```

The control case `::hw_sch3_control` (the same datum as the first call) passes: both say `expected float at 'f'`
(`logs/run1-hand.log`: it is not among the 7 failures).

Root cause: probatio validates a `Schema` object with its interpreted engine and installs generated code at the 50th
call (`probatio/schema.py:142`, `_auto_counter` at `schema.py:468-496`). The generated code for `Coerce(float)` is
`elif type(_v) is int: _v = float(_v)` with no guard (`probatio/_codegen.py:158-159`); the interpreted
`Coerce.__call__` catches every exception (`probatio/validators/coerce.py:77-106`). HALean follows the interpreted
engine (`pyFloat?`, `checkCoerce`, `HALean/Core/Probatio.lean:555-576`). Affected: `Coerce(float)`,
`cv.positive_float`, `cv.small_float`, `cv.time_period_dict` and what is built from them. The plain `float` type is
not affected (the generated code has the guard, `_codegen.py:296-304`).
`cv.time_period_dict` holds a process-wide `probatio.Schema` (`helpers/config_validation.py:475-489`), so its counter
runs across all services. In files `a` and `b` of the random runs no service is called more than 12 times, yet
32 (run 1) operations there are SCH-3: each is a time-period dict with a huge int (`logs/run1-classify-random.log`).
The Python-only fuzz found no other difference between probatio's two engines on 40,000 pairs
(`logs/fuzz-codegen-seed11.log`, `logs/fuzz-codegen-seed12.log`).
README lines 648-652: "Service schemas: the codegen path probatio switches a schema to after 50 validations
(`CompilePolicy.AUTO`) is not translated; it is meant to behave like the interpreted engine, which is what HALean
follows and what the differential tests (few calls per schema) exercise." The gap is listed. The statement that the two
behave alike does not hold for this input.

### SCH-4: the `TypeError` of iterating a `timedelta`

Reproducer (`cases/divergences.yaml::hw_sch4_timedelta_not_iterable`): schema `{e: All(cv.time_period, cv.entity_ids)}`, data `{e: 5}`.

`logs/run1-hand.jsonl` (operation 1), the same in run 2 and run 3:

```
HA     {"exception": "TypeError", "error_kind": "other", "message": "'datetime.timedelta' object is not iterable"}
HALean {"exception": "TypeError", "error_kind": "other", "message": "'timedelta' object is not iterable"}
```

Root cause: `pyIter`, `HALean/Core/ConfigValidation.lean:59-63`, prints `typeName v`
(`HALean/Template/Value.lean:374`), which is Python's `type(v).__name__`. CPython's message prints `tp_name`, which
is `datetime.timedelta`. Upstream: `_entity_ids`, `helpers/config_validation.py:348-356`. The same holds for
`cv.comp_entity_ids` and `cv.entity_domain`. Theorem `pyIter_error` (`HALean/Core/ConfigValidationSpec.lean:226-228`)
proves the model's message.
README line 335 says "a `TypeError` for a scalar escapes the schema, as upstream"; nothing on its text.

### SCH-5: `cv.slug` refuses text with `&` and `;` that holds no HTML entity

Reproducer (`cases/divergences.yaml::hw_sch5_slug_ampersand_semicolon`): schema `{sl: cv.slug}`, data `{sl: "a;&"}`.

`logs/run1-hand.jsonl` (operation 1), the same in run 2 and run 3:

```
HA     {"exception": "MultipleInvalid", "error_kind": "invalid", "message": "invalid slug a;& (try a) at 'sl'"}
HALean {"unsupported": "util.slugify of this text (HTML entities) is not modelled"}
```

Root cause: `slugify?`, `HALean/Automation/Slugify.lean:52`: `if text.contains '&' && text.contains ';' then none`.
python-slugify rewrites only `&name;` for a known name, `&#digits;` and `&#xhex;` (`slugify/_legacy.py:19-21`).
In `logs/fuzz-text-seed1.log` 577 of 30,000 random strings are refused this way.
README line 335, right column: "`util.slugify` of text with HTML entities". The refusal is wider than that.
`cases/documented_refusals.yaml::hw_refused_slugify_html_entities` holds four inputs with real entities; they count
as documented.

### SCH-6: `at_least_one: []`

Reproducer (`cases/divergences.yaml::hw_sch6_at_least_one_no_keys`):

```yaml
- {op: register, domain: hw, service: v, handler: {echo: true}, supports_response: only,
   schema: {fields: [{key: m, value: {at_least_one: []}}]}}
```

`logs/run1-hand.jsonl` (operation 0), the same in run 2 and run 3:

```
HA     {"exception": "SchemaError", "error_kind": "other", "message": "needs at least one key"}, no event
HALean ok, result null, event service_registered with data {'domain': 'hw', 'service': 'v'}
```

Root cause: the decoder accepts an empty key list (`HALean/Core/ServicesJson.lean:199-204`); `probatio.AtLeastOne()`
raises at construction (`_require_keys`, `probatio/validators/conditional.py:72-77`). No other schema-construction
error of probatio is reachable from the supported spec subset (the others belong to `Alias`, `Secret`, `Self` and the
`When*` validators: `markers.py:228-244, 400-413`, `_compile.py:595-599`, `conditional.py:40-55, 205-207`).
With the patch HALean answers `{"unsupported": "at_least_one needs at least one key"}`. The case then needs the
`unsupported: true` marker to pass, which is why it is still listed in `patches/patched-cases.log`.

## Reading findings without a reproducer

* **`str()` / `repr()` of an int with more than 4300 digits.** CPython raises `ValueError` ("Exceeds the limit (4300
  digits) for integer string conversion"): `cv.string` would give "not a valid value: Exceeds the limit ..." through
  `_compile_callable` (`probatio/_compile.py:648-654`), `Coerce(str)` "expected str" (`coerce.py:83`). `pyStr`
  (`HALean/Template/Value.lean:231-242`) prints the digits. Not drivable: `json.dumps` in the harness raises the same
  `ValueError` for such an int, and no supported validator makes one (`Coerce(int)` of text stops at 4300 digits,
  `Probatio.lean:265-268`, checked in `cases/numbers.yaml`; `int(float)` has at most 309 digits).
* **Only the first leaf of a `MultipleInvalid` is observable.** `runMapping` and `runSequence` build the whole list
  (`Schema.lean:107, 182`); the driver prints the first (`multipleInvalidStr`, `Probatio.lean:224`), as `str()` does
  upstream. The order of the other leaves was read against `_engine.py:244-286, 510-650` and no difference was seen,
  but no test can see one. Which leaf comes first was exercised with several errors at once
  (`cases/structure.yaml::hw_markers_groups_defaults`, `::hw_group_default_invalid`, `::hw_error_paths`).
* **`cv.icon`.** README line 335 (right column) lists "`cv.icon` and every other `cv.*`" as rejected. The decoder accepts
  `{"cv": "icon"}` (`ServicesJson.lean:122`), and the manifest maps `config_validation.py::icon` to `cvIcon`. The
  harness builder cannot build it (`schema_spec.py:24`, the `CV` set), so a case with it stops at an `AssertionError`
  in Python. With the name added in memory, both sides agree on 13 of 15 data and HALean refuses the other two
  (non-ASCII or control characters, although `cv.icon` only looks for `:`): `logs/icon-check.log`. This is a mismatch
  between README, decoder and harness, not a wrong answer.
* **`pyIter_error`** (`ConfigValidationSpec.lean:226`) is a theorem about the model's own message. It holds, and the
  message is wrong for a `timedelta` (SCH-4).

## Notes on the harness

* **Order dependence.** `cv.time_period_dict` contains a process-wide `probatio.Schema`. After its 50th validation in the
  pytest process its answer for a huge int changes (SCH-3). The HA side of the shipped harness can therefore answer the
  same case differently depending on which cases ran before it. No shipped case has such a datum.
* **Few calls per schema.** No shipped case reaches the generated code of a service schema (README lines 650-652 say
  so). `cases/divergences.yaml::hw_sch3_coerce_float_after_50_validations` and the `warm` random file (60 schemas, 70
  calls each) do.
* **One engine process for all cases.** A case that kills the engine (SCH-1) fails with a `JSONDecodeError`, and every
  later case of the run fails with it. The two crash cases are in their own directories for that reason.
* **What JSON cannot carry**, so neither the shipped harness nor this copy can test it: NaN and infinities as data
  (`json.dumps` writes `NaN`, the engine's parser refuses it: README line 350; they were tested only as the result of
  `Coerce(float)` on `"nan"` / `"inf"`), ints of more than 4300 digits, non-string mapping keys (the `[5]` path form;
  `VErr.unsupported "a non-string mapping key"`, `Schema.lean:142`), lone surrogates (`PyJson.lean:81-85`), tuples,
  sets, `timedelta` / `datetime` values as input, dict subclasses.
* **`unsupported: true` is not checked against HA or the README.** The harness only requires HALean to refuse and skips
  HA (`tests/differential/test_services.py:197-199`). A refusal outside the documented set (SCH-5) passes a case that
  carries the marker.
* **`schema_spec.py` against the decoder.** No spec was found that the Python builder turns into a different schema
  than the one HALean decodes and accepts. The builder is looser (it ignores further keys of a validator object, takes
  any `range` bound, turns `in: "abc"` into three members); the decoder refuses those specs. The two differences that
  matter are SCH-6 and `cv.icon` (above).
* **YAML.** PyYAML reads unquoted `1e3` as a string, `1:30` as the int 90, and `on` / `off` / `yes` / `no` as booleans.
  The generator writes its cases with `yaml.safe_dump` and asserts that they load back equal (`gen/gen_random.py`).
* **Record mode** (this copy only) is described in `README.md`. The verdict per case is unchanged:
  `logs/runN-hand-strict.log` (shipped assertions) and `logs/runN-hand.log` (record mode) show the same 7 failures.
