/-
  Specifications for the stateful helpers of `HALean/Template/Render.lean`
  (the `R` monad: errors plus the render state): what a render records in
  its `RenderInfo`, the step budget, the forgiving conversions (`float`,
  `int`, `bool`, `is_number`), the state functions (`is_state`,
  `state_attr`, `has_value`), iteration, and arithmetic.
-/
import HALean.Template.Render

namespace HALean.Template

set_option linter.unusedSimpArgs false

/-- Run a render action from a given state: the result (or error) and the
state afterwards. -/
abbrev runR (x : R α) (s : RS) : Except String α × RS := x.run.run s

/-- Unfold the `R` monad. -/
local macro "rsimp" "[" ls:Lean.Parser.Tactic.simpLemma,* "]" loc:(Lean.Parser.Tactic.location)? : tactic =>
  `(tactic| simp [runR, bind, pure, ExceptT.bind, ExceptT.pure, ExceptT.run, ExceptT.mk,
      ExceptT.bindCont, StateT.bind, StateT.pure, StateT.run, StateT.map, Functor.map, ExceptT.map,
      get, getThe, MonadStateOf.get, StateT.get, set, MonadStateOf.set, StateT.set, modify,
      modifyGet, MonadStateOf.modifyGet, StateT.modifyGet, liftM, monadLift, MonadLift.monadLift,
      ExceptT.lift, throw, throwThe, MonadExceptOf.throw, $ls,*] $[$loc]?)

/-! ## What a render records -/

/-- `collect` never fails and leaves the entity recorded. -/
theorem collect_mem (eid : String) (s : RS) :
    (runR (collect eid) s).1 = .ok () ∧ eid ∈ (runR (collect eid) s).2.info.entities := by
  rsimp [collect]
  split <;> simp_all

/-- Entities recorded earlier stay recorded. -/
theorem collect_mono (eid e : String) (s : RS) (h : e ∈ s.info.entities) :
    e ∈ (runR (collect eid) s).2.info.entities := by
  rsimp [collect]
  split <;> simp_all

/-- Recording an entity that is already recorded changes nothing. -/
theorem collect_of_mem (eid : String) (s : RS) (h : eid ∈ s.info.entities) :
    runR (collect eid) s = (.ok (), s) := by
  rsimp [collect, h]

/-- Recording is idempotent. -/
theorem collect_idem (eid : String) (s : RS) :
    runR (collect eid) (runR (collect eid) s).2 = (.ok (), (runR (collect eid) s).2) :=
  collect_of_mem eid _ (collect_mem eid s).2

/-- The entity list stays duplicate-free (it models a Python set). -/
theorem collect_nodup (eid : String) (s : RS) (h : s.info.entities.Nodup) :
    (runR (collect eid) s).2.info.entities.Nodup := by
  rsimp [collect]
  split
  · exact h
  · rename_i hn
    simp only [List.nodup_append, h, true_and]
    simp
    intro a ha he
    exact hn (he ▸ ha)

/-- `collect` touches only the entity list. -/
theorem collect_frame (eid : String) (s : RS) :
    let s' := (runR (collect eid) s).2
    s'.info.domains = s.info.domains ∧ s'.info.domainsLifecycle = s.info.domainsLifecycle ∧
      s'.info.allStates = s.info.allStates ∧ s'.info.allStatesLifecycle = s.info.allStatesLifecycle ∧
      s'.info.hasTime = s.info.hasTime ∧ s'.out = s.out ∧ s'.steps = s.steps ∧ s'.heap = s.heap := by
  rsimp [collect]
  split <;> simp

/-- Iterating a domain records it for state changes; asking its length
records it for lifecycle events (entities added or removed). -/
theorem collectDomain_spec (d : String) (lifecycle : Bool) (s : RS) :
    (runR (collectDomain d lifecycle) s).1 = .ok () ∧
      (if lifecycle then d ∈ (runR (collectDomain d lifecycle) s).2.info.domainsLifecycle ∧
          (runR (collectDomain d lifecycle) s).2.info.domains = s.info.domains
        else d ∈ (runR (collectDomain d lifecycle) s).2.info.domains ∧
          (runR (collectDomain d lifecycle) s).2.info.domainsLifecycle = s.info.domainsLifecycle) := by
  cases lifecycle <;> rsimp [collectDomain]

/-- `collectAll` sets exactly the matching all-states flag. -/
theorem collectAll_spec (lifecycle : Bool) (s : RS) :
    (runR (collectAll lifecycle) s).1 = .ok () ∧
      (runR (collectAll lifecycle) s).2.info.allStates = (s.info.allStates || !lifecycle) ∧
      (runR (collectAll lifecycle) s).2.info.allStatesLifecycle =
        (s.info.allStatesLifecycle || lifecycle) := by
  cases lifecycle <;> rsimp [collectAll]

/-- After `collectAll false` every entity passes the render-info filter. -/
theorem collectAll_filter (s : RS) (eid : String) :
    (runR (collectAll false) s).2.info.filter eid = true := by
  rsimp [collectAll, RInfo.filter]

/-- `now()` and friends mark the template as time-dependent. -/
theorem collectTime_spec (s : RS) :
    runR collectTime s = (.ok (), { s with info := { s.info with hasTime := true } }) := by
  rsimp [collectTime]

/-! ## The step budget -/

/-- Within the budget a step is counted. -/
theorem tick_ok (s : RS) (h : s.steps < MAX_STEPS) :
    runR tick s = (.ok (), { s with steps := s.steps + 1 }) := by
  rsimp [tick, Nat.not_le.mpr h]

/-- At the budget the render fails (and nothing else changes). -/
theorem tick_error (s : RS) (h : MAX_STEPS ≤ s.steps) :
    runR tick s = (.error "template exceeded HALean's step budget", s) := by
  rsimp [tick, h]

/-- `tick` succeeds exactly while under the budget. -/
theorem tick_ok_iff (s : RS) : (runR tick s).1 = .ok () ↔ s.steps < MAX_STEPS := by
  by_cases h : s.steps < MAX_STEPS
  · simp [tick_ok s h, h]
  · simp [tick_error s (by omega), h]

/-- The step counter never exceeds the budget once it is within it. -/
theorem tick_bound (s : RS) (h : s.steps ≤ MAX_STEPS) : (runR tick s).2.steps ≤ MAX_STEPS := by
  by_cases h' : s.steps < MAX_STEPS
  · rw [tick_ok s h']; simp; omega
  · rw [tick_error s (by omega)]; exact h

/-! ## Errors and conversions -/

/-- Using an Undefined always raises, without touching the render state. -/
theorem undefErr_error (v : Value) (s : RS) :
    ∃ e, runR (undefErr v : R α) s = (.error e, s) := by
  cases v <;> exact ⟨_, rfl⟩

/-- `noDefault` always raises. -/
theorem noDefault_error (fn : String) (v : Value) (s : RS) :
    ∃ e, runR (noDefault fn v : R α) s = (.error e, s) := ⟨_, rfl⟩

/-- `strOf` is `pyStr` lifted into the render monad. -/
theorem strOf_eq (v : Value) (s : RS) : runR (strOf v) s = (pyStr v, s) := by
  unfold strOf
  cases pyStr v <;> rfl

/-- `liftExcept` keeps the result and the state. -/
theorem liftExcept_eq (x : Except String α) (s : RS) : runR (liftExcept x) s = (x, s) := by
  cases x <;> rfl

/-- `float(x)` of a number is that number (an int too large for a float
raises `OverflowError`); text is read as Python reads it (Unicode digits and
spaces too); anything else is a `TypeError` (`none`). -/
theorem toFloat_cases (s : RS) :
    (∀ f, runR (toFloat? (.float f)) s = (.ok (some f), s)) ∧
    (∀ i, (intToFloat i).isInf = false → runR (toFloat? (.int i)) s = (.ok (some (intToFloat i)), s)) ∧
    (∀ i, (intToFloat i).isInf = true → ∃ e, runR (toFloat? (.int i)) s = (.error e, s)) ∧
    (∀ t, runR (toFloat? (.str t)) s = (.ok (pyFloatStr t), s)) ∧
    runR (toFloat? .none) s = (.ok none, s) ∧
    (∀ xs, runR (toFloat? (.list xs)) s = (.ok none, s)) ∧
    (∀ kvs, runR (toFloat? (.dict kvs)) s = (.ok none, s)) :=
  ⟨fun _ => rfl, fun _ hi => by rsimp [toFloat?, hi], fun _ hi => ⟨"OverflowError: int too large to convert to float", by rsimp [toFloat?, hi]⟩,
   fun _ => rfl, rfl, fun _ => rfl, fun _ => rfl⟩

/-- `toFloat?` never changes the render state, and only an Undefined, an
unmodelled object or an int too large for a float makes it raise. -/
theorem toFloat_total (v : Value) (s : RS) (h : isOpaqueOrUndef v = false)
    (hi : ∀ i, v = .int i → (intToFloat i).isInf = false) :
    ∃ r, runR (toFloat? v) s = (.ok r, s) := by
  cases v with
  | int i => exact ⟨some (intToFloat i), by rsimp [toFloat?, hi i rfl]⟩
  | _ => first | exact ⟨_, rfl⟩ | (simp [isOpaqueOrUndef] at h; done)

/-- `int(x)`: an int is itself and a bool is 0 or 1. -/
theorem doInt_int (i : Int) (b : Bool) (s : RS) :
    runR (doInt (.int i)) s = (.ok (some i), s) ∧
      runR (doInt (.bool b)) s = (.ok (some (if b then 1 else 0)), s) := ⟨rfl, rfl⟩

/-- Values that are neither numbers nor text have no int (the default). -/
theorem doInt_none (xs : List Value) (s : RS) :
    runR (doInt .none) s = (.ok none, s) ∧ runR (doInt (.list xs)) s = (.ok none, s) := ⟨rfl, rfl⟩

/-! ## `float`, `int`, `bool`, `is_number` -/

/-- `float(x, default)` never raises for a modelled value: the result is a
float or the default. -/
theorem forgivingFloat_default (v d : Value) (s : RS) (h : isOpaqueOrUndef v = false)
    (hi : ∀ i, v = .int i → (intToFloat i).isInf = false) :
    ∃ r, runR (forgivingFloat v (some d)) s = (.ok r, s) ∧ (r = d ∨ ∃ f, r = .float f) := by
  cases v with
  | int i =>
    exact ⟨.float (intToFloat i), by rsimp [forgivingFloat, toFloat?, hi i rfl], .inr ⟨_, rfl⟩⟩
  | str t =>
    cases hp : pyFloatStr t with
    | none => exact ⟨d, by rsimp [forgivingFloat, toFloat?, hp], .inl rfl⟩
    | some f => exact ⟨.float f, by rsimp [forgivingFloat, toFloat?, hp], .inr ⟨f, rfl⟩⟩
  | _ => first
    | exact ⟨_, rfl, .inl rfl⟩
    | exact ⟨_, rfl, .inr ⟨_, rfl⟩⟩
    | (simp [isOpaqueOrUndef] at h; done)

/-- A float is its own `float()`. -/
theorem forgivingFloat_float (f : Float) (d : Option Value) (s : RS) :
    runR (forgivingFloat (.float f) d) s = (.ok (.float f), s) := rfl

/-- `float(None)` without a default raises. -/
theorem forgivingFloat_none (s : RS) : ∃ e, runR (forgivingFloat .none none) s = (.error e, s) :=
  ⟨_, rfl⟩

/-- An int is its own `int()`, whatever the default. -/
theorem forgivingInt_int (i : Int) (d : Option Value) (s : RS) :
    runR (forgivingInt (.int i) d none) s = (.ok (.int i), s) := rfl

/-- `int(True) == 1`, `int(False) == 0`. -/
theorem forgivingInt_bool (b : Bool) (d : Option Value) (s : RS) :
    runR (forgivingInt (.bool b) d none) s = (.ok (.int (if b then 1 else 0)), s) := rfl

/-- `int(None, default)` is the default; without one it raises. -/
theorem forgivingInt_none (d : Value) (s : RS) :
    runR (forgivingInt .none (some d) none) s = (.ok d, s) ∧
      ∃ e, runR (forgivingInt .none none none) s = (.error e, s) := ⟨rfl, _, rfl⟩

/-- `bool(x, default)` is `cv.boolean(x)` when that is valid and the default
otherwise; it never raises for a modelled value. -/
theorem forgivingBool_default (v d : Value) (s : RS) (h : ∀ w, v ≠ .opaque w) :
    runR (forgivingBool v (some d)) s =
      (.ok (match cvBoolean v with | some b => .bool b | none => d), s) := by
  cases v <;> first
    | rfl
    | (exact absurd rfl (h _))
    | skip
  rename_i t
  rsimp [forgivingBool, cvBoolean]
  cases cvBooleanText t <;> rfl

/-- `bool(x)` without a default raises exactly when `cv.boolean` rejects. -/
theorem forgivingBool_no_default (v : Value) (s : RS) (h : ∀ w, v ≠ .opaque w)
    (hc : cvBoolean v = none) : ∃ e, runR (forgivingBool v none) s = (.error e, s) := by
  cases v <;> first
    | exact ⟨_, rfl⟩
    | (exact absurd rfl (h _))
    | (simp [cvBoolean] at hc; done)
    | skip
  rename_i t
  simp only [cvBoolean] at hc
  exact ⟨_, by rsimp [forgivingBool, cvBoolean, hc, noDefault]; rfl⟩

/-- `is_number` never raises for a modelled value (an int too large for a
float raises `OverflowError` in `float()`, which `is_number` does not catch). -/
theorem isNumber_total (v : Value) (s : RS) (h : isOpaqueOrUndef v = false)
    (hi : ∀ i, v = .int i → (intToFloat i).isInf = false) :
    ∃ b, runR (isNumber v) s = (.ok b, s) := by
  obtain ⟨r, hr⟩ := toFloat_total v s h hi
  rsimp [isNumber] at hr ⊢
  rw [hr]
  cases r <;> rsimp [id]

/-- Things that are not numbers or text are not numbers. -/
theorem isNumber_none (xs : List Value) (s : RS) :
    runR (isNumber .none) s = (.ok false, s) ∧ runR (isNumber (.list xs)) s = (.ok false, s) :=
  ⟨rfl, rfl⟩

/-! ## `is_state`, `state_attr`, `has_value` -/

/-- `is_state(entity_id, ...)` always records the entity in the render info,
so the template is re-rendered when that entity changes. -/
theorem isState_collects (ctx : Ctx) (e : String) (st : Value) (s : RS) :
    e ∈ (runR (isState ctx (.str e) st) s).2.info.entities := by
  have hc := collect_mem e s
  rsimp [isState] at hc ⊢
  cases hx : collect e s with
  | mk a s' =>
    rw [hx] at hc; simp at hc; obtain ⟨rfl, hm⟩ := hc
    cases ctx.states.get? e <;> rsimp [hm]

/-- `is_state` of an entity that does not exist is False. -/
theorem isState_missing (ctx : Ctx) (e : String) (st : Value) (s : RS)
    (h : ctx.states.get? e = none) : (runR (isState ctx (.str e) st) s).1 = .ok false := by
  have hc : (collect e s).1 = .ok () := (collect_mem e s).1
  rsimp [isState, h] at hc ⊢
  cases hx : collect e s with
  | mk a s' => rw [hx] at hc; simp at hc; subst hc; rsimp [id]

/-- `is_state` of a state equal to the one asked is True. -/
theorem isState_true (ctx : Ctx) (e : String) (st : EntityState) (v : Value) (s : RS)
    (h : ctx.states.get? e = some st) (hv : pyEq (.str st.state) v = true) :
    (runR (isState ctx (.str e) v) s).1 = .ok true := by
  have hc : (collect e s).1 = .ok () := (collect_mem e s).1
  rsimp [isState, h] at hc ⊢
  cases hx : collect e s with
  | mk a s' => rw [hx] at hc; simp at hc; subst hc; rsimp [hv]

/-- `is_state(entity, [a, b])`: a list of states matches when any of them does. -/
theorem isState_list (ctx : Ctx) (e : String) (st : EntityState) (xs : List Value) (s : RS)
    (h : ctx.states.get? e = some st) (x : Value) (hx : x ∈ xs)
    (hv : pyEq (.str st.state) x = true) :
    (runR (isState ctx (.str e) (.list xs)) s).1 = .ok true := by
  have hc : (collect e s).1 = .ok () := (collect_mem e s).1
  rsimp [isState, h] at hc ⊢
  cases hx' : collect e s with
  | mk a s' =>
    rw [hx'] at hc; simp at hc; subst hc; rsimp [id]
    exact Or.inr ⟨x, hx, hv⟩

/-- A non-string entity id is never in a state, and nothing is recorded. -/
theorem isState_nonstr (ctx : Ctx) (v st : Value) (s : RS) (h : ∀ e, v ≠ .str e) :
    runR (isState ctx v st) s = (.ok false, s) := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- `has_value` records the entity too. -/
theorem hasValue_collects (ctx : Ctx) (e : String) (s : RS) :
    e ∈ (runR (hasValue ctx (.str e)) s).2.info.entities := by
  have hc := collect_mem e s
  rsimp [hasValue] at hc ⊢
  cases hx : collect e s with
  | mk a s' =>
    rw [hx] at hc; simp at hc; obtain ⟨rfl, hm⟩ := hc
    cases ctx.states.get? e <;> rsimp [hm]

/-- **`has_value`**: true exactly when the entity exists and its state is
neither `unavailable` nor `unknown`. -/
theorem hasValue_iff (ctx : Ctx) (e : String) (s : RS) :
    (runR (hasValue ctx (.str e)) s).1 = .ok true ↔
      ∃ st, ctx.states.get? e = some st ∧ st.state ≠ STATE_UNAVAILABLE ∧ st.state ≠ STATE_UNKNOWN := by
  have hc : (collect e s).1 = .ok () := (collect_mem e s).1
  rsimp [hasValue] at hc ⊢
  cases hx : collect e s with
  | mk a s' =>
    rw [hx] at hc; simp at hc; subst hc
    cases ctx.states.get? e <;> rsimp [id]

/-- A non-string entity id has no value. -/
theorem hasValue_nonstr (ctx : Ctx) (v : Value) (s : RS) (h : ∀ e, v ≠ .str e) :
    runR (hasValue ctx v) s = (.ok false, s) := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- `state_attr` of an entity that does not exist is `None` (and the entity
is still recorded). -/
theorem stateAttrFn_missing (ctx : Ctx) (e n : String) (s : RS) (h : ctx.states.get? e = none) :
    (runR (stateAttrFn ctx (.str e) (.str n)) s).1 = .ok .none ∧
      e ∈ (runR (stateAttrFn ctx (.str e) (.str n)) s).2.info.entities := by
  have hc := collect_mem e s
  rsimp [stateAttrFn, h] at hc ⊢
  cases hx : collect e s with
  | mk a s' => rw [hx] at hc; simp at hc; obtain ⟨rfl, hm⟩ := hc; rsimp [hm]

/-- A non-string entity id has no attributes. -/
theorem stateAttrFn_nonstr (ctx : Ctx) (v n : Value) (s : RS) (h : ∀ e, v ≠ .str e) :
    runR (stateAttrFn ctx v n) s = (.ok .none, s) := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- `states.<domain>.<object_id>` of an existing entity is its (collecting)
state object. -/
theorem stateIfValid_some (ctx : Ctx) (eid : String) (st : EntityState) (s : RS)
    (h : ctx.states.get? eid = some st) :
    runR (stateIfValid ctx eid) s = (.ok (.state st true), s) := by
  unfold stateIfValid; rw [h]; rfl

/-- An invalid entity id raises instead of returning `None`. -/
theorem stateIfValid_invalid (ctx : Ctx) (eid : String) (s : RS)
    (h : ctx.states.get? eid = none) (hv : validEntityId eid = false) :
    ∃ e, runR (stateIfValid ctx eid) s = (.error e, s) := by
  unfold stateIfValid; rw [h]; simp only [hv]; exact ⟨_, rfl⟩

/-- `StateMachine.get` finds an id stored exactly as given. -/
theorem hassStatesGet_some (ctx : Ctx) (eid : String) (st : EntityState) (s : RS)
    (h : ctx.states.get? eid = some st) : runR (hassStatesGet ctx eid) s = (.ok (some st), s) := by
  unfold hassStatesGet; rw [h]; rfl

/-! ## Iteration, length, membership -/

/-- Iterating a list or tuple yields its items; an Undefined is empty. -/
theorem iterV_list (ctx : Ctx) (xs : List Value) (n : String) (s : RS) :
    runR (iterV ctx (.list xs)) s = (.ok xs, s) ∧ runR (iterV ctx (.tuple xs)) s = (.ok xs, s) ∧
      runR (iterV ctx (.undef n)) s = (.ok [], s) := ⟨rfl, rfl, rfl⟩

/-- Iterating a dict yields its keys, in insertion order. -/
theorem iterV_dict (ctx : Ctx) (kvs : List (Value × Value)) (s : RS) :
    runR (iterV ctx (.dict kvs)) s = (.ok (kvs.map (·.1)), s) := rfl

/-- Numbers and `None` are not iterable. -/
theorem iterV_scalar (ctx : Ctx) (i : Int) (s : RS) :
    (∃ e, runR (iterV ctx (.int i)) s = (.error e, s)) ∧
      (∃ e, runR (iterV ctx .none) s = (.error e, s)) := ⟨⟨_, rfl⟩, ⟨_, rfl⟩⟩

/-- For plain collections `len(x)` is the number of items iteration yields. -/
theorem lenV_eq_iterV_length (ctx : Ctx) (v : Value) (s : RS)
    (h : (∃ xs, v = .list xs) ∨ (∃ xs, v = .tuple xs) ∨ (∃ kvs, v = .dict kvs) ∨
      (∃ t, v = .str t) ∨ (∃ a b c, v = .range a b c) ∨ (∃ n, v = .undef n)) :
    ∃ xs, runR (iterV ctx v) s = (.ok xs, s) ∧ runR (lenV ctx v) s = (.ok (xs.length : Int), s) := by
  rcases h with ⟨xs, rfl⟩ | ⟨xs, rfl⟩ | ⟨kvs, rfl⟩ | ⟨t, rfl⟩ | ⟨a, b, c, rfl⟩ | ⟨n, rfl⟩
  · exact ⟨_, rfl, rfl⟩
  · exact ⟨_, rfl, rfl⟩
  · exact ⟨_, rfl, by simp [lenV, runR]; rfl⟩
  · exact ⟨_, rfl, by simp [lenV, runR, ← String.length_toList]; rfl⟩
  · exact ⟨_, rfl, by simp [lenV, runR]; rfl⟩
  · exact ⟨_, rfl, rfl⟩

/-- Iterating `states` records an all-states dependency and yields every
state; iterating a domain records the domain. -/
theorem iterV_allStates (ctx : Ctx) (s : RS) :
    (runR (iterV ctx .allStates) s).1 = .ok (statesOf ctx none) ∧
      (runR (iterV ctx .allStates) s).2.info.allStates = true := by
  rsimp [iterV, collectAll]

theorem iterV_domain (ctx : Ctx) (d : String) (s : RS) :
    (runR (iterV ctx (.domain d)) s).1 = .ok (statesOf ctx (some d)) ∧
      d ∈ (runR (iterV ctx (.domain d)) s).2.info.domains := by
  rsimp [iterV, collectDomain]

/-- `list(states.<domain>)` also records the lifecycle listener (CPython
asks for a length hint first). -/
theorem iterVList_domain (ctx : Ctx) (d : String) (s : RS) :
    (runR (iterVList ctx (.domain d)) s).1 = .ok (statesOf ctx (some d)) ∧
      d ∈ (runR (iterVList ctx (.domain d)) s).2.info.domains ∧
      d ∈ (runR (iterVList ctx (.domain d)) s).2.info.domainsLifecycle := by
  rsimp [iterVList, iterV, collectDomain]

/-- For a plain list `list(x)` is just iteration. -/
theorem iterVList_list (ctx : Ctx) (xs : List Value) (s : RS) :
    runR (iterVList ctx (.list xs)) s = (.ok xs, s) := rfl

/-- `x in <Undefined>` is False. -/
theorem containsV_undef (ctx : Ctx) (n : String) (x : Value) (s : RS) :
    runR (containsV ctx (.undef n) x) s = (.ok false, s) := rfl

/-- `x in <list>`: some item equals `x`. -/
theorem containsV_list (ctx : Ctx) (xs : List Value) (x : Value) (s : RS) :
    runR (containsV ctx (.list xs) x) s = (.ok (xs.any (pyEq · x)), s) := rfl

/-- `x in <dict>`: `x` is a key. -/
theorem containsV_dict (ctx : Ctx) (kvs : List (Value × Value)) (x : Value) (s : RS) :
    runR (containsV ctx (.dict kvs) x) s = (.ok (lookupKV kvs x).isSome, s) := rfl

/-- `"" in s` is True for every string, and `1 in "abc"` is a `TypeError`. -/
theorem containsV_str (ctx : Ctx) (t : String) (i : Int) (s : RS) :
    runR (containsV ctx (.str t) (.str "")) s = (.ok true, s) ∧
      ∃ e, runR (containsV ctx (.str t) (.int i)) s = (.error e, s) := by
  refine ⟨?_, _, rfl⟩
  rsimp [containsV]

/-! ## Item access -/

/-- Indexing a list by an int never raises: out of range is Undefined (as
in Jinja), in range is Python's `xs[i]`. -/
theorem getitemV_list (ctx : Ctx) (xs : List Value) (i : Int) (s : RS) :
    runR (getitemV ctx (.list xs) (.int i)) s =
      (.ok ((seqIndex xs i).getD (.undef "list index out of range")), s) := rfl

/-- A dict key that is present is returned. -/
theorem getitemV_dict (ctx : Ctx) (kvs : List (Value × Value)) (k x : Value) (s : RS)
    (h : lookupKV kvs k = some x) : runR (getitemV ctx (.dict kvs) k) s = (.ok x, s) := by
  rsimp [getitemV, h]

/-- `None[k]` is Undefined, and subscripting an Undefined raises. -/
theorem getitemV_none (ctx : Ctx) (k : Value) (n : String) (s : RS) :
    runR (getitemV ctx .none k) s = (.ok (.undef "'None' is not subscriptable"), s) ∧
      ∃ e, runR (getitemV ctx (.undef n) k) s = (.error e, s) := ⟨rfl, _, rfl⟩

/-- An empty attribute path is the item itself. -/
theorem attrPath_nil (ctx : Ctx) (x : Value) (d : Option Value) (s : RS) :
    runR (attrPath ctx x [] d) s = (.ok x, s) := rfl

/-- No attribute (`None`) means no path; a non-string attribute (an int
index) is a single part. -/
theorem attrParts_cases (i : Int) (s : RS) :
    runR (attrParts .none) s = (.ok [], s) ∧ runR (attrParts (.int i)) s = (.ok [.int i], s) :=
  ⟨rfl, rfl⟩

/-- `ignore_case` only touches strings. -/
theorem ignoreCase_nonstr (v : Value) (s : RS) (h : ∀ t, v ≠ .str t) :
    runR (ignoreCase v) s = (.ok v, s) := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- A case-sensitive sort key is the attribute lookup itself. -/
theorem sortKey_caseSensitive (ctx : Ctx) (parts : List Value) (x : Value) (s : RS) :
    runR (sortKey ctx parts true x) s = runR (attrPath ctx x parts) s := by
  rsimp [sortKey]
  cases attrPath ctx x parts none s with
  | mk a s' => cases a <;> rfl

/-- `min`/`max` of an empty sequence is Undefined (Jinja's
`environment.undefined("No aggregated item, sequence was empty.")`). -/
theorem minOrMax_empty (ctx : Ctx) (isMax cs : Bool) (attr : Value) (s : RS) :
    runR (minOrMax ctx isMax [] cs attr) s =
      (.ok (.undef "No aggregated item, sequence was empty."), s) := rfl

/-! ## Arguments -/

/-- A positional argument wins; a keyword is used only past the positionals. -/
theorem Args_get_pos (a : Args) (i : Nat) (k : String) (h : i < a.pos.length) :
    a.get i k = some a.pos[i] := by
  simp [Args.get, List.getElem?_eq_getElem h]

theorem Args_get_kw (a : Args) (i : Nat) (k : String) (h : a.pos.length ≤ i) :
    a.get i k = (a.kw.find? (·.1 == k)).map (·.2) := by
  simp [Args.get, List.getElem?_eq_none h]

/-- A keyword argument that is returned was passed under that name. -/
theorem Args_get_kw_mem (a : Args) (i : Nat) (k : String) (v : Value)
    (h : a.pos.length ≤ i) (hg : a.get i k = some v) : (k, v) ∈ a.kw := by
  rw [Args_get_kw a i k h] at hg
  simp only [Option.map_eq_some_iff] at hg
  obtain ⟨⟨k', v'⟩, hf, rfl⟩ := hg
  have h1 := List.mem_of_find?_eq_some hf
  have h2 := List.find?_some hf
  simp at h2
  rw [← h2]; exact h1

/-- `needStr` accepts exactly strings. -/
theorem needStr_iff (fn : String) (v : Value) (t : String) (s : RS) :
    runR (needStr fn v) s = (.ok t, s) ↔ v = .str t := by
  cases v <;> simp [needStr, runR, pure, ExceptT.pure, ExceptT.run, ExceptT.mk, StateT.pure,
    StateT.run, throw, throwThe, MonadExceptOf.throw]

/-- `asciiOnly` passes exactly for ASCII text, and never changes the state. -/
theorem asciiOnly_iff (fn t : String) (s : RS) :
    runR (asciiOnly fn t) s = (.ok (), s) ↔ ∀ c ∈ t.toList, c.toNat < 128 := by
  unfold asciiOnly
  split
  · rename_i h
    simp only [List.all_eq_true, decide_eq_true_eq] at h
    exact ⟨fun _ => h, fun _ => rfl⟩
  · rename_i h
    simp only [List.all_eq_true, decide_eq_true_eq] at h
    constructor
    · intro hh; rsimp [id] at hh
    · intro hh; exact absurd hh h

/-! ## `str.split` with a separator -/

/-- `s.split("")` raises `ValueError: empty separator`. -/
theorem pySplit_empty_sep (t : String) (m : Int) (s : RS) :
    runR (pySplit t (some "") m) s = (.error "ValueError: empty separator", s) := rfl

/-- With a separator, a non-negative `maxsplit` bounds the number of parts
by `maxsplit + 1`. -/
theorem pySplit_length_le (t sep : String) (m : Nat) (parts : List String) (s s' : RS)
    (h : runR (pySplit t (some sep) (m : Int)) s = (.ok parts, s')) : parts.length ≤ m + 1 := by
  unfold pySplit at h
  split at h
  · cases h
  · rename_i sp hne heq
    cases heq
    have hneg : ¬ ((m : Int) < 0) := by omega
    by_cases hl : (t.splitOn sep).length ≤ m + 1
    · rsimp [hneg, hl] at h
      rw [← h.1]; exact hl
    · rsimp [hneg, hl] at h
      rw [← h.1]
      simp; omega
  · rename_i hnone; cases hnone

/-- Without a limit, splitting on a separator is `splitOn`. -/
theorem pySplit_unlimited (t sep : String) (m : Int) (s : RS) (hs : sep ≠ "") (hm : m < 0) :
    runR (pySplit t (some sep) m) s = (.ok (t.splitOn sep), s) := by
  unfold pySplit
  split
  · rename_i heq; cases heq; exact absurd rfl hs
  · rename_i sp hne heq
    cases heq
    rsimp [hm]
  · rename_i hnone; cases hnone

/-! ## Dates -/

/-- `as_local` of an aware datetime keeps the instant and moves it to the
engine's offset. -/
theorem asLocal_aware (ctx : Ctx) (us : Int) (off : Int) (s : RS) :
    runR (asLocal ctx (.datetime us (some off))) s =
      (.ok (.datetime us (some ctx.now.tzOffsetSec)), s) := rfl

/-- `as_local` is idempotent on datetimes. -/
theorem asLocal_idem (ctx : Ctx) (us : Int) (off : Option Int) (s : RS) :
    ∃ v, runR (asLocal ctx (.datetime us off)) s = (.ok v, s) ∧
      runR (asLocal ctx v) s = (.ok v, s) := by
  cases off <;> exact ⟨_, rfl, rfl⟩

/-- `as_local` rejects anything that is not a datetime. -/
theorem asLocal_error (ctx : Ctx) (t : String) (s : RS) :
    ∃ e, runR (asLocal ctx (.str t)) s = (.error e, s) := ⟨_, rfl⟩

/-- `checkDate` accepts exactly the datetimes whose (wall-clock) year is in
`1..9999`, Python's `datetime.MINYEAR..MAXYEAR`. -/
theorem checkDate_iff (us : Int) (off : Option Int) (s : RS) :
    runR (checkDate us off) s = (.ok (.datetime us off), s) ↔
      1 ≤ (toCivil (wallOf us off)).year ∧ (toCivil (wallOf us off)).year ≤ 9999 := by
  rsimp [checkDate]
  split
  · rename_i h
    constructor
    · intro hh
      exact absurd (show ((Except.error "OverflowError: date value out of range" :
        Except String Value), s) = (Except.ok (Value.datetime us off), s) from hh) (by simp)
    · intro hh; omega
  · rename_i h
    exact ⟨fun _ => by omega, fun _ => rfl⟩

/-- A naive datetime has no timestamp in HALean (it would depend on the
system time zone), and neither does a non-datetime. -/
theorem timestampOf_error (us : Int) (i : Int) (s : RS) :
    (∃ e, runR (timestampOf (.datetime us none)) s = (.error e, s)) ∧
      (∃ e, runR (timestampOf (.int i)) s = (.error e, s)) := ⟨⟨_, rfl⟩, ⟨_, rfl⟩⟩

/-! ## Arithmetic -/

/-- Integer arithmetic is exact (Python ints are unbounded). -/
theorem arith_int (a b : Int) (s : RS) :
    runR (arith "+" (.int a) (.int b)) s = (.ok (.int (a + b)), s) ∧
    runR (arith "-" (.int a) (.int b)) s = (.ok (.int (a - b)), s) ∧
    runR (arith "*" (.int a) (.int b)) s = (.ok (.int (a * b)), s) := ⟨rfl, rfl, rfl⟩

/-- `//` and `%` on ints are floor division and its remainder, and the two
satisfy Python's identity `a == (a // b) * b + a % b`. -/
theorem arith_int_divmod (a b : Int) (s : RS) (hb : b ≠ 0) :
    runR (arith "//" (.int a) (.int b)) s = (.ok (.int (Int.fdiv a b)), s) ∧
    runR (arith "%" (.int a) (.int b)) s = (.ok (.int (Int.fmod a b)), s) ∧
    a = Int.fdiv a b * b + Int.fmod a b := by
  refine ⟨?_, ?_, ?_⟩
  · rsimp [arith, Value.num?, hb]
  · rsimp [arith, Value.num?, hb]
  · rw [Int.mul_comm]; exact (Int.mul_fdiv_add_fmod a b).symm

