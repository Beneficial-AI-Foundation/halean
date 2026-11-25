/-
  Specifications for the Python `str` methods, slicing and result parsing of
  `HALean/Template/Render.lean`: `str.title`, `str.capitalize`, `str.strip`,
  `str.replace` with an empty pattern, `xs[a:b:c]`, the `_IS_NUMERIC` regex
  and the agreement between the three render entry points.
-/
import HALean.Template.Render

namespace HALean.Template

/-! ## ASCII case mapping -/

private theorem toUpper_idem (c : Char) : c.toUpper.toUpper = c.toUpper := by
  simp only [Char.toUpper]
  split
  · split
    · next h1 h2 =>
      simp only [UInt32.le_iff_toNat_le, UInt32.toNat_add, seval] at h1 h2
      omega
    · simp
  · rfl

private theorem toLower_idem (c : Char) : c.toLower.toLower = c.toLower := by
  simp only [Char.toLower]
  split
  · split
    · next h1 h2 =>
      simp only [UInt32.le_iff_toNat_le, UInt32.toNat_add, seval] at h1 h2
      omega
    · simp
  · rfl

private theorem isAlpha_toUpper (c : Char) : c.toUpper.isAlpha = c.isAlpha := by
  simp only [Char.toUpper, Char.isAlpha, Char.isUpper, Char.isLower]
  split
  · next h1 =>
    simp only [UInt32.le_iff_toNat_le, UInt32.toNat_add, seval, ge_iff_le] at h1 ⊢
    simp
    have e0 : c.toNat = c.val.toNat := rfl
    have e : (c.toNat + 4294967264) % 4294967296 = c.toNat - 32 := by omega
    have a1 : 65 ≤ c.toNat - 32 := by omega
    have a2 : c.toNat - 32 ≤ 90 := by omega
    have a3 : 97 ≤ c.toNat := by omega
    have a4 : c.toNat ≤ 122 := by omega
    simp [e, a1, a2, a3, a4]
  · rfl

private theorem isAlpha_toLower (c : Char) : c.toLower.isAlpha = c.isAlpha := by
  simp only [Char.toLower, Char.isAlpha, Char.isUpper, Char.isLower]
  split
  · next h1 =>
    simp only [UInt32.le_iff_toNat_le, UInt32.toNat_add, seval, ge_iff_le] at h1 ⊢
    simp
    have e0 : c.toNat = c.val.toNat := rfl
    have e : (c.toNat + 32) % 4294967296 = c.toNat + 32 := by omega
    have a1 : 97 ≤ c.toNat + 32 := by omega
    have a2 : c.toNat + 32 ≤ 122 := by omega
    have a3 : 65 ≤ c.toNat := by omega
    have a4 : c.toNat ≤ 90 := by omega
    simp [e, a1, a2, a3, a4]
  · rfl

/-! ## `str.title()` -/

/-- `str.title()` as a recursion over the characters: a letter is upper-cased
when the previous character was not a letter (`prev = false`) and
lower-cased otherwise; other characters are kept and end the word. -/
def titleSpec : Bool → List Char → List Char
  | _, [] => []
  | prev, c :: cs =>
    if c.isAlpha then (if prev then c.toLower else c.toUpper) :: titleSpec true cs
    else c :: titleSpec false cs

private theorem title_loop (cs : List Char) (acc : String) (prev : Bool) :
    (Prod.fst <$>
      forIn (m := Id) cs (acc, prev) fun c __s =>
        if c.isAlpha = true then
          pure (ForInStep.yield (__s.fst.push (if __s.snd = true then c.toLower else c.toUpper), true))
        else pure (ForInStep.yield (__s.fst.push c, false))) =
    (pure (acc ++ String.ofList (titleSpec prev cs)) : Id String) := by
  induction cs generalizing acc prev with
  | nil => simp [titleSpec]
  | cons c cs ih =>
    simp only [List.forIn_cons, titleSpec]
    split
    · simp [ih]
      congr 1; apply String.toList_inj.mp; simp
    · simp [ih]
      congr 1; apply String.toList_inj.mp; simp

/-- The imperative `pyTitle` is the word-by-word recursion `titleSpec`. -/
theorem pyTitle_eq (s : String) : pyTitle s = String.ofList (titleSpec false s.toList) := by
  unfold pyTitle
  simp [Id.run]
  rw [title_loop]
  simp
  rfl

