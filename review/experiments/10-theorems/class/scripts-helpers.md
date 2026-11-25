# scripts-helpers: what the theorems say

Modules: `HALean.Script.ConfigSpec` (23), `HALean.Script.EntitySpec` (48), `HALean.Script.Proofs` (5),
`HALean.Script.ProtocolSpec` (17), `HALean.Script.ServiceSpec` (17), `HALean.Helpers.Proofs` (25). Total 135.

Classes (from `scripts-helpers.tsv`): C 5, O 90, E 8, H 32.

| module | C | O | E | H |
|---|---|---|---|---|
| Script.ConfigSpec | 2 | 11 | 1 | 9 |
| Script.EntitySpec | 2 | 33 | 3 | 10 |
| Script.Proofs | 1 | 3 | 1 | 0 |
| Script.ProtocolSpec | 0 | 10 | 3 | 4 |
| Script.ServiceSpec | 0 | 11 | 0 | 6 |
| Helpers.Proofs | 0 | 22 | 0 | 3 |

The five `C` theorems: `cvString_ok_iff`, `isSlug_iff`, `extractTargets_ok_iff`, `callResponse_true_iff`,
`supportsMax_iff`.

No theorem of these modules is used by a theorem outside them (grep over `HALean/`).

## What the theorems constrain

### `HALean/Script/Config.lean` (`script/config.py`)

* `cvString` (`cv.string`, restricted to strings and numbers): `cvString_ok_iff` (C) fixes when it is `ok` and
  the value.
* `isSlug` (`cv.slug` on the object id): `isSlug_iff` (C) says it holds exactly for `ValidSlug` texts.
  `isSlug_valid` (O) is its forward half.
* `decodeFields`: `decodeFields_ok` (O) gives necessary conditions for acceptance (names = mapping keys in
  order, each field a mapping, keys in `FIELD_KEYS`). It does not state the per-key type checks.
* `decodeScript`: `decodeScript_ok` (O) gives necessary conditions for acceptance: slug key, not reserved,
  mapping with keys in `SCRIPT_KEYS`, no `use_blueprint`, `sequence` present and `checkActions` ok;
  `objectId`, `entityId`, `alive`, `raw`; icon has `:` and is `none` without `icon:`; `id`, `triggers = []`,
  `conditions = []`, `entityId`, `uniqueId`; alias non-empty and equal to the key without `alias:`;
  `maxRuns ≥ 2`, 10 without `max:`; mode. Six rejection theorems follow from it: `decodeScript_not_slug`,
  `_reserved`, `_not_mapping`, `_extra_key`, `_blueprint`, `_no_sequence` (all O).
  `decodeScript_not_domain_service` (O).
* `decodeAll` (defined in `Service.lean`): `decodeAll_ok` (O), `decodeAll_keys` (O), `decodeAll_mem` (O).

### `HALean/Script/Entity.lean` (`script/__init__.py`, parts of `helpers/service.py`)

* `entityAttributes`: seven O theorems (`entityAttributes_mode`, `_current`, `_max`, `_icon`,
  `_friendly_name`, `_last_triggered`, `_keys`). Together they fix `field?` of the result for every key.
  They do not fix the key order of the JSON object (the object is a tree map, so order is by key).
* `unavailableAttributes`: `unavailableAttributes_restored`, `_keeps`, `_keys` (O). Together with the
  `entityAttributes` theorems they fix `field?` for every key.
* `entityState`: `entityState_off` and `entityState_on` (both O). Together they fix the result for every count.
* `supportsMax`: `supportsMax_iff` (C).
* `scriptThis`: `scriptThis_state`, `scriptThis_attributes` (O). Membership facts only: `entity_id`, `state`,
  `attributes` with `mode`, `current`, `friendly_name`, `last_triggered`, `last_action` iff `c > 0`, `max` iff
  supported, `icon`. Nothing on `last_changed`, `last_reported`, `last_updated`, `context`, on order, or on the
  value of `max`.
* `compEntityIds` (`cv.comp_entity_ids`): `compEntityIds_all`, `_none` (E), `_arr`, `_other`, `_valid` (O). No
  theorem says which strings are accepted or what the accepted ids are (trim, lower-case, split on `,`); only
  that each accepted id matches `EntityIdRe`.
* `normalizeTargetIds`: `normalizeTargetIds_not_obj` (E), `normalizeTargetIds_other` (O). Nothing about the
  five target keys, which is the part that changes values.
* `extractTargets` (`async_extract_entities`): `extractTargets_ok_iff` (C) fixes when it is `ok` and the list.
  Consequences: `extractTargets_all`, `_named`, `_live_sorted`, `_no_entity_id`, `_registry_target`, `_group` (O).
