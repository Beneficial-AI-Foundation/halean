/-
  Specifications for the pure helpers of `HALean/Template/Render.lean`:
  render-info rate limits and filters, Python sequence indexing and slicing,
  half-even rounding, `cv.boolean` on values, and Python `str` methods.
-/
import HALean.Template.Render

namespace HALean.Template

/-! ## `RenderInfo`: rate limit and filters -/

/-- A static template is never rate limited. -/
theorem rateLimit_static (i : RInfo) (h : i.isStatic = true) : i.rateLimit = none := by
  simp [RInfo.rateLimit, h]

/-- `ALL_STATES_RATE_LIMIT` applies exactly to non-static renders that
iterated all states or raised. -/
theorem rateLimit_eq_all_iff (i : RInfo) :
    i.rateLimit = some ALL_STATES_RATE_LIMIT ↔
      i.isStatic = false ∧ (i.allStates = true ∨ i.exception = true) := by
  unfold RInfo.rateLimit
  cases i.isStatic <;> cases i.allStates <;> cases i.exception <;>
    cases i.domains.isEmpty <;> cases i.domainsLifecycle.isEmpty <;>
    simp [ALL_STATES_RATE_LIMIT, DOMAIN_STATES_RATE_LIMIT]

/-- `DOMAIN_STATES_RATE_LIMIT` applies exactly to non-static renders that
did not touch all states, did not raise, and iterated some domain. -/
theorem rateLimit_eq_domain_iff (i : RInfo) :
    i.rateLimit = some DOMAIN_STATES_RATE_LIMIT ↔
      i.isStatic = false ∧ i.allStates = false ∧ i.exception = false ∧
        (i.domains ≠ [] ∨ i.domainsLifecycle ≠ []) := by
  unfold RInfo.rateLimit
  cases i.isStatic <;> cases i.allStates <;> cases i.exception <;>
    cases hd : i.domains <;> cases hl : i.domainsLifecycle <;>
    simp [ALL_STATES_RATE_LIMIT, DOMAIN_STATES_RATE_LIMIT]

/-- No rate limit: static, or only specific entities were read. -/
theorem rateLimit_eq_none_iff (i : RInfo) :
    i.rateLimit = none ↔
      i.isStatic = true ∨ (i.allStates = false ∧ i.exception = false ∧
        i.domains = [] ∧ i.domainsLifecycle = []) := by
  unfold RInfo.rateLimit
  cases i.isStatic <;> cases i.allStates <;> cases i.exception <;>
    cases hd : i.domains <;> cases hl : i.domainsLifecycle <;>
    simp

/-- The rate limit is one of the two HA constants. -/
theorem rateLimit_values (i : RInfo) (n : Nat) (h : i.rateLimit = some n) : n = 60 ∨ n = 1 := by
  unfold RInfo.rateLimit at h
  repeat' split at h
  all_goals simp_all [ALL_STATES_RATE_LIMIT, DOMAIN_STATES_RATE_LIMIT]
  all_goals omega

/-- A static template, a render that raised, or one that iterated all states
passes every entity through the filter. -/
theorem filter_all (i : RInfo) (eid : String)
    (h : i.isStatic = true ∨ i.exception = true ∨ i.allStates = true) : i.filter eid = true := by
  unfold RInfo.filter
  rcases h with h | h | h <;> simp [h]

/-- An entity the render read always passes its filter. -/
theorem filter_of_mem (i : RInfo) (eid : String) (h : eid ∈ i.entities) : i.filter eid = true := by
  unfold RInfo.filter
  repeat' split
  all_goals simp_all

/-- `RenderInfo.filter` (`_filter_domains_and_entities` / `_filter_entities`
/ the all-states filter), exactly. -/
theorem filter_iff (i : RInfo) (eid : String) :
    i.filter eid = true ↔
      i.isStatic = true ∨ i.exception = true ∨ i.allStates = true ∨
        eid ∈ i.entities ∨ domainOf eid ∈ i.domains := by
  unfold RInfo.filter
  cases i.isStatic <;> cases i.exception <;> cases i.allStates <;> cases hd : i.domains <;>
    simp
  rw [or_comm]

