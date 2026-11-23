/-
  The subset of `probatio` (the voluptuous-compatible validation library Home
  Assistant validates service data with since 2026) that the service registry
  model supports. It is pinned in `manifest.yaml` as `upstream.probatio`
  (0.13.0); it is a dependency, not HA code, like Jinja2.

  A service schema is a `probatio.Schema` around a mapping of literal string
  keys (`Required`, `Optional`, `Exclusive`, `Inclusive`, with defaults) and an
  extra-key policy. Values are validated by `Validator`s: the types `int`,
  `float`, `str`, `bool`, `object`, `list`, `dict`, `timedelta`; scalar
  literals; nested mappings (which inherit the schema's extra-key policy, as
  probatio compiles them); sequence schemas `[v, ...]`; and the validators
  `All`, `Any`, `In`, `NotIn`, `Range`, `Clamp`, `Length`,
  `Coerce(int|float|str)`, `Lower`, `Upper`, `EnsureList`, `Port`,
  `AtLeastOne`. The `cv.*` validators of
  `helpers/config_validation.py` are in `HALean.Core.ConfigValidation`; the
  evaluator that runs a whole schema is `HALean.Core.Schema`.

  Translated from probatio 0.13.0:
    * `_engine.py`: `_MappingValidator.__call__` / `_finalize` /
      `_check_groups` / `_empty_exclusive_group` / `_extra_key_error`,
      `_SequenceValidator.__call__` / `_validate_item`
    * `_compile.py`: `_TypeCheck`, `_FloatCheck`, `_compile_literal`,
      `_compile_callable` (a `ValueError` becomes `Invalid`)
    * `validators/combinators.py`: `All.__call__`, `Any.__call__`, `_run_any`,
      `_branch_label`, `_expected_label`
    * `validators/comparison.py`: `Range`, `Clamp`, `Length`, `In`, `NotIn`,
      `_sorted_for_message`; `validators/coerce.py`: `Coerce`;
      `validators/strings.py`: `Lower`, `Upper`;
      `validators/structural.py`: `EnsureList`; `validators/network.py`: `Port`;
      `validators/conditional.py`: `AtLeastOne`
    * `error.py`: `render_path`, `_format_candidates`, `_SuggestionInvalid`,
      `MultipleInvalid.__str__`; `_messages.py`: the catalog and `_display`

  Errors are `probatio.Invalid`s with a message and a path. A
  `MultipleInvalid` is flattened into its leaves, which is how every engine
  collects them, so a failed validation is a non-empty list of leaves, and
  `str(MultipleInvalid)` is the first. Any other exception (a `TypeError` out
  of a callable validator) escapes the schema (`VErr.raise`). Input HALean
  cannot validate the way Python would (text whose `str.lower()`, `strip()`
  or `int()` would differ from the ASCII model) is `VErr.unsupported`.
-/
import HALean.Core.PyJson

namespace HALean.Core
open HALean.Template

/-! ## Errors -/

/-- One segment of `Invalid.path`. -/
inductive PathSeg where
  /-- a mapping key (always a `str` here) -/
  | key (k : String)
  /-- a list index -/
  | idx (i : Nat)
  /-- `VirtualPathComponent(group)`: an `Exclusive`/`Inclusive` group -/
  | group (g : String)
  deriving BEq, Repr, Inhabited

/-- One `probatio.Invalid` leaf: its message (`error_message`, with any
"did you mean" suffix) and path. -/
structure SchemaError where
  message : String
  path : List PathSeg := []
  deriving BEq, Repr, Inhabited

/-- How a validation fails. -/
inductive VErr where
  /-- `probatio.Invalid`: the leaves of the `MultipleInvalid` (non-empty) -/
  | invalid (errs : List SchemaError)
  /-- another exception escapes (`TypeError`, `OverflowError`, ...) -/
  | raise (exception message : String)
  /-- input HALean does not model -/
  | unsupported (why : String)
  deriving Repr, Inhabited

abbrev VResult := Except VErr Value

