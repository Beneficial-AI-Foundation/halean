# Area `templates`: what the 435 theorems say

Modules: `HALean.Template.{CvBooleanSpec, DateParseSpec, ParseTimeSpec, Proofs, PyIntSpec, RegexSpec, RenderSpec,
RenderSpec2, RenderSpec3, SyntaxSpec, SyntaxSpec2, TimeSpec, ValueSpec}`.
Implementation files: `HALean/Template/{Syntax, Value, Render, Time, DateParse, ParseTime, PyInt, Regex, CvBoolean}.lean`.

Classification file: `class/templates.tsv` (435 lines). Counts: **C 24, O 121, E 118, H 172**.

| module | C | O | E | H | total |
|---|---|---|---|---|---|
| CvBooleanSpec | 1 | 0 | 0 | 1 | 2 |
| DateParseSpec | 3 | 12 | 8 | 7 | 30 |
| ParseTimeSpec | 1 | 0 | 0 | 0 | 1 |
| Proofs | 0 | 1 | 4 | 0 | 5 |
| PyIntSpec | 1 | 0 | 0 | 17 | 18 |
| RegexSpec | 0 | 0 | 0 | 7 | 7 |
| RenderSpec | 7 | 22 | 10 | 15 | 54 |
| RenderSpec2 | 4 | 20 | 11 | 23 | 58 |
| RenderSpec3 | 1 | 23 | 46 | 27 | 97 |
| SyntaxSpec | 1 | 0 | 0 | 1 | 2 |
| SyntaxSpec2 | 0 | 2 | 5 | 29 | 36 |
| TimeSpec | 4 | 28 | 12 | 28 | 72 |
| ValueSpec | 1 | 13 | 22 | 17 | 53 |

Rules used. "Upstream function" includes the CPython and Jinja functions the Lean code models (`int()`, `divmod`,
`timedelta` normalisation, `str.title`). A theorem about one constructor of `Value`, or about literal inputs, is `E`.
Theorems about helpers that exist only in HALean (`collect*`, `tick`, `Args.*`, the parser-monad primitives,
`roundHalfEven`, `scaledUs`, `pad0`, `Caps.get?`, `lookupKV`) are `H`, also when they are an `iff`.
The three `rateLimit_eq_*_iff` theorems are each counted `C`; they describe one function together.

Checks run (scratch files in `class/scratch/templates_*`):
`#print axioms` on the 384 non-private theorems: only `propext`, `Classical.choice`, `Quot.sound` (or none). No
`sorryAx`, no `Lean.ofReduceBool`. The 51 private theorems cannot be named from outside and were not checked this way.
61 theorems are proved by `rfl` alone (47 `E`, 13 `H`, 1 `O`). 17 are proved by `decide` alone.

## What the theorems constrain

**`CvBoolean.lean` (`cv.boolean` on strings).** `cvBooleanText_iff` (C): `cvBooleanText s = some b` iff the
lower-cased text is a true/false word with whitespace around it. The result on every string is fixed
(`none` otherwise).

**`PyInt.lean` (`int(str)`).** `parseIntChars_iff` (C) and its wrapper `parseIntStr_iff` (C, in ValueSpec): the
result is `some n` iff the text is whitespace, optional sign, `digit (["_"] digit)*`, whitespace, with value `n`.

**`ParseTime.lean` (`dt_util.parse_time`).** `parseTimeSeconds_iff` (C). `parseTime_some`, `parseTime_none_iff`
(O) tie the `(h, m, s)` wrapper in `Render.lean` to it.

**`Syntax.lean`.** `isTemplateString_iff` (C) for `is_template_string`. `compile_isStatic` (O): every compiled
template has `isStatic = !isTemplateString raw` and `src = raw.trim`. `unescape_plain` (O): string literals without a
backslash are kept. Nothing else in this file has a `C`/`O` theorem (see next section).

**`Time.lean` (calendar).** C: `isLeap_iff`, `fdivmod_unique` (Python `divmod` for a positive divisor),
`tdParts_unique` (timedelta normal form), `Civil.valid_eq_none_iff` (datetime field ranges; the error text is not fixed).
O: the two round trips `daysFromCivil_civilFromDays`, `civilFromDays_daysFromCivil`; `civilFromDays_valid`,
`daysFromCivil_inj`; calendar lengths `daysFromCivil_succ_day`, `_next_month`, `_next_year`, `_year_length`, `_add_400`;
`daysInMonth_bounds`, `daysInMonth_feb`, `daysInMonth_of_ne_feb`; `isLeap_add_400`, `isLeap_of_not_century`;
`fdivmod_spec`; `fromCivil_toCivil`, `toCivil_fromCivil`, `toCivil_fromCivil_of_valid`, `toCivil_ranges`,
`toCivil_valid`, `fromCivil_inj`; `weekdayOf_lt`, `_eq_of_day`, `_next_day`, `_add_week`, `_fromCivil`; `tdParts_spec`;
`isoformat_some`. Together with the epoch facts (E) these fix `daysFromCivil`, `civilFromDays`, `toCivil`,
`fromCivil`, `weekdayOf` on valid dates. This is the most complete part of the area. `isoformat`, `tdStr`,
`tdRepr`, `offsetStr` are covered only by literal examples and by `isoformat_some`.