/-- `RenderInfo.filter_lifecycle`, exactly. -/
theorem filterLifecycle_iff (i : RInfo) (eid : String) :
    i.filterLifecycle eid = true ↔
      i.isStatic = true ∨ i.exception = true ∨ i.allStatesLifecycle = true ∨
        domainOf eid ∈ i.domainsLifecycle := by
  unfold RInfo.filterLifecycle
  cases i.isStatic <;> cases i.exception <;> cases i.allStatesLifecycle <;> simp

/-- While a rate-limit timer is pending only the per-entity listeners fire. -/
theorem listens_rateLimited (i : RInfo) (eid : String) :
    i.listens eid true = true ↔ eid ∈ i.entities := by
  simp [RInfo.listens]

/-- Whatever is delivered while rate limited is also delivered otherwise. -/
theorem listens_mono (i : RInfo) (eid : String) (h : i.listens eid true = true) :
    i.listens eid false = true := by
  simp [RInfo.listens] at h ⊢
  simp [h]

/-- Outside a rate limit, a tracked change passes the filter or the lifecycle
filter only if some listener delivers it (unless the template is static or
raised, where the tracker re-renders on its own). -/
theorem listens_of_filter (i : RInfo) (eid : String)
    (hs : i.isStatic = false) (he : i.exception = false)
    (h : i.filter eid = true ∨ i.filterLifecycle eid = true) : i.listens eid false = true := by
  rw [filter_iff, filterLifecycle_iff] at h
  simp [RInfo.listens]
  simp [hs, he] at h
  rcases h with (h | h | h) | (h | h) <;> simp [h]

/-! ## `cv.boolean` / `result_as_boolean` on values -/

/-- `cv.boolean(int)`: `bool(value)`. -/
theorem cvBoolean_int (i : Int) : cvBoolean (.int i) = some true ↔ i ≠ 0 := by
  simp [cvBoolean]

/-- `cv.boolean` of text is `cvBooleanText` (characterised by
`cvBooleanText_iff`). -/
theorem cvBoolean_str (s : String) : cvBoolean (.str s) = cvBooleanText s := rfl

/-- Only bools, numbers and strings can be booleans: everything else is
`vol.Invalid`. -/
theorem cvBoolean_isSome (v : Value) (h : (cvBoolean v).isSome = true) :
    (∃ b, v = .bool b) ∨ (∃ i, v = .int i) ∨ (∃ f, v = .float f) ∨ (∃ s, v = .str s) := by
  cases v <;> simp_all [cvBoolean]

/-- `result_as_boolean`: true exactly when `cv.boolean` accepts the value as
true (`None` and anything invalid are False). -/
theorem resultAsBoolean_iff (v : Value) : resultAsBoolean v = true ↔ cvBoolean v = some true := by
  cases v <;> simp [resultAsBoolean, cvBoolean]
  rename_i s
  cases cvBooleanText s <;> simp

/-- A bool is its own result. -/
theorem resultAsBoolean_bool (b : Bool) : resultAsBoolean (.bool b) = b := by
  simp [resultAsBoolean, cvBoolean]

/-- Collections and other objects are never a true result. -/
theorem resultAsBoolean_list (xs : List Value) : resultAsBoolean (.list xs) = false := rfl

/-! ## `iif` -/

/-- With no branches given, `iif` returns a bool: the value's truthiness. -/
theorem iif_default (v : Value) : iif v none none none = .bool (truthy v) := by
  cases v <;> simp [iif] <;> split <;> simp_all

/-- `if_none` is only used for `None`. -/
theorem iif_not_none (v : Value) (t f n : Option Value) (h : v ≠ .none) :
    iif v t f n = iif v t f none := by
  cases v <;> cases n <;> simp_all [iif]

/-- `None` without `if_none` is falsy. -/
theorem iif_none_falsy (t f : Option Value) : iif .none t f none = f.getD (.bool false) := by
  simp [iif, truthy]

/-! ## Dict lookup -/

