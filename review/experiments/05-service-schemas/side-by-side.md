# Side by side: service schemas

Upstream: probatio 0.13.0 (`/opt/havenv/lib/python3.14/site-packages/probatio/`, written `P:` below),
Home Assistant 2026.10.4 (`/opt/havenv/lib/python3.14/site-packages/homeassistant/`, written `HA:`),
python-slugify 9.1.2 (`.../site-packages/slugify/`), CPython 3.14.
Lean: `/home/user/halean/HALean/...` at commit `f638a377`.

Every row is one `manifest.yaml` entry (or a group of entries with the same Lean target). Fuzz counts quoted in a
row come from `logs/fuzz-numeric-seed1.log`, `logs/fuzz-text-seed1.log` and `logs/fuzz-messages-seed1.log`
(fast tools, see `README.md`); harness counts are in `FINDINGS.md`.

## 1. The engine (`HALean/Core/Schema.lean`)

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `probatio:schema.py::Schema.__call__` | `P:schema.py:314`, bootstrap and compile policy `P:schema.py:427-493` (`_AUTO_COMPILE_THRESHOLD = 50`, `schema.py:142`) | `SchemaSpec.validate` `Schema.lean:187`, `multipleInvalidStr` `Probatio.lean:224` | Lean always runs the interpreted engine. Upstream switches a `Schema` object to generated code (`P:_codegen.py`) at its 50th validation. The generated code differs from the interpreted engine in one place found: **SCH-3**. The README (lines 648-652) names the gap and says the generated code "is meant to behave like the interpreted engine". |
| `probatio:_compile.py::_make_candidate` | `P:_compile.py:434-558` | `ServicesJson.decodeField` `ServicesJson.lean:211-234`, `Field`/`KeyMarker` `Probatio.lean:298-371` | Lean refuses `Exclusive`/`Inclusive` together with `required`, duplicate keys, non-string groups. None are built by `schema_spec.py` in a different way (it would take `exclusive` first, `schema_spec.py:81-89`); HALean answers `unsupported`. No difference for accepted specs. |
| `probatio:_engine.py::_MappingValidator.__call__` | `P:_engine.py:213-288` | `runMapping` `Schema.lean:114-182` | No difference found. Data order then `_finalize` then `_check_groups` on both sides; `out[key] = ...` in place is `store` (`Schema.lean:121`). A non-mapping is "expected a mapping" (`_engine.py:220`, `Schema.lean:115`). The inlined type check (`_engine.py:250-258`) gives the same message as `_TypeCheck`. |
| `..._collect` | `P:_engine.py:441-455` | `prependAll` `Probatio.lean:84`, used at `Schema.lean:133,152,168` | No difference found (`error_type` is not printed). |
| `..._unmatched`, `..._extra_key_error` | `P:_engine.py:457-508` | `Schema.lean:135-142`, `extraKeyError` `Probatio.lean:219` | No difference found. The key itself is excluded from the suggestion pool on both sides. Non-string data keys cannot arrive through JSON. |
| `..._finalize` | `P:_engine.py:510-562` | `Schema.lean:144-154` | No difference found. `Exclusive` members are not finalizers (`_engine.py:165-173`; `Schema.lean:147`). A default is validated by the value schema. |
| `..._check_groups`, `..._empty_exclusive_group` | `P:_engine.py:564-650` | `groupsOf` `Schema.lean:18-28`, `Schema.lean:156-181` | No difference found. Group order is the order of the first member; the first member with a default fills an empty group; `required_one_of` lists all members. |
| `probatio:_engine.py::_SequenceValidator.__call__`, `..._validate_item` | `P:_engine.py:717-816` | `runSequence` `Schema.lean:87-107` | No difference found. One element: every item; several: the last failing candidate's error; none: "invalid value". |
| `probatio:validators/combinators.py::All.__call__` | `P:combinators.py:293-321` | `runAll` `Schema.lean:56-58` | No difference found. |
| `...::Any.__call__`, `_run_any`, `_branch_label`, `_expected_label` | `P:combinators.py:125-197, 328-509` | `runAny` `Schema.lean:66-81`, `Validator.label?`/`expectedLabel` `Probatio.lean:383-394` | No difference found. The typed fast path (`_run_typed_any`, 395) and the float-superset path (424) give the same answers as `_run_any` for the supported branch kinds. Depth is the path length of the first leaf (`MultipleInvalid.path`). |
| extra-policy inheritance | `P:_compile.py:356-366`, `combinators.py:60-121` | `Validator.run extra` `Schema.lean:33-52`; `.schema fields ex` keeps its own policy (`Schema.lean:37`) | No difference found (`cases/structure.yaml::hw_extra_policies`: `time_period_dict` keeps `PREVENT_EXTRA` under `allow` and `remove`). |

