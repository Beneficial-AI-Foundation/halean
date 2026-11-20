/-
  The engine: one pure step function from an input message to new state plus
  commands for the I/O shell.

  Translated from:
    * triggers  – components/homeassistant/triggers/{state,numeric_state,time,
                  time_pattern,event}.py and helpers/event.py
                  (`process_state_match`, `async_track_same_state`)
    * admission – helpers/script.py `Script.async_run` (run modes, max)
    * automation– components/automation/__init__.py `async_trigger`
-/
import HALean.Automation.Script
import HALean.Automation.TimePeriod
import HALean.Automation.Location
import HALean.Automation.Sun
open Lean

namespace HALean.Automation

/-- Trigger variables handed to the run (subset of `trigger` in HA). -/
structure TriggerVars where
  id : String
  idx : Nat
  platform : String
  entityId : Option String := none
  description : String
  /-- The full `trigger` variable as HA builds it (`TriggerData` + platform
  fields), for templates. -/
  value : Template.Value := .none
  deriving Repr, Inhabited

open Template in
/-- `trigger_data` (`id`, `idx`, `alias`) + the platform's own fields. -/
def triggerValue (t : Trigger) (platform : String) (fields : List (String × Value)) : Value :=
  .dict ((([("id", Value.str t.id), ("idx", .str (toString t.idx)),
           ("alias", match t.alias with | some a => .str a | none => .none),
           ("platform", .str platform)] : List (String × Value)) ++ fields).map fun (k, v) => (.str k, v))

def stateVal : Option EntityState → Template.Value
  | some s => .state s false
  | none => .none

def forVal : Option Nat → Template.Value
  | none => .none
  | some ms => .timedelta (ms * 1000)

/-- Replace `trigger.for` in built trigger variables. -/
def TriggerVars.withFor (tv : TriggerVars) (v : Template.Value) : TriggerVars :=
  { tv with value := match tv.value with
    | .dict kvs => .dict (kvs.map fun (k, x) => match k with
      | .str "for" => (k, v)
      | _ => (k, x))
    | other => other }

/-- Whole milliseconds until a timer for `us` microseconds is due (the
engine's clock has millisecond resolution; a timer fires at the first
instant at or after its due time). -/
def usToMs (us : Int) : Nat := ((us + 999) / 1000).toNat

def boundVal : Option Bound → Template.Value
  | none => .none
  | some (.num f) => .float f
  | some (.entity e) => .str e

/-- `numeric_state.py::variables(entity_id)`: what a `value_template` sees
as `trigger` (no trigger_data, no states). -/
def numericTriggerVar (_t : Trigger) (eid : String) (below above : Option Bound)
    (attr : Option String) : Template.Value :=
  .dict [(.str "platform", .str "numeric_state"), (.str "entity_id", .str eid),
         (.str "below", boundVal below), (.str "above", boundVal above),
         (.str "attribute", match attr with | some a => .str a | none => .none)]

/-- What keeps a `for:` timer alive (`_check_same_state` / numeric check). -/
inductive SameCheck where
  /-- state trigger: `cur_value == new_value` -/
  | equalNew (attr : Option String) (v : Json)
  /-- state trigger with `from` but no `to`: `cur_value != old_value` -/
  | notEqualOld (attr : Option String) (v : Json)
  | numeric (below above : Option Bound) (attr : Option String) (vt : ValueTmpl := none)
  /-- template trigger timers are cancelled by the trigger itself, not by
  the entity they mention -/
  | always
  deriving Repr, Inhabited

/-- Who a trigger listener belongs to: an automation (by position), or a
run waiting in a `wait_for_trigger` step (`async_initialize_triggers` with
the step's `async_done` as the action). A `wait_template` tracker belongs to
its waiting run too. -/
inductive Owner where
  | auto (ai : Nat)
  | wait (runId : Nat)
  deriving Repr, Inhabited, BEq, DecidableEq

/-- The last result `async_track_template_result` saw. -/
inductive TmplResult where
  | ok (v : Template.Value)
  | err
  deriving Repr, Inhabited

/-- A state change the rate limiter deferred: entity, old, new. -/
abbrev Deferred := String × Option EntityState × Option EntityState

/-- State of one `template` trigger: the trigger's closure (`armed`,
`delay_cancel`) and its `TrackTemplateResultInfo` (`_info`, `_last_result`,
the `KeyedRateLimit`, the time listener is `info.hasTime`). -/
structure TmplTrig where
  owner : Owner
  trigIdx : Nat
  armed : Bool := false
  last : Option TmplResult := none
  pending : Option Nat := none
  info : Template.RInfo := {}
  lastTriggered : Option Millis := none
  /-- The rate limiter's timer: when it fires and the event it replays. -/
  rlTimer : Option (Millis × Deferred) := none
  /-- For a `wait_template` step (`async_track_template`): its template and
  the variables it was set up with. -/
  tmpl : Option Template.Tmpl := none
  vars : List (String × Template.Value) := []
  deriving Repr, Inhabited

/-- Same tracker: same owner and trigger position. -/
def TmplTrig.sameKey (a b : TmplTrig) : Bool :=
  a.owner == b.owner && a.trigIdx == b.trigIdx

/-- `_refresh`'s change test: a changed result; error after error is not a
change, the first render after setup always is. -/
def resultChanged (last : Option TmplResult) (r : Except String Template.Value) : Bool :=
  match last, r with
  | none, _ => true
  | some (.ok a), .ok b => !Template.pyEq a b
  | some .err, .error _ => false
  | _, _ => true

def TmplResult.of : Except String Template.Value → TmplResult
  | .ok v => .ok v
  | .error _ => .err

/-- A pending `for:` timer created by `async_track_same_state`. -/
structure PendingFor where
  id : Nat := 0
  owner : Owner
  entity : String
  fireAt : Millis
  check : SameCheck
  vars : TriggerVars
  /-- For a templated `for:` of a state or numeric_state trigger: the key of
  the trigger's `period[entity]`, which `call_action` reads when it fires. -/
  periodKey : Option (Owner × Nat × String) := none
  deriving Repr, Inhabited

/-- The triggers of a `wait_for_trigger` step while its run waits, and the
variables they see (`dict(self._variables)` before `wait` is set). -/
structure WaitTrig where
  runId : Nat
  autoIdx : Nat
  triggers : List Trigger
  vars : List (String × Template.Value)
  hasTimeout : Bool
  deriving Repr, Inhabited