/-- A lookup returns the value of some entry whose key equals the key asked. -/
theorem lookupKV_some (kvs : List (Value × Value)) (k v : Value) (h : lookupKV kvs k = some v) :
    ∃ k', (k', v) ∈ kvs ∧ pyEq k' k = true := by
  simp only [lookupKV, Option.map_eq_some_iff] at h
  obtain ⟨⟨k', v'⟩, hf, rfl⟩ := h
  exact ⟨k', List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf⟩

/-- A lookup fails exactly when no key equals the key asked. -/
theorem lookupKV_none_iff (kvs : List (Value × Value)) (k : Value) :
    lookupKV kvs k = none ↔ ∀ p ∈ kvs, pyEq p.1 k = false := by
  simp [lookupKV]

/-- The first matching entry wins. -/
theorem lookupKV_cons (kvs : List (Value × Value)) (k k' v : Value) :
    lookupKV ((k', v) :: kvs) k = if pyEq k' k then some v else lookupKV kvs k := by
  simp only [lookupKV, List.find?_cons]
  split <;> simp_all

/-! ## Sequence indexing (`xs[i]`) -/

/-- `seqIndex` by cases, with the bounds as propositions. -/
theorem seqIndex_eq (xs : List α) (i : Int) :
    seqIndex xs i =
      if i < 0 then (if i + xs.length < 0 then none else xs[(i + xs.length).toNat]?)
      else (if (xs.length : Int) ≤ i then none else xs[i.toNat]?) := by
  unfold seqIndex
  by_cases h1 : i < 0
  · by_cases h2 : i + xs.length < 0
    · simp [h1, h2]
    · have h3 : ¬ ((xs.length : Int) ≤ i + xs.length) := by omega
      simp [h1, h2, h3]
  · by_cases h2 : (xs.length : Int) ≤ i
    · simp [h1, h2]
    · simp [h1, h2]

/-- A non-negative index counts from the front. -/
theorem seqIndex_nonneg (xs : List α) (i : Nat) : seqIndex xs (i : Int) = xs[i]? := by
  rw [seqIndex_eq]
  have h1 : ¬ ((i : Int) < 0) := by omega
  simp only [h1, ↓reduceIte]
  split
  · rename_i h; symm; simp; omega
  · simp

/-- A negative index counts from the back: `xs[-k] = xs[len - k]`. -/
theorem seqIndex_neg (xs : List α) (k : Nat) (hk : 0 < k) (hl : k ≤ xs.length) :
    seqIndex xs (-(k : Int)) = xs[xs.length - k]? := by
  rw [seqIndex_eq]
  have h1 : (-(k : Int) < 0) := by omega
  have h2 : ¬ (-(k : Int) + (xs.length : Int) < 0) := by omega
  have h4 : (-(k : Int) + (xs.length : Int)).toNat = xs.length - k := by omega
  simp only [h1, h2, ↓reduceIte, h4]

/-- `xs[i]` is defined exactly for `-len ≤ i < len` (otherwise `IndexError`). -/
theorem seqIndex_isSome_iff (xs : List α) (i : Int) :
    (seqIndex xs i).isSome = true ↔ -(xs.length : Int) ≤ i ∧ i < xs.length := by
  rw [seqIndex_eq]
  split <;> split <;> simp <;> omega

/-- `xs[-1]` is the last item. -/
theorem seqIndex_last (xs : List α) : seqIndex xs (-1) = xs.getLast? := by
  cases h : xs.length with
  | zero => simp [List.length_eq_zero_iff.mp h, seqIndex]
  | succ n =>
    have := seqIndex_neg xs 1 (by omega) (by omega)
    simp only [Int.natCast_one] at this
    rw [this, List.getLast?_eq_getElem?]

/-- An indexed item is an item of the list. -/
theorem seqIndex_mem (xs : List α) (i : Int) (x : α) (h : seqIndex xs i = some x) : x ∈ xs := by
  rw [seqIndex_eq] at h
  split at h <;> split at h <;> first | (simp at h; done) | exact List.mem_of_getElem? h

/-! ## Half-even rounding -/

/-- What "round `n/d` to the nearest integer, ties to even" means: `r` is
within one half of `n/d`, and when `n/d` is exactly halfway `r` is even. -/
def IsRoundHalfEven (n d r : Nat) : Prop :=
  2 * (d * r) ≤ 2 * n + d ∧ 2 * n ≤ 2 * (d * r) + d ∧
    ((2 * (d * r) = 2 * n + d ∨ 2 * n = 2 * (d * r) + d) → r % 2 = 0)

/-- `roundHalfEven` rounds to nearest, ties to even. -/
theorem roundHalfEven_spec (n d : Nat) (hd : 0 < d) : IsRoundHalfEven n d (roundHalfEven n d) := by
  unfold roundHalfEven IsRoundHalfEven
  dsimp only
  have hdiv := Nat.div_add_mod n d
  have hmod := Nat.mod_lt n hd
  generalize n / d = q at *
  generalize n % d = r at *
  have hs : d * (q + 1) = d * q + d := Nat.mul_succ d q
  have hc : (decide (2 * r > d) || (2 * r == d && q % 2 == 1)) = true ↔
      (d < 2 * r ∨ (2 * r = d ∧ q % 2 = 1)) := by simp
  split
  · rename_i h
    rw [hc] at h
    rw [hs]
    refine ⟨by omega, by omega, ?_⟩
    intro h'
    omega
  · rename_i h
    rw [hc] at h
    refine ⟨by omega, by omega, ?_⟩
    intro h'
    omega

/-- The nearest-even rounding is unique, so the spec pins the function down. -/
theorem roundHalfEven_unique (n d r : Nat) (hd : 0 < d) (h : IsRoundHalfEven n d r) :
    roundHalfEven n d = r := by
  have h0 := roundHalfEven_spec n d hd
  generalize roundHalfEven n d = r0 at h0
  obtain ⟨a1, a2, a3⟩ := h0
  obtain ⟨b1, b2, b3⟩ := h
  -- the two candidates differ by at most one
  have key : ∀ x y : Nat, 2 * (d * x) ≤ 2 * n + d → 2 * n ≤ 2 * (d * y) + d → x ≤ y + 1 := by
    intro x y hx hy
    apply Classical.byContradiction
    intro hlt
    have hxy : y + 2 ≤ x := by omega
    have := Nat.mul_le_mul_left d hxy
    have hs : d * (y + 2) = d * y + 2 * d := by rw [Nat.mul_add]; omega
    omega
  have h1 := key r0 r a1 b2
  have h2 := key r r0 b1 a2
  rcases Nat.lt_trichotomy r0 r with hlt | heq | hgt
  · have : r = r0 + 1 := by omega
    subst this
    have hs : d * (r0 + 1) = d * r0 + d := Nat.mul_succ d r0
    have e1 := a3 (Or.inr (by omega))
    have e2 := b3 (Or.inl (by omega))
    omega
  · exact heq
  · have : r0 = r + 1 := by omega
    subst this
    have hs : d * (r + 1) = d * r + d := Nat.mul_succ d r
    have e1 := a3 (Or.inl (by omega))
    have e2 := b3 (Or.inr (by omega))
    omega

/-- Exact characterisation. -/
theorem roundHalfEven_iff (n d r : Nat) (hd : 0 < d) :
    roundHalfEven n d = r ↔ IsRoundHalfEven n d r :=
  ⟨fun h => h ▸ roundHalfEven_spec n d hd, roundHalfEven_unique n d r hd⟩

/-- An exact quotient is not changed by rounding. -/
theorem roundHalfEven_mul (q d : Nat) (hd : 0 < d) : roundHalfEven (q * d) d = q := by
  apply roundHalfEven_unique _ _ _ hd
  unfold IsRoundHalfEven
  rw [Nat.mul_comm q d]
  refine ⟨by omega, by omega, by omega⟩

/-- Dividing by one is exact. -/
theorem roundHalfEven_one (n : Nat) : roundHalfEven n 1 = n := by
  simpa using roundHalfEven_mul n 1 (by omega)

/-! ## `scaledUs`: exact scaling to microseconds -/

/-- An int scaled by a whole factor is the exact product (no rounding). -/
theorem scaledUs_int (i : Int) (num : Nat) : scaledUs (.int i) num 1 = some (i * num) := by
  simp only [scaledUs, roundHalfEven_one]
  split
  · congr 1
    rw [Int.natCast_mul]
    have : (i.natAbs : Int) = -i := by omega
    rw [this, Int.neg_mul, Int.neg_neg]
  · congr 1
    rw [Int.natCast_mul]
    have : (i.natAbs : Int) = i := by omega
    rw [this]

/-- A bool counts as 0 or 1. -/
theorem scaledUs_bool (b : Bool) (num : Nat) :
    scaledUs (.bool b) num 1 = scaledUs (.int (if b then 1 else 0)) num 1 := by
  cases b <;> simp [scaledUs, roundHalfEven_one]

/-- Scaling is odd: `-x` scales to the negation. -/
theorem scaledUs_neg (i : Int) (num den : Nat) (r : Int) (h : scaledUs (.int i) num den = some r) :
    scaledUs (.int (-i)) num den = some (-r) := by
  simp only [scaledUs, Int.natAbs_neg] at h ⊢
  rcases Int.lt_trichotomy i 0 with hi | hi | hi
  · have h1 : ¬ (-i < 0) := by omega
    simp [hi] at h ⊢
    omega
  · subst hi
    simp at h ⊢
    simp [roundHalfEven] at h ⊢
    omega
  · have h1 : (-i < 0) := by omega
    have h2 : ¬ (i < 0) := by omega
    simp [h2] at h ⊢
    omega

/-- Only numbers scale. -/
theorem scaledUs_isSome (x : Value) (num den : Nat) (h : (scaledUs x num den).isSome = true) :
    (∃ b, x = .bool b) ∨ (∃ i, x = .int i) ∨ (∃ f, x = .float f) := by
  cases x <;> simp_all [scaledUs]

/-! ## `utc_from_timestamp` -/

/-- `utc_from_timestamp` returns the aware UTC datetime at exactly
`value * 10^6` microseconds (rounded half to even), and only when its year
is in `1..9999` (otherwise Python raises). -/
theorem utcFromTimestamp_some (x v : Value) (h : utcFromTimestamp x = some v) :
    ∃ us, scaledUs x 1000000 = some us ∧ v = .datetime us (some 0) ∧
      1 ≤ (toCivil us).year ∧ (toCivil us).year ≤ 9999 := by
  unfold utcFromTimestamp at h
  split at h
  all_goals simp [Option.bind_eq_some_iff] at h
  all_goals
    obtain ⟨us, hus, hy, hv⟩ := h
    exact ⟨us, hus, hv.symm, by omega, by omega⟩

/-- For an int the microseconds are the exact product. -/
theorem utcFromTimestamp_int (i : Int) (v : Value) (h : utcFromTimestamp (.int i) = some v) :
    v = .datetime (i * 1000000) (some 0) := by
  obtain ⟨us, hus, hv, _⟩ := utcFromTimestamp_some _ _ h
  rw [scaledUs_int] at hus
  simp at hus
  rw [hv, ← hus]

/-- Non-numbers are a `TypeError`. -/
theorem utcFromTimestamp_str (s : String) : utcFromTimestamp (.str s) = none := rfl

/-! ## `parse_time` -/

/-- `parse_time` splits the seconds of the day into hour, minute, second:
minute and second are below 60 and the three recombine to the total. -/
theorem parseTime_some (s : String) (h m sec : Nat) (hp : parseTime s = some (h, m, sec)) :
    ∃ t, parseTimeSeconds s = some t ∧ t = h * 3600 + m * 60 + sec ∧ m < 60 ∧ sec < 60 := by
  simp only [parseTime, Option.map_eq_some_iff] at hp
  obtain ⟨t, ht, he⟩ := hp
  simp only [Prod.mk.injEq] at he
  exact ⟨t, ht, by omega, by omega, by omega⟩

/-- `parse_time` fails exactly when `parseTimeSeconds` does. -/
theorem parseTime_none_iff (s : String) : parseTime s = none ↔ parseTimeSeconds s = none := by
  simp [parseTime]

/-! ## Exact fractions of numbers -/

/-- An int is the fraction `±|v| / 1`. -/
theorem fracOf_int (v : Int) :
    (fracOf (.i v)).2.2 = 1 ∧
      v = (if (fracOf (.i v)).1 then -((fracOf (.i v)).2.1 : Int) else (fracOf (.i v)).2.1) := by
  simp only [fracOf, decide_eq_true_eq, true_and]
  split <;> omega

/-! ## Simple classifiers -/

theorem isOpaqueOrUndef_iff (v : Value) :
    isOpaqueOrUndef v = true ↔ (∃ n, v = .undef n) ∨ (∃ w, v = .opaque w) := by
  cases v <;> simp [isOpaqueOrUndef]

/-- Numbers, `None`, states and datetimes are not iterable. -/
theorem isIterable_scalar (v : Value) (h : isIterable v = true) :
    v ≠ .none ∧ (∀ b, v ≠ .bool b) ∧ (∀ i, v ≠ .int i) ∧ (∀ f, v ≠ .float f) ∧
      (∀ us off, v ≠ .datetime us off) ∧ (∀ us, v ≠ .timedelta us) := by
  cases v <;> simp_all [isIterable]

/-- `isinstance(result, (str, complex))`: strings and complex numbers. -/
theorem isComplexOrStr_iff (v : Value) :
    isComplexOrStr v = true ↔ (∃ s, v = .str s) ∨ v = .opaque "complex" := by
  unfold isComplexOrStr
  split <;> simp_all

/-! ## `math.floor` / `math.ceil` -/

/-- `floor` is the truncation or one below it; it fails only when the float
has no integer value (NaN, infinity). -/
theorem floorF_some (f : Float) (j : Int) (h : floorF f = some j) :
    ∃ i, floatToInt? f = some i ∧ (j = i ∨ j = i - 1) := by
  simp only [floorF, Option.bind_eq_bind] at h
  rw [Option.bind_eq_some_iff] at h
  obtain ⟨i, hi, h⟩ := h
  refine ⟨i, hi, ?_⟩
  split at h <;> simp at h <;> omega

/-- `ceil` is the truncation or one above it. -/
theorem ceilF_some (f : Float) (j : Int) (h : ceilF f = some j) :
    ∃ i, floatToInt? f = some i ∧ (j = i ∨ j = i + 1) := by
  simp only [ceilF, Option.bind_eq_bind] at h
  rw [Option.bind_eq_some_iff] at h
  obtain ⟨i, hi, h⟩ := h
  refine ⟨i, hi, ?_⟩
  split at h <;> simp at h <;> omega

/-- `floor` and `ceil` are defined on the same floats and differ by at most 1. -/
theorem floorF_ceilF (f : Float) :
    (floorF f).isSome = (ceilF f).isSome := by
  simp only [floorF, ceilF, Option.bind_eq_bind]
  cases floatToInt? f <;> simp <;> split <;> split <;> rfl

/-! ## States of a domain -/

/-- `states.<domain>` lists no more than all states. -/
theorem statesOf_length_le (ctx : Ctx) (dom : Option String) :
    (statesOf ctx dom).length ≤ ctx.states.length := by
  simp only [statesOf, List.length_map]
  exact List.length_filter_le _ _

/-- Iterating all states yields every state, in insertion order. -/
theorem statesOf_all (ctx : Ctx) :
    statesOf ctx none = ctx.states.map fun p => .state p.2 false := by
  have h : ∀ l : States, List.filter (fun _ => true) l = l :=
    fun l => List.filter_eq_self.mpr (by simp)
  simp [statesOf, h]

/-- Iterated states are plain (non-collecting) state objects of that domain. -/
theorem statesOf_mem (ctx : Ctx) (d : String) (v : Value) (h : v ∈ statesOf ctx (some d)) :
    ∃ p ∈ ctx.states, v = .state p.2 false ∧ (p.2.domain == d) = true := by
  simp only [statesOf, List.mem_map, List.mem_filter] at h
  obtain ⟨p, ⟨hp, hd⟩, rfl⟩ := h
  exact ⟨p, hp, rfl, hd⟩

end HALean.Template
