/-
  Specifications for `HALean/Core/Types.lean`: the `States` association list
  behaves like Python's `dict` (lookup after insert / delete, first-insertion
  order), and the `Instant` clock arithmetic stays within its bounds and
  advances as a calendar does.
-/
import HALean.Core.Types

namespace HALean.TypesSpec
open HALean

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

/-! ## `States`: a dict keyed by entity id -/

theorem any_key_iff (st : States) (k : String) :
    (st.any (·.1 == k) = true) ↔ k ∈ st.map (·.1) := by
  constructor
  · intro h
    obtain ⟨p, hp, hk⟩ := List.any_eq_true.mp h
    exact List.mem_map.mpr ⟨p, hp, by simpa using hk⟩
  · intro h
    obtain ⟨p, hp, hk⟩ := List.mem_map.mp h
    exact List.any_eq_true.mpr ⟨p, hp, by simpa using hk⟩

theorem find_replace (st : States) (s : EntityState)
    (h : st.any (·.1 == s.entityId) = true) :
    (st.map fun p => if p.1 == s.entityId then (s.entityId, s) else p).find? (·.1 == s.entityId)
      = some (s.entityId, s) := by
  induction st with
  | nil => simp at h
  | cons p ps ih =>
    rw [List.map_cons, List.find?_cons]
    by_cases hp : (p.1 == s.entityId) = true
    · rw [ifP hp]; simp only [beq_self_eq_true]
    · have h' : ps.any (·.1 == s.entityId) = true := by
        simpa [List.any_cons, hp] using h
      rw [ifN hp]
      have hp2 : (p.1 == s.entityId) = false := by simpa using hp
      simp only [hp2]
      exact ih h'

