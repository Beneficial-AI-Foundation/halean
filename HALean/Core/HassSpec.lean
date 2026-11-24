/-
  More specifications for `HALean/Core/Hass.lean` (what `HassProofs.lean` and
  `HassSchedProofs.lean` do not cover): the output entries and log records,
  how the errors of the state machine and the bus become Python exceptions,
  what the state machine and the registry hand to the bus (`smQueued`,
  `firedQueued`), futures and tasks (`futOf`, `setFut`, `resolve`, `park`,
  `findTask`, `spawn`), listener and handler scripts (`scriptOf`,
  `bodyLookup`, `bodyErase`), and the limits (`MAX_CALL_DEPTH`, the queue
  limit, fuel).
-/
import HALean.Core.Hass
open Lean HALean.Template

namespace HALean.Core.Hass
open HALean.Core HALean.Core.EventBus

/-! ## Output entries -/

/-- A delivery is never an out-of-model marker. -/
theorem Entry.isDelivery_not_isUnsupported (e : Entry) (h : e.isDelivery = true) :
    e.isUnsupported = false := by
  cases e <;> simp_all [Entry.isDelivery, Entry.isUnsupported]

/-- The three log entries the core writes are plain `error` log records:
not deliveries, not out-of-model markers, and with the exception as
`exc_info`. -/
theorem log_entries (e : Err) (pe : PyError) :
    (∃ r, filterLog e = .log r ∧ r.level = "error" ∧ r.exception.isSome = true) ∧
    (∃ r, gcLog pe = .log r ∧ r.level = "error" ∧ r.exception.isSome = true) ∧
    (∃ r, jobErrorLog (some pe) = [.log r] ∧ r.level = "error" ∧ r.exception.isSome = true) :=
  ⟨⟨_, rfl, rfl, rfl⟩, ⟨_, rfl, rfl, rfl⟩, ⟨_, rfl, rfl, rfl⟩⟩

/-- `_async_dispatch` logs "Error running job" exactly when the job raised;
what it logs is never a delivery or an out-of-model marker. -/
theorem jobErrorLog_spec (e : Option PyError) :
    (jobErrorLog e).length = (if e.isSome then 1 else 0) ∧
    ∀ x ∈ jobErrorLog e, x.isDelivery = false ∧ x.isUnsupported = false := by
  cases e <;> simp [jobErrorLog, Entry.isDelivery, Entry.isUnsupported]

/-- A task finalized with an unretrieved exception and a failing event
filter are logged, not reported as deliveries or as out of the model. -/
theorem gcLog_filterLog_kind (pe : PyError) (e : Err) :
    (gcLog pe).isDelivery = false ∧ (gcLog pe).isUnsupported = false ∧
    (filterLog e).isDelivery = false ∧ (filterLog e).isUnsupported = false :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- A listener that receives an event records exactly one delivery, counts
one more receipt for its job, and runs its script while the count is within
`reactTimes`. -/
theorem recordDelivery_spec (h : Hass) (job : Job) (ev : Event) :
    (recordDelivery h job ev).2.1 = [.delivery job.key job.listener ev] ∧
    (recordDelivery h job ev).1.bus.receivedOf job.key = h.bus.receivedOf job.key + 1 ∧
    ((recordDelivery h job ev).2.2 = true ↔
      ∀ n, job.reactTimes = some n → h.bus.receivedOf job.key + 1 ≤ n) := by
  refine ⟨rfl, ?_, ?_⟩
  · simp [recordDelivery, Bus.receivedOf]
  · simp only [recordDelivery]
    cases job.reactTimes <;> simp

/-- Recording a delivery does not change any other job's count. -/
theorem recordDelivery_receivedOf_other (h : Hass) (job : Job) (ev : Event) (k : Nat)
    (hk : k ≠ job.key) :
    (recordDelivery h job ev).1.bus.receivedOf k = h.bus.receivedOf k := by
  have : (k == job.key) = false := by simpa using hk
  simp [recordDelivery, Bus.receivedOf, List.lookup, this]

/-! ## Outcomes -/

/-- A finished coroutine (a value or an exception, no suspension) has a
synchronous outcome inside the model: nothing is reported, and the exception
(if any) is the one raised. -/
theorem syncOutcome_ofExcept (r : Except PyError Value) :
    syncOutcome (Res.ofExcept r) = ([], match r with | .ok _ => none | .error e => some e) := by
  cases r <;> rfl

