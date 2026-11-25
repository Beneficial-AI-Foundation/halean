# core-registry-schemas

Modules: `HALean.Core.{ConfigValidationSpec, ProbatioProofs, ProbatioSpec, PyJsonSpec, SchemaSpec, ServiceRegistryProofs,
ServiceRegistrySpec, ServicesJsonSpec}`. Implementation files: `HALean/Core/{ServiceRegistry, Probatio, ConfigValidation,
Schema, ServicesJson, PyJson}.lean`.

379 theorems. Classes (from `core-registry-schemas.tsv`): C 16, O 118, E 89, H 156.

| module | C | O | E | H | total |
|---|---|---|---|---|---|
| ConfigValidationSpec | 1 | 32 | 19 | 8 | 60 |
| ProbatioProofs | 2 | 7 | 1 | 0 | 10 |
| ProbatioSpec | 9 | 32 | 57 | 31 | 129 |
| PyJsonSpec | 0 | 0 | 0 | 20 | 20 |
| SchemaSpec | 0 | 6 | 0 | 20 | 26 |
| ServiceRegistryProofs | 0 | 9 | 1 | 16 | 26 |
| ServiceRegistrySpec | 4 | 32 | 6 | 15 | 57 |
| ServicesJsonSpec | 0 | 0 | 5 | 46 | 51 |

Classification rules used, where the brief leaves room:

* A theorem `f x = .ok w ↔ ...` over all inputs is `C`, although it does not say which error a rejected input gets
  (12 of the 16 `C` are of this kind; see "Specifications independent of the code?").
* An iff or equation that fixes the result only for one constructor of the input is `E` (brief rule). This puts
  `cvBoolean_str_iff`, `checkPort_int_iff`, `checkClamp_int` and `cvEntityIds_list` in `E`.
* Theorems about the drivers' JSON readers, decoders and printers (`ServicesJson.lean`), about `dictSet`/`dictOf`
  (`PyJson.lean`), about `keyNames`/`groupsOf` and about `errorKind`/`runHandler` are `H`: these functions have no upstream
  counterpart (protocol, test harness or internal table).
* `validate_ok_iff` and the other `validate_*` theorems are `O`: their right-hand side is the opaque `Validator.run`, so
  they do not determine a result.

No theorem in these modules uses `sorry`, `native_decide` or an added axiom (`#print axioms` on six of them: `propext`,
`Classical.choice`, `Quot.sound` only).

## What the theorems constrain

### `Probatio.lean` (probatio leaf validators, error printing)

* `_TypeCheck`: `checkType_ok_iff` (C; all types except `float`: success iff `IsInstance`, value unchanged),
  `checkType_error` (O; every failure is `expected <name>`), `checkType_float_ok` (O; `_FloatCheck` success is a float kept
  or an int converted). For `float` there is no converse: no theorem says which ints are accepted.
* Literals: `checkLiteral_ok_iff` (C), `checkLiteral_error` (O). Stated through opaque `pyEq`.
* `In` / `NotIn`: `checkIn_ok_iff`, `checkNotIn_ok_iff` (C). Stated through opaque `pyEq`. No theorem on their messages.
* `Range`: `checkRange_ok`, `checkRange_min`, `checkRange_max`, `checkRange_not_number` (O). They give necessary conditions
  for success and one error case. No converse (in-range number is accepted). `rangeError_below_min`, `rangeError_no_min` (E)
  fix two messages for int bounds.
* `Clamp`: `checkClamp_not_number` (O); `checkClamp_int`, `checkClamp_int_bounds`, `checkClamp_int_inside` (E; int bounds
  and int value only). Nothing for floats, one-sided bounds, or `a > b`.
* `Length`: `checkLength_ok_iff` (C). Messages: only `checkLength_int` (E).
* `Coerce`: `checkCoerce_str_iff` (C, relative to `pyStr`); `checkCoerce_int` (O; result is an int), `checkCoerce_float`
  (O; result is a float), `checkCoerce_int_error` (O). Which int or float is produced is fixed only for `int`, `bool`,
  `float`, `None` inputs (E theorems). `Coerce(int)` on a `str` or `float` and `Coerce(float)` on a `str` or `int` have no
  theorem that determines the value.
* `Lower` / `Upper`: `checkLower_ok_iff`, `checkUpper_ok_iff` (C, relative to `strOf`), `checkLower_ok_iff_checkUpper_ok` (O).
* `EnsureList`: `ensureList_none`, `ensureList_list` (E), `ensureList_scalar` (O) together cover every input;
  `ensureList_is_list`, `ensureList_idem` (O).
* `AtLeastOne`: `checkAtLeastOne_ok_iff` (C, through opaque `pyEq`), `checkAtLeastOne_non_dict` (O).
* `Port`: `checkPort_range` (O; result is an int in 1..65535), `checkPort_int_iff` (E; ints). No theorem for `str` or
  `float` inputs beyond `checkPort_range`.
