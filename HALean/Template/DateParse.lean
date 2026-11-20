/-
  Parsing and describing dates, times and durations. Translated from:
    * CPython `Lib/_strptime.py` – `TimeRE` (C locale), `_strptime`,
      `_calc_julian_from_U_or_W`, `_strptime_datetime_datetime`, `_parse_tz`
    * CPython `Modules/_datetimemodule.c` – `delta_new` / `accum`
      (`timedelta(...)` with float arguments), `date.fromisocalendar`
    * `homeassistant/util/dt.py` – `parse_duration` (with `STANDARD_DURATION_RE`,
      `ISO8601_DURATION_RE`, `POSTGRES_INTERVAL_RE`), `_get_timestring`,
      `get_age`, `get_time_remaining`, `timedelta_string`

  HALean only reads ASCII here: Python's `\d`, `\s` and case-insensitive
  matching extend to Unicode, which is rejected (a render error) rather
  than approximated.
-/
import HALean.Template.Value
import HALean.Template.Regex

namespace HALean.Template

open Rx

/-- How a Python call failed: `valueError` covers the exceptions HA's
template functions catch (`ValueError`, `TypeError`); anything else is a
render error. -/
inductive PyErr where
  | valueError (msg : String)
  | error (msg : String)
  deriving Inhabited

/-- Whether every character is ASCII. -/
def isAscii (s : String) : Bool := s.toList.all (fun c : Char => c.toNat < 128)

/-- Python `str.rstrip()` (of the spaces `_get_timestring` leaves). -/
def rstripSpaces (s : String) : String := String.ofList (s.toList.reverse.dropWhile (· == ' ')).reverse

/-! ## Numbers -/

private def roundHalfEvenNat (n d : Nat) : Nat :=
  let q := n / d
  let r := n % d
  if 2 * r > d || (2 * r == d && q % 2 == 1) then q + 1 else q

/-- Python `round(x)` for a finite float: the nearest int, ties to even. -/
def pyRoundFloat (f : Float) : Int :=
  let (neg, n, d) := floatFrac f
  let q : Int := roundHalfEvenNat n d
  if neg then -q else q

/-- C `modf`'s integral part. -/
def fTrunc (d : Float) : Float := if d ≥ 0 then d.floor else d.ceil

/-- `timedelta.total_seconds()`: `int / int`, correctly rounded. -/
def tdTotalSeconds (us : Int) : Float := ratToFloat (us < 0) us.natAbs 1000000

/-- `microseconds_to_delta_ex`: `OverflowError` outside the timedelta range. -/
def tdChecked (us : Int) : Except String Int :=
  let days := Int.fdiv us US_PER_DAY
  if days < -999999999 || days > 999999999 then
    throw s!"OverflowError: days={days}; must have magnitude <= 999999999"
  else pure us

/-- CPython's `timedelta.__new__` (`delta_new` with `accum`). `comps` are the
given arguments as `(name, microseconds per unit, value)`, in the order the C
code accumulates them: microseconds, milliseconds, seconds, minutes, hours,
days, weeks. Float parts are split with `modf`, the fraction times the factor
is computed in double precision, and the leftover fractions of a microsecond
are summed and rounded half to even once at the end, exactly as CPython does. -/
def timedeltaNew (comps : List (String × Nat × Value)) : Except PyErr Int := do
  let mut x : Int := 0
  let mut leftover : Float := 0
  for (tag, factor, v) in comps do
    match v with
    | .int i => x := x + i * factor
    | .bool b => x := x + (if b then (factor : Int) else 0)
    | .float d =>
      if d.isNaN then throw (.valueError "cannot convert float NaN to integer")
      if d.isInf then throw (.error "OverflowError: cannot convert float infinity to integer")
      let ip := fTrunc d
      let fp := d - ip
      x := x + (floatToInt? ip).getD 0 * factor
      if fp != 0 then
        let dn := intToFloat factor * fp
        let ip2 := fTrunc dn
        x := x + (floatToInt? ip2).getD 0
        leftover := leftover + (dn - ip2)
    | v => throw (.valueError s!"unsupported type for timedelta {tag} component: {typeName v}")
  if leftover != 0 then
    let mut whole := leftover.round
    if (whole - leftover).abs == 0.5 then
      let odd : Float := if x % 2 == 1 then 1 else 0
      whole := 2.0 * ((leftover + odd) * 0.5).round - odd
    x := x + (floatToInt? whole).getD 0
  match tdChecked x with
  | .ok us => pure us
  | .error e => throw (.error e)

