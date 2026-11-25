/-
  Jinja syntax: lexer, AST and parser for the subset of Jinja2 that Home
  Assistant templates use.

  Follows `jinja2/lexer.py` and `jinja2/parser.py` (the version HA pins):
  operator precedence, `is` tests, filters binding tighter than unary minus's
  operand, chained comparisons, `a if b else c`, whitespace control (`{{-`,
  `-%}`), comments, and the `if` / `for` / `set` / `break` / `continue`
  statements (`jinja2.ext.loopcontrols` is enabled in HA).

  Anything else (macros, `include`, `raw`, `call` blocks...) is rejected at
  load time with a message.
-/
import HALean.Template.Value
open Lean

namespace HALean.Template

inductive Expr where
  | lit (v : Value)
  | name (n : String)
  | list (xs : List Expr)
  | tuple (xs : List Expr)
  | dict (kvs : List (Expr × Expr))
  | getattr (e : Expr) (attr : String)
  | getitem (e : Expr) (key : Expr)
  | slice (e : Expr) (start stop step : Option Expr)
  | call (f : Expr) (args : List Expr) (kwargs : List (String × Expr))
  | filter (e : Expr) (name : String) (args : List Expr) (kwargs : List (String × Expr))
  | test (e : Expr) (name : String) (args : List Expr) (negated : Bool)
  | neg (e : Expr)
  | pos (e : Expr)
  /-- `+ - * / // % **` -/
  | binop (op : String) (a b : Expr)
  /-- `~` -/
  | concat (a b : Expr)
  /-- `a < b <= c`: Python's chained comparison. Ops: == != < <= > >= in notin -/
  | compare (first : Expr) (rest : List (String × Expr))
  | and (a b : Expr)
  | or (a b : Expr)
  | not (e : Expr)
  /-- `a if c else b`; a missing `else` gives Undefined. -/
  | cond (c a : Expr) (b : Option Expr)
  deriving Inhabited

inductive Node where
  | text (s : String)
  | output (e : Expr)
  | ifs (branches : List (Expr × List Node)) (else_ : List Node)
  | for (targets : List String) (iter : Expr) (filter : Option Expr) (body : List Node)
      (else_ : List Node)
  | set (targets : List String) (e : Expr)
  /-- `{% set ns.attr = e %}` -/
  | setAttr (obj attr : String) (e : Expr)
  | brk
  | cont
  deriving Inhabited

/-! ## Lexer -/

inductive Tok where
  | name (s : String)
  | str (s : String)
  | int (i : Int)
  | float (f : Float)
  | op (s : String)
  /-- end of the `{{ }}` / `{% %}` block -/
  | close
  deriving Inhabited, BEq

instance : ToString Tok where
  toString
    | .name s => s
    | .str s => strRepr s
    | .int i => toString i
    | .float f => floatRepr f
    | .op s => s
    | .close => "end of block"

/-- Raw template pieces before parsing statements. -/
inductive Piece where
  | text (s : String)
  | expr (toks : List Tok)
  | stmt (toks : List Tok)
  deriving Inhabited

abbrev P := Except String

def isNameStart (c : Char) : Bool := c.isAlpha || c == '_'
def isNameChar (c : Char) : Bool := c.isAlphanum || c == '_'

/-- The value of exactly `n` hex digits at the head of the list. -/
def unescapeHex : Nat → List Char → Nat → Option Nat
  | 0, _, v => some v
  | n + 1, c :: rest, v => (hexVal c).bind fun d => unescapeHex n rest (v * 16 + d)
  | _ + 1, [], _ => none

/-- Up to `n` octal digits at the head of the list: (value, how many). -/
def unescapeOctal : Nat → List Char → Nat → Nat × Nat
  | 0, _, v => (v, 0)
  | n + 1, c :: rest, v =>
    if '0' ≤ c && c ≤ '7' then
      let (v', k) := unescapeOctal n rest (v * 8 + (c.toNat - '0'.toNat)); (v', k + 1)
    else (v, 0)
  | _ + 1, [], v => (v, 0)

def unescapeCode (n : Nat) (what : String) : P Char := do
  if n > 0x10FFFF then throw "illegal Unicode character in string literal"
  if 0xD800 ≤ n && n ≤ 0xDFFF then throw s!"a lone surrogate ({what}) in a string literal is not supported by HALean"
  pure (Char.ofNat n)