**`DateParse.lean`.** C: `tdChecked_ok_iff` (timedelta range), `dateOk_iff`, `rstripSpaces_spec`.
O: `tdChecked_eq_ok`; `fromIsoCalendar_bad_year`, `_bad_week`, `_bad_weekday`, `_ok` (errors for out-of-range
arguments; a successful result is the date `monday_of_week_1 + 7(week-1) + (day-1)`); `dateOk_iff_valid`,
`dateOk_day_le`, `dayNum_succ`; `timeRE_isSome_iff` (which 45 directive keys exist, not what they match);
`seqToRE_shape`; `rstripSpaces_idem`, `rstripSpaces_of_no_trailing`.

**`Value.lean`.** C: `parseIntStr_iff` only. O: `pyRepr_ok_iff` (which values print; not what is printed),
`pyStr_eq_pyRepr`, `strRepr_plain` (strings without quote, backslash or control character),
`floatToInt?_eq_none_iff`, `mem_rangeItems_pos`, `_neg`, `_one`, `rangeItems_eq_nil_iff`, `rangeItems_one_length`
(membership and emptiness of `range`; order of items not stated), `numLt_int_trichotomy`, `numEq_int_comm`,
`numEq_int_float_comm`, `stateEq_fields`.

**`Render.lean`, render info.** C: `rateLimit_eq_none_iff`, `rateLimit_eq_all_iff`, `rateLimit_eq_domain_iff`
(`RenderInfo._freeze` rate limit), `filter_iff`, `filterLifecycle_iff`. O: `rateLimit_values`, `filter_all`,
`filter_of_mem`, `listens_rateLimited`, `listens_mono`, `listens_of_filter`.
These are statements about the record `RInfo`. No theorem says what a render puts into that record
(see "Assumptions").

**`Render.lean`, pure helpers.** C: `resultAsBoolean_iff`, `seqIndex_eq`, `isNumericStr_iff`, `pyTitle_eq`,
`pyCapitalize_cons`, `pyStrip_toList`. O: `cvBoolean_isSome`, `iif_truthy`, `iif_not_none`, `seqIndex_isSome_iff`,
`_nonneg`, `_neg`, `_mem`; `sliceList_step_one`, `_nat`, `_total`, `_subset`; `pyStrip_*` (6), `pyTitle_*` (3),
`pyCapitalize_idem`, `_length`; `parseResult_str`; `floorF_some`, `ceilF_some`, `floorF_ceilF`;
`utcFromTimestamp_some`; `statesOf_all`, `_length_le`, `_mem`; `isIterable_scalar`.

**`Render.lean`, helpers in the `R` monad (RenderSpec3).** C: `hasValue_iff` (string ids). O: `hasValue_collects`,
`hasValue_nonstr`; `isState_collects`, `_missing`, `_nonstr`, `_true`, `_list`; `stateAttrFn_missing`, `_nonstr`;
`stateIfValid_some`, `_invalid`; `hassStatesGet_some`; `forgivingBool_default`, `_no_default`;
`forgivingFloat_default`; `toFloat_total`, `isNumber_total`; `lenV_eq_iterV_length`; `cmpOp_ne`; `asLocal_idem`;
`pySplit_length_le`, `pySplit_unlimited`; `ignoreCase_nonstr`.
The other 46 + 27 RenderSpec3 theorems are per-constructor equations (`arith_int`, `iterV_dict`, `getitemV_list`,
`containsV_undef`, ...; 31 of them are `rfl`) and facts about `collect*`, `tick`, `Args.*`.

**`Render.lean`, entry points.** O: `render_unparsed`, `render_parsed`, `renderWithInfo_fst` (the three entry
points agree with each other), `renderWithInfo_error` (an error sets `exception`). E: `render_static`,
`renderString_static`, `renderWithInfo_static`, `compile_render_static`, `compile_static`.

**`Regex.lean`.** No `C` or `O` theorem. The 7 theorems are about the capture list `Caps.get?` (H).

## What they do not constrain

Figures from `logs/defs.tsv` (kinds `def` and `partial`) against the constants in the statements:

