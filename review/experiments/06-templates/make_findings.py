#!/usr/bin/env python3
"""Assemble FINDINGS.md from the logs (counts, reproducer outputs) and the per-ID notes below.
usage: python3 make_findings.py > FINDINGS.md"""
import json
import re
import sys

sys.path.insert(0, ".")
import classify  # noqa: E402

README = open("/home/user/halean/README.md").read().split("\n")


def load(p):
    return [json.loads(line) for line in open(p)]


hand = load("logs/run1-hand-batch.jsonl")
hand2 = load("logs/run2-hand-batch.jsonl")
rnd = {s: load(f"logs/run1-random-seed{s}.jsonl") for s in (101, 102)}
rnd2 = {s: load(f"logs/run2-random-seed{s}.jsonl") for s in (101, 102)}
after = {r["name"]: r for f in ("hand-batch", "random-seed101", "random-seed102") for r in load(f"patches/all-patches-{f}.jsonl")}
byname = {r["name"]: r for r in hand}
case_file = {}
for f in sorted(__import__("glob").glob("cases/*.yaml")) + ["gen/batch_only.yaml"]:
    for m in re.finditer(r"^- \{?name: (\w+)", open(f).read(), re.M):
        case_file[m.group(1)] = f


def fails(recs):
    return [r for r in recs if r["verdict"] == "fail"]


def per_id(recs):
    out = {}
    for r in fails(recs):
        out.setdefault(classify.classify(r), []).append(r)
    return out


H, R1, R2 = per_id(hand), per_id(rnd[101]), per_id(rnd[102])
assert None not in H and None not in R1 and None not in R2, "unclassified cases"
# rule 5: every failing case fails in both runs
for a, b in ((hand, hand2), (rnd[101], rnd2[101]), (rnd[102], rnd2[102])):
    assert [(r["name"], r["verdict"], r["cat"]) for r in a] == [(r["name"], r["verdict"], r["cat"]) for r in b]


def res(d):
    if "unsupported" in d:
        return "`unsupported`: " + d["unsupported"]
    if d.get("ok"):
        r = d["repr"]
        return f"{d['type']} `{r if len(r) < 150 else r[:70] + ' … ' + r[-40:]}`"
    return "error: " + d["error"][:160]


def rl(a, b):
    return " ".join(x.strip() for x in README[a - 1:b])


DOC_TZ = f"yes (README 662-665: \"{rl(662, 665)}\")"
DOC_KEYS = f"yes (README 653-656: \"{rl(653, 656)}\")"
SHIPPED = ("shipped tests pass with all patches applied: `patches/all-patches-shipped-test_templates.log` (361 passed), "
           "`patches/all-patches-shipped-differential.log` (611 passed, 6 skipped), `patches/all-patches-run_scenarios.log` (60/60), "
           "`patches/all-patches-run_script_scenarios.log` (11/11)")

