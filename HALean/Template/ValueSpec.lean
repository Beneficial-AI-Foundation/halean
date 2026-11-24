/-
  Template values (`HALean/Template/Value.lean`) against Python's own rules:
  `repr()`/`str()` of containers, `range`, number comparison, and the parts
  of the float code that do not depend on IEEE arithmetic (which Lean keeps
  opaque): special values, signs and the shape of the decoded fraction.
-/
import HALean.Template.Value
import HALean.Template.PyIntSpec

namespace HALean.Template

/-! ## Floats: what holds without evaluating IEEE operations -/

/-- The decoded mantissa has at most 53 bits and the exponent is a double's. -/
theorem decodeFloat_bounds (f : Float) :
    (decodeFloat f).2.1 < 2 ^ 53 ∧ -1074 ≤ (decodeFloat f).2.2 ∧ (decodeFloat f).2.2 ≤ 972 := by
  have hm : (f.toBits &&& 0xFFFFFFFFFFFFF).toNat ≤ 0xFFFFFFFFFFFFF := by
    rw [UInt64.toNat_and]; exact Nat.and_le_right
  have he : ((f.toBits >>> 52) &&& 0x7FF).toNat ≤ 0x7FF := by
    rw [UInt64.toNat_and]; exact Nat.and_le_right
  simp only [decodeFloat]
  split <;> dsimp only
  · refine ⟨?_, by omega, by omega⟩
    exact Nat.lt_of_le_of_lt hm (by decide)
  · rename_i hx
    simp only [beq_iff_eq] at hx
    refine ⟨?_, ?_, ?_⟩
    · exact Nat.lt_of_le_of_lt (Nat.add_le_add_right hm _) (by decide)
    · omega
    · have : ((0x7FF : UInt64).toNat : Int) = 2047 := by decide
      omega

/-- `floatFrac` returns a fraction with a positive denominator. -/
theorem floatFrac_den_pos (f : Float) : 0 < (floatFrac f).2.2 := by
  simp only [floatFrac]
  split
  · exact Nat.one_pos
  · exact Nat.pow_pos (by decide)

/-- Its numerator and sign are those of `decodeFloat`, and a non-negative
exponent gives an integer (denominator 1). -/
theorem floatFrac_of_exp_nonneg (f : Float) (h : 0 ≤ (decodeFloat f).2.2) :
    floatFrac f = ((decodeFloat f).1, (decodeFloat f).2.1 * 2 ^ (decodeFloat f).2.2.toNat, 1) := by
  simp [floatFrac, h]

/-- Every number has at least one decimal digit. -/
theorem natDigits_pos (n : Nat) : 0 < natDigits n := by
  unfold natDigits; exact Nat.length_repr_pos

/-- `repr(float('nan'))` -/
theorem floatRepr_nan (f : Float) (h : f.isNaN = true) : floatRepr f = "nan" := by
  simp [floatRepr, h]

/-- `repr(float('inf'))`, `repr(float('-inf'))` -/
theorem floatRepr_inf (f : Float) (hn : f.isNaN = false) (h : f.isInf = true) :
    floatRepr f = if f > 0 then "inf" else "-inf" := by
  simp [floatRepr, hn, h]

/-- `int(float)` fails exactly for NaN (`ValueError`) and the infinities
(`OverflowError`). -/
theorem floatToInt?_eq_none_iff (f : Float) : floatToInt? f = none ↔ f.isNaN = true ∨ f.isInf = true := by
  unfold floatToInt? Float.isFinite'
  by_cases hn : f.isNaN = true <;> by_cases hi : f.isInf = true <;> simp [hn, hi]