/-- Integer division and modulo by zero raise `ZeroDivisionError`. -/
theorem arith_int_div_zero (a : Int) (s : RS) :
    (∃ e, runR (arith "//" (.int a) (.int 0)) s = (.error e, s)) ∧
    (∃ e, runR (arith "%" (.int a) (.int 0)) s = (.error e, s)) ∧
    (∃ e, runR (arith "/" (.int a) (.int 0)) s = (.error e, s)) := ⟨⟨_, rfl⟩, ⟨_, rfl⟩, ⟨_, rfl⟩⟩

/-- `+` concatenates strings and lists. -/
theorem arith_concat (x y : String) (xs ys : List Value) (s : RS) :
    runR (arith "+" (.str x) (.str y)) s = (.ok (.str (x ++ y)), s) ∧
    runR (arith "+" (.list xs) (.list ys)) s = (.ok (.list (xs ++ ys)), s) := ⟨rfl, rfl⟩

/-- Any arithmetic with an Undefined operand raises. -/
theorem arith_undef (op n : String) (b : Value) (s : RS) :
    ∃ e, runR (arith op (.undef n) b) s = (.error e, s) := ⟨_, rfl⟩

/-- Timedeltas add and subtract exactly; two aware datetimes subtract to
the timedelta between their instants. -/
theorem arith_timedelta (x y : Int) (o1 o2 : Int) (s : RS) :
    runR (arith "+" (.timedelta x) (.timedelta y)) s = (.ok (.timedelta (x + y)), s) ∧
    runR (arith "-" (.timedelta x) (.timedelta y)) s = (.ok (.timedelta (x - y)), s) ∧
    runR (arith "-" (.datetime x (some o1)) (.datetime y (some o2))) s =
      (.ok (.timedelta (x - y)), s) := ⟨rfl, rfl, rfl⟩

