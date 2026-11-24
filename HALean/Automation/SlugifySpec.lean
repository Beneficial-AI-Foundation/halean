/-
  What `cv.slug` accepts. `cv.slug(value)` returns `value` iff
  `str(value) == util.slugify(str(value))`; on the text `slugify?` models
  that holds exactly for `""` and the valid slugs (`slugify_fixed_iff`).
-/
import HALean.Automation.Slugify
import HALean.Template.PyIntSpec

namespace HALean.Automation
open HALean.Template

/-- A valid slug: non-empty, `[0-9a-z_]`, no leading or trailing `_`, no `__`. -/
def ValidSlug (cs : List Char) : Prop :=
  cs ≠ [] ∧ (∀ c ∈ cs, c.isDigit ∨ ('a' ≤ c ∧ c ≤ 'z') ∨ c = '_') ∧
  cs.head? ≠ some '_' ∧ cs.getLast? ≠ some '_' ∧ ¬ ∃ a b, cs = a ++ '_' :: '_' :: b

/-! ### Characters -/

/-- Decide simple facts about ASCII character ranges by `omega`. -/
local macro "char_omega" : tactic => `(tactic| (
  have : ('0' : Char).val.toNat = 48 := rfl
  have : ('9' : Char).val.toNat = 57 := rfl
  have : ('a' : Char).val.toNat = 97 := rfl
  have : ('z' : Char).val.toNat = 122 := rfl
  have : ('A' : Char).val.toNat = 65 := rfl
  have : ('Z' : Char).val.toNat = 90 := rfl
  have : ('-' : Char).val.toNat = 45 := rfl
  have : ('_' : Char).val.toNat = 95 := rfl
  have : (',' : Char).val.toNat = 44 := rfl
  have : ('\'' : Char).val.toNat = 39 := rfl
  simp only [Char.isDigit, Bool.and_eq_true, decide_eq_true_eq, Char.le_def, UInt32.le_iff_toNat_le,
    Char.ext_iff, ← UInt32.toNat_inj, beq_iff_eq, ne_eq, Bool.not_eq_true, ge_iff_le,
    slugDisallowed, Bool.not_eq_eq_eq_not, Bool.not_true, Bool.or_eq_false_iff, Bool.or_eq_true,
    Bool.and_eq_false_iff, decide_eq_false_iff_not, beq_eq_false_iff_ne] at *
  omega))

theorem toLower_not_upper (d : Char) : ¬ ('A' ≤ d.toLower ∧ d.toLower ≤ 'Z') := by
  unfold Char.toLower
  have : ('A' : Char).val.toNat = 65 := rfl
  have : ('Z' : Char).val.toNat = 90 := rfl
  have : (('a' : Char).val - ('A' : Char).val).toNat = 32 := rfl
  split
  · rename_i h
    have h1 := UInt32.le_iff_toNat_le.mp h.1
    have h2 := UInt32.le_iff_toNat_le.mp h.2
    simp only [Char.le_def, UInt32.le_iff_toNat_le, UInt32.toNat_add] at *
    omega
  · rename_i h
    simp only [Char.le_def, UInt32.le_iff_toNat_le] at *
    omega

theorem toLower_id (d : Char) (h : ¬ ('A' ≤ d ∧ d ≤ 'Z')) : d.toLower = d := by
  unfold Char.toLower
  rw [dite_eq_right]
  simpa [Char.le_def] using h

/-- What the pipeline keeps before the final `-` → `_`: `[-0-9a-z]`. -/
def SlugChar (c : Char) : Prop := c = '-' ∨ c.isDigit ∨ ('a' ≤ c ∧ c ≤ 'z')

/-- A character of a valid slug. -/
def ValidChar (c : Char) : Prop := c.isDigit ∨ ('a' ≤ c ∧ c ≤ 'z') ∨ c = '_'

theorem slugChar_of (c : Char) (h1 : slugDisallowed c = false) (h2 : ¬ ('A' ≤ c ∧ c ≤ 'Z')) :
    SlugChar c := by
  simp only [slugDisallowed, Bool.not_eq_false', Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true,
    decide_eq_true_eq] at h1
  unfold SlugChar
  rcases h1 with ((h | h) | h) | h
  · exact .inl h
  · exact .inr (.inl h)
  · exact .inr (.inr h)
  · exact absurd h h2

theorem slugChar_us {c : Char} (h : SlugChar c) (hc : (if c == '-' then '_' else c) = '_') : c = '-' := by
  unfold SlugChar at h; split at hc
  · next h' => exact beq_iff_eq.mp h'
  · subst hc; char_omega

theorem validChar_facts {c : Char} (h : ValidChar c) :
    (c == '\'') = false ∧ ¬ ('A' ≤ c ∧ c ≤ 'Z') ∧ c ≠ ',' ∧ c ≠ '-' ∧
      (slugDisallowed c = true ↔ c = '_') := by
  unfold ValidChar at h
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · char_omega
  · char_omega
  · char_omega
  · char_omega
  · constructor
    · intro h'; char_omega
    · rintro rfl; decide

/-! ### Adjacent pairs -/

/-- No two adjacent characters both satisfy `p`. -/
def NoAdj (p : Char → Bool) (l : List Char) : Prop :=
  ¬ ∃ a u v b, l = a ++ u :: v :: b ∧ p u = true ∧ p v = true

theorem noAdj_cons {p : Char → Bool} {y : Char} {R : List Char} (hR : NoAdj p R)
    (hy : p y = true → R.head?.all (fun c => !p c)) : NoAdj p (y :: R) := by
  rintro ⟨a, u, v, b, h, pu, pv⟩
  cases a with
  | nil =>
    simp only [List.nil_append, List.cons.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa [pv] using hy pu
  | cons a0 a' =>
    simp only [List.cons_append, List.cons.injEq] at h
    exact hR ⟨a', u, v, b, h.2, pu, pv⟩

theorem noAdj_tail {p : Char → Bool} {y : Char} {R : List Char} (h : NoAdj p (y :: R)) : NoAdj p R := by
  rintro ⟨a, u, v, b, rfl, pu, pv⟩
  exact h ⟨y :: a, u, v, b, rfl, pu, pv⟩

theorem noAdj_head {p : Char → Bool} {y z : Char} {R : List Char} (h : NoAdj p (y :: z :: R))
    (hy : p y = true) : p z = false := by
  cases hz : p z
  · rfl
  · exact absurd ⟨[], y, z, R, rfl, hy, hz⟩ h

theorem noAdj_infix {p : Char → Bool} {x m y : List Char} (h : NoAdj p (x ++ m ++ y)) : NoAdj p m := by
  rintro ⟨a, u, v, b, rfl, pu, pv⟩
  exact h ⟨x ++ a, u, v, b ++ y, by simp, pu, pv⟩

theorem noAdj_map {p : Char → Bool} {f : Char → Char} {l : List Char}
    (h : NoAdj (fun c => p (f c)) l) : NoAdj p (l.map f) := by
  rintro ⟨a, u, v, b, hl, pu, pv⟩
  obtain ⟨l1, l2, rfl, -, h2⟩ := List.map_eq_append_iff.mp hl
  obtain ⟨u', l3, rfl, rfl, h3⟩ := List.map_eq_cons_iff.mp h2
  obtain ⟨v', l4, rfl, rfl, -⟩ := List.map_eq_cons_iff.mp h3
  exact h ⟨l1, u', v', l4, rfl, pu, pv⟩

theorem noAdj_mono {p q : Char → Bool} {l : List Char} (h : NoAdj p l)
    (hq : ∀ c ∈ l, q c = true → p c = true) : NoAdj q l := by
  rintro ⟨a, u, v, b, rfl, qu, qv⟩
  exact h ⟨a, u, v, b, rfl, hq u (by simp) qu, hq v (by simp) qv⟩

theorem noAdj_us_iff {l : List Char} : NoAdj (· == '_') l ↔ ¬ ∃ a b, l = a ++ '_' :: '_' :: b := by
  constructor
  · rintro h ⟨a, b, rfl⟩; exact h ⟨a, '_', '_', b, rfl, rfl, rfl⟩
  · rintro h ⟨a, u, v, b, rfl, hu, hv⟩
    simp only [beq_iff_eq] at hu hv; subst hu hv
    exact h ⟨a, b, rfl⟩

/-! ### Pipeline steps -/

theorem map_eq_self {f : Char → Char} : ∀ {l : List Char}, (∀ c ∈ l, f c = c) → l.map f = l
  | [], _ => rfl
  | c :: l, h => by
    rw [List.map_cons, h c List.mem_cons_self, map_eq_self (fun d hd => h d (List.mem_cons_of_mem _ hd))]

/-- Without `p`-characters `subRunsAux` is the identity. -/
theorem subRunsAux_id {p : Char → Bool} {r : List Char} :
    ∀ {b : Bool} {cs : List Char}, (∀ c ∈ cs, p c = false) → subRunsAux p r b cs = cs
  | _, [], _ => rfl
  | _, c :: cs, h => by
    simp only [subRunsAux, h c List.mem_cons_self, Bool.false_eq_true, ite_false]
    rw [subRunsAux_id (fun d hd => h d (List.mem_cons_of_mem _ hd))]

/-- With isolated `p`-characters and a one-character replacement, `subRunsAux`
replaces each `p`-character. -/
theorem subRunsAux_map {p : Char → Bool} {x : Char} :
    ∀ {b : Bool} {cs : List Char}, NoAdj p cs → (b = true → cs.head?.all (fun c => !p c)) →
      subRunsAux p [x] b cs = cs.map (fun c => if p c then x else c)
  | _, [], _, _ => rfl
  | b, c :: cs, hn, hb => by
    by_cases hc : p c = true
    · have hbf : b = false := by
        cases b
        · rfl
        · simpa [hc] using hb rfl
      subst hbf
      simp only [subRunsAux, hc, ite_true, Bool.false_eq_true, ite_false, List.map_cons,
        List.singleton_append]
      rw [subRunsAux_map (noAdj_tail hn)]
      intro _
      cases cs with
      | nil => rfl
      | cons d ds => simp [noAdj_head hn hc]
    · simp only [Bool.not_eq_true] at hc
      simp only [subRunsAux, hc, Bool.false_eq_true, ite_false, List.map_cons]
      rw [subRunsAux_map (noAdj_tail hn) (by simp)]

theorem mem_subRunsAux {p : Char → Bool} {r : List Char} :
    ∀ {b : Bool} {cs : List Char} {c : Char}, c ∈ subRunsAux p r b cs → (c ∈ cs ∧ p c = false) ∨ c ∈ r
  | _, [], _, h => by simp [subRunsAux] at h
  | b, d :: cs, c, h => by
    simp only [subRunsAux] at h
    split at h
    · rcases List.mem_append.mp h with h | h
      · split at h
        · simp at h
        · exact .inr h
      · rcases mem_subRunsAux h with ⟨h1, h2⟩ | h
        · exact .inl ⟨List.mem_cons_of_mem _ h1, h2⟩
        · exact .inr h
    · rename_i hd
      rcases List.mem_cons.mp h with rfl | h
      · exact .inl ⟨List.mem_cons_self, by simpa using hd⟩
      · rcases mem_subRunsAux h with ⟨h1, h2⟩ | h
        · exact .inl ⟨List.mem_cons_of_mem _ h1, h2⟩
        · exact .inr h

/-- Replacing runs of `p` by a `p`-character leaves no adjacent `p`-pair, and
none at the head when the input continues a run. -/
theorem subRunsAux_noAdj {p : Char → Bool} {x : Char} (hx : p x = true) :
    ∀ {b : Bool} {cs : List Char},
      NoAdj p (subRunsAux p [x] b cs) ∧ (b = true → (subRunsAux p [x] b cs).head?.all (fun c => !p c))
  | _, [] => ⟨by rintro ⟨a, u, v, b, h, -⟩; simp [subRunsAux] at h, by simp [subRunsAux]⟩
  | b, c :: cs => by
    obtain ⟨ih1, ih2⟩ := subRunsAux_noAdj hx (b := true) (cs := cs)
    obtain ⟨jh1, -⟩ := subRunsAux_noAdj hx (b := false) (cs := cs)
    simp only [subRunsAux]
    by_cases hc : p c = true
    · cases b
      · simp only [hc, ite_true, Bool.false_eq_true, ite_false, List.singleton_append]
        exact ⟨noAdj_cons ih1 (fun _ => ih2 rfl), by simp⟩
      · simp only [hc, ite_true, List.nil_append]
        exact ⟨ih1, fun _ => ih2 rfl⟩
    · simp only [hc, Bool.false_eq_true, ite_false]
      exact ⟨noAdj_cons jh1 (fun h => absurd h hc), fun _ => by simpa using hc⟩

theorem mem_delDigitCommas : ∀ {prev : Option Char} {cs : List Char} {c : Char},
    c ∈ delDigitCommas prev cs → c ∈ cs
  | _, [], _, h => by simp [delDigitCommas] at h
  | prev, d :: cs, c, h => by
    simp only [delDigitCommas] at h
    split at h
    · exact List.mem_cons_of_mem _ (mem_delDigitCommas h)
    · rcases List.mem_cons.mp h with rfl | h
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (mem_delDigitCommas h)

theorem delDigitCommas_id : ∀ {prev : Option Char} {cs : List Char},
    (∀ c ∈ cs, c ≠ ',') → delDigitCommas prev cs = cs
  | _, [], _ => rfl
  | prev, d :: cs, h => by
    have hd : (d == ',') = false := by simpa using h d List.mem_cons_self
    simp only [delDigitCommas, hd, Bool.false_and, Bool.false_eq_true, ite_false]
    rw [delDigitCommas_id (fun c hc => h c (List.mem_cons_of_mem _ hc))]

theorem getLast?_dropWhile_of_ne {p : Char → Bool} {l : List Char} (h : l.dropWhile p ≠ []) :
    (l.dropWhile p).getLast? = l.getLast? := by
  conv => rhs; rw [← List.takeWhile_append_dropWhile (p := p) (l := l)]
  rw [List.getLast?_append]
  cases hd : (l.dropWhile p).getLast? with
  | none => exact absurd (List.getLast?_eq_none_iff.mp hd) h
  | some x => rfl

/-- The core `stripBy` leaves neither starts nor ends with a `p`-character. -/
theorem stripBy_ends {p : Char → Bool} {l : List Char} :
    (stripBy p l).head?.all (fun c => !p c) ∧ (stripBy p l).getLast?.all (fun c => !p c) := by
  unfold stripBy
  generalize hm : l.dropWhile p = m
  have hm' : m.head?.all (fun c => !p c) := by
    have := List.head?_dropWhile_not p l
    rw [hm] at this
    cases h : m.head? <;> simp_all
  constructor
  · rw [List.head?_reverse]
    by_cases hne : m.reverse.dropWhile p = []
    · simp [hne]
    · rw [getLast?_dropWhile_of_ne hne, List.getLast?_reverse]; exact hm'
  · rw [List.getLast?_reverse]
    have := List.head?_dropWhile_not p m.reverse
    cases h : (m.reverse.dropWhile p).head? <;> simp_all

/-! ### The pipeline output -/

/-- The final `-` → `_` of a `[-0-9a-z]` core without `--` or edge `-` is a
valid slug. -/
theorem valid_of_core {t : List Char} (hne : t ≠ []) (ha : ∀ c ∈ t, SlugChar c)
    (hn : NoAdj (· == '-') t) (hh : t.head?.all (fun c => !(c == '-')))
    (hl : t.getLast?.all (fun c => !(c == '-'))) :
    ValidSlug (t.map fun c => if c == '-' then '_' else c) := by
  refine ⟨by simpa using hne, ?_, ?_, ?_, ?_⟩
  · intro c hc
    obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hc
    have := ha d hd
    unfold SlugChar at this
    by_cases h : d = '-'
    · simp [h]
    · simp only [beq_iff_eq, h, ite_false]
      rcases this with h' | h' | h'
      · exact absurd h' h
      · exact .inl h'
      · exact .inr (.inl h')
  · rw [List.head?_map]
    cases e : t.head? with
    | none => simp
    | some d =>
      intro h
      simp only [Option.map_some, Option.some.injEq] at h
      have := slugChar_us (ha d (List.mem_of_mem_head? e)) h
      simp [e, this] at hh
  · rw [List.getLast?_map]
    cases e : t.getLast? with
    | none => simp
    | some d =>
      intro h
      simp only [Option.map_some, Option.some.injEq] at h
      have := slugChar_us (ha d (List.mem_of_getLast? e)) h
      simp [e, this] at hl
  · rw [← noAdj_us_iff]
    apply noAdj_map
    refine noAdj_mono hn (fun c hc h => ?_)
    simpa using slugChar_us (ha c hc) (by simpa using h)

/-- Whenever slugify's pipeline gives a non-empty result, it is a valid slug. -/
theorem slugifyChars_valid (t : List Char) (hne : slugifyChars t ≠ []) : ValidSlug (slugifyChars t) := by
  unfold slugifyChars subRuns at *
  dsimp only at *
  generalize subRunsAux (· == '\'') ['-'] false t = t1 at *
  generalize e3 : subRunsAux (· == '\'') [] false (t1.map Char.toLower) = t3 at *
  generalize e5 : subRunsAux slugDisallowed ['-'] false (delDigitCommas none t3) = t5 at *
  generalize e6 : subRunsAux (· == '-') ['-'] false t5 = t6 at *
  have h5 : ∀ c ∈ t5, SlugChar c := by
    intro c hc
    rw [← e5] at hc
    rcases mem_subRunsAux hc with ⟨h4, hd⟩ | h
    · have h3 := mem_delDigitCommas h4
      rw [← e3] at h3
      rcases mem_subRunsAux h3 with ⟨h2, -⟩ | h
      · obtain ⟨d, -, rfl⟩ := List.mem_map.mp h2
        exact slugChar_of _ hd (toLower_not_upper d)
      · simp at h
    · simp only [List.mem_singleton] at h; exact .inl h
  have h6 : ∀ c ∈ t6, SlugChar c := by
    intro c hc
    rw [← e6] at hc
    rcases mem_subRunsAux hc with ⟨h, -⟩ | h
    · exact h5 c h
    · simp only [List.mem_singleton] at h; exact .inl h
  have n6 : NoAdj (· == '-') t6 := e6 ▸ (subRunsAux_noAdj (p := (· == '-')) (x := '-') rfl).1
  obtain ⟨w1, w2, e, -, -⟩ := stripBy_split (· == '-') t6
  have n7 : NoAdj (· == '-') (stripBy (· == '-') t6) := noAdj_infix (e ▸ n6)
  have h7 : ∀ c ∈ stripBy (· == '-') t6, SlugChar c := by
    intro c hc; apply h6; rw [e]; simp [hc]
  exact valid_of_core (by simpa using hne) h7 n7 stripBy_ends.1 stripBy_ends.2

/-- On a valid slug every step of the pipeline is the identity, except that
`[^-a-zA-Z0-9]+` turns each (isolated) `_` into `-` and the last step turns it back. -/
theorem slugifyChars_of_valid {cs : List Char} (h : ValidSlug cs) : slugifyChars cs = cs := by
  obtain ⟨hne, hc, hh, hl, hn⟩ := h
  have hv : ∀ c ∈ cs, ValidChar c := hc
  have nu : NoAdj (· == '_') cs := noAdj_us_iff.mpr hn
  unfold slugifyChars subRuns
  simp only []
  rw [subRunsAux_id (fun c h => (validChar_facts (hv c h)).1),
    map_eq_self (fun c h => toLower_id c (validChar_facts (hv c h)).2.1),
    subRunsAux_id (fun c h => (validChar_facts (hv c h)).1),
    delDigitCommas_id (fun c h => (validChar_facts (hv c h)).2.2.1),
    subRunsAux_map (noAdj_mono nu (fun c h h' => by simpa using ((validChar_facts (hv c h)).2.2.2.2).mp h'))
      (by simp)]
  generalize eg : (fun c => if slugDisallowed c = true then '-' else c) = g
  have hg : ∀ c ∈ cs, g c = if c = '_' then '-' else c := by
    intro c hc; rw [← eg]
    have := (validChar_facts (hv c hc)).2.2.2.2
    by_cases hu : c = '_'
    · subst hu; simp [show slugDisallowed '_' = true by decide]
    · simp [hu, this]
  have hgd : ∀ c ∈ cs, (g c == '-') = true → (c == '_') = true := by
    intro c hc h'
    have := (validChar_facts (hv c hc)).2.2.2.1
    rw [hg c hc] at h'
    by_cases hu : c = '_' <;> simp_all
  rw [subRunsAux_map (noAdj_map (noAdj_mono nu hgd)) (by simp)]
  have hid : (cs.map g).map (fun c => if (c == '-') = true then '-' else c) = cs.map g :=
    map_eq_self (fun c _ => by
      split
      · next h' => exact (beq_iff_eq.mp h').symm
      · rfl)
  rw [hid]
  have hcore : stripBy (· == '-') (cs.map g) = cs.map g := by
    have hh' : (cs.map g).head?.all (fun c => !(c == '-')) := by
      rw [List.head?_map]
      cases e : cs.head? with
      | none => rfl
      | some d =>
        have hd := List.mem_of_mem_head? e
        rw [e] at hh
        have : d ≠ '_' := fun h => hh (h ▸ rfl)
        simp [hg d hd, this, (validChar_facts (hv d hd)).2.2.2.1]
    have hl' : (cs.map g).getLast?.all (fun c => !(c == '-')) := by
      rw [List.getLast?_map]
      cases e : cs.getLast? with
      | none => rfl
      | some d =>
        have hd := List.mem_of_getLast? e
        rw [e] at hl
        have : d ≠ '_' := fun h => hl (h ▸ rfl)
        simp [hg d hd, this, (validChar_facts (hv d hd)).2.2.2.1]
    simpa using stripBy_eq (p := (· == '-')) (w1 := []) (w2 := []) (by simp) (by simp) hh' hl'
      (by simpa using hne)
  rw [hcore, List.map_map]
  apply map_eq_self
  intro c hc
  simp only [Function.comp, hg c hc]
  by_cases hu : c = '_'
  · simp [hu]
  · simp [hu, (validChar_facts (hv c hc)).2.2.2.1]

/-! ### `slugify?` -/

theorem slugify?_of_ne {s : String} (hs : slugify? s ≠ none) (he : s ≠ "") :
    slugify? s = some (if (slugifyChars s.toList).isEmpty then "unknown"
      else String.ofList (slugifyChars s.toList)) := by
  unfold slugify? at *
  have he' : s.isEmpty = false := by simpa using he
  simp only [he'] at *
  split at hs <;> simp_all

/-- **`cv.slug` accepts exactly the valid slugs (and `""`)** on the text slugify? models. -/
theorem slugify_fixed_iff (s : String) (hs : slugify? s ≠ none) :
    slugify? s = some s ↔ s = "" ∨ ValidSlug s.toList := by
  by_cases he : s = ""
  · subst he; simp only [true_or, iff_true]; decide
  rw [slugify?_of_ne hs he]
  simp only [he, false_or, Option.some.injEq]
  constructor
  · intro h
    split at h
    · subst h
      have hu : slugifyChars "unknown".toList = "unknown".toList := by decide
      exact hu ▸ slugifyChars_valid _ (by rw [hu]; decide)
    · rename_i hne
      rw [← h, String.toList_ofList]
      exact slugifyChars_valid _ (by simpa using hne)
  · intro h
    rw [slugifyChars_of_valid h]
    have : s.toList.isEmpty = false := by simpa using h.1
    simp [this, String.ofList_toList]

end HALean.Automation
