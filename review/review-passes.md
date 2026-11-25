# Review passes

Pass 0: initial report written (`REVIEW.md`). Passes of the second prompt append their "Changes in this pass" below.

## Pass 1

Changes in this pass:
- Summary: the 46 rows excluded from the bug list are 45 documented gaps or explicit refusals plus 1 duplicate (SCR-11, counted under AUT-14). The first draft called all 46 documented gaps or refusals.
- Section 6.4: replaced the invented kind split "26 Silent, 9 Accepts, 14 Refuses (3 documented)" with the split from `data/bugs.tsv` and `data/excluded.tsv` (36 in the list: 26/9/1; 12 excluded: 3 documented Silent or Order, 9 explicit refusals). Conclusion 2 said 9 undocumented template refusals; `data/excluded.tsv` has 6 undocumented and 2 partly documented.
- Section 7.3: the class-C split was wrong (29 independent / 41 restatement / 16 other). Recounted from the six `class/<area>.md` files: 32 independent, 52 restatements, 2 in between. Same fix in the summary and conclusion 4.
- Section 7.3, helpers: the draft said no theorem covers any helper service. `Helpers/Proofs.lean` has 25 theorems on `counter`, `input_number`, `input_select`, `input_boolean` bounds and membership (`class/scripts-helpers.tsv`). Rewritten to say what they cover and what is uncovered.
- Section 4: removed an unsupported statement about where `Classical.choice` comes from. Added `experiments/01-build-axioms/logs/module-imports.txt` as the log for "every module is imported".
- Section 9.1: "9 of the 10 edits go unnoticed" counted a control edit (a comment) that is not meant to be flagged. Now: none of the 8 edits to constants, a regex, a schema and an unmapped helper is flagged; the control body edit is. The count of manifest entries naming missing Lean definitions is 8 (not 7: one `proven` entry, M-28, also carries one).
- Section 7.3 schemas: partial-def count qualified (reviewer lists 17; `coverage.py` counts 16 in the area's files).
- Section 6.10: 7 case files (not 5) were run through the shipped harness copy.
- Section 10.4: removed a README claim (FIFO) that had been listed as a docstring example; it is now a separate "related README item".
- Section 10.3: named the two false PROPERTIES.md claims (P-3, P-69).
- Checked and left unchanged: the bug-list counts (101 rows; 68 Silent, 19 Accepts, 3 Refuses, 11 Tooling; 54 patched), the area table totals (1,978 hand-written cases; 144 root causes), documented-gap README line numbers for ST-4, ST-7, ST-8, ST-9, REG-4, HASS-1/3/4, TPL-25, TPL-27, TPL-46, SCR-12/13/16, HLP-18/21 (all quoted text found at the cited lines), the shared cause of SCH-1 and TPL-47 (`parseFloatStr`, `Template/Value.lean:187-192`), the shipped-test and mutation tables.
