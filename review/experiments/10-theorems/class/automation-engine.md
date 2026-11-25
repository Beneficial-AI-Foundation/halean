# automation-engine: what the theorems say

Modules (366 theorems): `HALean.Automation.EngineBound` (86), `EngineSpec` (51), `EngineSpec2` (44),
`EngineSpec3` (65), `EngineSpec4` (9), `Proofs` (14), `ScriptSpec` (67), `ProtocolSpec` (30).
Implementation files: `HALean/Automation/Engine.lean`, `Script.lean`, `Protocol.lean`.

Class counts (from `automation-engine.tsv`): C 11, O 149, E 68, H 138.

| module | C | O | E | H | total |
|---|---|---|---|---|---|
| EngineBound | 0 | 45 | 1 | 40 | 86 |
| EngineSpec | 7 | 5 | 10 | 29 | 51 |
| EngineSpec2 | 0 | 28 | 0 | 16 | 44 |
| EngineSpec3 | 0 | 39 | 14 | 12 | 65 |
| EngineSpec4 | 0 | 4 | 0 | 5 | 9 |
| Proofs | 0 | 5 | 9 | 0 | 14 |
| ScriptSpec | 4 | 11 | 26 | 26 | 67 |
| ProtocolSpec | 0 | 12 | 8 | 10 | 30 |

Rules used for the classes:

* A function "has an upstream counterpart" when `manifest.yaml` lists it or its docstring in the implementation
  file names an upstream function. Theorems about other functions (`usToMs`, `replaceRun`, `withFor`, `sameKey`,
  `valueOf`, `currentRepeat`, `Run.scopeVars`, `Wait.beq`, `setWaitFields`, `owners`, `getTT`, `saveTT`,
  `exec.loop`, the number readers of `Protocol.lean`, definitions made in the spec files such as `withRun`,
  `numericTv`) are `H`, also when they are an `iff`.
* `C` is given to each member of a family of theorems that together fix the result of one translated function for
  every input. There are 6 such families (11 theorems), listed below.
* A theorem that fixes the result for one constructor of the main argument (one `Action`, one `Pattern`, one
  `SameCheck`, one message type) is `E`. This makes all 21 `step_*` case theorems `E`.
* `Pres.f` ("`f` keeps the invariant `Inv`") is `O` when `f` has an upstream counterpart or is an input handler,
  and `H` for monad plumbing and fuel-indexed loops (`Pres.pure`, `Pres.bind`, `Pres.fireDueF`, ...).
* `Protocol.lean` is HALean's own wire format. It has no upstream counterpart, so none of its theorems is `C`.

Read-only checks that were run are in `class/scratch/automation_engine_ax.lean` and
`class/scratch/automation_engine_fuel.lean`. `#print axioms` of `runs_bounded`, `HPres.engine`,
`step_init_stateless`, `onEvent_no_match`, `unwindError_haError`, `processLine_cmds`, `exec_no_frames` shows only
`propext`, `Classical.choice`, `Quot.sound`.

## What the theorems constrain

### Engine.lean

**Admission (`helpers/script.py::Script.async_run`, the mode test).** `admit` is fixed for all inputs by
`admit_start_iff`, `admit_enqueue_iff`, `admit_restart_iff`, `admit_reject_iff` (C). The case split matches
upstream lines 1926-1939 (`is_running`, `single`, `runs == max_runs` unless `restart`). Further properties (O):
`single_exclusive`, `restart_never_rejects`, `admit_bounded`, `admit_adds_below_max`, `admit_room`,
`admit_restart`.

**`process_state_match`.** `StateMatch.matches` is fixed by `stateMatch_matches_iff` (C); `match_invert` (O).
The upstream tests on `MATCH_ALL`, a single string and an iterable are in the decoder, not in this function.

**Template tracker change test (`_refresh`).** `resultChanged` is fixed by `resultChanged_eq_false_iff` (C), in
terms of `Template.pyEq`.

**`_ScriptRun.async_stop`, quiet or cancelled.** `stoppedQuietly` is fixed by `stoppedQuietly_iff` (C).

**The run bound, over whole executions.** `runs_bounded` (O): after `Engine.step {} (.init ...)` and any list of
inputs satisfying `Input.ok`, a `single` or `restart` automation has at most 1 entry in `runsOf`, a `queued` or
`parallel` one at most `maxRuns`. It rests on `Inv.step`, `Inv.steps`, `Pres.handle`, `HPres.handlers`,
`HPres.engine` and the `Pres.*` theorems of the engine functions (38 of them are O). The invariant `Inv` is
"`scripts = []`, every `maxRuns ≥ 1`, every `runsOf` length within the cap".