* `int(str)`: `pyIntOfStr?_iff` (C; `parseIntStr` plus the 4300-digit limit), `pyIntOfStr?_short` (O).
* `_BARE_KEY`: `isBareKey_iff` (C).
* `render_path`: `renderPath_append_idx`, `renderPath_append_bare_key`, `renderPath_append_quoted_key` (O) give the effect of
  a trailing index, a trailing bare key of at most 500 characters, and a trailing non-bare key not starting with `<`.
  `renderSegment_short`, `renderSegment_long` (O). Group segments and keys starting with `<` have no theorem.
* `Invalid.__str__`, `MultipleInvalid.__str__`: `SchemaError.str_path`, `multipleInvalidStr_first` (O).
* `_format_candidates`: lengths 0 to 3 (`formatCandidates_nil/_one/_two/_three`, E). `getCloseMatches_length` (O) bounds
  the length by `n`, so these four cover every call the code makes.
* `get_close_matches`: `getCloseMatches_length`, `getCloseMatches_mem` (O). `suggestionSuffix_cases`,
  `suggestionSuffix_non_str` (O). `extraKeyError_path`, `extraKeyError_message` (O).
* `_expected_label`: `expectedLabel_unlabelled`, `expectedLabel_labelled` (O) together determine it; `label?_*` (E) fix
  `_branch_label` per constructor.
* `_sorted_for_message`, `_display`: `sortedForMessage_perm`, `sortedForMessage_mixed`, `displayList_ok_short`,
  `displayList_ok_long`, `displayList_error` (O).

### `ConfigValidation.lean` (`cv.*`)

* `cv.positive_timedelta`: `cvPositiveTimedelta_ok_iff` (C).
* `cv.string`: `cvString_str`, `cvString_rejects` (E), `cvString_other` (O) together cover every input (relative to
  `strOf`); `cvString_ok_str`, `cvString_idem` (O).
* `cv.boolean`: `cvBoolean_str_iff` (E; strings, relative to `cvBooleanText`), `cvBoolean_bool`, `cvBoolean_int` (E),
  `cvBoolean_ok_bool`, `cvBoolean_idem` (O).
* `cv.entity_id`, `cv.entity_ids`, `cv.entities_domain`, `cv.entity_domain`: `cvEntityId_ok`, `cvEntityId_valid`,
  `cvEntityIds_valid`, `cvEntityIds_list_length`, `cvEntityIds_str_length`, `cvEntitiesDomain_ok`, `cvEntitiesDomain_valid`,
  `cvEntitiesDomain_one`, `cvEntitiesDomain_many`, `cvEntityDomain_ok`, `cvEntityDomain_valid`, `cvEntityDomain_one` (O).
  All are of the form "if it succeeded, the output has property P". None says when it succeeds.
* `cv.slug`, `cv.color_hex`: `cvSlug_ok`, `cvColorHex_ok` (O; same form).
* `cv.time_period_str`, `cv.time_period_seconds`, `timedelta(**value)`: `cvTimePeriodStr_ok`, `cvTimePeriodSeconds_ok`,
  `cvTimedeltaKwargs_ok` (O; the result is some timedelta), `cvTimePeriodStr_other`, `cvTimedeltaKwargs_non_dict` (O).
  Which timedelta is not stated.
* Dispatcher `CvFn.run`: `CvFn.run_string`, `_boolean`, `_entityId`, `_entityIds`, `_entityDomain`, `_slug_colorHex`,
  `_timedelta` (O; output type per function).

### `ServiceRegistry.lean` (`core.py::ServiceRegistry`)

* `has_service`: `hasService_eq_asyncServicesForDomain` (C), `has_after_register`, `has_after_remove` (O).
* `supports_response`: `supportsResponse_ok_iff` (C), `supportsResponse_ok_iff_hasService`, `supportsResponse_error` (O).
* `SupportsResponse(value)`: `SupportsResponse.ofString?_eq_some_iff` (C).
* `_async_register` / `_async_remove`: `wf_register`, `wf_remove` (O; keys stay lowercase), `has_after_register`,
  `has_after_remove`, `asyncServices_after_register` (O).
* `return_response` rules: `responseCheck_none_iff` (C), `responseCheck_error`, `responseCheck_optional` (O).
* `async_call` before the handler: `prepareCall_not_found`, `prepareCall_response_error`, `prepareCall_ok`,
  `prepareCall_ok_schema`, `prepareCall_of_unsupportedCall`, `prepareCall_event` (O).
* `async_call` after the handler: `finishCall_non_blocking`, `finishCall_blocking_error`, `finishCall_blocking_no_logs`,
  `finishCall_no_response`, `finishCall_response_dict`, `finishCall_response_not_dict` (O). These six cover every case of
  `finishCall`, except the text of the log message, which is existentially quantified.
* `async_call` as a whole: `asyncCall_events`, `asyncCall_prepare_error`, `asyncCall_non_blocking`,
  `asyncCall_blocking_no_logs`, `call_not_found`, `call_after_remove_not_found`, `call_return_response_needs_blocking`,
  `call_none_return_response_errors`, `call_only_needs_return_response` (O). The five `call_*` theorems assume `r.WF`.