private theorem titleSpec_length (p : Bool) (cs : List Char) :
    (titleSpec p cs).length = cs.length := by
  induction cs generalizing p with
  | nil => rfl
  | cons c cs ih => simp only [titleSpec]; split <;> simp [ih]

private theorem titleSpec_idem (p : Bool) (cs : List Char) :
    titleSpec p (titleSpec p cs) = titleSpec p cs := by
  induction cs generalizing p with
  | nil => rfl
  | cons c cs ih =>
    simp only [titleSpec]
    split
    · rename_i h
      cases p
      · simp [titleSpec, isAlpha_toUpper, h, toUpper_idem, ih]
      · simp [titleSpec, isAlpha_toLower, h, toLower_idem, ih]
    · rename_i h
      simp [titleSpec, h, ih]

/-- `s.title().title() == s.title()` -/
theorem pyTitle_idem (s : String) : pyTitle (pyTitle s) = pyTitle s := by
  simp [pyTitle_eq, titleSpec_idem]

/-- `len(s.title()) == len(s)` -/
theorem pyTitle_length (s : String) : (pyTitle s).length = s.length := by
  simp [pyTitle_eq, titleSpec_length, ← String.length_toList]

/-- Text without letters is unchanged by `title`. -/
theorem pyTitle_no_alpha (s : String) (h : ∀ c ∈ s.toList, c.isAlpha = false) : pyTitle s = s := by
  rw [pyTitle_eq]
  have : ∀ (p : Bool) (cs : List Char), (∀ c ∈ cs, c.isAlpha = false) → titleSpec p cs = cs := by
    intro p cs
    induction cs generalizing p with
    | nil => intro _; rfl
    | cons c cs ih =>
      intro hc
      simp only [titleSpec, hc c (by simp)]
      simp [ih false (fun c hm => hc c (by simp [hm]))]
  rw [this false _ h]
  simp

/-! ## `str.capitalize()` -/

/-- `s.capitalize().capitalize() == s.capitalize()` -/
theorem pyCapitalize_idem (s : String) : pyCapitalize (pyCapitalize s) = pyCapitalize s := by
  have hl : Char.toLower ∘ Char.toLower = Char.toLower := funext toLower_idem
  unfold pyCapitalize
  cases h : s.toList with
  | nil => simp
  | cons c cs => simp [toUpper_idem, hl]

/-- `len(s.capitalize()) == len(s)` -/
theorem pyCapitalize_length (s : String) : (pyCapitalize s).length = s.length := by
  unfold pyCapitalize
  rw [← String.length_toList (s := s)]
  cases h : s.toList with
  | nil => simp
  | cons c cs => simp [← String.length_toList]

/-- The first character is upper-cased, the rest lower-cased. -/
theorem pyCapitalize_cons (c : Char) (cs : List Char) :
    (pyCapitalize (String.ofList (c :: cs))).toList = c.toUpper :: cs.map Char.toLower := by
  simp [pyCapitalize]

/-! ## `str.strip()` / `lstrip` / `rstrip` -/

private theorem dropWhile_head (p : α → Bool) (l : List α) (x : α)
    (h : (l.dropWhile p).head? = some x) : p x = false := by
  induction l with
  | nil => simp at h
  | cons a l ih =>
    by_cases ha : p a = true
    · rw [List.dropWhile_cons_of_pos ha] at h; exact ih h
    · rw [List.dropWhile_cons_of_neg ha] at h
      simp at h; subst h; simpa using ha

private theorem dropWhile_fix (p : α → Bool) (l : List α)
    (h : ∀ x, l.head? = some x → p x = false) : l.dropWhile p = l := by
  cases l with
  | nil => rfl
  | cons a l => exact List.dropWhile_cons_of_neg (by simp [h a rfl])

private theorem dropWhile_idem (p : α → Bool) (l : List α) :
    (l.dropWhile p).dropWhile p = l.dropWhile p :=
  dropWhile_fix p _ (dropWhile_head p l)

private theorem prefix_head (l m : List α) (x : α) (h : l <+: m) (hx : l.head? = some x) :
    m.head? = some x := by
  obtain ⟨t, rfl⟩ := h
  cases l with
  | nil => simp at hx
  | cons a l => simpa using hx

