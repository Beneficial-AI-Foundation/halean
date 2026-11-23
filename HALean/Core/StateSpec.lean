/-
  Specifications of the entity-id helpers in `HALean/Core/State.lean`,
  proved against what the upstream functions compute:

  * `validEntityId_iff`: `valid_entity_id` is exactly its regex
  * `validDomain_iff`: `valid_domain` is exactly its regex
  * `splitEntityId_some`: `split_entity_id` is `str.partition(".")` with
    both sides non-empty

  The regexes are written out as predicates (`EntityIdRe`, `DomainRe`),
  clause by clause; Python's `$` also matches before one final newline, and
  `\d` is read as the ASCII digits (Python's class is Unicode-aware, which is
  why callers reject non-ASCII ids).
-/
import HALean.Core.State
namespace HALean.Core

theorem span_loop {α} (p : α → Bool) : ∀ (as acc : List α),
    List.span.loop p as acc = (acc.reverse ++ as.takeWhile p, as.dropWhile p)
  | [], acc => by simp [List.span.loop]
  | a :: as, acc => by
    unfold List.span.loop
    cases h : p a
    · simp [List.takeWhile_cons, List.dropWhile_cons, h]
    · simp [List.takeWhile_cons, List.dropWhile_cons, h, span_loop p as (a :: acc)]

theorem span_eq {α} (p : α → Bool) (as : List α) :
    as.span p = (as.takeWhile p, as.dropWhile p) := by
  simp [List.span, span_loop]

theorem partitionDot_cons (c : Char) (cs : List Char) :
    partitionDot (c :: cs) =
      if c = '.' then ([], some cs) else (c :: (partitionDot cs).1, (partitionDot cs).2) := by
  unfold partitionDot
  rw [span_eq, span_eq]
  by_cases hc : c = '.'
  · subst hc; simp
  · have : (c != '.') = true := by simpa using hc
    simp only [List.takeWhile_cons, List.dropWhile_cons, this, hc, ite_false, ite_true]
    split <;> simp_all

end HALean.Core

namespace HALean.Core

theorem partitionDot_some {cs d o : List Char} :
    partitionDot cs = (d, some o) ↔ cs = d ++ '.' :: o ∧ '.' ∉ d := by
  induction cs generalizing d with
  | nil => simp [partitionDot, span_eq]
  | cons c cs ih =>
    rw [partitionDot_cons]
    by_cases hc : c = '.'
    · subst hc
      simp only [ite_true, Prod.mk.injEq, Option.some.injEq]
      constructor
      · rintro ⟨rfl, rfl⟩; simp
      · rintro ⟨h, hd⟩
        cases d with
        | nil => simp at h; exact ⟨rfl, h⟩
        | cons x d =>
          simp only [List.cons_append, List.cons.injEq] at h
          exact absurd (h.1 ▸ List.mem_cons_self) hd
    · simp only [hc, ite_false, Prod.mk.injEq]
      constructor
      · rintro ⟨rfl, h2⟩
        have := (ih (d := (partitionDot cs).1)).mp (Prod.ext rfl h2)
        refine ⟨by rw [List.cons_append, ← this.1], ?_⟩
        simp only [List.mem_cons, not_or]; exact ⟨fun e => hc e.symm, this.2⟩
      · rintro ⟨h, hd⟩
        cases d with
        | nil => simp at h; exact absurd h.1 hc
        | cons x d =>
          simp only [List.cons_append, List.cons.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          simp only [List.mem_cons, not_or] at hd
          have := (ih (d := d)).mpr ⟨rfl, hd.2⟩
          rw [this]; simp

/-! ### The regex of `valid_entity_id`, as a predicate -/

/-- `(?!_)[\da-z_]+(?<!_)`, with `\d` read as ASCII digits. -/
def SlugRe (x : List Char) : Prop :=
  x ≠ [] ∧ (∀ c ∈ x, isSlugChar c) ∧ x.head? ≠ some '_' ∧ x.getLast? ≠ some '_'

/-- The lookahead `(?!.+__)` fails: one or more characters other than a
newline (`.`), then `__`. -/
def LaterDoubleUnderscore (cs : List Char) : Prop :=
  ∃ a b, cs = a ++ '_' :: '_' :: b ∧ a ≠ [] ∧ '\n' ∉ a

/-- `VALID_ENTITY_ID.match(entity_id) is not None`, with
`^(?!.+__)(?!_)[\da-z_]+(?<!_)\.(?!_)[\da-z_]+(?<!_)$`; Python's `$` also
matches before one final newline. -/
def EntityIdRe (cs : List Char) : Prop :=
  ¬ LaterDoubleUnderscore cs ∧
  ∃ d o, (cs = d ++ '.' :: o ∨ cs = d ++ '.' :: o ++ ['\n']) ∧ SlugRe d ∧ SlugRe o

theorem validSlug_iff (x : List Char) : validSlug x = true ↔ SlugRe x := by
  unfold validSlug SlugRe
  cases x with
  | nil => simp
  | cons c x => simp [List.all_eq_true, and_assoc]

theorem hasDoubleUnderscore_cons (c : Char) (r : List Char) :
    hasDoubleUnderscore (c :: r) = ((c == '_' && r.head? == some '_') || hasDoubleUnderscore r) := by
  by_cases hc : c = '_'
  · subst hc
    cases r with
    | nil => simp [hasDoubleUnderscore]
    | cons d r =>
      by_cases hd : d = '_'
      · subst hd; simp [hasDoubleUnderscore]
      · simp [hasDoubleUnderscore, hd]
  · cases r with
    | nil => simp [hasDoubleUnderscore, hc]
    | cons d r =>
      have : (c == '_') = false := by simpa using hc
      simp only [this, Bool.false_and, Bool.false_or]
      conv => lhs; unfold hasDoubleUnderscore
      split
      · rename_i h; simp at h; exact absurd h.1 hc
      · rename_i h; simp at h; obtain ⟨-, rfl⟩ := h; rfl
      · simp at *

theorem hasDoubleUnderscore_iff (cs : List Char) :
    hasDoubleUnderscore cs = true ↔ ∃ a b, cs = a ++ '_' :: '_' :: b := by
  induction cs with
  | nil => simp [hasDoubleUnderscore]
  | cons c r ih =>
    rw [hasDoubleUnderscore_cons]
    simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, ih]
    constructor
    · rintro (⟨rfl, h⟩ | ⟨a, b, rfl⟩)
      · cases r with
        | nil => simp at h
        | cons d r => simp at h; subst h; exact ⟨[], r, rfl⟩
      · exact ⟨c :: a, b, rfl⟩
    · rintro ⟨a, b, h⟩
      cases a with
      | nil => simp at h; obtain ⟨rfl, rfl⟩ := h; simp
      | cons x a => simp at h; obtain ⟨rfl, rfl⟩ := h; exact .inr ⟨a, b, rfl⟩


