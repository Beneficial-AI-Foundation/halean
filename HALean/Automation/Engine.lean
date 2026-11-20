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
  autoIdx : Nat
  trigIdx : Nat
  armed : Bool := false
  last : Option TmplResult := none
  pending : Option Nat := none
  info : Template.RInfo := {}
  lastTriggered : Option Millis := none
  /-- The rate limiter's timer: when it fires and the event it replays. -/
  rlTimer : Option (Millis × Deferred) := none
  deriving Repr, Inhabited

/-- A pending `for:` timer created by `async_track_same_state`. -/
structure PendingFor where
  id : Nat := 0
  autoIdx : Nat
  entity : String
  fireAt : Millis
  check : SameCheck
  vars : TriggerVars
  /-- For a templated `for:` of a state or numeric_state trigger: the key of
  the trigger's `period[entity]`, which `call_action` reads when it fires. -/
  periodKey : Option (Nat × Nat × String) := none
  deriving Repr, Inhabited

structure Engine where
  automations : List Automation := []
  states : States := []
  now : Instant := {utc := 0}
  pendings : List PendingFor := []
  /-- numeric_state `armed_entities`: (automation, trigger idx, entity) -/
  armed : List (Nat × Nat × String) := []
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
  periods : List ((Nat × Nat × String) × Int) := []
  deriving Inhabited

inductive Input where
  | init (automations : List Automation) (states : List EntityState) (now : Instant)
  | stateChanged (entityId : String) (old new : Option EntityState) (now : Instant)
  | event (eventType : String) (data : Json) (now : Instant)
  | tick (now : Instant)
  | serviceResult (callId : Nat) (ok : Bool) (kind : ErrKind) (msg : String) (now : Instant)

abbrev EM := StateM (Engine × List Cmd)

def emit (cs : List Cmd) : EM Unit := modify fun (e, acc) => (e, acc ++ cs)
def getE : EM Engine := return (← get).1
def setE (e : Engine) : EM Unit := modify fun (_, acc) => (e, acc)

def Engine.condEnv (e : Engine) : CondEnv := { states := e.states, now := e.now }

/-- What trigger templates see: the static `trigger_variables`. -/
def tmplCtxOf (e : Engine) (ai : Nat) : Template.Ctx :=
  { states := e.states, now := e.now,
    vars := ((e.automations.getD ai default).triggerVars.map fun (k, v) => (k, Template.Value.ofJson v)) }

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

def runsOf (e : Engine) (ai : Nat) : List Run := e.runs.filter (·.autoIdx == ai)

def replaceRun (e : Engine) (r : Run) : Engine :=
  { e with runs := e.runs.map fun x => if x.id == r.id then r else x }

def removeRun (e : Engine) (id : Nat) : Engine :=
  { e with runs := e.runs.filter (·.id != id) }

mutual
/-- Drive a run until it blocks or ends; on end, `_finish` it (which for a
queued script releases the lock to the next waiter). -/
partial def drive (r : Run) : EM Unit := do
  let e ← getE
  let (res, cmds, ctx) := exec { env := e.condEnv, nextCallId := e.nextCallId } r
  setE { e with nextCallId := ctx.nextCallId }
  emit cmds
  match res with
  | .inl (some r') => setE (replaceRun (← getE) r')
  | .inl none => pure ()
  | .inr end_ => finishRun r end_

partial def finishRun (r : Run) (end_ : RunEnd) : EM Unit := do
  let e ← getE
  let a := e.automations.getD r.autoIdx default
  match end_ with
  | .error m => emit [.log "error" s!"Error while executing automation {a.alias}: {m}"]
  | .aborted m => emit [.log "debug" s!"{a.alias} aborted: {m}"]
  | .finished => pure ()
  setE (removeRun e r.id)
  -- `_QueuedScriptRun._finish` releases the FIFO lock
  if a.mode == .queued then
    let e ← getE
    if (runsOf e r.autoIdx).all (·.wait == .queued) then
      if let some nxt := (runsOf e r.autoIdx).head? then
        setE (replaceRun e { nxt with wait := .ready })
        drive { nxt with wait := .ready }
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
    [("last_triggered", lt), ("mode", .str mode), ("current", .int (e.runs.filter (·.autoIdx == ai)).length)] ++
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
def renderPeriod (e : Engine) (ai : Nat) (c : Complex) (trig : Template.Value) :
    Except String Int := do
  let vars := ("trigger", trig) :: ((tmplCtxOf e ai).vars.filter (·.1 != "trigger"))
  let v ← renderComplexV { e.condEnv with vars } c
  cvPositiveTimePeriod v