# ID: (reproducer, kind, README lists it?, patch, root cause)
META = {
 "TPL-1": ("syn_str_octal_escape", "Silent", "no", "`patches/TPL-1.patch` (partial: `\\u`, `\\U` decoded; `\\1`-`\\7` and `\\N{}` refused; `\\0dd` unchanged)",
  "Jinja decodes string literals with the `unicode-escape` codec (`jinja2/lexer.py:654`); `ast.literal_eval` uses Python's literal rules. `unescape` (`HALean/Template/Syntax.lean:93`) knows `\\n \\t \\r \\0 \\\\ \\' \\\" \\a \\b \\f \\v \\xHH` and keeps every other escape as written. The same function serves `literalEval` (`Render.lean:2004`). Other cases: `syn_str_u_escape`, `syn_str_bigu_escape`, `syn_str_name_escape`, `syn_str_octal_escape_012`, `pr_str_*_escape_in_list`."),
 "TPL-2": ("val_dict_dup_keys", "Silent / Accepts", "no", "`patches/TPL-2.patch`",
  "A dict is an association list (`Value.lean:29`). The dict display keeps every pair (`Render.lean:1226`), so equal keys (`'a'`/`'a'`, `1`/`1.0`/`True`) are not merged, and no key is hashed: `{[1]: 2}` and `[1] in {'a': 1}` (`containsV`, `Render.lean:454`) give a value where Python raises `TypeError`. `literalEval` does the same (`Render.lean:2056`-`2078`): `{1: 2, 1: 3}` and `{[1]: 2}` (HA returns the string). Jinja builds a real dict (`jinja2/compiler.py:1702`)."),
 "TPL-3": ("val_dict_keys_print", "Silent", "no", "none (needs a view value)",
  "`dict.keys` / `values` / `items` return lists (`Render.lean:1495`-`1497`). In Python they are views: they print as `dict_keys([...])`, are not equal to a list and cannot be indexed (`val_dict_keys_eq_list`, `val_dict_keys_index`)."),
 "TPL-4": ("val_truthy_domain_empty", "Silent (value and RenderInfo)", "no", "`patches/TPL-4.patch`",
  "`truthy` (`Value.lean:281`) is true for `states` and `states.<domain>`. In HA `bool()` calls `DomainStates.__len__` / `AllStates.__len__` (`helpers/template/states.py:142`, `:243` ff.), which returns the number of states and records `domains_lifecycle` / `all_states_lifecycle`. Affected: `if`, `not`, `and`, `or`, `iif`, `default(x, true)`. Jinja's `sync_do_map` (`jinja2/filters.py:1437`) and `select_or_reject` (`:1786`) start with `if value:`: over a states object that records the lifecycle listener (and for an empty domain nothing else), and a falsy non-iterable input (`none`, `false`, `timedelta(0)`) gives an empty result where Lean raises `not iterable` (`Render.lean:1651`, `1663`, `1672`). Most random cases are of the lifecycle kind: the result is equal, `domains_lifecycle` / `all_states_lifecycle` differ."),
 "TPL-5": ("st_domain_last", "Silent / Accepts", "no", "none",
  "`last` and `reverse` call `reversed(value)` (`jinja2/filters.py:674`, `:1386`). `DomainStates` and `AllStates` have `__len__` and `__getitem__` but no `__reversed__`, so Python uses the sequence protocol: `states.sensor[1]` is `states.sensor.1`, the (missing) entity `sensor.1`, i.e. `None`; for `states` it raises. Lean iterates the states backwards (`Render.lean:1615`, `:1645`). HA's result here is of no use to a template author; the difference is still a different value."),
 "TPL-6": ("st_case_insensitive_call", "Silent (value and RenderInfo)", "no (manifest.yaml, `StateMachine.get`: \"lower-case retry; only expand uses it so far\")", "`patches/TPL-6.patch`",
  "`hass.states.get` retries with `entity_id.lower()` (`core.py:2286`). `states()`, `is_state`, `state_attr`, `is_state_attr`, `has_value`, `states['X.y']` all go through it (`helpers/template/states.py:515`, `:522`). Lean looks up the id as written (`Render.lean:282`, `:833`, `:844`, `:852`, `:1317`, `:1333`); only `expand` uses `hassStatesGet` (`Render.lean:1061`). HA also records the id of the state it found (`sensor.temp`), Lean the id as written."),
 "TPL-7": ("flt_sum_float_compensated", "Silent", "no", "`patches/TPL-7.patch`",
  "The `sum` filter is Python's `sum` (`jinja2/filters.py:1340`). Since Python 3.12 `sum` adds floats with Neumaier's compensated summation (CPython `Python/bltinmodule.c`, `builtin_sum_impl`). Lean adds left to right with `arith \"+\"` (`Render.lean:1636`-`1640`)."),
 "TPL-8": ("val_repr_nbsp", "Silent", "no for templates (README 349 lists it for the service registry: \"`repr()` of strings with non-printable non-ASCII characters (Python escapes them, HALean does not)\")", "none (needs Unicode's printable table)",
  "`strRepr` (`Value.lean:215`) escapes only characters below U+0020 and U+007F. Python's `repr` escapes every non-printable character (`\\xa0`, `\\x85`, `\\xad`, `\\u2028`, `\\u200b`, `\\ue000`). Visible through `| string`, `~`, and in the `repr` the driver prints."),
 "TPL-9": ("val_print_undefined_in_list", "Silent", "no", "`patches/TPL-9.patch`",
  "`pyRepr (.undef _)` is `\"\"` (`Value.lean:241`). `repr(Undefined)` is `Undefined` (`jinja2/runtime.py:796` ff.). `{{ [trigger.x] }}` is the string `[Undefined]` in HA and the empty list in Lean (after `_parse_result`)."),
 "TPL-10": ("val_print_namespace", "Silent", "no", "none (the fields live in the render heap, `pyRepr` cannot see them)",
  "`pyRepr (.ns _)` is `<Namespace>` (`Value.lean:251`); Jinja prints `<Namespace {...}>` (`jinja2/utils.py:745` ff.)."),
 "TPL-11": ("val_print_loop", "Silent / Refuses / Accepts", "no (README 246 lists `loop.*` as supported)", "none",
  "`loop` is a dict with nine keys (`Render.lean:1800`-`1806`); Jinja's is a `LoopContext` (`jinja2/runtime.py:394`). Differences: printing (`<LoopContext 1/2>`), `loop is mapping` (False in HA), `loop | length` (the loop length in HA), iterating `loop`, `loop.depth` / `depth0` (Undefined in Lean), `loop.cycle()` / `loop.changed()` (render error in Lean), `{% set loop = 5 %}` inside a loop (TemplateAssertionError in HA)."),
 "TPL-12": ("loop_break_then_else", "Silent", "no", "`patches/TPL-12.patch`",
  "Jinja compiles `for … else` with a flag that is cleared at the end of the loop body (`jinja2/compiler.py:1252` and the `{iteration_indicator} = 0` line of `visit_For`). `break` and `continue` skip that line, so the `else` block runs unless some iteration reached the end of the body. Lean runs it only when there was no item (`Render.lean:1810`)."),
 "TPL-13": ("flt_generator_reused_sum", "Silent", "no", "none (needs one-shot iterators in the render state)",
  "`map`, `select`, `reject`, `selectattr`, `rejectattr`, `unique`, `reverse` return one-shot iterators in Jinja. Lean stores the items (`Value.gen`, `Value.lean:52`); using the value twice gives the items twice."),
 "TPL-14": ("flt_map_lazy_first", "Refuses / RenderInfo", "no", "none (same as TPL-13)",
  "The same lists are computed eagerly (`Render.lean:1650`-`1681`). Jinja's generators stop when the consumer stops: `[1, 'x'] | map('int') | first` never converts `'x'`, and `['sensor.a', 'sensor.b'] | map('states') | first` reads only `sensor.a` (case `flt_map_lazy_states_info`: Lean records both entities)."),
 "TPL-15": ("tst_iterable_range", "Silent", "no", "`patches/TPL-15.patch`",
  "`applyTest` (`Render.lean:1712`-`1713`): `sequence` is true for list, tuple, str, dict; `iterable` adds Undefined. Jinja (`jinja2/tests.py:167`, `:193`): `sequence` needs `len()` and `__getitem__` (true for range, `states`, `states.<domain>`, Undefined); `iterable` needs `iter()` (true for range, generators, `states`, `states.<domain>`)."),
 "TPL-16": ("flt_float_vt_ws", "Silent", "no", "none (a patch breaks theorem `toFloat?`-`parseFloatStr` at `RenderSpec3.lean:148`; not attempted)",
  "`parseFloatStr` (`Value.lean:154`) trims with Lean's `String.trim` (space, `\\t`, `\\n`, `\\r`) and reads ASCII digits. Python's `float()` strips every `str.isspace` character (`\\v`, `\\f`, `\\x1c`-`\\x1f`, U+00A0, …) and reads every Unicode decimal digit. `float`, `is_number`, `round`, `as_datetime` share it. `int` refuses non-ASCII text instead (`Render.lean:214`)."),
 "TPL-17": ("pr_fullwidth_int", "Silent", "no", "none (needs Unicode's decimal-digit table)",
  "`_IS_NUMERIC` is `^[+-]?(?!0\\d)\\d*(?:\\.\\d*)?$` on a str (`helpers/template/__init__.py:102`): `\\d` matches all Unicode decimal digits, and `int()` / `float()` read them. `isNumericStr` (`Render.lean:1900`) uses `Char.isDigit`."),
 "TPL-18": ("pr_static_nbsp_strip", "Silent", "no", "none (a patch breaks the theorem at `RenderSpec2.lean:750`, which states `render … = .str raw.trim`)",
  "`Template.__init__` strips with `str.strip()` (`helpers/template/__init__.py:359`). `compile` uses `raw.trim` (`Syntax.lean:622`), which strips four ASCII characters. Only static templates are affected; rendered output is stripped with `pyStrip` (`Render.lean:2155`)."),
 "TPL-19": ("flt_title_vt", "Silent", "no", "`patches/TPL-19.patch`",
  "`do_title` splits on `[-\\s({\\[<]+` (`jinja2/filters.py:331`, `_word_beginning_split_re`); Lean tests `Char.isWhitespace` (`Render.lean:1587`), so `\\v`, `\\f`, `\\x1c`-`\\x1f` do not start a word."),
 "TPL-20": ("val_str_split_none_maxsplit", "Silent", "no", "`patches/TPL-20.patch`",
  "`pySplit` with `sep=None` and a `maxsplit` strips the remainder on the right (`Render.lean:780`); Python keeps its trailing whitespace."),
 "TPL-21": ("val_floordiv_neg_by_inf", "Silent", "no", "`patches/TPL-21.patch`",
  "`floatFloorDivMod` (`Render.lean:589`-`590`) uses `floor(a / b)` and `a - b * floor(a / b)` when an operand is not finite. CPython's `float_divmod` uses `fmod` and a sign fix-up: `5 % inf = 5.0`, `-5 % inf = inf`, `-5 // inf = -1.0`, `inf // 2 = nan`."),
 "TPL-22": ("dt_timestamp_custom_default_format", "Silent", "no", "`patches/TPL-22.patch`",
  "`timestamp_custom`'s default `date_format` is `DATE_STR_FORMAT = \"%Y-%m-%d %H:%M:%S\"` (`helpers/template/extensions/datetime.py:16`, `:139`). Lean uses `\"%Y-%m-%d\"` (`Render.lean:1437`)."),
 "TPL-23": ("dt_as_datetime_hour_24", "Silent", "no", "`patches/TPL-23.patch` (turns it into a render error, like the other ciso8601-only forms)",
  "`parse_datetime` tries `ciso8601` first (`util/dt.py:232`), which reads `24:00:00` as midnight of the next day. Lean's regex path builds `hour=24`, fails the range check and returns `none` (`Render.lean:567`), so `as_datetime` returns `None`."),
 "TPL-24": ("dt_strftime_small_year", "Silent", "no", "`patches/TPL-24.patch`",
  "`%Y` and `%F` print the year without padding (`Time.lean:169`, `:175`). Python 3.14 pads `%Y` (and the year of `%F`) to four digits."),
 "TPL-25": ("dt_as_local_summer", "Silent", DOC_TZ, "none (needs a zone database)",
  "A datetime carries a fixed offset and the engine knows only the current one (`asLocal`, `Render.lean:504`; `today_at`, `:1362`). Consequences seen: `as_local`, `timestamp_local`, `timestamp_custom` of an instant on the other side of a DST change; `now() ± timedelta` and `.replace(month=…)` across a change (Python keeps the zone and the wall time, the offset changes); `today_at()` on the day of a change; subtraction of two datetimes of the same zone (Python subtracts wall clocks, Lean instants: `dt_same_zone_wall_subtraction` differs by 3600 s); dates before 1883 (local mean time)."),
 "TPL-26": ("val_var_float_exp", "Silent", "no (README 692-693 covers only floats sent on by HALean)", "none (Lean's `Json` has already dropped the distinction)",
  "`Value.ofJson` (`Value.lean:422`-`424`) makes an int of every JSON number whose `exponent` field is 0. Lean's JSON parser reads `1e+20` as mantissa 10^20, exponent 0, so a float that Python prints with an exponent (1e16 and above) arrives as an int. Applies to variables and to state attributes (`st_attr_float_exp`)."),
 "TPL-27": ("st_attr_order", "Order", DOC_KEYS, "none",
  "Attributes and variables are decoded from Lean JSON objects, which are sorted by key (`Value.lean:427`). Printing or iterating them gives sorted keys."),
 "TPL-28": ("pr_ellipsis_rendered", "Silent / Refuses", "no (manifest.yaml, `_cached_parse_result`: \"sets become lists, bytes stay strings\")", "none (needs set, bytes and Ellipsis values)",
  "`ast.literal_eval` returns any Python constant. HA returns it unless it is a str, a complex or a non-numeric-looking number (`helpers/template/__init__.py:268`-`299`). Lean's `literalEval` (`Render.lean:2116`): a set display becomes a list (`:2073`), `set()` and bytes stay strings, `...` stays a string (HA returns `Ellipsis`: a template that prints three dots renders to the `Ellipsis` object), and a container holding a complex is a render error (`pr_complex_in_list`)."),
 "TPL-29": ("pr_nested_unary_in_list", "Silent", "no", "`patches/TPL-29.patch`",
  "`litParse` accepts nested unary signs (`Render.lean:2022`-`2029`, comment: \"literal_eval allows nested unary on numbers\"). CPython's `ast.literal_eval` (`_convert_signed_num`) allows one sign on a number; `[--4]` is a `ValueError` and HA returns the string."),
 "TPL-30": ("syn_int_leading_zero", "Accepts", "no", "`patches/TPL-30.patch`",
  "`lexBlock` (`Syntax.lean:142`-`170`) starts a number at `.5` and reads `007` as 7. Jinja's `float_re` needs a digit before the point and `integer_re` is `[1-9](_?\\d)*|0(_?0)*` (`jinja2/lexer.py:32`, `:48`): both are `TemplateSyntaxError`."),
 "TPL-31": ("syn_if_cond_expr_in_test", "Accepts", "no", "`patches/TPL-31.patch` (partial: `if` tests and constant targets; not `loop` targets, not `break` outside a loop)",
  "`parseStmt` parses `if`/`elif` tests with `parseTuple` (`Syntax.lean:512`), which allows `a if b else c`; Jinja uses `parse_tuple(with_condexpr=False)` (`jinja2/parser.py:255`). `parseTargets` (`Syntax.lean:505`) accepts `none`/`true`/`false` (Jinja: \"can't assign to 'const'\", `parser.py:507`) and `loop` inside a loop. `{% break %}` / `{% continue %}` outside a loop render in Lean; HA's compile raises a Python `SyntaxError` that is not a `TemplateError` (cases in `gen/batch_only.yaml`)."),
 "TPL-32": ("val_int_div_overflow", "Accepts", "no", "`patches/TPL-32.patch` (not the timedelta range)",
  "Lean's ints convert to `inf` and float results overflow to `inf` silently: `int / int` (`Render.lean:676`), mixed arithmetic (`:692`), `int ** negative` (`:690`), `float ** float` (`:706`), `round(x, 400)` (`:907`). Python raises `OverflowError`. `str(int)` and `int(str)` above 4300 digits raise `ValueError` in Python (`Value.lean:243`, `Render.lean:2138`): `{{ 10 ** 5000 }}` fails at compile time in HA with a bare `ValueError` (batch-only case `val_int_print_over_limit`), and a static template of 4400 digits stays a string in HA (`pr_static_4400_digits`, Silent). `timedelta` arithmetic does not check the 999999999-day range (`td_overflow_mul`)."),
 "TPL-33": ("flt_arity_upper", "Accepts (one Silent)", "no", "none (every filter, test and method needs its signature)",
  "Arguments are read by position or name with defaults (`Args.get`, `Render.lean:814`); only some functions call `Args.check` (`:819`). Extra positional arguments, unknown keywords, duplicate values and missing required arguments are accepted for most filters (`upper`, `length`, `first`, `abs`, `string`, `list`, `trim`, `float`, `round`, `default`), tests (`eq` without an argument, `none(2)`, `defined(1)`), functions (`is_state('x')`, `state_attr('x')`, `has_value()`, `is_number()`, `iif()`) and methods (`dict.get(default=…)`, `isoformat('ab')`). `'abc'.startswith('b', 1)` ignores the start index and returns False (HA: True)."),
 "TPL-34": ("st_nonstr_is_state", "Accepts", "no", "`patches/TPL-34.patch`",
  "`isState`, `stateAttrFn`, `hasValue` and `is_state_attr` return False / None for an id that is not a string (`Render.lean:831`, `:841`, `:855`, `:1330`). HA calls `hass.states.get(entity_id)`, which fails on `entity_id.lower()` (`core.py:2286`); an Undefined raises `UndefinedError`. Theorems `isState_nonstr`, `hasValue_nonstr`, `stateAttrFn_nonstr` (`RenderSpec3.lean:287`, `:316`, `:331`) state the Lean behaviour."),
 "TPL-35": ("flt_sum_strings_start", "Accepts", "no", "`patches/TPL-7.patch`",
  "Python's `sum` refuses a str start value (`TypeError: sum() can't sum strings`); Lean concatenates (`Render.lean:1638`)."),
 "TPL-36": ("dt_timestamp_utc_as_global", "Accepts", "no", "`patches/TPL-36.patch`",
  "`GLOBALS` (`Render.lean:127`-`133`) lists `timestamp_local`, `timestamp_utc`, `timestamp_custom`. HA registers them as filters only (`helpers/template/extensions/datetime.py`, `as_filter=True` without `as_global`): as functions they are undefined (`logs/names.log`)."),
 "TPL-37": ("dt_timestamp_utc_1e20_default", "Accepts", "no", "none",
  "`timestamp_*` and `as_datetime` catch `ValueError` and `TypeError` only (`helpers/template/extensions/datetime.py:139`-`212`). `fromtimestamp` raises `OverflowError` / `OSError` for values outside the platform range, and `float(Undefined)` raises `UndefinedError`; HA lets these through. `utcFromTimestamp` returns `none` for all failures (`Render.lean:495`), so Lean returns the default."),
 "TPL-38": ("st_states_filter_info", "RenderInfo / Accepts", "no", "none (HA behaviour comes from Jinja's optimizer)",
  "Jinja folds constant expressions when it compiles (`jinja2/optimizer.py:27`, `nodes.py:472` `as_const`). A filter without a context decorator applied to a constant is evaluated once, at compile time: `'sensor.a' | states` is baked into the compiled template and records no entity (case `st_states_filter_info`; with a variable, `st_nonconst_states_filter_info`, both sides agree). `'nan' | float` folded into a `set` or an operation is written into the generated code as `nan`, a `NameError` at render (`val_const_fold_nan_set`). Lean evaluates everything at render time."),
 "TPL-39": ("syn_int_hex", "Refuses (at load)", "no (README 246 lists as rejected: \"any other global, filter or test, macros, `include`, `raw`\")", "`patches/TPL-30.patch` fixes `0x`/`0o`/`0b` literals and `x.0`; nothing for the rest",
  "Valid Jinja that `compile` rejects: radix integers and `seq.0` item access (`Syntax.lean:142`: `.0` after a name is lexed as a float), `+%}` (`:210`), `\\v`/`\\f` between tokens (`:136`), non-ASCII identifiers (`:89`), parenthesised or nested assignment targets (`:505`), `recursive` (`:531`), block `set` (`:538`), `*args` (`:406`), `x[]`. HALean answers `unsupported`, so nothing wrong is computed."),
 "TPL-40": ("val_str_method_join", "Refuses (at render)", "no (README 246: \"str methods `split`, `strip`, `replace`, `startswith`, ...\")", "none",
  "Attribute access is a closed list per type (`getattrV`, `Render.lean:299`-`348`; `STR_METHODS`, `:291`). Outside it Lean raises at render time: other str methods (`join`, `format`, `isdigit`, `count`, `find`, `zfill`, `rsplit`, `splitlines`, `partition`, `removeprefix`, …), list methods (`index`, `count`), int/float attributes, `dict.copy`, `%` string formatting (`:668`), `tuple * int`, `list * bool`, `timedelta // bool`. Where Python has no such attribute Jinja returns Undefined (`'abc'.foo is defined` is False); Lean raises there too, and for every `_name` (`:300`; Jinja: Undefined, or the dict key)."),
 "TPL-41": ("flt_int_base16", "Refuses (at render)", "no (manifest.yaml notes `base` and `rounded/with_unit`)", "none",
  "Argument forms that raise at render time: `int(base=…)` (`Render.lean:869`), `round` with a float precision (`:897`), `join(attribute=)` (`:1622`), `sum(attribute=)` (`:1637`), `last` on a dict (`:1618`), `dict(...)` / `namespace(...)` with positional arguments (`:1493`, `:1356`), `states(x, rounded=…, with_unit=…)` and `state_with_unit` (`:1313`, `:249`), `**` with an exponent above 100000 (`:687`) or a complex result (`:705`), slicing or indexing a range, `map(attribute=…)` over datetimes."),
 "TPL-42": ("dt_attr_date", "Refuses (at render)", "partly (README 248-249 names `tzinfo` and `strftime('%Z')` only)", "none",
  "`datetime` exposes seven fields and six methods (`Render.lean:326`-`338`); `date()`, `time()`, `isocalendar()`, `astimezone()`, `utcoffset()`, `fold` and unknown attributes raise. `isoformat(timespec=…)`, `replace(tzinfo=…)`, `replace` with a bool or positional argument raise (`:1444`-`1473`). `strftime` (`Time.lean:138`) lacks `%c %x %X %G %V %U %W %C %g %k %l %P %r`, flags other than `-`, and widths. `.timestamp()` / `as_timestamp` of a naive datetime raise (`Render.lean:578`)."),
 "TPL-43": ("dt_as_datetime_date_only", "Refuses (at render)", "no (manifest.yaml, `parse_datetime`: \"strings only ciso8601 would accept are errors\")", "none",
  "`parseDatetime` (`Render.lean:515`-`519`) raises for a string that starts with four digits and does not match `DATETIME_RE`. HA's `ciso8601` (`util/dt.py:232`) parses `2026-11-20`, `20261120T100000`, a lower-case `z`, a comma fraction; for other such strings HA returns None or the default (`dt_as_datetime_trailing_text`, `dt_as_timestamp_int_default`)."),
 "TPL-44": ("val_print_state_object", "Refuses (at render)", "partly (README 250-251 names generators only)", "none",
  "`pyRepr` raises for state objects, `states`, `states.<domain>`, functions and for a datetime inside a container (`Value.lean:252`-`256`). HA prints `<template TemplateState(...)>`, `<template AllStates>`, `datetime.datetime(...)`. `reverse` of a generator is a list in Jinja and prints (`flt_reverse_generator_is_list`). The random generator produces many datetimes inside lists and dicts, hence the count."),
 "TPL-45": ("und_first", "Refuses (at render)", "no", "`patches/TPL-45.patch` (first/last/reverse of Undefined, `as_datetime('nan')`)",
  "Places where HA returns Undefined or the default and Lean raises: `first` / `last` / `reverse` of Undefined (`Render.lean:1613`, `:1617`, `:1648`; Jinja iterates the empty Undefined), `as_datetime('nan')` (`:1404`; HA: None), `round(nan, 0, 'ceil', default)` (`:913`; HA: the default), slicing an int, float or dict (`:1247`; Jinja: Undefined)."),
 "TPL-46": ("-", "Refuses (at render)", f"yes (README 252-254: \"{rl(252, 254)}\")", "none",
  "Case mapping of non-ASCII text is a render error (`asciiOnly`, `Render.lean:731`). Seen only in the random runs (strings `é`); the shipped cases mark it `expect_error_in_halean_only`."),
 "TPL-47": ("flt_float_exponent_1e8", "Refuses (time, memory, engine abort)", "no", "`patches/TPL-47.patch` (log: `patches/TPL-47-huge-exponent.log`)",
  "`parseFloatStr` computes `m * 10 ^ exp` as an exact natural number before rounding (`Value.lean:189`). `{{ '1e100000000' | float }}` takes 2.9 s, `1e1000000000` 26.8 s, and `1e4000000000` aborts the engine process with `GNU MP: Cannot allocate memory` under a 6 GB limit (`logs/huge-exponent.log`). Python answers `inf` in microseconds. The same function reads float literals in templates, `_parse_result` input (`[1e4000000000]`) and state values passed to `float`. The hand-written case uses 1e8 and passes; the finding is the cost."),
 "TPL-48": ("loop_step_budget_nested", "Refuses (at render)", "no (README 695-696 mentions `STEP_FUEL` for scripts only)", "none",
  "`tick` (`Render.lean:119`) stops a render after 1,000,000 loop iterations and calls (`MAX_STEPS`, `:102`). HA has no such limit: 1500 × 700 empty iterations render to `x`."),
}

