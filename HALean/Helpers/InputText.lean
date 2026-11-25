/-
  `input_text`: translated from
  `homeassistant/components/input_text/__init__.py` (`CONFIG_SCHEMA`,
  `_cv_input_text`, `InputText`, the `set_value` entity service) and the
  parts of `TextEntity` (`components/text/__init__.py`) it uses:
  `capability_attributes`, `min`, `max`, `pattern_cmp` and `state`.

  `InputText.async_set_value` checks the length only (a value of the wrong
  length is dropped with a warning). The pattern is checked when the state is
  written (`TextEntity.state`), after the value was stored: a value that does
  not match makes the service call raise `ValueError`, the state machine keeps
  the old state, and the entity keeps the new value. An initial value that
  does not match makes the entity fail to be added (upstream logs the error;
  the other entities are added).

  Patterns are matched by `HALean.Helpers.Pattern` (a subset of Python's
  `re`); a config with a pattern outside it is refused.
-/
import HALean.Helpers.Common
import HALean.Helpers.Pattern

namespace HALean.Helpers.InputText
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "input_text"

/-- `MAX_LENGTH_STATE_STATE` -/
def MAX_LEN : Int := 255

inductive Mode where
  | text | password
  deriving DecidableEq, Inhabited

def Mode.str : Mode → String
  | .text => "text" | .password => "password"

structure Config where
  id : String
  name : Option String := none
  min : Int := 0
  max : Int := 100
  initial : Option String := none
  icon : Option String := none
  unit : Option String := none
  /-- the pattern and its compiled form -/
  pattern : Option (String × Rx) := none
  mode : Mode := .text
  deriving Inhabited

def fields : List Field :=
  [opt "name" vString,
   opt "min" (.all [.coerce .int, .range (some (.int 0)) (some (.int MAX_LEN)) true true]) (some (.int 0)),
   opt "max" (.all [.coerce .int, .range (some (.int 1)) (some (.int MAX_LEN)) true true]) (some (.int 100)),
   opt "initial" vString, opt "icon" vIcon, opt "unit_of_measurement" vString,
   opt "pattern" vString,
   opt "mode" (.isIn [.str "text", .str "password"]) (some (.str "text"))]

def int (kvs : List (String × Value)) (k : String) (d : Int) : Int :=
  match lk kvs k with
  | some (.int i) => i
  | _ => d

/-- `vol.All(lambda value: value or {}, {...}, _cv_input_text)` (the
message of the first check swaps the bounds, as upstream's). -/
def decode (id : String) (v : Value) : Except VErr Config := do
  let v := if truthy v then v else .dict []
  let kvs ← runDict fields v
  let min := int kvs "min" 0
  let max := int kvs "max" 100
  if min > max then invalid s!"Max len ({min}) is not greater than min len ({max})"
  let initial := lkStr kvs "initial"
  if let some s := initial then
    if (s.length : Int) < min || (s.length : Int) > max then
      invalid s!"Initial value {s} length not in range {min}-{max}"
  let pattern ← match lkStr kvs "pattern" with
    | none => pure none
    | some p => match Pattern.parse p with
      | .ok rx => pure (some (p, rx))
      | .error why => throw (.unsupported s!"the pattern {strRepr p} is outside the modelled regex subset ({why})")
  return { id, name := lkStr kvs "name", min, max, initial, icon := lkStr kvs "icon",
           unit := lkStr kvs "unit_of_measurement", pattern,
           mode := if lkStr kvs "mode" == some "password" then .password else .text }

def decodeConfig (cfg : Value) : Except ConfigError (List Config) := slugKeys DOMAIN cfg decode

structure Entity where
  cfg : Config
  /-- `_attr_native_value` -/
  value : Option String
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `__init__` then `async_added_to_hass`: `initial`, else the last state
(whatever it is, `unknown` included) when its length is within the bounds. -/
def Entity.create (cfg : Config) (lastState : Option String) : Entity :=
  match cfg.initial with
  | some v => { cfg, value := some v }
  | none =>
    match lastState with
    | some s => if cfg.min ≤ s.length && (s.length : Int) ≤ cfg.max then { cfg, value := some s }
                else { cfg, value := none }
    | none => { cfg, value := none }

/-- `TextEntity.min` / `max` -/
def Entity.minLen (e : Entity) : Int := Max.max e.cfg.min 0
def Entity.maxLen (e : Entity) : Int := Min.min e.cfg.max MAX_LEN

/-- `TextEntity.state`: the value, which must have the right length and
match the pattern (`ValueError` otherwise). -/
def Entity.state (e : Entity) : Except PyErr String :=
  match e.value with
  | none => .ok STATE_UNKNOWN
  | some v =>
    if (v.length : Int) < e.minLen then
      .error (pyErr "ValueError" s!"Entity {e.entityId} provides state {v} which is too short (minimum length {e.minLen})")
    else if (v.length : Int) > e.maxLen then
      .error (pyErr "ValueError" s!"Entity {e.entityId} provides state {v} which is too long (maximum length {e.maxLen})")
    else match e.cfg.pattern with
      | some (p, rx) =>
        if Pattern.isMatch rx v then .ok v
        else .error (pyErr "ValueError" s!"Entity {e.entityId} provides state {v} which does not match expected pattern {p}")
      | none => .ok v

/-- `capability_attributes` (`mode`, `min`, `max`, `pattern`), `editable`,
`unit_of_measurement`, `icon`, `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("mode", .str e.cfg.mode.str), ("min", .int e.minLen), ("max", .int e.maxLen),
   ("pattern", match e.cfg.pattern with | some (p, _) => .str p | none => .none),
   ("editable", .bool false)] ++ tailAttrs e.cfg.unit e.cfg.icon e.cfg.name

def write : HM Entity Unit := do
  let e ← getEnt
  match e.state with
  | .ok s => emit (.write e.entityId s e.attrs false)
  | .error err => throw err

/-- `InputText.async_set_value`: a value of the wrong length is dropped
with a warning (nothing is written); otherwise it is stored. -/
def setValue (e : Entity) (v : String) : Option Entity :=
  if (v.length : Int) < e.cfg.min || (v.length : Int) > e.cfg.max then none
  else some { e with value := some v }

def services : List (String × List Field) := [("set_value", [req "value" vString])]

def handle (_service : String) (args : List (String × Value)) : HM Entity Unit := do
  let e ← getEnt
  let v := (lkStr args "value").getD ""
  match setValue e v with
  | none => emit (.log "warning" s!"Invalid value: {v} (length range {e.cfg.min} - {e.cfg.max})")
  | some e' => setEnt e'; write

end HALean.Helpers.InputText
