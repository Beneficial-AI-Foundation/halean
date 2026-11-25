/-
  Specs for the pure helpers of the automation engine
  (HALean/Automation/Engine.lean): timer rounding, trigger variables,
  run-mode admission, state and time-pattern matching, the template
  tracker's change test, and the listener registry.
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

/-! ### `Owner` equality -/

private theorem owner_beq_iff (a b : Owner) : (a == b) = true ↔ a = b := by
  cases a <;> cases b <;> simp [BEq.beq, instBEqOwner.beq]

private instance : LawfulBEq Owner where
  eq_of_beq := fun h => (owner_beq_iff _ _).1 h
  rfl := (owner_beq_iff _ _).2 rfl

/-! ### `usToMs`: whole milliseconds until a µs timer is due -/

/-- A period that is not positive is due at once. -/
theorem usToMs_nonpos (us : Int) (h : us ≤ 0) : usToMs us = 0 := by
  unfold usToMs; omega

/-- A positive period is rounded up: the timer never fires early, and less
than a millisecond late. -/
theorem usToMs_ceil (us : Int) (h : 0 ≤ us) :
    us ≤ (usToMs us : Int) * 1000 ∧ (usToMs us : Int) * 1000 < us + 1000 := by
  unfold usToMs; omega

/-- Exact characterisation: `usToMs us` is `⌈us / 1000⌉`, clamped at 0. -/
theorem usToMs_eq_iff (us : Int) (n : Nat) :
    usToMs us = n ↔
      (us ≤ 0 ∧ n = 0) ∨ (0 < us ∧ us ≤ (n : Int) * 1000 ∧ (n : Int) * 1000 < us + 1000) := by
  unfold usToMs; omega

/-- It is the least millisecond count that covers the period. -/
theorem usToMs_least (us : Int) (n : Nat) (h : us ≤ (n : Int) * 1000) : usToMs us ≤ n := by
  unfold usToMs; omega

theorem usToMs_mono (a b : Int) (h : a ≤ b) : usToMs a ≤ usToMs b := by
  unfold usToMs; omega

/-- Whole milliseconds survive the round trip through microseconds (the
`for:` of a static period shown as a `timedelta`, see `forVal`). -/
theorem usToMs_of_ms (ms : Nat) : usToMs ((ms : Int) * 1000) = ms := by
  unfold usToMs; omega

/-! ### Trigger-variable values -/

theorem forVal_eq_none_iff (p : Option Nat) : forVal p = .none ↔ p = none := by
  cases p <;> simp [forVal]

/-- A static `for:` of `ms` milliseconds is a `timedelta` whose timer length
is `ms` again. -/
theorem forVal_some_timer (ms : Nat) :
    ∃ us : Int, forVal (some ms) = .timedelta us ∧ usToMs us = ms := by
  refine ⟨(ms : Int) * 1000, ?_, usToMs_of_ms ms⟩
  simp [forVal]

theorem stateVal_eq_none_iff (s : Option EntityState) : stateVal s = .none ↔ s = none := by
  cases s <;> simp [stateVal]

theorem boundVal_eq_none_iff (b : Option Bound) : boundVal b = .none ↔ b = none := by
  rcases b with _ | b
  · simp [boundVal]
  · cases b <;> simp [boundVal]

/-- `trigger` is a mapping with string keys: `trigger_data` (`id`, `idx`,
`alias`), `platform`, then the platform's fields in order. -/
theorem triggerValue_keys (t : Trigger) (platform : String)
    (fields : List (String × Template.Value)) :
    ∃ kvs, triggerValue t platform fields = .dict kvs ∧
      kvs.map (·.1) = (["id", "idx", "alias", "platform"] ++ fields.map (·.1)).map .str := by
  refine ⟨_, rfl, ?_⟩
  simp [List.map_map, Function.comp_def]

/-- `trigger.id`, `trigger.idx` and `trigger.platform` are the trigger's. -/
theorem triggerValue_head (t : Trigger) (platform : String)
    (fields : List (String × Template.Value)) :
    ∃ alias rest, triggerValue t platform fields = .dict
      ((.str "id", .str t.id) :: (.str "idx", .str (toString t.idx)) :: (.str "alias", alias)
        :: (.str "platform", .str platform) :: rest) := by
  exact ⟨_, _, rfl⟩

/-- The `trigger` of a state trigger has exactly the keys of
`state.py::call_action`, in HA's order. -/
theorem stateTriggerVars_keys (t : Trigger) (eid : String) (old new : Option EntityState)
    (attr : Option String) (forV : Template.Value) :
    ∃ kvs, (stateTriggerVars t eid old new attr forV).value = .dict kvs ∧
      kvs.map (·.1) = ["id", "idx", "alias", "platform", "entity_id", "from_state", "to_state",
        "for", "attribute", "description"].map .str := by
  exact ⟨_, rfl, rfl⟩