/-- Jinja's lexer unescapes a string literal with
`.encode("ascii", "backslashreplace").decode("unicode-escape")`: Python's
escapes (`\n`, `\xhh`, `\uhhhh`, `\Uhhhhhhhh`, octal `\ooo`, a
backslash-newline continuation...), unknown escapes kept as written. A
non-ASCII character reads as itself (its `backslashreplace` form decodes back
to it), except right after a backslash: `\é` is `\` followed by `xe9`.
`\N{name}` needs the Unicode name database and a lone surrogate (`\ud800`)
cannot be a Lean `Char`: both are rejected. -/
def unescape (cs : List Char) : P String := do
  let rec go : List Char → String → P String
    | [], acc => pure acc
    | '\\' :: c :: rest, acc =>
      if c.toNat ≥ 128 then go rest (acc ++ "\\" ++ ((escapeChar c).drop 1).toString) else
      match c with
      | 'n' => go rest (acc.push '\n')
      | 't' => go rest (acc.push '\t')
      | 'r' => go rest (acc.push '\r')
      | '\\' => go rest (acc.push '\\')
      | '\'' => go rest (acc.push '\'')
      | '"' => go rest (acc.push '"')
      | 'a' => go rest (acc.push (Char.ofNat 7))
      | 'b' => go rest (acc.push (Char.ofNat 8))
      | 'f' => go rest (acc.push (Char.ofNat 12))
      | 'v' => go rest (acc.push (Char.ofNat 11))
      | '\n' => go rest acc
      | 'x' => match unescapeHex 2 rest 0 with
        | some v => go (rest.drop 2) (acc.push (Char.ofNat v))
        | none => throw "truncated \\xXX escape in string literal"
      | 'u' => match unescapeHex 4 rest 0 with
        | some v => do go (rest.drop 4) (acc.push (← unescapeCode v "\\u"))
        | none => throw "truncated \\uXXXX escape in string literal"
      | 'U' => match unescapeHex 8 rest 0 with
        | some v => do go (rest.drop 8) (acc.push (← unescapeCode v "\\U"))
        | none => throw "truncated \\UXXXXXXXX escape in string literal"
      | 'N' => throw "\\N{...} escapes (Unicode character names) are not supported by HALean"
      | other =>
        if '0' ≤ other && other ≤ '7' then
          let (v, k) := unescapeOctal 2 rest (other.toNat - '0'.toNat)
          go (rest.drop k) (acc.push (Char.ofNat v))
        else go rest (acc.push '\\' |>.push other)  -- unknown escapes are kept
    | c :: rest, acc => go rest (acc.push c)
  termination_by cs => cs.length
  decreasing_by all_goals (simp only [List.length_drop, List.length_cons]; omega)
  go cs ""

/-- `d(_?d)*` at the head of `cs`, for a digit class `isD`, with an optional
leading underscore: (the matched characters, the rest). -/
def digitRun (isD : Char → Bool) : List Char → List Char × List Char
  | '_' :: d :: rest =>
    if isD d then let (m, r) := digitRun isD rest; ('_' :: d :: m, r) else ([], '_' :: d :: rest)
  | c :: rest => if isD c then let (m, r) := digitRun isD rest; (c :: m, r) else ([], c :: rest)
  | [] => ([], [])

/-- `(\d+_)*\d+` at the head: digits with single underscores between them. -/
def digitGroups (cs : List Char) : Option (List Char × List Char) :=
  match cs with
  | d :: _ => if d.isDigit then some (digitRun Char.isDigit cs) else none
  | [] => none

/-- Jinja's `float_re` at the head of `cs` (a digit): digit groups, then an
exponent with an optional fraction, or a fraction. -/
def lexFloat (cs : List Char) : Option (List Char × List Char) := do
  let (ip, r1) ← digitGroups cs
  let frac (r : List Char) : Option (List Char × List Char) := match r with
    | '.' :: r' => (digitGroups r').map fun (f, r'') => ('.' :: f, r'')
    | _ => none
  let expo (r : List Char) : Option (List Char × List Char) := match r with
    | e :: r' =>
      if e == 'e' || e == 'E' then
        let (sg, r'') := match r' with
          | '+' :: x => (['+'], x)
          | '-' :: x => (['-'], x)
          | x => ([], x)
        (digitGroups r'').map fun (ds, r3) => (e :: sg ++ ds, r3)
      else none
    | [] => none
  match frac r1 with
  | some (f, r2) => match expo r2 with
    | some (ex, r3) => some (ip ++ f ++ ex, r3)
    | none => match expo r1 with
      | some (ex, r3) => some (ip ++ ex, r3)
      | none => some (ip ++ f, r2)
  | none => (expo r1).map fun (ex, r3) => (ip ++ ex, r3)

/-- Jinja's `integer_re` at a digit `c`: `0b`/`0o`/`0x` literals (case
insensitive, underscores allowed), a decimal without leading zero, or zeros
(`0(_?0)*`). So `007` lexes as `00` followed by `7`. -/
def lexInt (c : Char) (rest : List Char) : Int × List Char :=
  let based (base : Nat) (isD : Char → Bool) : Option (Int × List Char) :=
    match rest with
    | p :: r =>
      let (ds, r') := digitRun isD r
      let marker := if base == 2 then 'b' else if base == 8 then 'o' else 'x'
      if c == '0' && p.toLower == marker && ds.any (· != '_') then
        some ((ds.filter (· != '_')).foldl (fun n d => n * base + ((hexVal d).getD 0 : Int)) 0, r')
      else none
    | [] => none
  match based 2 (fun d => d == '0' || d == '1') with
  | some x => x
  | none => match based 8 (fun d => '0' ≤ d && d ≤ '7') with
    | some x => x
    | none => match based 16 (fun d => (hexVal d).isSome) with
      | some x => x
      | none =>
        let (ds, r) := digitRun (if c == '0' then (· == '0') else Char.isDigit) rest
        ((digitValue (c :: ds) : Nat), r)

/-- Lex one `{{ }}` / `{% %}` body. Returns tokens and the rest after the
closing delimiter, plus whether it ended with `-` (strip following space). -/
partial def lexBlock (closer : Char) (cs : List Char) (acc : Array Tok) (prevDot : Bool := false) :
    P (List Tok × List Char × Bool) :=
  -- Jinja only ends a block when no bracket is open (`{{ {'a': 1}}}`)
  let depth : Int := acc.foldl (fun d t => match t with
    | .op "(" | .op "[" | .op "{" => d + 1
    | .op ")" | .op "]" | .op "}" => d - 1
    | _ => d) 0
  match cs with
  | [] => throw "unexpected end of template, expected a closing delimiter"
  | c :: rest =>
    if c.isWhitespace then lexBlock closer rest acc
    else if depth ≤ 0 && c == '-' && rest.take 2 == [closer, '}'] then pure (acc.toList, rest.drop 2, true)
    else if depth ≤ 0 && c == closer && rest.head? == some '}' then pure (acc.toList, rest.drop 1, false)
    else if isNameStart c then
      let name := (c :: rest).takeWhile isNameChar
      lexBlock closer ((c :: rest).drop name.length) (acc.push (.name (String.ofList name)))
    else if c.isDigit then
      -- Jinja tries `float_re` (not right after a `.`), then `integer_re`
      match (if prevDot then none else lexFloat (c :: rest)) with
      | some (txt, r) =>
        match parseFloatStr (String.ofList (txt.filter (· != '_'))) with
        | some f => lexBlock closer r (acc.push (.float f))
        | none => throw s!"invalid number {String.ofList txt}"
      | none =>
        let (i, r) := lexInt c rest
        lexBlock closer r (acc.push (.int i))
    else if c == '\'' || c == '"' then
      let rec str (xs : List Char) (body : Array Char) : P (List Char × List Char) :=
        match xs with
        | [] => throw "unterminated string literal"
        | '\\' :: x :: r => str r (body.push '\\' |>.push x)
        | x :: r => if x == c then pure (body.toList, r) else str r (body.push x)
      match str rest #[] with
      | .ok (body, r) => do
        let s ← unescape body
        lexBlock closer r (acc.push (.str s))
      | .error e => throw e
    else lexOp cs
where
  lexOp (cs : List Char) : P (List Tok × List Char × Bool) :=
    let ops := ["//", "**", "==", "!=", "<=", ">=", "+", "-", "*", "/", "%", "~", "<", ">",
                "(", ")", "[", "]", "{", "}", ",", ":", ".", "|", "="]
    match ops.find? (fun o => (String.ofList (cs.take o.length)) == o) with
    | some o => lexBlock closer (cs.drop o.length) (acc.push (.op o)) (o == ".")
    | none => throw s!"unexpected character '{cs.headD ' '}' in template"

def stripRight (s : String) : String := String.ofList (s.toList.reverse.dropWhile Char.isWhitespace).reverse
def dropLeadingWs (cs : List Char) : List Char := cs.dropWhile Char.isWhitespace

/-- Split a template into text, `{{ }}` and `{% %}` pieces (comments dropped),
applying `-` whitespace control. -/
partial def lexTemplate (src : String) : P (List Piece) :=
  let rec go (cs : List Char) (text : Array Char) (acc : Array Piece) (lstrip : Bool) : P (List Piece) :=
    let flush (strip : Bool) : Array Piece :=
      let t := String.ofList text.toList
      let t := if strip then stripRight t else t
      if t.isEmpty then acc else acc.push (.text t)
    match cs with
    | [] => pure (flush false).toList
    | '{' :: '{' :: rest =>
      let (strip, rest) := match rest with | '-' :: r => (true, r) | r => (false, r)
      match lexBlock '}' rest #[] with
      | .ok (toks, r, ws) => go (if ws then dropLeadingWs r else r) #[] ((flush strip).push (.expr toks)) false
      | .error e => throw e
    | '{' :: '%' :: rest =>
      let (strip, rest) := match rest with | '-' :: r => (true, r) | '+' :: r => (false, r) | r => (false, r)
      match lexBlock '%' rest #[] with
      | .ok (toks, r, ws) => go (if ws then dropLeadingWs r else r) #[] ((flush strip).push (.stmt toks)) false
      | .error e => throw e
    | '{' :: '#' :: rest =>
      let (strip, rest) := match rest with | '-' :: r => (true, r) | r => (false, r)
      let rec skip : List Char → P (List Char × Bool)
        | [] => throw "unterminated comment"
        | '-' :: '#' :: '}' :: r => pure (r, true)
        | '#' :: '}' :: r => pure (r, false)
        | _ :: r => skip r
      match skip rest with
      | .ok (r, ws) => go (if ws then dropLeadingWs r else r) #[] (flush strip) false
      | .error e => throw e
    | c :: rest => go rest (text.push c) acc lstrip
  go src.toList #[] #[] false

/-! ## Expression parser -/

abbrev PS := StateT (List Tok) P

def peek : PS (Option Tok) := return (← get).head?
def peek2 : PS (Option Tok) := return ((← get).drop 1).head?
def advance : PS Unit := modify (·.drop 1)

def isOp (o : String) : PS Bool := return (← peek) == some (.op o)
def isName (n : String) : PS Bool := return (← peek) == some (.name n)

def expectOp (o : String) : PS Unit := do
  match ← peek with
  | some (.op x) => if x == o then advance else throw s!"expected '{o}', got '{x}'"
  | some t => throw s!"expected '{o}', got '{t}'"
  | none => throw s!"expected '{o}', got end of block"

def expectName : PS String := do
  match ← peek with
  | some (.name n) => advance; pure n
  | some t => throw s!"expected a name, got '{t}'"
  | none => throw "expected a name, got end of block"

def expectKw (k : String) : PS Unit := do
  if ← isName k then advance else throw s!"expected '{k}'"

/-- Tokens that can start a test argument without parentheses
(`x is divisibleby 3`). -/
def startsPrimary : Option Tok → Bool
  | some (.name n) => !["else", "or", "and"].contains n
  | some (.str _) | some (.int _) | some (.float _) => true
  | some (.op o) => ["(", "[", "{"].contains o
  | _ => false

mutual
partial def parseExpr (withCond : Bool := true) : PS Expr := do
  if withCond then parseCondExpr else parseOr

partial def parseCondExpr : PS Expr := do
  let e ← parseOr
  let mut e := e
  while ← isName "if" do
    advance
    let c ← parseOr
    if ← isName "else" then
      advance
      let b ← parseCondExpr
      e := .cond c e (some b)
    else e := .cond c e none
  return e

partial def parseOr : PS Expr := do
  let mut e ← parseAnd
  while ← isName "or" do advance; e := .or e (← parseAnd)
  return e

partial def parseAnd : PS Expr := do
  let mut e ← parseNot
  while ← isName "and" do advance; e := .and e (← parseNot)
  return e

partial def parseNot : PS Expr := do
  if ← isName "not" then advance; return .not (← parseNot)
  parseCompare

partial def parseCompare : PS Expr := do
  let e ← parseMath1
  let mut ops : Array (String × Expr) := #[]
  repeat
    match ← peek with
    | some (.op o) =>
      if ["==", "!=", "<", "<=", ">", ">="].contains o then
        advance; ops := ops.push (o, ← parseMath1)
      else break
    | some (.name "in") => advance; ops := ops.push ("in", ← parseMath1)
    | some (.name "not") =>
      if (← peek2) == some (.name "in") then
        advance; advance; ops := ops.push ("notin", ← parseMath1)
      else break
    | _ => break
  return if ops.isEmpty then e else .compare e ops.toList

partial def parseMath1 : PS Expr := do
  let mut e ← parseConcat
  repeat
    match ← peek with
    | some (.op "+") => advance; e := .binop "+" e (← parseConcat)
    | some (.op "-") => advance; e := .binop "-" e (← parseConcat)
    | _ => break
  return e

partial def parseConcat : PS Expr := do
  let mut e ← parseMath2
  while ← isOp "~" do advance; e := .concat e (← parseMath2)
  return e

partial def parseMath2 : PS Expr := do
  let mut e ← parsePow
  repeat
    match ← peek with
    | some (.op o) =>
      if ["*", "/", "//", "%"].contains o then advance; e := .binop o e (← parsePow)
      else break
    | _ => break
  return e

partial def parsePow : PS Expr := do
  let mut e ← parseUnary
  while ← isOp "**" do advance; e := .binop "**" e (← parseUnary)
  return e

partial def parseUnary (withFilter : Bool := true) : PS Expr := do
  let e ← match ← peek with
    | some (.op "-") => do advance; pure (Expr.neg (← parseUnary false))
    | some (.op "+") => do advance; pure (Expr.pos (← parseUnary false))
    | _ => do parsePostfix (← parsePrimary)
  if withFilter then parseFilterExpr e else pure e

partial def parsePrimary : PS Expr := do
  match ← peek with
  | some (.name n) =>
    advance
    match n with
    | "true" | "True" => pure (.lit (.bool true))
    | "false" | "False" => pure (.lit (.bool false))
    | "none" | "None" => pure (.lit .none)
    | _ => pure (.name n)
  | some (.str s) =>
    advance
    -- adjacent string literals are concatenated
    let mut s := s
    repeat
      match ← peek with
      | some (.str t) => advance; s := s ++ t
      | _ => break
    pure (.lit (.str s))
  | some (.int i) => advance; pure (.lit (.int i))
  | some (.float f) => advance; pure (.lit (.float f))
  | some (.op "(") =>
    advance
    if ← isOp ")" then advance; return .tuple []
    let e ← parseTuple
    expectOp ")"
    pure e
  | some (.op "[") =>
    advance
    let mut xs : Array Expr := #[]
    while !(← isOp "]") do
      if !xs.isEmpty then expectOp ","
      if ← isOp "]" then break
      xs := xs.push (← parseExpr)
    expectOp "]"
    pure (.list xs.toList)
  | some (.op "{") =>
    advance
    let mut kvs : Array (Expr × Expr) := #[]
    while !(← isOp "}") do
      if !kvs.isEmpty then expectOp ","
      if ← isOp "}" then break
      let k ← parseExpr
      expectOp ":"
      kvs := kvs.push (k, ← parseExpr)
    expectOp "}"
    pure (.dict kvs.toList)
  | some t => throw s!"unexpected '{t}'"
  | none => throw "unexpected end of expression"

/-- `a, b` inside parentheses or at the top of `{{ }}`. -/
partial def parseTuple : PS Expr := do
  let first ← parseExpr
  if !(← isOp ",") then return first
  let mut xs := #[first]
  while ← isOp "," do
    advance
    match ← peek with
    | some (.op ")") | some .close | none => break
    | _ => xs := xs.push (← parseExpr)
  return .tuple xs.toList

partial def parseArgs : PS (List Expr × List (String × Expr)) := do
  expectOp "("
  let mut args : Array Expr := #[]
  let mut kwargs : Array (String × Expr) := #[]
  while !(← isOp ")") do
    if !args.isEmpty || !kwargs.isEmpty then expectOp ","
    if ← isOp ")" then break
    match ← peek, ← peek2 with
    | some (.name k), some (.op "=") =>
      advance; advance; kwargs := kwargs.push (k, ← parseExpr)
    | _, _ =>
      if !kwargs.isEmpty then throw "positional argument follows keyword argument"
      args := args.push (← parseExpr)
  expectOp ")"
  return (args.toList, kwargs.toList)

partial def parseSubscript : PS Expr := do
  -- `[a]`, `[a:b]`, `[a:b:c]`, `[:b]`, ...
  let part : PS (Option Expr) := do
    match ← peek with
    | some (.op ":") | some (.op "]") => pure none
    | _ => some <$> parseExpr
  let a ← part
  if !(← isOp ":") then
    match a with
    | some e => return e
    | none => throw "expected a subscript"
  advance
  let b ← part
  let c ← if ← isOp ":" then do advance; part else pure none
  return .slice (.lit .none) a b c  -- placeholder target, filled by the caller

partial def parsePostfix (e : Expr) : PS Expr := do
  let mut e := e
  repeat
    match ← peek with
    | some (.op ".") =>
      advance
      match ← peek with
      | some (.name n) => advance; e := .getattr e n
      | some (.int i) => advance; e := .getitem e (.lit (.int i))
      | _ => throw "expected an attribute name after '.'"
    | some (.op "[") =>
      advance
      let s ← parseSubscript
      expectOp "]"
      e := match s with
        | .slice _ a b c => .slice e a b c
        | k => .getitem e k
    | some (.op "(") =>
      let (args, kwargs) ← parseArgs
      e := .call e args kwargs
    | _ => break
  return e

partial def parseFilterExpr (e : Expr) : PS Expr := do
  let mut e := e
  repeat
    match ← peek with
    | some (.op "|") =>
      advance
      let mut n ← expectName
      while ← isOp "." do advance; n := n ++ "." ++ (← expectName)
      let (args, kwargs) ← if ← isOp "(" then parseArgs else pure ([], [])
      e := .filter e n args kwargs
    | some (.name "is") =>
      advance
      let negated ← if ← isName "not" then do advance; pure true else pure false
      let mut n ← expectName
      while ← isOp "." do advance; n := n ++ "." ++ (← expectName)
      let args ← if ← isOp "(" then do pure (← parseArgs).1
        else if startsPrimary (← peek) then do
          let a ← parsePostfix (← parsePrimary)
          pure [a]
        else pure []
      e := .test e n args negated
    | some (.op "(") =>
      let (args, kwargs) ← parseArgs
      e := .call e args kwargs
    | _ => break
  return e
end

def runExpr (p : PS α) (toks : List Tok) : P α := do
  let (a, rest) ← p.run toks
  match rest with
  | [] => pure a
  | t :: _ => throw s!"unexpected '{t}' at the end of the expression"

/-! ## Statements -/

inductive Stmt where
  | ifS (c : Expr) | elifS (c : Expr) | elseS | endifS
  | forS (targets : List String) (iter : Expr) (filter : Option Expr) | endforS
  | setS (targets : List String) (e : Expr)
  | setAttrS (obj attr : String) (e : Expr)
  | brkS | contS
  deriving Inhabited

def parseTargets : PS (List String) := do
  let mut ts := #[← expectName]
  while ← isOp "," do advance; ts := ts.push (← expectName)
  return ts.toList

def parseStmt (toks : List Tok) : P Stmt := do
  match toks with
  | .name "if" :: rest => return .ifS (← runExpr parseTuple rest)
  | .name "elif" :: rest => return .elifS (← runExpr parseTuple rest)
  | [.name "else"] => return .elseS
  | [.name "endif"] => return .endifS
  | [.name "endfor"] => return .endforS
  | [.name "break"] => return .brkS
  | [.name "continue"] => return .contS
  | .name "for" :: rest =>
    runExpr (do
      let ts ← parseTargets
      expectKw "in"
      -- `for x in xs if cond`: the iterable is parsed without `if`
      let it ← parseExpr (withCond := false)
      let it ← if ← isOp "," then do
          let mut xs := #[it]
          while ← isOp "," do advance; xs := xs.push (← parseExpr false)
          pure (Expr.tuple xs.toList)
        else pure it
      let f ← if ← isName "if" then do advance; some <$> parseExpr else pure none
      if ← isName "recursive" then throw "recursive loops are not supported by HALean"
      return Stmt.forS ts it f) rest
  | .name "set" :: .name obj :: .op "." :: .name attr :: .op "=" :: rest =>
    return .setAttrS obj attr (← runExpr parseTuple rest)
  | .name "set" :: rest =>
    runExpr (do
      let ts ← parseTargets
      if !(← isOp "=") then throw "block {% set %} is not supported by HALean"
      advance
      return Stmt.setS ts (← parseTuple)) rest
  | .name kw :: _ => throw s!"the '{kw}' tag is not supported by HALean"
  | _ => throw "empty or invalid statement"

/-- Build the node tree from the flat piece list. Returns the nodes up to a
terminating statement (one of `stops`) and that statement. -/
partial def buildNodes (ps : List Piece) (stops : List String) :
    P (List Node × Option Stmt × List Piece) := do
  let mut acc : Array Node := #[]
  let mut ps := ps
  repeat
    match ps with
    | [] =>
      if stops.isEmpty then return (acc.toList, none, [])
      else throw s!"unexpected end of template, expected one of {stops}"
    | .text t :: rest => acc := acc.push (.text t); ps := rest
    | .expr toks :: rest =>
      acc := acc.push (.output (← runExpr parseTuple toks)); ps := rest
    | .stmt toks :: rest =>
      let s ← parseStmt toks
      let kw := match s with
        | .elifS _ => "elif" | .elseS => "else" | .endifS => "endif" | .endforS => "endfor"
        | _ => ""
      if kw != "" then
        if stops.contains kw then return (acc.toList, some s, rest)
        else throw s!"unexpected '{kw}'"
      match s with
      | .ifS c =>
        let mut branches : Array (Expr × List Node) := #[]
        let mut cond := c
        let mut rest' := rest
        let mut elseBody : List Node := []
        repeat
          let (body, stop, r) ← buildNodes rest' ["elif", "else", "endif"]
          branches := branches.push (cond, body)
          rest' := r
          match stop with
          | some (.elifS c') => cond := c'
          | some .elseS =>
            let (eb, _, r2) ← buildNodes r ["endif"]
            elseBody := eb; rest' := r2; break
          | _ => break
        acc := acc.push (.ifs branches.toList elseBody); ps := rest'
      | .forS ts it f =>
        let (body, stop, r) ← buildNodes rest ["else", "endfor"]
        let (eb, r) ← match stop with
          | some .elseS => do let (eb, _, r2) ← buildNodes r ["endfor"]; pure (eb, r2)
          | _ => pure ([], r)
        acc := acc.push (.for ts it f body eb); ps := r
      | .setS ts e => acc := acc.push (.set ts e); ps := rest
      | .setAttrS o a e => acc := acc.push (.setAttr o a e); ps := rest
      | .brkS => acc := acc.push .brk; ps := rest
      | .contS => acc := acc.push .cont; ps := rest
      | _ => throw "unexpected statement"
  return (acc.toList, none, ps)

/-- A compiled template. `isStatic` mirrors `Template.is_static`
(`not is_template_string(template)`). -/
structure Tmpl where
  src : String
  isStatic : Bool
  nodes : List Node
  deriving Inhabited

/-- A `{` directly followed by `%`, `{` or `#`. -/
def hasJinjaOpen : List Char → Bool
  | '{' :: c :: rest => c == '%' || c == '{' || c == '#' || hasJinjaOpen (c :: rest)
  | _ :: rest => hasJinjaOpen rest
  | [] => false

/-- `is_template_string`: `"{" in s and ("{%" in s or "{{" in s or "{#" in s)`.
Proved: `HALean.Template.isTemplateString_iff`. -/
def isTemplateString (s : String) : Bool := hasJinjaOpen s.toList

/-- Jinja drops a single trailing newline (`keep_trailing_newline=False`). -/
def dropTrailingNewline (s : String) : String :=
  if s.endsWith "\r\n" then (s.dropEnd 2).toString
  else if s.endsWith "\n" || s.endsWith "\r" then (s.dropEnd 1).toString else s

/-- `Template.__init__` (`self.template = template.strip()`) + `_ensure_compiled`.
`is_static` is decided on the unstripped text, as upstream does. -/
def compile (raw : String) : P Tmpl := do
  let src := raw.trim
  if !isTemplateString raw then return { src, isStatic := true, nodes := [.text src] }
  -- `Lexer.tokeniter` joins the source's lines with "\n" (`\r\n` and `\r`
  -- become `\n`) and drops one trailing newline
  let pieces ← lexTemplate (dropTrailingNewline ((src.replace "\r\n" "\n").replace "\r" "\n"))
  let (nodes, _, _) ← buildNodes pieces []
  return { src, isStatic := false, nodes }

end HALean.Template
