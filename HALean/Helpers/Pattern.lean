/-
  `re.compile(pattern).match(value)` for the `pattern` of an `input_text`
  (`TextEntity.pattern_cmp`), for a subset of Python's regular expression
  syntax, parsed into the backtracking matcher `HALean.Template.Rx`:
  literals, `.`, `[...]` classes (ranges, negation, `\d \w \s` and escapes
  inside), `\d \D \w \W \s \S`, escaped metacharacters, `*` `+` `?` `{m}`
  `{m,}` `{m,n}` (greedy), groups `(...)` and `(?:...)`, `|`, a leading `^`
  and `$`.

  Anything else (lazy quantifiers, backreferences, lookarounds, flags, `\b`,
  `^` not at the start, ...) is refused, and so is the pattern. `\d`, `\w`
  and `\s` are Unicode-aware upstream; HALean matches them on ASCII only, so
  a value with non-ASCII characters is outside the model when the pattern
  uses them (`usesClassEscape`).
-/
import HALean.Template.Regex

namespace HALean.Helpers.Pattern
open HALean.Template

def isWordChar (c : Char) : Bool := c.isAlphanum || c == '_'
def isSpaceChar (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\r' || c.toNat == 11 || c.toNat == 12

/-- The predicate of `\d \D \w \W \s \S`. -/
def classEscape? : Char → Option (Char → Bool)
  | 'd' => some Char.isDigit
  | 'D' => some fun c => !c.isDigit
  | 'w' => some isWordChar
  | 'W' => some fun c => !isWordChar c
  | 's' => some isSpaceChar
  | 'S' => some fun c => !isSpaceChar c
  | _ => none

/-- An escaped character that stands for itself: punctuation, and the
control escapes Python knows. -/
def literalEscape? (c : Char) : Option Char :=
  if "\\.^$*+?{}[]()|/-".toList.contains c then some c
  else match c with
    | 'n' => some '\n' | 't' => some '\t' | 'r' => some '\r'
    | 'f' => some (Char.ofNat 12) | 'v' => some (Char.ofNat 11)
    | _ => if c.isAlphanum then none else some c

abbrev P := StateT (List Char) (Except String)

def peek : P (Option Char) := do return (← get).head?

def next : P Char := do
  match ← get with
  | c :: t => set t; return c
  | [] => throw "unexpected end of pattern"

/-- One item of a `[...]` class: a predicate. -/
def classAtom : P (Char → Bool) := do
  let c ← next
  let lo ← if c == '\\' then do
      let e ← next
      match classEscape? e with
      | some p => return p
      | none => match literalEscape? e with
        | some l => pure l
        | none => throw s!"unsupported escape \\{e}"
    else pure c
  -- a range `a-z` (a `-` before `]` is literal)
  match ← get with
  | '-' :: d :: _ =>
    if d == ']' then return (· == lo)
    discard next
    let hi ← next
    let hi ← if hi == '\\' then do
        let e ← next
        match literalEscape? e with
        | some l => pure l
        | none => throw s!"unsupported escape \\{e} in a range"
      else pure hi
    if hi < lo then throw "bad character range"
    return fun x => lo ≤ x && x ≤ hi
  | _ => return (· == lo)

partial def classItems (acc : List (Char → Bool)) (first : Bool) : P (List (Char → Bool)) := do
  match ← peek with
  | none => throw "unterminated character set"
  | some ']' =>
    if first then
      discard next
      classItems (acc ++ [(· == ']')]) false
    else discard next; return acc
  | some _ => do
    let a ← classAtom
    classItems (acc ++ [a]) false

def charClass : P Rx := do
  let neg ← match ← peek with
    | some '^' => discard next; pure true
    | _ => pure false
  let items ← classItems [] true
  return .cls fun c => (items.any (· c)) != neg

partial def parseNat (acc : Option Nat) : P (Option Nat) := do
  match ← peek with
  | some c => if c.isDigit then do discard next; parseNat (some ((acc.getD 0) * 10 + (c.toNat - 48))) else return acc
  | none => return acc

mutual
partial def alternation : P Rx := do
  let first ← sequence
  let mut alts := [first]
  while (← peek) == some '|' do
    discard next
    alts := alts ++ [← sequence]
  return if alts.length == 1 then first else .alt alts

partial def sequence : P Rx := do
  let mut items : List Rx := []
  repeat
    match ← peek with
    | none | some '|' | some ')' => break
    | some _ => items := items ++ [← quantified]
  return .seq items

partial def quantified : P Rx := do
  let a ← atom
  let r ← match ← peek with
    | some '*' => discard next; pure (Rx.rep a 0 none)
    | some '+' => discard next; pure (Rx.rep a 1 none)
    | some '?' => discard next; pure (Rx.rep a 0 (some 1))
    | some '{' => do
      -- `sre_parse`: `{lo}`, `{lo,hi}` with either bound omitted; anything
      -- else (`{}`, `{a}`, ...) is a literal `{`
      let saved ← get
      discard next
      if (← peek) == some '}' then set saved; return a
      let lo ← parseNat none
      let hi ← if (← peek) == some ',' then do discard next; parseNat none else pure lo
      if (← peek) != some '}' then
        set saved; pure a
      else
        discard next
        let lo := lo.getD 0
        if let some h := hi then if h < lo then throw "min repeat greater than max repeat"
        pure (Rx.rep a lo hi)
    | _ => pure a
  if r matches .rep .. then
    match ← peek with
    | some '?' | some '+' => throw "lazy and possessive quantifiers are not supported"
    | some '*' | some '{' => throw "a repeat after a repeat is not supported"
    | _ => pure ()
  return r

partial def atom : P Rx := do
  let c ← next
  match c with
  | '.' => return .cls (· != '\n')
  | '[' => charClass
  | '(' =>
    let nonCapturing ← match ← get with
      | '?' :: ':' :: _ => discard next; discard next; pure true
      | '?' :: _ => throw "group extensions other than (?:...) are not supported"
      | _ => pure false
    let _ := nonCapturing
    let r ← alternation
    if (← next) != ')' then throw "missing )"
    return r
  | '$' => return .eol
  | '\\' =>
    let e ← next
    match classEscape? e with
    | some p => return .cls p
    | none => match literalEscape? e with
      | some l => return .cls (· == l)
      | none => throw s!"unsupported escape \\{e}"
  | '*' | '+' | '?' => throw "nothing to repeat"
  | '^' => throw "'^' is supported only at the start of the pattern"
  | ')' => throw "unbalanced parenthesis"
  | c => return .cls (· == c)
end

/-- Parse a pattern; `none` when it is outside the supported subset. -/
def parse (pattern : String) : Except String Rx := do
  let cs := pattern.toList
  -- a leading `^` is a no-op for `re.match`
  let cs := match cs with | '^' :: t => t | t => t
  let (r, rest) ← alternation.run cs
  if !rest.isEmpty then throw "unbalanced parenthesis"
  return r

/-- Whether the pattern uses a Unicode-aware class (`\d \w \s` and their
negations). -/
def usesClassEscape (pattern : String) : Bool :=
  let rec go : List Char → Bool
    | '\\' :: c :: t => (classEscape? c).isSome || go t
    | _ :: t => go t
    | [] => false
  go pattern.toList

/-- `bool(re.compile(pattern).match(value))` -/
def isMatch (r : Rx) (value : String) : Bool := (Rx.matchPrefix r value).isSome

end HALean.Helpers.Pattern
