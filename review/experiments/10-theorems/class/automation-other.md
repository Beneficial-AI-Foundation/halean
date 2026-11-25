# automation-other: ConditionSpec, ConfigSpec, LocationSpec, SlugifySpec, SunSpec, TimePeriodSpec

Modules: `HALean.Automation.{Condition,Config,Location,Slugify,Sun,TimePeriod}Spec` (239 theorems).
Implementation files: `HALean/Automation/{Condition,Config,Location,Slugify,Sun,TimePeriod}.lean`.
Classification: `class/automation-other.tsv`.

| module | C | O | E | H | total |
|---|---|---|---|---|---|
| ConditionSpec | 16 | 21 | 24 | 11 | 72 |
| ConfigSpec | 0 | 5 | 18 | 48 | 71 |
| LocationSpec | 5 | 3 | 10 | 4 | 22 |
| SlugifySpec | 1 | 2 | 0 | 23 | 26 |
| SunSpec | 1 | 12 | 3 | 1 | 17 |
| TimePeriodSpec | 1 | 10 | 15 | 5 | 31 |
| all | 24 | 53 | 70 | 92 | 239 |

Rules I applied (they decide many borderline cases):

* A theorem that gives the result on one branch of the function's own case split is `E`, even when the branch
  holds many inputs (`timeCond_fixed`, `cvTimePeriod_str`, `forPeriod?_static_str`, `zoneCondition_coordinates`).
* When two or three `iff` theorems together determine the result of an upstream function, each is `C`
  (`evalAnd_false_iff` with `evalAnd_true_iff`).
* The key decoders of `Config.lean` (`field?`, `str?`, `strList`, `entityIds`, `weekday?`, `optDuration`, `bound?`,
  `timeBound?`, `valueTemplate?`, `compileTemplate`, `continueOnTimeout?`, `responseVariable?`, `noTemplate`,
  `orderedMapping`, `stateMatch`, `jsonNumToFloat`) have no `manifest.yaml` entry and no upstream function of their
  own. Their theorems are `H`, as the brief requires. 21 of these 48 `H` theorems are exact `iff`s. They are listed
  below so a reader can weigh them differently.
* Functions with a manifest entry or an upstream function named in their docstring count as translated
  (`ensureList`, `durationMs`, `isEnabled`, `forPeriod?`, `timeout?`, `decodeTrigger`, `automationName`,
  `availableEntityId`, `automationEntityIds`, `accum`, `timedeltaNew`, `hourAngle`, ...).

Axioms: `#print axioms` on the 221 public theorems gives only `propext`, `Classical.choice`, `Quot.sound`
(`class/scratch/automation-other-axioms.lean`). The 18 private theorems cannot be named from outside their file.

## Float: what the toolchain allows, and what the theorems conclude

The repository says in several places that Lean's `Float` is opaque. On this toolchain (`leanprover/lean4:v4.36.0`)
that is only partly true. Checked in `class/scratch/automation-other-float.lean` and `...-float2.lean`:

* `Float` is a structure over a bit-level model (`Float.toModel : Float.Model`, a `UInt64` with a validity proof).
  `+ - * /`, `neg`, `abs`, `sqrt`, `<`, `≤`, `==`, `isNaN`, `isInf`, `toUInt64`, `ofNat`, `ofInt` and literals are
  definitions. The kernel evaluates them: `((0 : Float) != 0) = false`, `(0.0 : Float) * 1000 = 0.0`,
  `((2.5 : Float) + 0.25 == 2.75) = true`, `(radians 180.0 == 3.141592653589793) = true` are proved by `decide` or
  `rfl`, with the three standard axioms only.
