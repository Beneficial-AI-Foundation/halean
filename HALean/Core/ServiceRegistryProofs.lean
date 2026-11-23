/-
  Properties of the service registry (`HALean/Core/ServiceRegistry.lean`).

  * `has_after_register`: registering is case-insensitive: after
    `async_register("Light", "Turn_On", ...)`, `has_service` is true for every
    spelling with the same lowercase form.
  * `has_after_remove`, `call_after_remove_not_found`: after `async_remove`,
    `has_service` is false and `async_call` raises `ServiceNotFound` (with the
    lowercased names), whatever the case of the names.
  * `call_none_return_response_errors`: `return_response=True` on a service
    registered with `SupportsResponse.NONE` always raises
    `ServiceValidationError`, before any event is fired or the handler runs.
  * `call_only_needs_return_response`: a `SupportsResponse.ONLY` service
    called without `return_response` always raises `ServiceValidationError`.
  * `call_return_response_needs_blocking`: `return_response=True` with
    `blocking=False` always raises `ServiceValidationError`.

  The registry invariant `Registry.WF` (every domain and service key is
  lowercase) holds for the empty registry and is preserved by `register` and
  `remove`, so it holds for every registry the model can reach.
-/
import HALean.Core.ServiceRegistry

namespace HALean.Core

/-! ## Lowercasing is idempotent -/

theorem Char.toLower_idem (c : Char) : c.toLower.toLower = c.toLower := by
  unfold Char.toLower
  split
  · rename_i h
    split
    · rename_i h2
      exfalso
      have h1 := h.1
      have h3 := h.2
      have h4 := h2.1
      have h5 := h2.2
      simp only [UInt32.le_iff_toNat_le, UInt32.toNat_add] at h1 h3 h4 h5
      simp at h1 h3 h4 h5
      omega
    · rfl
  · rfl

theorem String.toLower_idem (s : String) : s.toLower.toLower = s.toLower := by
  unfold String.toLower
  rw [String.map_map]
  congr 1
  funext c
  exact Char.toLower_idem c

/-! ## Association lists -/

theorem find?_none_of_not_any {α} {xs : List (String × α)} {k : String}
    (h : xs.any (·.1 == k) = false) : xs.find? (·.1 == k) = none := by
  rw [List.find?_eq_none]
  intro p hp
  have := List.any_eq_false.mp h p hp
  simpa using this

theorem assocGet?_some_mem {α} {xs : List (String × α)} {k : String} {v : α}
    (h : assocGet? xs k = some v) : (k, v) ∈ xs := by
  unfold assocGet? at h
  cases hf : xs.find? (·.1 == k) with
  | none => simp [hf] at h
  | some p =>
    simp [hf] at h
    have hm := List.mem_of_find?_eq_some hf
    have hk := List.find?_some hf
    simp at hk
    subst hk; subst h
    exact hm


theorem assocGet?_none_of_not_any {α} {xs : List (String × α)} {k : String}
    (h : xs.any (·.1 == k) = false) : assocGet? xs k = none := by
  unfold assocGet?
  rw [find?_none_of_not_any h]
  rfl

theorem any_of_assocGet?_some {α} {xs : List (String × α)} {k : String} {v : α}
    (h : assocGet? xs k = some v) : xs.any (·.1 == k) = true := by
  have := assocGet?_some_mem h
  exact List.any_eq_true.mpr ⟨(k, v), this, by simp⟩

theorem assocGet?_map_set {α} (xs : List (String × α)) (k : String) (v : α) :
    assocGet? (xs.map fun p => if p.1 == k then (k, v) else p) k =
      if xs.any (·.1 == k) then some v else none := by
  induction xs with
  | nil => rfl
  | cons p ps ih =>
    unfold assocGet? at ih ⊢
    cases hp : (p.1 == k)
    · have hf : (if (p.1 == k) = true then (k, v) else p) = p := by simp [hp]
      rw [List.map_cons, List.find?_cons, hf, hp, List.any_cons, hp, Bool.false_or]
      exact ih
    · have hf : (if (p.1 == k) = true then (k, v) else p) = (k, v) := by simp [hp]
      rw [List.map_cons, List.find?_cons, hf, List.any_cons, hp, Bool.true_or]
      simp