/-- A single `Invalid` leaf. -/
def inv (msg : String) (path : List PathSeg := []) : VErr :=
  .invalid [{ message := msg, path }]

/-- `Invalid.prepend`, on every leaf. -/
def prependAll (seg : PathSeg) (errs : List SchemaError) : List SchemaError :=
  errs.map fun e => { e with path := seg :: e.path }

/-! ## difflib -/

/-- `SequenceMatcher(None, a, b).find_longest_match(alo, ahi, blo, bhi)` with
no junk function. `popular` are the elements `autojunk` drops from `b2j`
(only when `len(b) >= 200`). -/
def findLongestMatch (a b : Array Char) (popular : Char → Bool)
    (alo ahi blo bhi : Nat) : Nat × Nat × Nat := Id.run do
  let mut besti := alo
  let mut bestj := blo
  let mut bestsize := 0
  -- j2len[j] = length of the match ending at a[i-1], b[j]
  let mut j2len : Array Nat := Array.replicate (b.size + 1) 0
  for i in [alo:ahi] do
    let mut newj2len : Array Nat := Array.replicate (b.size + 1) 0
    let ai := a[i]!
    if !popular ai then
      for j in [blo:bhi] do
        if b[j]! == ai then
          let k := (if j > 0 then j2len[j - 1]! else 0) + 1
          newj2len := newj2len.set! j k
          if k > bestsize then
            besti := i + 1 - k
            bestj := j + 1 - k
            bestsize := k
    j2len := newj2len
  -- extend over "popular" (non-junk) equal elements, as difflib does
  while besti > alo && bestj > blo && a[besti - 1]! == b[bestj - 1]! do
    besti := besti - 1
    bestj := bestj - 1
    bestsize := bestsize + 1
  while besti + bestsize < ahi && bestj + bestsize < bhi &&
      a[besti + bestsize]! == b[bestj + bestsize]! do
    bestsize := bestsize + 1
  return (besti, bestj, bestsize)

/-- Total size of `get_matching_blocks()`. -/
def matchingSize (a b : Array Char) (popular : Char → Bool) :
    Nat → Nat → Nat → Nat → Nat → Nat
  | 0, _, _, _, _ => 0
  | fuel + 1, alo, ahi, blo, bhi =>
    let (i, j, k) := findLongestMatch a b popular alo ahi blo bhi
    if k == 0 then 0 else
    k + (if alo < i && blo < j then matchingSize a b popular fuel alo i blo j else 0)
      + (if i + k < ahi && j + k < bhi then matchingSize a b popular fuel (i + k) ahi (j + k) bhi else 0)

/-- `SequenceMatcher(None, a, b).ratio()`. -/
def seqRatio (a b : String) : Float :=
  let ac := a.toList.toArray
  let bc := b.toList.toArray
  let n := bc.size
  let ntest := n / 100 + 1
  let popular : Char → Bool := fun c => n ≥ 200 && (bc.filter (· == c)).size > ntest
  let m := matchingSize ac bc popular (ac.size + bc.size + 1) 0 ac.size 0 bc.size
  let len := ac.size + bc.size
  if len == 0 then 1.0 else 2.0 * m.toFloat / len.toFloat

/-- Python's `str` ordering (code points). -/
def pyStrLt (a b : String) : Bool := decide (a < b)

/-- `difflib.get_close_matches(word, possibilities, n=3, cutoff)`.
`real_quick_ratio` and `quick_ratio` are upper bounds of `ratio`, so the
three-stage filter is the same as `ratio() >= cutoff`. `heapq.nlargest`
orders by `(score, x)` descending. -/
def getCloseMatches (word : String) (possibilities : List String) (cutoff : Float)
    (n : Nat := 3) : List String :=
  let scored := possibilities.filterMap fun x =>
    let r := seqRatio x word
    if r >= cutoff then some (r, x) else none
  let gt (p q : Float × String) : Bool := p.1 > q.1 || (p.1 == q.1 && pyStrLt q.2 p.2)
  ((scored.mergeSort fun p q => gt p q || !(gt q p)).take n).map (·.2)

