#!/usr/bin/env python3
"""Group the failing records of batch outputs by root cause (the TPL-<n> IDs of FINDINGS.md).

usage: classify.py OUT.jsonl [OUT2.jsonl ...]      prints, per file, the count of failing cases per ID
       classify.py --list ID OUT.jsonl             prints the names of the cases assigned to ID

Hand-written cases are assigned by name (HAND, first match wins); random cases by rules on the template
and on both results (rules(), first match wins).  Anything no rule matches is reported as UNCLASSIFIED.
"""
import json
import re
import sys

TITLES = {
    "TPL-1": "string escapes \\ooo \\u \\U \\N not decoded",
    "TPL-2": "dict keys: no dedup, no hash check",
    "TPL-3": "dict.keys()/values()/items() are lists",
    "TPL-4": "bool() of states objects; `if value:` guard of map/select",
    "TPL-5": "last / reverse over states objects",
    "TPL-6": "case-insensitive entity id lookup",
    "TPL-7": "float sum is not compensated",
    "TPL-8": "repr(str) non-printable characters",
    "TPL-9": "Undefined inside a printed container",
    "TPL-10": "Namespace repr",
    "TPL-11": "loop object is a dict",
    "TPL-12": "for-else after break/continue",
    "TPL-13": "generators can be consumed twice",
    "TPL-14": "generators are evaluated eagerly",
    "TPL-15": "tests sequence / iterable",
    "TPL-16": "float(): whitespace and digits",
    "TPL-17": "_parse_result: Unicode digits",
    "TPL-18": "static template strip is ASCII-only",
    "TPL-19": "title filter whitespace",
    "TPL-20": "str.split(None, maxsplit) remainder",
    "TPL-21": "float // and % with infinities",
    "TPL-22": "timestamp_custom default format",
    "TPL-23": "T24:00:00 gives None",
    "TPL-24": "strftime %Y below year 1000",
    "TPL-25": "zone database / DST (documented)",
    "TPL-26": "JSON numbers with an exponent become ints",
    "TPL-27": "attribute / variable key order (documented)",
    "TPL-28": "literal_eval: set, bytes, Ellipsis, complex",
    "TPL-29": "literal_eval: nested unary sign",
    "TPL-30": "lexer accepts .5 and 007",
    "TPL-31": "parser accepts invalid Jinja",
    "TPL-32": "OverflowError / digit limit not raised",
    "TPL-33": "argument count and keywords not checked",
    "TPL-34": "non-string / Undefined entity id",
    "TPL-35": "sum(start=str)",
    "TPL-36": "timestamp_* accepted as globals",
    "TPL-37": "uncaught HA errors treated as 'use default'",
    "TPL-38": "Jinja compile-time constant folding",
    "TPL-39": "valid Jinja syntax rejected at load",
    "TPL-40": "Python methods / attributes / operators not modelled",
    "TPL-41": "argument forms not modelled",
    "TPL-42": "datetime methods and strftime directives not modelled",
    "TPL-43": "date strings only ciso8601 parses",
    "TPL-44": "printing objects",
    "TPL-45": "HA gives Undefined/default, HALean raises",
    "TPL-46": "documented render errors (non-ASCII case mapping)",
    "TPL-47": "huge float exponent: time and memory",
    "TPL-48": "step budget of 1,000,000",
}

