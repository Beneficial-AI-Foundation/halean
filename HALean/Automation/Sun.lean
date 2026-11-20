/-
  Sunrise and sunset, as the `sun` trigger schedules them.

  Translated from:
    * astral 2.2 `astral/sun.py` (the NOAA solar calculator HA uses):
      `julianday`, `minutes_to_timedelta`, the solar-position helpers,
      `hour_angle`, `adjust_to_horizon`, `refraction_at_zenith`,
      `time_of_transit`, `sunrise`, `sunset`
    * helpers/sun.py – `get_observer_astral_event_next`

  Floating point follows CPython: `math.radians`/`math.degrees` multiply by
  `pi/180` / `180/pi`, `%` on floats is Python's (sign of the divisor), the
  transcendental functions are the platform libm, and `int()` truncates.
  A math domain error (`acos` of a value outside [-1, 1], when the sun does
  not reach the zenith that day) is `none`.
-/
import HALean.Template
open Lean

namespace HALean.Automation.Sun
open Template

def RAD : Float := 3.141592653589793 / 180.0
def DEG : Float := 180.0 / 3.141592653589793
def radians (x : Float) : Float := x * RAD
def degrees (x : Float) : Float := x * DEG

/-- Python float `%`. -/
def fmod360 (x : Float) : Float := (floatFloorDivMod x 360.0).2

/-- `math.floor` of a float, as an exact integer-valued float. -/
def ffloor (x : Float) : Float := Float.floor x

/-- Using 32 arc minutes as sun's apparent diameter -/
def SUN_APPARENT_RADIUS : Float := 32.0 / (60.0 * 2.0)

/-- An observer: latitude, longitude (degrees), elevation (metres, a float). -/
structure Observer where
  latitude : Float
  longitude : Float
  elevation : Float
  deriving Repr, Inhabited

def julianday (y0 : Int) (m0 d : Nat) : Float :=
  let (y, m) : Int × Nat := if m0 ≤ 2 then (y0 - 1, m0 + 12) else (y0, m0)
  let yf := Float.ofInt y
  let a := ffloor (yf / 100)
  let b := 2 - a + ffloor (a / 4)
  ffloor (365.25 * (yf + 4716)) + ffloor (30.6001 * (Float.ofNat m + 1)) + Float.ofNat d + b - 1524.5

/-- Python `int(x)` for a finite float. -/
def truncInt (x : Float) : Int :=
  let t := if x < 0 then Float.ceil x else Float.floor x
  (floatToInt? t).getD 0

/-- `minutes_to_timedelta`, in microseconds. -/
def minutesToUs (minutes : Float) : Int :=
  let d := truncInt (minutes / 1440)
  let minutes := minutes - Float.ofInt (d * 1440)
  let minutes := minutes * 60
  let s := truncInt minutes
  let sfrac := minutes - Float.ofInt s
  let us := truncInt (sfrac * 1000000)
  d * 86400000000 + s * 1000000 + us

def jdayToJcentury (jd : Float) : Float := (jd - 2451545.0) / 36525.0
def jcenturyToJday (jc : Float) : Float := (jc * 36525.0) + 2451545.0

def geomMeanLongSun (jc : Float) : Float :=
  fmod360 (280.46646 + jc * (36000.76983 + 0.0003032 * jc))

def geomMeanAnomalySun (jc : Float) : Float :=
  357.52911 + jc * (35999.05029 - 0.0001537 * jc)

def eccentricLocationEarthOrbit (jc : Float) : Float :=
  0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)

def sunEqOfCenter (jc : Float) : Float :=
  let mrad := radians (geomMeanAnomalySun jc)
  let sinm := Float.sin mrad
  let sin2m := Float.sin (mrad + mrad)
  let sin3m := Float.sin (mrad + mrad + mrad)
  sinm * (1.914602 - jc * (0.004817 + 0.000014 * jc))
    + sin2m * (0.019993 - 0.000101 * jc)
    + sin3m * 0.000289

def sunTrueLong (jc : Float) : Float := geomMeanLongSun jc + sunEqOfCenter jc

def sunApparentLong (jc : Float) : Float :=
  let omega := 125.04 - 1934.136 * jc
  sunTrueLong jc - 0.00569 - 0.00478 * Float.sin (radians omega)

def meanObliquityOfEcliptic (jc : Float) : Float :=
  let seconds := 21.448 - jc * (46.815 + jc * (0.00059 - jc * (0.001813)))
  23.0 + (26.0 + (seconds / 60.0)) / 60.0

def obliquityCorrection (jc : Float) : Float :=
  let omega := 125.04 - 1934.136 * jc
  meanObliquityOfEcliptic jc + 0.00256 * Float.cos (radians omega)

def sunDeclination (jc : Float) : Float :=
  let sint := Float.sin (radians (obliquityCorrection jc)) * Float.sin (radians (sunApparentLong jc))
  degrees (Float.asin sint)

