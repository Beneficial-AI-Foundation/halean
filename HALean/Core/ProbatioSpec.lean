/-
  Specifications for `HALean/Core/Probatio.lean`: error rendering, the
  "did you mean" machinery, the type names, and the leaf validators
  (`_TypeCheck`, literals, `Clamp`, `Length`, `Coerce`, `Lower`/`Upper`,
  `EnsureList`, `AtLeastOne`, `Port`).  `In`, `NotIn` and `Range` are in
  `HALean/Core/ProbatioProofs.lean`.

  `pyEq` and `safeValue` are `partial def`s, so they appear here only as
  opaque predicates.
-/
import HALean.Core.Probatio

set_option linter.unusedSimpArgs false

namespace HALean.Core.ProbatioSpec
open HALean.Template HALean.Core

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

/-! ## Errors -/

/-- `Invalid.prepend` keeps every leaf (and their order). -/
theorem prependAll_length (seg : PathSeg) (errs : List SchemaError) :
    (prependAll seg errs).length = errs.length := by simp [prependAll]

/-- Every leaf's path gains exactly the new first segment, its message is
untouched. -/
theorem prependAll_getElem? (seg : PathSeg) (errs : List SchemaError) (i : Nat) :
    (prependAll seg errs)[i]? =
      errs[i]?.map fun e => { message := e.message, path := seg :: e.path } := by
  simp [prependAll]

theorem prependAll_messages (seg : PathSeg) (errs : List SchemaError) :
    (prependAll seg errs).map (·.message) = errs.map (·.message) := by
  simp [prependAll]

theorem prependAll_paths (seg : PathSeg) (errs : List SchemaError) :
    (prependAll seg errs).map (·.path) = errs.map (seg :: ·.path) := by
  simp [prependAll]

/-- No leaf is at the top level once a segment is prepended, so each prints
with an ` at '...'` suffix. -/
theorem prependAll_path_ne_nil (seg : PathSeg) (errs : List SchemaError) :
    ∀ e ∈ prependAll seg errs, e.path.isEmpty = false := by
  intro e he
  obtain ⟨e', _, rfl⟩ := List.mem_map.mp he
  rfl

/-- Prepending is compatible with concatenating error lists (the engines
collect errors with `++`). -/
theorem prependAll_append (seg : PathSeg) (a b : List SchemaError) :
    prependAll seg (a ++ b) = prependAll seg a ++ prependAll seg b := by
  simp [prependAll]

/-- `inv` is a `MultipleInvalid` of exactly one leaf. -/
theorem inv_single (msg : String) (path : List PathSeg) :
    ∃ e, inv msg path = .invalid [e] ∧ e.message = msg ∧ e.path = path := ⟨_, rfl, rfl, rfl⟩

/-- `str(Invalid)` with an empty path is just the message. -/
theorem SchemaError.str_no_path (m : String) : SchemaError.str { message := m, path := [] } = m := rfl

/-- `str(Invalid)` with a path: `<message> at '<path>'`. -/
theorem SchemaError.str_path (m : String) (seg : PathSeg) (rest : List PathSeg) :
    SchemaError.str { message := m, path := seg :: rest } =
      m ++ " at '" ++ renderPath (seg :: rest) ++ "'" := rfl