/-! ## `dt_util.parse_duration` -/

/-- `STANDARD_DURATION_RE`:
```
^(?:(?P<days>-?\d+) (days?, )?)?(?P<sign>-?)((?:(?P<hours>\d+):)(?=\d+:\d+))?
(?:(?P<minutes>\d+):)?(?P<seconds>\d+)(?:[\.,](?P<microseconds>\d{1,6})\d{0,6})?$
``` -/
def STANDARD_DURATION_RE : Rx :=
  .seq [
    opt (.seq [.group "days" (.seq [opt (ch '-'), plus digit]), ch ' ',
               opt (.seq [lit "day", opt (ch 's'), lit ", "])]),
    .group "sign" (opt (ch '-')),
    opt (.seq [.group "hours" (plus digit), ch ':', .ahead (.seq [plus digit, ch ':', plus digit])]),
    opt (.seq [.group "minutes" (plus digit), ch ':']),
    .group "seconds" (plus digit),
    opt (.seq [oneOf ".,", .group "microseconds" (nTimes digit 1 6), nTimes digit 0 6]),
    .eol]

/-- `ISO8601_DURATION_RE`:
```
^(?P<sign>[-+]?)P(?:(?P<days>\d+([\.,]\d+)?)D)?(?:T(?:(?P<hours>\d+([\.,]\d+)?)H)?
(?:(?P<minutes>\d+([\.,]\d+)?)M)?(?:(?P<seconds>\d+([\.,]\d+)?)S)?)?$
``` -/
def ISO8601_DURATION_RE : Rx :=
  let num := Rx.seq [plus digit, opt (.seq [oneOf ".,", plus digit])]
  .seq [
    .group "sign" (opt (oneOf "-+")), ch 'P',
    opt (.seq [.group "days" num, ch 'D']),
    opt (.seq [ch 'T',
      opt (.seq [.group "hours" num, ch 'H']),
      opt (.seq [.group "minutes" num, ch 'M']),
      opt (.seq [.group "seconds" num, ch 'S'])]),
    .eol]

/-- `POSTGRES_INTERVAL_RE`:
```
^(?:(?P<days>-?\d+) (days? ?))?(?:(?P<sign>[-+])?(?P<hours>\d+):(?P<minutes>\d\d):
(?P<seconds>\d\d)(?:\.(?P<microseconds>\d{1,6}))?)?$
``` -/
def POSTGRES_INTERVAL_RE : Rx :=
  .seq [
    opt (.seq [.group "days" (.seq [opt (ch '-'), plus digit]), ch ' ', lit "day", opt (ch 's'), opt (ch ' ')]),
    opt (.seq [opt (.group "sign" (oneOf "-+")), .group "hours" (plus digit), ch ':',
               .group "minutes" (.seq [digit, digit]), ch ':', .group "seconds" (.seq [digit, digit]),
               opt (.seq [ch '.', .group "microseconds" (nTimes digit 1 6)])]),
    .eol]

