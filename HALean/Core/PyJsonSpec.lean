/-
  Specifications for the pure helpers of `HALean/Core/PyJson.lean`:
  `dictSet` is Python's `d[k] = v` on an insertion-ordered dict, and
  `dictOf` / `Value.strItems?` / `Value.get?` convert between string-keyed
  association lists and `Value.dict` without loss.

  The parser itself (`parsePyJson`) is built from `partial def`s and is not
  covered here.
-/
import HALean.Core.PyJson

namespace HALean.Core.PyJsonSpec
open HALean.Template HALean.Core

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

/-! ## `dictSet` -/

theorem any_key_iff (kvs : List (String × Value)) (k : String) :
    (kvs.any (·.1 == k) = true) ↔ k ∈ kvs.map (·.1) := by
  constructor
  · intro h
    obtain ⟨p, hp, hk⟩ := List.any_eq_true.mp h
    exact List.mem_map.mpr ⟨p, hp, by simpa using hk⟩
  · intro h
    obtain ⟨p, hp, hk⟩ := List.mem_map.mp h
    exact List.any_eq_true.mpr ⟨p, hp, by simpa using hk⟩

theorem lookup_replace (kvs : List (String × Value)) (k x : String) (v : Value) :
    (kvs.map fun p => if p.1 == k then (k, v) else p).lookup x =
      if x = k then (if k ∈ kvs.map (·.1) then some v else none) else kvs.lookup x := by
  induction kvs with
  | nil => by_cases hx : x = k <;> simp [hx]
  | cons p ps ih =>
    obtain ⟨pk, pv⟩ := p
    rw [List.map_cons]
    by_cases hp : (pk == k) = true
    · have hpk : pk = k := by simpa using hp
      subst hpk
      rw [ifP hp, List.lookup_cons, List.lookup_cons]
      by_cases hx : x = pk
      · subst hx; simp
      · have hb : (x == pk) = false := by simpa using hx
        simp only [hb, ih, ifN hx]
    · have hpk : ¬ pk = k := by simpa using hp
      rw [ifN hp, List.lookup_cons, List.lookup_cons, ih]
      by_cases hx : x = k
      · subst hx
        have hb : (x == pk) = false := by simpa using fun h => hpk h.symm
        have hm : (x ∈ List.map (·.1) ((pk, pv) :: ps)) ↔ x ∈ List.map (·.1) ps := by
          rw [List.map_cons, List.mem_cons]
          exact ⟨fun h => h.elim (fun e => absurd e.symm hpk) id, Or.inr⟩
        simp only [hb, ↓reduceIte]
        by_cases hmem : x ∈ List.map (·.1) ps
        · rw [ifP hmem, ifP (hm.mpr hmem)]
        · rw [ifN hmem, ifN (fun h => hmem (hm.mp h))]
      · simp only [ifN hx]

/-- `d[k] = v; d[k]` is `v`. -/
theorem lookup_dictSet_same (kvs : List (String × Value)) (k : String) (v : Value) :
    (dictSet kvs k v).lookup k = some v := by
  unfold dictSet
  by_cases h : kvs.any (·.1 == k) = true
  · rw [ifP h, lookup_replace, ifP rfl, ifP ((any_key_iff _ _).mp h)]
  · rw [ifN h]
    have hn : kvs.lookup k = none := by
      rw [List.lookup_eq_none_iff]
      intro p hp
      cases hq : k == p.1
      · simp [bne, hq]
      · have : (p.1 == k) = true := by
          have : k = p.1 := by simpa using hq
          simp [this]
        exact absurd (List.any_eq_true.mpr ⟨p, hp, this⟩) h
    simp [List.lookup_append, hn]

/-- Setting one key leaves every other key's value unchanged. -/
theorem lookup_dictSet_other (kvs : List (String × Value)) (k x : String) (v : Value)
    (hne : x ≠ k) : (dictSet kvs k v).lookup x = kvs.lookup x := by
  unfold dictSet
  split
  · rw [lookup_replace, ifN hne]
  · have hb : (x == k) = false := by simpa using hne
    cases hl : kvs.lookup x <;> simp [List.lookup_append, hl, List.lookup, hb]

/-- The keys after `d[k] = v`: unchanged, in the same order, when `k` was
there (it keeps its first position), otherwise `k` is appended. -/
theorem keys_dictSet (kvs : List (String × Value)) (k : String) (v : Value) :
    (dictSet kvs k v).map (·.1) =
      if k ∈ kvs.map (·.1) then kvs.map (·.1) else kvs.map (·.1) ++ [k] := by
  unfold dictSet
  have hany := any_key_iff kvs k
  by_cases h : kvs.any (·.1 == k) = true
  · rw [ifP h, ifP (hany.mp h), List.map_map]
    apply List.map_congr_left
    intro p _
    by_cases hp : p.1 = k
    · simp [hp]
    · simp [hp]
  · rw [ifN h, ifN (fun hm => h (hany.mpr hm))]; simp

/-- The dict grows by at most the one new key. -/
theorem length_dictSet (kvs : List (String × Value)) (k : String) (v : Value) :
    (dictSet kvs k v).length = if k ∈ kvs.map (·.1) then kvs.length else kvs.length + 1 := by
  have := congrArg List.length (keys_dictSet kvs k v)
  split at this <;> simp_all

