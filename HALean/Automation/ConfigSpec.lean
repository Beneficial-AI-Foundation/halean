/-
  Specs for the automation config decoder (`HALean/Automation/Config.lean`),
  the part of `config_validation` and the platform schemas HALean models.

  Each decoder of an optional key is characterised by what is in the config:
  when it gives nothing, when it gives a value, and when it rejects.
-/
import HALean.Automation.Config
import HALean.Template.ParseTimeSpec
open Lean

set_option linter.unusedSimpArgs false

namespace HALean.Automation

/-! ### Generic: `mapM` in `Except` succeeds exactly on images -/

private theorem mapM_ok_iff {α β : Type} (f : α → Except String β) (g : β → α)
    (hf : ∀ a b, f a = .ok b ↔ a = g b) :
    ∀ (l : List α) (xs : List β), l.mapM f = .ok xs ↔ l = xs.map g
  | [], xs => by
    cases xs <;> simp [pure, Except.pure]
  | a :: l, xs => by
    rw [List.mapM_cons]
    have ih := mapM_ok_iff f g hf l
    cases hfa : f a with
    | error e =>
      simp only [bind, Except.bind, reduceCtorEq, false_iff]
      intro h
      cases xs with
      | nil => simp at h
      | cons b xs =>
        simp only [List.map_cons, List.cons.injEq] at h
        have := (hf a b).mpr h.1
        rw [hfa] at this; cases this
    | ok b =>
      cases hl : l.mapM f with
      | error e =>
        simp only [bind, Except.bind, reduceCtorEq, false_iff]
        intro h
        cases xs with
        | nil => simp at h
        | cons b' xs =>
          simp only [List.map_cons, List.cons.injEq] at h
          have := (ih xs).mpr h.2
          rw [hl] at this; cases this
      | ok bs =>
        simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq]
        constructor
        · rintro rfl
          simp only [List.map_cons, List.cons.injEq]
          exact ⟨(hf a b).mp hfa, (ih bs).mp hl⟩
        · intro h
          cases xs with
          | nil => simp at h
          | cons b' xs =>
            simp only [List.map_cons, List.cons.injEq] at h
            have h1 := (hf a b').mpr h.1
            rw [hfa] at h1
            have h2 := (ih xs).mpr h.2
            rw [hl] at h2
            injection h1 with h1; injection h2 with h2
            rw [h1, h2]

/-! ### `field?`, `has`, `str?` -/

/-- Only a mapping has keys. -/
theorem field?_not_obj (j : Json) (k : String) (h : ∀ kvs, j ≠ .obj kvs) : field? j k = none := by
  unfold field? Json.getObjVal?
  cases j <;> first | rfl | exact absurd rfl (h _)

/-- A key of a mapping is looked up in the mapping. -/
theorem field?_obj (kvs) (k : String) : field? (.obj kvs) k = kvs.get? k := by
  unfold field? Json.getObjVal?
  cases h : kvs.get? k <;> simp [h, pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- `has` is "the key is present" (a present `null` counts). -/
theorem has_iff (j : Json) (k : String) : has j k = true ↔ ∃ v, field? j k = some v := by
  unfold has
  cases field? j k <;> simp

/-- `str?` gives a key's value exactly when it is present and a string. -/
theorem str?_eq_some_iff (j : Json) (k s : String) :
    str? j k = some s ↔ field? j k = some (.str s) := by
  unfold str?
  cases field? j k with
  | none => simp
  | some v => cases v <;> simp [Json.getStr?, Except.toOption, pure, Except.pure, throw, throwThe,
      MonadExceptOf.throw]

/-- A key that is absent is not a string either. -/
theorem str?_none_of_absent (j : Json) (k : String) (h : field? j k = none) : str? j k = none := by
  simp [str?, h]

/-! ### `ensureList` (`cv.ensure_list`) -/

/-- A list is kept as it is. -/
theorem ensureList_arr_toArray (l : List Json) : ensureList (.arr l.toArray) = l := rfl

/-- `ensure_list` of its own result changes nothing. -/
theorem ensureList_idem (j : Json) : ensureList (.arr (ensureList j).toArray) = ensureList j := rfl

/-- Anything that is neither a list nor `None` is wrapped in a list. -/
theorem ensureList_scalar (j : Json) (h1 : ∀ a, j ≠ .arr a) (h2 : j ≠ .null) :
    ensureList j = [j] := by
  cases j <;> first | rfl | exact absurd rfl h2 | exact absurd rfl (h1 _)

/-- The result is empty only for `None` and the empty list. -/
theorem ensureList_eq_nil_iff (j : Json) : ensureList j = [] ↔ j = .null ∨ j = .arr #[] := by
  cases j with
  | arr a =>
    simp only [ensureList, reduceCtorEq, Json.arr.injEq, false_or]
    constructor
    · intro h; exact Array.toList_eq_nil_iff.mp h
    · rintro rfl; rfl
  | null => simp [ensureList]
  | bool b => simp [ensureList]
  | num n => simp [ensureList]
  | str s => simp [ensureList]
  | obj o => simp [ensureList]

/-! ### `strList`, `entityIds`, `weekday?` -/

/-- `strList` succeeds exactly when every item is a string, and returns
those strings in order. -/
theorem strList_ok_iff (j : Json) (xs : List String) :
    strList j = .ok xs ↔ ensureList j = xs.map Json.str := by
  unfold strList
  apply mapM_ok_iff
  intro a b
  cases a <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- A single string is a one-item list. -/
theorem strList_str (s : String) : strList (.str s) = .ok [s] :=
  (strList_ok_iff _ _).mpr rfl

/-- `None` is the empty list. -/
theorem strList_null : strList .null = .ok [] := (strList_ok_iff _ _).mpr rfl

/-- A list of strings round-trips. -/
theorem strList_arr (xs : List String) : strList (.arr (xs.map Json.str).toArray) = .ok xs :=
  (strList_ok_iff _ _).mpr rfl

/-- `entity_id` is required. -/
theorem entityIds_missing (j : Json) (h : field? j "entity_id" = none) :
    entityIds j = .error "missing entity_id" := by
  simp [entityIds, h, throw, throwThe, MonadExceptOf.throw]

/-- Every item of a `mapM` result comes from some input item. -/
private theorem mapM_ok_mem {α β : Type} (f : α → Except String β) :
    ∀ (l : List α) (ys : List β), l.mapM f = .ok ys → ∀ y ∈ ys, ∃ x ∈ l, f x = .ok y
  | [], ys, h => by
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at h
    subst h; simp
  | a :: l, ys, h => by
    rw [List.mapM_cons] at h
    cases hfa : f a with
    | error e => simp [hfa, bind, Except.bind] at h
    | ok b =>
      cases hl : l.mapM f with
      | error e => simp [hfa, hl, bind, Except.bind] at h
      | ok bs =>
        simp only [hfa, hl, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst h
        intro y hy
        rcases List.mem_cons.mp hy with rfl | hy
        · exact ⟨a, List.mem_cons_self .., hfa⟩
        · obtain ⟨x, hx, hfx⟩ := mapM_ok_mem f l bs hl y hy
          exact ⟨x, List.mem_cons_of_mem _ hx, hfx⟩

/-- `cv.entity_id` returns a valid entity id. -/
theorem cvEntityIdStr_valid (s r : String) (h : cvEntityIdStr s = .ok r) :
    Template.validEntityId r = true := by
  unfold cvEntityIdStr at h
  by_cases ha : s.toList.all (fun c => decide (c.toNat < 128)) = true
  · by_cases hv : Template.validEntityId s.toLower = true
    · simp only [ha, hv, Bool.not_true, Bool.false_eq_true, ↓reduceIte, pure, Except.pure,
        Except.ok.injEq, bind, Except.bind] at h
      subst h; exact hv
    · simp [ha, hv, throw, throwThe, MonadExceptOf.throw, bind, Except.bind] at h
  · simp [ha, throw, throwThe, MonadExceptOf.throw, bind, Except.bind] at h

/-- Decoded entity ids are valid entity ids (lower-cased, `domain.object_id`). -/
theorem entityIds_valid (j : Json) (ids : List String) (h : entityIds j = .ok ids) :
    ∀ s ∈ ids, Template.validEntityId s = true := by
  unfold entityIds at h
  split at h
  · simp [throw, throwThe, MonadExceptOf.throw] at h
  · unfold cvEntityIds at h
    intro s hs
    obtain ⟨x, _, hx⟩ := mapM_ok_mem _ _ ids h s hs
    split at hx
    · exact cvEntityIdStr_valid _ _ hx
    · simp [throw, throwThe, MonadExceptOf.throw] at hx
  · simp [throw, throwThe, MonadExceptOf.throw] at h

/-- No `weekday` key: no restriction. -/
theorem weekday?_none_iff (j : Json) : weekday? j = .ok none ↔ field? j "weekday" = none := by
  unfold weekday?
  cases hf : field? j "weekday" with
  | none => simp [pure, Except.pure]
  | some v => cases hs : strList v <;> simp [hs, Functor.map, Except.map]

/-- A `weekday` key gives exactly its strings. -/
theorem weekday?_some_iff (j : Json) (xs : List String) :
    weekday? j = .ok (some xs) ↔
      ∃ v, field? j "weekday" = some v ∧ ensureList v = xs.map Json.str := by
  unfold weekday?
  cases hf : field? j "weekday" with
  | none => simp [pure, Except.pure]
  | some v =>
    simp only [Option.some.injEq, exists_eq_left']
    rw [← strList_ok_iff]
    cases hs : strList v <;> simp [hs, Functor.map, Except.map]

/-! ### `isEnabled`, `continueOnTimeout?`, `responseVariable?`, `noTemplate` -/

/-- `enabled` defaults to true. -/
theorem isEnabled_absent (j : Json) (how : EnabledTmpl) (h : field? j "enabled" = none) :
    isEnabled j how = .ok true := by
  unfold isEnabled; simp [h, pure, Except.pure]

/-- A literal boolean is the answer, wherever it appears. -/
theorem isEnabled_bool (j : Json) (how : EnabledTmpl) (b : Bool) (h : field? j "enabled" = some (.bool b)) :
    isEnabled j how = .ok b := by
  unfold isEnabled; simp [h, pure, Except.pure]

/-- `continue_on_timeout` defaults to true and must otherwise be a boolean. -/
theorem continueOnTimeout?_ok_iff (j : Json) (b : Bool) :
    continueOnTimeout? j = .ok b ↔
      (field? j "continue_on_timeout" = none ∧ b = true) ∨
        field? j "continue_on_timeout" = some (.bool b) := by
  unfold continueOnTimeout?
  cases hf : field? j "continue_on_timeout" with
  | none => simp [pure, Except.pure, eq_comm]
  | some v => cases v <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- `response_variable` is optional and must be a string. -/
theorem responseVariable?_ok_iff (j : Json) (r : Option String) :
    responseVariable? j = .ok r ↔
      (field? j "response_variable" = none ∧ r = none) ∨
        ∃ s, field? j "response_variable" = some (.str s) ∧ r = some s := by
  unfold responseVariable?
  cases hf : field? j "response_variable" with
  | none => simp [pure, Except.pure, eq_comm]
  | some v => cases v <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- `noTemplate` accepts exactly the configs without the key. -/
theorem noTemplate_ok_iff (j : Json) (k : String) : noTemplate j k = .ok () ↔ has j k = false := by
  unfold noTemplate
  cases has j k <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-! ### `jsonNumToFloat`, `durationMs`, `optDuration` -/

/-- Only numbers and strings can be read as a float. -/
theorem jsonNumToFloat_isSome_imp (v : Json) (h : (jsonNumToFloat v).isSome = true) :
    (∃ n, v = .num n) ∨ ∃ s, v = .str s := by
  cases v <;> simp [jsonNumToFloat] at h ⊢

/-- A JSON number always reads as a float. -/
theorem jsonNumToFloat_num (n : JsonNumber) : (jsonNumToFloat (.num n)).isSome = true := rfl

/-- `None` and lists are not time periods. -/
theorem durationMs_bad_type (v : Json) (h : v = .null ∨ ∃ a, v = .arr a) :
    durationMs v = .error s!"invalid time period: {v.compress}" := by
  rcases h with rfl | ⟨a, rfl⟩ <;> rfl

/-- A template is not accepted where a static period is required. -/
theorem durationMs_template (s : String) (h : Template.isTemplateString s = true) :
    durationMs (.str s) = .error s!"templated durations are not supported here: {s}" := by
  simp [durationMs, h, throw, throwThe, MonadExceptOf.throw, bind, Except.bind]

/-- A decoded period is `cv.time_period`'s, not negative
(`positive_timedelta`), rounded up to whole ms. -/
theorem durationMs_ok (v : Json) (ms : Nat) (h : durationMs v = .ok ms) :
    ∃ us, cvTimePeriod (Template.Value.ofJson v) = .ok us ∧ 0 ≤ us ∧ ms = ((us + 999) / 1000).toNat := by
  unfold durationMs at h
  have tail : ∀ (x : Except String Int),
      (match x with
        | .error e => (throw s!"invalid time period {v.compress}: {e}" : D Nat)
        | .ok us => if us < 0 then throw "negative time period" else pure ((us + 999) / 1000).toNat) = .ok ms →
      ∃ us, x = .ok us ∧ 0 ≤ us ∧ ms = ((us + 999) / 1000).toNat := by
    intro x hx
    cases x with
    | error e => simp [throw, throwThe, MonadExceptOf.throw] at hx
    | ok us =>
      by_cases hn : us < 0
      · simp [hn, throw, throwThe, MonadExceptOf.throw] at hx
      · simp only [hn, ↓reduceIte, pure, Except.pure, Except.ok.injEq] at hx
        exact ⟨us, rfl, by omega, hx.symm⟩
  cases v with
  | null => simp [throw, throwThe, MonadExceptOf.throw, bind, Except.bind] at h
  | arr a => simp [throw, throwThe, MonadExceptOf.throw, bind, Except.bind] at h
  | str s =>
    by_cases ht : Template.isTemplateString s = true
    · simp [ht, throw, throwThe, MonadExceptOf.throw, bind, Except.bind] at h
    · simp only [ht, Bool.false_eq_true, ↓reduceIte, bind, Except.bind, pure, Except.pure] at h
      exact tail _ h
  | bool b => exact tail _ h
  | num n => exact tail _ h
  | obj o => exact tail _ h

/-- An optional period is absent exactly when its key is. -/
theorem optDuration_none_iff (j : Json) (k : String) :
    optDuration j k = .ok none ↔ field? j k = none := by
  unfold optDuration
  cases hf : field? j k with
  | none => simp [pure, Except.pure]
  | some v => cases hd : durationMs v <;> simp [hd, Functor.map, Except.map]

/-- A present period is decoded by `durationMs`. -/
theorem optDuration_some_iff (j : Json) (k : String) (ms : Nat) :
    optDuration j k = .ok (some ms) ↔ ∃ v, field? j k = some v ∧ durationMs v = .ok ms := by
  unfold optDuration
  cases hf : field? j k with
  | none => simp [pure, Except.pure]
  | some v => cases hd : durationMs v <;> simp [hd, Functor.map, Except.map]

/-! ### `bound?` (`below` / `above`) -/

/-- No bound: the key is absent or `None`. -/
theorem bound?_none_iff (j : Json) (k : String) :
    bound? j k = .ok none ↔ field? j k = none ∨ field? j k = some .null := by
  unfold bound?
  cases hf : field? j k with
  | none => simp [pure, Except.pure]
  | some v =>
    cases v with
    | str s =>
      simp only [reduceCtorEq, Option.some.injEq, or_self, iff_false]
      cases parsePyFloatStr s with
      | some f => simp [pure, Except.pure]
      | none => by_cases hc : s.contains '.' <;> simp [hc, pure, Except.pure, throw, throwThe,
          MonadExceptOf.throw]
    | _ => simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- An entity bound comes only from a string that is not a number and looks
like an entity id (contains a dot). -/
theorem bound?_entity_iff (j : Json) (k e : String) :
    bound? j k = .ok (some (.entity e)) ↔
      field? j k = some (.str e) ∧ parsePyFloatStr e = none ∧ e.contains '.' = true := by
  unfold bound?
  cases hf : field? j k with
  | none => simp [pure, Except.pure]
  | some v =>
    cases v with
    | str s =>
      simp only [Option.some.injEq, Json.str.injEq]
      cases hp : parsePyFloatStr s with
      | some f =>
        simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq, reduceCtorEq, false_iff]
        rintro ⟨rfl, h2, -⟩
        rw [hp] at h2; cases h2
      | none =>
        by_cases hc : s.contains '.'
        · simp only [hc, ite_true, pure, Except.pure, Except.ok.injEq, Option.some.injEq,
            Bound.entity.injEq]
          constructor
          · rintro rfl; exact ⟨rfl, hp, hc⟩
          · rintro ⟨rfl, -, -⟩; rfl
        · simp only [hc, ↓reduceIte, throw, throwThe, MonadExceptOf.throw, reduceCtorEq, false_iff]
          rintro ⟨rfl, -, h3⟩
          exact hc h3
    | _ => simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- A numeric bound comes from a number, or from a string Python's
`float()` accepts (`vol.Coerce(float)`). -/
theorem bound?_num_imp (j : Json) (k : String) (f : Float)
    (h : bound? j k = .ok (some (.num f))) :
    (∃ n, field? j k = some (.num n) ∧ f = n.toFloat) ∨
      ∃ s, field? j k = some (.str s) ∧ parsePyFloatStr s = some f := by
  unfold bound? at h
  cases hf : field? j k with
  | none => simp [hf, pure, Except.pure] at h
  | some v =>
    rw [hf] at h
    cases v with
    | num n =>
      simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq, Bound.num.injEq] at h
      exact Or.inl ⟨n, rfl, h.symm⟩
    | str s =>
      refine Or.inr ⟨s, rfl, ?_⟩
      simp only at h
      cases hp : parsePyFloatStr s with
      | some f' =>
        simp only [hp, pure, Except.pure, Except.ok.injEq, Option.some.injEq, Bound.num.injEq] at h
        rw [h]
      | none =>
        rw [hp] at h
        by_cases hc : s.contains '.' <;>
          simp [hc, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
    | null => simp [pure, Except.pure] at h
    | bool b => simp [throw, throwThe, MonadExceptOf.throw] at h
    | arr a => simp [throw, throwThe, MonadExceptOf.throw] at h
    | obj o => simp [throw, throwThe, MonadExceptOf.throw] at h

/-! ### `timeBound?` (`before` / `after` of the time condition) -/

/-- No bound exactly when the key is not a string. -/
theorem timeBound?_none_iff (j : Json) (k : String) :
    timeBound? j k = .ok none ↔ str? j k = none := by
  unfold timeBound?
  cases hs : str? j k with
  | none => simp [pure, Except.pure]
  | some s =>
    simp only [reduceCtorEq, iff_false]
    cases Template.parseTimeSeconds s with
    | some sec => simp [pure, Except.pure]
    | none => by_cases hc : s.contains '.' <;> simp [hc, pure, Except.pure, throw, throwThe,
        MonadExceptOf.throw]

/-- A fixed bound is the time upstream's `parse_time` reads, in
microseconds. -/
theorem timeBound?_fixed_iff (j : Json) (k : String) (us : Nat) :
    timeBound? j k = .ok (some (.fixed us)) ↔
      ∃ s sec, str? j k = some s ∧ Template.ParseTimeSpec s sec ∧ us = sec * 1000000 := by
  unfold timeBound?
  cases hs : str? j k with
  | none => simp [pure, Except.pure]
  | some s =>
    simp only [Option.some.injEq]
    cases hp : Template.parseTimeSeconds s with
    | some sec =>
      simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq, TimeBound.fixed.injEq]
      constructor
      · intro h; exact ⟨s, sec, rfl, (Template.parseTimeSeconds_iff s sec).mp hp, h.symm⟩
      · rintro ⟨s', sec', rfl, h1, h2⟩
        have := (Template.parseTimeSeconds_iff s sec').mpr h1
        rw [hp] at this; injection this with this
        rw [h2, this]
    | none =>
      have hno : ∀ sec, ¬ Template.ParseTimeSpec s sec := by
        intro sec h
        have := (Template.parseTimeSeconds_iff s sec).mpr h
        rw [hp] at this; cases this
      constructor
      · intro h
        by_cases hc : s.contains '.' <;>
          simp [hc, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
      · rintro ⟨s', sec', rfl, h1, -⟩; exact absurd h1 (hno _)

/-- A fixed bound is a whole number of seconds within one day. -/
theorem timeBound?_fixed_range (j : Json) (k : String) (us : Nat)
    (h : timeBound? j k = .ok (some (.fixed us))) :
    us % 1000000 = 0 ∧ us < 86400 * 1000000 := by
  obtain ⟨s, sec, -, hspec, rfl⟩ := (timeBound?_fixed_iff j k us).mp h
  obtain ⟨p0, p1, rest, hh, m, sc, -, -, -, -, h0, h1, h2, h3, h4, h5, h6⟩ := hspec
  refine ⟨by omega, ?_⟩
  have : (sec : Int) < 86400 := by omega
  omega

/-- An entity bound comes only from a string that is not a time and
contains a dot. -/
theorem timeBound?_entity_iff (j : Json) (k e : String) :
    timeBound? j k = .ok (some (.entity e)) ↔
      str? j k = some e ∧ Template.parseTimeSeconds e = none ∧ e.contains '.' = true := by
  unfold timeBound?
  cases hs : str? j k with
  | none => simp [pure, Except.pure]
  | some s =>
    simp only [Option.some.injEq]
    cases hp : Template.parseTimeSeconds s with
    | some sec =>
      simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq, reduceCtorEq, false_iff]
      rintro ⟨rfl, h2, -⟩
      rw [hp] at h2; cases h2
    | none =>
      by_cases hc : s.contains '.'
      · simp only [hc, ite_true, pure, Except.pure, Except.ok.injEq, Option.some.injEq,
          TimeBound.entity.injEq]
        constructor
        · rintro rfl; exact ⟨rfl, hp, hc⟩
        · rintro ⟨rfl, -, -⟩; rfl
      · simp only [hc, ↓reduceIte, throw, throwThe, MonadExceptOf.throw, reduceCtorEq, false_iff]
        rintro ⟨rfl, -, h3⟩
        exact hc h3

/-! ### `compileTemplate`, `valueTemplate?` -/

/-- A template is accepted exactly when it compiles and uses only names
HALean can supply. -/
theorem compileTemplate_ok_iff (s : String) (vars : List String) (t : Template.Tmpl) :
    compileTemplate s vars = .ok t ↔
      Template.compile s = .ok t ∧ Template.check t vars = .ok () := by
  unfold compileTemplate
  cases hc : Template.compile s with
  | error e => simp [bind, Except.bind, throw, throwThe, MonadExceptOf.throw]
  | ok t' =>
    simp only [bind, Except.bind, pure, Except.pure, Except.ok.injEq]
    cases hk : Template.check t' vars with
    | error e =>
      simp only [throw, throwThe, MonadExceptOf.throw, reduceCtorEq, false_iff]
      rintro ⟨rfl, h⟩
      rw [hk] at h; cases h
    | ok u =>
      cases u
      simp only [Except.ok.injEq]
      constructor
      · rintro rfl; exact ⟨rfl, hk⟩
      · rintro ⟨rfl, -⟩; rfl

/-- A template that does not compile is rejected, with the template quoted. -/
theorem compileTemplate_compile_error (s e : String) (vars : List String)
    (h : Template.compile s = .error e) :
    compileTemplate s vars = .error s!"invalid template ({e}): {s}" := by
  simp [compileTemplate, h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- No `value_template` key: none. -/
theorem valueTemplate?_none_iff (j : Json) (nm : List String) :
    valueTemplate? j nm = .ok none ↔ field? j "value_template" = none := by
  unfold valueTemplate?
  cases hf : field? j "value_template" with
  | none => simp [pure, Except.pure]
  | some v =>
    cases v with
    | str s => cases hc : compileTemplate s (nm ++ ["state"]) <;> simp [hc, Functor.map, Except.map]
    | _ => simp [throw, throwThe, MonadExceptOf.throw]

/-- A `value_template` is compiled with `state` in scope, next to the
caller's names. -/
theorem valueTemplate?_some_iff (j : Json) (nm : List String) (t : Template.Tmpl) :
    valueTemplate? j nm = .ok (some t) ↔
      ∃ s, field? j "value_template" = some (.str s) ∧
        compileTemplate s (nm ++ ["state"]) = .ok t := by
  unfold valueTemplate?
  cases hf : field? j "value_template" with
  | none => simp [pure, Except.pure]
  | some v =>
    cases v with
    | str s => cases hc : compileTemplate s (nm ++ ["state"]) <;> simp [hc, Functor.map, Except.map]
    | _ => simp [throw, throwThe, MonadExceptOf.throw]

/-! ### `forPeriod?`, `timeout?` -/

/-- No `for:` key: no period. -/
theorem forPeriod?_absent (j : Json) (k : String) (nm : List String) (h : field? j k = none) :
    forPeriod? j k nm = .ok none := by
  simp [forPeriod?, h, pure, Except.pure]

/-- A static string period is decoded by `durationMs`. -/
theorem forPeriod?_static_str (j : Json) (k s : String) (nm : List String)
    (h : field? j k = some (.str s)) (hs : Template.isTemplateString s = false) :
    forPeriod? j k nm = (durationMs (.str s)).map (fun ms => some (.fixed ms)) := by
  simp only [forPeriod?, h, hs, bind, Except.bind]
  cases durationMs (.str s) <;> rfl

/-- A template string is kept as a template, to be rendered when the
trigger's condition is met. -/
theorem forPeriod?_template_str (j : Json) (k s : String) (nm : List String) (t : Template.Tmpl)
    (h : field? j k = some (.str s)) (hs : Template.isTemplateString s = true)
    (ht : compileTemplate s nm = .ok t) :
    forPeriod? j k nm = .ok (some (.tmpl (.tmpl t))) := by
  simp [forPeriod?, h, hs, ht, bind, Except.bind, pure, Except.pure]

/-- No `timeout` key: no timeout. -/
theorem timeout?_absent (j : Json) (nm : List String) (h : field? j "timeout" = none) :
    timeout? j nm = .ok none := by
  simp [timeout?, h, pure, Except.pure]

/-! ### `orderedMapping` -/

/-- An object is read in its (sorted) key order. -/
theorem orderedMapping_obj (what : String) (kvs) :
    orderedMapping what (.obj kvs) = .ok kvs.toList := rfl

/-- A list is accepted exactly when it is a list of `[key, value]` pairs,
and those pairs are returned in the order given. -/
theorem orderedMapping_arr_ok_iff (what : String) (xs : Array Json) (kvs : List (String × Json)) :
    orderedMapping what (.arr xs) = .ok kvs ↔
      xs.toList = kvs.map fun p => Json.arr #[.str p.1, p.2] := by
  unfold orderedMapping
  apply mapM_ok_iff
  intro a b
  obtain ⟨bk, bv⟩ := b
  cases a with
  | arr ys =>
    obtain ⟨l⟩ := ys
    match l with
    | [] => exact ⟨fun h => (by cases h), fun h => (by simp at h)⟩
    | [x] => exact ⟨fun h => (by cases h), fun h => (by simp at h)⟩
    | [x, y] =>
      cases x with
      | str k =>
        show (Except.ok (k, y) : Except String (String × Json)) = .ok (bk, bv) ↔ _
        simp [eq_comm]
      | _ => exact ⟨fun h => (by cases h), fun h => (by simp at h)⟩
    | x :: y :: z :: w => exact ⟨fun h => (by cases h), fun h => (by simp at h)⟩
  | _ => exact ⟨fun h => (by cases h), fun h => (by simp at h)⟩

/-- The `[[key, value], ...]` encoding round-trips, keeping the order. -/
theorem orderedMapping_roundtrip (what : String) (kvs : List (String × Json)) :
    orderedMapping what (.arr (kvs.map fun p => Json.arr #[.str p.1, p.2]).toArray) = .ok kvs :=
  (orderedMapping_arr_ok_iff what _ kvs).mpr rfl

/-- Anything that is neither an object nor a list is rejected. -/
theorem orderedMapping_bad (what : String) (j : Json) (h1 : ∀ o, j ≠ .obj o) (h2 : ∀ a, j ≠ .arr a) :
    orderedMapping what j = .error s!"{what} must be a mapping" := by
  cases j <;> first | rfl | exact absurd rfl (h1 _) | exact absurd rfl (h2 _)

/-! ### `stateMatch` (`from` / `not_from`, `to` / `not_to`) -/

/-- A key counts as given when it is present and not `None`. -/
def Given (j : Json) (k : String) : Prop := ∃ v, field? j k = some v ∧ v ≠ .null

private theorem not_given (j : Json) (k : String) :
    ¬ Given j k ↔ field? j k = none ∨ field? j k = some .null := by
  unfold Given
  cases field? j k with
  | none => simp
  | some v =>
    by_cases hv : v = .null
    · subst hv; simp
    · simp [hv]

/-- `process_state_match`: `None` and `MATCH_ALL` match everything. -/
theorem processStateMatch_values_none_iff (v : Json) (i : Bool) :
    (processStateMatch v i).values = none ↔ v = .null ∨ v = .str "*" := by
  unfold processStateMatch
  split <;> simp_all

/-- `invert` is kept as given. -/
theorem processStateMatch_invert (v : Json) (i : Bool) : (processStateMatch v i).invert = i := by
  unfold processStateMatch; split <;> rfl

/-- The positive key wins. -/
theorem stateMatch_pos (j : Json) (pos neg : String) (v : Json)
    (h : field? j pos = some v) (hv : v ≠ .null) :
    stateMatch j pos neg = processStateMatch v false := by
  unfold stateMatch
  rw [h]
  cases v <;> first | rfl | exact absurd rfl hv

/-- Without the positive key, the negative key is matched inverted. -/
theorem stateMatch_neg (j : Json) (pos neg : String) (v : Json)
    (hp : ¬ Given j pos) (h : field? j neg = some v) (hv : v ≠ .null) :
    stateMatch j pos neg = processStateMatch v true := by
  unfold stateMatch
  rcases (not_given j pos).mp hp with hp | hp <;> rw [hp] <;> simp only [h] <;>
    cases v <;> first | rfl | exact absurd rfl hv

/-- Neither key given: MATCH_ALL. -/
theorem stateMatch_none (j : Json) (pos neg : String) (hp : ¬ Given j pos) (hn : ¬ Given j neg) :
    stateMatch j pos neg = {} := by
  unfold stateMatch
  rcases (not_given j pos).mp hp with hp | hp <;>
    rcases (not_given j neg).mp hn with hn | hn <;> rw [hp] <;> simp only [hn]

/-! ### `decodeTrigger` -/

/-- A trigger with `enabled: false` is dropped, whatever else it says. -/
theorem decodeTrigger_disabled (idx : Nat) (j : Json) (tnm : List String)
    (tvals : Option (List (String × Json))) (h : field? j "enabled" = some (.bool false)) :
    decodeTrigger idx j tnm tvals = .ok none := by
  unfold decodeTrigger
  simp only [isEnabled_bool j _ false h, bind, Except.bind, pure, Except.pure, Bool.not_false, ite_true]

/-- An `enabled` HALean cannot decide (a template in a `wait_for_trigger`)
is rejected rather than guessed. -/
theorem decodeTrigger_enabled_error (idx : Nat) (j : Json) (tnm : List String)
    (tvals : Option (List (String × Json))) (e : String)
    (h : isEnabled j (match tvals with
      | some tv => .render tv (some false)
      | none => .unsupported) = .error e) :
    decodeTrigger idx j tnm tvals = .error e := by
  unfold decodeTrigger
  cases tvals <;> simp only at h ⊢ <;> simp only [h, bind, Except.bind]

/-! ### `automationName` (`_automation_name`) -/

/-- A non-empty alias is the name. -/
theorem automationName_alias (j : Json) (n : Nat) (a : String)
    (h : field? j "alias" = some (.str a)) (ha : a ≠ "") : automationName j n = a := by
  have hs : str? j "alias" = some a := (str?_eq_some_iff _ _ _).mpr h
  have he : a.isEmpty = false := by
    cases hh : a.isEmpty
    · rfl
    · exact absurd (String.isEmpty_iff.mp hh) ha
  simp [automationName, hs, he]

/-- Without a usable alias the name is `automation <position>`. -/
theorem automationName_default (j : Json) (n : Nat)
    (h : str? j "alias" = none ∨ str? j "alias" = some "") :
    automationName j n = s!"automation {n}" := by
  rcases h with h | h <;> simp [automationName, h]

/-- The name is one of the two. -/
theorem automationName_cases (j : Json) (n : Nat) :
    automationName j n = s!"automation {n}" ∨
      (str? j "alias" = some (automationName j n) ∧ automationName j n ≠ "") := by
  unfold automationName
  cases hs : str? j "alias" with
  | none => exact Or.inl rfl
  | some a =>
    cases he : a.isEmpty
    · refine Or.inr ?_
      simp only [he, Bool.false_eq_true, ite_false, true_and]
      intro h; rw [h] at he; simp at he
    · exact Or.inl (by simp [he])

/-! ### `availableEntityId`, `automationEntityIds` -/

/-- `async_get_available_entity_id`: when `domain.slug` (cut to the maximum
entity id length) is free, it is the id. -/
theorem availableEntityId_free (domain slug : String) (taken : List String)
    (h : taken.contains
      (String.ofList ((s!"{domain}.{slug}").toList.take MAX_LENGTH_STATE_ENTITY_ID)) = false) :
    availableEntityId domain slug taken =
      String.ofList ((s!"{domain}.{slug}").toList.take MAX_LENGTH_STATE_ENTITY_ID) := by
  unfold availableEntityId
  simp only [Id.run, Std.Legacy.Range.forIn_eq_forIn_range', Std.Legacy.Range.size]
  have : (taken.length + 1 - 0 + 1 - 1) / 1 = taken.length + 1 := by simp
  rw [this, List.range'_succ, List.forIn_cons]
  simp only [h]
  rfl

/-- With nothing taken the preferred id is always used. -/
theorem availableEntityId_nil (domain slug : String) :
    availableEntityId domain slug [] =
      String.ofList ((s!"{domain}.{slug}").toList.take MAX_LENGTH_STATE_ENTITY_ID) :=
  availableEntityId_free domain slug [] rfl

/-- The same computation as `automationEntityIds`, from any loop state. -/
private def entityIdsFrom (l : List (Json × Nat)) (taken0 : List String) (known0 : Bool)
    (out0 : List (Option String)) : List (Option String) := Id.run do
  let mut taken := taken0
  let mut known := known0
  let mut out : List (Option String) := out0
  for (j, i) in l do
    match known, slugify? (automationName j i) with
    | true, some slug =>
      let eid := availableEntityId "automation" slug taken
      taken := taken ++ [eid]
      out := out ++ [some eid]
    | _, _ =>
      known := false
      out := out ++ [none]
  return out

private theorem automationEntityIds_eq (raw : List Json) (taken : List String) :
    automationEntityIds raw taken = entityIdsFrom raw.zipIdx taken true [] := rfl

private theorem entityIdsFrom_nil (taken : List String) (known : Bool) (out : List (Option String)) :
    entityIdsFrom [] taken known out = out := rfl

private theorem entityIdsFrom_cons_unknown (j : Json) (i : Nat) (l : List (Json × Nat))
    (taken : List String) (known : Bool) (out : List (Option String))
    (h : known = false ∨ slugify? (automationName j i) = none) :
    entityIdsFrom ((j, i) :: l) taken known out = entityIdsFrom l taken false (out ++ [none]) := by
  unfold entityIdsFrom
  simp only [List.forIn_cons, Id.run]
  rcases h with rfl | h
  · rfl
  · cases known <;> simp only [h] <;> rfl

private theorem entityIdsFrom_cons_known (j : Json) (i : Nat) (l : List (Json × Nat))
    (taken : List String) (out : List (Option String)) (slug : String)
    (h : slugify? (automationName j i) = some slug) :
    entityIdsFrom ((j, i) :: l) taken true out =
      entityIdsFrom l (taken ++ [availableEntityId "automation" slug taken]) true
        (out ++ [some (availableEntityId "automation" slug taken)]) := by
  unfold entityIdsFrom
  simp only [List.forIn_cons, Id.run, h]
  rfl

private theorem entityIdsFrom_unknown (l : List (Json × Nat)) (taken : List String)
    (out : List (Option String)) :
    entityIdsFrom l taken false out = out ++ List.replicate l.length none := by
  induction l generalizing out with
  | nil => simp [entityIdsFrom_nil]
  | cons a l ih =>
    obtain ⟨j, i⟩ := a
    rw [entityIdsFrom_cons_unknown j i l taken false out (Or.inl rfl), ih]
    simp [List.replicate_succ]

private theorem entityIdsFrom_shape (l : List (Json × Nat)) (taken : List String)
    (out : List (Option String)) :
    ∃ ids : List String, ids.length ≤ l.length ∧
      entityIdsFrom l taken true out =
        out ++ ids.map some ++ List.replicate (l.length - ids.length) none := by
  induction l generalizing taken out with
  | nil => exact ⟨[], by simp, by simp [entityIdsFrom_nil]⟩
  | cons a l ih =>
    obtain ⟨j, i⟩ := a
    cases hs : slugify? (automationName j i) with
    | none =>
      refine ⟨[], by simp, ?_⟩
      rw [entityIdsFrom_cons_unknown j i l taken true out (Or.inr hs), entityIdsFrom_unknown]
      simp [List.replicate_succ]
    | some slug =>
      obtain ⟨ids, hlen, heq⟩ := ih (taken ++ [availableEntityId "automation" slug taken])
        (out ++ [some (availableEntityId "automation" slug taken)])
      refine ⟨availableEntityId "automation" slug taken :: ids, by simp; omega, ?_⟩
      rw [entityIdsFrom_cons_known j i l taken out slug hs, heq]
      simp

/-- Every configured automation gets one answer: an id, or "unknown". -/
theorem automationEntityIds_length (raw : List Json) (taken : List String) :
    (automationEntityIds raw taken).length = raw.length := by
  obtain ⟨ids, hlen, heq⟩ := entityIdsFrom_shape raw.zipIdx taken []
  rw [automationEntityIds_eq, heq]
  simp only [List.length_zipIdx] at hlen ⊢
  simp; omega

/-- The known ids are a prefix: once one automation's id is unknown, so is
the id of every automation after it. -/
theorem automationEntityIds_prefix (raw : List Json) (taken : List String) :
    ∃ ids : List String, ids.length ≤ raw.length ∧
      automationEntityIds raw taken =
        ids.map some ++ List.replicate (raw.length - ids.length) none := by
  obtain ⟨ids, hlen, heq⟩ := entityIdsFrom_shape raw.zipIdx taken []
  rw [List.length_zipIdx] at hlen heq
  exact ⟨ids, hlen, by rw [automationEntityIds_eq, heq]; simp⟩

/-- No automations, no ids. -/
theorem automationEntityIds_nil (taken : List String) : automationEntityIds [] taken = [] := rfl

end HALean.Automation