theorem slug_no_dot {x : List Char} (h : SlugRe x) : '.' ∉ x := fun hm => by
  have := h.2.1 _ hm; simp [isSlugChar] at this

theorem slug_no_nl {x : List Char} (h : SlugRe x) : '\n' ∉ x := fun hm => by
  have := h.2.1 _ hm; simp [isSlugChar] at this

theorem slug_last_ne_nl {x : List Char} (h : SlugRe x) : x.getLast? ≠ some '\n' := by
  intro e
  exact slug_no_nl h (List.mem_of_getLast? e)

/-- On the part before a final newline: `hasDoubleUnderscore` decides the
lookahead, because a slug cannot start with `_` and has no newline. -/
theorem hasDU_iff_later {d o : List Char} (hd : SlugRe d) (ho : SlugRe o) :
    hasDoubleUnderscore (d ++ '.' :: o) = true ↔ LaterDoubleUnderscore (d ++ '.' :: o) := by
  rw [hasDoubleUnderscore_iff]
  constructor
  · rintro ⟨a, b, h⟩
    refine ⟨a, b, h, ?_, ?_⟩
    · rintro rfl
      cases d with
      | nil => exact hd.1 rfl
      | cons c d => simp at h; exact hd.2.2.1 (by simp [h.1])
    · intro hm
      have : '\n' ∈ d ++ '.' :: o := h ▸ List.mem_append_left _ hm
      simp only [List.mem_append, List.mem_cons] at this
      rcases this with h1 | h1 | h1
      · exact slug_no_nl hd h1
      · cases h1
      · exact slug_no_nl ho h1
  · rintro ⟨a, b, h, -, -⟩; exact ⟨a, b, h⟩