* `planCall` (service handlers): `planCall_domain` and its three instances `planCall_turn_on`, `_turn_off`,
  `_toggle` (O) say the result is one of: one `invalid` failure, one `other` failure with the extraction error,
  or the map of a stated function over the extracted targets. `planCall_turn_on_ops`, `_turn_off_ops`,
  `planCall_domain_isSome`, `planCall_response_refused`, `planCall_script`, `planCall_none_iff` (O).
* `callResponse`: `callResponse_true_iff` (C, for `returnResponse = true`), `callResponse_no_response` (E,
  for `false`), `callResponse_dict` (O). The two first fix the `ok` results for both values of the flag.

### `HALean/Script/Service.lean`

* `Service.step`, input `engine`: `Service.step_owned_echo` and `Service.step_engine` (O) reduce it to
  `Engine.step`. Both unfold the definition.
* `Service.step`, other inputs: `Service.step_engine_call_frame`, `step_reload_configs`,
  `step_reload_rejected`, `step_init` (O) fix the `restored`, `automationConfigs` and rejected-list parts.
* `addScripts`: `addScripts_aligned` (O), under `e.scripts.length ≤ e.automations.length`.
* `lastTriggeredOf`: `lastTriggeredOf_some` (O).
* `writeEntity` (in `Automation/Engine.lean`): `writeEntity_frame` (O).
* `stoppedQuietly` (in `Automation/Engine.lean`): `stopped_nested_cancels` (O).

### `HALean/Script/Protocol.lean`

* `decodeScripts`: `decodeScripts_pairs`, `_arr_ok` (O), `_null`, `_obj`, `_scalar` (E). Together they fix the
  result for every JSON constructor, up to the error text.
* `decodeInput`: `decodeInput_no_type`, `_no_now`, `_call_no_service`, `_reload` (O).
* `processLine`: `processLine_error`, `_error_output`, `_ok`, `_ok_output` (O).

### `HALean/Helpers/*.lean`: the 25 theorems, by helper and service

The implementation files have 1,655 lines (`wc -l`, comments included). `Helpers/Proofs.lean` has 242.

| helper | theorem | about (Lean function = upstream method/service) | class |
|---|---|---|---|
| input_boolean | `toggle_toggle` | `toggle` = `toggle` service method (`ToggleEntity.async_toggle`) | O |
| input_boolean | `state_toggle` | `toggle` and `Entity.state` | O |
| input_boolean | `turnOn_idem`, `state_turnOn` | `turnOn` = `turn_on` | O, O |
| input_boolean | `turnOff_idem`, `state_turnOff` | `turnOff` = `turn_off` | O, O |
| input_number | `setValue_bounded`, `setValue_error` | `setValue` = `set_value` (`async_set_native_value`) | O, O |
| input_number | `increment_bounded` | `increment` = `increment` | O |
| input_number | `decrement_bounded` | `decrement` = `decrement` | O |
| input_select | `selectOption_valid` | `selectOption` = `select_option` | O |
| input_select | `selectIndex_valid` | `selectIndex` = `select_first`, `select_last` (`_async_select_index`) | O |
| input_select | `offsetIndex_valid` | `offsetIndex` = `select_next`, `select_previous` (`_async_offset_index`) | O |
| input_select | `setOptions_valid` | `setOptions` = `set_options` | O |
| input_select | `create_valid` | `Entity.create` = `__init__` + `async_added_to_hass` (no service) | O |
| input_select | `state_of_valid` | `Entity.state` = `SelectEntity.state` (no service) | O |
| counter | `clamp_le_max`, `min_le_clamp` | `clamp` = `compute_next_state` (no service) | O, O |
| counter | `clamp_inBounds` | lemma for the next three | H |
| counter | `increment_inBounds` | `increment` = `increment` | O |
| counter | `decrement_inBounds` | `decrement` = `decrement` | O |
| counter | `reset_inBounds` | `reset` = `reset` | O |
| counter | `setValue_inBounds` | `setValue` = `set_value` | O |
| timer | `toIdle_idle`, `toIdle_not_due` | `toIdle`, an internal record update shared by `cancel`, `finish`, `finished`; and `Entity.due` | H, H |

Helpers with no theorem:

* `input_text` (`InputText.lean`, 153 lines) and its regex parser and matcher (`Pattern.lean`, 198 lines): none.
* `timer`: no theorem mentions a service. `start`, `change`, `pause`, `cancel`, `finish`, `finished`, `handle`,
  `fireAndWrite`, `formatTd`, `nowSec`, `decode`, `Entity.create` have no theorem. The two timer theorems are
  about `toIdle` only.
* `Common.lean` (277 lines) and `Component.lean` (274 lines): none.

