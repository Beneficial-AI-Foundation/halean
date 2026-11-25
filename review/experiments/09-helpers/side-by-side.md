# 09-helpers: reading comparison

Upstream paths are relative to `upstream/ha-core/homeassistant/`. Lean paths are relative to
`HALean/Helpers/`. "ID" refers to `FINDINGS.md`. Every difference listed here was then driven
through the harness unless the last section of `FINDINGS.md` says otherwise.

## Shared (`Common.lean`, `Component.lean`)

| manifest entry | upstream | Lean | what differs |
|---|---|---|---|
| `helpers/config_validation.py::schema_with_slug_keys` | `helpers/config_validation.py:620-640` (`verify`: not a dict → `Invalid("expected dictionary")`; every key through `cv.slug` (602-610); then `Schema({str: value_schema})`) | `Common.lean:158` `slugKeys` | A key that is not a string is `unsupported` (Lean 168); upstream stringifies it for `cv.slug` and then fails on `{str: ...}`. JSON cannot carry such a key, so not driven. `cv.slug("")` passes on both sides; upstream then fails to add the entity `<domain>.` (invalid entity id), Lean adds it: **HLP-16**. A non-ASCII key is refused by `cvSlug` (documented, **HLP-19**). When one item is invalid the function returns only the error: the warnings that `_cv_input_select` logged for the other items are lost: **HLP-4**. |
| `helpers/config_validation.py::icon` | `helpers/config_validation.py:450` | `Common.lean:201` `vIcon` → `Core.cvIcon` | no difference found (cases `hw_m_icon_*`, `hw_it_config_bad_icon_and_name`) |
| `helpers/config_validation.py::_make_entity_service_schema` | `helpers/config_validation.py:1360-1382`, `ENTITY_SERVICE_FIELDS` 1276 | `Common.lean:227` `entityServiceFields`, `:236` `validateEntityCall` | no difference found for ASCII data (`hw_ib_service_schema`, 21 steps). Non-ASCII `entity_id` text is refused (**HLP-19**, documented). |
| `probatio:_engine.py::_MappingValidator._apply` (only the `Remove` branch) | site-packages `probatio/_engine.py` | `Common.lean:238` (filter of a dict-valued `metadata`) | no difference found (`metadata: {x: 1}` dropped, `metadata: 5` is an extra key: `hw_ib_service_schema`) |
| `helpers/service.py::_resolve_entity_service_call_entities` | `helpers/service.py:679-772` | `Common.lean:253` `targetOf`, `:272` `selectTargets`, `Component.lean:257-260` | `registered_entities` upstream is the component's own entities (`entities.values()` of that `EntityComponent`). Lean `selectTargets … .all` returns `List.range entityIds.length`: the indices of **every** entity in `Helpers.entities`, also those of the other helper domains (their id was mapped to `""` in `Component.lean:257` but `.all` does not look at it). `runService` then dispatches on the entity's type and each handler's fall-through arm runs: **HLP-1**. Missing-entity warnings (`referenced.log_missing`, 734) are not modelled (manifest note says so; logger `homeassistant.helpers.service`, not observed by the harness). |
| `helpers/service.py::_get_permissible_entity_candidates` | `helpers/service.py:632-676` | `Common.lean:272` `selectTargets` | explicit ids: set order upstream (676), given order in Lean; documented (README 569-571). Same `.all` issue as above. |
| `helpers/service.py::entity_service_call`, `::_async_handle_entity_calls` | `helpers/service.py:886-926`, `775-825` | `Component.lean:238` `Helpers.call` | no difference found for one target. With several targets the first error in entity order is raised on both sides, but upstream's order is the set order (documented). |
| `helpers/entity.py::Entity._stringify_state` | `helpers/entity.py:1069-1082` (`f"{state:.{FLOAT_PRECISION}}"`, `FLOAT_PRECISION` = 15, line 81) | `Common.lean:116` `stringifyState`, `:89` `floatPrec15`, `:68` `digits15` | no difference found. 18 formats in `hw_in_state_format` (1e15, 1e16, 5e-324, 0.30000000000000004, 1.7976931348623157e308, `-0.0`, …) and the random `input_number` cases agree. |
| `helpers/entity.py::Entity.__async_calculate_state` | `helpers/entity.py:1090-1185` (capability attrs, `extra_state_attributes`, `unit_of_measurement` if not `None`, `icon` if not `None`, `friendly_name` if truthy) | `Common.lean:126` `tailAttrs` + each `Entity.attrs` | no difference found (`name: ""` gives no `friendly_name`, `unit_of_measurement: ""` is kept: `hw_it_config_name_forms`). |
| (not in the manifest for Helpers) `core.py::StateMachine.async_set_internal` as used by `_async_write_ha_state` | `core.py:2460-2510`; over-long state → `unknown` at `core.py:2501-2508`, after `same_state` was computed | `Component.lean:96` `applyEffects` | Lean has the "nothing changed → no event" rule (lines 100-106) but not the 255-character rule: **HLP-3**. `attrsEq` (91) compares with `pyEq` or equal `repr`; fine for the attributes helpers write. |
| (not in the manifest) `helpers/entity.py` `_setter` of `CachedProperties` | `helpers/entity.py:306-318`: assigning `_attr_x = val` does nothing when the old value `== val` and has the same type | — | Not translated. Observable for `InputNumber._attr_native_value` only: `0.0 == -0.0`: **HLP-2**. |
| `helpers/entity.py::ToggleEntity.state`, `::async_toggle` | `helpers/entity.py:1779`, `1814` | `InputBoolean.lean:56`, `:71` | no difference found |
| `helpers/event.py::_TrackPointUTCTime.__call__` | `helpers/event.py:1469-1490` (run when `expected_fire_timestamp - now <= 0`) | `Timer.lean:195` `Entity.due`, `Component.lean:204` `Helpers.tick` | Due test `end ≤ now` agrees at ±1 µs (`hw_t_tick_boundaries`, `hw_t_tick_before_whole_second`). Several due timers run in entity order in Lean, in time order upstream: documented, **HLP-21**. |