/-- `dt_util.parse_duration`: a timedelta in microseconds, or `none`. -/
def parseDuration (value : String) : Except PyErr (Option Int) := do
  if !isAscii value then
    throw (.error "as_timedelta on non-ASCII text is not supported by HALean")
  let (iso, caps) ← match matchPrefix STANDARD_DURATION_RE value with
    | some (_, c) => pure (false, c)
    | none => match matchPrefix ISO8601_DURATION_RE value with
      | some (_, c) => pure (true, c)
      | none => match matchPrefix POSTGRES_INTERVAL_RE value with
        | some (_, c) => pure (false, c)
        | none => return none
  let sign : Int := if caps.get? "sign" == some "-" then -1 else 1
  let fl (k : String) : Option Value := (caps.get? k).map fun v =>
    let v := if k == "microseconds" && !v.isEmpty then v ++ "".pushn '0' (6 - v.length) else v
    -- `float(v.replace(",", "."))` of `\d+([.,]\d+)?`: always parses
    .float ((parseFloatStr (v.replace "," ".")).getD 0)
  let days ← timedeltaNew [("days", 86400000000, (fl "days").getD (.float 0))]
  let days := if iso then days * sign else days
  let comps := [("microseconds", 1), ("seconds", 1000000), ("minutes", 60000000), ("hours", 3600000000)]
  let rest ← timedeltaNew (comps.filterMap fun (k, f) => (fl k).map fun v => (k, f, v))
  let ck (us : Int) : Except PyErr Int := match tdChecked us with
    | .ok u => pure u
    | .error e => throw (.error e)
  let rest ← ck (sign * rest)
  pure (some (← ck (days + rest)))

/-! ## `dt_util._get_timestring` and friends -/

/-- `dt_util._get_timestring(timediff, precision)` for an int `timediff ≥ 0`.
`precision` is compared with Python `==`, like upstream. -/
def getTimestring (timediff : Nat) (precision : Value) : String := Id.run do
  let formatn (n : Int) (unit : String) : String :=
    if n == 1 then s!"1 {unit} " else s!"{n} {unit}s "
  if timediff == 0 then return "0 seconds"
  let units : List (String × Nat) := [("year", 365 * 24 * 60 * 60), ("month", 30 * 24 * 60 * 60),
    ("day", 24 * 60 * 60), ("hour", 60 * 60), ("minute", 60), ("second", 1)]
  let mut result := ""
  let mut cur : Nat := 0
  let mut td := timediff
  for (unit, factor) in units do
    if td < factor then continue
    cur := cur + 1
    if pyEq (.int cur) precision then
      -- `round(timediff / current_factor)`: true division, then round half even
      return rstripSpaces (result ++ formatn (pyRoundFloat (ratToFloat false td factor)) unit)
    let c := td / factor
    result := result ++ formatn c unit
    td := td - c * factor
  return rstripSpaces result

/-- `round(td.total_seconds())` as `get_age`, `get_time_remaining` and
`timedelta_string` compute it. -/
def roundedSeconds (us : Int) : Int := pyRoundFloat (tdTotalSeconds us)

/-! ## `datetime.strptime` (CPython `_strptime`, C locale) -/