theorem entityIdBody_iff (cs : List Char) :
    entityIdBody cs = true ↔
      ¬ LaterDoubleUnderscore cs ∧ ∃ d o, cs = d ++ '.' :: o ∧ SlugRe d ∧ SlugRe o := by
  unfold entityIdBody
  constructor
  · intro h
    simp only [Bool.and_eq_true, Bool.not_eq_true'] at h
    obtain ⟨hdu, hm⟩ := h
    split at hm
    · rename_i d o hp
      simp only [Bool.and_eq_true, validSlug_iff] at hm
      obtain ⟨rfl, -⟩ := partitionDot_some.mp hp
      refine ⟨fun hl => ?_, d, o, rfl, hm.1, hm.2⟩
      have := (hasDU_iff_later hm.1 hm.2).mpr hl
      simp_all
    · cases hm
  · rintro ⟨hl, d, o, rfl, hd, ho⟩
    have hp : partitionDot (d ++ '.' :: o) = (d, some o) :=
      partitionDot_some.mpr ⟨rfl, slug_no_dot hd⟩
    simp only [hp, Bool.and_eq_true, Bool.not_eq_true', validSlug_iff]
    refine ⟨?_, hd, ho⟩
    cases h : hasDoubleUnderscore (d ++ '.' :: o)
    · rfl
    · exact absurd ((hasDU_iff_later hd ho).mp h) hl


/-- A final newline never helps the lookahead: `.` does not match it. -/
theorem later_append_nl (x : List Char) :
    LaterDoubleUnderscore (x ++ ['\n']) ↔ LaterDoubleUnderscore x := by
  constructor
  · rintro ⟨a, b, h, ha, hn⟩
    rcases List.eq_nil_or_concat b with rfl | ⟨b, z, rfl⟩
    · have := congrArg List.getLast? h
      simp at this
    · refine ⟨a, b, ?_, ha, hn⟩
      have : x ++ ['\n'] = (a ++ '_' :: '_' :: b) ++ [z] := by simp [h]
      exact List.append_inj_left' this rfl
  · rintro ⟨a, b, rfl, ha, hn⟩
    exact ⟨a, b ++ ['\n'], by simp, ha, hn⟩

/-- **`valid_entity_id` is exactly its regex.** For every string, HALean's
`validEntityId` accepts exactly the strings that match
`^(?!.+__)(?!_)[\da-z_]+(?<!_)\.(?!_)[\da-z_]+(?<!_)$` under Python's
`re.match` (with `$` matching before one final newline). `\d` is read as
the ASCII digits: on other Unicode digits Python's class is larger, which
is why callers reject non-ASCII entity ids. -/
theorem validEntityId_iff (s : String) : validEntityId s = true ↔ EntityIdRe s.toList := by
  unfold validEntityId
  generalize s.toList = cs
  by_cases hl : cs.getLast? = some '\n'
  · have hcs : cs = cs.dropLast ++ ['\n'] := by
      have hne : cs ≠ [] := by rintro rfl; simp at hl
      have := List.dropLast_concat_getLast hne
      rw [List.getLast?_eq_some_getLast hne] at hl
      simp only [Option.some.injEq] at hl
      rw [hl] at this; exact this.symm
    simp only [hl, beq_self_eq_true, ite_true]
    rw [entityIdBody_iff]
    unfold EntityIdRe
    rw [hcs, later_append_nl, List.dropLast_concat]
    have tail : ∀ x d o : List Char, x ++ ['\n'] = d ++ '.' :: o ++ ['\n'] → x = d ++ '.' :: o :=
      fun x d o h => List.append_inj_left' (by simpa using h) rfl
    constructor
    · rintro ⟨hl', d, o, h, hd, ho⟩
      exact ⟨hl', d, o, .inr (by rw [h]), hd, ho⟩
    · rintro ⟨hl', d, o, h, hd, ho⟩
      refine ⟨hl', d, o, ?_, hd, ho⟩
      rcases h with h | h
      · exfalso
        have hm : '\n' ∈ d ++ '.' :: o := h ▸ List.mem_append_right _ (List.mem_singleton_self _)
        simp only [List.mem_append, List.mem_cons] at hm
        rcases hm with hm | hm | hm
        · exact slug_no_nl hd hm
        · cases hm
        · exact slug_no_nl ho hm
      · exact tail _ _ _ h
  · have hne : (cs.getLast? == some '\n') = false := by simpa using hl
    simp only [hne]
    rw [entityIdBody_iff]
    unfold EntityIdRe
    constructor
    · rintro ⟨hl', d, o, rfl, hd, ho⟩; exact ⟨hl', d, o, .inl rfl, hd, ho⟩
    · rintro ⟨hl', d, o, h, hd, ho⟩
      refine ⟨hl', d, o, ?_, hd, ho⟩
      rcases h with h | h
      · exact h
      · exact absurd (by simp only [h, List.getLast?_concat]) hl


/-! ### `valid_domain` -/

/-- `VALID_DOMAIN.match(domain) is not None`, with
`^(?!.+__)(?!_)[\da-z_]+(?<!_)$`. -/
def DomainRe (cs : List Char) : Prop :=
  ¬ LaterDoubleUnderscore cs ∧ ∃ x, (cs = x ∨ cs = x ++ ['\n']) ∧ SlugRe x

theorem hasDU_iff_later_slug {x : List Char} (hx : SlugRe x) :
    hasDoubleUnderscore x = true ↔ LaterDoubleUnderscore x := by
  rw [hasDoubleUnderscore_iff]
  constructor
  · rintro ⟨a, b, h⟩
    refine ⟨a, b, h, ?_, fun hm => slug_no_nl hx (h ▸ List.mem_append_left _ hm)⟩
    rintro rfl
    exact hx.2.2.1 (by simp [h])
  · rintro ⟨a, b, h, -, -⟩; exact ⟨a, b, h⟩

/-- **`valid_domain` is exactly its regex** (ASCII digits for `\d`). -/
theorem validDomain_iff (s : String) : validDomain s = true ↔ DomainRe s.toList := by
  unfold validDomain DomainRe
  generalize s.toList = cs
  have body : ∀ x : List Char,
      (!hasDoubleUnderscore x && validSlug x) = true ↔ ¬ LaterDoubleUnderscore x ∧ SlugRe x := by
    intro x
    simp only [Bool.and_eq_true, Bool.not_eq_true', validSlug_iff]
    constructor
    · rintro ⟨h1, h2⟩
      exact ⟨fun hl => (by rw [(hasDU_iff_later_slug h2).mpr hl] at h1; cases h1), h2⟩
    · rintro ⟨h1, h2⟩
      refine ⟨?_, h2⟩
      cases h : hasDoubleUnderscore x
      · rfl
      · exact absurd ((hasDU_iff_later_slug h2).mp h) h1
  by_cases hl : cs.getLast? = some '\n'
  · have hne : cs ≠ [] := by rintro rfl; simp at hl
    have hcs : cs = cs.dropLast ++ ['\n'] := by
      have := List.dropLast_concat_getLast hne
      rw [List.getLast?_eq_some_getLast hne] at hl
      simp only [Option.some.injEq] at hl
      rw [hl] at this; exact this.symm
    simp only [hl, beq_self_eq_true, ite_true, body]
    rw [hcs, later_append_nl, List.dropLast_concat]
    constructor
    · rintro ⟨h1, h2⟩; exact ⟨h1, _, .inr rfl, h2⟩
    · rintro ⟨h1, x, h | h, hx⟩
      · exact absurd (h ▸ List.mem_append_right _ (List.mem_singleton_self _)) (slug_no_nl hx)
      · have e := List.append_inj_left' h rfl
        rw [e] at h1 ⊢; exact ⟨h1, hx⟩
  · have hne : (cs.getLast? == some '\n') = false := by simpa using hl
    simp only [hne, body]
    constructor
    · rintro ⟨h1, h2⟩; exact ⟨h1, _, .inl rfl, h2⟩
    · rintro ⟨h1, x, h | h, hx⟩
      · subst h; exact ⟨h1, hx⟩
      · exact absurd (by simp only [h, List.getLast?_concat]) hl

/-! ### `split_entity_id` -/

/-- **`split_entity_id`**: `entity_id.partition(".")`, a `ValueError` (here
`none`) when the domain or the object id is empty. -/
theorem splitEntityId_some (s d o : String) :
    splitEntityId s = some (d, o) ↔
      s.toList = d.toList ++ '.' :: o.toList ∧ '.' ∉ d.toList ∧ d ≠ "" ∧ o ≠ "" := by
  unfold splitEntityId
  constructor
  · intro h
    split at h
    · rename_i d' o' hp
      obtain ⟨hs, hd⟩ := partitionDot_some.mp hp
      split at h
      · cases h
      · rename_i hne
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        simp only [Bool.or_eq_true, List.isEmpty_iff, not_or] at hne
        simp only [String.toList_ofList, ne_eq, ← String.toList_eq_nil_iff]
        exact ⟨hs, hd, hne.1, hne.2⟩
    · cases h
  · rintro ⟨hs, hd, hdn, hon⟩
    rw [hs, partitionDot_some.mpr ⟨rfl, hd⟩]
    have h1 : d.toList.isEmpty = false := by
      cases h : d.toList with
      | nil => exact absurd (String.toList_eq_nil_iff.mp h) hdn
      | cons _ _ => rfl
    have h2 : o.toList.isEmpty = false := by
      cases h : o.toList with
      | nil => exact absurd (String.toList_eq_nil_iff.mp h) hon
      | cons _ _ => rfl
    simp [h1, h2, String.ofList_toList]

end HALean.Core