theorem find_replace_other (st : States) (s : EntityState) (eid : String)
    (hne : eid ≠ s.entityId) :
    (st.map fun p => if p.1 == s.entityId then (s.entityId, s) else p).find? (·.1 == eid)
      = st.find? (·.1 == eid) := by
  induction st with
  | nil => rfl
  | cons p ps ih =>
    rw [List.map_cons, List.find?_cons, List.find?_cons, ih]
    by_cases hp : (p.1 == s.entityId) = true
    · have hp' : p.1 = s.entityId := by simpa using hp
      have h1 : (s.entityId == eid) = false := by simpa using fun h => hne h.symm
      have h2 : (p.1 == eid) = false := by rw [hp']; exact h1
      rw [ifP hp]; simp only [h1, h2]
    · rw [ifN hp]

/-- `d[k] = v; d[k]` is `v`. -/
theorem get?_set_same (st : States) (s : EntityState) :
    (st.set s).get? s.entityId = some s := by
  unfold States.set States.get?
  by_cases h : st.any (·.1 == s.entityId) = true
  · rw [ifP h, find_replace st s h]; rfl
  · have hn : ∀ p ∈ st, (p.1 == s.entityId) = false := by
      intro p hp
      cases hq : p.1 == s.entityId
      · rfl
      · exact absurd (List.any_eq_true.mpr ⟨p, hp, hq⟩) h
    rw [ifN h, List.find?_append, List.find?_eq_none.mpr (by simpa using hn)]
    simp

/-- Writing one entity leaves every other entity's lookup unchanged. -/
theorem get?_set_other (st : States) (s : EntityState) (eid : String)
    (hne : eid ≠ s.entityId) : (st.set s).get? eid = st.get? eid := by
  unfold States.set States.get?
  have h1 : (s.entityId == eid) = false := by simpa using fun h => hne h.symm
  split
  · rw [find_replace_other st s eid hne]
  · rw [List.find?_append]
    cases st.find? (·.1 == eid) <;> simp [List.find?, h1]

/-- The keys after a write: unchanged (same order) when the entity existed,
otherwise the new id is appended (first-insertion order, like a `dict`). -/
theorem keys_set (st : States) (s : EntityState) :
    (st.set s).map (·.1) =
      if s.entityId ∈ st.map (·.1) then st.map (·.1) else st.map (·.1) ++ [s.entityId] := by
  unfold States.set
  have hany := any_key_iff st s.entityId
  by_cases h : st.any (·.1 == s.entityId) = true
  · rw [ifP h, ifP (hany.mp h), List.map_map]
    apply List.map_congr_left
    intro p _
    by_cases hp : p.1 == s.entityId
    · have : p.1 = s.entityId := by simpa using hp
      simp [this]
    · have : ¬ p.1 = s.entityId := by simpa using hp
      simp [this]
  · rw [ifN h, ifN (fun hm => h (hany.mpr hm))]; simp

/-- A write never changes the number of entities by more than the one added. -/
theorem length_set (st : States) (s : EntityState) :
    (st.set s).length = if s.entityId ∈ st.map (·.1) then st.length else st.length + 1 := by
  have := congrArg List.length (keys_set st s)
  split at this <;> simp_all

/-- Writing the same snapshot twice is the same as writing it once. -/
theorem set_set (st : States) (s : EntityState) : (st.set s).set s = st.set s := by
  have hmem : s.entityId ∈ (st.set s).map (·.1) := by
    rw [keys_set]; split <;> simp_all
  have hany : (st.set s).any (·.1 == s.entityId) = true := (any_key_iff _ _).mpr hmem
  have e : ∀ t : States, t.any (·.1 == s.entityId) = true →
      t.set s = t.map (fun p => if p.1 == s.entityId then (s.entityId, s) else p) := by
    intro t ht; unfold States.set; rw [ifP ht]
  rw [e _ hany]
  -- every pair keyed by the id already holds `s`
  have hall : ∀ p ∈ st.set s, (p.1 == s.entityId) = true → p = (s.entityId, s) := by
    intro p hp hk
    unfold States.set at hp
    split at hp
    · obtain ⟨q, _, rfl⟩ := List.mem_map.mp hp
      by_cases hq : q.1 == s.entityId
      · simp [hq]
      · simp [hq] at hk
    · rename_i hno
      rcases List.mem_append.mp hp with hp | hp
      · exact absurd (List.any_eq_true.mpr ⟨p, hp, hk⟩) hno
      · simpa using hp
  calc (st.set s).map (fun p => if p.1 == s.entityId then (s.entityId, s) else p)
      = (st.set s).map id := by
        apply List.map_congr_left
        intro p hp
        by_cases hk : p.1 == s.entityId
        · simp [hall p hp hk]
        · simp [hk]
    _ = st.set s := List.map_id _

/-- `del d[k]`: the entity is gone. -/
theorem get?_remove_same (st : States) (eid : String) : (st.remove eid).get? eid = none := by
  unfold States.remove States.get?
  rw [List.find?_eq_none.mpr]; · rfl
  intro p hp
  have := (List.mem_filter.mp hp).2
  simpa using this

/-- Removing one entity leaves the others' lookups unchanged. -/
theorem get?_remove_other (st : States) (eid x : String) (hne : x ≠ eid) :
    (st.remove eid).get? x = st.get? x := by
  unfold States.remove States.get?
  congr 1
  induction st with
  | nil => rfl
  | cons p ps ih =>
    rw [List.filter_cons, List.find?_cons]
    by_cases hp : (p.1 == eid) = true
    · have hp' : p.1 = eid := by simpa using hp
      have h1 : (p.1 == x) = false := by rw [hp']; simpa using fun h => hne h.symm
      have h2 : (p.1 != eid) = false := by simp [hp']
      simp only [h1, h2]; exact ih
    · have h2 : (p.1 != eid) = true := by simpa using hp
      rw [ifP h2, List.find?_cons, ih]

/-- Removal keeps the remaining entities in order. -/
theorem keys_remove (st : States) (eid : String) :
    (st.remove eid).map (·.1) = (st.map (·.1)).filter (· != eid) := by
  unfold States.remove
  rw [List.filter_map]; rfl

/-- Removing an entity that is not there changes nothing. -/
theorem remove_absent (st : States) (eid : String) (h : st.get? eid = none) :
    st.remove eid = st := by
  unfold States.remove
  unfold States.get? at h
  have hn : st.find? (·.1 == eid) = none := by
    cases hf : st.find? (·.1 == eid) <;> simp_all
  apply List.filter_eq_self.mpr
  intro p hp
  have := List.find?_eq_none.mp hn p hp
  simpa using this

/-- A written-then-removed entity is absent. -/
theorem get?_remove_set (st : States) (s : EntityState) :
    ((st.set s).remove s.entityId).get? s.entityId = none := get?_remove_same _ _

/-! ## Attributes -/

/-- `hasAttr` is true exactly when `attr?` finds a value. -/
theorem hasAttr_iff (s : EntityState) (k : String) :
    s.hasAttr k = true ↔ ∃ v, s.attr? k = some v := by
  unfold EntityState.hasAttr
  cases s.attr? k <;> simp

/-- An entity whose attributes are not a JSON object has no attributes. -/
theorem attr?_non_object (s : EntityState) (k : String)
    (h : ∀ o, s.attributes ≠ .obj o) : s.attr? k = none := by
  unfold EntityState.attr?
  cases hj : s.attributes with
  | obj o => exact absurd hj (h o)
  | _ => rfl

/-! ## The clock -/

theorem msPerDay_pos : (0 : Int) < msPerDay := by decide

/-- The time of day is the local time modulo one day. -/
theorem timeOfDay_eq (t : Instant) : (t.timeOfDay : Int) = t.localMillis % msPerDay := by
  unfold Instant.timeOfDay
  exact Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))

/-- The time of day is always within one day (also before 1970 and for
negative offsets: `%` is Python's floor modulo). -/
theorem timeOfDay_lt (t : Instant) : t.timeOfDay < 86400000 := by
  have h := timeOfDay_eq t
  have h2 : t.localMillis % msPerDay < msPerDay := Int.emod_lt_of_pos _ msPerDay_pos
  have : (t.timeOfDay : Int) < 86400000 := by rw [h]; exact h2
  omega

/-- `weekday()` is 0..6. -/
theorem weekdayIdx_lt (t : Instant) : t.weekdayIdx < 7 := by
  unfold Instant.weekdayIdx
  have h1 : 0 ≤ (t.localMillis / msPerDay + 3) % 7 := Int.emod_nonneg _ (by decide)
  have h2 : (t.localMillis / msPerDay + 3) % 7 < 7 := Int.emod_lt_of_pos _ (by decide)
  omega

/-- The weekday name is always one of `WEEKDAYS`. -/
theorem weekday_mem (t : Instant) : t.weekday ∈ WEEKDAYS := by
  unfold Instant.weekday
  have h := weekdayIdx_lt t
  generalize t.weekdayIdx = n at h
  have : n = 0 ∨ n = 1 ∨ n = 2 ∨ n = 3 ∨ n = 4 ∨ n = 5 ∨ n = 6 := by omega
  rcases this with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

/-- The weekday name is the `weekdayIdx`-th entry of `WEEKDAYS`. -/
theorem weekday_getElem (t : Instant) : WEEKDAYS[t.weekdayIdx]? = some t.weekday := by
  unfold Instant.weekday
  have h := weekdayIdx_lt t
  generalize t.weekdayIdx = n at h
  have : n = 0 ∨ n = 1 ∨ n = 2 ∨ n = 3 ∨ n = 4 ∨ n = 5 ∨ n = 6 := by omega
  rcases this with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

/-- 1970-01-01T00:00:00Z was a Thursday. -/
theorem epoch_thursday : (Instant.mk 0 0).weekday = "thu" := by decide

/-- With no offset, local time is UTC. -/
theorem localMillis_utc (u : Millis) : (Instant.mk u 0).localMillis = u := by
  simp [Instant.localMillis]

/-- The offset shifts local time by whole seconds. -/
theorem localMillis_offset (u : Millis) (off : Int) :
    (Instant.mk u off).localMillis = (Instant.mk u 0).localMillis + off * 1000 := by
  simp [Instant.localMillis]

/-- One day later it is the same time of day. -/
theorem timeOfDay_add_day (u : Millis) (off : Int) :
    (Instant.mk (u + 86400000) off).timeOfDay = (Instant.mk u off).timeOfDay := by
  have h1 := timeOfDay_eq (Instant.mk (u + 86400000) off)
  have h2 := timeOfDay_eq (Instant.mk u off)
  have : (Instant.mk (u + 86400000) off).localMillis = (Instant.mk u off).localMillis + msPerDay := by
    simp [Instant.localMillis, msPerDay]; omega
  rw [this, Int.add_emod_right] at h1
  omega

/-- One day later it is the next weekday (Sunday wraps to Monday). -/
theorem weekdayIdx_add_day (u : Millis) (off : Int) :
    (Instant.mk (u + 86400000) off).weekdayIdx = ((Instant.mk u off).weekdayIdx + 1) % 7 := by
  have hl : (Instant.mk (u + 86400000) off).localMillis = (Instant.mk u off).localMillis + msPerDay := by
    simp [Instant.localMillis, msPerDay]; omega
  unfold Instant.weekdayIdx
  rw [hl, Int.add_ediv_of_dvd_right (Int.dvd_refl _), Int.ediv_self (by decide)]
  generalize (Instant.mk u off).localMillis / msPerDay = d
  omega

/-- A week later it is the same weekday. -/
theorem weekdayIdx_add_week (u : Millis) (off : Int) :
    (Instant.mk (u + 7 * 86400000) off).weekdayIdx = (Instant.mk u off).weekdayIdx := by
  have hl : (Instant.mk (u + 7 * 86400000) off).localMillis
      = (Instant.mk u off).localMillis + 7 * msPerDay := by
    simp [Instant.localMillis, msPerDay]; omega
  unfold Instant.weekdayIdx
  rw [hl, Int.add_mul_ediv_right _ _ (by decide)]
  generalize (Instant.mk u off).localMillis / msPerDay = d
  omega

/-- Local time splits into whole days and the time of day. -/
theorem localMillis_split (t : Instant) :
    t.localMillis = msPerDay * (t.localMillis / msPerDay) + t.timeOfDay := by
  rw [timeOfDay_eq]; exact (Int.mul_ediv_add_emod _ _).symm

/-! ## `float(x)` on JSON values -/

/-- `float(True)` is 1.0 and `float(False)` is 0.0. -/
theorem pyFloat?_bool (b : Bool) :
    pyFloat? (.bool b) = some (if b then 1.0 else 0.0) := rfl

/-- `float(None)`, `float([...])` and `float({...})` raise `TypeError`. -/
theorem pyFloat?_non_scalar (j : Lean.Json)
    (h : j = .null ∨ (∃ a, j = .arr a) ∨ ∃ o, j = .obj o) : pyFloat? j = none := by
  rcases h with rfl | ⟨a, rfl⟩ | ⟨o, rfl⟩ <;> rfl

/-- A JSON number always converts. -/
theorem pyFloat?_num (n : Lean.JsonNumber) : (pyFloat? (.num n)).isSome = true := rfl

end HALean.TypesSpec