/-! ## Errors as probatio prints them -/

/-- `probatio.error._BARE_KEY`: `[A-Za-z_][A-Za-z0-9_-]*`. -/
def isBareKey (s : String) : Bool :=
  match s.toList with
  | [] => false
  | c :: cs => (c.isAlpha || c == '_') && cs.all fun c => c.isAlphanum || c == '_' || c == '-'

/-- `probatio.error._render_segment`: the repr, cut at 500 characters. -/
def renderSegment (r : String) : String :=
  if r.length > 500 then (r.take 497).toString ++ "..." else r

/-- `probatio.error.render_path`: string keys (and `<group>` components) that
are identifier-like join with dots, list indices render as `[n]`, anything else
as its bracketed `repr`. -/
def renderPath (path : List PathSeg) : String := Id.run do
  let mut out := ""
  for seg in path do
    match seg with
    | .idx i => out := out ++ s!"[{i}]"
    | .key s | .group s =>
      -- `str(segment)`: a `VirtualPathComponent` renders as `<group>`
      let text := match seg with | .group g => "<" ++ g ++ ">" | _ => s
      let bare := text.length ≤ 500 &&
        (isBareKey text || (text.startsWith "<" && text.endsWith ">" &&
          isBareKey ((text.drop 1).toString.dropEnd 1).toString))
      if bare then
        out := if out.isEmpty then text else out ++ "." ++ text
      else
        -- `repr(VirtualPathComponent)` is its `str`
        let r := match seg with | .group _ => text | _ => strRepr s
        out := out ++ "[" ++ renderSegment r ++ "]"
  return out

/-- `str(Invalid)`: the message, then ` at '<path>'`. -/
def SchemaError.str (e : SchemaError) : String :=
  if e.path.isEmpty then e.message else e.message ++ " at '" ++ renderPath e.path ++ "'"

/-- `probatio.error._format_candidates` -/
def formatCandidates (names : List String) : String :=
  let quoted := names.map strRepr
  match quoted.reverse with
  | [] => ""
  | [one] => one
  | last :: rest => ", ".intercalate rest.reverse ++ " or " ++ last

/-- `probatio.error._SUGGESTION_CUTOFF` -/
def SUGGESTION_CUTOFF : Float := 0.7

/-- `_SuggestionInvalid._suffix_text`: `", did you mean ...?"` when
`get_close_matches(value, pool)` finds anything (only for a `str` value). -/
def suggestionSuffix (value : Value) (pool : List String) : String :=
  match value with
  | .str s =>
    let cands := getCloseMatches s pool SUGGESTION_CUTOFF
    if cands.isEmpty then "" else ", did you mean " ++ formatCandidates cands ++ "?"
  | _ => ""

/-- `_MappingValidator._extra_key_error`: "not a valid option", with
", did you mean ...?" when difflib finds close schema keys (the key itself
excluded). -/
def extraKeyError (keyNames : List String) (key : String) : SchemaError :=
  { message := "not a valid option" ++ suggestionSuffix (.str key) (keyNames.filter (· != key)),
    path := [.key key] }

/-- `str(MultipleInvalid(errors))`: the first error. -/
def multipleInvalidStr : List SchemaError → String
  | [] => "no validation errors"
  | e :: _ => e.str

/-! ## Text HALean models -/

/-- Characters whose Python string handling HALean models exactly: ASCII,
without the vertical tab, form feed and the `\x1c`-`\x1f` separators, which
Python's `strip()`/`int()` treat as whitespace and Lean's `trim` does not.
(`str.lower()` and `int()` are Unicode-aware upstream.) -/
def safeChar (c : Char) : Bool :=
  c.toNat < 128 && c.toNat != 0x0b && c.toNat != 0x0c && !(0x1c ≤ c.toNat && c.toNat ≤ 0x1f)

def safeText (s : String) : Bool := s.toList.all safeChar