`Helpers.setup` (`Component.lean:140`): a second `setup` of a domain is `unsupported` (line 143); upstream
`async_setup_component` returns `True` and changes nothing: **HLP-22**.

## input_boolean

| manifest entry | upstream (`components/input_boolean/__init__.py`) | Lean (`InputBoolean.lean`) | what differs |
|---|---|---|---|
| `async_setup` (CONFIG_SCHEMA 42-55, services 151-153) | `Any({name, initial: cv.boolean, icon}, None)` | `:27` `valueSchema`, `:36` `decodeConfig`, `:74` `services` | no difference found (`hw_ib_initial_*`, `hw_ib_value_*`, `hw_ib_config_*`). `cv.boolean` of non-ASCII text is refused (**HLP-19**). |
| `InputBoolean.__init__`, `.async_added_to_hass` (198-205) | `initial` else `last_state == "on"` | `:50` `Entity.create` | no difference found (`hw_ib_restore_states`, `hw_ib_initial_null`) |
| `.extra_state_attributes` (193) | `{editable}` | `:59` | no difference found |
| `.async_turn_on` / `.async_turn_off` | 207-217 | `:67-68`, `:78` `handle` | no difference found |

## input_number

| manifest entry | upstream (`components/input_number/__init__.py`, `components/number/__init__.py`) | Lean (`InputNumber.lean`) | what differs |
|---|---|---|---|
| `_cv_input_number` | 52-65 (message has min and max swapped) | `:58` `checkConfig` | no difference found (`hw_in_config_min_ge_max`, `…_floats`, `…_initial_*`; `repr` of floats agrees) |
| `async_setup` (CONFIG_SCHEMA 83-104, services 157-165) | `Coerce(float)`, `Range(min=1e-9)`, `In([box, slider])` | `:45` `fields`, `:67` `decode`, `:135` `services` | no difference found for ASCII input. `Coerce(float)` of a str with non-ASCII digits is refused (**HLP-19**, documented). |
| `InputNumber.__init__`, `._update_config_attributes` | 221-237 | `Config`, `:88` | no difference found |
| `.async_added_to_hass` | 263-281: `float(state.state)` under `suppress(ValueError)`, in range, else min | `:88` `Entity.create` with `Template.parseFloatStr` (`HALean/Template/Value.lean:154`) | `parseFloatStr` is not `float()` on two inputs: Unicode decimal digits (`"٤٢"` → 42.0 upstream, `none` in Lean) and padding with `\x0b`/`\x0c` (`String.trim` does not strip them): **HLP-11**. |
| `.async_set_native_value` | 284-295 | `:117` `setValue`, `:138` `handle` | The assignment is a no-op upstream when the value compares equal (`entity.py:312`): **HLP-2**. Message and `Invalid` class agree. |
| `.async_increment` / `.async_decrement` | 297-307 (`min(v + step, max)`, `max(v - step, min)`) | `:128`, `:132`, `:124` `pyMin`/`pyMax` | no difference found (NaN bounds and values, `inf` step, accumulation of 0.1: `hw_in_config_nan_bounds`, `hw_in_increment_accumulation`, `hw_in_absorbed_step`) |
| `.extra_state_attributes` | 255-260 | `:102` `Entity.attrs` | no difference found (all floats; `initial: None`) |
| `NumberEntity.capability_attributes`, `._calculate_step`, `.state` | `number/__init__.py:218-234`, `312-321`, `338` | `:102`, `:97` | no difference found (`native_step` is always set, so `_calculate_step` returns it) |

