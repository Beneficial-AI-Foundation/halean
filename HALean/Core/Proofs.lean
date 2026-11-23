/-
  Theorems about the state machine (`HALean/Core/StateMachine.lean`).
-/
import HALean.Core.StateMachine
open Lean

namespace HALean.Core.StateMachine

/-! ### The dict -/

theorem find_map_replace (st : List (String × State)) (k : String) (v : State) :
    (st.map fun p => if p.1 == k then (k, v) else p).find? (·.1 == k)
      = if st.any (·.1 == k) then some (k, v) else none := by
  induction st with
  | nil => simp
  | cons p rest ih =>
    cases hpk : p.1 == k
    · simp only [List.map_cons, List.find?_cons, List.any_cons, hpk, Bool.false_eq_true,
        ite_false, Bool.false_or]
      exact ih
    · simp only [List.map_cons, List.find?_cons, List.any_cons, hpk, ite_true, Bool.true_or,
        beq_self_eq_true]

theorem lookup_setItem (sm : StateMachine) (k : String) (v : State) :
    ({ sm with states := setItem sm.states k v } : StateMachine).lookup k = some v := by
  unfold lookup setItem
  by_cases h : sm.states.any (·.1 == k)
  · simp only [h, ite_true, find_map_replace, Option.map_some]
  · simp only [h]
    have : sm.states.find? (·.1 == k) = none := by
      rw [List.find?_eq_none]; intro x hx hk
      exact h (List.any_eq_true.mpr ⟨x, hx, hk⟩)
    simp [List.find?_append, this]

theorem find_map_replace_other (st : List (String × State)) (k x : String) (v : State)
    (hx : x ≠ k) :
    (st.map fun p => if p.1 == k then (k, v) else p).find? (·.1 == x) = st.find? (·.1 == x) := by
  have hkx : (k == x) = false := by simpa using fun e : k = x => hx e.symm
  induction st with
  | nil => simp
  | cons p rest ih =>
    cases hpk : p.1 == k
    · simp only [List.map_cons, List.find?_cons, hpk, Bool.false_eq_true, ite_false]
      rw [ih]
    · have hpx : (p.1 == x) = false := by
        rw [beq_iff_eq.mp hpk]; exact hkx
      simp only [List.map_cons, List.find?_cons, hpk, ite_true, hkx, hpx]
      exact ih

/-- Setting one entity leaves every other entity as it was. -/
theorem lookup_setItem_other (sm : StateMachine) (k x : String) (v : State) (hx : x ≠ k) :
    ({ sm with states := setItem sm.states k v } : StateMachine).lookup x = sm.lookup x := by
  unfold lookup setItem
  by_cases h : sm.states.any (·.1 == k)
  · simp only [h, ite_true, find_map_replace_other _ _ _ _ hx]
  · have hkx : k ≠ x := fun e => hx e.symm
    simp [h, List.find?_append, hkx]

theorem lookup_delItem (sm : StateMachine) (k : String) :
    ({ sm with states := delItem sm.states k } : StateMachine).lookup k = none := by
  unfold lookup delItem
  simp only [Option.map_eq_none_iff, List.find?_eq_none, List.mem_filter]
  intro x hx
  simpa using hx.2

theorem keys_setItem (st : List (String × State)) (k x : String) (v : State) :
    x ∈ (setItem st k v).map (·.1) ↔ x ∈ st.map (·.1) ∨ x = k := by
  unfold setItem
  by_cases h : st.any (·.1 == k)
  · simp only [h, ite_true, List.map_map]
    have hk : k ∈ st.map (·.1) := by
      obtain ⟨p, hp, hpk⟩ := List.any_eq_true.mp h
      exact List.mem_map.mpr ⟨p, hp, beq_iff_eq.mp hpk⟩
    have : ((·.1) ∘ fun p : String × State => if p.1 == k then (k, v) else p) = (·.1) := by
      funext p; by_cases hp : p.1 = k <;> simp [hp]
    rw [this]
    constructor
    · exact Or.inl
    · rintro (h | rfl) <;> assumption
  · simp [h]

theorem keys_delItem (st : List (String × State)) (k x : String) :
    x ∈ (delItem st k).map (·.1) ↔ x ∈ st.map (·.1) ∧ x ≠ k := by
  unfold delItem
  simp only [List.mem_map, List.mem_filter, bne_iff_ne, ne_eq]
  constructor
  · rintro ⟨p, ⟨hp, hpk⟩, rfl⟩; exact ⟨⟨p, hp, rfl⟩, hpk⟩
  · rintro ⟨⟨p, hp, rfl⟩, hpk⟩; exact ⟨p, ⟨hp, hpk⟩, rfl⟩

/-! ### `async_set_internal` -/

