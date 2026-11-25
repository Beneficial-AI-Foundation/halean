/-
  Specifications for the `cv.*` validators of
  `HALean/Core/ConfigValidation.lean` (`helpers/config_validation.py`):
  what each accepts, the type of what it returns, and its error cases.

  `safeValue` and `pyEq` are `partial def`s, so text conversions appear
  through `strOf` / `requireSafe` rather than being evaluated.
-/
import HALean.Core.ConfigValidation

set_option linter.unusedSimpArgs false

namespace HALean.Core.ConfigValidationSpec
open HALean.Template HALean.Core

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

/-- A successful `>>=` in `Except`: both steps succeeded. -/
theorem bind_ok {ε α β} {x : Except ε α} {f : α → Except ε β} {b : β}
    (h : (x >>= f) = .ok b) : ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error e => cases h
  | ok a => exact ⟨a, rfl, h⟩

set_option hygiene false in
/-- Peel a successful `do` block in `Except` (hypothesis `h`) down to its
last statement. -/
macro "peel" : tactic =>
  `(tactic| repeat' (first | (obtain ⟨_, _, h⟩ := bind_ok h) | split at h))

set_option hygiene false in
macro "peel2" : tactic =>
  `(tactic| repeat' (first | split at h | (obtain ⟨_, _, h⟩ := bind_ok h)))


/-- A `for` loop in `Except` that never breaks and finishes without raising:
its body succeeded on every element. -/
theorem forIn_ok_all {α ε} {f : α → Except ε (ForInStep PUnit)} {P : α → Prop}
    (hP : ∀ a r, f a = .ok r → r = .yield PUnit.unit ∧ P a) :
    ∀ (l : List α) (u : PUnit), forIn l PUnit.unit (fun a _ => f a) = .ok u → ∀ a ∈ l, P a := by
  intro l
  induction l with
  | nil => intro _ _ a ha; cases ha
  | cons x xs ih =>
    intro u h a ha
    rw [List.forIn_cons] at h
    obtain ⟨r, hr, h⟩ := bind_ok h
    obtain ⟨hy, hx⟩ := hP x r hr
    subst hy
    rcases List.mem_cons.mp ha with rfl | ha
    · exact hx
    · exact ih u h a ha

/-- `mapM` in `Except` succeeds only if every item does, with one result per
item. -/
theorem mapM_ok {α β ε} {f : α → Except ε β} {P : β → Prop} (hf : ∀ a b, f a = .ok b → P b) :
    ∀ (l : List α) (r : List β), l.mapM f = .ok r → r.length = l.length ∧ ∀ b ∈ r, P b := by
  intro l
  induction l with
  | nil =>
    intro r h
    simp [pure, Except.pure] at h
    subst h; simp
  | cons a as ih =>
    intro r h
    rw [List.mapM_cons] at h
    simp only [bind, Except.bind] at h
    cases hfa : f a with
    | error e => rw [hfa] at h; cases h
    | ok b =>
      rw [hfa] at h
      cases hm : as.mapM f with
      | error e => rw [hm] at h; cases h
      | ok bs =>
        rw [hm] at h
        simp only [pure, Except.pure, Except.ok.injEq] at h
        subst h
        obtain ⟨hl, hall⟩ := ih bs hm
        refine ⟨by simp [hl], ?_⟩
        intro x hx
        rcases List.mem_cons.mp hx with rfl | hx
        · exact hf a _ hfa
        · exact hall x hx

/-! ## `cv.string` -/

/-- A string is kept as it is. -/
theorem cvString_str (s : String) : cvString (.str s) = .ok (.str s) := rfl

/-- `None`, a list and a dict are rejected, with upstream's two messages. -/
theorem cvString_rejects (xs : List Value) (kvs : List (Value × Value)) :
    cvString .none = .error (inv "string value is None") ∧
    cvString (.list xs) = .error (inv "value should be a string") ∧
    cvString (.dict kvs) = .error (inv "value should be a string") := ⟨rfl, rfl, rfl⟩

/-- Everything else is `str(value)`. -/
theorem cvString_other (v : Value) (h0 : v ≠ .none) (h1 : ∀ s, v ≠ .str s)
    (h2 : ∀ xs, v ≠ .list xs) (h3 : ∀ kvs, v ≠ .dict kvs) :
    cvString v = (strOf v).map Value.str := by
  cases v <;>
    first
    | exact absurd rfl h0 | exact absurd rfl (h1 _) | exact absurd rfl (h2 _)
    | exact absurd rfl (h3 _)
    | (simp only [cvString, bind, Except.bind, Except.map, pure, Except.pure]; first | done | (split <;> rfl))

/-- `cv.string` always returns a `str`. -/
theorem cvString_ok_str (v w : Value) (h : cvString v = .ok w) : ∃ s, w = .str s := by
  by_cases h0 : v = .none
  · subst h0; cases h
  by_cases h1 : ∃ s, v = .str s
  · obtain ⟨s, rfl⟩ := h1; cases h; exact ⟨s, rfl⟩
  by_cases h2 : ∃ xs, v = .list xs
  · obtain ⟨s, rfl⟩ := h2; cases h
  by_cases h3 : ∃ xs, v = .dict xs
  · obtain ⟨s, rfl⟩ := h3; cases h
  rw [cvString_other v h0 (fun s hs => h1 ⟨s, hs⟩) (fun s hs => h2 ⟨s, hs⟩)
    (fun s hs => h3 ⟨s, hs⟩)] at h
  cases hs : strOf v with
  | error e => rw [hs] at h; cases h
  | ok s => rw [hs] at h; cases h; exact ⟨s, rfl⟩

/-- `cv.string` is idempotent: its output passes unchanged. -/
theorem cvString_idem (v w : Value) (h : cvString v = .ok w) : cvString w = .ok w := by
  obtain ⟨s, rfl⟩ := cvString_ok_str v w h
  rfl

/-! ## `cv.boolean` -/

/-- A `bool` is kept. -/
theorem cvBoolean_bool (b : Bool) : cvBoolean (.bool b) = .ok (.bool b) := rfl

/-- A number is truthy when non-zero (`bool(value)`). -/
theorem cvBoolean_int (i : Int) : cvBoolean (.int i) = .ok (.bool (i != 0)) := rfl

/-- `0` is false and `1` is true. -/
theorem cvBoolean_zero_one :
    cvBoolean (.int 0) = .ok (.bool false) ∧ cvBoolean (.int 1) = .ok (.bool true) := ⟨rfl, rfl⟩

/-- A string is accepted exactly when `cvBooleanText` reads it (the words
`1/true/yes/on/enable` and `0/false/no/off/disable`, see
`HALean.Template.cvBooleanText_iff`). -/
theorem cvBoolean_str_iff (s : String) (w : Value) :
    cvBoolean (.str s) = .ok w ↔ ∃ b, Template.cvBooleanText s = some b ∧ w = .bool b := by
  unfold cvBoolean
  simp only [bind, Except.bind]
  cases hb : Template.cvBooleanText s with
  | some b => simp [hb, pure, Except.pure, eq_comm]
  | none =>
    simp only [hb]
    cases requireSafe (.str s) <;> simp [throw, throwThe, MonadExceptOf.throw]

/-- `cv.boolean` always returns a `bool`. -/
theorem cvBoolean_ok_bool (v w : Value) (h : cvBoolean v = .ok w) : ∃ b, w = .bool b := by
  cases v with
  | bool b => cases h; exact ⟨b, rfl⟩
  | int i => cases h; exact ⟨_, rfl⟩
  | float f => cases h; exact ⟨_, rfl⟩
  | str s =>
    obtain ⟨b, _, rfl⟩ := (cvBoolean_str_iff s w).mp h
    exact ⟨b, rfl⟩
  | _ =>
    simp only [cvBoolean, bind, Except.bind] at h
    split at h <;> cases h

/-- `cv.boolean` is idempotent. -/
theorem cvBoolean_idem (v w : Value) (h : cvBoolean v = .ok w) : cvBoolean w = .ok w := by
  obtain ⟨b, rfl⟩ := cvBoolean_ok_bool v w h
  rfl

/-- `None` is not a boolean. -/
theorem cvBoolean_none (w : Value) : cvBoolean .none ≠ .ok w := by
  intro h
  simp only [cvBoolean, bind, Except.bind] at h
  split at h <;> cases h

/-! ## `cv.entity_id` -/

/-- `cv.entity_id` returns the lower-cased `cv.string` of its input, and only
when that is a valid entity id (`HALean.Core.validEntityId_iff`). -/
theorem cvEntityId_ok (v w : Value) (h : cvEntityId v = .ok w) :
    ∃ s, cvString v = .ok (.str s) ∧ w = .str (s.map Char.toLower) ∧
      validEntityId (s.map Char.toLower) = true := by
  unfold cvEntityId at h
  simp only [bind, Except.bind] at h
  cases hs : cvString v with
  | error e => rw [hs] at h; cases h
  | ok r =>
    rw [hs] at h
    obtain ⟨s, rfl⟩ := cvString_ok_str v r hs
    simp only at h
    cases hr : requireSafe (.str s) with
    | error e => rw [hr] at h; cases h
    | ok u =>
      rw [hr] at h
      simp only at h
      by_cases hv : validEntityId (s.map Char.toLower) = true
      · rw [ifP hv] at h
        cases h
        exact ⟨s, rfl, rfl, hv⟩
      · rw [ifN hv] at h
        cases hso : strOf v with
        | error e => rw [hso] at h; cases h
        | ok t => rw [hso] at h; cases h

/-- What `cv.entity_id` returns is a valid entity id. -/
theorem cvEntityId_valid (v w : Value) (h : cvEntityId v = .ok w) :
    ∃ s, w = .str s ∧ validEntityId s = true := by
  obtain ⟨s, _, hw, hv⟩ := cvEntityId_ok v w h
  exact ⟨_, hw, hv⟩

/-- `None`, lists and dicts are rejected by the inner `cv.string`. -/
theorem cvEntityId_rejects (xs : List Value) (kvs : List (Value × Value)) :
    cvEntityId .none = .error (inv "string value is None") ∧
    cvEntityId (.list xs) = .error (inv "value should be a string") ∧
    cvEntityId (.dict kvs) = .error (inv "value should be a string") := ⟨rfl, rfl, rfl⟩

/-! ## `iter()` and `cv.entity_ids` -/

/-- A list iterates its items, a dict its keys. -/
theorem pyIter_list (xs : List Value) : pyIter (.list xs) = .ok xs := rfl
theorem pyIter_dict (kvs : List (Value × Value)) : pyIter (.dict kvs) = .ok (kvs.map (·.1)) := rfl

/-- Iterating anything else is a `TypeError`, not an `Invalid`: it escapes
the schema. -/
theorem pyIter_error (v : Value) (e : VErr) (h : pyIter v = .error e) :
    e = .raise "TypeError" s!"'{typeName v}' object is not iterable" := by
  cases v <;> first | (cases h; rfl) | cases h

/-- `iter(5)`: `'int' object is not iterable`. -/
theorem pyIter_int (i : Int) :
    pyIter (.int i) = .error (.raise "TypeError" "'int' object is not iterable") := rfl

/-- `cv.entity_ids(None)` is invalid. -/
theorem cvEntityIds_none : cvEntityIds .none = .error (inv "Entity IDs cannot be None") := rfl

/-- A list is validated item by item, in order. -/
theorem cvEntityIds_list (xs : List Value) : cvEntityIds (.list xs) = xs.mapM cvEntityId := rfl

/-- The empty list is valid. -/
theorem cvEntityIds_nil : cvEntityIds (.list []) = .ok [] := rfl

/-- An `int` is not iterable: `TypeError` escapes. -/
theorem cvEntityIds_int (i : Int) :
    cvEntityIds (.int i) = .error (.raise "TypeError" "'int' object is not iterable") := rfl

/-- Every id `cv.entity_ids` returns is a valid entity id. -/
theorem cvEntityIds_valid (v : Value) (ids : List Value) (h : cvEntityIds v = .ok ids) :
    ∀ id ∈ ids, ∃ s, id = .str s ∧ validEntityId s = true := by
  unfold cvEntityIds at h
  simp only [] at h
  peel
  all_goals exact (mapM_ok (P := fun id => ∃ s, id = .str s ∧ validEntityId s = true)
    cvEntityId_valid _ ids h).2

/-- A list of `n` items yields `n` ids. -/
theorem cvEntityIds_list_length (xs : List Value) (ids : List Value)
    (h : cvEntityIds (.list xs) = .ok ids) : ids.length = xs.length := by
  rw [cvEntityIds_list] at h
  exact (mapM_ok (P := fun _ => True) (fun _ _ _ => trivial) xs ids h).1

/-- A comma-separated string yields one id per part. -/
theorem cvEntityIds_str_length (s : String) (ids : List Value)
    (h : cvEntityIds (.str s) = .ok ids) : ids.length = (s.splitOn ",").length := by
  unfold cvEntityIds at h
  simp only [] at h
  obtain ⟨u, _, h⟩ := bind_ok h
  obtain ⟨items, hitems, h⟩ := bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at hitems
  subst hitems
  have := (mapM_ok (P := fun _ => True) (fun _ _ _ => trivial) _ ids h).1
  simpa using this

/-! ## `cv.entities_domain` / `cv.entity_domain` -/

/-- `cv.entities_domain` returns exactly what `cv.entity_ids` does (it only
adds a check). -/
theorem cvEntitiesDomain_ok (d : DomainArg) (v : Value) (ids : List Value)
    (h : cvEntitiesDomain d v = .ok ids) : cvEntityIds v = .ok ids := by
  unfold cvEntitiesDomain at h
  obtain ⟨ids', hi, h⟩ := bind_ok h
  simp only [] at h
  peel
  all_goals
    simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    exact hi

/-- So its ids are valid entity ids too. -/
theorem cvEntitiesDomain_valid (d : DomainArg) (v : Value) (ids : List Value)
    (h : cvEntitiesDomain d v = .ok ids) : ∀ id ∈ ids, ∃ s, id = .str s ∧ validEntityId s = true :=
  cvEntityIds_valid v ids (cvEntitiesDomain_ok d v ids h)

/-- `cv.entities_domain("light")`: every entity returned is in that domain. -/
theorem cvEntitiesDomain_one (dn : String) (v : Value) (ids : List Value)
    (h : cvEntitiesDomain (.one dn) v = .ok ids) :
    ∀ id ∈ ids, ∃ e, id = .str e ∧ ((splitEntityId e).map (·.1)).getD "" = dn := by
  unfold cvEntitiesDomain at h
  obtain ⟨ids', hi, h⟩ := bind_ok h
  simp only [] at h
  obtain ⟨shown, _, h⟩ := bind_ok h
  obtain ⟨u, hfor, h⟩ := bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at h
  subst h
  refine forIn_ok_all (P := fun id => ∃ e, id = .str e ∧ ((splitEntityId e).map (·.1)).getD "" = dn)
    ?_ ids' u hfor
  intro a r hr
  cases a <;> try (obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx; done)
  rename_i e
  simp only [] at hr
  cases hsp : splitEntityId e with
  | none =>
    simp only [hsp] at hr
    by_cases hbad : ("" != dn) = true
    · rw [ifP hbad] at hr; obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx
    · rw [ifN hbad] at hr
      simp only [pure, Except.pure, Except.ok.injEq] at hr
      refine ⟨hr.symm, e, rfl, ?_⟩
      simpa [hsp] using hbad
  | some p =>
    obtain ⟨dm, o⟩ := p
    simp only [hsp] at hr
    by_cases hbad : (dm != dn) = true
    · rw [ifP hbad] at hr; obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx
    · rw [ifN hbad] at hr
      simp only [pure, Except.pure, Except.ok.injEq] at hr
      refine ⟨hr.symm, e, rfl, ?_⟩
      simpa [hsp] using hbad

/-- `cv.entities_domain([...])`: every entity's domain is one of the list. -/
theorem cvEntitiesDomain_many (ds : List String) (v : Value) (ids : List Value)
    (h : cvEntitiesDomain (.many ds) v = .ok ids) :
    ∀ id ∈ ids, ∃ e, id = .str e ∧ ((splitEntityId e).map (·.1)).getD "" ∈ ds := by
  unfold cvEntitiesDomain at h
  obtain ⟨ids', hi, h⟩ := bind_ok h
  simp only [] at h
  obtain ⟨shown, _, h⟩ := bind_ok h
  obtain ⟨u, hfor, h⟩ := bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at h
  subst h
  refine forIn_ok_all (P := fun id => ∃ e, id = .str e ∧ ((splitEntityId e).map (·.1)).getD "" ∈ ds)
    ?_ ids' u hfor
  intro a r hr
  cases a <;> try (obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx; done)
  rename_i e
  simp only [] at hr
  cases hsp : splitEntityId e with
  | none =>
    simp only [hsp] at hr
    by_cases hbad : (!ds.contains "") = true
    · rw [ifP hbad] at hr; obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx
    · rw [ifN hbad] at hr
      simp only [pure, Except.pure, Except.ok.injEq] at hr
      refine ⟨hr.symm, e, rfl, ?_⟩
      simpa [hsp] using hbad
  | some p =>
    obtain ⟨dm, o⟩ := p
    simp only [hsp] at hr
    by_cases hbad : (!ds.contains dm) = true
    · rw [ifP hbad] at hr; obtain ⟨_, hx, _⟩ := bind_ok hr; cases hx
    · rw [ifN hbad] at hr
      simp only [pure, Except.pure, Except.ok.injEq] at hr
      refine ⟨hr.symm, e, rfl, ?_⟩
      simpa [hsp] using hbad

/-- `cv.entity_domain` accepts only when there is exactly one entity, and
returns it. -/
theorem cvEntityDomain_ok (d : DomainArg) (v w : Value) (h : cvEntityDomain d v = .ok w) :
    cvEntitiesDomain d v = .ok [w] := by
  unfold cvEntityDomain at h
  obtain ⟨ids, hi, h⟩ := bind_ok h
  split at h
  · simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    exact hi
  · cases h

/-- The entity `cv.entity_domain` returns is a valid entity id. -/
theorem cvEntityDomain_valid (d : DomainArg) (v w : Value) (h : cvEntityDomain d v = .ok w) :
    ∃ s, w = .str s ∧ validEntityId s = true :=
  cvEntitiesDomain_valid d v [w] (cvEntityDomain_ok d v w h) w (by simp)

/-- An empty list of entities is not "exactly one". -/
theorem cvEntityDomain_empty (s : String) :
    cvEntityDomain (.one s) (.list []) = .error (inv "Expected exactly 1 entity, got 0") := rfl

/-! ## `cv.positive_timedelta` and `timedelta(...)` -/

/-- `cv.positive_timedelta` accepts exactly the non-negative timedeltas
(zero included), unchanged. -/
theorem cvPositiveTimedelta_ok_iff (v w : Value) :
    cvPositiveTimedelta v = .ok w ↔ ∃ us, v = .timedelta us ∧ 0 ≤ us ∧ w = v := by
  cases v <;> try (simp [cvPositiveTimedelta, throw, throwThe, MonadExceptOf.throw]; done)
  rename_i us
  by_cases h : us < 0
  · simp [cvPositiveTimedelta, h, throw, throwThe, MonadExceptOf.throw]; omega
  · simp [cvPositiveTimedelta, h, pure, Except.pure, eq_comm]; omega

/-- A negative period: "Time period should be positive". -/
theorem cvPositiveTimedelta_negative (us : Int) (h : us < 0) :
    cvPositiveTimedelta (.timedelta us) = .error (inv "Time period should be positive") := by
  simp [cvPositiveTimedelta, h, throw, throwThe, MonadExceptOf.throw]

/-- `timedelta(...)` returns a timedelta, raises (`ValueError`,
`OverflowError`) or is unsupported; it never raises `Invalid`. -/
theorem timedeltaV_ok (args : List (Nat × HALean.Automation.TdArg)) (w : Value)
    (h : timedeltaV args = .ok w) :
    ∃ us, w = .timedelta us ∧ HALean.Automation.timedeltaNew args = .ok us := by
  unfold timedeltaV at h
  cases ht : HALean.Automation.timedeltaNew args with
  | error e => rw [ht] at h; simp only [] at h; split at h <;> cases h
  | ok us => rw [ht] at h; cases h; exact ⟨us, rfl, rfl⟩

/-- A product `timedelta` (`microseconds_to_delta_ex`) that does not raise
is the timedelta of its microseconds. -/
theorem deltaOfUs_ok (us : Int) (w : Value) (h : deltaOfUs us = .ok w) : w = .timedelta us := by
  unfold deltaOfUs at h
  split at h
  · cases h
  · cases h; rfl

theorem timedeltaV_error (args : List (Nat × HALean.Automation.TdArg)) (e : VErr)
    (h : timedeltaV args = .error e) : ∀ errs, e ≠ .invalid errs := by
  intro errs he
  subst he
  unfold timedeltaV at h
  cases ht : HALean.Automation.timedeltaNew args with
  | ok us => rw [ht] at h; cases h
  | error e' =>
    rw [ht] at h
    simp only [] at h
    cases hr : timedeltaRaise? e' with
    | none => rw [hr] at h; cases h
    | some p => rw [hr] at h; cases h

/-! ## `cv.time_period_seconds`, `timedelta(**value)`, `cv.time_period_str` -/

theorem secondsDelta_ok (v : Value) (f : Float) (w : Value) (h : secondsDelta v f = .ok w) :
    ∃ us, w = .timedelta us := by
  unfold secondsDelta at h
  split at h
  · obtain ⟨_, _, h⟩ := bind_ok h; cases h
  · obtain ⟨us, hw, _⟩ := timedeltaV_ok _ _ h
    exact ⟨us, hw⟩

/-- `cv.time_period_seconds` returns a timedelta. -/
theorem cvTimePeriodSeconds_ok (v w : Value) (h : cvTimePeriodSeconds v = .ok w) :
    ∃ us, w = .timedelta us := by
  unfold cvTimePeriodSeconds at h
  simp only [] at h
  peel
  all_goals exact secondsDelta_ok _ _ _ h

/-- `timedelta(**value)` returns a timedelta. -/
theorem cvTimedeltaKwargs_ok (v w : Value) (h : cvTimedeltaKwargs v = .ok w) :
    ∃ us, w = .timedelta us := by
  cases v <;> try (cases h; done)
  unfold cvTimedeltaKwargs at h
  obtain ⟨args, _, h⟩ := bind_ok h
  obtain ⟨us, hw, _⟩ := timedeltaV_ok _ _ h
  exact ⟨us, hw⟩

/-- `timedelta(**value)` of something that is not a dict is unsupported (the
schema in front of it only lets dicts through). -/
theorem cvTimedeltaKwargs_non_dict (v : Value) (h : ∀ kvs, v ≠ .dict kvs) :
    cvTimedeltaKwargs v = .error (.unsupported "timedelta(**value) of a non-dict") := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- An unquoted number (YAML `1:30` read as an int, or a bool) gets the
"wrap time values in quotes" hint. -/
theorem cvTimePeriodStr_int_bool (i : Int) (b : Bool) :
    cvTimePeriodStr (.int i) = .error (inv "Make sure you wrap time values in quotes") ∧
    cvTimePeriodStr (.bool b) = .error (inv "Make sure you wrap time values in quotes") :=
  ⟨rfl, rfl⟩

/-- `cv.entity_domain("light")` returns one entity of that domain. -/
theorem cvEntityDomain_one (dn : String) (v w : Value) (h : cvEntityDomain (.one dn) v = .ok w) :
    ∃ e, w = .str e ∧ ((splitEntityId e).map (·.1)).getD "" = dn :=
  cvEntitiesDomain_one dn v [w] (cvEntityDomain_ok _ v w h) w (by simp)

/-- `cv.time_period_str` returns a timedelta. -/
theorem cvTimePeriodStr_ok (v w : Value) (h : cvTimePeriodStr v = .ok w) :
    ∃ us, w = .timedelta us := by
  cases v with
  | str s =>
    unfold cvTimePeriodStr at h
    simp only [] at h
    obtain ⟨_, _, h⟩ := bind_ok h
    generalize (if s.startsWith "-" = true then (true, (s.drop 1).toString)
      else if s.startsWith "+" = true then (false, (s.drop 1).toString) else (false, s)) = nb at h
    obtain ⟨neg, body⟩ := nb
    simp only [] at h
    peel2
    all_goals first
      | (cases h; done)
      | exact ⟨_, deltaOfUs_ok _ _ h⟩
      | (simp only [pure, Except.pure, Except.ok.injEq] at h; exact ⟨_, h.symm⟩)
  | int i =>
    have e : cvTimePeriodStr (.int i) = .error (inv "Make sure you wrap time values in quotes") := rfl
    rw [e] at h; cases h
  | bool b =>
    have e : cvTimePeriodStr (.bool b) = .error (inv "Make sure you wrap time values in quotes") := rfl
    rw [e] at h; cases h
  | _ =>
    unfold cvTimePeriodStr at h
    simp only [] at h
    peel
    all_goals first
      | (cases h; done)

/-- Any other value fails with `TIME_PERIOD_ERROR` showing `str(value)`. -/
theorem cvTimePeriodStr_other (v : Value) (s : String) (h1 : ∀ i, v ≠ .int i)
    (h2 : ∀ b, v ≠ .bool b) (h3 : ∀ t, v ≠ .str t) (hs : strOf v = .ok s) :
    cvTimePeriodStr v = .error (inv (timePeriodError s)) := by
  cases v <;> first
    | exact absurd rfl (h1 _) | exact absurd rfl (h2 _) | exact absurd rfl (h3 _)
    | (simp only [cvTimePeriodStr, hs, bind, Except.bind]; rfl)

/-! ## `cv.slug`, `cv.color_hex` -/

/-- `[0-9A-Fa-f]` by code point. -/
theorem isHexDigit_iff (c : Char) :
    isHexDigit c = true ↔
      (48 ≤ c.toNat ∧ c.toNat ≤ 57) ∨ (97 ≤ c.toNat ∧ c.toNat ≤ 102) ∨
      (65 ≤ c.toNat ∧ c.toNat ≤ 70) := by
  simp only [isHexDigit, Char.isDigit, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq,
    Char.le_def, Char.toNat]
  simp only [ge_iff_le, UInt32.le_iff_toNat_le]
  have e0 : '0'.val.toNat = 48 := rfl
  have e9 : '9'.val.toNat = 57 := rfl
  have ea : 'a'.val.toNat = 97 := rfl
  have ef : 'f'.val.toNat = 102 := rfl
  have eA : 'A'.val.toNat = 65 := rfl
  have eF : 'F'.val.toNat = 70 := rfl
  rw [e0, e9, ea, ef, eA, eF]
  omega


/-- `cv.slug` returns `str(value)`, and only when that text is its own
slug (`util.slugify`, see `HALean.Automation.SlugifySpec`). -/
theorem cvSlug_ok (v w : Value) (h : cvSlug v = .ok w) :
    ∃ s, w = .str s ∧ HALean.Core.strOf v = .ok s ∧ HALean.Automation.slugify? s = some s := by
  unfold cvSlug at h
  simp only [] at h
  peel
  all_goals first
    | (cases h; done)
    | (simp [throw, throwThe, MonadExceptOf.throw] at *; done)
    | (simp only [pure, Except.pure, Except.ok.injEq] at h
       refine ⟨_, h.symm, by assumption, ?_⟩
       simp_all)

/-- `cv.color_hex` returns `str(value)`, and only when it is `#` and six hex
digits, optionally followed by one newline (Python's `$`). -/
theorem cvColorHex_ok (v w : Value) (h : cvColorHex v = .ok w) :
    ∃ s, w = .str s ∧ HALean.Core.strOf v = .ok s ∧ ∃ rest : List Char,
      (s.toList = '#' :: rest ∨ s.toList = '#' :: rest ++ ['\n']) ∧ rest.length = 6 ∧
      rest.all isHexDigit = true := by
  unfold cvColorHex at h
  simp only [] at h
  peel
  all_goals first
    | (cases h; done)
    | (simp only [pure, Except.pure, Except.ok.injEq] at h
       rename_i s hs _ rest heq hc
       simp only [Bool.and_eq_true, beq_iff_eq] at hc
       refine ⟨s, h.symm, hs, rest, ?_, hc.1, hc.2⟩
       by_cases hl : (s.toList.length == 8 && s.toList.getLast? == some '\n') = true
       · rw [ifP hl] at heq
         simp only [Bool.and_eq_true, beq_iff_eq] at hl
         right
         obtain ⟨ys, hys⟩ := List.getLast?_eq_some_iff.mp hl.2
         rw [hys, List.dropLast_concat] at heq
         rw [hys, heq]
       · rw [ifN hl] at heq
         exact Or.inl heq)


/-- `cv.slug(None)` is invalid. -/
theorem cvSlug_none : cvSlug .none = .error (inv "Slug should not be None") := rfl

/-- The whole dispatcher: the timedelta-producing `cv.*` return timedeltas,
`cv.string`-like ones strings, `cv.boolean` a bool, `cv.entity_ids` a list of
valid entity ids. -/
theorem CvFn.run_string (v w : Value) (h : CvFn.run .string v = .ok w) : ∃ s, w = .str s :=
  cvString_ok_str v w h

theorem CvFn.run_boolean (v w : Value) (h : CvFn.run .boolean v = .ok w) : ∃ b, w = .bool b :=
  cvBoolean_ok_bool v w h

theorem CvFn.run_entityId (v w : Value) (h : CvFn.run .entityId v = .ok w) :
    ∃ s, w = .str s ∧ validEntityId s = true := cvEntityId_valid v w h

theorem CvFn.run_entityIds (v w : Value) (h : CvFn.run .entityIds v = .ok w) :
    ∃ ids, w = .list ids ∧ ∀ id ∈ ids, ∃ s, id = .str s ∧ validEntityId s = true := by
  simp only [CvFn.run] at h
  obtain ⟨ids, hi, h⟩ := bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at h
  exact ⟨ids, h.symm, cvEntityIds_valid v ids hi⟩

theorem CvFn.run_entityDomain (d : DomainArg) (v w : Value)
    (h : CvFn.run (.entityDomain d) v = .ok w) : ∃ s, w = .str s ∧ validEntityId s = true :=
  cvEntityDomain_valid d v w h

theorem CvFn.run_slug_colorHex (v w : Value)
    (h : CvFn.run .slug v = .ok w ∨ CvFn.run .colorHex v = .ok w) :
    ∃ s, w = .str s ∧ HALean.Core.strOf v = .ok s := by
  rcases h with h | h
  · obtain ⟨s, hw, hs, _⟩ := cvSlug_ok v w h; exact ⟨s, hw, hs⟩
  · obtain ⟨s, hw, hs, _⟩ := cvColorHex_ok v w h; exact ⟨s, hw, hs⟩

theorem CvFn.run_timedelta (f : CvFn) (v w : Value)
    (hf : f = .timePeriodStr ∨ f = .timePeriodSeconds ∨ f = .timedeltaKwargs ∨ f = .positiveTimedelta)
    (h : CvFn.run f v = .ok w) : ∃ us, w = .timedelta us := by
  rcases hf with rfl | rfl | rfl | rfl
  · exact cvTimePeriodStr_ok v w h
  · exact cvTimePeriodSeconds_ok v w h
  · exact cvTimedeltaKwargs_ok v w h
  · obtain ⟨us, hv, _, hw⟩ := (cvPositiveTimedelta_ok_iff v w).mp h
    exact ⟨us, hw.trans hv⟩

end HALean.Core.ConfigValidationSpec
