/-
  Specifications for `HALean/Automation/TimePeriod.lean`
  (`cv.time_period`, `cv.positive_time_period` and CPython's `timedelta(...)`).
-/
import HALean.Automation.TimePeriod

namespace HALean.Automation
open HALean.Template

/-- `timedelta.min <= td <= timedelta.max`, on the day count. -/
def InTimedeltaRange (us : Int) : Prop :=
  (Int.fdiv us 86400000000).natAbs ≤ MAX_DELTA_DAYS

/-! ### `modf`, `accum` -/

/-- C `modf`: the two parts add up to `x` (fractional part is `x - ip`) and
the integral part is `floor` or `ceil` of `x`. -/
theorem modf_spec (x : Float) :
    (modf x).1 = x - (modf x).2 ∧ ((modf x).2 = x.floor ∨ (modf x).2 = x.ceil) := by
  unfold modf
  by_cases h : x ≥ 0 <;> simp [h]

/-- An `int` argument is accumulated exactly and never touches the leftover. -/
theorem accum_int (sofar : Int) (left : Float) (factor : Nat) (i : Int) :
    accum sofar left factor (.int i) = .ok (sofar + i * factor, left) := rfl

/-- `timedelta(seconds=float("nan"))` is a `ValueError`. -/
theorem accum_nan (sofar : Int) (left : Float) (factor : Nat) (x : Float) (h : x.isNaN = true) :
    accum sofar left factor (.float x) =
      .error "ValueError: cannot convert float NaN to integer" := by
  simp [accum, h]; rfl

/-- `timedelta(seconds=float("inf"))` is an `OverflowError`. -/
theorem accum_inf (sofar : Int) (left : Float) (factor : Nat) (x : Float)
    (hn : x.isNaN = false) (h : x.isInf = true) :
    accum sofar left factor (.float x) =
      .error "OverflowError: cannot convert float infinity to integer" := by
  simp [accum, h, hn]; rfl

/-- What was accumulated so far is only ever added to: shifting the running
total shifts the result by the same amount, and the leftover is unchanged. -/
theorem accum_shift (sofar k : Int) (left : Float) (factor : Nat) (a : TdArg) (r : Int) (l : Float)
    (h : accum sofar left factor a = .ok (r, l)) :
    accum (sofar + k) left factor a = .ok (r + k, l) := by
  cases a with
  | int i =>
    simp only [accum_int, Except.ok.injEq, Prod.mk.injEq] at h ⊢
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨by rw [Int.add_right_comm], rfl⟩
  | float x =>
    simp only [accum] at h ⊢
    by_cases h1 : x.isNaN = true
    · simp [h1] at h; cases h
    by_cases h2 : x.isInf = true
    · simp [h1, h2] at h; cases h
    simp only [h1, h2] at h ⊢
    revert h
    simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw]
    generalize floatToInt? (modf x).snd = o1
    generalize floatToInt? (modf (factor.toFloat * (modf x).fst)).snd = o2
    cases o1 with
    | none => simp
    | some ii =>
      by_cases h3 : ((modf x).fst == 0) = true
      · simp only [h3, Bool.false_eq_true, ite_false, ite_true, Except.ok.injEq, Prod.mk.injEq]
        rintro ⟨rfl, rfl⟩
        exact ⟨by rw [Int.add_right_comm], rfl⟩
      · cases o2 with
        | none => simp [h3]
        | some i2 =>
          simp only [h3, Bool.false_eq_true, ite_false, Except.ok.injEq, Prod.mk.injEq]
          rintro ⟨rfl, rfl⟩
          exact ⟨by omega, rfl⟩

/-! ### `timedeltaNew` -/

/-- Every `timedelta` that `timedelta(...)` returns is in range. -/
theorem timedeltaNew_range (args : List (Nat × TdArg)) (us : Int)
    (h : timedeltaNew args = .ok us) : InTimedeltaRange us := by
  unfold timedeltaNew at h
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
  revert h
  generalize forIn (m := Except String) args ((0 : Int), (0 : Float)) _ = r
  intro h
  cases r with
  | error e => simp at h
  | ok v =>
    simp only at h
    split at h
    · split at h
      · split at h
        · cases h
        · cases h; unfold InTimedeltaRange; omega
      · cases h
    · split at h
      · cases h
      · cases h; unfold InTimedeltaRange; omega

