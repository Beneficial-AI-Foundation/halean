/-
  Specifications for `HALean/Core/Schema.lean`.

  The evaluator itself (`Validator.run`, `runAll`, `runAny`, `runSequence`,
  `runMapping`) is a block of mutually recursive `partial def`s and cannot be
  unfolded.  What is specified here is what surrounds it: the key pool for
  "did you mean" (`keyNames`), the `Exclusive` / `Inclusive` group table that
  `_check_groups` walks (`groupsOf`), and the wrapper `SchemaSpec.validate`,
  with the evaluator as an opaque function.
-/
import HALean.Core.Schema

set_option linter.unusedSimpArgs false

namespace HALean.Core.SchemaLemmas
open HALean.Template HALean.Core

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

theorem bind_ok {ε α β} {x : Except ε α} {f : α → Except ε β} {b : β}
    (h : (x >>= f) = .ok b) : ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error e => cases h
  | ok a => exact ⟨a, rfl, h⟩

/-! ## `keyNames` -/

/-- One name per schema key, in schema order. -/
theorem keyNames_length (fields : List Field) : (keyNames fields).length = fields.length := by
  simp [keyNames]

theorem mem_keyNames (fields : List Field) (k : String) :
    k ∈ keyNames fields ↔ ∃ f ∈ fields, f.key = k := by
  simp [keyNames]

/-- The `i`-th name is the `i`-th field's key. -/
theorem keyNames_getElem? (fields : List Field) (i : Nat) :
    (keyNames fields)[i]? = fields[i]?.map Field.key := by
  simp [keyNames]

/-- The four accessors read back the constructor's arguments. -/
theorem field_eta (f : Field) : Field.mk f.key f.marker f.default f.value = f := by
  cases f; rfl

/-! ## `groupsOf` -/

/-- The group a field belongs to, for the `Exclusive` (`true`) or `Inclusive`
(`false`) pass. -/
def groupOf (excl : Bool) (f : Field) : Option String :=
  match f.marker, excl with
  | .exclusive g _, true => some g
  | .inclusive g, false => some g
  | _, _ => none

/-- One step of the group table: add index `i` to its group, creating the
group at the end if it is new. -/
def groupStep (excl : Bool) (acc : List (String × List Nat)) (p : Nat × Field) :
    List (String × List Nat) :=
  match groupOf excl p.2 with
  | none => acc
  | some g =>
    if acc.any (·.1 == g) then acc.map fun (h, ms) => if h == g then (h, ms ++ [p.1]) else (h, ms)
    else acc ++ [(g, [p.1])]

theorem groupsOf_eq_foldl (fields : List Field) (excl : Bool) :
    groupsOf fields excl = ((List.range fields.length).zip fields).foldl (groupStep excl) [] := rfl

/-- No fields, no groups. -/
theorem groupsOf_nil (excl : Bool) : groupsOf [] excl = [] := rfl

theorem foldl_inv {α β} (Inv : β → Prop) (step : β → α → β) :
    ∀ (l : List α) (acc : β), Inv acc → (∀ acc x, x ∈ l → Inv acc → Inv (step acc x)) →
      Inv (l.foldl step acc) := by
  intro l
  induction l with
  | nil => intro acc h _; exact h
  | cons x xs ih =>
    intro acc h hs
    exact ih _ (hs acc x (by simp) h) (fun acc y hy => hs acc y (by simp [hy]))

/-- A schema with only `Required` / `Optional` keys has no groups. -/
theorem groupsOf_no_groups (fields : List Field) (excl : Bool)
    (h : ∀ f ∈ fields, groupOf excl f = none) : groupsOf fields excl = [] := by
  rw [groupsOf_eq_foldl]
  refine foldl_inv (β := List (String × List Nat)) (fun acc => acc = []) (groupStep excl) _ [] rfl ?_
  intro acc p hp hacc
  have hf : p.2 ∈ fields := (List.of_mem_zip hp).2
  simp [groupStep, h p.2 hf, hacc]

theorem groupOf_required_optional (excl : Bool) (f : Field)
    (h : f.marker = .required ∨ f.marker = .optional) : groupOf excl f = none := by
  unfold groupOf
  rcases h with h | h <;> rw [h]

/-- `Inclusive` keys are invisible to the `Exclusive` pass and vice versa. -/
theorem groupOf_other_pass (f : Field) (g : String) (r : Bool) :
    (f.marker = .inclusive g → groupOf true f = none) ∧
    (f.marker = .exclusive g r → groupOf false f = none) := by
  constructor <;> intro h <;> simp [groupOf, h]

