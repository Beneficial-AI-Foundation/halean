# HALean: faithfulness and proof review

Reviewed commit: `f638a3779195a42a5162939aa67981b9b501618e` (`logs/halean-commit.txt`).
Reference: Home Assistant `2026.10.4` (commit `357cae5c598dfcd7a0ea7dc5b1facccd4ec6037b`, `logs/upstream-checkout.txt`), Jinja2 3.1.6, probatio 0.13.0 (`logs/ha-install.txt`). These are the pins in `manifest.yaml`.
All paths below are relative to `review/`. Every number points to a log, a data file or a case directory. Section 13 lists the commands that reproduce them.

## 1. Summary

**Question 1: is the translation faithful?** For the inputs the shipped tests use, yes. All shipped tests pass on two runs. Outside those inputs, no. Seven independent differential campaigns (new hand-written cases plus seeded random generators, run against real Home Assistant and HALean) found 144 distinct root causes. 46 of them are documented gaps or explicit refusals (section 6.9). The other 98 are in the bug list (section 2), together with 3 found while auditing `manifest.yaml`. 68 give a different answer with no error, 19 accept what HA refuses, 3 refuse what HA accepts without saying so in the README, and 11 are faults of the test harness or drivers. Two of them crash or stall the engine process: a float written with a huge exponent (SCH-1, TPL-47) aborts it. 54 bugs have a patch tested in a throwaway copy; the shipped tests still pass with the patches, but several patches make theorems of `HALean/` fail to build (section 6).

**Question 2: how useful are the proofs?** The proofs are sound as far as Lean goes: no `sorry`, no added axiom, no `native_decide`, only `propext`, `Classical.choice` and `Quot.sound` (section 4). What they say is narrow.
- Of 1,943 theorems written in the source, 86 are central specifications (class C), 661 one-operation properties (O), 381 edge cases (E) and 815 helper lemmas (H) (section 7). Of the 86 central specifications, 52 restate the implementation's own case split, 32 are independent of the code and 2 are in between (section 7.3).
- Definitions named in a class-C statement make up 5.7% of the implementation lines. Counting class-O statements too, 40.3% (section 9).
- 85 `partial def`s hold 1,999 lines. The kernel cannot unfold them, so no theorem constrains the template parser, the template evaluator, the JSON decoders or the schema evaluator.
- No theorem is about the observable behaviour of an entry point (`Engine.step`, `render`, `Hass.step`, `Helpers.call`) for a non-trivial input.
- The 2 `opaque` fuel constants of the engine mean no theorem can show that the engine's handlers do anything.

**Documentation.** Of 253 claims in `README.md`, 238 are correct, 8 overstated, 2 false, 2 stale, 3 not checkable here (section 10.1). Of 402 manifest entries, 322 are correct and 59 overstated, including 41 of the 53 entries with status `proven` (section 10.2). Of 1,471 theorem docstrings and module headers, 96 are overstated and 13 false (section 10.4).

**Table: new cases and divergences per area.** "Divergent cases" are cases that differ between HA and HALean on at least two runs. "Root causes" are the IDs in the area's `FINDINGS.md`.

| Area | New hand-written cases | Random cases per run | Runs | Divergent cases (per run) | Root causes | Findings |
|---|---|---|---|---|---|---|
| State machine and event bus | 139 (94 state, 45 bus) | 700 | 3 | 27 hand-written, 0 random | 12 | `experiments/03-core-states-bus/FINDINGS.md` |
| Service registry and joined core | 105 (+8 HA-only) | 1,600 | 2 | 9 hand-written, 0 random | 8 | `experiments/04-core-registry-hass/FINDINGS.md` |
| Service schemas | 32 cases, 547 data points | 2,060 schemas, 28,200 schema/data pairs | 3 | 9 hand-written; 66 random (runs 1, 2), 62 (run 3) | 6 | `experiments/05-service-schemas/FINDINGS.md` |
| Templates | 1,249 (+4 batch-only) | 6,000 | 2 | 696 (316 hand-written, 380 random) | 48 | `experiments/06-templates/FINDINGS.md` |
| Automation engine | 150 | 800 | 2 | 65 (51 hand-written, 14 random) | 26 | `experiments/07-automation/FINDINGS.md` |
| Scripts | 90 (+110 load-time entries) | 600 | 2 | 25 hand-written, 15 load-time, 157 random | 19 | `experiments/08-scripts/FINDINGS.md` |
| Helpers | 213 (640 steps) | 810 | 3 | 41 hand-written, 1 random | 25 | `experiments/09-helpers/FINDINGS.md` |
| Total | 1,978 | 12,570 (without the schema pairs) | | | 144 | |

The seven campaigns were run by seven separate review agents; each wrote its own `README.md`, `side-by-side.md` (upstream and Lean read side by side), cases, generator, logs and patches.
I re-ran a sample myself through the unmodified shipped harness (section 6.10).

## 2. Bug list

One row per bug. It leaves out documented gaps and explicit refusals (listed in section 6.9). "Patched" means a patch exists in `experiments/<area>/patches/`, was applied in a throwaway copy, and the shipped tests pass with it; `partial` means the patch fixes some of the cases. Kinds: Silent (different answer, no error), Accepts (HALean accepts what HA refuses), Refuses (HALean refuses what HA accepts), Order, Tooling (harness, driver, bridge). IDs `MAN-*` come from the claims audit (`experiments/12-claims/CLAIMS-MANIFEST-TRANSLATED.md`, rows M-8, M-17, M-80), not from a differential campaign; their probes are in `experiments/12-claims/logs-manifest/`.