| file | defs | partial | code lines | lines in partial defs | defs named in a C/O statement | lines of defs named in no statement |
|---|---|---|---|---|---|---|
| Syntax | 43 | 20 | 463 | 349 | 4 | 356 |
| Value | 37 | 8 | 310 | 71 | 11 | 77 |
| Render | 125 | 18 | 1788 | 819 | 44 | 1095 |
| Time | 24 | 1 | 133 | 50 | 14 | 50 |
| DateParse | 31 | 1 | 383 | 36 | 7 | 255 |
| ParseTime | 2 | 0 | 13 | 0 | 1 | 3 |
| PyInt | 7 | 0 | 21 | 0 | 1 | 2 |
| Regex | 12 | 1 | 36 | 24 | 0 | 34 |
| CvBoolean | 5 | 0 | 13 | 0 | 1 | 2 |
| total | 286 | 49 | 3160 | 1349 | 83 | 1874 |

### (a) `partial def`s

The area has 49 `partial def`s. `#print` shows each as an `opaque` constant (checked: `pyEq`, `Rx.run`,
`renderNodes`). A proof cannot unfold them.

Only one of the 49 occurs in any theorem statement: **`pyEq`** (Python `==`), in 7 theorems:
`lookupKV_cons`, `lookupKV_none_iff`, `lookupKV_some` (RenderSpec), `containsV_list`, `cmpOp_notin`, `isState_true`,
`isState_list` (RenderSpec3). In these `pyEq` is an unknown function `Value → Value → Bool`. The five equations hold
for every such function. They say "the result is whatever `pyEq` returns". `isState_true` and `isState_list` have the
hypothesis `pyEq (.str st.state) v = true`. No theorem proves `pyEq x y = true` for any `x`, `y` (not even
`pyEq (.str a) (.str a)`), so this hypothesis cannot be discharged inside Lean for any concrete value.
The same holds indirectly for `getitemV_dict` (hypothesis `lookupKV kvs k = some x`, and `lookupKV` calls `pyEq`).

The other 48 occur in no statement:

* Parser, `Syntax.lean` (20): `lexBlock`, `lexTemplate`, `parseExpr`, `parseCondExpr`, `parseOr`, `parseAnd`,
  `parseNot`, `parseCompare`, `parseMath1`, `parseConcat`, `parseMath2`, `parsePow`, `parseUnary`, `parsePrimary`,
  `parseTuple`, `parseArgs`, `parseSubscript`, `parsePostfix`, `parseFilterExpr`, `buildNodes`.
* Evaluator, `Render.lean` (18): `eval`, `callV`, `strMethod`, `applyFilter`, `applyTest`, `attrGet`, `isUndef`,
  `emitOut`, `renderNodes`, `bindTargets`, `hashCheck`, `exprNames`, `nodeNames`, `litLex`, `litParse`, `litItems`,
  `litElem`, `litTupleRest`.
* `Value.lean` (7 besides `pyEq`): `listEq`, `dictSub`, `dictLookup`, `pyLt`, `seqLt`, `Value.ofJson`, `Value.toJson`.
* `Time.lean`: `strftime`. `DateParse.lean`: `patternGo`. `Regex.lean`: `Rx.run`.

Non-partial definitions that call them inherit the gap: nothing can be proved about `renderString`, `render`,
`renderWithInfo` on a non-static template (they call `renderNodes`), about `compile` on text with a Jinja opening
(`lexTemplate`, `buildNodes`), about `check` (`nodeNames`), `literalEval` and therefore most of `parseResult`
(`litLex`, `litParse`), `strptime`, `strptimePattern`, `parseDuration`, `Rx.matchPrefix` (`Rx.run`, `patternGo`),
`doSort`/`minOrMax`/`doUnique` beyond the empty list (`pyLt`, `pyEq`).

### (b) Parsers, decoders, matchers

* **Jinja lexer and parser.** No theorem states anything about the output of `lexTemplate`, `lexBlock`,
  `parseExpr` (and the 16 other expression parsers) or `buildNodes`. There is no theorem of the form
  "`compile src = .ok t` with `t.nodes = ...`" for any text that contains `{{`, `{%` or `{#`. No precedence,
  associativity, filter-binding or whitespace-control property is stated.
  What SyntaxSpec2 has instead: the token-stream primitives (`peek_run`, `peek2_run`, `advance_run`, `isOp_run`,
  `isName_run`, `expectOp_iff`, `expectName_iff`, `expectKw_run`, `expectKw_op`, `expect_eof`, `runExpr_iff`,
  `runExpr_error`), character classes (`isNameChar_iff`, ...), `startsPrimary_*`, `stripRight_*`,
  `dropLeadingWs_*`, `unescape_*`, and `parseStmt` on seven literal token lists (`parseStmt_keywords`,
  `parseStmt_invalid`). The `parseStmt` cases chosen are the ones that do not reach `parseExpr`/`parseTuple`.
  `parseTargets` and `dropTrailingNewline` (not partial) have no theorem.
