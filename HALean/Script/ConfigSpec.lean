/-
  Specifications of the script configuration decoder
  (`HALean/Script/Config.lean`), proved against
  `homeassistant/components/script/config.py`:

  * `isSlug_iff`: `cv.slug` on an object id is exactly "a valid slug"
  * `cvString_ok_iff`, `actionName_eq_some_iff`, `checkAttributes_ok_iff`
  * `decodeScript_ok`: what every accepted script looks like (its entity,
    its `Automation`, `max ≥ 2`, ...) and what must hold of its config
  * the reserved object ids are the domain's own services
-/
import HALean.Script.Service
import HALean.Automation.SlugifySpec
open Lean

namespace HALean.Script
open HALean.Automation

/-! ### `cv.string`, `cv.slug` -/

/-- `cvString` accepts strings (unchanged) and numbers (as Lean prints
them), nothing else. -/
theorem cvString_ok_iff (what : String) (j : Json) (s : String) :
    cvString what j = .ok s ↔ j = .str s ∨ ∃ n, j = .num n ∧ s = toString n := by
  cases j <;> simp [cvString, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- An object id that passes `cv.slug` is a valid slug: non-empty,
`[0-9a-z_]` only, no `_` at either end, no `__`. -/
theorem isSlug_valid (s : String) (h : isSlug s = true) : ValidSlug s.toList := by
  simp only [isSlug, Bool.and_eq_true, Bool.not_eq_true', beq_iff_eq] at h
  have hne : s ≠ "" := by
    intro e; subst e; simp at h
  rcases (slugify_fixed_iff s (by simp [h.2])).1 h.2 with e | hv
  · exact absurd e hne
  · exact hv

/-- **`cv.slug` on an object id, exactly**: `isSlug` accepts the valid
slugs and nothing else. -/
theorem isSlug_iff (s : String) : isSlug s = true ↔ ValidSlug s.toList := by
  refine ⟨isSlug_valid s, fun h => ?_⟩
  have hne : s ≠ "" := by
    intro e; subst e; exact h.1 rfl
  have hs : slugify? s ≠ none := by
    unfold slugify?
    have he : s.isEmpty = false := by simpa using hne
    simp [he]
    refine ⟨fun x hx => ?_, fun hamp => ?_⟩
    · have hx := h.2.1 x hx
      have : ('a' : Char).val.toNat = 97 := rfl
      have : ('z' : Char).val.toNat = 122 := rfl
      have : ('_' : Char).val.toNat = 95 := rfl
      simp only [Char.isDigit, Bool.and_eq_true, decide_eq_true_eq, Char.le_def,
        UInt32.le_iff_toNat_le, Char.ext_iff, ← UInt32.toNat_inj, ge_iff_le] at hx
      show x.val.toNat < 128
      have : ('0' : Char).val.toNat = 48 := rfl
      have : ('9' : Char).val.toNat = 57 := rfl
      omega
    · exact absurd (h.2.1 '&' hamp) (by decide)
  simp only [isSlug, Bool.and_eq_true, Bool.not_eq_true', beq_iff_eq]
  exact ⟨by simpa using hne, (slugify_fixed_iff s hs).2 (.inr h)⟩

/-- `action:` wins over `service:`; a non-string `action:` falls back to
`service:`. -/
theorem actionName_eq_some_iff (j : Json) (a : String) :
    actionName j = some a ↔
      str? j "action" = some a ∨ (str? j "action" = none ∧ str? j "service" = some a) := by
  unfold actionName
  cases str? j "action" <;> simp [Option.orElse]

/-- Reading the same text gives the same verdict, and the verdict is: no
`last_action` anywhere, and `last_triggered` only inside
`this.attributes.last_triggered`. -/
theorem checkAttributes_ok_iff (j : Json) :
    checkAttributes j = .ok () ↔
      (j.compress.splitOn "last_action").length ≤ 1 ∧
      (("".intercalate (j.compress.splitOn "this.attributes.last_triggered")).splitOn
        "last_triggered").length ≤ 1 := by
  simp only [checkAttributes, bind, Except.bind, pure, Except.pure, throw, throwThe,
    MonadExceptOf.throw]
  by_cases h1 : (j.compress.splitOn "last_action").length > 1
  · simp [h1] <;> omega
  · by_cases h2 : (("".intercalate (j.compress.splitOn "this.attributes.last_triggered")).splitOn
        "last_triggered").length > 1
    · simp [h1, h2] <;> omega
    · simp [h1, h2] <;> omega

/-! ### Names passed between scripts -/

/-- The names are collected script by script: loading more scripts (or
automations, see `decodeAll`) only adds names. -/
theorem passedNames_append (a b : List (String × Json)) :
    passedNames (a ++ b) = passedNames a ++ passedNames b := by
  simp [passedNames]

theorem passedNames_subset (a b : List (String × Json)) (n : String) (h : n ∈ passedNames a) :
    n ∈ passedNames (a ++ b) ∧ n ∈ passedNames (b ++ a) := by
  simp [passedNames_append, h]

/-! ### `decodeFields`, `decodeScript` -/

private theorem bind_ok {α β : Type} {x : D α} {f : α → D β} {r : β} (h : (x >>= f) = .ok r) :
    ∃ a, x = .ok a ∧ f a = .ok r := by
  cases x with
  | error e => cases h
  | ok a => exact ⟨a, rfl, h⟩

private theorem throw_bind {α β : Type} {e : String} {f : α → D β} {r : β}
    (h : ((throw e : D α) >>= f) = .ok r) : False := by cases h

/-- A `for` loop that throws on the items with `c` ends well only when no
item has `c`. -/
private theorem forIn_guard_ok {α : Type} {c : α → Bool} {e : α → String} :
    ∀ {l : List α} {w : PUnit},
      forIn (m := D) l PUnit.unit (fun x _ =>
        if c x = true then (do throw (e x); pure (ForInStep.yield PUnit.unit))
        else pure (ForInStep.yield PUnit.unit)) = .ok w → ∀ x ∈ l, c x = false
  | [], _, _ => by simp
  | a :: l, w, h => by
    simp only [List.forIn_cons] at h
    cases hc : c a
    · simp only [hc, Bool.false_eq_true, ite_false] at h
      have := forIn_guard_ok (l := l) (w := w) h
      simpa [hc] using this
    · simp only [hc, ite_true] at h
      cases h

/-- A `for` loop without `break` ends well only if every step does. -/
private theorem forIn_ok_all {α : Type} {P : α → Prop} {body : α → PUnit.{1} → D (ForInStep PUnit.{1})}
    (hb : ∀ x u r, body x u = .ok r → P x ∧ r = .yield PUnit.unit) :
    ∀ {l : List α} {w : PUnit.{1}}, forIn l PUnit.unit body = .ok w → ∀ x ∈ l, P x
  | [], _, _ => by simp
  | a :: l, w, h => by
    simp only [List.forIn_cons] at h
    obtain ⟨r, hr, h⟩ := bind_ok h
    obtain ⟨hp, rfl⟩ := hb _ _ _ hr
    have := forIn_ok_all hb (l := l) (w := w) h
    simpa [hp] using this

/-- **`CONF_FIELDS`**: when `decodeFields` accepts, the names it gives are
the keys of the `fields` mapping, in its order, every field is a mapping,
and every key of a field is one the schema knows (`FIELD_KEYS`). -/
theorem decodeFields_ok (j : Json) (names : List String) (h : decodeFields j = .ok names) :
    ∃ fs, orderedMapping "fields" j = .ok fs ∧ names = fs.map (·.1) ∧
      ∀ f ∈ fs, ∃ kvs, f.2 = .obj kvs ∧ ∀ p ∈ kvs.toList, p.1 ∈ FIELD_KEYS := by
  unfold decodeFields at h
  obtain ⟨fs, hfs, h⟩ := bind_ok h
  obtain ⟨_, hloop, h⟩ := bind_ok h
  cases h
  refine ⟨fs, hfs, rfl, forIn_ok_all ?_ hloop⟩
  rintro ⟨name, f⟩ u r hr
  simp only at hr
  split at hr
  rotate_left
  · cases hr
  rename_i kvs
  obtain ⟨_, hin, hr⟩ := bind_ok hr
  cases hr
  refine ⟨⟨kvs, rfl, forIn_ok_all ?_ hin⟩, rfl⟩
  rintro ⟨k, v⟩ u r hr
  simp only at hr
  split at hr
  · exact (throw_bind hr).elim
  · rename_i hk
    refine ⟨by simpa using hk, ?_⟩
    split at hr
    all_goals first
      | (cases hr; rfl)
      | exact (throw_bind hr).elim
      | (obtain ⟨_, _, hr⟩ := bind_ok hr; cases hr; rfl)

/-- **What an accepted script looks like.** If `decodeScript` accepts
`key: j`, then

  * `key` passes `cv.slug` and is not a reserved id; `j` is a mapping with
    only `SCRIPT_ENTITY_SCHEMA`'s keys, no blueprint, and a `sequence`
    that passes `checkActions`;
  * the entity is `script.<key>`, alive, with the raw config and the
    `prefix:name` icon (if any);
  * the `Automation` the engine runs has no triggers or conditions, the
    key as id and unique id, a non-empty name (the alias, else the key),
    `max ≥ 2` (10 by default), and the mode `mode:` names (`single` by
    default). -/
theorem decodeScript_ok (key : String) (j : Json) (extra : List String) (s : ScriptEntity)
    (a : Automation) (h : decodeScript key j extra = .ok (s, a)) :
    isSlug key = true ∧ key ∉ INVALID_OBJECT_IDS ∧
    (∃ kvs, j = .obj kvs ∧ ∀ p ∈ kvs.toList, p.1 ∈ SCRIPT_KEYS) ∧
    has j "use_blueprint" = false ∧
    (∃ seq, field? j "sequence" = some seq ∧ checkActions seq = .ok ()) ∧
    s.objectId = key ∧ s.entityId = "script." ++ key ∧ s.alive = true ∧ s.raw = j.compress ∧
    (∀ i, s.icon = some i → i.contains ':' = true) ∧ (field? j "icon" = none → s.icon = none) ∧
    a.id = key ∧ a.triggers = [] ∧ a.conditions = [] ∧ a.entityId = some s.entityId ∧
    a.uniqueId = some key ∧
    a.alias ≠ "" ∧ (field? j "alias" = none → a.alias = key) ∧
    2 ≤ a.maxRuns ∧ (field? j "max" = none → a.maxRuns = 10) ∧
    (field? j "mode" = none → a.mode = .single) ∧
    (∀ v, field? j "mode" = some v → v = .str (modeStr a.mode)) ∧
    (∀ me, field? j "max_exceeded" = some me →
      ∃ c, cvString "max_exceeded" me = .ok c ∧ c.toUpper ∈ MAX_EXCEEDED_CHOICES) := by
  generalize hr : (s, a) = r at h
  unfold decodeScript at h
  extract_lets -underBinder jpSlug at h
  replace h : isSlug key = true ∧ jpSlug () = .ok r := by
    clear_value jpSlug
    split at h
    · exact (throw_bind h).elim
    · exact ⟨by simp_all, h⟩
  obtain ⟨hslug, h⟩ := h
  simp -zeta only [jpSlug] at h
  clear jpSlug
  extract_lets -underBinder jpRes at h
  replace h : INVALID_OBJECT_IDS.contains key = false ∧ jpRes () = .ok r := by
    clear_value jpRes
    split at h
    · exact (throw_bind h).elim
    · exact ⟨by simp_all, h⟩
  obtain ⟨hres, h⟩ := h
  simp -zeta only [jpRes] at h
  clear jpRes
  cases j with
  | obj kvs => 
    simp -zeta only at h
    extract_lets -underBinder jpBp at h
    replace h : has (.obj kvs) "use_blueprint" = false ∧ jpBp () = .ok r := by
      clear_value jpBp
      split at h
      · exact (throw_bind h).elim
      · exact ⟨by simp_all, h⟩
    obtain ⟨hbp, h⟩ := h
    simp -zeta only [jpBp] at h
    clear jpBp
    obtain ⟨_, hkeys, h⟩ := bind_ok h
    extract_lets -underBinder jpAlias at h
    replace h : ∃ al : Option String, (field? (.obj kvs) "alias" = none → al = none) ∧
        (∀ a, al = some a → a ≠ "") ∧ jpAlias al = .ok r := by
      clear_value jpAlias
      split at h
      · rename_i v hv
        obtain ⟨a, _, h⟩ := bind_ok h
        simp only at h
        split at h
        · exact (throw_bind h).elim
        · rename_i hne
          exact ⟨some a, fun hn => (by rw [hn] at hv; cases hv),
            fun a' e => (by cases e; simpa using hne), h⟩
      · exact ⟨none, by simp, by simp, h⟩
    obtain ⟨al, hal1, hal2, h⟩ := h
    simp -zeta only [jpAlias] at h
    clear jpAlias
    extract_lets -underBinder jpIcon at h
    replace h : ∃ ic : Option String, (field? (.obj kvs) "icon" = none → ic = none) ∧
        (∀ i, ic = some i → i.contains ':' = true) ∧ jpIcon ic = .ok r := by
      clear_value jpIcon
      split at h
      · exact ⟨none, by simp, by simp, h⟩
      · rename_i v hv
        obtain ⟨a, _, h⟩ := bind_ok h
        simp only at h
        split at h
        · exact (throw_bind h).elim
        · rename_i hne
          exact ⟨some a, fun hn => (by rw [hn] at hv; cases hv),
            fun a' e => (by cases e; simpa using hne), h⟩
    obtain ⟨ic, hic1, hic2, h⟩ := h
    simp -zeta only [jpIcon] at h
    clear jpIcon
    extract_lets -underBinder jpDesc at h
    replace h : jpDesc () = .ok r := by
      clear_value jpDesc
      split at h
      · obtain ⟨a, _, h⟩ := bind_ok h
        exact h
      · exact h
    simp -zeta only [jpDesc] at h
    clear jpDesc
    extract_lets -underBinder jpTrace at h
    replace h : jpTrace () = .ok r := by
      clear_value jpTrace
      split at h
      · split at h
        · obtain ⟨a, _, h⟩ := bind_ok h
          exact h
        · exact (throw_bind h).elim
      · exact h
    simp -zeta only [jpTrace] at h
    clear jpTrace
    extract_lets -underBinder jpMode at h
    replace h : ∃ m : Mode, (field? (.obj kvs) "mode" = none → m = .single) ∧
        (∀ v, field? (.obj kvs) "mode" = some v → v = .str (modeStr m)) ∧ jpMode m = .ok r := by
      clear_value jpMode
      split at h
      all_goals first
        | exact (throw_bind h).elim
        | (rename_i hv; exact ⟨_, fun hn => (by first | rfl | (rw [hn] at hv; cases hv)),
            fun v e => (by rw [hv] at e; cases e <;> rfl), h⟩)
    obtain ⟨mode, hmode1, hmode2, h⟩ := h
    simp -zeta only [jpMode] at h
    clear jpMode
    extract_lets -underBinder jpMax at h
    replace h : ∃ n : Nat, 2 ≤ n ∧ (field? (.obj kvs) "max" = none → n = 10) ∧
        jpMax n = .ok r := by
      clear_value jpMax
      split at h
      · exact ⟨10, by decide, fun _ => rfl, h⟩
      · rename_i v hv
        split at h
        · split at h
          · exact (throw_bind h).elim
          · rename_i hlt
            exact ⟨_, by omega, fun hn => (by rw [hn] at hv; cases hv), h⟩
        · exact (throw_bind h).elim
    obtain ⟨maxRuns, hmax1, hmax2, h⟩ := h
    simp -zeta only [jpMax] at h
    clear jpMax
    extract_lets -underBinder jpExc at h
    replace h : (∀ me, field? (.obj kvs) "max_exceeded" = some me →
        ∃ c, cvString "max_exceeded" me = .ok c ∧ c.toUpper ∈ MAX_EXCEEDED_CHOICES) ∧
        jpExc () = .ok r := by
      clear_value jpExc
      split at h
      · rename_i me hv
        obtain ⟨c, hc, h⟩ := bind_ok h
        split at h
        · exact (throw_bind h).elim
        · rename_i hin
          exact ⟨fun me' e => (by rw [hv] at e; cases e; exact ⟨c, hc, by simpa using hin⟩), h⟩
      · rename_i hv
        exact ⟨fun me e => absurd e (hv me), h⟩
    obtain ⟨hexc, h⟩ := h
    simp -zeta only [jpExc] at h
    clear jpExc
    extract_lets -underBinder jpFields at h
    replace h : ∃ fs : List String, jpFields fs = .ok r := by
      clear_value jpFields
      split at h
      · exact ⟨_, h⟩
      · obtain ⟨a, _, h⟩ := bind_ok h
        exact ⟨_, h⟩
    obtain ⟨fields, h⟩ := h
    simp -zeta only [jpFields] at h
    clear jpFields
    extract_lets -underBinder jpVars at h
    replace h : ∃ vs : List (String × Json), jpVars vs = .ok r := by
      clear_value jpVars
      split at h
      · exact ⟨_, h⟩
      · obtain ⟨a, _, h⟩ := bind_ok h
        exact ⟨_, h⟩
    obtain ⟨vars, h⟩ := h
    simp -zeta only [jpVars] at h
    clear jpVars
    split at h
    rotate_left
    · cases h
    rename_i seqJ hseq
    obtain ⟨_, hca, h⟩ := bind_ok h
    obtain ⟨_, hattr, h⟩ := bind_ok h
    simp only at h
    obtain ⟨mvars, hmv, h⟩ := bind_ok h
    obtain ⟨acts, hacts, h⟩ := bind_ok h
    cases h
    cases hr
    have hkey : key ≠ "" := by
      intro e; subst e; simp [isSlug] at hslug
    refine ⟨hslug, by simpa using hres, ⟨kvs, rfl, ?_⟩, hbp, ⟨seqJ, hseq, hca⟩, rfl, rfl, rfl, rfl,
      hic2, hic1, rfl, rfl, rfl, rfl, rfl, ?_, ?_, hmax1, hmax2, hmode1, hmode2, hexc⟩
    · intro p hp
      simpa using forIn_guard_ok (c := fun x => !SCRIPT_KEYS.contains x.1) hkeys p hp
    · show al.getD key ≠ ""
      cases al with
      | none => exact hkey
      | some a => exact hal2 a rfl
    · intro hn
      show al.getD key = key
      rw [hal1 hn]; rfl
  | _ => cases h

private theorem error_of_not_ok {α : Type} {x : D α} (h : ∀ r, x ≠ .ok r) : ∃ m, x = .error m := by
  cases x with
  | error m => exact ⟨m, rfl⟩
  | ok r => exact absurd rfl (h r)

/-- `_SCRIPT_OBJECT_ID_SCHEMA`: an object id that is not a valid slug is
refused. -/
theorem decodeScript_not_slug (key : String) (j : Json) (extra : List String)
    (h : ¬ ValidSlug key.toList) : ∃ m, decodeScript key j extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => h ((isSlug_iff key).1 (decodeScript_ok key j extra s a hr).1)

/-- `_SCRIPT_OBJECT_ID_SCHEMA`: `reload`, `turn_on`, `turn_off` and `toggle`
are refused. -/
theorem decodeScript_reserved (key : String) (j : Json) (extra : List String)
    (h : key ∈ INVALID_OBJECT_IDS) : ∃ m, decodeScript key j extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => (decodeScript_ok key j extra s a hr).2.1 h

/-- A config that is not a mapping is refused. -/
theorem decodeScript_not_mapping (key : String) (j : Json) (extra : List String)
    (h : ∀ kvs, j ≠ .obj kvs) : ∃ m, decodeScript key j extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => by
    obtain ⟨kvs, hj, _⟩ := (decodeScript_ok key j extra s a hr).2.2.1
    exact h kvs hj

/-- A key outside `SCRIPT_ENTITY_SCHEMA` is refused (`extra keys not
allowed`). -/
theorem decodeScript_extra_key (key : String) (kvs : Std.TreeMap.Raw String Json compare)
    (extra : List String) (p : String × Json) (hp : p ∈ kvs.toList) (hk : p.1 ∉ SCRIPT_KEYS) :
    ∃ m, decodeScript key (.obj kvs) extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => by
    obtain ⟨kvs', hj, hall⟩ := (decodeScript_ok key _ extra s a hr).2.2.1
    cases hj
    exact hk (hall p hp)

/-- Blueprint scripts are refused. -/
theorem decodeScript_blueprint (key : String) (j : Json) (extra : List String)
    (h : has j "use_blueprint" = true) : ∃ m, decodeScript key j extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => by
    have := (decodeScript_ok key j extra s a hr).2.2.2.1
    simp [h] at this

/-- `sequence` is required. -/
theorem decodeScript_no_sequence (key : String) (j : Json) (extra : List String)
    (h : field? j "sequence" = none) : ∃ m, decodeScript key j extra = .error m :=
  error_of_not_ok fun ⟨s, a⟩ hr => by
    obtain ⟨seq, hs, _⟩ := (decodeScript_ok key j extra s a hr).2.2.2.2.1
    rw [h] at hs; cases hs

/-- An accepted script's service name is never one of the domain's own
services, so `planCall`'s two branches cannot collide. -/
theorem decodeScript_not_domain_service (key : String) (j : Json) (extra : List String)
    (s : ScriptEntity) (a : Automation) (h : decodeScript key j extra = .ok (s, a)) :
    s.objectId ∉ DOMAIN_SERVICES := by
  obtain ⟨_, hres, _, _, _, hid, _⟩ := decodeScript_ok key j extra s a h
  rw [hid]
  simpa [INVALID_OBJECT_IDS, DOMAIN_SERVICES, or_comm, or_assoc, or_left_comm] using hres

/-- Every script `decodeAll` accepts is the entity `script.<its key>`, with
the key as its service name, and never a domain service. -/
theorem decodeAll_ok (scripts : List (String × Json)) (autos : List Json) (k : String)
    (s : ScriptEntity) (a : Automation) (h : (k, Except.ok (s, a)) ∈ decodeAll scripts autos) :
    s.objectId = k ∧ s.entityId = "script." ++ k ∧ s.alive = true ∧
    a.entityId = some ("script." ++ k) ∧ ValidSlug k.toList ∧ k ∉ DOMAIN_SERVICES := by
  simp only [decodeAll, List.mem_map] at h
  obtain ⟨⟨k', j⟩, _, he⟩ := h
  simp only [Prod.mk.injEq] at he
  obtain ⟨rfl, he⟩ := he
  have h := decodeScript_ok k' j _ s a he
  have hnd := decodeScript_not_domain_service k' j _ s a he
  obtain ⟨hslug, _, _, _, _, hid, heid, halive, _, _, _, _, _, _, haeid, _⟩ := h
  rw [hid] at hnd
  exact ⟨hid, heid, halive, by rw [haeid, heid], (isSlug_iff k').1 hslug, hnd⟩

/-! ### Reserved ids -/

/-- `_INVALID_OBJECT_IDS` are exactly the services `async_setup` registers
for the domain, so a script can never shadow one of them. -/
theorem invalid_object_ids_iff (s : String) : s ∈ INVALID_OBJECT_IDS ↔ s ∈ DOMAIN_SERVICES := by
  simp [INVALID_OBJECT_IDS, DOMAIN_SERVICES]
  constructor <;> (intro h; rcases h with h | h | h | h <;> simp [h])

end HALean.Script
