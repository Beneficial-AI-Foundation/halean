/-
  Script runs. Translated from `homeassistant/helpers/script.py`
  (`_ScriptRun`, `_QueuedScriptRun`, the `_async_step_*` handlers).

  Python runs a script as a coroutine. Here a run is an explicit control
  stack of `Frame`s that `exec` advances until the run finishes or blocks on
  something only the outside world can resolve (a service call or a delay).
  Every `seq` frame is one `Script.async_run` (the root sequence or a
  sub-script started by choose / if / repeat / sequence), which is exactly the
  boundary where `_ConditionFail` is caught.
-/
import HALean.Automation.Condition
open Lean

namespace HALean.Automation

inductive Frame where
  /-- Remaining actions of one script. `coe` is the `continue_on_error` of the
  action whose handler started this sub-script (false for the root). -/
  | seq (rest : List Action) (coe : Bool)
  | repeatCount (i n : Nat) (body : List Action) (coe : Bool)
  | repeatWhile (i : Nat) (conds : List Condition) (body : List Action) (coe : Bool)
  /-- `i = 0`: the body has not run yet. -/
  | repeatUntil (i : Nat) (conds : List Condition) (body : List Action) (coe : Bool)
  deriving Repr, Inhabited

def Frame.coe : Frame → Bool
  | .seq _ c | .repeatCount _ _ _ c | .repeatWhile _ _ _ c | .repeatUntil _ _ _ c => c

inductive Wait where
  | ready
  /-- Waiting for the lock of a queued script (`_QueuedScriptRun`). -/
  | queued
  | delayUntil (t : Millis)
  /-- Blocking service call; `coe` is the step's own `continue_on_error`. -/
  | service (callId : Nat) (coe : Bool)
  deriving Repr, Inhabited, BEq

structure Run where
  id : Nat
  autoIdx : Nat
  triggerId : String
  /-- The run's `trigger` variable. -/
  trigger : Template.Value := .none
  frames : List Frame
  wait : Wait := .ready
  deriving Repr, Inhabited

/-- How a run ended (`script_execution_set`). -/
inductive RunEnd where
  | finished
  | aborted (why : String)
  | error (why : String)
  deriving Repr, Inhabited, BEq

/-- Commands the engine asks the I/O shell to perform. -/
inductive Cmd where
  | callService (callId runId : Nat) (domain service : String) (data target : Json)
  | fireEvent (eventType : String) (data : Json)
  | automationTriggered (automationId name source : String)
  | log (level msg : String)
  deriving Repr, Inhabited

/-- The kind of a failed service call, which decides what
`continue_on_error` may swallow (`_handle_exception`, `_async_step_call_service`):
  * `invalid`  – `vol.Invalid` / configuration errors: never swallowed
  * `haError`  – `HomeAssistantError` (incl. ServiceNotFound): swallowed by any
                 enclosing step with `continue_on_error`
  * `other`    – any other exception: only the service step's own
                 `continue_on_error` converts it to a HomeAssistantError -/
inductive ErrKind where
  | invalid | haError | other
  deriving Repr, Inhabited, BEq

/-- `REPEAT_TERMINATE_ITERATIONS` -/
def REPEAT_TERMINATE_ITERATIONS : Nat := 10000

inductive StepOut where
  | next (r : Run)
  | blocked (r : Run)
  | done (e : RunEnd)
  deriving Inhabited

structure ExecCtx where
  env : CondEnv
  nextCallId : Nat

/-- `_ConditionFail` raised by a `condition` step in the top `seq` frame:
that sub-script ends ("aborted"), its parent continues. Popping the root
ends the run. -/
def conditionFail (r : Run) : StepOut :=
  match r.frames with
  | _ :: rest@(_ :: _) => .next { r with frames := rest }
  | _ => .done (.aborted "condition failed")

/-- Unwind an exception through the frames. A frame whose action had
`continue_on_error` stops a `haError`, and execution resumes in its parent. -/
def unwindError (r : Run) (k : ErrKind) (msg : String) : StepOut :=
  let rec go : List Frame → StepOut
    | [] => .done (.error msg)
    | f :: rest =>
      if f.coe && k == .haError then
        match rest with
        | [] => .done (.error msg)  -- unreachable: the root has coe = false
        | _ => .next { r with frames := rest }
      else go rest
  go r.frames

