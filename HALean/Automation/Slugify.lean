/-
  `homeassistant.util.slugify` with `separator="_"`: python-slugify's legacy
  pipeline (`slugify._legacy.slugify`, python-slugify 9.1.2) on ASCII text
  without HTML entities, then `"unknown"` for an empty slug. Each step below
  is one line of that pipeline. A regex `[class]+` replaced by `r`
  (`re.sub`, leftmost, greedy, non-overlapping) replaces each maximal run of
  the class with `r` (`subRuns`). Proved in `SlugifySpec.lean`.
-/
import HALean.Template.PyInt

namespace HALean.Automation

/-- Replace each maximal run of characters `p` holds for with `r`
(`re.sub("[...]+", r, text)`); `inRun`: the previous character was in a run. -/
def subRunsAux (p : Char → Bool) (r : List Char) : Bool → List Char → List Char
  | _, [] => []
  | inRun, c :: cs => if p c then (if inRun then [] else r) ++ subRunsAux p r true cs
                      else c :: subRunsAux p r false cs

def subRuns (p : Char → Bool) (r : List Char) (cs : List Char) : List Char :=
  subRunsAux p r false cs

/-- `NUMBERS_PATTERN.sub('', text)` with `(?<=\d),(?=\d)`: drop each comma
whose neighbours in the input are digits (`prev`: the input character
before). -/
def delDigitCommas : Option Char → List Char → List Char
  | _, [] => []
  | prev, c :: cs =>
    if c == ',' && prev.any Char.isDigit && cs.head?.any Char.isDigit then delDigitCommas (some c) cs
    else c :: delDigitCommas (some c) cs

/-- `[^-a-zA-Z0-9]` -/
def slugDisallowed (c : Char) : Bool :=
  !(c == '-' || c.isDigit || ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z'))

/-- The legacy pipeline (lowercase, separator `_`) on ASCII text. -/
def slugifyChars (text : List Char) : List Char :=
  let t := subRuns (· == '\'') ['-'] text            -- QUOTE_PATTERN.sub('-')
  let t := t.map Char.toLower                          -- NFKD (no-op on ASCII), .lower()
  let t := subRuns (· == '\'') [] t                   -- QUOTE_PATTERN.sub('')
  let t := delDigitCommas none t                       -- NUMBERS_PATTERN.sub('')
  let t := subRuns slugDisallowed ['-'] t              -- DISALLOWED_CHARS_PATTERN.sub('-')
  let t := subRuns (· == '-') ['-'] t                  -- DUPLICATE_DASH_PATTERN.sub('-')
  let t := Template.stripBy (· == '-') t               -- .strip('-')
  t.map fun c => if c == '-' then '_' else c           -- .replace('-', '_')

/-- `util.slugify(text)`; `none` for text HALean does not model: non-ASCII
(transliteration) or anything an HTML entity pattern could match. -/
def slugify? (text : String) : Option String := do
  if text.isEmpty then return ""
  if !text.toList.all (fun c : Char => c.toNat < 128) then none
  if text.contains '&' && text.contains ';' then none
  let s := slugifyChars text.toList
  return if s.isEmpty then "unknown" else String.ofList s

end HALean.Automation