| ID | Area | Bug | Kind | Patched |
|---|---|---|---|---|
| ST-1 | State machine | A JSON float of 1e16 or more is read as an int: state `1e+16` becomes `10000000000000000`, `1.5e+300` raises `InvalidStateError`, attribute equality is wrong both ways (`1e23` vs `10**23`). README 294-295 documents a narrower case. | Silent | no |
| ST-2 | State machine | State `-0.0` becomes `"0.0"`. | Silent | no |
| ST-3 | State machine | `async_set_internal` with a Unicode-digit id answers `InvalidEntityFormatError` (an HA error class) where HA creates the entity; the documented answer for non-ASCII ids is `unsupported`. | Refuses | yes |
| ST-6 | State machine | Driver reads a non-bool `force_update` (`1`) as false. | Tooling | yes |
| ST-10 | State machine | Lone surrogates become U+FFFD in the drivers, so different strings compare equal (state, attributes, event type). | Silent | no |
| BUS-1 | Event bus | Generated-context numbering counts events only HA's own listeners saw (`#1` where the harness has `#0`). | Tooling | yes |
| BUS-2 | Event bus | `Filter.eq` compares decimal text: `1e23 == 10**23` is true in HALean, false in Python. | Silent | no |
| REG-1 | Service registry | `ServiceNotFound` message: a domain containing `{service}` is substituted twice. | Silent | yes |
| REG-2 | Service registry | Driver keeps `Context(id="")` as id `''`; HA draws a fresh ULID. | Silent | yes |
| REG-3 | Service registry | Handler spec with more than one of `return`/`echo`/`raise`: driver and shipped harness pick different ones. | Tooling | yes |
| SCH-1 | Service schemas | `float()` of text with a huge exponent (`"1e9999999999"`) kills the engine process (`INTERNAL PANIC: Nat.pow exponent is too big`); HA returns `inf`. Same root cause as TPL-47. | Refuses | yes |
| SCH-3 | Service schemas | After a schema's 50th validation probatio's generated code raises `OverflowError` for `Coerce(float)` of an int ≥ 2^1024; HALean says `expected float`. README 648-652 says the generated path behaves like the interpreted one. | Silent | no |
| SCH-4 | Service schemas | `TypeError` text for a timedelta in `cv.entity_ids`: `'timedelta' object is not iterable` vs HA's `'datetime.timedelta' object is not iterable`. Theorem `pyIter_error` states the model's text. | Silent | yes |
| SCH-6 | Service schemas | Decoder accepts `at_least_one: []`; `probatio.AtLeastOne()` raises `SchemaError`. | Accepts | yes |
| TPL-1 | Templates | String escapes `\ooo`, `\u`, `\U`, `\N{}` are not decoded (Jinja literals and `literal_eval`). | Silent | partial |
| TPL-2 | Templates | Dict keys: equal keys are not merged; unhashable keys are accepted. | Silent | yes |
| TPL-3 | Templates | `dict.keys()/values()/items()` are lists (HA: `dict_keys(...)`). | Silent | no |
| TPL-4 | Templates | `bool()` of `states` / `states.<domain>` is always true and records no lifecycle; the `if value:` guard of map/select is missing. | Silent | yes |
| TPL-5 | Templates | `last` / `reverse` over states objects differ (HA: None or an error). | Silent | no |
| TPL-6 | Templates | The case-insensitive entity-id fallback of `hass.states.get` is missing in `states()`, `is_state`, `state_attr`, `has_value`, `states[...]`. | Silent | yes |
| TPL-7 | Templates | Float `sum` is not compensated (Python ≥ 3.12): `[0.1, 0.2, 0.3, 1e100, -1e100] \| sum` is 0.6 in HA, 0.0 in HALean. | Silent | yes |
| TPL-9 | Templates | Undefined inside a printed container prints as `''`, not `Undefined`. | Silent | yes |
| TPL-10 | Templates | Namespace `repr` differs. | Silent | no |
| TPL-11 | Templates | `loop` is a dict: repr, mapping test, length, iteration, `depth` differ; `cycle`/`changed` are missing; it is assignable. | Silent | no |
| TPL-12 | Templates | for-else: HA runs `else` unless an iteration reached the end of the body (break/continue); HALean does not. | Silent | yes |
| TPL-13 | Templates | Generators can be consumed twice. | Silent | no |
| TPL-14 | Templates | Generators are evaluated eagerly: errors and RenderInfo for unconsumed items. | Silent | no |
| TPL-15 | Templates | Tests `sequence` / `iterable` are wrong for range, generators, states, Undefined. | Silent | yes |
| TPL-16 | Templates | `float()` / `is_number`: whitespace (`\v`, `\f`, `\x1c`-`\x1f`, NBSP) and Unicode digits. | Silent | no |
| TPL-17 | Templates | `_parse_result`: `\d` matches Unicode digits in HA. | Silent | no |
| TPL-18 | Templates | Static templates are stripped with an ASCII-only `trim`. | Silent | no |
| TPL-19 | Templates | `title` filter: word break on `\s` vs four whitespace characters. | Silent | yes |
| TPL-20 | Templates | `str.split(None, maxsplit)` strips the remainder. | Silent | yes |
| TPL-21 | Templates | Float `//` and `%` with infinite operands. | Silent | yes |
| TPL-22 | Templates | `timestamp_custom` default format is `%Y-%m-%d` (HA: `%Y-%m-%d %H:%M:%S`). | Silent | yes |
| TPL-23 | Templates | `as_datetime('…T24:00:00')` gives None (ciso8601 gives the next day). The patch turns it into a refusal. | Silent | yes |
| TPL-24 | Templates | `strftime` `%Y` / `%F` are not zero-padded below year 1000. | Silent | yes |
| TPL-26 | Templates | JSON numbers with an exponent (`1e+20`) become ints (variables, attributes). Same root cause as ST-1. | Silent | no |
| TPL-28 | Templates | `literal_eval` results: set becomes a list; bytes, `...`, `set()` stay strings; a complex in a container is an error. | Silent | no |
| TPL-29 | Templates | `literal_eval` accepts nested unary signs inside containers. | Silent | yes |
| TPL-30 | Templates | Lexer accepts `.5` and `007`. | Accepts | yes |
| TPL-31 | Templates | Parser accepts invalid Jinja: a conditional expression in an `if` test, assignment to `none`/`true`/`loop`, break/continue outside a loop. | Accepts | partial |
| TPL-32 | Templates | `OverflowError` (int to float, float pow, round precision, timedelta range) and the 4300-digit int/str limit are not raised. | Accepts | partial |
| TPL-33 | Templates | Argument counts and keywords are not checked (filters, tests, functions, methods); `startswith(x, start)` ignores `start` (a different value). | Accepts | no |
| TPL-34 | Templates | A non-string / Undefined entity id returns False/None where HA raises. | Accepts | yes |
| TPL-35 | Templates | `sum(start='')` over strings is accepted. | Accepts | yes |
| TPL-36 | Templates | `timestamp_local/utc/custom` are accepted as global functions. | Accepts | yes |
| TPL-37 | Templates | Errors HA does not catch (`OverflowError`/`OSError` of `fromtimestamp`, Undefined) are treated as "use default". | Accepts | no |
| TPL-38 | Templates | Jinja compile-time constant folding: `'x' \| states` records no entity in HA; `'nan' \| float` in `set` is a NameError in HA. | Accepts | no |
| TPL-47 | Templates | Huge float exponent: `'1e1000000000' \| float` takes 27 s; `1e4000000000` aborts the engine. Same root cause as SCH-1. | Refuses | yes |
| AUT-1 | Automation engine | `restart` with a live run: HA starts the new run one loop iteration later; HALean starts it at once and runs extra actions. | Silent | partial |
| AUT-2 | Automation engine | State trigger `to`/`from: "*"` is match-all in HA, literal text in HALean. | Silent | yes |
| AUT-3 | Automation engine | Attribute values are compared by JSON equality, not Python `==` (`1 == True == 1.0`). | Silent | yes |
| AUT-4 | Automation engine | Entity ids in triggers/conditions are not lower-cased or validated. | Silent | yes |
| AUT-5 | Automation engine | A duplicate entry in `entity_id` / `at` / `event_type` fires twice in HA, once in HALean. | Silent | yes |
| AUT-6 | Automation engine | Static float `repeat.count`: `2.5` runs 25 times, `3.0` 30 times (HA: 2, 3). | Silent | yes |
| AUT-7 | Automation engine | `continue_on_error` / stop `error` given as `"true"` or `1` are false in HALean. | Silent | yes |
| AUT-8 | Automation engine | Assigning `repeat` inside a loop leaks to the run variables (HA: loop-local). | Silent | no |
| AUT-9 | Automation engine | A time / time_pattern trigger for the second the automations load in fires in HA, never in HALean. | Silent | no |
| AUT-10 | Automation engine | `initial_state: false` is ignored: the automation triggers. | Silent | yes |
| AUT-11 | Automation engine | HA caches condition checkers by `str()` of their values (`state: 1` and `state: "1"` share one); HALean evaluates each. | Silent | no |
| AUT-12 | Automation engine | `numeric_state` reads `"1_1"` and non-ASCII digits as non-numbers. | Silent | partial |
| AUT-14 | Automation engine | Configs HA's schemas reject are run: unknown keys, missing required keys, `trigger`+`triggers`, invalid condition forms, `above > below`, `from`+`not_from`, bad weekday, int trigger `id` (also seen for script actions: SCR-11). | Accepts | no |
| AUT-15 | Automation engine | Static time periods use an ad-hoc parser: accepts `{secs: 1}`, `{}`, `"0.5:00"`, `{weeks: 1}`; refuses `delay: true`. | Accepts | yes |
| AUT-16 | Automation engine | Two automations with the same `id` both run (HA ignores the second). | Accepts | no |
| AUT-21 | Automation engine | Shipped harness merges `data` over `target` (HA: target wins). | Tooling | no |
| AUT-22 | Automation engine | Harness `_walk_actions` misses mapping-form `action:` and list-form parallel branches (services unregistered, events unobserved). | Tooling | no |
| AUT-23 | Automation engine | Harness fires HA timers due in one tick in heap order and up to 0.5 s early. README 675-677 mentions part of it. | Tooling | no |
| AUT-24 | Automation engine | Scenario format lets a call with `response_variable` be answered `ok` without a response; HA raises. | Tooling | no |
| AUT-25 | Automation engine | `tests/run_scenarios.py::build` sends `state_changed` for a `set` that changes nothing; HA fires none. | Tooling | no |
| AUT-26 | Automation engine | A run restarted while its `parallel` branches are scheduled but not started: HA still runs each branch to its first wait; HALean drops them. | Silent | no |
| MAN-8 | Automation engine | Time condition with a timestamp sensor whose state is a date only (`2023-11-14`): HA says true, HALean silently says false. | Silent | no |
| MAN-17 | Automation engine | A call to a missing service with `continue_on_error: true`: HA ends the run (`ServiceNotFound` is in `CONFIGURATION_ERRORS`); the bridge reports `not_found` as `ha_error` and the engine goes on. The shipped live test asserts the HALean behaviour. | Silent | no |
| MAN-80 | Automation engine | A static `target.entity_id` is sent as written (`"Light.A, light.b"`); HA normalises it to `['light.a', 'light.b']` and rejects an invalid id at load. | Silent | no |
| SCR-1 | Scripts | `turn_on`/`turn_off`/`toggle` with an invalid `entity_id` fails with kind `other`; HA gives `invalid` (the kind decides whether `continue_on_error` applies). | Silent | yes |
| SCR-3 | Scripts | `metadata` of any type is accepted by `turn_on`; HA requires a dict. | Accepts | yes |
| SCR-4 | Scripts | `toggle` decides start/stop for every target before acting; HA reads `is_on` when each target's turn comes. | Silent | yes |
| SCR-5 | Scripts | A stop (`turn_off`, `toggle`, `restart`) is complete at once; in HA it takes event-loop iterations (other order, missing events, an extra run). | Silent | partial |
| SCR-6 | Scripts | A run stopped from inside its own `script.turn_on` step is reported cancelled; in HA it ends quietly and its caller goes on. | Silent | no |
| SCR-7 | Scripts | After the caller of a queued, waiting run is cancelled, HA keeps `current` one too high until the next write; HALean writes the exact count. | Silent | no |
| SCR-8 | Scripts | Reload is one atomic step; in HA a waiting script resumes mid-reload and its call of the changed script is `ServiceNotFound`. | Silent | no |
| SCR-9 | Scripts | `last_action` is readable by listing `states.script.x.attributes`; the load check only looks for the word. README 506 documents only the direct use. | Silent | no |
| SCR-15 | Scripts | A `script.*` service HALean does not own is sent to HA; the harness has no HA to answer. | Tooling | no |
| SCR-17 | Scripts | Two delays ending in the same harness tick: outcome and order follow asyncio's timer heap in the harness. | Tooling | no |
| SCR-18 | Scripts | A `result` step without `response` for a call that asked for one: the harness's HA handler returns `None` and HA raises. | Tooling | no |
| SCR-19 | Scripts | A run stopped in a top-level `parallel` step ends quietly; HA re-raises a finished branch's `stop` (response) or error. | Silent | yes |
| HLP-1 | Helpers | `entity_id: all` runs the service on the entities of every helper domain (`input_boolean.toggle` on `all` resets counters). | Silent | yes |
| HLP-2 | Helpers | `input_number`: HA keeps `-0.0` when `0.0` is set; HALean replaces it and fires `state_changed`. | Silent | yes |
| HLP-3 | Helpers | A state longer than 255 characters is `unknown` in HA; HALean writes it. | Silent | yes |
| HLP-4 | Helpers | `input_select`: the duplicate-options warning of a valid item is lost when another item makes the config invalid. | Silent | no |
| HLP-5 | Helpers | Pattern with a quantifier after `$` (`a$*`): Python raises, HALean accepts. | Accepts | yes |
| HLP-6 | Helpers | Pattern `{m}` / `{m,n}` with nothing to repeat: Python raises, HALean reads literals. | Accepts | yes |
| HLP-7 | Helpers | Pattern with a class escape before `-` in a set (`[\d-z]`): Python raises, HALean accepts. | Accepts | yes |
| HLP-8 | Helpers | Pattern `[]-a]`: a leading `]` starting a range is parsed as three literals. | Silent | yes |
| HLP-9 | Helpers | `\s` does not match U+001C..U+001F, which Python's `\s` matches. | Silent | yes |
| HLP-10 | Helpers | `input_text`: a non-ASCII initial or restored value against `\d \w \s` is matched with ASCII classes; the entity is silently not added. README 551 claims a refusal. | Silent | yes |
| HLP-11 | Helpers | `input_number` restore: `float()` of Unicode digits or `\x0b`/`\x0c` padding gives `min` instead of the value. | Silent | yes |
| HLP-13 | Helpers | Timer: start/change whose end leaves `datetime`'s range raises `OverflowError` in HA; HALean starts the timer. | Accepts | yes |
| HLP-14 | Helpers | Timer restore: a `last_transition` that is not a string is dropped; HA keeps it. | Silent | yes |
| HLP-15 | Helpers | `input_select` duplicate warning prints `''` instead of `<unnamed>` for `name: ""`. | Silent | yes |
| HLP-16 | Helpers | An empty config key `""`: HA adds no entity, HALean adds `input_boolean.`. | Accepts | yes |