structure Engine where
  automations : List Automation := []
  states : States := []
  now : Instant := {utc := 0}
  pendings : List PendingFor := []
  /-- numeric_state `armed_entities`: (owner, trigger idx, entity) -/
  armed : List (Owner × Nat × String) := []
  /-- All live runs, oldest first (each automation's `Script._runs`). -/
  runs : List Run := []
  nextRunId : Nat := 0
  nextCallId : Nat := 0
  nextPendingId : Nat := 0
  /-- Second (UTC, whole seconds) up to which time triggers were evaluated. -/
  lastSec : Nat := 0
  tmplTrigs : List TmplTrig := []
  /-- `Script.last_triggered` per automation, in UTC microseconds. -/
  lastTriggered : List (Nat × Int) := []
  /-- The `period` dicts of state and numeric_state triggers with a
  templated `for:`: (automation, trigger idx, entity) → microseconds. -/
  periods : List ((Owner × Nat × String) × Int) := []
  /-- Runs waiting in a `wait_for_trigger` step, with their triggers. -/
  waitTrigs : List WaitTrig := []
  /-- Runs whose wait completed during the current input; they continue
  once its callbacks are done. -/
  woken : List Nat := []
  /-- HA's location (`hass.config` latitude, longitude, elevation), for the
  `sun` trigger. -/
  location : Option Sun.Observer := none
  /-- The next event of each `sun` trigger: (owner, trigger idx) → UTC µs
  (`async_track_point_in_utc_time`). -/
  sunNext : List ((Owner × Nat) × Int) := []
  deriving Inhabited

inductive Input where
  | init (automations : List Automation) (states : List EntityState) (now : Instant)
      (location : Option Sun.Observer := none)
  | stateChanged (entityId : String) (old new : Option EntityState) (now : Instant)
  | event (eventType : String) (data : Json) (now : Instant)
  | tick (now : Instant)
  | serviceResult (callId : Nat) (ok : Bool) (kind : ErrKind) (msg : String) (now : Instant)
      (response : Json := .null)

abbrev EM := StateM (Engine × List Cmd)

def emit (cs : List Cmd) : EM Unit := modify fun (e, acc) => (e, acc ++ cs)
def getE : EM Engine := return (← get).1
def setE (e : Engine) : EM Unit := modify fun (_, acc) => (e, acc)

def Engine.condEnv (e : Engine) : CondEnv := { states := e.states, now := e.now }

/-- What trigger templates see: an automation's static
`trigger_variables`, or the waiting run's variables. -/
def tmplCtxOf (e : Engine) (o : Owner) : Template.Ctx :=
  { states := e.states, now := e.now,
    vars := match o with
      | .auto ai => (e.automations.getD ai default).triggerVars.map fun (k, v) => (k, Template.Value.ofJson v)
      | .wait rid => ((e.waitTrigs.find? (·.runId == rid)).map (·.vars)).getD [] }

/-- The automation an owner's messages are about. -/
def Engine.ownerAuto (e : Engine) : Owner → Automation
  | .auto ai => e.automations.getD ai default
  | .wait rid => match e.runs.find? (·.id == rid) with
    | some r => e.automations.getD r.autoIdx default
    | none => default

/-! ## Value helpers -/

def valueOf (attr : Option String) : Option EntityState → Json
  | none => .null
  | some s => match attr with
    | none => .str s.state
    | some a => (s.attr? a).getD .null

/-- `process_state_match` -/
def StateMatch.matches (m : StateMatch) (v : Json) : Bool :=
  match m.values with
  | none => !m.invert
  | some vs => m.invert != vs.contains v

/-! ## Runs and run modes -/

/-- The automation's runs (`Script._runs`); `parallel` branches are
sub-scripts, not runs of the automation. -/
def runsOf (e : Engine) (ai : Nat) : List Run := e.runs.filter fun r => r.autoIdx == ai && r.parent.isNone

/-- A run and all branches below it. -/
partial def familyOf (e : Engine) (id : Nat) : List Nat :=
  id :: (e.runs.filter (·.parent == some id)).flatMap fun c => familyOf e c.id

/-- The top run of a branch. -/
partial def rootOf (e : Engine) (id : Nat) : Nat :=
  match (e.runs.find? (·.id == id)).bind (·.parent) with
  | some p => rootOf e p
  | none => id

/-- Variables a branch keeps to itself: `wait` (`assign_parallel_protected`)
and the `repeat` of the loop it was started in. -/
def BRANCH_LOCAL : List String := ["wait", "repeat"]

/-- Branches share the run's variables (`ScriptRunVariables` assigns to the
outer scope). Branches interleave only where they block, so copying a
branch's variables to the rest of its family whenever it stops is exact. -/
def syncFamily (e : Engine) (r : Run) : Engine :=
  let root := rootOf e r.id
  let fam := familyOf e root
  if fam.length ≤ 1 then e else
  let shared := r.vars.filter fun (k, _) => !BRANCH_LOCAL.contains k
  { e with runs := e.runs.map fun x =>
      if x.id == r.id || !fam.contains x.id then x
      else { x with vars := shared.foldl (fun vs (k, v) => setVar vs k v) x.vars } }

def replaceRun (e : Engine) (r : Run) : Engine :=
  { e with runs := e.runs.map fun x => if x.id == r.id then r else x }

/-- Remove every listener of a run's wait (the `finally: unsub()` /
`remove_triggers()` of `_async_wait_with_optional_timeout`). -/
def cleanupWait (e : Engine) (rid : Nat) : Engine :=
  let o := Owner.wait rid
  { e with tmplTrigs := e.tmplTrigs.filter (·.owner != o),
           waitTrigs := e.waitTrigs.filter (·.runId != rid),
           pendings := e.pendings.filter (·.owner != o),
           sunNext := e.sunNext.filter (·.1.1 != o),
           armed := e.armed.filter (·.1 != o),
           periods := e.periods.filter (·.1.1 != o) }

/-- Remove a run with its branches, and the listeners of their waits (also
on stop: stopping a run cancels its sub-scripts). -/
def removeRun (e : Engine) (id : Nat) : Engine :=
  let fam := familyOf e id
  fam.foldl cleanupWait { e with runs := e.runs.filter (!fam.contains ·.id) }

