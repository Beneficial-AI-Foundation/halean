---
name: translation-review
description: Run an evidence-based faithfulness-and-proof-usefulness review of a formal translation of a reference implementation (for example a Lean/Coq/Rust port of Python code with a manifest, a differential test harness and theorems), then review the report in a loop until a pass changes nothing. Use when asked to audit, review or red-team such a translation, its tests, its proofs or its documentation claims.
---

# Translation review

Reviews a repository that translates parts of a reference implementation (the upstream) into another language, usually with proofs. Two questions: is the translation faithful to upstream, and how useful are the proofs. Produces `review/REVIEW.md` and every log, case and patch behind it. Then a second prompt reviews the report in a loop.

Do not trust the repository's README, manifest notes or theorem docstrings. Every claim is checked against upstream, the build, the tests or a probe.

## Inputs (fill from the repo; ask only if you cannot find them)

- `REPO`: the repository; `UPSTREAM_PIN`: upstream tag and commit as pinned by the repo (manifest, lockfile, harness pin); dependency pins that the upstream code relies on.
- `BUILD`: build and test commands; `HARNESS`: the differential harness (reference implementation vs translation); `MANIFEST`: the mapping from upstream functions to translated definitions, with its tracking tool.
- `AREAS`: the translated components (one review agent each). Derive them from the manifest and the directory layout.

## Rules for the whole run

1. Never modify the reviewed code, tests, manifest or docs. Work in `review/`: one subdirectory per area under `review/experiments/`, each with a `README.md` (how to rerun), `cases/`, `gen/`, `harness/`, `logs/`, `patches/`, and later `FINDINGS.md`. Patches and mutations only in throwaway copies (`cp -a` the repo to a scratch directory; delete copies when done).
2. Pin the reference. Install the exact upstream release the repo pins (the harness usually pins it through a test-support package) and keep a sparse checkout of the tag for reading. Record the reviewed commit of the repo in `review/logs/`.
3. Cap memory for builds (cgroup or `ulimit`) at the size the user names; write the peak into a log.
4. Every number and claim in the report must point to a log, data file or case directory under `review/`. Report a divergence only if it reproduced on two or more runs. Keep both logs. Random generators take a seed; record seeds; minimise random failures by hand into named cases.
5. Write plainly: short sentences, no hedging adjectives, no marketing words. Do not state a cause you have not verified.
6. Commit and push `review/` after each stage if the session asks for it. Do not create pull requests unless asked.
7. Environment hazards seen in practice: the network proxy may block registries or toolchain hosts (fetch release tarballs from a reachable mirror and say so in the log); a container image may need a mirror (check the image id is identical); never `pkill -f` a process name while other agents run (it kills their engines); subagents may be refused when they try to write report files: tell them to return the finished text and save it yourself.

## Stage 1: build and axiom audit

- Build under the memory cap; record toolchain, wall time, peak memory, warnings.
- Write a file for the proof assistant that collects the axioms of every theorem in every module of the translation, including generated ones, memoised over the environment; split source-written from generated theorems. Tabulate the axiom sets per area.
- Search the sources for `sorry`, `admit`, `native_decide`/native evaluation, `axiom`, `implemented_by`, `extern`, `unsafe`, `opaque`; count non-total (`partial`) definitions per file and their code lines. Check every module is imported by the library root.
- Say what CI runs: read every workflow and list what runs on pull requests, on the main branch, and what never runs (typically the differential suite).

## Stage 2: shipped tests

- Run every shipped test (differential suite, scenario runners, bridge or end-to-end, numeric comparisons, live/container test) at least twice; log each. Record skip reasons from the verbose run.
- Check the README's sensitivity claims ("the tests catch X") with one-line mutations in throwaway copies; record failing-test counts. Add 2-3 mutations of your own in places a proof or test should catch (flip an admission comparison, flip a disabled-condition result, remove a limit) and report which suites notice.

## Stage 3: faithfulness per area (one agent per area, in parallel)

Give each agent this brief. Put the shared rules in a `review/CONVENTIONS.md` and tell it to read that first.

1. Read upstream and the translation side by side for every manifest entry of the area; write `side-by-side.md` with file:line on both sides. Look for missing branches, order of checks, error classes and messages, string handling and Unicode, number parsing and formatting, ordering, equality semantics, and what the JSON driver or bridge does to input before the model sees it.
2. Write new hand-written cases in the harness's format (aim far beyond the shipped count, one behaviour per case) and a seeded random generator over an edge-case-rich pool.
3. Run both through a copy of the shipped harness against the real reference and the translation. The copy changes only the case directory, the engine path and optional dumps; the pass/fail rule stays the shipped one. At least two runs.
4. For every divergence: minimal reproducer, reference result, translation result, kind, root cause with file:line on both sides, whether the README lists it (quote the line), and where a small patch fixes it, test the patch in a throwaway copy and confirm the shipped tests still pass.
   Kinds: **Silent** (different answer, no error), **Accepts** (translation accepts what the reference refuses), **Refuses** (translation refuses what the reference accepts), **Order**, **Tooling** (harness, driver, bridge, tracking tool).