Counts (`data/buglist-counts.txt`, built from `data/bugs.tsv` by `data/build_buglist.py`):

| area | Silent | Accepts | Refuses | Order | Tooling | total | patched yes | partial | no |
|---|---|---|---|---|---|---|---|---|---|
| State machine | 3 | 0 | 1 | 0 | 1 | 5 | 2 | 0 | 3 |
| Event bus | 1 | 0 | 0 | 0 | 1 | 2 | 1 | 0 | 1 |
| Service registry | 2 | 0 | 0 | 0 | 1 | 3 | 3 | 0 | 0 |
| Service schemas | 2 | 1 | 1 | 0 | 0 | 4 | 3 | 0 | 1 |
| Templates | 26 | 9 | 1 | 0 | 0 | 36 | 19 | 3 | 14 |
| Automation engine | 16 | 3 | 0 | 0 | 5 | 24 | 8 | 2 | 14 |
| Scripts | 8 | 1 | 0 | 0 | 3 | 12 | 4 | 1 | 7 |
| Helpers | 10 | 5 | 0 | 0 | 0 | 15 | 14 | 0 | 1 |
| ALL | 68 | 19 | 3 | 0 | 11 | 101 | 54 | 6 | 41 |

Where the 101 rows come from: 144 root causes in the seven `FINDINGS.md` files, minus 46 documented gaps and explicit refusals (`data/excluded.tsv`), plus 3 `MAN-*` rows. SCR-11 is counted under AUT-14 (same decoder). TPL-47 and SCH-1 share one cause (`parseFloatStr`, `HALean/Template/Value.lean:187-192`) and are both listed because the area reviewers reported them separately.

Patches change the proofs. The area reviewers report that patches for REG-1, REG-3, SCR-1, SCR-3, SCR-4, SCR-5, SCR-10 and the template and automation patch sets break theorems that state the old behaviour (`experiments/04-core-registry-hass/patches/`, `experiments/06-templates/patches/spec-build-with-all-patches.log` (17 theorems), `experiments/07-automation/patches/all-patches.lib-build.log` (33 errors in six proof files), `experiments/08-scripts/patches/per-patch-lake-build.log`). The shipped tests do not build the proof files that the executables do not import, so they do not notice. Some of the broken theorems state the divergent behaviour as correct, for example `isState_nonstr` (templates) and `ServiceRegistrySpec.formatPlaceholders_nil` (REG-1).

## 3. Build

- Toolchain: Lean 4.36.0 (`experiments/01-build-axioms/logs/toolchain.txt`). `releases.lean-lang.org` is not reachable from this machine; the toolchain was taken from the GitHub release and linked with `elan toolchain link`.
- `lake build HALean`: 198 jobs, success (`experiments/01-build-axioms/logs/build-lib.log`). The nine executables: 187 jobs, success (`build-exe.log`). Wall time 110 s. Peak memory 1.88 GB in a 16 GiB cgroup, limit never hit (`logs/memcap.txt`: `max_usage_in_bytes=1881616384`, `failcnt=0`).
- 12 lines of the library build log contain `warning` or `error`; all are linter warnings (unused `simp` arguments, one deprecation).
- 97 modules in `HALean/`; every one is imported by another module (check in `experiments/01-build-axioms/README.md` step list). 35,926 lines (26,331 without blank lines and comments) in `HALean/`, 714 code lines in `Exe/` (`experiments/11-coverage-drift/logs/coverage.txt`).
- What CI runs: `.github/workflows/lean_action_ci.yml` runs `lake build` of the library and eight executables on every push and pull request (not `halean-helpers`; `lakefile.toml` has no test driver, so no test runs). `binaries.yml` and `release.yml` run only after a merge to `master`: they build two executables and run `tests/run_scenarios.py` and `tests/run_script_scenarios.py`, then build the demo image and smoke-test it. No workflow runs the differential suite (the comparison with real Home Assistant), `bridge_e2e.py`, the sun comparison or `tests/live/docker_e2e.py`. The README says that pull requests run only the Lean build (line 214-215); that is correct. It does not say that the differential suite is never run in CI.

## 4. Axiom audit

`experiments/01-build-axioms/AxiomAudit.lean` walks every theorem of every `HALean.*` module in the compiled environment, including compiler-generated ones, and collects the axioms each depends on.