theorem timePeriodStr_range (s : String) (us : Int) (h : timePeriodStr s = some (.ok us)) :
    InTimedeltaRange us := by
  unfold timePeriodStr at h
  simp only [bind, Option.bind, Except.bind, pure, Except.pure] at h
  revert h
  generalize (if s.startsWith "-" = true then (true, s.dropS 1)
    else if s.startsWith "+" = true then (false, s.dropS 1) else (false, s)) = p
  generalize p.snd.splitOn ":" = parts
  generalize parseIntStr (parts.getD 0 "") = oh
  generalize parseIntStr (parts.getD 1 "") = om
  generalize parseFloatStr (parts.getD 2 "") = os
  intro h
  split at h
  · cases h
  cases oh with
  | none => cases h
  | some hh =>
  cases om with
  | none => cases h
  | some mm =>
  simp only at h
  split at h
  · cases os with
    | none => cases h
    | some ss =>
      simp only [Option.map, Option.some.injEq] at h
      revert h
      generalize timedeltaNew _ = r
      intro h
      cases r with
      | error e => cases h
      | ok v =>
        simp only at h
        by_cases hc : ((if p.fst = true then -v else v).fdiv 86400000000).natAbs > MAX_DELTA_DAYS
        · rw [ite_eq_left_of_eq_true _ _ (eq_true hc)] at h
          simp [throw, throwThe, MonadExceptOf.throw] at h
        · rw [ite_eq_right_of_eq_false _ _ (eq_false hc)] at h
          cases h; exact Nat.le_of_not_gt hc
  · skip
    simp only [Option.some.injEq] at h
    revert h
    generalize timedeltaNew _ = r
    intro h
    cases r with
    | error e => cases h
    | ok v =>
      simp only at h
      by_cases hc : ((if p.fst = true then -v else v).fdiv 86400000000).natAbs > MAX_DELTA_DAYS
      · rw [ite_eq_left_of_eq_true _ _ (eq_true hc)] at h
        simp [throw, throwThe, MonadExceptOf.throw] at h
      · rw [ite_eq_right_of_eq_false _ _ (eq_false hc)] at h
        cases h; exact Nat.le_of_not_gt hc

/-- A mapping's time period, when valid, is in range. -/
theorem timePeriodDict_range (v : Value) (us : Int) (h : timePeriodDict v = some (.ok us)) :
    InTimedeltaRange us := by
  unfold timePeriodDict at h
  simp only [bind, Option.bind, pure] at h
  split at h
  · split at h
    · cases h
    · split at h
      · cases h
      · exact timedeltaNew_range _ _ (Option.some.inj h)
  · cases h

/-- `cv.time_period_dict` only takes mappings, and not the empty one. -/
theorem timePeriodDict_not_dict (v : Value) (h : ∀ kvs, v ≠ .dict kvs) : timePeriodDict v = none := by
  unfold timePeriodDict
  cases v <;> first | rfl | exact absurd rfl (h _)

theorem timePeriodDict_empty : timePeriodDict (.dict []) = none := rfl

/-- A loop over an `Option` body that never breaks fails as soon as one
element makes the body fail. -/
theorem forIn_option_none {α β : Type} (f : α → β → Option (ForInStep β))
    (hd : ∀ a b b', f a b ≠ some (.done b')) :
    ∀ (l : List α) (init : β), (∃ a ∈ l, ∀ b, f a b = none) → forIn l init f = none
  | [], _, h => by obtain ⟨a, ha, _⟩ := h; cases ha
  | x :: xs, init, h => by
    rw [List.forIn_cons]
    cases hx : f x init with
    | none => rfl
    | some r =>
      cases r with
      | done b => exact absurd hx (hd _ _ _)
      | yield b =>
        simp only [bind, Option.bind]
        apply forIn_option_none f hd xs b
        obtain ⟨a, ha, hn⟩ := h
        cases ha with
        | head => rw [hn] at hx; cases hx
        | tail _ ha => exact ⟨a, ha, hn⟩

