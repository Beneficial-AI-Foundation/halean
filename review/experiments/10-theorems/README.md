# 10-theorems: what the theorems say

Inputs (machine-made, do not edit):

* `logs/decls.tsv`: every source declaration of the built library, from the Lean environment (`Inventory.lean`).
  Rerun: `lake env lean review/experiments/10-theorems/Inventory.lean` (after `lake build HALean`).
* `logs/theorems.tsv`: the 1,943 theorems written in the source, one per line:
  `module, name, file, start line, end line, proof_lines, stmt_lines, has_docstring, HALean constants in the statement`.
  `logs/defs.tsv`: source definitions: `kind (def|partial|opaque|inductive|structure|instance), module, name, file, start, end, code_lines, constants used`.
  Rerun: `python3 review/experiments/10-theorems/inventory.py` (totals in `logs/inventory-summary.txt`).
  Line counts exclude blank lines and comments.

Classification (hand-made, by reading each theorem): `class/<area>.tsv`, one line per theorem:
`module <TAB> name <TAB> class <TAB> reason`. Classes:

* `C` central specification: characterises the whole input-output behaviour of a translated function over all its
  inputs (an `iff`/equation that determines the result, or agreement with an independently written specification).
* `O` one-operation property: holds for all inputs (of a stated class) of one operation, but does not determine its
  result (an invariant is kept, a bound, monotonicity, idempotence, "no event is fired when ...").
* `E` edge case: about one concrete input or a narrow input class (closed terms proved by `rfl`/`decide`, the empty
  list, one constructor, one literal).
* `H` helper lemma: an auxiliary fact used to prove others (list/arithmetic/data-structure lemmas, unfolding lemmas,
  facts about internal helper functions), not itself a statement about upstream behaviour.

`class/<area>.md` holds the per-area notes (what is constrained, what is not, unchecked assumptions, docstring and
manifest claim verdicts). `classify_summary.py` joins everything into `logs/classification-summary.txt`.
