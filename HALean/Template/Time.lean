/-
  Python's `datetime` and `timedelta`, as far as Home Assistant templates use
  them: the proleptic Gregorian calendar, `isoformat`, `str(timedelta)`, and
  `strftime` as glibc implements it (HA runs on Linux, C locale).

  A datetime is microseconds since the Unix epoch plus an optional UTC offset
  in seconds. Aware datetimes store the instant (UTC); naive ones store their
  wall-clock time as if it were UTC.
-/
namespace HALean.Template

def US_PER_SEC : Int := 1000000
def US_PER_DAY : Int := 86400 * US_PER_SEC

/-- `(year, month, day)` of a day number (days since 1970-01-01).
Howard Hinnant's `civil_from_days`. -/
def civilFromDays (z : Int) : Int × Nat × Nat :=
  let z := z + 719468
  let era := (if z ≥ 0 then z else z - 146096) / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y := yoe + era * 400
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  ((if m ≤ 2 then y + 1 else y), m.toNat, d.toNat)

/-- Day number of a civil date. Hinnant's `days_from_civil`. -/
def daysFromCivil (y : Int) (m d : Nat) : Int :=
  let y := if m ≤ 2 then y - 1 else y
  let era := (if y ≥ 0 then y else y - 399) / 400
  let yoe := y - era * 400
  let mi : Int := m
  let doy := (153 * (if mi > 2 then mi - 3 else mi + 9) + 2) / 5 + d - 1
  let doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

