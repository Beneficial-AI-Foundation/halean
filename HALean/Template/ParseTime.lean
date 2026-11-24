/-
  `dt_util.parse_time`, shared by templates and automation configs
  (`cv.time`). Proved in `HALean/Template/ParseTimeSpec.lean`.
-/
import HALean.Template.PyInt

namespace HALean.Template

/-- `int(parts[2]) if len(parts) > 2 else 0` of `parse_time`, given the parts
after the minutes. -/
def parseTimeSecond : List (List Char) → Option Int
  | [] => some 0
  | p2 :: _ => parseIntChars p2

/-- `dt_util.parse_time` (what `cv.time` does with a string), as seconds
since midnight: `str.split(":")`, at least two parts, `int()` of the first
two and of the third if there is one (later parts are ignored), then
`datetime.time(hour, minute, second)`; `None` on a `ValueError`. Proved:
`HALean.Template.parseTimeSeconds_iff`. Non-ASCII text (where Python's `int()`
also takes other digits) gives `none`. -/
def parseTimeSeconds (s : String) : Option Nat :=
  match s.toList.splitOn ':' with
  | p0 :: p1 :: rest => do
    let h ← parseIntChars p0
    let m ← parseIntChars p1
    let sec ← parseTimeSecond rest
    if 0 ≤ h ∧ h < 24 ∧ 0 ≤ m ∧ m < 60 ∧ 0 ≤ sec ∧ sec < 60 then
      some (h * 3600 + m * 60 + sec).toNat
    else none
  | _ => none

end HALean.Template