**`triggerAutomation` (`AutomationEntity.async_trigger` plus admission).** One theorem per branch (O, one E):
`triggerAutomation_missing`, `_trigger_vars_error`, `_render_error`, `_conditions`, `_reject`, `_enqueue`,
`_start`, `_restart`. The eight cover every branch. In the two admitted branches the right-hand side is
`(drive run).run (...)`, which is not evaluated further (see the fuel section), so the family does not fix the
result and is not `C`. `triggerAutomation_single_busy` and `triggerAutomation_full` say the engine is unchanged
when a `single` automation has a run or a `queued`/`parallel` one is at `max`.

**State operations.** `runsOf` (`Script.runs`): `mem_runsOf_iff`, `runsOf_sublist`, `runsOf_length_le`,
`runsOf_append_top`, `runsOf_append_branches`. `cleanupWait` (`unsub()` / `remove_triggers()`):
`cleanupWait_rest`, `_none_left`, `_keeps`, `_not_listening`, `_listening_other`, `_owners`, `_idem`, `_comm`.
`removeRun`: `removeRun_runs`, `_runs_sublist`, `_family_gone`, `_keeps_others`, `_runsOf_le`, `_rest`,
`_listeners`, `_family_silent`, `_keeps_auto`. `syncFamily` (`ScriptRunVariables`): `syncFamily_only_vars`,
`_length`, `_runsOf_length`, `_self`, `_branch_local`, `_rest`. All O. The `removeRun` and `syncFamily` theorems
are relative to whatever `familyOf` returns.

**Trigger listeners, single cases (O unless noted).**
* `fire` on a wait: `fire_wait`, `fire_wait_quiet`, `fire_wait_gone` (E), `fire_run_gone` (E).
* State trigger: `onStateTrigger_other_entity`, `_attr_unchanged`, `_no_match`, `_fires` (no `for`), `_for`
  (fixed `for`, `p > 0`, `fromKeyOnly = false`, `matchAll = false`).
* Numeric trigger: `onNumericTrigger_other_entity`, `_arms`, `_not_armed`, `_error`, `_fires`, `_for`,
  `_removed` (E).
* Template trigger: `templateListener_error`, `_false`, `_not_armed`, `_fires` (no `for`),
  `templateRefresh_unchanged`, `trackerGate_not_listening`, `onTemplateTrigger_no_tracker`, `setupWait_spec`,
  `waitRefresh_not_wait` (E), `waitRefresh_auto` (E).
* `for:` timers: `renderPeriod_nonneg`, `addPeriodPending_spec`, `addPeriodPending_fresh`,
  `sameStillHolds_notEqualOld`, `sameStillHolds_numeric` (E), `_removed` (E), `_always` (E).
* Zone and time entities: `onZoneTrigger_other_entity`, `updateTimeEntity_removed` (E).
* Events: `onEvent_no_match`, `onEvent_unknown_type`, `onEvent_no_listeners` (E). All three are "nothing
  happens" cases.
* Attaching: `attachTriggers_stateless`, `attachTriggers_nil` (E).
* Trigger variables: `triggerValue_keys`, `triggerValue_head`, `stateTriggerVars_keys`,
  `numericTriggerVar_keys`, `thisValue_keys`. The key lists match upstream `state.py` lines 177-186,
  `numeric_state.py` lines 122-128 and 169-179.
* Script entities absent: `writeEntity_no_script`.

**`Engine.step`.** `Inv.step`, `Inv.steps`, `runs_bounded` (invariant only); `step_init_forgets`,
`step_init_stateless` (O), `step_init_empty` (E) (the `init` input only).

### Script.lean

**`_handle_exception`.** `unwindError` is fixed by `unwindError_haError` (against `resumePoint`, a function
written in the spec file) and `unwindError_not_haError` (C). `unwindError_no_coe`, `unwindError_cases` (O).
This matches upstream lines 614-641 for the kinds `haError` and "not a `HomeAssistantError`".

**`_ConditionFail` at a sub-script boundary.** `conditionFail` is fixed by `conditionFail_root` and
`conditionFail_sub` (C).

**`resumeService`.** Six case theorems (O): `resumeService_not_waiting`, `_ok`, `_ok_response`, `_coe`,
`_invalid`, `_failed`. The case "success, `response_variable` is the empty string" has no theorem, so the family
is not complete.

**`step`.** 21 single-constructor cases (E): `step_no_frames`, `step_root_done`, `step_sub_done`,
`step_repeatCount_iter`, `step_repeatCount_done`, `step_repeatEach`, `step_repeatUntil_first`,
`step_repeatWhile_limit`, `step_delay_zero`, `step_delay_pos`, `step_stop_error`, `step_stop_error_coe`,
`step_stop`, `step_sequence`, `step_repeatCount_start`, `step_parallel_nil`, `step_parallel_cons`,
`step_choose_empty`, `step_choose_default`, `step_if_no_conditions`, `step_condition_disabled`. One property
for all inputs: `step_callId` (O), `exec_callId` (O): `nextCallId` does not decrease. `exec_no_frames` (E).

**`set_repeat_var`.** `repeatVar_first_index` (O), four E cases.

### Protocol.lean