* `target` merging: `mergeTarget_keeps_keys`, `mergeTarget_has_target_keys` (O). The merged values and key order are not
  stated, except for a one-key target (`mergeTarget_single`, E).
* Translated messages: `rstripDots_prefix` and `rstripDots_no_trailing_dot` (O) together are `str.rstrip(".")`;
  `exceptionMessage_unknown`, `exceptionMessage_no_placeholders`, `exceptionTemplate_isSome_iff` (O).

### `Schema.lean`

* `SchemaSpec.validate` (wrapper of `Schema.__call__`): `validate_ok_iff`, `validate_ok`, `validate_of_run`,
  `validate_error_of_run`, `validate_invalid`, `validate_error_after_ok` (O). They say the wrapper passes the evaluator's
  result through and converts keys. They say nothing about what the evaluator returns.

### `ServicesJson.lean`, `PyJson.lean`

No `C` or `O` theorem. The 5 `E` theorems (`timePeriodDict_shape`, `timePeriod_shape`, `decodeCv_probatio_objects`,
`decodeCv_time_periods`, `decodeCv_comp_entity_ids`) fix the validator terms that 11 fixed `cv.*` names decode to. I compared
them with `helpers/config_validation.py` lines 183-197, 314, 369-372, 475-486, 566-568, 583-584: they match.

## What they do not constrain

### (a) Partial defs

`logs/defs.tsv` lists 17 `partial` definitions in the six implementation files, and `pyEq` (`HALean/Template/Value.lean:338`)
is used by them. `#print` shows each as an `opaque` constant, for example
`opaque HALean.Core.Validator.run : Extra → Validator → Value → VResult`. The kernel does not see the recursive code. A
theorem that mentions one of these holds for any function of that type put in its place. So it cannot say anything about
what the compiled code computes.

Checked with `lake env lean class/scratch/crs_check.lean`: none of the following is provable by `rfl` or `decide`:
`pyEq (.bool true) (.int 1) = true`, `safeValue (.str "a") = true`,
`(Validator.type .int).run .prevent (.int 1) = .ok (.int 1)`, `checkIn [.int 1] (.int 1) = .ok (.int 1)`,
`SchemaSpec.validate {fields := []} [] = .ok []`, `cvString (.int 1) = .ok (.str "1")`.

Theorems whose statement names a partial def (from column 9 of `logs/theorems.tsv`), 15 in total:

* `pyEq` (4): `checkIn_ok_iff`, `checkNotIn_ok_iff`, `checkLiteral_ok_iff`, `checkAtLeastOne_ok_iff`. Each says "succeeds
  iff `pyEq` returns true". They restate the `if` of the definition. They do not say that `pyEq` is Python `==`, nor that
  `1` is in `[1]`.
* `safeValue` (4): `requireSafe_ok_iff`, `strOf_ok_iff`, `pyInt?_str`, `specText_ok_iff`. The first, second and fourth say
  "succeeds iff `safeValue v = true`". `pyInt?_str` assumes `safeValue (.str s) = true`, which cannot be proved for any `s`.
* `Validator.run` (7): `validate_eq`, `validate_ok`, `validate_of_run`, `validate_ok_iff`, `validate_error_of_run`,
  `validate_invalid`, `validate_error_after_ok`. They describe the wrapper around the evaluator, for any evaluator.

Theorems that reach a partial def through another function are affected in the same way:

* Through `strOf` / `requireSafe` (which call `safeValue`): `checkLower_ok_iff`, `checkUpper_ok_iff`, `cvString_other`,
  `cvTimePeriodStr_other`, `cvSlug_ok`, `cvColorHex_ok`, `CvFn.run_slug_colorHex`, `requireSafe_error`, `strOf_error`,
  `specText_ok_iff_requireSafe`. `cvEntityId` calls `requireSafe` on every success path, so the hypothesis
  `cvEntityId v = .ok w` cannot be proved for any concrete `v`. This affects `cvEntityId_ok`, `cvEntityId_valid`,
  `cvEntityIds_valid`, `cvEntitiesDomain_*`, `cvEntityDomain_ok/_valid/_one`, `CvFn.run_entityId/_entityIds/_entityDomain`.
  They are implications that hold for any `safeValue`; no theorem shows a non-empty input for which the premise holds.
* Through `SchemaSpec.validate`: `prepareCall_ok_schema`, and every `prepareCall`/`asyncCall` theorem when the service has a
  schema. `prepareCall_ok` and `asyncCall_events` then say "if validation succeeded ...", for any evaluator.
* Through `reprHelper` (via `ServiceCall.repr`): `finishCall_non_blocking` states the log record as `∃ msg`; the message
  text is not determined. `ServiceCall.repr_no_data` covers only empty data.

