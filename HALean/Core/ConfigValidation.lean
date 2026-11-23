/-
  The `cv.*` validators of `helpers/config_validation.py` that service schemas
  commonly use and that HALean translates exactly. They are plain callables to
  probatio (compiled by `_compile_callable`), so the `probatio.Invalid` they
  raise surfaces as is, and any other exception (`TypeError` from iterating an
  `int`) escapes the schema.

  The `cv.*` that are probatio objects are written as the validators they are
  (`HALean.Core.ServicesJson.decodeValidator`): `positive_int`,
  `positive_float`, `small_float`, `byte` (`All(Coerce(..), Range(..))`),
  `port` (`Port()`), `ensure_list` (`EnsureList()`), `comp_entity_ids`
  (`Any(All(Lower, Any('all', 'none')), entity_ids)`), `time_period`
  (`Any(time_period_str, time_period_seconds, timedelta, time_period_dict)`),
  `time_period_dict` and `positive_time_period`.
-/
import HALean.Core.Probatio
import HALean.Core.State
import HALean.Automation.Config

namespace HALean.Core
open HALean.Template

/-- `cv.string`: `None`, a list and a dict fail; a `str` is kept; anything
else is `str(value)`. -/
def cvString (v : Value) : VResult :=
  match v with
  | .none => throw (inv "string value is None")
  | .str _ => pure v
  | .list _ | .dict _ => throw (inv "value should be a string")
  | v => do return .str (← strOf v)

/-- `cv.boolean`. A string is lower-cased and stripped first, and the error
message shows the string as it is then. -/
def cvBoolean (v : Value) : VResult := do
  match v with
  | .bool _ => return v
  | .str s =>
    requireSafe v
    let t := (s.map Char.toLower).trim
    if ["1", "true", "yes", "on", "enable"].contains t then return .bool true
    if ["0", "false", "no", "off", "disable"].contains t then return .bool false
    throw (inv s!"invalid boolean value {t}")
  | .int i => return .bool (i != 0)
  | .float f => return .bool (f != 0)
  | v => throw (inv s!"invalid boolean value {← strOf v}")

/-- `cv.entity_id`: `cv.string`, lower-cased, then `valid_entity_id`. -/
def cvEntityId (v : Value) : VResult := do
  let .str s ← cvString v | throw (.unsupported "cv.string returned a non-string")
  requireSafe (.str s)
  let lowered := s.map Char.toLower
  if validEntityId lowered then return .str lowered
  throw (inv s!"Entity ID {← strOf v} is an invalid entity ID")

/-- `iter(value)` for `cv.entity_ids`: a list's items, a dict's keys;
`TypeError` for a scalar. -/
def pyIter (v : Value) : Except VErr (List Value) :=
  match v with
  | .list xs => pure xs
  | .dict kvs => pure (kvs.map (·.1))
  | v => throw (.raise "TypeError" s!"'{typeName v}' object is not iterable")

/-- `cv.entity_ids` (`_entity_ids(value, allow_uuid=False)`): a string is split
at commas and each part stripped; every item must pass `cv.entity_id` (the
first failure is raised as it is, without an index). -/
def cvEntityIds (v : Value) : Except VErr (List Value) := do
  let items ← match v with
    | .none => throw (inv "Entity IDs cannot be None")
    | .str s => do
      requireSafe v
      pure ((s.splitOn ",").map fun p => Value.str p.trim)
    | v => pyIter v
  items.mapM cvEntityId

/-- `cv.entities_domain(domain)`: `cv.entity_ids`, then every domain must be
the one given (or one of the list). -/
def cvEntitiesDomain (d : DomainArg) (v : Value) : Except VErr (List Value) := do
  let ids ← cvEntityIds v
  let shown ← match d with
    | .one s => pure s
    | .many ds => strOf (.list (ds.map .str))
  for id in ids do
    let .str e := id | throw (.unsupported "cv.entity_id returned a non-string")
    let dom := match splitEntityId e with | some (dm, _) => dm | none => ""
    let bad := match d with
      | .one s => dom != s
      | .many ds => !ds.contains dom
    if bad then throw (inv s!"Entity ID '{e}' does not belong to domain '{shown}'")
  return ids

/-- `cv.entity_domain(domain)`: exactly one entity of the domain. -/
def cvEntityDomain (d : DomainArg) (v : Value) : VResult := do
  let ids ← cvEntitiesDomain d v
  match ids with
  | [id] => return id
  | _ => throw (inv s!"Expected exactly 1 entity, got {ids.length}")

def isHexDigit (c : Char) : Bool :=
  c.isDigit || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F')

/-- `cv.color_hex`: `str(value)` must match `^#[0-9A-F]{6}$` ignoring case
(`$` also matches before a final newline). -/
def cvColorHex (v : Value) : VResult := do
  let s ← strOf v
  let cs := s.toList
  let cs' := if cs.length == 8 && cs.getLast? == some '\n' then cs.dropLast else cs
  match cs' with
  | '#' :: rest =>
    if rest.length == 6 && rest.all isHexDigit then return .str s
  | _ => pure ()
  throw (inv "Color should be in the format #RRGGBB")