* **Regex matcher.** `Rx.run`, `matchPrefix` and the builders `ch`, `oneOf`, `digit`, `range`, `lit`, `opt`, `plus`,
  `nTimes` have no theorem. The three duration regexes (`STANDARD_DURATION_RE`, `ISO8601_DURATION_RE`,
  `POSTGRES_INTERVAL_RE`) are hand-written `Rx` terms; nothing relates them to the upstream pattern strings.
  RegexSpec's header says this itself.
* **`strptime` / `strftime` / `parse_duration`.** Only tables: `timeRE_isSome_iff`, `timeRE_unsupported`,
  `timeRE_aliases`, `locale_names`, `name_tables`, `seqToRE_shape`. No theorem about a parsed or formatted value.
* **`literal_eval` and `_parse_result`.** `literalEval` has no theorem. `parseResult` has one: `parseResult_str`
  (a string result is the input text). `isNumericStr_iff` covers the test for the fast path, not the value produced.
  No round-trip theorem (`parseResult (toString i) = .int i`) exists.
* **JSON.** `Value.ofJson`, `Value.toJson` are partial; `floatToJson` has only `floatToJson_not_finite` (E).
* **Floats.** `ratToFloat`, `shortestDigits`, `floatRepr`, `parseFloatStr`, `pyRound`, `floatFloorDivMod`,
  `pyRoundFloat`, `fTrunc`, `tdTotalSeconds`, `roundedSeconds`: only special-value facts (`floatRepr_nan`,
  `floatRepr_inf`, `ratToFloat_zero`, `intToFloat_zero`, `pyRound_nonfinite`, `decodeFloat_bounds`). Nothing about
  correct rounding or shortest repr. ValueSpec's header says so.

### (c) Entry points: `render`, `eval`, `compile`

Theorems whose statement contains `render`, `renderString`, `renderWithInfo` or `compile` (10):
`render_static`, `renderString_static`, `renderWithInfo_static`, `compile_static`, `compile_isStatic`,
`compile_render_static`, `render_unparsed`, `render_parsed`, `renderWithInfo_fst`, `renderWithInfo_error`.

* The first six are about **static** templates: text with no `{{`, `{%`, `{#`. For these `render` returns `t.src`
  without calling the evaluator. Each proof is `simp` on the first `if` of the definition.
* `render_unparsed`, `render_parsed`, `renderWithInfo_fst` say the three wrappers return the same thing. They hold
  for every possible `renderNodes`.
* `renderWithInfo_error` says: if the result is an error, `exception` is set. It holds for every `renderNodes`.

**No theorem says anything about the value `render`, `renderString` or `renderWithInfo` returns for a template that
contains a Jinja construct.** Not for `{{ 1 }}`, not for `{{ states('x.y') }}`. **No theorem mentions `eval`,
`renderNodes`, `callV`, `applyFilter`, `applyTest` or `strMethod`.** No theorem says which entities, domains or flags
a render records in its `RInfo`. No theorem says rendering terminates or stays within `MAX_STEPS`
(`tick_*` are about one call of `tick`). `check` (the load-time whitelist of names, filters, tests) has no theorem.

What the 209 RenderSpec/RenderSpec2/RenderSpec3 theorems are about instead:

1. the `RInfo` record as data: rate limit and filters (14 theorems);
2. non-recursive helper functions that the evaluator calls: `seqIndex`, `sliceList`, `roundHalfEven`, `scaledUs`,
   `utcFromTimestamp`, `floorF`/`ceilF`, `lookupKV`, `statesOf`, `cvBoolean`, `resultAsBoolean`, `iif`, `pyTitle`,
   `pyCapitalize`, `pyStrip`, `pyReplace` (empty pattern only), `isNumericStr`, `parseResult_str`;
3. helpers in the `R` monad, mostly one equation per `Value` constructor: `toFloat?`, `doInt`, `forgivingFloat`,
   `forgivingInt`, `forgivingBool`, `isNumber`, `isState`, `stateAttrFn`, `hasValue`, `stateIfValid`, `iterV`,
   `lenV`, `containsV`, `getitemV`, `arith` (11 literal operator/constructor combinations out of the whole
   operator table), `cmpOp`, `asLocal`, `pySplit`;
4. bookkeeping helpers: `collect`, `collectDomain`, `collectAll`, `collectTime`, `tick`, `Args.get`, `Args.check`;
5. the static-template shortcut and the agreement of the wrappers (10 theorems above).

That these helpers are called by `eval`/`callV`/`applyFilter` with the right arguments is not stated anywhere and
cannot be, while those are `partial`.