## input_select

| manifest entry | upstream (`components/input_select/__init__.py`, `components/select/__init__.py`) | Lean (`InputSelect.lean`) | what differs |
|---|---|---|---|
| `_remove_duplicates` | 68-82: `name or "<unnamed>"` | `:45` `dedup`, warning text at `:58-59` with `name.getD "<unnamed>"` | `name: ""` is falsy upstream and prints `<unnamed>`; Lean prints the empty name: **HLP-15**. |
| `_cv_input_select` | 85-94 | `:49` `decode` | no difference found (`initial` checked before deduplication: `hw_is_config_initial_duplicate`) |
| `async_setup` (CONFIG_SCHEMA 97-113, services 187-220) | | `:35` `optionsSchema`, `:37` `fields`, `:136` `services` | Warnings of valid items are lost when another item is invalid: **HLP-4** (`Common.lean:158` returns the error only; `Component.lean:167-169` emits the warnings only on success). |
| `InputSelect.__init__`, `.async_added_to_hass` | 265-271, 292-302 | `:79` `Entity.create` | no difference found (`hw_is_restore`) |
| `.async_select_option` | 311-319 | `:103` | no difference found |
| `.async_set_options` | 321-336 | `:128` | no difference found (`hw_is_set_options`, 12 steps) |
| `.extra_state_attributes`, `SelectEntity.capability_attributes`, `SelectEntity.state` | 306; `select/__init__.py:108`, `117` | `:94`, `:90` | An option longer than 255 characters: **HLP-3** (state machine rule, not this file). |
| `SelectEntity.async_first/last/next/previous`, `._async_offset_index`, `._async_select_index` | `select/__init__.py:185-240` | `:114`, `:118`, `:109` | no difference found (`hw_is_cycle`, `hw_is_single_option`). `async_next` with `current_option is None` (200-202) is not reachable for an input select. |

## input_text and the pattern subset

| manifest entry | upstream (`components/input_text/__init__.py`, `components/text/__init__.py`) | Lean | what differs |
|---|---|---|---|
| `_cv_input_text` | 71-84 | `InputText.lean:65-74` | no difference found (lengths in code points on both sides: `hw_it_length_code_points`) |
| `async_setup` (CONFIG_SCHEMA 87-110) | `lambda value: value or {}` | `InputText.lean:50` `fields`, `:65` `decode` | no difference found (`null`, `{}`, `0`, `""`, `[]` as item value: `hw_it_config_none_and_falsy`). A pattern Lean cannot parse makes the whole `setup` `unsupported` (`:77-79`); upstream fails only that entity when Python's `re` rejects the pattern: **HLP-23** (refusal, README 551). |
| `InputText.__init__`, `._update_config_attributes`, `.async_added_to_hass` | 205-218, 243-254 | `InputText.lean:96` | no difference found for the value. A non-ASCII initial or restored value with a `\d \w \s` pattern is matched with ASCII classes (no refusal as for `set_value`, `Component.lean:219`): **HLP-10**. |
| `.async_set_value` | 257-268 | `InputText.lean:140`, `:146` | no difference found |
| `.extra_state_attributes`, `TextEntity.capability_attributes`, `.min`, `.max` | 238; `text/__init__.py:122`, `170`, `184` | `InputText.lean:127`, `:106-107` | no difference found |
| `TextEntity.state` | `text/__init__.py:134-153` | `InputText.lean:111` | no difference found (messages, order of the three checks) |
| `TextEntity.pattern_cmp` (`re.compile(pattern)`, `.match`) | `text/__init__.py:196-205`, CPython `re/_parser.py` | `Pattern.lean:178` `parse`, `:196` `isMatch`, `HALean/Template/Regex.lean:34` `Rx.run` | The matcher is a backtracking matcher over the same language; `.` excludes `\n`; `$` is end or before a final `\n` (`Regex.lean:55-57`): agree (random regex × strings, 0 divergences outside the parser issues below). Parser differences: (a) a quantifier after `$` is accepted (`Pattern.lean:120-141` never looks at the atom), `re` raises "nothing to repeat": **HLP-5**; (b) `{m}`, `{m,n}`, `{,n}` where an atom is expected is read as literal text (`Pattern.lean:174`, the catch-all of `atom`), `re` raises "nothing to repeat": **HLP-6**; (c) `[\d-z]`: `classAtom` returns the class at once (`:58`) and `-z` become literals, `re` raises "bad character range": **HLP-7**; (d) a leading `]` in a set is added as a literal without looking for a range (`:83-85`), so `[]-a]` is `]`, `-`, `a` instead of the range `]`..`a`: **HLP-8**; (e) `isSpaceChar` (`:22`) lacks U+001C..U+001F, which `str.isspace()` and `\s` accept: **HLP-9**; (f) a literal `{` after a repeat (`a{2}{x`) is refused as "a repeat after a repeat" (`:145`): **HLP-17**. |

