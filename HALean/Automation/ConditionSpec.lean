/-
  Specs for condition evaluation (`HALean/Automation/Condition.lean`,
  upstream `homeassistant/helpers/condition.py`).

  The main results are exact characterisations of the three combinators
  (`and` / `or` / `not`), of the two condition-list checkers the automation
  and the script runner use, of the entity loop shared by the `state` and
  `numeric_state` conditions, and of the `time` condition on fixed bounds.
-/
import HALean.Automation.Condition
open Lean

set_option linter.unusedSimpArgs false
set_option linter.deprecated false

namespace HALean.Automation

/-! ### `setVar` (`ScriptRunVariables.assign`) -/

/-- Replace the entry for `k`, leave the others. -/
private def upd (k : String) (v : Template.Value) (p : String × Template.Value) :
    String × Template.Value := if p.1 == k then (k, v) else p

private theorem setVar_eq (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    setVar vs k v = if vs.any (·.1 == k) then vs.map (upd k v) else vs ++ [(k, v)] := by
  unfold setVar
  have : (fun (x : String × Template.Value) =>
      match x with | (k', v') => if k' == k then (k, v) else (k', v')) = upd k v := by
    funext ⟨a, b⟩; rfl
  rw [this]

private theorem upd_fst (k : String) (v : Template.Value) (p : String × Template.Value) :
    (upd k v p).1 = p.1 := by
  unfold upd
  by_cases e : p.1 == k
  · simp only [e, ite_true]; exact (beq_iff_eq.mp e).symm
  · simp [e]

private theorem any_iff_mem (vs : List (String × Template.Value)) (k : String) :
    vs.any (·.1 == k) = true ↔ k ∈ vs.map (·.1) := by
  simp only [List.any_eq_true, beq_iff_eq, List.mem_map]

/-- The keys after an assignment: unchanged (and in the same order) when the
key exists, else the key is added at the end. -/
theorem setVar_keys (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    (setVar vs k v).map (·.1) = if k ∈ vs.map (·.1) then vs.map (·.1) else vs.map (·.1) ++ [k] := by
  rw [setVar_eq]
  by_cases h : vs.any (·.1 == k) = true
  · rw [if_pos h, if_pos ((any_iff_mem vs k).mp h), List.map_map]
    apply List.map_congr_left
    intro a _
    exact upd_fst k v a
  · rw [if_neg h, if_neg (fun hm => h ((any_iff_mem vs k).mpr hm))]
    simp

/-- An assignment never removes a variable and adds at most one. -/
theorem setVar_length (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    (setVar vs k v).length = if k ∈ vs.map (·.1) then vs.length else vs.length + 1 := by
  have h := congrArg List.length (setVar_keys vs k v)
  rw [List.length_map] at h
  rw [h]; split <;> simp

private theorem find_upd_self (k : String) (v : Template.Value) :
    ∀ (l : List (String × Template.Value)), l.any (·.1 == k) = true →
      (l.map (upd k v)).find? (·.1 == k) = some (k, v)
  | [], h => by simp at h
  | a :: l, h => by
    rw [List.map_cons, List.find?_cons]
    by_cases e : a.1 == k
    · have : upd k v a = (k, v) := by simp [upd, e]
      rw [this]; simp
    · have h1 : upd k v a = a := by simp [upd, e]
      have h2 : (a.1 == k) = false := by simpa using e
      rw [h1, h2]
      rw [List.any_cons, h2, Bool.false_or] at h
      exact find_upd_self k v l h

/-- Reading back the assigned variable gives the assigned value. -/
theorem setVar_find_self (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    (setVar vs k v).find? (·.1 == k) = some (k, v) := by
  rw [setVar_eq]
  by_cases h : vs.any (·.1 == k) = true
  · rw [if_pos h]; exact find_upd_self k v vs h
  · rw [if_neg h, List.find?_append]
    have : vs.find? (·.1 == k) = none := by
      rw [List.find?_eq_none]
      intro x hx hxk
      exact h (List.any_eq_true.mpr ⟨x, hx, hxk⟩)
    rw [this]; simp

private theorem find_upd_other (k k' : String) (v : Template.Value) (hne : k' ≠ k) :
    ∀ (l : List (String × Template.Value)),
      (l.map (upd k v)).find? (·.1 == k') = l.find? (·.1 == k')
  | [] => rfl
  | a :: l => by
    rw [List.map_cons, List.find?_cons, List.find?_cons, upd_fst, find_upd_other k k' v hne l]
    by_cases e : a.1 == k
    · have : (a.1 == k') = false := by
        rw [beq_iff_eq.mp e]; simpa using Ne.symm hne
      rw [this]
    · have h1 : upd k v a = a := by simp [upd, e]
      rw [h1]

/-- An assignment does not change any other variable. -/
theorem setVar_find_other (vs : List (String × Template.Value)) (k k' : String) (v : Template.Value)
    (hne : k' ≠ k) :
    (setVar vs k v).find? (·.1 == k') = vs.find? (·.1 == k') := by
  rw [setVar_eq]
  split
  · exact find_upd_other k k' v hne vs
  · rw [List.find?_append]
    have : ((k, v).1 == k') = false := by simpa using Ne.symm hne
    simp [List.find?_cons, this]

/-- Assigning the same value twice is the same as assigning it once. -/
theorem setVar_idem (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    setVar (setVar vs k v) k v = setVar vs k v := by
  have hin : (setVar vs k v).any (·.1 == k) = true := by
    have := setVar_find_self vs k v
    exact List.any_eq_true.mpr ⟨(k, v), List.mem_of_find?_eq_some this, by simp⟩
  rw [setVar_eq (setVar vs k v), if_pos hin]
  have hupd : ∀ p, upd k v (upd k v p) = upd k v p := by
    intro p
    by_cases e : p.1 == k <;> simp [upd, e]
  rw [setVar_eq]
  split
  · rw [List.map_map]
    apply List.map_congr_left
    intro a _; exact hupd a
  · rename_i hh
    rw [List.map_append]
    have h1 : [(k, v)].map (upd k v) = [(k, v)] := by simp [upd]
    rw [h1]
    congr 1
    conv => rhs; rw [← List.map_id vs]
    apply List.map_congr_left
    intro a ha
    have : ¬ (a.1 == k) = true := fun e => hh (List.any_eq_true.mpr ⟨a, ha, e⟩)
    simp [upd, this]

/-! ### `templateCond` (`condition.async_template`) -/

/-- A template condition holds exactly when the template renders to text
that is `true` in any letter case. -/
theorem templateCond_true_iff (env : CondEnv) (t : Template.Tmpl) :
    templateCond env t = .ok true ↔
      ∃ s, Template.render t env.tmplCtx false = .ok (.str s) ∧ s.toLower = "true" := by
  unfold templateCond
  split
  · rename_i s h
    simp [h]
  · rename_i v hn h
    simp only [Except.ok.injEq, Bool.false_eq_true, false_iff]
    rintro ⟨s, hs, _⟩
    rw [h] at hs
    injection hs with hs
    exact hn s hs
  · rename_i e h
    simp [h]

/-- It raises a `ConditionError` exactly when rendering raises. -/
theorem templateCond_error_iff (env : CondEnv) (t : Template.Tmpl) (m : String) :
    templateCond env t = .error m ↔
      ∃ e, Template.render t env.tmplCtx false = .error e ∧
        m = s!"Error in 'template' condition: {e}" := by
  unfold templateCond
  split
  · rename_i s h; simp [h]
  · rename_i v hn h; simp [h]
  · rename_i e h
    simp only [h, Except.error.injEq]
    constructor
    · intro hm; exact ⟨e, rfl, hm.symm⟩
    · rintro ⟨e', he, hm⟩; rw [hm, he]

/-! ### `renderVariables` (`ScriptVariables.async_render`) -/

/-- Rendering variables keeps the run variables that already exist, in
place: the result extends them. -/
theorem renderVariables_prefix (env : CondEnv) (defs : List (String × Complex))
    (vs : List (String × Template.Value)) (h : renderVariables env defs = .ok vs) :
    env.vars <+: vs := by
  unfold renderVariables at h
  generalize env.vars = init at h
  induction defs generalizing init with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at h
    subst h; exact List.prefix_refl _
  | cons d defs ih =>
    obtain ⟨k, c⟩ := d
    simp only [List.foldlM_cons, bind, Except.bind] at h
    split at h
    · exact absurd h (by simp)
    · rename_i x w hw
      have hpre : init <+: w := by
        split at hw
        · simp only [pure, Except.pure, Except.ok.injEq] at hw
          subst hw; exact List.prefix_refl _
        · split at hw
          · exact absurd hw (by simp)
          · simp only [pure, Except.pure, Except.ok.injEq] at hw
            subst hw; exact List.prefix_append _ _
      exact List.IsPrefix.trans hpre (ih w h)

/-- Every defined variable is set after a successful render. -/
theorem renderVariables_defines (env : CondEnv) (defs : List (String × Complex))
    (vs : List (String × Template.Value)) (h : renderVariables env defs = .ok vs)
    (k : String) (hk : k ∈ defs.map (·.1)) : k ∈ vs.map (·.1) := by
  unfold renderVariables at h
  generalize env.vars = init at h
  induction defs generalizing init with
  | nil => simp at hk
  | cons d defs ih =>
    obtain ⟨k0, c⟩ := d
    simp only [List.foldlM_cons, bind, Except.bind] at h
    split at h
    · exact absurd h (by simp)
    · rename_i x w hw
      simp only [List.map_cons, List.mem_cons] at hk
      rcases hk with rfl | hk
      · -- the key is in `w`, and `w` is a prefix of `vs`
        have hin : k ∈ w.map (·.1) := by
          split at hw
          · rename_i hany
            simp only [pure, Except.pure, Except.ok.injEq] at hw
            subst hw
            simp only [List.any_eq_true, beq_iff_eq] at hany
            obtain ⟨y, hy, rfl⟩ := hany
            exact List.mem_map_of_mem hy
          · split at hw
            · exact absurd hw (by simp)
            · simp only [pure, Except.pure, Except.ok.injEq] at hw
              subst hw; simp
        have hpre : w <+: vs := by
          have := renderVariables_prefix { env with vars := w } defs vs
            (by unfold renderVariables; exact h)
          exact this
        obtain ⟨t, rfl⟩ := hpre
        simp only [List.map_append, List.mem_append]
        exact Or.inl hin
      · exact ih hk w h

/-- Without definitions the run variables are returned as they are. -/
theorem renderVariables_nil (env : CondEnv) : renderVariables env [] = .ok env.vars := rfl

/-! ### `normalizeTarget` -/

/-- A rendered target that is not a mapping is rejected. -/
theorem normalizeTarget_not_obj (j : Json) (h : ∀ kvs, j ≠ .obj kvs) :
    normalizeTarget j = .error "Error rendering service target template: not a mapping" := by
  unfold normalizeTarget
  cases j <;> first | rfl | exact absurd rfl (h _)

/-- A target without `entity_id` is passed through unchanged. -/
theorem normalizeTarget_no_entity_id (j : Json) (kvs) (hj : j = .obj kvs)
    (h : field? j "entity_id" = none) : normalizeTarget j = .ok j := by
  subst hj
  unfold normalizeTarget
  simp only [h]
  rfl

/-! ### `isInputEntityId` (`cv.INPUT_ENTITY_ID`) -/

/-- What the regex demands of the two halves of an input entity id. -/
theorem isInputEntityId_parts (s : String) (h : isInputEntityId s = true) :
    ∃ dom obj, s.splitOn "." = [dom, obj] ∧
      dom ∈ ["input_select", "input_text", "input_number", "input_boolean", "input_datetime"] ∧
      obj ≠ "" ∧ obj.startsWith "_" = false ∧ obj.endsWith "_" = false ∧
      (obj.splitOn "__").length = 1 ∧
      obj.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'z') || c == '_') = true := by
  unfold isInputEntityId at h
  split at h
  · rename_i dom obj hs
    simp only [Bool.and_eq_true, List.contains_iff_mem, Bool.not_eq_true', beq_iff_eq,
      String.isEmpty_iff] at h
    obtain ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩ := h
    exact ⟨dom, obj, hs, h1, (by intro e; rw [e] at h2; simp at h2), h4, h5, h6, h3⟩
  · exact absurd h (by simp)

/-! ### `stateOne`, `resolveBound`, `numericStateOf`, `numericStateOne` -/

/-- A `state` condition on an entity that does not exist raises. -/
theorem stateOne_unknown (env : CondEnv) (eid : String) (req : List Json) (forMs : Option Nat)
    (attr : Option String) (h : env.states.get? eid = none) :
    stateOne env eid req forMs attr = .error s!"unknown entity {eid}" := by
  simp [stateOne, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- A literal bound resolves to itself. -/
theorem resolveBound_num (env : CondEnv) (which : String) (v : Float) :
    resolveBound env which (.num v) = .ok (some v) := rfl

/-- An entity bound whose entity does not exist raises. -/
theorem resolveBound_unknown (env : CondEnv) (which e : String) (h : env.states.get? e = none) :
    resolveBound env which (.entity e) = .error s!"unknown '{which}' entity {e}" := by
  simp [resolveBound, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- An entity bound whose entity is unavailable or unknown gives no number
(the condition is then false rather than an error). -/
theorem resolveBound_unavailable (env : CondEnv) (which e : String) (be : EntityState)
    (h : env.states.get? e = some be)
    (hs : be.state = STATE_UNAVAILABLE ∨ be.state = STATE_UNKNOWN) :
    resolveBound env which (.entity e) = .ok none := by
  have : (be.state == STATE_UNAVAILABLE || be.state == STATE_UNKNOWN) = true := by
    rcases hs with hs | hs <;> simp [hs]
  simp [resolveBound, h, this, bind, Except.bind, pure, Except.pure]

/-- An entity bound resolves to a number only if the entity's state parses
as that number. -/
theorem resolveBound_entity_some (env : CondEnv) (which e : String) (f : Float)
    (h : resolveBound env which (.entity e) = .ok (some f)) :
    ∃ be, env.states.get? e = some be ∧ parsePyFloatStr be.state = some f := by
  unfold resolveBound at h
  cases hg : env.states.get? e with
  | none => simp [hg, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at h
  | some be =>
    refine ⟨be, rfl, ?_⟩
    simp only [hg, bind, Except.bind, pure, Except.pure] at h
    split at h
    · simp at h
    · split at h
      · rename_i f' hf
        simp only [Except.ok.injEq, Option.some.injEq] at h
        rw [hf, h]
      · simp [throw, throwThe, MonadExceptOf.throw] at h

/-- `float()` of a template value fails on `None`. -/
theorem pyFloatV_none : pyFloatV .none = none := rfl

/-- `float()` of a number or a boolean always succeeds. -/
theorem pyFloatV_number (f : Float) (i : Int) (b : Bool) :
    (pyFloatV (.float f)).isSome ∧ (pyFloatV (.int i)).isSome ∧ (pyFloatV (.bool b)).isSome :=
  ⟨rfl, rfl, rfl⟩

/-- `numeric_state` on a missing attribute is false, whatever the bounds. -/
theorem numericStateOf_missing_attr (env : CondEnv) (ent : EntityState) (below above : Option Bound)
    (a : String) (vt : ValueTmpl) (h : ent.hasAttr a = false) :
    numericStateOf env ent below above (some a) vt = .ok false := by
  simp [numericStateOf, h, bind, Except.bind, pure, Except.pure]

/-- `numeric_state` on an entity that does not exist raises. -/
theorem numericStateOne_unknown (env : CondEnv) (eid : String) (below above : Option Bound)
    (attr : Option String) (vt : ValueTmpl) (h : env.states.get? eid = none) :
    numericStateOne env eid below above attr vt = .error s!"unknown entity {eid}" := by
  simp [numericStateOne, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- For an entity that exists, the condition is decided by its state alone. -/
theorem numericStateOne_known (env : CondEnv) (eid : String) (below above : Option Bound)
    (attr : Option String) (vt : ValueTmpl) (ent : EntityState) (h : env.states.get? eid = some ent) :
    numericStateOne env eid below above attr vt = numericStateOf env ent below above attr vt := by
  simp [numericStateOne, h, bind, Except.bind]

/-! ### `resolveTimeBound`, `timeCond` (`conditions.time`) -/

/-- A time bound naming an entity that does not exist raises. -/
theorem resolveTimeBound_unknown (env : CondEnv) (which eid : String) (isAfter : Bool)
    (h : env.states.get? eid = none) :
    resolveTimeBound env which eid isAfter = .error s!"unknown '{which}' entity {eid}" := by
  simp [resolveTimeBound, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- The local time of day is always within one day. -/
theorem timeOfDay_lt (t : Instant) : t.timeOfDay < 86400000 := by
  unfold Instant.timeOfDay msPerDay
  have h1 := Int.emod_nonneg t.localMillis (b := 86400000) (by decide)
  have h2 := Int.emod_lt_of_pos t.localMillis (b := 86400000) (by decide)
  omega

/-- The `time` condition on fixed bounds: with `after < before` the window
is `[after, before)`; otherwise it wraps around midnight and only
`[before, after)` is excluded. -/
theorem timeCond_fixed (env : CondEnv) (b a : Nat) :
    timeCond env (some (.fixed b)) (some (.fixed a)) none =
      .ok (if a < b then decide (a ≤ env.now.timeOfDay * 1000 ∧ env.now.timeOfDay * 1000 < b)
           else !decide (b ≤ env.now.timeOfDay * 1000 ∧ env.now.timeOfDay * 1000 < a)) := by
  unfold timeCond
  simp only [bind, Except.bind, pure, Except.pure]
  by_cases hab : a < b
  · by_cases h1 : a ≤ env.now.timeOfDay * 1000 <;> by_cases h2 : env.now.timeOfDay * 1000 < b <;>
      simp [hab, h1, h2]
  · by_cases h1 : b ≤ env.now.timeOfDay * 1000 <;> by_cases h2 : env.now.timeOfDay * 1000 < a <;>
      simp [hab, h1, h2]

/-- A `time` condition with only `weekday` holds exactly on those days. -/
theorem timeCond_weekday (env : CondEnv) (wd : List String) :
    timeCond env none none (some wd) = .ok (wd.contains env.now.weekday) := by
  have h := timeOfDay_lt env.now
  have h2 : env.now.timeOfDay * 1000 < 86399999999 := by omega
  unfold timeCond
  simp only [bind, Except.bind, pure, Except.pure]
  cases hc : wd.contains env.now.weekday <;> simp [h2, hc]

/-- A `time` condition with nothing set always holds. -/
theorem timeCond_unbounded (env : CondEnv) : timeCond env none none none = .ok true := by
  have h := timeOfDay_lt env.now
  have h2 : env.now.timeOfDay * 1000 < 86399999999 := by omega
  unfold timeCond
  simp [bind, Except.bind, pure, Except.pure, h2]

/-- A weekday outside the list makes the condition false whatever the
fixed bounds are. -/
theorem timeCond_wrong_weekday (env : CondEnv) (b a : Nat) (wd : List String)
    (h0 : wd.contains env.now.weekday = false) :
    timeCond env (some (.fixed b)) (some (.fixed a)) (some wd) = .ok false := by
  have h : env.now.weekday ∉ wd := by simpa using h0
  unfold timeCond
  simp only [bind, Except.bind, pure, Except.pure]
  by_cases hab : a < b
  · by_cases h1 : a ≤ env.now.timeOfDay * 1000 <;> by_cases h2 : env.now.timeOfDay * 1000 < b <;>
      simp [hab, h1, h2, h]
  · by_cases h1 : b ≤ env.now.timeOfDay * 1000 <;> by_cases h2 : env.now.timeOfDay * 1000 < a <;>
      simp [hab, h1, h2, h]

/-! ### `entityLoop` (`if_state` / `if_numeric_state`) -/

/-- The loop as a recursion over the entities: `errs` are the errors so
far, `res` the result so far. -/
def entityLoopSpec (check : String → Except String Bool) (matchAny : Bool) :
    List String → List String → Bool → CondResult
  | [], errs, res => if errs.isEmpty then .ok (some res) else .err (String.intercalate "; " errs)
  | e :: es, errs, res =>
    match check e with
    | .ok true => entityLoopSpec check matchAny es errs true
    | .ok false => if matchAny then entityLoopSpec check matchAny es errs res else .ok (some false)
    | .error m => entityLoopSpec check matchAny es (errs ++ [m]) res

/-- The same loop as `entityLoop`, started from any state. -/
private def entityLoopFrom (eids : List String) (check : String → Except String Bool)
    (matchAny : Bool) (errors0 : List String) (result0 : Bool) : CondResult := Id.run do
  let mut errors : List String := errors0
  let mut result := result0
  for eid in eids do
    match check eid with
    | .ok true => result := true
    | .ok false => if !matchAny then return .ok (some false)
    | .error e => errors := errors ++ [e]
  if !errors.isEmpty then return .err (String.intercalate "; " errors)
  return .ok (some result)

private theorem entityLoopFrom_eq (eids : List String) (check : String → Except String Bool)
    (matchAny : Bool) (errs : List String) (res : Bool) :
    entityLoopFrom eids check matchAny errs res = entityLoopSpec check matchAny eids errs res := by
  induction eids generalizing errs res with
  | nil =>
    unfold entityLoopFrom entityLoopSpec
    cases errs <;> rfl
  | cons e es ih =>
    have ih1 := ih
    unfold entityLoopFrom at ih1 ⊢
    unfold entityLoopSpec
    simp only [List.forIn_cons, Id.run] at ih1 ⊢
    cases hc : check e with
    | error m => simpa [hc] using ih1 (errs ++ [m]) res
    | ok b =>
      cases b with
      | true => simpa [hc] using ih1 errs true
      | false =>
        cases matchAny with
        | true => simpa [hc] using ih1 errs res
        | false => first | rfl | simp [hc, pure]

/-- `entityLoop` is the recursion `entityLoopSpec`. -/
theorem entityLoop_eq_spec (eids : List String) (check : String → Except String Bool)
    (matchAny : Bool) :
    entityLoop eids check matchAny = entityLoopSpec check matchAny eids [] (!matchAny) :=
  entityLoopFrom_eq eids check matchAny [] (!matchAny)

private theorem entityLoopSpec_all (check : String → Except String Bool) (eids errs : List String) :
    entityLoopSpec check false eids errs true = .ok (some false) ↔
      ∃ e ∈ eids, check e = .ok false := by
  induction eids generalizing errs with
  | nil =>
    unfold entityLoopSpec
    cases errs <;> simp
  | cons e es ih =>
    unfold entityLoopSpec
    cases hc : check e with
    | error m => simp [hc, ih]
    | ok b => cases b <;> simp [hc, ih]

/-- Match-all (`state` without `match: any`, and `numeric_state`): the
condition is false exactly when some entity's check is false, even if other
entities raised. -/
theorem entityLoop_all_false_iff (eids : List String) (check : String → Except String Bool) :
    entityLoop eids check false = .ok (some false) ↔ ∃ e ∈ eids, check e = .ok false := by
  rw [entityLoop_eq_spec]; exact entityLoopSpec_all check eids []

private theorem entityLoopSpec_all_true (check : String → Except String Bool)
    (eids errs : List String) :
    entityLoopSpec check false eids errs true = .ok (some true) ↔
      errs = [] ∧ ∀ e ∈ eids, check e = .ok true := by
  induction eids generalizing errs with
  | nil =>
    unfold entityLoopSpec
    cases errs <;> simp
  | cons e es ih =>
    unfold entityLoopSpec
    cases hc : check e with
    | error m => simp [hc, ih]
    | ok b => cases b <;> simp [hc, ih]

/-- Match-all: the condition is true exactly when every entity's check is
true (an empty entity list is true). -/
theorem entityLoop_all_true_iff (eids : List String) (check : String → Except String Bool) :
    entityLoop eids check false = .ok (some true) ↔ ∀ e ∈ eids, check e = .ok true := by
  rw [entityLoop_eq_spec]
  have := entityLoopSpec_all_true check eids []
  simpa using this

private theorem entityLoopSpec_any_true (check : String → Except String Bool)
    (eids errs : List String) (res : Bool) :
    entityLoopSpec check true eids errs res = .ok (some true) ↔
      (errs = [] ∧ ∀ e ∈ eids, ∃ b, check e = .ok b) ∧
        (res = true ∨ ∃ e ∈ eids, check e = .ok true) := by
  induction eids generalizing errs res with
  | nil =>
    unfold entityLoopSpec
    cases errs <;> simp
  | cons e es ih =>
    unfold entityLoopSpec
    cases hc : check e with
    | error m => simp [hc, ih]
    | ok b => cases b <;> simp [hc, ih]

/-- `match: any`: the condition is true exactly when no check raised and
some entity's check is true. -/
theorem entityLoop_any_true_iff (eids : List String) (check : String → Except String Bool) :
    entityLoop eids check true = .ok (some true) ↔
      (∀ e ∈ eids, ∃ b, check e = .ok b) ∧ ∃ e ∈ eids, check e = .ok true := by
  rw [entityLoop_eq_spec, entityLoopSpec_any_true]; simp

/-- The loop never returns `None`. -/
theorem entityLoop_ne_none (eids : List String) (check : String → Except String Bool)
    (matchAny : Bool) : entityLoop eids check matchAny ≠ .ok none := by
  rw [entityLoop_eq_spec]
  generalize ([] : List String) = errs
  generalize (!matchAny) = res
  induction eids generalizing errs res with
  | nil => unfold entityLoopSpec; split <;> simp
  | cons e es ih =>
    unfold entityLoopSpec
    cases hc : check e with
    | error m => simpa [hc] using ih _ _
    | ok b =>
      cases b
      · cases matchAny
        · simp
        · simpa using ih _ _
      · simpa using ih _ _

/-! ### `zoneById`, `zoneCond`, `sunCond` -/

/-- Matching against a zone that does not exist raises. -/
theorem zoneById_unknown_zone (env : CondEnv) (zid eid : String) (h : env.states.get? zid = none) :
    zoneById env zid eid = .error s!"unknown zone {zid}" := by
  simp [zoneById, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- Matching an entity that does not exist raises. -/
theorem zoneById_unknown_entity (env : CondEnv) (zid eid : String) (z : EntityState)
    (hz : env.states.get? zid = some z) (h : env.states.get? eid = none) :
    zoneById env zid eid = .error s!"unknown entity {eid}" := by
  simp [zoneById, hz, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- A `zone` condition without entities is true. -/
theorem zoneCond_no_entities (env : CondEnv) (zones : List String) :
    zoneCond env [] zones = .ok (some true) := by
  simp [zoneCond]

/-- A `zone` condition with entities but no zones is false. -/
theorem zoneCond_no_zones (env : CondEnv) (e : String) (es : List String) :
    zoneCond env (e :: es) [] = .ok (some false) := by
  have key : ∀ (l : List String) (ok : Bool),
      l.foldl (fun (acc : Bool × List String) (_eid : String) => (acc.1 && false, acc.2))
        (ok, ([] : List String)) = (ok && l.isEmpty, []) := by
    intro l
    induction l with
    | nil => intro ok; simp
    | cons a l ih => intro ok; rw [List.foldl_cons, ih]; simp
  unfold zoneCond
  simp only [List.foldl_nil]
  have := key (e :: es) true
  simp only [Bool.and_false] at this ⊢
  simp [this]

/-- The `sun` condition needs HA's location. -/
theorem sunCond_no_location (env : CondEnv) (before after : Option Bool) (bo ao : Int)
    (h : env.location = none) :
    sunCond env before after bo ao = .error "the sun condition needs HA's location" := by
  simp [sunCond, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-! ### `evalCond`: leaf cases -/

/-- A `trigger` condition holds exactly when the run was started by one of
the listed trigger ids. -/
theorem evalCond_trigger_true_iff (env : CondEnv) (ids : List String) :
    evalCond env (.trigger ids) = .ok (some true) ↔ ∃ t, env.triggerId = some t ∧ t ∈ ids := by
  simp only [evalCond]
  cases env.triggerId <;> simp

/-- A `trigger` condition never raises and never returns `None`. -/
theorem evalCond_trigger_total (env : CondEnv) (ids : List String) :
    ∃ b, evalCond env (.trigger ids) = .ok (some b) := by
  simp [evalCond]

/-- Outside a triggered run (no trigger id) a `trigger` condition is false. -/
theorem evalCond_trigger_no_id (env : CondEnv) (ids : List String) (h : env.triggerId = none) :
    evalCond env (.trigger ids) = .ok (some false) := by
  simp [evalCond, h]

/-- A `template` condition never returns `None`. -/
theorem evalCond_template_ne_none (env : CondEnv) (t : Template.Tmpl) :
    evalCond env (.template t) ≠ .ok none := by
  simp only [evalCond]
  split <;> simp

/-- A `time` condition never returns `None`. -/
theorem evalCond_time_ne_none (env : CondEnv) (b a : Option TimeBound) (wd : Option (List String)) :
    evalCond env (.time b a wd) ≠ .ok none := by
  simp only [evalCond]
  split <;> simp

/-- `state` and `numeric_state` conditions never return `None`. -/
theorem evalCond_state_ne_none (env : CondEnv) (eids : List String) (req : List Json)
    (forMs : Option Nat) (attr : Option String) (matchAny : Bool) :
    evalCond env (.state eids req forMs attr matchAny) ≠ .ok none := by
  simp only [evalCond]
  exact entityLoop_ne_none _ _ _

/-- A `state` condition on no entities: true for match-all, false for
`match: any`. -/
theorem evalCond_state_no_entities (env : CondEnv) (req : List Json) (forMs : Option Nat)
    (attr : Option String) (matchAny : Bool) :
    evalCond env (.state [] req forMs attr matchAny) = .ok (some (!matchAny)) := by
  simp only [evalCond, entityLoop_eq_spec]
  simp [entityLoopSpec]

/-! ### `evalAnd` / `evalOr` / `evalNot` -/

private theorem append_singleton_ne_nil (l : List String) (e : String) : l ++ [e] ≠ [] := by
  simp

/-- `and` is false exactly when one of its conditions is false; errors
raised by other conditions do not hide that. -/
theorem evalAnd_false_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalAnd env cs errs = .ok (some false) ↔ ∃ c ∈ cs, evalCond env c = .ok (some false) := by
  induction cs generalizing errs with
  | nil =>
    simp only [evalAnd]
    split <;> simp
  | cons c cs ih =>
    simp only [evalAnd]
    split
    · rename_i h; simp [h]
    · rename_i r hn h
      rw [ih]
      simp only [List.mem_cons, exists_eq_or_imp]
      constructor
      · intro h'; exact Or.inr h'
      · rintro (h' | h')
        · rw [h] at h'; injection h' with h'; exact absurd h' hn
        · exact h'
    · rename_i e h
      rw [ih]; simp [h]

/-- `and` is true exactly when nothing raised and no condition is false
(a disabled condition, which returns `None`, is skipped). -/
theorem evalAnd_true_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalAnd env cs errs = .ok (some true) ↔
      errs = [] ∧ ∀ c ∈ cs, ∃ r, evalCond env c = .ok r ∧ r ≠ some false := by
  induction cs generalizing errs with
  | nil =>
    simp only [evalAnd]
    cases errs <;> simp
  | cons c cs ih =>
    simp only [evalAnd]
    split
    · rename_i h; simp [h]
    · rename_i r hn h
      rw [ih]
      simp only [List.mem_cons, forall_eq_or_imp]
      constructor
      · rintro ⟨h1, h2⟩
        exact ⟨h1, ⟨r, h, hn⟩, h2⟩
      · rintro ⟨h1, -, h2⟩; exact ⟨h1, h2⟩
    · rename_i e h
      rw [ih]; simp [h]

/-- `and` never returns `None`. -/
theorem evalAnd_ne_none (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalAnd env cs errs ≠ .ok none := by
  induction cs generalizing errs with
  | nil => simp only [evalAnd]; split <;> simp
  | cons c cs ih => simp only [evalAnd]; split <;> simp [ih]

/-- `or` is true exactly when one of its conditions is true; errors raised
by other conditions do not hide that. -/
theorem evalOr_true_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalOr env cs errs = .ok (some true) ↔ ∃ c ∈ cs, evalCond env c = .ok (some true) := by
  induction cs generalizing errs with
  | nil =>
    simp only [evalOr]
    split <;> simp
  | cons c cs ih =>
    simp only [evalOr]
    split
    · rename_i h; simp [h]
    · rename_i r hn h
      rw [ih]
      simp only [List.mem_cons, exists_eq_or_imp]
      constructor
      · intro h'; exact Or.inr h'
      · rintro (h' | h')
        · rw [h] at h'; injection h' with h'; exact absurd h' hn
        · exact h'
    · rename_i e h
      rw [ih]; simp [h]

/-- `or` is false exactly when nothing raised and no condition is true. -/
theorem evalOr_false_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalOr env cs errs = .ok (some false) ↔
      errs = [] ∧ ∀ c ∈ cs, ∃ r, evalCond env c = .ok r ∧ r ≠ some true := by
  induction cs generalizing errs with
  | nil =>
    simp only [evalOr]
    cases errs <;> simp
  | cons c cs ih =>
    simp only [evalOr]
    split
    · rename_i h; simp [h]
    · rename_i r hn h
      rw [ih]
      simp only [List.mem_cons, forall_eq_or_imp]
      constructor
      · rintro ⟨h1, h2⟩
        exact ⟨h1, ⟨r, h, hn⟩, h2⟩
      · rintro ⟨h1, -, h2⟩; exact ⟨h1, h2⟩
    · rename_i e h
      rw [ih]; simp [h]

/-- `or` never returns `None`. -/
theorem evalOr_ne_none (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalOr env cs errs ≠ .ok none := by
  induction cs generalizing errs with
  | nil => simp only [evalOr]; split <;> simp
  | cons c cs ih => simp only [evalOr]; split <;> simp [ih]

/-- Negating a checker's outcome: booleans flip, errors stay. -/
def CondResult.negate : CondResult → CondResult
  | .ok (some b) => .ok (some (!b))
  | r => r

/-- `not` is the negation of `or` over the same conditions, including which
errors are reported. -/
theorem evalNot_eq_negate_evalOr (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalNot env cs errs = (evalOr env cs errs).negate := by
  induction cs generalizing errs with
  | nil =>
    simp only [evalNot, evalOr]
    split <;> simp [CondResult.negate]
  | cons c cs ih =>
    simp only [evalNot, evalOr]
    cases h : evalCond env c with
    | err e => simp [ih]
    | ok r =>
      cases r with
      | none => simp [ih]
      | some b => cases b <;> simp [ih, CondResult.negate]

/-- `not` is false exactly when one of its conditions is true. -/
theorem evalNot_false_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalNot env cs errs = .ok (some false) ↔ ∃ c ∈ cs, evalCond env c = .ok (some true) := by
  rw [evalNot_eq_negate_evalOr, ← evalOr_true_iff env cs errs]
  cases h : evalOr env cs errs with
  | err e => simp [CondResult.negate]
  | ok r =>
    cases r with
    | none => simp [CondResult.negate]
    | some b => cases b <;> simp [CondResult.negate]

/-- `not` is true exactly when nothing raised and no condition is true. -/
theorem evalNot_true_iff (env : CondEnv) (cs : List Condition) (errs : List String) :
    evalNot env cs errs = .ok (some true) ↔
      errs = [] ∧ ∀ c ∈ cs, ∃ r, evalCond env c = .ok r ∧ r ≠ some true := by
  rw [evalNot_eq_negate_evalOr, ← evalOr_false_iff env cs errs]
  cases h : evalOr env cs errs with
  | err e => simp [CondResult.negate]
  | ok r =>
    cases r with
    | none => simp [CondResult.negate]
    | some b => cases b <;> simp [CondResult.negate]

/-- The `and` / `or` / `not` conditions never return `None`: only a
disabled condition does. -/
theorem evalCond_combinator_ne_none (env : CondEnv) (cs : List Condition) :
    evalCond env (.and cs) ≠ .ok none ∧ evalCond env (.or cs) ≠ .ok none ∧
      evalCond env (.not cs) ≠ .ok none := by
  refine ⟨?_, ?_, ?_⟩
  · simp only [evalCond]; exact evalAnd_ne_none _ _ _
  · simp only [evalCond]; exact evalOr_ne_none _ _ _
  · simp only [evalCond]
    rw [evalNot_eq_negate_evalOr]
    have := evalOr_ne_none env cs []
    cases h : evalOr env cs [] with
    | err e => simp [CondResult.negate]
    | ok r =>
      cases r with
      | none => exact absurd h this
      | some b => simp [CondResult.negate]

/-- Double negation: `not [not cs]` is true exactly when `or cs` is. -/
theorem evalCond_not_not_true_iff (env : CondEnv) (cs : List Condition) :
    evalCond env (.not [.not cs]) = .ok (some true) ↔ evalCond env (.or cs) = .ok (some true) := by
  have hnn := (evalCond_combinator_ne_none env cs).2.2
  simp only [evalCond] at hnn ⊢
  rw [evalNot_true_iff]
  simp only [List.mem_singleton, forall_eq, true_and, evalCond]
  rw [evalOr_true_iff, ← evalNot_false_iff env cs []]
  constructor
  · rintro ⟨r, hr, hne⟩
    cases r with
    | none => exact absurd hr hnn
    | some b =>
      cases b
      · exact hr
      · exact absurd rfl hne
  · intro h; exact ⟨some false, h, by simp⟩

/-! ### `checkAutomationConditions`, `testConditions` -/

/-- The automation-level check passes exactly when no condition raises and
none is false. -/
theorem checkAutomationConditions_iff (env : CondEnv) (cs : List Condition) :
    checkAutomationConditions env cs = true ↔
      ∀ c ∈ cs, ∃ r, evalCond env c = .ok r ∧ r ≠ some false := by
  have h := evalAnd_true_iff env cs []
  simp only [true_and] at h
  rw [← h]
  unfold checkAutomationConditions
  have hn := evalAnd_ne_none env cs []
  cases hr : evalAnd env cs [] with
  | err e => simp
  | ok r =>
    cases r with
    | none => exact absurd hr hn
    | some b => cases b <;> simp

/-- `_test_conditions` is true under exactly the same circumstances. -/
theorem testConditions_true_iff (env : CondEnv) (cs : List Condition) :
    testConditions env cs = some true ↔
      ∀ c ∈ cs, ∃ r, evalCond env c = .ok r ∧ r ≠ some false := by
  induction cs with
  | nil => simp [testConditions]
  | cons c cs ih =>
    simp only [testConditions]
    split
    · rename_i h; simp [h]
    · rename_i r hn h
      rw [ih]
      simp only [List.mem_cons, forall_eq_or_imp]
      constructor
      · intro h2
        exact ⟨⟨r, h, hn⟩, h2⟩
      · rintro ⟨-, h2⟩; exact h2
    · rename_i e h
      simp [h]

/-- The script runner's check and the automation's check agree on success. -/
theorem testConditions_true_iff_check (env : CondEnv) (cs : List Condition) :
    testConditions env cs = some true ↔ checkAutomationConditions env cs = true := by
  rw [testConditions_true_iff, checkAutomationConditions_iff]

/-- `_test_conditions` is false exactly when a condition is false and every
condition before it passed without raising. -/
theorem testConditions_false_iff (env : CondEnv) (cs : List Condition) :
    testConditions env cs = some false ↔
      ∃ pre c post, cs = pre ++ c :: post ∧ evalCond env c = .ok (some false) ∧
        ∀ p ∈ pre, ∃ r, evalCond env p = .ok r ∧ r ≠ some false := by
  induction cs with
  | nil => simp [testConditions]
  | cons c cs ih =>
    simp only [testConditions]
    split
    · rename_i h
      simp only [true_iff]
      exact ⟨[], c, cs, rfl, h, by simp⟩
    · rename_i r hn h
      rw [ih]
      constructor
      · rintro ⟨pre, c', post, rfl, hc, hp⟩
        refine ⟨c :: pre, c', post, rfl, hc, ?_⟩
        intro p hp'
        rcases List.mem_cons.mp hp' with rfl | hp'
        · exact ⟨r, h, hn⟩
        · exact hp p hp'
      · rintro ⟨pre, c', post, heq, hc, hp⟩
        cases pre with
        | nil =>
          simp only [List.nil_append, List.cons.injEq] at heq
          obtain ⟨rfl, rfl⟩ := heq
          rw [h] at hc; injection hc with hc; exact absurd hc hn
        | cons p pre =>
          simp only [List.cons_append, List.cons.injEq] at heq
          obtain ⟨rfl, rfl⟩ := heq
          exact ⟨pre, c', post, rfl, hc, fun q hq => hp q (List.mem_cons_of_mem _ hq)⟩
    · rename_i e h
      simp only [reduceCtorEq, false_iff]
      rintro ⟨pre, c', post, heq, hc, hp⟩
      cases pre with
      | nil =>
        simp only [List.nil_append, List.cons.injEq] at heq
        obtain ⟨rfl, rfl⟩ := heq
        rw [h] at hc; cases hc
      | cons p pre =>
        simp only [List.cons_append, List.cons.injEq] at heq
        obtain ⟨rfl, rfl⟩ := heq
        obtain ⟨r, hr, -⟩ := hp c (List.mem_cons_self ..)
        rw [h] at hr; cases hr

/-- When `_test_conditions` says false, so does the `and` checker (the
converse fails: `and` keeps going past an error, `_test_conditions` stops). -/
theorem testConditions_false_imp_evalAnd (env : CondEnv) (cs : List Condition) (errs : List String)
    (h : testConditions env cs = some false) : evalAnd env cs errs = .ok (some false) := by
  rw [evalAnd_false_iff]
  obtain ⟨pre, c, post, rfl, hc, -⟩ := (testConditions_false_iff env cs).mp h
  exact ⟨c, by simp, hc⟩

end HALean.Automation