/-- Stripping the right end keeps the left end stripped. -/
private theorem dropWhile_rstrip (p : α → Bool) (l : List α) :
    ((((l.dropWhile p).reverse.dropWhile p).reverse).dropWhile p) =
      ((l.dropWhile p).reverse.dropWhile p).reverse := by
  apply dropWhile_fix
  intro x hx
  have hpre : ((l.dropWhile p).reverse.dropWhile p).reverse <+: l.dropWhile p := by
    have := List.dropWhile_suffix p (l := (l.dropWhile p).reverse)
    simpa using List.reverse_prefix.mpr this
  exact dropWhile_head p l x (prefix_head _ _ x hpre hx)

/-- The characters `strip` removes: the given set, or Unicode whitespace. -/
def stripSet : Option String → Char → Bool
  | some cs => fun c => cs.contains c
  | none => pyIsSpace

/-- `pyStrip` on character lists: `dropWhile` from the chosen ends. -/
theorem pyStrip_toList (s : String) (chars : Option String) (left right : Bool) :
    (pyStrip s chars left right).toList =
      let l := if left then s.toList.dropWhile (stripSet chars) else s.toList
      if right then (l.reverse.dropWhile (stripSet chars)).reverse else l := by
  have hw : isPyWs = pyIsSpace := rfl
  cases chars <;> cases left <;> cases right <;> simp [pyStrip, stripSet, hw]

/-- Stripping neither end changes nothing. -/
theorem pyStrip_neither (s : String) (chars : Option String) : pyStrip s chars false false = s := by
  apply String.toList_inj.mp
  simp [pyStrip_toList]

/-- Stripping is idempotent (`s.strip().strip() == s.strip()`, and the same
for `lstrip`/`rstrip`, with or without a character set). -/
theorem pyStrip_idem (s : String) (chars : Option String) (left right : Bool) :
    pyStrip (pyStrip s chars left right) chars left right = pyStrip s chars left right := by
  apply String.toList_inj.mp
  rw [pyStrip_toList, pyStrip_toList]
  cases left <;> cases right <;> simp [dropWhile_idem, dropWhile_rstrip]

/-- `s.strip() == s.lstrip().rstrip()` -/
theorem pyStrip_both (s : String) (chars : Option String) :
    pyStrip s chars true true = pyStrip (pyStrip s chars true false) chars false true := by
  apply String.toList_inj.mp
  simp [pyStrip_toList]

/-- After `lstrip`/`strip` the first character is not a stripped one. -/
theorem pyStrip_head (s : String) (chars : Option String) (right : Bool) (c : Char)
    (h : (pyStrip s chars true right).toList.head? = some c) : stripSet chars c = false := by
  rw [pyStrip_toList] at h
  cases right
  · exact dropWhile_head _ _ c (by simpa using h)
  · simp only [ite_true] at h
    have hpre : ((s.toList.dropWhile (stripSet chars)).reverse.dropWhile (stripSet chars)).reverse
        <+: s.toList.dropWhile (stripSet chars) := by
      have := List.dropWhile_suffix (stripSet chars)
        (l := (s.toList.dropWhile (stripSet chars)).reverse)
      simpa using List.reverse_prefix.mpr this
    exact dropWhile_head _ _ c (prefix_head _ _ c hpre h)

/-- After `rstrip`/`strip` the last character is not a stripped one. -/
theorem pyStrip_last (s : String) (chars : Option String) (left : Bool) (c : Char)
    (h : (pyStrip s chars left true).toList.getLast? = some c) : stripSet chars c = false := by
  rw [pyStrip_toList] at h
  simp only [ite_true, List.getLast?_reverse] at h
  exact dropWhile_head _ _ c h

/-- The stripped text is a contiguous piece of the original. -/
theorem pyStrip_infix (s : String) (chars : Option String) (left right : Bool) :
    (pyStrip s chars left right).toList <:+: s.toList := by
  rw [pyStrip_toList]
  have h1 : ∀ l : List Char, l.dropWhile (stripSet chars) <:+: l :=
    fun l => (List.dropWhile_suffix _).isInfix
  have h2 : ∀ l : List Char, (l.reverse.dropWhile (stripSet chars)).reverse <:+: l := by
    intro l
    have := List.dropWhile_suffix (stripSet chars) (l := l.reverse)
    have := List.reverse_prefix.mpr this
    simp only [List.reverse_reverse] at this
    exact this.isInfix
  cases left <;> cases right <;> simp only [ite_true, Bool.false_eq_true, ite_false]
  · exact List.infix_refl _
  · exact h2 _
  · exact h1 _
  · exact (h2 _).trans (h1 _)