/-- `str(MultipleInvalid)` is the first leaf, whatever follows. -/
theorem multipleInvalidStr_first (e : SchemaError) (es es' : List SchemaError) :
    multipleInvalidStr (e :: es) = multipleInvalidStr (e :: es') := rfl

/-- The string of a single-leaf `inv` at the top level is its message. -/
theorem multipleInvalidStr_inv (msg : String) :
    multipleInvalidStr [{ message := msg, path := [] }] = msg := rfl

/-! ## Rendering -/

/-- `_BARE_KEY = [A-Za-z_][A-Za-z0-9_-]*`, written as a predicate on the
characters. -/
def BareKey (cs : List Char) : Prop :=
  ∃ c rest, cs = c :: rest ∧ (c.isAlpha = true ∨ c = '_') ∧
    ∀ d ∈ rest, d.isAlphanum = true ∨ d = '_' ∨ d = '-'

theorem isBareKey_iff (s : String) : isBareKey s = true ↔ BareKey s.toList := by
  unfold isBareKey BareKey
  cases h : s.toList with
  | nil => simp
  | cons c cs =>
    simp only [Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, List.all_eq_true]
    constructor
    · rintro ⟨h1, h2⟩; exact ⟨c, cs, rfl, h1, fun d hd => by simpa [or_assoc] using h2 d hd⟩
    · rintro ⟨c', rest, heq, h1, h2⟩
      cases heq
      exact ⟨h1, fun d hd => by simpa [or_assoc] using h2 d hd⟩

/-- The empty string is not a bare key. -/
theorem isBareKey_empty : isBareKey "" = false := rfl

/-- A short repr is rendered whole. -/
theorem renderSegment_short (r : String) (h : r.length ≤ 500) : renderSegment r = r := by
  unfold renderSegment
  rw [ifN (by omega)]

/-- A long repr is cut and ends with an ellipsis. -/
theorem renderSegment_long (r : String) (h : 500 < r.length) :
    ∃ pre, renderSegment r = pre ++ "..." := by
  unfold renderSegment
  rw [ifP h]; exact ⟨_, rfl⟩

/-- The empty path renders as nothing. -/
theorem renderPath_nil : renderPath [] = "" := rfl

/-- One step of `render_path`: what one more segment appends to the text
rendered so far. -/
def renderStep (out : String) (seg : PathSeg) : String :=
  match seg with
  | .idx i => out ++ s!"[{i}]"
  | .key s | .group s =>
    let text := match seg with | .group g => "<" ++ g ++ ">" | _ => s
    let bare := text.length ≤ 500 &&
      (isBareKey text || (text.startsWith "<" && text.endsWith ">" &&
        isBareKey ((text.drop 1).toString.dropEnd 1).toString))
    if bare then (if out.isEmpty then text else out ++ "." ++ text)
    else
      let r := match seg with | .group _ => text | _ => strRepr s
      out ++ "[" ++ renderSegment r ++ "]"

/-- `render_path` is a left fold of its segments (the imperative loop
written as a fold). -/
theorem renderPath_foldl (path : List PathSeg) : renderPath path = path.foldl renderStep "" := by
  unfold renderPath
  simp only [Id.run]
  generalize "" = acc
  induction path generalizing acc with
  | nil => rfl
  | cons a as ih =>
    rw [List.forIn_cons, List.foldl_cons]
    cases a with
    | idx i => simp only [renderStep, pure_bind]; exact ih _
    | key s =>
      simp only [renderStep]
      split <;> simp only [pure_bind] <;> exact ih _
    | group s =>
      simp only [renderStep]
      split <;> simp only [pure_bind] <;> exact ih _

/-- Rendering a longer path only appends to the rendering of its prefix. -/
theorem renderPath_append (p q : List PathSeg) :
    renderPath (p ++ q) = q.foldl renderStep (renderPath p) := by
  simp only [renderPath_foldl, List.foldl_append]

/-- A list index renders as `[n]`, glued to what precedes it. -/
theorem renderPath_append_idx (path : List PathSeg) (i : Nat) :
    renderPath (path ++ [.idx i]) = renderPath path ++ ("[" ++ toString i ++ "]") := by
  simp only [renderPath_append, List.foldl_cons, List.foldl_nil, renderStep]
  rfl

/-- An identifier-like key at the start renders bare. -/
theorem renderPath_bare_key (k : String) (h : isBareKey k = true) (hl : k.length ≤ 500) :
    renderPath [.key k] = k := by
  rw [renderPath_foldl]; simp [renderStep, h, hl]

/-- An identifier-like key after other segments joins with a dot (unless
nothing was rendered before it). -/
theorem renderPath_append_bare_key (path : List PathSeg) (k : String)
    (h : isBareKey k = true) (hl : k.length ≤ 500) :
    renderPath (path ++ [.key k]) =
      if (renderPath path).isEmpty then k else renderPath path ++ "." ++ k := by
  simp [renderPath_append, renderStep, h, hl]

/-- `items[0]`: a key then an index. -/
theorem renderPath_key_idx (k : String) (i : Nat) (h : isBareKey k = true) (hl : k.length ≤ 500) :
    renderPath [.key k, .idx i] = k ++ ("[" ++ toString i ++ "]") := by
  have := renderPath_append_idx [.key k] i
  rw [renderPath_bare_key k h hl] at this
  exact this

/-- A key that is not identifier-like (and not `<...>`) renders as its
bracketed, possibly cut, repr. -/
theorem renderPath_append_quoted_key (path : List PathSeg) (k : String)
    (h : isBareKey k = false) (hlt : k.startsWith "<" = false) :
    renderPath (path ++ [.key k]) = renderPath path ++ "[" ++ renderSegment (strRepr k) ++ "]" := by
  simp [renderPath_append, renderStep, h, hlt]

/-- `str(Invalid)` of an error at a list index. -/
theorem SchemaError.str_idx (m : String) (i : Nat) :
    SchemaError.str { message := m, path := [.idx i] } = m ++ " at '" ++ ("[" ++ toString i ++ "]") ++ "'" := by
  have := renderPath_append_idx [] i
  simp only [List.nil_append, renderPath_nil] at this
  rw [SchemaError.str_path, this]
  simp

/-! ## `_format_candidates` -/

theorem formatCandidates_nil : formatCandidates [] = "" := rfl

/-- One candidate: just its repr. -/
theorem formatCandidates_one (a : String) : formatCandidates [a] = strRepr a := rfl

/-- Two candidates: `'a' or 'b'`. -/
theorem formatCandidates_two (a b : String) :
    formatCandidates [a, b] = strRepr a ++ " or " ++ strRepr b := rfl

/-- Three candidates: `'a', 'b' or 'c'`. -/
theorem formatCandidates_three (a b c : String) :
    formatCandidates [a, b, c] = strRepr a ++ ", " ++ strRepr b ++ " or " ++ strRepr c := rfl

/-! ## difflib -/

/-- Python's `str` ordering is Lean's (code points). -/
theorem pyStrLt_iff (a b : String) : pyStrLt a b = true ↔ a < b := by simp [pyStrLt]

theorem pyStrLt_irrefl (a : String) : pyStrLt a a = false := by
  simp [pyStrLt, Std.lt_irrefl]

/-- `get_close_matches` returns at most `n` names. -/
theorem getCloseMatches_length (word : String) (ps : List String) (cutoff : Float) (n : Nat) :
    (getCloseMatches word ps cutoff n).length ≤ n := by
  simp [getCloseMatches, List.length_take]
  exact Nat.min_le_left _ _

/-- Every suggestion is one of the possibilities, and it scored at least the
cutoff. -/
theorem getCloseMatches_mem (word : String) (ps : List String) (cutoff : Float) (n : Nat)
    (x : String) (h : x ∈ getCloseMatches word ps cutoff n) :
    x ∈ ps ∧ (seqRatio x word ≥ cutoff) = true := by
  unfold getCloseMatches at h
  obtain ⟨p, hp, rfl⟩ := List.mem_map.mp h
  have hp := List.mem_of_mem_take hp
  rw [List.mem_mergeSort] at hp
  obtain ⟨y, hy, hsome⟩ := List.mem_filterMap.mp hp
  by_cases hr : seqRatio y word ≥ cutoff
  · rw [ifP hr] at hsome
    cases hsome
    exact ⟨hy, by simpa using hr⟩
  · rw [ifN hr] at hsome; cases hsome

/-- Nothing to choose from: no suggestion. -/
theorem getCloseMatches_nil (word : String) (cutoff : Float) (n : Nat) :
    getCloseMatches word [] cutoff n = [] := by
  simp [getCloseMatches]

/-- Asking for zero matches gives none. -/
theorem getCloseMatches_zero (word : String) (ps : List String) (cutoff : Float) :
    getCloseMatches word ps cutoff 0 = [] := by
  simp [getCloseMatches]

/-- Only a string gets a "did you mean" suffix. -/
theorem suggestionSuffix_non_str (v : Value) (pool : List String) (h : ∀ s, v ≠ .str s) :
    suggestionSuffix v pool = "" := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- With an empty pool there is no suffix. -/
theorem suggestionSuffix_empty_pool (v : Value) : suggestionSuffix v [] = "" := by
  cases v <;> first | rfl | simp [suggestionSuffix, getCloseMatches_nil]

/-- The suffix is empty or `, did you mean <candidates>?` with candidates
from the pool (at most three). -/
theorem suggestionSuffix_cases (s : String) (pool : List String) :
    suggestionSuffix (.str s) pool = "" ∨
      ∃ cands, cands ≠ [] ∧ cands.length ≤ 3 ∧ (∀ c ∈ cands, c ∈ pool) ∧
        suggestionSuffix (.str s) pool = ", did you mean " ++ formatCandidates cands ++ "?" := by
  unfold suggestionSuffix
  by_cases h : (getCloseMatches s pool SUGGESTION_CUTOFF).isEmpty = true
  · left; simp only [h, ifP]
  · right
    refine ⟨getCloseMatches s pool SUGGESTION_CUTOFF, ?_, getCloseMatches_length _ _ _ _, ?_, ?_⟩
    · intro he; rw [he] at h; exact h rfl
    · intro c hc; exact (getCloseMatches_mem _ _ _ _ _ hc).1
    · simp only [h, ifN, Bool.false_eq_true, not_false_eq_true]

/-- An unknown key is reported at that key. -/
theorem extraKeyError_path (names : List String) (key : String) :
    (extraKeyError names key).path = [.key key] := rfl

/-- With no schema keys to suggest, the message is exactly
"not a valid option". -/
theorem extraKeyError_no_names (key : String) :
    (extraKeyError [] key).message = "not a valid option" := by
  simp [extraKeyError, suggestionSuffix_empty_pool]

/-- The key itself is never suggested: a schema whose only key is the
unknown key suggests nothing. -/
theorem extraKeyError_only_self (key : String) :
    (extraKeyError [key] key).message = "not a valid option" := by
  simp [extraKeyError, suggestionSuffix_empty_pool]

/-- The message always starts with "not a valid option". -/
theorem extraKeyError_message (names : List String) (key : String) :
    ∃ suffix, (extraKeyError names key).message = "not a valid option" ++ suffix := ⟨_, rfl⟩

/-! ## Text the model handles -/

/-- `safeChar`: ASCII, except VT, FF and the four separators FS, GS, RS, US. -/
theorem safeChar_iff (c : Char) :
    safeChar c = true ↔ c.toNat < 128 ∧ c.toNat ∉ [0x0b, 0x0c, 0x1c, 0x1d, 0x1e, 0x1f] := by
  simp only [safeChar, Bool.and_eq_true, decide_eq_true_eq, bne_iff_ne, Bool.not_eq_true',
    Bool.and_eq_false_iff, decide_eq_false_iff_not, List.mem_cons, List.not_mem_nil, or_false]
  omega

/-- A safe character is ASCII. -/
theorem safeChar_ascii (c : Char) (h : safeChar c = true) : c.toNat < 128 :=
  ((safeChar_iff c).mp h).1

/-- Space, tab, newline and carriage return (what Lean's `trim` and Python's
`strip` agree on) are safe. -/
theorem safeChar_ws : safeChar ' ' = true ∧ safeChar '\t' = true ∧ safeChar '\n' = true ∧
    safeChar '\r' = true := by decide

/-- The whitespace Python strips and Lean does not is excluded. -/
theorem safeChar_py_ws : safeChar (Char.ofNat 0x0b) = false ∧ safeChar (Char.ofNat 0x0c) = false ∧
    safeChar (Char.ofNat 0x1c) = false ∧ safeChar (Char.ofNat 0x1f) = false := by decide

theorem safeText_iff (s : String) : safeText s = true ↔ ∀ c ∈ s.toList, safeChar c = true := by
  simp [safeText]

theorem safeText_empty : safeText "" = true := rfl

/-- Concatenation is safe exactly when both halves are. -/
theorem safeText_append (a b : String) : safeText (a ++ b) = (safeText a && safeText b) := by
  simp [safeText, String.toList_append]

/-- `requireSafe` succeeds exactly on safe values. -/
theorem requireSafe_ok_iff (v : Value) : requireSafe v = .ok () ↔ safeValue v = true := by
  unfold requireSafe
  by_cases h : safeValue v = true
  · simp [h, pure, Except.pure]
  · simp [h, throw, throwThe, MonadExceptOf.throw]

/-- `requireSafe` fails only as "unsupported", never as a validation error. -/
theorem requireSafe_error (v : Value) (e : VErr) (h : requireSafe v = .error e) :
    ∃ why, e = .unsupported why := by
  unfold requireSafe at h
  split at h
  · cases h
  · cases h; exact ⟨_, rfl⟩

/-- `strOf` is `str(v)` on safe values, and nothing else. -/
theorem strOf_ok_iff (v : Value) (s : String) :
    strOf v = .ok s ↔ safeValue v = true ∧ pyStr v = .ok s := by
  unfold strOf requireSafe
  by_cases h : safeValue v = true
  · cases pyStr v <;>
      simp [h, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw]
  · simp [h, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- `strOf` never raises a validation error. -/
theorem strOf_error (v : Value) (e : VErr) (h : strOf v = .error e) : ∃ why, e = .unsupported why := by
  unfold strOf requireSafe at h
  by_cases hs : safeValue v = true
  · simp [hs, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
    cases hp : pyStr v with
    | ok s => rw [hp] at h; cases h
    | error m => rw [hp] at h; cases h; exact ⟨_, rfl⟩
  · simp [hs, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at h
    exact ⟨_, h.symm⟩

/-- `reprOf` is `repr(v)` wherever HALean can print it. -/
theorem reprOf_ok_iff (v : Value) (s : String) : reprOf v = .ok s ↔ pyRepr v = .ok s := by
  unfold reprOf
  cases pyRepr v <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw]

/-- `int(str)`: what `parseIntStr` reads, unless the text has more than 4300
digits (CPython's `sys.int_info.str_digits_check_threshold` limit). -/
theorem pyIntOfStr?_iff (s : String) (i : Int) :
    pyIntOfStr? s = some i ↔
      parseIntStr s = some i ∧ (s.toList.filter Char.isDigit).length ≤ 4300 := by
  unfold pyIntOfStr?
  cases hp : parseIntStr s with
  | none => simp
  | some j =>
    by_cases hd : (s.toList.filter Char.isDigit).length > 4300
    · simp [hd]
    · simp [hd]; omega

/-- A short text converts exactly as `parseIntStr` does. -/
theorem pyIntOfStr?_short (s : String) (h : s.length ≤ 4300) : pyIntOfStr? s = parseIntStr s := by
  have hl : (s.toList.filter Char.isDigit).length ≤ 4300 :=
    Nat.le_trans (List.length_filter_le _ _) (by rw [String.length_toList]; exact h)
  cases hp : parseIntStr s with
  | none => simp [pyIntOfStr?, hp]
  | some j => exact (pyIntOfStr?_iff s j).mpr ⟨hp, hl⟩

/-! ## Type names -/

/-- A type's name reads back as the type. -/
theorem PyType.ofString?_name (t : PyType) : PyType.ofString? t.name = some t := by
  cases t <;> rfl

/-- Distinct types have distinct names. -/
theorem PyType.name_injective (t u : PyType) (h : t.name = u.name) : t = u := by
  have := congrArg PyType.ofString? h
  rw [PyType.ofString?_name, PyType.ofString?_name] at this
  exact Option.some.inj this

/-- `any` is an alias of `object`. -/
theorem PyType.ofString?_any : PyType.ofString? "any" = some .object := rfl

/-- The only names read are the types' own names and `any`. -/
theorem PyType.ofString?_some (s : String) (t : PyType) (h : PyType.ofString? s = some t) :
    s = t.name ∨ (s = "any" ∧ t = .object) := by
  unfold PyType.ofString? at h
  split at h <;> first | (cases h; simp [PyType.name]) | cases h

theorem CoerceType.name_injective (t u : CoerceType) (h : t.name = u.name) : t = u := by
  cases t <;> cases u <;> first | rfl | exact absurd h (by decide)

/-- `Coerce(T)` and the type `T` print the same name in "expected T". -/
theorem CoerceType.name_eq_pyType :
    CoerceType.int.name = PyType.int.name ∧ CoerceType.float.name = PyType.float.name ∧
    CoerceType.str.name = PyType.str.name := ⟨rfl, rfl, rfl⟩

/-! ## Branch labels (`_branch_label`, `_expected_label`) -/

/-- A type branch is labelled with its name. -/
theorem label?_type (t : PyType) : (Validator.type t).label? = some t.name := rfl

/-- The literal `None` is labelled `None`. -/
theorem label?_literal_none : (Validator.literal .none).label? = some "None" := rfl

/-- A string literal is labelled with its repr. -/
theorem label?_literal_str (s : String) : (Validator.literal (.str s)).label? = some (strRepr s) := by
  simp [Validator.label?, pyRepr, Except.toOption, pure, Except.pure]

/-- An int literal is labelled with its decimal text. -/
theorem label?_literal_int (i : Int) : (Validator.literal (.int i)).label? = some (toString i) := by
  simp [Validator.label?, pyRepr, Except.toOption, pure, Except.pure]

/-- `True` / `False` literals. -/
theorem label?_literal_bool (b : Bool) :
    (Validator.literal (.bool b)).label? = some (if b then "True" else "False") := by
  simp [Validator.label?, pyRepr, Except.toOption, pure, Except.pure, boolStr]

/-- Validator branches (combinators, mappings, sequences, `cv.*`) have no
label, so `Any` reports the deepest branch error instead of "expected ...". -/
theorem label?_validators (vs : List Validator) (fs : List Field) (ex : Extra) (f : CvFn)
    (c : List Value) (t : CoerceType) :
    (Validator.all vs).label? = none ∧ (Validator.any vs).label? = none ∧
    (Validator.dict fs).label? = none ∧ (Validator.schema fs ex).label? = none ∧
    (Validator.seq vs).label? = none ∧ (Validator.cv f).label? = none ∧
    (Validator.isIn c).label? = none ∧ (Validator.notIn c).label? = none ∧
    (Validator.coerce t).label? = none ∧ Validator.lower.label? = none ∧
    Validator.upper.label? = none ∧ Validator.ensureList.label? = none ∧
    Validator.port.label? = none := ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- `Any()` with no branches has no "expected" label. -/
theorem expectedLabel_nil : expectedLabel [] = none := rfl

/-- One unlabelled branch is enough to drop the "expected ..." message. -/
theorem expectedLabel_unlabelled (vs : List Validator) (v : Validator) (hv : v ∈ vs)
    (hl : v.label? = none) : expectedLabel vs = none := by
  have hm : vs.mapM Validator.label? = none := by
    induction vs with
    | nil => cases hv
    | cons x xs ih =>
      rw [List.mapM_cons]
      rcases List.mem_cons.mp hv with rfl | hx
      · simp [hl]
      · cases hx' : x.label? <;> simp [ih hx]
  simp [expectedLabel, hm]

/-- When every branch has a label, the labels are joined with ` or `. -/
theorem expectedLabel_labelled (vs : List Validator) (labels : List String)
    (hm : vs.mapM Validator.label? = some labels) (hne : vs ≠ []) :
    expectedLabel vs = some (" or ".intercalate labels) := by
  have hl : labels ≠ [] := by
    cases vs with
    | nil => exact absurd rfl hne
    | cons x xs =>
      rw [List.mapM_cons] at hm
      cases hx : x.label? with
      | none => simp [hx] at hm
      | some l =>
        cases hxs : xs.mapM Validator.label? with
        | none => simp [hx, hxs] at hm
        | some ls => simp [hx, hxs] at hm; subst hm; simp
  cases labels with
  | nil => exact absurd rfl hl
  | cons l ls => simp [expectedLabel, hm]

/-- `Any(int, None)` fails with "expected int or None" (probatio's documented
message shape). -/
theorem expectedLabel_int_or_none :
    expectedLabel [.type .int, .literal .none] = some "int or None" := by
  rw [expectedLabel_labelled _ ["int", "None"] rfl (by simp)]; rfl

/-! ## `_TypeCheck` / `_FloatCheck` -/

/-- `isinstance(v, t)` for the types a schema can name, written
independently: a `bool` is an `int`, everything is an `object`. -/
def IsInstance : PyType → Value → Prop
  | .object, _ => True
  | .int, .int _ | .int, .bool _ => True
  | .str, .str _ => True
  | .bool, .bool _ => True
  | .list, .list _ => True
  | .dict, .dict _ => True
  | .timedelta, .timedelta _ => True
  | .float, .float _ => True
  | _, _ => False

/-- A type other than `float` accepts exactly its instances, unchanged. -/
theorem checkType_ok_iff (t : PyType) (v w : Value) (ht : t ≠ .float) :
    checkType t v = .ok w ↔ w = v ∧ IsInstance t v := by
  cases t <;> first | exact absurd rfl ht | skip
  all_goals
    cases v <;>
      simp [checkType, IsInstance, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- `object` accepts everything. -/
theorem checkType_object (v : Value) : checkType .object v = .ok v := by
  cases v <;> rfl

/-- `float` keeps a float as it is. -/
theorem checkType_float_float (f : Float) : checkType .float (.float f) = .ok (.float f) := rfl

/-- `float` does not take a `bool` (the numeric tower excludes it), a string
or `None`. -/
theorem checkType_float_rejects (v : Value)
    (h : (∃ b, v = .bool b) ∨ (∃ s, v = .str s) ∨ v = .none) :
    checkType .float v = .error (inv "expected float") := by
  rcases h with ⟨b, rfl⟩ | ⟨s, rfl⟩ | rfl <;> rfl

/-- What `float` accepts is a float or an int, and the result is always a
float (an int is converted). -/
theorem checkType_float_ok (v w : Value) (h : checkType .float v = .ok w) :
    (∃ f, v = .float f ∧ w = .float f) ∨ (∃ i, v = .int i ∧ w = .float (intToFloat i)) := by
  cases v <;> simp [checkType, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
  · rename_i i
    by_cases hi : (intToFloat i).isInf = true
    · simp [hi] at h
    · simp [hi] at h; exact Or.inr ⟨i, rfl, h.symm⟩
  · exact Or.inl ⟨_, rfl, h.symm⟩

/-- The only failure of a type check is "expected <type>". -/
theorem checkType_error (t : PyType) (v : Value) (e : VErr) (h : checkType t v = .error e) :
    e = inv ("expected " ++ t.name) := by
  have key : (throw (inv s!"expected {t.name}") : VResult) = .error (inv ("expected " ++ t.name)) := by
    simp [throw, throwThe, MonadExceptOf.throw, toString]
  cases t <;> cases v <;>
    simp [checkType, pure, Except.pure] at h <;>
    first
    | (rw [key] at h; cases h; rfl)
    | (split at h <;> first | (rw [key] at h; cases h; rfl) | (cases h; rfl) | cases h)

/-! ## Literals -/

/-- A literal accepts exactly the values equal (Python `==`) to it. -/
theorem checkLiteral_ok_iff (lit v w : Value) :
    checkLiteral lit v = .ok w ↔ (pyEq v lit = true ∧ w = v) := by
  unfold checkLiteral
  by_cases h : pyEq v lit = true
  · simp only [h, ite_true, true_and, pure, Except.pure, Except.ok.injEq]; exact eq_comm
  · simp [h, throw, throwThe, MonadExceptOf.throw]

/-- A literal mismatch is "not a valid value". -/
theorem checkLiteral_error (lit v : Value) (e : VErr) (h : checkLiteral lit v = .error e) :
    e = inv "not a valid value" := by
  unfold checkLiteral at h
  split at h
  · cases h
  · cases h; rfl

/-! ## Messages -/

/-- `sorted(container)` (or the container itself) has the same members. -/
theorem sortedForMessage_perm (c : List Value) : (sortedForMessage c).Perm c := by
  unfold sortedForMessage
  split
  · exact List.Perm.refl _
  · split
    · exact List.mergeSort_perm _ _
    · split
      · exact List.mergeSort_perm _ _
      · exact List.Perm.refl _

theorem sortedForMessage_length (c : List Value) : (sortedForMessage c).length = c.length :=
  (sortedForMessage_perm c).length_eq

/-- A container mixing strings and numbers cannot be sorted and is shown as
written. -/
theorem sortedForMessage_mixed (c : List Value) (s : String) (i : Int)
    (hs : Value.str s ∈ c) (hi : Value.int i ∈ c) : sortedForMessage c = c := by
  unfold sortedForMessage
  split
  · rfl
  · rw [ifN, ifN]
    · intro h
      have := List.all_eq_true.mp h _ hs
      simp [Value.num?] at this
    · intro h
      have := List.all_eq_true.mp h _ hi
      simp at this

/-- The empty list displays as `[]`. -/
theorem displayList_nil : displayList [] = .ok "[]" := rfl

/-- Up to 40 members are all shown, as `[r1, r2, ...]`. -/
theorem displayList_ok_short (vs : List Value) (rs : List String)
    (h : vs.mapM reprOf = .ok rs) (hl : rs.length ≤ 40) :
    displayList vs = .ok ("[" ++ ", ".intercalate rs ++ "]") := by
  have hn : ¬ rs.length > 40 := by omega
  simp [displayList, h, bind, Except.bind, hn, pure, Except.pure]

/-- Beyond 40 members the list is cut, with the count of the rest. -/
theorem displayList_ok_long (vs : List Value) (rs : List String)
    (h : vs.mapM reprOf = .ok rs) (hl : 40 < rs.length) :
    displayList vs = .ok ("[" ++ ", ".intercalate (rs.take 40) ++
      (", ...] (" ++ toString (rs.length - 40) ++ " more not shown)")) := by
  simp [displayList, h, bind, Except.bind, hl, pure, Except.pure, toString]

/-- A member HALean cannot print makes the message unsupported. -/
theorem displayList_error (vs : List Value) (e : VErr) (h : vs.mapM reprOf = .error e) :
    displayList vs = .error e := by
  simp [displayList, h, bind, Except.bind]

/-! ## Numbers and bounds -/

/-- On ints `>=` is the integer order. -/
theorem numGe_int (a b : Int) : numGe (.i a) (.i b) = true ↔ b ≤ a := by
  simp [numGe, numLt, numEq]; omega

/-- On ints, `>=` is the negation of `<`. -/
theorem numGe_int_not_lt (a b : Int) : numGe (.i a) (.i b) = !numLt (.i a) (.i b) := by
  by_cases h : a < b <;> simp [numGe, numLt, numEq, h] <;> omega

/-- An int bound prints in decimal. -/
theorem boundStr_int (i : Int) : boundStr (.int i) = .ok (toString i) := by
  simp [boundStr, pyStr, pyRepr, pure, Except.pure]

/-- Below an inclusive int minimum: "value must be at least <min>", whatever
the maximum (the minimum is checked first). -/
theorem rangeError_below_min (a x : Int) (mx : Option Value) (maxIncl : Bool) (h : x < a) :
    rangeError (some (.int a)) mx true maxIncl (.i x) = inv ("value must be at least " ++ toString a) := by
  have hf : minOk true (.i x) (.i a) = false := by
    simp [minOk, numGe, numLt, numEq]; omega
  simp [rangeError, Value.num?, hf, boundStr_int, invWith,
    bind, Except.bind, pure, Except.pure, toString]

/-- With no minimum, the error of an inclusive int maximum is "value must be
at most <max>". -/
theorem rangeError_no_min (b : Int) (x : Num) (minIncl : Bool) :
    rangeError none (some (.int b)) minIncl true x = inv ("value must be at most " ++ toString b) := by
  simp [rangeError, rangeError.maxError, Value.num?, boundStr_int, invWith,
    bind, Except.bind, pure, Except.pure, toString]

/-! ## `Clamp` -/

/-- `Clamp()` without bounds accepts anything. -/
theorem checkClamp_none (v : Value) : checkClamp none none v = .ok v := rfl

/-- With a bound, a value that is not a number fails. -/
theorem checkClamp_not_number (mn mx : Option Value) (v : Value)
    (hb : mn.isSome ∨ mx.isSome) (hv : v.num? = none) :
    checkClamp mn mx v = .error (inv "invalid value or type") := by
  have hnone : (mn.isNone && mx.isNone) = false := by
    cases mn <;> cases mx <;> simp_all
  simp [checkClamp, hnone, hv, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- `Clamp(min=a, max=b)` on ints is `max(a, min(x, b))`. -/
theorem checkClamp_int (a b x : Int) (hab : a ≤ b) :
    checkClamp (some (.int a)) (some (.int b)) (.int x) = .ok (.int (max a (min x b))) := by
  by_cases h1 : x < a
  · have : max a (min x b) = a := by omega
    simp [checkClamp, Value.num?, numLt, h1, this, bind, Except.bind, pure, Except.pure]
  · by_cases h2 : b < x
    · have : max a (min x b) = b := by omega
      simp [checkClamp, Value.num?, numLt, h1, h2, this, bind, Except.bind, pure, Except.pure]
    · have : max a (min x b) = x := by omega
      simp [checkClamp, Value.num?, numLt, h1, h2, this, bind, Except.bind, pure, Except.pure]

/-- Clamping an int into `[a, b]` lands in `[a, b]`. -/
theorem checkClamp_int_bounds (a b x : Int) (hab : a ≤ b) :
    ∃ y, checkClamp (some (.int a)) (some (.int b)) (.int x) = .ok (.int y) ∧ a ≤ y ∧ y ≤ b :=
  ⟨_, checkClamp_int a b x hab, by omega, by omega⟩

/-- An int already inside the bounds is returned unchanged. -/
theorem checkClamp_int_inside (a b x : Int) (h1 : a ≤ x) (h2 : x ≤ b) :
    checkClamp (some (.int a)) (some (.int b)) (.int x) = .ok (.int x) := by
  rw [checkClamp_int a b x (by omega)]
  have : max a (min x b) = x := by omega
  rw [this]

/-! ## `Length` -/

/-- `len()` exists for strings, lists and dicts only. -/
theorem pyLen?_isSome_iff (v : Value) :
    (pyLen? v).isSome = true ↔ (∃ s, v = .str s) ∨ (∃ xs, v = .list xs) ∨ ∃ kvs, v = .dict kvs := by
  cases v <;> simp [pyLen?]

theorem pyLen?_list (xs : List Value) : pyLen? (.list xs) = some xs.length := rfl

/-- `Length(min, max)` accepts exactly the sized values whose length is
within the bounds given, unchanged (and everything when no bound is given). -/
theorem checkLength_ok_iff (mn mx : Option Int) (v w : Value) :
    checkLength mn mx v = .ok w ↔
      w = v ∧ ((mn = none ∧ mx = none) ∨
        ∃ n, pyLen? v = some n ∧ (∀ m, mn = some m → m ≤ (n : Int)) ∧
          (∀ m, mx = some m → (n : Int) ≤ m)) := by
  unfold checkLength
  cases mn with
  | none =>
    cases mx with
    | none => simp [pure, Except.pure, eq_comm] <;> first | omega | (intros; omega)
    | some b =>
      cases hl : pyLen? v with
      | none => simp [bind, Except.bind, throw, throwThe, MonadExceptOf.throw] <;> first | omega | (intros; omega)
      | some n =>
        by_cases hb : (n : Int) > b
        · simp [hb, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] <;> first | omega | (intros; omega)
        · simp [hb, bind, Except.bind, pure, Except.pure, eq_comm] <;> first | omega | (intros; omega)
  | some a =>
    cases hl : pyLen? v with
    | none => simp [bind, Except.bind, throw, throwThe, MonadExceptOf.throw] <;> first | omega | (intros; omega)
    | some n =>
      by_cases ha : (n : Int) < a
      · simp [ha, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] <;> first | omega | (intros; omega)
      · cases mx with
        | none => simp [ha, bind, Except.bind, pure, Except.pure, eq_comm] <;> first | omega | (intros; omega)
        | some b =>
          by_cases hb : (n : Int) > b
          · simp [ha, hb, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] <;> first | omega | (intros; omega)
          · simp [ha, hb, bind, Except.bind, pure, Except.pure, eq_comm] <;> first | omega | (intros; omega)

/-- A number has no length. -/
theorem checkLength_int (mn mx : Option Int) (i : Int) (hb : mn.isSome ∨ mx.isSome) :
    checkLength mn mx (.int i) = .error (inv "value has no length") := by
  have hnone : (mn.isNone && mx.isNone) = false := by
    cases mn <;> cases mx <;> simp_all
  simp [checkLength, hnone, pyLen?, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-! ## `int()` / `float()` / `Coerce` -/

theorem pyInt?_int (i : Int) : pyInt? (.int i) = .ok (some i) := rfl

/-- `int(True) == 1`, `int(False) == 0`. -/
theorem pyInt?_bool (b : Bool) : pyInt? (.bool b) = .ok (some (if b then 1 else 0)) := rfl

/-- `int(None)`, `int([..])`, `int({..})` raise `TypeError`. -/
theorem pyInt?_none_list_dict (xs : List Value) (kvs : List (Value × Value)) :
    pyInt? .none = .ok none ∧ pyInt? (.list xs) = .ok none ∧ pyInt? (.dict kvs) = .ok none :=
  ⟨rfl, rfl, rfl⟩

/-- `int(str)` goes through `pyIntOfStr?` on safe text. -/
theorem pyInt?_str (s : String) (h : safeValue (.str s) = true) :
    pyInt? (.str s) = .ok (pyIntOfStr? s) := by
  simp [pyInt?, requireSafe, h, bind, Except.bind, pure, Except.pure]

theorem pyFloat?_float (f : Float) : Core.pyFloat? (.float f) = .ok (some f) := rfl

/-- `float(None)` raises. -/
theorem pyFloat?_none : Core.pyFloat? .none = .ok none := rfl

/-- `Coerce(int)` leaves an int alone. -/
theorem checkCoerce_int_int (i : Int) : checkCoerce .int (.int i) = .ok (.int i) := rfl

/-- `Coerce(int)(True)` is `1`. -/
theorem checkCoerce_int_bool (b : Bool) :
    checkCoerce .int (.bool b) = .ok (.int (if b then 1 else 0)) := rfl

/-- `Coerce(int)(None)` fails with "expected int". -/
theorem checkCoerce_int_none : checkCoerce .int .none = .error (inv "expected int") := rfl

/-- `Coerce(float)` always yields a float. -/
theorem checkCoerce_float (v w : Value) (h : checkCoerce .float v = .ok w) : ∃ f, w = .float f := by
  unfold checkCoerce at h
  simp only [bind, Except.bind] at h
  cases hf : Core.pyFloat? v with
  | error e => rw [hf] at h; cases h
  | ok o =>
    rw [hf] at h
    cases o with
    | none => simp [throw, throwThe, MonadExceptOf.throw] at h
    | some f => simp [pure, Except.pure] at h; exact ⟨f, h.symm⟩

/-- `Coerce(float)` leaves a float alone. -/
theorem checkCoerce_float_float (f : Float) : checkCoerce .float (.float f) = .ok (.float f) := rfl

/-- `Coerce(str)` is `str(v)`. -/
theorem checkCoerce_str_iff (v w : Value) :
    checkCoerce .str v = .ok w ↔ ∃ s, pyStr v = .ok s ∧ w = .str s := by
  unfold checkCoerce
  cases pyStr v <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- `Coerce(str)` leaves a string alone. -/
theorem checkCoerce_str_str (s : String) : checkCoerce .str (.str s) = .ok (.str s) := by
  simp [checkCoerce, pyStr, pure, Except.pure]

/-- `Coerce(int)` and `Coerce(float)` fail only with "expected <type>" or as
unsupported text; they never let another exception escape. -/
theorem checkCoerce_int_error (v : Value) (e : VErr) (h : checkCoerce .int v = .error e) :
    e = inv "expected int" ∨ ∃ why, e = .unsupported why := by
  unfold checkCoerce at h
  simp only [bind, Except.bind] at h
  cases hf : pyInt? v with
  | error e' =>
    rw [hf] at h; cases h
    cases v <;> simp [pyInt?, pure, Except.pure, bind, Except.bind] at hf
    rename_i s
    cases hr : requireSafe (.str s) with
    | ok u => rw [hr] at hf; cases hf
    | error e'' => rw [hr] at hf; cases hf; exact Or.inr (requireSafe_error _ _ hr)
  | ok o =>
    rw [hf] at h
    cases o with
    | none => simp [throw, throwThe, MonadExceptOf.throw] at h; exact Or.inl h.symm
    | some i => cases h

/-! ## `Lower` / `Upper` / `EnsureList` -/

/-- `Lower` is `str(v).lower()` (ASCII model), always a string. -/
theorem checkLower_ok_iff (v w : Value) :
    checkLower v = .ok w ↔ ∃ s, strOf v = .ok s ∧ w = .str (s.map Char.toLower) := by
  unfold checkLower
  cases strOf v <;> simp [bind, Except.bind, pure, Except.pure, eq_comm]

/-- `Upper` is `str(v).upper()`. -/
theorem checkUpper_ok_iff (v w : Value) :
    checkUpper v = .ok w ↔ ∃ s, strOf v = .ok s ∧ w = .str (s.map Char.toUpper) := by
  unfold checkUpper
  cases strOf v <;> simp [bind, Except.bind, pure, Except.pure, eq_comm]

/-- `Lower` and `Upper` accept the same values. -/
theorem checkLower_ok_iff_checkUpper_ok (v : Value) :
    (∃ w, checkLower v = .ok w) ↔ ∃ w, checkUpper v = .ok w := by
  constructor
  · rintro ⟨w, h⟩
    obtain ⟨s, hs, _⟩ := (checkLower_ok_iff v w).mp h
    exact ⟨_, (checkUpper_ok_iff v _).mpr ⟨s, hs, rfl⟩⟩
  · rintro ⟨w, h⟩
    obtain ⟨s, hs, _⟩ := (checkUpper_ok_iff v w).mp h
    exact ⟨_, (checkLower_ok_iff v _).mpr ⟨s, hs, rfl⟩⟩

/-- `EnsureList` is idempotent. -/
theorem ensureList_idem (v : Value) : ensureList (ensureList v) = ensureList v := by
  cases v <;> rfl

/-- `EnsureList()(None)` is `[]`. -/
theorem ensureList_none : ensureList .none = .list [] := rfl

/-- A scalar is wrapped in a one-element list. -/
theorem ensureList_scalar (v : Value) (h1 : v ≠ .none) (h2 : ∀ xs, v ≠ .list xs) :
    ensureList v = .list [v] := by
  cases v <;> first | rfl | exact absurd rfl h1 | exact absurd rfl (h2 _)

/-! ## `AtLeastOne` -/

/-- `AtLeastOne(*keys)` accepts exactly the mappings holding one of the
keys, unchanged. -/
theorem checkAtLeastOne_ok_iff (keys : List String) (v w : Value) :
    checkAtLeastOne keys v = .ok w ↔
      w = v ∧ ∃ kvs, v = .dict kvs ∧
        (keys.any fun k => kvs.any fun p => pyEq p.1 (.str k)) = true := by
  cases v <;> try (simp [checkAtLeastOne, throw, throwThe, MonadExceptOf.throw]; done)
  rename_i kvs
  by_cases h : (keys.any fun k => kvs.any fun p => pyEq p.1 (.str k)) = true
  · have h' := h
    simp at h'
    simp [checkAtLeastOne, h, pure, Except.pure]
    exact ⟨fun e => ⟨e.symm, h'⟩, fun e => e.1.symm⟩
  · have h' := h
    simp at h'
    simp [checkAtLeastOne, h, throw, throwThe, MonadExceptOf.throw]
    intro _; exact h'

/-- Anything but a mapping: "expected a mapping". -/
theorem checkAtLeastOne_non_dict (keys : List String) (v : Value) (h : ∀ kvs, v ≠ .dict kvs) :
    checkAtLeastOne keys v = .error (inv "expected a mapping") := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-- With no keys to look for, every mapping fails. -/
theorem checkAtLeastOne_no_keys (v w : Value) : checkAtLeastOne [] v ≠ .ok w := by
  intro h
  obtain ⟨_, kvs, _, hk⟩ := (checkAtLeastOne_ok_iff [] v w).mp h
  simp at hk

/-! ## `Port` -/

/-- `Port()` on an int: exactly 1..65535, unchanged. -/
theorem checkPort_int_iff (i : Int) (w : Value) :
    checkPort (.int i) = .ok w ↔ (1 ≤ i ∧ i ≤ 65535 ∧ w = .int i) := by
  by_cases h : 1 ≤ i ∧ i ≤ 65535
  · simp [checkPort, pyInt?, h, bind, Except.bind, pure, Except.pure, eq_comm]
  · have : ¬ (1 ≤ i ∧ i ≤ 65535) := h
    simp [checkPort, pyInt?, bind, Except.bind, pure, Except.pure, throw, throwThe,
      MonadExceptOf.throw]
    rw [ifN h]
    constructor
    · intro h'; cases h'
    · rintro ⟨h1, h2, _⟩; exact absurd ⟨h1, h2⟩ this

/-- `True` is not a port, although `int(True) == 1`. -/
theorem checkPort_bool (b : Bool) :
    checkPort (.bool b) = .error (inv "expected a port number between 1 and 65535") := rfl

/-- `None` is not a port. -/
theorem checkPort_none :
    checkPort .none = .error (inv "expected a port number between 1 and 65535") := rfl

/-- 0 and 65536 are out of range. -/
theorem checkPort_edges (w : Value) :
    checkPort (.int 0) ≠ .ok w ∧ checkPort (.int 65536) ≠ .ok w ∧
    checkPort (.int 1) = .ok (.int 1) ∧ checkPort (.int 65535) = .ok (.int 65535) := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro h; have := (checkPort_int_iff 0 w).mp h; omega
  · intro h; have := (checkPort_int_iff 65536 w).mp h; omega
  · exact (checkPort_int_iff 1 _).mpr ⟨by omega, by omega, rfl⟩
  · exact (checkPort_int_iff 65535 _).mpr ⟨by omega, by omega, rfl⟩

end HALean.Core.ProbatioSpec
