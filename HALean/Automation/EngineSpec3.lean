/-
  Specs for the engine's handlers (HALean/Automation/Engine.lean): what one
  call does to the engine state and to the commands for the shell.

  The handlers are `EM` actions (`StateM (Engine × List Cmd)`). `drive` and
  the functions around it are `partial`, so a theorem can follow a handler
  only up to the point where it hands a run to `drive`; where that happens
  the statement says so (`... = (drive run).run (state, commands)`).
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

private theorem owner_beq_iff (a b : Owner) : (a == b) = true ↔ a = b := by
  cases a <;> cases b <;> simp [BEq.beq, instBEqOwner.beq]

private instance : LawfulBEq Owner where
  eq_of_beq := fun h => (owner_beq_iff _ _).1 h
  rfl := (owner_beq_iff _ _).2 rfl

/-- Unfold the `EM` monad. -/
local macro "em_simp" "[" ls:Lean.Parser.Tactic.simpLemma,* "]" : tactic =>
  `(tactic| simp [getE, setE, emit, StateT.run, bind, StateT.bind, pure, StateT.pure, get, getThe,
      MonadStateOf.get, StateT.get, modify, modifyGet, MonadStateOf.modifyGet, StateT.modifyGet, $ls,*])

private theorem forIn_pure_yield {α β σ : Type} (l : List α) (g : β → α → β) (init : β) (s : σ) :
    (forIn (m := StateT σ Id) l init (fun x b => StateT.pure (ForInStep.yield (g b x)))) s
      = (l.foldl g init, s) := by
  induction l generalizing init with
  | nil => rfl
  | cons x xs ih => rw [List.forIn_cons]; exact ih (g init x)

/-! ### Triggering an automation (`AutomationEntity.async_trigger`) -/

/-- The environment an automation's `variables` are rendered in: `this`
(when the automation has an entity) and `trigger`. -/
def trigEnv (e : Engine) (ai : Nat) (a : Automation) (tv : TriggerVars) : CondEnv :=
  { states := e.condEnv.states, now := e.condEnv.now, triggerId := some tv.id,
    vars := (match a.entityId with
        | some eid => [("this", thisValue e ai a eid)]
        | none => []) ++ [("trigger", tv.value)],
    location := e.condEnv.location }

/-- The environment its conditions are checked in: the rendered variables. -/
def condEnvOf (e : Engine) (tv : TriggerVars) (vars : List (String × Template.Value)) : CondEnv :=
  { states := e.condEnv.states, now := e.condEnv.now, triggerId := some tv.id, vars,
    location := e.condEnv.location }

/-- The run a trigger starts. -/
def newRun (e : Engine) (ai : Nat) (a : Automation) (tv : TriggerVars)
    (vars : List (String × Template.Value)) (wait : Wait) : Run :=
  { id := e.nextRunId, autoIdx := ai, triggerId := tv.id, vars, frames := [.seq a.actions false], wait }

/-- The engine once the run is added: a fresh id is used up and
`last_triggered` is now. -/
def withRun (e : Engine) (ai : Nat) (run : Run) : Engine :=
  { e with runs := e.runs ++ [run], nextRunId := e.nextRunId + 1,
           lastTriggered := (e.lastTriggered.filter (·.1 != ai)) ++ [(ai, (e.now.utc : Int) * 1000)] }

/-- A trigger of an automation that does not exist does nothing. -/
theorem triggerAutomation_missing (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (h : e.automations[ai]? = none) :
    (triggerAutomation ai tv).run (e, acc) = ((), (e, acc)) := by
  em_simp [triggerAutomation, h]

/-- An error rendering `variables` stops the trigger: one error is logged. -/
theorem triggerAutomation_render_error (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (msg : String)
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .error msg) :
    (triggerAutomation ai tv).run (e, acc) =
      ((), (e, acc ++ [.log "error" s!"{a.alias}: Error rendering variables: {msg}"])) := by
  unfold trigEnv at hv
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv]

/-- Conditions are checked before the run mode: when they fail nothing
changes, whatever is running. -/
theorem triggerAutomation_conditions (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (vars : List (String × Template.Value))
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .ok vars)
    (hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions = false) :
    (triggerAutomation ai tv).run (e, acc) =
      ((), (e, acc ++ [.log "debug" s!"{a.alias}: conditions not met"])) := by
  unfold trigEnv at hv
  unfold condEnvOf at hc
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv, hc]

/-- A rejected trigger (`single` while running, `max` reached) only logs a
warning. -/
theorem triggerAutomation_reject (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (vars : List (String × Template.Value)) (why : String)
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .ok vars)
    (hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions = true)
    (hr : admit a.mode a.maxRuns (runsOf e ai).length = .reject why) :
    (triggerAutomation ai tv).run (e, acc) =
      ((), (e, acc ++ [.log "warning" s!"{a.alias}: {why}"])) := by
  unfold trigEnv at hv
  unfold condEnvOf at hc
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv, hc, hr]

/-- `queued` with a run in flight: the new run is added at the end, waiting
for the lock; it is announced but not driven. -/
theorem triggerAutomation_enqueue (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (vars : List (String × Template.Value))
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .ok vars)
    (hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions = true)
    (hr : admit a.mode a.maxRuns (runsOf e ai).length = .enqueue) :
    (triggerAutomation ai tv).run (e, acc) =
      ((), (withRun e ai (newRun e ai a tv vars .queued),
            acc ++ [.automationTriggered a.id a.alias tv.description])) := by
  unfold trigEnv at hv
  unfold condEnvOf at hc
  have h1 : (Admit.enqueue == Admit.restart) = false := by decide
  have h3 : (Admit.enqueue == Admit.enqueue) = true := by decide
  have h2 : (Wait.queued == Wait.ready) = false := by rfl
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv, hc, hr, h1, h2, h3, withRun, newRun]

/-- An admitted run that may start at once: it is added, announced, and
then driven. -/
theorem triggerAutomation_start (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (vars : List (String × Template.Value))
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .ok vars)
    (hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions = true)
    (hr : admit a.mode a.maxRuns (runsOf e ai).length = .start) :
    (triggerAutomation ai tv).run (e, acc) =
      (drive (newRun e ai a tv vars .ready)).run
        (withRun e ai (newRun e ai a tv vars .ready),
         acc ++ [.automationTriggered a.id a.alias tv.description]) := by
  unfold trigEnv at hv
  unfold condEnvOf at hc
  have h1 : (Admit.start == Admit.restart) = false := by decide
  have h3 : (Admit.start == Admit.enqueue) = false := by decide
  have h2 : (Wait.ready == Wait.ready) = true := by rfl
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv, hc, hr, h1, h2, h3, withRun, newRun]

/-- `restart`: the new run is added first, then every older run of the
automation is removed, and only then is the new one driven. -/
theorem triggerAutomation_restart (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (vars : List (String × Template.Value))
    (ha : e.automations[ai]? = some a)
    (hv : renderVariables (trigEnv e ai a tv) a.variables = .ok vars)
    (hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions = true)
    (hr : admit a.mode a.maxRuns (runsOf e ai).length = .restart) :
    (triggerAutomation ai tv).run (e, acc) =
      (drive (newRun e ai a tv vars .ready)).run
        ((runsOf e ai).foldl (fun e old => removeRun e old.id)
            (withRun e ai (newRun e ai a tv vars .ready)),
         acc ++ [.automationTriggered a.id a.alias tv.description]) := by
  unfold trigEnv at hv
  unfold condEnvOf at hc
  have h1 : (Admit.restart == Admit.restart) = true := by decide
  have h3 : (Admit.restart == Admit.enqueue) = false := by decide
  have h2 : (Wait.ready == Wait.ready) = true := by rfl
  cases hE : a.entityId <;> simp [hE] at hv <;>
  em_simp [triggerAutomation, ha, hE, hv, hc, hr, h1, h2, h3, withRun, newRun, forIn_pure_yield]

/-- `single` really is single, one trigger at a time: while the automation
has a run, a trigger never changes the engine (it can only log). -/
theorem triggerAutomation_single_busy (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (ha : e.automations[ai]? = some a) (hm : a.mode = .single)
    (hb : runsOf e ai ≠ []) :
    ((triggerAutomation ai tv).run (e, acc)).2.1 = e := by
  have hr : admit a.mode a.maxRuns (runsOf e ai).length = .reject "Already running" := by
    have : (runsOf e ai).length ≠ 0 := by simpa using hb
    simp [admit, hm, this]
  cases hv : renderVariables (trigEnv e ai a tv) a.variables with
  | error msg => rw [triggerAutomation_render_error ai tv e acc a msg ha hv]
  | ok vars =>
    cases hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions with
    | false => rw [triggerAutomation_conditions ai tv e acc a vars ha hv hc]
    | true => rw [triggerAutomation_reject ai tv e acc a vars _ ha hv hc hr]

/-- `max` is respected, one trigger at a time: a `queued` or `parallel`
automation that already has `max` runs never gets another. -/
theorem triggerAutomation_full (ai : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (a : Automation) (ha : e.automations[ai]? = some a)
    (hm : a.mode = .queued ∨ a.mode = .parallel)
    (hfull : (runsOf e ai).length = a.maxRuns) (hpos : a.maxRuns ≠ 0) :
    ((triggerAutomation ai tv).run (e, acc)).2.1 = e := by
  have hr : admit a.mode a.maxRuns (runsOf e ai).length
      = .reject "Maximum number of runs exceeded" := by
    rcases hm with hm | hm <;> simp [admit, hm, hfull, hpos]
  cases hv : renderVariables (trigEnv e ai a tv) a.variables with
  | error msg => rw [triggerAutomation_render_error ai tv e acc a msg ha hv]
  | ok vars =>
    cases hc : checkAutomationConditions (condEnvOf e tv vars) a.conditions with
    | false => rw [triggerAutomation_conditions ai tv e acc a vars ha hv hc]
    | true => rw [triggerAutomation_reject ai tv e acc a vars _ ha hv hc hr]

/-- `queued` is first-in, first-out at admission: the new run goes behind
every run the automation already has, and other automations are not
affected. -/
theorem withRun_runsOf (e : Engine) (ai aj : Nat) (a : Automation) (tv : TriggerVars)
    (vars : List (String × Template.Value)) (w : Wait) :
    runsOf (withRun e ai (newRun e ai a tv vars w)) aj =
      if ai = aj then runsOf e aj ++ [newRun e ai a tv vars w] else runsOf e aj := by
  by_cases h : ai = aj <;> simp [runsOf, withRun, newRun, List.filter_append, h]

/-- The new run's id is fresh, given the engine's invariant that live ids
are below `nextRunId`; and the invariant is kept. -/
theorem withRun_fresh (e : Engine) (ai : Nat) (a : Automation) (tv : TriggerVars)
    (vars : List (String × Template.Value)) (w : Wait) (hinv : ∀ r ∈ e.runs, r.id < e.nextRunId) :
    (∀ r ∈ e.runs, r.id ≠ (newRun e ai a tv vars w).id) ∧
    (∀ r ∈ (withRun e ai (newRun e ai a tv vars w)).runs,
        r.id < (withRun e ai (newRun e ai a tv vars w)).nextRunId) := by
  constructor
  · intro r hr; exact Nat.ne_of_lt (hinv r hr)
  · intro r hr
    simp only [withRun, List.mem_append, List.mem_singleton] at hr
    rcases hr with hr | rfl
    · exact Nat.lt_succ_of_lt (hinv r hr)
    · exact Nat.lt_succ_self _

/-- `last_triggered` holds exactly one entry for the automation: now. -/
theorem withRun_lastTriggered (e : Engine) (ai : Nat) (run : Run) :
    (withRun e ai run).lastTriggered.filter (·.1 == ai) = [(ai, (e.now.utc : Int) * 1000)] := by
  simp [withRun, List.filter_append, List.filter_filter]

/-! ### A trigger of a waiting run (`wait_for_trigger`) -/

/-- The wait is over already: nothing happens. -/
theorem fire_wait_gone (rid : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (h : e.waitTrigs.find? (·.runId == rid) = none) :
    (fire (.wait rid) tv).run (e, acc) = ((), (e, acc)) := by
  em_simp [fire, h]

/-- The run is gone: nothing happens. -/
theorem fire_run_gone (rid : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (h : e.runs.find? (·.id == rid) = none) :
    (fire (.wait rid) tv).run (e, acc) = ((), (e, acc)) := by
  cases hw : e.waitTrigs.find? (·.runId == rid) <;> em_simp [fire, h, hw]

/-- The trigger completes the wait: the run becomes ready with
`wait.completed`, `wait.trigger` and `wait.remaining` set, and is scheduled
to resume after the current callbacks. Nothing is sent to the shell. -/
theorem fire_wait (rid : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd) (w : WaitTrig)
    (r : Run) (hw : e.waitTrigs.find? (·.runId == rid) = some w)
    (hr : e.runs.find? (·.id == rid) = some r) :
    let rem : Template.Value := if w.hasTimeout then .opaque "wait.remaining" else .none
    let fields := [("remaining", rem), ("completed", .bool true), ("trigger", tv.value)]
    let r' : Run := { r with wait := .ready, vars := setWaitFields r.vars fields }
    let e' := replaceRun e r'
    (fire (.wait rid) tv).run (e, acc) =
      ((), ({ e' with woken := if e.woken.contains rid then e.woken else e.woken ++ [rid] }, acc)) := by
  em_simp [fire, hw, hr, replaceRun]

/-- Whatever happens, a trigger of a wait sends nothing to the shell, keeps
the listeners (they are removed when the run resumes), and never schedules
a run twice. -/
theorem fire_wait_quiet (rid : Nat) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (hnd : e.woken.Nodup) :
    let out := (fire (.wait rid) tv).run (e, acc)
    out.2.2 = acc ∧ out.2.1.waitTrigs = e.waitTrigs ∧ out.2.1.woken.Nodup ∧
    out.2.1.runs.length = e.runs.length := by
  cases hw : e.waitTrigs.find? (·.runId == rid) with
  | none => simp [fire_wait_gone rid tv e acc hw, hnd]
  | some w =>
    cases hr : e.runs.find? (·.id == rid) with
    | none => simp [fire_run_gone rid tv e acc hr, hnd]
    | some r =>
      have := fire_wait rid tv e acc w r hw hr
      rw [this]
      refine ⟨rfl, rfl, ?_, by simp [replaceRun]⟩
      simp only
      by_cases hc : rid ∈ e.woken
      · simpa [hc] using hnd
      · simp only [List.contains_eq_mem, hc, decide_false, Bool.false_eq_true, ite_false]
        rw [List.nodup_append]
        exact ⟨hnd, by simp, by
          intro a ha b hb; simp at hb; subst hb; intro h; subst h; exact hc ha⟩

/-! ### `for:` timers -/

/-- A `for:` period that rendered is never negative
(`cv.positive_time_period`). -/
theorem renderPeriod_nonneg (e : Engine) (o : Owner) (c : Complex) (trig : Template.Value)
    (us : Int) (h : renderPeriod e o c trig = .ok us) : 0 ≤ us := by
  unfold renderPeriod at h
  simp only [bind, Except.bind] at h
  split at h
  · cases h
  · unfold cvPositiveTimePeriod at h
    simp only [bind, Except.bind] at h
    split at h
    · cases h
    · split at h
      · cases h
      · simp only [pure, Except.pure, Except.ok.injEq] at h
        omega

/-- `period[entity] = us` and its timer: nothing is sent to the shell, the
timer gets a fresh id and is due at the first millisecond at or after the
period, and the period is the only one recorded for the key. -/
theorem addPeriodPending_spec (o : Owner) (key : Owner × Nat × String) (us : Int)
    (check : SameCheck) (tv : TriggerVars) (e : Engine) (acc : List Cmd) :
    ∃ e' p, (addPeriodPending o key us check tv).run (e, acc) = ((), (e', acc)) ∧
      e'.pendings = e.pendings ++ [p] ∧ p.id = e.nextPendingId ∧
      e'.nextPendingId = e.nextPendingId + 1 ∧ p.owner = o ∧
      p.fireAt = e.now.utc + usToMs us ∧ p.periodKey = some key ∧
      e'.periods.filter (·.1 == key) = [(key, us)] ∧ e'.runs = e.runs := by
  refine ⟨_, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ?_, rfl⟩
  simp [List.filter_append, List.filter_filter]

/-- Timer ids stay fresh: if every pending timer's id is below
`nextPendingId`, that still holds afterwards and the ids stay distinct. -/
theorem addPeriodPending_fresh (o : Owner) (key : Owner × Nat × String) (us : Int)
    (check : SameCheck) (tv : TriggerVars) (e : Engine) (acc : List Cmd)
    (hinv : ∀ p ∈ e.pendings, p.id < e.nextPendingId) (hnd : (e.pendings.map (·.id)).Nodup) :
    let e' := ((addPeriodPending o key us check tv).run (e, acc)).2.1
    (∀ p ∈ e'.pendings, p.id < e'.nextPendingId) ∧ (e'.pendings.map (·.id)).Nodup := by
  obtain ⟨e', p, hrun, hp, hid, hn, _⟩ := addPeriodPending_spec o key us check tv e acc
  simp only [hrun, hp, hn]
  constructor
  · intro q hq
    rcases List.mem_append.1 hq with hq | hq
    · exact Nat.lt_succ_of_lt (hinv q hq)
    · rw [List.mem_singleton.1 hq, hid]; exact Nat.lt_succ_self _
  · rw [List.map_append, List.nodup_append]
    refine ⟨hnd, by simp, ?_⟩
    intro a ha b hb
    simp only [List.map_cons, List.map_nil, List.mem_singleton] at hb
    obtain ⟨q, hq, rfl⟩ := List.mem_map.1 ha
    rw [hb, hid]
    exact Nat.ne_of_lt (hinv q hq)

/-- The error of a `for:` template is logged once; the engine is unchanged. -/
theorem logPeriodError_spec (o : Owner) (msg : String) (e : Engine) (acc : List Cmd) :
    ∃ m, (logPeriodError o msg).run (e, acc) = ((), (e, acc ++ [.log "error" m])) :=
  ⟨_, rfl⟩

/-- `_check_same_state`: a removed entity always cancels the timer. -/
theorem sameStillHolds_removed (env : CondEnv) (c : SameCheck) : sameStillHolds env c none = false :=
  rfl

/-- A template trigger's timer is not cancelled by state changes. -/
theorem sameStillHolds_always (env : CondEnv) (s : EntityState) :
    sameStillHolds env .always (some s) = true := rfl

/-- The two state-trigger checks are complementary while the entity exists:
"still the new value" against "still different from the old value". -/
theorem sameStillHolds_notEqualOld (env : CondEnv) (attr : Option String) (v : Json)
    (s : EntityState) :
    sameStillHolds env (.notEqualOld attr v) (some s)
      = !sameStillHolds env (.equalNew attr v) (some s) := by
  simp [sameStillHolds, bne]

/-- A numeric timer survives exactly while the entity is in range; an error
of the check cancels it. -/
theorem sameStillHolds_numeric (env : CondEnv) (below above : Option Bound) (attr : Option String)
    (vt : ValueTmpl) (s : EntityState) :
    sameStillHolds env (.numeric below above attr vt) (some s) = true
      ↔ numericStateOf env s below above attr vt = .ok true := by
  simp only [sameStillHolds]
  cases h : numericStateOf env s below above attr vt <;> simp

/-! ### State triggers (`state.py::state_automation_listener`) -/

/-- A change of an entity the trigger does not name is ignored. -/
theorem onStateTrigger_other_entity (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (fromM toM : StateMatch) (matchAll : Bool) (attr : Option String)
    (forP : Option ForPeriod) (fko : Bool)
    (hk : t.kind = .state eids fromM toM matchAll attr forP fko) (h : eid ∉ eids) :
    (onStateTrigger o t eid old new).run (e, acc) = ((), (e, acc)) := by
  em_simp [onStateTrigger, hk, h]

/-- An attribute trigger ignores changes that leave the attribute as it was. -/
theorem onStateTrigger_attr_unchanged (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (fromM toM : StateMatch) (matchAll : Bool) (a : String)
    (forP : Option ForPeriod) (fko : Bool)
    (hk : t.kind = .state eids fromM toM matchAll (some a) forP fko)
    (h : (valueOf (some a) old == valueOf (some a) new) = true) :
    (onStateTrigger o t eid old new).run (e, acc) = ((), (e, acc)) := by
  em_simp [onStateTrigger, hk, h]

/-- `from:`/`to:` that do not match: ignored. -/
theorem onStateTrigger_no_match (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (fromM toM : StateMatch) (matchAll : Bool) (attr : Option String)
    (forP : Option ForPeriod) (fko : Bool)
    (hk : t.kind = .state eids fromM toM matchAll attr forP fko)
    (h : fromM.matches (valueOf attr old) = false ∨ toM.matches (valueOf attr new) = false) :
    (onStateTrigger o t eid old new).run (e, acc) = ((), (e, acc)) := by
  rcases h with h | h <;> em_simp [onStateTrigger, hk, h]

/-- Without `for:`, a matching change fires at once, with `trigger.for`
`None`. -/
theorem onStateTrigger_fires (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (fromM toM : StateMatch) (attr : Option String) (fko : Bool)
    (hk : t.kind = .state eids fromM toM false attr none fko) (h : eid ∈ eids)
    (hne : (valueOf attr old == valueOf attr new) = false)
    (hf : fromM.matches (valueOf attr old) = true) (ht : toM.matches (valueOf attr new) = true) :
    (onStateTrigger o t eid old new).run (e, acc) =
      (fire o (stateTriggerVars t eid old new attr .none)).run (e, acc) := by
  em_simp [onStateTrigger, hk, h, hne, hf, ht]

/-- With a static `for: p` (`p > 0`), a matching change fires nothing yet:
it starts one timer, due `p` ms from now, that lives while the entity keeps
its new value. No command is sent and no run is touched. -/
theorem onStateTrigger_for (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (fromM toM : StateMatch) (attr : Option String) (p : Nat) (hp : p ≠ 0)
    (hk : t.kind = .state eids fromM toM false attr (some (.fixed p)) false) (h : eid ∈ eids)
    (hne : (valueOf attr old == valueOf attr new) = false)
    (hf : fromM.matches (valueOf attr old) = true) (ht : toM.matches (valueOf attr new) = true) :
    (onStateTrigger o t eid old new).run (e, acc) =
      ((), ({ e with
          nextPendingId := e.nextPendingId + 1,
          pendings := e.pendings ++ [{
            id := e.nextPendingId, owner := o, entity := eid, fireAt := e.now.utc + p,
            check := .equalNew attr (valueOf attr new),
            vars := stateTriggerVars t eid old new attr (forVal (some p)) }] }, acc)) := by
  obtain ⟨n, rfl⟩ := Nat.exists_eq_succ_of_ne_zero hp
  em_simp [onStateTrigger, hk, h, hne, hf, ht]

/-! ### Numeric state triggers (`numeric_state.py`) -/

/-- The `value_template` and its variables, as the listener passes them to
the range check. -/
def numericVt (e : Engine) (o : Owner) (t : Trigger) (eid : String) (below above : Option Bound)
    (attr : Option String) (vtm : Option Template.Tmpl) : ValueTmpl :=
  vtm.map fun tm => (tm, (tmplCtxOf e o).vars ++ [("trigger", numericTriggerVar t eid below above attr)])

/-- A removed entity is ignored. -/
theorem onNumericTrigger_removed (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (e : Engine) (acc : List Cmd) :
    (onNumericTrigger o t eid old none).run (e, acc) = ((), (e, acc)) := by
  cases hk : t.kind <;> em_simp [onNumericTrigger, hk]

/-- A change of an entity the trigger does not name is ignored. -/
theorem onNumericTrigger_other_entity (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (forP : Option ForPeriod) (vtm : Option Template.Tmpl)
    (hk : t.kind = .numericState eids below above attr forP vtm) (h : eid ∉ eids) :
    (onNumericTrigger o t eid old new).run (e, acc) = ((), (e, acc)) := by
  em_simp [onNumericTrigger, hk, h]

/-- Outside the range: the entity is armed (once); nothing fires. -/
theorem onNumericTrigger_arms (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (to : EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (forP : Option ForPeriod) (vtm : Option Template.Tmpl)
    (hk : t.kind = .numericState eids below above attr forP vtm) (h : eid ∈ eids)
    (hn : numericStateOf e.condEnv to below above attr (numericVt e o t eid below above attr vtm)
            = .ok false) :
    (onNumericTrigger o t eid old (some to)).run (e, acc) =
      ((), (if e.armed.contains (o, t.idx, eid) then e
            else { e with armed := e.armed ++ [(o, t.idx, eid)] }, acc)) := by
  unfold numericVt at hn
  by_cases ha : (o, t.idx, eid) ∈ e.armed <;>
  em_simp [onNumericTrigger, hk, h, hn, ha]

/-- Inside the range but not armed (it was inside before): nothing fires.
The trigger fires only on crossing into the range. -/
theorem onNumericTrigger_not_armed (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (to : EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (forP : Option ForPeriod) (vtm : Option Template.Tmpl)
    (hk : t.kind = .numericState eids below above attr forP vtm) (h : eid ∈ eids)
    (hn : numericStateOf e.condEnv to below above attr (numericVt e o t eid below above attr vtm)
            = .ok true)
    (ha : (o, t.idx, eid) ∉ e.armed) :
    (onNumericTrigger o t eid old (some to)).run (e, acc) = ((), (e, acc)) := by
  unfold numericVt at hn
  em_simp [onNumericTrigger, hk, h, hn, ha]

/-- An error of the range check is a warning; nothing else changes. -/
theorem onNumericTrigger_error (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (to : EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (forP : Option ForPeriod) (vtm : Option Template.Tmpl) (m : String)
    (hk : t.kind = .numericState eids below above attr forP vtm) (h : eid ∈ eids)
    (hn : numericStateOf e.condEnv to below above attr (numericVt e o t eid below above attr vtm)
            = .error m) :
    (onNumericTrigger o t eid old (some to)).run (e, acc) =
      ((), (e, acc ++ [.log "warning" s!"Error in numeric_state trigger: {m}"])) := by
  unfold numericVt at hn
  em_simp [onNumericTrigger, hk, h, hn]

/-- `numeric_state.py::call_action`: the `trigger` of a numeric_state
trigger that fired. -/
def numericTv (t : Trigger) (eid : String) (below above : Option Bound)
    (old new : Option EntityState) (forV : Template.Value) : TriggerVars :=
  { id := t.id, idx := t.idx, platform := "numeric_state",
    entityId := some eid, description := s!"numeric state of {eid}",
    value := triggerValue t "numeric_state" [
      ("entity_id", .str eid), ("below", boundVal below), ("above", boundVal above),
      ("from_state", stateVal old), ("to_state", stateVal new), ("for", forV),
      ("description", .str s!"numeric state of {eid}")] }

/-- Unlike the variables its `value_template` sees, it has no `attribute`. -/
theorem numericTv_keys (t : Trigger) (eid : String) (below above : Option Bound)
    (old new : Option EntityState) (forV : Template.Value) :
    ∃ kvs, (numericTv t eid below above old new forV).value = .dict kvs ∧
      kvs.map (·.1) = ["id", "idx", "alias", "platform", "entity_id", "below", "above",
        "from_state", "to_state", "for", "description"].map .str :=
  ⟨_, rfl, rfl⟩

/-- Crossing into the range with no `for:`: the entity is disarmed and the
trigger fires. -/
theorem onNumericTrigger_fires (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (to : EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (vtm : Option Template.Tmpl)
    (hk : t.kind = .numericState eids below above attr none vtm) (h : eid ∈ eids)
    (hn : numericStateOf e.condEnv to below above attr (numericVt e o t eid below above attr vtm)
            = .ok true)
    (ha : (o, t.idx, eid) ∈ e.armed) :
    (onNumericTrigger o t eid old (some to)).run (e, acc) =
      (fire o (numericTv t eid below above old (some to) .none)).run
        ({ e with armed := e.armed.filter (· != (o, t.idx, eid)) }, acc) := by
  unfold numericVt at hn
  em_simp [onNumericTrigger, hk, h, hn, ha, numericTv]

/-- Crossing into the range with a static `for: p` (`p > 0`): the entity is
disarmed and one timer starts, due `p` ms from now, that lives while the
entity stays in range. Nothing fires yet. -/
theorem onNumericTrigger_for (o : Owner) (t : Trigger) (eid : String)
    (old : Option EntityState) (to : EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (below above : Option Bound) (attr : Option String)
    (vtm : Option Template.Tmpl) (p : Nat) (hp : p ≠ 0)
    (hk : t.kind = .numericState eids below above attr (some (.fixed p)) vtm) (h : eid ∈ eids)
    (hn : numericStateOf e.condEnv to below above attr (numericVt e o t eid below above attr vtm)
            = .ok true)
    (ha : (o, t.idx, eid) ∈ e.armed) :
    (onNumericTrigger o t eid old (some to)).run (e, acc) =
      ((), ({ e with
          armed := e.armed.filter (· != (o, t.idx, eid)),
          nextPendingId := e.nextPendingId + 1,
          pendings := e.pendings ++ [{
            id := e.nextPendingId, owner := o, entity := eid, fireAt := e.now.utc + p,
            check := .numeric below above attr (numericVt e o t eid below above attr vtm),
            vars := numericTv t eid below above old (some to) (forVal (some p)) }] }, acc)) := by
  unfold numericVt at hn
  obtain ⟨n, rfl⟩ := Nat.exists_eq_succ_of_ne_zero hp
  em_simp [onNumericTrigger, hk, h, hn, ha, numericTv, numericVt]

/-! ### Template trackers -/

/-- `getTT` only reads: it returns a template trigger's tracker (never a
`wait_template` one) with the asked owner and position. -/
theorem getTT_spec (o : Owner) (idx : Nat) (e : Engine) (acc : List Cmd) :
    ((getTT o idx).run (e, acc)).2 = (e, acc) ∧
    ∀ st, ((getTT o idx).run (e, acc)).1 = some st →
      st ∈ e.tmplTrigs ∧ st.owner = o ∧ st.trigIdx = idx ∧ st.tmpl = none := by
  refine ⟨rfl, ?_⟩
  intro st h
  have h' : e.tmplTrigs.find? (fun x => x.tmpl.isNone && x.owner == o && x.trigIdx == idx) = some st := h
  have hm := List.mem_of_find?_eq_some h'
  have hp := List.find?_some h'
  simp only [Bool.and_eq_true, Option.isNone_iff_eq_none, beq_iff_eq] at hp
  exact ⟨hm, hp.1.2, hp.2, hp.1.1⟩

/-- `saveTT` writes the tracker over every entry with its key: no command,
nothing but `tmplTrigs` changes, no tracker is added or removed. -/
theorem saveTT_spec (st : TmplTrig) (e : Engine) (acc : List Cmd) :
    ∃ e', (saveTT st).run (e, acc) = ((), (e', acc)) ∧
      e'.tmplTrigs.length = e.tmplTrigs.length ∧
      (∀ x ∈ e'.tmplTrigs, x.sameKey st = true → x = st) ∧
      (∀ x ∈ e.tmplTrigs, x.sameKey st = false → x ∈ e'.tmplTrigs) ∧
      e'.tmplTrigs.map (fun x => (x.owner, x.trigIdx)) = e.tmplTrigs.map (fun x => (x.owner, x.trigIdx)) ∧
      e'.runs = e.runs ∧ e'.pendings = e.pendings := by
  refine ⟨{ e with tmplTrigs := e.tmplTrigs.map fun x => if x.sameKey st then st else x }, rfl,
    by simp, ?_, ?_, ?_, rfl, rfl⟩
  · intro x hx hk
    obtain ⟨y, _, rfl⟩ := List.mem_map.1 hx
    by_cases hy : y.sameKey st = true
    · simp [hy]
    · simp [hy] at hk
  · intro x hx hk
    exact List.mem_map.2 ⟨x, hx, by simp [hk]⟩
  · simp only [List.map_map]
    apply List.map_congr_left
    intro x _
    by_cases hx : x.sameKey st = true
    · have := hx
      simp only [TmplTrig.sameKey, Bool.and_eq_true, beq_iff_eq] at this
      simp [hx, this.1, this.2]
    · simp [hx]

/-- Saving a tracker with no entry does nothing. -/
theorem saveTT_absent (st : TmplTrig) (e : Engine) (acc : List Cmd)
    (h : ∀ x ∈ e.tmplTrigs, x.sameKey st = false) :
    (saveTT st).run (e, acc) = ((), (e, acc)) := by
  have : e.tmplTrigs.map (fun x => if x.sameKey st then st else x) = e.tmplTrigs := by
    conv => rhs; rw [← List.map_id e.tmplTrigs]
    apply List.map_congr_left
    intro x hx
    simp [h x hx]
  show ((), ({ e with tmplTrigs := e.tmplTrigs.map fun (x : TmplTrig) => if x.sameKey st then st else x }, acc)) = _
  rw [this]

/-- A render error of a template trigger: the tracker is saved and a
warning logged; no run starts and no timer changes. -/
theorem templateListener_error (o : Owner) (t : Trigger) (forP : Option ForPeriod) (st : TmplTrig)
    (msg : String) (ev : Option Deferred) (e : Engine) (acc : List Cmd) :
    (templateListener o t forP st (.error msg) ev).run (e, acc) =
      ((), (((saveTT st).run (e, acc)).2.1,
            acc ++ [.log "warning" s!"Error evaluating 'template' trigger: {msg}"])) := by
  em_simp [templateListener, saveTT]

/-- The pending `for:` timer of a template trigger, cancelled. -/
def cancelPending (e : Engine) (st : TmplTrig) : Engine :=
  match st.pending with
  | some pid => { e with pendings := e.pendings.filter (·.id != pid) }
  | none => e

/-- A false result cancels the trigger's timer and arms it; nothing fires. -/
theorem templateListener_false (o : Owner) (t : Trigger) (forP : Option ForPeriod) (st : TmplTrig)
    (v : Template.Value) (ev : Option Deferred) (e : Engine) (acc : List Cmd)
    (hv : Template.resultAsBoolean v = false) :
    (templateListener o t forP st (.ok v) ev).run (e, acc) =
      (saveTT { st with pending := none, armed := true }).run (cancelPending e st, acc) := by
  unfold cancelPending
  cases hp : st.pending <;> em_simp [templateListener, hv, hp, saveTT]

/-- A true result while not armed (it was true before): nothing fires. The
trigger fires only when the template turns from false to true. -/
theorem templateListener_not_armed (o : Owner) (t : Trigger) (forP : Option ForPeriod)
    (st : TmplTrig) (v : Template.Value) (ev : Option Deferred) (e : Engine) (acc : List Cmd)
    (hv : Template.resultAsBoolean v = true) (ha : st.armed = false) :
    (templateListener o t forP st (.ok v) ev).run (e, acc) =
      (saveTT { st with pending := none }).run (cancelPending e st, acc) := by
  unfold cancelPending
  cases hp : st.pending <;> em_simp [templateListener, hv, hp, ha, saveTT]

/-- `template/trigger.py::call_action`: the `trigger` of a template trigger
that fired, for the state change `ev` that caused the render (`none`: the
time listener). -/
def templateTv (t : Trigger) (ev : Option Deferred) (forV : Template.Value) : TriggerVars :=
  match ev with
  | some (eid, old, new) =>
    { id := t.id, idx := t.idx, platform := "template", entityId := some eid,
      description := s!"{eid} via template",
      value := triggerValue t "template" [
        ("entity_id", .str eid), ("from_state", stateVal old), ("to_state", stateVal new),
        ("for", forV), ("description", .str s!"{eid} via template")] }
  | none =>
    { id := t.id, idx := t.idx, platform := "template", entityId := none,
      description := "time change or manual update via template",
      value := triggerValue t "template" [
        ("entity_id", .none), ("from_state", .none), ("to_state", .none),
        ("for", forV), ("description", .str "time change or manual update via template")] }

/-- A true result while armed, with no `for:`: the trigger is disarmed, its
timer cancelled, and it fires. -/
theorem templateListener_fires (o : Owner) (t : Trigger) (st : TmplTrig)
    (v : Template.Value) (ev : Option Deferred) (e : Engine) (acc : List Cmd)
    (hv : Template.resultAsBoolean v = true) (ha : st.armed = true) :
    (templateListener o t none st (.ok v) ev).run (e, acc) =
      (fire o (templateTv t ev .none)).run
        ((saveTT { st with pending := none, armed := false }).run (cancelPending e st, acc)).2 := by
  unfold cancelPending templateTv
  cases hp : st.pending <;> rcases ev with _ | ⟨eid, old, new⟩ <;>
    em_simp [templateListener, hv, hp, ha, saveTT]

/-- A render that did not change the result (equal value, or error after
error) is not passed to the listener: only the tracker's render info and
rate-limit clock are updated. -/
theorem templateRefresh_unchanged (o : Owner) (t : Trigger) (ev : Option Deferred) (e : Engine)
    (acc : List Cmd) (tm : Template.Tmpl) (forP : Option ForPeriod) (st : TmplTrig)
    (hk : t.kind = .template tm forP)
    (hst : e.tmplTrigs.find? (fun x => x.tmpl.isNone && x.owner == o && x.trigIdx == t.idx) = some st)
    (hr : resultChanged st.last (Template.renderWithInfo tm (tmplCtxOf e o) true).1 = false) :
    (templateRefresh o t ev).run (e, acc) =
      (saveTT { st with info := (Template.renderWithInfo tm (tmplCtxOf e o) true).2,
                        lastTriggered := some e.now.utc, rlTimer := none }).run (e, acc) := by
  em_simp [templateRefresh, getTT, hk, hst, hr, saveTT]

/-- A tracker that is not a `wait_template`'s is not for `waitRefresh`. -/
theorem waitRefresh_not_wait (st : TmplTrig) (e : Engine) (acc : List Cmd) (h : st.tmpl = none) :
    (waitRefresh st).run (e, acc) = (none, (e, acc)) := by
  em_simp [waitRefresh, h]

/-- A tracker owned by an automation never completes a wait. -/
theorem waitRefresh_auto (st : TmplTrig) (ai : Nat) (e : Engine) (acc : List Cmd)
    (h : st.owner = .auto ai) : (waitRefresh st).run (e, acc) = (none, (e, acc)) := by
  cases ht : st.tmpl <;> em_simp [waitRefresh, h, ht]

/-- A state change the tracker does not listen to does not render. -/
theorem trackerGate_not_listening (st : TmplTrig) (eid : String) (old new : Option EntityState)
    (e : Engine) (acc : List Cmd) (h : st.info.listens eid st.rlTimer.isSome = false) :
    (trackerGate st eid old new false).run (e, acc) = (false, (e, acc)) := by
  em_simp [trackerGate, h]

/-- A template trigger without a tracker ignores state changes. -/
theorem onTemplateTrigger_no_tracker (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (replay : Bool) (e : Engine) (acc : List Cmd)
    (h : e.tmplTrigs.find? (fun x => x.tmpl.isNone && x.owner == o && x.trigIdx == t.idx) = none) :
    (onTemplateTrigger o t eid old new replay).run (e, acc) = ((), (e, acc)) := by
  cases hk : t.kind <;> em_simp [onTemplateTrigger, getTT, hk, h]

/-- `async_track_template` for a `wait_template`: afterwards the run has
exactly one tracker, for its template, at position 0; other trackers are
kept in order; nothing is sent. -/
theorem setupWait_spec (r : Run) (t : Template.Tmpl) (e : Engine) (acc : List Cmd) :
    ∃ e' st, (setupWait r t).run (e, acc) = ((), (e', acc)) ∧
      e'.tmplTrigs.filter (·.owner == .wait r.id) = [st] ∧
      st.trigIdx = 0 ∧ st.vars = r.scopeVars ∧ st.last = none ∧ st.armed = false ∧
      (∀ o, o ≠ .wait r.id →
        e'.tmplTrigs.filter (·.owner == o) = e.tmplTrigs.filter (·.owner == o)) ∧
      e'.runs = e.runs := by
  let ctx : Template.Ctx := { states := e.states, now := e.now, vars := r.scopeVars }
  let info := (Template.renderWithInfo t ctx true).2
  let st : TmplTrig := { owner := .wait r.id, trigIdx := 0, tmpl := some t, vars := r.scopeVars, info := info }
  refine ⟨_, st, rfl, ?_, rfl, rfl, rfl, rfl, ?_, rfl⟩
  · show ((e.tmplTrigs.filter (·.owner != .wait r.id)) ++ [st]).filter (·.owner == .wait r.id) = [st]
    have h0 : (e.tmplTrigs.filter (·.owner != .wait r.id)).filter (·.owner == .wait r.id) = [] := by
      rw [List.filter_filter, List.filter_eq_nil_iff]
      intro x _
      simp
    have h1 : (st.owner == Owner.wait r.id) = true := beq_self_eq_true _
    rw [List.filter_append, h0, List.nil_append]
    simp only [List.filter_cons, h1, List.filter_nil, ite_true]
  · intro o ho
    have ho' : (Owner.wait r.id == o) = false := by
      simp only [beq_eq_false_iff_ne, ne_eq]; exact fun h => ho h.symm
    simp only [List.filter_append, List.filter_filter, List.filter_cons, ho', List.filter_nil,
      List.append_nil, Bool.false_eq_true, ite_false]
    apply List.filter_congr
    intro x _
    by_cases hx : x.owner = o
    · simp [hx, ho]
    · simp [hx]

/-! ### Zone triggers -/

/-- A change of an entity the trigger does not name is ignored. -/
theorem onZoneTrigger_other_entity (o : Owner) (t : Trigger) (eid : String)
    (old new : Option EntityState) (e : Engine) (acc : List Cmd)
    (eids : List String) (zoneId : String) (enter : Bool)
    (hk : t.kind = .zone eids zoneId enter) (h : eid ∉ eids) :
    (onZoneTrigger o t eid old new).run (e, acc) = ((), (e, acc)) := by
  em_simp [onZoneTrigger, hk, h]

/-! ### Time-trigger entities (`time.py::update_entity_trigger`) -/

/-- An entity that disappears loses its listener; nothing is logged. -/
theorem updateTimeEntity_removed (o : Owner) (idx : Nat) (eid : String) (off : Int) (e : Engine)
    (acc : List Cmd) :
    (updateTimeEntity o idx eid off none).run (e, acc) =
      ((), ({ e with timeEnt := e.timeEnt.filter (·.1 != (o, idx, eid, off)) }, acc)) := by
  em_simp [updateTimeEntity]

/-! ### Script entities -/

/-- An engine without script entities (plain automations) writes no entity
state. -/
theorem writeEntity_no_script (ai : Nat) (e : Engine) (acc : List Cmd) (h : e.scripts[ai]? = none) :
    (writeEntity ai).run (e, acc) = ((), (e, acc)) := by
  em_simp [writeEntity, h]

/-- ... and handles no service call itself: every call goes to HA. -/
theorem localCall?_no_scripts (e : Engine) (cid : Nat) (rr : Bool) (cmds : List Cmd)
    (h : e.scripts = []) : localCall? e cid rr cmds = none := by
  simp [localCall?, h]

/-! ### `this` -/

/-- `this` is the automation entity's state as a mapping with HA's keys;
the automation is `on`. -/
theorem thisValue_keys (e : Engine) (ai : Nat) (a : Automation) (eid : String) :
    ∃ attrs rest, thisValue e ai a eid = .dict
      ((.str "entity_id", .str eid) :: (.str "state", .str "on") :: (.str "attributes", attrs) :: rest)
      ∧ rest.map (·.1) = ["last_changed", "last_reported", "last_updated", "context"].map .str :=
  ⟨_, _, rfl, rfl⟩

/-! ### Owners -/

/-- A wait whose record is gone sees no variables. -/
theorem tmplCtxOf_wait_gone (e : Engine) (rid : Nat)
    (h : e.waitTrigs.find? (·.runId == rid) = none) : (tmplCtxOf e (.wait rid)).vars = [] := by
  simp [tmplCtxOf, h]

/-- Trigger templates see the engine's states and clock, like conditions. -/
theorem tmplCtxOf_env (e : Engine) (o : Owner) :
    (tmplCtxOf e o).states = e.condEnv.states ∧ (tmplCtxOf e o).now = e.condEnv.now := ⟨rfl, rfl⟩

/-- Messages about a wait name the automation of its run. -/
theorem ownerAuto_wait (e : Engine) (rid : Nat) (r : Run) (h : e.runs.find? (·.id == rid) = some r) :
    e.ownerAuto (.wait rid) = e.ownerAuto (.auto r.autoIdx) := by
  simp [Engine.ownerAuto, h]

/-! ### `Engine.step` -/

/-- Attaching no triggers does nothing. -/
theorem attachTriggers_nil (o : Owner) (e : Engine) (acc : List Cmd) :
    (attachTriggers o []).run (e, acc) = ((), (e, acc)) := by
  em_simp [attachTriggers]

/-- `init` starts from scratch: the previous engine does not matter. -/
theorem step_init_forgets (e e' : Engine) (autos : List Automation) (sts : List EntityState)
    (now : Instant) (loc : Option Sun.Observer) :
    Engine.step e (.init autos sts now loc) = Engine.step e' (.init autos sts now loc) := by
  em_simp [Engine.step, handle]

/-- `init` without automations: the states are loaded, the clock set, and
nothing is sent. -/
theorem step_init_empty (e : Engine) (sts : List EntityState) (now : Instant)
    (loc : Option Sun.Observer) :
    Engine.step e (.init [] sts now loc) =
      ({ automations := [], states := sts.map (fun s => (s.entityId, s)), now := now,
         lastSec := now.utc / 1000, location := loc }, []) := by
  em_simp [Engine.step, handle, initArmed]

/-- An event nobody listens to does nothing. -/
theorem onEvent_no_listeners (ty : String) (data : Json) (e : Engine) (acc : List Cmd)
    (h1 : e.automations = []) (h2 : e.waitTrigs = []) :
    (onEvent ty data).run (e, acc) = ((), (e, acc)) := by
  em_simp [onEvent, Engine.owners, h1, h2]

end HALean.Automation