- 7,016 theorems: 1,943 written with the `theorem` keyword (`experiments/10-theorems/logs/inventory-summary.txt`), 5,073 generated or structure fields (`experiments/01-build-axioms/logs/axioms-by-area.txt`).
- Axiom sets of the 1,943: none 52; `propext` 111; `propext, Quot.sound` 367; `propext, Classical.choice, Quot.sound` 1,413. Generated theorems: none 843; `propext` 540; `propext, Quot.sound` 2,840; all three 850.
- 0 theorems depend on `sorryAx`. 0 `axiom` declarations in `HALean/`. No `native_decide`, `implemented_by`, `extern` or `sorry` in the sources (`experiments/01-build-axioms/logs/grep-audit.txt`). The word `admit` appears only as the name of the run-mode function `admit`. `unsafe` appears once, in a string.
- `Classical.choice` is used by 1,413 + 850 theorems; it is the standard classical axiom and comes from `simp`/`omega`/`decide` machinery, not from a declaration of this repository.
- 85 `partial def`s in `HALean/` (99 with `Exe/`): templates 49, service schemas 16, automation engine 11, helpers 6, event bus 1, service registry 1, scripts 1 (`experiments/11-coverage-drift/logs/coverage.txt`). 2 source `opaque` constants: `ENGINE_FUEL` and `LOOP_FUEL` (`HALean/Automation/Engine.lean:927,1029`). The environment holds 90 opaque constants in `HALean.*` modules (`logs/axiom-audit-run.log`); 3 of them are not attributed to a source declaration.
- A `partial def` is an opaque constant for the kernel. A theorem that mentions one holds for any function in its place (section 7).

## 5. Shipped tests

Three runs of the differential suite and two runs of every other test (`experiments/02-shipped-tests/logs/`).

| Test | Result, runs 1 and 2 | Log |
|---|---|---|
| `tests/run_scenarios.py` | 60/60 passed | `run{1,2}-scenarios.log` |
| `tests/run_script_scenarios.py` | 11/11 passed | `run{1,2}-script_scenarios.log` |
| `tests/bridge_e2e.py` | PASS | `run{1,2}-bridge_e2e.log` |
| `tests/sun/compare.py` (astral 2.2) | 3000/3000 match | `run{1,2}-sun.log` |
| `tests/differential/run.py` | 611 passed, 6 skipped, in all three runs | `run{1,2}-differential.log`, `run3-differential-venv-verbose.log` |
| `tests/live/docker_e2e.py` | 3/3 checks passed | `run{1,2}-live_docker.log` |

- The 6 skips each have a reason in the test code (`run3-differential-venv-verbose.log`): one test opt-out because the harness cannot model a 0 s timer, one where HA raises in a callback, three scenarios that only check HALean's refusal, one script scenario that checks rejections. 617 tests are collected (`logs/differential-test-counts.txt`).
- The live test needs `ghcr.io/home-assistant/home-assistant:2026.10.4`. The layer host of ghcr.io is blocked in this environment (`logs/live-ghcr-pull.log` records the first attempt). The layers were pulled from Docker Hub (`homeassistant/home-assistant:2026.10.4`); both names resolve to image id `sha256:23f4dfbb...` with label `io.hass.version=2026.10.4` (`logs/live-image.txt`). The test therefore ran against the pinned release.
- The live test asserts `continue_on_error` carries on past a missing service. Upstream does not swallow `ServiceNotFound` (`helpers/script.py:140-147, 633`), so the test pins HALean's behaviour, not HA's (MAN-17).

**Mutation checks of the README's sensitivity claims.** In throwaway copies, one change each.

| Claim | Mutation | Result | Evidence |
|---|---|---|---|
| README 115-116: a failing nested `condition` ending the whole run fails `nested_condition` | engine ends the run on a nested condition failure | 1 failing test in the scenario suite and 1 in the differential suite (`nested_condition`): claim holds | `experiments/07-automation/mutations/` |
| README 410-411: LIFO ready queue fails all 15 async cases | ready queue made LIFO | 15 of 38 `test_core` cases fail (+3 teardown errors): holds | `experiments/04-core-registry-hass/mutations/` |
| README 411-412: freeing a failed task at its done callback fails 3 | as stated | 3 fail: holds | same |
| README 413: dropping `async_block_till_done`'s first `sleep(0)` fails 1 | as stated | 1 fails: holds | same |
| (new) admission `existing > maxRuns` instead of `=` | | does not build without removing a proof import (`Automation/Proofs.lean:79,84` fail); with the import removed, 2 scenario and 2 differential tests fail | `experiments/07-automation/mutations/` |
| (new) `or` counts a disabled condition as true | | 0 failing in both suites; caught only by `ConditionSpec.lean` in the library build; a new case (`cond_disabled_members`) catches it against HA | same |
| (new) repeat limit 10,000 raised to 1,000,000,000 | | 0 failing in both suites; no proof catches it; README 257-270 says a scenario covers it; none exists | same |

## 6. Faithfulness per area

Method per area: read the upstream function and the Lean definition side by side for every manifest entry of the area (`experiments/<area>/side-by-side.md`); write new hand-written cases; run a seeded random generator; run all of it through a copy of the shipped differential harness against real Home Assistant 2026.10.4 and the unpatched executables; at least two runs; minimise each divergence; classify; check the README; patch where small and rerun the shipped tests. A divergence is reported only if it was present in every run (each `FINDINGS.md`, section Counts). Harness copies differ from the shipped ones only in the case directory, the engine path and optional result dumps (each area's README). Details, minimal reproducers and both results are in each area's `FINDINGS.md`; the table below gives the headline of each area.

### 6.1 State machine and event bus (`experiments/03-core-states-bus/`)
139 hand-written cases, 700 random sequences per run (8,265 state operations; 5,799 bus operations with 356,186 deliveries for the first seeds), 3 runs. 27 hand-written cases diverge in all three runs; 0 of 700 random sequences diverge. The random pools exclude the inputs behind the known divergences. ASCII ids, finite JSON values and floats below 1e16 agree. Differences are at the JSON boundary: floats of 1e16 or more become ints (ST-1, also BUS-2), `-0.0` becomes `0.0` (ST-2), lone surrogates collapse (ST-10); plus two driver faults (ST-6, BUS-1) and an answer of the wrong form for a documented refusal (ST-3). Patched: ST-3, ST-6, BUS-1 (`patches/`; `logs/patch-shipped-tests.log`: 94 passed).

### 6.2 Service registry and joined core (`experiments/04-core-registry-hass/`)
105 hand-written cases, 1,600 random cases per run, 2 runs. 9 hand-written cases diverge; 0 random. 140 of 13,634 random core operations were answered `unsupported`, all for two documented reasons. The scheduler model (FIFO ready queue, eager tasks, futures, `block_till_done`) matched HA on every random sequence. Bugs: REG-1 (a domain containing `{service}` is substituted twice in the `ServiceNotFound` message), REG-2, REG-3. The README's reason for the nesting limit is wrong: HA returns normally at 33, 41 and 151 nested calls and raises `RecursionError` near 191 (HASS-1).

### 6.3 Service schemas (`experiments/05-service-schemas/`)
32 case files with 547 data points; 2,060 random schemas with 28,200 schema/data pairs per run; 3 runs (seeds 101-103 twice, 201-203 once). 9 hand-written and 62-66 random cases diverge; 1,403 random operations were documented refusals; 0 unclassified. 6 root causes; the engine process dies on `float("1e9999999999")` (SCH-1; reproduced by me through `halean-template`, `INTERNAL PANIC: Nat.pow exponent is too big`).

### 6.4 Templates (`experiments/06-templates/`)
1,249 hand-written cases, 6,000 random templates per run, 2 runs (random outputs byte-identical across runs). 696 divergent cases per run in 48 root causes: 26 Silent, 9 Accepts, 14 Refuses (with 3 documented), plus harness-visible RenderInfo differences. Typical Silent causes: float `sum` is not compensated, for-else, `dict.keys()` printed as a list, the case-insensitive entity-id fallback missing, string escapes not decoded, `timestamp_custom` default format. The refusals are explicit (HALean says it does not support the construct); 6 are undocumented and 2 partly documented (section 6.9). 22 patches tested together: the shipped template suite passes (361), the whole differential suite passes (611/6 skipped).

### 6.5 Automation engine (`experiments/07-automation/`)
150 hand-written scenarios, 800 random scenarios per run (seeds 101, 202 default; 303 `modes`), 2 runs; 65 divergent cases (51 + 14) in 26 root causes, 21 in the Lean model and 5 in the harness. Notable: a restarted run starts too early (AUT-1), `to: "*"` is literal (AUT-2), attribute equality is JSON equality (AUT-3), a static float `repeat.count` of 2.5 runs 25 times (AUT-6), `initial_state: false` is ignored (AUT-10), configs HA rejects are run (AUT-14). The harness copy reports what the shipped harness cannot observe (section Notes on the harness).

### 6.6 Scripts (`experiments/08-scripts/`)
90 hand-written scenarios and 110 load-time matrix entries, 600 random scenarios per run, 2 runs. 25 hand-written scenarios, 15 matrix entries and 157 random scenarios diverge (84 + 73); 78 of the random failures are the documented `turn_on` gap (SCR-13). 19 root causes. The largest class is that a stop (`turn_off`, `toggle`, `restart`) takes event-loop iterations in HA and is instant in HALean (SCR-5, SCR-6, SCR-19). Unclassified: 26 + 23 random `other` cases were not all minimised, and 16 `ha-indexerror` cases were not looked at one by one (`FINDINGS.md`, section Counts); a root cause that only they show cannot be excluded.

### 6.7 Helpers (`experiments/09-helpers/`)
213 hand-written cases (640 steps), 810 random cases per run, 3 runs. 41 hand-written cases diverge in all runs; 1 random case per run (HLP-4). 25 root causes. The `input_text` pattern matcher (`Helpers/Pattern.lean`, 6 `partial def`s) differs from Python's `re` in 7 ways (HLP-5 to HLP-9, HLP-17, plus non-ASCII). `entity_id: all` hits every helper domain (HLP-1). 14 of the 15 listed bugs are patched; the shipped `test_helpers.py` still passes with the patches (57 passed).

### 6.8 What the shipped harness cannot observe
From the "Notes on the harness" section of each `FINDINGS.md`: dict key order (state, bus), numeric type of event data in the bus harness (`1`, `1.0`, `True` compare equal), anything inside one clock instant (the clock is frozen per operation), the order between the three streams of the automation harness, load-time rejection of invalid configs (scripts: not compared at all), HALean's own logs, `last_action`, intermediate state writes, `unsupported: true` operations (never run on HA, so HA's answer is not checked), inputs for which HA raises a non-`HomeAssistantError`, and HA timers due in one tick (heap order, not stable between sessions, AUT-23, SCR-17).

