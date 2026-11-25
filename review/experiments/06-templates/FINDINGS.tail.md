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
   `exception` and the rate limit are not compared. Only 2 of the 361 shipped cases with states use it on
   `states.<domain>` in a boolean position, which is where TPL-4 shows.
7. **Results are compared by `repr`.** HALean's driver prints `pyRepr`; HA's side prints Python's `repr`. A value that
   is equal but whose Lean `repr` is wrong (TPL-8: a list holding U+00A0) fails; that is a true finding about
   `strRepr`, but the same mechanism cannot tell `1` from `True` inside equal-looking containers only if the reprs
   coincide, which they do not, so no blind spot there.
8. **One fresh `hass` per case, compiled after the states are set.** Jinja's compile-time folding (TPL-38) therefore
   always sees the final states; a second render after a state change, where HA would return the stale folded value,
   is never made.
9. **No timeout on the engine.** A template on which `halean-template` does not answer (TPL-47) blocks the suite.
   `harness/test_batch.py` adds a 20 s timeout and restarts the engine.
10. **The shipped cases combine several expressions per template** (for example five `as_datetime` calls in one
    case). One wrong sub-result fails the case, but a sub-expression that raises hides all the others.