## 2. Leaf validators (`HALean/Core/Probatio.lean`)

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `_compile.py::_TypeCheck.__call__`, `_FloatCheck.__call__` | `P:_compile.py:182-249` | `checkType` `Probatio.lean:401-412` | No difference found. `float`: an int that overflows is "expected float" on both sides (`_compile.py:236-244`; `Probatio.lean:409-411`). |
| `_compile.py::_compile_literal` | `P:_compile.py:659-668` (`data != schema`, returns `data`) | `checkLiteral` `Probatio.lean:415` | No difference found. |
| `_compile.py::_compile_callable` | `P:_compile.py:632-656`: `Invalid` passes, `ValueError` becomes "not a valid value: <detail>", others escape | `CvFn.run` `ConfigValidation.lean:204-216` | The only `ValueError` a translated `cv.*` raises comes from `timedelta(...)` with NaN; Lean answers `unsupported` there (README line 335 lists it). The `TypeError` of `cv.entity_ids` on a scalar escapes on both sides, but its message differs for a `timedelta`: **SCH-4**. |
| `comparison.py::Range.__call__` | `P:comparison.py:180-219` | `checkRange`, `rangeOk`, `rangeError` `Probatio.lean:469-515` | No difference found. Minimum first; a non-number against a numeric bound is "invalid value or type". Bounds are numbers only (decoder, `ServicesJson.lean:84-88`). |
| `comparison.py::Clamp.__call__` | `P:comparison.py:240-252` | `checkClamp` `Probatio.lean:518-527` | No difference found (the bound object itself is returned). |
| `comparison.py::Length.__call__` | `P:comparison.py:855-895` | `checkLength`, `pyLen?` `Probatio.lean:530-544` | No difference found. `len(str)` counts code points on both sides. |
| `comparison.py::In.__call__`, `NotIn.__call__`, `_sorted_for_message` | `P:comparison.py:36-46, 947-1005` | `checkIn`, `checkNotIn`, `sortedForMessage` `Probatio.lean:423-461` | No difference found. Python `in` on a list is `==` per member for the values JSON holds. |
| `_messages.py::_display` | `P:_messages.py:157-175` | `displayList` `Probatio.lean:437-441` | No difference found (cap at 40, " more not shown"). |
| `coerce.py::Coerce.__call__` | `P:coerce.py:66-107` | `checkCoerce`, `pyInt?`, `pyFloat?`, `pyIntOfStr?` `Probatio.lean:265-268, 547-576` | Interpreted: no difference found for text that is printable ASCII. `float(str)` (`parseFloatStr`, `Template/Value.lean:154-192`) computes `10 ^ exponent` as a `Nat`: an exponent of 10 digits kills the process: **SCH-1**. Generated code: **SCH-3**. `str()` of an int of more than 4300 digits raises `ValueError` in Python (`Coerce(str)` then says "expected str"); `pyStr` prints it. Not reachable through the harness (see FINDINGS, reading findings). |
| `strings.py::Lower`, `Upper` | `P:strings.py:279-286` | `checkLower`, `checkUpper` `Probatio.lean:579-583` | No difference found for printable ASCII; other text is refused (`requireSafe`, `Probatio.lean:246`). |
| `structural.py::EnsureList.__call__` | `P:structural.py:305-309` | `ensureList` `Probatio.lean:586-589` | No difference found. |
| `network.py::Port.__call__` | `P:network.py:219-239` | `checkPort` `Probatio.lean:600-611` | No difference found. |
| `conditional.py::AtLeastOne.__call__` | `P:conditional.py:326-335`; the constructor refuses an empty key list (`_require_keys`, `conditional.py:72-77`) | `checkAtLeastOne` `Probatio.lean:593-596`; decoder `ServicesJson.lean:199-204` | The decoder accepts `at_least_one: []`: **SCH-6**. |