* `Float.sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `floor`, `ceil`, `round` are `opaque`.
  `decide` on `(Float.floor 1.5 == 1.0) = true` fails.
* `==` on `Lean.Json` is opaque (a `partial def`): `(Json.num 1 == Json.null) = false` is not provable.

Consequences for the three numeric files:

* **Sun.** Every path to a sunrise or sunset time goes through `ffloor` (`julianday`), `Float.sin` /`asin` /`tan`
  (`sunDeclination`, `eqOfTime`), `Float.cos` /`acos` (`hourAngle`) and `Float.floor` /`ceil` (`truncInt`,
  `minutesToUs`). No theorem states a numeric value, a bound, or a monotonicity fact for `julianday`, `hourAngle`,
  `timeOfTransit`, `sunEvent` or `minutesToUs`, and with these opaque functions none can be derived by evaluation.
  The theorems conclude: (1) `nextEvent` is the first of 368 day offsets whose `sunEvent` plus offset is after
  `nowUs` (`nextEvent_eq`), treating `sunEvent` as an unknown function; (2) the returned `Int` is `> nowUs`
  (`nextEvent_gt`), integer arithmetic; (3) rising and setting hour angles are defined together and are each
  other's `Float.neg` (`hourAngle_isSome`, `hourAngle_setting`, `hourAngle_rising`); (4) branch facts under a Float
  comparison hypothesis (`adjustToHorizon_nonpos`, `refractionAtZenith_high`, `*_elevation`). They cannot
  conclude that any returned time is a sunrise, is on the requested day, or is within any distance of the true value.
* **Location.** `vincenty` uses `Float.tan`, `atan`, `sin`, `cos`, `atan2` and `Template.pyRound`. The only theorem
  about its value is the first line (`vincenty_coincident`: Float-equal inputs give `some 0.0`). No theorem says the
  loop converges, that the distance is non-negative, symmetric, or zero only for equal points. `inZone_true`
  concludes `d - radius < r` as a Float comparison on an unknown `d`. `distance_coincident` concludes
  `some (0.0 * 1000)`; this equals `some 0.0` by `rfl` on this toolchain, the theorem does not say so.
* **TimePeriod.** `modf` uses `floor`/`ceil`, `timedeltaNew` uses `round`: the float path of `accum` and the
  half-even rounding are not characterised (only NaN, infinity and `accum_shift`). Integer facts are proved:
  the day-range bound (`*_range`), and the exact weighted sum for `int`-only arguments (`timedeltaNew_ints`). No
  theorem gives the microsecond value of any float or string period, e.g. that `"0:00:01.5"` is 1 500 000.
  `durationMs` (`Config.lean`) uses `(f * 1000).round.toUInt64`: no theorem about any accepted value.
* Float hypotheses in theorem statements (`(lat1 == lat2 && lon1 == lon2) = true`, `elevation ≤ 0`,
  `¬ o.elevation > 0.0`, `x.isNaN = true`, `((0 : Float) != 0) = false`) are decidable for concrete literals by
  `decide`. So `timedeltaNew_ints`'s hypothesis `h0` can be discharged (`g5` in the scratch file) and is not needed
  as a hypothesis.

## What the theorems constrain

**Condition.lean (`helpers/condition.py`, `helpers/script.py`)**

* `evalAnd` (`AndConditionChecker`): `evalAnd_false_iff`, `evalAnd_true_iff`, `evalAnd_ne_none` fix when the result
  is `ok false`, `ok true`, never `ok none`; so it is an error in all other cases. The error text is not fixed.
* `evalOr`: `evalOr_true_iff`, `evalOr_false_iff`, `evalOr_ne_none`, same shape.
* `evalNot`: `evalNot_eq_negate_evalOr` (equal to `evalOr` with the boolean flipped, same error value),
  `evalNot_false_iff`, `evalNot_true_iff`. `evalCond_combinator_ne_none`, `evalCond_not_not_true_iff`.
* `checkAutomationConditions` (`ConditionsChecker.async_check`): `checkAutomationConditions_iff` determines the
  `Bool` result.
* `testConditions` (`_test_conditions`): `testConditions_true_iff`, `testConditions_false_iff` determine the
  `Option Bool` result (`none` otherwise). `testConditions_true_iff_check`, `testConditions_false_imp_evalAnd`.
* All of the above are relative to `evalCond env c` of the member conditions.
* `entityLoop` (loop of `state_from_config` / `async_numeric_state_from_config`): `entityLoop_eq_spec` (equal to
  the recursion `entityLoopSpec`, error text included), `entityLoop_all_false_iff`, `entityLoop_all_true_iff`,
  `entityLoop_any_true_iff`, `entityLoop_ne_none`. Relative to the per-entity `check` function.
* `evalCond`, `trigger` case: `evalCond_trigger_true_iff`, `evalCond_trigger_total` determine it.
  `template`, `time`, `state` cases: only "never `ok none`" (`evalCond_template_ne_none`, `evalCond_time_ne_none`,
  `evalCond_state_ne_none`).
* `templateCond` (`async_template`): `templateCond_true_iff`, `templateCond_error_iff` determine it relative to
  `Template.render`.
* `setVar` (`ScriptRunVariables._assign`): `setVar_keys`, `setVar_length`, `setVar_find_self`,
  `setVar_find_other`, `setVar_idem`. These fix the key list and what `find?` returns. For a list with a repeated
  key the stored values behind the first entry are not fixed.
* `renderVariables`: `renderVariables_prefix`, `renderVariables_defines` (on success only).
* `isInputEntityId`: `isInputEntityId_parts` (necessary conditions, one direction).
* `resolveBound`: `resolveBound_entity_some` (one direction).

**Config.lean**

* `ensureList` (`cv.ensure_list`): `ensureList_idem`, `ensureList_eq_nil_iff`; with the `E` theorems
  `ensureList_arr_toArray`, `ensureList_scalar` all inputs are covered (array, `null`, anything else).
* `automationName`: `automationName_cases`; with `automationName_alias`, `automationName_default` (`E`) all cases
  are covered.
* `automationEntityIds`: `automationEntityIds_length`, `automationEntityIds_prefix` (shape of the result, not the
  ids).
* No `C` theorem. The 21 exact `iff` theorems on key decoders, classed `H`: `has_iff`, `str?_eq_some_iff`,
  `strList_ok_iff`, `weekday?_none_iff`, `weekday?_some_iff`, `continueOnTimeout?_ok_iff`,
  `responseVariable?_ok_iff`, `noTemplate_ok_iff`, `optDuration_none_iff`, `optDuration_some_iff`,
  `bound?_none_iff`, `bound?_entity_iff`, `timeBound?_none_iff`, `timeBound?_fixed_iff`, `timeBound?_entity_iff`,
  `compileTemplate_ok_iff`, `valueTemplate?_none_iff`, `valueTemplate?_some_iff`, `orderedMapping_arr_ok_iff`,
  `stateMatch_values_none_iff`, `stateMatch_invert_iff`. They say how one key is read. `timeBound?_fixed_iff`
  connects to the independent `Template.ParseTimeSpec`.

**Location.lean**

* `hasLocation` (`get_state_coordinates is not None`): `hasLocation_iff`.
* `inZonesAttribute` (`get_in_zones_attribute`): `inZonesAttribute_eq_some`, `inZonesAttribute_eq_none`.
* `stateHasZoneInfo`: `stateHasZoneInfo_iff`.
* `distance`: `distance_eq_some`, `distance_eq_none` (relative to `vincenty`).
* `inZone` (`zone.in_zone`): `inZone_spec` with `inZone_unavailable`, `inZone_bad_latitude`,
  `inZone_bad_longitude` cover every input, relative to `distance` and Float `-`/`<`. `inZone_true`.

**Slugify.lean**

* `slugify?`: `slugify_fixed_iff` (fixed points are `""` and the `ValidSlug` texts, on text with
  `slugify? s ≠ none`). `slugifyChars_valid` (non-empty output is a `ValidSlug`), `slugifyChars_of_valid`
  (identity on `ValidSlug`).

**Sun.lean**

* `nextEvent` (`get_observer_astral_event_next`): `nextEvent_eq`, `nextEvent_gt`, `nextEvent_is_event`,
  `nextEvent_eq_none`, `nextEvent_first`, `nextEvent_no_offset`, `nextEvent_elevation`. Relative to `sunEvent`.
* `hourAngle`: `hourAngle_isSome`, `hourAngle_setting`, `hourAngle_rising`.
* `timeOfTransit`, `sunEvent`: `timeOfTransit_elevation`, `sunEvent_elevation`, `timeOfTransit_some`.

**TimePeriod.lean**

* `cvPositiveTimePeriod`: `cvPositiveTimePeriod_ok` with `_negative`, `_error` determine it relative to
  `cvTimePeriod`.
* `cvTimePeriod`: `cvTimePeriod_range`; the `E` theorems `cvTimePeriod_timedelta`, `_int`, `_float`, `_bool`,
  `_str_nonascii`, `_str`, `_other` restate every branch except the mapping branch.
* `timedeltaNew`, `timePeriodStr`, `timePeriodDict`, `timePeriodSeconds`: `*_range`; `timePeriodDict_bad_key`,
  `timePeriodDict_bad_value`, `timePeriodSeconds_eq_none`; `timedeltaNew_ints`; `accum_shift`.

## What they do not constrain

(a) **Partial defs** (from `logs/defs.tsv`): `renderComplex`, `renderComplexV`, `Complex.hasTemplate`
(`Condition.lean`); `decodeComplex`, `Complex.hasTemplate'`, `decodeCondition`, `renderJsonTemplates`, `jsonHasList`,
`decodeAction`, `actionVariableNames` (`Config.lean`). No theorem statement in the 239 mentions any of them
(checked against the constants column of `logs/theorems.tsv`). Theorems about functions that call them:

* `renderVariables_prefix`, `renderVariables_defines`, `renderVariables_nil`: `renderVariables` calls
  `renderComplexV`. The theorems hold for any behaviour of it. They say nothing about the rendered values or about
  when rendering succeeds.
* `stateOne_unknown`, the `evalCond` and `evalAnd`/`evalOr`/`evalNot` theorems: `stateOne` calls `renderComplexV`
  for a templated `for:`. The theorems treat the result of a `state` condition as unknown.
* `forPeriod?_absent`, `forPeriod?_static_str`, `forPeriod?_template_str`, `timeout?_absent`: these cover the
  branches that do not reach `decodeComplex` / `hasTemplate'`. The mapping branch of `forPeriod?` and every
  non-absent `timeout?` have no theorem.
* `decodeTrigger_disabled`, `decodeTrigger_enabled_error`: `decodeTrigger` calls `decodeComplex`,
  `renderJsonTemplates`, `jsonHasList`. Both theorems return before those calls.

(b) **JSON decoders.** `decodeCondition`, `decodeAction`, `decodeComplex` are partial: zero theorems, and none can
unfold them. `decodeTrigger` (a `def`, lines 709 to 984) has two theorems, both about the `enabled` gate.
`decodeAutomation` has none. Because the composite decoders are partial or untouched, no theorem connects a
key-decoder fact (for example `timeBound?_fixed_range`) to the `Condition`, `Trigger` or `Action` value the engine
receives. Defs in `Config.lean` with zero theorems: `limitedRenderJson`, `limitedRenderStr`, `cvTemplateText`,
`cvStringOf`, `mqttValidTopic`, `mqttValidSubscribeTopic`, `mqttQos`, `isUtf8Encoding`, `pyUpperMethod`,
`webhookMethods`, `compEntityIds`, `pyIntOfJson?`, `maxRunsOf`, `decodeAutomation`. Partly covered:
`durationMs` (three rejection cases; no accepted value), `isEnabled` (absent and literal boolean; not numbers,
strings, templates), `bound?` (numeric case one direction), `availableEntityId` (only when the preferred id is
free; the `_2`, `_3` suffix search has no theorem), `automationEntityIds` (shape only). `durationMs` and
`cvTimePeriod` both translate `cv.time_period`; no theorem relates them.