theorem assocGet?_assocSet {α} (xs : List (String × α)) (k : String) (v : α) :
    assocGet? (assocSet xs k v) k = some v := by
  unfold assocSet
  split
  · rename_i h
    rw [assocGet?_map_set]; simp [h]
  · rename_i h
    have h' : xs.any (·.1 == k) = false := by rwa [Bool.not_eq_true] at h
    unfold assocGet?
    rw [List.find?_append, find?_none_of_not_any h']
    simp

theorem mem_assocSet {α} {xs : List (String × α)} {k : String} {v : α} {p : String × α}
    (h : p ∈ assocSet xs k v) : p ∈ xs ∨ p = (k, v) := by
  unfold assocSet at h
  split at h
  · rcases List.mem_map.mp h with ⟨q, hq, rfl⟩
    by_cases hk : q.1 == k
    · right; simp [hk]
    · left; simp [hk]; exact hq
  · rcases List.mem_append.mp h with h | h
    · exact Or.inl h
    · right; simpa using h

theorem any_assocErase {α} (xs : List (String × α)) (k : String) :
    (assocErase xs k).any (·.1 == k) = false := by
  unfold assocErase
  rw [List.any_eq_false]
  intro p hp
  have := (List.mem_filter.mp hp).2
  simpa using this

theorem mem_assocErase {α} {xs : List (String × α)} {k : String} {p : String × α}
    (h : p ∈ assocErase xs k) : p ∈ xs :=
  (List.mem_filter.mp h).1

/-! ## The invariant -/

/-- Every domain and service key is lowercase (`_async_register` lowercases). -/
def Registry.WF (r : Registry) : Prop :=
  ∀ p ∈ r, p.1.toLower = p.1 ∧ ∀ q ∈ p.2, q.1.toLower = q.1

theorem wf_empty : Registry.WF [] := by
  intro p hp; cases hp

theorem wf_register (r : Registry) (d s : String) (svc : Service) (now : Millis)
    (hwf : r.WF) : (r.register d s svc now).1.WF := by
  unfold Registry.register
  intro p hp
  dsimp only at hp
  split at hp
  · rename_i svcs hsv
    rcases mem_assocSet hp with hp | hp
    · exact hwf p hp
    · subst hp
      refine ⟨String.toLower_idem d, ?_⟩
      intro q hq
      rcases mem_assocSet hq with hq | hq
      · exact (hwf _ (assocGet?_some_mem hsv)).2 q hq
      · subst hq; exact String.toLower_idem s
  · rcases mem_assocSet hp with hp | hp
    · exact hwf p hp
    · subst hp
      refine ⟨String.toLower_idem d, ?_⟩
      intro q hq
      simp at hq; subst hq; exact String.toLower_idem s

theorem wf_remove (r : Registry) (d s : String) (now : Millis)
    (hwf : r.WF) : (r.remove d s now).1.WF := by
  unfold Registry.remove
  intro p hp
  dsimp only at hp
  split at hp
  · rename_i svcs hsv
    split at hp
    · simp only at hp
      split at hp
      · exact hwf p (mem_assocErase hp)
      · rcases mem_assocSet hp with hp | hp
        · exact hwf p hp
        · subst hp
          have hk := hwf _ (assocGet?_some_mem hsv)
          exact ⟨hk.1, fun q hq => hk.2 q (mem_assocErase hq)⟩
    · exact hwf p hp
  · exact hwf p hp

/-! ## has_service -/

/-- Registering is case-insensitive. -/
theorem has_after_register (r : Registry) (d s d' s' : String) (svc : Service) (now : Millis)
    (hd : d'.toLower = d.toLower) (hs : s'.toLower = s.toLower) :
    (r.register d s svc now).1.hasService d' s' = true := by
  unfold Registry.register Registry.hasService
  dsimp only
  rw [hd, hs]
  cases hr : assocGet? r d.toLower with
  | some svcs =>
    simp only [assocGet?_assocSet]
    exact any_of_assocGet?_some (assocGet?_assocSet _ _ _)
  | none => simp [assocGet?_assocSet]

theorem has_after_remove (r : Registry) (d s d' s' : String) (now : Millis)
    (hd : d'.toLower = d.toLower) (hs : s'.toLower = s.toLower) :
    (r.remove d s now).1.hasService d' s' = false := by
  unfold Registry.remove Registry.hasService
  dsimp only
  rw [hd, hs]
  cases hr : assocGet? r d.toLower with
  | none => simp [hr]
  | some svcs =>
    by_cases hany : svcs.any (·.1 == s.toLower) = true
    · by_cases he : (assocErase svcs s.toLower).isEmpty = true
      · simp [hany, he, assocGet?_none_of_not_any (any_assocErase r d.toLower)]
      · simp [hany, he, assocGet?_assocSet, any_assocErase]
    · simp [hr, hany]

/-! ## async_call -/

theorem hasService_of_lookup (r : Registry) (d s : String) (h : Service)
    (hl : r.lookup d.toLower s.toLower = some h) : r.hasService d s = true := by
  unfold Registry.lookup at hl
  unfold Registry.hasService
  cases hd : assocGet? r d.toLower with
  | none => simp [hd] at hl
  | some svcs =>
    simp [hd] at hl
    simp only [hd]
    exact any_of_assocGet?_some hl

/-- Under the invariant, a lookup with the names as given only succeeds when
they are lowercase already. -/
theorem lookup_lower (r : Registry) (hwf : r.WF) (d s : String) (h : Service)
    (hl : r.lookup d s = some h) : d.toLower = d ∧ s.toLower = s ∧
      r.lookup d.toLower s.toLower = some h := by
  unfold Registry.lookup at hl
  cases hd : assocGet? r d with
  | none => simp [hd] at hl
  | some svcs =>
    simp [hd] at hl
    have hk := hwf _ (assocGet?_some_mem hd)
    have hs := hk.2 _ (assocGet?_some_mem hl)
    simp only at hk hs
    refine ⟨hk.1, hs, ?_⟩
    rw [hk.1, hs]
    unfold Registry.lookup
    simp [hd, hl]

/-- Under the invariant, `async_call` finds exactly the service that
`has_service` sees, under its lowercased names. -/
theorem find_eq (r : Registry) (hwf : r.WF) (d s : String) :
    r.find d s = (r.lookup d.toLower s.toLower).map fun h => (d.toLower, s.toLower, h) := by
  unfold Registry.find
  split
  · rename_i h hl
    obtain ⟨hd, hs, hl'⟩ := lookup_lower r hwf d s h hl
    rw [hl']; simp [hd, hs]
  · rfl

theorem find_none (r : Registry) (hwf : r.WF) (d s : String) (hno : r.hasService d s = false) :
    r.find d s = none := by
  rw [find_eq r hwf]
  cases hl : r.lookup d.toLower s.toLower with
  | none => rfl
  | some h =>
    have := hasService_of_lookup r d s h hl
    rw [hno] at this; cases this

/-- A call to a service `has_service` doesn't know raises `ServiceNotFound`,
fires nothing and logs nothing. -/
theorem call_not_found (r : Registry) (hwf : r.WF) (a : CallArgs) (now : Millis)
    (hno : r.hasService a.domain a.service = false) :
    r.asyncCall a now = { result := .error (serviceNotFound a.domain.toLower a.service.toLower) } := by
  simp [Registry.asyncCall, Registry.prepareCall, find_none r hwf _ _ hno]

theorem call_after_remove_not_found (r : Registry) (hwf : r.WF) (d s : String) (now now' : Millis)
    (a : CallArgs) (hd : a.domain.toLower = d.toLower) (hs : a.service.toLower = s.toLower) :
    (r.remove d s now).1.asyncCall a now' =
      { result := .error (serviceNotFound d.toLower s.toLower) } := by
  rw [call_not_found _ (wf_remove r d s now hwf) a now' (has_after_remove r d s _ _ now hd hs), hd, hs]

theorem find_some (r : Registry) (hwf : r.WF) (a : CallArgs) (svc : Service)
    (hl : r.lookup a.domain.toLower a.service.toLower = some svc) :
    r.find a.domain a.service = some (a.domain.toLower, a.service.toLower, svc) := by
  rw [find_eq r hwf, hl]; rfl

theorem call_return_response_needs_blocking (r : Registry) (hwf : r.WF) (a : CallArgs)
    (now : Millis) (svc : Service)
    (hl : r.lookup a.domain.toLower a.service.toLower = some svc)
    (hrr : a.returnResponse = true) (hb : a.blocking = false) :
    r.asyncCall a now = { result := .error (serviceValidationError "service_should_be_blocking"
        [("return_response", "return_response=True"), ("non_blocking_argument", "blocking=False")]) } := by
  simp [Registry.asyncCall, Registry.prepareCall, responseCheck, find_some r hwf a svc hl, hrr, hb]

theorem call_none_return_response_errors (r : Registry) (hwf : r.WF) (a : CallArgs)
    (now : Millis) (svc : Service)
    (hl : r.lookup a.domain.toLower a.service.toLower = some svc)
    (hnone : svc.supportsResponse = .none) (hrr : a.returnResponse = true) :
    ∃ key ph, r.asyncCall a now = { result := .error (serviceValidationError key ph) } := by
  cases hb : a.blocking
  · exact ⟨_, _, call_return_response_needs_blocking r hwf a now svc hl hrr hb⟩
  · refine ⟨"service_does_not_support_response", [("return_response", "return_response=True")], ?_⟩
    simp [Registry.asyncCall, Registry.prepareCall, responseCheck, find_some r hwf a svc hl, hrr, hb, hnone]

theorem call_only_needs_return_response (r : Registry) (hwf : r.WF) (a : CallArgs)
    (now : Millis) (svc : Service)
    (hl : r.lookup a.domain.toLower a.service.toLower = some svc)
    (honly : svc.supportsResponse = .only) (hrr : a.returnResponse = false) :
    r.asyncCall a now = { result := .error (serviceValidationError "service_lacks_response_request"
        [("return_response", "return_response=True")]) } := by
  simp [Registry.asyncCall, Registry.prepareCall, responseCheck, find_some r hwf a svc hl, hrr, honly]

end HALean.Core