/-- Record `period[entity] = us` and start a `for:` timer that reads it. -/
def addPeriodPending (ai : Nat) (key : Nat × Nat × String) (us : Int) (check : SameCheck)
    (tv : TriggerVars) : EM Unit := do
  let e ← getE
  setE { e with
    periods := (e.periods.filter (·.1 != key)) ++ [(key, us)],
    nextPendingId := e.nextPendingId + 1,
    pendings := e.pendings ++ [{
      id := e.nextPendingId, autoIdx := ai, entity := key.2.2,
      fireAt := e.now.utc + usToMs us, check, vars := tv, periodKey := some key }] }

/-- The `_LOGGER.error("Error rendering '%s' for template: %s", ...)` of the
state, numeric_state and template triggers when their `for:` fails. -/
def logPeriodError (ai : Nat) (msg : String) : EM Unit := do
  let a := (← getE).automations.getD ai default
  emit [.log "error" s!"Error rendering '{a.alias}' for template: {msg}"]

/-- `state.py::state_automation_listener` -/
def onStateTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .state eids fromM toM matchAll attr forP fromKeyOnly := t.kind | return
  if !eids.contains eid then return
  let oldV := valueOf attr old
  let newV := valueOf attr new
  if attr.isSome && oldV == newV then return
  if !fromM.matches oldV || !toM.matches newV || (!matchAll && oldV == newV) then return
  let check := if fromKeyOnly then SameCheck.notEqualOld attr oldV else .equalNew attr newV
  match forP with
  | none => triggerAutomation ai (stateTriggerVars t eid old new attr .none)
  -- `if not time_delta: call_action()` with `for` = the static period
  | some (.fixed 0) => triggerAutomation ai (stateTriggerVars t eid old new attr (forVal (some 0)))
  | some (.fixed p) =>
    let e ← getE
    setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
      [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p, check,
         vars := stateTriggerVars t eid old new attr (forVal (some p)) }] }
  | some (.tmpl c) =>
    let trig : Template.Value := .dict [(.str "platform", .str "state"), (.str "entity_id", .str eid),
      (.str "from_state", stateVal old), (.str "to_state", stateVal new)]
    match renderPeriod (← getE) ai c trig with
    | .error m => logPeriodError ai m
    | .ok us =>
      addPeriodPending ai (ai, t.idx, eid) us check (stateTriggerVars t eid old new attr (.timedelta us))

/-- `numeric_state.py::state_automation_listener` -/
def onNumericTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .numericState eids below above attr forP vtm := t.kind | return
  if !eids.contains eid then return
  let some to := new | return
  let e ← getE
  let vt := vtm.map fun tm => (tm, (tmplCtxOf e ai).vars ++ [("trigger", numericTriggerVar t eid below above attr)])
  match numericStateOf e.condEnv to below above attr vt with
  | .error m => emit [.log "warning" s!"Error in numeric_state trigger: {m}"]
  | .ok false =>
    if !e.armed.contains (ai, t.idx, eid) then
      setE { e with armed := e.armed ++ [(ai, t.idx, eid)] }
  | .ok true =>
    if e.armed.contains (ai, t.idx, eid) then
      let e := { e with armed := e.armed.filter (· != (ai, t.idx, eid)) }
      setE e
      let tv (forV : Template.Value) : TriggerVars := {
        id := t.id, idx := t.idx, platform := "numeric_state",
        entityId := some eid, description := s!"numeric state of {eid}",
        value := triggerValue t "numeric_state" [
          ("entity_id", .str eid), ("below", boundVal below), ("above", boundVal above),
          ("attribute", match attr with | some a => .str a | none => .none),
          ("from_state", stateVal old), ("to_state", stateVal new), ("for", forV),
          ("description", .str s!"numeric state of {eid}")] }
      match forP with
      | none => triggerAutomation ai (tv .none)
      | some (.fixed 0) => triggerAutomation ai (tv (forVal (some 0)))
      | some (.fixed p) =>
        setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
          [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p,
             check := .numeric below above attr vt, vars := tv (forVal (some p)) }] }
      | some (.tmpl c) =>
        -- rendered after the entity is disarmed: an error leaves it disarmed
        match renderPeriod e ai c (numericTriggerVar t eid below above attr) with
        | .error m => logPeriodError ai m
        | .ok us =>
          addPeriodPending ai (ai, t.idx, eid) us (.numeric below above attr vt) (tv (.timedelta us))

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


def getTT (ai idx : Nat) : EM (Option TmplTrig) := do
  return (← getE).tmplTrigs.find? (fun x => x.autoIdx == ai && x.trigIdx == idx)

def saveTT (st : TmplTrig) : EM Unit := do
  let e ← getE
  setE { e with tmplTrigs := e.tmplTrigs.map fun x =>
    if x.autoIdx == st.autoIdx && x.trigIdx == st.trigIdx then st else x }