# (regex on the case name, ID) for the hand-written cases
HAND = [
    (r"syn_str_(octal|u_|bigu|name)|pr_str_(u_escape|octal|named)", "TPL-1"),
    (r"val_dict_(dup|int_bool|unhashable)|val_in_dict_unhashable|pr_dict_(dup|int_bool|unhashable)|pr_set_unhashable", "TPL-2"),
    (r"val_dict_(keys|values|items)_(print|eq|index)|val_dict_keys_eq|val_dict_keys_index", "TPL-3"),
    (r"val_truthy_(domain|all_states)|val_not_domain|st_domain_(if|join|select|sum|and|iif|default_boolean)_info|st_domain_default_boolean|st_empty_domain|st_all_select_info", "TPL-4"),
    (r"st_(domain|all)_(reverse|last)", "TPL-5"),
    (r"st_case_insensitive", "TPL-6"),
    (r"flt_sum_float", "TPL-7"),
    (r"val_repr_(nbsp|c1|soft|line|private|zero)", "TPL-8"),
    (r"val_print_undefined", "TPL-9"),
    (r"val_print_namespace", "TPL-10"),
    (r"val_print_loop|loop_(cycle|changed|depth|is_mapping|length_filter|iterate_loop|name_reassigned)", "TPL-11"),
    (r"loop_(break_then_else|continue_all_then_else|filtered_all_continue_else)", "TPL-12"),
    (r"loop_over_generator_twice|loop_generator_list_twice|flt_generator_|flt_reverse_iterator_reused|flt_unique_generator_reused", "TPL-13"),
    (r"flt_(map|select)_lazy", "TPL-14"),
    (r"tst_(sequence|iterable)_|und_is_sequence", "TPL-15"),
    (r"flt_float_(vt|ff|us|nbsp|arabic|fullwidth)", "TPL-16"),
    (r"pr_(fullwidth|arabic)", "TPL-17"),
    (r"pr_static_(vt|nbsp|us)", "TPL-18"),
    (r"flt_title_vt", "TPL-19"),
    (r"val_str_split_none_maxsplit", "TPL-20"),
    (r"val_(mod|floordiv)_(inf|neg_by_inf)", "TPL-21"),
    (r"dt_timestamp_custom_default_format", "TPL-22"),
    (r"dt_as_datetime_hour_24", "TPL-23"),
    (r"dt_strftime_small_year", "TPL-24"),
    (r"dt_(timestamp_local_summer|timestamp_custom_summer|as_local_summer|as_local_naive_summer|add_days|sub_days|replace_month|same_zone|today_at_dst|today_at_midnight_dst)", "TPL-25"),
    (r"val_var_float_exp|st_attr_float_exp", "TPL-26"),
    (r"val_var_dict_order|st_attr_(order|keys_order|nested_order)", "TPL-27"),
    (r"pr_(set|bytes|ellipsis|complex_in_list|rendered_set_like)|syn_dict_lone_brace", "TPL-28"),
    (r"pr_signs_in_list|pr_nested_unary_in_list", "TPL-29"),
    (r"syn_float_leading_dot|syn_int_leading_zero", "TPL-30"),
    (r"syn_if_cond_expr|syn_set_to_(none|true)_name|syn_(break|continue)_outside_loop", "TPL-31"),
    (r"val_(int_div_overflow|int_plus_float_overflow|float_pow_overflow|int_pow_neg_overflow)|flt_round_huge_precision|td_overflow_mul|pr_(static|list|rendered)_4400|val_int_(str_4301|print_over)", "TPL-32"),
    (r"flt_arity|flt_default_extra|tst_(eq_missing|none_extra|defined_extra|eq_two)|flt_select_missing_test_arg|val_dict_get_kw|val_str_startswith_start|dt_isoformat_long_sep", "TPL-33"),
    (r"st_(nonstr|list_id)|und_(is_state|state_attr|has_value)_arg", "TPL-34"),
    (r"flt_sum_strings_start", "TPL-35"),
    (r"dt_timestamp_(utc|local|custom)_as_global", "TPL-36"),
    (r"dt_timestamp_utc_1e20_default|und_as_datetime_default", "TPL-37"),
    (r"val_(cmp_nan_eq_self|nan_in_list_identity|const_fold)|dt_timestamp_utc_inf_default|st_states_filter_(info|missing)|st_const_fold", "TPL-38"),
    (r"syn_(dot_int|int_hex|int_bin|int_oct|ws_plus_right|ws_formfeed|for_paren|for_nested|for_recursive|set_paren|set_block|star_args|nonascii_name|subscript_empty)", "TPL-39"),
    (r"val_(str_method|list_method|list_attr|list_str_sub|str_attr|int_attr|int_dot|int_real|int_method|float_is_integer|private|dict_copy|dict_items_key|str_lower_no_call|str_percent|tuple_mul|bool_mul_list)|tst_divisibleby_str_format|flt_(map_attribute_on|selectattr_on_strs)|td_(attr_unknown|floordiv_bool)|st_(all|domain)_private", "TPL-40"),
    (r"val_(pow_complex|pow_large_exp|dict_global_positional|dict_global_pairs)|ns_positional|flt_(int_base|round_precision_float|join_attribute|sum_attribute|last_dict)|st_(rounded|with_unit|state_with_unit)|dt_sort_datetimes", "TPL-41"),
    (r"dt_(strftime_|attr_|isoformat_timespec|replace_(tzinfo|bool|positional)|naive_timestamp|as_timestamp_naive)", "TPL-42"),
    (r"dt_as_datetime_(date_only|compact|lower_z|comma|trailing_text)|dt_as_timestamp_(int|date_only)", "TPL-43"),
    (r"val_print_(function|states|domain|state_object)|dt_in_list_repr|flt_reverse_generator_is_list", "TPL-44"),
    (r"und_(first|last|reverse)|dt_as_datetime_nan_string|flt_round_nan_ceil_default", "TPL-45"),
    (r"flt_float_exponent", "TPL-47"),
    (r"loop_step_budget", "TPL-48"),
]


def info_diff(r):
    h = r.get("ha_info") or {}
    le = r["lean"].get("info") or {}
    return {k for k in h if h[k] != le.get(k)}