Partial defs that no theorem statement mentions (15 of the 17): `runAll`, `runAny`, `runSequence`, `runMapping`
(`Schema.lean`), `reprHelper` (`ServiceRegistry.lean`), `decodeValidator`, `decodeField`, `decodeFields`
(`ServicesJson.lean`), `skipWs`, `strBody`, `digits`, `value`, `obj`, `arr`, `orjsonFix` (`PyJson.lean`). The two that are
mentioned are `safeValue` and `Validator.run`.

Consequence for upstream functions. All of these manifest entries have only partial code behind them and no theorem about
their behaviour: `_MappingValidator.__call__`, `_collect`, `_unmatched`, `_finalize`, `_check_groups`,
`_empty_exclusive_group`, `_SequenceValidator.__call__`, `_validate_item`, `All.__call__`, `Any.__call__`, `_run_any`,
`Schema.__call__` (beyond the wrapper), `util.repr_helper`.

### (b) JSON decoders, parsers, drivers

* `parsePyJson`, `orjsonLoads` and every parser piece (`number`, `hex4`, `expectLit`, `peek`, `next`, ...): no theorem.
  `PyJsonSpec` covers only `dictSet`, `dictOf`, `strItems?`, `get?`.
* `decodeValidator`, `decodeField`, `decodeFields`: no theorem. `decodeSchema` has one theorem, for a missing or `null`
  schema (`decodeSchema_none`). So nothing is proved about any decoded schema that has fields: not the duplicate-key check,
  not the `specText` checks, not the mapping from JSON to `Validator`.
* `decodeCv`: 11 fixed names (E theorems) and one error case. The names `string`, `boolean`, `entity_id`, `entity_ids`,
  `color_hex`, `slug`, `icon`, `time_period_str`, `time_period_seconds` and `entity_domain` with a domain have no theorem.
* `decodeHandler`: three partial facts (`_none`, `_return`, `_raise`). The `echo` branch and the message of a `raise`
  handler have no theorem.
* `Exe/CoreServices.lean` (`step`, `processLine`, `loop`): outside these modules; no theorem in these modules mentions them.
* Output: `eventJson_fields`, `errorJson_fields`, `logJson_fields`, `contextJson_fields` state that named fields are present
  with given values. `reprOr (dictOf e.data)` is not determined further.

### (c) Entry points

* `SchemaSpec.validate`: theorems exist (6, all O), all relative to the opaque evaluator. There is no theorem of the form
  "this schema on this data returns this", not even for the empty schema.
* `Registry.asyncCall`: 9 theorems name it. All are about error paths, event count, or logs. No theorem states the result
  of a successful blocking call in terms of the handler and the data. The pieces exist (`prepareCall_ok`,
  `finishCall_response_dict`, `finishCall_no_response`, `runHandler_ret`) and are not composed.
* `Registry.register`, `Registry.remove`: no theorem states the fired event, the log record for an unknown service, that
  other services are kept, that a re-registered service replaces the old one, or that `lookup` after `register` returns the
  new service.
* `CvFn.run`: output-type theorems per function, none for `.icon`.

### Other definitions with no `C`/`O` theorem

* `cvIcon`, `findLongestMatch`, `matchingSize`, `invWith`, `SUGGESTION_CUTOFF`: not mentioned in any statement.
* `seqRatio`: appears only as an uninterpreted score in `getCloseMatches_mem`. The difflib model (`findLongestMatch`,
  `matchingSize`, `seqRatio`, the autojunk rule, the sort order of `getCloseMatches`) has no theorem. So no theorem
  determines which names a "did you mean" suffix lists, or their order.
* `rangeError`: two E theorems (int bounds). The exclusive-bound messages and float bounds have none.
* `checkRange`: no theorem that an in-range number is accepted.
* `pyFloat?`: two E theorems (`float`, `None`).
* `cvTimePeriodStr`, `cvTimePeriodSeconds`, `cvTimedeltaKwargs`: the computed duration is not stated.
* `renderPath` on `.group` segments; `extraKeyError` suggestions.
* `exceptionTemplate`: which keys exist, not the texts. `formatPlaceholders`: no theorem that a placeholder is replaced.
* `Registry.find` is specified only under `WF` (`find_eq`, H).

## Assumptions that nothing checks