def varY (jc : Float) : Float :=
  let y := Float.tan (radians (obliquityCorrection jc) / 2.0)
  y * y

def eqOfTime (jc : Float) : Float :=
  let l0 := geomMeanLongSun jc
  let e := eccentricLocationEarthOrbit jc
  let m := geomMeanAnomalySun jc
  let y := varY jc
  let sin2l0 := Float.sin (2.0 * radians l0)
  let sinm := Float.sin (radians m)
  let cos2l0 := Float.cos (2.0 * radians l0)
  let sin4l0 := Float.sin (4.0 * radians l0)
  let sin2m := Float.sin (2.0 * radians m)
  let etime := y * sin2l0 - 2.0 * e * sinm + 4.0 * e * y * sinm * cos2l0
    - 0.5 * y * y * sin4l0 - 1.25 * e * e * sin2m
  degrees etime * 4.0

/-- `hour_angle`; `none` for a math domain error. -/
def hourAngle (latitude declination zenith : Float) (rising : Bool) : Option Float :=
  let latR := radians latitude
  let decR := radians declination
  let zenR := radians zenith
  let h := (Float.cos zenR - Float.sin latR * Float.sin decR) / (Float.cos latR * Float.cos decR)
  if h < -1 || h > 1 || h.isNaN then none
  else
    let ha := Float.acos h
    some (if rising then ha else -ha)

def adjustToHorizon (elevation : Float) : Float :=
  if elevation ≤ 0 then 0 else
  let r : Float := 6356900  -- radius of the earth
  degrees (Float.acos (r / (r + elevation)))

def refractionAtZenith (zenith : Float) : Float :=
  let elevation := 90 - zenith
  if elevation ≥ 85.0 then 0 else
  let te := Float.tan (radians elevation)
  let rc :=
    if elevation > 5.0 then 58.1 / te - 0.07 / (te * te * te) + 0.000086 / (te * te * te * te * te)
    else if elevation > -0.575 then
      let step1 := -12.79 + elevation * 0.711
      let step2 := 103.4 + elevation * step1
      let step3 := -518.2 + elevation * step2
      1735.0 + elevation * step3
    else -20.774 / te
  rc / 3600.0

/-- `time_of_transit(observer, date, zenith, direction)`: microseconds since
the epoch (UTC), or `none` for a math domain error. -/
def timeOfTransit (o : Observer) (y : Int) (m d : Nat) (zenith : Float) (rising : Bool) : Option Int := do
  let latitude := if o.latitude > 89.8 then 89.8 else if o.latitude < -89.8 then -89.8 else o.latitude
  let adjElev := if o.elevation > 0.0 then adjustToHorizon o.elevation else 0.0
  let adjRefr := refractionAtZenith (zenith + adjElev)
  let jd := julianday y m d
  let t := jdayToJcentury jd
  let solarDec := sunDeclination t
  let ha ← hourAngle latitude solarDec (zenith + adjElev - adjRefr) rising
  let delta := -o.longitude - degrees ha
  let timeDiff := 4.0 * delta
  let timeUTC := 720.0 + timeDiff - eqOfTime t
  let t := jdayToJcentury (jcenturyToJday t + timeUTC / 1440.0)
  let solarDec := sunDeclination t
  let ha ← hourAngle latitude solarDec (zenith + adjElev + adjRefr) rising
  let delta := -o.longitude - degrees ha
  let timeDiff := 4.0 * delta
  let timeUTC := 720 + timeDiff - eqOfTime t
  -- `datetime(date.year, date.month, date.day) + td`, localized to UTC
  return Template.daysFromCivil y m d * Template.US_PER_DAY + minutesToUs timeUTC

/-- `astral.sun.sunrise` / `sunset` in UTC microseconds. -/
def sunEvent (o : Observer) (sunrise : Bool) (y : Int) (m d : Nat) : Option Int :=
  timeOfTransit o y m d (90.0 + SUN_APPARENT_RADIUS) sunrise

/-- `get_observer_astral_event_next(observer, event, now, offset)`: the first
event (plus `offset`) after `nowUs`, trying the local dates from yesterday
on, for a year. `tzOffsetSec` gives the local date (`dt_util.as_local`). -/
def nextEvent (o : Observer) (sunrise : Bool) (nowUs : Int) (tzOffsetSec : Int) (offsetUs : Int) :
    Option Int := Id.run do
  let localDay := Int.fdiv (nowUs + tzOffsetSec * Template.US_PER_SEC) Template.US_PER_DAY
  for k in [0:368] do
    let (y, m, d) := Template.civilFromDays (localDay - 1 + k)
    if let some t := sunEvent o sunrise y m d then
      if t + offsetUs > nowUs then return some (t + offsetUs)
  return none

end HALean.Automation.Sun