/-- Same state and equal attributes (and no `force_update`): the stored state
is the old one with only `last_reported` moved to now, and the only event is
`state_reported` carrying that state and the previous `last_reported`. -/
theorem set_same_only_reports (sm : StateMachine) (eid st : String) (attrs : Option Json)
    (ctx : Option Context) (now : Int) (o : State)
    (hold : sm.lookup eid = some o) (hst : o.state = st) (hattr : attrsEq o.attributes attrs = true) :
    ∃ sm' c, sm.asyncSetInternal eid st attrs false ctx now
        = .ok (sm', [.stateReported eid now o.lastReported { o with lastReported := now } c now])
      ∧ sm'.lookup eid = some { o with lastReported := now } := by
  unfold asyncSetInternal
  cases ctx with
  | none =>
    refine ⟨{ sm.freshContext.2 with states := setItem sm.freshContext.2.states eid { o with lastReported := now } },
      sm.freshContext.1, ?_, lookup_setItem _ _ _⟩
    simp [hold, hst, hattr, freshContext]
    rfl
  | some c =>
    refine ⟨{ sm with states := setItem sm.states eid { o with lastReported := now } }, c, ?_,
      lookup_setItem _ _ _⟩
    simp [hold, hst, hattr]
    rfl

theorem State.new_ok (e st : String) (a : Option Json) (lc lr lu : Option Int) (c : Context)
    (v : Bool) (now : Int) (s : State) (h : State.new e st a lc lr lu c v now = .ok s) :
    s.entityId = e ∧ s.lastChanged = lc.getD (lu.getD (lr.getD now)) := by
  unfold State.new at h
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
  repeat' split at h
  all_goals first
    | (cases h; done)
    | (cases h; exact ⟨rfl, rfl⟩)

/-- What a successful `async_set_internal` does to the dict: it stores one
state under `eid`, either the old one with only `last_reported` moved (the
report branch) or one made by `State.new`, whose `last_changed` argument is
the old `last_changed` exactly when the state is unchanged. -/
theorem set_cases (sm sm' : StateMachine) (eid st : String) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (now : Int) (evs : List SMEvent)
    (h : sm.asyncSetInternal eid st attrs force ctx now = .ok (sm', evs)) :
    ∃ base : StateMachine, base.states = sm.states ∧ ∃ s : State,
      sm'.states = setItem base.states eid s ∧
      ((∃ o, sm.lookup eid = some o ∧ o.state = st ∧ force = false ∧ s = { o with lastReported := now })
       ∨ ∃ st' a lc v c, State.new eid st' a lc (some now) (some now) c v now = .ok s
          ∧ lc = (match sm.lookup eid with
            | some o => if (o.state == st && !force) then some o.lastChanged else none
            | none => none)) := by
  unfold asyncSetInternal at h
  cases ctx <;> cases hold : sm.lookup eid <;>
    simp only [hold, bind, Except.bind, pure, Except.pure] at h
  all_goals
    split at h
  all_goals first
    | (rename_i s hnew; cases h; exact ⟨_, rfl, s, rfl, Or.inr ⟨_, _, _, _, _, hnew, by simp⟩⟩)
    | (rename_i hrep; cases h
       simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hrep
       exact ⟨_, rfl, _, rfl, Or.inl ⟨_, rfl, hrep.1.1, hrep.1.2, rfl⟩⟩)
    | (cases h; done)
    | (split at h
       · cases h
       · rename_i s hnew; cases h; exact ⟨_, rfl, s, rfl, Or.inr ⟨_, _, _, _, _, hnew, by simp⟩⟩)

theorem lookup_eq_of_states {a b : StateMachine} (h : a.states = b.states) (k : String) :
    a.lookup k = b.lookup k := by
  simp [lookup, h]

/-- `async_set` with the same state never moves `last_changed`, whether the
attributes changed (new state object) or not (report only). -/
theorem set_same_state_keeps_last_changed (sm sm' : StateMachine) (eid st : String)
    (attrs : Option Json) (ctx : Option Context) (now : Int) (o : State) (evs : List SMEvent)
    (hold : sm.lookup eid = some o) (hst : o.state = st)
    (h : sm.asyncSetInternal eid st attrs false ctx now = .ok (sm', evs)) :
    ∃ s, sm'.lookup eid = some s ∧ s.lastChanged = o.lastChanged := by
  obtain ⟨base, hb, s, hs, hcase⟩ := set_cases sm sm' eid st attrs false ctx now evs h
  have hl : sm'.lookup eid = some s := by
    have := lookup_setItem base eid s
    rw [← this]; exact lookup_eq_of_states (by simp [hs]) eid
  refine ⟨s, hl, ?_⟩
  rcases hcase with ⟨o', ho', _, _, rfl⟩ | ⟨st', a, lc, v, c, hnew, hlc⟩
  · rw [hold] at ho'; cases ho'; rfl
  · have := (State.new_ok _ _ _ _ _ _ _ _ _ _ hnew).2
    simp [hold, hst] at hlc
    rw [this, hlc]; rfl

/-- A successful `async_set_internal` stores a state under the id it was given
and changes no other entity. -/
theorem set_frame (sm sm' : StateMachine) (eid st : String) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (now : Int) (evs : List SMEvent)
    (h : sm.asyncSetInternal eid st attrs force ctx now = .ok (sm', evs)) :
    (sm'.lookup eid).isSome ∧ ∀ x, x ≠ eid → sm'.lookup x = sm.lookup x := by
  obtain ⟨base, hb, s, hs, _⟩ := set_cases sm sm' eid st attrs force ctx now evs h
  have e : ∀ k, sm'.lookup k = ({ base with states := setItem base.states eid s } : StateMachine).lookup k :=
    lookup_eq_of_states (by simp [hs])
  refine ⟨by simp [e, lookup_setItem], fun x hx => ?_⟩
  rw [e, lookup_setItem_other _ _ _ _ hx]
  exact lookup_eq_of_states hb x

/-- The entity ids after a successful set: the old ones plus the id set. -/
theorem set_keys (sm sm' : StateMachine) (eid st : String) (attrs : Option Json)
    (force : Bool) (ctx : Option Context) (now : Int) (evs : List SMEvent)
    (h : sm.asyncSetInternal eid st attrs force ctx now = .ok (sm', evs)) (x : String) :
    x ∈ sm'.states.map (·.1) ↔ x ∈ sm.states.map (·.1) ∨ x = eid := by
  obtain ⟨base, hb, s, hs, _⟩ := set_cases sm sm' eid st attrs force ctx now evs h
  rw [hs, keys_setItem, hb]

/-! ### `async_remove` -/

/-- After `async_remove`, the removed (lower-cased) id is gone. -/
theorem remove_then_lookup_none (sm sm' : StateMachine) (eid : String) (ctx : Option Context)
    (now : Int) (b : Bool) (evs : List SMEvent)
    (h : sm.asyncRemove eid ctx now = .ok (b, sm', evs)) :
    sm'.lookup (lowerAscii eid) = none := by
  unfold asyncRemove at h
  simp [checkAscii, bind, Except.bind, pure, Except.pure] at h
  split at h
  · cases h
  · split at h
    · cases h; exact lookup_delItem _ _
    · cases ctx <;> (cases h; simp [freshContext, lookup, delItem])

/-- Remove, then get: `None` (for an id that is already lower case). -/
theorem remove_then_get_none (sm sm' : StateMachine) (eid : String) (ctx : Option Context)
    (now : Int) (b : Bool) (evs : List SMEvent) (hlow : lowerAscii eid = eid)
    (h : sm.asyncRemove eid ctx now = .ok (b, sm', evs)) :
    sm'.get eid = .ok none := by
  have hl := remove_then_lookup_none sm sm' eid ctx now b evs h
  rw [hlow] at hl
  have hasc : isAscii eid = true := by
    by_cases ha : isAscii eid = true
    · exact ha
    · simp [asyncRemove, checkAscii, ha, bind, Except.bind, throw, throwThe,
        MonadExceptOf.throw] at h
  simp [get, checkAscii, hasc, hl, hlow, bind, Except.bind, pure, Except.pure]

/-- The entity ids after a successful remove: the old ones minus the id. -/
theorem remove_keys (sm sm' : StateMachine) (eid : String) (ctx : Option Context)
    (now : Int) (b : Bool) (evs : List SMEvent)
    (h : sm.asyncRemove eid ctx now = .ok (b, sm', evs)) (x : String) :
    x ∈ sm'.states.map (·.1) ↔ x ∈ sm.states.map (·.1) ∧ x ≠ lowerAscii eid := by
  unfold asyncRemove at h
  simp [checkAscii, bind, Except.bind, pure, Except.pure] at h
  split at h
  · cases h
  · split at h
    · cases h; exact keys_delItem _ _ _
    · cases ctx <;> (cases h; simpa [freshContext] using keys_delItem sm.states (lowerAscii eid) x)

/-! ### The domain index -/

/-- `async_entity_ids(domain)` lists exactly the stored entities of that
domain (with `set_keys` / `remove_keys`: those set and not removed since). -/
theorem mem_domainEntityIds (sm : StateMachine) (d x : String) :
    x ∈ sm.domainEntityIds d ↔ ∃ s, (x, s) ∈ sm.states ∧ s.domain = d := by
  simp [domainEntityIds, List.mem_map, List.mem_filter]

/-! ### Reservations -/

/-- A reserved id is no longer available. -/
theorem reserve_then_unavailable (sm sm' : StateMachine) (eid : String)
    (hasc : isAscii eid = true) (hlow : lowerAscii eid = eid)
    (h : sm.asyncReserve eid = .ok sm') : sm'.asyncAvailable eid = .ok false := by
  unfold asyncReserve at h
  split at h
  · cases h
  · cases h
    simp [asyncAvailable, checkAscii, hasc, hlow, bind, Except.bind, pure, Except.pure]

end HALean.Core.StateMachine
