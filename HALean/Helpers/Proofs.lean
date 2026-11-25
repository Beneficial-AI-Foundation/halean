/-
  Properties of the helper state machines.

  * `input_boolean`: `toggle` is an involution; `turn_on` / `turn_off` are
    idempotent and set the state.
  * `input_number`: every service that succeeds leaves the value not strictly
    below `min` and not strictly above `max` (NaN satisfies this, and upstream
    does let a NaN through: the statement is exactly what the range check
    guarantees, see `InputNumber.lean`).
  * `input_select`: every service that succeeds keeps the current option among
    the options, so the state is never `unknown`; a fresh entity starts that
    way when its config is valid.
  * `counter`: `increment` / `decrement` / `reset` and a successful
    `set_value` leave the value within `[minimum, maximum]` when
    `minimum ≤ maximum` (and below `maximum` / above `minimum` when only one
    is set); upstream does not clamp `initial`, so a fresh counter may be
    outside them.
  * `timer`: cancelling or finishing leaves it idle, with nothing scheduled,
    no remaining time, and its configured duration.
-/
import HALean.Helpers.Component

namespace HALean.Helpers
open HALean.Core HALean.Template

/-! ## input_boolean -/

namespace InputBoolean

theorem toggle_toggle (e : Entity) : toggle (toggle e) = e := by
  cases e with
  | mk cfg isOn => cases isOn <;> rfl

theorem turnOn_idem (e : Entity) : turnOn (turnOn e) = turnOn e := rfl
theorem turnOff_idem (e : Entity) : turnOff (turnOff e) = turnOff e := rfl

theorem state_turnOn (e : Entity) : (turnOn e).state = "on" := rfl
theorem state_turnOff (e : Entity) : (turnOff e).state = "off" := rfl

theorem state_toggle (e : Entity) : (toggle e).state ≠ e.state := by
  cases e with
  | mk cfg isOn => cases isOn <;> simp [toggle, turnOn, turnOff, Entity.state]

end InputBoolean

/-! ## input_number -/

namespace InputNumber

/-- Never strictly outside `[min, max]`. -/
def Entity.Bounded (e : Entity) : Prop := ¬ (e.value < e.cfg.min) ∧ ¬ (e.value > e.cfg.max)