## 3. Errors as text (`HALean/Core/Probatio.lean`)

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `error.py::render_path` | `P:error.py:68-110` (`_BARE_KEY`, 78) | `renderPath`, `isBareKey`, `renderSegment` `Probatio.lean:161-190` | Same rule. The bracketed fallback is `repr(key)`; Lean's `strRepr` (`Template/Value.lean:215`) does not escape non-printable non-ASCII characters: **SCH-2** (README line 348). |
| `error.py::Invalid.__str__`, `MultipleInvalid.__str__` | `P:error.py:277-285, 529-531` | `SchemaError.str` `Probatio.lean:193`, `multipleInvalidStr` 224 | No difference found. |
| `error.py::_format_candidates`, `_SuggestionInvalid.candidates` | `P:error.py:39-45, 327-415`; CPython `difflib.get_close_matches`, `SequenceMatcher` | `formatCandidates`, `suggestionSuffix`, `getCloseMatches`, `seqRatio`, `matchingSize`, `findLongestMatch` `Probatio.lean:89-214` | No difference found. `a` is the pool member, `b` the value (autojunk reads `len(b) >= 200`); `2.0 * M / T >= 0.7`; three best by `(ratio, text)`. Driven by 26,140 + 720 + 11,794 fuzz pairs (`logs/fuzz-messages-seed1.log`) and `cases/structure.yaml::hw_in_messages`. |

## 4. `cv.*` (`HALean/Core/ConfigValidation.lean`, helpers)

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `config_validation.py::string` | `HA:helpers/config_validation.py:653-668` | `cvString` `ConfigValidation.lean:25-30` | No difference found. |
| `config_validation.py::boolean` | `HA:...:218-231` | `cvBoolean` `ConfigValidation.lean:34-47`, `cvBooleanText`/`cvBooleanCore`/`pyIsSpace` `Template/CvBoolean.lean:21-37` | No difference found. The result is exact for any text (U+00A0, U+3000 are stripped on both sides: `cases/divergences.yaml::hw_sch2_event_repr`, result equal); the *message* for non-ASCII text is refused. |
| `config_validation.py::entity_id` | `HA:...:317-323`, `HA:core.py:180-198` | `cvEntityId` `ConfigValidation.lean:50-55`, `validEntityId` `Core/State.lean:79` | No difference found (20,000 fuzz strings). |
| `config_validation.py::_entity_ids`, `entity_ids` | `HA:...:348-361` | `cvEntityIds`, `pyIter` `ConfigValidation.lean:59-75` | `pyIter` builds the `TypeError` text from `typeName`; CPython prints `tp_name`, which is `datetime.timedelta` for a timedelta: **SCH-4**. Other scalars agree. |
| `comp_entity_ids` (note of `entity_ids`) | `HA:...:369-372` | `ServicesJson.decodeCv` `ServicesJson.lean:136-137` | No difference found. |
| `config_validation.py::entity_domain`, `entities_domain` | `HA:...:406-436` | `cvEntityDomain`, `cvEntitiesDomain` `ConfigValidation.lean:79-98` | No difference found. |
| `config_validation.py::color_hex` | `HA:...:460-470` | `cvColorHex` `ConfigValidation.lean:105-113` | No difference found (`$` before one final `\n`). |
| `config_validation.py::slug`, `util/__init__.py::slugify` | `HA:...:602-610`, `HA:util/__init__.py:39-44`, `slugify/_legacy.py:19-26, 137-161` | `cvSlug` `ConfigValidation.lean:116-122`, `slugify?`/`slugifyChars` `Automation/Slugify.lean:38-55` | No difference found on 30,000 fuzz strings the model accepts. `slugify?` returns `none` for any text that holds both `&` and `;` (`Slugify.lean:52`); python-slugify only rewrites `&name;`, `&#123;`, `&#x1f;`: **SCH-5** (wider refusal than the README states). |
| `config_validation.py::icon` | `HA:...:450-457` | `cvIcon` `ConfigValidation.lean:125-128`, decoder `ServicesJson.lean:122` | No difference found with the fast tool. The README (line 335) lists `cv.icon` as rejected; the decoder accepts it; `schema_spec.py` (`CV`, line 24) cannot build it. See FINDINGS, notes on the harness. |
| `config_validation.py::time_period_str` | `HA:...:523-555` | `cvTimePeriodStr` `ConfigValidation.lean:144-166` (and `Automation/TimePeriod.lean:86-101` for automations) | No difference found (35,000 fuzz strings). NaN, infinity and overflow are refused (`timedeltaV`, `ConfigValidation.lean:133-136`; README line 335). |
| `config_validation.py::time_period_seconds` | `HA:...:558-563` | `cvTimePeriodSeconds` `ConfigValidation.lean:171-180` | No difference found. Upstream turns `timedelta(seconds=nan)` into `Invalid("Expected seconds, got nan")`; Lean refuses (documented). |
| `time_period_dict`, `time_period`, `positive_time_period(_dict)`, `positive_timedelta` | `HA:...:473-489, 566-584` | `timePeriodDict`, `timePeriod` `ServicesJson.lean:103-110`, `cvTimedeltaKwargs`, `cvPositiveTimedelta` `ConfigValidation.lean:184-201`, `timedeltaNew`/`accum` `Automation/TimePeriod.lean:27-65` | No difference found (8,000 fuzz dicts, rounding half to even of the leftover). The nested `probatio.Schema` in `time_period_dict` is a process-wide object: it reaches its 50th validation across all services, so **SCH-3** shows there first. |
| `positive_int`, `positive_float`, `small_float`, `byte`, `port`, `ensure_list` | `HA:...:183-197`, `cv.ensure_list` | `decodeCv` `ServicesJson.lean:113-135` | No difference found. |
| `int()` of text | CPython `int(str)`, 4300-digit limit | `parseIntChars` `Template/PyInt.lean:39-44`, `pyIntOfStr?` `Probatio.lean:265` | No difference found (20,000 fuzz strings; 4300 / 4301 digits, leading zeros and underscores counted the same). |

