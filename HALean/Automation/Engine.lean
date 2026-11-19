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
open Lean

namespace HALean.Automation

/-- Trigger variables handed to the run (subset of `trigger` in HA). -/
structure TriggerVars where
  id : String
  idx : Nat
  platform : String
  entityId : Option String := none
  description : String
  deriving Repr, Inhabited

/-- What keeps a `for:` timer alive (`_check_same_state` / numeric check). -/
inductive SameCheck where
  /-- state trigger: `cur_value == new_value` -/
  | equalNew (attr : Option String) (v : Json)
  /-- state trigger with `from` but no `to`: `cur_value != old_value` -/
  | notEqualOld (attr : Option String) (v : Json)
  | numeric (below above : Option Bound) (attr : Option String)
  deriving Repr, Inhabited

/-- A pending `for:` timer created by `async_track_same_state`. -/
structure PendingFor where
  id : Nat := 0
  autoIdx : Nat
  entity : String
  fireAt : Millis
  check : SameCheck
  vars : TriggerVars
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
  let env := { e.condEnv with triggerId := some tv.id }
  if !checkAutomationConditions env a.conditions then
    emit [.log "debug" s!"{a.alias}: conditions not met"]
    return
  let existing := runsOf e ai
  let decision := admit a.mode a.maxRuns existing.length
  if let .reject why := decision then
    emit [.log "warning" s!"{a.alias}: {why}"]
    return
  let wait : Wait := if decision == .enqueue then .queued else .ready
  let run : Run := { id := e.nextRunId, autoIdx := ai, triggerId := tv.id,
                     frames := [.seq a.actions false], wait }
  let mut e := { e with runs := e.runs ++ [run], nextRunId := e.nextRunId + 1 }
  if decision == .restart then
    -- "first add the new run and then stop any other runs"
    for old in existing do e := removeRun e old.id
  setE e
  emit [.automationTriggered a.id a.alias tv.description]
  if wait == .ready then drive run

/-! ## Triggers -/

def stateTriggerVars (t : Trigger) (eid : String) : TriggerVars :=
  { id := t.id, idx := t.idx, platform := "state", entityId := some eid,
    description := s!"state of {eid}" }

/-- `state.py::state_automation_listener` -/
def onStateTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .state eids fromM toM matchAll attr forMs fromKeyOnly := t.kind | return
  if !eids.contains eid then return
  let oldV := valueOf attr old
  let newV := valueOf attr new
  if attr.isSome && oldV == newV then return
  if !fromM.matches oldV || !toM.matches newV || (!matchAll && oldV == newV) then return
  let tv := stateTriggerVars t eid
  match forMs with
  | none | some 0 => triggerAutomation ai tv
  | some p =>
    let e ← getE
    let check := if fromKeyOnly then SameCheck.notEqualOld attr oldV else .equalNew attr newV
    setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
      [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p, check, vars := tv }] }

/-- `numeric_state.py::state_automation_listener` -/
def onNumericTrigger (ai : Nat) (t : Trigger) (eid : String) (new : Option EntityState) :
    EM Unit := do
  let .numericState eids below above attr forMs := t.kind | return
  if !eids.contains eid then return
  let some to := new | return
  let e ← getE
  match numericStateOf e.condEnv to below above attr with
  | .error m => emit [.log "warning" s!"Error in numeric_state trigger: {m}"]
  | .ok false =>
    if !e.armed.contains (ai, t.idx, eid) then
      setE { e with armed := e.armed ++ [(ai, t.idx, eid)] }
  | .ok true =>
    if e.armed.contains (ai, t.idx, eid) then
      let e := { e with armed := e.armed.filter (· != (ai, t.idx, eid)) }
      setE e
      let tv : TriggerVars := { id := t.id, idx := t.idx, platform := "numeric_state",
                                entityId := some eid, description := s!"numeric state of {eid}" }
      match forMs with
      | none | some 0 => triggerAutomation ai tv
      | some p =>
        setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
          [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p,
             check := .numeric below above attr, vars := tv }] }

/-- `_check_same_state` / `check_numeric_state_no_raise` -/
def sameStillHolds (env : CondEnv) (c : SameCheck) (new : Option EntityState) : Bool :=
  match new with
  | none => false
  | some s =>
    match c with
    | .equalNew attr v => valueOf attr (some s) == v
    | .notEqualOld attr v => valueOf attr (some s) != v
    | .numeric below above attr =>
      match numericStateOf env s below above attr with
      | .ok b => b
      | .error _ => false

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
      | .numericState .. => onNumericTrigger ai t eid new
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
          triggerAutomation ai { id := t.id, idx := t.idx, platform := "event",
                                 description := s!"event '{ty}'" }

def Pattern.matches (p : Pattern) (v : Nat) : Bool :=
  match p with
  | .any => true
  | .every n => v % n == 0
  | .exact n => v == n

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
          triggerAutomation ai { id := t.id, idx := t.idx, platform := "time",
                                 description := "time" }
      | .timePattern ph pm ps =>
        if ph.matches h && pm.matches m && ps.matches s then
          triggerAutomation ai { id := t.id, idx := t.idx, platform := "time_pattern",
                                 description := "time pattern" }
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
  match p?, d? with
  | some p, _ =>
    setE { e with pendings := e.pendings.filter (·.id != p.id) }
    triggerAutomation p.autoIdx p.vars
    fireDue t
  | none, some r =>
    let r := { r with wait := .ready }
    setE (replaceRun e r)
    drive r
    fireDue t
  | none, none => pure ()

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
  let e ← getE
  setE { e with now := now, lastSec := max e.lastSec target }
  fireDue now.utc

def initArmed : EM Unit := do
  let e ← getE
  let mut armed := []
  for (a, ai) in e.automations.zipIdx do
    for t in a.triggers do
      if let .numericState eids below above attr _ := t.kind then
        for eid in eids do
          -- "Each entity that starts outside the range is already armed"
          if let .ok false := numericStateOne e.condEnv eid below above attr then
            armed := armed ++ [(ai, t.idx, eid)]
  setE { e with armed }

def handle : Input → EM Unit
  | .init autos sts now => do
    setE { automations := autos, states := sts.map (fun s => (s.entityId, s)),
           now, lastSec := now.utc / 1000 }
    initArmed
  | .stateChanged eid old new now => do advanceTo now; onStateChanged eid old new
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