### 6.9 Documented gaps and explicit refusals (left out of the bug list)
| ID | Area | What | Kind | Status | README |
|---|---|---|---|---|---|
| ST-4 | State machine | A dict state prints with sorted keys. | Silent | documented | README 294, 653 |
| ST-5 | State machine | `repr` of non-printable non-ASCII characters inside a list or dict state is not escaped (same root as SCH-2, TPL-8, HLP-25). | Silent | documented (in the registry section) | README 348-349 |
| ST-7 | State machine | Instants after 2242-03-16 (2^33 s): HA's float timestamp rounds to another microsecond. | Silent | documented | README 290-291 |
| ST-8 | State machine | `NaN`/`Infinity` attribute values answered `unsupported`. | Refuses | documented | README 288, 350 |
| ST-9 | State machine | Non-ASCII ids and `str` domain filters answered `unsupported`. | Refuses | documented | README 288 |
| REG-4 | Service registry | Falsy non-dict `data`/`target` (`[]`) refused. | Refuses | documented | README 339 |
| HASS-1 | Joined core | Service calls nested deeper than 32 refused. The README's reason is wrong: HA returns normally at 33, 41 and 151 nested calls. | Refuses | documented (reason false) | README 429 |
| HASS-2 | Joined core | Core driver refuses a context with an empty id; HA accepts it. | Refuses | undocumented explicit refusal | none |
| HASS-3 | Joined core | A future resolved twice is refused. | Refuses | documented | README 429 |
| HASS-4 | Joined core | Two failed tasks freed by one `block_till_done` check are refused. | Refuses | documented | README 429 |
| SCH-2 | Service schemas | `repr()` of non-printable non-ASCII characters not escaped. | Silent | documented | README 348-349 |
| SCH-5 | Service schemas | `cv.slug` answers `unsupported` for any text with both `&` and `;`, although it holds no HTML entity. | Refuses | partly documented | README 335 |
| TPL-8 | Templates | `repr(str)` does not escape non-printable non-ASCII characters. | Silent | documented for another area, not for templates | README 349 |
| TPL-25 | Templates | Only the current UTC offset is used (DST, old dates). | Silent | documented | README 662-665 |
| TPL-27 | Templates | Attribute and variable dict key order is sorted. | Order | documented | README 653-656 |
| TPL-39 | Templates | Valid Jinja rejected at load: `0x`/`0o`/`0b` ints, `seq.0`, `+%}`, `\v`/`\f`, non-ASCII names, parenthesised targets, `recursive`, block set, `*args`. | Refuses | undocumented explicit refusal | none |
| TPL-40 | Templates | Python methods, attributes and operators not modelled (str/list/dict/int methods, `%` formatting, `tuple * int`). | Refuses | undocumented explicit refusal | manifest notes only |
| TPL-41 | Templates | Argument forms not modelled: `int(base=)`, `join`/`sum(attribute=)`, positional `dict()`/`namespace()`, big `**`, complex, range slicing. | Refuses | undocumented explicit refusal | manifest notes only |
| TPL-42 | Templates | datetime methods, `strftime` directives and flags, `isoformat(timespec=)`, naive timestamps. | Refuses | partly documented | README 248-249 |
| TPL-43 | Templates | Date strings only ciso8601 parses (`2026-11-20`, compact, `z`, comma fraction). | Refuses | undocumented explicit refusal | manifest note only |
| TPL-44 | Templates | Printing state objects, `states`, functions, datetime inside containers. | Refuses | partly documented (generators only) | README 250-251 |
| TPL-45 | Templates | HA gives Undefined or the default, HALean raises (first/last/reverse of Undefined, `as_datetime('nan')`, slicing an int). | Refuses | undocumented explicit refusal | none |
| TPL-46 | Templates | Non-ASCII case mapping is a render error. | Refuses | documented | README 252-254 |
| TPL-48 | Templates | Step budget of 1,000,000 iterations per render (HA has none). | Refuses | undocumented explicit refusal | none |
| AUT-13 | Automation engine | A template using an undefined name (incl. `context`, `x | default(...)`) makes the automation `unsupported`. | Refuses | undocumented explicit refusal | none |
| AUT-17 | Automation engine | A `parallel` branch written as a list of actions is `unsupported`. | Refuses | undocumented explicit refusal | none |
| AUT-18 | Automation engine | `stop:` with null is `unsupported`. | Refuses | undocumented explicit refusal | none |
| AUT-19 | Automation engine | time_pattern values `" 26 "`, `"+27"`, `28.0` are `unsupported`. | Refuses | undocumented explicit refusal | none |
| AUT-20 | Automation engine | A nested `triggers:` list is `unsupported`. | Refuses | undocumented explicit refusal | none |
| SCR-2 | Scripts | Outside calls with `group.*`, `area_id` or `device_id` fail. | Refuses | partly documented | README 492 |
| SCR-10 | Scripts | Values HA coerces (`alias: true`, `required: "yes"`, `stored_traces: "5"`, ...) are rejected at load. | Refuses | undocumented explicit refusal | none |
| SCR-11 | Scripts | An action with an extra key is loaded (same root cause as AUT-14). | Accepts | counted under AUT-14 | none |
| SCR-12 | Scripts | Invalid field selectors are loaded. | Accepts | documented | README 515 |
| SCR-13 | Scripts | `turn_on` of a script that does not start fails at once; HA waits. | Refuses | documented | README 510-512 |
| SCR-14 | Scripts | The run variable `context` is a render error on any use. | Silent | documented | README 492 |
| SCR-16 | Scripts | Reload compares config text. | Silent | documented | README 515-516 |
| HLP-12 | Helpers | Counter restore with Unicode digits is refused; HA restores 42. | Refuses | partly documented | README 552 |
| HLP-17 | Helpers | A pattern with a literal `{` after a repeat is refused; HA accepts it. | Refuses | undocumented explicit refusal | none |
| HLP-18 | Helpers | The JSON driver refuses `NaN`/`Infinity`. | Tooling | documented | README 350 |
| HLP-19 | Helpers | Non-ASCII text read by a text-handling validator is refused. | Refuses | documented | README 335 |
| HLP-20 | Helpers | Durations whose `timedelta` overflows or is NaN are refused. | Refuses | documented | README 335 |
| HLP-21 | Helpers | Timers due in the same tick finish in entity order; HA finishes them in time order. | Order | documented | README 573 |
| HLP-22 | Helpers | A second `setup` of a domain is refused; HA returns True. | Refuses | undocumented explicit refusal | none |
| HLP-23 | Helpers | A pattern Python rejects makes the whole setup refused; HA leaves only that entity out. | Refuses | documented loosely | README 551 |
| HLP-24 | Helpers | Timer restore with a last state other than idle/paused/active is refused. | Refuses | partly documented | README 553 |
| HLP-25 | Helpers | `repr()` of a non-printable non-ASCII character in attributes is not escaped. | Silent | documented | README 349 |