ids = sorted(set(H) | set(R1) | set(R2) | set(META), key=lambda x: int(x.split("-")[1]))
out = []
w = out.append
n_hand_yaml = sum(1 for n, f in case_file.items() if f.startswith("cases/"))
pyt1 = open("logs/run1-hand-pytest.log").read().strip().split("\n")[-1]
pyt2 = open("logs/run2-hand-pytest.log").read().strip().split("\n")[-1]
div_total = len(fails(hand)) + len(fails(rnd[101])) + len(fails(rnd[102]))

w("# FINDINGS: templates (`HALean/Template/`)\n")
w("Reviewed commit `f638a3779195a42a5162939aa67981b9b501618e`, against Home Assistant 2026.10.4, Jinja2 3.1.6, CPython 3.14.\n")
w("## Counts\n")
w(f"* New hand-written cases: {n_hand_yaml} in `cases/*.yaml` (run by the harness copy: `logs/run1-hand-pytest.log`, last line `{pyt1}`; `logs/run2-hand-pytest.log`, `{pyt2}`), plus {len(hand) - n_hand_yaml} batch-only cases in `gen/batch_only.yaml` on which HA raises an exception that is not a `TemplateError` ({len(hand)} cases in `logs/run1-hand-batch.jsonl`).")
w(f"* Random cases per run: {len(rnd[101]) + len(rnd[102])} ({len(rnd[101])} with seed 101, `logs/run1-random-seed101.jsonl`; {len(rnd[102])} with seed 102, `logs/run1-random-seed102.jsonl`).")
w("* Runs: 2 (`logs/run1-*`, `logs/run2-*`). Verdict and category of every case are the same in both runs (checked by `make_findings.py`; the two random outputs are byte-identical).")
w(f"* Cases that diverge (fail the shipped pass/fail rule): {div_total} per run = {len(fails(hand))} hand-written (`logs/run1-hand-batch.classified.log`; {pyt1.split(',')[0]} in the harness copy, the other {len(fails(hand)) - int(pyt1.split()[0])} are the batch-only cases) + {len(fails(rnd[101]))} random with seed 101 (`logs/run1-random-seed101.classified.log`) + {len(fails(rnd[102]))} random with seed 102 (`logs/run1-random-seed102.classified.log`).")
w(f"* Distinct root causes: {len(ids)}. Per root cause, the number of diverging cases (hand-written / seed 101 / seed 102), from the three `classified.log` files above:\n")
w("| ID | hand | seed 101 | seed 102 | root cause |\n|---|---|---|---|---|")
for i in ids:
    w(f"| {i} | {len(H.get(i, []))} | {len(R1.get(i, []))} | {len(R2.get(i, []))} | {classify.TITLES[i]} |")