def rules(r):
    """Root cause of a failing random case, or None."""
    t = r["template"]
    ha, le = r["ha"], r["lean"]
    herr = ha.get("error", "") if not ha.get("ok") else ""
    lerr = le.get("error", "") if not le.get("ok", True) or "error" in le else ""
    hrepr, lrepr = ha.get("repr", ""), le.get("repr", "")
    if "unsupported" in le:
        return "TPL-39"
    if lerr:
        for pat, rid in (
            (r"repr\(\) of a datetime|^printing ", "TPL-44"),
            (r"(slicing|indexing) (range|datetime|timedelta)|complex results|exponent too large|with positional|base other than", "TPL-41"),
            (r"timestamps of naive|^datetime\.\w+ is not supported|strftime directive|replace\(", "TPL-42"),
            (r"unsupported operand type\(s\) for (\*|//): '(tuple|int|list|bool|timedelta)' and '(tuple|int|list|bool)'", "TPL-40"),
            (r"attribute '\w+' of \w+ is not supported|^str\.\w+ is not supported|timedelta\.\w+ is not supported|is unsafe|string formatting with %", "TPL-40"),
            (r"non-ASCII", "TPL-46"),
            (r"step budget", "TPL-48"),
            (r"parsing '.*' as a date/time", "TPL-43"),
            (r"ValueError: year is out of range|slicing (int|float|dict|bool|NoneType)", "TPL-45"),
            (r"object is not iterable", "TPL-4"),
        ):
            if re.search(pat, lerr) and ha.get("ok"):
                return rid
    if herr and le.get("ok"):
        if "timestamp out of range" in herr or "cannot convert float infinity" in herr or "Value too large" in herr:
            return "TPL-37"
        if "as a dict key" in herr or "unhashable" in herr:
            return "TPL-2"
        if re.search(r"NameError: name '(nan|inf)'", herr):
            return "TPL-38"
        if "OverflowError" in herr or "Exceeds the limit" in herr:
            return "TPL-32"
        if "has no attribute 'lower'" in herr:
            return "TPL-34"
    both_err = not ha.get("ok") and not le.get("ok", True)
    if (ha.get("ok") and le.get("ok")) or both_err:
        same_result = both_err or {k: v for k, v in le.items() if k != "info"} == ha
        if not same_result:
            if "Undefined" in hrepr and "Undefined" not in lrepr:
                return "TPL-9"
            if hrepr != lrepr and sorted(hrepr) == sorted(lrepr) and "'id'" in hrepr:
                return "TPL-27"
            if re.search(r"else %\}", t) and re.search(r"\{% (break|continue) %\}", t) and (
                    "empty" in hrepr or len(hrepr) > len(lrepr)):
                return "TPL-12"
            if re.search(r"[-+]0[78]:00|timestamp_(local|custom)|as_local|today_at|now\(\)", t + hrepr) and re.search(
                    r"\d\d:\d\d|\d{6,}\.\d|days?, ", hrepr):
                return "TPL-25"
            if re.search(r"(true|false|1|1\.0|2\.5|none): ", t) and hrepr.count(": ") < lrepr.count(": "):
                return "TPL-2"
            if re.search(r"[A-Z][a-z]+\.[A-Z]|light\.B|Sensor\.A", t):
                return "TPL-6"
            if "| sum" in t:
                return "TPL-7"
        d = info_diff(r)
        if d:
            if re.search(r"Sensor\.A|light\.B", t) and "entities" in d:
                return "TPL-6"
            if d <= {"all_states_lifecycle", "domains_lifecycle", "domains", "all_states"}:
                return "TPL-4"
    return None


def classify(r):
    name = r.get("name") or ""
    if not re.match(r"r\d+_\d+$", name):
        for pat, rid in HAND:
            if re.match(pat, name):
                return rid
        return None
    return rules(r)


def main():
    args = sys.argv[1:]
    listing = None
    if args and args[0] == "--list":
        listing, args = args[1], args[2:]
    for path in args:
        counts, total, fails, uncl = {}, 0, 0, []
        for line in open(path):
            r = json.loads(line)
            total += 1
            if r["verdict"] == "pass":
                continue
            fails += 1
            rid = classify(r)
            if rid is None:
                uncl.append(r)
            else:
                counts[rid] = counts.get(rid, 0) + 1
                if rid == listing:
                    print("   ", r["name"])
        print(f"{path}: cases={total} failing={fails} unclassified={len(uncl)}")
        for rid in sorted(counts, key=lambda x: int(x.split("-")[1])):
            print(f"  {rid:7} {counts[rid]:5}  {TITLES[rid]}")
        for r in uncl:
            ha, le = r["ha"], r["lean"]
            print(f"  UNCLASSIFIED {r['name']} [{r['cat']}] {r['template'][:160]!r}\n      HA: {str(ha)[:200]}\n    Lean: {str(le)[:200]}")


if __name__ == "__main__":
    main()