/-- Group names in the table are distinct: each group is listed once. -/
theorem groupsOf_nodup (fields : List Field) (excl : Bool) :
    ((groupsOf fields excl).map (·.1)).Nodup := by
  rw [groupsOf_eq_foldl]
  refine foldl_inv (β := List (String × List Nat)) (fun acc => (acc.map (·.1)).Nodup) (groupStep excl) _ [] (by simp) ?_
  intro acc p _ hacc
  unfold groupStep
  cases groupOf excl p.2 with
  | none => exact hacc
  | some g =>
    dsimp only
    by_cases hany : acc.any (·.1 == g) = true
    · rw [ifP hany]
      have : (acc.map fun (h, ms) => if h == g then (h, ms ++ [p.1]) else (h, ms)).map (·.1)
          = acc.map (·.1) := by
        rw [List.map_map]
        apply List.map_congr_left
        intro q _
        obtain ⟨h, ms⟩ := q
        by_cases hq : h = g <;> simp [hq]
      rw [this]; exact hacc
    · rw [ifN hany]
      rw [List.map_append, List.nodup_append]
      refine ⟨hacc, by simp, ?_⟩
      intro a ha b hb
      have hb' : b = g := by simpa using hb
      subst hb'
      intro hab
      subst hab
      obtain ⟨q, hq, rfl⟩ := List.mem_map.mp ha
      exact hany (List.any_eq_true.mpr ⟨q, hq, by simp⟩)

/-- Every listed group has at least one member, and every member is the
index of a field that carries that group's marker. -/
theorem groupsOf_members (fields : List Field) (excl : Bool) :
    ∀ gm ∈ groupsOf fields excl, gm.2 ≠ [] ∧
      ∀ i ∈ gm.2, ∃ f, fields[i]? = some f ∧ groupOf excl f = some gm.1 := by
  rw [groupsOf_eq_foldl]
  refine foldl_inv (β := List (String × List Nat)) (fun acc => ∀ gm ∈ acc, gm.2 ≠ [] ∧
      ∀ i ∈ gm.2, ∃ f, fields[i]? = some f ∧ groupOf excl f = some gm.1) (groupStep excl) _ []
    (by intro gm h; cases h) ?_
  intro acc p hp hacc
  have hidx : fields[p.1]? = some p.2 := by
    obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp hp
    rw [List.getElem?_zip_eq_some] at hi
    obtain ⟨h1, h2⟩ := hi
    have hlt : i < fields.length := by
      have := (List.getElem?_eq_some_iff.mp h2).1
      exact this
    have : p.1 = i := by
      rw [List.getElem?_range hlt] at h1
      exact (Option.some.inj h1).symm
    rw [this]; exact h2
  unfold groupStep
  cases hg : groupOf excl p.2 with
  | none => exact hacc
  | some g =>
    dsimp only
    by_cases hany : acc.any (·.1 == g) = true
    · rw [ifP hany]
      intro gm hgm
      obtain ⟨q, hq, rfl⟩ := List.mem_map.mp hgm
      obtain ⟨h, ms⟩ := q
      obtain ⟨hne, hmem⟩ := hacc (h, ms) hq
      by_cases hh : (h == g) = true
      · have hhg : h = g := by simpa using hh
        simp only [hh, ite_true]
        refine ⟨by simp, ?_⟩
        intro i hi
        rcases List.mem_append.mp hi with hi | hi
        · exact hmem i hi
        · have : i = p.1 := by simpa using hi
          subst this
          exact ⟨p.2, hidx, by rw [hg, hhg]⟩
      · simp only [hh]
        exact ⟨hne, hmem⟩
    · rw [ifN hany]
      intro gm hgm
      rcases List.mem_append.mp hgm with hgm | hgm
      · exact hacc gm hgm
      · have : gm = (g, [p.1]) := by simpa using hgm
        subst this
        refine ⟨by simp, ?_⟩
        intro i hi
        have : i = p.1 := by simpa using hi
        subst this
        exact ⟨p.2, hidx, hg⟩

/-- Member indices are in range. -/
theorem groupsOf_index_lt (fields : List Field) (excl : Bool) (g : String) (ms : List Nat)
    (h : (g, ms) ∈ groupsOf fields excl) : ∀ i ∈ ms, i < fields.length := by
  intro i hi
  obtain ⟨f, hf, _⟩ := (groupsOf_members fields excl (g, ms) h).2 i hi
  exact (List.getElem?_eq_some_iff.mp hf).1

/-! ## `SchemaSpec.validate` -/

/-- The conversion `validate` applies to the evaluator's dict. -/
def strKey : Value × Value → Except VErr (String × Value)
  | (.str k, v) => pure (k, v)
  | _ => throw (VErr.unsupported "a non-string key")

theorem mapM_strKey_ok {kvs : List (Value × Value)} {out : List (String × Value)}
    (h : kvs.mapM strKey = .ok out) : kvs = out.map fun (k, v) => (Value.str k, v) := by
  induction kvs generalizing out with
  | nil =>
    simp [pure, Except.pure] at h
    subst h; rfl
  | cons p ps ih =>
    rw [List.mapM_cons] at h
    obtain ⟨q, hq, h⟩ := bind_ok h
    obtain ⟨qs, hqs, h⟩ := bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    obtain ⟨k, v⟩ := p
    cases k <;> first | (cases hq; done) | skip
    simp only [strKey, pure, Except.pure, Except.ok.injEq] at hq
    subst hq
    simp [ih hqs]

