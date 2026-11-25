/-
  `input_number`: translated from
  `homeassistant/components/input_number/__init__.py` (`CONFIG_SCHEMA`,
  `_cv_input_number`, `InputNumber`, the `set_value` / `increment` /
  `decrement` entity services) and the parts of `NumberEntity`
  (`components/number/__init__.py`) it uses: `capability_attributes`,
  `state`, `step`. A YAML input number has no device class, so no unit
  conversion happens and `min`/`max`/`value` are the native ones.

  Values are Python floats (`Float`, IEEE doubles, compared as Python
  compares them). The value is never strictly below `min` nor strictly above
  `max` (`Proofs.lean`); it can be NaN, which upstream lets through
  (`set_value` with `value: nan` passes both range checks).
-/
import HALean.Helpers.Common

namespace HALean.Helpers.InputNumber
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "input_number"

inductive Mode where
  | slider | box
  deriving DecidableEq, Inhabited

def Mode.str : Mode → String
  | .slider => "slider" | .box => "box"

structure Config where
  id : String
  name : Option String := none
  min : Float
  max : Float
  initial : Option Float := none
  step : Float := 1.0
  icon : Option String := none
  unit : Option String := none
  mode : Mode := .slider
  deriving Inhabited

/-- `1e-9` as Python reads it. -/
def STEP_MIN : Float := ratToFloat false 1 1000000000

/-- The mapping of the value schema. -/
def fields : List Field :=
  [opt "name" vString, req "min" (.coerce .float), req "max" (.coerce .float),
   opt "initial" (.coerce .float),
   opt "step" (.all [.coerce .float, .range (some (.float STEP_MIN)) none true true]) (some (.int 1)),
   opt "icon" vIcon, opt "unit_of_measurement" vString,
   opt "mode" (.isIn [.str "box", .str "slider"]) (some (.str "slider"))]

def fl (kvs : List (String × Value)) (k : String) : Option Float :=
  match lk kvs k with
  | some (.float f) => some f
  | _ => none

/-- `_cv_input_number` (its message swaps the two bounds, as upstream's). -/
def checkConfig (c : Config) : Except VErr Config := do
  if c.min ≥ c.max then
    invalid s!"Maximum ({floatRepr c.min}) is not greater than minimum ({floatRepr c.max})"
  if let some s := c.initial then
    if s < c.min || s > c.max then
      invalid s!"Initial value {floatRepr s} not in range {floatRepr c.min}-{floatRepr c.max}"
  return c

/-- `vol.All({...}, _cv_input_number)` -/
def decode (id : String) (v : Value) : Except VErr Config := do
  let kvs ← runDict fields v
  checkConfig {
    id, name := lkStr kvs "name", min := (fl kvs "min").getD 0, max := (fl kvs "max").getD 0,
    initial := fl kvs "initial", step := (fl kvs "step").getD 1.0, icon := lkStr kvs "icon",
    unit := lkStr kvs "unit_of_measurement",
    mode := if lkStr kvs "mode" == some "box" then .box else .slider }

def decodeConfig (cfg : Value) : Except ConfigError (List Config) := slugKeys DOMAIN cfg decode

structure Entity where
  cfg : Config
  /-- `_attr_native_value` (set from the start: `async_added_to_hass` falls
  back to `min`) -/
  value : Float
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `async_added_to_hass`: `initial`, else the last state when `float()`
reads it and it is within the bounds, else `min`. -/
def Entity.create (cfg : Config) (lastState : Option String) : Entity :=
  match cfg.initial with
  | some v => { cfg, value := v }
  | none =>
    match lastState.bind parseFloatStr with
    | some v => if cfg.min ≤ v && v ≤ cfg.max then { cfg, value := v } else { cfg, value := cfg.min }
    | none => { cfg, value := cfg.min }

/-- `NumberEntity.state` (the value, a float), stringified. -/
def Entity.state (e : Entity) : String := floatPrec15 e.value

/-- `capability_attributes` (`min`, `max`, `step`, `mode`), then
`extra_state_attributes` (`initial`, `editable`), `unit_of_measurement`,
`icon`, `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("min", .float e.cfg.min), ("max", .float e.cfg.max), ("step", .float e.cfg.step),
   ("mode", .str e.cfg.mode.str),
   ("initial", match e.cfg.initial with | some v => .float v | none => .none),
   ("editable", .bool false)] ++ tailAttrs e.cfg.unit e.cfg.icon e.cfg.name

def write : HM Entity Unit := do
  let e ← getEnt
  emit (.write e.entityId e.state e.attrs false)

/-- The range check of `async_set_native_value`. -/
def inRange (c : Config) (v : Float) : Bool := !(v < c.min || v > c.max)

/-- `async_set_native_value`: a value outside `[min, max]` is refused with
`vol.Invalid`; otherwise it is stored. -/
def setValue (e : Entity) (v : Float) : Except PyErr Entity :=
  if inRange e.cfg v then .ok { e with value := v }
  else .error (pyErr "Invalid"
    s!"Invalid value for {e.entityId}: {floatRepr v} (range {floatRepr e.cfg.min} - {floatRepr e.cfg.max})")

/-- Python's `min(a, b)` and `max(a, b)`: the first argument unless the second
compares strictly smaller (greater). -/
def pyMin (a b : Float) : Float := if b < a then b else a
def pyMax (a b : Float) : Float := if b > a then b else a

/-- `async_increment`: `min(value + step, max)` -/
def increment (e : Entity) : Except PyErr Entity :=
  setValue e (pyMin (e.value + e.cfg.step) e.cfg.max)

/-- `async_decrement`: `max(value - step, min)` -/
def decrement (e : Entity) : Except PyErr Entity :=
  setValue e (pyMax (e.value - e.cfg.step) e.cfg.min)

def services : List (String × List Field) :=
  [("set_value", [req "value" (.coerce .float)]), ("increment", []), ("decrement", [])]

def handle (service : String) (args : List (String × Value)) : HM Entity Unit := do
  let e ← getEnt
  let r := match service, lk args "value" with
    | "set_value", some (.float v) => setValue e v
    | "increment", _ => increment e
    | _, _ => decrement e
  match r with
  | .ok e' => setEnt e'; write
  | .error err => throw err

end HALean.Helpers.InputNumber