/-- Only a suspension inside a `@callback` is out of the model. -/
theorem syncOutcome_unsupported_iff (r : Res) :
    (∃ e ∈ (syncOutcome r).1, e.isUnsupported = true) ↔ ∃ w k, r = .susp w k := by
  cases r <;> simp [syncOutcome, Entry.isUnsupported]

/-- The main task's outcome when it did not suspend: the loop does not run,
nothing is added to the output. -/
theorem drive_ofExcept (now : Nat) (h : Hass) (out : Out) (r : Except PyError Value) :
    drive now (h, out, Res.ofExcept r) = (h, out, r) := by
  cases r <;> rfl

/-- An eager task that finished in its first step is never added to
`hass._tasks`; an exception it finished with is logged as never
retrieved. -/
theorem spawn_ofExcept (h : Hass) (r : Except PyError Value) :
    h.spawn (Res.ofExcept r) = (h, match r with | .ok _ => [] | .error e => [gcLog e]) := by
  cases r <;> rfl

/-- An eager task that suspended becomes a new task with the next task id,
and logs nothing. -/
theorem spawn_susp (h : Hass) (w : Wait) (k : List Frame) :
    (h.spawn (.susp w k)).2 = [] ∧ (h.spawn (.susp w k)).1.nextTask = h.nextTask + 1 ∧
    (h.spawn (.susp w k)).1.tasks.map (·.id) = h.tasks.map (·.id) ++ [h.nextTask] := by
  refine ⟨rfl, ?_, ?_⟩ <;>
    (simp only [Hass.spawn, Hass.park]
     cases w with
     | soon => simp [Hass.enqueue]
     | round => simp
     | fut f =>
       simp only [Hass.futOf]
       split <;> simp [Hass.setFut, Hass.enqueue])

/-! ## Errors as Python exceptions -/

/-- A state machine error is an exception of the class it names; only the
model's own `unsupported` has none. -/
theorem smError_spec (e : SMError) :
    (smError e = none ↔ ∃ m, e = .unsupported m) ∧
    ∀ pe, smError e = some pe →
      errorKind pe.exception = "ha_error" ∧
      (pe.exception = "InvalidEntityFormatError" ↔ ∃ m, e = .invalidEntityFormat m) ∧
      (pe.exception = "InvalidStateError" ↔ ∃ m, e = .invalidState m) := by
  cases e <;> simp [smError] <;> decide

/-- The message of a state machine exception is the state machine's. -/
theorem smError_message (e : SMError) (pe : PyError) (h : smError e = some pe) :
    e = .invalidEntityFormat pe.message ∨ e = .invalidState pe.message ∨
      e = .homeAssistant pe.message := by
  cases e <;> simp [smError] at h <;> (subst h; simp)

/-- A bus error is the exception of that class; only its
`HomeAssistantError` is an `ha_error` for the protocol. -/
theorem busError_spec (e : Err) :
    (busError e).exception = e.name ∧
    (errorKind (busError e).exception = "ha_error" ↔ e = .homeAssistantError) := by
  cases e <;> simp [busError, Err.name] <;> decide

/-- The queue-full error is a `HomeAssistantError`; running out of fuel is a
`RecursionError`, which the protocol reports as `other`. -/
theorem queueFull_exhausted_kind (et : String) :
    errorKind (queueFull et).exception = "ha_error" ∧ errorKind exhausted.exception = "other" := by
  constructor
  · show errorKind "HomeAssistantError" = "ha_error"; decide
  · show errorKind "RecursionError" = "other"; decide

/-! ## What the state machine and the registry hand to the bus -/

/-- A state machine event enters the bus exactly as `async_fire` would queue
it with origin `LOCAL`, no `time_fired` and the state machine's context. -/
theorem smQueued_eq_mkQueued (now : Nat) (e : SMEvent) (ctx : Option Context) :
    smQueued now e ctx =
      mkQueued now { eventType := e.eventType, data := some e.dataJson } ctx := rfl