| theorem | hypothesis | where the value comes from at run time | discharged? |
|---|---|---|---|
| `call_not_found`, `call_after_remove_not_found`, `call_return_response_needs_blocking`, `call_none_return_response_errors`, `call_only_needs_return_response`, `find_eq`, `find_none`, `find_some`, `lookup_lower` | `r.WF` (all keys lowercase) | `Exe/CoreServices.lean` starts `loop` with `[]` and changes the registry only by `register`/`remove`; `Hass.lean` has `services : Registry := []` and updates it at lines 570-581 by `register`/`remove` | Partly. `wf_empty`, `wf_register`, `wf_remove` give the induction steps. No theorem states `WF` for the driver's `step` or for a reachable `Hass` state. `wf_*` are not used outside the two registry proof files (grep). |
| `call_return_response_needs_blocking`, `call_none_return_response_errors`, `call_only_needs_return_response` | `r.lookup a.domain.toLower a.service.toLower = some svc` | registry content | No. No theorem says `lookup` after `register` returns `svc` (`has_after_register` gives `hasService` only). |
| `has_after_register`, `has_after_remove`, all `toLower` statements | `String.toLower` is Lean's ASCII lowering; upstream uses `str.lower()` | names from JSON (`getName` rejects non-ASCII) or from `Hass` actions | `getName_ok_iff` shows `getName` returns ASCII text. No theorem links it to `register`/`asyncCall`. Names that reach the registry inside `Hass.lean` were not examined here. |
| `pyInt?_str` | `safeValue (.str s) = true` | `safeValue` is a partial def | No. Not provable for any `s`. |
| `cvTimePeriodStr_other` | `strOf v = .ok s` | `strOf` calls `safeValue` | No. Not provable for any `v`. |
| `cvEntityId_ok`, `cvEntityId_valid`, `cvEntityIds_valid`, `cvEntitiesDomain_ok/_valid/_one/_many`, `cvEntityDomain_ok/_valid/_one`, `cvSlug_ok`, `cvColorHex_ok`, `CvFn.run_entityId/_entityIds/_entityDomain/_slug_colorHex` | `f v = .ok w` | success needs `safeValue` true | Not provable for any concrete non-empty input. `cvEntityIds (.list []) = .ok []` (`cvEntityIds_nil`) is the only instance shown. |
| `validate_of_run`, `validate_error_of_run`, `validate_error_after_ok` | a given result of `Validator.run` | partial def | No. No theorem gives any value of `Validator.run`. |
| `prepareCall_ok`, `prepareCall_ok_schema`, `prepareCall_event`, `asyncCall_non_blocking` | `r.prepareCall a c = .ok p` | with a schema, needs `validate` to succeed | Only for services without a schema (then all functions involved are kernel-reducible). |
| `prepareCall` code comment "never reached: the drivers answer `unsupported` first" (`ServiceRegistry.lean:358`) | `unsupportedCall? a = none` whenever `prepareCall` is run | `Exe/CoreServices.lean:85`, `Hass.lean:607` | `prepareCall_of_unsupportedCall` gives one direction (`some why` → error). No theorem that `unsupportedCall? = none` implies `prepareCall` does not return the `unsupported` error, and the driver is not covered. |
| `displayList_ok_short`, `displayList_ok_long` | `vs.mapM reprOf = .ok rs` | container members of a schema | No theorem that `reprOf` succeeds on scalars. The decoder restricts `in`/`not_in` members to scalars, in partial code. |
| `checkRange_min`, `checkRange_max` | the bound has `num?` | decoded by `getNum?` | `getNum?_num` proves it for `getNum?`. The call site is in `decodeValidator` (partial), so the link is not a theorem. |
| `checkClamp_int`, `checkClamp_int_bounds` | `a ≤ b` | schema JSON | Nothing checks it. The decoder accepts any two numbers. |
| `nodup_keys_dictSet` | input keys distinct | `obj` builds dicts by `dictSet` from `[]` | Step lemma only. `obj` is partial; no theorem about parser output. |
| `renderPath_bare_key`, `renderPath_append_bare_key`, `renderPath_key_idx` | `k.length ≤ 500` | schema keys | Nothing bounds key length. The other case has no theorem. |
| `expectedLabel_labelled` | `vs.mapM Validator.label? = some labels` | schema | It is the definition's own intermediate value. |
| `slugify_fixed_iff` (outside these modules, used by the manifest for `cv.slug`) | `slugify? s ≠ none` | `cvSlug` returns `unsupported` otherwise | Consistent with the code, but `cvSlug_ok` is the only link and goes one way. |

Vacuous, weaker than they read, or restatements:

* Restatements proved by `rfl` or by unfolding one `if`/`match`, which say nothing independent of the code:
  `SchemaError.str_no_path`, `SchemaError.str_path`, `multipleInvalidStr_first`, `multipleInvalidStr_inv`, `inv_single`,
  `extraKeyError_path`, `extraKeyError_message`, `translatedError_spec`, `cvEntityIds_list`, `pyIter_list`, `pyIter_dict`,
  `groupsOf_eq_foldl`, `validate_eq`, `formatPlaceholders_nil`, `mergeTarget_falsy`, `runHandler_ret`,
  `timePeriodDict_shape`, `timePeriod_shape` (first conjunct), `decodeCv_probatio_objects`, `decodeCv_time_periods`,
  `decodeCv_comp_entity_ids`, `contextJson_fields`, `eventJson_fields`, `pyStrLt_iff`, `safeText_iff`, `isAscii_iff`,
  `requireSafe_ok_iff`, `specText_ok_iff`, `checkIn_ok_iff`, `checkNotIn_ok_iff`, `checkLiteral_ok_iff`, and the closed-term
  E theorems (`checkPort_bool`, `checkCoerce_int_none`, `cvString_rejects`, ...).