/-- What a numeric_state `value_template` sees as `trigger`: five keys. -/
theorem numericTriggerVar_keys (t : Trigger) (eid : String) (below above : Option Bound)
    (attr : Option String) :
    ∃ kvs, numericTriggerVar t eid below above attr = .dict kvs ∧
      kvs.map (·.1) = ["platform", "entity_id", "below", "above", "attribute"].map .str := by
  exact ⟨_, rfl, rfl⟩

/-! ### `TriggerVars.withFor` -/

/-- Only `value` changes. -/
theorem withFor_fields (tv : TriggerVars) (v : Template.Value) :
    (tv.withFor v).id = tv.id ∧ (tv.withFor v).idx = tv.idx ∧
    (tv.withFor v).platform = tv.platform ∧ (tv.withFor v).entityId = tv.entityId ∧
    (tv.withFor v).description = tv.description := ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- A `trigger` that is not a mapping is left alone. -/
theorem withFor_not_dict (tv : TriggerVars) (v : Template.Value)
    (h : ∀ kvs, tv.value ≠ .dict kvs) : tv.withFor v = tv := by
  unfold TriggerVars.withFor
  split
  · next kvs hk => exact absurd hk (h kvs)
  · rfl

/-- The mapping keeps its keys, in order. -/
theorem withFor_keys (tv : TriggerVars) (v : Template.Value) (kvs : List (Template.Value × Template.Value))
    (h : tv.value = .dict kvs) :
    ∃ kvs', (tv.withFor v).value = .dict kvs' ∧ kvs'.map (·.1) = kvs.map (·.1) := by
  unfold TriggerVars.withFor
  rw [h]
  refine ⟨_, rfl, ?_⟩
  rw [List.map_map]
  apply List.map_congr_left
  intro p _
  rcases p with ⟨k, x⟩
  simp only [Function.comp]
  split <;> rfl

