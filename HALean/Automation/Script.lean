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
import HALean.Automation.TimePeriod
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
  | repeatEach (i : Nat) (items : List Template.Value) (body : List Action) (coe : Bool)
  deriving Repr, Inhabited

def Frame.coe : Frame → Bool
  | .seq _ c | .repeatCount _ _ _ c | .repeatWhile _ _ _ c | .repeatUntil _ _ _ c
  | .repeatEach _ _ _ c => c

/-- `set_repeat_var(iteration, count, item)` -/
def repeatVar (iteration : Nat) (count : Option Nat) (item : Option Template.Value) :
    Template.Value :=
  .dict ((([(.str "first", .bool (iteration == 1)), (.str "index", .int iteration)]
      ++ (match count with
          | some c => if c > 0 then [(.str "last", .bool (iteration == c))] else []
          | none => [])
      ++ (match item with
          | some .none | none => []
          | some x => [(.str "item", x)])) : List (Template.Value × Template.Value)))

/-- The `repeat` variable in scope: defined locally by the innermost repeat. -/
def currentRepeat : List Frame → Option Template.Value
  | [] => none
  | .repeatCount i n _ _ :: _ => some (repeatVar i (some n) none)
  | .repeatWhile i _ _ _ :: _ => some (repeatVar i none none)
  | .repeatUntil i _ _ _ :: _ => some (repeatVar i none none)
  | .repeatEach i items _ _ :: _ => some (repeatVar i (some items.length) (items[i - 1]?))
  | .seq .. :: rest => currentRepeat rest

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

