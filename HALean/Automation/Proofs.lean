/-
  First theorems about the translated engine.
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

/-! ### Conditions -/

/-- An empty `and` is true (`AndConditionChecker` with no conditions). -/
theorem evalAnd_nil (env : CondEnv) : evalCond env (.and []) = .ok (some true) := by
  simp [evalCond, evalAnd]

/-- An empty `or` is false. -/
theorem evalOr_nil (env : CondEnv) : evalCond env (.or []) = .ok (some false) := by
  simp [evalCond, evalOr]

/-- A disabled condition returns `None` … -/
theorem evalCond_disabled (env : CondEnv) : evalCond env .disabled = .ok none := by
  simp [evalCond]

/-- … which `not` treats as falsy, so `not [disabled]` is true. -/
theorem evalNot_disabled (env : CondEnv) :
    evalCond env (.not [.disabled]) = .ok (some true) := by
  simp [evalCond, evalNot]

/-- … and `and` skips, so disabling every condition of an `and` makes it true. -/
theorem evalAnd_all_disabled (env : CondEnv) (n : Nat) :
    evalAnd env (List.replicate n .disabled) [] = .ok (some true) := by
  induction n with
  | zero => simp [evalAnd]
  | succ n ih => simp [List.replicate_succ, evalAnd, evalCond, ih]

/-- An automation with no conditions always passes its condition check. -/
theorem checkAutomationConditions_nil (env : CondEnv) :
    checkAutomationConditions env [] = true := by
  simp [checkAutomationConditions, evalAnd]

/-- `_test_conditions` on an empty list is `True`. -/
theorem testConditions_nil (env : CondEnv) : testConditions env [] = some true := rfl

/-! ### State matching (`process_state_match`) -/

/-- `not_to: X` matches exactly what `to: X` does not. -/
theorem match_invert (vs : List Json) (v : Json) :
    StateMatch.matches { values := some vs, invert := true } v
      = !StateMatch.matches { values := some vs, invert := false } v := by
  simp [StateMatch.matches]

/-- With neither from/to given, every value matches. -/
theorem match_all (v : Json) : StateMatch.matches {} v = true := by
  simp [StateMatch.matches]

/-! ### Run modes (`Script.async_run`) -/

/-- `single`: a second run is admitted only when nothing is running. -/
theorem single_exclusive (m n : Nat) :
    (admit .single m n = .start) ↔ n = 0 := by
  unfold admit; by_cases h : n = 0 <;> simp [h]

/-- `restart` never rejects a trigger. -/
theorem restart_never_rejects (m n : Nat) (why : String) :
    admit .restart m n ≠ .reject why := by
  unfold admit; by_cases h : n = 0 <;> simp [h]

/-- `queued`/`parallel`: admitting never takes the number of runs above `max`
(given the invariant `n ≤ max` and `max ≥ 1`, which config validation ensures). -/
theorem admit_bounded (mode : Mode) (m n : Nat) (hm : 1 ≤ m) (hn : n ≤ m)
    (hmode : mode ≠ .restart) (hadm : admit mode m n = .start ∨ admit mode m n = .enqueue) :
    n + 1 ≤ m := by
  unfold admit at hadm
  by_cases h0 : n = 0
  · omega
  · by_cases hs : mode = .single
    · subst hs; simp [h0] at hadm
    · by_cases hmax : n = m
      · subst hmax; simp [h0, hs, hmode] at hadm
      · omega

/-- A `queued` script with work in flight always queues (never runs in parallel). -/
theorem queued_waits (m n : Nat) (h0 : n ≠ 0) (hm : n ≠ m) :
    admit .queued m n = .enqueue := by
  unfold admit; simp [h0, hm]

end HALean.Automation