/-- Every string in the value (keys included) is `safeText`. -/
partial def safeValue : Value → Bool
  | .str s => safeText s
  | .list xs => xs.all safeValue
  | .dict kvs => kvs.all fun (k, v) => safeValue k && safeValue v
  | _ => true

def requireSafe (v : Value) : Except VErr Unit :=
  if safeValue v then pure ()
  else throw (.unsupported "text outside printable ASCII in a value a text-handling validator reads")

/-- `str(v)` (also what `f"{v}"` prints), for text the model handles. -/
def strOf (v : Value) : Except VErr String := do
  requireSafe v
  match pyStr v with
  | .ok s => pure s
  | .error e => throw (.unsupported e)

/-- `repr(v)` for a message. -/
def reprOf (v : Value) : Except VErr String :=
  match pyRepr v with
  | .ok s => pure s
  | .error e => throw (.unsupported e)

/-- Python's `int(str)`: `parseIntStr`, and CPython's limit of 4300 digits
for decimal strings (`ValueError` beyond). -/
def pyIntOfStr? (s : String) : Option Int := do
  let i ← parseIntStr s
  if (s.toList.filter Char.isDigit).length > 4300 then none
  return i

/-! ## Schemas -/

/-- The types a schema can name. `float` is probatio's numeric tower
(`_FloatCheck`), the others are `isinstance` checks (`_TypeCheck`). -/
inductive PyType where
  | int | float | str | bool | object | list | dict | timedelta
  deriving BEq, Repr, Inhabited

def PyType.name : PyType → String
  | .int => "int" | .float => "float" | .str => "str" | .bool => "bool"
  | .object => "object" | .list => "list" | .dict => "dict" | .timedelta => "timedelta"

def PyType.ofString? : String → Option PyType
  | "int" => some .int | "float" => some .float | "str" => some .str
  | "bool" => some .bool | "any" | "object" => some .object
  | "list" => some .list | "dict" => some .dict | "timedelta" => some .timedelta
  | _ => none

/-- `Coerce(int)`, `Coerce(float)`, `Coerce(str)` -/
inductive CoerceType where
  | int | float | str
  deriving BEq, Repr, Inhabited

def CoerceType.name : CoerceType → String
  | .int => "int" | .float => "float" | .str => "str"

/-- The key markers: `Required`, `Optional`, `Exclusive(key, group,
required=...)`, `Inclusive(key, group)`. -/
inductive KeyMarker where
  | required
  | optional
  | exclusive (group : String) (groupRequired : Bool)
  | inclusive (group : String)
  deriving BEq, Repr, Inhabited

/-- `cv.entity_domain`'s argument: a domain or a list of them. -/
inductive DomainArg where
  | one (d : String)
  | many (ds : List String)
  deriving BEq, Repr, Inhabited

/-- The `helpers/config_validation.py` functions HALean translates (the
`cv.*` that are probatio objects, such as `cv.positive_int`, are written as
the probatio validators they are). -/
inductive CvFn where
  | string | boolean | entityId | entityIds | entityDomain (domain : DomainArg)
  | colorHex | slug
  /-- `cv.time_period_str`, `cv.time_period_seconds`, `cv.positive_timedelta` -/
  | timePeriodStr | timePeriodSeconds | positiveTimedelta
  /-- the `lambda value: timedelta(**value)` of `cv.time_period_dict` -/
  | timedeltaKwargs
  deriving BEq, Repr, Inhabited

/-- `PREVENT_EXTRA`, `ALLOW_EXTRA`, `REMOVE_EXTRA` -/
inductive Extra where
  | prevent | allow | remove
  deriving BEq, Repr, Inhabited