What the 22 O theorems fix:

* input_boolean: `toggle` is an involution and flips `state`; `turnOn`/`turnOff` are idempotent and give
  state `on`/`off`. No statement that `cfg` is kept by `turnOn`/`turnOff`.
* input_number: a successful `setValue`/`increment`/`decrement` gives a value with `¬ (v < min) ∧ ¬ (v > max)`
  and the same config; `setValue` fails with exception `"Invalid"` when `v < min ∨ v > max`.
* input_select: a successful `selectOption`/`selectIndex`/`offsetIndex` gives `current ∈ options` and the same
  options; `setOptions` with a non-empty list gives `current ∈ opts`; `create` gives `current ∈ options` under
  two hypotheses; then `state = current`.
* counter: `clamp ≤ maximum`; `minimum ≤ clamp` if `minimum ≤ maximum`; `increment`/`decrement`/`reset` end
  within the set bounds if `minimum ≤ maximum`; a successful `setValue` gives `{e with value := v}` within bounds.

## What they do not constrain

### Definitions no `C`/`O` theorem mentions (from `logs/theorems.tsv`, column 9, against `logs/defs.tsv`)

* `Script/Config.lean`: `objects` (partial), `actionName`, `checkAttributes`, `passedNames` (the last three
  only in H theorems). `checkActions` appears only as the conjunct `checkActions seq = .ok ()` of
  `decodeScript_ok`; no theorem says what it accepts.
* `Script/Service.lean`: `reloadScripts` (no theorem at all), `unsupportedCmds` (one H theorem; the function
  is not called anywhere in `HALean/` or `Exe/`).
* `Script/Entity.lean`, `Script/Protocol.lean`: every definition is mentioned by some C/O theorem.
* `Helpers/Common.lean`: all 32 definitions except the abbreviation `PyErr`: `slugKeys`, `runDict`,
  `validateEntityCall`, `entityServiceFields`, `compEntityIds`, `idList`, `targetOf`, `serviceArgs`,
  `selectTargets`, `stringifyState`, `floatPrec15`, `digits15`, `tailAttrs`, `HM.exec`, `emit`, `getEnt`,
  `setEnt`, `raise`, `withPath`, `ConfigError.ofVErr`, and the small ones.
* `Helpers/Component.lean`: all 14: `Helpers.setup`, `Helpers.call`, `Helpers.tick`, `applyEffects`,
  `attrsEq`, `initialWrite`, `runService`, `runOn`, `unsupportedArgs`, `servicesOf`, `DOMAINS`, `Ent.domain`,
  `Ent.entityId`, `Written`.
* `Helpers/Counter.lean`: `decode`, `decodeConfig`, `fields`, `positiveInt`, `optInt`, `Entity.create`,
  `Entity.state`, `Entity.attrs`, `Entity.entityId`, `write`, `services`, `handle`.
* `Helpers/InputBoolean.lean`: `valueSchema`, `decode`, `decodeConfig`, `Entity.create`, `Entity.attrs`,
  `Entity.entityId`, `write`, `services`, `handle`.
* `Helpers/InputNumber.lean`: `checkConfig`, `decode`, `decodeConfig`, `fields`, `fl`, `STEP_MIN`,
  `Entity.create`, `Entity.state`, `Entity.attrs`, `Entity.entityId`, `inRange`, `pyMin`, `pyMax`, `write`,
  `services`, `handle`, `Mode.str`.
* `Helpers/InputSelect.lean`: `decode`, `decodeConfig`, `fields`, `optionsSchema`, `strList`, `dedup`, `atMod`,
  `Entity.attrs`, `Entity.entityId`, `write`, `services`, `handle`.
* `Helpers/InputText.lean`: all 17 definitions.
* `Helpers/Pattern.lean`: all 18 definitions.
* `Helpers/Timer.lean`: all 24 definitions (`toIdle` and `Entity.due` only in H theorems).

### (a) Partial defs

In the implementation files of this area: `Script.objects` and six in `Helpers/Pattern.lean`
(`classItems`, `parseNat`, `alternation`, `sequence`, `quantified`, `atom`).

* No theorem statement of this area names a partial def (column 9 of `theorems.tsv`).
* `objects` is reached through `checkActions` and `passedNames`.
  `decodeScript_ok` states `checkActions seq = .ok ()`. Since `objects` is opaque, this conjunct only repeats
  that the check returned ok. It cannot mean "no action in the sequence is `script.reload`" or any other
  property of the actions.
  `passedNames_append`, `passedNames_subset` (H) hold for any function in place of `objects`.
  `decodeAll_ok`, `decodeAll_keys`, `decodeAll_mem` mention `decodeAll`, which calls `passedNames`; their
  conclusions do not depend on it.
