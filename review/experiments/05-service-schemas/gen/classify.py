"""Classify the operations a record-mode run wrote (SCH_RECORD jsonl) by root
cause. Usage: classify.py FILE.jsonl [...]. Prints counts and, for anything
unclassified, the full record."""
from __future__ import annotations
import collections, json, re, sys

ENTITY = re.compile(r"&(#\d+|#x[0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);")


def unescape_eq(ha: str, lean: str) -> bool:
    """HA's repr escapes non-printable characters; HALean prints the non-ASCII
    ones raw (and escapes the ASCII ones like Python)."""
    def raw(m):
        cp = int(m.group(1)[1:], 16)
        return chr(cp) if cp >= 0x80 else m.group(0)
    return re.sub(r"\\(x[0-9a-f]{2}|u[0-9a-f]{4}|U[0-9a-f]{8})", raw, ha) == lean


def strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, dict):
        for k, x in v.items():
            yield k
            yield from strings(x)


def classify(rec: dict) -> str:
    ha, le = rec["ha"], rec["halean"]
    if rec["kind"] == "unsupported":
        why = le["unsupported"]
        if why.startswith("text outside printable ASCII"):
            return "documented refusal: text that is not printable ASCII (README 335)"
        if why.startswith("timedelta(...) raises"):
            return "documented refusal: timedelta overflow / NaN (README 335)"
        if why.startswith("util.slugify"):
            data = {**(rec["op"].get("data") or {}), **(rec["op"].get("target") or {})}
            if any(ENTITY.search(s) for s in strings(data)) or any(ENTITY.search(s) for s in strings(rec.get("schema"))):
                return "documented refusal: slugify of text with an HTML entity (README 335)"
            return "SCH-5 slugify refused for text with '&' and ';' but no HTML entity"
        return "UNCLASSIFIED unsupported: " + why
    if le.get("type") == "error":
        return "UNCLASSIFIED engine error"
    if ha.get("ok") and le.get("ok"):
        if unescape_eq(ha["result"], le["result"]):
            return "SCH-2 repr() of non-printable non-ASCII characters (README 348)"
        return "UNCLASSIFIED value"
    if not ha.get("ok") and not le.get("ok"):
        he, lee = ha["error"], le["error"]
        if he["exception"] == "OverflowError" and he["message"] == "int too large to convert to float":
            return "SCH-3 Coerce(float) of a huge int after the schema's 50th validation"
        if he["exception"] == "TypeError" and "'datetime.timedelta' object is not iterable" == he["message"] \
                and lee["message"] == "'timedelta' object is not iterable":
            return "SCH-4 TypeError names 'timedelta' instead of 'datetime.timedelta'"
        if he["exception"] == lee["exception"] and unescape_eq(he["message"], lee["message"]):
            return "SCH-2 repr() of non-printable non-ASCII characters (README 348)"
        if he["exception"] == "SchemaError":
            return "SCH-6 AtLeastOne() without keys"
        return "UNCLASSIFIED error"
    if not ha.get("ok") and ha["error"]["exception"] == "OverflowError" and \
            ha["error"]["message"] == "int too large to convert to float":
        return "SCH-3 Coerce(float) of a huge int after the schema's 50th validation"
    if not ha.get("ok") and ha["error"]["exception"] == "SchemaError":
        return "SCH-6 AtLeastOne() without keys"
    return "UNCLASSIFIED ok/error"


total_div_cases = set(); total_div_ops = 0; total_doc_ops = 0
for path in sys.argv[1:]:
    counts = collections.Counter(); first = {}; div_cases = set(); doc_cases = set()
    n = 0
    for line in open(path):
        rec = json.loads(line); n += 1
        c = classify(rec); counts[c] += 1; first.setdefault(c, rec)
        (doc_cases if c.startswith("documented") else div_cases).add(rec["case"])
    div_ops = sum(k for c, k in counts.items() if not c.startswith("documented"))
    total_div_cases |= {(path, c) for c in div_cases}; total_div_ops += div_ops; total_doc_ops += n - div_ops
    print(f"{path}: {n} recorded operations (different or unsupported): {div_ops} divergent in {len(div_cases)} cases, "
          f"{n - div_ops} documented refusals; {len(div_cases | doc_cases)} cases with a recorded operation")
    for c, k in sorted(counts.items()):
        print(f"  {k:6d}  {c}   first: {first[c]['case']} op {first[c]['op_index']}")
    for c, rec in first.items():
        if c.startswith("UNCLASSIFIED"):
            print("  UNCLASSIFIED EXAMPLE:", json.dumps(rec)[:3000])
print(f"TOTAL: {total_div_ops} divergent operations in {len(total_div_cases)} cases; {total_doc_ops} documented refusals")
