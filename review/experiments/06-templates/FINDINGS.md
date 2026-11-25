# FINDINGS: templates (`HALean/Template/`)

Reviewed commit `f638a3779195a42a5162939aa67981b9b501618e`, against Home Assistant 2026.10.4, Jinja2 3.1.6, CPython 3.14.

## Counts

* New hand-written cases: 1249 in `cases/*.yaml` (run by the harness copy: `logs/run1-hand-pytest.log`, last line `312 failed, 937 passed, 6 warnings in 77.64s (0:01:17)`; `logs/run2-hand-pytest.log`, `312 failed, 937 passed, 6 warnings in 56.96s`), plus 4 batch-only cases in `gen/batch_only.yaml` on which HA raises an exception that is not a `TemplateError` (1253 cases in `logs/run1-hand-batch.jsonl`).
* Random cases per run: 6000 (3000 with seed 101, `logs/run1-random-seed101.jsonl`; 3000 with seed 102, `logs/run1-random-seed102.jsonl`).
* Runs: 2 (`logs/run1-*`, `logs/run2-*`). Verdict and category of every case are the same in both runs (checked by `make_findings.py`; the two random outputs are byte-identical).
* Cases that diverge (fail the shipped pass/fail rule): 696 per run = 316 hand-written (`logs/run1-hand-batch.classified.log`; 312 failed in the harness copy, the other 4 are the batch-only cases) + 185 random with seed 101 (`logs/run1-random-seed101.classified.log`) + 195 random with seed 102 (`logs/run1-random-seed102.classified.log`).
* Distinct root causes: 48. Per root cause, the number of diverging cases (hand-written / seed 101 / seed 102), from the three `classified.log` files above:

| ID | hand | seed 101 | seed 102 | root cause |
|---|---|---|---|---|
| TPL-1 | 8 | 0 | 0 | string escapes \ooo \u \U \N not decoded |
| TPL-2 | 9 | 10 | 8 | dict keys: no dedup, no hash check |
| TPL-3 | 5 | 0 | 0 | dict.keys()/values()/items() are lists |
| TPL-4 | 14 | 43 | 63 | bool() of states objects; `if value:` guard of map/select |
| TPL-5 | 3 | 0 | 0 | last / reverse over states objects |
| TPL-6 | 6 | 5 | 2 | case-insensitive entity id lookup |
| TPL-7 | 3 | 0 | 0 | float sum is not compensated |
| TPL-8 | 7 | 0 | 0 | repr(str) non-printable characters |
| TPL-9 | 3 | 21 | 21 | Undefined inside a printed container |
| TPL-10 | 2 | 0 | 0 | Namespace repr |
| TPL-11 | 8 | 0 | 0 | loop object is a dict |
| TPL-12 | 3 | 5 | 9 | for-else after break/continue |
| TPL-13 | 7 | 0 | 0 | generators can be consumed twice |
| TPL-14 | 3 | 0 | 0 | generators are evaluated eagerly |
| TPL-15 | 6 | 0 | 0 | tests sequence / iterable |
| TPL-16 | 5 | 0 | 0 | float(): whitespace and digits |
| TPL-17 | 3 | 0 | 0 | _parse_result: Unicode digits |
| TPL-18 | 3 | 0 | 0 | static template strip is ASCII-only |
| TPL-19 | 1 | 0 | 0 | title filter whitespace |
| TPL-20 | 1 | 0 | 0 | str.split(None, maxsplit) remainder |
| TPL-21 | 4 | 0 | 0 | float // and % with infinities |
| TPL-22 | 1 | 0 | 0 | timestamp_custom default format |
| TPL-23 | 1 | 0 | 0 | T24:00:00 gives None |
| TPL-24 | 1 | 0 | 0 | strftime %Y below year 1000 |
| TPL-25 | 12 | 7 | 8 | zone database / DST (documented) |
| TPL-26 | 2 | 0 | 0 | JSON numbers with an exponent become ints |
| TPL-27 | 4 | 2 | 1 | attribute / variable key order (documented) |
| TPL-28 | 12 | 0 | 0 | literal_eval: set, bytes, Ellipsis, complex |
| TPL-29 | 2 | 0 | 0 | literal_eval: nested unary sign |
| TPL-30 | 2 | 0 | 0 | lexer accepts .5 and 007 |
| TPL-31 | 5 | 0 | 0 | parser accepts invalid Jinja |
| TPL-32 | 11 | 0 | 0 | OverflowError / digit limit not raised |
| TPL-33 | 25 | 0 | 0 | argument count and keywords not checked |
| TPL-34 | 8 | 0 | 0 | non-string / Undefined entity id |
| TPL-35 | 1 | 0 | 0 | sum(start=str) |
| TPL-36 | 3 | 0 | 0 | timestamp_* accepted as globals |
| TPL-37 | 2 | 1 | 0 | uncaught HA errors treated as 'use default' |
| TPL-38 | 7 | 3 | 1 | Jinja compile-time constant folding |
| TPL-39 | 16 | 0 | 0 | valid Jinja syntax rejected at load |
| TPL-40 | 39 | 11 | 10 | Python methods / attributes / operators not modelled |
| TPL-41 | 15 | 18 | 14 | argument forms not modelled |
| TPL-42 | 24 | 4 | 1 | datetime methods and strftime directives not modelled |
| TPL-43 | 7 | 1 | 0 | date strings only ciso8601 parses |
| TPL-44 | 6 | 50 | 53 | printing objects |
| TPL-45 | 5 | 3 | 2 | HA gives Undefined/default, HALean raises |
| TPL-46 | 0 | 1 | 2 | documented render errors (non-ASCII case mapping) |
| TPL-47 | 0 | 0 | 0 | huge float exponent: time and memory |
| TPL-48 | 1 | 0 | 0 | step budget of 1,000,000 |

A random case is assigned to the first rule of `classify.py` that matches; one case can contain more than one divergence. No random case is left unclassified. No divergence was traced to the generator itself: every random divergence falls under a root cause that also has a hand-written reproducer, except TPL-46 (documented).

## Divergences