## 5. Decoder and driver (`ServicesJson.lean`, `PyJson.lean`, `Exe/CoreServices.lean`) against `schema_spec.py`

| point | Python builder (`tests/differential/schema_spec.py`) | Lean decoder | difference |
|---|---|---|---|
| validator name | first key of the object, other keys ignored (line 33) | first key; more than one key is refused except for `cv` (`ServicesJson.lean:156-157`) | Lean stricter, answers `unsupported`. |
| `cv` names | the set `CV` (line 24) plus `entity_domain` | the same plus `icon` (`ServicesJson.lean:122`) | `icon` cannot be tested through the shipped harness. |
| `at_least_one: []` | `probatio.AtLeastOne()` raises `SchemaError` | accepted | **SCH-6**. |
| `in: "abc"` | `In(list("abc"))` | refused ("needs a list") | Lean stricter. |
| `range`/`clamp` bounds | anything | int or float (not bool) | Lean stricter. |
| `default` | `"default" in f`, deep-copied | `f.get? "default"` (`ServicesJson.lean:234`): `default: null` is a default of `None` on both sides | none. |
| JSON numbers | `json.dumps` writes ints of any size and floats as `repr` | `parsePyJson` (`PyJson.lean:96-124`): int without fraction/exponent, else `parseFloatStr` | none for finite numbers. `NaN`/`Infinity` are refused (README line 350). A float literal with a 10-digit exponent would hit **SCH-1**; `json.dumps` never writes one. |
| JSON strings | `ensure_ascii` escapes, surrogate pairs | `strBody` (`PyJson.lean:63-87`) | A lone surrogate is refused by the parser (blind spot, see FINDINGS). |
| object order, duplicate keys | Python dict | `dictSet` (`PyJson.lean:26`) | none. |
| result | `repr()` of the echo dict | `reprOr` (`ServicesJson.lean:265`), `pyRepr` (`Template/Value.lean:239`), `floatRepr` (133) | **SCH-2** for non-printable non-ASCII characters (documented). `repr(float)` agreed on 7,996 random doubles. |