/-- Python's `\s` on ASCII. -/
def isPyWsAscii (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\x0b' || c == '\x0c'
    || ('\x1c' ≤ c && c ≤ '\x1f')

/-- A literal under `re.IGNORECASE` (ASCII). -/
def chI (c : Char) : Rx := .cls (fun x => x.toLower == c.toLower)
def litI (s : String) : Rx := .seq (s.toList.map chI)

/-- `LocaleTime` in the C locale (lower-cased, as `_strptime` keeps them). -/
def A_WEEKDAY : List String := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
def F_WEEKDAY : List String := ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
def A_MONTH : List String := ["", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
def F_MONTH : List String := ["", "january", "february", "march", "april", "may", "june", "july",
  "august", "september", "october", "november", "december"]
def AM_PM : List String := ["am", "pm"]

/-- `TimeRE.__seqToRE`: the names longest first (a stable sort), as an
alternation in a named group. -/
def seqToRE (names : List String) (directive : String) : Rx :=
  let sorted := (names.filter (· != "")).mergeSort (fun a b => a.length ≥ b.length)
  .group directive (.alt (sorted.map litI))

/-- The `TimeRE` entry for a directive key: `none` when the key is not in
`TimeRE` (a `KeyError`, which `_strptime` turns into a `ValueError`). The
regex comes with its group names, in order. -/
def timeRE (key : String) : Option (Except String (List (Rx × String))) :=
  let g (n : String) (r : Rx) : Option (Except String (List (Rx × String))) := some (.ok [(.group n r, n)])
  let alt := Rx.alt
  let sq := Rx.seq
  let r12 := range '1' '2'
  let r19 := range '1' '9'
  let r05 := range '0' '5'
  let dRe := alt [sq [ch '3', range '0' '1'], sq [r12, digit], sq [ch '0', r19], r19, sq [ch ' ', r19]]
  let hRe := alt [sq [ch '2', range '0' '3'], sq [range '0' '1', digit], digit, sq [ch ' ', digit]]
  let iRe := alt [sq [ch '1', range '0' '2'], sq [ch '0', r19], r19, sq [ch ' ', r19]]
  let uRe := alt [sq [ch '5', range '0' '3'], sq [range '0' '4', digit], digit]
  let unsupported (why : String) : Option (Except String (List (Rx × String))) :=
    some (.error s!"strptime directive %{key} is not supported by HALean ({why})")
  match key with
  | "d" | "e" => g "d" dRe
  | "f" => g "f" (nTimes digit 1 6)
  | "H" | "k" => g "H" hRe
  | "I" | "l" => g "I" iRe
  | "G" => g "G" (sq [digit, digit, digit, digit])
  | "j" => g "j" (alt [sq [lit "36", range '0' '6'], sq [ch '3', r05, digit], sq [r12, digit, digit],
      sq [ch '0', r19, digit], sq [lit "00", r19], sq [r19, digit], sq [ch '0', r19], r19])
  | "m" => g "m" (alt [sq [ch '1', range '0' '2'], sq [ch '0', r19], r19])
  | "M" => g "M" (alt [sq [r05, digit], digit])
  | "S" => g "S" (alt [sq [ch '6', range '0' '1'], sq [r05, digit], digit])
  | "U" => g "U" uRe
  | "W" => g "W" uRe
  | "w" => g "w" (range '0' '6')
  | "u" => g "u" (range '1' '7')
  | "V" => g "V" (alt [sq [ch '5', range '0' '3'], sq [ch '0', r19], sq [range '1' '4', digit], digit])
  | "y" => g "y" (sq [digit, digit])
  | "Y" => g "Y" (sq [digit, digit, digit, digit])
  -- `[+-]\d\d:?[0-5]\d(:?[0-5]\d(\.\d{1,6})?)?|(?-i:Z)`
  | "z" => g "z" (alt [sq [oneOf "+-", digit, digit, opt (ch ':'), r05, digit,
        opt (sq [opt (ch ':'), r05, digit, opt (sq [ch '.', nTimes digit 1 6])])], ch 'Z'])
  | "A" => some (.ok [(seqToRE F_WEEKDAY "A", "A")])
  | "a" => some (.ok [(seqToRE A_WEEKDAY "a", "a")])
  | "B" => some (.ok [(seqToRE (F_MONTH.drop 1) "B", "B")])
  | "b" => some (.ok [(seqToRE (A_MONTH.drop 1) "b", "b")])
  | "p" | "P" => some (.ok [(seqToRE AM_PM "p", "p")])
  | "%" => some (.ok [(ch '%', "")])
  | "T" => some (.ok [(.group "H" hRe, "H"), (ch ':', ""), (.group "M" (alt [sq [r05, digit], digit]), "M"),
      (ch ':', ""), (.group "S" (alt [sq [ch '6', range '0' '1'], sq [r05, digit], digit]), "S")])
  | "R" => some (.ok [(.group "H" hRe, "H"), (ch ':', ""), (.group "M" (alt [sq [r05, digit], digit]), "M")])
  | "Z" => unsupported "it matches the host's time.tzname"
  | "Od" | "Om" | "Ow" | "Oy" | "OC" | "OH" | "OI" | "OM" | "OS" | "Oe" | "Op" =>
    unsupported "locale alternative digits"
  | "r" | "X" | "x" | "c" => unsupported "locale formats"
  | _ => none

/-- Python's escape set in `TimeRE.pattern`: `[\\.^$*+?\(\){}\[\]|]`. -/
def RE_SPECIAL : String := "\\.^$*+?(){}[]|"

/-- The loop of `strptimePattern`. -/
partial def patternGo (fmt : String) (cs : List Char) (rx : Array Rx) (names : Array String) :
    Except PyErr (Array Rx × Array String) := do
  match cs with
  | [] => pure (rx, names)
  | c :: rest =>
    if isPyWsAscii c then
      patternGo fmt (rest.dropWhile isPyWsAscii) (rx.push (plus (.cls isPyWsAscii))) names
    else if c == '\'' then
      patternGo fmt rest (rx.push (.cls (fun x => x == '\'' || x == 'ʼ'))) names
    else if c != '%' then
      patternGo fmt rest (rx.push (chI c)) names
    else
      let r1 := rest.dropWhile (fun x => "-_0#".toList.contains x)
      let r2 := r1.dropWhile Char.isDigit
      let (pre, r3) := match r2 with
        | 'O' :: t => ("O", t)
        | 'E' :: t => ("E", t)
        | t => ("", t)
      -- the character after the prefix; whitespace, `'` and escaped
      -- characters give keys like `\s`, `[`, `\.` that are never in TimeRE
      let (key, r4, normal) := match r3 with
        | [] => (pre, [], true)
        | x :: t =>
          if isPyWsAscii x || x == '\'' || RE_SPECIAL.toList.contains x then (pre ++ "\\", t, false)
          else (pre.push x, t, true)
      let bad : Except PyErr (Array Rx × Array String) :=
        if key.isEmpty || key == "\\" then throw (.valueError s!"stray % in format '{fmt}'")
        else throw (.valueError s!"'{key}' is a bad directive in format '{fmt}'")
      match (if normal then timeRE key else none) with
      | none => bad
      | some (.error e) => throw (.error e)
      | some (.ok pieces) =>
        let mut names := names
        for (_, n) in pieces do
          if n != "" then
            if names.contains n then throw (.error s!"re.error: redefinition of group name '{n}'")
            names := names.push n
        patternGo fmt r4 (rx ++ (pieces.map (·.1)).toArray) names

/-- `TimeRE.pattern` + `re.compile(..., IGNORECASE)`: the format as a list of
regex pieces and the group names in order. Literal text is matched
case-insensitively, whitespace runs become `\s+`, `'` becomes `['ʼ]`, and a
directive `%[-_0^#]*[0-9]*([OE]?\\?.?)` is looked up in `TimeRE` (after the
escaping, so a `^` flag or a special character makes it a bad directive). -/
def strptimePattern (fmt : String) : Except PyErr (List Rx × List String) := do
  let (rx, names) ← patternGo fmt fmt.toList #[] #[]
  pure (rx.toList, names.toList)

/-- `datetime.date(y, m, d)` validity. -/
def dateOk (y : Int) (m d : Int) : Bool :=
  1 ≤ y && y ≤ 9999 && 1 ≤ m && m ≤ 12 && 1 ≤ d && d ≤ (daysInMonth y m.toNat : Int)

/-- `date.toordinal()` as a day number since 1970-01-01 (the offset cancels). -/
def dayNum (y : Int) (m d : Int) : Int := daysFromCivil y m.toNat d.toNat

/-- `date.fromisocalendar(year, week, day)` (CPython's `iso_to_ymd`). -/
def fromIsoCalendar (year week day : Int) : Except PyErr (Int × Int × Int) := do
  if year < 1 || year > 9999 then throw (.valueError s!"Year is out of range: {year}")
  -- `ymd_to_ord(y, 1, 1) % 7`: Monday is 1, Sunday 0; 1970-01-01 was a Thursday
  let ordMod7 := fun (dn : Int) => Int.emod (dn + 4) 7
  if week ≤ 0 || week ≥ 53 then
    let ok := week == 53 &&
      (let fw := ordMod7 (dayNum year 1 1); fw == 4 || (fw == 3 && isLeap year))
    if !ok then throw (.valueError s!"Invalid week: {week}")
  if day ≤ 0 || day ≥ 8 then throw (.valueError s!"Invalid weekday: {day} (range is [1, 7])")
  -- `iso_week1_monday`
  let first := dayNum year 1 1
  let fwd := Int.emod (first + 3) 7  -- (ordinal + 6) % 7: Monday = 0
  let mon := first - fwd + (if fwd > 3 then 7 else 0)
  let (y, m, d) := civilFromDays (mon + (week - 1) * 7 + day - 1)
  if y < 1 || y > 9999 then throw (.valueError s!"year {y} is out of range")
  pure (y, (m : Int), (d : Int))

/-- `datetime.strptime(data, fmt)`, via `_strptime._strptime_datetime_datetime`.
A naive datetime unless `%z` matched. -/
def strptime (data fmt : String) : Except PyErr Value := do
  if !(isAscii data && isAscii fmt) then
    throw (.error "strptime on non-ASCII text is not supported by HALean")
  let (rxs, names) ← strptimePattern fmt
  let some (rest, caps) := matchPrefix (.seq rxs) data
    | throw (.valueError s!"time data '{data}' does not match format '{fmt}'")
  if !rest.isEmpty then throw (.valueError s!"unconverted data remains: {String.ofList rest}")
  let get (n : String) : String := (caps.get? n).getD ""
  let int (n : String) : Except PyErr Int := match parseIntStr (get n) with
    | some i => pure i
    | none => throw (.valueError s!"invalid literal for int() with base 10: '{get n}'")
  let idx (xs : List String) (s : String) : Int := (xs.idxOf s.toLower : Nat)
  let mut isoYear : Option Int := none
  let mut year : Option Int := none
  let mut month : Int := 1
  let mut day : Int := 1
  let mut hour : Int := 0
  let mut minute : Int := 0
  let mut second : Int := 0
  let mut fraction : Int := 0
  let mut gmtoff : Option Int := none
  let mut gmtoffFraction : Int := 0
  let mut isoWeek : Option Int := none
  let mut weekOfYear : Option Int := none
  let mut weekOfYearStart : Int := 0
  let mut weekday : Option Int := none
  let mut julian : Option Int := none
  for n in names do
    match n with
    | "y" =>
      let y ← int "y"
      year := some (if y ≤ 68 then y + 2000 else y + 1900)
    | "Y" => year := some (← int "Y")
    | "G" => isoYear := some (← int "G")
    | "m" => month := ← int "m"
    | "B" => month := idx F_MONTH (get "B")
    | "b" => month := idx A_MONTH (get "b")
    | "d" => day := ← int "d"
    | "H" => hour := ← int "H"
    | "I" =>
      hour := ← int "I"
      let ampm := (get "p").toLower
      if ampm == "" || ampm == "am" then
        if hour == 12 then hour := 0
      else if ampm == "pm" then
        if hour != 12 then hour := hour + 12
    | "M" => minute := ← int "M"
    | "S" => second := ← int "S"
    | "f" =>
      let s := get "f"
      fraction := (s ++ "".pushn '0' (6 - s.length)).toNat!
    | "A" => weekday := some (idx F_WEEKDAY (get "A"))
    | "a" => weekday := some (idx A_WEEKDAY (get "a"))
    | "w" =>
      let w ← int "w"
      weekday := some (if w == 0 then 6 else w - 1)
    | "u" => weekday := some ((← int "u") - 1)
    | "j" => julian := some (← int "j")
    | "U" | "W" =>
      weekOfYear := some (← int n)
      weekOfYearStart := if n == "U" then 6 else 0
    | "V" => isoWeek := some (← int "V")
    | "z" =>
      let z0 := get "z"
      if z0 == "Z" then gmtoff := some 0 else
        let mut z := z0.toList
        if z.getD 3 ' ' == ':' then
          z := z.take 3 ++ z.drop 4
          if z.length > 5 then
            if z.getD 5 ' ' != ':' then throw (.valueError s!"Inconsistent use of : in {z0}")
            z := z.take 5 ++ z.drop 6
        let pint (cs : List Char) : Except PyErr Int := match parseIntStr (String.ofList cs) with
          | some i => pure i
          | none => throw (.valueError s!"invalid literal for int() with base 10: '{String.ofList cs}'")
        let hours ← pint ((z.drop 1).take 2)
        let minutes ← pint ((z.drop 3).take 2)
        let secPart := (z.drop 5).take 2
        let seconds ← if secPart.isEmpty then pure 0 else pint secPart
        let mut off := hours * 3600 + minutes * 60 + seconds
        let remainder := z.drop 8
        let mut frac ← pint (remainder ++ List.replicate (6 - remainder.length) '0')
        if z.head? == some '-' then
          off := -off
          frac := -frac
        gmtoff := some off
        gmtoffFraction := frac
    | _ => pure ()
  -- ambiguities
  if isoYear.isSome then
    if julian.isSome then
      throw (.valueError "Day of the year directive '%j' is not compatible with ISO year directive '%G'. Use '%Y' instead.")
    else if isoWeek.isNone || weekday.isNone then
      throw (.valueError "ISO year directive '%G' must be used with the ISO week directive '%V' and a weekday directive ('%A', '%a', '%w', or '%u').")
  else if isoWeek.isSome then
    throw (.valueError "ISO week directive '%V' is incompatible with the year directive '%Y'. Use the ISO year '%G' instead.")
  let mut leapYearFix := false
  let mut y : Int := 0
  match year with
  | some yy => y := yy
  | none =>
    if month == 2 && day == 29 then
      y := 1904
      leapYearFix := true
    else y := 1900
  let yearRange (yy : Int) : Except PyErr Unit :=
    if yy < 1 || yy > 9999 then throw (.valueError s!"year {yy} is out of range") else pure ()
  if julian.isNone then
    if let some wd := weekday then
      if let some woy := weekOfYear then
        -- `_calc_julian_from_U_or_W`
        yearRange y
        let mut firstWeekday := weekdayOf (dayNum y 1 1 * US_PER_DAY)
        let mut dow := wd
        if weekOfYearStart != 0 then
          firstWeekday := (firstWeekday + 1) % 7
          dow := Int.emod (dow + 1) 7
        let week0Length : Int := Int.emod (7 - (firstWeekday : Int)) 7
        julian := some (if woy == 0 then 1 + dow - firstWeekday
          else 1 + week0Length + 7 * (woy - 1) + dow)
      else if let (some iy, some iw) := (isoYear, isoWeek) then
        let (yy, mm, dd) ← fromIsoCalendar iy iw (wd + 1)
        y := yy
        month := mm
        day := dd
      if let some j := julian then
        if j ≤ 0 then
          y := y - 1
          julian := some (j + (if isLeap y then 366 else 365))
  match julian with
  | none =>
    if !dateOk y month day then throw (.valueError "day is out of range for month")
  | some j =>
    yearRange y
    let (yy, mm, dd) := civilFromDays (j - 1 + dayNum y 1 1)
    if yy < 1 || yy > 9999 then throw (.valueError "ordinal must be in 1..3652059")
    y := yy
    month := mm
    day := dd
  if leapYearFix then y := 1900
  -- `_parse_tz`: `timezone(timedelta(seconds=gmtoff, microseconds=fraction))`
  if let some off := gmtoff then
    let offUs := off * US_PER_SEC + gmtoffFraction
    if offUs.natAbs ≥ (US_PER_DAY.natAbs) then
      throw (.valueError "offset must be a timedelta strictly between -timedelta(hours=24) and timedelta(hours=24)")
  let c : Civil := { year := y, month := month.toNat, day := day.toNat, hour := hour.toNat,
                     minute := minute.toNat, second := second.toNat, micro := fraction.toNat }
  if let some e := c.valid then throw (.valueError e)
  let wall := fromCivil c
  match gmtoff with
  | none => pure (.datetime wall none)
  | some off =>
    if gmtoffFraction != 0 then
      throw (.error "UTC offsets with fractions of a second are not supported by HALean")
    pure (.datetime (wall - off * US_PER_SEC) (some off))

end HALean.Template