* `renderPath_foldl`: the right-hand side `renderStep` is a copy of the loop body written in the spec file. The theorem says
  the `for` loop is a fold. It is used as a lemma.
* `extraKeyError_message`: `∃ suffix, message = "not a valid option" ++ suffix`. True by definition for any suffix function.
* `renderSegment_long`: `∃ pre, renderSegment r = pre ++ "..."`. It does not say `pre` is the first 497 characters.
* `suggestionSuffix_cases`: the candidates are "some list of 1 to 3 pool members". Which ones is not stated.
* `finishCall_non_blocking`: the log message is `∃ msg`.
* `call_none_return_response_errors`: `∃ key ph`. The key is not stated (it is one of two).
* `validate_ok_iff`: an iff between the wrapper and an opaque function.
* `checkAtLeastOne_no_keys`, `cvBoolean_none`: `≠ .ok w` only; the error is not stated.
* `rangeError_no_min`: holds for every `x`, including values in range; `rangeError` is only called out of range.
* No theorem has a `True` conclusion. I found no theorem whose hypotheses contradict each other.

## Specifications independent of the code?

16 `C` theorems.

Right-hand side written separately from the implementation (5):

* `isBareKey_iff`: `BareKey`, a `Prop` over the character list (`ProbatioSpec.lean:80`). It has the same shape as the
  definition.
* `checkType_ok_iff`: `IsInstance` (`ProbatioSpec.lean:491`), a separate predicate. It mirrors the `match` of `checkType`.
* `checkLength_ok_iff`: bounds written as two universally quantified inequalities over `pyLen?`.
* `responseCheck_none_iff`: two implications over `returnResponse`, `blocking`, `supportsResponse`.
* `SupportsResponse.ofString?_eq_some_iff`: `str = s.value`, the inverse of a separately defined function.

Restatement of the implementation's own condition or case split (11): `checkIn_ok_iff`, `checkNotIn_ok_iff`,
`checkLiteral_ok_iff`, `checkAtLeastOne_ok_iff` (the `if` condition, with opaque `pyEq`), `checkCoerce_str_iff` (relative to
`pyStr`), `checkLower_ok_iff`, `checkUpper_ok_iff` (relative to `strOf`), `pyIntOfStr?_iff` (relative to `parseIntStr`),
`cvPositiveTimedelta_ok_iff`, `hasService_eq_asyncServicesForDomain`, `supportsResponse_ok_iff`.

None of the 16 compares the model with a specification of Python or probatio semantics that is larger than a few lines.
There is no regular-expression semantics or reference interpreter in these modules.

Second split of the same 16: 4 determine the whole result (`isBareKey_iff`, `pyIntOfStr?_iff`,
`SupportsResponse.ofString?_eq_some_iff`, `hasService_eq_asyncServicesForDomain`); 12 determine when the function succeeds
and with what value, and leave the error unspecified. For `checkType` and `checkLiteral` a separate `O` theorem fixes the
error (`checkType_error`, `checkLiteral_error`). For `checkIn`, `checkNotIn`, `checkLength`, `checkCoerce .str`,
`checkLower`, `checkUpper`, `checkAtLeastOne`, `cvPositiveTimedelta`, `responseCheck`, `supportsResponse` the error (and
whether it is `invalid` or `unsupported`) is not determined, or only its class is (`responseCheck_error`,
`supportsResponse_error`).

## Docstring claims

Claims checked: 311. These are the 293 theorem docstrings (column 8 of `logs/theorems.tsv`) and 18 claims in the 8 module
headers (ProbatioSpec 2, ProbatioProofs 1, ConfigValidationSpec 2, SchemaSpec 2, PyJsonSpec 2, ServicesJsonSpec 2,
ServiceRegistrySpec 1, ServiceRegistryProofs 6). Docstrings on `def`s in the spec files are not counted.

Verdicts: correct 292, overstated 16, false 3, correct for the wrong reason 0, stale 0.

The module headers' statements about partial defs are correct: `ProbatioSpec.lean:8` ("`pyEq` and `safeValue` are
`partial def`s, so they appear here only as opaque predicates"), `SchemaSpec.lean:4-9` ("cannot be unfolded ... with the
evaluator as an opaque function"), `PyJsonSpec.lean:7` ("The parser itself ... is not covered here"),
`ServicesJsonSpec.lean:7` ("`decodeValidator`, `decodeField` and `decodeFields` ... are not covered"),
`ConfigValidationSpec.lean:6`.

False (3):

1. `pyIntOfStr?_iff` (`ProbatioSpec.lean:363`): "CPython's `sys.int_info.str_digits_check_threshold` limit". The 4300 limit
   is `sys.int_info.default_max_str_digits`; `str_digits_check_threshold` is 640 (checked in `/opt/havenv` Python). The
   number in the statement is right, the named constant is wrong.
2. `isScalar_label` (`ServicesJsonSpec.lean:157`): "A scalar that is not a string always has a `repr`". The hypothesis is
   `∀ f, v ≠ .float f`: floats are excluded, strings are included.