/-- Mixing naive and aware datetimes in a subtraction is a `TypeError`. -/
theorem arith_naive_aware (x y o : Int) (s : RS) :
    ∃ e, runR (arith "-" (.datetime x none) (.datetime y (some o))) s = (.error e, s) :=
  ⟨_, rfl⟩

/-! ## Comparisons -/

/-- `!=` is the negation of `==`. -/
theorem cmpOp_ne (ctx : Ctx) (a b : Value) (s : RS) :
    (runR (cmpOp ctx "!=" a b) s).1 = (runR (cmpOp ctx "==" a b) s).1.map (!·) := by
  cases a <;> cases b <;> rfl

/-- `not in` is the negation of `in`. -/
theorem cmpOp_notin (ctx : Ctx) (a : Value) (xs : List Value) (s : RS) (h : ∀ w, a ≠ .opaque w) :
    runR (cmpOp ctx "notin" a (.list xs)) s = (.ok (!(xs.any (pyEq · a))), s) ∧
      runR (cmpOp ctx "in" a (.list xs)) s = (.ok (xs.any (pyEq · a)), s) := by
  constructor <;> cases a <;> first | rfl | exact absurd rfl (h _)

/-- Comparing with an unmodelled object raises instead of guessing. -/
theorem cmpOp_opaque (ctx : Ctx) (op w : String) (b : Value) (s : RS) :
    ∃ e, runR (cmpOp ctx op (.opaque w) b) s = (.error e, s) := ⟨_, rfl⟩