/-- Execute one step of the top frame. `cmds` are emitted commands. -/
def step (ctx : ExecCtx) (r : Run) : StepOut × List Cmd × ExecCtx :=
  let env : CondEnv := { ctx.env with triggerId := some r.triggerId, trigger := r.trigger }
  let push (f : Frame) (rest : List Frame) : Run := { r with frames := f :: rest }
  match r.frames with
  | [] => (.done .finished, [], ctx)
  | .seq [] _ :: rest =>
    -- sub-script finished; root finished ends the run
    if rest.isEmpty then (.done .finished, [], ctx) else (.next { r with frames := rest }, [], ctx)
  | .seq (a :: as) c :: rest =>
    let cur := Frame.seq as c :: rest
    let r' := { r with frames := cur }
    let rec run (coe : Bool) : Action → StepOut × List Cmd × ExecCtx
      | .continueOnError a => run true a
      | .service d s data tgt =>
        -- `async_prepare_call_from_config` runs inside the step: a template
        -- error is a HomeAssistantError raised by the step itself.
        let prepared : Except String (Json × Json) := do
          let tj ← renderComplex env tgt
          let tj ← if tgt.hasTemplate then normalizeTarget tj else pure tj
          let dj ← renderComplex env data
          pure (dj, tj)
        match prepared with
        | .error msg =>
          let out := if coe then StepOut.next r' else unwindError r' .haError msg
          (out, [.log "error" msg], ctx)
        | .ok (dj, tj) =>
          let cid := ctx.nextCallId
          (.blocked { r' with wait := .service cid coe },
           [.callService cid r.id d s dj tj], { ctx with nextCallId := cid + 1 })
      | .delay ms =>
        if ms == 0 then (.next r', [], ctx)
        else (.blocked { r' with wait := .delayUntil (env.now.utc + ms) }, [], ctx)
      | .condition c =>
        -- `check = cond.async_check(...)`, ConditionError → False; `if not check`
        match evalCond env c with
        | .ok (some true) => (.next r', [], ctx)
        | .ok _ => (conditionFail r', [], ctx)
        | .err e => (conditionFail r', [.log "warning" s!"Error in 'condition' evaluation: {e}"], ctx)
      | .choose opts dflt =>
        let chosen := opts.find? fun (cs, _) => testConditions env cs == some true
        match chosen, dflt with
        | some (_, body), _ => (.next (push (.seq body coe) cur), [], ctx)
        | none, some body => (.next (push (.seq body coe) cur), [], ctx)
        | none, none => (.next r', [], ctx)
      | .ifThen cs th el =>
        -- `if test_conditions:` – None is falsy
        if testConditions env cs == some true then (.next (push (.seq th coe) cur), [], ctx)
        else match el with
          | some body => (.next (push (.seq body coe) cur), [], ctx)
          | none => (.next r', [], ctx)
      | .repeatCount n body => (.next (push (.repeatCount 0 n body coe) cur), [], ctx)
      | .repeatWhile cs body => (.next (push (.repeatWhile 0 cs body coe) cur), [], ctx)
      | .repeatUntil cs body => (.next (push (.repeatUntil 0 cs body coe) cur), [], ctx)
      | .stop reason err =>
        -- `_AbortScript` / `_StopScript` are not HomeAssistantErrors: they
        -- reach the top whatever `continue_on_error` says.
        if err then (.done (.aborted reason), [], ctx) else (.done .finished, [], ctx)
      | .event t data =>
        -- `_async_step_event`: a template error is logged and the event is
        -- fired with the data rendered so far (none).
        match renderComplex env data with
        | .ok dj => (.next r', [.fireEvent t dj], ctx)
        | .error e => (.next r', [.log "error" s!"Error rendering event data template: {e}",
                                  .fireEvent t (Json.mkObj [])], ctx)
      | .sequence body => (.next (push (.seq body coe) cur), [], ctx)
    run false a
  | .repeatCount i n body c :: rest =>
    if i < n then (.next (push (.seq body false) (.repeatCount (i + 1) n body c :: rest)), [], ctx)
    else (.next { r with frames := rest }, [], ctx)
  | .repeatWhile i cs body c :: rest =>
    let it := i + 1
    if testConditions env cs != some true then (.next { r with frames := rest }, [], ctx)
    else if it > REPEAT_TERMINATE_ITERATIONS then
      (.done (.aborted s!"While condition terminated because it looped {REPEAT_TERMINATE_ITERATIONS} times"), [], ctx)
    else (.next (push (.seq body false) (.repeatWhile it cs body c :: rest)), [], ctx)
  | .repeatUntil i cs body c :: rest =>
    if i == 0 then (.next (push (.seq body false) (.repeatUntil 1 cs body c :: rest)), [], ctx)
    else
      -- `if self._test_conditions(conditions, "until") in [True, None]: break`
      if testConditions env cs != some false then (.next { r with frames := rest }, [], ctx)
      else if i ≥ REPEAT_TERMINATE_ITERATIONS then
        (.done (.aborted s!"Until condition terminated because it looped {REPEAT_TERMINATE_ITERATIONS} times"), [], ctx)
      else (.next (push (.seq body false) (.repeatUntil (i + 1) cs body c :: rest)), [], ctx)

/-- Safety net for nested loops (HA would hang the event loop instead). -/
def STEP_FUEL : Nat := 1000000

/-- Run until the run blocks or ends. -/
def exec (ctx : ExecCtx) (r : Run) : (Option Run ⊕ RunEnd) × List Cmd × ExecCtx :=
  let rec loop : Nat → ExecCtx → Run → List Cmd → (Option Run ⊕ RunEnd) × List Cmd × ExecCtx
    | 0, ctx, _, acc => (.inr (.error "step budget exhausted"), acc, ctx)
    | fuel + 1, ctx, r, acc =>
      match step ctx r with
      | (.next r', cs, ctx') => loop fuel ctx' r' (acc ++ cs)
      | (.blocked r', cs, ctx') => (.inl (some r'), acc ++ cs, ctx')
      | (.done e, cs, ctx') => (.inr e, acc ++ cs, ctx')
  loop STEP_FUEL ctx r []

/-- Resume a run whose service call completed. -/
def resumeService (r : Run) (ok : Bool) (k : ErrKind) (msg : String) : StepOut :=
  match r.wait with
  | .service _ coe =>
    let r := { r with wait := .ready }
    if ok then .next r
    else if coe && k != .invalid then .next r  -- the step's own continue_on_error
    else unwindError r k msg
  | _ => .next r

end HALean.Automation