* `decodeScript` calls `decodeAction`, `decodeComplex`, `actionVariableNames` (partial, in
  `Automation/Config.lean`). `decodeScript_ok` says nothing about `a.actions` or `a.variables`, the two
  fields these produce. The actions a script runs are not constrained by any theorem here.
* `Pattern.parse` (a `def`) calls the partial `alternation`. No theorem mentions `parse` or `isMatch`.
* `Helpers.digits15` uses `while` loops (Lean's `Loop.forIn`, a partial function). `floatPrec15`, hence
  `InputNumber.Entity.state`, depends on it. No theorem mentions them.
* The helper config decoders (`decode` of each helper, `InputBoolean.valueSchema.run`) go through
  `Core.runMapping` and `Core.Validator.run`, both partial (`defs.tsv`). No theorem of this area mentions
  a helper `decode`.

### (b) JSON decoders, protocol drivers, parsers

* `Script.decodeScript`: necessary conditions only (`decodeScript_ok`). No sufficient condition: no theorem
  shows that any config is accepted. The checks on `description`, `trace`, `stored_traces`, `fields` contents,
  `variables`, `checkAttributes`, and the decoded actions do not appear in a statement. The alias value when
  `alias:` is present, the icon value, and `maxRuns` when `max:` is present (other than `≥ 2`) are not fixed.
* `Script.decodeInput`: three rejection theorems and the `reload` case. Nothing on `init`, on `call` when it
  succeeds (`call_id`, `data` default, `return_response` default), or on the fall-through to
  `Automation.decodeInput`.
* `Script.decodeScripts`: fixed for every constructor (see above). It has no upstream counterpart.
* `Script.processLine`: the new service equals `sv` or `(sv.step i).1`; the output has `type` and, for a
  batch, a `cmds` array of the stated length. The contents and order of `cmds` are not stated.
* `Helpers`: the JSON driver is `Exe/Helpers.lean` (`step`, `decodeRestore`, `parsePyJson`), outside this
  area; no theorem of this area mentions it. `slugKeys`, `runDict`, `validateEntityCall`, `targetOf`,
  `selectTargets`: no theorem.
* `Helpers.Pattern.parse` (regex parser) and `Pattern.isMatch`: no theorem.

### (c) Entry points

* `Script.Service.step`: there are theorems about the entry point itself, but only for these parts:
  the `engine` input (reduced to `Engine.step`); the `restored`, `automationConfigs` and rejected components
  for the other inputs. No theorem says anything about the engine state or the commands after `init`, `call`
  or `reload`. No theorem connects `Service.step (.call ..)` to `planCall`: the `planCall_*` theorems are about
  the pure planner, and the step function's use of it (`callLocal`, `resumeWoken`, the `ha_error` branch for
  `return_response`) is not in any statement. `reloadScripts` has no theorem. `addScripts_aligned` is not
  applied to `Service.step` by any theorem.
* `Script.processLine`: four O theorems, conditional on the decode result (see (b)).
* `Helpers.Helpers.setup`, `Helpers.call`, `Helpers.tick`: no theorem. Each helper's `handle` (the function
  that maps a service name to the method and writes the state): no theorem. All 22 helper O theorems are
  about single entity methods. Nothing states that a property survives a `Helpers.call`.

## Assumptions that nothing checks

Hypotheses not discharged for run-time values:

| theorem | hypothesis | where the value comes from | discharged by a theorem? |
|---|---|---|---|
| `Counter.increment_inBounds`, `decrement_inBounds`, `reset_inBounds`, `clamp_inBounds`, `min_le_clamp` | `e.cfg.Consistent` (`minimum ≤ maximum` when both set) | `Counter.decode` (through partial `runMapping`). Neither upstream nor `decode` checks it: `minimum: 10, maximum: 5` is accepted. | No, and it is false for some accepted configs. |
| `InputSelect.create_valid` | `cfg.options ≠ []`; `initial ∈ cfg.options` | `InputSelect.decode` (`optionsSchema` length check, `strList`, `dedup`) | No. The docstring says "what `decode` returns"; no theorem about `decode`. |
| `InputSelect.setOptions_valid` | `opts ≠ []` | `strList (lk args "options")` after `validateEntityCall` in `handle` | No. `strList` also drops non-string items. |
| `InputSelect.state_of_valid` | `e.Valid` | entity after `setup` and any calls | No chain: no theorem says `Helpers.setup` creates valid entities or that `handle`/`Helpers.call` keep `Valid`. |
| `InputNumber.*_bounded` (conclusion `Bounded`) | none, but `Bounded` of the initial entity is not proved | `InputNumber.Entity.create` | No theorem about `create` or `checkConfig`. `InputNumber.lean` header says "The value is never strictly below `min` nor strictly above `max` (`Proofs.lean`)"; `Proofs.lean` proves it only after a successful service method. |
| `addScripts_aligned` | `e.scripts.length ≤ e.automations.length` | the engine before `addScripts`: the fresh `e0` at `init` (both lists empty), the engine after earlier steps at `reload` | No. No theorem states it for `e0`, or that `Service.step`/`Engine.step` keep it. |
| `processLine_ok`, `processLine_ok_output`, `processLine_error`, `processLine_error_output` | `Json.parse line >>= decodeInput = .ok i` (or `.error err`) | Lean core's JSON parser and `decodeInput` (which for `init` calls `Automation.decodeInput` and the partial action decoders) | Conditional by design. Nothing says which lines decode. |
| `decodeInput_reload` | `decodeInstant j = .ok now`, `decodeScripts .. = .ok scripts` | the message from the Python bridge | Conditional by design. |
| `decodeScripts_pairs` | the input is exactly `.arr (pairs.map ..)` | `bridge/protocol.py::protocol_scripts`, then `Json.parse` | No theorem about the bridge or the parser. |
| `entityAttributes_*`, `scriptThis_*` | the arguments `c` ("number of runs") and `lt` | `writeEntity` passes `(runsOf e ai).length` and a lookup in `lastTriggered` | Not in this area's theorems. |
| `planCall_*` | `running : Nat → Bool` is arbitrary | `Service.step` passes `fun i => !(runsOf e i).isEmpty` | No theorem about that call site. |
| `decodeScript_ok`, `decodeFields_ok`, `decodeAll_ok` | "decoder returned ok" | the config | Conditional by design; no acceptance theorem exists. |

Theorems that are weaker than they read, or restate the definition:

* `InputNumber.increment_bounded`, `decrement_bounded`: proof term `setValue_bounded h`. They hold for any
  value passed to `setValue`. They say nothing about `pyMin (value + step) max` or `pyMax (value - step) min`.
* `InputSelect.selectIndex_valid`, `offsetIndex_valid`: proof term `selectOption_valid h`. They hold for any
  option passed to `selectOption`. They say nothing about which option `select_first`, `select_last`,
  `select_next`, `select_previous` pick (`atMod`, the offset arithmetic, `cycle`).
* `InputSelect.selectOption_valid`: does not state `e'.current = o`.
* `InputNumber.setValue_bounded`: does not state `e'.value = v`. No theorem says an in-range value is accepted.
* `Counter.increment_inBounds`, `decrement_inBounds`, `reset_inBounds`: proof term `clamp_inBounds e hc _`.
  They hold for any argument of `clamp`. They say nothing about `+ step`, `- step`, `initial`.
* `Counter.setValue_inBounds`: the step check (multiple of `step`, `step = 0`) is not in the statement.
* `InputBoolean.turnOn_idem`, `turnOff_idem`, `state_turnOn`, `state_turnOff`: `rfl`; restate the definition.
* `Timer.toIdle_idle`, `toIdle_not_due`: `rfl`; restate the definition of `toIdle` (five of its fields).
  They are not about `cancel`, `finish` or `finished`.
* `decodeScripts_null`, `addScripts_nil`: `rfl`. `decodeScripts_obj`, `decodeInput_no_type`,
  `processLine_error`, `processLine_ok`, `Service.owns_iff`, `Service.step_owned_echo`, `Service.step_engine`,
  `decodeAll_keys`, `callResponse_no_response`, `supportsMax_iff`, `checkAttributes_ok_iff`,
  `actionName_eq_some_iff`: one `simp`/unfold of the definition; they restate it.
* `decodeAll_mem`: `extra` is existentially quantified. The statement does not say it is `passedNames` of
  anything; any list satisfies the shape.
* `unsupportedCmds_spec`: about a function nothing calls. `Service.step` returns the rejected list and
  `processLine` builds the `unsupported` objects itself.
* `decodeScript_not_domain_service`: its docstring gives "so `planCall`'s two branches cannot collide" as the
  use. `planCall` tests the three domain names first, so the branches cannot collide whatever the object ids are.
* `planCall_script`: does not say which live script is started when two have the same object id.
* `isSlug_iff`: relative to `slugify?`; see the docstring section for the empty string.
* `passedNames_subset`: immediate from `passedNames_append`.
* No theorem with contradictory hypotheses or a `True` conclusion was found.

## Specifications independent of the code?

Five `C` theorems.

