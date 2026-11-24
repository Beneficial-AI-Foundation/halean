/-
  `cv.boolean` on strings: `value.lower().strip()` among the true / false
  words. Proved in `HALean/Template/CvBooleanSpec.lean` for ASCII text.

  It is exact for all text, by two facts about Unicode (checked
  exhaustively against CPython's `str` methods): `str.isspace()` holds for
  exactly the 29 code points of `pyIsSpace`, and the only non-ASCII
  characters whose `lower()` contains ASCII are U+0130 (to `i` + U+0307, not
  all ASCII) and U+212A KELVIN SIGN (to `k`, in none of the words). So a
  non-ASCII character left after stripping never matches, as here, where
  `Char.toLower` leaves it alone.
-/
import HALean.Template.PyInt

namespace HALean.Template

/-- `str.isspace()`: `\t \n \v \f \r`, `\x1c`-`\x1f`, space, U+0085, U+00A0,
U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000. -/
def pyIsSpace (c : Char) : Bool :=
  let n := c.toNat
  (9 ≤ n && n ≤ 13) || (28 ≤ n && n ≤ 32) || n == 0x85 || n == 0xA0 || n == 0x1680 ||
  (0x2000 ≤ n && n ≤ 0x200A) || n == 0x2028 || n == 0x2029 || n == 0x202F || n == 0x205F || n == 0x3000

def CV_TRUE_WORDS : List String := ["1", "true", "yes", "on", "enable"]
def CV_FALSE_WORDS : List String := ["0", "false", "no", "off", "disable"]

/-- `value.lower().strip()` (ASCII `lower`, see above). -/
def cvBooleanCore (s : String) : String :=
  String.ofList (stripBy pyIsSpace (s.toList.map Char.toLower))

/-- `cv.boolean(s)` for a string: `some b`, or `none` for `Invalid`. -/
def cvBooleanText (s : String) : Option Bool :=
  let t := cvBooleanCore s
  if CV_TRUE_WORDS.contains t then some true
  else if CV_FALSE_WORDS.contains t then some false
  else none

end HALean.Template
