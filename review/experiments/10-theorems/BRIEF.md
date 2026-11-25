# Brief for theorem reviewers (step 4 and the theorem-related part of step 6)

Repository: /home/user/halean (HALean: Lean 4 translation of parts of Home Assistant core; commit f638a37).
Read `review/experiments/10-theorems/README.md` first (inputs and class definitions). Upstream source for
reference: `/home/user/halean/upstream/ha-core/homeassistant/` and `/opt/havenv/lib/python3.14/site-packages/{probatio,jinja2}`.
Do not modify anything outside `review/experiments/10-theorems/class/`. Do not run `lake build` in /home/user/halean.
You may run read-only Lean checks: `export PATH=$HOME/.elan/bin:$PATH; cd /home/user/halean; lake env lean <your file under class/scratch/>`
(for example `#print axioms X`, `#check @X`, `#print X`) when you need the exact statement of a theorem.

You are assigned a list of modules. For your modules produce two files (replace `<area>` with your area name):

## 1. `class/<area>.tsv`
One line per theorem of your modules listed in `logs/theorems.tsv` (every one; the line count must equal the number
of `theorems.tsv` rows for your modules): `module <TAB> name <TAB> class <TAB> reason`, class in {C, O, E, H} as
defined in the README, reason = at most 15 words saying what the statement says. Read each theorem's statement in
the source (file and lines are in `theorems.tsv`); do not classify from the name. Be strict about `C`: the statement
must determine the result of a translated upstream function for all inputs in its domain (possibly under stated
hypotheses); a theorem that fixes the result only for one constructor or one literal input is `E`; a theorem about
an internal helper with no upstream counterpart is `H` even if it is an `iff`.

## 2. `class/<area>.md` with these sections
* `## What the theorems constrain`: per implementation file / upstream function group, which behaviour is pinned
  down by `C` and `O` theorems. Name the theorems.
* `## What they do not constrain`: definitions of the implementation files in your area that no `C`/`O` theorem
  mentions, with emphasis on (a) `partial def`s (opaque to the kernel: list any theorem whose statement mentions a
  partial def and say what it can and cannot mean), (b) the JSON decoders / protocol drivers / parsers, (c) the
  main entry points (e.g. the top-level step/eval/render function): is there any theorem about the entry point
  itself, or only about pieces? Use `logs/defs.tsv` (kind column) to find partial defs.
* `## Assumptions that nothing checks`: theorems whose hypotheses (well-formedness predicates, "no duplicate",
  "fuel suffices", "decoder returned ok", bounds on sizes, hypotheses about opaque/partial functions, hypotheses
  that an input list is sorted, etc.) are not established by any other theorem for the values the running code
  actually produces (for example: the hypothesis is about the output of a `partial def` decoder, or of the
  unverified Python bridge/driver, or is a property of the initial state nobody proves the initial state has).
  For each: theorem, hypothesis, where the value comes from at run time, whether some theorem discharges it.
  Also list theorems that are vacuous or weaker than they read (hypotheses that cannot hold together, conclusion
  that holds for any function, `True` conclusions, statements proved by `rfl` that only restate the definition —
  mark restatements as such: a theorem that unfolds to the definition says nothing independent of the code).
* `## Specifications independent of the code?`: for each `C` theorem, is the right-hand side an independently
  written specification (a predicate/relation/reference function written separately, e.g. a regular-expression
  semantics) or a restatement of the implementation's own case split? Count both kinds.
* `## Docstring claims`: for every theorem docstring and every module header comment in your modules that makes a
  factual claim (about what is proved, about upstream behaviour, about what is not covered): verdict
  `correct | correct for the wrong reason | overstated | false | stale`, with the evidence (quote + line). List
  every claim that is not `correct` individually; give the count of claims checked and the count per verdict.
* `## manifest.yaml claims`: for every `manifest.yaml` entry whose `lean:` names live in the implementation files of
  your area and whose status is `proven`, or whose `notes:` name a theorem: does the theorem exist (name), does it
  state what the note says, and does `proven` fit (does the theorem determine the function's behaviour, or only one
  property of it)? Verdict per entry in the same vocabulary. Give counts per verdict.
* `## PROPERTIES.md claims`: `/home/user/halean/PROPERTIES.md` lists properties. For every row/claim that refers to
  theorems of your modules: verdict in the same vocabulary, with evidence. Give counts per verdict.

Write plainly: short sentences, no hedging adjectives, no marketing words. Every count must be reproducible from
your tsv. Your final message: the two file paths, the class counts (C/O/E/H), and the counts per verdict for
docstrings, manifest and PROPERTIES.md. Nothing else.