/-- `template/trigger.py::template_listener`, called with the tracker's
update. `ev` is the state change that caused it (`none` for the time
listener). -/
def templateListener (ai : Nat) (t : Trigger) (forP : Option ForPeriod) (st : TmplTrig)
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
        [{ id := pid, autoIdx := ai, entity := "", fireAt := e.now.utc + ms, check := .always, vars := tv forV }] }
      saveTT { st with pending := some pid }
    match forP with
    | none =>
      saveTT st
      triggerAutomation ai (tv .none)
    | some (.fixed 0) =>
      saveTT st
      triggerAutomation ai (tv (forVal (some 0)))
    | some (.fixed p) => later p (forVal (some p))
    | some (.tmpl c) =>
      -- `period_variables`: the trigger variables and `template_variables`
      let trig : Template.Value := .dict [(.str "platform", .str "template"), (.str "entity_id", eidV),
        (.str "from_state", oldV), (.str "to_state", newV)]
      match renderPeriod (← getE) ai c trig with
      | .error m =>
        saveTT st
        logPeriodError ai m
      | .ok us => later (usToMs us) (.timedelta us)

/-- Render now (`_rate_limit.async_triggered` + `async_render_to_info`), and
pass a changed result on to the listener. Error after error, or an equal
result, is not a change; the first render after setup always is. -/
def templateRefresh (ai : Nat) (t : Trigger) (ev : Option Deferred) : EM Unit := do
  let .template tm forP := t.kind | return
  let some st ← getTT ai t.idx | return
  let e ← getE
  let (r, info) := Template.renderWithInfo tm (tmplCtxOf e ai) true
  let st := { st with info, lastTriggered := some e.now.utc, rlTimer := none }
  let changed := match st.last, r with
    | none, _ => true
    | some (.ok a), .ok b => !Template.pyEq a b
    | some .err, .error _ => false
    | _, _ => true
  if !changed then
    saveTT st
    return
  let st := { st with last := some (match r with | .ok v => .ok v | .error _ => .err) }
  templateListener ai t forP st r ev

/-- `TrackTemplateResultInfo._refresh` for a state change (or the replay of
one the rate limiter deferred): `_event_triggers_rerender`, then
`KeyedRateLimit.async_schedule_action` (entities the template named are
exempt), then render. -/
def onTemplateTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState)
    (replay : Bool := false) : EM Unit := do
  let .template .. := t.kind | return
  let some st ← getTT ai t.idx | return
  if !replay && !st.info.listens eid st.rlTimer.isSome then return
  let lifecycle := old.isNone || new.isNone
  if !(st.info.filter eid || (lifecycle && st.info.filterLifecycle eid)) then return
  let now := (← getE).now.utc
  let limit := if st.info.entities.contains eid then none else st.info.rateLimit
  if let (some secs, some last) := (limit, st.lastTriggered) then
    let due := last + secs * 1000
    if due > now then
      if st.rlTimer.isNone then saveTT { st with rlTimer := some (due, (eid, old, new)) }
      return
  templateRefresh ai t (some (eid, old, new))

def onStateChanged (eid : String) (old new : Option EntityState) : EM Unit := do
  -- the state machine is updated before listeners run
  let e ← getE
  let states := match new with
    | some s => e.states.set s
    | none => e.states.remove eid
  setE { e with states }
  let autos := (← getE).automations
  for (a, ai) in autos.zipIdx do
    for t in a.triggers do
      match t.kind with
      | .state .. => onStateTrigger ai t eid old new
      | .numericState .. => onNumericTrigger ai t eid old new
      | .template .. => onTemplateTrigger ai t eid old new
      | _ => pure ()
  -- `state_for_cancel_listener`s: drop timers whose condition broke
  let e ← getE
  setE { e with pendings := e.pendings.filter fun p =>
    p.entity != eid || sameStillHolds e.condEnv p.check new }