3. `timePeriod_shape` (`ServicesJsonSpec.lean:259`): "none of them has a branch label". The third branch is `.type
   .timedelta`, which has the label `timedelta` (`label?_type`). The statement proves `expectedLabel [...] = none`, which
   holds because not every branch has a label.

Overstated (16):

1. `renderSegment_long` (`ProbatioSpec.lean:104`): "A long repr is cut and ends with an ellipsis". The statement gives only
   the ending.
2. `pyStrLt_iff` (`:210`): "Python's `str` ordering is Lean's (code points)". The statement unfolds `decide (a < b)`.
   Nothing about Python is stated.
3. `extraKeyError_only_self` (`:282`): "The key itself is never suggested". Proved only for a schema whose single key is
   the unknown key.
4. `label?_validators` (`:434`): "so `Any` reports the deepest branch error instead of "expected ..."". `runAny` is partial;
   no theorem about what `Any` reports.
5. `expectedLabel_int_or_none` (`:481`): "`Any(int, None)` fails with "expected int or None"". The statement is about
   `expectedLabel` only. (probatio 0.13.0 does print this message; checked by running it.)
6. `checkCoerce_int_error` (`:789`): "`Coerce(int)` and `Coerce(float)` fail only with ...". Only `Coerce(int)` is proved.
7. `checkLength_int` (`:725`): "A number has no length". Proved for `int` only.
8. `checkIn_ok_iff` (`ProbatioProofs.lean:9`): "(Python `==`, so `True` is a member of `[1]`)". The statement is in terms
   of opaque `pyEq`; `pyEq (.bool true) (.int 1) = true` is not provable.
9. `cvBoolean_int` (`ConfigValidationSpec.lean:133`): "A number is truthy when non-zero". Proved for `int` only; no theorem
   for `float`.
10. `CvFn.run_string` (`:560`): "The whole dispatcher". No theorem for `.icon`.
11. `contextJson_fields` (`ServicesJsonSpec.lean:376`): "exactly the three upstream fields". Presence of three fields is
    proved, not absence of others.
12. `errorJson_translation` (`:419`): "The translation fields appear only for a translated error". Only `translation_key`
    is stated.
13. `prepareCall_of_unsupportedCall` (`ServiceRegistrySpec.lean:442`): "`unsupportedCall?` is exactly the case where ...".
    One direction is proved.
14. Header of `ConfigValidationSpec.lean:2-4`: "what each accepts, the type of what it returns, and its error cases". An
    acceptance iff exists for `cv.positive_timedelta` and for `cv.boolean` on strings only; `cv.icon` has no theorem.
15. Header of `ServicesJsonSpec.lean:2-5`: lists "the handler / schema / context decoders". `decodeSchema` has one theorem,
    for the no-schema input.
16. Header of `ServiceRegistryProofs.lean:18-20`: "`Registry.WF` ... holds for the empty registry and is preserved by
    `register` and `remove`, so it holds for every registry the model can reach". The first two parts are proved
    (`wf_empty`, `wf_register`, `wf_remove`). There is no definition of reachable and no theorem for the driver or `Hass`.

Upstream facts in docstrings that I checked against source and found correct: the `cv.string` messages
(`config_validation.py:656-668`), the `cv.*` object definitions (lines 183-197, 314, 369, 475, 566, 583),
`TIME_PERIOD_ERROR` (119), "wrap time values in quotes" for an `int` (525), `_COLOR_HEX` (460), `has_service` and
`async_services_for_domain` lowercasing (`core.py:2676`, `2656`), `supports_response` `KeyError` (2685), the exception
classes (`exceptions.py:110,114,379,415`), probatio messages (`_messages.py`), `_BARE_KEY` and the 500 limit
(`error.py:36,78`), cutoff 0.7 (`error.py:327`), `Port` on `True`, `None`, `0`, `65536` (run). I could not check the five
English templates of `exceptionTemplate`: `components/homeassistant/strings.json` is not in `upstream/ha-core`.

## manifest.yaml claims

72 manifest entries have a `lean:` name in the six implementation files (66 `translated`, 6 `proven`). 12 of them are
`proven` or name a theorem in `notes:`. Verdicts: correct 6, overstated 6, false 0, stale 0, correct for the wrong reason 0.