| theorem | right-hand side | kind |
|---|---|---|
| `isSlug_iff` | `ValidSlug`, a predicate written in `Automation/SlugifySpec.lean` (non-empty, `[0-9a-z_]`, no `_` at the ends, no `__`) | independent |
| `cvString_ok_iff` | `j = .str s ∨ ∃ n, j = .num n ∧ s = toString n`: the two accepting branches of the `match` | restatement |
| `extractTargets_ok_iff` | the same `match` on `field? data "entity_id"` with `compEntityIds`, the same `zipIdx.filter .. .map` expressions as the code | restatement |
| `callResponse_true_iff` | `truthy v = false ∧ r = .dict []`, or `v` a non-empty dict and `r = v`; the case split of the code with `truthy` unfolded for dicts | restatement |
| `supportsMax_iff` | `m = .parallel ∨ m = .queued` | restatement |

Independent: 1. Restatement: 4.

Among the O theorems, `compEntityIds_valid` uses an independent predicate (`Core.EntityIdRe`), and
`extractTargets_all`, `_named`, `_live_sorted` restate the result with `scripts[i]?` and `Pairwise (· < ·)`
instead of `zipIdx`/`filter`.

## Docstring claims

Checked: 98 theorem docstrings and 26 module-header claims (each header bullet is one claim; the "proved
against upstream" sentence of a header is one claim). Total 124.

| verdict | theorem docstrings | header claims | total |
|---|---|---|---|
| correct | 85 | 18 | 103 |
| overstated | 13 | 8 | 21 |
| correct for the wrong reason | 0 | 0 | 0 |
| false | 0 | 0 | 0 |
| stale | 0 | 0 | 0 |

Theorem docstrings that are not `correct` (all `overstated`):

1. `isSlug_iff` (ConfigSpec 37-38): "**`cv.slug` on an object id, exactly**". Upstream
   `cv.slug("")` returns `""` (`util.slugify` returns `""` for `""`, `config_validation.py` 602-610,
   `util/__init__.py` 41-42). `isSlug ""` is false. The statement is exact for `isSlug` against `ValidSlug`,
   not for `cv.slug`. `PROPERTIES.md` line 148 itself lists `""` as accepted by `cv.slug`.
2. `isSlug_valid` (ConfigSpec 27-28): "An object id that passes `cv.slug` is a valid slug: non-empty". Same
   evidence.
3. `decodeScript_not_slug` (ConfigSpec 382-383): "`_SCRIPT_OBJECT_ID_SCHEMA`: an object id that is not a valid
   slug is refused". True of `decodeScript`; upstream's schema accepts `""`.
4. `decodeScript_ok` (ConfigSpec 171-182): "a non-empty name (the alias, else the key)" and "with the raw config
   and the `prefix:name` icon (if any)". The statement has `a.alias ≠ ""` and `alias absent → a.alias = key`; it
   does not say the name is the alias when one is given. For the icon it says "contains `:`" and "absent →
   none"; it does not say the icon is the configured one.
5. `supportsMax_iff` (Proofs 37): "`max` is an attribute exactly in the modes that support it". The statement
   is `supportsMax m = true ↔ m = .parallel ∨ m = .queued`. It does not mention attributes
   (`entityAttributes_max` does).
6. `processLine_ok_output` (ProtocolSpec 162-163): "an `unsupported` entry per rejected script, then the step's
   commands". The statement gives only `cmds.size = rejected.length + commands.length`.
7. `decodeAll_mem` (ServiceSpec 27-28): "only the names other configs pass (`passedNames`) come from the rest
   of the file". The statement has `∃ extra`; `passedNames` does not occur in it.
8. `addScripts_aligned` (ServiceSpec 101-105): "`scripts` is as long as `automations`". Stated only for
   `new ≠ []`, and the whole theorem needs `e.scripts.length ≤ e.automations.length`, which the docstring
   does not mention.
9. `unsupportedCmds_spec` (ServiceSpec 157): "One `unsupported` log line per rejected script, in order". The
   statement gives the length and the log level, not the order or the text. The function is unused.
10. `Service.step_owned_echo` (ServiceSpec 174-175): "changes nothing but the clock". The statement is equality
    with the step on `.tick now`; a tick can fire timers and run scripts.
11. `Counter.setValue_inBounds` (Helpers 176-177): "succeeds only within the bounds ... and on a multiple of the
    step". The multiple-of-step part is not in the statement.
12. `InputNumber.setValue_error` (Helpers 70): "and the error names it". The statement fixes only
    `err.exception = "Invalid"`.
13. `Timer.toIdle_not_due` (Helpers 237): "An idle timer's callback is never due". The statement is about the
    output of `toIdle`, not about every entity with `state = .idle`.

Header claims that are not `correct` (all `overstated`):

14. ConfigSpec header 2-4: "proved against `homeassistant/components/script/config.py`". The statements are
    about the Lean definitions only; nothing in Lean refers to the Python.
15. ConfigSpec header 6: "`isSlug_iff`: `cv.slug` on an object id is exactly 'a valid slug'". See 1.
16. EntitySpec header 2-4: "proved against what `homeassistant/components/script/__init__.py` and the helpers
    it uses compute". Same as 14.
17. ServiceSpec header 2-5: "proved against ... (`async_setup`, `_async_process_config`,
    `async_added_to_hass`)". Same as 14; in addition `reloadScripts` (`_async_process_config`) has no theorem.