(c) **Entry points.**

* `decodeAutomation` (config entry): no theorem.
* `evalCond` (condition entry): theorems exist for the `trigger` case (complete), the combinators (complete relative
  to members), and "not `ok none`" for `template`, `time`, `state`. No theorem for the `numericState`, `zone`, `sun`
  cases of `evalCond`, and none for `.disabled` in these modules (`evalCond_disabled` is in `Automation/Proofs.lean`).
* `checkAutomationConditions`, `testConditions`: determined, relative to `evalCond`.
* Leaf evaluators: `stateOne` (only missing entity), `numericStateOf` (only missing attribute; the comparisons
  `fv >= bv`, `fv <= av` have no theorem), `resolveTimeBound` (only missing entity), `timeCond` (of the 18
  constructor combinations of before/after/weekday, 3 are covered fully: both fixed without weekday, weekday only,
  nothing; one partly: both fixed with a non-matching weekday; no entity bound, no single bound, no fixed bounds
  with a matching weekday),
  `zoneCond` (empty lists only), `zoneById` (missing entities only), `sunCond` (missing location only),
  `normalizeTarget` (no `entity_id` handling), `pyFloatV`.
* `zoneCondition`: five branch theorems; no theorem for `gps_accuracy` present, `null` coordinates, or other
  `in_zones` value types.
* `vincenty`, `julianday`, `minutesToUs`, `truncInt`, `timeOfTransit` (latitude clamp, two-pass refinement),
  `refractionAtZenith` (three of four branches), `adjustToHorizon` (positive elevation): no theorem on values.
* `slugify?` on text that is not already a slug: the output is only known to be `"unknown"` or a `ValidSlug`. No
  theorem gives the slug of any text (for example that `"Hello World"` gives `"hello_world"`). `subRuns` and
  `delDigitCommas` are not related to a regular-expression semantics by any theorem; the header of `Slugify.lean`
  ("Proved in `SlugifySpec.lean`") refers to properties of the pipeline output only.