/-- Text with nothing to strip at either end is unchanged. -/
theorem pyStrip_fix (s : String) (chars : Option String) (left right : Bool)
    (hh : ∀ c, s.toList.head? = some c → stripSet chars c = false)
    (hl : ∀ c, s.toList.getLast? = some c → stripSet chars c = false) :
    pyStrip s chars left right = s := by
  apply String.toList_inj.mp
  rw [pyStrip_toList]
  have h1 := dropWhile_fix (stripSet chars) s.toList hh
  have h2 : s.toList.reverse.dropWhile (stripSet chars) = s.toList.reverse :=
    dropWhile_fix _ _ (by simpa using hl)
  cases left <;> cases right <;> simp [h1, h2]

/-! ## `str.replace` with an empty pattern -/

private theorem replaceGo_zero (new : String) (l : List String) :
    pyReplace.go new l 0 = String.join l := by
  cases l <;> simp [pyReplace.go]

private theorem join_chars (cs : List Char) : String.join (cs.map toString) = String.ofList cs := by
  apply String.toList_inj.mp
  simp only [String.toList_join, String.toList_ofList]
  induction cs with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.map_cons, List.flatMap_cons, ih]
    show (String.singleton c).toList ++ cs = _
    simp

/-- `s.replace("", new, 0) == s` -/
theorem pyReplace_empty_zero (s new : String) : pyReplace s "" new 0 = s := by
  simp [pyReplace, replaceGo_zero, join_chars]

