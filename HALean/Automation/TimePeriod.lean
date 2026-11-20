/-
  Time periods as `config_validation` builds them at run time: a trigger's
  templated `for:` is rendered and then validated by
  `cv.positive_time_period`, which builds a Python `timedelta`.

  Translated from:
    * helpers/config_validation.py – `time_period_str`, `time_period_seconds`,
      `time_period_dict`, `time_period`, `positive_timedelta`,
      `positive_time_period`
    * CPython Modules/_datetimemodule.c – `delta_new` / `accum` (how
      `timedelta(...)` turns float arguments into whole microseconds)
-/
import HALean.Template
open Lean

namespace HALean.Automation
open Template

/-- One argument of `timedelta(...)`: a Python `int` or `float`. -/
inductive TdArg where
  | int (i : Int)
  | float (f : Float)

/-- C `modf`: `(fractional part, integral part)`, both with the sign of `x`. -/
def modf (x : Float) : Float × Float :=
  let ip := if x ≥ 0 then x.floor else x.ceil
  (x - ip, ip)

/-- `_datetimemodule.c::accum`: add `num * factor` microseconds to `sofar`,
exactly for the integral part of a float, in double arithmetic for its
fractional part, whose sub-microsecond rest goes to `leftover`. -/
def accum (sofar : Int) (leftover : Float) (factor : Nat) : TdArg → Except String (Int × Float)
  | .int i => pure (sofar + i * factor, leftover)
  | .float x => do
    if x.isNaN then throw "ValueError: cannot convert float NaN to integer"
    if x.isInf then throw "OverflowError: cannot convert float infinity to integer"
    let (fp, ip) := modf x
    let some ii := floatToInt? ip | throw "OverflowError"
    let sum := sofar + ii * factor
    if fp == 0 then return (sum, leftover)
    let (fp2, ip2) := modf (factor.toFloat * fp)
    let some i2 := floatToInt? ip2 | throw "OverflowError"
    return (sum + i2, leftover + fp2)

/-- `timedelta.max.days` -/
def MAX_DELTA_DAYS : Nat := 999999999

/-- `_datetimemodule.c::delta_new`, in microseconds. `args` are
`(microseconds per unit, value)` in the order `delta_new` accumulates them
(microseconds, milliseconds, seconds, minutes, hours, days, weeks). The
leftover fraction is rounded half to even once, at the end. -/
def timedeltaNew (args : List (Nat × TdArg)) : Except String Int := do
  let mut x : Int := 0
  let mut left : Float := 0
  for (f, a) in args do
    (x, left) ← accum x left f a
  if left != 0 then
    let w0 := left.round
    let w := if (w0 - left).abs == 0.5 then
        let odd : Float := if x % 2 == 0 then 0 else 1
        2.0 * ((left + odd) * 0.5).round - odd
      else w0
    let some wi := floatToInt? w | throw "OverflowError"
    x := x + wi
  if (Int.fdiv x 86400000000).natAbs > MAX_DELTA_DAYS then
    throw s!"OverflowError: days={Int.fdiv x 86400000000}; must have magnitude <= {MAX_DELTA_DAYS}"
  return x

def US_PER_MS : Nat := 1000
def US_PER_SECOND : Nat := 1000000
def US_PER_MINUTE : Nat := 60000000
def US_PER_HOUR : Nat := 3600000000
def US_PER_DAY : Nat := 86400000000

/-- Outcome of one `probatio.Any` alternative: `none` is `Invalid` (try the
next one); an error is any other exception, which escapes `Any`. -/
abbrev Alt := Option (Except String Int)

/-- Python's `int()`/`float()` accept Unicode digits; HALean parses ASCII
only, so other text is an error rather than a different answer. -/
def asciiOnly (s : String) : Except String Unit :=
  if s.toList.all (fun c : Char => c.toNat < 128) then pure () else throw s!"non-ASCII time period '{s}' is not supported by HALean"

/-- `cv.time_period_str` -/
def timePeriodStr (s : String) : Alt := do
  let (neg, body) :=
    if s.startsWith "-" then (true, s.dropS 1)
    else if s.startsWith "+" then (false, s.dropS 1) else (false, s)
  let parts := body.splitOn ":"
  if parts.length != 2 && parts.length != 3 then none
  let h ← parseIntStr (parts.getD 0 "")
  let m ← parseIntStr (parts.getD 1 "")
  let sec ← if parts.length == 3 then (parseFloatStr (parts.getD 2 "")).map TdArg.float
    else some (TdArg.int 0)
  return do
    let us ← timedeltaNew [(US_PER_SECOND, sec), (US_PER_MINUTE, .int m), (US_PER_HOUR, .int h)]
    -- `offset *= -1`
    let us := if neg then -us else us
    if (Int.fdiv us 86400000000).natAbs > MAX_DELTA_DAYS then throw "OverflowError"
    pure us

/-- `float(value)` as `cv.time_period_seconds` and `Coerce(float)` use it;
`none` is the `ValueError`/`TypeError` they turn into `Invalid`. -/
def pyFloatV? : Value → Option Float
  | .str s => parseFloatStr s
  | .int i => some (intToFloat i)
  | .bool b => some (if b then 1 else 0)
  | .float f => some f
  | _ => none

/-- `cv.time_period_seconds` -/
def timePeriodSeconds (v : Value) : Alt :=
  (pyFloatV? v).map fun f => timedeltaNew [(US_PER_SECOND, .float f)]

/-- `cv.time_period_dict`: only the five units, each `Coerce(float)`, at
least one, then `timedelta(**value)`. -/
def timePeriodDict (v : Value) : Alt := do
  let .dict kvs := v | none
  if kvs.isEmpty then none
  let units : List (String × Nat) := [("milliseconds", US_PER_MS), ("seconds", US_PER_SECOND),
    ("minutes", US_PER_MINUTE), ("hours", US_PER_HOUR), ("days", US_PER_DAY)]
  let mut given : List (String × Float) := []
  for (k, x) in kvs do
    let .str k := k | none
    if !units.any (·.1 == k) then none
    given := (given.filter (·.1 != k)) ++ [(k, ← pyFloatV? x)]
  -- `delta_new` accumulates milliseconds, seconds, minutes, hours, days
  let args := units.filterMap fun (k, f) => (given.find? (·.1 == k)).map fun (_, x) => (f, TdArg.float x)
  return timedeltaNew args

/-- `cv.time_period` on a rendered value (may be negative), in
microseconds. -/
def cvTimePeriod (v : Value) : Except String Int := do
  if let .str s := v then asciiOnly s
  if let .dict kvs := v then
    for (_, x) in kvs do if let .str s := x then asciiOnly s
  -- `time_period = Any(time_period_str, time_period_seconds, timedelta, time_period_dict)`
  let strAlt : Alt := match v with | .str s => timePeriodStr s | _ => none
  let alts : List (Unit → Alt) := [fun _ => strAlt, fun _ => timePeriodSeconds v,
    fun _ => match v with | .timedelta us => some (pure us) | _ => none,
    fun _ => timePeriodDict v]
  let some r := alts.findSome? (· ()) | throw "invalid time period: expected 'HH:MM', 'HH:MM:SS', seconds or a mapping"
  r

/-- `cv.positive_time_period` (`time_period` then `positive_timedelta`). -/
def cvPositiveTimePeriod (v : Value) : Except String Int := do
  let us ← cvTimePeriod v
  if us < 0 then throw "Time period should be positive"
  return us

end HALean.Automation