theorem setValue_bounded {e e' : Entity} {v : Float} (h : setValue e v = .ok e') :
    e'.Bounded ∧ e'.cfg = e.cfg := by
  unfold setValue inRange at h
  by_cases hr : (!(decide (v < e.cfg.min) || decide (v > e.cfg.max))) = true
  · simp only [hr, ↓reduceIte] at h
    cases h
    simp only [Bool.not_or, Bool.and_eq_true, Bool.not_eq_true', decide_eq_false_iff_not] at hr
    exact ⟨⟨hr.1, hr.2⟩, rfl⟩
  · simp only [hr, ↓reduceIte, Bool.false_eq_true] at h
    cases h

theorem increment_bounded {e e' : Entity} (h : increment e = .ok e') :
    e'.Bounded ∧ e'.cfg = e.cfg := setValue_bounded h

theorem decrement_bounded {e e' : Entity} (h : decrement e = .ok e') :
    e'.Bounded ∧ e'.cfg = e.cfg := setValue_bounded h

/-- A value outside the range is refused, and the error names it. -/
theorem setValue_error {e : Entity} {v : Float} (h : v < e.cfg.min ∨ v > e.cfg.max) :
    ∃ err, setValue e v = .error err ∧ err.exception = "Invalid" := by
  unfold setValue inRange
  have : (!(decide (v < e.cfg.min) || decide (v > e.cfg.max))) = false := by
    rcases h with h | h <;> simp [h]
  simp only [this, Bool.false_eq_true, ↓reduceIte]
  exact ⟨_, rfl, rfl⟩

end InputNumber

/-! ## input_select -/

namespace InputSelect

/-- The current option is one of the options. -/
def Entity.Valid (e : Entity) : Prop := e.current ∈ e.options

theorem state_of_valid {e : Entity} (h : e.Valid) : e.state = e.current := by
  unfold Entity.state
  have h' : e.current ∈ e.options := h
  simp [h']

theorem selectOption_valid {e e' : Entity} {o : String} (h : selectOption e o = .ok e') :
    e'.Valid ∧ e'.options = e.options := by
  unfold selectOption at h
  by_cases hc : e.options.contains o = true
  · simp only [hc, ↓reduceIte] at h
    cases h
    exact ⟨List.elem_iff.mp hc, rfl⟩
  · simp only [hc, ↓reduceIte, Bool.false_eq_true] at h
    cases h

theorem selectIndex_valid {e e' : Entity} {i : Int} (h : selectIndex e i = .ok e') :
    e'.Valid ∧ e'.options = e.options := selectOption_valid h

theorem offsetIndex_valid {e e' : Entity} {o : Int} {c : Bool} (h : offsetIndex e o c = .ok e') :
    e'.Valid ∧ e'.options = e.options := selectOption_valid h

theorem setOptions_valid {e e' : Entity} {opts : List String} {w : Option String}
    (hne : opts ≠ []) (h : setOptions e opts = .ok (e', w)) : e'.Valid ∧ e'.options = opts := by
  unfold setOptions at h
  split at h
  · cases h
  · split at h
    · cases h
      rename_i hc
      exact ⟨List.elem_iff.mp hc, rfl⟩
    · cases h
      refine ⟨?_, rfl⟩
      cases opts with
      | nil => exact absurd rfl hne
      | cons x xs => exact List.mem_cons_self
end InputSelect

/-- A valid config (what `decode` returns: non-empty options, `initial`
among them) gives a valid entity, restored or not. -/
theorem InputSelect.create_valid (cfg : InputSelect.Config) (last : Option String)
    (hne : cfg.options ≠ []) (hi : ∀ i, cfg.initial = some i → i ∈ cfg.options) :
    (InputSelect.Entity.create cfg last).Valid := by
  have first : cfg.options.headD "" ∈ cfg.options := by
    cases h : cfg.options with
    | nil => exact absurd h hne
    | cons x xs => exact List.mem_cons_self
  unfold InputSelect.Entity.create InputSelect.Entity.Valid
  split
  · exact hi _ (by assumption)
  · split
    · dsimp only
      split
      · exact List.elem_iff.mp (by assumption)
      · exact first
    · exact first

/-! ## counter -/

namespace Counter

theorem clamp_le_max {c : Config} {m : Int} (hm : c.maximum = some m) (v : Int) : clamp c v ≤ m := by
  unfold clamp; rw [hm]; exact Int.min_le_left _ _

theorem min_le_clamp {c : Config} {m : Int} (hm : c.minimum = some m)
    (hM : ∀ M', c.maximum = some M' → m ≤ M') (v : Int) : m ≤ clamp c v := by
  unfold clamp; rw [hm]
  cases h : c.maximum with
  | none => exact Int.le_max_left _ _
  | some M' => exact Int.le_min.mpr ⟨hM M' h, Int.le_max_left _ _⟩

/-- Within the bounds that are set (when `minimum ≤ maximum`). -/
def Entity.InBounds (e : Entity) : Prop :=
  (∀ m, e.cfg.minimum = some m → m ≤ e.value) ∧ (∀ M, e.cfg.maximum = some M → e.value ≤ M)

/-- The bounds are consistent. -/
def Config.Consistent (c : Config) : Prop := ∀ m M, c.minimum = some m → c.maximum = some M → m ≤ M

theorem clamp_inBounds (e : Entity) (hc : e.cfg.Consistent) (v : Int) :
    Entity.InBounds { e with value := clamp e.cfg v } :=
  ⟨fun m hm => min_le_clamp hm (fun M hM => hc m M hm hM) v, fun _ hM => clamp_le_max hM v⟩

theorem increment_inBounds (e : Entity) (hc : e.cfg.Consistent) : (increment e).InBounds :=
  clamp_inBounds e hc _
theorem decrement_inBounds (e : Entity) (hc : e.cfg.Consistent) : (decrement e).InBounds :=
  clamp_inBounds e hc _
theorem reset_inBounds (e : Entity) (hc : e.cfg.Consistent) : (reset e).InBounds :=
  clamp_inBounds e hc _

/-- `set_value` succeeds only within the bounds (whatever they are) and on a
multiple of the step. -/
theorem setValue_inBounds {e e' : Entity} {v : Int} (h : setValue e v = .ok e') :
    e'.InBounds ∧ e'.value = v ∧ e'.cfg = e.cfg := by
  unfold setValue setValue.rest setValue.stepCheck at h
  have hstep : setValue.stepCheck e v = .ok e' → e' = { e with value := v } := by
    unfold setValue.stepCheck
    intro h'
    split at h'
    · cases h'
    · split at h'
      · cases h'
      · cases h'; rfl
  cases hM : e.cfg.maximum with
  | none =>
    rw [hM] at h; simp only at h
    cases hm : e.cfg.minimum with
    | none =>
      rw [hm] at h; simp only at h
      have := hstep h; subst this
      exact ⟨⟨fun m h => by simp [hm] at h, fun M h => by simp [hM] at h⟩, rfl, rfl⟩
    | some m =>
      rw [hm] at h; simp only at h
      split at h
      · cases h
      · rename_i hlt
        have := hstep h; subst this
        refine ⟨⟨fun m' h' => ?_, fun M h => by simp [hM] at h⟩, rfl, rfl⟩
        simp [hm] at h'; subst h'; exact Int.not_lt.mp hlt
  | some M =>
    rw [hM] at h; simp only at h
    split at h
    · cases h
    · rename_i hgt
      cases hm : e.cfg.minimum with
      | none =>
        rw [hm] at h; simp only at h
        have := hstep h; subst this
        refine ⟨⟨fun m h => by simp [hm] at h, fun M' h' => ?_⟩, rfl, rfl⟩
        simp [hM] at h'; subst h'; exact Int.not_lt.mp hgt
      | some m =>
        rw [hm] at h; simp only at h
        split at h
        · cases h
        · rename_i hlt
          have := hstep h; subst this
          refine ⟨⟨fun m' h' => ?_, fun M' h' => ?_⟩, rfl, rfl⟩
          · simp [hm] at h'; subst h'; exact Int.not_lt.mp hlt
          · simp [hM] at h'; subst h'; exact Int.not_lt.mp hgt

end Counter

/-! ## timer -/

namespace Timer

theorem toIdle_idle (e : Entity) :
    (toIdle e).state = .idle ∧ (toIdle e).scheduled = false ∧ (toIdle e).remaining = none ∧
    (toIdle e).end_ = none ∧ (toIdle e).running = e.cfg.duration :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- An idle timer's callback is never due. -/
theorem toIdle_not_due (e : Entity) (now : Int) : (toIdle e).due now = false := rfl

end Timer

end HALean.Helpers