* `timePeriodStr`: parse result not characterised (only range). `timePeriodDict`: accepted value not characterised.

## Assumptions that nothing checks

| theorem | hypothesis | where the value comes from at run time | discharged by a theorem? |
|---|---|---|---|
| `zoneCondition_coordinates` | `n1 : (latJ == Json.null) = false`, `n2` likewise | attributes of an entity state sent by the bridge | No. `Json` `==` is opaque; not provable even for `Json.num 1`. True at run time for numbers. |
| `zoneCondition_in_zones` | conclusion is `xs.contains (.str zone.entityId)` | same | The conclusion is stated with the opaque `Json` `==`; nothing says it means membership. |
| `timedeltaNew_ints` | `h0 : ((0 : Float) != 0) = false` | constant | Not by the repository. `by decide` proves it (scratch `g5`); the hypothesis is unnecessary. |
| `timeOfTransit_elevation`, `sunEvent_elevation`, `nextEvent_elevation` | `¬ o.elevation > 0.0` for both observers | HA location config through the bridge (`CondEnv.location`, engine state) | No theorem about the observer the engine holds. Decidable for a concrete literal. |
| `refractionAtZenith_high` | `90 - zenith ≥ 85.0` | `timeOfTransit` passes `90 + SUN_APPARENT_RADIUS + adjElev ± adjRefr` | No. For the base zenith the hypothesis is false (`g8` in scratch proves `¬ (90 - (90.0 + SUN_APPARENT_RADIUS) ≥ 85.0)`). The theorem is about a branch the sunrise/sunset code does not take. |
| `adjustToHorizon_nonpos` | `elevation ≤ 0` | `timeOfTransit` calls `adjustToHorizon` only when `o.elevation > 0.0` | No. From `timeOfTransit` the hypothesis holds for no call (the two comparisons exclude each other for non-NaN values); the theorem is about a branch that caller never takes. |
| `vincenty_coincident`, `distance_coincident` | `(lat1 == lat2 && lon1 == lon2) = true` (Float `==`) | entity and zone attributes | No theorem; decidable for literals. |
| `nextEvent_first`, `nextEvent_is_event`, `nextEvent_gt`, `nextEvent_no_offset`, `timeOfTransit_some` | `nextEvent ... = some t`, `candidate ... k = some t`, `timeOfTransit ... = some t` | `sunEvent`, computed with opaque libm functions | No closed instance can be proved in the kernel. Nothing shows a sunrise exists for any observer and date. |
| `slugify_fixed_iff`, `slugify?_of_ne` | `slugify? s ≠ none` | automation aliases, schema keys | No theorem states when it holds (ASCII and not both `&` and `;`). `cvSlug` and `automationEntityIds` test it at run time. |
| `renderVariables_prefix`, `renderVariables_defines` | `renderVariables env defs = .ok vs` | `renderComplexV` (partial) | No theorem says when rendering succeeds. |
| `compileTemplate_ok_iff`, `valueTemplate?_some_iff`, `templateCond_*` | stated in terms of `Template.compile`, `Template.check`, `Template.render` | template engine (other area) | Out of this area. |
| `inZone_spec` | zone available, `numAttr` latitude and longitude ok | zone entity state from the bridge | Not needed: the three sibling theorems cover the other cases. |
| all `evalAnd`/`evalOr`/`evalNot`/`checkAutomationConditions`/`testConditions` theorems | none, but stated over `evalCond env c` | `Condition` values come from `decodeCondition` (partial) | Nothing relates the decoded condition to the configuration. |

Vacuous, or weaker than they read:

* `timedeltaNew_range`, `timePeriodStr_range`, `timePeriodDict_range`, `timePeriodSeconds_range`,
  `cvTimePeriod_range`: the conclusion is the guard the function checks just before returning.
* `timeOfTransit_some`: `∃ minutes : Float, t = midnight + minutesToUs minutes`. `minutes` is not tied to the
  computation and is not bounded, so `t` is not shown to lie on the requested day.
* `modf_spec`: first conjunct is the definition (`fp = x - ip` in Float arithmetic); the second is the `if`.
* `distance_coincident`: result `some (0.0 * 1000)`, not `some 0.0`.
* `numericStateOne_known`, `forPeriod?_static_str`, `cvTimePeriod_str`, `inZone_spec`, `zoneCondition_coordinates`:
  the right-hand side is the next layer of the implementation.
