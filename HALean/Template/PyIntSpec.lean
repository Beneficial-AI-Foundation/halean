/-
  Python's `int(str)` on ASCII text, written as its grammar
  (`DigitsUs`, `PyIntSpec`), and `parseIntChars` proved to decide it
  (`parseIntChars_iff`). Non-ASCII digits and spaces, which Python also
  accepts, are outside this (`parseIntChars` rejects them).
-/
import HALean.Template.PyInt

namespace HALean.Template

/-- Python's grammar for the digits of a base-10 integer:
`digit (["_"] digit)*`. -/
inductive DigitsUs : List Char → Prop
  | one {d} : d.isDigit → DigitsUs [d]
  | cons {d rest} : d.isDigit → DigitsUs rest → DigitsUs (d :: rest)
  | us {d rest} : d.isDigit → DigitsUs rest → DigitsUs (d :: '_' :: rest)

/-- `int(s) == n` for an ASCII string `s`: optional whitespace, an optional
sign, the digits, optional whitespace. -/
def PyIntSpec (cs : List Char) (n : Int) : Prop :=
  ∃ w1 sgn body w2, cs = w1 ++ sgn ++ body ++ w2 ∧
    (∀ c ∈ w1, pySpace c) ∧ (∀ c ∈ w2, pySpace c) ∧
    (sgn = [] ∨ sgn = ['+'] ∨ sgn = ['-']) ∧ DigitsUs body ∧
    n = (if sgn = ['-'] then -(digitValue body : Int) else digitValue body)

theorem digitsUs_head {cs : List Char} (h : DigitsUs cs) : ∃ d r, cs = d :: r ∧ d.isDigit := by
  cases h with
  | one hd => exact ⟨_, _, rfl, hd⟩
  | cons hd _ => exact ⟨_, _, rfl, hd⟩
  | us hd _ => exact ⟨_, _, rfl, hd⟩

theorem digitsUs_last {cs : List Char} (h : DigitsUs cs) : ∃ d, cs.getLast? = some d ∧ d.isDigit := by
  induction h with
  | one hd => exact ⟨_, rfl, hd⟩
  | @cons d rest _ hr ih =>
    obtain ⟨e, he, hed⟩ := ih
    obtain ⟨x, r, rfl, -⟩ := digitsUs_head hr
    exact ⟨e, by simpa [List.getLast?_cons_cons] using he, hed⟩
  | @us d rest _ hr ih =>
    obtain ⟨e, he, hed⟩ := ih
    obtain ⟨x, r, rfl, -⟩ := digitsUs_head hr
    exact ⟨e, by simpa [List.getLast?_cons_cons] using he, hed⟩

theorem digitsUs_cc (d e : Char) (rest : List Char) :
    digitsUs (d :: e :: rest) =
      if e = '_' then (d.isDigit && digitsUs rest) else (d.isDigit && digitsUs (e :: rest)) := by
  by_cases he : e = '_'
  · subst he; simp [digitsUs]
  · simp only [he, ite_false]
    conv => lhs; unfold digitsUs
    split
    · rename_i h; simp at h
    · rename_i h; simp at h; exact absurd h.2.1 he
    · rename_i h; simp at h; obtain ⟨rfl, rfl⟩ := h; rfl
    · rename_i h; simp at h

theorem digitsUs_iff (cs : List Char) : digitsUs cs = true ↔ DigitsUs cs := by
  match cs with
  | [] => simp [digitsUs]; intro h; cases h
  | [d] =>
    simp only [digitsUs]
    constructor
    · exact .one
    · intro h; cases h with
      | one hd => exact hd
      | cons _ hr => cases hr
  | d :: e :: rest =>
    rw [digitsUs_cc]
    by_cases he : e = '_'
    · subst he
      simp only [ite_true, Bool.and_eq_true, digitsUs_iff rest]
      constructor
      · rintro ⟨hd, hr⟩; exact .us hd hr
      · intro h; cases h with
        | cons _ hr =>
          obtain ⟨x, r, hx, hxd⟩ := digitsUs_head hr
          cases hx; simp [Char.isDigit] at hxd
        | us hd hr => exact ⟨hd, hr⟩
    · simp only [he, ite_false, Bool.and_eq_true, digitsUs_iff (e :: rest)]
      constructor
      · rintro ⟨hd, hr⟩; exact .cons hd hr
      · intro h; cases h with
        | cons hd hr => exact ⟨hd, hr⟩
        | us _ _ => exact absurd rfl he
termination_by cs.length

/-! ### Stripping whitespace -/