/-- A NaN or infinity cannot be sent as JSON. -/
theorem floatToJson_not_finite (f : Float) (h : Float.isFinite' f = false) :
    floatToJson f = .error s!"{floatRepr f} cannot be sent as JSON" := by
  simp [floatToJson, h]; rfl

/-- `0 / den` is zero with the requested sign (`-0.0` exists in Python). -/
theorem ratToFloat_zero (neg : Bool) (den : Nat) :
    ratToFloat neg 0 den = if neg then -0.0 else 0.0 := by
  unfold ratToFloat
  simp only [Id.run, beq_self_eq_true, ↓reduceIte]
  rfl

/-- `float(0)` is `0.0`. -/
theorem intToFloat_zero : intToFloat 0 = 0.0 := by
  unfold intToFloat
  rw [show (0 : Int).natAbs = 0 from rfl, ratToFloat_zero]; rfl

/-! ## `int(str)` and what text is modelled -/

/-- **`int(s)`**: `parseIntStr` is Python's `int()` grammar (`PyIntSpec`). -/
theorem parseIntStr_iff (s : String) (n : Int) : parseIntStr s = some n ↔ PyIntSpec s.toList n :=
  parseIntChars_iff s.toList n

/-- Text is modelled exactly when it is ASCII. -/
theorem numberTextModelled_iff (s : String) :
    numberTextModelled s = true ↔ ∀ c ∈ s.toList, c.toNat < 128 := by
  simp [numberTextModelled]

theorem numberTextModelled_append (s t : String) :
    numberTextModelled (s ++ t) = (numberTextModelled s && numberTextModelled t) := by
  simp [numberTextModelled, String.toList_append]

/-! ## `repr(str)` -/

/-- `hexDigit n` is the lower-case hexadecimal digit of `n < 16`. -/
theorem hexDigit_spec : ∀ n, n < 16 → hexDigit n = Char.ofNat (if n < 10 then 48 + n else 87 + n) := by
  decide

/-- `repr('')` -/
theorem strRepr_empty : strRepr "" = "''" := by
  simp [strRepr, String.foldl_eq_foldl_toList]

/-- A string containing `'` but no `"` is quoted with `"` instead, so
nothing needs escaping: `repr("it's")` is `"it's"`. -/
theorem strRepr_apostrophe : strRepr "it's" = "\"it's\"" := by
  simp [strRepr, String.foldl_eq_foldl_toList]

private theorem foldl_plain (f : String → Char → String) (l : List Char)
    (hf : ∀ acc c, c ∈ l → f acc c = acc.push c) (acc : String) :
    l.foldl f acc = acc ++ String.ofList l := by
  induction l generalizing acc with
  | nil => simp
  | cons c l ih =>
    rw [List.foldl_cons, hf acc c (by simp), ih (fun a d hd => hf a d (by simp [hd]))]
    rw [String.ext_iff]; simp

/-- **`repr` of a plain string** (no quote, backslash or control character)
is the string in single quotes, unchanged. -/
theorem strRepr_plain (s : String)
    (h : ∀ c ∈ s.toList, c ≠ '\'' ∧ c ≠ '\\' ∧ 32 ≤ c.toNat ∧ c.toNat ≠ 127) :
    strRepr s = "'" ++ s ++ "'" := by
  have hq : s.toList.contains '\'' = false := by
    rw [List.contains_eq_mem, decide_eq_false_iff_not]
    intro hm; exact (h _ hm).1 rfl
  unfold strRepr
  simp only [String.foldl_eq_foldl_toList]
  have hc : (s.contains '\'' && !s.contains '"') = false := by
    simp; intro hm; exact absurd rfl (h _ hm).1
  simp only [hc]
  rw [foldl_plain _ s.toList]
  · simp
  · intro acc c hcm
    obtain ⟨h1, h2, h3, h4⟩ := h c hcm
    have n1 : c ≠ '\n' := by rintro rfl; simp at h3
    have n2 : c ≠ '\r' := by rintro rfl; simp at h3
    have n3 : c ≠ '\t' := by rintro rfl; simp at h3
    simp [h1, h2, n1, n2, n3, h4]
    omega

theorem boolStr_eq_True (b : Bool) : boolStr b = "True" ↔ b = true := by
  cases b <;> decide

theorem boolStr_eq_False (b : Bool) : boolStr b = "False" ↔ b = false := by
  cases b <;> decide

/-! ## `repr()` and `str()` of values -/

/-- `reprList` is `repr` of each item, failing if one fails. -/
theorem reprList_eq_mapM (xs : List Value) : reprList xs = xs.mapM pyRepr := by
  induction xs with
  | nil => simp [reprList]
  | cons x xs ih => simp [reprList, ih, List.mapM_cons]

/-- `repr` of a list: its items' `repr`s, comma-separated, in brackets. -/
theorem pyRepr_list (xs : List Value) :
    pyRepr (.list xs) = (xs.mapM pyRepr).map (fun ps => "[" ++ ", ".intercalate ps ++ "]") := by
  rw [pyRepr, reprList_eq_mapM]; rfl

/-- `repr([])`, `repr(())`, `repr({})` -/
theorem pyRepr_empty : pyRepr (.list []) = .ok "[]" ∧ pyRepr (.tuple []) = .ok "()" ∧
    pyRepr (.dict []) = .ok "{}" := by
  refine ⟨?_, ?_, ?_⟩ <;> simp [pyRepr, reprList, reprDict] <;> rfl

/-- A one-element tuple prints with its trailing comma: `(1,)`. -/
theorem pyRepr_tuple_singleton (x : Value) :
    pyRepr (.tuple [x]) = (pyRepr x).map (fun s => "(" ++ s ++ ",)") := by
  rw [pyRepr]
  simp only [reprList]
  cases pyRepr x <;> rfl

/-- `str()` of a string is the string; `repr()` quotes it. -/
theorem pyStr_str (s : String) : pyStr (.str s) = .ok s ∧ pyRepr (.str s) = .ok (strRepr s) := by
  constructor <;> simp [pyStr, pyRepr] <;> rfl

/-- Inside a container a string is printed by `repr`, even under `str()`. -/
theorem pyStr_list_str (s : String) : pyStr (.list [.str s]) = .ok ("[" ++ strRepr s ++ "]") := by
  simp [pyStr, pyRepr, reprList]; rfl

/-- `str(None)`, `str(True)`, `str(False)` -/
theorem pyStr_consts : pyStr .none = .ok "None" ∧ pyStr (.bool true) = .ok "True" ∧
    pyStr (.bool false) = .ok "False" := by
  refine ⟨?_, ?_, ?_⟩ <;> simp [pyStr, pyRepr, boolStr] <;> rfl

/-- An undefined value prints as the empty string. -/
theorem pyStr_undef (n : String) : pyStr (.undef n) = .ok "" := by simp [pyStr]; rfl

/-- `str(datetime)` is `isoformat(" ")`, while its `repr` is not modelled:
an error, never a guess. -/
theorem pyStr_datetime (us : Int) (off : Option Int) :
    pyStr (.datetime us off) = .ok (isoformat us off " ") ∧
      pyRepr (.datetime us off) = .error "repr() of a datetime is not supported by HALean" := by
  constructor <;> simp [pyStr, pyRepr] <;> rfl

/-- `str(timedelta)` and `repr(timedelta)`. -/
theorem pyStr_timedelta (us : Int) :
    pyStr (.timedelta us) = .ok (tdStr us) ∧ pyRepr (.timedelta us) = .ok (tdRepr us) := by
  constructor <;> simp [pyStr, pyRepr] <;> rfl

/-- `repr(range(a, b))` omits a step of 1. -/
theorem pyRepr_range_one (a b : Int) : pyRepr (.range a b 1) = .ok s!"range({a}, {b})" := by
  simp [pyRepr]; rfl

/-! ### Which values can be printed

`repr()` is supported exactly on plain data: `None`, undefined, numbers,
strings, timedeltas, ranges, namespaces, and lists, tuples and dicts of
those. Everything else (states, functions, datetimes, generators, ...) is an
error at any depth, never an approximation. -/

/-- The values `repr()` is modelled for. -/
inductive Printable : Value → Prop where
  | none : Printable .none
  | undef (n : String) : Printable (.undef n)
  | bool (b : Bool) : Printable (.bool b)
  | int (i : Int) : Printable (.int i)
  | float (f : Float) : Printable (.float f)
  | str (s : String) : Printable (.str s)
  | ns (id : Nat) : Printable (.ns id)
  | timedelta (us : Int) : Printable (.timedelta us)
  | range (a b c : Int) : Printable (.range a b c)
  | list (xs : List Value) : (∀ x ∈ xs, Printable x) → Printable (.list xs)
  | tuple (xs : List Value) : (∀ x ∈ xs, Printable x) → Printable (.tuple xs)
  | dict (kvs : List (Value × Value)) : (∀ kv ∈ kvs, Printable kv.1) → (∀ kv ∈ kvs, Printable kv.2) →
      Printable (.dict kvs)

/-- A list's items print exactly when each of them prints. -/
theorem reprList_ok_iff (xs : List Value) :
    (∃ ps, reprList xs = .ok ps) ↔ ∀ x ∈ xs, ∃ s, pyRepr x = .ok s := by
  induction xs with
  | nil => simp [reprList]; exact ⟨[], rfl⟩
  | cons x xs ih =>
    simp only [reprList, List.mem_cons, forall_eq_or_imp, ← ih]
    cases hx : pyRepr x with
    | error e => simp [bind, Except.bind]
    | ok s =>
      cases hxs : reprList xs with
      | error e => simp [bind, Except.bind]
      | ok ps => simp [bind, Except.bind, pure, Except.pure]

/-- A dict's items print exactly when every key and every value prints. -/
theorem reprDict_ok_iff (kvs : List (Value × Value)) :
    (∃ ps, reprDict kvs = .ok ps) ↔
      (∀ kv ∈ kvs, ∃ s, pyRepr kv.1 = .ok s) ∧ (∀ kv ∈ kvs, ∃ s, pyRepr kv.2 = .ok s) := by
  induction kvs with
  | nil => simp [reprDict]; exact ⟨[], rfl⟩
  | cons kv kvs ih =>
    obtain ⟨k, v⟩ := kv
    simp only [reprDict, List.mem_cons, forall_eq_or_imp]
    rw [and_and_and_comm, ← ih]
    cases hk : pyRepr k with
    | error e => simp [bind, Except.bind]
    | ok s =>
      cases hv : pyRepr v with
      | error e => simp [bind, Except.bind]
      | ok t =>
        cases hxs : reprDict kvs with
        | error e => simp [bind, Except.bind]
        | ok ps => simp [bind, Except.bind, pure, Except.pure]

/-- Plain data always prints. -/
theorem pyRepr_ok_of_printable (v : Value) (h : Printable v) : ∃ s, pyRepr v = .ok s := by
  induction h with
  | list xs _ ih =>
    obtain ⟨ps, hps⟩ := (reprList_ok_iff xs).2 ih
    exact ⟨_, by rw [pyRepr, hps]; rfl⟩
  | tuple xs _ ih =>
    obtain ⟨ps, hps⟩ := (reprList_ok_iff xs).2 ih
    exact ⟨_, by rw [pyRepr, hps]; rfl⟩
  | dict kvs _ _ ih1 ih2 =>
    obtain ⟨ps, hps⟩ := (reprDict_ok_iff kvs).2 ⟨ih1, ih2⟩
    exact ⟨_, by rw [pyRepr, hps]; rfl⟩
  | _ => exact ⟨_, by rw [pyRepr]; rfl⟩

/-- Only plain data prints: a value with anything else inside it, at any
depth, is an error. -/
theorem printable_of_pyRepr_ok : ∀ (v : Value) (s : String), pyRepr v = .ok s → Printable v
  | .none, _, _ => .none
  | .undef n, _, _ => .undef n
  | .bool b, _, _ => .bool b
  | .int i, _, _ => .int i
  | .float f, _, _ => .float f
  | .str s, _, _ => .str s
  | .ns id, _, _ => .ns id
  | .timedelta us, _, _ => .timedelta us
  | .range a b c, _, _ => .range a b c
  | .list xs, s, h => by
    have hl : ∃ ps, reprList xs = .ok ps := by
      rw [pyRepr] at h
      cases hps : reprList xs with
      | error e => rw [hps] at h; cases h
      | ok ps => exact ⟨ps, rfl⟩
    refine .list xs (fun x hx => ?_)
    obtain ⟨t, ht⟩ := (reprList_ok_iff xs).1 hl x hx
    have := List.sizeOf_lt_of_mem hx
    exact printable_of_pyRepr_ok x t ht
  | .tuple xs, s, h => by
    have hl : ∃ ps, reprList xs = .ok ps := by
      rw [pyRepr] at h
      cases hps : reprList xs with
      | error e => rw [hps] at h; cases h
      | ok ps => exact ⟨ps, rfl⟩
    refine .tuple xs (fun x hx => ?_)
    obtain ⟨t, ht⟩ := (reprList_ok_iff xs).1 hl x hx
    have := List.sizeOf_lt_of_mem hx
    exact printable_of_pyRepr_ok x t ht
  | .dict kvs, s, h => by
    have hl : ∃ ps, reprDict kvs = .ok ps := by
      rw [pyRepr] at h
      cases hps : reprDict kvs with
      | error e => rw [hps] at h; cases h
      | ok ps => exact ⟨ps, rfl⟩
    obtain ⟨h1, h2⟩ := (reprDict_ok_iff kvs).1 hl
    refine .dict kvs (fun kv hx => ?_) (fun kv hx => ?_)
    · obtain ⟨t, ht⟩ := h1 kv hx
      have := List.sizeOf_lt_of_mem hx
      have : sizeOf kv.1 < sizeOf kv := by cases kv; simp; omega
      exact printable_of_pyRepr_ok kv.1 t ht
    · obtain ⟨t, ht⟩ := h2 kv hx
      have := List.sizeOf_lt_of_mem hx
      have : sizeOf kv.2 < sizeOf kv := by cases kv; simp; omega
      exact printable_of_pyRepr_ok kv.2 t ht
  | .state _ _, _, h | .domain _, _, h | .allStates, _, h | .func _ _, _, h | .datetime _ _, _, h
  | .gen _ _, _, h | .pyobj _ _, _, h | .opaque _, _, h => by rw [pyRepr] at h; cases h
termination_by v => sizeOf v
decreasing_by all_goals simp_wf; all_goals omega

/-- **`repr()` succeeds exactly on plain data.** -/
theorem pyRepr_ok_iff (v : Value) : (∃ s, pyRepr v = .ok s) ↔ Printable v :=
  ⟨fun ⟨s, h⟩ => printable_of_pyRepr_ok v s h, pyRepr_ok_of_printable v⟩

/-- `str()` is `repr()` except on strings, undefined, datetimes and
timedeltas; in particular it prints the same containers. -/
theorem pyStr_eq_pyRepr (v : Value) (h1 : ∀ s, v ≠ .str s) (h2 : ∀ us off, v ≠ .datetime us off)
    (h3 : ∀ us, v ≠ .timedelta us) : pyStr v = pyRepr v := by
  cases v <;> simp_all [pyStr, pyRepr] <;> rfl

/-! ## `range` -/

/-- A zero step gives nothing (Python raises before building such a range). -/
theorem rangeItems_step_zero (a b : Int) : rangeItems a b 0 = [] := by simp [rangeItems]

private theorem lt_ceil_iff (n c : Int) (i : Nat) (hc : 0 < c) :
    i < ((n + c - 1) / c).toNat ↔ c * i < n := by
  have h1 : (i : Int) < (n + c - 1) / c ↔ (i : Int) + 1 ≤ (n + c - 1) / c := by omega
  have h2 := Int.le_ediv_iff_mul_le (a := (i : Int) + 1) (b := n + c - 1) hc
  have h3 : ((i : Int) + 1) * c = c * i + c := by rw [Int.add_mul, Int.mul_comm]; simp
  constructor
  · intro h
    have : (i : Int) + 1 ≤ (n + c - 1) / c := by omega
    have := h2.1 this
    omega
  · intro h
    have : (i : Int) + 1 ≤ (n + c - 1) / c := h2.2 (by omega)
    omega

/-- **`range` with a positive step**: `a, a + c, a + 2c, ...` below `b`. -/
theorem mem_rangeItems_pos (a b c x : Int) (hc : 0 < c) :
    x ∈ rangeItems a b c ↔ ∃ i : Nat, x = a + c * i ∧ x < b := by
  have e : rangeItems a b c =
      (List.range ((b - a + c - 1) / c).toNat).map (fun (i : Nat) => a + c * (i : Int)) := by
    have hne : c ≠ 0 := by omega
    simp [rangeItems, hne, hc]
  rw [e]
  simp only [List.mem_map, List.mem_range]
  constructor
  · rintro ⟨i, hi, rfl⟩
    exact ⟨i, rfl, by have := (lt_ceil_iff (b - a) c i hc).1 hi; omega⟩
  · rintro ⟨i, rfl, hlt⟩
    exact ⟨i, (lt_ceil_iff (b - a) c i hc).2 (by omega), rfl⟩

/-- **`range` with a negative step**: `a, a + c, a + 2c, ...` above `b`. -/
theorem mem_rangeItems_neg (a b c x : Int) (hc : c < 0) :
    x ∈ rangeItems a b c ↔ ∃ i : Nat, x = a + c * i ∧ b < x := by
  have e : rangeItems a b c =
      (List.range ((a - b + -c - 1) / -c).toNat).map (fun (i : Nat) => a + c * (i : Int)) := by
    have hne : c ≠ 0 := by omega
    have hnp : ¬ (0 < c) := by omega
    have e' : a - b - c - 1 = a - b + -c - 1 := by omega
    simp [rangeItems, hne, hnp, e']
  rw [e]
  simp only [List.mem_map, List.mem_range]
  have key : ∀ i : Nat, i < ((a - b + -c - 1) / -c).toNat ↔ b < a + c * i := by
    intro i
    have := lt_ceil_iff (a - b) (-c) i (by omega)
    rw [Int.neg_mul] at this
    omega
  constructor
  · rintro ⟨i, hi, rfl⟩
    exact ⟨i, rfl, (key i).1 hi⟩
  · rintro ⟨i, rfl, hlt⟩
    exact ⟨i, (key i).2 hlt, rfl⟩

/-- `len(range(a, b))` -/
theorem rangeItems_one_length (a b : Int) : (rangeItems a b 1).length = (b - a).toNat := by
  simp [rangeItems]

/-- `range(a, b)` holds exactly the integers from `a` up to, not including, `b`. -/
theorem mem_rangeItems_one (a b x : Int) : x ∈ rangeItems a b 1 ↔ a ≤ x ∧ x < b := by
  rw [mem_rangeItems_pos a b 1 x (by decide)]
  constructor
  · rintro ⟨i, rfl, h⟩; omega
  · rintro ⟨h1, h2⟩; exact ⟨(x - a).toNat, by omega, h2⟩

/-- A range is empty exactly when its first item would already be past the stop. -/
theorem rangeItems_eq_nil_iff (a b c : Int) :
    rangeItems a b c = [] ↔ c = 0 ∨ (0 < c ∧ b ≤ a) ∨ (c < 0 ∧ a ≤ b) := by
  by_cases h0 : c = 0
  · subst h0; simp [rangeItems]
  · by_cases hc : 0 < c
    · have := mem_rangeItems_pos a b c a hc
      constructor
      · intro h
        rw [h] at this
        have hn : ¬ ∃ i : Nat, a = a + c * i ∧ a < b := fun h' => by simpa using this.2 h'
        refine Or.inr (Or.inl ⟨hc, ?_⟩)
        apply Int.not_lt.1
        intro hlt; exact hn ⟨0, by simp, hlt⟩
      · rintro (h | ⟨_, h⟩ | ⟨h, _⟩)
        · exact absurd h h0
        · rw [List.eq_nil_iff_forall_not_mem]
          intro x hx
          obtain ⟨i, rfl, hlt⟩ := (mem_rangeItems_pos a b c x hc).1 hx
          have : 0 ≤ c * (i : Int) := Int.mul_nonneg (Int.le_of_lt hc) (Int.natCast_nonneg i)
          omega
        · omega
    · have hc' : c < 0 := by omega
      have := mem_rangeItems_neg a b c a hc'
      constructor
      · intro h
        rw [h] at this
        have hn : ¬ ∃ i : Nat, a = a + c * i ∧ b < a := fun h' => by simpa using this.2 h'
        refine Or.inr (Or.inr ⟨hc', ?_⟩)
        apply Int.not_lt.1
        intro hlt; exact hn ⟨0, by simp, hlt⟩
      · rintro (h | ⟨h, _⟩ | ⟨_, h⟩)
        · exact absurd h h0
        · omega
        · rw [List.eq_nil_iff_forall_not_mem]
          intro x hx
          obtain ⟨i, rfl, hlt⟩ := (mem_rangeItems_neg a b c x hc').1 hx
          have : 0 ≤ (-c) * (i : Int) := Int.mul_nonneg (by omega) (Int.natCast_nonneg i)
          rw [Int.neg_mul] at this
          omega

/-- `bool(range(...))`: a range is truthy exactly when it has an item. -/
theorem truthy_range (a b c : Int) :
    truthy (.range a b c) = true ↔ (0 < c ∧ a < b) ∨ (c < 0 ∧ b < a) := by
  have h := rangeItems_eq_nil_iff a b c
  simp only [truthy, Bool.not_eq_true', List.isEmpty_eq_false_iff]
  constructor
  · intro hne
    have : ¬ (c = 0 ∨ (0 < c ∧ b ≤ a) ∨ (c < 0 ∧ a ≤ b)) := fun h' => hne (h.2 h')
    omega
  · intro hc hnil
    have := h.1 hnil
    omega

/-! ## Comparing numbers -/

/-- On ints, `==` and `<` are the integers' own: exactly one of `a < b`,
`a == b`, `b < a` holds. -/
theorem numLt_int_trichotomy (a b : Int) :
    (numLt (.i a) (.i b) = true ∧ numEq (.i a) (.i b) = false ∧ numLt (.i b) (.i a) = false) ∨
    (numLt (.i a) (.i b) = false ∧ numEq (.i a) (.i b) = true ∧ numLt (.i b) (.i a) = false) ∨
    (numLt (.i a) (.i b) = false ∧ numEq (.i a) (.i b) = false ∧ numLt (.i b) (.i a) = true) := by
  simp only [numLt, numEq, decide_eq_true_eq, decide_eq_false_iff_not, beq_iff_eq, beq_eq_false_iff_ne, ne_eq]
  omega

/-- Mixed int/float equality does not depend on the order of the operands. -/
theorem numEq_int_float_comm (a : Int) (f : Float) : numEq (.i a) (.f f) = numEq (.f f) (.i a) := rfl

/-- Mixed int/float `<` one way is `>` the other way. -/
theorem numEq_int_comm (a b : Int) : numEq (.i a) (.i b) = numEq (.i b) (.i a) := by
  simp only [numEq]; rw [Bool.eq_iff_iff]; simp only [beq_iff_eq]; omega

/-- NaN is not equal to any int and not ordered with it (`1 == nan`,
`1 < nan`, `nan < 1` are all False). -/
theorem num_nan (a : Int) (f : Float) (h : f.isNaN = true) :
    numEq (.i a) (.f f) = false ∧ numEq (.f f) (.i a) = false ∧
      numLt (.i a) (.f f) = false ∧ numLt (.f f) (.i a) = false := by
  simp [numEq, numLt, h]

/-- Every int is below `+inf` and above `-inf`, whatever its size. -/
theorem cmpIntFloat_inf (i : Int) (f : Float) (hn : f.isNaN = false) (h : f.isInf = true) :
    cmpIntFloat i f = if f > 0 then .lt else .gt := by
  simp [cmpIntFloat, hn, h]

/-- `True == 1`, `False == 0`: a bool is the int Python says it is. -/
theorem num?_bool (b : Bool) : (Value.bool b).num?.map (numEq (.i (if b then 1 else 0))) = some true := by
  cases b <;> rfl

/-- Equal states have the same entity id and state string (timestamps are
not compared). -/
theorem stateEq_fields (a b : EntityState) (h : stateEq a b = true) :
    a.entityId = b.entityId ∧ a.state = b.state := by
  simp only [stateEq, Bool.and_eq_true, beq_iff_eq] at h
  exact ⟨h.1.1, h.1.2⟩

/-- The numeric values are exactly the ones Python calls `bool`, `int`, `float`. -/
theorem typeName_of_num (v : Value) (h : v.num?.isSome = true) :
    typeName v = "bool" ∨ typeName v = "int" ∨ typeName v = "float" := by
  cases v <;> simp_all [Value.num?, typeName]

end HALean.Template