/-- `vol.Schema({"days": ..., "hours": ..., "minutes": ..., "seconds": ...,
"milliseconds": ...})`: any other key (a non-string one too) is `Invalid`. -/
theorem timePeriodDict_bad_key (kvs : List (Value × Value))
    (h : ∃ p ∈ kvs, ∀ k, p.1 = .str k →
      k ∉ ["milliseconds", "seconds", "minutes", "hours", "days"]) :
    timePeriodDict (.dict kvs) = none := by
  unfold timePeriodDict
  simp only [bind, Option.bind, pure]
  split
  · rfl
  · rw [forIn_option_none]
    · intro a b b'
      split <;> (try split) <;> (try split) <;> simp
    · obtain ⟨p, hp, hk⟩ := h
      refine ⟨p, hp, fun b => ?_⟩
      split
      · rename_i k hk'
        have := hk k hk'
        rw [ite_eq_left]
        simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at this
        simp [List.any, Ne.symm this.1, Ne.symm this.2.1, Ne.symm this.2.2.1,
          Ne.symm this.2.2.2.1, Ne.symm this.2.2.2.2]
      · rfl

/-- Each unit is `vol.Coerce(float)`: one value `float()` rejects makes the
whole mapping `Invalid`. -/
theorem timePeriodDict_bad_value (kvs : List (Value × Value))
    (h : ∃ p ∈ kvs, pyFloatV? p.2 = none) : timePeriodDict (.dict kvs) = none := by
  unfold timePeriodDict
  simp only [bind, Option.bind, pure]
  split
  · rfl
  · rw [forIn_option_none]
    · intro a b b'
      split <;> (try split) <;> (try split) <;> simp
    · obtain ⟨p, hp, hk⟩ := h
      refine ⟨p, hp, fun b => ?_⟩
      split
      · split
        · rfl
        · rw [hk]
      · rfl

/-! ### `asciiOnly`, `pyFloatV?`, `timePeriodSeconds` -/