/-- The same for a registry event, when its data has a JSON form. -/
theorem firedQueued_eq_mkQueued (now : Nat) (e : FiredEvent) :
    firedQueued now e = (valuesJson e.data).map fun d =>
      mkQueued now { eventType := e.eventType, data := some d } e.context := rfl

/-- A registry event is handed on exactly when its data has a JSON form; it
then keeps its type and its context, always has data, and is stamped with
the clock of the fire (not the registry's millisecond clock). -/
theorem firedQueued_spec (now : Nat) (e : FiredEvent) :
    (firedQueued now e).isSome = (valuesJson e.data).isSome ∧
    ∀ q, firedQueued now e = some q →
      q.eventType = e.eventType ∧ q.context = e.context ∧ q.origin = .local ∧
      q.data.isSome = true ∧ q.timeFired = timestampOf now := by
  unfold firedQueued
  cases valuesJson e.data with
  | none => simp
  | some d =>
    refine ⟨rfl, ?_⟩
    intro q hq
    simp only [Option.map_some, Option.some.injEq] at hq
    subst hq
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- Two state machine events fired at the same clock are stamped the same,
so a listener cannot tell their order by `time_fired`. -/
theorem smQueued_timeFired (now : Nat) (e e' : SMEvent) (c c' : Option Context) :
    (smQueued now e c).timeFired = (smQueued now e' c').timeFired := rfl

/-! ## The queue limit and fuel -/

/-- A fire during a dispatch is queued: nothing runs, nothing is output. -/
theorem fireInternal_nested (n now : Nat) (h : Hass) (q : Queued)
    (hd : h.bus.dispatching = true) (hq : h.bus.queuedCount < MAX_QUEUED_EVENT_DISPATCHES) :
    (fireInternal (n + 1) now h q).2 = ([], none) ∧
    (fireInternal (n + 1) now h q).1.bus.queue = h.bus.queue ++ [q] ∧
    (fireInternal (n + 1) now h q).1.states = h.states ∧
    (fireInternal (n + 1) now h q).1.services = h.services := by
  have hn : ¬ (h.bus.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES) := by omega
  simp [fireInternal, hd, fireNested, hn]

/-- Once `_MAX_QUEUED_EVENT_DISPATCHES` events were queued in one dispatch,
a further fire raises the upstream `HomeAssistantError` and changes
nothing. -/
theorem fireInternal_queue_full (n now : Nat) (h : Hass) (q : Queued)
    (hd : h.bus.dispatching = true) (hq : h.bus.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES) :
    fireInternal (n + 1) now h q = (h, [], some (queueFull q.eventType)) := by
  simp [fireInternal, hd, fireNested, hq]

/-- Running out of fuel is never silent: every function of the mutual block
reports an out-of-model entry at fuel 0, so the driver rejects the
operation. -/
theorem fuel_zero_unsupported (now : Nat) (env : Env) (h : Hass) (q : Queued) (qs : List Queued)
    (ev? : Option Event) (js : List Job) (job : Job) (ev : Event) (as : List Action)
    (a : Action) (ca : CallArgs) :
    (∃ e ∈ (fireInternal 0 now h q).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (fireList 0 now h qs).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (dispatchLoop 0 now q h ev? js).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (drain 0 now h).2, e.isUnsupported = true) ∧
    (∃ e ∈ (runListener 0 now h job ev).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (runJob 0 now h job ev).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (runActions 0 env h as).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (runAction 0 env h a).2.1, e.isUnsupported = true) ∧
    (∃ e ∈ (callService 0 env h ca).2.1, e.isUnsupported = true) := by
  simp [fireInternal, fireList, dispatchLoop, drain, runListener, runJob, runActions, runAction,
    callService, Entry.isUnsupported]

/-- Service calls nested `MAX_CALL_DEPTH` deep are out of the model, and the
call does nothing. -/
theorem callService_too_deep (n : Nat) (env : Env) (h : Hass) (a : CallArgs)
    (hd : env.depth ≥ MAX_CALL_DEPTH) :
    callService (n + 1) env h a = (h, [.unsupported "call depth"], .err exhausted) := by
  simp [callService, hd]

/-- A call that `prepareCall` rejects (unknown service, a `return_response`
rule, the schema) raises that error without firing `call_service`, running
anything, or changing the core. -/
theorem callService_prepare_error (n : Nat) (env : Env) (h : Hass) (a : CallArgs) (c : Context)
    (e : PyError) (hd : env.depth < MAX_CALL_DEPTH)
    (huns : h.services.unsupportedCall? a = none) (hc : a.context = some c)
    (hp : h.services.prepareCall a c = .error e) :
    callService (n + 1) env h a = (h, [], .err e) := by
  have hn : ¬ (env.depth ≥ MAX_CALL_DEPTH) := by omega
  simp [callService, hn, huns, hc, Hass.ctxOr, hp]

/-- The same at the top level: `await hass.services.async_call(...)` on such
a call raises the error; no output, no change. -/
theorem step_call_prepare_error (now : Nat) (h : Hass) (a : CallArgs) (c : Context)
    (e : PyError) (huns : h.services.unsupportedCall? a = none) (hc : a.context = some c)
    (hp : h.services.prepareCall a c = .error e) :
    step now h (.call a) = (h, [], .error e) := by
  have hf : FUEL = 999999 + 1 := rfl
  have := callService_prepare_error 999999 { now } h a c e (by show (0 : Nat) < 32; decide) huns hc hp
  simp only [step, hf, this, drive]
  rfl

/-- The read operations of the top level never change the core and never
output anything. -/
theorem step_reads (now : Nat) (h : Hass) (d s : String) :
    step now h .listeners = (h, [], .ok (.listeners (asyncListeners h.bus))) ∧
    step now h (.has d s) = (h, [], .ok (.bool (h.services.hasService d s))) ∧
    (step now h (.get d)).1 = h := by
  refine ⟨rfl, rfl, ?_⟩
  simp only [step]
  split <;> rfl

/-! ## Futures -/

/-- A future is pending with no waiters until something touches it
(`loop.create_future()` on first use). -/
theorem futOf_new (f : String) : Hass.new.futOf f = .pending [] := rfl

/-- `setFut` then `futOf` reads back the value ... -/
theorem futOf_setFut_self (h : Hass) (f : String) (v : Fut) : (h.setFut f v).futOf f = v := by
  simp [Hass.setFut, Hass.futOf]

/-- ... and leaves every other future alone. -/
theorem futOf_setFut_other (h : Hass) (f g : String) (v : Fut) (hne : g ≠ f) :
    (h.setFut f v).futOf g = h.futOf g := by
  have h1 : (g == f) = false := by simpa using hne
  simp only [Hass.setFut, Hass.futOf, List.lookup, h1]
  congr 1
  induction h.futures with
  | nil => rfl
  | cons p rest ih =>
    obtain ⟨k, x⟩ := p
    by_cases hk : k = f
    · subst hk
      simp [List.filter, List.lookup, h1, ih]
    · have h2 : (k != f) = true := by simpa using hk
      simp only [List.filter, h2, List.lookup]
      cases g == k <;> simp [ih]

private theorem foldl_enqueue (ws : List Nat) (h : Hass) :
    (ws.foldl (fun h t => h.enqueue (.step t)) h).ready = h.ready ++ ws.map .step ∧
    (ws.foldl (fun h t => h.enqueue (.step t)) h).futures = h.futures ∧
    (ws.foldl (fun h t => h.enqueue (.step t)) h).tasks = h.tasks := by
  induction ws generalizing h with
  | nil => simp
  | cons w ws ih =>
    simp only [List.foldl_cons]
    obtain ⟨h1, h2, h3⟩ := ih (h.enqueue (.step w))
    rw [h1, h2, h3]
    simp [Hass.enqueue]

/-- `fut.set_result(None)` on a pending future: it is done afterwards, and
each waiter's wakeup is scheduled at the end of the ready queue, in the order
they started waiting. Tasks are untouched. -/
theorem resolve_pending (h : Hass) (f : String) (ws : List Nat) (hf : h.futOf f = .pending ws) :
    ∃ h', h.resolve f = some h' ∧ h'.futOf f = .done ∧
      h'.ready = h.ready ++ ws.map .step ∧ h'.tasks = h.tasks := by
  unfold Hass.resolve
  rw [hf]
  refine ⟨_, rfl, ?_, ?_, ?_⟩
  · have := (foldl_enqueue ws (h.setFut f .done)).2.1
    simp only [Hass.futOf, this]
    have := futOf_setFut_self h f .done
    simp only [Hass.futOf] at this
    rw [this]
  · rw [(foldl_enqueue ws _).1]; rfl
  · rw [(foldl_enqueue ws _).2.2]; rfl

/-- Resolving a future that is already done is outside the model
(`asyncio.InvalidStateError`). In particular a future cannot be resolved
twice. -/
theorem resolve_twice (h h' : Hass) (f : String) (hr : h.resolve f = some h') :
    h'.resolve f = none := by
  unfold Hass.resolve at hr
  split at hr
  · cases hr
  · rename_i ws hf
    obtain ⟨h2, hr2, hdone, _⟩ := resolve_pending h f ws hf
    unfold Hass.resolve at hr2
    rw [hf] at hr2
    have : h' = h2 := Option.some.inj (hr.symm.trans hr2)
    subst this
    unfold Hass.resolve
    rw [hdone]

/-- `await fut` on a pending future registers the task as its last waiter
and schedules nothing. -/
theorem park_fut_pending (h : Hass) (t : Nat) (f : String) (ws : List Nat)
    (hf : h.futOf f = .pending ws) :
    (h.park t (.fut f)).futOf f = .pending (ws ++ [t]) ∧
    (h.park t (.fut f)).ready = h.ready := by
  simp only [Hass.park, hf]
  exact ⟨futOf_setFut_self _ _ _, rfl⟩

/-- `await fut` on a done future, and `await asyncio.sleep(0)`, re-schedule
the task at the end of the ready queue. -/
theorem park_ready (h : Hass) (t : Nat) (f : String) (hf : h.resolve f = none) :
    (h.park t (.fut f)).ready = h.ready ++ [.step t] ∧
    (h.park t .soon).ready = h.ready ++ [.step t] ∧
    (h.park t .round).ready = h.ready := by
  refine ⟨?_, rfl, rfl⟩
  unfold Hass.resolve at hf
  simp only [Hass.park]
  split at hf
  · rename_i hd; rw [hd]; rfl
  · cases hf

/-- In a script, `await fut` goes on at once when the future is done and
suspends on it otherwise; either way nothing is output and the core is
unchanged. -/
theorem runAction_wait (n : Nat) (env : Env) (h : Hass) (f : String) :
    (runAction (n + 1) env h (.wait f)).1 = h ∧ (runAction (n + 1) env h (.wait f)).2.1 = [] := by
  simp only [runAction]
  split <;> exact ⟨rfl, rfl⟩

/-! ## Tasks -/

/-- `findTask` finds a task with that id, from the task list. -/
theorem findTask_some (h : Hass) (t : Nat) (r : TaskRec) (hf : h.findTask t = some r) :
    r.id = t ∧ r ∈ h.tasks := by
  unfold Hass.findTask at hf
  exact ⟨by simpa using List.find?_some hf, List.mem_of_find?_eq_some hf⟩

/-- It fails exactly when no task has the id. -/
theorem findTask_none_iff (h : Hass) (t : Nat) :
    h.findTask t = none ↔ ∀ r ∈ h.tasks, r.id ≠ t := by
  simp [Hass.findTask, List.find?_eq_none]

/-- A fresh core has no tasks. -/
theorem findTask_new (t : Nat) : Hass.new.findTask t = none := rfl

/-- Updating a task in place (keeping its id) is seen by `findTask`, and
does not affect how other ids are found beyond the update. -/
theorem findTask_updTask (h : Hass) (t u : Nat) (g : TaskRec → TaskRec)
    (hg : ∀ x, (g x).id = x.id) :
    (h.updTask t g).findTask u = (h.findTask u).map fun x => if x.id == t then g x else x := by
  simp only [Hass.updTask, Hass.findTask]
  induction h.tasks with
  | nil => rfl
  | cons x rest ih =>
    simp only [List.map_cons, List.find?_cons]
    have hid : (if x.id == t then g x else x).id = x.id := by
      split
      · exact hg x
      · rfl
    rw [hid]
    cases hx : x.id == u
    · exact ih
    · rfl

/-! ## Scripts -/

/-- A fresh core knows no listener script. -/
theorem scriptOf_new (k : Nat) : Hass.new.scriptOf k = [] := rfl

/-- A script subscribes a scripted listener: the new job's key (the bus's
next key) gets the script, nothing is output, and the job is marked as a
coroutine function exactly when `isAsync`. -/
theorem runAction_listen_ok (n : Nat) (env : Env) (h : Hass) (id et : String) (once : Bool)
    (filter : Option FilterSpec) (react : List Action) (rt : Option Nat) (isAsync : Bool)
    (b : Bus) (hb : listenOp h.bus id et once filter none [] rt = .ok b) :
    let r := runAction (n + 1) env h (.listen id et once filter react rt isAsync)
    r.1.scriptOf h.bus.nextKey = react ∧ r.1.bus = b ∧ r.2.1 = [] ∧
    (r.1.asyncJobs.contains h.bus.nextKey = true ↔
      isAsync = true ∨ h.asyncJobs.contains h.bus.nextKey = true) := by
  simp only [runAction, hb]
  refine ⟨by simp [Hass.scriptOf, List.lookup], trivial, trivial, ?_⟩
  cases isAsync <;> simp