| entry | status | theorems named | exist | verdict |
|---|---|---|---|---|
| `helpers/config_validation.py::boolean` | proven | `cvBooleanText_iff` (`Template/CvBooleanSpec.lean:26`) | yes | overstated. The theorem is about `cvBooleanText`. `cvBoolean_str_iff` links it to `cvBoolean` for strings. The error message for a rejected string, the `float` case and other types are not determined ("Numbers and bools: direct": `cvBoolean_bool`, `cvBoolean_int` exist, nothing for `float`). |
| `core.py::ServiceRegistry.has_service` | proven | `has_after_register`, `has_after_remove` | yes | overstated. Both state what the note says. They are two properties, not a determination. `hasService_eq_asyncServicesForDomain` restates the definition. |
| `core.py::ServiceRegistry._async_register` | proven | `has_after_register` | yes | overstated. One property. No theorem on the fired event, on replacing a service, or on keeping other services. |
| `core.py::ServiceRegistry._async_remove` | proven | `has_after_remove`, `call_after_remove_not_found` | yes | overstated. Two properties (the second assumes `WF`). No theorem on the event, the warning, or other services. |
| `core.py::ServiceRegistry.async_call` | proven | `call_none_return_response_errors`, `call_only_needs_return_response`, `call_return_response_needs_blocking`, `call_after_remove_not_found` | yes | overstated. Four error paths, each under `WF`. The successful path is not determined; with a schema it depends on the partial evaluator. |
| `probatio:validators/comparison.py::Range.__call__` | translated | `checkRange_ok`, `checkRange_min`, `checkRange_max`, `checkRange_not_number` | yes | correct |
| `probatio:validators/comparison.py::In.__call__` | translated | `checkIn_ok_iff` | yes | correct (the theorem is relative to opaque `pyEq`) |
| `probatio:validators/comparison.py::NotIn.__call__` | translated | `checkNotIn_ok_iff` | yes | correct (same remark) |
| `probatio:validators/coerce.py::Coerce.__call__` | translated | `checkCoerce_int` | yes | correct |
| `probatio:validators/structural.py::EnsureList.__call__` | translated | `ensureList_is_list`, `ensureList_list` | yes | correct |
| `probatio:validators/network.py::Port.__call__` | translated | `checkPort_range` | yes | correct |
| `helpers/config_validation.py::slug` | proven | `slugify_fixed_iff` (`Automation/SlugifySpec.lean:413`) | yes | overstated. The theorem is about `slugify?`, under `slugify? s ≠ none`. The note says `cv.slug` "accepts exactly" those texts. The only link is `cvSlug_ok` (success implies fixed point). The converse is not proved, and `cvSlug` succeeds only through `strOf`, which depends on opaque `safeValue`. |

## PROPERTIES.md claims

8 claims refer to theorems of these modules: the 7 table rows at lines 41-47 and the paragraph "Service schemas"
(lines 244-248). Verdicts: correct 4, overstated 4, false 0, stale 0, correct for the wrong reason 0.

| line | claim | verdict | evidence |
|---|---|---|---|
| 41 | `has_after_register`: case-insensitive registration | correct | statement at `ServiceRegistryProofs.lean:190` |
| 42 | `has_after_remove`, `call_after_remove_not_found`: after remove, `has_service` false, `async_call` raises `ServiceNotFound`, no event, no log | correct | `:202`, `:275`; the result record has default `events := []`, `logs := []`. The second theorem assumes `r.WF` (line 44 says so). |
| 43 | the three `call_*` theorems: each violation raises `ServiceValidationError` before schema, event, handler | correct | `:286-310`; assume `r.WF` and that the service exists |
| 44 | `wf_register`, `wf_remove`: "every reachable registry has only lowercase domain and service keys" | overstated | The two theorems are preservation steps. No reachability statement exists; `wf_*` are not used outside `ServiceRegistryProofs.lean` and `ServiceRegistrySpec.lean`. |
| 45 | `checkIn_ok_iff`, `checkNotIn_ok_iff`: `In` accepts exactly the members "(Python `==`, so `True` is a member of `[1]`)" | overstated | The statements are in terms of `pyEq`, a `partial def` (`Template/Value.lean:338`). The example is not provable in Lean (scratch check). |
| 46 | `checkRange_*`: "`Range` never accepts a number outside its bounds ..., nor a value that is not a number" | overstated | `checkRange_ok` and `checkRange_not_number` assume `mn.isSome ∨ mx.isSome`. Without a bound `checkRange` accepts any value (`Probatio.lean:510`), as probatio does. The row omits the hypothesis. |
| 47 | `ensureList_is_list`, `checkCoerce_int`, `checkPort_range` | correct | `ProbatioProofs.lean:80, 86, 97` |
| 246-248 | "the leaf validators are total and proved in `HALean/Core/ProbatioProofs.lean` (table above)" | overstated | The leaf validators are `def`s, but `checkIn`, `checkNotIn`, `checkLiteral`, `checkAtLeastOne` call partial `pyEq`, and `strOf`/`pyInt?`/`pyFloat?` call partial `safeValue`. `ProbatioProofs.lean` has 10 theorems on 6 validators, mostly one-directional. `Clamp`, `Length`, `Lower`, `Upper`, `AtLeastOne`, type and literal checks are in `ProbatioSpec.lean`. |

The same paragraph says `Validator.run` is "`partial` for now" and lists properties as "next candidates". That part is
correct: none of them is proved.

Lines 147 and 148 (`cv.boolean` on strings, `cv.slug`) name theorems of other modules (`cvBooleanText_iff`,
`slugify_fixed_iff`); they are not counted here. See the manifest table for how far `cvBoolean_str_iff` and `cvSlug_ok`
connect them to `cvBoolean` and `cvSlug`.
