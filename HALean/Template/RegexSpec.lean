/-
  `HALean/Template/Regex.lean`: the captured-group store of the matcher.

  The matcher itself (`Rx.run`) is a `partial def`, which Lean does not let
  proofs unfold, so nothing can be stated about `matchPrefix` or about what
  the pattern builders (`ch`, `oneOf`, `digit`, `range`, `lit`, `opt`, `plus`,
  `nTimes`) match. What is proved here is `Caps.get?`, Python's
  `match.group(name)`: the most recent capture of a name wins.
-/
import HALean.Template.Regex

namespace HALean.Template.Rx

/-- No group took part: `None`. -/
theorem Caps.get?_nil (n : String) : Caps.get? [] n = none := rfl

/-- The most recently captured value of a group is the one returned (a group
inside a repetition is overwritten by its last iteration, as in Python). -/
theorem Caps.get?_cons_self (c : Caps) (n v : String) : Caps.get? ((n, v) :: c) n = some v := by
  simp [Caps.get?]

/-- Captures of other groups do not affect a group's value. -/
theorem Caps.get?_cons_of_ne (c : Caps) (m n v : String) (h : m ≠ n) :
    Caps.get? ((m, v) :: c) n = Caps.get? c n := by
  simp [Caps.get?, h]

/-- A returned value was captured under that name. -/
theorem Caps.mem_of_get?_eq_some (c : Caps) (n v : String) (h : Caps.get? c n = some v) : (n, v) ∈ c := by
  simp only [Caps.get?, Option.map_eq_some_iff] at h
  obtain ⟨⟨m, w⟩, hf, rfl⟩ := h
  have hm := List.mem_of_find?_eq_some hf
  have hp := List.find?_some hf
  simp only [beq_iff_eq] at hp
  subst hp; exact hm

/-- A group has no value exactly when nothing was captured under its name. -/
theorem Caps.get?_eq_none_iff (c : Caps) (n : String) : Caps.get? c n = none ↔ ∀ p ∈ c, p.1 ≠ n := by
  simp [Caps.get?]

/-- A group that was captured has a value. -/
theorem Caps.get?_isSome_of_mem (c : Caps) (n v : String) (h : (n, v) ∈ c) : (Caps.get? c n).isSome = true := by
  cases hg : Caps.get? c n with
  | some w => rfl
  | none => exact absurd rfl ((Caps.get?_eq_none_iff c n).1 hg (n, v) h)

/-- What `matchPrefix` hands on is the group list `Caps.get?` reads: appending
older captures never changes a value that is already there. -/
theorem Caps.get?_append_of_isSome (c d : Caps) (n : String) (h : (Caps.get? c n).isSome = true) :
    Caps.get? (c ++ d) n = Caps.get? c n := by
  simp only [Caps.get?, Option.isSome_map] at h ⊢
  rw [List.find?_append]
  cases hf : List.find? (fun x => x.1 == n) c with
  | none => rw [hf] at h; cases h
  | some p => rfl

end HALean.Template.Rx