theorem asciiOnly_ok (s : String) : asciiOnly s = .ok () ↔ ∀ c ∈ s.toList, c.toNat < 128 := by
  unfold asciiOnly
  split <;> simp_all [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- `float(value)` raises (so the alternative is `Invalid`) exactly for
unparsable text and for anything that is not `str`, `int`, `bool`, `float`. -/
theorem pyFloatV?_eq_none (v : Value) : pyFloatV? v = none ↔
    (∀ s, v = .str s → parseFloatStr s = none) ∧ (∀ i, v ≠ .int i) ∧ (∀ b, v ≠ .bool b) ∧
    (∀ f, v ≠ .float f) := by
  cases v <;> simp [pyFloatV?]

theorem timePeriodSeconds_eq_none (v : Value) : timePeriodSeconds v = none ↔ pyFloatV? v = none := by
  simp [timePeriodSeconds]

theorem timePeriodSeconds_range (v : Value) (us : Int) (h : timePeriodSeconds v = some (.ok us)) :
    InTimedeltaRange us := by
  unfold timePeriodSeconds at h
  cases hf : pyFloatV? v with
  | none => rw [hf] at h; cases h
  | some f => rw [hf] at h; exact timedeltaNew_range _ _ (Option.some.inj h)

/-- `cv.time_period_seconds(float("nan"))`: the `ValueError` of
`timedelta(seconds=nan)` is not `Invalid`, so it escapes `vol.Any`. -/
theorem timePeriodSeconds_nan (f : Float) (h : f.isNaN = true) :
    timePeriodSeconds (.float f) =
      some (.error "ValueError: cannot convert float NaN to integer") := by
  simp [timePeriodSeconds, pyFloatV?, timedeltaNew, accum_nan _ _ _ _ h]
  rfl

/-! ### `cv.time_period`, one input type at a time -/

theorem cvTimePeriod_timedelta (us : Int) : cvTimePeriod (.timedelta us) = .ok us := rfl

theorem cvTimePeriod_int (i : Int) :
    cvTimePeriod (.int i) = timedeltaNew [(US_PER_SECOND, .float (intToFloat i))] := rfl

theorem cvTimePeriod_float (f : Float) :
    cvTimePeriod (.float f) = timedeltaNew [(US_PER_SECOND, .float f)] := rfl

theorem cvTimePeriod_bool (b : Bool) :
    cvTimePeriod (.bool b) = timedeltaNew [(US_PER_SECOND, .float (if b then 1 else 0))] := rfl

theorem cvTimePeriod_str_nonascii (s : String) (e : String) (h : asciiOnly s = .error e) :
    cvTimePeriod (.str s) = .error e := by
  simp [cvTimePeriod, h, bind, Except.bind]

theorem cvTimePeriod_str (s : String) (h : asciiOnly s = .ok ()) :
    cvTimePeriod (.str s) = match timePeriodStr s with
      | some r => r
      | none => match parseFloatStr s with
        | some f => timedeltaNew [(US_PER_SECOND, .float f)]
        | none => .error "invalid time period: expected 'HH:MM', 'HH:MM:SS', seconds or a mapping" := by
  simp only [cvTimePeriod, h, bind, Except.bind, List.findSome?, timePeriodSeconds, pyFloatV?]
  cases timePeriodStr s with
  | some r => rfl
  | none => cases parseFloatStr s <;> rfl

/-- Anything that is not text, a number, a `timedelta` or a mapping. -/
theorem cvTimePeriod_other (v : Value) (hs : ∀ s, v ≠ .str s) (hi : ∀ i, v ≠ .int i)
    (hb : ∀ b, v ≠ .bool b) (hf : ∀ f, v ≠ .float f) (ht : ∀ us, v ≠ .timedelta us)
    (hd : ∀ kvs, v ≠ .dict kvs) :
    cvTimePeriod v =
      .error "invalid time period: expected 'HH:MM', 'HH:MM:SS', seconds or a mapping" := by
  cases v <;> first
    | rfl
    | exact absurd rfl (hs _) | exact absurd rfl (hi _) | exact absurd rfl (hb _)
    | exact absurd rfl (hf _) | exact absurd rfl (ht _) | exact absurd rfl (hd _)

/-- Whatever `cv.time_period` returns is a `timedelta` Python can hold,
unless the input already was a `timedelta` (returned as is). -/
theorem cvTimePeriod_range (v : Value) (us : Int) (h : cvTimePeriod v = .ok us) :
    v = .timedelta us ∨ InTimedeltaRange us := by
  by_cases hs : ∃ s, v = .str s
  · obtain ⟨s, rfl⟩ := hs
    right
    cases ha : asciiOnly s with
    | error e => rw [cvTimePeriod_str_nonascii s e ha] at h; cases h
    | ok u =>
      rw [cvTimePeriod_str s ha] at h
      cases hp : timePeriodStr s with
      | some r => rw [hp] at h; subst h; exact timePeriodStr_range s us hp
      | none =>
        rw [hp] at h
        cases hq : parseFloatStr s with
        | none => rw [hq] at h; cases h
        | some f => rw [hq] at h; exact timedeltaNew_range _ _ h
  by_cases hd : ∃ kvs, v = .dict kvs
  · obtain ⟨kvs, rfl⟩ := hd
    right
    simp only [cvTimePeriod, bind, Except.bind, List.findSome?, timePeriodSeconds, pyFloatV?,
      Option.map] at h
    split at h
    · cases h
    · cases hq : timePeriodDict (.dict kvs) with
      | none => rw [hq] at h; cases h
      | some r => rw [hq] at h; subst h; exact timePeriodDict_range _ _ hq
  cases v with
  | str s => exact absurd ⟨s, rfl⟩ hs
  | dict kvs => exact absurd ⟨kvs, rfl⟩ hd
  | int i => exact .inr (timedeltaNew_range _ _ h)
  | float f => exact .inr (timedeltaNew_range _ _ h)
  | bool b => exact .inr (timedeltaNew_range _ _ h)
  | timedelta u => left; cases h; rfl
  | _ => cases h

/-! ### `cv.positive_time_period` -/

/-- `positive_time_period = All(time_period, positive_timedelta)`. -/
theorem cvPositiveTimePeriod_ok (v : Value) (us : Int) :
    cvPositiveTimePeriod v = .ok us ↔ cvTimePeriod v = .ok us ∧ 0 ≤ us := by
  unfold cvPositiveTimePeriod
  cases cvTimePeriod v with
  | error e => simp [bind, Except.bind]
  | ok u =>
    simp only [bind, Except.bind, pure, Except.pure]
    by_cases hu : u < 0
    · simp [hu, throw, throwThe, MonadExceptOf.throw]; intro h; omega
    · simp [hu]; intro h; omega

theorem cvPositiveTimePeriod_negative (v : Value) (us : Int) (h : cvTimePeriod v = .ok us)
    (hn : us < 0) : cvPositiveTimePeriod v = .error "Time period should be positive" := by
  simp [cvPositiveTimePeriod, h, bind, Except.bind, hn, throw, throwThe, MonadExceptOf.throw]

/-- The errors of `cv.time_period` pass through unchanged. -/
theorem cvPositiveTimePeriod_error (v : Value) (e : String) (h : cvTimePeriod v = .error e) :
    cvPositiveTimePeriod v = .error e := by
  simp [cvPositiveTimePeriod, h, bind, Except.bind]

/-! ### `timedelta(...)` on integers -/

/-- The accumulation loop of `delta_new` on `int` arguments is an exact sum. -/
theorem accum_loop_ints : ∀ (l : List (Nat × Int)) (x : Int) (left : Float),
    forIn (m := Except String) (l.map fun p => (p.1, TdArg.int p.2)) (x, left)
      (fun p s => do
        let r ← accum s.1 s.2 p.1 p.2
        pure (ForInStep.yield (r.1, r.2))) =
    .ok (x + (l.map fun p => p.2 * (p.1 : Int)).sum, left)
  | [], x, left => by simp [pure, Except.pure]
  | p :: l, x, left => by
    simp only [List.map_cons, List.forIn_cons, accum_int, bind, Except.bind, pure, Except.pure,
      List.sum_cons]
    have := accum_loop_ints l (x + p.2 * (p.1 : Int)) left
    simp only [bind, Except.bind, pure, Except.pure] at this
    rw [this, Int.add_assoc]

/-- `timedelta(...)` with only `int` arguments is the exact weighted sum, or
an `OverflowError` when that is out of range. (`h0` is `0.0 != 0.0 = False`,
which Lean's opaque `Float` cannot evaluate in a proof.) -/
theorem timedeltaNew_ints (l : List (Nat × Int)) (h0 : ((0 : Float) != 0) = false) (us : Int) :
    timedeltaNew (l.map fun p => (p.1, TdArg.int p.2)) = .ok us ↔
      us = (l.map fun p => p.2 * (p.1 : Int)).sum ∧ InTimedeltaRange us := by
  have key := accum_loop_ints l 0 0
  simp only [bind, Except.bind, pure, Except.pure] at key
  unfold timedeltaNew
  simp only [bind, Except.bind, pure, Except.pure, key, h0, Int.zero_add]
  unfold InTimedeltaRange
  split
  · rename_i h; cases h
  · by_cases hc : MAX_DELTA_DAYS < ((List.map (fun p => p.snd * (p.fst : Int)) l).sum.fdiv 86400000000).natAbs
    · rw [ite_eq_left_of_eq_true _ _ (eq_true hc)]
      simp only [throw, throwThe, MonadExceptOf.throw]
      constructor
      · intro h; cases h
      · rintro ⟨rfl, h⟩; omega
    · rw [ite_eq_right_of_eq_false _ _ (eq_false hc)]
      constructor
      · intro h; cases h; exact ⟨rfl, by omega⟩
      · rintro ⟨rfl, _⟩; rfl

end HALean.Automation