/-- How a run ended. Sub-scripts (`parallel` branches) re-raise all but
`_ConditionFail`, so the kind matters. -/
inductive RunEnd where
  | finished
  /-- `_ConditionFail` reached the top of the run -/
  | conditionFailed
  /-- `_StopScript` (`stop` without `error`), with its `response` (the
  `response_variable`'s value, `None` without one). -/
  | stopped (why : String) (response : Template.Value := .none)
  /-- `_AbortScript` -/
  | aborted (why : String)
  | error (k : ErrKind) (why : String)
  deriving Repr, Inhabited

/-- A sub-script's end that its parent re-raises. -/
def RunEnd.raises : RunEnd → Bool
  | .finished | .conditionFailed => false
  | _ => true

inductive Wait where
  | ready
  /-- Waiting for the lock of a queued script (`_QueuedScriptRun`). -/
  | queued
  | delayUntil (t : Millis)
  /-- Blocking service call; `coe` is the step's own `continue_on_error`. -/
  | service (callId : Nat) (coe : Bool) (respVar : Option String := none)
  /-- `wait_template` that was false: the engine tracks `t` (like
  `async_track_template`) until it turns true or `deadline` passes. -/
  | waitTmpl (t : Template.Tmpl) (deadline : Option Millis) (continueOnTimeout : Bool)
  /-- `wait_for_trigger`: the engine attaches `triggers`, which see `vars`,
  until one fires or `deadline` passes. -/
  | waitTrig (triggers : List Trigger) (vars : List (String × Template.Value))
      (deadline : Option Millis) (continueOnTimeout : Bool)
  /-- `parallel`: the branch runs (in order), the ends of those that are
  done, and the step's `continue_on_error`. -/
  | joinPar (children : List Nat) (results : List (Nat × RunEnd)) (coe : Bool)
  deriving Repr, Inhabited

/-- Templates have no equality; waits compare by everything else. -/
def Wait.beq : Wait → Wait → Bool
  | .ready, .ready | .queued, .queued => true
  | .delayUntil a, .delayUntil b => a == b
  | .service a c x, .service b d y => a == b && c == d && x == y
  | .waitTmpl _ a c, .waitTmpl _ b d => a == b && c == d
  | .waitTrig _ _ a c, .waitTrig _ _ b d => a == b && c == d
  | .joinPar a _ c, .joinPar b _ d => a == b && c == d
  | _, _ => false

instance : BEq Wait := ⟨Wait.beq⟩

/-- Who waits for a run of a script entity to end (`ScriptEntity._service_handler`
awaiting `Script.async_run`): a run blocked in its service call step `callId`,
or a call from outside the engine (the shell's own call id). -/
inductive Caller where
  | run (runId callId : Nat)
  | external (callId : Nat) (returnResponse : Bool)
  deriving Repr, Inhabited, BEq

structure Run where
  id : Nat
  autoIdx : Nat
  triggerId : String
  /-- The run's variables (`trigger`, automation `variables`, assignments
  by `variables` actions). -/
  vars : List (String × Template.Value) := []
  frames : List Frame
  wait : Wait := .ready
  /-- For a `parallel` branch: the run that started it. -/
  parent : Option Nat := none
  /-- For a run of a script entity called with `wait=True`: who waits for it. -/
  caller : Option Caller := none
  /-- `script_stack_cv` as the run sees it: the script entities (by index)
  of the blocking call chain that led to this run, itself last. -/
  stack : List Nat := []
  deriving Repr, Inhabited

/-- The variables a step sees: the run's, plus the innermost `repeat`. -/
def Run.scopeVars (r : Run) : List (String × Template.Value) :=
  match currentRepeat r.frames with
  | some v => ("repeat", v) :: r.vars
  | none => r.vars

/-- The `wait` variable of the wait steps: `{"remaining": ..., "completed": ...}`. -/
def waitVar (remaining : Template.Value) (completed : Bool) : Template.Value :=
  .dict [(.str "remaining", remaining), (.str "completed", .bool completed)]

/-- Set fields of the `wait` variable in place (`self._variables["wait"][k] = v`). -/
def setWaitFields (vars : List (String × Template.Value)) (fields : List (String × Template.Value)) :
    List (String × Template.Value) :=
  vars.map fun (k, v) =>
    if k != "wait" then (k, v) else
    match v with
    | .dict kvs => (k, .dict (kvs.map fun (kk, vv) => match kk with
        | .str f => match fields.find? (·.1 == f) with
          | some (_, nv) => (kk, nv)
          | none => (kk, vv)
        | _ => (kk, vv)))
    | other => (k, other)

/-- `_TIMEOUT_MSG` -/
def TIMEOUT_MSG : String := "Timeout reached, abort script."

/-- Commands the engine asks the I/O shell to perform. -/
inductive Cmd where
  | callService (callId runId : Nat) (domain service : String) (data target : Json)
      (returnResponse : Bool := false)
  | fireEvent (eventType : String) (data : Json)
  | automationTriggered (automationId name source : String)
  | log (level msg : String)
  /-- `Entity.async_write_ha_state` of an entity the engine owns (a script entity). -/
  | setState (entityId state : String) (attributes : Json)
  /-- The answer to a call the shell made (`call` input): the service's
  response, or the exception it raised (`kind`: `invalid`, `ha_error`,
  `other` or `cancelled`). -/
  | callDone (callId : Nat) (ok : Bool) (response : Json) (kind msg : String)
  deriving Repr, Inhabited

/-- `REPEAT_TERMINATE_ITERATIONS` -/
def REPEAT_TERMINATE_ITERATIONS : Nat := 10000

inductive StepOut where
  | next (r : Run)
  | blocked (r : Run)
  /-- Start these sub-scripts and wait for all of them (`parallel`). -/
  | spawn (r : Run) (branches : List (List Action)) (coe : Bool)
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
  | _ => .done .conditionFailed

/-- Unwind an exception through the frames. A frame whose action had
`continue_on_error` stops a `haError`, and execution resumes in its parent. -/
def unwindError (r : Run) (k : ErrKind) (msg : String) : StepOut :=
  let rec go : List Frame → StepOut
    | [] => .done (.error k msg)
    | f :: rest =>
      if f.coe && k == .haError then
        match rest with
        | [] => .done (.error k msg)  -- unreachable: the root has coe = false
        | _ => .next { r with frames := rest }
      else go rest
  go r.frames

/-- Execute one step of the top frame. `cmds` are emitted commands. -/
def step (ctx : ExecCtx) (r : Run) : StepOut × List Cmd × ExecCtx :=
  let env : CondEnv := { ctx.env with triggerId := some r.triggerId, vars := r.scopeVars }
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
      | .service name datas tgt eid rv =>
        -- `async_prepare_call_from_config` runs inside the step: its errors
        -- are raised by the step itself (`HomeAssistantError`, except a
        -- target that renders to something `dict.update` cannot take)
        let prepared : Except (ErrKind × String) (String × String × Json × Json) := do
          let haErr {α : Type} (e : Except String α) : Except (ErrKind × String) α :=
            e.mapError fun m => (.haError, m)
          -- the name: rendered, then `cv.service`
          let (d, s) ← match name with
            | .static d s => pure (d, s)
            | .tmpl t =>
              let v ← haErr ((Template.render t env.tmplCtx true).mapError
                fun m => s!"Error rendering service name template: {m}")
              let str ← match v with
                | .str x => pure x
                | .none => throw (.haError, "Template rendered invalid service: None")
                | v => haErr (Template.pyStr v)
              let svc := str.toLower
              match svc.splitOn "." with
              | [d, s] =>
                if Template.validEntityId svc then pure (d, s)
                else throw (.haError, s!"Template rendered invalid service: {str}")
              | _ => throw (.haError, s!"Template rendered invalid service: {str}")
          -- the target
          let tj ← haErr ((renderComplex env tgt).mapError
            fun m => s!"Error rendering service target template: {m}")
          let .obj _ := tj
            | throw (.other, s!"ValueError: the target rendered to {tj.compress}, not a mapping")
          let tj ← if tgt.hasTemplate then haErr (normalizeTarget tj) else pure tj
          -- the data: `data`, then `data_template`
          let dj ← datas.foldlM (init := Json.mkObj []) fun acc c => do
            let v ← haErr ((renderComplex env c).mapError fun m => s!"Error rendering data template: {m}")
            let .obj kvs := v
              | throw (.haError, "Error rendering data template: Result is not a Dictionary")
            pure (kvs.toList.foldl (fun a (k, x) => a.setObjVal! k x) acc)
          -- the action's own `entity_id`
          let tj := match eid with
            | some ids => tj.setObjVal! "entity_id" ids
            | none => tj
          pure (d, s, dj, tj)
        match prepared with
        | .error (k, msg) =>
          let out := if coe && k == .haError then StepOut.next r' else unwindError r' k msg
          (out, [.log "error" msg], ctx)
        | .ok (d, s, dj, tj) =>
          let cid := ctx.nextCallId
          -- `return_response = response_variable is not None`
          (.blocked { r' with wait := .service cid coe rv },
           [.callService cid r.id d s dj tj rv.isSome], { ctx with nextCallId := cid + 1 })
      | .delay ms =>
        if ms == 0 then (.next r', [], ctx)
        else (.blocked { r' with wait := .delayUntil (env.now.utc + ms) }, [], ctx)
      | .delayT c =>
        -- `_get_pos_time_period_template`: an error is logged and aborts
        match (do cvPositiveTimePeriod (← renderComplexV env c) : Except String Int) with
        | .error e =>
          let m := s!"Error rendering delay template: {e}"
          (.done (.aborted m), [.log "error" m], ctx)
        | .ok 0 => (.next r', [], ctx)
        | .ok us => (.blocked { r' with wait := .delayUntil (env.now.utc + ((us + 999) / 1000).toNat) }, [], ctx)
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
      | .repeatCountT t body =>
        -- `int(count.async_render(...))`; TemplateError/ValueError abort the script
        match Template.render t env.tmplCtx true with
        | .error e =>
          let m := s!"Error rendering repeat count template: {e}"
          (.done (.aborted m), [.log "error" m], ctx)
        | .ok v =>
          let n? : Except String (Option Int) := match v with
            | .int i => .ok (some i)
            | .bool b => .ok (some (if b then 1 else 0))
            | .float f => if f.isNaN then .ok none
                          else match Template.floatToInt? f with
                            | some i => .ok (some i)
                            | none => .error "cannot convert float infinity to integer"
            | .str s => if Template.numberTextModelled s then .ok (Template.parseIntStr s)
                        else .error "int() of non-ASCII text is not supported by HALean"
            | v => .error s!"int() argument must be a string or a number, not '{Template.typeName v}'"
          match n? with
          | .ok (some n) => (.next (push (.repeatCount 0 n.toNat body coe) cur), [], ctx)
          | .ok none =>
            let m := s!"Error rendering repeat count template: invalid literal for int()"
            (.done (.aborted m), [.log "error" m], ctx)
          | .error m => (unwindError r' .other m, [], ctx)
      | .repeatEach items body =>
        match renderComplexV env items with
        | .ok (.list xs) => (.next (push (.repeatEach 0 xs body coe) cur), [], ctx)
        | .ok v =>
          let m := s!"Repeat 'for_each' must be a list of items, got: {(Template.pyStr v).toOption.getD (Template.typeName v)}"
          (.done (.aborted "Repeat 'for_each' must be a list of items"), [.log "error" m], ctx)
        | .error e =>
          let m := s!"Error rendering repeat for each items template: {e}"
          (.done (.aborted m), [.log "error" m], ctx)
      | .variables defs =>
        -- `async_simple_render` (each value sees the ones before it), then assign
        let rendered : Except String (List (String × Template.Value)) :=
          defs.foldlM (fun acc (k, c) => do
            let v ← renderComplexV { env with vars := (acc.reverse ++ env.vars) } c
            pure ((k, v) :: acc)) []
        match rendered with
        | .ok kvs =>
          let vars := kvs.reverse.foldl (fun vs (k, v) => setVar vs k v) r'.vars
          (.next { r' with vars }, [], ctx)
        | .error msg =>
          -- a TemplateError is one of the `CONFIGURATION_ERRORS`, which
          -- `continue_on_error` never swallows
          (unwindError r' .invalid msg, [.log "error" msg], ctx)
      | .repeatWhile cs body => (.next (push (.repeatWhile 0 cs body coe) cur), [], ctx)
      | .repeatUntil cs body => (.next (push (.repeatUntil 0 cs body coe) cur), [], ctx)
      | .stop reason err rv =>
        -- `_AbortScript` / `_StopScript` are not HomeAssistantErrors: they
        -- reach the top whatever `continue_on_error` says.
        if err then (.done (.aborted reason), [], ctx)
        else match rv with
          | some v =>
            match env.vars.find? (·.1 == v) with
            | some (_, resp) => (.done (.stopped reason resp), [], ctx)
            | none => (.done (.aborted s!"Response variable '{v}' is not defined"), [], ctx)
          | none => (.done (.stopped reason), [], ctx)
      | .event t datas =>
        -- `_async_step_event`: `event_data`, then `event_data_template`, each
        -- merged in; one that fails to render is logged and left out
        let (dj, logs) := datas.foldl (fun (acc, logs) c =>
          match renderComplex env c with
          | .ok (.obj kvs) => (kvs.toList.foldl (fun a (k, x) => a.setObjVal! k x) acc, logs)
          | .ok _ => (acc, logs)
          | .error e => (acc, logs ++ [Cmd.log "error" s!"Error rendering event data template: {e}"]))
          (Json.mkObj [], [])
        (.next r', logs ++ [.fireEvent t dj], ctx)
      | .sequence body => (.next (push (.seq body coe) cur), [], ctx)
      | .parallel [] => (.next r', [], ctx)
      | .parallel branches => (.spawn r' branches coe, [], ctx)
      | .waitTemplate t timeout cot =>
        -- `_get_timeout_seconds_from_action`: a render or validation error
        -- is logged and aborts the script
        let tus : Except String (Option Int) := match timeout with
          | none => .ok none
          | some c => do
            let v ← renderComplexV env c
            some <$> cvPositiveTimePeriod v
        match tus with
        | .error e =>
          let m := s!"Error rendering timeout template: {e}"
          (.done (.aborted m), [.log "error" m], ctx)
        | .ok tus =>
          -- `wait = {"remaining": timeout, "completed": False}` (seconds, a float)
          let rem : Template.Value := match tus with
            | some us => .float (Float.ofInt us / 1000000)
            | none => .none
          let r1 := { r' with vars := setVar r'.vars "wait" (waitVar rem false) }
          -- `condition.async_template(...)`: a ConditionError is one of the
          -- `CONFIGURATION_ERRORS`, which `continue_on_error` never swallows
          match templateCond { env with vars := r1.scopeVars } t with
          | .error e => (unwindError r1 .invalid e, [.log "error" e], ctx)
          | .ok true => (.next { r1 with vars := setVar r1.vars "wait" (waitVar rem true) }, [], ctx)
          | .ok false =>
            if tus == some 0 then
              -- `_async_handle_timeout`
              let r2 := { r1 with vars := setVar r1.vars "wait" (waitVar (.float 0) false) }
              if cot then (.next r2, [], ctx)
              else (.done (.aborted TIMEOUT_MSG), [.log "info" TIMEOUT_MSG], ctx)
            else
              let deadline := tus.map fun us => env.now.utc + ((us + 999) / 1000).toNat
              (.blocked { r1 with wait := .waitTmpl t deadline cot }, [], ctx)
      | .waitForTrigger trigs timeout cot =>
        let tus : Except String (Option Int) := match timeout with
          | none => .ok none
          | some c => do
            let v ← renderComplexV env c
            some <$> cvPositiveTimePeriod v
        match tus with
        | .error e =>
          let m := s!"Error rendering timeout template: {e}"
          (.done (.aborted m), [.log "error" m], ctx)
        | .ok tus =>
          -- `variables = dict(self._variables)`, taken before `wait` is set
          let snapshot := r'.scopeVars
          let rem : Template.Value := match tus with
            | some us => .float (Float.ofInt us / 1000000)
            | none => .none
          let w0 : Template.Value :=
            .dict [(.str "remaining", rem), (.str "completed", .bool false), (.str "trigger", .none)]
          let r1 := { r' with vars := setVar r'.vars "wait" w0 }
          if tus == some 0 then
            let r2 := { r1 with vars := setWaitFields r1.vars [("remaining", .float 0)] }
            if cot then (.next r2, [], ctx)
            else (.done (.aborted TIMEOUT_MSG), [.log "info" TIMEOUT_MSG], ctx)
          -- `if not remove_triggers: return`
          else if trigs.isEmpty then (.next r1, [], ctx)
          else
            let deadline := tus.map fun us => env.now.utc + ((us + 999) / 1000).toNat
            (.blocked { r1 with wait := .waitTrig trigs snapshot deadline cot }, [], ctx)
    run false a
  | .repeatCount i n body c :: rest =>
    if i < n then (.next (push (.seq body false) (.repeatCount (i + 1) n body c :: rest)), [], ctx)
    else (.next { r with frames := rest }, [], ctx)
  | .repeatEach i items body c :: rest =>
    if i < items.length then (.next (push (.seq body false) (.repeatEach (i + 1) items body c :: rest)), [], ctx)
    else (.next { r with frames := rest }, [], ctx)
  | .repeatWhile i cs body c :: rest =>
    let it := i + 1
    -- `set_repeat_var(iteration)` happens before the while check
    let env := { env with vars := ("repeat", repeatVar it none none) :: r.vars }
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

/-- Where `exec` stopped. `done` carries the run as it was at its last step
(its variables). -/
inductive ExecRes where
  | blocked (r : Run)
  | spawn (r : Run) (branches : List (List Action)) (coe : Bool)
  | done (r : Run) (e : RunEnd)

/-- Run until the run blocks or ends. -/
def exec (ctx : ExecCtx) (r : Run) : ExecRes × List Cmd × ExecCtx :=
  let rec loop : Nat → ExecCtx → Run → List Cmd → ExecRes × List Cmd × ExecCtx
    | 0, ctx, r, acc => (.done r (.error .other "step budget exhausted"), acc, ctx)
    | fuel + 1, ctx, r, acc =>
      match step ctx r with
      | (.next r', cs, ctx') => loop fuel ctx' r' (acc ++ cs)
      | (.blocked r', cs, ctx') => (.blocked r', acc ++ cs, ctx')
      | (.spawn r' bs c, cs, ctx') => (.spawn r' bs c, acc ++ cs, ctx')
      | (.done e, cs, ctx') => (.done r e, acc ++ cs, ctx')
  loop STEP_FUEL ctx r []

/-- Resume a run whose service call completed. -/
def resumeService (r : Run) (ok : Bool) (k : ErrKind) (msg : String)
    (response : Template.Value := .none) : StepOut :=
  match r.wait with
  | .service _ coe rv =>
    let r := { r with wait := .ready }
    -- `if response_variable: self._variables[response_variable] = response_data`
    if ok then match rv with
      | some v => if v.isEmpty then .next r
                  else .next { r with vars := setVar r.vars v response }
      | none => .next r
    else if coe && k != .invalid then .next r  -- the step's own continue_on_error
    else unwindError r k msg
  | _ => .next r

end HALean.Automation
