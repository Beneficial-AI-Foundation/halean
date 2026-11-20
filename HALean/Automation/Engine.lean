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
  | some s => .state s
  | none => .none

def forVal : Option Nat → Template.Value
  | none => .none
  | some _ => .opaque "timedelta"

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

/-- State of one `template` trigger (`async_attach_trigger`'s closure:
`armed`, `delay_cancel`, plus the tracker's `_last_result`). -/
structure TmplTrig where
  autoIdx : Nat
  trigIdx : Nat
  armed : Bool := false
  last : Option TmplResult := none
  pending : Option Nat := none
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
  tmplTrigs : List TmplTrig := []
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
  let env := { e.condEnv with triggerId := some tv.id, trigger := tv.value }
  if !checkAutomationConditions env a.conditions then
    emit [.log "debug" s!"{a.alias}: conditions not met"]
    return
  let existing := runsOf e ai
  let decision := admit a.mode a.maxRuns existing.length
  if let .reject why := decision then
    emit [.log "warning" s!"{a.alias}: {why}"]
    return
  let wait : Wait := if decision == .enqueue then .queued else .ready
  let run : Run := { id := e.nextRunId, autoIdx := ai, triggerId := tv.id, trigger := tv.value,
                     frames := [.seq a.actions false], wait }
  let mut e := { e with runs := e.runs ++ [run], nextRunId := e.nextRunId + 1 }
  if decision == .restart then
    -- "first add the new run and then stop any other runs"
    for old in existing do e := removeRun e old.id
  setE e
  emit [.automationTriggered a.id a.alias tv.description]
  if wait == .ready then drive run

/-! ## Triggers -/

/-- `state.py::call_action` -/
def stateTriggerVars (t : Trigger) (eid : String) (old new : Option EntityState)
    (attr : Option String) (forMs : Option Nat) : TriggerVars :=
  { id := t.id, idx := t.idx, platform := "state", entityId := some eid,
    description := s!"state of {eid}",
    value := triggerValue t "state" [
      ("entity_id", .str eid), ("from_state", stateVal old), ("to_state", stateVal new),
      ("for", forVal forMs), ("attribute", match attr with | some a => .str a | none => .none),
      ("description", .str s!"state of {eid}")] }

/-- `state.py::state_automation_listener` -/
def onStateTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .state eids fromM toM matchAll attr forMs fromKeyOnly := t.kind | return
  if !eids.contains eid then return
  let oldV := valueOf attr old
  let newV := valueOf attr new
  if attr.isSome && oldV == newV then return
  if !fromM.matches oldV || !toM.matches newV || (!matchAll && oldV == newV) then return
  let tv := stateTriggerVars t eid old new attr forMs
  match forMs with
  | none | some 0 => triggerAutomation ai tv
  | some p =>
    let e ← getE
    let check := if fromKeyOnly then SameCheck.notEqualOld attr oldV else .equalNew attr newV
    setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
      [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p, check, vars := tv }] }

/-- `numeric_state.py::state_automation_listener` -/
def onNumericTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .numericState eids below above attr forMs vtm := t.kind | return
  let vt := vtm.map fun tm => (tm, [("trigger", numericTriggerVar t eid below above attr)])
  if !eids.contains eid then return
  let some to := new | return
  let e ← getE
  match numericStateOf e.condEnv to below above attr vt with
  | .error m => emit [.log "warning" s!"Error in numeric_state trigger: {m}"]
  | .ok false =>
    if !e.armed.contains (ai, t.idx, eid) then
      setE { e with armed := e.armed ++ [(ai, t.idx, eid)] }
  | .ok true =>
    if e.armed.contains (ai, t.idx, eid) then
      let e := { e with armed := e.armed.filter (· != (ai, t.idx, eid)) }
      setE e
      let tv : TriggerVars := {
        id := t.id, idx := t.idx, platform := "numeric_state",
        entityId := some eid, description := s!"numeric state of {eid}",
        value := triggerValue t "numeric_state" [
          ("entity_id", .str eid), ("below", boundVal below), ("above", boundVal above),
          ("attribute", match attr with | some a => .str a | none => .none),
          ("from_state", stateVal old), ("to_state", stateVal new), ("for", forVal forMs),
          ("description", .str s!"numeric state of {eid}")] }
      match forMs with
      | none | some 0 => triggerAutomation ai tv
      | some p =>
        setE { e with nextPendingId := e.nextPendingId + 1, pendings := e.pendings ++
          [{ id := e.nextPendingId, autoIdx := ai, entity := eid, fireAt := e.now.utc + p,
             check := .numeric below above attr vt, vars := tv }] }

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