w("")
w("A random case is assigned to the first rule of `classify.py` that matches; one case can contain more than one divergence. "
  "No random case is left unclassified. No divergence was traced to the generator itself: every random divergence falls under a root cause that also has a hand-written reproducer, except TPL-46 (documented).\n")

w("## Divergences\n")
w("`HA result` and `HALean result` are copied from `logs/run1-hand-batch.jsonl`. "
  f"Patches were tested together in one throwaway copy (`patches/ALL.patch` = all `TPL-*.patch` in order); {SHIPPED}. "
  "With the patches the Template `*Spec.lean` modules no longer all compile (`patches/spec-build-with-all-patches.log`): see \"Notes on the patches\" below.\n")
w("| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |\n|---|---|---|---|---|---|---|")
for i in ids:
    rep, kind, doc, patch, _ = META[i]
    if rep == "-":
        r = (R1.get(i) or R2.get(i))[0]
        where = f"`gen/random-seed101.jsonl::{r['name']}`" if r["name"].startswith("r101") else f"`gen/random-seed102.jsonl::{r['name']}`"
    else:
        r = byname[rep]
        where = f"`{case_file[rep]}::{rep}`"
    ptxt = patch if patch.startswith("none") else patch + "; yes, with all patches"
    w(f"| {i} | {where} | {res(r['ha']).replace('|', chr(92) + '|')} | {res(r['lean']).replace('|', chr(92) + '|')} | {kind} | {doc.replace('|', chr(92) + '|')} | {ptxt.replace('|', chr(92) + '|')} |")
