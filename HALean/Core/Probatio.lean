/-
  The subset of service schemas the service registry model supports.

  Since 2026, Home Assistant validates service data with `probatio`, a
  voluptuous-compatible library (pinned in `manifest.yaml` as
  `upstream.probatio`; it is a dependency, not HA code, like Jinja2). A service
  schema here is a flat mapping schema:

    probatio.Schema({Required("a"): int, Optional("b", default="x"): str, ...},
                    extra=PREVENT_EXTRA | ALLOW_EXTRA | REMOVE_EXTRA)

  with value types `int`, `float`, `str`, `bool` and `object` (anything).
  `validate` follows `probatio._engine._MappingValidator.__call__`: errors are
  collected in data order, then the missing required keys and the defaults in
  schema order, and `str(MultipleInvalid)` is the first error. Unknown keys get
  probatio's "did you mean" hint, which uses `difflib.get_close_matches`
  (translated below).
-/
import HALean.Core.PyJson

namespace HALean.Core
open HALean.Template

inductive FieldType where
  | int | float | str | bool | any
  deriving BEq, Repr, Inhabited

def FieldType.ofString? : String → Option FieldType
  | "int" => some .int
  | "float" => some .float
  | "str" => some .str
  | "bool" => some .bool
  | "any" => some .any
  | _ => none

def FieldType.name : FieldType → String
  | .int => "int" | .float => "float" | .str => "str" | .bool => "bool" | .any => "object"

structure FieldSpec where
  key : String
  required : Bool
  type : FieldType
  default : Option Value := none
  deriving Inhabited

inductive Extra where
  | prevent | allow | remove
  deriving BEq, Repr, Inhabited

structure SchemaSpec where
  fields : List FieldSpec
  extra : Extra := .prevent
  deriving Inhabited

/-- One `probatio.Invalid` with its path (always one key deep here). -/
structure SchemaError where
  message : String
  path : List String
  deriving BEq, Repr, Inhabited

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

/-- `probatio.error.render_path` for a path of string keys. -/
def renderPath (path : List String) : String := Id.run do
  let mut out := ""
  for seg in path do
    let bare := seg.length ≤ 500 &&
      (isBareKey seg || (seg.startsWith "<" && seg.endsWith ">" &&
        isBareKey ((seg.drop 1).toString.dropEnd 1).toString))
    if bare then
      out := if out.isEmpty then seg else out ++ "." ++ seg
    else
      let r := strRepr seg
      let r := if r.length > 500 then (r.take 497).toString ++ "..." else r
      out := out ++ "[" ++ r ++ "]"
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

/-- `_MappingValidator._extra_key_error`: "not a valid option", with
", did you mean ...?" when difflib finds close schema keys. -/
def extraKeyError (keyNames : List String) (key : String) : SchemaError :=
  let pool := keyNames.filter (· != key)
  let cands := getCloseMatches key pool SUGGESTION_CUTOFF
  let suffix := if cands.isEmpty then "" else ", did you mean " ++ formatCandidates cands ++ "?"
  { message := "not a valid option" ++ suffix, path := [key] }

/-! ## Validation -/

/-- The value check of one field: the inlined `isinstance` for `int`, `str`,
`bool`, `object`, and `_FloatCheck` for `float` (an `int`, not a `bool`, is
accepted and converted; one too large for a float is rejected). -/
def checkValue (t : FieldType) (v : Value) : Option Value :=
  match t, v with
  | .any, v => some v
  | .int, .int i => some (.int i)
  | .int, .bool b => some (.bool b)
  | .str, .str s => some (.str s)
  | .bool, .bool b => some (.bool b)
  | .float, .float f => some (.float f)
  | .float, .int i =>
    let f := intToFloat i
    if f.isInf then none else some (.float f)
  | _, _ => none

def typeError (t : FieldType) (key : String) : SchemaError :=
  { message := s!"expected {t.name}", path := [key] }

/-- `_MappingValidator.__call__` for a flat schema of literal string keys.
Returns the validated dict (in data order, then defaults in schema order) or
the collected errors (`MultipleInvalid.errors`). -/
def SchemaSpec.validate (s : SchemaSpec) (data : List (String × Value)) :
    Except (List SchemaError) (List (String × Value)) := Id.run do
  let keyNames := s.fields.map (·.key)
  let mut out : List (String × Value) := []
  let mut errors : Array SchemaError := #[]
  let mut seen : List String := []
  for (k, v) in data do
    match s.fields.find? (·.key == k) with
    | some f =>
      seen := k :: seen
      match checkValue f.type v with
      | some v' => out := dictSet out k v'
      | none => errors := errors.push (typeError f.type k)
    | none =>
      match s.extra with
      | .allow => out := dictSet out k v
      | .remove => pure ()
      | .prevent => errors := errors.push (extraKeyError keyNames k)
  -- `_finalize`: defaults (validated through the value schema) and missing
  -- required keys, in schema order
  for f in s.fields do
    if !(f.required || f.default.isSome) || seen.contains f.key then continue
    match f.default with
    | some d =>
      match checkValue f.type d with
      | some d' => out := dictSet out f.key d'
      | none => errors := errors.push (typeError f.type f.key)
    | none => errors := errors.push { message := "required key not provided", path := [f.key] }
  if errors.isEmpty then return .ok out else return .error errors.toList

/-- `str(MultipleInvalid(errors))`: the first error. -/
def multipleInvalidStr : List SchemaError → String
  | [] => "no validation errors"
  | e :: _ => e.str

end HALean.Core