/-- Every `for` entry now holds `v`; every other entry is unchanged. -/
theorem withFor_entries (tv : TriggerVars) (v : Template.Value) (kvs : List (Template.Value × Template.Value))
    (h : tv.value = .dict kvs) :
    ∃ kvs', (tv.withFor v).value = .dict kvs' ∧ kvs'.length = kvs.length ∧
      ∀ i (hi : i < kvs.length) (hi' : i < kvs'.length),
        (kvs[i].1 = .str "for" → kvs'[i] = (.str "for", v)) ∧
        (kvs[i].1 ≠ .str "for" → kvs'[i] = kvs[i]) := by
  unfold TriggerVars.withFor
  rw [h]
  refine ⟨_, rfl, by simp, ?_⟩
  intro i hi hi'
  simp only [List.getElem_map]
  rcases hp : kvs[i] with ⟨k, x⟩
  constructor
  · intro hk
    simp only at hk
    subst hk
    rfl
  · intro hk
    simp only at hk
    split
    · next heq => exact absurd heq hk
    · rfl

/-- The last write wins. -/
theorem withFor_withFor (tv : TriggerVars) (v w : Template.Value) :
    (tv.withFor v).withFor w = tv.withFor w := by
  unfold TriggerVars.withFor
  cases hv : tv.value <;> simp only []
  rename_i kvs
  simp only [List.map_map]
  congr 2
  apply List.map_congr_left
  intro p _
  rcases p with ⟨k, x⟩
  simp only [Function.comp]
  split <;> split <;> simp_all

/-! ### Template trackers -/

/-- `sameKey` is: same owner, same trigger position. -/
theorem sameKey_iff (a b : TmplTrig) :
    a.sameKey b = true ↔ a.owner = b.owner ∧ a.trigIdx = b.trigIdx := by
  simp [TmplTrig.sameKey]

theorem sameKey_refl (a : TmplTrig) : a.sameKey a = true := by simp [sameKey_iff]

theorem sameKey_symm (a b : TmplTrig) : a.sameKey b = b.sameKey a := by
  rw [Bool.eq_iff_iff, sameKey_iff, sameKey_iff]
  constructor <;> (rintro ⟨h1, h2⟩; exact ⟨h1.symm, h2.symm⟩)

theorem sameKey_trans (a b c : TmplTrig) (h1 : a.sameKey b = true) (h2 : b.sameKey c = true) :
    a.sameKey c = true := by
  rw [sameKey_iff] at *
  exact ⟨h1.1.trans h2.1, h1.2.trans h2.2⟩

/-- `_refresh` passes a result on unless it equals the last one (`==`), or
is an error after an error. -/
theorem resultChanged_eq_false_iff (last : Option TmplResult) (r : Except String Template.Value) :
    resultChanged last r = false ↔
      (∃ a b, last = some (.ok a) ∧ r = .ok b ∧ Template.pyEq a b = true) ∨
      (last = some .err ∧ ∃ m, r = .error m) := by
  rcases last with _ | l
  · simp [resultChanged]
  · cases l <;> cases r <;> simp [resultChanged]

/-- The first render after setup always counts as a change. -/
theorem resultChanged_first (r : Except String Template.Value) : resultChanged none r = true := by
  simp [resultChanged]

/-- An error is not reported twice in a row, whatever the messages. -/
theorem resultChanged_error_twice (m m' : String) :
    resultChanged (some (TmplResult.of (.error m))) (.error m') = false := by
  simp [resultChanged, TmplResult.of]

/-- A switch between a value and an error (either way) is a change. -/
theorem resultChanged_ok_error (v : Template.Value) (m : String) :
    resultChanged (some (TmplResult.of (.ok v))) (.error m) = true ∧
    resultChanged (some (TmplResult.of (.error m))) (.ok v) = true := by
  simp [resultChanged, TmplResult.of]

/-! ### State values and `process_state_match` -/

/-- Without an attribute, only a missing state gives `null`. -/
theorem valueOf_state_eq_null_iff (s : Option EntityState) : valueOf none s = .null ↔ s = none := by
  cases s <;> simp [valueOf]

/-- A missing state has no attributes either. -/
theorem valueOf_none (attr : Option String) : valueOf attr none = .null := by
  cases attr <;> rfl

/-- An attribute the state lacks reads as `null` (Python's `attributes.get`). -/
theorem valueOf_attr_missing (a : String) (s : EntityState) (h : s.attr? a = none) :
    valueOf (some a) (some s) = .null := by
  simp [valueOf, h]

/-- Exact characterisation of `process_state_match`. -/
theorem stateMatch_matches_iff (m : StateMatch) (v : Json) :
    m.matches v = true ↔
      (m.values = none ∧ m.invert = false) ∨
      ∃ vs, m.values = some vs ∧ (m.invert = true ↔ vs.any (pyJsonEq · v) = false) := by
  rcases m with ⟨vals, inv⟩
  cases vals <;> cases inv <;> simp [StateMatch.matches]

/-! ### Run modes: exact outcome of `admit` -/

theorem admit_start_iff (mode : Mode) (m n : Nat) :
    admit mode m n = .start ↔ n = 0 ∨ (mode = .parallel ∧ n ≠ m) := by
  unfold admit
  by_cases h0 : n = 0 <;> by_cases hm : n = m <;> cases mode <;> (try subst hm) <;> simp [*]

theorem admit_enqueue_iff (mode : Mode) (m n : Nat) :
    admit mode m n = .enqueue ↔ mode = .queued ∧ n ≠ 0 ∧ n ≠ m := by
  unfold admit
  by_cases h0 : n = 0 <;> by_cases hm : n = m <;> cases mode <;> (try subst hm) <;> simp [*]

theorem admit_restart_iff (mode : Mode) (m n : Nat) :
    admit mode m n = .restart ↔ mode = .restart ∧ n ≠ 0 := by
  unfold admit
  by_cases h0 : n = 0 <;> by_cases hm : n = m <;> cases mode <;> (try subst hm) <;> simp [*]

theorem admit_reject_iff (mode : Mode) (m n : Nat) (why : String) :
    admit mode m n = .reject why ↔ n ≠ 0 ∧
      ((mode = .single ∧ why = "Already running") ∨
       ((mode = .queued ∨ mode = .parallel) ∧ n = m ∧ why = "Maximum number of runs exceeded")) := by
  unfold admit
  by_cases h0 : n = 0 <;> by_cases hm : n = m <;> cases mode <;> (try subst hm) <;>
    (try have hm' : ¬ m = n := fun h => hm h.symm) <;> simp [eq_comm, *]

/-- With nothing running, every mode starts the run. -/
theorem admit_zero (mode : Mode) (m : Nat) : admit mode m 0 = .start := by
  simp [admit]

/-- `max` is respected in every mode but `restart`: a run is added only
below `max` (for `single`, only when nothing runs). -/
theorem admit_adds_below_max (mode : Mode) (m n : Nat) (hn : n ≤ m) (hm : 1 ≤ m)
    (hmode : mode ≠ .restart) (h : ∀ why, admit mode m n ≠ .reject why) : n < m := by
  cases mode
  · have := h "Already running"
    rw [Ne, admit_reject_iff] at this
    simp at this; omega
  · exact absurd rfl hmode
  · have := h "Maximum number of runs exceeded"
    rw [Ne, admit_reject_iff] at this
    simp at this; omega
  · have := h "Maximum number of runs exceeded"
    rw [Ne, admit_reject_iff] at this
    simp at this; omega

/-! ### Time patterns -/

theorem pattern_any (v : Nat) : Pattern.any.matches v = true := rfl

/-- `/n` matches the multiples of `n` (for `n = 0`: only 0). -/
theorem pattern_every_iff (n v : Nat) : (Pattern.every n).matches v = true ↔ n ∣ v := by
  simp [Pattern.matches, Nat.dvd_iff_mod_eq_zero]

theorem pattern_exact_iff (n v : Nat) : (Pattern.exact n).matches v = true ↔ v = n := by
  simp [Pattern.matches]

/-- `/1` is `*`. -/
theorem pattern_every_one (v : Nat) : (Pattern.every 1).matches v = true := by
  simp [pattern_every_iff]

/-! ### Small total functions -/

theorem errKind_str_injective (a b : ErrKind) (h : a.str = b.str) : a = b := by
  cases a <;> cases b <;> first | rfl | (exact absurd h (by decide))

/-- A stop ends the run without `CancelledError` exactly in a top-level
frame waiting on a delay, a wait or its `parallel` branches. -/
theorem stoppedQuietly_iff (r : Run) :
    stoppedQuietly r = true ↔ r.frames.length ≤ 1 ∧
      ((∃ t, r.wait = .delayUntil t) ∨ (∃ t d c, r.wait = .waitTmpl t d c) ∨
       (∃ ts vs d c, r.wait = .waitTrig ts vs d c) ∨ (∃ ids rs c, r.wait = .joinPar ids rs c)) := by
  unfold stoppedQuietly
  cases r.wait <;> simp

/-- A run blocked in a service call is always cancelled loudly. -/
theorem stoppedQuietly_service (r : Run) (cid : Nat) (coe : Bool) (rv : Option String)
    (h : r.wait = .service cid coe rv) : stoppedQuietly r = false := by
  simp [stoppedQuietly, h]

/-- A target that is not a mapping adds nothing to the service data. -/
theorem mergeTarget_not_obj (data target : Json) (h : ∀ kvs, target ≠ .obj kvs) :
    mergeTarget data target = data := by
  unfold mergeTarget
  split
  · next kvs => exact absurd rfl (h kvs)
  · rfl

/-! ### The listener registry -/

/-- One listener group per automation, then one per waiting run. -/
theorem owners_length (e : Engine) :
    e.owners.length = e.automations.length + e.waitTrigs.length := by
  simp [Engine.owners]

/-- Automation `ai` is registered with its own triggers. -/
theorem auto_mem_owners_iff (e : Engine) (ai : Nat) (ts : List Trigger) :
    (Owner.auto ai, ts) ∈ e.owners ↔ ∃ a, e.automations[ai]? = some a ∧ a.triggers = ts := by
  simp only [Engine.owners, List.mem_append, List.mem_map, Prod.mk.injEq, reduceCtorEq, false_and,
    and_false, exists_false, or_false, Prod.exists, Owner.auto.injEq]
  constructor
  · rintro ⟨a, i, hmem, rfl, rfl⟩
    exact ⟨a, (List.mem_zipIdx_iff_getElem?.1 hmem), rfl⟩
  · rintro ⟨a, ha, rfl⟩
    exact ⟨a, ai, List.mem_zipIdx_iff_getElem?.2 (by simpa using ha), rfl, rfl⟩

/-- A waiting run is registered iff it has a `wait_for_trigger` record. -/
theorem wait_mem_owners_iff (e : Engine) (rid : Nat) (ts : List Trigger) :
    (Owner.wait rid, ts) ∈ e.owners ↔ ∃ w ∈ e.waitTrigs, w.runId = rid ∧ w.triggers = ts := by
  simp [Engine.owners]

/-- Everything in the registry is listening. -/
theorem owners_listening (e : Engine) (o : Owner) (ts : List Trigger) (h : (o, ts) ∈ e.owners) :
    e.listening o = true := by
  cases o with
  | auto ai => rfl
  | wait rid =>
    obtain ⟨w, hw, hr, _⟩ := (wait_mem_owners_iff e rid ts).1 h
    simp only [Engine.listening, List.any_eq_true]
    exact ⟨w, hw, by simp [hr]⟩

/-- A wait listens iff it is in the registry. -/
theorem listening_wait_iff (e : Engine) (rid : Nat) :
    e.listening (.wait rid) = true ↔ ∃ ts, (Owner.wait rid, ts) ∈ e.owners := by
  constructor
  · intro h
    simp only [Engine.listening, List.any_eq_true, beq_iff_eq] at h
    obtain ⟨w, hw, hr⟩ := h
    exact ⟨w.triggers, (wait_mem_owners_iff e rid _).2 ⟨w, hw, hr, rfl⟩⟩
  · rintro ⟨ts, h⟩; exact owners_listening e _ ts h

end HALean.Automation