18. ServiceSpec header 11: "what each kind of input can and cannot change in the `Service`". Only `restored`,
    `automationConfigs` and the rejected list are covered; nothing on `engine` for `init`, `call`, `reload`.
19. ProtocolSpec header 7-8: "what `reload` and `call` messages decode to". For `call` there is only the
    missing-service error (`decodeInput_call_no_service`).
20. Helpers.Proofs header 10-12: "`input_select`: every service that succeeds keeps the current option among
    the options". `setOptions_valid` needs `opts ≠ []`; in the model `setOptions e []` succeeds and gives an
    invalid entity. The non-empty list comes from the service schema, which no theorem covers.
21. Helpers.Proofs header 18-19: "`timer`: cancelling or finishing leaves it idle, with nothing scheduled, no
    remaining time, and its configured duration". The theorems are about `toIdle`; `cancel`, `finish` and
    `finished` do not occur in any statement.

Not counted (implementation-file headers that cite `Proofs.lean`): `InputSelect.lean` 15-16 "the options are
never empty (`Proofs.lean`)": no such theorem. `InputNumber.lean` 11-12 "The value is never strictly below
`min` nor strictly above `max` (`Proofs.lean`)": proved only for the result of a successful service method.

## manifest.yaml claims

100 manifest entries have a `lean:` name defined in this area's implementation files: 74 `translated`,
26 `proven`. No `translated` entry names a theorem. None of the 110 Script theorems is named in the manifest;
all Script entries except the shared `async_call` one are `translated`.

The 26 `proven` entries. Every named theorem exists. Verdict on "`proven` fits":

| # | python | lean | theorems named | what they state | verdict |
|---|---|---|---|---|---|
| 1 | `core.py::ServiceRegistry.async_call` | 15 names, incl. `Script.callResponse`, `Script.normalizeTargetIds` | `call_none_return_response_errors`, `call_only_needs_return_response`, `call_return_response_needs_blocking`, `call_after_remove_not_found` (`Core/ServiceRegistryProofs.lean`, outside this area) | four error cases of `Registry.asyncCall`; none mentions the two Script names (their own theorems, `callResponse_true_iff` etc., are not cited) | overstated |
| 2 | `ToggleEntity.async_toggle` | `InputBoolean.toggle` | `toggle_toggle`, `state_toggle` | involution; state flips. Does not state `cfg` is kept | overstated |
| 3 | `InputBoolean.async_turn_on` | `turnOn` | `turnOn_idem`, `state_turnOn` | idempotent; state `on` | overstated |
| 4 | `InputBoolean.async_turn_off` | `turnOff` | `turnOff_idem`, `state_turnOff` | idempotent; state `off` | overstated |
| 5 | `InputNumber.async_set_native_value` | `InputNumber.setValue` | `setValue_bounded`, `setValue_error` | success → bounded, cfg kept; out of range → `Invalid`. Stored value and success condition not stated | overstated |
| 6 | `InputNumber.async_increment` | `increment`, `pyMin` | `increment_bounded` | success → bounded; true for any new value | overstated |
| 7 | `InputNumber.async_decrement` | `decrement`, `pyMax` | `decrement_bounded` | same | overstated |
| 8 | `InputSelect.__init__` | `InputSelect.Entity.create` | `create_valid` | one invariant under two hypotheses | overstated |
| 9 | `InputSelect.async_added_to_hass` | `Entity.create` | `create_valid` | same | overstated |
| 10 | `InputSelect.async_select_option` | `selectOption` | `selectOption_valid` | invariant; `current = option` not stated | overstated |
| 11 | `InputSelect.async_set_options` | `setOptions` | `setOptions_valid` | invariant for non-empty list | overstated |
| 12 | `SelectEntity.state` | `InputSelect.Entity.state` | `state_of_valid` | result for valid entities only | overstated |
| 13 | `SelectEntity.async_first` | `selectIndex` | `selectIndex_valid` | invariant; not that the first option is selected | overstated |
| 14 | `SelectEntity.async_last` | `selectIndex` | `selectIndex_valid` | same | overstated |
| 15 | `SelectEntity.async_next` | `offsetIndex` | `offsetIndex_valid` | invariant; not which option | overstated |
| 16 | `SelectEntity.async_previous` | `offsetIndex` | `offsetIndex_valid` | same | overstated |
| 17 | `SelectEntity._async_offset_index` | `offsetIndex` | `offsetIndex_valid` | same | overstated |
| 18 | `SelectEntity._async_select_index` | `selectIndex`, `atMod` | `selectIndex_valid` | same; `atMod` not mentioned | overstated |
| 19 | `Counter.compute_next_state` | `Counter.clamp` | `clamp_le_max`, `min_le_clamp` | two bounds; not the value (e.g. `clamp v = v` in range) | overstated |
| 20 | `Counter.async_increment` | `increment` | `increment_inBounds` | bound under `Consistent`; true for any argument of `clamp` | overstated |
| 21 | `Counter.async_decrement` | `decrement` | `decrement_inBounds` | same | overstated |
| 22 | `Counter.async_reset` | `reset` | `reset_inBounds` | same | overstated |
| 23 | `Counter.async_set_value` | `Counter.setValue` | `setValue_inBounds` | success result fixed; failure conditions not stated. The note's "step 0 raises ZeroDivisionError" has no theorem | overstated |
| 24 | `Timer.async_cancel` | `Timer.cancel`, `toIdle` | `toIdle_idle` | about `toIdle`; `cancel` not in the statement | overstated |
| 25 | `Timer.async_finish` | `Timer.finish`, `toIdle` | `toIdle_idle` | about `toIdle`; `finish` not in the statement | overstated |
| 26 | `Timer._async_finished` | `Timer.finished` | `toIdle_not_due` | about `toIdle` and `due`; `finished` not in the statement | overstated |