## counter

| manifest entry | upstream (`components/counter/__init__.py`) | Lean (`Counter.lean`) | what differs |
|---|---|---|---|
| `async_setup` (CONFIG_SCHEMA 71-95, services 127-134) | | `:34` `fields`, `:47` `decode`, `:118` `services` | no difference found (`hw_c_config_*`; `Coerce(int)` of `"inf"`, `1e400`: same error on both sides) |
| `Counter.__init__`, `.async_added_to_hass` | 168-171, 239-248: `int(state.state)` | `:74` `Entity.create` with `Core.pyIntOfStr?` | `" -7 "`, `"1_000"`, `"+0009"` agree. A last state with Unicode digits (`"٤٢"`) is read by `int()` upstream (42); Lean answers `unsupported` with the reason "int() raises ValueError": **HLP-12**. |
| `.compute_next_state` | 229-236 | `:67` `clamp` | no difference found (`minimum > maximum`: `hw_c_min_gt_max`) |
| `.async_increment/decrement/reset` | 250-266 | `:93-95` | no difference found |
| `.async_set_value` | 269-290 | `:99` | no difference found (order of the three checks, negative values, step 0 → `ZeroDivisionError: division by zero`) |
| `.extra_state_attributes` | 210-221 | `:83` | no difference found. A value whose decimal form is longer than 255 characters: **HLP-3**. |

## timer

| manifest entry | upstream (`components/timer/__init__.py`) | Lean (`Timer.lean`) | what differs |
|---|---|---|---|
| `_format_timedelta` | 77-81 (float `divmod`) | `:28` `formatTd` (integer µs) | no difference found, including negative values and > 24 h (`hw_t_durations_over_24h`, `hw_t_duration_negative_forms`, `hw_t_rounding_microseconds`). |
| `async_setup` (CONFIG_SCHEMA 90-109, services 157-169) | | `:55` `fields`, `:65` `decode`, `:208` `services` | no difference found for durations `timedelta` can hold. Overflowing or NaN durations are refused (**HLP-20**, documented). |
| `Timer.__init__` | 208-221 | `:76`, `:96` | no difference found |
| `.async_added_to_hass` | 287-327 | `:96` `Entity.create` | (a) `last_transition` is restored only when it is a string (`:101-103`); upstream copies any value (297-299): **HLP-14**. (b) Any last state other than `idle` is refused with the text "restoring a paused or active timer"; for e.g. `unavailable` upstream fails to add the entity (`KeyError: 'duration'` at 305): **HLP-24**. |
| `.async_start` | 330-355 | `:135` | `self._end = start + self._remaining` (349) raises `OverflowError` when the result leaves `datetime`'s range, after `_state`, `_remaining`, `_running_duration` were set; Lean has unbounded integers and writes a `finishes_at` in year 10240: **HLP-13**. Otherwise no difference found. |
| `.async_change` | 358-386 | `:148` | `self._end + duration` (366) can raise the same `OverflowError` before the two range checks; Lean reports "negative time remaining": **HLP-13**. Otherwise no difference found (`hw_t_change_matrix`). |
| `.async_pause`, `.async_cancel`, `.async_finish`, `._async_finished` | 389-450 | `:164`, `:179`, `:187`, `:199` | no difference found |
| `.extra_state_attributes`, `._fire_event_and_write_state` | 260-278, 469-478 | `:108`, `:123` | no difference found (attribute order, `restore` only when true, event after the write) |