Non-partial `Render.lean` definitions with no theorem at all: `getattrV`, `expand`, `callDateTime`, `parseDatetime`,
`floatFloorDivMod`, `literalEval`, `check`, `pyErrMsg`, `digitsN`, `Ctx.nowDT`, the name tables `GLOBALS`, `FILTERS`,
`TESTS`, `TIME_NAMES`, `STR_METHODS`, `RESERVED_NAMES`, `NUMBER_ATTRS`, `STATE_OPAQUE`,
`COLLECTABLE_STATE_ATTRIBUTES`, `MULTIDICT_METHODS`, `DATETIME2_NAMES`, `MAX_TEMPLATE_OUTPUT`.
With only `E`/`H` theorems: `arith`, `containsV`, `getitemV`, `doInt`, `forgivingInt`, `forgivingRound`, `doSort`,
`doUnique`, `minOrMax`, `stateAttr`, `datetimeAsString`, `timestampOf`, `pyReplace`, `pyRound`, `attrPath`,
`attrParts`, `sortKey`, `iterVList`.

## Assumptions that nothing checks

1. **`Tmpl.isStatic = true`** (`render_static`, `renderString_static`, `renderWithInfo_static`). `Tmpl` is a plain
   structure; the flag is not tied to `src` or `nodes`. For values produced by `compile` the flag is fixed by
   `compile_isStatic`. Discharged for `compile` output, not for a `Tmpl` built any other way.
2. **`pyEq … = true`** (`isState_true`, `isState_list`) and **`lookupKV kvs k = some x`** (`getitemV_dict`):
   `pyEq` is opaque. No theorem discharges these for any concrete value. At run time the compiled `pyEq` decides.
3. **`s.info.entities.Nodup`** (`collect_nodup`) and **`s.steps ≤ MAX_STEPS`** (`tick_bound`). True for the initial
   state `{}`. The state during a render is produced by the opaque `renderNodes`. No theorem carries the invariant
   through a render. `filter_iff`, `rateLimit_*`, `listens_*` take an arbitrary `RInfo`; the `RInfo` of a real render
   is the output of `renderNodes`, about which nothing is known.
4. **Year in `1..9999`** (`toCivil_valid`). `checkDate_iff` shows `checkDate` tests it. No theorem shows that every
   `Value.datetime` the evaluator creates went through `checkDate`.
5. **ASCII.** `cvBooleanText_iff`, `parseIntChars_iff`, `parseTimeSeconds_iff`, `isNumericStr_iff`, `pyTitle_eq`,
   `pyCapitalize_cons` have no ASCII hypothesis. Their specifications are written with ASCII classes
   (`Char.toLower`, `Char.isDigit`, `Char.isAlpha`, `pySpace`). Agreement with Python on other text is outside
   the theorems. Checked here with CPython 3.14:
   * `cv.boolean`: holds for all text. `str.isspace` is exactly the 29 code points of `pyIsSpace`; only U+0130 and
     U+212A lower-case to text containing ASCII; no character changes whitespace status under `lower()`.
   * `int()` and `\d`: fail on Unicode digits. Callers must reject such text. `doInt` does (`numberTextModelled`).
     `parseResult` does not: `_parse_result("١٢")` is the int `12` upstream; `parseResult "١٢"` is the string, and
     `render (compile "{{ \"١٢\" }}")` returns `.str "١٢"` in HALean (run in `scratch/templates_axioms.lean`).
     No theorem states which callers reject non-ASCII text.
6. **`String.trim` is taken as Python's `strip()`** (`compile_static`, `compile_isStatic`, `compile_render_static`).
   Lean's `trim` does not remove `\x0b`, `\x0c`, `\x1c`-`\x1f` or non-ASCII spaces. Upstream uses
   `template.strip()`. `compile "\x0cfoo\x0b"` keeps 5 characters; Python gives `"foo"`. The theorems are true about
   `compile` as written; they do not show that `compile` strips like upstream.
7. **`List.splitOn ':'` is taken as `str.split(":")`** (`ParseTimeSpec`). The same Lean function is used in the
   implementation and in the specification. Stated in the module header, not proved.
8. **`int()` has a 4300-digit limit in CPython.** `PyIntSpec` has no bound. See "Docstring claims" 2 and 3.

Weaker than they read, or restatements:

* Hold for any `pyEq`: `lookupKV_cons`, `lookupKV_none_iff`, `lookupKV_some`, `containsV_list`, `cmpOp_notin`.
  Hold for any `renderNodes`: `render_unparsed`, `render_parsed`, `renderWithInfo_fst`, `renderWithInfo_error`.