mutual
/-- A probatio schema node. -/
inductive Validator where
  /-- a type: `int`, `float`, `str`, ... -/
  | type (t : PyType)
  /-- a scalar literal (`str`, `int`, `float`, `bool`, `None`): equality -/
  | literal (v : Value)
  /-- a nested mapping of literal string keys -/
  | dict (fields : List Field)
  /-- a nested `probatio.Schema(mapping, extra=...)`, with its own policy -/
  | schema (fields : List Field) (extra : Extra)
  /-- a sequence schema `[v, ...]` (a list) -/
  | seq (elems : List Validator)
  | all (vs : List Validator)
  | any (vs : List Validator)
  /-- `In(container)` (a list of scalars) -/
  | isIn (container : List Value)
  | notIn (container : List Value)
  | range (min max : Option Value) (minIncluded maxIncluded : Bool)
  | clamp (min max : Option Value)
  | length (min max : Option Int)
  | coerce (t : CoerceType)
  | lower
  | upper
  | ensureList
  | port
  /-- `AtLeastOne(*keys)` (`cv.has_at_least_one_key`) -/
  | atLeastOne (keys : List String)
  | cv (f : CvFn)

/-- One key of a mapping schema. -/
inductive Field where
  | mk (key : String) (marker : KeyMarker) (default : Option Value) (value : Validator)
end

instance : Inhabited Validator := ⟨.type .object⟩
instance : Inhabited Field := ⟨.mk "" .optional none default⟩

def Field.key : Field → String | .mk k .. => k
def Field.marker : Field → KeyMarker | .mk _ m .. => m
def Field.default : Field → Option Value | .mk _ _ d _ => d
def Field.value : Field → Validator | .mk _ _ _ v => v

/-- `probatio.Schema({...}, extra=...)`. Nested mappings are compiled with
the same `extra` (probatio threads the policy into nested dicts, also through
combinators and sequences). -/
structure SchemaSpec where
  fields : List Field
  extra : Extra := .prevent
  deriving Inhabited

/-- `combinators._branch_label`: a type's name, `None`, or a scalar literal's
repr; `none` for a validator branch. -/
def Validator.label? : Validator → Option String
  | .type t => some t.name
  | .literal .none => some "None"
  | .literal v@(.str _) | .literal v@(.int _) | .literal v@(.float _) | .literal v@(.bool _) =>
    (pyRepr v).toOption
  | _ => none

/-- `combinators._expected_label`: the branch labels joined with `or`, when
every branch has one (and there is at least one). -/
def expectedLabel (vs : List Validator) : Option String := do
  let labels ← vs.mapM Validator.label?
  if labels.isEmpty then none else some (" or ".intercalate labels)

/-! ## Leaf validators -/

/-- `_TypeCheck.__call__` (`isinstance`; a `bool` is an `int`) and
`_FloatCheck.__call__` (a `float`, or an `int` (not a `bool`) converted, unless
it is too large for a float). -/
def checkType (t : PyType) (v : Value) : VResult :=
  let fail : VResult := throw (inv s!"expected {t.name}")
  match t, v with
  | .object, v => pure v
  | .int, .int _ | .int, .bool _ => pure v
  | .str, .str _ | .bool, .bool _ | .list, .list _ | .dict, .dict _
  | .timedelta, .timedelta _ => pure v
  | .float, .float _ => pure v
  | .float, .int i =>
    let f := intToFloat i
    if f.isInf then fail else pure (.float f)
  | _, _ => fail

/-- `_compile_literal`: `data != schema` fails with "not a valid value". -/
def checkLiteral (lit v : Value) : VResult :=
  if pyEq v lit then pure v else throw (inv "not a valid value")

/-- `comparison._sorted_for_message`: `sorted(container)`, or the container
as it is when sorting raises. For a container of scalars: strings sort, and
numbers (`bool` included) sort; a mix of the two, or `None` among two or
more members, makes `sorted` raise. Python's sort is stable, and so is
`List.mergeSort`. -/
def sortedForMessage (c : List Value) : List Value :=
  if c.length ≤ 1 then c
  else if c.all (fun v => match v with | .str _ => true | _ => false) then
    c.mergeSort fun a b => match a, b with
      | .str x, .str y => !decide (y < x)
      | _, _ => true
  else if c.all (fun v => v.num?.isSome) then
    c.mergeSort fun a b => match a.num?, b.num? with
      | some x, some y => !numLt y x
      | _, _ => true
  else c