/-- `cv.slug`: `str(value)` must equal its `util.slugify`. -/
def cvSlug (v : Value) : VResult := do
  if let .none := v then throw (inv "Slug should not be None")
  let s ← strOf v
  let some slg := HALean.Automation.slugify? s
    | throw (.unsupported "util.slugify of this text (HTML entities) is not modelled")
  if s == slg then return .str s
  throw (inv s!"invalid slug {s} (try {slg})")

/-- `timedelta(...)` (`HALean.Automation.timedeltaNew`); a NaN, an infinity or
an overflow, where CPython raises `ValueError` or `OverflowError` with
messages HALean does not reproduce, is unsupported. -/
def timedeltaV (args : List (Nat × HALean.Automation.TdArg)) : VResult :=
  match HALean.Automation.timedeltaNew args with
  | .ok us => pure (.timedelta us)
  | .error e => throw (.unsupported s!"timedelta(...) raises ({e})")

/-- `config_validation.TIME_PERIOD_ERROR` -/
def timePeriodError (v : String) : String :=
  s!"offset {v} should be format 'HH:MM', 'HH:MM:SS' or 'HH:MM:SS.F'"

/-- `cv.time_period_str`: `[+-]H:M[:S]`, `int()` for hours and minutes,
`float()` for seconds. The error shows the text without its sign. -/
def cvTimePeriodStr (v : Value) : VResult := do
  match v with
  | .int _ | .bool _ => throw (inv "Make sure you wrap time values in quotes")
  | .str s =>
    requireSafe v
    let (neg, body) :=
      if s.startsWith "-" then (true, (s.drop 1).toString)
      else if s.startsWith "+" then (false, (s.drop 1).toString) else (false, s)
    let parts := body.splitOn ":"
    if parts.length != 2 && parts.length != 3 then throw (inv (timePeriodError body))
    let some h := pyIntOfStr? (parts.getD 0 "") | throw (inv (timePeriodError body))
    let some m := pyIntOfStr? (parts.getD 1 "") | throw (inv (timePeriodError body))
    let sec ← if parts.length == 3 then
        match parseFloatStr (parts.getD 2 "") with
        | some f => pure (HALean.Automation.TdArg.float f)
        | none => throw (inv (timePeriodError body))
      else pure (HALean.Automation.TdArg.int 0)
    let .timedelta us ← timedeltaV [(HALean.Automation.US_PER_SECOND, sec),
        (HALean.Automation.US_PER_MINUTE, .int m), (HALean.Automation.US_PER_HOUR, .int h)]
      | throw (.unsupported "timedelta")
    -- `offset *= -1` (symmetric, so it cannot overflow)
    return .timedelta (if neg then -us else us)
  | v => throw (inv (timePeriodError (← strOf v)))

/-- `cv.time_period_seconds`: `timedelta(seconds=float(value))`; the
`ValueError`/`TypeError` of `float()` is "Expected seconds, got ..."; an int
too large for a float raises `OverflowError`, which is not caught. -/
def cvTimePeriodSeconds (v : Value) : VResult := do
  let f ← match v with
    | .int i =>
      let f := intToFloat i
      if f.isInf then throw (.raise "OverflowError" "int too large to convert to float") else pure f
    | v => do
      match ← pyFloat? v with
      | some f => pure f
      | none => throw (inv s!"Expected seconds, got {← strOf v}")
  timedeltaV [(HALean.Automation.US_PER_SECOND, .float f)]

/-- `lambda value: timedelta(**value)` after `time_period_dict`'s schema:
the five units, as floats. -/
def cvTimedeltaKwargs (v : Value) : VResult := do
  let .dict kvs := v | throw (.unsupported "timedelta(**value) of a non-dict")
  let units : List (String × Nat) := [("milliseconds", HALean.Automation.US_PER_MS),
    ("seconds", HALean.Automation.US_PER_SECOND), ("minutes", HALean.Automation.US_PER_MINUTE),
    ("hours", HALean.Automation.US_PER_HOUR), ("days", HALean.Automation.US_PER_DAY)]
  -- `delta_new` accumulates the units in this order, whatever the kwargs order
  let args ← units.filterMapM fun (k, f) =>
    match kvs.find? (fun p => pyEq p.1 (.str k)) with
    | some (_, .float x) => pure (some (f, HALean.Automation.TdArg.float x))
    | some _ => throw (.unsupported "timedelta(**value) with a non-float")
    | none => pure none
  timedeltaV args

/-- `cv.positive_timedelta` -/
def cvPositiveTimedelta (v : Value) : VResult := do
  match v with
  | .timedelta us => if us < 0 then throw (inv "Time period should be positive") else return v
  | _ => throw (.unsupported "positive_timedelta of a non-timedelta")

/-- Run a `cv.*` function. -/
def CvFn.run : CvFn → Value → VResult
  | .string, v => cvString v
  | .boolean, v => cvBoolean v
  | .entityId, v => cvEntityId v
  | .entityIds, v => do return .list (← cvEntityIds v)
  | .entityDomain d, v => cvEntityDomain d v
  | .colorHex, v => cvColorHex v
  | .slug, v => cvSlug v
  | .timePeriodStr, v => cvTimePeriodStr v
  | .timePeriodSeconds, v => cvTimePeriodSeconds v
  | .timedeltaKwargs, v => cvTimedeltaKwargs v
  | .positiveTimedelta, v => cvPositiveTimedelta v

end HALean.Core
