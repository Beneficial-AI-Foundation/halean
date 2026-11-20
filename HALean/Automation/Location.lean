/-
  Locations and zones, as the `zone` trigger uses them.

  Translated from:
    * util/location.py          – `vincenty`, `distance`
    * helpers/location.py       – `get_state_coordinates`, `has_location`
    * components/zone/__init__.py  – `in_zone`
    * components/zone/condition.py – `zone`
    * components/zone/helpers.py   – `get_in_zones_attribute`

  Floating point follows CPython: `math.radians(x)` is `x * (pi / 180)`,
  `x ** 2` is correctly rounded like `x * x`, the trigonometric functions are
  the platform's libm (the same one HA uses when both run on one host), and
  `round(s, 6)` is Python's correctly rounded `round`.
-/
import HALean.Core.Types
import HALean.Template
open Lean

namespace HALean.Automation

def AXIS_A : Float := 6378137
def FLATTENING : Float := 1 / 298.257223563
def AXIS_B : Float := 6356752.314245
def MAX_ITERATIONS : Nat := 200
def CONVERGENCE_THRESHOLD : Float := 1e-12

/-- CPython `math.radians`: `x * degToRad`, `degToRad = Py_MATH_PI / 180.0`. -/
def radians (x : Float) : Float := x * (3.141592653589793 / 180.0)

/-- `vincenty(point1, point2)` in kilometres, `none` when it does not converge. -/
def vincenty (lat1 lon1 lat2 lon2 : Float) : Option Float := Id.run do
  -- short-circuit coincident points
  if lat1 == lat2 && lon1 == lon2 then return some 0.0
  let u1 := Float.atan ((1 - FLATTENING) * Float.tan (radians lat1))
  let u2 := Float.atan ((1 - FLATTENING) * Float.tan (radians lat2))
  let l := radians (lon2 - lon1)
  let sinU1 := Float.sin u1
  let cosU1 := Float.cos u1
  let sinU2 := Float.sin u2
  let cosU2 := Float.cos u2
  let mut lam := l
  let mut converged := false
  let mut sinSigma := 0.0
  let mut cosSigma := 0.0
  let mut sigma := 0.0
  let mut cosSqAlpha := 0.0
  let mut cos2SigmaM := 0.0
  for _ in [0:MAX_ITERATIONS] do
    let sinLambda := Float.sin lam
    let cosLambda := Float.cos lam
    let a := cosU2 * sinLambda
    let b := cosU1 * sinU2 - sinU1 * cosU2 * cosLambda
    sinSigma := Float.sqrt (a * a + b * b)
    if sinSigma == 0.0 then return some 0.0  -- coincident points
    cosSigma := sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
    sigma := Float.atan2 sinSigma cosSigma
    let sinAlpha := cosU1 * cosU2 * sinLambda / sinSigma
    cosSqAlpha := 1 - sinAlpha * sinAlpha
    -- `except ZeroDivisionError: cos2SigmaM = 0`
    cos2SigmaM := if cosSqAlpha == 0.0 then 0.0 else cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
    let c := FLATTENING / 16 * cosSqAlpha * (4 + FLATTENING * (4 - 3 * cosSqAlpha))
    let prev := lam
    lam := l + (1 - c) * FLATTENING * sinAlpha * (sigma
      + c * sinSigma * (cos2SigmaM + c * cosSigma * (-1 + 2 * (cos2SigmaM * cos2SigmaM))))
    if Float.abs (lam - prev) < CONVERGENCE_THRESHOLD then
      converged := true
      break
  if !converged then return none
  let uSq := cosSqAlpha * (AXIS_A * AXIS_A - AXIS_B * AXIS_B) / (AXIS_B * AXIS_B)
  let bigA := 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
  let bigB := uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
  let deltaSigma := bigB * sinSigma * (cos2SigmaM + bigB / 4 * (cosSigma * (-1 + 2 * (cos2SigmaM * cos2SigmaM))
    - bigB / 6 * cos2SigmaM * (-3 + 4 * (sinSigma * sinSigma)) * (-3 + 4 * (cos2SigmaM * cos2SigmaM))))
  let s := AXIS_B * bigA * (sigma - deltaSigma)
  return some (Template.pyRound (s / 1000) 6)