private theorem replaceGo_all (new : String) (l : List String) (k : Nat) (hk : l.length < k) :
    pyReplace.go new l k = new ++ String.join (l.map (· ++ new)) := by
  induction l generalizing k with
  | nil =>
    have : k > 0 := by simpa using hk
    simp [pyReplace.go, this]
  | cons c l ih =>
    have hk' : k > 0 := by omega
    simp only [pyReplace.go, hk', ite_true]
    rw [ih (k - 1) (by simp at hk; omega)]
    simp [String.join_cons, String.append_assoc]

/-- `s.replace("", new)` puts `new` before every character and at the end:
`"abc".replace("", "-") == "-a-b-c-"`. -/
theorem pyReplace_empty_all (s new : String) (count : Int) (h : count < 0) :
    pyReplace s "" new count =
      new ++ String.join (s.toList.map fun c => toString c ++ new) := by
  have he : ("" : String).isEmpty = true := by simp
  simp only [pyReplace, he, ite_true, h]
  rw [replaceGo_all _ _ _ (by simp)]
  simp [List.map_map, Function.comp_def]

/-- `"".replace("", new) == new` -/
theorem pyReplace_empty_empty (new : String) : pyReplace "" "" new (-1) = new := by
  rw [pyReplace_empty_all _ _ _ (by omega)]
  simp

/-! ## Slices -/

/-- Python's clamping of a slice bound for a positive step
(`slice.indices`): negative bounds count from the end, and everything is
clamped to `0..len`. -/
def clampIdx (n : Nat) (i : Int) : Nat :=
  if i < 0 then (i + n).toNat else min i.toNat n

private theorem range_getElem_take (xs : List α) (s m : Nat) :
    (List.range m).filterMap (fun k => xs[s + k]?) = (xs.drop s).take m := by
  induction m with
  | zero => simp
  | succ m ih =>
    rw [List.range_succ, List.filterMap_append, ih, List.take_add_one]
    cases h : xs[s + m]? <;> simp [h]

/-- `xs[a:b:0]` raises `ValueError`. -/
theorem sliceList_step_zero (xs : List α) (a b : Option Int) :
    sliceList xs a b (some 0) = .error "slice step cannot be zero" := rfl

/-- Any slice with a non-zero step succeeds (slicing never raises
`IndexError`). -/
theorem sliceList_total (xs : List α) (a b c : Option Int) (hc : c ≠ some 0) :
    ∃ ys, sliceList xs a b c = .ok ys := by
  unfold sliceList
  have h0 : (c.getD 1 == 0) = false := by
    cases c with
    | none => rfl
    | some v => simp at hc ⊢; exact hc
  simp only [bind, Except.bind, pure, Except.pure]
  split
  · rename_i h; exact absurd h (by simp [h0])
  · split <;> exact ⟨_, rfl⟩

/-- **`xs[a:b]`**: the items from the clamped start up to the clamped stop;
an omitted bound is the corresponding end. -/
theorem sliceList_step_one (xs : List α) (a b : Option Int) :
    sliceList xs a b none =
      .ok ((xs.take ((b.map (clampIdx xs.length)).getD xs.length)).drop
        ((a.map (clampIdx xs.length)).getD 0)) := by
  have hnorm : ∀ i : Int,
      (if (if i < 0 then i + (xs.length : Int) else i) < 0 then (0 : Int)
        else if (xs.length : Int) < (if i < 0 then i + (xs.length : Int) else i) then (xs.length : Int)
        else (if i < 0 then i + (xs.length : Int) else i)) = ((clampIdx xs.length i : Nat) : Int) := by
    intro i
    unfold clampIdx
    split <;> split <;> (try split) <;> omega
  have key : ∀ s e : Nat,
      List.filterMap (fun (i : Int) => xs[i.toNat]?)
        (List.filterMap ((fun (k : Int) => some ((s : Int) + k)) ∘ Int.ofNat)
          (List.range ((e : Int) - (s : Int)).toNat)) = (xs.take e).drop s := by
    intro s e
    rw [List.filterMap_filterMap]
    have hf : (fun (k : Nat) => (((fun (k : Int) => some ((s : Int) + k)) ∘ Int.ofNat) k).bind
        (fun (i : Int) => xs[i.toNat]?)) = fun k => xs[s + k]? := by
      funext k
      simp only [Function.comp, Option.bind_some]
      congr 1
    rw [hf, range_getElem_take]
    have : ((e : Int) - (s : Int)).toNat = e - s := by omega
    rw [this, List.drop_take]
  unfold sliceList
  cases a with
  | none =>
    cases b with
    | none =>
      simp [pure, Except.pure]
      simpa using key 0 xs.length
    | some v =>
      simp [pure, Except.pure, hnorm]
      simpa using key 0 (clampIdx xs.length v)
  | some u =>
    cases b with
    | none =>
      simp [pure, Except.pure, hnorm]
      simpa using key (clampIdx xs.length u) xs.length
    | some v =>
      simp [pure, Except.pure, hnorm]
      simpa using key (clampIdx xs.length u) (clampIdx xs.length v)

/-- `xs[:]` is a copy of the whole list. -/
theorem sliceList_all (xs : List α) : sliceList xs none none none = .ok xs := by
  rw [sliceList_step_one]; simp

/-- `xs[a:b]` for non-negative bounds: drop `a`, keep up to position `b`. -/
theorem sliceList_nat (xs : List α) (a b : Nat) :
    sliceList xs (some (a : Int)) (some (b : Int)) none = .ok ((xs.take b).drop a) := by
  rw [sliceList_step_one]
  have h : ∀ k : Nat, clampIdx xs.length (k : Int) = min k xs.length := by
    intro k; unfold clampIdx
    have : ¬ ((k : Int) < 0) := by omega
    simp [this]
  simp only [Option.map_some, Option.getD_some, h]
  congr 1
  have ht : xs.take (min b xs.length) = xs.take b := by
    rcases Nat.le_total b xs.length with hb | hb
    · rw [Nat.min_eq_left hb]
    · rw [Nat.min_eq_right hb, List.take_of_length_le hb, List.take_of_length_le (Nat.le_refl _)]
  rw [ht]
  rcases Nat.le_total a xs.length with ha | ha
  · rw [Nat.min_eq_left ha]
  · rw [Nat.min_eq_right ha, List.drop_eq_nil_of_le (by simp [List.length_take]; omega),
      List.drop_eq_nil_of_le (by simp [List.length_take]; omega)]

/-- `xs[-k:]` is the last `k` items. -/
theorem sliceList_last (xs : List α) (k : Nat) (hk : 0 < k) (hl : k ≤ xs.length) :
    sliceList xs (some (-(k : Int))) none none = .ok (xs.drop (xs.length - k)) := by
  rw [sliceList_step_one]
  have : clampIdx xs.length (-(k : Int)) = xs.length - k := by
    unfold clampIdx
    have h : (-(k : Int)) < 0 := by omega
    simp only [h, ite_true]; omega
  simp [this]

/-- Every item of a slice is an item of the list. -/
theorem sliceList_subset (xs ys : List α) (a b c : Option Int) (h : sliceList xs a b c = .ok ys) :
    ∀ y ∈ ys, y ∈ xs := by
  unfold sliceList at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · cases h
  · split at h
    all_goals
      injection h with h
      subst h
      intro y hy
      rw [List.mem_filterMap] at hy
      obtain ⟨i, _, hi⟩ := hy
      first
        | exact List.mem_of_getElem? hi
        | (split at hi
           · cases hi
           · exact List.mem_of_getElem? hi)

private theorem filterMap_congr' {f g : α → Option β} (l : List α) (h : ∀ x ∈ l, f x = g x) :
    l.filterMap f = l.filterMap g := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.filterMap_cons, h a (by simp)]
    rw [ih (fun x hx => h x (by simp [hx]))]