/-- `_messages._display` on a list placeholder, then `str.format`: more than
40 members are cut. -/
def displayList (vs : List Value) : Except VErr String := do
  let reprs ← vs.mapM reprOf
  if reprs.length > 40 then
    return "[" ++ ", ".intercalate (reprs.take 40) ++ s!", ...] ({reprs.length - 40} more not shown)"
  return "[" ++ ", ".intercalate reprs ++ "]"

/-- A message built from text that may be `unsupported`. -/
def invWith (msg : Except VErr String) : VErr :=
  match msg with
  | .ok m => inv m
  | .error e => e

/-- `In.__call__` (no `fold_case`, no `space`): `value in container`; a miss
lists the sorted members and suggests close string members. -/
def checkIn (c : List Value) (v : Value) : VResult :=
  if c.any (pyEq v ·) then pure v
  else
    let pool := c.filterMap fun m => match m with | .str s => some s | _ => none
    throw (invWith do
      return "value must be one of " ++ (← displayList (sortedForMessage c)) ++ suggestionSuffix v pool)

/-- `NotIn.__call__` -/
def checkNotIn (c : List Value) (v : Value) : VResult :=
  if !c.any (pyEq v ·) then pure v
  else throw (invWith do return "value must not be one of " ++ (← displayList (sortedForMessage c)))

/-- `str.format` of a numeric bound. -/
def boundStr (b : Value) : Except VErr String :=
  match pyStr b with
  | .ok s => pure s
  | .error e => throw (.unsupported e)

/-- `value >= bound` / `value > bound` for numbers (`False` for NaN). -/
def numGe (x y : Num) : Bool := numLt y x || numEq x y

/-- The minimum check: `value >= min` (inclusive) or `value > min`. -/
def minOk (incl : Bool) (x a : Num) : Bool := if incl then numGe x a else numLt a x

/-- The maximum check: `value <= max` (inclusive) or `value < max`. -/
def maxOk (incl : Bool) (x b : Num) : Bool := if incl then numGe b x else numLt x b

/-- Both bounds hold (a bound that is not a number never holds). -/
def rangeOk (min max : Option Value) (minIncl maxIncl : Bool) (x : Num) : Bool :=
  (min.all fun m => match m.num? with | some a => minOk minIncl x a | none => false) &&
  (max.all fun m => match m.num? with | some b => maxOk maxIncl x b | none => false)

/-- The error `Range` raises for a number out of bounds: the minimum is
checked first. -/
def rangeError (min max : Option Value) (minIncl maxIncl : Bool) (x : Num) : VErr :=
  let minFails := min.any fun m => match m.num? with | some a => !minOk minIncl x a | none => true
  match min, max with
  | some m, _ =>
    if minFails then
      match m.num? with
      | none => .unsupported "a non-numeric Range bound"
      | some _ => invWith do
        let b ← boundStr m
        return if minIncl then s!"value must be at least {b}" else s!"value must be higher than {b}"
    else maxError m
  | none, _ => maxError .none
where
  maxError (_ : Value) : VErr :=
    match max with
    | some m => match m.num? with
      | none => .unsupported "a non-numeric Range bound"
      | some _ => invWith do
        let b ← boundStr m
        return if maxIncl then s!"value must be at most {b}" else s!"value must be lower than {b}"
    | none => .unsupported "Range: no bound failed"

/-- `Range.__call__`. A bound compared with a value that is not a number
raises `TypeError`, which `Range` reports as "invalid value or type". -/
def checkRange (min max : Option Value) (minIncl maxIncl : Bool) (v : Value) : VResult :=
  if min.isNone && max.isNone then pure v else
  match v.num? with
  | none => throw (inv "invalid value or type")
  | some x =>
    if rangeOk min max minIncl maxIncl x then pure v
    else throw (rangeError min max minIncl maxIncl x)