/-- `distance(lat1, lon1, lat2, lon2)` in metres. -/
def distance (lat1 lon1 lat2 lon2 : Float) : Option Float :=
  (vincenty lat1 lon1 lat2 lon2).map (· * 1000)

/-- A Python `int`/`float` attribute (a `bool` is an `int` too). -/
def pyNumber? : Json → Option Float
  | .num n => some n.toFloat
  | .bool b => some (if b then 1 else 0)
  | _ => none

/-- `get_state_coordinates(state) is not None` -/
def hasLocation (s : EntityState) : Bool :=
  ((s.attr? "latitude").bind pyNumber?).isSome && ((s.attr? "longitude").bind pyNumber?).isSome

/-- `get_in_zones_attribute`: person and device_tracker entities report the
zones they are in. -/
def inZonesAttribute (s : EntityState) : Option String :=
  let dom := (s.entityId.splitOn ".").headD ""
  if dom == "person" || dom == "device_tracker" then some "in_zones" else none

/-- `zone/trigger.py::_state_has_zone_info` -/
def stateHasZoneInfo (s : EntityState) : Bool :=
  hasLocation s || match inZonesAttribute s with
    | some a => (s.attr? a).isSome
    | none => false

/-- A number from a zone or entity attribute; anything else would raise
`TypeError` in the arithmetic. -/
def numAttr (s : EntityState) (k : String) : Except String Float :=
  match s.attr? k with
  | some v => match pyNumber? v with
    | some f => pure f
    | none => throw s!"{s.entityId} attribute '{k}' is not a number: {v.compress}"
  | none => throw s!"{s.entityId} has no '{k}' attribute"

/-- `zone.in_zone(zone, latitude, longitude, radius)` -/
def inZone (zone : EntityState) (lat lon radius : Float) : Except String Bool := do
  if zone.state == "unavailable" then return false
  let zlat ← numAttr zone "latitude"
  let zlon ← numAttr zone "longitude"
  let some d := distance lat lon zlat zlon | return false
  match zone.attr? "radius" with
  | none => throw s!"{zone.entityId} has no 'radius' attribute"
  | some .null => return false
  | some _ => return d - radius < (← numAttr zone "radius")

/-- `zone/condition.py::zone(hass, zone_state, entity_state)`. An error is
the `ConditionErrorMessage` (or other exception) HA would raise. -/
def zoneCondition (zone : EntityState) (entity : EntityState) : Except String Bool := do
  if entity.state == "unavailable" || entity.state == "unknown" then return false
  -- prefer the `in_zones` attribute (person, device_tracker)
  if let some a := inZonesAttribute entity then
    match entity.attr? a with
    | none | some .null => pure ()
    | some (.arr xs) => return xs.contains (.str zone.entityId)
    | some (.str s) => return (s.splitOn zone.entityId).length > 1
    | some v => throw s!"in_zones is not a list: {v.compress}"
  let some latJ := entity.attr? "latitude" | throw s!"entity {entity.entityId} has no 'latitude' attribute"
  if latJ == .null then throw s!"entity {entity.entityId} has no 'latitude' attribute"
  let some lonJ := entity.attr? "longitude" | throw s!"entity {entity.entityId} has no 'longitude' attribute"
  if lonJ == .null then throw s!"entity {entity.entityId} has no 'longitude' attribute"
  let lat ← numAttr entity "latitude"
  let lon ← numAttr entity "longitude"
  let acc ← match entity.attr? "gps_accuracy" with
    | none => pure 0.0
    | some _ => numAttr entity "gps_accuracy"
  inZone zone lat lon acc

end HALean.Automation