Counts: correct 0, overstated 26, correct for the wrong reason 0, false 0, stale 0.

In every entry the notes name the theorems correctly; the overstatement is the status `proven`: each theorem
gives one property, none determines the function. `PROPERTIES.md` (lines 132-137) says the manifest marks
`proven` the entries where "the translation is proved to decide exactly that predicate"; none of these 26
meets that.

The reverse case: `helpers/script.py::Script.supports_max` (`Script.supportsMax`) is `translated`, and
`supportsMax_iff` determines it.

## PROPERTIES.md claims

`PROPERTIES.md` names no theorem of the five Script modules. It names all 25 `Helpers.Proofs` theorems except
`clamp_inBounds` in the "Helpers" section (lines 99-123).

| # | row / claim | verdict | evidence |
|---|---|---|---|
| 1 | line 106, `toggle_toggle`, `state_toggle` | correct | statements match |
| 2 | line 107, `turnOn_idem`, `turnOff_idem`, `state_turnOn`, `state_turnOff` | correct | statements match |
| 3 | line 108, `setValue_bounded`, `increment_bounded`, `decrement_bounded` | correct | `Bounded ∧ cfg = e.cfg` on success |
| 4 | line 109, `setValue_error`: "refused with `probatio.Invalid`" | correct | `err.exception = "Invalid"`; upstream raises `probatio.Invalid` (`input_number/__init__.py` 288-289) |
| 5 | line 110, `selectOption_valid`, `selectIndex_valid`, `offsetIndex_valid` | correct | `Valid ∧ options` unchanged on success |
| 6 | line 111, `setOptions_valid`: "with a non-empty list" | correct | hypothesis `opts ≠ []` |
| 7 | line 112, `create_valid`, `state_of_valid` | correct | hypotheses and conclusions match |
| 8 | line 113, `increment_inBounds`, `decrement_inBounds`, `reset_inBounds`: "with `minimum ≤ maximum`" | correct | hypothesis `Consistent` |
| 9 | line 114, `setValue_inBounds` | correct | `InBounds ∧ value = v` |
| 10 | line 115, `clamp_le_max`, `min_le_clamp`: "`compute_next_state` clamps" | correct | the two bounds; `min_le_clamp` under `minimum ≤ maximum` |
| 11 | line 116, `toIdle_idle`, `toIdle_not_due`: "cancelling or finishing leaves the timer idle, with nothing scheduled ..." | overstated | both statements are about `toIdle e`; `cancel`, `finish`, `finished` do not occur |
| 12 | lines 118-120: `set_value` with `nan` passes both range checks | correct | upstream `num_value < min or num_value > max` (`input_number/__init__.py` 288) |
| 13 | lines 120-123: a counter can start outside its bounds | correct | upstream `__init__` sets `initial`; `compute_next_state` is applied only on restore (`counter/__init__.py` 244-248) |

Counts: correct 12, overstated 1, correct for the wrong reason 0, false 0, stale 0.