def tmplCtxOf (e : Engine) : Template.Ctx := { states := e.states }

/-- `template/trigger.py::template_listener`, driven the way
`async_track_template_result` drives it. The tracker re-renders when an
entity the last render read changes, and calls the listener only when the
parsed result differs from the last one (the first re-render always counts;
error → error does not). Re-rendering on every state change is equivalent:
a change to an entity the template did not read cannot change its result. -/
def onTemplateTrigger (ai : Nat) (t : Trigger) (eid : String) (old new : Option EntityState) :
    EM Unit := do
  let .template tm forMs := t.kind | return
  let e ← getE
  let some st := e.tmplTrigs.find? (fun x => x.autoIdx == ai && x.trigIdx == t.idx) | return
  let r := Template.render tm (tmplCtxOf e) true
  let changed := match st.last, r with
    | none, _ => true
    | some (.ok a), .ok b => !Template.pyEq a b
    | some .err, .error _ => false
    | _, _ => true
  if !changed then return
  let save (st : TmplTrig) : EM Unit := do
    let e ← getE
    setE { e with tmplTrigs := e.tmplTrigs.map fun x =>
      if x.autoIdx == ai && x.trigIdx == t.idx then st else x }
  match r with
  | .error msg =>
    save { st with last := some .err }
    emit [.log "warning" s!"Error evaluating 'template' trigger: {msg}"]
  | .ok v =>
    -- `delay_cancel()`
    if let some pid := st.pending then
      let e ← getE
      setE { e with pendings := e.pendings.filter (·.id != pid) }
    let st := { st with last := some (.ok v), pending := none }
    if !Template.resultAsBoolean v then
      save { st with armed := true }
      return
    if !st.armed then
      save st
      return
    let st := { st with armed := false }
    let desc := s!"{eid} via template"
    let tv : TriggerVars := {
      id := t.id, idx := t.idx, platform := "template", entityId := some eid,
      description := desc,
      value := triggerValue t "template" [
        ("entity_id", .str eid), ("from_state", stateVal old), ("to_state", stateVal new),
        ("for", forVal forMs), ("description", .str desc)] }
    match forMs with
    | none | some 0 =>
      save st
      triggerAutomation ai tv
    | some p =>
      let e ← getE
      let pid := e.nextPendingId
      setE { e with nextPendingId := pid + 1, pendings := e.pendings ++
        [{ id := pid, autoIdx := ai, entity := "", fireAt := e.now.utc + p, check := .always, vars := tv }] }
      save { st with pending := some pid }

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
            value := triggerValue t "time" [("now", .opaque "datetime"),
              ("description", .str "time"), ("entity_id", .none)] }
      | .timePattern ph pm ps =>
        if ph.matches h && pm.matches m && ps.matches s then
          triggerAutomation ai {
            id := t.id, idx := t.idx, platform := "time_pattern",
            description := "time pattern",
            value := triggerValue t "time_pattern" [("now", .opaque "datetime"),
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
      if let .numericState eids below above attr _ vtm := t.kind then
        for eid in eids do
          let vt := vtm.map fun tm => (tm, [("trigger", numericTriggerVar t eid below above attr)])
          -- "Each entity that starts outside the range is already armed"
          if let .ok false := numericStateOne e.condEnv eid below above attr vt then
            armed := armed ++ [(ai, t.idx, eid)]
  -- template triggers: "Arm at setup if the template is already false"
  let mut tts : List TmplTrig := []
  let mut logs : List Cmd := []
  for (a, ai) in e.automations.zipIdx do
    for t in a.triggers do
      if let .template tm _ := t.kind then
        match Template.render tm (tmplCtxOf e) true with
        | .ok v => tts := tts ++ [{ autoIdx := ai, trigIdx := t.idx, armed := !Template.resultAsBoolean v }]
        | .error msg =>
          tts := tts ++ [{ autoIdx := ai, trigIdx := t.idx }]
          logs := logs ++ [.log "warning" s!"Error initializing 'template' trigger for '{a.alias}': {msg}"]
  setE { e with armed, tmplTrigs := tts }
  emit logs

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
