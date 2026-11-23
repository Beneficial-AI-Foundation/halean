/-
  Properties of the probatio validators (`HALean/Core/Probatio.lean`).
-/
import HALean.Core.Schema

namespace HALean.Core
open HALean.Template

/-- `In` accepts exactly the members of its container (Python `==`, so `True`
is a member of `[1]`), and returns the value unchanged. -/
theorem checkIn_ok_iff (c : List Value) (v w : Value) :
    checkIn c v = .ok w ↔ (c.any (pyEq v ·) = true ∧ w = v) := by
  unfold checkIn
  by_cases h : c.any (pyEq v ·) = true
  · simp only [h, ite_true, true_and, pure, Except.pure, Except.ok.injEq]
    exact eq_comm
  · simp [h, throw, throwThe, MonadExceptOf.throw]

/-- `NotIn` accepts exactly the values that are not members. -/
theorem checkNotIn_ok_iff (c : List Value) (v w : Value) :
    checkNotIn c v = .ok w ↔ (c.any (pyEq v ·) = false ∧ w = v) := by
  unfold checkNotIn
  by_cases h : c.any (pyEq v ·) = true
  · simp [h, throw, throwThe, MonadExceptOf.throw]
  · have h' : c.any (pyEq v ·) = false := by simpa using h
    simp only [h', Bool.not_false, ite_true, true_and, pure, Except.pure, Except.ok.injEq]
    exact eq_comm

/-- `Range` accepts only numbers within both bounds, and returns them
unchanged: it never accepts a number below an inclusive minimum (or not above
an exclusive one), nor one above an inclusive maximum (or not below an
exclusive one). -/
theorem checkRange_ok (mn mx : Option Value) (minIncl maxIncl : Bool) (v w : Value)
    (hb : mn.isSome ∨ mx.isSome) (h : checkRange mn mx minIncl maxIncl v = .ok w) :
    w = v ∧ ∃ x, v.num? = some x ∧ rangeOk mn mx minIncl maxIncl x = true := by
  unfold checkRange at h
  have hnone : (mn.isNone && mx.isNone) = false := by
    cases mn <;> cases mx <;> simp_all
  simp only [hnone, Bool.false_eq_true, ite_false] at h
  split at h
  · simp [throw, throwThe, MonadExceptOf.throw] at h
  · rename_i x hx
    split at h
    · rename_i hok
      simp only [pure, Except.pure, Except.ok.injEq] at h
      exact ⟨h.symm, x, hx, hok⟩
    · simp [throw, throwThe, MonadExceptOf.throw] at h

/-- With a numeric minimum `a`, an accepted value is at least `a` (above it
when the minimum is exclusive). -/
theorem checkRange_min (m : Value) (mx : Option Value) (minIncl maxIncl : Bool) (v w : Value)
    (a : Num) (hm : m.num? = some a) (h : checkRange (some m) mx minIncl maxIncl v = .ok w) :
    ∃ x, v.num? = some x ∧ minOk minIncl x a = true := by
  obtain ⟨-, x, hx, hok⟩ := checkRange_ok _ _ _ _ _ _ (Or.inl rfl) h
  refine ⟨x, hx, ?_⟩
  simp only [rangeOk, Option.all_some, hm, Bool.and_eq_true] at hok
  exact hok.1

/-- With a numeric maximum `b`, an accepted value is at most `b` (below it
when the maximum is exclusive). -/
theorem checkRange_max (mn : Option Value) (m : Value) (minIncl maxIncl : Bool) (v w : Value)
    (b : Num) (hm : m.num? = some b) (h : checkRange mn (some m) minIncl maxIncl v = .ok w) :
    ∃ x, v.num? = some x ∧ maxOk maxIncl x b = true := by
  obtain ⟨-, x, hx, hok⟩ := checkRange_ok _ _ _ _ _ _ (Or.inr rfl) h
  refine ⟨x, hx, ?_⟩
  simp only [rangeOk, Option.all_some, hm, Bool.and_eq_true] at hok
  exact hok.2

/-- A value that is not a number (a string, `None`, a list, a dict) is never
in range. -/
theorem checkRange_not_number (mn mx : Option Value) (minIncl maxIncl : Bool) (v : Value)
    (hb : mn.isSome ∨ mx.isSome) (hv : v.num? = none) :
    checkRange mn mx minIncl maxIncl v = .error (inv "invalid value or type") := by
  unfold checkRange
  have hnone : (mn.isNone && mx.isNone) = false := by
    cases mn <;> cases mx <;> simp_all
  simp [hnone, hv, throw, throwThe, MonadExceptOf.throw]

/-- `EnsureList` always produces a list; a list is kept as it is. -/
theorem ensureList_is_list (v : Value) : ∃ xs, ensureList v = .list xs := by
  cases v <;> simp [ensureList]

theorem ensureList_list (xs : List Value) : ensureList (.list xs) = .list xs := rfl

/-- `Coerce(int)` only ever produces an `int`. -/
theorem checkCoerce_int (v w : Value) (h : checkCoerce .int v = .ok w) : ∃ i, w = .int i := by
  unfold checkCoerce at h
  simp only [bind, Except.bind] at h
  cases hp : pyInt? v with
  | error e => simp [hp] at h
  | ok r =>
    cases r with
    | none => simp [hp, throw, throwThe, MonadExceptOf.throw] at h
    | some i => simp [hp, pure, Except.pure] at h; exact ⟨i, h.symm⟩

/-- `Port` only ever produces an `int` from 1 to 65535. -/
theorem checkPort_range (v w : Value) (h : checkPort v = .ok w) :
    ∃ i, w = .int i ∧ 1 ≤ i ∧ i ≤ 65535 := by
  unfold checkPort at h
  split at h
  · simp [throw, throwThe, MonadExceptOf.throw] at h
  · split at h
    · simp [throw, throwThe, MonadExceptOf.throw] at h
    · split at h
      · split at h
        · simp [pure, Except.pure] at h; rename_i hi; exact ⟨_, h.symm, by simp_all⟩
        · simp [throw, throwThe, MonadExceptOf.throw] at h
      · simp [throw, throwThe, MonadExceptOf.throw] at h
  · simp only [bind, Except.bind] at h
    split at h
    · simp at h
    · split at h
      · split at h
        · simp [pure, Except.pure] at h; rename_i hi; exact ⟨_, h.symm, by simp_all⟩
        · simp [throw, throwThe, MonadExceptOf.throw] at h
      · simp [throw, throwThe, MonadExceptOf.throw] at h

end HALean.Core