* 19 theorems conclude `∃ e, … = (.error e, s)` (for example `arith_int_div_zero`, `iterV_scalar`,
  `forgivingFloat_none`). The error text and kind are not fixed. Docstrings name `ZeroDivisionError`, `TypeError`.
* `isOp_run`, `isName_run`: `∃ b, … = .ok (b, toks)`. Only "does not fail, does not consume".
* `floorF_ceilF`: only `isSome` equality.
* Restate the definition's own case split (proof is `simp`/`cases`/`rfl` on the definition): `isLeap_iff`,
  `Civil.valid_eq_none_iff`, `dateOk_iff`, `rateLimit_eq_none_iff`, `rateLimit_eq_all_iff`,
  `rateLimit_eq_domain_iff`, `filter_iff`, `filterLifecycle_iff`, `resultAsBoolean_iff`, `seqIndex_eq`,
  `pyStrip_toList`, `pyCapitalize_cons`, `hasValue_iff`, `iif_truthy`, `numEq_int_float_comm` (`rfl`),
  `cvBoolean_str` (`rfl`), and the 61 `rfl`-only theorems (list: proof column of the scratch script
  `templates_classify.py` reasons marked "(rfl)", plus `peek_run`, `peek2_run`, `advance_run`, `isOp_run`, ...).
* No theorem has a `True` conclusion. No theorem was found with hypotheses that cannot hold together.
* `parseIntStr_iff` is `parseIntChars_iff` applied to `s.toList`; it is one fact counted twice in `C`.

## Specifications independent of the code?

24 `C` theorems. **11 independent, 13 restatements.**

Independent (a predicate or reference function written separately from the implementation):

| theorem | specification | shared with the implementation |
|---|---|---|
| `cvBooleanText_iff` | `CvBooleanSpec` (∃ word, padding) | word lists, `pyIsSpace`, `Char.toLower` |
| `parseIntChars_iff` | `PyIntSpec` + inductive `DigitsUs` | `pySpace`, `digitValue` |
| `parseIntStr_iff` | same (wrapper) | same |
| `parseTimeSeconds_iff` | `ParseTimeSpec` | `List.splitOn`, `PyIntSpec` |
| `isTemplateString_iff` | `TemplateStringSpec` | nothing |
| `isNumericStr_iff` | `IsNumericSpec` | `Char.isDigit` |
| `pyTitle_eq` | recursion `titleSpec` | `Char.isAlpha`, `toUpper`, `toLower` |
| `fdivmod_unique` | `a = q*b + r ∧ 0 ≤ r < b` | nothing |
| `tdParts_unique` | normal form `(d, s, u)` | nothing |
| `rstripSpaces_spec` | "input minus trailing spaces, no trailing space" | nothing |
| `tdChecked_ok_iff` | bounds in microseconds | nothing (implementation tests days) |

Restatements of the implementation's own case split: `isLeap_iff`, `Civil.valid_eq_none_iff`, `dateOk_iff`,
`rateLimit_eq_none_iff`, `rateLimit_eq_all_iff`, `rateLimit_eq_domain_iff`, `filter_iff` (drops one redundant branch),
`filterLifecycle_iff`, `resultAsBoolean_iff`, `seqIndex_eq`, `pyStrip_toList`, `pyCapitalize_cons`, `hasValue_iff`.

Independent specifications among `O`/`H` theorems, for reference: the two calendar round trips with
`daysFromCivil_year_length` etc.; `roundHalfEven_iff` against `IsRoundHalfEven`; `pyRepr_ok_iff` against `Printable`;
`sliceList_step_one` against `clampIdx`.

## Docstring claims

Checked: 351 theorem docstrings and 13 module headers = 364 claims.
**correct 331, overstated 28, false 4, stale 1, correct for the wrong reason 0.**

False (4):

1. `numEq_int_comm` (ValueSpec.lean:468): docstring "Mixed int/float `<` one way is `>` the other way." The statement
   is `numEq (.i a) (.i b) = numEq (.i b) (.i a)`: two ints, equality. No theorem states the docstring's claim.
2. `parseIntChars_iff` (PyIntSpec.lean:204): "**Python's `int(s)` for ASCII `s`**: `parseIntChars` returns `n`
   exactly when …". CPython refuses decimal strings with more than 4300 digits
   (`int("1"*4301)` → `ValueError`, `sys.get_int_max_str_digits() == 4300`, HA does not change it).
   `parseIntStr` of 4301 ones is `some _` (evaluated). `HALean/Core/Probatio.lean:263` knows the limit and adds it for
   `Coerce(int)` only.
3. `parseTimeSeconds_iff` (ParseTimeSpec.lean:21): "`parseTimeSeconds s = some t` exactly when upstream's
   `parse_time(s)` returns the time `t` … (for ASCII text)". Counterexample, ASCII: `s = "0"*4301 + "1:00"`.
   Upstream `dt_util.parse_time(s)` is `None` (run against `upstream/ha-core`). `parseTimeSeconds s = some 3600`
   (evaluated).