Counts (`data/excluded.tsv`): 46 rows; 22 documented, 1 documented loosely, 1 documented for another area, 6 partly documented, 15 undocumented explicit refusals (HALean answers `unsupported` or a render error), 1 counted under AUT-14. Two documented rows carry wrong reasons or understate the behaviour: HASS-1 (the stated reason is false) and ST-1 (README 294-295 names a narrower case; it is in the bug list).

### 6.10 My own re-check
`experiments/13-verification/`: 20 template reproducers (including a control) in 2 runs: 16 diverge in both runs, 4 agree (`logs/templates-run{1,2}.log`); 7 automation scenarios, 5 state/bus/schema/registry/helper case files (145 tests) through an unmodified copy of the shipped harness, twice: 7 and 38 failures, the same ids both times (`logs/automation-shipped-harness-run{1,2}.log`, `logs/core-helpers-shipped-harness-run{1,2}.log`). I also confirmed `ServiceNotFound` in `CONFIGURATION_ERRORS` in the upstream source and the template engine abort by hand.

## 7. What the theorems say

Method: `Inventory.lean` reads every source declaration from the compiled environment (`experiments/10-theorems/logs/decls.tsv`); `inventory.py` joins it with the source to get proof and statement lengths (`logs/theorems.tsv`: 1,943 theorems, 11,762 proof lines). Six reviewers read every statement in the source and classified it (`class/<area>.tsv`, validated by `classify_summary.py`: 1,943 classified, 0 missing, 0 duplicates). The classes:
C central specification: determines the result of a translated function over its domain. O one-operation property: holds for all inputs of a class but does not determine the result. E edge case: one concrete input or one constructor. H helper lemma.

### 7.1 Counts and proof lengths (`experiments/10-theorems/logs/classification-summary.txt`)

| Class | Theorems | Proof lines (total) | Median | Mean | Max | 1-line proofs |
|---|---|---|---|---|---|---|
| C | 86 | 884 | 6 | 10.3 | 48 | 3 |
| O | 661 | 4,931 | 4 | 7.5 | 178 | 54 |
| E | 381 | 855 | 2 | 2.2 | 13 | 154 |
| H | 815 | 5,092 | 4 | 6.2 | 51 | 134 |
| all | 1,943 | 11,762 | 3 | 6.1 | 178 | 345 |

Per area (C / O / E / H): state machine 6/73/16/41; event bus 0/33/7/101; service registry 4/41/7/31; joined core 0/24/5/83; service schemas 12/77/82/125; templates 24/121/118/172; automation engine 35/202/138/230; scripts 5/68/8/29; helpers 0/22/0/3 (`experiments/11-coverage-drift/logs/coverage.txt`).

### 7.2 What they constrain
Each `experiments/10-theorems/class/<area>.md` section "What the theorems constrain" names them. In summary:
- Exact specifications exist for small pure functions: entity-id and domain syntax against a regex written clause by clause (`validEntityId_iff`, `validDomain_iff`), `str.partition`, Python `int()` on ASCII text (`parseIntChars_iff`), `cv.boolean` on strings, `cv.slug` (`slugify_fixed_iff`), run-mode admission (`admit_*_iff`, which restate the `if` chain), the condition combinators relative to their members, calendar arithmetic, sun and location control flow.
- Invariants: at most `max` runs of an automation exist after any sequence of inputs (`runs_bounded`; holds for engines without scripts and with decoder-checked `max ≥ 1`), event-bus invariants (`once_at_most_once`, `reachable_wf`, `unsub_silent`), ready-queue prefix property and `blockTillDone_no_tasks` (under the hypothesis that the operation returns `ok`).
- Case statements: "if rendering returned X then ..." for triggers and the script executor.

### 7.3 What they do not constrain
- **Partial definitions.** 85 `partial def`s, 1,999 code lines, are opaque. 5,572 of 9,644 definition lines are in a partial def or call one (`coverage.txt`). Templates: the parser (20 partial defs) and evaluator (18) appear in no theorem statement; only `pyEq` appears, in 7 theorems, as an unknown function. No theorem says what any non-static template renders to. Service schemas: 15 of 17 partial defs, including the evaluators `runMapping`, `runAll`, `runAny`, appear in no statement; `Validator.run` appears in 7 theorems that describe the wrapper for any evaluator. Automation: `decodeCondition`, `decodeAction`, `decodeComplex` are partial; there is no theorem about them and none about `decodeAutomation`.
- **Entry points.** No theorem gives the commands `Engine.step` produces for a `stateChanged`, `event`, `tick`, `mqtt`, `webhook` or `serviceResult` input; the only exact `Engine.step` theorems are for `init`. No theorem about `EventBus.step (.fire ..)` (who receives what, in which order), `Hass.step (.act ..)`, `Helpers.call`, `Helpers.setup`, or `render` of a non-static template.
- **The engine's fuel.** `ENGINE_FUEL` and `LOOP_FUEL` are `opaque`; the kernel cannot prove they are non-zero (`example : LOOP_FUEL ≠ 0 := by decide` fails). Every theorem about `drive`, `step` and `Engine.step` holds for an engine whose handlers only log; `runs_bounded` is true of such an engine. No theorem rules out the "fuel ran out" branches. `STEP_FUEL` (1,000,000, a plain `def`) is reachable by valid scripts: `repeat count 400000` over `delay 0` ends with "step budget exhausted" (`class/automation-engine.md`).
- **Helpers.** 25 theorems for 1,087 implementation lines. No theorem about any helper's services, restore, state formatting or timer behaviour; `Pattern.lean`, `InputText`, `Timer` have none.
- **Float.** Basic `Float` arithmetic is kernel-evaluable on this toolchain; `sin`, `cos`, `atan`, `floor`, `round` are opaque (`class/automation-other.md`, checks in `class/scratch/`). The sun, location and time-period theorems prove control flow, not numeric results.
- **Specifications written from upstream.** Of the 86 class-C theorems, 32 have a right-hand side written separately from the implementation, 52 restate the implementation's own condition or case split, and 2 are in between (per area, independent / restatement / between: automation-engine 0 / 9 / 2; automation-other 12 / 12 / 0; core-registry-schemas 5 / 11 / 0; core-states-bus-hass 3 / 3 / 0; templates 11 / 13 / 0; scripts-helpers 1 / 4 / 0; from each `class/<area>.md`, section "Specifications independent of the code?"). "Independent" means a separately written predicate or reference, not a specification derived from the upstream source.

