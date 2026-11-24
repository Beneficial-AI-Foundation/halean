/-
  More specifications for `HALean/Core/EventBus.lean` (what
  `EventBusProofs.lean` does not cover): the enum values, the constants and
  the guards built on them (event-type length, queue limit, the types
  excluded from `MATCH_ALL`), `async_listeners`, event filters
  (`evalFilter`, `filterPasses`), `mkQueued` (`time_fired or time.time()`),
  the per-listener receipt counter, and `Event.as_dict`.
-/
import Std.Data.TreeMap.Raw.Lemmas
import HALean.Core.EventBus
import HALean.Core.EventBusProofs
import HALean.Core.StateMachine
open Lean

namespace HALean.Core.EventBus

private theorem ebMkObj_getObjVal? {l : List (String × Json)} {k : String} {v : Json}
    (distinct : l.Pairwise (fun a b => ¬ a.1 = b.1)) (mem : (k, v) ∈ l) :
    (Json.mkObj l).getObjVal? k = .ok v := by
  have h : (Std.TreeMap.Raw.ofList l compare)[k]? = some v :=
    Std.TreeMap.Raw.getElem?_ofList_of_mem (k := k) (by simp)
      (by simpa using distinct) mem
  have h' : (Std.TreeMap.Raw.ofList l compare).get? k = some v := h
  simp only [Json.mkObj, Json.getObjVal?]
  rw [h']; rfl

/-! ## Enum values -/

/-- `EventOrigin.value` tells the two origins apart. -/
theorem Origin.value_injective (a b : Origin) (h : a.value = b.value) : a = b := by
  cases a <;> cases b <;> first | rfl | (simp [Origin.value] at h)

/-- Each exception has its own Python class name. -/
theorem Err.name_injective (a b : Err) (h : a.name = b.name) : a = b := by
  cases a <;> cases b <;> first | rfl | (simp [Err.name] at h)

/-! ## Constants -/

/-- The bus and the state machine agree on the name of `state_reported`. -/
theorem EVENT_STATE_REPORTED_eq : EVENT_STATE_REPORTED = HALean.Core.EVENT_STATE_REPORTED := rfl

/-- `MATCH_ALL` is not itself excluded from `MATCH_ALL` (so a `*` listener
gets a `*` event once per list: both lists are the same). -/
theorem MATCH_ALL_not_excluded : MATCH_ALL ∉ EVENTS_EXCLUDED_FROM_MATCH_ALL := by decide

/-- `EventBus.__init__`: an empty `MATCH_ALL` list and the one
`logging_changed` listener, in that dict order. -/
theorem asyncListeners_new :
    asyncListeners Bus.new = [(MATCH_ALL, 0), (EVENT_LOGGING_CHANGED, 1)] := rfl

/-! ## `async_listeners` -/

/-- One entry per event type of the dict, in dict order. -/
theorem asyncListeners_keys (b : Bus) :
    (asyncListeners b).map (·.1) = b.listeners.map (·.1) := by
  simp [asyncListeners]

/-- Each entry is an event type with the length of its listener list. -/
theorem mem_asyncListeners (b : Bus) (et : String) (n : Nat) :
    (et, n) ∈ asyncListeners b ↔ ∃ l, (et, l) ∈ b.listeners ∧ l.length = n := by
  simp only [asyncListeners, List.mem_map, Prod.mk.injEq, Prod.exists]
  constructor
  · rintro ⟨a, l, hm, rfl, rfl⟩; exact ⟨l, hm, rfl⟩
  · rintro ⟨l, hm, rfl⟩; exact ⟨et, l, hm, rfl, rfl⟩

/-- The count reported for an event type is the length of
`_listeners.get(event_type, [])` (0 for a type that is not in the dict). -/
theorem asyncListeners_lookup (b : Bus) (et : String) :
    ((asyncListeners b).lookup et).getD 0 = (b.listeners.get et).length := by
  unfold asyncListeners Table.get
  induction b.listeners with
  | nil => rfl
  | cons p rest ih =>
    obtain ⟨k, l⟩ := p
    simp only [List.map_cons, List.lookup]
    cases et == k <;> simp_all

/-- Adding a listener raises its event type's count by one and leaves every
other type's count alone. -/
theorem asyncListeners_listen (b : Bus) (job : Job) (et : String) :
    ((asyncListeners (listenFilterableJob b job).1).lookup et).getD 0 =
      ((asyncListeners b).lookup et).getD 0 + (if et = job.eventType then 1 else 0) := by
  rw [asyncListeners_lookup, asyncListeners_lookup]
  simp only [listenFilterableJob]
  by_cases h : et = job.eventType
  · subst h
    rw [get_set_self (exists_touch _ _), get_touch]
    simp
  · rw [get_set_ne h, get_touch_any]
    simp [h]

/-- Queueing an event during a dispatch changes no listener count. -/
theorem asyncListeners_fireNested (b : Bus) (q : Queued) :
    asyncListeners (fireNested b q).1 = asyncListeners b := by
  unfold fireNested asyncListeners
  split <;> rfl

/-! ## The event-type length and queue limits -/

/-- While dispatching, a fire is queued exactly while fewer than
`_MAX_QUEUED_EVENT_DISPATCHES` (10,000) events were queued. -/
theorem fireNested_ok_iff (b : Bus) (q : Queued) :
    (fireNested b q).2 = none ↔ b.queuedCount < MAX_QUEUED_EVENT_DISPATCHES := by
  unfold fireNested
  split <;> simp_all <;> omega

/-- A queued event goes to the end of the queue (FIFO) and is counted. -/
theorem fireNested_queued (b : Bus) (q : Queued)
    (h : b.queuedCount < MAX_QUEUED_EVENT_DISPATCHES) :
    (fireNested b q).1.queue = b.queue ++ [q] ∧
    (fireNested b q).1.queuedCount = b.queuedCount + 1 := by
  have hn : ¬ (b.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES) := by omega
  simp only [fireNested, hn, ↓reduceIte, and_self]

/-- A full queue raises `HomeAssistantError` and leaves the bus alone. -/
theorem fireNested_full (b : Bus) (q : Queued)
    (h : b.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES) :
    fireNested b q = (b, some .homeAssistantError) := by
  simp only [fireNested, h, ↓reduceIte]

/-- Every way `async_fire` can raise: `MaxLengthExceeded` for an event type
longer than `MAX_LENGTH_EVENT_EVENT_TYPE` (64) characters, checked first;
`HomeAssistantError` when called during a dispatch with a full queue.
Nothing else. -/
theorem asyncFire_error_iff (now : Nat) (b : Bus) (f : FireArgs) (ctx : Option Context) (e : Err) :
    asyncFire now b f ctx = .error e ↔
      (f.eventType.length > MAX_LENGTH_EVENT_EVENT_TYPE ∧ e = .maxLengthExceeded) ∨
      (f.eventType.length ≤ MAX_LENGTH_EVENT_EVENT_TYPE ∧ b.dispatching = true ∧
        b.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES ∧ e = .homeAssistantError) := by
  unfold asyncFire
  by_cases hl : f.eventType.length > MAX_LENGTH_EVENT_EVENT_TYPE
  · simp only [hl, ↓reduceIte]
    constructor
    · intro h; cases h; exact .inl ⟨trivial, rfl⟩
    · rintro (⟨_, rfl⟩ | ⟨h, _⟩)
      · rfl
      · omega
  · simp only [hl, ↓reduceIte]
    cases hd : b.dispatching with
    | false =>
      simp only [Bool.false_eq_true, ite_false]
      constructor
      · intro h; cases h
      · rintro (⟨h, _⟩ | ⟨_, h, _⟩)
        · exact h.elim
        · cases h
    | true =>
      simp only [ite_true]
      by_cases hq : b.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES
      · rw [fireNested_full b _ hq]
        constructor
        · intro h; cases h; exact .inr ⟨by omega, trivial, hq, rfl⟩
        · rintro (⟨h, _⟩ | ⟨_, _, _, rfl⟩)
          · exact h.elim
          · rfl
      · have hn : (fireNested b (mkQueued now f ctx)).2 = none :=
          (fireNested_ok_iff b _).mpr (by omega)
        constructor
        · intro h
          split at h
          · cases h
          · rename_i heq; rw [heq] at hn; cases hn
        · rintro (⟨h, _⟩ | ⟨_, _, h, _⟩)
          · exact h.elim
          · exact absurd h hq

/-- A listener that fires an event with too long a type gets
`MaxLengthExceeded`, and nothing is queued. -/
theorem react1_fire_too_long (now : Nat) (ev : Event) (b : Bus) (f : FireArgs)
    (h : f.eventType.length > MAX_LENGTH_EVENT_EVENT_TYPE) :
    react1 now ev b (.fire f) = (b, some .maxLengthExceeded) := by
  simp [react1, h]

/-! ## Event types excluded from `MATCH_ALL` -/

/-- `state_reported` and `homeassistant_close` only reach their own
listeners; every other type also reaches the `MATCH_ALL` listeners, after
its own. -/
theorem snapshot_eq (t : Table) (et : String) :
    snapshot t et =
      if et = EVENT_STATE_REPORTED ∨ et = EVENT_HOMEASSISTANT_CLOSE then t.get et
      else t.get et ++ t.get MATCH_ALL := by
  unfold snapshot EVENTS_EXCLUDED_FROM_MATCH_ALL
  by_cases h1 : et = EVENT_STATE_REPORTED
  · subst h1; simp
  · by_cases h2 : et = EVENT_HOMEASSISTANT_CLOSE
    · subst h2; simp
    · simp [h1, h2]

/-- Listening to `state_reported` needs an event filter (`async_listen`
raises `HomeAssistantError` without one): the event is too frequent. -/
theorem asyncListen_state_reported_no_filter (b : Bus) (id : String) (react : List Reaction)
    (rt : Option Nat) :
    asyncListen b id EVENT_STATE_REPORTED none none react rt = .error .homeAssistantError := by
  simp [asyncListen]

/-- With a `@callback` filter it is accepted. -/
theorem asyncListen_state_reported_filter (b : Bus) (id : String) (fs : FilterSpec)
    (react : List Reaction) (rt : Option Nat) (hcb : fs.isCallback = true) :
    ∃ r, asyncListen b id EVENT_STATE_REPORTED (some fs) none react rt = .ok r := by
  simp [asyncListen, hcb]

/-- Every way `async_listen` can raise, in upstream's order: the
`run_immediately` argument (`RuntimeError`), a filter that is not a
`@callback`, and `state_reported` without a filter (both
`HomeAssistantError`). -/
theorem asyncListen_error_iff (b : Bus) (id et : String) (filter : Option FilterSpec)
    (ri : Option Bool) (react : List Reaction) (rt : Option Nat) (e : Err) :
    asyncListen b id et filter ri react rt = .error e ↔
      (ri.isSome = true ∧ e = .runtimeError) ∨
      (ri = none ∧ e = .homeAssistantError ∧
        ((∃ fs, filter = some fs ∧ fs.isCallback = false) ∨
         (et = EVENT_STATE_REPORTED ∧ filter = none))) := by
  unfold asyncListen
  cases ri with
  | some x =>
    simp only [Option.isSome_some, ite_true, true_and, reduceCtorEq, false_and, or_false]
    constructor
    · intro h; cases h; rfl
    · rintro rfl; rfl
  | none =>
    cases filter with
    | none =>
      by_cases het : et = EVENT_STATE_REPORTED
      · simp [het]
        constructor
        · intro h; exact h.symm
        · intro h; exact h.symm
      · simp [het]
    | some fs =>
      cases hcb : fs.isCallback
      · simp [hcb]
        constructor
        · intro h; exact h.symm
        · intro h; exact h.symm
      · simp [hcb]

/-- `async_listen_once` takes no filter (`TypeError`) and no
`run_immediately` (`RuntimeError`); any event type is accepted, even
`state_reported`. -/
theorem asyncListenOnce_error_iff (b : Bus) (id et : String) (filter : Option FilterSpec)
    (ri : Option Bool) (react : List Reaction) (rt : Option Nat) (e : Err) :
    asyncListenOnce b id et filter ri react rt = .error e ↔
      (filter.isSome = true ∧ e = .typeError) ∨
      (filter = none ∧ ri.isSome = true ∧ e = .runtimeError) := by
  unfold asyncListenOnce
  cases filter <;> cases ri <;> simp <;>
    (constructor <;> (intro h; exact h.symm))

/-! ## Event filters -/

/-- A constant filter returns its constant. -/
theorem evalFilter_const (v : Bool) (data : Json) : evalFilter (.const v) data = .ok v := rfl

/-- A filter raises exactly when it is the raising filter (`ValueError`). -/
theorem evalFilter_error_iff (f : Filter) (data : Json) (e : Err) :
    evalFilter f data = .error e ↔ f = .raises ∧ e = .valueError := by
  cases f <;> simp [evalFilter]
  constructor <;> (intro h; exact h.symm)

/-- `has k` is true exactly when the data has the key. -/
theorem evalFilter_has_iff (k : String) (data : Json) :
    evalFilter (.has k) data = .ok true ↔ ∃ v, data.getObjVal? k = .ok v := by
  simp only [evalFilter, Except.ok.injEq]
  cases data.getObjVal? k <;> simp [Except.toOption]

/-- An `eq` filter with no keys accepts everything. -/
theorem evalFilter_eq_nil (data : Json) : evalFilter (.eq []) data = .ok true := rfl

/-- An `eq` filter is a conjunction over its keys: it accepts exactly when
each single-key filter accepts. -/
theorem evalFilter_eq_cons (kv : String × Json) (kvs : List (String × Json)) (data : Json) :
    evalFilter (.eq (kv :: kvs)) data = .ok true ↔
      evalFilter (.eq [kv]) data = .ok true ∧ evalFilter (.eq kvs) data = .ok true := by
  simp [evalFilter]

/-- An `eq` filter only accepts data that has all of its keys. -/
theorem evalFilter_eq_has (kvs : List (String × Json)) (data : Json)
    (h : evalFilter (.eq kvs) data = .ok true) :
    ∀ kv ∈ kvs, evalFilter (.has kv.1) data = .ok true := by
  intro kv hkv
  simp only [evalFilter, Except.ok.injEq, List.all_eq_true] at h
  have := h kv hkv
  rw [evalFilter_has_iff]
  cases hg : data.getObjVal? kv.1 with
  | ok v => exact ⟨v, rfl⟩
  | error e => simp [hg] at this

/-- A job without a filter always runs. -/
theorem filterPasses_no_filter (job : Job) (data : Option Json) (h : job.filter = none) :
    filterPasses job data = .ok true := by
  simp [filterPasses, h]

/-- `event_filter` is not called when the event data is `None`: the job is
skipped, even if the filter would raise. -/
theorem filterPasses_no_data (job : Job) (fs : FilterSpec) (h : job.filter = some fs) :
    filterPasses job none = .ok false := by
  simp [filterPasses, h]

/-- Otherwise the filter decides. -/
theorem filterPasses_data (job : Job) (fs : FilterSpec) (d : Json) (h : job.filter = some fs) :
    filterPasses job (some d) = evalFilter fs.filter d := by
  simp [filterPasses, h]

/-- The only filter error the dispatch can log is the raising filter's
`ValueError`, on an event that has data. -/
theorem filterPasses_error (job : Job) (data : Option Json) (e : Err)
    (h : filterPasses job data = .error e) :
    e = .valueError ∧ data.isSome = true ∧ ∃ fs, job.filter = some fs ∧ fs.filter = .raises := by
  unfold filterPasses at h
  split at h
  · cases h
  · rename_i fs hf
    split at h
    · cases h
    · rename_i d
      have := (evalFilter_error_iff _ _ _).mp h
      exact ⟨this.2, rfl, fs, hf, this.1⟩

/-! ## `mkQueued`: `time_fired or time.time()` -/

/-- The queued event keeps the type, data and origin of the fire, and the
context it was given. -/
theorem mkQueued_fields (now : Nat) (f : FireArgs) (ctx : Option Context) :
    (mkQueued now f ctx).eventType = f.eventType ∧ (mkQueued now f ctx).data = f.data ∧
    (mkQueued now f ctx).origin = f.origin ∧ (mkQueued now f ctx).context = ctx :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- Python's `or`: a `time_fired` of 0 is falsy, so it means "now", like
`None`. -/
theorem mkQueued_timeFired_zero (now : Nat) (f : FireArgs) (ctx : Option Context)
    (h : f.timeFired = some 0) :
    mkQueued now f ctx = mkQueued now { f with timeFired := none } ctx := by
  simp [mkQueued, h]

/-- Without a `time_fired` the event is stamped with the clock. -/
theorem mkQueued_timeFired_none (now : Nat) (f : FireArgs) (ctx : Option Context)
    (h : f.timeFired = none) : (mkQueued now f ctx).timeFired = timestampOf now := by
  simp [mkQueued, h]

/-- A given non-zero `time_fired` is used, and the clock does not matter. -/
theorem mkQueued_timeFired_some (now now' : Nat) (f : FireArgs) (ctx : Option Context) (t : Nat)
    (h : f.timeFired = some t) (ht : t ≠ 0) :
    (mkQueued now f ctx).timeFired = timestampOf t ∧ mkQueued now f ctx = mkQueued now' f ctx := by
  simp [mkQueued, h, ht]

/-! ## The receipt counter -/

/-- A new bus has delivered nothing to anyone. -/
theorem receivedOf_new (k : Nat) : Bus.new.receivedOf k = 0 := rfl

private theorem asyncRemoveListener_received (b : Bus) (et : String) (k : Nat) :
    (asyncRemoveListener b et k).received = b.received := by
  unfold asyncRemoveListener
  simp only
  split <;> rfl

private theorem listenOp_received {b b' : Bus} {id et once filter ri react rt}
    (h : listenOp b id et once filter ri react rt = .ok b') : b'.received = b.received := by
  unfold listenOp at h
  split at h
  · rename_i b1 hd heq
    cases h
    obtain ⟨j, hj⟩ := listen_ok heq
    have h1 : b1 = (listenFilterableJob b j).1 := by rw [hj]
    subst h1
    rfl
  · cases h

private theorem react1_received (now : Nat) (ev : Event) (b : Bus) (r : Reaction) :
    (react1 now ev b r).1.received = b.received := by
  cases r with
  | fire f =>
    simp only [react1]
    split
    · rfl
    · unfold fireNested; split <;> rfl
  | listen id et once filter ri react rt =>
    simp only [react1]
    split
    · rename_i b' heq; exact listenOp_received heq
    · rfl
  | unsub id =>
    simp only [react1, unsubOp]
    cases hl : b.handles.lookup id with
    | none => rfl
    | some p => exact asyncRemoveListener_received b p.1 p.2
  | raise e => rfl

/-- A listener's reactions (firing, listening, unsubscribing, raising) never
touch the receipt counters. -/
theorem runReactions_received (now : Nat) (ev : Event) (b : Bus) (rs : List Reaction) :
    (runReactions now ev b rs).1.received = b.received := by
  induction rs generalizing b with
  | nil => rfl
  | cons r rs ih =>
    simp only [runReactions]
    have h1 := react1_received now ev b r
    split
    · rename_i b' e heq; rw [heq] at h1; exact h1
    · rename_i b' heq; rw [heq] at h1; rw [ih b']; exact h1

/-- Calling a listener counts one more receipt for its job and none for any
other job, whatever its reactions do. -/
theorem callListener_receivedOf (now : Nat) (b : Bus) (job : Job) (ev : Event) (k : Nat) :
    (callListener now b job ev).1.receivedOf k =
      b.receivedOf k + (if k = job.key then 1 else 0) := by
  have hrec : (callListener now b job ev).1.received
      = (job.key, b.receivedOf job.key + 1) :: b.received := by
    unfold callListener
    simp only
    split
    · rw [runReactions_received]
    · rfl
  unfold Bus.receivedOf at hrec ⊢
  rw [hrec]
  by_cases hk : k = job.key
  · subst hk; simp [List.lookup]
  · have : (k == job.key) = false := by simpa using hk
    simp [List.lookup, this, hk]

/-- A system listener (one that exists before the model starts) records
nothing and reacts to nothing. -/
theorem runJob_system (now : Nat) (b : Bus) (job : Job) (ev : Event) (h : job.system = true) :
    runJob now b job ev = (b, none) := by
  simp [runJob, h]

/-- A one-time listener that already ran does nothing: no receipt, no
reaction. -/
theorem runJob_once_spent (now : Nat) (b : Bus) (job : Job) (ev : Event)
    (hs : job.system = false) (ho : job.once = true)
    (hr : b.onceRemoved.contains job.key = true) :
    (runJob now b job ev).1.receivedOf job.key = b.receivedOf job.key := by
  have hr' : job.key ∈ b.onceRemoved := by simpa using hr
  simp [runJob, hs, ho, hr']

/-- An ordinary listener that runs gets exactly one more receipt. -/
theorem runJob_plain_receivedOf (now : Nat) (b : Bus) (job : Job) (ev : Event)
    (hs : job.system = false) (ho : job.once = false) :
    (runJob now b job ev).1.receivedOf job.key = b.receivedOf job.key + 1 := by
  simp [runJob, hs, ho, callListener_receivedOf]

/-! ## `Event.as_dict` -/

/-- Every key of `Event.as_dict()`: the type, the data unchanged, the origin's
enum value, `time_fired` as UTC `isoformat()` and the context's dict. -/
theorem Event.asDict_fields (e : Event) :
    e.asDict.getObjVal? "event_type" = .ok (.str e.eventType) ∧
    e.asDict.getObjVal? "data" = .ok e.data ∧
    e.asDict.getObjVal? "origin" = .ok (.str e.origin.value) ∧
    e.asDict.getObjVal? "time_fired" = .ok (.str e.timeFiredIso) ∧
    e.asDict.getObjVal? "context" = .ok e.context.asDict := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> (apply ebMkObj_getObjVal? <;> simp)

/-- An event made for a queued fire with a context shows that context and
the fire's origin in `as_dict()`, and `{}` for missing data. -/
theorem makeEvent_asDict (b : Bus) (q : Queued) (c : Context) (h : q.context = some c) :
    (makeEvent b q).2.asDict.getObjVal? "context" = .ok c.asDict ∧
    (makeEvent b q).2.asDict.getObjVal? "origin" = .ok (.str q.origin.value) ∧
    (makeEvent b q).2.asDict.getObjVal? "data" = .ok (q.data.getD (Json.mkObj [])) ∧
    (makeEvent b q).1 = b := by
  have hf := Event.asDict_fields (makeEvent b q).2
  simp only [makeEvent, h] at hf ⊢
  exact ⟨hf.2.2.2.2, hf.2.2.1, hf.2.1, trivial⟩

end HALean.Core.EventBus