/-- `event.py` (flat event_data: subset match) -/
def onEvent (ty : String) (data : Json) : EM Unit := do
  let autos := (← getE).automations
  for (a, ai) in autos.zipIdx do
    for t in a.triggers do
      if let .event types want := t.kind then
        if types.contains ty && want.all (fun (k, v) => field? data k == some v) then
          let ev : Template.Value := .pyobj "Event" [
            ("event_type", .str ty), ("data", Template.Value.ofJson data),
            ("origin", .opaque "event.origin"), ("time_fired", .opaque "datetime"),
            ("context", .opaque "context")]
          triggerAutomation ai {
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
  let autos := (← getE).automations
  for (a, ai) in autos.zipIdx do
    for t in a.triggers do
      match t.kind with
      | .time ats wd =>
        if ats.contains tod && (wd.map (·.contains inst.weekday)).getD true then
          triggerAutomation ai {
            id := t.id, idx := t.idx, platform := "time",
            description := "time",
            value := triggerValue t "time" [("now", .datetime (sec * 1000000 + TIME_CHANGE_MICROSECOND) (some tz)),
              ("description", .str "time"), ("entity_id", .none)] }
      | .template .. =>
        -- `async_track_utc_time_change(second=0)` while the last render used the clock
        if sec % 60 == 0 then
          if let some st ← getTT ai t.idx then
            if st.info.hasTime then templateRefresh ai t none
      | .timePattern ph pm ps =>
        if ph.matches h && pm.matches m && ps.matches s then
          triggerAutomation ai {
            id := t.id, idx := t.idx, platform := "time_pattern",
            description := "time pattern",
            value := triggerValue t "time_pattern" [("now", .datetime (sec * 1000000 + TIME_CHANGE_MICROSECOND) (some tz)),
              ("description", .str "time pattern")] }
      | _ => pure ()

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
    triggerAutomation p.autoIdx vars
    fireDue t
  | none, some r =>
    let r := { r with wait := .ready }
    setE (replaceRun e r)
    drive r
    fireDue t
  | none, none =>
    match rl? with
    | some x =>
      -- the rate limiter's `call_later` replays the deferred event
      let some (_, (eid, old, new)) := x.rlTimer | pure ()
      saveTT { x with rlTimer := none }
      let a := e.automations.getD x.autoIdx default
      if let some t := a.triggers.find? (·.idx == x.trigIdx) then
        onTemplateTrigger x.autoIdx t eid old new (replay := true)
      fireDue t
    | none => pure ()

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
    fireTimeTriggers sec now.tzOffsetSec
    -- a templated `for:` that rendered to 0 is due at once
    fireDue (sec * 1000)
  let e ← getE
  setE { e with now := now, lastSec := max e.lastSec target }
  fireDue now.utc

def initArmed : EM Unit := do
  let e ← getE
  let mut armed := []
  for (a, ai) in e.automations.zipIdx do
    for t in a.triggers do
      if let .numericState eids below above attr _ vtm := t.kind then
        for eid in eids do
          let vt := vtm.map fun tm => (tm, (tmplCtxOf e ai).vars ++ [("trigger", numericTriggerVar t eid below above attr)])
          -- "Each entity that starts outside the range is already armed"
          if let .ok false := numericStateOne e.condEnv eid below above attr vt then
            armed := armed ++ [(ai, t.idx, eid)]
  -- template triggers: "Arm at setup if the template is already false"
  let mut tts : List TmplTrig := []
  let mut logs : List Cmd := []
  for (a, ai) in e.automations.zipIdx do
    for t in a.triggers do
      if let .template tm _ := t.kind then
        -- the trigger's own first render arms it; the tracker's setup render
        -- (same template, same moment) gives the first render info
        match Template.renderWithInfo tm (tmplCtxOf e ai) true with
        | (.ok v, info) => tts := tts ++ [{ autoIdx := ai, trigIdx := t.idx, armed := !Template.resultAsBoolean v, info }]
        | (.error msg, info) =>
          tts := tts ++ [{ autoIdx := ai, trigIdx := t.idx, info }]
          logs := logs ++ [.log "warning" s!"Error initializing 'template' trigger for '{a.alias}': {msg}"]
  setE { e with armed, tmplTrigs := tts }
  emit logs

def handle : Input → EM Unit
  | .init autos sts now => do
    setE { automations := autos, states := sts.map (fun s => (s.entityId, s)),
           now, lastSec := now.utc / 1000 }
    initArmed
  | .stateChanged eid old new now => do
    advanceTo now
    onStateChanged eid old new
    -- `async_call_later(hass, 0, ...)`: a templated `for:` that rendered to 0
    -- fires on the next loop iteration, before the next input
    fireDue now.utc
  | .event ty data now => do advanceTo now; onEvent ty data
  | .tick now => advanceTo now
  | .serviceResult cid ok kind msg now => do
    advanceTo now
    let e ← getE
    let some r := e.runs.find? (fun r => match r.wait with
        | .service c _ => c == cid
        | _ => false) |
      return  -- run was stopped meanwhile (restart): ignore
    match resumeService r ok kind msg with
    | .next r' => setE (replaceRun e r'); drive r'
    | .blocked r' => setE (replaceRun e r')
    | .done end_ => finishRun r end_

/-- The engine's single entry point. -/
def Engine.step (e : Engine) (i : Input) : Engine × List Cmd :=
  let ((), (e', cmds)) := (handle i).run (e, [])
  (e', cmds)

end HALean.Automation