w("")

w("## Details\n")
for i in ids:
    rep, kind, doc, patch, cause = META[i]
    if rep == "-":
        r = (R1.get(i) or R2.get(i))[0]
    else:
        r = byname[rep]
    w(f"### {i}: {classify.TITLES[i]}\n")
    w(f"Kind: {kind}. Cases: {len(H.get(i, []))} hand-written, {len(R1.get(i, []))} + {len(R2.get(i, []))} random.\n")
    w("```")
    w(f"case:     {r['name']}")
    w(f"template: {r['template'] if len(r['template']) < 300 else r['template'][:300] + ' …'}")
    w(f"HA:       {json.dumps(r['ha'], ensure_ascii=False)[:400]}")
    lean = dict(r["lean"])
    w(f"HALean:   {json.dumps(lean, ensure_ascii=False)[:400]}")
    if r.get("ha_info") and r["cat"] == "info":
        w(f"HA info:  {json.dumps(r['ha_info'])}")
    w("```\n")
    w(cause + "\n")
    others = [x["name"] for x in H.get(i, []) if x["name"] != r["name"]]
    if others:
        w("Other hand-written cases: " + ", ".join(f"`{n}`" for n in others[:40]) + (" …" if len(others) > 40 else "") + ".\n")
    a = after.get(r["name"])
    if not patch.startswith("none") and a is not None:
        w(f"With the patches (`patches/all-patches-hand-batch.jsonl`): HALean gives {res({k: v for k, v in a['lean'].items() if k != 'info'})} (category `{a['cat']}`).\n")

sys.stdout.write("\n".join(out) + "\n")
sys.stdout.write(open("FINDINGS.tail.md").read())