5. Separate real divergences from generator artefacts and harness limits. One ID per root cause (`<AREA>-<n>`).
6. Deliver `FINDINGS.md` with: Counts (hand-written cases, random per run, runs, divergent cases, each with its log); Divergences table (ID, reproducer, reference result, translation result, kind, README lists it with line, patch and test log); Details; Reading findings without a reproducer; Notes on the harness (what it cannot observe).

## Stage 4: what the theorems say (agents by module group)

- Dump every source declaration from the compiled environment (kind, module, name, line range, constants used in the statement and body); join with the source to get proof and statement lengths (exclude blank lines and comments). Cross-check the theorem count against a text grep.
- Each agent classifies every theorem of its modules by reading the statement: **C** central specification (determines the result of a translated function over its domain), **O** one-operation property (holds for a class of inputs, does not determine the result), **E** edge case (one input or constructor), **H** helper lemma. Be strict about C. Key by (module, name); validate counts with a script (no missing, no duplicates).
- Per area, write: what is constrained; what is not (non-total definitions that statements mention hold for any function in their place; decoders and parsers; entry points; opaque fuel or budget constants); assumptions nothing discharges (well-formedness, freshness, decoder output); vacuous or restating theorems; for each C theorem whether its right-hand side is an independent specification or a restatement of the implementation's case split; theorem docstring and module-header claims with verdicts; manifest entries with status `proven` (does the cited theorem determine the function?); properties-document claims.
- Consolidate verdicts across overlapping scopes with one agent that rereads every `false` verdict itself.

## Stage 5: coverage and the tracking tool

- Code lines per area (no blank lines, no comments), theorems and non-total definitions per area, lines inside or calling a non-total definition, and the share of implementation definition lines named in a C statement, in a C or O statement, and reachable from those through total definitions. State the definitions in the script docstring.
- Test the tracking tool for blind spots in a copy of upstream: a control edit of a mapped function body and a comment edit; then edit a constant, a regex, a module-level schema, a limit, an unmapped helper called by a mapped function, a file with no manifest entry. Record which are flagged. Measure by script what mapped functions read that the tool does not hash. Check that every translated name in the manifest exists as a declaration.

## Stage 6: claims audit

Verdicts: `correct`, `correct for the wrong reason`, `overstated`, `false`, `stale`. Audit every claim in the README (split into numbered claims with line numbers; probe a sample of 60+ behavioural claims with a shipped case or a direct probe), every manifest entry (resolve upstream refs, check names exist, check notes against both sources, check status), the properties document, theorem docstrings. Use `git log -S` for stale claims. Each verdict needs evidence: file:line, a command and saved log, or a case name.

## Stage 7: write `review/REVIEW.md`

Sections: summary with a table of new cases and divergences per area; one bug list table (ID, area, bug, kind, patched yes/partial/no) that leaves out documented gaps and explicit refusals; build and axioms; shipped tests (with mutation table); faithfulness per area; what the theorems say; coverage; claims audit; conclusions; recommended next steps; how to reproduce; limits of the review. Build the bug list and its counts from a data file with a script, and keep the excluded rows (documented gaps, explicit refusals, duplicates) in a second data file so that `root causes = listed + excluded` reconciles. Re-verify a sample of reviewer findings yourself through the unmodified shipped harness, twice, and say so. Say plainly what the review did not do.

Reconcile before writing: per-area root-cause counts vs the bug list, kind counts vs the summary, theorem class counts vs per-area tables, claim verdict totals vs the audit files.

## Stage 8: review the report (run under `/loop`, no interval)

Create `review/review-passes.md`. Run this prompt as `/loop <prompt>`; stop after 3 passes or when a pass writes "No changes":

```
Review review/REVIEW.md against the repository and the evidence under `review/`. Do not add new findings about HALean-like defects; check the report itself.
For every number, table row and claim in the report:

* Reproduce it from the logs or by rerunning the case. Recount totals (cases, divergences, theorems, lines, claims per verdict) and check that the summary, the bug list and the per-area sections agree with each other.
* Check each bug still reproduces, against both the reference and the translation, and that its kind (Silent / Accepts / Refuses / Order / Tooling) and "patched" column are right. Drop or correct anything that does not hold, and say why.
* Check each "documented gap" against the README text, and each claim verdict against the quoted source.
* Check the wording: every statement must be supported by the evidence it cites; remove overstatement, hedging and claims without a log.

Edit review/REVIEW.md in place and append a short "Changes in this pass" list at the end of review/review-passes.md (what changed, and why). If this pass changed nothing of substance, write "No changes" there and stop the loop.
```

Per pass: recount with scripts, not by eye; recheck documented-gap line numbers by reading the cited README lines; rerun at least five bug reproducers through the shipped harness; look for sentences that state a cause, count or scope without a log (they were the commonest error in practice: invented kind splits, wrong independent/restatement counts, control edits counted as misses, "no theorem covers X" where a theorem did). In a cloud session a loop timer dies with its container; say so when arming it.
