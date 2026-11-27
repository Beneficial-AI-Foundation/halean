---
name: translation-review
description: Review a formal translation of a reference implementation (a port with a manifest, a differential test harness and proofs) for faithfulness and proof usefulness, writing review/REVIEW.md; then review the report in a loop. Use when asked to audit, review or red-team such a translation, its tests, proofs or documentation claims.
---

# Translation review

Two prompts. Prompt 1 writes the review. Prompt 2 reviews the review and is meant to run 2 to 3 times under `/loop`.

Fill the placeholders from the repository before you start (read the manifest, lockfile, harness pins and directory layout; ask the user only if you cannot find them):

- `<REPO>`: the translation. `<UPSTREAM>`: the reference implementation and its pinned tag or commit. `<DEPS>`: other pinned dependencies the reference uses.
- `<PROVER>`: the proof language and build tool. `<MANIFEST>`: the file mapping upstream functions to translated definitions. `<TRACKER>`: the tool that tracks upstream drift.
- `<HARNESS>`: the differential harness. `<AREAS>`: the translated components, taken from the manifest and the directory layout.
- `<MEMCAP>`: build memory cap (default 16 GB).

## Prompt 1: write the review

Review `<REPO>` (a `<PROVER>` translation of parts of `<UPSTREAM>`) for two questions: is the translation faithful to upstream, and how useful are the proofs. Do not trust the README; check everything.

Pin the reference. Use the upstream commit and versions pinned in `<MANIFEST>` (`<UPSTREAM>` tag, `<DEPS>`). Install that exact upstream release (the differential harness usually pins it through a test-support package) and a sparse checkout of the tag for reading. Record the `<REPO>` commit you review.

Work in a `review/` directory that you create: one subdirectory per area under `review/experiments/`, each with a `README.md` saying how to rerun it, its cases, scripts, logs and any patches. Never change the translation or its `tests/`; test patches only in throwaway copies.

Do this, in order:

1. **Build and axiom audit.** Build under a `<MEMCAP>` memory cap. Write a `<PROVER>` file that collects the axioms of every theorem in every module of the translation (including generated ones) and tabulate them. Search the sources for `sorry`, `admit`, `native_decide`, `axiom`, `implemented_by`, `extern`, and count `partial` definitions. Say what CI runs.
2. **Shipped tests.** Run every shipped test (differential suite, scenario runners, end-to-end, numeric comparisons) and report the results. Check the README's claims that tests are sensitive by one-line mutations in throwaway copies.
3. **Faithfulness per area** (`<AREAS>`). For each: compare the translated definitions with the upstream functions that `<MANIFEST>` maps them to, by reading side by side; then write new hand-written cases and a random generator, run them against real upstream and the translation with the shipped differential harness (copied to read your case directory), and run everything at least twice. For every divergence: give a minimal reproducer, upstream's result, the translation's result, and classify it as Silent (different answer, no error), Accepts (the translation accepts what upstream refuses), Refuses, Order, or Tooling; check whether the README lists it as a known gap; and, where a small patch fixes it, test the patch in a throwaway copy and confirm the shipped tests still pass.
4. **What the theorems say.** Classify every theorem written in the source (central specifications, one-operation properties, edge cases, helper lemmas), with proof lengths. Say which parts of the behaviour they constrain and which they do not, and where a theorem's assumptions come from code nothing checks.
5. **Coverage.** Code lines per area (without blank lines and comments), theorems and `partial` definitions per area, and the share of code that substantive theorems cover. Test `<TRACKER>` for blind spots, for example by changing a constant that a mapped function uses in a copy of upstream.
6. **Claims audit.** Check every factual claim in `README.md`, the properties document, `<MANIFEST>` (statuses and notes) and theorem docstrings. Verdict for each: correct, correct for the wrong reason, overstated, false, or stale, with evidence.

Write the report as `review/REVIEW.md` with: a summary with a table of new cases and divergences per area; one bug list table holding every bug (ID, area, bug, kind, patched yes/no) that leaves out documented gaps and explicit refusals; then sections for build and axioms, shipped tests, faithfulness per area, the theorems, coverage, the claims audit, conclusions, recommended next steps, and how to reproduce. Every number and claim in the report must point to a log or a case under `review/`. Report only divergences that reproduced on two or more runs. Write plainly: short sentences, no hedging adjectives, no marketing words.

### Orchestration notes

- Run steps 3, 4 and 6 with one subagent per area or module group, in parallel. Give each the same conventions file (`review/CONVENTIONS.md`: environment paths, "never modify the reviewed repo", "patches only in throwaway copies", divergence kinds, the `FINDINGS.md` structure) and ask for `FINDINGS.md` with counts, a divergence table, details and notes on what the harness cannot observe.
- Subagents may be refused when they write report files. Tell them to return the finished text and save it yourself.
- Do not `pkill -f` an engine name while other agents run; it kills their processes.
- If a registry or toolchain host is blocked, fetch from a reachable mirror and record that in a log.
- Keep the bug list and its counts in a data file and build the table with a script. Keep the excluded rows (documented gaps, explicit refusals, duplicates) in a second file so that root causes equal listed plus excluded.
- Re-run a sample of reported divergences yourself through the unmodified harness before you write the report.

## Prompt 2: review the review (run it 2 to 3 times)

Review `review/REVIEW.md` against the repository and the evidence under `review/`. Do not add new findings about the translation; check the report itself.
For every number, table row and claim in the report:

* Reproduce it from the logs or by rerunning the case. Recount totals (cases, divergences, theorems, lines, claims per verdict) and check that the summary, the bug list and the per-area sections agree with each other.
* Check each bug still reproduces, against both upstream and the translation, and that its kind (Silent / Accepts / Refuses / Order / Tooling) and "patched" column are right. Drop or correct anything that does not hold, and say why.
* Check each "documented gap" against the README text, and each claim verdict against the quoted source.
* Check the wording: every statement must be supported by the evidence it cites; remove overstatement, hedging and claims without a log.

Edit `review/REVIEW.md` in place and append a short "Changes in this pass" list at the end of `review/review-passes.md` (what changed, and why). If this pass changed nothing of substance, write "No changes" there and stop the loop.

## Running it

1. Start a session in the repository and run Prompt 1. It is long-running; let it finish.
2. Run Prompt 2 under `/loop` without an interval, so the session paces itself and stops on its own:

   ```
   /loop <the whole of Prompt 2>
   ```

   - With no interval, Claude decides when to run the next pass; the loop ends when a pass writes "No changes".
   - To cap it, add "stop after 3 passes" to the prompt, or give a fixed interval, for example `/loop 10m ...`.
   - Stop it by hand at any time by telling Claude to stop the loop.
   - In a cloud session a loop timer lives in the container and does not survive it being released.
3. Read `review/review-passes.md` to see what each pass corrected.