private theorem range_rev (xs : List α) :
    (List.range xs.length).filterMap (fun k => xs[xs.length - 1 - k]?) = xs.reverse := by
  induction xs with
  | nil => rfl
  | cons x t ih =>
    rw [List.length_cons, List.range_succ, List.filterMap_append, List.reverse_cons]
    congr 1
    · rw [← ih]
      apply filterMap_congr'
      intro k hk
      have hk' : k < t.length := by simpa using hk
      have : t.length + 1 - 1 - k = (t.length - 1 - k) + 1 := by omega
      rw [this, List.getElem?_cons_succ]
    · simp

/-- `xs[::-1]` is the reversed list. -/
theorem sliceList_reverse (xs : List α) : sliceList xs none none (some (-1)) = .ok xs.reverse := by
  unfold sliceList
  simp [pure, Except.pure]
  rw [List.filterMap_filterMap, ← range_rev]
  apply filterMap_congr'
  intro k hk
  have hk' : k < xs.length := by simpa using hk
  have h1 : ¬ ((xs.length : Int) - 1 - (k : Int) < 0) := by omega
  have h2 : ((xs.length : Int) - 1 - (k : Int)).toNat = xs.length - 1 - k := by omega
  simp [h1, h2]

/-! ## `_IS_NUMERIC` -/

/-- `^[+-]?(?!0\d)\d*(?:\.\d*)?$` read as a grammar: an optional sign,
digits, an optional `.` with digits, and no leading zero before a digit. -/
def IsNumericSpec (cs : List Char) : Prop :=
  ∃ sign ip frac, cs = sign ++ ip ++ frac ∧
    (sign = [] ∨ sign = ['+'] ∨ sign = ['-']) ∧
    (∀ c ∈ ip, c.isDigit = true) ∧
    (frac = [] ∨ ∃ fs, frac = '.' :: fs ∧ ∀ c ∈ fs, c.isDigit = true) ∧
    ¬ (∃ d r, ip = '0' :: d :: r)

private theorem mem_takeWhile_true (p : α → Bool) (l : List α) (x : α)
    (h : x ∈ l.takeWhile p) : p x = true := by
  induction l with
  | nil => simp at h
  | cons a l ih =>
    by_cases ha : p a = true
    · simp only [List.takeWhile_cons, ha, ite_true, List.mem_cons] at h
      rcases h with rfl | h
      · exact ha
      · exact ih h
    · simp [ha] at h

private theorem drop_takeWhile_length (p : α → Bool) (l : List α) :
    l.drop (l.takeWhile p).length = l.dropWhile p := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    by_cases ha : p a = true
    · simp [ha, ih]
    · simp [ha]

private theorem takeWhile_digits (ip frac : List Char) (h : ∀ c ∈ ip, c.isDigit = true)
    (hf : frac = [] ∨ ∃ fs, frac = '.' :: fs) :
    (ip ++ frac).takeWhile Char.isDigit = ip := by
  induction ip with
  | nil =>
    rcases hf with rfl | ⟨fs, rfl⟩
    · rfl
    · simp
  | cons c ip ih =>
    simp only [List.cons_append, List.takeWhile_cons, h c (by simp), ite_true]
    rw [ih (fun c hc => h c (by simp [hc]))]

/-- The digits-and-fraction part of the check, on the text after the sign. -/
private def numBody (cs : List Char) : Bool :=
  (match cs with | '0' :: d :: _ => !d.isDigit | _ => true) &&
  (match cs.drop (cs.takeWhile Char.isDigit).length with
    | [] => true
    | '.' :: fs => fs.all Char.isDigit
    | _ => false)