* `evalCond_trigger_total`, `*_ne_none`: say only that a result has a given shape.
* No theorem has a `True` conclusion. I found no theorem whose hypotheses cannot hold together.

Restatements proved by `rfl` (17; they unfold to the definition and say nothing independent of the code):
`renderVariables_nil`, `resolveBound_num`, `pyFloatV_none`, `pyFloatV_number`, `ensureList_arr_toArray`,
`ensureList_idem`, `jsonNumToFloat_num`, `orderedMapping_obj`, `automationEntityIds_eq`, `entityIdsFrom_nil`,
`automationEntityIds_nil`, `accum_int`, `timePeriodDict_empty`, `cvTimePeriod_timedelta`, `cvTimePeriod_int`,
`cvTimePeriod_float`, `cvTimePeriod_bool`. (`ensureList_idem` uses `List.toArray`/`Array.toList` reduction, so it is
a small fact, not a pure restatement.)

Theorems that pin behaviour which differs from upstream (checked by running the HA in `/opt/havenv` on
`upstream/ha-core`):

* `timePeriodSeconds_nan`: Lean returns `some (.error "ValueError: ...")`, an error that escapes the `Any`.
  Upstream `cv.time_period_seconds(float("nan"))` raises `Invalid("Expected seconds, got nan")`
  (`config_validation.py` lines 560 to 563 catch `ValueError`). Both sides fail; the kind and text differ.
* `durationMs_bad_type`: Lean rejects booleans. Upstream `cv.time_period(True)` is `timedelta(seconds=1)` and
  `cv.positive_time_period_template(True)` likewise. `for: true` is refused by HALean and accepted by HA.