theorem takeWhile_all {p : Char → Bool} : ∀ {l : List Char} {c : Char}, c ∈ l.takeWhile p → p c
  | [], _, h => by simp at h
  | a :: l, c, h => by
    simp only [List.takeWhile_cons] at h
    split at h
    · rename_i ha
      rcases List.mem_cons.mp h with rfl | h
      · exact ha
      · exact takeWhile_all h
    · simp at h

theorem dropWhile_prefix {p : Char → Bool} :
    ∀ {w x : List Char}, (∀ c ∈ w, p c) → (x.head?.all fun c => !p c) → (w ++ x).dropWhile p = x
  | [], [], _, _ => rfl
  | [], a :: x, _, hx => by simp at hx; simp [List.dropWhile_cons, hx]
  | a :: w, x, hw, hx => by
    simp only [List.cons_append, List.dropWhile_cons, hw a List.mem_cons_self, ite_true]
    exact dropWhile_prefix (fun c hc => hw c (List.mem_cons_of_mem _ hc)) hx

/-- Stripping `w1 ++ core ++ w2`, with `p`-characters around a core that
starts and ends with other characters, gives the core. -/
theorem stripBy_eq {p : Char → Bool} {w1 core w2 : List Char} (h1 : ∀ c ∈ w1, p c) (h2 : ∀ c ∈ w2, p c)
    (hh : core.head?.all fun c => !p c) (hl : core.getLast?.all fun c => !p c)
    (hne : core ≠ []) : stripBy p (w1 ++ core ++ w2) = core := by
  unfold stripBy
  have hh' : (core ++ w2).head?.all (fun c => !p c) := by
    cases core with
    | nil => exact absurd rfl hne
    | cons a r => simpa using hh
  rw [List.append_assoc, dropWhile_prefix h1 hh', List.reverse_append]
  have hr : core.reverse.head?.all (fun c => !p c) := by
    rw [List.head?_reverse]; exact hl
  rw [dropWhile_prefix (fun c hc => h2 c (List.mem_reverse.mp hc)) hr, List.reverse_reverse]

/-- Every list is its stripped core with `p`-characters around it. -/
theorem stripBy_split (p : Char → Bool) (cs : List Char) :
    ∃ w1 w2, cs = w1 ++ stripBy p cs ++ w2 ∧ (∀ c ∈ w1, p c) ∧ (∀ c ∈ w2, p c) := by
  let m := cs.dropWhile p
  refine ⟨cs.takeWhile p, (m.reverse.takeWhile p).reverse, ?_,
    fun c hc => takeWhile_all hc, fun c hc => takeWhile_all (List.mem_reverse.mp hc)⟩
  have e1 := (List.takeWhile_append_dropWhile (p := p) (l := cs)).symm
  have e2 := (List.takeWhile_append_dropWhile (p := p) (l := m.reverse))
  have e3 : m = (m.reverse.dropWhile p).reverse ++ (m.reverse.takeWhile p).reverse := by
    rw [← List.reverse_append, e2, List.reverse_reverse]
  unfold stripBy
  conv => lhs; rw [e1]
  rw [List.append_assoc]
  exact congrArg _ e3

theorem stripPy_eq {w1 core w2 : List Char} (h1 : ∀ c ∈ w1, pySpace c) (h2 : ∀ c ∈ w2, pySpace c)
    (hh : core.head?.all fun c => !pySpace c) (hl : core.getLast?.all fun c => !pySpace c)
    (hne : core ≠ []) : stripPy (w1 ++ core ++ w2) = core := stripBy_eq h1 h2 hh hl hne

theorem stripPy_split (cs : List Char) :
    ∃ w1 w2, cs = w1 ++ stripPy cs ++ w2 ∧ (∀ c ∈ w1, pySpace c) ∧ (∀ c ∈ w2, pySpace c) :=
  stripBy_split pySpace cs

theorem digit_not_space (c : Char) (h : c.isDigit = true) : pySpace c = false := by
  have a0 : ('0' : Char).val.toNat = 48 := rfl
  have a9 : ('9' : Char).val.toNat = 57 := rfl
  have at' : ('\t' : Char).val.toNat = 9 := rfl
  have ar : ('\r' : Char).val.toNat = 13 := rfl
  have asp : (' ' : Char).val.toNat = 32 := rfl
  simp only [Char.isDigit, Bool.and_eq_true, decide_eq_true_eq] at h
  simp only [pySpace, Bool.or_eq_false_iff, Bool.and_eq_false_iff, decide_eq_false_iff_not, beq_eq_false_iff_ne]
  simp only [Char.le_def, UInt32.le_iff_toNat_le, ne_eq, Char.ext_iff, UInt32.toNat_inj.symm] at *
  omega

theorem digitsUs_head_nonspace {body : List Char} (h : DigitsUs body) :
    body.head?.all (fun c => !pySpace c) := by
  obtain ⟨d, r, rfl, hd⟩ := digitsUs_head h
  simp [digit_not_space d hd]

theorem digitsUs_last_nonspace {body : List Char} (h : DigitsUs body) :
    body.getLast?.all (fun c => !pySpace c) := by
  obtain ⟨d, he, hd⟩ := digitsUs_last h
  simp [he, digit_not_space d hd]

theorem digitsUs_ne_nil {body : List Char} (h : DigitsUs body) : body ≠ [] := by
  obtain ⟨d, r, rfl, -⟩ := digitsUs_head h; simp

theorem digitsUs_not_sign {body b : List Char} (h : DigitsUs body) :
    body ≠ '-' :: b ∧ body ≠ '+' :: b := by
  obtain ⟨d, r, rfl, hd⟩ := digitsUs_head h
  constructor <;> rintro ⟨⟩ <;> simp [Char.isDigit] at hd

theorem signSplit_spec (core : List Char) :
    ∃ sgn, core = sgn ++ (signSplit core).2 ∧ (sgn = [] ∨ sgn = ['+'] ∨ sgn = ['-']) ∧
      (signSplit core).1 = (sgn == ['-']) := by
  unfold signSplit
  split
  · exact ⟨['-'], rfl, by simp⟩
  · exact ⟨['+'], rfl, by simp⟩
  · exact ⟨[], rfl, by simp⟩

theorem signSplit_of {sgn body : List Char} (hs : sgn = [] ∨ sgn = ['+'] ∨ sgn = ['-'])
    (hb : DigitsUs body) : signSplit (sgn ++ body) = (sgn == ['-'], body) := by
  rcases hs with rfl | rfl | rfl
  · obtain ⟨d, r, rfl, hd⟩ := digitsUs_head hb
    unfold signSplit
    split
    · rename_i h; simp at h; obtain ⟨rfl, -⟩ := h; simp [Char.isDigit] at hd
    · rename_i h; simp at h; obtain ⟨rfl, -⟩ := h; simp [Char.isDigit] at hd
    · rfl
  · rfl
  · rfl

/-- **Python's `int(s)` for ASCII `s`**: `parseIntChars` returns `n` exactly
when `s` is whitespace, an optional sign, `digit (["_"] digit)*`,
whitespace, with value `n`. -/
theorem parseIntChars_iff (cs : List Char) (n : Int) : parseIntChars cs = some n ↔ PyIntSpec cs n := by
  unfold parseIntChars
  constructor
  · intro h
    obtain ⟨w1, w2, hcs, h1, h2⟩ := stripPy_split cs
    obtain ⟨sgn, hcore, hsgn, hneg⟩ := signSplit_spec (stripPy cs)
    dsimp only at h
    split at h
    · rename_i hd
      simp only [Option.some.injEq] at h
      refine ⟨w1, sgn, (signSplit (stripPy cs)).2, w2, ?_, h1, h2, hsgn, (digitsUs_iff _).mp hd, ?_⟩
      · generalize stripPy cs = core at hcs hcore ⊢
        rw [hcs]
        conv => lhs; rw [hcore]
        simp [List.append_assoc]
      · rw [← h, hneg]
        rcases hsgn with rfl | rfl | rfl <;> simp
    · cases h
  · rintro ⟨w1, sgn, body, w2, rfl, h1, h2, hsgn, hb, rfl⟩
    have hne : sgn ++ body ≠ [] := by simp [digitsUs_ne_nil hb]
    have hh : (sgn ++ body).head?.all (fun c => !pySpace c) := by
      rcases hsgn with rfl | rfl | rfl
      · simpa using digitsUs_head_nonspace hb
      · simp [pySpace]
      · simp [pySpace]
    have hl : (sgn ++ body).getLast?.all (fun c => !pySpace c) := by
      rw [List.getLast?_append]
      obtain ⟨d, he, hd⟩ := digitsUs_last hb
      simp [he, digit_not_space d hd]
    rw [show w1 ++ sgn ++ body ++ w2 = w1 ++ (sgn ++ body) ++ w2 by simp [List.append_assoc],
      stripPy_eq h1 h2 hh hl hne, signSplit_of hsgn hb]
    simp only [(digitsUs_iff body).mpr hb, ite_true]
    rcases hsgn with rfl | rfl | rfl <;> simp

end HALean.Template