4. `isNumericStr_iff` (RenderSpec2.lean:606): "the fast numeric path of `_parse_result` is taken exactly for text
   matching the regex's grammar". The upstream regex is `^[+-]?(?!0\d)\d*(?:\.\d*)?$`. In Python `\d` matches Unicode
   digits and `$` matches before a final newline: `_IS_NUMERIC.match("١٢")` and `_IS_NUMERIC.match("12\n")` both match.
   `isNumericStr` is `false` on both (evaluated). `IsNumericSpec` reads `\d` as `Char.isDigit` and `$` as end of text.

Stale (1):

5. RenderSpec.lean header (lines 2-4): "… Python sequence indexing and slicing, half-even rounding, `cv.boolean` on
   values, and Python `str` methods." The file has no theorem on slicing or `str` methods; those are in RenderSpec2.

Overstated (28). The docstring says more than the statement:

6. PyIntSpec.lean header: "Python's `int(str)` on ASCII text, written as its grammar". Digit limit missing (see 2).
7. ParseTimeSpec.lean header: "proved against what upstream computes". See 3.
8. `timeRE_aliases` (DateParseSpec.lean:188): "… and `%U` and `%W` read the same digits." The statement has four
   equalities (`e/d`, `k/H`, `l/I`, `P/p`). Nothing about `U`/`W`.
9. `typeName_of_num` (ValueSpec): "The numeric values are exactly the ones Python calls `bool`, `int`, `float`."
   One direction only. The converse is false in the model: `typeName (.gen "int" []) = "int"`.
10. `iif_none` (Proofs.lean:22): "picks it exactly when the value is None". Statement: only the None case.
11. `floorF_ceilF` (RenderSpec.lean:440): "… and differ by at most 1". Statement: only `isSome` equality.
12. `floorF_some` (RenderSpec.lean:421): "it fails only when the float has no integer value". Not in the statement.
13. `isIterable_scalar` (RenderSpec.lean:407): "Numbers, `None`, states and datetimes". The statement does not
    mention states.
14. `Rx.Caps.get?_append_of_isSome` (RegexSpec): "What `matchPrefix` hands on is the group list `Caps.get?` reads".
    The statement is a list fact; `matchPrefix` is not in it.
15. `forgivingBool_no_default`: "raises exactly when `cv.boolean` rejects". One direction.
16. `arith_undef`: "Any arithmetic with an Undefined operand raises." Statement: left operand only.
17. `toFloat_cases`: "of anything that is neither a number nor text it is a `TypeError` (`none`)". Statement: `None`,
    list, dict. For `undef` and `opaque` the function raises instead (definition, Render.lean:182-183).
18. `doInt_none`: "Values that are neither numbers nor text have no int". Statement: `None` and list.
19. `fromIsoCalendar_bad_weekday`: "A weekday that is not in 1..7 is a `ValueError`." Hypothesis `week ≤ 52`; week 53
    is not covered.