`decodeInstant_ok`, `decodeEntityState_ok`, `decodeOptState_some` (O) fix the success results of three small
decoders. `decodeInput`: `decodeInput_bad_instant`, `decodeInput_unknown`, `decodeInput_rejected` (O),
`decodeInput_no_type`, `decodeInput_tick`, `decodeInput_event` (E). `Cmd.toJson`: `Cmd.toJson_type`,
`Cmd.toJson_injective` (O, not for `call_done`). `processLine`: `processLine_error`, `processLine_ok`,
`processLine_cmds`, `processLine_reply_type` (O). Together these four say: the reply is an `error` object and the
engine is kept, or the engine is `(e.step i).1` and the reply is a `batch` whose `cmds` are the rejected
automations followed by the encoded commands of the step.

## What they do not constrain

Counts from `logs/theorems.tsv` (constants in statements) and `logs/defs.tsv`: of 109 `def`/`partial`/`opaque`
declarations in `Engine.lean`, 41 are not named in the statement of any `C`/`O` theorem; of 16 in `Script.lean`,
7; of 12 in `Protocol.lean`, 3. Being named does not mean being fixed: most engine functions are named only by
their `Pres.*` theorem.

### (a) Partial and opaque definitions

`Engine.lean` has one `partial def`, `eventDataMatches` (line 1410), and two `opaque` constants, `ENGINE_FUEL`
(line 927) and `LOOP_FUEL` (line 1029). `Script.lean` and `Protocol.lean` have none of their own. They call
partial definitions of other files: `renderComplex`, `renderComplexV`, `Complex.hasTemplate` (`Condition.lean`),
the template evaluator (`Template.render`, `renderWithInfo`, `pyEq`, ...), `HALean.Core.orjsonLoads` (its parser
functions are partial), and through `decodeInput` the partial decoders `decodeAction`, `decodeCondition`,
`decodeComplex` of `Config.lean`.

Theorems whose statements involve these:

* `resultChanged_eq_false_iff` names `Template.pyEq` (partial) directly. It says when `resultChanged` is false
  given the value of `pyEq a b`. It says nothing about which values `pyEq` calls equal.
* `onEvent_no_match` uses `IgnoresEvent`, which contains `eventDataMatches want data`. `#print` shows
  `opaque HALean.Automation.eventDataMatches`. The kernel cannot evaluate it, so for an event trigger whose type
  list contains the event type the hypothesis cannot be proved for any concrete `want` and `data`, not even for
  `want = []`. The theorem can be applied to such a trigger only with the fact assumed. `onEvent_unknown_type`
  avoids this by assuming the type is not in the list. No theorem states anything about `eventDataMatches`.
* All `triggerAutomation_*` theorems, `renderPeriod_nonneg`, `onNumericTrigger_arms/_not_armed/_error/_fires/_for`,
  `templateRefresh_unchanged`, `sameStillHolds_numeric`, `templateCond_static` have hypotheses or conclusions
  about `renderVariables`, `renderPeriod`, `numericStateOf`, `renderWithInfo`, `checkAutomationConditions`. These
  call partial functions. The theorems hold for any behaviour of those functions; they are case statements
  ("if rendering returned X then ..."). They cannot be instantiated in the kernel for a concrete template.
* Every theorem about `step`, `exec`, `drive`, `Engine.step` (including `runs_bounded`) is about a function that
  calls partial functions. The statements hold whatever those functions return. The compiled program may also
  fail to return inside them: Lean gives no termination guarantee for a `partial def`.

### The two opaque fuel constants

`engine := handlers ENGINE_FUEL`; `handlers 0 = Handlers.out` (every handler only logs `FUEL_OUT_MSG`).
`resumeWoken`, `fireDue`, `fireSun`, `fireTimePoints` run `LOOP_FUEL` rounds; with fuel 0 they log
`LOOP_OUT_MSG`.

What the theorems can conclude with these opaque:

* Statements that hold for every fuel value. `HPres.handlers : ∀ n, HPres (handlers n)` gives `HPres.engine`;
  `Pres.resumeWokenF`, `Pres.fireDueF`, `Pres.fireSunF`, `Pres.fireTimePointsF` are proved for all `n`. This is
  how `runs_bounded` is proved. It is true also of an engine whose handlers do nothing.

What they cannot conclude:

* Nothing that depends on the value. `example : ENGINE_FUEL = 10000 := by rfl` fails ("not definitionally
  equal") and `example : LOOP_FUEL ≠ 0 := by decide` fails (scratch file). The kernel cannot prove
  `ENGINE_FUEL ≠ 0`, so for the kernel `engine` may be `Handlers.out`.
* Therefore no theorem can say what `drive`, `finishRun`, `stopRun`, `callLocal` do. `triggerAutomation_start`
  and `triggerAutomation_restart` end in `(drive (newRun ...)).run (...)` and stop there. No theorem unfolds
  `drive` one level, although `driveH h` could be specified for an arbitrary `h` (the proof of `Pres.driveH` does
  that for the invariant only).
* No theorem can give the output of `Engine.step` on a `stateChanged`, `event`, `tick`, `mqtt`, `webhook` or
  `serviceResult` input, not even "a tick with nothing due sends nothing": `handle` calls `advanceTo`, which calls
  `fireDue = fireDueF _ LOOP_FUEL`, and `fireDueF _ 0` emits a log line. The only exact `Engine.step` theorems are
  for `init`, which calls none of the loops.

Are the "fuel ran out" branches ruled out? No.

* No theorem in any module names `FUEL_OUT_MSG`, `LOOP_OUT_MSG`, `ENGINE_FUEL`, `LOOP_FUEL` or `STEP_FUEL`
  (`logs/theorems.tsv`). No theorem says the nesting depth of handler calls stays below 10000 or that a loop
  ends within 100000 rounds for reachable engines.
* `STEP_FUEL` (`Script.lean`, a plain `def`, 1000000) is not opaque. `exec_loop_zero` (rfl) states the exhausted
  branch: the run ends with `.error .other "step budget exhausted"`. No theorem rules it out. It is reachable with
  a small script. Measured with `#eval` (scratch file): `exec` of `repeat count 400000` over `[delay 0]` ends with
  "step budget exhausted" (300000 finishes). `repeat while []` over a body of 100 `delay 0` ends with "step budget
  exhausted" before the 10000-iteration abort that `step_repeatWhile_limit` describes. Upstream runs the first to
  the end and aborts the second with `_AbortScript`.
* `step_repeatWhile_limit` fixes the abort text as `While condition terminated because it looped 10000 times`.
  Upstream (`script.py` lines 955-959) raises `f"While condition {repeat[CONF_WHILE]} terminated because it
  looped  {REPEAT_TERMINATE_ITERATIONS} times"` (with the conditions and two spaces). The theorem pins the Lean
  text, not the upstream text.

### (b) Decoders, protocol, parsers

* `decodeInput`: no theorem for the `init`, `state_changed`, `mqtt`, `webhook`, `service_result` branches (5 of 7
  message types). `decodePair` and `decodePairs` appear in no theorem.
* Nothing relates a decoded `Input` to the `Input.ok` hypothesis of `runs_bounded` (see below).
* `getNat` on a number that is negative or has an exponent goes through `toFloat.floor.toUInt64.toNat`.
  `getNat_isOk` says it succeeds; no theorem says what value it returns there. `getNat_int` covers only
  exponent 0 and mantissa ≥ 0.
* `Cmd.toJson_injective` excludes `call_done`. For a failed `call_done` the response is dropped and for a
  successful one `kind` and `msg` are dropped, so it is not injective there; `toJson_callDone_ok/_error` state
  the fields.
* There is no decoder for the reply; no round-trip theorem.
* `Json.parse line >>= decodeInput` is a hypothesis in all `processLine_*` theorems. Nothing is proved about
  which lines parse.

### (c) Entry points

* `Engine.step`: only the invariant (`Inv.step`, `Inv.steps`, `runs_bounded`) and the `init` case
  (`step_init_forgets`, `step_init_empty`, `step_init_stateless`). No theorem about its commands for any other
  input.
* `handle`, `advanceTo`, `onStateChanged`, `onMqtt`, `onWebhook`, `fireTimeTriggers`, `fireDue`, `fireSun`,
  `fireTimePoints`, `resumeWoken`, `initArmed`, `writeEntity` (except "no script"), `updateTimeEntity` (except
  "removed"), `onZoneTrigger` (except "other entity"): only `Pres.*`.
* The ten handlers `driveH`, `finishRunH`, `releaseQueueH`, `finishBranchH`, `answerH`, `continueNowH`,
  `stopRunH`, `cancelRunH`, `startScriptH`, `callLocalH`: only `Pres.*`. No theorem about queue hand-over
  (`releaseQueueH`), the `parallel` join (`finishBranchH`), stop propagation (`stopRunH`), or `woken`.
* `step`: no theorem for the actions `service`, `variables`, `event`, `delayT`, `repeatCountT`, `repeatEach`
  (the action), `waitTemplate`, `waitForTrigger`, `condition` other than `disabled`, `choose` with options,
  `ifThen` with conditions, `continueOnError` other than around `stop`; nor for the frames `repeatWhile` with
  conditions and `repeatUntil` after the first pass.
* `exec`: `exec_no_frames`, `exec_callId` and the one-round unfolding lemmas. No theorem about a run of two or
  more steps.
* `processLine`: specified relative to `Json.parse`, `decodeInput` and `Engine.step` (see above).
* In no theorem of any module: `mqttLevelsMatch`, `mqttTopicMatches`, `mqttSimple`, `mqttPayloadMatches`,
  `mqttTriggerVars`, `multiDictValue`, `eventDataMatches`, `familyOfF`, `rootOf`, `rootOfF`, `callLocal`,
  `stopRun`, `TIME_CHANGE_MICROSECOND`, `TIMEOUT_MSG`, `decodePair`, `decodePairs`, the three fuel constants and
  the two fuel messages.
* `familyOf`: the only fact proved is `mem_familyOf_self`. Nothing says a `parallel` branch is in the family of
  its parent. So `removeRun_family_gone` and `removeRun_family_silent` do not show that stopping a run removes
  its branches.
* `cleanupWait` also filters `haStart` and does not touch `mqttRetained`. `cleanupWait_none_left` and
  `removeRun_listeners` list seven fields and omit both. An `mqttRetained` entry keyed by `(Owner.wait rid, idx)`
  stays after the wait ends.

## Assumptions that nothing checks

| theorem | hypothesis | where the value comes from at run time | discharged by a theorem? |
|---|---|---|---|
| `runs_bounded`, `Inv.step`, `Inv.steps`, `Pres.handle` | `Input.ok`: every automation of an `init` has `1 ≤ maxRuns` | `decodeInput` → `decodeAutomation` (`Config.lean`; `maxRunsOf` refuses values below 2, default 10) | No. No theorem states `decodeInput j = .ok (i, _) → i.ok`, and `ConfigSpec.lean` has no theorem that names `maxRuns`. True by reading the code. |
| `runs_bounded` | start state `Engine.step {} (.init ...)` | `Exe/Automation.lean` starts with `default`, and inputs may arrive before the first `init` | Partly. `step_init_forgets` makes the previous engine irrelevant once an `init` arrives. `Inv default` is not stated (it holds; `Inv.empty` is about `{}`). |
| `runs_bounded` (through `Inv`) | `scripts = []` | holds for every engine built by `Engine.step` (no branch sets `scripts`). `HALean/Script/Service.lean` lines 76 and 117 set `scripts` and then use the same handlers | For the script service the bound is not proved; PROPERTIES.md says so. |
| `admit_bounded`, `admit_adds_below_max` | `n ≤ m`, `1 ≤ m` | `n = (runsOf e ai).length`, `m = a.maxRuns` | `n ≤ m` by `runs_bounded` for engines without scripts; `1 ≤ m` as in row 1. |
| `triggerAutomation_full` | `a.maxRuns ≠ 0` | decoder | as row 1 |
| `withRun_fresh` | `∀ r ∈ e.runs, r.id < e.nextRunId` | engine state | No. It is proved to be kept by `withRun` only. `driveH` also allocates ids (branches) and no theorem covers that. No theorem says run ids are distinct in a reachable engine; `replaceRun`, `find?` by id and `familyOf` rely on it. |
| `addPeriodPending_fresh` | pending ids below `nextPendingId` and distinct | engine state | No. Kept by `addPeriodPending` only; `onStateTrigger`, `onNumericTrigger`, `templateListener` also add timers. |
| `fire_wait_quiet` | `e.woken.Nodup` | engine state | No. `driveH` and `finishBranchH` append to `woken` without a membership test. |
| `replaceRun_find_same` | stored run has the same `autoIdx` and `parent` as `r` | caller | No theorem; docstring says "it does when `r` is a stepped copy". No theorem says `step` keeps `autoIdx` and `parent`. |
| `removeRun_*`, `syncFamily_*` | none, but stated relative to `familyOf` | `familyOfF` with depth `runs.length + 1` | Nothing proved about `familyOf` beyond `mem_familyOf_self`. |
| `onEvent_no_match` | `IgnoresEvent`, which contains `eventDataMatches` | partial def | Cannot be proved for a concrete trigger whose type matches. |
| `triggerAutomation_*` (8) | results of `renderVariables`, `checkAutomationConditions`, `admit` | partial template functions | Case hypotheses; all outcomes have a theorem. Nothing is assumed, but nothing can be computed in the kernel either. |
| `processLine_error/_ok/_cmds` | result of `Json.parse line >>= decodeInput` | stdin line | Case hypotheses; both outcomes covered. |
| `templateCond_static` | `t.isStatic = true` | `Template` parser | not checked here |
| `Cmd.toJson_injective` | `c₁.tag ≠ "call_done"` | the command | holds for 5 of 6 constructors |
| `onStateTrigger_fires/_for`, `onNumericTrigger_*` | `t.kind = ...`, `eid ∈ eids`, match results | trigger and event | Case hypotheses. `onStateTrigger_fires` and `_for` cover only `matchAll = false`; `_for` only `fromKeyOnly = false`. The `for:` template case and `for: 0` have no theorem. |

Weaker than they read, vacuous, or restatements:

* `runs_bounded` counts entries of the Lean list `runsOf`. It does not relate them to runs in Home Assistant.
  It holds whether or not fuel runs out, and would hold if every handler did nothing.
* `Pres.startScriptH`, `Pres.callLocalH`: under `Inv` (`scripts = []`) `startScriptH` returns `.rejected` at its
  second line and `callLocalH` is never called (`localCall?_no_scripts`). The two theorems are about code that
  does not run under the invariant. `HPres.engine` lists `startScript` and `callLocal` among the handlers that
  "keep the invariant" for this reason.
* `Inv.restarted` concludes `Inv`, i.e. at most one run. Its docstring says "one run is left".
* `step_init_forgets`: `handle (.init ..)` starts with `setE` of a new record, so the statement is immediate.
* `step_callId`, `exec_callId`, `step_run_callId`: `nextCallId` does not decrease. They do not say it increases
  when a call is emitted, so they do not give "ids are never reused".
* `setupWait_spec` does not state `st.tmpl = some t`.
* `withRun_runsOf`, `withRun_fresh`, `withRun_lastTriggered`, `numericTv_keys` are about definitions made in
  `EngineSpec3.lean` (`withRun`, `newRun`, `numericTv`). They concern the engine only through
  `triggerAutomation_enqueue/_start/_restart` and `onNumericTrigger_fires/_for`, which use these definitions on
  their right-hand sides.
* Proved by `rfl` (or a tuple of `rfl`) and restating the definition: `testConditions_nil`, `pattern_any`,
  `withFor_fields`, `replaceRun_rest`, `cleanupWait_rest`, `sameStillHolds_removed`, `sameStillHolds_always`,
  `tmplCtxOf_env`, `repeatVar_item_none`, `repeatVar_count_zero`, `repeatVar_plain`, `currentRepeat_repeatCount`,
  `exec_loop_zero`, `Cmd.toJson_callDone_ok`, `Cmd.toJson_callDone_error`, `Inv.let_`, `Pres.let_`,
  `HPres.engine` (an instance of `HPres.handlers`). 18 theorems.
* Restatements proved by `simp`/`unfold` of one definition with a fixed constructor: the 21 `step_*` case
  theorems, the 6 `resumeService_*`, `conditionFail_root/_sub`, `fire_wait*`, `triggerAutomation_*` except
  `_single_busy` and `_full`, `onStateTrigger_*`, `onNumericTrigger_*`, `templateListener_*`, `decodeInput_*`,
  `decodeEntityState_*`, `decodeOptState_*`, `processLine_error/_ok/_cmds`, `exec_loop_done/_blocked/_next`. They
  say what the code says for one branch.
* No theorem has hypotheses that cannot hold together, and none has conclusion `True`.

## Specifications independent of the code?

11 `C` theorems in 6 families.

| function | theorems | right-hand side |
|---|---|---|
| `admit` | `admit_start_iff`, `admit_enqueue_iff`, `admit_restart_iff`, `admit_reject_iff` | Restatement. The four conditions are the definition's `if` chain turned into propositions. |
| `StateMatch.matches` | `stateMatch_matches_iff` | Restatement of the two-line `match`. |
| `resultChanged` | `resultChanged_eq_false_iff` | Restatement of the four-line `match`. |
| `stoppedQuietly` | `stoppedQuietly_iff` | Restatement (the `match` on `wait` written with existentials). |
| `conditionFail` | `conditionFail_root`, `conditionFail_sub` | Restatement of the `match` on `frames`. |
| `unwindError` | `unwindError_haError`, `unwindError_not_haError` | `unwindError_haError` uses `resumePoint`, written in the spec file: a second recursive function with the same shape as `unwindError.go` (it differs only in returning the frames, not the `StepOut`). `resumePoint_suffix` and `unwindError_cases` then give properties not visible in the code (the stack gets strictly shorter and stays non-empty). `unwindError_not_haError` is a property proved by induction, not a restatement. |

Counts: independent specification 0; restatement of the implementation's case split 9; in between 2
(`unwindError_haError`: a separately written but same-shaped function; `unwindError_not_haError`: an inductive
property). No `C` theorem compares a function with a specification written from the upstream source.

The theorems that say something the code does not show directly are `O`: `runs_bounded` and its invariant,
`unwindError_cases`, `removeRun_listeners`, `cleanupWait_owners`, `syncFamily_branch_local`,
`Cmd.toJson_injective`, `usToMs_eq_iff` and `usToMs_least` (H, internal helper).

## Docstring claims

Checked: 256 (248 theorem docstrings, 8 module headers). Verdicts: correct 245, overstated 10, stale 1,
false 0, correct for the wrong reason 0.

Not correct:

1. `EngineSpec3.lean` header, lines 5-8: "`drive` and the functions around it are `partial`, so a theorem can
   follow a handler only up to the point where it hands a run to `drive`". **stale**. `drive` is
   `engine.drive` with `engine := handlers ENGINE_FUEL` (`Engine.lean` 930-932), a total definition. The theorems
   stop at `drive` because `ENGINE_FUEL` is opaque and no theorem unfolds `driveH`.
2. `Proofs.queued_waits` line 82: "A `queued` script with work in flight always queues". **overstated**. The
   theorem has `hm : n ≠ m`; at `n = max` `admit` rejects (`admit_reject_iff`).
3. `EngineBound.Inv.restarted` lines 426-427: "one run is left". **overstated**. The conclusion is `Inv`, which
   gives at most one.
4. `EngineSpec2.cleanupWait_none_left` line 168: "Afterwards nothing is left that belongs to the wait."
   **overstated**. The statement lists 7 fields. `mqttRetained` entries of the wait are not removed by
   `cleanupWait` (`Engine.lean` 348-357) and are not in the statement; `haStart` is removed but not stated.
5. `EngineSpec2.removeRun_listeners` lines 307-308: "The listeners after removal: exactly those not owned by a
   wait of a run in the family." **overstated**. Same 7 fields; `haStart` and `mqttRetained` are missing.
6. `EngineSpec3.withRun_fresh` lines 254-255: "given the engine's invariant that live ids are below
   `nextRunId`". **overstated**. No theorem shows this holds for engines produced by `Engine.step`.
7. `EngineSpec3.setupWait_spec` lines 751-753: "the run has exactly one tracker, for its template".
   **overstated**. The statement gives `trigIdx`, `vars`, `last`, `armed`, not `tmpl = some t`.
8. `ScriptSpec.Wait.beq_ready_iff` lines 147-148: "Waits of different kinds are never equal". **overstated**.
   The theorem is about `.ready` only.
9. `ScriptSpec.step_delay_zero` lines 440-441: "No step other than a service call emits a service call".
   **overstated**. The theorem is about `delay 0` only, and no other theorem states the first sentence.
10. `ScriptSpec.step_run_callId` lines 560-561: "Service call ids are never reused". **overstated**. The
    statement is `ctx.nextCallId ≤ ...`; reuse is excluded only if the id also increases at each call, which is
    not stated.
11. `ProtocolSpec.lean` header lines 2-4: "what each decoder accepts". **overstated**. `decodeInput` has no
    theorem for `init`, `state_changed`, `mqtt`, `webhook`, `service_result`; `decodePair(s)` has none.

Not a theorem docstring, not counted: `Input.ok` (`EngineBound.lean` 582-583) says "the decoder gives at least
2, as HA does". True by reading `maxRunsOf`; no theorem.

Upstream statements in docstrings that were compared with the source and found correct: the trigger key lists
(`stateTriggerVars_keys`, `numericTv_keys`, `numericTriggerVar_keys`), `thisValue_keys` (`State.as_dict` keys),
`repeatVar_*` (`set_repeat_var`), `unwindError_*` (`_handle_exception`), the `admit` texts ("Already running",
"Maximum number of runs exceeded").

## manifest.yaml claims

9 entries checked: 3 with `lean:` names in the implementation files of this area and status `proven`, and 6 with
other `lean:` names whose `notes:` name theorems of these modules. Verdicts: correct 1, correct for the wrong
reason 1, overstated 7, false 0, stale 0.

| entry | lean | cited theorems | exist | verdict |
|---|---|---|---|---|
| `helpers/script.py::Script.async_run` | `admit`, `triggerAutomation`, `startScript` | `single_exclusive`, `restart_never_rejects`, `admit_bounded`, `queued_waits` | yes | **overstated**. All four are about `admit`. `admit` is fixed (by the uncited `admit_*_iff`). `triggerAutomation` has branch theorems that stop at `drive`. `HALean.Automation.startScript` does not exist (it is `startScriptH`); its only theorem is `Pres.startScriptH`. |
| `helpers/event.py::process_state_match` | `StateMatch.matches` | `match_invert`, `match_all` | yes | **correct for the wrong reason**. The two cited theorems give two properties. `proven` fits because of `stateMatch_matches_iff`, which is not cited and restates the definition. |
| `core.py::ServiceRegistry.async_call` | 15 names, among them `mergeTarget` | `call_none_return_response_errors`, `call_only_needs_return_response`, `call_return_response_needs_blocking`, `call_after_remove_not_found` (`Core/ServiceRegistryProofs.lean`) | yes | **overstated**. Four error-path results of `Registry.asyncCall`. For the engine-side name `mergeTarget` the only theorem is `mergeTarget_not_obj` (E). |
| `helpers/condition.py::AndConditionChecker._async_check` | `evalAnd` | `evalAnd_nil`, `evalAnd_all_disabled` | yes | **overstated** as cited: two edge cases; the note's sentence "errors are collected and raised only if no condition returned False" is not what they state. `ConditionSpec.lean` has `evalAnd_true_iff`, `evalAnd_false_iff` (other area, not cited). |
| `helpers/condition.py::OrConditionChecker._async_check` | `evalOr` | `evalOr_nil` | yes | **overstated** as cited: one edge case. |
| `helpers/condition.py::NotConditionChecker._async_check` | `evalNot` | `evalNot_disabled` | yes | **overstated** as cited: the single input `not [disabled]`. |
| `helpers/condition.py::DisabledConditionChecker._async_check` | `evalCond` | `evalCond_disabled` | yes | **correct**. The upstream function returns `None`; the theorem states `evalCond env .disabled = .ok none`. |
| `helpers/condition.py::ConditionsChecker.async_check` | `checkAutomationConditions` | `checkAutomationConditions_nil` | yes | **overstated** as cited: the empty list only; "errors count as False" is not stated by it (`ConditionSpec.checkAutomationConditions_iff` states it, other area). |
| `helpers/script.py::_ScriptRun._test_conditions` | `testConditions` | `testConditions_nil` | yes | **overstated** as cited: `rfl` on the empty list; "stops at first error and returns None" is not stated by it. |

Outside the count: 77 further entries name definitions of the three implementation files with status
`translated`. 8 entries name `HALean.Automation` definitions that do not exist in the source (`finishBranch` in
2 entries, `startScript` in 3, `continueNow`, `answer`, `releaseQueue`, `cancelRun`); the functions are now
`finishBranchH`, `startScriptH`, ... These names are stale.

## PROPERTIES.md claims

22 claims that refer to theorems or definitions of these modules. Verdicts: correct 17, overstated 3, false 1,
stale 1, correct for the wrong reason 0.

| # | claim (line) | verdict | evidence |
|---|---|---|---|
| 1 | `single_exclusive` row (34) | correct | `admit .single m n = .start ↔ n = 0` |
| 2 | `restart_never_rejects` row (35) | correct | statement |
| 3 | `admit_bounded`: "`queued` / `parallel` admission never exceeds `max`" (36) | overstated | needs `n ≤ m` and `1 ≤ m`; with `max = 0` and no run `admit` starts a run (`admit_zero`). The text at lines 60-63 says so itself. |
| 4 | `queued_waits`: "`queued` with a run in flight queues" (37) | overstated | needs `n ≠ max`; at `max` it is rejected |
| 5 | `evalAnd_nil`, ... "edge cases" (38) | correct | all E in the tsv |
| 6 | `match_invert`, `match_all` (39) | correct | statements |
| 7 | `templateCond_static`: static template "is never evaluated" (40) | correct | result is `.ok (t.src.toLower == "true")`, independent of `env` |
| 8 | `runs_bounded` row (55) | correct | statement; "no script entities" holds because `init` builds `scripts = []` |
| 9 | `Inv.step`, `Inv.steps` row (56) | correct | statements |
| 10 | `HPres.engine` row, "at every nesting depth" (57) | correct | `HPres.handlers : ∀ n`; for `startScript` and `callLocal` see "weaker than they read" |
| 11 | `Inv.admitted`, `Inv.restarted` row (58) | correct | statements |
| 12 | "first theorem about whole executions of `Engine.step`" (49-51) | correct | no other theorem folds `Engine.step` |
| 13 | "With script entities the bound is not proved" (73) | correct | `Inv` contains `scripts = []` |
| 14 | fuel paragraph (92-97): `handlers n`, `engine = handlers ENGINE_FUEL` opaque, `LOOP_FUEL`, `runs.length + 1`, "When fuel runs out, the engine logs an error and does nothing more" | correct | `Engine.lean` 600-610, 921-930, 1037-1049, 305-321 |
| 15 | "`Engine.lean` has no `partial` definitions any more" (156) | **false** | `partial def eventDataMatches`, `Engine.lean` line 1410; `#print` gives `opaque` |
| 16 | "Properties 1 and 2, and the 'one run' part of 4, are proved (`runs_bounded`)" (157-158) | correct | statement |
| 17 | Property 1, "Lifts `single_exclusive` from `admit` to all reachable states" (160-163) | correct | reachable = from `init` by `Engine.step`, inputs with `Input.ok` |
| 18 | Property 2 "(proved: `runs_bounded`)" (164-165) | correct | with `max ≥ 1` |
| 19 | Property 4: "At most one run is proved; that it is the newest is not" (168-170) | correct | no theorem about which run remains after `drive` |
| 20 | Property 5: "Today a step budget (`STEP_FUEL`) guarantees this" (171-172) | overstated | `Engine.step` is total because of three budgets (`STEP_FUEL`, `ENGINE_FUEL`, `LOOP_FUEL`) and it calls `partial` functions (templates, `renderComplex`, `eventDataMatches`, `orjsonLoads`) for which nothing guarantees return. The budget is reached by valid scripts (see fuel section). |
| 21 | Property 7 (`continue_on_error`) listed as still to prove (178-180) | stale | `unwindError_haError`, `unwindError_not_haError`, `resumeService_invalid`, `resumeService_coe` prove it for the two named functions. It is not proved for `step` or the engine. |
| 22 | Property 10 cites `evalAnd_all_disabled`, `evalNot_disabled` (190-193) | correct | statements |

Outside the count (no theorem involved): the model paragraph (lines 14-17) lists the inputs as "initial states
and automations, state changes, events, clock ticks and service-call results" and the commands as "call a
service, fire an event, or log". `Input` also has `mqtt` and `webhook`; `Cmd` also has `automationTriggered`,
`setState`, `callDone`. Property 6 names `finishBranch`, which is now `finishBranchH`.