/-- The key is always present afterwards. -/
theorem mem_keys_dictSet (kvs : List (String × Value)) (k : String) (v : Value) :
    k ∈ (dictSet kvs k v).map (·.1) := by
  rw [keys_dictSet]; split <;> simp_all

/-- A dict without duplicate keys stays without duplicate keys (so building
one by `dictSet` from `[]`, as the parser does, never yields a duplicate). -/
theorem nodup_keys_dictSet (kvs : List (String × Value)) (k : String) (v : Value)
    (h : (kvs.map (·.1)).Nodup) : ((dictSet kvs k v).map (·.1)).Nodup := by
  rw [keys_dictSet]
  split
  · exact h
  · rename_i hk
    rw [List.nodup_append]
    refine ⟨h, by simp, ?_⟩
    intro a ha b hb
    have : b = k := by simpa using hb
    subst this
    intro hab; subst hab; exact hk ha

/-- Assigning the same key twice keeps only the last value. -/
theorem lookup_dictSet_twice (kvs : List (String × Value)) (k x : String) (v w : Value) :
    (dictSet (dictSet kvs k v) k w).lookup x = (dictSet kvs k w).lookup x := by
  by_cases hx : x = k
  · subst hx; rw [lookup_dictSet_same, lookup_dictSet_same]
  · rw [lookup_dictSet_other _ _ _ _ hx, lookup_dictSet_other _ _ _ _ hx,
      lookup_dictSet_other _ _ _ _ hx]

/-- Assigning the same key twice does not move it or add a key. -/
theorem keys_dictSet_twice (kvs : List (String × Value)) (k : String) (v w : Value) :
    (dictSet (dictSet kvs k v) k w).map (·.1) = (dictSet kvs k v).map (·.1) := by
  rw [keys_dictSet (dictSet kvs k v), ifP (mem_keys_dictSet kvs k v)]

/-! ## `dictOf`, `strItems?`, `get?` -/

theorem mapM_strKeys (kvs : List (String × Value)) :
    (kvs.map fun (k, v) => (Value.str k, v)).mapM
      (fun ((k, v) : Value × Value) => match k with
        | .str s => some (s, v)
        | _ => none) = some kvs := by
  induction kvs with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨k, v⟩ := p
    simp only [List.map_cons, List.mapM_cons, ih]
    rfl

theorem mapM_some_length {α β} {f : α → Option β} :
    ∀ (l : List α) (r : List β), l.mapM f = some r → l.length = r.length := by
  intro l
  induction l with
  | nil => intro r h; simp at h; subst h; rfl
  | cons a as ih =>
    intro r h
    rw [List.mapM_cons] at h
    cases hf : f a with
    | none => simp [hf] at h
    | some b =>
      cases hm : as.mapM f with
      | none => simp [hf, hm] at h
      | some bs =>
        simp [hf, hm] at h
        subst h
        simp [ih _ hm]

/-- `strItems?` undoes `dictOf`: a dict built from string keys reads back as
the same items, in the same order. -/
theorem strItems?_dictOf (kvs : List (String × Value)) : (dictOf kvs).strItems? = some kvs := by
  unfold dictOf Value.strItems?
  exact mapM_strKeys kvs

/-- Reading a key of `dictOf kvs` is the association-list lookup. -/
theorem get?_dictOf (kvs : List (String × Value)) (k : String) :
    (dictOf kvs).get? k = kvs.lookup k := by
  unfold Value.get?
  rw [strItems?_dictOf]; rfl

/-- After `d[k] = v`, `d.get(k)` is `v`. -/
theorem get?_dictOf_dictSet (kvs : List (String × Value)) (k : String) (v : Value) :
    (dictOf (dictSet kvs k v)).get? k = some v := by
  rw [get?_dictOf, lookup_dictSet_same]

/-- Only a dict has string items. -/
theorem strItems?_some_dict (v : Value) (items : List (String × Value))
    (h : v.strItems? = some items) : ∃ kvs, v = .dict kvs ∧ kvs.length = items.length := by
  cases v with
  | dict kvs =>
    refine ⟨kvs, rfl, ?_⟩
    unfold Value.strItems? at h
    exact mapM_some_length _ _ h
  | _ => simp [Value.strItems?] at h

/-- A value that is not a dict has no keys. -/
theorem get?_non_dict (v : Value) (k : String) (h : ∀ kvs, v ≠ .dict kvs) : v.get? k = none := by
  unfold Value.get?
  cases hs : v.strItems? with
  | none => rfl
  | some items =>
    obtain ⟨kvs, hv, _⟩ := strItems?_some_dict v items hs
    exact absurd hv (h kvs)

/-- A dict with a non-string key has no string items (the service drivers
reject it). -/
theorem strItems?_non_str_key (pre post : List (Value × Value)) (k v : Value)
    (hk : ∀ s, k ≠ .str s) : (Value.dict (pre ++ (k, v) :: post)).strItems? = none := by
  unfold Value.strItems?
  induction pre with
  | nil =>
    cases k <;> first | exact absurd rfl (hk _) | simp [List.mapM_cons]
  | cons p ps ih =>
    obtain ⟨pk, pv⟩ := p
    cases pk <;> simp [List.mapM_cons, ih]

end HALean.Core.PyJsonSpec