`HA result` and `HALean result` are copied from `logs/run1-hand-batch.jsonl`. Patches were tested together in one throwaway copy (`patches/ALL.patch` = all `TPL-*.patch` in order); shipped tests pass with all patches applied: `patches/all-patches-shipped-test_templates.log` (361 passed), `patches/all-patches-shipped-differential.log` (611 passed, 6 skipped), `patches/all-patches-run_scenarios.log` (60/60), `patches/all-patches-run_script_scenarios.log` (11/11). With the patches the Template `*Spec.lean` modules no longer all compile (`patches/spec-build-with-all-patches.log`): see "Notes on the patches" below.

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| TPL-1 | `cases/01_syntax.yaml::syn_str_octal_escape` | str `'A'` | str `'\\101'` | Silent | no | `patches/TPL-1.patch` (partial: `\u`, `\U` decoded; `\1`-`\7` and `\N{}` refused; `\0dd` unchanged); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-2 | `cases/02_values.yaml::val_dict_dup_keys` | dict `{'a': 2}` | dict `{'a': 1, 'a': 2}` | Silent / Accepts | no | `patches/TPL-2.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-3 | `cases/02_values.yaml::val_dict_keys_print` | str `"dict_keys(['a'])"` | list `['a']` | Silent | no | none (needs a view value) |
| TPL-4 | `cases/02_values.yaml::val_truthy_domain_empty` | str `'n'` | str `'y'` | Silent (value and RenderInfo) | no | `patches/TPL-4.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-5 | `cases/06_states.yaml::st_domain_last` | str `''` | int `6` | Silent / Accepts | no | none |
| TPL-6 | `cases/06_states.yaml::st_case_insensitive_call` | int `21` | str `'unknown'` | Silent (value and RenderInfo) | no (manifest.yaml, `StateMachine.get`: "lower-case retry; only expand uses it so far") | `patches/TPL-6.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-7 | `cases/04_filters_tests.yaml::flt_sum_float_compensated` | float `1.0` | float `0.9999999999999999` | Silent | no | `patches/TPL-7.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-8 | `cases/02_values.yaml::val_repr_nbsp` | int `8` | int `5` | Silent | no for templates (README 349 lists it for the service registry: "`repr()` of strings with non-printable non-ASCII characters (Python escapes them, HALean does not)") | none (needs Unicode's printable table) |
| TPL-9 | `cases/02_values.yaml::val_print_undefined_in_list` | str `'[Undefined]'` | list `[]` | Silent | no | `patches/TPL-9.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-10 | `cases/02_values.yaml::val_print_namespace` | str `"<Namespace {'a': 1}>"` | str `'<Namespace>'` | Silent | no | none (the fields live in the render heap, `pyRepr` cannot see them) |
| TPL-11 | `cases/02_values.yaml::val_print_loop` | str `'<LoopContext 1/2><LoopContext 2/2>'` | str `"{'index': 1, 'index0': 0, 'revindex': 2, 'revindex0': 1, 'first': Tru … ength': 2, 'previtem': 1, 'nextitem': }"` | Silent / Refuses / Accepts | no (README 246 lists `loop.*` as supported) | none |
| TPL-12 | `cases/03_undefined_scope.yaml::loop_break_then_else` | str `'ex'` | str `'x'` | Silent | no | `patches/TPL-12.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-13 | `cases/08_extra.yaml::flt_generator_reused_sum` | int `30` | int `33` | Silent | no | none (needs one-shot iterators in the render state) |
| TPL-14 | `cases/04_filters_tests.yaml::flt_map_lazy_first` | int `1` | error: Template error: int got invalid input 'x' but no default was specified | Refuses / RenderInfo | no | none (same as TPL-13) |
| TPL-15 | `cases/04_filters_tests.yaml::tst_iterable_range` | bool `True` | bool `False` | Silent | no | `patches/TPL-15.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-16 | `cases/04_filters_tests.yaml::flt_float_vt_ws` | float `1.5` | int `0` | Silent | no | none (a change of `toFloat?` breaks theorem `toFloat_cases`, `RenderSpec3.lean:147`; not attempted) |
| TPL-17 | `cases/05_parse_result.yaml::pr_fullwidth_int` | int `12` | str `'１２'` | Silent | no | none (needs Unicode's decimal-digit table) |
| TPL-18 | `cases/05_parse_result.yaml::pr_static_nbsp_strip` | int `42` | str `' 42 '` | Silent | no | none (a change breaks theorem `compile_render_static`, `RenderSpec2.lean:749`, which states that a static template renders to `raw.trim`) |
| TPL-19 | `cases/04_filters_tests.yaml::flt_title_vt` | str `'B'` | str `'b'` | Silent | no | `patches/TPL-19.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-20 | `cases/02_values.yaml::val_str_split_none_maxsplit` | list `['a', 'b  c ']` | list `['a', 'b  c']` | Silent | no | `patches/TPL-20.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-21 | `cases/02_values.yaml::val_floordiv_neg_by_inf` | float `-1.0` | float `-0.0` | Silent | no | `patches/TPL-21.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-22 | `cases/07_datetime.yaml::dt_timestamp_custom_default_format` | str `'2023-11-14 14:13:20'` | str `'2023-11-14'` | Silent | no | `patches/TPL-22.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-23 | `cases/07_datetime.yaml::dt_as_datetime_hour_24` | str `'2026-11-21 00:00:00'` | NoneType `None` | Silent | no | `patches/TPL-23.patch` (turns it into a render error, like the other ciso8601-only forms); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-24 | `cases/07_datetime.yaml::dt_strftime_small_year` | str `'0999\|99\|0999-01-02\|01/02/99'` | str `'999\|99\|999-01-02\|01/02/99'` | Silent | no | `patches/TPL-24.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-25 | `cases/07_datetime.yaml::dt_as_local_summer` | str `'2026-07-01 05:00:00-07:00'` | str `'2026-07-01 04:00:00-08:00'` | Silent | yes (README 662-665: "* Time zones: the engine knows the current UTC offset, not the zone database. `as_local` and friends use that offset, so instants on the other side of a DST change are off by the DST difference. Zone names (`strftime('%Z')`, `tzinfo`) are errors.") | none (needs a zone database) |
| TPL-26 | `cases/02_values.yaml::val_var_float_exp` | str `'1e+20'` | int `100000000000000000000` | Silent | no (README 670-671 covers only floats sent on by HALean) | none (Lean's `Json` has already dropped the distinction) |
| TPL-27 | `cases/06_states.yaml::st_attr_order` | dict `{'b': 1, 'a': 2}` | dict `{'a': 2, 'b': 1}` | Order | yes (README 653-656: "* Lean's JSON objects are sorted by key. Where HA depends on the written order (`variables`), the shell sends ordered `[key, value]` lists (`bridge/protocol.py`). Elsewhere a dict printed by a template, such as `{{ trigger.event.data }}`, lists its keys sorted, not in arrival order.") | none |
| TPL-28 | `cases/05_parse_result.yaml::pr_ellipsis_rendered` | ellipsis `Ellipsis` | str `'...'` | Silent / Refuses | no (manifest.yaml, `_cached_parse_result`: "sets become lists, bytes stay strings") | none (needs set, bytes and Ellipsis values) |
| TPL-29 | `cases/08_extra.yaml::pr_nested_unary_in_list` | str `'[--4]'` | list `[4]` | Silent | no | `patches/TPL-29.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-30 | `cases/01_syntax.yaml::syn_int_leading_zero` | error: TemplateSyntaxError: expected token 'end of print statement', got 'integer' | int `7` | Accepts | no | `patches/TPL-30.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-31 | `cases/01_syntax.yaml::syn_if_cond_expr_in_test` | error: TemplateSyntaxError: expected token 'end of statement block', got 'if' | str `'x'` | Accepts | no | `patches/TPL-31.patch` (partial: `if` tests and constant targets; not `loop` targets, not `break` outside a loop); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-32 | `cases/02_values.yaml::val_int_div_overflow` | error: OverflowError: integer division result too large for a float | str `'inf'` | Accepts | no | `patches/TPL-32.patch` (not the timedelta range); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-33 | `cases/04_filters_tests.yaml::flt_arity_upper` | error: TypeError: do_upper() takes 1 positional argument but 2 were given | str `'A'` | Accepts (one Silent) | no | none (every filter, test and method needs its signature) |
| TPL-34 | `cases/06_states.yaml::st_nonstr_is_state` | error: AttributeError: 'int' object has no attribute 'lower' | bool `False` | Accepts | no | `patches/TPL-34.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-35 | `cases/04_filters_tests.yaml::flt_sum_strings_start` | error: TypeError: sum() can't sum strings [use ''.join(seq) instead] | str `'ab'` | Accepts | no | `patches/TPL-7.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-36 | `cases/07_datetime.yaml::dt_timestamp_utc_as_global` | error: UndefinedError: 'timestamp_utc' is undefined | str `'1970-01-01T00:00:00+00:00'` | Accepts | no | `patches/TPL-36.patch`; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-37 | `cases/07_datetime.yaml::dt_timestamp_utc_1e20_default` | error: OverflowError: timestamp out of range for platform time_t | str `'d'` | Accepts | no | none |
| TPL-38 | `cases/06_states.yaml::st_states_filter_info` | int `5`; info entities=[] | int `5`; info entities=['sensor.a'] | RenderInfo / Accepts | no | none (HA behaviour comes from Jinja's optimizer) |
| TPL-39 | `cases/01_syntax.yaml::syn_int_hex` | int `31` | `unsupported`: unexpected 'x1F' at the end of the expression | Refuses (at load) | no (README 246 lists as rejected: "any other global, filter or test, macros, `include`, `raw`") | `patches/TPL-30.patch` fixes `0x`/`0o`/`0b` literals and `x.0`; nothing for the rest; yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-40 | `cases/02_values.yaml::val_str_method_join` | str `'a,b'` | error: str.join is not supported by HALean | Refuses (at render) | no (README 246: "str methods `split`, `strip`, `replace`, `startswith`, ...") | none |
| TPL-41 | `cases/04_filters_tests.yaml::flt_int_base16` | int `26` | error: int() with a base other than 10 is not supported by HALean | Refuses (at render) | no (manifest.yaml notes `base` and `rounded/with_unit`) | none |
| TPL-42 | `cases/07_datetime.yaml::dt_attr_date` | str `'2026-11-20'` | error: datetime.date is not supported by HALean | Refuses (at render) | partly (README 248-249 names `tzinfo` and `strftime('%Z')` only) | none |
| TPL-43 | `cases/07_datetime.yaml::dt_as_datetime_date_only` | str `'2026-11-20 00:00:00'` | error: parsing '2026-11-20' as a date/time is not supported by HALean | Refuses (at render) | no (manifest.yaml, `parse_datetime`: "strings only ciso8601 would accept are errors") | none |
| TPL-44 | `cases/02_values.yaml::val_print_state_object` | str `'<template TemplateState(<state sensor.a=1 @ 2026-11-20T08:30:45.123000-08:00>)>'` | error: printing the state object of sensor.a is not supported by HALean | Refuses (at render) | partly (README 250-251 names generators only) | none |
| TPL-45 | `cases/03_undefined_scope.yaml::und_first` | bool `False` | error: UndefinedError: 'dict object' has no attribute 'x' is undefined | Refuses (at render) | no | `patches/TPL-45.patch` (first/last/reverse of Undefined, `as_datetime('nan')`); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-46 | `gen/random-seed101.jsonl::r101_2244` | str `"6 months 21 days 18 hours 45 seconds[{'a': -1, 'b': 'unknown'}, {'a': 10, 'b': 'true'}, {'a': 12, 'b': 'é'}]"` | error: lower on non-ASCII text is not supported by HALean | Refuses (at render) | yes (README 252-254: "so it is never a silent wrong answer. Case-changing filters on non-ASCII text are also errors for now, and so are case-insensitive `sort`/`min`/`max`/`unique` over non-ASCII strings (`str.lower()`) and sorting keys that are not totally ordered") | none |
| TPL-47 | `cases/08_extra.yaml::flt_float_exponent_1e8` | str `'inf'` | str `'inf'` | Refuses (time, memory, engine abort) | no | `patches/TPL-47.patch` (log: `patches/TPL-47-huge-exponent.log`); yes, tested with all patches applied: `patches/all-patches-shipped-differential.log` |
| TPL-48 | `cases/08_extra.yaml::loop_step_budget_nested` | str `'x'` | error: template exceeded HALean's step budget | Refuses (at render) | no (README 693-694 mentions `STEP_FUEL` for scripts only) | none |

## Details

### TPL-1: string escapes \ooo \u \U \N not decoded

Kind: Silent. Cases: 8 hand-written, 0 + 0 random.

```
case:     syn_str_octal_escape
template: {{ '\101' }}
HA:       {"ok": true, "type": "str", "repr": "'A'"}
HALean:   {"ok": true, "repr": "'\\\\101'", "type": "str"}
```

Jinja decodes string literals with the `unicode-escape` codec (`jinja2/lexer.py:654`); `ast.literal_eval` uses Python's literal rules. `unescape` (`HALean/Template/Syntax.lean:93`) knows `\n \t \r \0 \\ \' \" \a \b \f \v \xHH` and keeps every other escape as written. The same function serves `literalEval` (`Render.lean:2004`). Other cases: `syn_str_u_escape`, `syn_str_bigu_escape`, `syn_str_name_escape`, `syn_str_octal_escape_012`, `pr_str_*_escape_in_list`.

Other hand-written cases: `syn_str_octal_escape_012`, `syn_str_u_escape`, `syn_str_bigu_escape`, `syn_str_name_escape`, `pr_str_u_escape_in_list`, `pr_str_octal_escape_in_list`, `pr_str_named_escape_in_list`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives `unsupported`: octal escapes are not supported by HALean (category `refuses_load`).

### TPL-2: dict keys: no dedup, no hash check

Kind: Silent / Accepts. Cases: 9 hand-written, 10 + 8 random.

```
case:     val_dict_dup_keys
template: {{ {'a': 1, 'a': 2} }}
HA:       {"ok": true, "type": "dict", "repr": "{'a': 2}"}
HALean:   {"ok": true, "repr": "{'a': 1, 'a': 2}", "type": "dict"}
```

A dict is an association list (`Value.lean:29`). The dict display keeps every pair (`Render.lean:1226`), so equal keys (`'a'`/`'a'`, `1`/`1.0`/`True`) are not merged, and no key is hashed: `{[1]: 2}` and `[1] in {'a': 1}` (`containsV`, `Render.lean:454`) give a value where Python raises `TypeError`. `literalEval` does the same (`Render.lean:2056`-`2078`): `{1: 2, 1: 3}` and `{[1]: 2}` (HA returns the string). Jinja builds a real dict (`jinja2/compiler.py:1702`).

Other hand-written cases: `val_in_dict_unhashable`, `val_dict_dup_keys_len`, `val_dict_int_bool_float_keys`, `val_dict_unhashable_key`, `pr_dict_dup_key`, `pr_dict_int_bool_key`, `pr_dict_unhashable_key`, `pr_set_unhashable`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives dict `{'a': 2}` (category `same`).

### TPL-3: dict.keys()/values()/items() are lists

Kind: Silent. Cases: 5 hand-written, 0 + 0 random.

```
case:     val_dict_keys_print
template: {{ {'a': 1}.keys() }}
HA:       {"ok": true, "type": "str", "repr": "\"dict_keys(['a'])\""}
HALean:   {"ok": true, "repr": "['a']", "type": "list"}
```

`dict.keys` / `values` / `items` return lists (`Render.lean:1495`-`1497`). In Python they are views: they print as `dict_keys([...])`, are not equal to a list and cannot be indexed (`val_dict_keys_eq_list`, `val_dict_keys_index`).

Other hand-written cases: `val_dict_values_print`, `val_dict_items_print`, `val_dict_keys_eq_list`, `val_dict_keys_index`.

### TPL-4: bool() of states objects; `if value:` guard of map/select

Kind: Silent (value and RenderInfo). Cases: 14 hand-written, 43 + 63 random.

```
case:     val_truthy_domain_empty
template: {{ 'y' if states.sensor else 'n' }}
HA:       {"ok": true, "type": "str", "repr": "'n'"}
HALean:   {"info": {"all_states": false, "all_states_lifecycle": false, "domains": [], "domains_lifecycle": [], "entities": []}, "ok": true, "repr": "'y'", "type": "str"}
HA info:  {"entities": [], "domains": [], "domains_lifecycle": ["sensor"], "all_states": false, "all_states_lifecycle": false}
```

`truthy` (`Value.lean:281`) is true for `states` and `states.<domain>`. In HA `bool()` calls `DomainStates.__len__` / `AllStates.__len__` (`helpers/template/states.py:142`, `:243` ff.), which returns the number of states and records `domains_lifecycle` / `all_states_lifecycle`. Affected: `if`, `not`, `and`, `or`, `iif`, `default(x, true)`. Jinja's `sync_do_map` (`jinja2/filters.py:1437`) and `select_or_reject` (`:1786`) start with `if value:`: over a states object that records the lifecycle listener (and for an empty domain nothing else), and a falsy non-iterable input (`none`, `false`, `timedelta(0)`) gives an empty result where Lean raises `not iterable` (`Render.lean:1651`, `1663`, `1672`). Most random cases are of the lifecycle kind: the result is equal, `domains_lifecycle` / `all_states_lifecycle` differ.

Other hand-written cases: `val_truthy_domain_nonempty`, `val_truthy_all_states_empty`, `val_not_domain_empty`, `st_domain_join_info`, `st_domain_select_info`, `st_domain_sum_info`, `st_domain_if_info`, `st_empty_domain_select_info`, `st_empty_domain_map_info`, `st_all_select_info`, `st_domain_and_info`, `st_domain_iif_info`, `st_domain_default_boolean_info`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'n'` (category `same`).

### TPL-5: last / reverse over states objects

Kind: Silent / Accepts. Cases: 3 hand-written, 0 + 0 random.

```
case:     st_domain_last
template: {{ (states.sensor | last).state }}
HA:       {"ok": true, "type": "str", "repr": "''"}
HALean:   {"info": {"all_states": false, "all_states_lifecycle": false, "domains": ["sensor"], "domains_lifecycle": [], "entities": []}, "ok": true, "repr": "6", "type": "int"}
HA info:  {"entities": ["sensor.1"], "domains": [], "domains_lifecycle": ["sensor"], "all_states": false, "all_states_lifecycle": false}
```

`last` and `reverse` call `reversed(value)` (`jinja2/filters.py:674`, `:1386`). `DomainStates` and `AllStates` have `__len__` and `__getitem__` but no `__reversed__`, so Python uses the sequence protocol: `states.sensor[1]` is `states.sensor.1`, the (missing) entity `sensor.1`, i.e. `None`; for `states` it raises. Lean iterates the states backwards (`Render.lean:1615`, `:1645`). HA's result here is of no use to a template author; the difference is still a different value.

Other hand-written cases: `st_domain_reverse`, `st_all_reverse`.

### TPL-6: case-insensitive entity id lookup

Kind: Silent (value and RenderInfo). Cases: 6 hand-written, 5 + 2 random.

```
case:     st_case_insensitive_call
template: {{ states('SENSOR.Temp') }}
HA:       {"ok": true, "type": "int", "repr": "21"}
HALean:   {"info": {"all_states": false, "all_states_lifecycle": false, "domains": [], "domains_lifecycle": [], "entities": ["SENSOR.Temp"]}, "ok": true, "repr": "'unknown'", "type": "str"}
HA info:  {"entities": ["sensor.temp"], "domains": [], "domains_lifecycle": [], "all_states": false, "all_states_lifecycle": false}
```

`hass.states.get` retries with `entity_id.lower()` (`core.py:2286`). `states()`, `is_state`, `state_attr`, `is_state_attr`, `has_value`, `states['X.y']` all go through it (`helpers/template/states.py:515`, `:522`). Lean looks up the id as written (`Render.lean:282`, `:833`, `:844`, `:852`, `:1317`, `:1333`); only `expand` uses `hassStatesGet` (`Render.lean:1061`). HA also records the id of the state it found (`sensor.temp`), Lean the id as written.

Other hand-written cases: `st_case_insensitive_is_state`, `st_case_insensitive_state_attr`, `st_case_insensitive_has_value`, `st_case_insensitive_subscript`, `st_case_insensitive_is_state_attr`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives int `21` (category `same`).

### TPL-7: float sum is not compensated

Kind: Silent. Cases: 3 hand-written, 0 + 0 random.

```
case:     flt_sum_float_compensated
template: {{ [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1] | sum }}
HA:       {"ok": true, "type": "float", "repr": "1.0"}
HALean:   {"ok": true, "repr": "0.9999999999999999", "type": "float"}
```

The `sum` filter is Python's `sum` (`jinja2/filters.py:1340`). Since Python 3.12 `sum` adds floats with Neumaier's compensated summation (CPython `Python/bltinmodule.c`, `builtin_sum_impl`). Lean adds left to right with `arith "+"` (`Render.lean:1636`-`1640`).

Other hand-written cases: `flt_sum_float_cancel`, `flt_sum_float_start`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives float `1.0` (category `same`).

### TPL-8: repr(str) non-printable characters

Kind: Silent. Cases: 7 hand-written, 0 + 0 random.

```
case:     val_repr_nbsp
template: {{ [' '] | string | length }}
HA:       {"ok": true, "type": "int", "repr": "8"}
HALean:   {"ok": true, "repr": "5", "type": "int"}
```

`strRepr` (`Value.lean:215`) escapes only characters below U+0020 and U+007F. Python's `repr` escapes every non-printable character (`\xa0`, `\x85`, `\xad`, `\u2028`, `\u200b`, `\ue000`). Visible through `| string`, `~`, and in the `repr` the driver prints.

Other hand-written cases: `val_repr_c1_control`, `val_repr_soft_hyphen`, `val_repr_line_separator`, `val_repr_private_use`, `val_repr_zero_width_space`, `val_repr_nbsp_result`.

### TPL-9: Undefined inside a printed container

Kind: Silent. Cases: 3 hand-written, 21 + 21 random.

```
case:     val_print_undefined_in_list
template: {{ [trigger.x] }}
HA:       {"ok": true, "type": "str", "repr": "'[Undefined]'"}
HALean:   {"ok": true, "repr": "[]", "type": "list"}
```

`pyRepr (.undef _)` is `""` (`Value.lean:241`). `repr(Undefined)` is `Undefined` (`jinja2/runtime.py:796` ff.). `{{ [trigger.x] }}` is the string `[Undefined]` in HA and the empty list in Lean (after `_parse_result`).

Other hand-written cases: `val_print_undefined_in_dict`, `val_print_undefined_in_tuple_len`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'[Undefined]'` (category `same`).

### TPL-10: Namespace repr

Kind: Silent. Cases: 2 hand-written, 0 + 0 random.

```
case:     val_print_namespace
template: {{ namespace(a=1) }}
HA:       {"ok": true, "type": "str", "repr": "\"<Namespace {'a': 1}>\""}
HALean:   {"ok": true, "repr": "'<Namespace>'", "type": "str"}
```

`pyRepr (.ns _)` is `<Namespace>` (`Value.lean:251`); Jinja prints `<Namespace {...}>` (`jinja2/utils.py:745` ff.).

Other hand-written cases: `val_print_namespace_empty`.

### TPL-11: loop object is a dict

Kind: Silent / Refuses / Accepts. Cases: 8 hand-written, 0 + 0 random.

```
case:     val_print_loop
template: {% for x in [1, 2] %}{{ loop }}{% endfor %}
HA:       {"ok": true, "type": "str", "repr": "'<LoopContext 1/2><LoopContext 2/2>'"}
HALean:   {"ok": true, "repr": "\"{'index': 1, 'index0': 0, 'revindex': 2, 'revindex0': 1, 'first': True, 'last': False, 'length': 2, 'previtem': , 'nextitem': 2}{'index': 2, 'index0': 1, 'revindex': 1, 'revindex0': 0, 'first': False, 'last': True, 'length': 2, 'previtem': 1, 'nextitem': }\"", "type": "str"}
```

`loop` is a dict with nine keys (`Render.lean:1800`-`1806`); Jinja's is a `LoopContext` (`jinja2/runtime.py:394`). Differences: printing (`<LoopContext 1/2>`), `loop is mapping` (False in HA), `loop | length` (the loop length in HA), iterating `loop`, `loop.depth` / `depth0` (Undefined in Lean), `loop.cycle()` / `loop.changed()` (render error in Lean), `{% set loop = 5 %}` inside a loop (TemplateAssertionError in HA).

Other hand-written cases: `loop_cycle`, `loop_changed`, `loop_depth`, `loop_is_mapping`, `loop_length_filter`, `loop_iterate_loop`, `loop_name_reassigned`.

### TPL-12: for-else after break/continue

Kind: Silent. Cases: 3 hand-written, 5 + 9 random.

```
case:     loop_break_then_else
template: {% for i in [1] %}{% break %}{% else %}e{% endfor %}x
HA:       {"ok": true, "type": "str", "repr": "'ex'"}
HALean:   {"ok": true, "repr": "'x'", "type": "str"}
```

Jinja compiles `for … else` with a flag that is cleared at the end of the loop body (`jinja2/compiler.py:1252` and the `{iteration_indicator} = 0` line of `visit_For`). `break` and `continue` skip that line, so the `else` block runs unless some iteration reached the end of the body. Lean runs it only when there was no item (`Render.lean:1810`).

Other hand-written cases: `loop_continue_all_then_else`, `loop_filtered_all_continue_else`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'ex'` (category `same`).

### TPL-13: generators can be consumed twice

Kind: Silent. Cases: 7 hand-written, 0 + 0 random.

```
case:     flt_generator_reused_sum
template: {% set g = [1, 2] | map('int') %}{{ g | sum }}{{ g | sum }}
HA:       {"ok": true, "type": "int", "repr": "30"}
HALean:   {"ok": true, "repr": "33", "type": "int"}
```

`map`, `select`, `reject`, `selectattr`, `rejectattr`, `unique`, `reverse` return one-shot iterators in Jinja. Lean stores the items (`Value.gen`, `Value.lean:52`); using the value twice gives the items twice.

Other hand-written cases: `loop_over_generator_twice`, `loop_generator_list_twice`, `flt_generator_length_after_list`, `flt_generator_first_then_list`, `flt_reverse_iterator_reused`, `flt_unique_generator_reused`.

### TPL-14: generators are evaluated eagerly

Kind: Refuses / RenderInfo. Cases: 3 hand-written, 0 + 0 random.

```
case:     flt_map_lazy_first
template: {{ [1, 'x'] | map('int') | first }}
HA:       {"ok": true, "type": "int", "repr": "1"}
HALean:   {"error": "Template error: int got invalid input 'x' but no default was specified", "ok": false}
```

The same lists are computed eagerly (`Render.lean:1650`-`1681`). Jinja's generators stop when the consumer stops: `[1, 'x'] | map('int') | first` never converts `'x'`, and `['sensor.a', 'sensor.b'] | map('states') | first` reads only `sensor.a` (case `flt_map_lazy_states_info`: Lean records both entities).

Other hand-written cases: `flt_select_lazy_first`, `flt_map_lazy_states_info`.

### TPL-15: tests sequence / iterable

Kind: Silent. Cases: 6 hand-written, 0 + 0 random.

```
case:     tst_iterable_range
template: {{ range(3) is iterable }}
HA:       {"ok": true, "type": "bool", "repr": "True"}
HALean:   {"ok": true, "repr": "False", "type": "bool"}
```

`applyTest` (`Render.lean:1712`-`1713`): `sequence` is true for list, tuple, str, dict; `iterable` adds Undefined. Jinja (`jinja2/tests.py:167`, `:193`): `sequence` needs `len()` and `__getitem__` (true for range, `states`, `states.<domain>`, Undefined); `iterable` needs `iter()` (true for range, generators, `states`, `states.<domain>`).

Other hand-written cases: `und_is_sequence`, `tst_sequence_range`, `tst_iterable_generator`, `tst_iterable_states`, `tst_iterable_domain`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives bool `True` (category `same`).

### TPL-16: float(): whitespace and digits

Kind: Silent. Cases: 5 hand-written, 0 + 0 random.

```
case:     flt_float_vt_ws
template: {{ '1.5' | float(0) }}
HA:       {"ok": true, "type": "float", "repr": "1.5"}
HALean:   {"ok": true, "repr": "0", "type": "int"}
```

`parseFloatStr` (`Value.lean:154`) trims with Lean's `String.trim` (space, `\t`, `\n`, `\r`) and reads ASCII digits. Python's `float()` strips every `str.isspace` character (`\v`, `\f`, `\x1c`-`\x1f`, U+00A0, …) and reads every Unicode decimal digit. `float`, `is_number`, `round`, `as_datetime` share it. `int` refuses non-ASCII text instead (`Render.lean:214`).

Other hand-written cases: `flt_float_ff_ws_isnumber`, `flt_float_nbsp_ws`, `flt_float_arabic_digits`, `flt_float_fullwidth_isnumber`.

### TPL-17: _parse_result: Unicode digits

Kind: Silent. Cases: 3 hand-written, 0 + 0 random.

```
case:     pr_fullwidth_int
template: １２
HA:       {"ok": true, "type": "int", "repr": "12"}
HALean:   {"ok": true, "repr": "'１２'", "type": "str"}
```

`_IS_NUMERIC` is `^[+-]?(?!0\d)\d*(?:\.\d*)?$` on a str (`helpers/template/__init__.py:102`): `\d` matches all Unicode decimal digits, and `int()` / `float()` read them. `isNumericStr` (`Render.lean:1900`) uses `Char.isDigit`.

Other hand-written cases: `pr_fullwidth_float`, `pr_arabic_int_rendered`.

### TPL-18: static template strip is ASCII-only

Kind: Silent. Cases: 3 hand-written, 0 + 0 random.

```
case:     pr_static_nbsp_strip
template:  42 
HA:       {"ok": true, "type": "int", "repr": "42"}
HALean:   {"ok": true, "repr": "' 42 '", "type": "str"}
```

`Template.__init__` strips with `str.strip()` (`helpers/template/__init__.py:359`). `compile` uses `raw.trim` (`Syntax.lean:622`), which strips four ASCII characters. Only static templates are affected; rendered output is stripped with `pyStrip` (`Render.lean:2155`).

Other hand-written cases: `pr_static_vt_strip`, `pr_static_us_strip_text`.

### TPL-19: title filter whitespace

Kind: Silent. Cases: 1 hand-written, 0 + 0 random.

```
case:     flt_title_vt
template: {{ 'ab' | title | last }}
HA:       {"ok": true, "type": "str", "repr": "'B'"}
HALean:   {"ok": true, "repr": "'b'", "type": "str"}
```

`do_title` splits on `[-\s({\[<]+` (`jinja2/filters.py:331`, `_word_beginning_split_re`); Lean tests `Char.isWhitespace` (`Render.lean:1587`), so `\v`, `\f`, `\x1c`-`\x1f` do not start a word.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'B'` (category `same`).

### TPL-20: str.split(None, maxsplit) remainder

Kind: Silent. Cases: 1 hand-written, 0 + 0 random.

```
case:     val_str_split_none_maxsplit
template: {{ ' a b  c '.split(none, 1) }}
HA:       {"ok": true, "type": "list", "repr": "['a', 'b  c ']"}
HALean:   {"ok": true, "repr": "['a', 'b  c']", "type": "list"}
```

`pySplit` with `sep=None` and a `maxsplit` strips the remainder on the right (`Render.lean:780`); Python keeps its trailing whitespace.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives list `['a', 'b  c ']` (category `same`).

### TPL-21: float // and % with infinities

Kind: Silent. Cases: 4 hand-written, 0 + 0 random.

```
case:     val_floordiv_neg_by_inf
template: {{ -5 // ('inf' | float) }}
HA:       {"ok": true, "type": "float", "repr": "-1.0"}
HALean:   {"ok": true, "repr": "-0.0", "type": "float"}
```

`floatFloorDivMod` (`Render.lean:589`-`590`) uses `floor(a / b)` and `a - b * floor(a / b)` when an operand is not finite. CPython's `float_divmod` uses `fmod` and a sign fix-up: `5 % inf = 5.0`, `-5 % inf = inf`, `-5 // inf = -1.0`, `inf // 2 = nan`.

Other hand-written cases: `val_mod_inf_divisor`, `val_mod_neg_by_inf`, `val_floordiv_inf_dividend`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives float `-1.0` (category `same`).

### TPL-22: timestamp_custom default format

Kind: Silent. Cases: 1 hand-written, 0 + 0 random.

```
case:     dt_timestamp_custom_default_format
template: {{ 1700000000 | timestamp_custom }}
HA:       {"ok": true, "type": "str", "repr": "'2023-11-14 14:13:20'"}
HALean:   {"ok": true, "repr": "'2023-11-14'", "type": "str"}
```

`timestamp_custom`'s default `date_format` is `DATE_STR_FORMAT = "%Y-%m-%d %H:%M:%S"` (`helpers/template/extensions/datetime.py:16`, `:139`). Lean uses `"%Y-%m-%d"` (`Render.lean:1437`).

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'2023-11-14 14:13:20'` (category `same`).

### TPL-23: T24:00:00 gives None

Kind: Silent. Cases: 1 hand-written, 0 + 0 random.

```
case:     dt_as_datetime_hour_24
template: {{ as_datetime('2026-11-20T24:00:00') }}
HA:       {"ok": true, "type": "str", "repr": "'2026-11-21 00:00:00'"}
HALean:   {"ok": true, "repr": "None", "type": "NoneType"}
```

`parse_datetime` tries `ciso8601` first (`util/dt.py:232`), which reads `24:00:00` as midnight of the next day. Lean's regex path builds `hour=24`, fails the range check and returns `none` (`Render.lean:567`), so `as_datetime` returns `None`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives error: parsing '2026-11-20T24:00:00' as a date/time is not supported by HALean (category `refuses_render`).

### TPL-24: strftime %Y below year 1000

Kind: Silent. Cases: 1 hand-written, 0 + 0 random.

```
case:     dt_strftime_small_year
template: {{ as_datetime('0999-01-02 03:04:05').strftime('%Y|%y|%F|%D') }}
HA:       {"ok": true, "type": "str", "repr": "'0999|99|0999-01-02|01/02/99'"}
HALean:   {"ok": true, "repr": "'999|99|999-01-02|01/02/99'", "type": "str"}
```

`%Y` and `%F` print the year without padding (`Time.lean:169`, `:174`). Python 3.14 pads `%Y` (and the year of `%F`) to four digits.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'0999|99|0999-01-02|01/02/99'` (category `same`).

### TPL-25: zone database / DST (documented)

Kind: Silent. Cases: 12 hand-written, 7 + 8 random.

```
case:     dt_as_local_summer
template: {{ as_datetime('2026-07-01T12:00:00+00:00') | as_local }}
HA:       {"ok": true, "type": "str", "repr": "'2026-07-01 05:00:00-07:00'"}
HALean:   {"ok": true, "repr": "'2026-07-01 04:00:00-08:00'", "type": "str"}
```

A datetime carries a fixed offset and the engine knows only the current one (`asLocal`, `Render.lean:504`; `today_at`, `:1362`). Consequences seen: `as_local`, `timestamp_local`, `timestamp_custom` of an instant on the other side of a DST change; `now() ± timedelta` and `.replace(month=…)` across a change (Python keeps the zone and the wall time, the offset changes); `today_at()` on the day of a change; subtraction of two datetimes of the same zone (Python subtracts wall clocks, Lean instants: `dt_same_zone_wall_subtraction` differs by 3600 s); dates before 1883 (local mean time).

Other hand-written cases: `dt_timestamp_local_summer`, `dt_timestamp_custom_summer`, `dt_as_local_naive_summer`, `dt_add_days_across_dst`, `dt_sub_days_across_dst`, `dt_replace_month_summer`, `dt_same_zone_wall_subtraction`, `dt_today_at_dst_start_day_before_gap`, `dt_today_at_dst_start_day_after_gap`, `dt_today_at_dst_end_day`, `dt_today_at_midnight_dst_start_day`.

### TPL-26: JSON numbers with an exponent become ints

Kind: Silent. Cases: 2 hand-written, 0 + 0 random.

```
case:     val_var_float_exp
template: {{ x }}
HA:       {"ok": true, "type": "str", "repr": "'1e+20'"}
HALean:   {"ok": true, "repr": "100000000000000000000", "type": "int"}
```

`Value.ofJson` (`Value.lean:422`-`424`) makes an int of every JSON number whose `exponent` field is 0. Lean's JSON parser reads `1e+20` as mantissa 10^20, exponent 0, so a float that Python prints with an exponent (1e16 and above) arrives as an int. Applies to variables and to state attributes (`st_attr_float_exp`).

Other hand-written cases: `st_attr_float_exp`.

### TPL-27: attribute / variable key order (documented)

Kind: Order. Cases: 4 hand-written, 2 + 1 random.

```
case:     st_attr_order
template: {{ states.sensor.t.attributes }}
HA:       {"ok": true, "type": "dict", "repr": "{'b': 1, 'a': 2}"}
HALean:   {"ok": true, "repr": "{'a': 2, 'b': 1}", "type": "dict"}
```

Attributes and variables are decoded from Lean JSON objects, which are sorted by key (`Value.lean:427`). Printing or iterating them gives sorted keys.

Other hand-written cases: `val_var_dict_order`, `st_attr_keys_order`, `st_attr_nested_order`.

### TPL-28: literal_eval: set, bytes, Ellipsis, complex

Kind: Silent / Refuses. Cases: 12 hand-written, 0 + 0 random.

```
case:     pr_ellipsis_rendered
template: {{ '...' }}
HA:       {"ok": true, "type": "ellipsis", "repr": "Ellipsis"}
HALean:   {"ok": true, "repr": "'...'", "type": "str"}
```

`ast.literal_eval` returns any Python constant. HA returns it unless it is a str, a complex or a non-numeric-looking number (`helpers/template/__init__.py:268`-`299`). Lean's `literalEval` (`Render.lean:2116`): a set display becomes a list (`:2073`), `set()` and bytes stay strings, `...` stays a string (HA returns `Ellipsis`: a template that prints three dots renders to the `Ellipsis` object), and a container holding a complex is a render error (`pr_complex_in_list`).

Other hand-written cases: `syn_dict_lone_brace_text`, `pr_set`, `pr_set_empty_call`, `pr_set_dedupe`, `pr_bytes`, `pr_bytes_in_list`, `pr_complex_in_list`, `pr_ellipsis`, `pr_ellipsis_in_list`, `pr_set_single_str`, `pr_rendered_set_like`.

### TPL-29: literal_eval: nested unary sign

Kind: Silent. Cases: 2 hand-written, 0 + 0 random.

```
case:     pr_nested_unary_in_list
template: [--4]
HA:       {"ok": true, "type": "str", "repr": "'[--4]'"}
HALean:   {"ok": true, "repr": "[4]", "type": "list"}
```

`litParse` accepts nested unary signs (`Render.lean:2022`-`2029`, comment: "literal_eval allows nested unary on numbers"). CPython's `ast.literal_eval` (`_convert_signed_num`) allows one sign on a number; `[--4]` is a `ValueError` and HA returns the string.

Other hand-written cases: `pr_signs_in_list`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'[--4]'` (category `same`).

### TPL-30: lexer accepts .5 and 007

Kind: Accepts. Cases: 2 hand-written, 0 + 0 random.

```
case:     syn_int_leading_zero
template: {{ 007 }}
HA:       {"ok": false, "error": "TemplateSyntaxError: expected token 'end of print statement', got 'integer'"}
HALean:   {"ok": true, "repr": "7", "type": "int"}
```

`lexBlock` (`Syntax.lean:142`-`170`) starts a number at `.5` and reads `007` as 7. Jinja's `float_re` needs a digit before the point and `integer_re` is `[1-9](_?\d)*|0(_?0)*` (`jinja2/lexer.py:32`, `:48`): both are `TemplateSyntaxError`.

Other hand-written cases: `syn_float_leading_dot`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives `unsupported`: invalid number 007 (category `both_refuse_load`).

### TPL-31: parser accepts invalid Jinja

Kind: Accepts. Cases: 5 hand-written, 0 + 0 random.

```
case:     syn_if_cond_expr_in_test
template: {% if 1 if 0 else 2 %}x{% endif %}
HA:       {"ok": false, "error": "TemplateSyntaxError: expected token 'end of statement block', got 'if'"}
HALean:   {"ok": true, "repr": "'x'", "type": "str"}
```

`parseStmt` parses `if`/`elif` tests with `parseTuple` (`Syntax.lean:512`), which allows `a if b else c`; Jinja uses `parse_tuple(with_condexpr=False)` (`jinja2/parser.py:255`). `parseTargets` (`Syntax.lean:505`) accepts `none`/`true`/`false` (Jinja: "can't assign to 'const'", `parser.py:507`) and `loop` inside a loop. `{% break %}` / `{% continue %}` outside a loop render in Lean; HA's compile raises a Python `SyntaxError` that is not a `TemplateError` (cases in `gen/batch_only.yaml`).

Other hand-written cases: `syn_set_to_none_name`, `syn_set_to_true_name`, `syn_break_outside_loop`, `syn_continue_outside_loop`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives `unsupported`: unexpected 'if' at the end of the expression (category `both_refuse_load`).

### TPL-32: OverflowError / digit limit not raised

Kind: Accepts. Cases: 11 hand-written, 0 + 0 random.

```
case:     val_int_div_overflow
template: {{ 10 ** 400 / 1 }}
HA:       {"ok": false, "error": "OverflowError: integer division result too large for a float"}
HALean:   {"ok": true, "repr": "'inf'", "type": "str"}
```

Lean's ints convert to `inf` and float results overflow to `inf` silently: `int / int` (`Render.lean:676`), mixed arithmetic (`:692`), `int ** negative` (`:690`), `float ** float` (`:706`), `round(x, 400)` (`:907`). Python raises `OverflowError`. `str(int)` and `int(str)` above 4300 digits raise `ValueError` in Python (`Value.lean:243`, `Render.lean:2138`): `{{ 10 ** 5000 }}` fails at compile time in HA with a bare `ValueError` (batch-only case `val_int_print_over_limit`), and a static template of 4400 digits stays a string in HA (`pr_static_4400_digits`, Silent). `timedelta` arithmetic does not check the 999999999-day range (`td_overflow_mul`).

Other hand-written cases: `val_int_plus_float_overflow`, `val_float_pow_overflow`, `val_int_pow_neg_overflow`, `flt_round_huge_precision`, `td_overflow_mul`, `pr_static_4400_digits`, `pr_list_4400_digits`, `pr_rendered_4400_digits`, `val_int_str_4301_limit`, `val_int_print_over_limit`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives error: OverflowError: integer division result too large for a float (category `same`).

### TPL-33: argument count and keywords not checked

Kind: Accepts (one Silent). Cases: 25 hand-written, 0 + 0 random.

```
case:     flt_arity_upper
template: {{ 'a' | upper(1) }}
HA:       {"ok": false, "error": "TypeError: do_upper() takes 1 positional argument but 2 were given"}
HALean:   {"ok": true, "repr": "'A'", "type": "str"}
```

Arguments are read by position or name with defaults (`Args.get`, `Render.lean:814`); only some functions call `Args.check` (`:819`). Extra positional arguments, unknown keywords, duplicate values and missing required arguments are accepted for most filters (`upper`, `length`, `first`, `abs`, `string`, `list`, `trim`, `float`, `round`, `default`), tests (`eq` without an argument, `none(2)`, `defined(1)`), functions (`is_state('x')`, `state_attr('x')`, `has_value()`, `is_number()`, `iif()`) and methods (`dict.get(default=…)`, `isoformat('ab')`). `'abc'.startswith('b', 1)` ignores the start index and returns False (HA: True).

Other hand-written cases: `val_dict_get_kw`, `val_str_startswith_start`, `flt_default_extra_args`, `flt_select_missing_test_arg`, `flt_arity_length`, `flt_arity_first`, `flt_arity_abs`, `flt_arity_string`, `flt_arity_list`, `flt_arity_trim`, `flt_arity_float`, `flt_arity_is_state_missing`, `flt_arity_state_attr_missing`, `flt_arity_has_value_missing`, `flt_arity_is_number_missing`, `flt_arity_iif_missing`, `flt_arity_dup_kw`, `flt_arity_round_extra`, `flt_arity_unknown_kw`, `tst_eq_missing_arg`, `tst_none_extra_arg`, `tst_defined_extra_arg`, `tst_eq_two_args`, `dt_isoformat_long_sep`.

### TPL-34: non-string / Undefined entity id

Kind: Accepts. Cases: 8 hand-written, 0 + 0 random.

```
case:     st_nonstr_is_state
template: {{ is_state(5, 'on') }}
HA:       {"ok": false, "error": "AttributeError: 'int' object has no attribute 'lower'"}
HALean:   {"ok": true, "repr": "False", "type": "bool"}
```

`isState`, `stateAttrFn`, `hasValue` and `is_state_attr` return False / None for an id that is not a string (`Render.lean:831`, `:841`, `:855`, `:1330`). HA calls `hass.states.get(entity_id)`, which fails on `entity_id.lower()` (`core.py:2286`); an Undefined raises `UndefinedError`. Theorems `isState_nonstr`, `hasValue_nonstr`, `stateAttrFn_nonstr` (`RenderSpec3.lean:287`, `:316`, `:331`) state the Lean behaviour.

Other hand-written cases: `und_is_state_arg`, `und_state_attr_arg`, `und_has_value_arg`, `st_nonstr_state_attr`, `st_nonstr_has_value`, `st_nonstr_is_state_attr`, `st_list_id_is_state`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives error: AttributeError: 'int' object has no attribute 'lower' (category `same`).

### TPL-35: sum(start=str)

Kind: Accepts. Cases: 1 hand-written, 0 + 0 random.

```
case:     flt_sum_strings_start
template: {{ ['a', 'b'] | sum(start='') }}
HA:       {"ok": false, "error": "TypeError: sum() can't sum strings [use ''.join(seq) instead]"}
HALean:   {"ok": true, "repr": "'ab'", "type": "str"}
```

Python's `sum` refuses a str start value (`TypeError: sum() can't sum strings`); Lean concatenates (`Render.lean:1638`).

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives error: TypeError: sum() can't sum strings [use ''.join(seq) instead] (category `same`).

### TPL-36: timestamp_* accepted as globals

Kind: Accepts. Cases: 3 hand-written, 0 + 0 random.

```
case:     dt_timestamp_utc_as_global
template: {{ timestamp_utc(0) }}
HA:       {"ok": false, "error": "UndefinedError: 'timestamp_utc' is undefined"}
HALean:   {"ok": true, "repr": "'1970-01-01T00:00:00+00:00'", "type": "str"}
```

`GLOBALS` (`Render.lean:127`-`133`) lists `timestamp_local`, `timestamp_utc`, `timestamp_custom`. HA registers them as filters only (`helpers/template/extensions/datetime.py`, `as_filter=True` without `as_global`): as functions they are undefined (`logs/names.log`).

Other hand-written cases: `dt_timestamp_local_as_global`, `dt_timestamp_custom_as_global`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives error: UndefinedError: 'timestamp_utc' is undefined (category `same`).

### TPL-37: uncaught HA errors treated as 'use default'

Kind: Accepts. Cases: 2 hand-written, 1 + 0 random.

```
case:     dt_timestamp_utc_1e20_default
template: {{ 1e20 | timestamp_utc('d') }}
HA:       {"ok": false, "error": "OverflowError: timestamp out of range for platform time_t"}
HALean:   {"ok": true, "repr": "'d'", "type": "str"}
```

`timestamp_*` and `as_datetime` catch `ValueError` and `TypeError` only (`helpers/template/extensions/datetime.py:139`-`212`). `fromtimestamp` raises `OverflowError` / `OSError` for values outside the platform range, and `float(Undefined)` raises `UndefinedError`; HA lets these through. `utcFromTimestamp` returns `none` for all failures (`Render.lean:495`), so Lean returns the default.

Other hand-written cases: `und_as_datetime_default`.

### TPL-38: Jinja compile-time constant folding

Kind: RenderInfo / Accepts. Cases: 7 hand-written, 3 + 1 random.

```
case:     st_states_filter_info
template: {{ 'sensor.a' | states }}
HA:       {"ok": true, "type": "int", "repr": "5"}
HALean:   {"info": {"all_states": false, "all_states_lifecycle": false, "domains": [], "domains_lifecycle": [], "entities": ["sensor.a"]}, "ok": true, "repr": "5", "type": "int"}
HA info:  {"entities": [], "domains": [], "domains_lifecycle": [], "all_states": false, "all_states_lifecycle": false}
```

Jinja folds constant expressions when it compiles (`jinja2/optimizer.py:27`, `nodes.py:472` `as_const`). A filter without a context decorator applied to a constant is evaluated once, at compile time: `'sensor.a' | states` is baked into the compiled template and records no entity (case `st_states_filter_info`; with a variable, `st_nonconst_states_filter_info`, both sides agree). `'nan' | float` folded into a `set` or an operation is written into the generated code as `nan`, a `NameError` at render (`val_const_fold_nan_set`). Lean evaluates everything at render time.

Other hand-written cases: `val_cmp_nan_eq_self_in_list`, `val_nan_in_list_identity`, `st_states_filter_missing`, `dt_timestamp_utc_inf_default`, `val_const_fold_nan_set`, `st_const_fold_states_filter_value`.

### TPL-39: valid Jinja syntax rejected at load

Kind: Refuses (at load). Cases: 16 hand-written, 0 + 0 random.

```
case:     syn_int_hex
template: {{ 0x1F }}
HA:       {"ok": true, "type": "int", "repr": "31"}
HALean:   {"unsupported": "unexpected 'x1F' at the end of the expression"}
```

Valid Jinja that `compile` rejects: radix integers and `seq.0` item access (`Syntax.lean:142`: `.0` after a name is lexed as a float), `+%}` (`:210`), `\v`/`\f` between tokens (`:136`), non-ASCII identifiers (`:89`), parenthesised or nested assignment targets (`:505`), `recursive` (`:531`), block `set` (`:538`), `*args` (`:406`), `x[]`. HALean answers `unsupported`, so nothing wrong is computed.

Other hand-written cases: `syn_dot_int_index`, `syn_dot_int_index_tuple`, `syn_dot_int_var`, `syn_int_bin`, `syn_int_oct`, `syn_ws_plus_right`, `syn_ws_formfeed_in_expr`, `syn_for_paren_targets`, `syn_for_nested_targets`, `syn_for_recursive`, `syn_set_paren_targets`, `syn_set_block`, `syn_star_args`, `syn_nonascii_name`, `syn_subscript_empty`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives int `31` (category `same`).

### TPL-40: Python methods / attributes / operators not modelled

Kind: Refuses (at render). Cases: 39 hand-written, 11 + 10 random.

```
case:     val_str_method_join
template: {{ ','.join(['a', 'b']) }}
HA:       {"ok": true, "type": "str", "repr": "'a,b'"}
HALean:   {"error": "str.join is not supported by HALean", "ok": false}
```

Attribute access is a closed list per type (`getattrV`, `Render.lean:299`-`348`; `STR_METHODS`, `:291`). Outside it Lean raises at render time: other str methods (`join`, `format`, `isdigit`, `count`, `find`, `zfill`, `rsplit`, `splitlines`, `partition`, `removeprefix`, …), list methods (`index`, `count`), int/float attributes, `dict.copy`, `%` string formatting (`:668`), `tuple * int`, `list * bool`, `timedelta // bool`. Where Python has no such attribute Jinja returns Undefined (`'abc'.foo is defined` is False); Lean raises there too, and for every `_name` (`:300`; Jinja: Undefined, or the dict key).

Other hand-written cases: `val_bool_mul_list`, `val_tuple_mul`, `val_str_percent_format`, `val_str_percent_single`, `val_dict_copy`, `val_dict_items_key`, `val_list_method_index`, `val_list_method_count`, `val_list_attr_undefined`, `val_list_str_subscript`, `val_str_attr_undefined`, `val_int_attr_undefined`, `val_int_dot_attr_lex`, `val_int_real_attr`, `val_int_method_bit_length`, `val_float_is_integer`, `val_private_attr`, `val_private_attr_dict`, `val_str_method_format`, `val_str_method_isdigit`, `val_str_method_count`, `val_str_method_find`, `val_str_method_zfill`, `val_str_method_rsplit`, `val_str_method_splitlines`, `val_str_method_partition`, `val_str_method_removeprefix`, `val_str_method_swapcase`, `val_str_method_center`, `val_str_lower_no_call`, `flt_map_attribute_on_str`, `flt_map_attribute_on_list`, `flt_selectattr_on_strs`, `tst_divisibleby_str_format`, `st_all_private_attr`, `st_domain_private_attr`, `td_attr_unknown`, `td_floordiv_bool`.

### TPL-41: argument forms not modelled

Kind: Refuses (at render). Cases: 15 hand-written, 18 + 14 random.

```
case:     flt_int_base16
template: {{ '1A' | int(base=16) }}
HA:       {"ok": true, "type": "int", "repr": "26"}
HALean:   {"error": "int() with a base other than 10 is not supported by HALean", "ok": false}
```

Argument forms that raise at render time: `int(base=…)` (`Render.lean:869`), `round` with a float precision (`:897`), `join(attribute=)` (`:1622`), `sum(attribute=)` (`:1637`), `last` on a dict (`:1618`), `dict(...)` / `namespace(...)` with positional arguments (`:1493`, `:1356`), `states(x, rounded=…, with_unit=…)` and `state_with_unit` (`:1313`, `:249`), `**` with an exponent above 100000 (`:687`) or a complex result (`:705`), slicing or indexing a range, `map(attribute=…)` over datetimes.

Other hand-written cases: `val_pow_complex`, `val_pow_large_exp`, `val_dict_global_positional`, `val_dict_global_pairs`, `ns_positional_dict`, `flt_round_precision_float_default`, `flt_int_base_pos`, `flt_last_dict`, `flt_join_attribute`, `flt_sum_attribute`, `st_rounded_kw`, `st_with_unit_kw`, `st_state_with_unit`, `dt_sort_datetimes`.

### TPL-42: datetime methods and strftime directives not modelled

Kind: Refuses (at render). Cases: 24 hand-written, 4 + 1 random.

```
case:     dt_attr_date
template: {{ now().date() }}
HA:       {"ok": true, "type": "str", "repr": "'2026-11-20'"}
HALean:   {"error": "datetime.date is not supported by HALean", "ok": false}
```

`datetime` exposes seven fields and six methods (`Render.lean:326`-`338`); `date()`, `time()`, `isocalendar()`, `astimezone()`, `utcoffset()`, `fold` and unknown attributes raise. `isoformat(timespec=…)`, `replace(tzinfo=…)`, `replace` with a bool or positional argument raise (`:1444`-`1473`). `strftime` (`Time.lean:138`) lacks `%c %x %X %G %V %U %W %C %g %k %l %P %r`, flags other than `-`, and widths. `.timestamp()` / `as_timestamp` of a naive datetime raise (`Render.lean:578`).

Other hand-written cases: `dt_as_timestamp_naive`, `dt_strftime_c`, `dt_strftime_x`, `dt_strftime_G_V`, `dt_strftime_U_W`, `dt_strftime_s`, `dt_strftime_k_l_P`, `dt_strftime_r`, `dt_strftime_underscore_flag`, `dt_strftime_caret_flag`, `dt_strftime_width`, `dt_strftime_colon_z`, `dt_attr_time`, `dt_attr_isocalendar`, `dt_attr_astimezone`, `dt_attr_utcoffset`, `dt_attr_fold`, `dt_attr_unknown`, `dt_isoformat_timespec`, `dt_replace_tzinfo_none`, `dt_replace_bool`, `dt_replace_positional`, `dt_naive_timestamp`.

### TPL-43: date strings only ciso8601 parses

Kind: Refuses (at render). Cases: 7 hand-written, 1 + 0 random.

```
case:     dt_as_datetime_date_only
template: {{ as_datetime('2026-11-20') }}
HA:       {"ok": true, "type": "str", "repr": "'2026-11-20 00:00:00'"}
HALean:   {"error": "parsing '2026-11-20' as a date/time is not supported by HALean", "ok": false}
```

`parseDatetime` (`Render.lean:515`-`519`) raises for a string that starts with four digits and does not match `DATETIME_RE`. HA's `ciso8601` (`util/dt.py:232`) parses `2026-11-20`, `20261120T100000`, a lower-case `z`, a comma fraction; for other such strings HA returns None or the default (`dt_as_datetime_trailing_text`, `dt_as_timestamp_int_default`).

Other hand-written cases: `dt_as_datetime_compact`, `dt_as_datetime_lower_z`, `dt_as_datetime_comma_frac`, `dt_as_datetime_trailing_text`, `dt_as_timestamp_int_default`, `dt_as_timestamp_date_only_default`.

### TPL-44: printing objects

Kind: Refuses (at render). Cases: 6 hand-written, 50 + 53 random.

```
case:     val_print_state_object
template: {{ states.sensor.a }}
HA:       {"ok": true, "type": "str", "repr": "'<template TemplateState(<state sensor.a=1 @ 2026-11-20T08:30:45.123000-08:00>)>'"}
HALean:   {"error": "printing the state object of sensor.a is not supported by HALean", "ok": false}
```

`pyRepr` raises for state objects, `states`, `states.<domain>`, functions and for a datetime inside a container (`Value.lean:252`-`256`). HA prints `<template TemplateState(...)>`, `<template AllStates>`, `datetime.datetime(...)`. `reverse` of a generator is a list in Jinja and prints (`flt_reverse_generator_is_list`). The random generator produces many datetimes inside lists and dicts, hence the count.

Other hand-written cases: `val_print_function`, `val_print_states`, `val_print_domain`, `flt_reverse_generator_is_list`, `dt_in_list_repr`.

### TPL-45: HA gives Undefined/default, HALean raises

Kind: Refuses (at render). Cases: 5 hand-written, 3 + 2 random.

```
case:     und_first
template: {{ trigger.x | first is defined }}
HA:       {"ok": true, "type": "bool", "repr": "False"}
HALean:   {"error": "UndefinedError: 'dict object' has no attribute 'x' is undefined", "ok": false}
```

Places where HA returns Undefined or the default and Lean raises: `first` / `last` / `reverse` of Undefined (`Render.lean:1613`, `:1617`, `:1648`; Jinja iterates the empty Undefined), `as_datetime('nan')` (`:1404`; HA: None), `round(nan, 0, 'ceil', default)` (`:913`; HA: the default), slicing an int, float or dict (`:1247`; Jinja: Undefined).

Other hand-written cases: `und_last`, `und_reverse`, `flt_round_nan_ceil_default`, `dt_as_datetime_nan_string`.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives bool `False` (category `same`).

### TPL-46: documented render errors (non-ASCII case mapping)

Kind: Refuses (at render). Cases: 0 hand-written, 1 + 2 random.

```
case:     r101_2244
template: {{ time_since((as_datetime('2026-11-20T10:00:00+05:30') - (0.5 * timedelta(minutes=3600, hours=0.0000005, days=400))), 0) }}{{ ([{'a': 12, 'b': 'é'}, {'a': -1, 'b': 'unknown'}, {'a': 10, 'b': 'true'}] | sort(attribute='a,b') | list) }}
HA:       {"ok": true, "type": "str", "repr": "\"6 months 21 days 18 hours 45 seconds[{'a': -1, 'b': 'unknown'}, {'a': 10, 'b': 'true'}, {'a': 12, 'b': 'é'}]\""}
HALean:   {"error": "lower on non-ASCII text is not supported by HALean", "ok": false}
```

Case mapping of non-ASCII text is a render error (`asciiOnly`, `Render.lean:731`). Seen only in the random runs (strings `é`); the shipped cases mark it `expect_error_in_halean_only`.

### TPL-47: huge float exponent: time and memory

Kind: Refuses (time, memory, engine abort). Cases: 0 hand-written, 0 + 0 random.

```
case:     flt_float_exponent_1e8
template: {{ '1e100000000' | float }}
HA:       {"ok": true, "type": "str", "repr": "'inf'"}
HALean:   {"ok": true, "repr": "'inf'", "type": "str"}
```

`parseFloatStr` computes `m * 10 ^ exp` as an exact natural number before rounding (`Value.lean:189`). `{{ '1e100000000' | float }}` takes 2.9 s, `1e1000000000` 26.8 s, and `1e4000000000` aborts the engine process with `GNU MP: Cannot allocate memory` under a 6 GB limit (`logs/huge-exponent.log`). Python answers `inf` in microseconds. The same function reads float literals in templates, `_parse_result` input (`[1e4000000000]`) and state values passed to `float`. The hand-written case uses 1e8 and passes; the finding is the cost.

With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives str `'inf'` (category `same`).

### TPL-48: step budget of 1,000,000

Kind: Refuses (at render). Cases: 1 hand-written, 0 + 0 random.

```
case:     loop_step_budget_nested
template: {% for i in range(1500) %}{% for j in range(700) %}{% endfor %}{% endfor %}x
HA:       {"ok": true, "type": "str", "repr": "'x'"}
HALean:   {"error": "template exceeded HALean's step budget", "ok": false}
```

`tick` (`Render.lean:119`) stops a render after 1,000,000 loop iterations and calls (`MAX_STEPS`, `:102`). HA has no such limit: 1500 × 700 empty iterations render to `x`.

### Notes on the patches

* All 22 patch files were applied in one throwaway copy (`/tmp/claude-0/halean-copies/06-templates-1`, since deleted), in the
  order of `patches/ALL.patch`: TPL-1, 12, 9, 22, 36, 6, 34, 21, 7, 15, 20, 24, 29, 2, 47, 19, 30, 23, 31, 32, 45, 4.
  `halean-template`, `halean-automation` and `halean-script` were rebuilt there. Each `TPL-n.patch` is the diff of one
  commit on top of the previous ones; some need the earlier ones to apply (TPL-34 after TPL-6).
* Shipped tests in that copy: `tests/differential/test_templates.py` 361 passed
  (`patches/all-patches-shipped-test_templates.log`); the whole `tests/differential` directory 611 passed, 6 skipped
  (`patches/all-patches-shipped-differential.log`; same numbers as the unpatched run in
  `review/experiments/02-shipped-tests/logs/run1-differential.log`); `tests/run_scenarios.py` 60/60
  (`patches/all-patches-run_scenarios.log`); `tests/run_script_scenarios.py` 11/11
  (`patches/all-patches-run_script_scenarios.log`).
* Effect on the review cases (`patches/all-patches-before-after.log`): hand-written failing 316 → 228, seed 101
  185 → 99, seed 102 195 → 91, no case newly failing. The remaining failures of patched IDs are cases where the patch
  turns a wrong answer into a refusal (TPL-1 octal and `\N{}`, TPL-23) or where both sides now refuse and the case is
  not marked `unsupported` (TPL-30, TPL-31).
* The patches do not keep the proofs: `lake build` of the Template `*Spec` modules in the patched copy fails in
  `ValueSpec`, `RenderSpec2`, `RenderSpec3` (`patches/spec-build-with-all-patches.log`). The executables do not import
  these modules, so the shipped tests do not notice. Theorems that would have to be restated, because they state the
  behaviour the patch changes: `isState_collects`, `isState_missing`, `isState_true`, `isState_list`, `isState_nonstr`,
  `hasValue_collects`, `hasValue_iff`, `hasValue_nonstr`, `stateAttrFn_missing`, `stateAttrFn_nonstr`,
  `stateIfValid_some`, `stateIfValid_invalid` (RenderSpec3.lean:255-344; TPL-6, TPL-34), `containsV_list`,
  `containsV_dict` (RenderSpec3.lean:412-414; TPL-2), `pyStr_eq_pyRepr` (ValueSpec.lean:339; TPL-9),
  `pyRepr_ok_of_printable` (ValueSpec.lean:276; TPL-32), `parseResult_str` (RenderSpec2.lean:671; TPL-32).
  These theorems are true of the Lean functions; they say nothing about Python. `isState_nonstr` proves that
  `is_state(5, …)` is False, which is the opposite of what HA does (TPL-34).

## Reading findings without a reproducer

* **`State` values that are not `TemplateState`s.** `Value.state s false` (`Value.lean:34`: iterated states and
  `trigger.to_state`) and `Value.pyobj` (`Event`, `MultiDictProxy`, `Value.lean:55`) are built by the automation
  engine. The template harness passes variables as JSON, so `trigger.to_state` is a dict there. `stateEq`
  (`Value.lean:333`) compares `TemplateState` and `State` as equal; in HA `State.__eq__` requires the same class.
  Not drivable through `halean-template`.
* **`limited` and `strict` renders.** `Template.async_render(limited=…, strict=…)` (`helpers/template/__init__.py:435`)
  are not modelled (manifest note). `strict=True` replaces `LoggingUndefined` by `StrictUndefined`. The harness never
  passes either flag, and `check … allowTime=false` (`Render.lean:1878`, trigger templates) is not reachable from it.
* **Float floor division of finite operands.** `floatFloorDivMod` (`Render.lean:591`-`601`) rounds the exact
  quotient floor once. CPython computes `floor((vx - fmod(vx, wx)) / wx)` in doubles, with two roundings. I found no
  input where they differ (edge cases `val_floordiv_*`, and the `//` operator in both random runs), and I have no
  proof that there is none.
* **Identity shortcuts.** Python's container comparison and `in` treat an object as equal to itself (`x in [x]` with
  NaN). Lean compares by value (`Value.lean:338`). The natural reproducer (`{% set x = 'nan' | float %}{{ x in [x] }}`)
  hits TPL-38 in HA first.
* **Platform dependence.** `Float.pow` is the C library's `pow`, as in CPython; equal on this machine, not by
  construction. `as_timestamp` / `.timestamp()` of naive datetimes use the system time zone in HA; Lean refuses.
* **`RenderInfo` fields the harness does not compare.** `has_time`, `exception`, `rate_limit`, `filter`,
  `filter_lifecycle` (`Render.lean:45`-`77`) are computed but never compared by `test_templates.py`. For example
  `relative_time` sets `hasTime` in Lean (`Render.lean:1142`) even for a non-datetime argument, as HA does
  (`extensions/datetime.py:273`); only reading confirms it.
* **Jinja `LoggingUndefined` logging.** HA logs a warning for each use of an Undefined; no log is modelled or compared.

## Notes on the harness

What `tests/differential/test_templates.py` cannot observe, or observes in a way that hides differences:

1. **HA exceptions other than `TemplateError` / `HomeAssistantError` crash the test.** HA raises a bare Python
   exception when the failure is in the compile step: `SyntaxError` for `{% break %}` outside a loop, `ValueError`
   for `{{ 10 ** 5000 }}`. Such cases cannot be written in the shipped format (`gen/batch_only.yaml` holds the four I
   found; `harness/test_batch.py` records them as `ha_crash`).
2. **`unsupported: true` skips HA.** The test returns before HA renders, so a case marked `unsupported` never checks
   that HA would refuse too. Any valid template can be made to "pass" by marking it. Conversely, a template that
   both sides refuse (HA at render, HALean at load) can only pass if it is marked `unsupported`.
3. **When HA raises, any HALean error passes**, whatever the reason; `expect_error_in_halean_only` also accepts any
   error text. A render error caused by an unimplemented feature is indistinguishable from the right error.
4. **The clock is sent in milliseconds** (`"now": _us(dt_util.utcnow()) // 1000`), and as one UTC offset (`"tz"`).
   A `now:` with microseconds below a millisecond would differ in the harness, not in the engine. All zone-database
   behaviour is outside what the driver can be given (TPL-25).
5. **Variables and attributes travel as JSON.** Key order is lost (TPL-27) and floats that Python prints with an
   exponent arrive as ints (TPL-26); `State`, `Event` and datetime objects cannot be passed as variables.
6. **`render_info` is compared first and only on request.** A case with `render_info: true` fails on the info
   difference before the results are compared, so the assertion message can hide a result difference. `has_time`,
   `exception` and the rate limit are not compared.
7. **Results are compared by `repr`.** HALean's driver prints `pyRepr`, HA's side Python's `repr`. A value that is
   equal but whose Lean `repr` is wrong fails (TPL-8, case `val_repr_nbsp_result`: a list holding U+00A0). The
   failure is about `strRepr`, not about the rendered value.
8. **One fresh `hass` per case, compiled after the states are set.** Jinja's compile-time folding (TPL-38) therefore
   always sees the final states; a second render after a state change, where HA would return the stale folded value,
   is never made.
9. **No timeout on the engine.** A template on which `halean-template` does not answer (TPL-47) blocks the suite.
   `harness/test_batch.py` adds a 20 s timeout and restarts the engine.
10. **The shipped cases combine several expressions per template** (for example five `as_datetime` calls in one
    case). One wrong sub-result fails the case, but a sub-expression that raises hides all the others.