def isLeap (y : Int) : Bool := (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

def daysInMonth (y : Int) (m : Nat) : Nat :=
  match m with
  | 2 => if isLeap y then 29 else 28
  | 4 | 6 | 9 | 11 => 30
  | _ => 31

structure Civil where
  year : Int
  month : Nat
  day : Nat
  hour : Nat
  minute : Nat
  second : Nat
  micro : Nat
  deriving Repr, BEq

/-- Floor division and modulo (Python's `divmod`). -/
def fdivmod (a b : Int) : Int × Int := (Int.fdiv a b, Int.fmod a b)

def toCivil (wall : Int) : Civil :=
  let (days, rem) := fdivmod wall US_PER_DAY
  let (y, m, d) := civilFromDays days
  let rem := rem.toNat
  { year := y, month := m, day := d,
    hour := rem / 3600000000, minute := rem / 60000000 % 60, second := rem / 1000000 % 60,
    micro := rem % 1000000 }

def fromCivil (c : Civil) : Int :=
  daysFromCivil c.year c.month c.day * US_PER_DAY
    + ((c.hour * 3600 + c.minute * 60 + c.second : Nat) : Int) * US_PER_SEC + c.micro

/-- The `datetime` constructor's range checks. -/
def Civil.valid (c : Civil) : Option String :=
  if c.year < 1 || c.year > 9999 then some s!"year {c.year} is out of range"
  else if c.month < 1 || c.month > 12 then some "month must be in 1..12"
  else if c.day < 1 || c.day > daysInMonth c.year c.month then some "day is out of range for month"
  else if c.hour > 23 then some "hour must be in 0..23"
  else if c.minute > 59 then some "minute must be in 0..59"
  else if c.second > 59 then some "second must be in 0..59"
  else if c.micro > 999999 then some "microsecond must be in 0..999999"
  else none

/-- The wall-clock microseconds of a datetime. -/
def wallOf (us : Int) (off : Option Int) : Int :=
  us + (off.getD 0) * US_PER_SEC

/-- Python `weekday()`: Monday = 0. 1970-01-01 was a Thursday. -/
def weekdayOf (wall : Int) : Nat := ((Int.fdiv wall US_PER_DAY + 3) % 7).toNat

def pad0 (n : Nat) (w : Nat) : String :=
  let s := toString n
  "".pushn '0' (w - s.length) ++ s

def padYear (y : Int) : String := if y < 0 then toString y else pad0 y.toNat 4

/-- `+HH:MM` (and `:SS` when the offset has seconds), as `isoformat` prints it. -/
def offsetStr (off : Int) (colon : Bool := true) : String :=
  let sign := if off < 0 then "-" else "+"
  let a := off.natAbs
  let base := pad0 (a / 3600) 2 ++ (if colon then ":" else "") ++ pad0 (a / 60 % 60) 2
  sign ++ base ++ (if a % 60 != 0 then (if colon then ":" else "") ++ pad0 (a % 60) 2 else "")

/-- `datetime.isoformat(sep)` -/
def isoformat (us : Int) (off : Option Int) (sep : String := "T") : String :=
  let c := toCivil (wallOf us off)
  padYear c.year ++ "-" ++ pad0 c.month 2 ++ "-" ++ pad0 c.day 2 ++ sep
    ++ pad0 c.hour 2 ++ ":" ++ pad0 c.minute 2 ++ ":" ++ pad0 c.second 2
    ++ (if c.micro != 0 then "." ++ pad0 c.micro 6 else "")
    ++ (match off with | some o => offsetStr o | none => "")

/-- `timedelta`'s normalised `(days, seconds, microseconds)`. -/
def tdParts (us : Int) : Int × Nat × Nat :=
  let (d, rem) := fdivmod us US_PER_DAY
  (d, (rem / US_PER_SEC).toNat, (rem % US_PER_SEC).toNat)

/-- `str(timedelta)` -/
def tdStr (us : Int) : String :=
  let (d, s, u) := tdParts us
  let hms := toString (s / 3600) ++ ":" ++ pad0 (s / 60 % 60) 2 ++ ":" ++ pad0 (s % 60) 2
  let dayPart := if d != 0 then s!"{d} day{if d.natAbs != 1 then "s" else ""}, " else ""
  dayPart ++ hms ++ (if u != 0 then "." ++ pad0 u 6 else "")

/-- `repr(timedelta)` -/
def tdRepr (us : Int) : String :=
  let (d, s, u) := tdParts us
  let parts := (if d != 0 then [s!"days={d}"] else []) ++ (if s != 0 then [s!"seconds={s}"] else [])
    ++ (if u != 0 then [s!"microseconds={u}"] else [])
  "datetime.timedelta(" ++ (if parts.isEmpty then "0" else ", ".intercalate parts) ++ ")"

def DAY_ABBR : List String := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
def DAY_FULL : List String := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
def MON_ABBR : List String := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
def MON_FULL : List String := ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]

/-- `datetime.strftime` with glibc's directives in the C locale. Directives
HALean does not implement are errors, never guesses. -/
partial def strftime (us : Int) (off : Option Int) (fmt : String) : Except String String := do
  let wall := wallOf us off
  let c := toCivil wall
  let wd := weekdayOf wall
  let yday := (daysFromCivil c.year c.month c.day - daysFromCivil c.year 1 1 + 1).toNat
  let h12 := if c.hour % 12 == 0 then 12 else c.hour % 12
  let num (pad : Bool) (n : Nat) (w : Nat) : String := if pad then pad0 n w else toString n
  let rec go : List Char → String → Except String String
    | [], acc => pure acc
    | '%' :: rest, acc => do
      let (pad, rest) := match rest with
        | '-' :: r => (false, r)
        | r => (true, r)
      match rest with
      | [] => pure (acc ++ "%")
      | d :: r =>
        let piece : Except String String := match d with
          | 'a' => pure (DAY_ABBR.getD wd "")
          | 'A' => pure (DAY_FULL.getD wd "")
          | 'b' | 'h' => pure (MON_ABBR.getD (c.month - 1) "")
          | 'B' => pure (MON_FULL.getD (c.month - 1) "")
          | 'd' => pure (num pad c.day 2)
          | 'e' => pure (if pad then (if c.day < 10 then " " else "") ++ toString c.day else toString c.day)
          | 'H' => pure (num pad c.hour 2)
          | 'I' => pure (num pad h12 2)
          | 'j' => pure (num pad yday 3)
          | 'm' => pure (num pad c.month 2)
          | 'M' => pure (num pad c.minute 2)
          | 'S' => pure (num pad c.second 2)
          | 'p' => pure (if c.hour < 12 then "AM" else "PM")
          | 'y' => pure (num pad (Int.fmod c.year 100).toNat 2)
          | 'Y' => pure (toString c.year)
          | 'f' => pure (pad0 c.micro 6)
          | 'w' => pure (toString ((wd + 1) % 7))
          | 'u' => pure (toString (wd + 1))
          | 'z' => pure (match off with | some o => offsetStr o false | none => "")
          | 'F' => pure (toString c.year ++ "-" ++ pad0 c.month 2 ++ "-" ++ pad0 c.day 2)
          | 'T' => pure (pad0 c.hour 2 ++ ":" ++ pad0 c.minute 2 ++ ":" ++ pad0 c.second 2)
          | 'R' => pure (pad0 c.hour 2 ++ ":" ++ pad0 c.minute 2)
          | 'D' => pure (pad0 c.month 2 ++ "/" ++ pad0 c.day 2 ++ "/" ++ pad0 (Int.fmod c.year 100).toNat 2)
          | 'n' => pure "\n"
          | 't' => pure "\t"
          | '%' => pure "%"
          | 'Z' => match off with
            | none => pure ""
            | some _ => throw "strftime %Z (time zone names) is not supported by HALean"
          | x => throw s!"strftime directive %{x} is not supported by HALean"
        go r (acc ++ (← piece))
    | ch :: rest, acc => go rest (acc.push ch)
  go fmt.toList ""

end HALean.Template