/-- A rejected subscription raises the bus's exception and changes
nothing. -/
theorem runAction_listen_error (n : Nat) (env : Env) (h : Hass) (id et : String) (once : Bool)
    (filter : Option FilterSpec) (react : List Action) (rt : Option Nat) (isAsync : Bool)
    (e : Err) (hb : listenOp h.bus id et once filter none [] rt = .error e) :
    runAction (n + 1) env h (.listen id et once filter react rt isAsync)
      = (h, [], .err (busError e)) := by
  simp only [runAction, hb]

/-- `bodyLookup` is a dict lookup with `[]` as the default. -/
theorem bodyLookup_eq (bs : List ((String × String) × List Action)) (key : String × String) :
    bodyLookup bs key = ((bs.find? (·.1 == key)).map (·.2)).getD [] := by
  induction bs with
  | nil => rfl
  | cons p rest ih =>
    obtain ⟨k, b⟩ := p
    simp only [bodyLookup, List.find?_cons]
    cases hk : k == key
    · simpa using ih
    · simp

/-- After erasing a service's handler script there is none. -/
theorem bodyLookup_bodyErase_self (bs : List ((String × String) × List Action))
    (key : String × String) : bodyLookup (bodyErase bs key) key = [] := by
  induction bs with
  | nil => rfl
  | cons p rest ih =>
    obtain ⟨k, b⟩ := p
    unfold bodyErase at ih ⊢
    by_cases hk : k = key
    · simpa [List.filter, hk] using ih
    · have h1 : (k != key) = true := by simpa using hk
      have h2 : (k == key) = false := by simpa using hk
      simp only [List.filter, h1, bodyLookup, h2]
      exact ih

