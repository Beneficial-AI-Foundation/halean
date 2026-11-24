/-
  Template values: the Python objects a Home Assistant template can see and
  produce, with Python's own semantics for `str()`, `repr()`, `==`, ordering
  and truthiness.

  Jinja is evaluated over Python objects, so getting these right is most of
  getting templates right: `{{ 0.1 + 0.2 }}` must print `0.30000000000000004`,
  `{{ [1, 'a'] }}` must print `[1, 'a']` and `1 == 1.0 == True`.
-/
import HALean.Core.Types
import HALean.Template.Time
import HALean.Template.PyInt
open Lean

namespace HALean.Template

inductive Value where
  | none
  /-- Jinja's `Undefined` (HA's `LoggingUndefined`): renders as "", is falsy,
  iterates as empty, and raises on anything else. -/
  | undef (name : String)
  | bool (b : Bool)
  | int (i : Int)
  | float (f : Float)
  | str (s : String)
  | list (xs : List Value)
  | tuple (xs : List Value)
  /-- Insertion-ordered, like Python's dict. -/
  | dict (kvs : List (Value × Value))
  /-- A state object. `collect` is true for the `TemplateState`s that
  `states(...)`/`states.x.y` hand out (reading them is recorded in the render
  info) and false for iterated states and plain `State`s such as
  `trigger.to_state`. -/
  | state (s : EntityState) (collect : Bool)
  /-- `DomainStates`: `states.light`. -/
  | domain (d : String)
  /-- `AllStates`: `states`, both callable and subscriptable. -/
  | allStates
  /-- A built-in function or a bound method such as `d.items`. -/
  | func (name : String) (self : Option Value)
  /-- A `namespace()` object; its fields live in the renderer's heap. -/
  | ns (id : Nat)
  /-- `datetime`: microseconds since the epoch (the instant when aware, the
  wall clock when naive) and the UTC offset in seconds (`none` = naive). -/
  | datetime (us : Int) (off : Option Int)
  /-- `timedelta`, in microseconds. -/
  | timedelta (us : Int)
  /-- `range(start, stop, step)` (Jinja's sandboxed `safe_range`). -/
  | range (start stop step : Int)
  /-- A one-shot iterator: what `map`, `select`, `reverse`... return. Printing
  it is not supported (Python prints `<generator object ...>`). -/
  | gen (kind : String) (xs : List Value)
  /-- A plain Python object exposing a few attributes (e.g. the `Event` in
  `trigger.event`). Printing it is not supported. -/
  | pyobj (cls : String) (fields : List (String × Value))
  /-- A Python object HALean does not model yet (datetime, timedelta, ...).
  Using it in any way is a render error, never a silent approximation. -/
  | opaque (what : String)
  deriving Inhabited

/-! ## Floats, exactly as CPython prints and parses them -/

/-- `|f| = m * 2^e` exactly (finite `f` only). -/
def decodeFloat (f : Float) : Bool × Nat × Int :=
  let b := f.toBits
  let neg := (b >>> 63) == 1
  let ex := ((b >>> 52) &&& 0x7FF).toNat
  let man := (b &&& 0xFFFFFFFFFFFFF).toNat
  if ex == 0 then (neg, man, -1074) else (neg, man + 2 ^ 52, (ex : Int) - 1075)

def Float.isFinite' (f : Float) : Bool := !f.isNaN && !f.isInf

/-- Correctly rounded (round-half-even) `num / den` as a double, like
CPython's `int / int` and `float(str)`. -/
def ratToFloat (neg : Bool) (num den : Nat) : Float := Id.run do
  if num == 0 then return (if neg then -0.0 else 0.0)
  let mut sh : Int := (num.log2 : Int) - den.log2 - 52
  if sh < -1074 then sh := -1074
  let qr (sh : Int) : Nat × Nat × Nat :=
    let n := if sh < 0 then num * 2 ^ (-sh).toNat else num
    let d := if sh > 0 then den * 2 ^ sh.toNat else den
    (n / d, n % d, d)
  let mut (q, r, d) := qr sh
  -- bring q into [2^52, 2^53) (or below 2^52 for subnormals)
  for _ in [0:4] do
    if q ≥ 2 ^ 53 then sh := sh + 1; (q, r, d) := qr sh
    else if q < 2 ^ 52 && sh > -1074 then sh := sh - 1; (q, r, d) := qr sh
  if 2 * r > d || (2 * r == d && q % 2 == 1) then q := q + 1
  if q == 2 ^ 53 then q := 2 ^ 52; sh := sh + 1
  let sign : UInt64 := if neg then (1 : UInt64) <<< 63 else 0
  if sh + 52 > 1023 then return (if neg then -1.0 / 0.0 else 1.0 / 0.0)
  if q < 2 ^ 52 then return Float.ofBits (sign ||| q.toUInt64)
  let biased := (sh + 1075).toNat
  return Float.ofBits (sign ||| (biased.toUInt64 <<< 52) ||| (q - 2 ^ 52).toUInt64)

def intToFloat (i : Int) : Float := ratToFloat (i < 0) i.natAbs 1

/-- Exact `m * 2^e` as a fraction. -/
def floatFrac (f : Float) : Bool × Nat × Nat :=
  let (neg, m, e) := decodeFloat f
  if e ≥ 0 then (neg, m * 2 ^ e.toNat, 1) else (neg, m, 2 ^ (-e).toNat)

def natDigits (n : Nat) : Nat := (toString n).length

/-- The shortest digit string that reads back as `f` (CPython's `repr`),
with `decpt` such that `|f| = 0.d1d2... * 10^decpt`. `f` finite, nonzero. -/
def shortestDigits (f : Float) : String × Int := Id.run do
  let (neg, num, den) := floatFrac f
  -- k = floor(log10 (num/den))
  let mut k : Int := (natDigits num : Int) - natDigits den
  let ge (k : Int) : Bool :=  -- num/den ≥ 10^k
    if k ≥ 0 then num ≥ den * 10 ^ k.toNat else num * 10 ^ (-k).toNat ≥ den
  while !ge k do k := k - 1
  while ge (k + 1) do k := k + 1
  for p in [1:18] do
    -- round num/den * 10^(p-1-k) to an integer, half-even
    let s : Int := (p : Int) - 1 - k
    let n := if s ≥ 0 then num * 10 ^ s.toNat else num
    let d := if s < 0 then den * 10 ^ (-s).toNat else den
    let mut q := n / d
    let r := n % d
    if 2 * r > d || (2 * r == d && q % 2 == 1) then q := q + 1
    let back := if s ≥ 0 then ratToFloat neg q (10 ^ s.toNat) else ratToFloat neg (q * 10 ^ (-s).toNat) 1
    if back == f then
      -- q may have p+1 digits after a carry (e.g. 9.99 → 10.0)
      let ds := toString q
      let ds := String.ofList (ds.toList.reverse.dropWhile (· == '0')).reverse
      let decpt := k + 1 + ((toString q).length - p : Int)
      return ((if ds.isEmpty then "0" else ds), decpt)
  return ("0", 0)  -- unreachable: 17 digits always round-trip

/-- `repr(float)` / `str(float)` in CPython 3. -/
def floatRepr (f : Float) : String :=
  if f.isNaN then "nan"
  else if f.isInf then (if f > 0 then "inf" else "-inf")
  else
    let (neg, _, _) := decodeFloat f
    let sign := if neg then "-" else ""
    if f == 0 then sign ++ "0.0" else
    let (ds, decpt) := shortestDigits f
    let n := ds.length
    if decpt > -4 && decpt ≤ 16 then
      if decpt ≤ 0 then sign ++ "0." ++ "".pushn '0' (-decpt).toNat ++ ds
      else if decpt.toNat ≥ n then sign ++ ds ++ "".pushn '0' (decpt.toNat - n) ++ ".0"
      else sign ++ (ds.take decpt.toNat).toString ++ "." ++ (ds.drop decpt.toNat).toString
    else
      let e := decpt - 1
      let mant := if n == 1 then ds else (ds.take 1).toString ++ "." ++ (ds.drop 1).toString
      let es := toString e.natAbs
      sign ++ mant ++ "e" ++ (if e < 0 then "-" else "+") ++ (if es.length < 2 then "0" ++ es else es)

/-- Python `float(s)` for strings: decimal and exponent forms, `inf`, `nan`,
surrounding whitespace and digit-group underscores. Correctly rounded. -/
def parseFloatStr (s : String) : Option Float := do
  let s := s.trim
  let (neg, body) :=
    if s.startsWith "-" then (true, s.dropS 1)
    else if s.startsWith "+" then (false, s.dropS 1) else (false, s)
  let lower := body.toLower
  if lower == "inf" || lower == "infinity" then return (if neg then -1.0 / 0.0 else 1.0 / 0.0)
  if lower == "nan" then return (0.0 / 0.0)
  let (mant, expPart) ← match lower.splitOn "e" with
    | [m] => some (m, none)
    | [m, e] => some (m, some e)
    | _ => none
  let (ip, fp) ← match mant.splitOn "." with
    | [i] => some (i, "")
    | [i, f] => some (i, f)
    | _ => none
  -- underscores only between digits
  let grp (d : String) : Option String :=
    if d.isEmpty then some "" else
    if d.startsWith "_" || d.endsWith "_" || (d.splitOn "__").length > 1 then none
    else let d' := d.replace "_" ""
      if d'.all Char.isDigit then some d' else none
  let ip ← grp ip
  let fp ← grp fp
  if ip.isEmpty && fp.isEmpty then none
  let e : Int ← match expPart with
    | none => some 0
    | some e =>
      let (eneg, ed) := if e.startsWith "-" then (true, e.dropS 1)
        else if e.startsWith "+" then (false, e.dropS 1) else (false, e)
      let ed ← grp ed
      if ed.isEmpty then none
      some (if eneg then -(ed.toNat! : Int) else ed.toNat!)
  let m := (ip ++ fp).toNat!
  let exp : Int := e - fp.length
  if exp ≥ 0 then return ratToFloat neg (m * 10 ^ exp.toNat) 1
  -- huge negative exponents underflow to zero anyway; cap the work
  if exp < -400 && m < 10 ^ 400 then return (if neg then -0.0 else 0.0)
  return ratToFloat neg m (10 ^ (-exp).toNat)

/-- Python `int(s)` (base 10): whitespace, sign, underscores between digits.
Proved against Python's grammar for ASCII text (`parseIntChars_iff`);
non-ASCII digits and spaces, which Python also accepts, give `none`. -/
def parseIntStr (s : String) : Option Int := parseIntChars s.toList

/-- Text `int()` / `float()` read the same way in HALean as in Python: ASCII
only (Python also takes other Unicode digits and spaces). -/
def numberTextModelled (s : String) : Bool := s.toList.all fun c => decide (c.toNat < 128)

/-- Truncate toward zero (`int(float)`); `none` for inf/nan (OverflowError/ValueError). -/
def floatToInt? (f : Float) : Option Int :=
  if !Float.isFinite' f then none else
  let (neg, num, den) := floatFrac f
  let q := num / den
  some (if neg then -(q : Int) else q)

/-! ## str() and repr() -/

def hexDigit (n : Nat) : Char := "0123456789abcdef".toList.getD n '0'

/-- `repr(str)`. -/
def strRepr (s : String) : String :=
  let q := if s.contains '\'' && !s.contains '"' then '"' else '\''
  let body := s.foldl (fun acc c =>
    if c == q || c == '\\' then acc.push '\\' |>.push c
    else if c == '\n' then acc ++ "\\n"
    else if c == '\r' then acc ++ "\\r"
    else if c == '\t' then acc ++ "\\t"
    else if c.toNat < 0x20 || c.toNat == 0x7f then
      acc ++ "\\x" ++ toString (hexDigit (c.toNat / 16)) ++ toString (hexDigit (c.toNat % 16))
    else acc.push c) ""
  toString q ++ body ++ toString q

def boolStr (b : Bool) : String := if b then "True" else "False"

mutual
/-- `str(x)`; `none` when HALean cannot print `x` the way Python would. -/
def pyStr : Value → Except String String
  | .str s => pure s
  | .undef _ => pure ""
  | .datetime us off => pure (isoformat us off " ")
  | .timedelta us => pure (tdStr us)
  | v => pyRepr v

/-- `repr(x)` -/
def pyRepr : Value → Except String String
  | .none => pure "None"
  | .undef _ => pure ""
  | .bool b => pure (boolStr b)
  | .int i => pure (toString i)
  | .float f => pure (floatRepr f)
  | .str s => pure (strRepr s)
  | .list xs => do pure ("[" ++ ", ".intercalate (← reprList xs) ++ "]")
  | .tuple xs => do
    let parts ← reprList xs
    pure (if parts.length == 1 then "(" ++ parts.headD "" ++ ",)" else "(" ++ ", ".intercalate parts ++ ")")
  | .dict kvs => do pure ("{" ++ ", ".intercalate (← reprDict kvs) ++ "}")
  | .ns _ => pure "<Namespace>"
  | .state s _ => throw s!"printing the state object of {s.entityId} is not supported by HALean"
  | .domain d => throw s!"printing states.{d} is not supported by HALean"
  | .allStates => throw "printing `states` is not supported by HALean"
  | .func n _ => throw s!"printing the function {n} is not supported by HALean"
  | .datetime .. => throw "repr() of a datetime is not supported by HALean"
  | .timedelta us => pure (tdRepr us)
  | .range a b c => pure (if c == 1 then s!"range({a}, {b})" else s!"range({a}, {b}, {c})")
  | .gen k _ => throw s!"printing a {k} object is not supported by HALean"
  | .pyobj c _ => throw s!"printing a {c} object is not supported by HALean"
  | .opaque w => throw s!"{w} values are not supported by HALean"

def reprList : List Value → Except String (List String)
  | [] => pure []
  | x :: xs => do pure ((← pyRepr x) :: (← reprList xs))

def reprDict : List (Value × Value) → Except String (List String)
  | [] => pure []
  | (k, v) :: kvs => do pure (((← pyRepr k) ++ ": " ++ (← pyRepr v)) :: (← reprDict kvs))
end

/-! ## Truthiness, equality, ordering -/

/-- The items of `range(a, b, c)`. -/
def rangeItems (a b c : Int) : List Int :=
  if c == 0 then [] else
  let n : Int := if c > 0 then (b - a + c - 1) / c else (a - b - c - 1) / (-c)
  (List.range n.toNat).map fun (i : Nat) => a + c * (i : Int)

/-- `bool(x)` -/
def truthy : Value → Bool
  | .none | .undef _ => false
  | .bool b => b
  | .int i => i != 0
  | .float f => f != 0
  | .str s => !s.isEmpty
  | .list xs | .tuple xs => !xs.isEmpty
  | .dict kvs => !kvs.isEmpty
  | .range a b c => !(rangeItems a b c).isEmpty
  | .timedelta us => us != 0
  | _ => true

/-- Numbers as Python sees them (`bool` is an `int`). -/
inductive Num where
  | i (v : Int)
  | f (v : Float)

def Value.num? : Value → Option Num
  | .bool b => some (.i (if b then 1 else 0))
  | .int i => some (.i i)
  | .float f => some (.f f)
  | _ => Option.none

def Num.toFloat : Num → Float
  | .i v => intToFloat v
  | .f v => v

/-- Exact comparison of an int with a float, as CPython does. -/
def cmpIntFloat (i : Int) (f : Float) : Ordering :=
  if f.isNaN then .eq  -- callers treat NaN separately
  else if f.isInf then (if f > 0 then .lt else .gt)
  else
    let (neg, num, den) := floatFrac f
    let fl : Int := if neg then -(num : Int) else num
    compare (i * den) fl

def numEq : Num → Num → Bool
  | .i a, .i b => a == b
  | .f a, .f b => a == b
  | .i a, .f b => !b.isNaN && cmpIntFloat a b == .eq
  | .f a, .i b => !a.isNaN && cmpIntFloat b a == .eq

/-- `a < b` etc. on numbers; `none` never happens for numbers, but NaN
compares false both ways. -/
def numLt : Num → Num → Bool
  | .i a, .i b => a < b
  | .f a, .f b => a < b
  | .i a, .f b => !b.isNaN && cmpIntFloat a b == .lt
  | .f a, .i b => !a.isNaN && cmpIntFloat b a == .gt

def stateEq (a b : EntityState) : Bool :=
  a.entityId == b.entityId && a.state == b.state && a.attributes == b.attributes

mutual
/-- Python `==` -/
partial def pyEq : Value → Value → Bool
  | .none, .none => true
  | .undef _, .undef _ => true
  | .str a, .str b => a == b
  | .list a, .list b => listEq a b
  | .tuple a, .tuple b => listEq a b
  | .dict a, .dict b => a.length == b.length && dictSub a b
  | .state a _, .state b _ => stateEq a b
  | .domain a, .domain b => a == b
  | .allStates, .allStates => true
  | .ns a, .ns b => a == b
  | .range a b c, .range x y z => rangeItems a b c == rangeItems x y z
  -- aware datetimes compare instants; aware vs naive are never equal
  | .datetime a (some _), .datetime b (some _) => a == b
  | .datetime a none, .datetime b none => a == b
  | .timedelta a, .timedelta b => a == b
  | a, b => match a.num?, b.num? with
    | some x, some y => numEq x y
    | _, _ => false

partial def listEq : List Value → List Value → Bool
  | [], [] => true
  | x :: xs, y :: ys => pyEq x y && listEq xs ys
  | _, _ => false

partial def dictSub : List (Value × Value) → List (Value × Value) → Bool
  | [], _ => true
  | (k, v) :: kvs, other => (match dictLookup other k with
      | some w => pyEq v w
      | none => false) && dictSub kvs other

partial def dictLookup : List (Value × Value) → Value → Option Value
  | [], _ => none
  | (k, v) :: kvs, key => if pyEq k key then some v else dictLookup kvs key
end

def typeName : Value → String
  | .none => "NoneType"
  | .undef _ => "Undefined"
  | .bool _ => "bool"
  | .int _ => "int"
  | .float _ => "float"
  | .str _ => "str"
  | .list _ => "list"
  | .tuple _ => "tuple"
  | .dict _ => "dict"
  | .state _ _ => "TemplateState"
  | .domain _ => "DomainStates"
  | .allStates => "AllStates"
  | .func _ _ => "function"
  | .ns _ => "Namespace"
  | .datetime .. => "datetime"
  | .timedelta _ => "timedelta"
  | .range .. => "range"
  | .gen k _ => k
  | .pyobj c _ => c
  | .opaque w => w

mutual
/-- Python `a < b`; errors where Python raises `TypeError`. -/
partial def pyLt (a b : Value) : Except String Bool :=
  match a, b with
  | .str x, .str y => pure (x < y)
  | .list x, .list y => seqLt x y
  | .tuple x, .tuple y => seqLt x y
  | .datetime x (some _), .datetime y (some _) => pure (x < y)
  | .datetime x none, .datetime y none => pure (x < y)
  | .datetime .., .datetime .. => throw "can't compare offset-naive and offset-aware datetimes"
  | .timedelta x, .timedelta y => pure (x < y)
  | _, _ => match a.num?, b.num? with
    | some x, some y => pure (numLt x y)
    | _, _ => throw s!"'<' not supported between instances of '{typeName a}' and '{typeName b}'"

/-- Lexicographic order of sequences, as Python compares lists. -/
partial def seqLt : List Value → List Value → Except String Bool
  | [], [] => pure false
  | [], _ => pure true
  | _, [] => pure false
  | x :: xs, y :: ys => if pyEq x y then seqLt xs ys else pyLt x y
end

partial def Value.ofJson : Json → Value
  | .null => .none
  | .bool b => .bool b
  | .num n =>
    if n.exponent == 0 then .int n.mantissa
    else .float (ratToFloat (n.mantissa < 0) n.mantissa.natAbs (10 ^ n.exponent))
  | .str s => .str s
  | .arr xs => .list (xs.toList.map Value.ofJson)
  | .obj kvs => .dict (kvs.toList.map fun (k, v) => (.str k, Value.ofJson v))

/-- A float as a JSON number that keeps it a float (`20.0`, not `20`). -/
def floatToJson (f : Float) : Except String Json :=
  if !Float.isFinite' f then throw s!"{floatRepr f} cannot be sent as JSON"
  else if f == 0 then pure (.num { mantissa := 0, exponent := 1 })
  else
    let (neg, _, _) := decodeFloat f
    let (ds, decpt) := shortestDigits f
    let n := ds.length
    let d : Int := ds.toNat!
    let d := if neg then -d else d
    let shift : Int := decpt - n
    pure <| .num <|
      if shift ≥ 0 then { mantissa := d * 10 ^ (shift.toNat + 1), exponent := 1 }
      else { mantissa := d, exponent := (-shift).toNat }

/-- How HA hands a rendered value on (service data, event data): Python
objects that the WebSocket API serialises as JSON. -/
partial def Value.toJson : Value → Except String Json
  | .none => pure .null
  | .bool b => pure (.bool b)
  | .int i => pure (.num (JsonNumber.fromInt i))
  | .float f => floatToJson f
  | .str s => pure (.str s)
  | .list xs | .tuple xs => do pure (.arr (← xs.mapM Value.toJson).toArray)
  | .dict kvs => do
    let fields ← kvs.mapM fun (k, v) => do
      let key ← match k with
        | .str s => pure s
        | k => pyStr k
      pure (key, ← v.toJson)
    pure (Json.mkObj fields)
  | v => throw s!"a {typeName v} value cannot be sent to Home Assistant by HALean"

instance : Repr Value where
  reprPrec v _ := match pyRepr v with
    | .ok s => s
    | .error _ => s!"<{typeName v}>"

end HALean.Template