private theorem numBody_iff (cs : List Char) :
    numBody cs = true ↔ ∃ ip frac, cs = ip ++ frac ∧ (∀ c ∈ ip, c.isDigit = true) ∧
      (frac = [] ∨ ∃ fs, frac = '.' :: fs ∧ ∀ c ∈ fs, c.isDigit = true) ∧
      ¬ (∃ d r, ip = '0' :: d :: r) := by
  constructor
  · intro h
    simp only [numBody, Bool.and_eq_true] at h
    obtain ⟨hz, hr⟩ := h
    have hsplit : cs = cs.takeWhile Char.isDigit ++ cs.drop (cs.takeWhile Char.isDigit).length := by
      rw [drop_takeWhile_length, List.takeWhile_append_dropWhile]
    refine ⟨cs.takeWhile Char.isDigit, cs.drop (cs.takeWhile Char.isDigit).length, hsplit,
      fun c hc => mem_takeWhile_true _ _ c hc, ?_, ?_⟩
    · split at hr
      · rename_i e; exact .inl e
      · rename_i fs e; exact .inr ⟨fs, e, by simpa using hr⟩
      · cases hr
    · rintro ⟨d, r, hip⟩
      have hd : d.isDigit = true := mem_takeWhile_true Char.isDigit cs d (by rw [hip]; simp)
      rw [hsplit, hip] at hz
      simp [hd] at hz
  · rintro ⟨ip, frac, rfl, hip, hfrac, hz⟩
    have htw : (ip ++ frac).takeWhile Char.isDigit = ip :=
      takeWhile_digits ip frac hip (hfrac.imp id fun ⟨fs, h, _⟩ => ⟨fs, h⟩)
    simp only [numBody, Bool.and_eq_true, htw, List.drop_left]
    constructor
    · split
      · rename_i d r e
        cases ip with
        | nil =>
          rcases hfrac with rfl | ⟨fs, rfl, _⟩
          · simp at e
          · simp at e
        | cons c ip =>
          cases ip with
          | nil =>
            rcases hfrac with rfl | ⟨fs, rfl, _⟩
            · simp at e
            · simp at e; rw [← e.2.1]; decide
          | cons c2 ip =>
            simp at e
            exact absurd ⟨c2, ip, by rw [e.1]⟩ hz
      · rfl
    · rcases hfrac with rfl | ⟨fs, rfl, hfs⟩
      · rfl
      · simpa using hfs

private theorem isNumericStr_eq (s : String) :
    isNumericStr s = numBody (match s.toList with | '+' :: r | '-' :: r => r | r => r) := by
  unfold isNumericStr numBody
  rfl

