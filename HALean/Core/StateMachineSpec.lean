/-
  More specifications for `HALean/Core/StateMachine.lean` (what
  `Proofs.lean` does not cover): the ASCII and length guards, the read
  operations (`async_entity_ids`, `async_entity_ids_count`, `async_all`,
  `is_state`, `domain_states`), fresh contexts, and what the fired events
  carry (`SMEvent.context`, `SMEvent.timeFired`, `SMEvent.toJson`).
-/
import Std.Data.TreeMap.Raw.Lemmas
import HALean.Core.StateMachine
open Lean HALean.Template

namespace HALean.Core

private theorem smMkObj_getObjVal? {l : List (String × Json)} {k : String} {v : Json}
    (distinct : l.Pairwise (fun a b => ¬ a.1 = b.1)) (mem : (k, v) ∈ l) :
    (Json.mkObj l).getObjVal? k = .ok v := by
  have h : (Std.TreeMap.Raw.ofList l compare)[k]? = some v :=
    Std.TreeMap.Raw.getElem?_ofList_of_mem (k := k) (by simp)
      (by simpa using distinct) mem
  have h' : (Std.TreeMap.Raw.ofList l compare).get? k = some v := h
  simp only [Json.mkObj, Json.getObjVal?]
  rw [h']; rfl

/-! ## Events -/

/-- The two event types are different strings. -/
theorem event_types_ne : EVENT_STATE_CHANGED ≠ EVENT_STATE_REPORTED := by decide

/-- An event is `state_reported` exactly when it is the report constructor. -/
theorem SMEvent.eventType_reported_iff (e : SMEvent) :
    e.eventType = EVENT_STATE_REPORTED ↔
      ∃ eid lr olr n c t, e = .stateReported eid lr olr n c t := by
  cases e with
  | stateChanged eid o n c t =>
    simp only [SMEvent.eventType]
    constructor
    · intro h; exact absurd h event_types_ne
    · rintro ⟨_, _, _, _, _, _, h⟩; cases h
  | stateReported eid lr olr n c t =>
    simp only [SMEvent.eventType, true_iff]
    exact ⟨_, _, _, _, _, _, rfl⟩

/-- An event is `state_changed` exactly when it is the change constructor. -/
theorem SMEvent.eventType_changed_iff (e : SMEvent) :
    e.eventType = EVENT_STATE_CHANGED ↔
      ∃ eid o n c t, e = .stateChanged eid o n c t := by
  cases e with
  | stateChanged eid o n c t =>
    simp only [SMEvent.eventType, true_iff]
    exact ⟨_, _, _, _, _, rfl⟩
  | stateReported eid lr olr n c t =>
    simp only [SMEvent.eventType]
    constructor
    · intro h; exact absurd h.symm event_types_ne
    · rintro ⟨_, _, _, _, _, h⟩; cases h

/-- What a listener (and the differential test) reads from the event: its
type, data, context dict, `time_fired` as UTC `isoformat()`, and origin
`LOCAL` (the state machine never fires a remote event). -/
theorem SMEvent.toJson_fields (e : SMEvent) :
    e.toJson.getObjVal? "event_type" = .ok (.str e.eventType) ∧
    e.toJson.getObjVal? "data" = .ok e.dataJson ∧
    e.toJson.getObjVal? "context" = .ok e.context.asDict ∧
    e.toJson.getObjVal? "time_fired" = .ok (.str (isoUtc e.timeFired)) ∧
    e.toJson.getObjVal? "origin" = .ok (.str "LOCAL") := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> (apply smMkObj_getObjVal? <;> simp)

namespace StateMachine

/-! ## Guards -/

/-- `checkAscii` passes exactly on ASCII text. -/
theorem checkAscii_ok_iff (what s : String) : checkAscii what s = .ok () ↔ isAscii s = true := by
  unfold checkAscii
  split <;> simp_all [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- Its only error is `unsupported` (never one of HA's exceptions). -/
theorem checkAscii_error (what s : String) (e : SMError) (h : checkAscii what s = .error e) :
    isAscii s = false ∧ ∃ m, e = .unsupported m := by
  unfold checkAscii at h
  split at h
  · cases h
  · simp only [throw, throwThe, MonadExceptOf.throw] at h
    cases h
    exact ⟨by simp_all, _, rfl⟩

/-- `validate_state` passes exactly up to `MAX_LENGTH_STATE_STATE` (255)
characters. -/
theorem validateState_ok_iff (st : String) :
    validateState st = .ok () ↔ st.length ≤ MAX_LENGTH_STATE_STATE := by
  unfold validateState
  split <;> simp_all [pure, Except.pure, throw, throwThe, MonadExceptOf.throw] <;> omega

/-- Its only error is `InvalidStateError`. -/
theorem validateState_error (st : String) (e : SMError) (h : validateState st = .error e) :
    st.length > MAX_LENGTH_STATE_STATE ∧ ∃ m, e = .invalidState m := by
  unfold validateState at h
  split at h
  · rename_i hl
    simp only [throw, throwThe, MonadExceptOf.throw] at h
    cases h
    exact ⟨hl, _, rfl⟩
  · cases h

/-- `async_set` raises `InvalidStateError` for a state longer than 255
characters, whatever is in the machine (unlike `async_set_internal`, which
stores `unknown`). -/
theorem asyncSet_too_long (sm : StateMachine) (eid st : String) (v : Value) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (ts : Int)
    (hasc : isAscii eid = true) (hstr : pyStr v = .ok st)
    (hlen : st.length > MAX_LENGTH_STATE_STATE) :
    ∃ m, sm.asyncSet eid v attrs force ctx ts = .error (.invalidState m) := by
  have h1 : checkAscii "entity_id" eid = .ok () := (checkAscii_ok_iff _ _).mpr hasc
  unfold asyncSet
  simp only [h1, hstr, bind, Except.bind, pure, Except.pure]
  cases hv : validateState st with
  | ok u => exact absurd ((validateState_ok_iff st).mp (by cases u; exact hv)) (by omega)
  | error e =>
    obtain ⟨_, m, rfl⟩ := validateState_error st e hv
    exact ⟨m, rfl⟩

/-- `async_set` on a non-ASCII id is outside the model, before anything else
is looked at. -/
theorem asyncSet_non_ascii (sm : StateMachine) (eid : String) (v : Value) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (ts : Int) (hasc : isAscii eid = false) :
    ∃ m, sm.asyncSet eid v attrs force ctx ts = .error (.unsupported m) := by
  unfold asyncSet checkAscii
  simp [hasc, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-! ## `domain_states` -/

/-- `domain_states(d)` is the states of the dict whose domain is `d`. -/
theorem mem_domainStates (sm : StateMachine) (d : String) (s : State) :
    s ∈ sm.domainStates d ↔ ∃ k, (k, s) ∈ sm.states ∧ s.domain = d := by
  simp [domainStates, List.mem_map, List.mem_filter]

/-- Every state it returns has that domain. -/
theorem domainStates_domain (sm : StateMachine) (d : String) :
    ∀ s ∈ sm.domainStates d, s.domain = d := by
  intro s hs
  obtain ⟨_, _, h⟩ := (mem_domainStates sm d s).mp hs
  exact h

/-- `domain_entity_ids` and `domain_states` list the same entries, in the
same (dict) order: zipped, they are the dict filtered by domain. -/
theorem domainEntityIds_zip_domainStates (sm : StateMachine) (d : String) :
    (sm.domainEntityIds d).zip (sm.domainStates d) = sm.states.filter (·.2.domain == d) := by
  unfold domainEntityIds domainStates
  generalize sm.states.filter (·.2.domain == d) = l
  induction l with
  | nil => rfl
  | cons p rest ih => simp [ih]

theorem domainStates_length (sm : StateMachine) (d : String) :
    (sm.domainStates d).length = (sm.domainEntityIds d).length := by
  simp [domainStates, domainEntityIds]

/-- The domain lists are sublists of the whole dict's. -/
theorem domainStates_sublist (sm : StateMachine) (d : String) :
    (sm.domainStates d).Sublist (sm.states.map (·.2)) :=
  (List.filter_sublist).map _

/-! ## `async_entity_ids`, `async_entity_ids_count`, `async_all` -/

private theorem foldl_add_length {α β} (f : α → List β) (ds : List α) (n : Nat) :
    (ds.map fun d => (f d).length).foldl (· + ·) n = n + (ds.flatMap f).length := by
  induction ds generalizing n with
  | nil => simp
  | cons d rest ih => simp [ih, Nat.add_assoc]

/-- `async_entity_ids_count` is the length of `async_entity_ids`, for every
kind of filter, and fails exactly when it does. -/
theorem asyncEntityIdsCount_eq (sm : StateMachine) (f : DomainFilter) :
    sm.asyncEntityIdsCount f = (sm.asyncEntityIds f).map List.length := by
  cases f with
  | all => simp [asyncEntityIdsCount, asyncEntityIds, pure, Except.pure, Except.map]
  | one d =>
    simp only [asyncEntityIdsCount, asyncEntityIds, bind, Except.bind]
    cases checkAscii "domain" d <;> rfl
  | many ds =>
    simp [asyncEntityIdsCount, asyncEntityIds, pure, Except.pure, Except.map, foldl_add_length]

/-- `async_all` returns as many states as `async_entity_ids` returns ids. -/
theorem asyncAll_length (sm : StateMachine) (f : DomainFilter) :
    (sm.asyncAll f).map List.length = sm.asyncEntityIdsCount f := by
  rw [asyncEntityIdsCount_eq]
  cases f with
  | all => simp [asyncAll, asyncEntityIds, pure, Except.pure, Except.map]
  | one d =>
    simp only [asyncAll, asyncEntityIds, bind, Except.bind]
    cases checkAscii "domain" d <;>
      simp [Except.map, pure, Except.pure, domainStates_length]
  | many ds =>
    simp only [asyncAll, asyncEntityIds, pure, Except.pure, Except.map, Except.ok.injEq]
    induction ds with
    | nil => rfl
    | cons d rest ih => simp [List.flatMap_cons, ih, domainStates_length]

/-- The reads fail only for a non-ASCII `str` filter; `None` and an iterable
never fail. -/
theorem asyncEntityIds_ok_iff (sm : StateMachine) (f : DomainFilter) :
    (∃ l, sm.asyncEntityIds f = .ok l) ↔ ∀ d, f = .one d → isAscii d = true := by
  cases f with
  | all => simp [asyncEntityIds, pure, Except.pure]
  | many ds => simp [asyncEntityIds, pure, Except.pure]
  | one d =>
    simp only [asyncEntityIds, bind, Except.bind, DomainFilter.one.injEq, forall_eq']
    rw [← checkAscii_ok_iff "domain" d]
    cases checkAscii "domain" d <;> simp [pure, Except.pure]

/-- Without a filter: every key of the dict, in dict order. -/
theorem mem_asyncEntityIds_all (sm : StateMachine) (x : String) (l : List String)
    (h : sm.asyncEntityIds .all = .ok l) : x ∈ l ↔ ∃ s, (x, s) ∈ sm.states := by
  simp only [asyncEntityIds, pure, Except.pure, Except.ok.injEq] at h
  subst h
  simp

/-- A `str` filter is lower-cased; the domains of an iterable are not. So
`async_entity_ids("LIGHT")` is `async_entity_ids(["light"])`. -/
theorem asyncEntityIds_one_eq_many (sm : StateMachine) (d : String) (h : isAscii d = true) :
    sm.asyncEntityIds (.one d) = sm.asyncEntityIds (.many [lowerAscii d]) := by
  simp [asyncEntityIds, (checkAscii_ok_iff "domain" d).mpr h, bind, Except.bind]

/-- The same for `async_all`. -/
theorem asyncAll_one_eq_many (sm : StateMachine) (d : String) (h : isAscii d = true) :
    sm.asyncAll (.one d) = sm.asyncAll (.many [lowerAscii d]) := by
  simp [asyncAll, (checkAscii_ok_iff "domain" d).mpr h, bind, Except.bind]

/-- An id listed for an iterable of domains belongs to one of them. -/
theorem mem_asyncEntityIds_many (sm : StateMachine) (ds : List String) (x : String)
    (l : List String) (h : sm.asyncEntityIds (.many ds) = .ok l) :
    x ∈ l ↔ ∃ d ∈ ds, ∃ s, (x, s) ∈ sm.states ∧ s.domain = d := by
  simp only [asyncEntityIds, pure, Except.pure, Except.ok.injEq] at h
  subst h
  simp [domainEntityIds, List.mem_flatMap, List.mem_map, List.mem_filter]

/-- Every state `async_all` returns for an iterable of domains has one of
those domains. -/
theorem asyncAll_many_domain (sm : StateMachine) (ds : List String) (l : List State)
    (h : sm.asyncAll (.many ds) = .ok l) : ∀ s ∈ l, s.domain ∈ ds := by
  simp only [asyncAll, pure, Except.pure, Except.ok.injEq] at h
  subst h
  intro s hs
  obtain ⟨d, hd, hsd⟩ := List.mem_flatMap.mp hs
  rw [domainStates_domain sm d s hsd]; exact hd

/-! ## `is_state` -/

/-- `is_state(entity_id, state)` is `get(entity_id)` compared with `state`:
`False` for a missing entity, and the same error as `get`. -/
theorem isState_eq (sm : StateMachine) (eid st : String) :
    sm.isState eid st = (sm.get eid).map fun o => o.any (·.state == st) := by
  unfold isState
  cases h : sm.get eid with
  | error e => rfl
  | ok o => cases o <;> rfl

/-- `is_state` is true exactly when `get` finds a state with that value. -/
theorem isState_true_iff (sm : StateMachine) (eid st : String) :
    sm.isState eid st = .ok true ↔ ∃ s, sm.get eid = .ok (some s) ∧ s.state = st := by
  rw [isState_eq]
  cases h : sm.get eid with
  | error e => simp [Except.map]
  | ok o => cases o <;> simp [Except.map]

/-- An entity is never in two states at once. -/
theorem isState_unique (sm : StateMachine) (eid a b : String)
    (ha : sm.isState eid a = .ok true) (hb : sm.isState eid b = .ok true) : a = b := by
  obtain ⟨s, hs, rfl⟩ := (isState_true_iff _ _ _).mp ha
  obtain ⟨t, ht, rfl⟩ := (isState_true_iff _ _ _).mp hb
  rw [hs] at ht; cases ht; rfl

/-- On an empty machine `is_state` is `False` for every ASCII id. -/
theorem isState_empty (eid st : String) (h : isAscii eid = true) :
    ({} : StateMachine).isState eid st = .ok false := by
  rw [isState_eq]
  simp [get, (checkAscii_ok_iff "entity_id" eid).mpr h, bind, Except.bind, pure, Except.pure,
    lookup, Except.map]

/-! ## Fresh contexts -/

/-- Making a fresh context touches nothing but the counter, and the context
has no user and no parent (`Context()`). -/
theorem freshContext_spec (sm : StateMachine) :
    sm.freshContext.2.states = sm.states ∧
    sm.freshContext.2.reservations = sm.reservations ∧
    sm.freshContext.2.freshCount = sm.freshCount + 1 ∧
    sm.freshContext.1.userId = none ∧ sm.freshContext.1.parentId = none :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The fresh context is named after the counter alone: two machines with the
same count name it the same (what lets the differential test rename HA's
ULIDs in order of appearance). -/
theorem freshContext_congr (a b : StateMachine) (h : a.freshCount = b.freshCount) :
    a.freshContext.1 = b.freshContext.1 := by
  simp [freshContext, h]

/-! ## What the fired events carry -/

/-- `async_remove` fires at most one event: a `state_changed` at the clock
`now`, with the context passed (or a fresh one), exactly when it removed
something. -/
theorem asyncRemove_events (sm sm' : StateMachine) (eid : String) (ctx : Option Context)
    (now : Int) (removed : Bool) (evs : List SMEvent)
    (h : sm.asyncRemove eid ctx now = .ok (removed, sm', evs)) :
    evs.length = (if removed then 1 else 0) ∧
    ∀ ev ∈ evs, ev.eventType = EVENT_STATE_CHANGED ∧ ev.timeFired = now ∧
      (∀ c, ctx = some c → ev.context = c) ∧
      (ctx = none → ev.context = sm.freshContext.1) := by
  unfold asyncRemove at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · cases h
  · split at h
    · cases h; simp
    · cases ctx with
      | some c =>
        cases h
        simp [SMEvent.eventType, SMEvent.timeFired, SMEvent.context]
      | none =>
        cases h
        simp [SMEvent.eventType, SMEvent.timeFired, SMEvent.context, freshContext]

/-- A removal that passes its context does not use up a fresh one. -/
theorem asyncRemove_freshCount (sm sm' : StateMachine) (eid : String) (c : Context)
    (now : Int) (removed : Bool) (evs : List SMEvent)
    (h : sm.asyncRemove eid (some c) now = .ok (removed, sm', evs)) :
    sm'.freshCount = sm.freshCount := by
  unfold asyncRemove at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · cases h
  · split at h <;> (cases h; rfl)

/-- `async_set_internal` fires exactly one event, at the clock `timestamp`,
with the context passed (or the fresh one): `state_reported` or
`state_changed`. -/
theorem asyncSetInternal_events (sm sm' : StateMachine) (eid st : String) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (ts : Int) (evs : List SMEvent)
    (h : sm.asyncSetInternal eid st attrs force ctx ts = .ok (sm', evs)) :
    ∃ ev, evs = [ev] ∧ ev.timeFired = ts ∧
      (∀ c, ctx = some c → ev.context = c) ∧
      (ctx = none → ev.context = sm.freshContext.1) ∧
      (ev.eventType = EVENT_STATE_CHANGED ∨ ev.eventType = EVENT_STATE_REPORTED) := by
  unfold asyncSetInternal at h
  cases ctx <;> cases hold : sm.lookup eid <;>
    simp only [hold, bind, Except.bind, pure, Except.pure] at h
  all_goals
    split at h
  all_goals first
    | (cases h; done)
    | (cases h
       exact ⟨_, rfl, rfl, by simp [SMEvent.context, freshContext], by simp [SMEvent.context, freshContext],
         by simp [SMEvent.eventType]⟩)
    | (split at h
       · cases h
       · cases h
         exact ⟨_, rfl, rfl, by simp [SMEvent.context, freshContext],
           by simp [SMEvent.context, freshContext], by simp [SMEvent.eventType]⟩)

/-- With `force_update` the event is always `state_changed` (a forced update
is never just a report). -/
theorem asyncSetInternal_force_changed (sm sm' : StateMachine) (eid st : String)
    (attrs : Option Json) (ctx : Option Context) (ts : Int) (evs : List SMEvent)
    (h : sm.asyncSetInternal eid st attrs true ctx ts = .ok (sm', evs)) :
    ∀ ev ∈ evs, ev.eventType = EVENT_STATE_CHANGED := by
  unfold asyncSetInternal at h
  cases ctx <;> cases hold : sm.lookup eid <;>
    simp only [hold, bind, Except.bind, pure, Except.pure, Bool.not_true, Bool.and_false,
      Bool.false_and, Bool.false_eq_true, ite_false] at h
  all_goals
    split at h
  all_goals first
    | (cases h; done)
    | (cases h; simp [SMEvent.eventType])

/-- A new entity's first event is `state_changed` with no old state. -/
theorem asyncSetInternal_new_entity (sm sm' : StateMachine) (eid st : String)
    (attrs : Option Json) (force : Bool) (ctx : Option Context) (ts : Int) (evs : List SMEvent)
    (hnew : sm.lookup eid = none)
    (h : sm.asyncSetInternal eid st attrs force ctx ts = .ok (sm', evs)) :
    ∃ s c, evs = [.stateChanged eid none (some s) c ts] ∧ s.entityId = eid ∧ s.lastChanged = ts := by
  unfold asyncSetInternal at h
  cases ctx <;>
    simp only [hnew, bind, Except.bind, pure, Except.pure] at h
  all_goals
    split at h
  all_goals first
    | (cases h; done)
    | (rename_i s hs
       cases h
       unfold State.new at hs
       simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at hs
       repeat' split at hs
       all_goals first
         | (cases hs; done)
         | (cases hs; exact ⟨_, _, rfl, rfl, rfl⟩))

end StateMachine
end HALean.Core