/-! ## More edge cases -/

/-- With no keyword arguments, `Args.check` passes exactly when there are
not too many positional ones. -/
theorem Args_check_pos (pos : List Value) (fn : String) (names : List String) (s : RS) :
    runR (Args.check ⟨pos, []⟩ fn names) s = (.ok (), s) ↔ pos.length ≤ names.length := by
  by_cases h : pos.length ≤ names.length
  · have h' : ¬ (names.length < pos.length) := by omega
    simp only [h, iff_true]
    rsimp [Args.check, h']
  · have h' : names.length < pos.length := by omega
    simp only [h, iff_false]
    rsimp [Args.check, h']

/-- The strict check agrees with the plain one when there are no keywords. -/
theorem Args_checkStrict_pos (pos : List Value) (fn : String) (names : List String) (s : RS)
    (h : pos.length ≤ names.length) : runR (Args.checkStrict ⟨pos, []⟩ fn names) s = (.ok (), s) := by
  have h' : ¬ (names.length < pos.length) := by omega
  rsimp [Args.checkStrict, Args.check, h']

/-- Sorting nothing gives an empty list; `unique` of nothing an empty
generator. -/
theorem doSort_nil (ctx : Ctx) (rev cs : Bool) (s : RS) :
    runR (doSort ctx [] rev cs .none) s = (.ok (.list []), s) := by
  rsimp [doSort, attrParts]

theorem doUnique_nil (ctx : Ctx) (cs : Bool) (s : RS) :
    runR (doUnique ctx [] cs .none) s = (.ok (.gen "generator" []), s) := rfl

/-- `relative_time` & co. return a non-datetime input unchanged, and still
mark the template as time-dependent. -/
theorem datetimeAsString_passthrough (ctx : Ctx) (t : String) (p : Value) (future : Bool) (s : RS) :
    runR (datetimeAsString ctx (.str t) p future) s =
      (.ok (.str t), { s with info := { s.info with hasTime := true } }) := rfl

/-- Rounding leaves NaN and the infinities alone. -/
theorem pyRound_nonfinite (f : Float) (n : Int) (h : Float.isFinite' f = false) : pyRound f n = f := by
  simp [pyRound, h]

/-- `round` with a precision that is not an int raises. -/
theorem forgivingRound_bad_precision (v : Value) (p : String) (m d : Option Value) (s : RS) :
    ∃ e, runR (forgivingRound v (some (.str p)) m d) s = (.error e, s) := ⟨_, rfl⟩

/-- Reading `state` from a collecting state object returns the state string
and records the entity. -/
theorem stateAttr_state (st : EntityState) (s : RS) :
    (runR (stateAttr st true "state") s).1 = .ok (.str st.state) ∧
      st.entityId ∈ (runR (stateAttr st true "state") s).2.info.entities := by
  have hc := collect_mem st.entityId s
  have hm : "state" ∈ COLLECTABLE_STATE_ATTRIBUTES := by simp [COLLECTABLE_STATE_ATTRIBUTES]
  rsimp [stateAttr, hm] at hc ⊢
  cases hx : collect st.entityId s with
  | mk a s' => rw [hx] at hc; dsimp only at hc; obtain ⟨rfl, hm'⟩ := hc; rsimp [hm']

/-- A non-collecting state object (an iterated state, `trigger.to_state`)
records nothing. -/
theorem stateAttr_no_collect (st : EntityState) (s : RS) :
    runR (stateAttr st false "state") s = (.ok (.str st.state), s) := rfl

end HALean.Template
