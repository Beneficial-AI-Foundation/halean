/-
  Core data types shared by the engine.

  Mirrors (a subset of) `homeassistant/core.py::State` and the event payloads
  delivered by `async_track_state_change_event`.
-/
import Lean.Data.Json
open Lean

/-! Compatibility helpers for the Lean 4.2x+ `String.Slice` API. -/
def String.trim (s : String) : String := s.trimAscii.toString
def String.dropS (s : String) (n : Nat) : String := (s.drop n).toString

instance : Repr Json := ⟨fun j _ => j.compress⟩

namespace HALean

/-- Milliseconds since the Unix epoch (UTC). The engine never reads a clock:
time only enters through input messages, so every run is reproducible. -/
abbrev Millis := Nat

/-- A wall-clock instant as seen by the engine: UTC millis plus the local UTC
offset in seconds (supplied by the I/O shell, so DST is the shell's job). -/
structure Instant where
  utc : Millis
  tzOffsetSec : Int := 0
  deriving Repr, Inhabited, BEq

/-- Snapshot of one entity, as in `homeassistant.core.State`. -/
structure EntityState where
  entityId : String
  state : String
  attributes : Json := Json.mkObj []
  lastChanged : Millis := 0
  /-- `last_changed` / `last_updated` in microseconds, as HA has them (the
  shell sends them when it can; templates print them exactly). -/
  lastChangedUs : Option Int := none
  lastUpdatedUs : Option Int := none
  deriving Repr, Inhabited, BEq

def EntityState.domain (s : EntityState) : String :=
  (s.entityId.splitOn ".").headD ""

def EntityState.attr? (s : EntityState) (k : String) : Option Json :=
  match s.attributes.getObjVal? k with
  | .ok v => some v
  | .error _ => none

def EntityState.hasAttr (s : EntityState) (k : String) : Bool :=
  (s.attr? k).isSome

/-- The state machine (`hass.states`): an association list keyed by entity id.
A list keeps the model simple to reason about; the engine sizes involved
(hundreds of entities) make this cheap enough. -/
abbrev States := List (String × EntityState)

def States.get? (st : States) (eid : String) : Option EntityState :=
  (st.find? (·.1 == eid)).map (·.2)

/-- Update in place, or append a new entity: HA's state machine is a dict,
so iteration (`states`, `states.light`) follows first-insertion order. -/
def States.set (st : States) (s : EntityState) : States :=
  if st.any (·.1 == s.entityId) then st.map fun p => if p.1 == s.entityId then (s.entityId, s) else p
  else st ++ [(s.entityId, s)]

def States.remove (st : States) (eid : String) : States :=
  st.filter (·.1 != eid)

/-- `homeassistant.const` -/
def STATE_UNAVAILABLE := "unavailable"
def STATE_UNKNOWN := "unknown"

/-- Weekday names as in `homeassistant.const.WEEKDAYS` (Monday first). -/
def WEEKDAYS : List String := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

/-- Local time of day in milliseconds since local midnight. -/
def Instant.localMillis (t : Instant) : Int :=
  (t.utc : Int) + t.tzOffsetSec * 1000

def msPerDay : Int := 86400000

def Instant.timeOfDay (t : Instant) : Nat :=
  (t.localMillis % msPerDay).toNat

/-- Python `datetime.weekday()`: Monday = 0. 1970-01-01 was a Thursday (3). -/
def Instant.weekdayIdx (t : Instant) : Nat :=
  ((t.localMillis / msPerDay + 3) % 7).toNat

def Instant.weekday (t : Instant) : String :=
  WEEKDAYS.getD t.weekdayIdx "mon"

/-- Python's `float(x)` on the values that appear in states and attributes.
Returns `none` where Python raises `ValueError`/`TypeError`. -/
def parsePyFloatStr (s : String) : Option Float :=
  let s := s.trim
  let (neg, body) :=
    if s.startsWith "-" then (true, s.dropS 1)
    else if s.startsWith "+" then (false, s.dropS 1) else (false, s)
  let lower := body.toLower
  let r : Option Float :=
    if lower == "inf" || lower == "infinity" then some (1.0 / 0.0)
    else if lower == "nan" then some (0.0 / 0.0)
    else
      -- digits [. digits] [e[+-]digits]
      let (mant, expPart) := match lower.splitOn "e" with
        | [m] => (m, none)
        | [m, e] => (m, some e)
        | _ => ("", none)
      let (ip, fp) := match mant.splitOn "." with
        | [i] => (i, "")
        | [i, f] => (i, f)
        | _ => ("", "x")
      let digitsOk (d : String) := d.all Char.isDigit
      if (ip.isEmpty && fp.isEmpty) || !digitsOk ip || !digitsOk fp then none
      else
        let e : Option Int := match expPart with
          | none => some 0
          | some e =>
            let (eneg, ed) := if e.startsWith "-" then (true, e.dropS 1)
              else if e.startsWith "+" then (false, e.dropS 1) else (false, e)
            if ed.isEmpty || !digitsOk ed then none
            else some (if eneg then -(ed.toNat! : Int) else ed.toNat!)
        e.map fun e =>
          let m := (ip ++ fp).toNat!
          let exp : Int := e - fp.length
          if exp ≥ 0 then Float.ofScientific m false exp.toNat
          else Float.ofScientific m true (-exp).toNat
  r.map fun f => if neg then -f else f

def pyFloat? : Json → Option Float
  | .str s => parsePyFloatStr s
  | .num n => some n.toFloat
  | .bool b => some (if b then 1.0 else 0.0)
  | _ => none

end HALean
