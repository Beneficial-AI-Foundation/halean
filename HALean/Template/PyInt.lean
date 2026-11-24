/-
  Python's `int(str)` (base 10), as CPython parses it for ASCII text:
  whitespace, an optional sign, `digit (["_"] digit)*`, whitespace.
  Proved against that grammar in `HALean/Template/PyIntSpec.lean`
  (`parseIntChars_iff`).
-/
namespace HALean.Template

/-- The whitespace `int()` strips from ASCII text: `Py_ISSPACE`, the C locale's
`isspace` (space and `\t \n \v \f \r`). Not `str.isspace()`: `\x1c`-`\x1f`
are spaces only on the Unicode path, which `int()` takes for non-ASCII text. -/
def pySpace (c : Char) : Bool :=
  c == ' ' || ('\t' ≤ c && c ≤ '\r')

/-- The value of the digits, underscores skipped. -/
def digitValue (cs : List Char) : Nat :=
  (cs.filter Char.isDigit).foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0

def digitsUs : List Char → Bool
  | [d] => d.isDigit
  | d :: '_' :: rest => d.isDigit && digitsUs rest
  | d :: rest => d.isDigit && digitsUs rest
  | [] => false

def stripPy (cs : List Char) : List Char :=
  ((cs.dropWhile pySpace).reverse.dropWhile pySpace).reverse

/-- An optional sign: (negative?, the rest). -/
def signSplit : List Char → Bool × List Char
  | '-' :: b => (true, b)
  | '+' :: b => (false, b)
  | b => (false, b)

def parseIntChars (cs : List Char) : Option Int :=
  let sb := signSplit (stripPy cs)
  if digitsUs sb.2 then
    some (if sb.1 then -(digitValue sb.2 : Int) else digitValue sb.2)
  else none


end HALean.Template