/-- Erasing one service's script leaves the others alone. -/
theorem bodyLookup_bodyErase_other (bs : List ((String × String) × List Action))
    (key key' : String × String) (hne : key' ≠ key) :
    bodyLookup (bodyErase bs key) key' = bodyLookup bs key' := by
  induction bs with
  | nil => rfl
  | cons p rest ih =>
    obtain ⟨k, b⟩ := p
    unfold bodyErase at ih ⊢
    by_cases hk : k = key
    · subst hk
      have h2 : (k == key') = false := by simpa using fun e : k = key' => hne e.symm
      simpa [List.filter, bodyLookup, h2] using ih
    · have h1 : (k != key) = true := by simpa using hk
      simp only [List.filter, h1, bodyLookup]
      split
      · rfl
      · exact ih

/-- Registering a handler script (`(key, body) :: bodyErase bodies key`, as
`register` does) makes it the one found, replacing any older one. -/
theorem bodyLookup_register (bs : List ((String × String) × List Action))
    (key : String × String) (body : List Action) :
    bodyLookup ((key, body) :: bodyErase bs key) key = body ∧
    ∀ key', key' ≠ key →
      bodyLookup ((key, body) :: bodyErase bs key) key' = bodyLookup bs key' := by
  refine ⟨by simp [bodyLookup], ?_⟩
  intro key' hne
  have h2 : (key == key') = false := by simpa using fun e : key = key' => hne e.symm
  simp only [bodyLookup, h2]
  exact bodyLookup_bodyErase_other bs key key' hne

end HALean.Core.Hass