/-- `Clamp.__call__`: the bound itself replaces a value outside it. -/
def checkClamp (min max : Option Value) (v : Value) : VResult := do
  if min.isNone && max.isNone then return v
  let some x := v.num? | throw (inv "invalid value or type")
  if let some m := min then
    let some mn := m.num? | throw (.unsupported "a non-numeric Clamp bound")
    if numLt x mn then return m
  if let some m := max then
    let some mx := m.num? | throw (.unsupported "a non-numeric Clamp bound")
    if numLt mx x then return m
  return v

/-- `len(value)` for the values JSON can hold. -/
def pyLen? : Value → Option Nat
  | .str s => some s.length
  | .list xs => some xs.length
  | .dict kvs => some kvs.length
  | _ => none

/-- `Length.__call__` -/
def checkLength (min max : Option Int) (v : Value) : VResult := do
  if min.isNone && max.isNone then return v
  let some n := pyLen? v | throw (inv "value has no length")
  if let some m := min then
    if (n : Int) < m then throw (inv s!"length of value must be at least {m}")
  if let some m := max then
    if (n : Int) > m then throw (inv s!"length of value must be at most {m}")
  return v

/-- `int(value)` for the values JSON can hold; `none` where Python raises. -/
def pyInt? : Value → Except VErr (Option Int)
  | .bool b => pure (some (if b then 1 else 0))
  | .int i => pure (some i)
  | .float f => pure (floatToInt? f)
  | .str s => do requireSafe (.str s); pure (pyIntOfStr? s)
  | _ => pure none

/-- `float(value)`; `none` where Python raises. -/
def pyFloat? : Value → Except VErr (Option Float)
  | .bool b => pure (some (if b then 1.0 else 0.0))
  | .int i => let f := intToFloat i; pure (if f.isInf then none else some f)
  | .float f => pure (some f)
  | .str s => do requireSafe (.str s); pure (parseFloatStr s)
  | _ => pure none

/-- `Coerce(int|float|str).__call__`: `type(value)`, or `CoerceInvalid`
("expected <type>"; no suggestion, the target is not an `Enum`). -/
def checkCoerce (t : CoerceType) (v : Value) : VResult := do
  let fail : VResult := throw (inv s!"expected {t.name}")
  match t with
  | .int => match ← pyInt? v with
    | some i => pure (.int i)
    | none => fail
  | .float => match ← pyFloat? v with
    | some f => pure (.float f)
    | none => fail
  | .str =>
    match pyStr v with
    | .ok s => pure (.str s)
    | .error e => throw (.unsupported e)

/-- `strings.Lower` / `strings.Upper`: `str(value).lower()` / `.upper()`. -/
def checkLower (v : Value) : VResult := do
  return .str ((← strOf v).map Char.toLower)

def checkUpper (v : Value) : VResult := do
  return .str ((← strOf v).map Char.toUpper)

/-- `EnsureList.__call__` -/
def ensureList : Value → Value
  | .none => .list []
  | .list xs => .list xs
  | v => .list [v]

/-- `conditional.AtLeastOne.__call__`: a mapping with at least one of the
keys. -/
def checkAtLeastOne (keys : List String) (v : Value) : VResult := do
  let .dict kvs := v | throw (inv "expected a mapping")
  if keys.any fun k => kvs.any fun (k', _) => pyEq k' (.str k) then return v
  throw (invWith do return s!"at least one of {← displayList (keys.map .str)} is required")

/-- `network.Port.__call__`: an `int` from 1 to 65535 (a `bool`, a float
with a fraction, or anything `int()` rejects fails). -/
def checkPort (v : Value) : VResult := do
  let fail : VResult := throw (inv "expected a port number between 1 and 65535")
  match v with
  | .bool _ => fail
  | .float f =>
    if !Float.isFinite' f || f.floor != f then fail
    else match floatToInt? f with
      | some i => if 1 ≤ i && i ≤ 65535 then pure (.int i) else fail
      | none => fail
  | v => match ← pyInt? v with
    | some i => if 1 ≤ i && i ≤ 65535 then pure (.int i) else fail
    | none => fail

end HALean.Core