### 7.4 Assumptions that nothing checks
Each area file lists theorems whose hypotheses nothing discharges for the values the running code produces. The main cases:
- `runs_bounded` needs `Input.ok` (every automation's `maxRuns ≥ 1`). The decoder enforces it (`maxRunsOf` refuses values below 2), but no theorem states that `decodeInput` yields an `Input.ok`. With script entities the bound is not proved at all (the invariant includes `scripts = []`); `HALean/Script/Service.lean` sets `scripts`.
- Many theorems take `pyEq a b = true`, `safeValue v = true` or `Value.ofJson v` results as hypotheses. These cannot be proved for any concrete value because the functions are opaque. Examples: `isState_true`, `pyInt?_str`, `cvEntityId_ok` and the `cvEntity*` family, `set_same_only_reports` (its hypothesis `attrsEq .. = true` cannot be shown for identical attributes), `onEvent_no_match`.
- `withRun_fresh`, `addPeriodPending_fresh`, `fire_wait_quiet`, `replaceRun_find_same`: freshness and distinctness assumed about engine state, proved to be kept only by one operation, not by the others that also allocate ids or append.
- The decoder hypothesis `Json.parse line >>= decodeInput` is a hypothesis in all `processLine_*` theorems; nothing is proved about which lines parse. The bridge (`bridge/bridge.py`) and the drivers in `Exe/` are unverified Python and Lean with no theorem.
- Restatements: 18 engine theorems are proved by `rfl` and restate a definition (`testConditions_nil`, `exec_loop_zero`, `Cmd.toJson_callDone_ok`, ...); the automation-other file lists 17 more; the schemas file lists restatements for 11 `C` theorems.

## 8. Per-module theorem counts

Per module counts are in `experiments/10-theorems/logs/classification-summary.txt` (51 modules). Where a theorem states a behaviour HA does not have, the proof verifies the model, not the upstream function. SCH-4 is the clearest case: theorem `pyIter_error` proves the wrong `TypeError` text. Per-area details (what is constrained, what is not, assumptions, independence of specifications) are in `experiments/10-theorems/class/<area>.md`.

## 9. Coverage

Per area. Code lines exclude blank lines and comments. "Implementation" = files without theorems; "proof" = Spec/Proofs/Bound files. "Direct %" = share of definition lines (def, partial, opaque, instance; types excluded) whose name occurs in the statement of at least one class C or O theorem. "C only %" counts class C only. "Reach %" adds the callees reachable through non-partial definitions (an upper bound). A partial def is never counted as covered. Definitions in `coverage.py`'s docstring; output `experiments/11-coverage-drift/logs/coverage.txt`.

| Area | Impl lines | Proof lines | Theorems | Partial defs (lines) | Def lines | Lines in or calling a partial def | Direct % | C only % | Reach % |
|---|---|---|---|---|---|---|---|---|---|
| State machine | 344 | 1,195 | 136 | 0 | 282 | 53 | 89.7 | 14.9 | 98.6 |
| Event bus | 340 | 1,390 | 141 | 1 (17) | 244 | 86 | 59.4 | 0.0 | 93.0 |
| Service registry | 249 | 660 | 83 | 1 (5) | 191 | 62 | 81.7 | 17.3 | 93.2 |
| Joined core | 500 | 1,134 | 112 | 0 | 410 | 295 | 74.1 | 0.0 | 99.0 |
| Service schemas | 1,064 | 1,838 | 296 | 16 (292) | 958 | 574 | 35.5 | 7.8 | 45.8 |
| Templates | 3,370 | 2,896 | 435 | 49 (1,349) | 3,172 | 1,948 | 18.6 | 4.5 | 34.9 |
| Automation engine | 3,449 | 4,954 | 605 | 11 (250) | 3,076 | 1,960 | 54.8 | 7.0 | 89.7 |
| Scripts | 450 | 1,220 | 110 | 1 (5) | 402 | 250 | 85.8 | 10.0 | 98.3 |
| Helpers | 1,087 | 166 | 25 | 6 (81) | 909 | 344 | 7.3 | 0.0 | 8.5 |
| Total | 10,853 | 15,453 | 1,943 | 85 (1,999) | 9,644 | 5,572 | 40.3 | 5.7 | 60.8 |

Outside the table: 25 lines in the four umbrella modules; 714 lines in `Exe/` (9 drivers, 14 partial defs, no theorems).

Reading the table: the "reach" figure is high for the core and scripts because most of their definitions are small and called from theorem statements. It says a definition is mentioned in a theorem, not that its behaviour is fixed: of the "direct" lines, most are named only by an invariant-preservation (`Pres.*`) theorem. The proof volume is 15,453 lines against 10,853 lines of implementation, but 815 of the 1,943 theorems are helper lemmas.

### 9.1 Drift tool (`tools/drift.py`)
`experiments/11-coverage-drift/`. On the pristine tree: 402 entries, 0 stale, 0 missing; `compare` against the installed `homeassistant` package: 363 of 363 mapped functions identical (`logs/drift-check-pristine.log`, `drift-compare-installed.log`). Coverage: 360 of 1,668 functions in the tracked files are mapped (`logs/drift-coverage.log`).

Blind spots, tested by editing a copy of the upstream tree and running `check` (`drift_blindspots.sh`, `logs/drift-blindspots.log`):

| Edit | Flagged |
|---|---|
| control: `>` to `>=` in a mapped function (`validate_state`) | yes (STALE) |
| control: a comment added inside a mapped function | no (as designed) |
| `MAX_LENGTH_STATE_STATE` 255 to 256 (`const.py`) | no |
| `MAX_LENGTH_EVENT_EVENT_TYPE` 64 to 32 | no |
| `_MAX_QUEUED_EVENT_DISPATCHES` 10,000 to 5 | no |
| `_OBJECT_ID` regex of `VALID_ENTITY_ID` (used by `valid_entity_id`, status `proven`) | no |
| `REPEAT_TERMINATE_ITERATIONS` 10,000 to 10 | no |
| `DEFAULT_MAX` 10 to 3 | no |
| `NUMERIC_STATE_CONDITION_SCHEMA` changed (module-level assignment, not a `def`) | no |
| unmapped helper `is_callback` made to return False (called by a mapped function) | no |

9 of the 10 edits go unnoticed. The tool hashes only the AST of the mapped function or class. Of 363 mapped HA functions, 245 read something it does not hash: unmapped same-file functions (106 entries), unmapped methods of the same class (56), module-level assignments (121 entries, 185 names), names imported from `const` (110 entries, 225 names) (`experiments/11-coverage-drift/logs/untracked-deps.log`). A change in `const.py` is invisible because no `const.py` entry exists. Further structural facts: 6 Lean names in `manifest.yaml` name no declaration (`logs/manifest-names.log`; the functions were renamed `...H`), 4 refs resolve to `@overload` stubs so the hash is the stub's (M-76, M-107, M-239, M-305), 8 entries map classes, one Lean name is shared by up to 20 entries (`Automation.step`).

## 10. Claims audit

Verdicts: correct, correct for the wrong reason, overstated, false, stale. Every verdict has evidence in the file named.

### 10.1 `README.md` (`experiments/12-claims/CLAIMS-README.md`, 253 claims)

| Verdict | Claims |
|---|---|
| correct | 238 |
| overstated | 8 |
| false | 2 |
| stale | 2 |
| not checkable here | 3 |

Not correct: R-15 (one bridge for all services: it starts only `halean-automation` or `halean-script`); R-28 (drift "shows exactly which translations need revisiting": see 9.1); R-29 ("versioned wire protocol": no message carries a version, nothing reads `protocol/schema.json`); **R-30 false** (Setup block exports `ELAN_HOME=/Volumes/MacStorage/...`, a path on the author's machine); R-44 (the live test checks only that the target is still off about 1 s after a `for: 2s` trigger); R-56 ("every test exercises exactly the code that was translated": the sun test compares against its own copy, the scenario runners and `bridge_e2e` run no upstream code); **R-60 stale** (the sparse-checkout command misses files of 18 manifest entries: `components/mqtt/`, `components/webhook/`, `components/tag/trigger.py`, `exceptions.py`); **R-113 false** (`max_exceeded` log levels listed as rejected at load; they load and the key is ignored); R-131 (README 257-258 says each kept behaviour is covered by a scenario; the 10,000-iteration repeat limit, a `condition` inside `if`/`repeat`, a disabled condition inside `and`/`or`/`not`, a `while` whose condition raises have none); R-148 (the float gap is wider: `1.0e16`, `1e+16`, `1.5e3` also read as ints); R-162 stale (`cv.icon` listed as rejected since `eaee9a4` it validates); R-242 (402 "upstream functions": 394 functions or methods and 8 classes, 39 of them probatio). Also from the area reviews: README 429 gives a false reason for the nesting limit (HASS-1); README 551 says patterns outside the regex subset are refused, but `input_text` initial and restored values are not refused (HLP-10); README 294-295 understates ST-1.

### 10.2 `manifest.yaml` (402 entries)

| Verdict | `proven` (53) | `translated` (349) | all |
|---|---|---|---|
| correct | 6 | 316 | 322 |
| correct for the wrong reason | 6 | 3 | 9 |
| overstated | 41 | 18 | 59 |
| false | 0 | 2 | 2 |
| stale | 0 | 10 | 10 |

Files: `experiments/12-claims/CLAIMS-MANIFEST-PROVEN.md`, `CLAIMS-MANIFEST-TRANSLATED.md`. A `proven` entry is judged correct only if the cited theorems determine the function's result. 41 of the 53 cite edge cases or properties (for example `Script.async_run` cites four theorems about `admit`). The 10 stale entries: 7 name Lean definitions that no longer exist (`finishBranch`, `startScript`, `continueNow`, `answer`, `releaseQueue`, `cancelRun`, removed in commit `bf053c0`) and 3 have notes that describe an earlier state (templated `for`, `trigger_variables`, `last_changed`). The 2 false: M-274 ("Executor is rejected": nothing rejects it) and M-281 (a translated `cv` function does raise `ValueError` for `"0:0:nan"`). The 3 correct-for-the-wrong-reason entries from the translated set hash an `@overload` stub. Limits: for entries without notes in the template, core, schema and helper areas the verdict rests on structure checks and the area reviewers' side-by-side tables; M-50 (paho) and M-167 (Vincenty) were not compared with the libraries.

### 10.3 `PROPERTIES.md` (117 claims, `CLAIMS-PROPERTIES.md`)
Correct 89, overstated 22, false 2, stale 4. 83 judged by the theorem reviewers, 34 by the consolidator. False: P-3 (the model paragraph says `Cmd` is only call a service, fire an event or log; `Cmd` also has `automationTriggered`, `setState`, `callDone`) and P-69 ("`Engine.lean` has no `partial` definitions any more"; `partial def eventDataMatches`, `Engine.lean:1410`).

### 10.4 Theorem docstrings and module headers (`CLAIMS-DOCSTRINGS.md`, 1,471 claims)
Correct 1,359, overstated 96, false 13, stale 2, correct for the wrong reason 1. By area: automation-engine 256 checked (10 overstated, 1 stale); automation-other 189 (9 overstated, 3 false, 1 wrong reason); core-registry-schemas 311 (16, 3 false); core-states-bus-hass 227 (11, 4 false); scripts-helpers 124 (21 overstated); templates 364 (28, 4 false, 1 stale). One reviewed `false` claim was downgraded to `overstated` after a second reading (`isScalar_label`). The 13 false ones are listed with quotes in `CLAIMS-DOCSTRINGS.md`. Related README item (not in these counts): README 390-391 says the scheduler's theorems cover FIFO; `runHandle_fifo` and `resume_main_fifo` are one-handle queue-prefix statements and no theorem covers `runLoop` order (`experiments/10-theorems/class/core-states-bus-hass.md`), so the claim is overstated.

## 11. Conclusions

1. The translation is faithful in its core and for ordinary inputs. Every shipped test passes; the scheduler model, the state machine, the registry and the bus matched HA on 700 + 1,600 random sequences each with no divergence outside the inputs excluded after the hand-written cases found them. Faithfulness fails at the edges: number parsing (floats at 1e16 and above, `-0.0`), Unicode, argument checking, error kinds, and the timing of stops and restarts.
2. The template engine has the widest gap: 36 bugs in the list and 6 undocumented refusals (2 more are partly documented). Its 49 `partial def`s are also where the proofs say least. The automation engine has 21 bugs in the list, scripts 12, helpers 15.
3. 19 bugs make HALean accept what HA rejects. Config validation is looser than HA's in the automation engine (AUT-14, AUT-15, AUT-16), the template parser (TPL-30 to TPL-38) and the pattern matcher (HLP-5 to HLP-7).
4. The proofs verify a model of the code, and most of that model is not about upstream behaviour: 815 of 1,943 theorems are helper lemmas, 381 are edge cases, and the central specifications that are independent of the code number 32. The theorems do not cover the parts where the divergences were found, because those parts are partial definitions (templates, decoders, evaluators) or entry points. A theorem can also state the divergent behaviour as correct (`pyIter_error`, `isState_nonstr`, `formatPlaceholders_nil`).
5. The tracking tool and the manifest do not support the claim that they show exactly what needs revisiting. 9 of 10 test edits to upstream went unnoticed, 59 of 402 manifest entries are overstated, 7 name Lean definitions that do not exist.
6. The shipped tests catch a changed ordering decision (scheduler, nested condition) but miss a flipped disabled-condition result and a removed repeat limit. The sensitivity claims in the README are correct for the cases it names.
7. Documentation is mostly accurate (238 of 253 README claims), with two false statements (a macOS path, `max_exceeded`) and several overstatements about coverage by tests and proofs.

## 12. Recommended next steps

1. Abort-class bugs first: SCH-1 and TPL-47 (a float with a huge exponent kills or stalls the engine process). Patches: `experiments/05-service-schemas/patches/SCH-1.patch`, `experiments/06-templates/patches/`.
2. Fix the `continue_on_error` and `ServiceNotFound` behaviour (MAN-17) in the engine or bridge and change `tests/live/docker_e2e.py`, which currently asserts the wrong behaviour.
3. Add the new cases to `tests/`: the hand-written case directories under `experiments/*/cases/` are in the shipped format. Start with the 98 listed bugs' minimal reproducers; the area `FINDINGS.md` files give them.
4. Run the differential suite in CI. It is the only test that compares with real Home Assistant, and no workflow runs it.
5. Teach `tools/drift.py` to hash module-level constants and the unmapped helpers a mapped function reads, and `const.py`. Fix the 6 stale Lean names in `manifest.yaml` and the 4 refs that resolve to overload stubs.
6. Move `partial def`s that are partial only for convenience to structural or fuel-based recursion in the parser, the decoders and the pattern matcher, so the theorems can reach them; give `ENGINE_FUEL` and `LOOP_FUEL` as plain `def`s and prove they are non-zero.
7. State and prove central specifications for the entry points (`Engine.step` on `tick` and `stateChanged`, `render` on a small fragment, `Helpers.call` for one helper) written from the upstream source, not from the Lean case split; before adding more edge-case theorems.
8. Downgrade the `proven` status of the 41 overstated manifest entries or add the theorems that justify it; correct the README items in 10.1 (R-30, R-113, R-60, R-162, R-131); correct the 13 false docstrings (`CLAIMS-DOCSTRINGS.md`).
9. Update proofs together with each patch (the patches in `experiments/*/patches/` break theorems that state the old behaviour); then rerun `lake build HALean`, not only the executables.

## 13. How to reproduce

Environment (`CONVENTIONS.md`): Lean 4.36.0 via elan, Python 3.14 venv `/opt/havenv` with `pytest-homeassistant-custom-component==0.13.375`, sparse checkout of the tag `2026.10.4` in `upstream/ha-core` (command in `README.md` line 137), Docker for the live test.

```bash
review/experiments/01-build-axioms/build.sh                       # build under a 16 GiB cgroup (root, cgroup v1)
lake env lean review/experiments/01-build-axioms/AxiomAudit.lean   # axioms of every theorem
review/experiments/01-build-axioms/grep_audit.sh > review/experiments/01-build-axioms/logs/grep-audit.txt
review/experiments/02-shipped-tests/run_all.sh run1                # every shipped test
lake env lean review/experiments/10-theorems/Inventory.lean && python3 review/experiments/10-theorems/inventory.py
python3 review/experiments/10-theorems/classify_summary.py         # validates class/*.tsv
python3 review/experiments/11-coverage-drift/coverage.py           # section 9 table
review/experiments/11-coverage-drift/drift_blindspots.sh           # section 9.1
python3 review/data/build_buglist.py                               # section 2 table and counts
```

Per area: `cat review/experiments/<area>/README.md` (commands to rerun the harness copy, the generator with its seeds, the patches and the mutation checks). The area reviewers' patches were applied only in throwaway copies; nothing in `HALean/`, `Exe/`, `tests/`, `bridge/`, `tools/`, `manifest.yaml`, `README.md` or `PROPERTIES.md` was changed (`git diff f638a37 -- HALean Exe tests bridge tools manifest.yaml README.md PROPERTIES.md` is empty).

## 14. Limits of this review
- The seven faithfulness campaigns and the six theorem classifications were done by separate review agents. I verified a sample myself (6.10), re-read the theorem notes for the entry-point, fuel and partial-definition claims, and checked the 98 + 3 bug rows against the area files for count consistency; I did not rerun every area's full campaign.
- Two reviewers ran `pkill -f` on an engine name at known times while other reviewers were working. Divergences are reported only if they repeated across runs; a spurious failure from a killed process would not repeat.
- Scripts: 26 + 23 random `other` cases were not all minimised, 16 `ha-indexerror` cases were not examined individually.
- Random pools were reduced after each hand-written reproducer was found (state/bus, registry), so "0 random divergences" there is conditional on the pools.
- Coverage percentages measure that a definition is named in a theorem statement, not that its behaviour is determined.
- The live test used the pinned release from Docker Hub because ghcr.io layers were blocked.