theorem mapM_strKey_map (out : List (String × Value)) :
    (out.map fun (k, v) => (Value.str k, v)).mapM strKey = .ok out := by
  induction out with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨k, v⟩ := p
    simp only [List.map_cons, List.mapM_cons, ih, strKey, bind, Except.bind, pure, Except.pure]

theorem mapM_strKey_error {kvs : List (Value × Value)} {e : VErr}
    (h : kvs.mapM strKey = .error e) : e = VErr.unsupported "a non-string key" := by
  induction kvs with
  | nil => cases h
  | cons p ps ih =>
    rw [List.mapM_cons] at h
    simp only [bind, Except.bind] at h
    cases hp : strKey p with
    | error e' =>
      rw [hp] at h
      obtain ⟨k, v⟩ := p
      cases k <;> first | (cases hp; cases h; rfl) | cases hp
    | ok q =>
      rw [hp] at h
      cases hm : ps.mapM strKey with
      | error e' => rw [hm] at h; cases h; exact ih hm
      | ok qs => rw [hm] at h; cases h

theorem validate_eq (s : SchemaSpec) (data : List (String × Value)) :
    s.validate data = (do
      match ← (Validator.dict s.fields).run s.extra (dictOf data) with
      | .dict kvs => kvs.mapM strKey
      | _ => throw (.unsupported "a mapping schema returned a non-dict")) := by
  unfold SchemaSpec.validate
  congr 1
  funext r
  cases r <;> first | rfl | skip
  rename_i kvs
  simp only
  congr 1
  funext p
  obtain ⟨k, v⟩ := p
  cases k <;> rfl

/-- A successful `Schema.__call__`: the evaluator returned a dict whose keys
are all strings, and the result is exactly that dict's items in order. -/
theorem validate_ok (s : SchemaSpec) (data out : List (String × Value))
    (h : s.validate data = .ok out) :
    (Validator.dict s.fields).run s.extra (dictOf data) = .ok (dictOf out) := by
  rw [validate_eq] at h
  obtain ⟨r, hr, h⟩ := bind_ok h
  cases r <;> first | (cases h; done) | skip
  rw [hr, mapM_strKey_ok h]; rfl

/-- The converse: when the evaluator returns a string-keyed dict, that is the
result. -/
theorem validate_of_run (s : SchemaSpec) (data out : List (String × Value))
    (h : (Validator.dict s.fields).run s.extra (dictOf data) = .ok (dictOf out)) :
    s.validate data = .ok out := by
  rw [validate_eq, h]
  exact mapM_strKey_map out

/-- So `validate` succeeds exactly when the evaluator returns a string-keyed
dict. -/
theorem validate_ok_iff (s : SchemaSpec) (data out : List (String × Value)) :
    s.validate data = .ok out ↔
      (Validator.dict s.fields).run s.extra (dictOf data) = .ok (dictOf out) :=
  ⟨validate_ok s data out, validate_of_run s data out⟩

/-- An evaluator failure (`Invalid`, an escaping exception, unsupported
input) is reported unchanged. -/
theorem validate_error_of_run (s : SchemaSpec) (data : List (String × Value)) (e : VErr)
    (h : (Validator.dict s.fields).run s.extra (dictOf data) = .error e) :
    s.validate data = .error e := by
  rw [validate_eq, h]; rfl

/-- A `probatio.Invalid` out of `validate` always comes from the evaluator:
the wrapper itself never invents a validation error. -/
theorem validate_invalid (s : SchemaSpec) (data : List (String × Value))
    (errs : List SchemaError) (h : s.validate data = .error (.invalid errs)) :
    (Validator.dict s.fields).run s.extra (dictOf data) = .error (.invalid errs) := by
  rw [validate_eq] at h
  cases hr : (Validator.dict s.fields).run s.extra (dictOf data) with
  | error e => rw [hr] at h; cases h; rfl
  | ok r =>
    rw [hr] at h
    exfalso
    cases r <;> first | (cases h; done) | skip
    have := mapM_strKey_error h
    cases this

/-- When the evaluator succeeds, the only way `validate` can still fail is
"unsupported" (a non-string key or a non-dict result). -/
theorem validate_error_after_ok (s : SchemaSpec) (data : List (String × Value)) (r : Value)
    (e : VErr) (hr : (Validator.dict s.fields).run s.extra (dictOf data) = .ok r)
    (h : s.validate data = .error e) : ∃ why, e = .unsupported why := by
  rw [validate_eq, hr] at h
  cases r <;> first | (cases h; exact ⟨_, rfl⟩) | skip
  exact ⟨_, mapM_strKey_error h⟩

end HALean.Core.SchemaLemmas
