/-
  JSON decoded the way Python's `json.loads` decodes it.

  Lean's `Json` keeps objects sorted by key and reads `1.0` and `1e3`
  inconsistently as ints or floats. The service registry's behaviour depends
  on both (dict order shows in error order and in `repr`; a `float` schema field
  coerces an `int`), so the services executable reads its input with this parser
  into `HALean.Template.Value`: objects keep their written order (a duplicate key
  keeps its first position and its last value, like `dict`), and a number is a
  `float` exactly when it has a fraction or an exponent.
-/
import HALean.Template.Value

namespace HALean.Core
open HALean.Template

private def isWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\r'

private def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- Insert like `d[k] = v`: replace in place, or append. -/
def dictSet (kvs : List (String × Value)) (k : String) (v : Value) : List (String × Value) :=
  if kvs.any (·.1 == k) then kvs.map fun p => if p.1 == k then (k, v) else p
  else kvs ++ [(k, v)]

structure JP where
  cs : Array Char
  pos : Nat

abbrev JParser := StateT JP (Except String)

private def peek : JParser (Option Char) := do
  let s ← get
  return s.cs[s.pos]?

private def next : JParser Char := do
  let s ← get
  match s.cs[s.pos]? with
  | some c => set { s with pos := s.pos + 1 }; return c
  | none => throw "unexpected end of JSON"

private partial def skipWs : JParser Unit := do
  match ← peek with
  | some c => if isWs c then do let _ ← next; skipWs else return ()
  | none => return ()

private def expectLit (lit : String) : JParser Unit := do
  for c in lit.toList do
    if (← next) != c then throw s!"invalid literal, expected {lit}"

private def hex4 : JParser Nat := do
  let mut n := 0
  for _ in [0:4] do
    match hexVal (← next) with
    | some d => n := n * 16 + d
    | none => throw "invalid \\u escape"
  return n

private partial def strBody (acc : String) : JParser String := do
  let c ← next
  if c == '"' then return acc
  if c.toNat < 0x20 then throw "invalid control character in string"
  if c != '\\' then return ← strBody (acc.push c)
  match ← next with
  | '"' => strBody (acc.push '"')
  | '\\' => strBody (acc.push '\\')
  | '/' => strBody (acc.push '/')
  | 'b' => strBody (acc.push (Char.ofNat 8))
  | 'f' => strBody (acc.push (Char.ofNat 12))
  | 'n' => strBody (acc.push '\n')
  | 'r' => strBody (acc.push '\r')
  | 't' => strBody (acc.push '\t')
  | 'u' =>
    let u ← hex4
    if 0xD800 ≤ u && u < 0xDC00 then
      -- a surrogate pair; a lone surrogate cannot be a Lean `Char`
      if (← next) != '\\' || (← next) != 'u' then throw "lone surrogate in string"
      let l ← hex4
      if !(0xDC00 ≤ l && l < 0xE000) then throw "lone surrogate in string"
      strBody (acc.push (Char.ofNat (0x10000 + (u - 0xD800) * 0x400 + (l - 0xDC00))))
    else if 0xDC00 ≤ u && u < 0xE000 then throw "lone surrogate in string"
    else strBody (acc.push (Char.ofNat u))
  | _ => throw "invalid escape in string"

private partial def digits (acc : String) : JParser String := do
  match ← peek with
  | some c => if c.isDigit then do let _ ← next; digits (acc.push c) else return acc
  | none => return acc

/-- `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?`: an `int` without
fraction or exponent, otherwise Python's correctly rounded `float(text)`. -/
private def number : JParser Value := do
  let mut text := ""
  if (← peek) == some '-' then let _ ← next; text := "-"
  let ip ← digits ""
  if ip.isEmpty || (ip.length > 1 && ip.startsWith "0") then throw "invalid number"
  text := text ++ ip
  let mut isFloat := false
  if (← peek) == some '.' then
    let _ ← next
    let fp ← digits ""
    if fp.isEmpty then throw "invalid number"
    text := text ++ "." ++ fp
    isFloat := true
  if (← peek) == some 'e' || (← peek) == some 'E' then
    let _ ← next
    text := text ++ "e"
    if (← peek) == some '-' || (← peek) == some '+' then text := text.push (← next)
    let ep ← digits ""
    if ep.isEmpty then throw "invalid number"
    text := text ++ ep
    isFloat := true
  if isFloat then
    match parseFloatStr text with
    | some f => return .float f
    | none => throw s!"invalid number {text}"
  else
    match parseIntStr text with
    | some i => return .int i
    | none => throw s!"invalid number {text}"

mutual
private partial def value : JParser Value := do
  skipWs
  match ← peek with
  | some '{' => let _ ← next; obj []
  | some '[' => let _ ← next; arr #[]
  | some '"' => let _ ← next; return .str (← strBody "")
  | some 't' => expectLit "true"; return .bool true
  | some 'f' => expectLit "false"; return .bool false
  | some 'n' => expectLit "null"; return .none
  | some c => if c == '-' || c.isDigit then number else throw s!"unexpected character {c}"
  | none => throw "unexpected end of JSON"

private partial def obj (acc : List (String × Value)) : JParser Value := do
  skipWs
  if acc.isEmpty && (← peek) == some '}' then let _ ← next; return .dict []
  if (← next) != '"' then throw "expected a string key"
  let k ← strBody ""
  skipWs
  if (← next) != ':' then throw "expected ':'"
  let v ← value
  let acc := dictSet acc k v
  skipWs
  match ← next with
  | ',' => obj acc
  | '}' => return .dict (acc.map fun (k, v) => (.str k, v))
  | _ => throw "expected ',' or '}'"

private partial def arr (acc : Array Value) : JParser Value := do
  skipWs
  if acc.isEmpty && (← peek) == some ']' then let _ ← next; return .list []
  let v ← value
  skipWs
  match ← next with
  | ',' => arr (acc.push v)
  | ']' => return .list (acc.push v).toList
  | _ => throw "expected ',' or ']'"
end

/-- Python's `json.loads` (without `NaN`/`Infinity`, which HALean rejects). -/
def parsePyJson (s : String) : Except String Value := do
  let (v, st) ← (do let v ← value; skipWs; return v).run ⟨s.toList.toArray, 0⟩
  if st.pos < st.cs.size then throw "extra data after JSON value"
  return v

/-- The string-keyed items of a dict value. -/
def _root_.HALean.Template.Value.strItems? : Value → Option (List (String × Value))
  | .dict kvs => kvs.mapM fun (k, v) => match k with
    | .str s => some (s, v)
    | _ => none
  | _ => none

def _root_.HALean.Template.Value.get? (v : Value) (k : String) : Option Value :=
  (v.strItems?.bind fun kvs => kvs.lookup k)

def dictOf (kvs : List (String × Value)) : Value := .dict (kvs.map fun (k, v) => (.str k, v))

end HALean.Core