/-- `async_track_template(hass, wait_template, ..., self._variables)`: set
up the tracker with its first render's info. -/
def setupWait (r : Run) (t : Template.Tmpl) : EM Unit := do
  let e ← getE
  let vars := r.scopeVars
  let (_, info) := Template.renderWithInfo t { states := e.states, now := e.now, vars } true
  setE { e with tmplTrigs := (e.tmplTrigs.filter (·.owner != .wait r.id)) ++
    [{ owner := .wait r.id, trigIdx := 0, tmpl := some t, vars, info }] }

/-- Attach triggers (`async_attach_trigger`): numeric_state entities that
start outside the range are armed ("Each entity that starts outside the
range is already armed"); template triggers are armed when their first render
is false, and that render gives the tracker's first info. -/
def attachTriggers (o : Owner) (trigs : List Trigger) : EM Unit := do
  let e ← getE
  let a := e.ownerAuto o
  let mut armed := e.armed
  let mut tts := e.tmplTrigs
  let mut logs : List Cmd := []
  let mut sun := e.sunNext
  for t in trigs do
    match t.kind with
    | .numericState eids below above attr _ vtm =>
      for eid in eids do
        let vt := vtm.map fun tm => (tm, (tmplCtxOf e o).vars ++ [("trigger", numericTriggerVar t eid below above attr)])
        if let .ok false := numericStateOne e.condEnv eid below above attr vt then
          armed := armed ++ [(o, t.idx, eid)]
    | .sun sunrise off =>
      -- `schedule_next_event()`
      match e.location with
      | none => logs := logs ++ [.log "error" s!"{a.alias}: the sun trigger needs HA's location"]
      | some obs =>
        match Sun.nextEvent obs sunrise ((e.now.utc : Int) * 1000) e.now.tzOffsetSec off with
        | some at_ => sun := sun ++ [((o, t.idx), at_)]
        | none => logs := logs ++ [.log "error" s!"{a.alias}: Unable to find event after one year"]
    | .template tm _ =>
      match Template.renderWithInfo tm (tmplCtxOf e o) true with
      | (.ok v, info) => tts := tts ++ [{ owner := o, trigIdx := t.idx, armed := !Template.resultAsBoolean v, info }]
      | (.error msg, info) =>
        tts := tts ++ [{ owner := o, trigIdx := t.idx, info }]
        logs := logs ++ [.log "warning" s!"Error initializing 'template' trigger for '{a.alias}': {msg}"]
    | _ => pure ()
  setE { e with armed, tmplTrigs := tts, sunNext := sun }
  emit logs

mutual
/-- Drive a run until it blocks or ends; on end, `_finish` it (which for a
queued script releases the lock to the next waiter). -/
partial def drive (r : Run) : EM Unit := do
  let e ← getE
  let (res, cmds, ctx) := exec { env := e.condEnv, nextCallId := e.nextCallId } r
  let last := match res with | .blocked x | .spawn x .. | .done x _ => x
  setE (syncFamily { e with nextCallId := ctx.nextCallId } last)
  emit cmds
  match res with
  | .spawn r' branches coe =>
    -- `asyncio.gather` of one sub-script per branch, each with a scope of
    -- its own (`enter_scope(parallel=True)`); they start in order
    let e ← getE
    let ids := List.range' e.nextRunId branches.length
    let kids : List Run := (branches.zip ids).map fun (b, id) =>
      { id, autoIdx := r'.autoIdx, triggerId := r'.triggerId, vars := r'.scopeVars,
        frames := [.seq b false], parent := some r'.id }
    let e := replaceRun e { r' with wait := .joinPar ids [] coe }
    -- `gather` wraps the branches in tasks that are not started eagerly:
    -- they run after the callbacks of the current input
    setE { e with runs := e.runs ++ kids, nextRunId := e.nextRunId + branches.length,
                  woken := e.woken ++ ids }
  | .blocked r' =>
    setE (replaceRun (← getE) r')
    match r'.wait with
    | .waitTmpl t _ _ => setupWait r' t
    | .waitTrig trigs vars deadline _ =>
      let e ← getE
      setE { e with waitTrigs := (e.waitTrigs.filter (·.runId != r'.id)) ++
        [{ runId := r'.id, autoIdx := r'.autoIdx, triggers := trigs, vars, hasTimeout := deadline.isSome }] }
      attachTriggers (.wait r'.id) trigs
    | _ => pure ()
  | .done _ end_ => finishRun r end_

partial def finishRun (r : Run) (end_ : RunEnd) : EM Unit := do
  let e ← getE
  if let some pid := r.parent then
    finishBranch pid r.id end_
    return
  let a := e.automations.getD r.autoIdx default
  match end_ with
  | .error _ m => emit [.log "error" s!"Error while executing automation {a.alias}: {m}"]
  | .aborted m => emit [.log "debug" s!"{a.alias} aborted: {m}"]
  | .conditionFailed => emit [.log "debug" s!"{a.alias} aborted: condition failed"]
  | .finished | .stopped _ => pure ()
  setE (removeRun e r.id)
  -- `_QueuedScriptRun._finish` releases the FIFO lock
  if a.mode == .queued then
    let e ← getE
    if (runsOf e r.autoIdx).all (·.wait == .queued) then
      if let some nxt := (runsOf e r.autoIdx).head? then
        setE (replaceRun e { nxt with wait := .ready })
        drive { nxt with wait := .ready }

/-- A `parallel` branch ended. Once all have, `gather` returns and the
first branch (in order) that raised re-raises in the parent; an error is
then handled like any step's (`_handle_exception` with the parallel step's
`continue_on_error`). -/
partial def finishBranch (pid kid : Nat) (end_ : RunEnd) : EM Unit := do
  setE (removeRun (← getE) kid)
  let e ← getE
  let some p := e.runs.find? (·.id == pid) | return
  let .joinPar ids results coe := p.wait | return
  let results := results ++ [(kid, end_)]
  if !ids.all (fun i => results.any (·.1 == i)) then
    setE (replaceRun e { p with wait := .joinPar ids results coe })
    return
  let p := { p with wait := .ready }
  -- the parent wakes up later, when `gather`'s future is done
  let later (p : Run) : EM Unit := do
    let e ← getE
    setE { replaceRun e p with woken := e.woken ++ [p.id] }
  setE (replaceRun e p)
  let raised := ids.findSome? fun i => (results.find? (·.1 == i)).bind fun (_, x) =>
    if x.raises then some x else none
  match raised with
  | none => later p
  | some (.error k m) =>
    if coe && k == .haError then later p
    else match unwindError p k m with
      | .next p' => later p'
      | .done x => finishRun p x
      | _ => pure ()
  | some x => finishRun p x
end

/-- `this` as `AutomationEntity.async_trigger` builds it:
`hass.states.get(self.entity_id).as_dict()`. The automation entity is `on`
whenever it can trigger, and its attributes are what
`_async_calculate_state` writes (capability `id`, then
`extra_state_attributes`, then `friendly_name`); `Script._changed` rewrites
them whenever a run is added or finishes, so they always reflect the live
runs and the last admitted trigger. The timestamps depend on when HA started
and the context ids are random, so using them is an error. -/
def thisValue (e : Engine) (ai : Nat) (a : Automation) (eid : String) : Template.Value :=
  let lt : Template.Value := match e.lastTriggered.find? (·.1 == ai) with
    | some (_, us) => .datetime us (some 0)
    | none => .none
  let mode := match a.mode with
    | .single => "single" | .restart => "restart" | .queued => "queued" | .parallel => "parallel"
  let attrs : List (String × Template.Value) :=
    (match a.uniqueId with | some u => [("id", .str u)] | none => []) ++
    [("last_triggered", lt), ("mode", .str mode), ("current", .int (runsOf e ai).length)] ++
    (if a.mode == .queued || a.mode == .parallel then [("max", .int a.maxRuns)] else []) ++
    [("friendly_name", .str a.alias)]
  .dict ([("entity_id", Template.Value.str eid), ("state", .str "on"),
    ("attributes", .dict (attrs.map fun (k, v) => (.str k, v))),
    ("last_changed", .opaque "this.last_changed"), ("last_reported", .opaque "this.last_reported"),
    ("last_updated", .opaque "this.last_updated"), ("context", .opaque "this.context")].map
    fun (k, v) => (.str k, v))

/-- Admission decision of `Script.async_run`, as a pure function of the
mode, `max` and how many runs (running or queued) exist. -/
inductive Admit where
  | reject (why : String)
  | start
  | enqueue
  | restart
  deriving Repr, BEq, DecidableEq

def admit (mode : Mode) (maxRuns existing : Nat) : Admit :=
  if existing = 0 then .start
  else if mode = .single then .reject "Already running"
  else if mode ≠ .restart ∧ existing = maxRuns then .reject "Maximum number of runs exceeded"
  else match mode with
    | .queued => .enqueue
    | .restart => .restart
    | _ => .start

/-- `Script.async_run` admission + `AutomationEntity.async_trigger`. -/
def triggerAutomation (ai : Nat) (tv : TriggerVars) : EM Unit := do
  let e ← getE
  let some a := e.automations[ai]? | return
  -- conditions are checked before the mode check (entity.py)
  -- `variables = {"this": ..., **run_variables}`, then the automation's
  -- variables rendered on top (an error stops the trigger right here)
  let this := match a.entityId with
    | some eid => [("this", thisValue e ai a eid)]
    | none => []
  let env0 := { e.condEnv with triggerId := some tv.id, vars := this ++ [("trigger", tv.value)] }
  let vars ← match renderVariables env0 a.variables with
    | .ok vs => pure vs
    | .error msg =>
      emit [.log "error" s!"{a.alias}: Error rendering variables: {msg}"]
      return
  let env := { env0 with vars }
  if !checkAutomationConditions env a.conditions then
    emit [.log "debug" s!"{a.alias}: conditions not met"]
    return
  let existing := runsOf e ai
  let decision := admit a.mode a.maxRuns existing.length
  if let .reject why := decision then
    emit [.log "warning" s!"{a.alias}: {why}"]
    return
  let wait : Wait := if decision == .enqueue then .queued else .ready
  let run : Run := { id := e.nextRunId, autoIdx := ai, triggerId := tv.id, vars,
                     frames := [.seq a.actions false], wait }
  -- `self.last_triggered = utcnow()` once the run is added (queued or not)
  let mut e := { e with
    runs := e.runs ++ [run], nextRunId := e.nextRunId + 1
    lastTriggered := (e.lastTriggered.filter (·.1 != ai)) ++ [(ai, (e.now.utc : Int) * 1000)] }
  if decision == .restart then
    -- "first add the new run and then stop any other runs"
    for old in existing do e := removeRun e old.id
  setE e
  emit [.automationTriggered a.id a.alias tv.description]
  if wait == .ready then drive run

/-- A trigger of `o` fired: start the automation, or complete the wait
(`_async_step_wait_for_trigger.async_done`: `wait.remaining`, `completed`,
`trigger`). Listeners stay until the run resumes, so another trigger of the
same wait firing in the same round overwrites `wait.trigger`, as in HA. -/
def fire (o : Owner) (tv : TriggerVars) : EM Unit := do
  match o with
  | .auto ai => triggerAutomation ai tv
  | .wait rid =>
    let e ← getE
    let some w := e.waitTrigs.find? (·.runId == rid) | return
    let some r := e.runs.find? (·.id == rid) | return
    let rem : Template.Value := if w.hasTimeout then .opaque "wait.remaining" else .none
    let r := { r with wait := .ready,
                      vars := setWaitFields r.vars [("remaining", rem), ("completed", .bool true), ("trigger", tv.value)] }
    let e := replaceRun e r
    setE { e with woken := if e.woken.contains rid then e.woken else e.woken ++ [rid] }

/-- Run what is scheduled for after the current callbacks, in order: runs
whose `wait_for_trigger` completed (their triggers are removed first),
`parallel` branches, and parents whose branches are all done. Runs started
here can schedule more. -/
partial def resumeWoken : EM Unit := do
  let ws := (← getE).woken
  if ws.isEmpty then return
  setE { (← getE) with woken := [] }
  for rid in ws do
    setE (cleanupWait (← getE) rid)
    if let some r := (← getE).runs.find? (·.id == rid) then
      if r.wait == .ready then drive r
  resumeWoken

/-- Every trigger listener, in registration order: the automations', then
those of waiting runs. -/
def Engine.owners (e : Engine) : List (Owner × List Trigger) :=
  e.automations.zipIdx.map (fun (a, ai) => (Owner.auto ai, a.triggers))
    ++ e.waitTrigs.map fun w => (Owner.wait w.runId, w.triggers)

/-- A wait's listeners are gone once its run resumed, timed out or stopped. -/
def Engine.listening (e : Engine) : Owner → Bool
  | .auto _ => true
  | .wait rid => e.waitTrigs.any (·.runId == rid)

/-! ## Triggers -/

/-- `state.py::call_action` -/
def stateTriggerVars (t : Trigger) (eid : String) (old new : Option EntityState)
    (attr : Option String) (forV : Template.Value) : TriggerVars :=
  { id := t.id, idx := t.idx, platform := "state", entityId := some eid,
    description := s!"state of {eid}",
    value := triggerValue t "state" [
      ("entity_id", .str eid), ("from_state", stateVal old), ("to_state", stateVal new),
      ("for", forV), ("attribute", match attr with | some a => .str a | none => .none),
      ("description", .str s!"state of {eid}")] }

/-- `template.render_complex(time_delta, variables)` then
`cv.positive_time_period`, as state, numeric_state and template triggers do
for a templated `for:`. `variables` are the trigger-time variables
(`trigger_variables`) with the platform's `trigger` mapping on top. Returns
microseconds. -/
def renderPeriod (e : Engine) (o : Owner) (c : Complex) (trig : Template.Value) :
    Except String Int := do
  let vars := ("trigger", trig) :: ((tmplCtxOf e o).vars.filter (·.1 != "trigger"))
  let v ← renderComplexV { e.condEnv with vars } c
  cvPositiveTimePeriod v

/-- Record `period[entity] = us` and start a `for:` timer that reads it. -/
def addPeriodPending (o : Owner) (key : Owner × Nat × String) (us : Int) (check : SameCheck)
    (tv : TriggerVars) : EM Unit := do
  let e ← getE
  setE { e with
    periods := (e.periods.filter (·.1 != key)) ++ [(key, us)],
    nextPendingId := e.nextPendingId + 1,
    pendings := e.pendings ++ [{
      id := e.nextPendingId, owner := o, entity := key.2.2,
      fireAt := e.now.utc + usToMs us, check, vars := tv, periodKey := some key }] }

/-- The `_LOGGER.error("Error rendering '%s' for template: %s", ...)` of the
state, numeric_state and template triggers when their `for:` fails. -/
def logPeriodError (o : Owner) (msg : String) : EM Unit := do
  let a := (← getE).ownerAuto o
  emit [.log "error" s!"Error rendering '{a.alias}' for template: {msg}"]

/-- `state.py::state_automation_listener` -/
def onStateTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .state eids fromM toM matchAll attr forP fromKeyOnly := t.kind | return
  if !eids.contains eid then return
  let oldV := valueOf attr old
  let newV := valueOf attr new
  if attr.isSome && oldV == newV then return
  if !fromM.matches oldV || !toM.matches newV || (!matchAll && oldV == newV) then return
  let check := if fromKeyOnly then SameCheck.notEqualOld attr oldV else .equalNew attr newV
  match forP with
  | none => fire o (stateTriggerVars t eid old new attr .none)
  -- `if not time_delta: call_action()` with `for` = the static period
  | some (.fixed 0) => fire o (stateTriggerVars t eid old new attr (forVal (some 0)))
  | some (.fixed p) =>
    let e ← getE
    setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
      [{ id := e.nextPendingId, owner := o, entity := eid, fireAt := e.now.utc + p, check,
         vars := stateTriggerVars t eid old new attr (forVal (some p)) }] }
  | some (.tmpl c) =>
    let trig : Template.Value := .dict [(.str "platform", .str "state"), (.str "entity_id", .str eid),
      (.str "from_state", stateVal old), (.str "to_state", stateVal new)]
    match renderPeriod (← getE) o c trig with
    | .error m => logPeriodError o m
    | .ok us =>
      addPeriodPending o (o, t.idx, eid) us check (stateTriggerVars t eid old new attr (.timedelta us))

/-- `numeric_state.py::state_automation_listener` -/
def onNumericTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .numericState eids below above attr forP vtm := t.kind | return
  if !eids.contains eid then return
  let some to := new | return
  let e ← getE
  let vt := vtm.map fun tm => (tm, (tmplCtxOf e o).vars ++ [("trigger", numericTriggerVar t eid below above attr)])
  match numericStateOf e.condEnv to below above attr vt with
  | .error m => emit [.log "warning" s!"Error in numeric_state trigger: {m}"]
  | .ok false =>
    if !e.armed.contains (o, t.idx, eid) then
      setE { e with armed := e.armed ++ [(o, t.idx, eid)] }
  | .ok true =>
    if e.armed.contains (o, t.idx, eid) then
      let e := { e with armed := e.armed.filter (· != (o, t.idx, eid)) }
      setE e
      let tv (forV : Template.Value) : TriggerVars := {
        id := t.id, idx := t.idx, platform := "numeric_state",
        entityId := some eid, description := s!"numeric state of {eid}",
        value := triggerValue t "numeric_state" [
          -- `numeric_state.py::call_action`: no `attribute` key (unlike the
          -- variables its value_template sees)
          ("entity_id", .str eid), ("below", boundVal below), ("above", boundVal above),
          ("from_state", stateVal old), ("to_state", stateVal new), ("for", forV),
          ("description", .str s!"numeric state of {eid}")] }
      match forP with
      | none => fire o (tv .none)
      | some (.fixed 0) => fire o (tv (forVal (some 0)))
      | some (.fixed p) =>
        setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
          [{ id := e.nextPendingId, owner := o, entity := eid, fireAt := e.now.utc + p,
             check := .numeric below above attr vt, vars := tv (forVal (some p)) }] }
      | some (.tmpl c) =>
        -- rendered after the entity is disarmed: an error leaves it disarmed
        match renderPeriod e o c (numericTriggerVar t eid below above attr) with
        | .error m => logPeriodError o m
        | .ok us =>
          addPeriodPending o (o, t.idx, eid) us (.numeric below above attr vt) (tv (.timedelta us))

/-- `_check_same_state` / `check_numeric_state_no_raise` -/
def sameStillHolds (env : CondEnv) (c : SameCheck) (new : Option EntityState) : Bool :=
  match new with
  | none => false
  | some s =>
    match c with
    | .equalNew attr v => valueOf attr (some s) == v
    | .notEqualOld attr v => valueOf attr (some s) != v
    | .numeric below above attr vt =>
      match numericStateOf env s below above attr vt with
      | .ok b => b
      | .error _ => false
    | .always => true


def getTT (o : Owner) (idx : Nat) : EM (Option TmplTrig) := do
  return (← getE).tmplTrigs.find? (fun x => x.tmpl.isNone && x.owner == o && x.trigIdx == idx)

def saveTT (st : TmplTrig) : EM Unit := do
  let e ← getE
  setE { e with tmplTrigs := e.tmplTrigs.map fun x => if x.sameKey st then st else x }

/-- `template/trigger.py::template_listener`, called with the tracker's
update. `ev` is the state change that caused it (`none` for the time
listener). -/
def templateListener (o : Owner) (t : Trigger) (forP : Option ForPeriod) (st : TmplTrig)
    (r : Except String Template.Value) (ev : Option Deferred) : EM Unit := do
  match r with
  | .error msg =>
    saveTT st
    emit [.log "warning" s!"Error evaluating 'template' trigger: {msg}"]
  | .ok v =>
    -- `delay_cancel()`
    if let some pid := st.pending then
      let e ← getE
      setE { e with pendings := e.pendings.filter (·.id != pid) }
    let st := { st with pending := none }
    if !Template.resultAsBoolean v then
      saveTT { st with armed := true }
      return
    if !st.armed then
      saveTT st
      return
    let st := { st with armed := false }
    let (eidV, oldV, newV, desc) := match ev with
      | some (eid, old, new) => (Template.Value.str eid, stateVal old, stateVal new, s!"{eid} via template")
      | none => (.none, .none, .none, "time change or manual update via template")
    let tv (forV : Template.Value) : TriggerVars := {
      id := t.id, idx := t.idx, platform := "template", entityId := ev.map (·.1),
      description := desc,
      value := triggerValue t "template" [
        ("entity_id", eidV), ("from_state", oldV), ("to_state", newV),
        ("for", forV), ("description", .str desc)] }
    -- `delay_cancel = async_call_later(hass, period, call_action)`
    let later (ms : Nat) (forV : Template.Value) : EM Unit := do
      let e ← getE
      let pid := e.nextPendingId
      setE { e with nextPendingId := pid + 1, pendings := e.pendings ++
        [{ id := pid, owner := o, entity := "", fireAt := e.now.utc + ms, check := .always, vars := tv forV }] }
      saveTT { st with pending := some pid }
    match forP with
    | none =>
      saveTT st
      fire o (tv .none)
    | some (.fixed 0) =>
      saveTT st
      fire o (tv (forVal (some 0)))
    | some (.fixed p) => later p (forVal (some p))
    | some (.tmpl c) =>
      -- `period_variables`: the trigger variables and `template_variables`
      let trig : Template.Value := .dict [(.str "platform", .str "template"), (.str "entity_id", eidV),
        (.str "from_state", oldV), (.str "to_state", newV)]
      match renderPeriod (← getE) o c trig with
      | .error m =>
        saveTT st
        logPeriodError o m
      | .ok us => later (usToMs us) (.timedelta us)

/-- Render now (`_rate_limit.async_triggered` + `async_render_to_info`), and
pass a changed result on to the listener. Error after error, or an equal
result, is not a change; the first render after setup always is. -/
def templateRefresh (o : Owner) (t : Trigger) (ev : Option Deferred) : EM Unit := do
  let .template tm forP := t.kind | return
  let some st ← getTT o t.idx | return
  let e ← getE
  let (r, info) := Template.renderWithInfo tm (tmplCtxOf e o) true
  let st := { st with info, lastTriggered := some e.now.utc, rlTimer := none }
  if !resultChanged st.last r then
    saveTT st
    return
  let st := { st with last := some (TmplResult.of r) }
  templateListener o t forP st r ev

/-- The rest of `_refresh` for a state change: `_event_triggers_rerender`,
then `KeyedRateLimit.async_schedule_action` (entities the template named are
exempt). True when the tracker should render now; a deferred change is
saved for the rate limiter's timer. -/
def trackerGate (st : TmplTrig) (eid : String) (old new : Option EntityState)
    (replay : Bool) : EM Bool := do
  if !replay && !st.info.listens eid st.rlTimer.isSome then return false
  let lifecycle := old.isNone || new.isNone
  if !(st.info.filter eid || (lifecycle && st.info.filterLifecycle eid)) then return false
  let now := (← getE).now.utc
  let limit := if st.info.entities.contains eid then none else st.info.rateLimit
  if let (some secs, some last) := (limit, st.lastTriggered) then
    let due := last + secs * 1000
    if due > now then
      if st.rlTimer.isNone then saveTT { st with rlTimer := some (due, (eid, old, new)) }
      return false
  return true

/-- A wait's tracker rendered (`async_track_template`'s
`_template_changed_listener`): an error is logged; the wait completes when
the result is true and the previous one was not. The run resumes later, so
returns its id. `wait.remaining` is read from the event loop's clock
(`timeout_handle.when() - loop.time()`), which HALean does not model: it is
an error to use it. -/
def waitRefresh (st : TmplTrig) : EM (Option Nat) := do
  let (some t, .wait rid) := (st.tmpl, st.owner) | return none
  let e ← getE
  let (r, info) := Template.renderWithInfo t { states := e.states, now := e.now, vars := st.vars } true
  let prev := st.last
  let st := { st with info, lastTriggered := some e.now.utc, rlTimer := none }
  if !resultChanged prev r then
    saveTT st
    return none
  saveTT { st with last := some (TmplResult.of r) }
  match r with
  | .error _ =>
    emit [.log "error" s!"Error while processing template: {t.src}"]
    return none
  | .ok v =>
    let wasTrue := match prev with | some (.ok lv) => Template.resultAsBoolean lv | _ => false
    if wasTrue || !Template.resultAsBoolean v then return none
    let e ← getE
    let some run := e.runs.find? (·.id == rid) | return none
    let .waitTmpl _ deadline _ := run.wait | return none
    let rem : Template.Value := if deadline.isSome then .opaque "wait.remaining" else .none
    let run := { run with wait := .ready, vars := setVar run.vars "wait" (waitVar rem true) }
    setE { replaceRun e run with tmplTrigs := e.tmplTrigs.filter (·.owner != .wait rid) }
    return some rid

/-- Continue runs whose wait completed (their task wakes up after the
callbacks of the current event). -/
def resumeRuns (rids : List Nat) : EM Unit := do
  for rid in rids do
    if let some r := (← getE).runs.find? (·.id == rid) then
      if r.wait == .ready then drive r

/-- Wait trackers for a state change, oldest first. -/
def onWaitTrackers (eid : String) (old new : Option EntityState) : EM (List Nat) := do
  let mut done := []
  for st0 in (← getE).tmplTrigs do
    if st0.tmpl.isNone then continue
    let some st := (← getE).tmplTrigs.find? (·.sameKey st0) | continue
    if ← trackerGate st eid old new false then
      if let some rid ← waitRefresh st then done := done ++ [rid]
  return done

/-- `TrackTemplateResultInfo._refresh` for a state change (or the replay of
one the rate limiter deferred): `_event_triggers_rerender`, then
`KeyedRateLimit.async_schedule_action` (entities the template named are
exempt), then render. -/
def onTemplateTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState)
    (replay : Bool := false) : EM Unit := do
  let .template .. := t.kind | return
  let some st ← getTT o t.idx | return
  if ← trackerGate st eid old new replay then
    templateRefresh o t (some (eid, old, new))

/-- `zone/trigger.py::LegacyZoneTrigger.zone_automation_listener` -/
def onZoneTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .zone eids zoneId enter := t.kind | return
  if !eids.contains eid then return
  -- states that cannot be matched against a zone are ignored
  if (old.map (!stateHasZoneInfo ·)).getD false || (new.map (!stateHasZoneInfo ·)).getD false then return
  let e ← getE
  let some zs := e.states.get? zoneId |
    emit [.log "warning" s!"Non-existing zone '{zoneId}' in a zone trigger"]
  let check (s : Option EntityState) : Except String Bool :=
    match s with
    | some s => zoneCondition zs s
    | none => .ok false
  -- an exception in the listener is logged by the event bus
  let r : Except String (Option String) := do
    let fromM ← check old
    let toM ← check new
    if (enter && !fromM && toM) || (!enter && fromM && !toM) then
      let name ← match zs.attr? "friendly_name" with
        | some (.str n) => pure n
        | some v => Template.pyStr (Template.Value.ofJson v)
        | none => throw "KeyError: 'friendly_name'"
      let verb := if enter then "entering" else "leaving"
      pure (some s!"{eid} {verb} {name}")
    else pure none
  match r with
  | .error m => emit [.log "error" s!"Error in zone trigger listener: {m}"]
  | .ok none => pure ()
  | .ok (some desc) =>
    -- `run_action({...}, description)`: trigger_data, platform, description,
    -- then the payload
    let value := triggerValue t "zone" [("description", .str desc), ("entity_id", .str eid),
      ("from_state", stateVal old), ("to_state", stateVal new), ("zone", .state zs false),
      ("event", .str (if enter then "enter" else "leave"))]
    fire o { id := t.id, idx := t.idx, platform := "zone", entityId := some eid,
             description := desc, value }

def onStateChanged (eid : String) (old new : Option EntityState) : EM Unit := do
  -- the state machine is updated before listeners run
  let e ← getE
  let states := match new with
    | some s => e.states.set s
    | none => e.states.remove eid
  setE { e with states }
  for (o, trigs) in (← getE).owners do
    for t in trigs do
      if !(← getE).listening o then break
      match t.kind with
      | .state .. => onStateTrigger o t eid old new
      | .numericState .. => onNumericTrigger o t eid old new
      | .template .. => onTemplateTrigger o t eid old new
      | .zone .. => onZoneTrigger o t eid old new
      | _ => pure ()
  let done ← onWaitTrackers eid old new
  -- `state_for_cancel_listener`s: drop timers whose condition broke
  let e ← getE
  setE { e with pendings := e.pendings.filter fun p =>
    p.entity != eid || sameStillHolds e.condEnv p.check new }
  resumeRuns done
  resumeWoken

/-- `event.py` (flat event_data: subset match) -/
def onEvent (ty : String) (data : Json) : EM Unit := do
  for (o, trigs) in (← getE).owners do
    for t in trigs do
      if !(← getE).listening o then break
      if let .event types want := t.kind then
        if types.contains ty && want.all (fun (k, v) => field? data k == some v) then
          let ev : Template.Value := .pyobj "Event" [
            ("event_type", .str ty), ("data", Template.Value.ofJson data),
            ("origin", .opaque "event.origin"), ("time_fired", .opaque "datetime"),
            ("context", .opaque "context")]
          fire o {
            id := t.id, idx := t.idx, platform := "event",
            description := s!"event '{ty}'",
            value := triggerValue t "event" [("event", ev), ("description", .str s!"event '{ty}'")] }

def Pattern.matches (p : Pattern) (v : Nat) : Bool :=
  match p with
  | .any => true
  | .every n => v % n == 0
  | .exact n => v == n

/-- HA fires each time-change tracker at a random microsecond in
`RANDOM_MICROSECOND_MIN..RANDOM_MICROSECOND_MAX` (50 000..500 000) into the
matching second, and `trigger.now` is the time the callback ran. HALean uses
the top of that range (what HA's own test harness produces). -/
def TIME_CHANGE_MICROSECOND : Int := 500000

/-- Time and time-pattern triggers for one whole local second. -/
def fireTimeTriggers (sec : Nat) (tz : Int) : EM Unit := do
  let inst : Instant := { utc := sec * 1000, tzOffsetSec := tz }
  let tod := inst.timeOfDay / 1000
  let (h, m, s) := (tod / 3600, tod / 60 % 60, tod % 60)
  for (o, trigs) in (← getE).owners do
    for t in trigs do
      if !(← getE).listening o then break
      match t.kind with
      | .time ats wd =>
        if ats.contains tod && (wd.map (·.contains inst.weekday)).getD true then
          fire o {
            id := t.id, idx := t.idx, platform := "time",
            description := "time",
            value := triggerValue t "time" [("now", .datetime (sec * 1000000 + TIME_CHANGE_MICROSECOND) (some tz)),
              ("description", .str "time"), ("entity_id", .none)] }
      | .template .. =>
        -- `async_track_utc_time_change(second=0)` while the last render used the clock
        if sec % 60 == 0 then
          if let some st ← getTT o t.idx then
            if st.info.hasTime then templateRefresh o t none
      | .timePattern ph pm ps =>
        if ph.matches h && pm.matches m && ps.matches s then
          fire o {
            id := t.id, idx := t.idx, platform := "time_pattern",
            description := "time pattern",
            value := triggerValue t "time_pattern" [("now", .datetime (sec * 1000000 + TIME_CHANGE_MICROSECOND) (some tz)),
              ("description", .str "time pattern")] }
      | _ => pure ()
  -- the time listener of wait trackers whose last render used the clock
  if sec % 60 == 0 then
    let mut done := []
    for st in (← getE).tmplTrigs do
      if st.tmpl.isSome && st.info.hasTime then
        if let some rid ← waitRefresh st then done := done ++ [rid]
    resumeRuns done
  resumeWoken

/-- Fire everything due at or before `t`: `for:` timers and delays. -/
partial def fireDue (t : Millis) : EM Unit := do
  let e ← getE
  -- earliest pending timer
  -- earliest due timer; ties in creation order
  let p? := (e.pendings.filter (·.fireAt ≤ t)).foldl (fun acc p => match acc with
    | some q => if p.fireAt < q.fireAt then some p else acc
    | none => some p) none
  let d? := e.runs.find? fun r => match r.wait with
    | .delayUntil w => w ≤ t
    | .waitTmpl _ (some w) _ => w ≤ t
    | .waitTrig _ _ (some w) _ => w ≤ t
    | _ => false
  let rl? := e.tmplTrigs.find? fun x => match x.rlTimer with
    | some (due, _) => due ≤ t
    | none => false
  match p?, d? with
  | some p, _ =>
    setE { e with pendings := e.pendings.filter (·.id != p.id) }
    -- `"for": period[entity]` is read when `call_action` runs
    let vars := match p.periodKey.bind fun k => e.periods.find? (·.1 == k) with
      | some (_, us) => p.vars.withFor (.timedelta us)
      | none => p.vars
    fire p.owner vars
    resumeWoken
    fireDue t
  | none, some r =>
    match r.wait with
    | .waitTmpl _ _ cot | .waitTrig _ _ _ cot =>
      -- the wait's timeout: `_async_handle_timeout`, then `unsub()`
      let r := { r with wait := .ready, vars := setWaitFields r.vars [("remaining", .float 0)] }
      setE (cleanupWait (replaceRun e r) r.id)
      if cot then drive r
      else
        emit [.log "info" TIMEOUT_MSG]
        finishRun r (.aborted TIMEOUT_MSG)
    | _ =>
      let r := { r with wait := .ready }
      setE (replaceRun e r)
      drive r
    resumeWoken
    fireDue t
  | none, none =>
    match rl? with
    | some x =>
      -- the rate limiter's `call_later` replays the deferred event
      let some (_, (eid, old, new)) := x.rlTimer | pure ()
      let x := { x with rlTimer := none }
      saveTT x
      if x.tmpl.isSome then
        if ← trackerGate x eid old new true then
          if let some rid ← waitRefresh x then resumeRuns [rid]
      else
        let trigs := ((e.owners.find? (·.1 == x.owner)).map (·.2)).getD []
        if let some t := trigs.find? (·.idx == x.trigIdx) then
          onTemplateTrigger x.owner t eid old new (replay := true)
          resumeWoken
      fireDue t
    | none => pure ()

/-- `sun` triggers due at or before `t` (ms): schedule the next event, then
run the action (`handle_event`). -/
partial def fireSun (t : Millis) : EM Unit := do
  let e ← getE
  let some ((o, idx), at_) := e.sunNext.find? (·.2 ≤ (t : Int) * 1000) | return
  let trig? := ((e.owners.find? (·.1 == o)).map (·.2)).bind fun ts => ts.find? (·.idx == idx)
  let rest := e.sunNext.filter (·.1 != (o, idx))
  match trig?, e.location with
  | some tr, some obs =>
    let .sun sunrise off := tr.kind | setE { e with sunNext := rest }
    -- `utcnow()` when the timer runs is the event's instant
    let nxt := Sun.nextEvent obs sunrise at_ e.now.tzOffsetSec off
    setE { e with sunNext := rest ++ (nxt.map (fun n => ((o, idx), n))).toList }
    let ev := if sunrise then "sunrise" else "sunset"
    let desc := s!"sun event {ev}"
    fire o { id := tr.id, idx := tr.idx, platform := "sun", description := desc,
             value := triggerValue tr "sun" [("description", .str desc), ("event", .str ev),
               ("offset", .timedelta off)] }
    resumeWoken
  | _, _ => setE { e with sunNext := rest }
  fireSun t

/-- Advance the clock to `now`, firing time triggers second by second. -/
def advanceTo (now : Instant) : EM Unit := do
  let e ← getE
  let target := now.utc / 1000
  -- bound catch-up to one day if the shell stalled
  let start := max (e.lastSec + 1) (if target > 86400 then target - 86400 else 0)
  for sec in List.range' start (target + 1 - start) do
    let e ← getE
    setE { e with now := { utc := sec * 1000, tzOffsetSec := now.tzOffsetSec } }
    fireDue (sec * 1000)
    fireSun (sec * 1000)
    fireTimeTriggers sec now.tzOffsetSec
    -- a templated `for:` that rendered to 0 is due at once
    fireDue (sec * 1000)
  let e ← getE
  setE { e with now := now, lastSec := max e.lastSec target }
  fireDue now.utc

def initArmed : EM Unit := do
  for (a, ai) in (← getE).automations.zipIdx do
    attachTriggers (.auto ai) a.triggers

def handle : Input → EM Unit
  | .init autos sts now loc => do
    setE { automations := autos, states := sts.map (fun s => (s.entityId, s)),
           now, lastSec := now.utc / 1000, location := loc }
    initArmed
  | .stateChanged eid old new now => do
    advanceTo now
    onStateChanged eid old new
    -- `async_call_later(hass, 0, ...)`: a templated `for:` that rendered to 0
    -- fires on the next loop iteration, before the next input
    fireDue now.utc
  | .event ty data now => do advanceTo now; onEvent ty data; resumeWoken
  | .tick now => advanceTo now
  | .serviceResult cid ok kind msg now resp => do
    advanceTo now
    let e ← getE
    let some r := e.runs.find? (fun r => match r.wait with
        | .service c .. => c == cid
        | _ => false) |
      return  -- run was stopped meanwhile (restart): ignore
    match resumeService r ok kind msg resp with
    | .next r' => setE (replaceRun e r'); drive r'
    | .blocked r' | .spawn r' .. => setE (replaceRun e r')  -- not produced by resumeService
    | .done end_ => finishRun r end_
    resumeWoken

/-- The engine's single entry point. -/
def Engine.step (e : Engine) (i : Input) : Engine × List Cmd :=
  let ((), (e', cmds)) := (handle i).run (e, [])
  (e', cmds)

end HALean.Automation
