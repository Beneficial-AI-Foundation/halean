# 09-helpers: findings

Reviewed: `HALean/Helpers/*.lean`, `Exe/Helpers.lean` at commit `f638a377`, against Home Assistant 2026.10.4.
Engine: the unpatched `/home/user/halean/.lake/build/bin/halean-helpers`. Harness: `harness/test_helpers.py`
(shipped comparison, unchanged). The 57 shipped cases pass through the harness copy
(`logs/shipped-cases-through-copy.log`: `57 passed`).

Short answer to the question: no. For inputs the README lists as supported, 17 root causes give a result
that differs from HA without a refusal the README documents (HLP-1 … HLP-17), 2 more are refusals the
README does not name (HLP-22, HLP-24), and 6 are gaps the README documents (HLP-18 … HLP-21, HLP-23,
HLP-25). Outside these, the 213 hand-written cases and the 1620 random cases (two seeds) agree step by step.

## Counts

| what | number | log |
|---|---|---|
| new hand-written cases (`cases/*.yaml`, 9 files, names `hw_*`) | 213 (640 steps) | `logs/run1-handwritten.log` (`41 failed, 172 passed`) |
| random cases per run | 810 (80 per helper × 6, 80 with several domains, 250 regex × strings; 8053 steps with seed 101, 7849 with seed 202) | `logs/run1-gen-seed101.txt` (`seed 101: 810 cases`), `logs/run3-gen-seed202.txt` (`seed 202: 810 cases`) |
| runs | 3: run 1 (hand-written + seed 101), run 2 (same inputs again; the sha256 sums of the generated files in `logs/run2-gen-seed101.txt` equal those of run 1), run 3 (hand-written + seed 202) | `logs/run1-*.log`, `logs/run2-*.log`, `logs/run3-*.log` |
| hand-written cases that diverge | 41, the same 41 with the same outputs in the three runs | `logs/run1-handwritten.log`, `logs/run2-handwritten.log`, `logs/run3-handwritten.log` (`41 failed, 172 passed` each); per case in `logs/run<N>-handwritten.classified.txt` and `.triage.txt` |
| random cases that diverge | 1 of 810 with seed 101 (`rnd_input_select_s101_7`, runs 1 and 2), 1 of 810 with seed 202 (`rnd_input_select_s202_42`, run 3); both are HLP-4 | `logs/run1-random-seed101.log`, `logs/run2-random-seed101.log`, `logs/run3-random-seed202.log` (`1 failed, 809 passed` each), `*.classified.txt` |
| hand-written cases with a step marked `unsupported: true` (a refusal the README documents; the case passes when HALean refuses) | 19 | `logs/ha-only-documented-refusals.log` (HA's result at these steps; `19 failed` = 19 cases shown) |

The 41 divergent hand-written cases by root cause (`logs/run1-handwritten.classified.txt`, last line):
HLP-1: 3, HLP-2: 2, HLP-3: 2, HLP-4: 3, HLP-5: 3, HLP-6: 4, HLP-7: 3, HLP-8: 2, HLP-9: 1, HLP-10: 3,
HLP-11: 2, HLP-12: 1, HLP-13: 4, HLP-14: 1, HLP-15: 1, HLP-16: 1, HLP-17: 1, HLP-21: 1, HLP-22: 1,
HLP-24: 1, HLP-25: 1.

The random generator avoids, by default, the inputs of root causes that already have a hand-written
reproducer (list in the docstring of `gen/gen_random.py`). Three earlier exploratory random runs
(seeds 1, 2, 3; 730 + 1650 + 1650 cases; logs not kept) are where HLP-4 and the harness artefact of the
last section were first seen; both have reproducers here.

## Divergences

"shipped ok" = the shipped `tests/differential/test_helpers.py`, run in the throwaway copy with the patch
and a rebuilt `halean-helpers`: `57 passed` in the named log. Only `HALean/Helpers/*` is patched and only
`halean-helpers` is rebuilt, so no other shipped suite was rerun.

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| HLP-1 | `cases/misc.yaml::hw_m_all_hits_other_domains` | `input_boolean.toggle` with `entity_id: all`: only `input_boolean.x` changes; `counter.x` stays `7` | also runs on the entities of the other helper domains: `counter.x` is set to `0` | Silent | no | `patches/HLP-1.patch`; reproducers pass (`patches/HLP-1.repro.log`: `4 passed`); shipped ok (`patches/HLP-1.shipped.log`) |
| HLP-2 | `cases/input_number.yaml::hw_in_negative_zero_kept` | value `-0.0`, `set_value 0`: no event, state stays `-0.0` | `state_changed` to `0.0` | Silent | no | `patches/HLP-2.patch`; `patches/HLP-2.repro.log`: `3 passed`; shipped ok (`patches/HLP-2.shipped.log`) |
| HLP-3 | `cases/input_select.yaml::hw_is_long_option`, `cases/counter.yaml::hw_c_state_too_long` | a state longer than 255 characters is written as `unknown` | the long state is written | Silent | no (line 288 lists the rule for the core model only) | `patches/HLP-3.patch`; `patches/HLP-3.repro.log`: `2 passed`; shipped ok (`patches/HLP-3.shipped.log`) |
| HLP-4 | `cases/input_select.yaml::hw_is_dup_warning_with_invalid_sibling_icon` (also `rnd_input_select_s101_7`, `rnd_input_select_s202_42`) | config refused, and the "had duplicated options" warning of the valid item is logged (once or twice) | config refused with the same error, no warning | Silent | no | no patch (HA logs the warning once or twice depending on the error; not reduced to a rule) |
| HLP-5 | `cases/input_text_pattern.yaml::hw_pat_dollar_star_no_initial` | pattern `a$*`: `set_value` raises `PatternError: nothing to repeat at position 2`; with an `initial` the entity is not added | pattern accepted, value `a` matches and is written | Accepts | no | `patches/HLP-5.patch` makes HALean refuse the pattern (`unsupported`), as it does for other patterns Python rejects; `patches/HLP-5.repro.log`: `3 failed, 1 passed` (the 3 are now refusals); shipped ok (`patches/HLP-5.shipped.log`) |
| HLP-6 | `cases/input_text_pattern.yaml::hw_pat_brace_at_start_no_initial` | pattern `{2}`: `PatternError: nothing to repeat at position 0` | `{2}` read as three literal characters; value `{2}` is written | Accepts | no | `patches/HLP-6.patch` (refuses); `patches/HLP-6.repro.log`: `4 failed, 1 passed` (4 refusals); shipped ok (`patches/HLP-6.shipped.log`) |
| HLP-7 | `cases/input_text_pattern.yaml::hw_pat_class_escape_range_no_initial` | pattern `[\d-z]`: `PatternError: bad character range \d-z at position 1` | set read as `\d`, `-`, `z`; value `5` is written | Accepts | no | `patches/HLP-7.patch` (refuses); `patches/HLP-7.repro.log`: `3 failed, 1 passed` (3 refusals); shipped ok (`patches/HLP-7.shipped.log`) |
| HLP-8 | `cases/input_text_pattern.yaml::hw_pat_bracket_first_range` | pattern `[]-a]+$`, value `^_`: matches, written | `ValueError … does not match expected pattern` | Silent | no | `patches/HLP-8.patch`; `patches/HLP-8.repro.log`: `3 passed`; shipped ok (`patches/HLP-8.shipped.log`) |
| HLP-9 | `cases/input_text_pattern.yaml::hw_pat_space_class_fs` | pattern `a\sb`, value `a\x1cb`: matches, written | `ValueError … does not match expected pattern` | Silent | no | `patches/HLP-9.patch`; `patches/HLP-9.repro.log`: `2 passed`; shipped ok (`patches/HLP-9.shipped.log`) |
| HLP-10 | `cases/input_text_pattern.yaml::hw_pat_nonascii_initial` (also `…_restore`, `…_digit_initial`) | pattern `\w+$`, `initial: été`: entity added with state `été` | entity not added (no state), no refusal | Silent | no. Line 551 says "non-ASCII values against `\d \w \s`" are refused; that holds for `set_value` only | `patches/HLP-10.patch` (refuses, as for `set_value`); `patches/HLP-10.repro.log`: `3 failed, 1 passed` (3 refusals); shipped ok (`patches/HLP-10.shipped.log`) |
| HLP-11 | `cases/input_number.yaml::hw_in_restore_forms`, `::hw_in_restore_control_whitespace` | last state `٤٢` restores `42.0`; `"\x0c5\x0b"` restores `5.0` | both restore `min` (`0.0`) | Silent | no | `patches/HLP-11.patch` (strips `\x0b`/`\x0c`; refuses a non-ASCII last state); `patches/HLP-11.repro.log`: `1 failed, 2 passed` (1 refusal); shipped ok (`patches/HLP-11.shipped.log`) |
| HLP-12 | `cases/counter.yaml::hw_c_restore_arabic_digits` | last state `٤٢` restores `42` (`logs/ha-only-refused.log`) | refused: "the last state is not an integer (int() raises ValueError)" | Refuses | partly: line 552 lists "a last state `int()` cannot read"; `int()` reads this one | no patch |
| HLP-13 | `cases/timer.yaml::hw_t_far_future` (also `hw_t_far_future_change`, `hw_t_far_future_then_cancel`, `hw_t_far_past_start`) | `timer.start` with a duration of 3,000,000 days: `OverflowError: date value out of range`, state stays `idle` | timer `active`, `finishes_at: 10240-08-10T16:30:45+00:00` | Accepts | no | `patches/HLP-13.patch`; `patches/HLP-13.repro.log`: `4 passed`; shipped ok (`patches/HLP-13.shipped.log`) |
| HLP-14 | `cases/timer.yaml::hw_t_restore_idle_attrs` | restored `last_transition: 5` is kept (`'last_transition': 5`) | `'last_transition': None` | Silent | no | `patches/HLP-14.patch`; `patches/HLP-14.repro.log`: `1 passed`; shipped ok (`patches/HLP-14.shipped.log`) |
| HLP-15 | `cases/input_select.yaml::hw_is_config_duplicates_empty_name` | warning `Input select '<unnamed>' with options …` for `name: ""` | warning `Input select '' with options …` | Silent | no | `patches/HLP-15.patch`; `patches/HLP-15.repro.log`: `3 passed`; shipped ok (`patches/HLP-15.shipped.log`) |
| HLP-16 | `cases/input_boolean.yaml::hw_ib_slug_empty` | config key `""` accepted, no entity added | entity `input_boolean.` added with state `off` | Accepts | no | `patches/HLP-16.patch`; `patches/HLP-16.repro.log`: `6 passed`; shipped ok (`patches/HLP-16.shipped.log`) |
| HLP-17 | `cases/input_text_pattern.yaml::hw_pat_brace_literal_after_repeat` | pattern `a{2}{x`, `initial: aa{x`: entity added (`logs/ha-only-refused.log`) | refused: "a repeat after a repeat is not supported" | Refuses | no (the pattern uses only features line 551 does not exclude) | no patch |
| HLP-18 | `cases/input_text.yaml::hw_it_config_min_inf`, `::hw_it_config_min_nan` (step marked `unsupported`) | `min: .inf`: `expected int at 'input_text.a.min'` | driver refuses the request: `bad input: unexpected character I` | Tooling | yes, for the service driver: line 350 "`NaN`/`Infinity` in the input JSON" | no patch |
| HLP-19 | `cases/input_boolean.yaml::hw_ib_slug_unicode`, `cases/misc.yaml::hw_m_entity_id_non_ascii`, `::hw_m_name_non_ascii_lower`, `cases/input_number.yaml::hw_in_set_value_arabic_digit_refused` (steps marked `unsupported`) | e.g. `invalid slug é (try e) at 'input_boolean'`; `set_value "٣"` writes `3.0` | refused: "text outside printable ASCII in a value a text-handling validator reads" | Refuses | yes: line 335 "data a text-handling validator reads that is not printable ASCII" | no patch |
| HLP-20 | `cases/timer.yaml::hw_t_too_huge_duration_config`, `::hw_t_start_nan`, `::hw_t_start_big_float`, `::hw_t_service_schema` step 7 (steps marked `unsupported`) | `OverflowError` escapes the schema, or (`"nan"`) `offset nan should be format …` | refused: "timedelta(...) raises (…)" | Refuses | yes: line 335 "a `timedelta` that would overflow or be NaN" | no patch |
| HLP-21 | `cases/timer.yaml::hw_t_two_finish_same_tick` | three timers due in one tick finish in time order (b, c, a) | entity order (a, b, c) | Order | yes: line 573 "Timers finishing in the same tick finish in entity order." | no patch |
| HLP-22 | `cases/misc.yaml::hw_m_setup_twice` | second `setup` of `counter`: returns `True`, nothing changes | refused: "counter is already set up" | Refuses | no | no patch |
| HLP-23 | `cases/input_text_pattern.yaml::hw_pat_invalid_regex_ha_side` (step marked `unsupported`) | pattern `a(` on entity `a`: `a` is not added, `b` is | the whole `setup` is refused | Refuses | yes, loosely: line 551 "patterns outside the regex subset" | no patch |
| HLP-24 | `cases/timer.yaml::hw_t_restore_unknown_state` | `restore: true`, last state `unavailable`: entity not added (`logs/ha-only-refused.log`) | refused: "restoring a paused or active timer is not supported" | Refuses | partly: line 553 lists "restoring a paused or active timer" only | no patch |
| HLP-25 | `cases/extra.yaml::hw_x_nbsp_option_repr` | attributes `{'options': ['a\xa0b'], …}` (`repr` escapes U+00A0) | the character is printed unescaped | Silent | yes, for the service driver: line 349 "`repr()` of strings with non-printable non-ASCII characters" | no patch |

All patches together (`patches/ALL.patch`, 6 files): `patches/ALL.cases.log` `23 failed, 190 passed`
(the 23 are HLP-4, 5, 6, 7, 10, 11, 12, 17, 21, 22, 24, 25: unpatched or turned into refusals,
`patches/ALL.cases.classified.txt`), `patches/ALL.shipped.log` `57 passed`,
`patches/ALL.random-seed202.log` `1 failed, 809 passed` (the HLP-4 case).

## Details

Outputs are copied from `logs/run2-handwritten.triage.txt` (same text in runs 1 and 3). Attribute dicts
are shortened with `…` where they do not matter.

### HLP-1: `entity_id: all` runs the service on every helper domain's entities

```yaml
- setup: {input_boolean: {x: null}}
- setup: {counter: {x: {initial: 7}}}
- call: input_boolean.toggle
  data: {entity_id: all}
```
HA: `'outs': [['state_changed', 'input_boolean.x', 'on', "{'editable': False}"]]`, `counter.x` stays `'7'`.
HALean: `'outs': [['state_changed', 'counter.x', '0', "{'editable': False, 'initial': 7, 'step': 1}"], ['state_changed', 'input_boolean.x', 'on', "{'editable': False}"]]`.

Root cause: `Component.lean:257` maps the entities of other domains to the id `""`, but
`Common.lean:273` (`selectTargets … .all => List.range entityIds.length`) returns every index.
`runService` (`Component.lean:192`) dispatches on the entity's type, and each handler's fall-through arm
runs: `Counter.handle` treats any unknown service as `set_value` with value 0 (`Counter.lean:127-131`),
`InputBoolean.handle` as `toggle` (`InputBoolean.lean:83`), `InputText.handle` as `set_value ""`,
`InputNumber.handle` as `decrement`, `InputSelect.handle` as `select_option ""`, `Timer.handle` as `change`.
Other reproducers: `hw_m_all_timer_cancel_resets_counter` (`timer.start` on `all` sets `counter.x` to `0`
and `input_text.s` to `''`), `hw_m_all_counter_increment_toggles_boolean` (`counter.increment` on `all`
turns `input_boolean.x` on, changes `input_number.n` from `2.0` to `3.0`, and raises
`HomeAssistantError: Invalid option:  (possible options: a, b)` from the input select).
Upstream: `helpers/service.py:662-663` (`list(entities.values())` of the component's own entities).
The shipped cases never set up two domains before an `all` call.

### HLP-2: assigning an equal float does not replace `-0.0` / `0.0`

```yaml
- setup: {input_number: {a: {min: -5, max: 5, initial: -0.0}, b: {min: -5, max: 5, initial: 0}}}
- call: input_number.set_value
  data: {entity_id: input_number.a, value: 0}
```
HA: `'outs': []`, `['input_number.a', '-0.0', …]`. HALean: `'outs': [['state_changed', 'input_number.a', '0.0', …]]`.
Also `hw_in_state_format` step 11 (`set_value -0.0`, then `set_value 0`).

Root cause: `_attr_native_value` is a cached-property attribute; its setter returns without storing when
the old value `== val` and has the same type (`helpers/entity.py:312-315`). `0.0 == -0.0`. Lean
`InputNumber.lean:118` always stores the new value. The patch does the comparison in `handle`
(`InputNumber.lean:145`), not in `setValue`: a first version in `setValue` broke
`Proofs.lean:53` (`setValue_bounded`), which is proved from the stored value being the argument.

### HLP-3: a state longer than 255 characters

```yaml
- setup: {input_select: {a: {options: [short, "LLL…L (300 characters)"]}}}
- call: input_select.select_last
  data: {entity_id: input_select.a}
```
HA: `['state_changed', 'input_select.a', 'unknown', "{'options': ['short', 'LLL…'], 'editable': False}"]`.
HALean: `['state_changed', 'input_select.a', 'LLL…', "{'options': ['short', 'LLL…'], 'editable': False}"]`.
`hw_c_state_too_long`: `counter.set_value` with a 256-digit value: HA `'unknown'`, HALean the number; a
following `counter.increment` fires another `state_changed` to `unknown` in HA (the comparison with the
old state is made before the replacement).

Root cause: `core.py:2501-2508` (`if not same_state and len(new_state) > MAX_LENGTH_STATE_STATE: … new_state = STATE_UNKNOWN`).
`Component.lean:96-108` (`applyEffects`) has no such rule. README line 288 lists "over-long state → `unknown`"
for the core state machine model, which the helpers model does not use.

### HLP-4: warnings of valid items are lost when the config is refused

```yaml
- setup: {input_select: {c: {options: [a, a]}, l: {options: [b], icon: 5}}}
```
HA: `{'ok': False, 'error': 'Icons should be specified in the form "prefix:name" at \'input_select.l.icon\'', 'outs': [], 'logs': [['warning', "Input select '<unnamed>' with options ['a', 'a'] had duplicated options, the duplicates have been removed"]], 'states': []}`.
HALean: same `error`, `'logs': []`.
With the invalid item first (`hw_is_dup_warning_with_invalid_sibling_first`) HA logs the warning once; with
an extra key as the error (`hw_is_dup_warning_with_invalid_sibling_extra_key`) twice. When the duplicated
and the invalid item are the same (`hw_is_dup_and_invalid_same_item`) neither side logs: that case passes.

Root cause: `Schema({str: value_schema})` validates every item and collects errors; `_cv_input_select`
(`components/input_select/__init__.py:85-94`) logs while validating a valid item. Lean `slugKeys`
(`Common.lean:173-180`) returns only the errors, and `Helpers.setup` emits the warnings only in the `.ok`
branch (`Component.lean:167-169`).

### HLP-5: a quantifier after `$`

```yaml
- setup: {input_text: {a: {pattern: "a$*"}}}
- call: input_text.set_value
  data: {entity_id: input_text.a, value: "a"}
```
HA: `'error': {'type': 'PatternError', 'message': 'nothing to repeat at position 2'}`, state stays `unknown`.
HALean: `'error': None`, `['state_changed', 'input_text.a', 'a', "{…'pattern': 'a$*', 'editable': False}"]`.
With `initial: a` (`hw_pat_dollar_star`) HA does not add the entity, HALean adds it with state `a`.
`hw_pat_dollar_quantifiers`: the same for `a$+`, `a$?`, `a${2}`; `(a$)*` and `a$|b${x` are valid in
Python and agree.

Root cause: CPython `re/_parser.py` raises "nothing to repeat" when the repeated item is an `AT` code.
`Pattern.lean:120-141` (`quantified`) wraps whatever `atom` returned, `.eol` included.

### HLP-6: `{m}`, `{m,n}`, `{,n}` where an atom is expected

```yaml
- setup: {input_text: {a: {pattern: "{2}"}}}
- call: input_text.set_value
  data: {entity_id: input_text.a, value: "{2}"}
```
HA: `'error': {'type': 'PatternError', 'message': 'nothing to repeat at position 0'}`.
HALean: `'error': None`, state `{2}`.
`hw_pat_brace_forms_at_start`: `{,3}`, `({1,2})`, `^{2}` are not added by HA and added by HALean; `{x}`,
`{}`, `{1,2` are literals on both sides. `hw_pat_brace_after_bar`: `a|{2}`.

Root cause: `{` is in `REPEAT_CHARS`; a well-formed repeat with nothing before it is an error in
`re/_parser.py`. Lean handles `{` only after an atom (`Pattern.lean:126-140`); at the start of a sequence
it falls to the literal arm of `atom` (`Pattern.lean:174`).

### HLP-7: a class escape before `-` in a set

```yaml
- setup: {input_text: {a: {pattern: "[\\d-z]"}}}
- call: input_text.set_value
  data: {entity_id: input_text.a, value: "5"}
```
HA: `'error': {'type': 'PatternError', 'message': 'bad character range \\d-z at position 1'}`.
HALean: `'error': None`, state `5`.
`hw_pat_class_escape_dash_end`: `[\d-]` is valid on both sides; `[\w-.]` is not added by HA, added by HALean.

Root cause: `Pattern.lean:57-58` (`classAtom`) returns the class predicate at once, so the following `-z`
are read as two literals.

### HLP-8: `]` as the start of a range at the beginning of a set

```yaml
- setup: {input_text: {a: {pattern: "[]-a]+$"}}}
- call: input_text.set_value
  data: {entity_id: input_text.a, value: "^_"}
```
HA: `'error': None`, `['state_changed', 'input_text.a', '^_', …]` (the set is the range from `]` to `a`).
HALean: `'error': {'message': 'Entity input_text.a provides state ^_ which does not match expected pattern []-a]+$', 'type': 'ValueError'}`.
`hw_pat_negated_bracket_first_range`: `[^]-a]+$` with value `-`: HA writes it, HALean raises `ValueError`.

Root cause: `Pattern.lean:83-85` (`classItems`): a leading `]` is appended as a literal and the range
syntax after it is not looked at; the set becomes `]`, `-`, `a`.

### HLP-9: `\s` and U+001C..U+001F

```yaml
- setup: {input_text: {a: {pattern: "a\\sb"}}}
- call: input_text.set_value
  data: {entity_id: input_text.a, value: "a\x1cb"}
```
HA: `'error': None`, state `a\x1cb`. HALean: `'error': {'message': 'Entity input_text.a provides state a\x1cb which does not match expected pattern a\\sb', 'type': 'ValueError'}`.

Root cause: `Pattern.lean:22` (`isSpaceChar`) lists space, `\t \n \r \x0b \x0c`. Python's `\s` on `str` is
`str.isspace()`, also true for the ASCII separators `\x1c`..`\x1f`. The value is ASCII, so the refusal for
non-ASCII values (`Component.lean:219`) does not apply.

### HLP-10: non-ASCII initial or restored value against `\d \w \s`

```yaml
- setup: {input_text: {a: {pattern: "\\w+$", initial: "été"}}}
```
HA: `['state_changed', 'input_text.a', 'été', "{…'pattern': '\\\\w+$', 'editable': False}"]`.
HALean: `'ok': True, 'outs': [], 'states': []` (the entity is not added).
Same with the value in the restore cache (`hw_pat_nonascii_restore`) and with `\d+$` and `١٢`
(`hw_pat_nonascii_digit_initial`).

Root cause: the refusal "matching non-ASCII text against \d, \w or \s is not modelled"
(`Component.lean:219-230`, `unsupportedArgs`) is checked for `input_text.set_value` only. The initial
write (`Component.lean:117-124`, `InputText.lean:111-123`) matches with the ASCII classes
(`Pattern.lean:22-32`) and treats the mismatch as "entity not added".

### HLP-11: `float()` of a restored input_number state

```yaml
- setup: {input_number: {l: {min: 0, max: 100}, a: {min: 0, max: 100}}}
  restore: [[input_number.l, "٤٢", {}], [input_number.a, "\x0c5\x0b", {}]]
```
(two cases in `cases/`: `hw_in_restore_forms` entity `l`, `hw_in_restore_control_whitespace` entity `a`.)
HA: `['input_number.l', '42.0', …]`, `['input_number.a', '5.0', …]`. HALean: `'0.0'` for both.

Root cause: `InputNumber.lean:92` uses `Template.parseFloatStr` (`HALean/Template/Value.lean:154`), which
accepts ASCII digits only (`Char.isDigit`, line 175) and trims with `String.trim` (line 155: no `\x0b`,
`\x0c`). Python's `float()` (`components/input_number/__init__.py:272`) maps Unicode decimal digits and
spaces to ASCII first and skips `" \t\n\r\x0b\x0c"`.

### HLP-12: `int()` of a restored counter state with Unicode digits

```yaml
- setup: {counter: {a: {}}}
  restore: [[counter.a, "٤٢", {}]]
```
HA (`logs/ha-only-refused.log`): `['state_changed', 'counter.a', '42', "{'editable': False, 'initial': 0, 'step': 1}"]`.
HALean: `HALean rejected it: counter.a: the last state is not an integer (int() raises ValueError)`.

Root cause: `Counter.lean:76` (`pyIntOfStr?`, ASCII digits) returning `none` is reported as the README's
documented refusal (line 552), but `int("٤٢")` is 42 (`components/counter/__init__.py:248`).

### HLP-13: timers whose end leaves `datetime`'s range

```yaml
- setup: {timer: {t: {duration: {days: 3000000}}}}
- call: timer.start
  data: {entity_id: timer.t}
```
HA: `'error': {'type': 'OverflowError', 'message': 'date value out of range'}, 'outs': []`, state `idle`.
HALean: `'error': None`, `['state_changed', 'timer.t', 'active', "{'duration': '72000000:00:00', 'editable': False, 'last_transition': 'started', 'finishes_at': '10240-08-10T16:30:45+00:00', 'remaining': '72000000:00:00'}"], ['event', 'timer.started', "{'entity_id': 'timer.t'}"]`.
`hw_t_far_past_start` (`start` with `{days: -800000}`): HA the same `OverflowError`; HALean starts and
finishes the timer with `finished_at: '-164-07-24T16:30:45+00:00'`.
`hw_t_far_future_change` (`change` by `{days: -800000}` on an active timer): HA `OverflowError`, HALean
`HomeAssistantError: Not possible to change timer timer.t to negative time remaining`.
`hw_t_far_future_then_cancel`: after the failed start the entity object is active in HA (line 340 ran),
so a following `timer.cancel` fires `timer.cancelled`; the patch models this and the case passes with it.

Root cause: `components/timer/__init__.py:349` (`self._end = start + self._remaining`) and `:366`
(`self._end + duration`) are `datetime` arithmetic; `Timer.lean:144` and `:154` are unbounded `Int`
arithmetic, and `isoformat` prints years outside 1..9999.

### HLP-14: restored `last_transition` that is not a string

```yaml
- setup: {timer: {a: {restore: true, duration: 5}}}
  restore: [[timer.a, "idle", {last_transition: 5, duration: "0:10:00"}]]
```
HA: `"{'duration': '0:00:05', 'editable': False, 'last_transition': 5, 'restore': True}"`.
HALean: `"{'duration': '0:00:05', 'editable': False, 'last_transition': None, 'restore': True}"`.
Root cause: `Timer.lean:101-103` keeps the attribute only when it is a `.str`; upstream copies it
(`components/timer/__init__.py:297-299`).

### HLP-15: `<unnamed>` for an empty name

```yaml
- setup: {input_select: {a: {options: [a, a], name: ""}}}
```
HA: `['warning', "Input select '<unnamed>' with options ['a', 'a'] had duplicated options, the duplicates have been removed"]`.
HALean: `['warning', "Input select '' with options ['a', 'a'] had duplicated options, the duplicates have been removed"]`.
Root cause: `name or "<unnamed>"` (`components/input_select/__init__.py:79`) against `name.getD "<unnamed>"`
(`InputSelect.lean:59`).

### HLP-16: an empty config key

```yaml
- setup: {input_boolean: {"": null}}
```
HA: `{'ok': True, 'outs': [], 'logs': [], 'states': []}`. HALean: `'outs': [['state_changed', 'input_boolean.', 'off', "{'editable': False}"]]`.
Root cause: `cv.slug("")` passes (`helpers/config_validation.py:602-610`); the entity id `input_boolean.`
is invalid and HA fails to add the entity. `Helpers.setup` (`Component.lean:172-182`) adds every entity
whose first write does not raise.

### HLP-17: a literal `{` after a repeat is refused

```yaml
- setup: {input_text: {a: {pattern: "a{2}{x", initial: "aa{x"}}}
```
HA (`logs/ha-only-refused.log`): `['state_changed', 'input_text.a', 'aa{x', "{…'pattern': 'a{2}{x', 'editable': False}"]`.
HALean: `HALean rejected it: the pattern 'a{2}{x' is outside the modelled regex subset (a repeat after a repeat is not supported)`.
Root cause: `Pattern.lean:145` refuses any `{` after a repeat without checking that it starts a repeat.

### HLP-18: non-finite floats in the request (Tooling)

`{input_text: {a: {min: .inf}}}`: the harness sends `Infinity` (Python's `json.dumps`), the driver answers
`bad input: unexpected character I`. HA (`logs/ha-only-documented-refusals.log`): `expected int at 'input_text.a.min'`.
`parsePyJson` (`Exe/Helpers.lean:102`). The strings `"inf"`, `"nan"` go through and agree
(`hw_in_config_nan_bounds`, `hw_c_set_value_inf`).

### HLP-19, HLP-20, HLP-23: documented refusals

HA's results at the refused steps are in `logs/ha-only-documented-refusals.log`:
`{input_boolean: {"é": null}}` → `invalid slug é (try e) at 'input_boolean'`;
`entity_id: "counter.é"` → `MultipleInvalid: expected 'all' or 'none' at 'entity_id'`;
`initial: "ÖN"` → `invalid boolean value ön at 'input_boolean.a.initial'`;
`input_number.set_value` with `"٣"` → state `3.0`;
`timer.start` with `duration: {days: 1000000000}` → `OverflowError: days=1000000000; must have magnitude <= 999999999`;
`duration: "nan"` → `MultipleInvalid: offset nan should be format 'HH:MM', 'HH:MM:SS' or 'HH:MM:SS.F' at 'duration'`
(HALean's reason, "timedelta(...) raises (ValueError: cannot convert float NaN to integer)", is not what
HA reports here: one branch of `cv.time_period` fails that way and the schema reports another branch);
`duration: "1e300"` → `OverflowError: Python int too large to convert to C int`;
pattern `a(` with `initial: a` → only the other entity is added.

### HLP-21: timers due in the same tick (documented)

`hw_t_two_finish_same_tick`: timers a (5 s), c (4 s), b (3 s) started, then `advance: 10`.
HA `outs`: `timer.b` (finished_at 16:30:48), `timer.c` (16:30:49), `timer.a` (16:30:50).
HALean `outs`: `timer.a`, `timer.b`, `timer.c`. `Component.lean:204-216`.

### HLP-22: a second `setup` of a domain

```yaml
- setup: {counter: {a: {initial: 1}}}
- setup: {counter: {b: {initial: 2}}}
```
HA (`logs/ha-only-refused.log`): `{'ok': True, 'outs': [], 'logs': [], 'states': [['counter.a', '1', …]]}`.
HALean: `HALean rejected it: counter is already set up` (`Component.lean:143`).

### HLP-24: restoring a timer whose last state is not `idle`, `paused` or `active`

```yaml
- setup: {timer: {a: {restore: true}}}
  restore: [[timer.a, "unavailable", {}]]
```
HA (`logs/ha-only-refused.log`): `{'ok': True, 'outs': [], 'logs': [], 'states': []}` (the entity is not
added: `state.attributes[DURATION]` at `components/timer/__init__.py:305-307` raises).
HALean: `HALean rejected it: timer.a: restoring a paused or active timer is not supported` (`Timer.lean:104`).

### HLP-25: `repr()` of a non-printable non-ASCII character (documented)

`{input_select: {a: {options: ["a b"]}}}`: HA `"{'options': ['a\\xa0b'], 'editable': False}"`,
HALean `"{'options': ['a\xa0b'], 'editable': False}"` (the character itself). `Exe/Helpers.lean:28` (`pyRepr`).

## Reading findings without a reproducer

* **Non-string config keys** (`Common.lean:168`): `unsupported`. Upstream `cv.slug` stringifies the key and
  `Schema({str: …})` then refuses it. The JSON request cannot carry a non-string key (Python's `json.dumps`
  turns `1` into `"1"`), so the harness cannot send one.
* **Missing-entity warning** (`helpers/service.py:734`, `referenced.log_missing`): not modelled (the
  manifest says so). The record is logged by `homeassistant.helpers.service`; the harness keeps only the
  warnings of `homeassistant.components.<helper>`.
* **Error-level records**: `Helpers.setup` writes `Error adding entity … for domain … with platform …`
  (`Component.lean:182`) when a first write raises; HA logs with `_LOGGER.exception`. The harness compares
  warnings only (`lean["logs"]` is filtered to `warning`), so the text is never compared. The same holds
  for the `State … is longer than 255` error of HLP-3.
* **Setup after a failed setup**: HA's `async_setup_component` returns `False` again for a domain whose
  first setup failed; HALean sets the domain up. The harness asserts `ok == ha["ok"]` before it compares
  with HALean and stops there (`gen/artefacts/setup_retry.yaml`, `logs/artefact-run1.log`:
  `async_setup_component returned False`). A real HA reads its config once, so this is a property of the
  harness sequence; it is not listed as a divergence.
* **HLP-5/6/7 patches**: they refuse the pattern. A full fix would keep the entity, leave it out when it
  has a value at setup, and raise `PatternError` with Python's message and position at the first write of
  a value. That needs positions in `Pattern.parse`; not done.
* **Several targets, two errors**: HA raises the first error in `set` order (documented, README 571);
  the random generator uses lists only for services that cannot raise.
* **`Proofs.lean`**: `InputNumber.setValue_bounded` (`Proofs.lean:53`) is about `setValue`. With upstream's
  "equal value is not stored" rule (HLP-2) what is stored after `set_value 0.0` can be `-0.0`; the theorem
  does not cover the stored value once that rule is added in `handle`.

## Notes on the harness

* **Frozen event-loop clock and a zero-duration timer on a whole second** (artefact, not a divergence).
  `gen/artefacts/whole_second_zero_timer.yaml`: after `advance: 0.876544` the clock is exactly
  16:30:46.000000; `timer.start` with a zero duration gives `finishes_at` equal to now. HALean finishes
  the timer in the same step. HA under the harness leaves it `active` until the next `advance`
  (`logs/artefact-run1.log`, `logs/artefact-run2.log`: `artefact_zero_timer_on_whole_second` fails,
  the control case with `advance: 0.876545` passes). HA schedules the callback with
  `loop.call_at(loop.time() + end.timestamp() - time.time())` (`helpers/event.py`, `_TrackPointUTCTime`).
  My reading, not verified by instrumenting the loop: with the clock frozen the float sum lands just after
  `loop.time()` and the handle does not become ready. On a running HA the clock moves and the callback
  runs. The generator avoids this clock value.
* **Non-finite floats** cannot be sent (HLP-18).
* **A refused step ends the case** (`unsupported` is checked before HA runs), so HA's behaviour at a
  refused step is not recorded by the harness. `gen/stub/halean-helpers` was used to record it
  (`logs/ha-only-refused.log`, `logs/ha-only-documented-refusals.log`).
* **Config errors that are not `probatio.Invalid`** (`OverflowError` from `timedelta`) make the harness
  itself fail (`logs/ha-only-documented-refusals.log`, `hw_t_too_huge_duration_config`:
  `OverflowError: days=1000000000; must have magnitude <= 999999999`).
* **Order of several targets**: the harness sorts `outs` when `entity_id` is a list of two or more or
  `all`. A comma-separated string (`"counter.a,counter.b"`) is not sorted and would compare HA's set order.
* **Only warnings** of the six component loggers are compared; errors and other loggers are not (above).
* **`async_setup_component` is preceded by a direct `CONFIG_SCHEMA` call** in the harness; the warnings of
  that call are cleared, the ones compared come from HA's own validation during setup (once or twice, HLP-4).