20. to 33. General rule in the docstring, one constructor or token kind in the statement:
    `expectKw_op` ("anything that is not a name": operator tokens only), `parseStmt_invalid` ("does not start with a
    name": operator first only), `resultAsBoolean_list` ("Collections and other objects": lists),
    `utcFromTimestamp_str` ("Non-numbers": strings), `isNumber_none` (None, list), `iterV_scalar` ("Numbers": int),
    `asLocal_error` ("anything that is not a datetime": strings), `timestampOf_error` ("a non-datetime": int),
    `arith_naive_aware` (naive − aware only), `cmpOp_opaque` (left operand only), `cmpOp_notin` (list containers),
    `datetimeAsString_passthrough` ("a non-datetime input": strings), `forgivingRound_bad_precision` ("not an int":
    strings), `Args_checkStrict_pos` ("agrees with the plain one": success direction only).

Notes on claims found correct:

* CvBooleanSpec and `CvBoolean.lean` headers ("exact for all text, by two facts about Unicode"): both facts were
  re-checked exhaustively over all code points with CPython 3.14. They hold.
* RegexSpec header ("nothing can be stated about `matchPrefix`"), DateParseSpec header ("`parseDuration`,
  `strptimePattern` and `strptime` … cannot be unfolded"), ValueSpec header (IEEE arithmetic opaque), SyntaxSpec2
  header ("non-recursive helpers"): accurate descriptions of the limits.
* `render_static` docstring: "A static template (no `{{`, `{%`, `{#`) renders to its own text when the result is not
  parsed". Correct; the link from `isStatic` to the text is `compile_isStatic`.
* Not counted (implementation files): `PyInt.lean` header "as CPython parses it for ASCII text" has the same gap
  as 2. `Render.lean` header "Every name, filter and test a template uses is checked at load time (`check`);
  anything outside the supported set is rejected, never guessed" has no theorem behind it.

## manifest.yaml claims

64 entries have a `lean:` name defined in the implementation files of this area: 59 `translated`, 5 `proven`.
No `translated` entry names a theorem. The 5 `proven` entries:

| python | theorem named | exists | verdict |
|---|---|---|---|
| `helpers/template/__init__.py::is_template_string` | `isTemplateString_iff` | yes (SyntaxSpec) | correct |
| `helpers/config_validation.py::boolean` | `cvBooleanText_iff` | yes (CvBooleanSpec) | correct |
| `core.py::valid_entity_id` | `validEntityId_iff` | yes (`HALean.Core.StateSpec`, other area) | correct |
| `core.py::valid_domain` | `validDomain_iff` | yes (`HALean.Core.StateSpec`, other area) | correct |
| `util/dt.py::parse_time` | `parseTimeSeconds_iff` | yes (ParseTimeSpec) | overstated |

**correct 4, overstated 1.**

* `is_template_string`: the theorem determines the function. `proven` fits. The note text is cut off
  (`… "{#" is`).
* `boolean`: the note limits the theorem to strings and says "Numbers and bools: direct". The `lean:` list also has
  `HALean.Template.cvBoolean` and `HALean.Core.cvBoolean`. For `Template.cvBoolean` there are `cvBoolean_bool`,
  `cvBoolean_int`, `cvBoolean_str`, `cvBoolean_isSome`; the float branch has no theorem. The definition matches
  upstream line by line (`config_validation.py:218-231`). The Unicode claim in the note was re-checked and holds.
* `valid_entity_id`, `valid_domain`: for this area only the alias was checked. `Template.validEntityId s :=
  Core.validEntityId s` and `Template.validDomain s := Core.validDomain s` (Render.lean:158-161). "The template
  engine uses the same function" is correct. The statements of the two Core theorems belong to another area.
* `parse_time`: the theorem exists and states what the note says. `proven` does not fit for all inputs: the
  specification's `int()` has no 4300-digit limit (counterexample in "Docstring claims" 3), and on non-ASCII digits
  upstream returns a time where HALean returns `none` (`parse_time("١٢:٠٠")` is `12:00:00` upstream). The note mentions
  ASCII, not the digit limit.

## PROPERTIES.md claims

8 claims refer to theorems of this area. **correct 4, overstated 3, stale 1.**

1. Line 30/40, table row "`render_static`, `templateCond_static` | a template without `{{ }}`/`{% %}` is never
   evaluated", located in `HALean/Template/Proofs.lean`. **correct** for `render_static` (it exists there; statement:
   `isStatic` and `parse = false` give `.ok (.str t.src)`). The row omits `{#` and the `parse = false` condition.
   `templateCond_static` is in another area.
2. Line 144, `parseIntChars_iff`: "Python's `int(str)` (base 10) … ASCII text (non-ASCII is refused with an
   error)". **overstated**. The grammar is right. CPython's 4300-digit limit is missing. `parseIntChars` returns
   `none` on non-ASCII text, the same as for invalid text; whether an error follows depends on the caller, and no
   theorem covers the callers (`parseResult` returns a string, see Assumptions 5).
3. Line 145, `parseTimeSeconds_iff`: "`str.split(":")`, `int()` of the first two or three parts …". **overstated**
   (counterexample in "Docstring claims" 3).
4. Line 146, `isTemplateString_iff`. **correct**.
5. Line 147, `cvBooleanText_iff`: "`value.lower().strip()` is one of the true / false words; `str.isspace` is the
   exact Unicode set". **correct** (set re-checked: 29 code points, equal to `pyIsSpace`).
6. Lines 131-137, introduction to that table: "the translation is proved to decide exactly that predicate … The
   remaining trust is in the predicate matching Python, which is short enough to check by eye." **overstated** for
   the rows of this area: two of the four predicates (`PyIntSpec`, `ParseTimeSpec`) do not match Python on inputs
   found in this review.
7. Lines 150-152: "`\d` is read as the ASCII digits … The template engine uses the same proved functions."
   **correct** (aliases in Render.lean:158-161).
8. Lines 211-222, section "Templates": "Errors, not wrong answers. Every value HALean does not model yet (datetimes,
   for instance) leads to an error". **stale**: datetimes are modelled (`Value.datetime`, `pyStr_datetime`,
   `arith_timedelta`, `asLocal_*`). The three bullets are labelled candidate properties; none is proved. No theorem
   states termination of `render`, a round trip through `parseResult`, or "error, never a different result" for the
   evaluator.