* `timeBound?_none_iff`: a `before`/`after` that is present but not a string gives "no bound", not an error.
* `continueOnTimeout?_ok_iff`: only JSON booleans are accepted; upstream `cv.boolean` also takes `"yes"`, `1`, ...
  (the def's docstring says so).

## Specifications independent of the code?

24 `C` theorems. Independent specification: 12. Restatement of the implementation's own case split: 12.

Independent (a declarative statement over the members' results, where the code is a recursion with an error
accumulator; or a separately written predicate):

1. `evalAnd_false_iff`
2. `evalAnd_true_iff`
3. `evalOr_true_iff`
4. `evalOr_false_iff`
5. `evalNot_false_iff`
6. `evalNot_true_iff`
7. `checkAutomationConditions_iff`
8. `testConditions_true_iff`
9. `testConditions_false_iff`
10. `entityLoop_all_false_iff`
11. `entityLoop_all_true_iff`
12. `slugify_fixed_iff` (predicate `ValidSlug`, written separately; relative to the transcribed pipeline
    `slugifyChars`, which I compared with `slugify/_legacy.py` lines 137 to 161: same eight steps)

Restatement:

1. `entityLoop_eq_spec` (`entityLoopSpec` is the same loop written as a recursion)
2. `evalNot_eq_negate_evalOr` (relates two implementation functions)
3. `templateCond_true_iff` (the `match` on the render result)
4. `templateCond_error_iff` (same)
5. `evalCond_trigger_true_iff` (`ids.contains t` written as `t ∈ ids`)
6. `hasLocation_iff` (in terms of the helper `numAttr`)
7. `inZonesAttribute_eq_some` (`s.domain` is the same expression as in the definition)
8. `stateHasZoneInfo_iff` (in terms of `hasLocation`)
9. `distance_eq_some` (`Option.map`)
10. `inZone_spec` (the function's own `match`)
11. `nextEvent_eq` (`candidate` is the loop body, defined in the spec file)
12. `cvPositiveTimePeriod_ok` (the function's own `if`)

Outside `C`, two theorems have an independently written right-hand side: `timeBound?_fixed_iff`
(`Template.ParseTimeSpec`) and `timedeltaNew_ints` (weighted integer sum).

## Docstring claims

Checked: 183 theorem docstrings and 6 module header comments, 189 in total.
Verdicts: correct 176, overstated 9, false 3, correct for the wrong reason 1, stale 0.

Not `correct`:

1. `ConditionSpec.lean` header, lines 5 to 8: "exact characterisations of the three combinators ..., of the entity
   loop ..., and of the `time` condition on fixed bounds". **overstated.** For `evalAnd`/`evalOr` the error value is
   not characterised. For `time`, `timeCond_fixed` (line 370) has `weekday = none`; fixed bounds with a matching
   weekday have no theorem.
2. `numericStateOne_known`, line 346: "the condition is decided by its state alone". **overstated.** The statement
   is `numericStateOne env eid ... = numericStateOf env ent ...`; the right side still depends on `env` (bound
   entities, template variables).
3. `evalCond_state_ne_none`, line 620: "`state` and `numeric_state` conditions never return `None`".
   **overstated.** The statement is about `.state` only. No theorem covers `.numericState`.
4. `evalCond_combinator_ne_none`, lines 790 to 791: "only a disabled condition does". **overstated.** The statement
   covers `and`/`or`/`not`. No theorem excludes `ok none` for `numericState`, `zone`, `sun`.
5. `ConfigSpec.lean` header, lines 5 to 6: "Each decoder of an optional key is characterised by what is in the
   config: when it gives nothing, when it gives a value, and when it rejects." **overstated.** `durationMs` has only
   rejection theorems; `isEnabled` only absent and boolean; `timeout?` only absent; `forPeriod?` no mapping form;
   `bound?_num_imp` is one direction.
6. `durationMs_bad_type`, line 246: "`None`, booleans and lists are not time periods." **false** for booleans as a
   statement about `cv.time_period` (the def's docstring names it): `cv.time_period(True)` returns
   `timedelta(seconds=1)` in the installed HA. Correct as a statement about `durationMs`.
7. `inZone_bad_latitude`, line 112: "A zone without a numeric latitude is an error (Python's `TypeError`)".
   **overstated.** A missing key is `KeyError` upstream (`zone.attributes[...]`, `zone/__init__.py` line 295).
8. `LocationSpec.lean` header, lines 5 to 7: "IEEE double arithmetic, which Lean's `Float` keeps opaque".
   **correct for the wrong reason.** Float `+ - * / sqrt` and comparisons are not opaque on v4.36.0. The
   conclusion (only control flow is proved) holds because `tan`, `atan`, `sin`, `cos`, `atan2` are opaque.
9. `SunSpec.lean` header, lines 5 to 7: "which Lean's `Float` keeps opaque: nothing numeric can be proved about it".
   **overstated.** The libm functions and `floor` are opaque; arithmetic, comparisons and literals are not
   (`adjustToHorizon 0.0 = 0` and the falsity of the `refractionAtZenith_high` hypothesis for the sea-level zenith
   are provable, scratch `g7`, `g8`).
10. `timeOfTransit_some`, lines 186 to 187: "its midnight plus `minutes_to_timedelta` of the computed minutes".
    **overstated.** The statement is `∃ minutes`, any float.
11. `modf_spec`, lines 16 to 17: "the two parts add up to `x`". **overstated.** Proved: `fp = x - ip` (the
    definition). `fp + ip = x` is not stated.
12. `timePeriodSeconds_nan`, lines 259 to 260: "the `ValueError` of `timedelta(seconds=nan)` is not `Invalid`, so it
    escapes `vol.Any`". **false.** `time_period_seconds` catches `ValueError` and raises `Invalid`
    (`config_validation.py` lines 560 to 563); the installed HA gives `Invalid: Expected seconds, got nan`, and
    `cv.time_period(float("nan"))` gives `MultipleInvalid`.
13. `timedeltaNew_ints`, lines 383 to 385: "`h0` is `0.0 != 0.0 = False`, which Lean's opaque `Float` cannot
    evaluate in a proof". **false** on this toolchain: `by decide` proves it. Also "or an `OverflowError`" is not in
    the statement (the `iff` is about `.ok` only).

Checked and correct against upstream source: `templateCond_true_iff` (`value.lower() == "true"`),
`entityLoop_*` (loop of `state_from_config`), `timeCond_fixed`, `nextEvent_eq` (`while mod < 367` from `-1`),
`hasLocation_iff`, `inZonesAttribute_eq_some`, `stateHasZoneInfo_iff`, `distance_eq_some`, `inZone_spec`,
`zoneCondition_in_zones_str`, `timePeriodDict_bad_key`, `timePeriodDict_bad_value`, `cvPositiveTimePeriod_ok`,
`accum_nan`, `accum_inf`, `SlugifySpec.lean` header (`cv.slug`). `zoneCondition_coordinates` ("`==` on `Json` is
opaque") is correct.

## manifest.yaml claims

Entries whose `lean:` names are in my implementation files: 55 (49 `translated`, 6 `proven`). In scope (status
`proven`, or notes naming a theorem): 7. Verdicts: correct 2, correct for the wrong reason 5.

| entry | lean | status | theorems named | verdict |
|---|---|---|---|---|
| `condition.py::AndConditionChecker._async_check` | `evalAnd` | proven | `evalAnd_nil`, `evalAnd_all_disabled` (both exist, in `HALean.Automation.Proofs`) | **correct for the wrong reason.** The named theorems are the empty list and the all-disabled list. The note's sentence "errors are collected and raised only if no condition returned False" is what `evalAnd_false_iff` / `evalAnd_true_iff` (ConditionSpec) state; these are not named. `proven` fits through them, up to the error text. |
| `condition.py::OrConditionChecker._async_check` | `evalOr` | proven | `evalOr_nil` (exists, Proofs) | **correct for the wrong reason.** One literal input. `evalOr_true_iff` / `evalOr_false_iff` carry the status. |
| `condition.py::NotConditionChecker._async_check` | `evalNot` | proven | `evalNot_disabled` (exists, Proofs) | **correct for the wrong reason.** `not [disabled]` only. `evalNot_eq_negate_evalOr`, `evalNot_true_iff`, `evalNot_false_iff` carry the status. |
| `condition.py::DisabledConditionChecker._async_check` | `evalCond` | proven | `evalCond_disabled` (exists, Proofs) | **correct.** `evalCond env .disabled = .ok none` is the whole upstream function. |
| `condition.py::ConditionsChecker.async_check` | `checkAutomationConditions` | proven | `checkAutomationConditions_nil` (exists, Proofs) | **correct for the wrong reason.** Empty list only. "errors count as False" is `checkAutomationConditions_iff`. |
| `script.py::_ScriptRun._test_conditions` | `testConditions` | proven | `testConditions_nil` (exists, Proofs; `rfl`) | **correct for the wrong reason.** Empty list only. "stops at first error and returns None" follows from `testConditions_true_iff` and `testConditions_false_iff`. |
| `util/__init__.py::slugify` | `slugify?`, `slugifyChars`, `subRuns`, `delDigitCommas` | translated | `slugifyChars_valid`, `slugifyChars_of_valid`, `slugify_fixed_iff` (all exist) | **correct.** Each theorem states what the note says. `translated` fits: the output is not determined. |

All six `proven` entries are relative to `evalCond` on the member conditions. Not in scope but related: the entry
`helpers/config_validation.py::slug` (`HALean.Core.cvSlug`, `proven`) names `slugify_fixed_iff`. That theorem is
about `slugify?`, not `cvSlug`; the link is `cvSlug_ok` (`Core/ConfigValidationSpec.lean` line 519), one direction.

## PROPERTIES.md claims

`PROPERTIES.md` names 2 of the 239 theorems (`slugify_fixed_iff`, `slugifyChars_valid`), both in one row (line 148).
I split the row into three claims. Verdicts: correct 2, overstated 1.

1. "`helpers/config_validation.py::slug` (what it accepts) | `slugify_fixed_iff` | `""`, or non-empty `[0-9a-z_]`
   text without a leading, trailing or double `_`", under the section sentence "the translation is proved to decide
   exactly that predicate" (line 135). **overstated.** `slugify_fixed_iff` is about `slugify? s = some s` and has the
   hypothesis `slugify? s ≠ none`, which the row does not mention. For `cvSlug` only `cvSlug_ok` exists (accepted
   implies fixed point); no theorem says a valid slug is accepted by `cvSlug`.
2. "Relative to `util.slugify` transcribed step by step from python-slugify's legacy pipeline (`slugifyChars`)".
   **correct.** Compared with `slugify/_legacy.py` (9.1.2) lines 137 to 161 for ASCII text without entities.
3. "also `slugifyChars_valid` (every non-empty slugify result is such a slug)". **correct.**

Other rows that concern my implementation files name theorems of `Automation/Proofs.lean`, not of my modules
(line 38: `evalAnd_nil`, `evalOr_nil`, `evalNot_disabled`, `evalAnd_all_disabled`; item 10, lines 188 to 191).
`PROPERTIES.md` does not mention the condition `iff` theorems of `ConditionSpec.lean`, nor any theorem of
`ConfigSpec`, `LocationSpec`, `SunSpec`, `TimePeriodSpec`.