/-- **`_IS_NUMERIC`**: the fast numeric path of `_parse_result` is taken
exactly for text matching the regex's grammar. -/
theorem isNumericStr_iff (s : String) : isNumericStr s = true ↔ IsNumericSpec s.toList := by
  rw [isNumericStr_eq]
  unfold IsNumericSpec
  constructor
  · intro h
    split at h
    · rename_i r e
      obtain ⟨ip, frac, rfl, h1, h2, h3⟩ := (numBody_iff r).mp h
      exact ⟨['+'], ip, frac, by simp [e], by simp, h1, h2, h3⟩
    · rename_i r e
      obtain ⟨ip, frac, rfl, h1, h2, h3⟩ := (numBody_iff r).mp h
      exact ⟨['-'], ip, frac, by simp [e], by simp, h1, h2, h3⟩
    · obtain ⟨ip, frac, e, h1, h2, h3⟩ := (numBody_iff _).mp h
      exact ⟨[], ip, frac, by simpa using e, by simp, h1, h2, h3⟩
  · rintro ⟨sign, ip, frac, e, hs, h1, h2, h3⟩
    rcases hs with rfl | rfl | rfl
    · -- no sign: the body does not start with `+` or `-`
      have hbody := (numBody_iff (ip ++ frac)).mpr ⟨ip, frac, rfl, h1, h2, h3⟩
      simp only [List.nil_append] at e
      rw [e]
      split
      · rename_i r e'
        cases ip with
        | nil =>
          rcases h2 with rfl | ⟨fs, rfl, _⟩
          · simp at e'
          · simp at e'
        | cons c ip =>
          simp at e'
          have := h1 c (by simp)
          rw [e'.1] at this
          exact absurd this (by decide)
      · rename_i r e'
        cases ip with
        | nil =>
          rcases h2 with rfl | ⟨fs, rfl, _⟩
          · simp at e'
          · simp at e'
        | cons c ip =>
          simp at e'
          have := h1 c (by simp)
          rw [e'.1] at this
          exact absurd this (by decide)
      · exact hbody
    · rw [e]
      exact (numBody_iff (ip ++ frac)).mpr ⟨ip, frac, rfl, h1, h2, h3⟩
    · rw [e]
      exact (numBody_iff (ip ++ frac)).mpr ⟨ip, frac, rfl, h1, h2, h3⟩

/-! ## `_parse_result` -/

/-- `_parse_result` never invents text: when the result is a string it is
the rendered text itself. -/
theorem parseResult_str (r s : String) (h : parseResult r = .str s) : s = r := by
  unfold parseResult at h
  simp only at h
  split at h
  · rename_i v hv
    split at hv
    · split at hv
      · simp only [Option.map_eq_some_iff] at hv
        obtain ⟨f, _, rfl⟩ := hv
        cases h
      · simp only [Option.map_eq_some_iff] at hv
        obtain ⟨f, _, rfl⟩ := hv
        cases h
    · cases hv
  · split at h
    · cases h; rfl
    · split at h
      · cases h; rfl
      · rename_i v _ hc
        split at h
        · split at h
          · cases h
          · cases h; rfl
        · split at h
          · cases h
          · cases h; rfl
        · subst h
          simp [isComplexOrStr] at hc

/-! ## The render entry points agree -/

/-- Unparsed, `render` is `renderString` wrapped as a string value. -/
theorem render_unparsed (t : Tmpl) (ctx : Ctx) :
    render t ctx false = (renderString t ctx).map Value.str := by
  unfold render renderString
  cases t.isStatic
  · simp only [Bool.false_eq_true, ite_false]
    split <;> rfl
  · rfl

/-- Parsed, `render` is `_parse_result` of `renderString`. -/
theorem render_parsed (t : Tmpl) (ctx : Ctx) :
    render t ctx true = (renderString t ctx).map parseResult := by
  unfold render renderString
  cases t.isStatic
  · simp only [Bool.false_eq_true, ite_false]
    split <;> simp only [Except.map, bind, Except.bind, pure, Except.pure, ite_true]
  · rfl

/-- `async_render_to_info` returns the same result as `async_render`. -/
theorem renderWithInfo_fst (t : Tmpl) (ctx : Ctx) (parse : Bool) :
    (renderWithInfo t ctx parse).1 = render t ctx parse := by
  unfold renderWithInfo render renderString
  cases t.isStatic
  · simp only [Bool.false_eq_true, ite_false]
    split <;> rfl
  · rfl

/-- A static template's render info is static (so never rate limited and
every entity passes its filter) and its result is the source text. -/
theorem renderWithInfo_static (t : Tmpl) (ctx : Ctx) (h : t.isStatic = true) :
    (renderWithInfo t ctx false).1 = .ok (.str t.src) ∧
      (renderWithInfo t ctx false).2.isStatic = true ∧
      (renderWithInfo t ctx false).2.rateLimit = none := by
  simp [renderWithInfo, h, RInfo.rateLimit]

/-- A render that raises marks its info with `exception`, which makes the
tracker listen to every state (`RenderInfo.filter` is then always true). -/
theorem renderWithInfo_error (t : Tmpl) (ctx : Ctx) (parse : Bool) (e : String)
    (h : (renderWithInfo t ctx parse).1 = .error e) :
    (renderWithInfo t ctx parse).2.exception = true ∧
      ∀ eid, (renderWithInfo t ctx parse).2.filter eid = true := by
  unfold renderWithInfo at h ⊢
  cases hs : t.isStatic
  · simp only [hs, Bool.false_eq_true, ite_false] at h ⊢
    split at h
    · cases h
    · rename_i e' st heq
      exact ⟨by simp, fun eid => by simp [RInfo.filter]⟩
  · simp [hs] at h

/-- A static template renders to its source text. -/
theorem renderString_static (t : Tmpl) (ctx : Ctx) (h : t.isStatic = true) :
    renderString t ctx = .ok t.src := by
  simp [renderString, h]

/-- End to end: text without any Jinja opening compiles and renders
(unparsed) to itself, stripped, whatever the states are. -/
theorem compile_render_static (raw : String) (ctx : Ctx) (h : isTemplateString raw = false) :
    ∃ t, compile raw = .ok t ∧ render t ctx false = .ok (.str raw.trim) ∧
      renderString t ctx = .ok raw.trim := by
  refine ⟨{ src := raw.trim, isStatic := true, nodes := [.text raw.trim] }, ?_, ?_, ?_⟩
  · simp [compile, h, pure, Except.pure]
  · simp [render]
  · simp [renderString]

end HALean.Template
