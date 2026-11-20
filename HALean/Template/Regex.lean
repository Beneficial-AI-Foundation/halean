/-
  A small backtracking regular-expression matcher with Python `re`'s
  semantics for the constructs HALean's translated patterns use: character
  classes, sequences, ordered alternation, greedy bounded/unbounded
  repetition, named groups, positive lookahead and `$`.

  Patterns are written as `Rx` terms rather than parsed from strings; each
  one is a hand translation of an upstream regex, kept next to its source
  text. Matching is `re.match`: anchored at the start, the first match in
  backtracking order, not necessarily consuming the whole input.
-/
namespace HALean.Template

inductive Rx where
  /-- One character satisfying the predicate. -/
  | cls (p : Char → Bool)
  | seq (xs : List Rx)
  /-- `a|b|...`, tried left to right. -/
  | alt (xs : List Rx)
  /-- Greedy `r{lo,hi}` (`hi = none`: unbounded). -/
  | rep (r : Rx) (lo : Nat) (hi : Option Nat)
  /-- `(?P<name>r)` -/
  | group (name : String) (r : Rx)
  /-- `(?=r)` (atomic, as in Python) -/
  | ahead (r : Rx)
  /-- `$` without MULTILINE: end of input, or before a final newline. -/
  | eol

namespace Rx

/-- Captured groups, most recent first. -/
abbrev Caps := List (String × String)

partial def run {α : Type} (r : Rx) (s : List Char) (caps : Caps)
    (k : List Char → Caps → Option α) : Option α :=
  match r with
  | .cls p => match s with
    | c :: t => if p c then k t caps else none
    | [] => none
  | .seq [] => k s caps
  | .seq (x :: xs) => run x s caps (fun s' c' => run (.seq xs) s' c' k)
  | .alt [] => none
  | .alt (x :: xs) => (run x s caps k).orElse (fun _ => run (.alt xs) s caps k)
  | .rep x lo hi =>
    if lo > 0 then run x s caps (fun s' c' => run (.rep x (lo - 1) (hi.map (· - 1))) s' c' k)
    else if hi == some 0 then k s caps
    else
      (run x s caps (fun s' c' =>
          if s'.length == s.length then none else run (.rep x 0 (hi.map (· - 1))) s' c' k)).orElse
        (fun _ => k s caps)
  | .group n x => run x s caps (fun s' c' => k s' ((n, String.ofList (s.take (s.length - s'.length))) :: c'))
  | .ahead x => match run x s caps (fun _ c => some c) with
    | some _ => k s caps
    | none => none
  | .eol => match s with
    | [] | ['\n'] => k s caps
    | _ => none

/-- `re.match`: the unmatched rest of the input and the groups. -/
def matchPrefix (r : Rx) (s : String) : Option (List Char × Caps) :=
  run r s.toList [] (fun rest c => some (rest, c))

/-- The value of a named group, `none` if it did not participate. -/
def Caps.get? (c : Caps) (n : String) : Option String := (c.find? (·.1 == n)).map (·.2)

def ch (c : Char) : Rx := .cls (· == c)
def oneOf (cs : String) : Rx := .cls (fun c => cs.toList.contains c)
/-- `\d` on ASCII input. -/
def digit : Rx := .cls Char.isDigit
def range (a b : Char) : Rx := .cls (fun c => a ≤ c && c ≤ b)
def lit (s : String) : Rx := .seq (s.toList.map ch)
def opt (r : Rx) : Rx := .rep r 0 (some 1)
def plus (r : Rx) : Rx := .rep r 1 none
def nTimes (r : Rx) (lo hi : Nat) : Rx := .rep r lo (some hi)

end Rx
end HALean.Template
