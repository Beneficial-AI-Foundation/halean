/-
  `input_boolean`: translated from
  `homeassistant/components/input_boolean/__init__.py` (`CONFIG_SCHEMA`,
  `InputBoolean`, the `turn_on` / `turn_off` / `toggle` entity services) and
  `ToggleEntity` (`helpers/entity.py`: `state`, `async_toggle`).

  Only YAML items are modelled (`editable` is false); storage items (the
  UI's helpers) and `input_boolean.reload` are not.
-/
import HALean.Helpers.Common

namespace HALean.Helpers.InputBoolean
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "input_boolean"

/-- One YAML item, validated (`{CONF_ID: id_, **conf}`). -/
structure Config where
  id : String
  name : Option String := none
  initial : Option Bool := none
  icon : Option String := none
  deriving Inhabited

/-- The value schema of `CONFIG_SCHEMA`: `Any({name: cv.string, initial:
cv.boolean, icon: cv.icon}, None)`. -/
def valueSchema : Validator :=
  .any [.dict [opt "name" vString, opt "initial" vBoolean, opt "icon" vIcon], .literal .none]

def decode (id : String) (v : Value) : Except VErr Config := do
  let out ← valueSchema.run .prevent v
  let kvs := (out.strItems?).getD []
  return { id, name := lkStr kvs "name", icon := lkStr kvs "icon",
           initial := match lk kvs "initial" with | some (.bool b) => some b | _ => none }

def decodeConfig (cfg : Value) : Except ConfigError (List Config) := slugKeys DOMAIN cfg decode

/-- `InputBoolean` (from YAML: `editable` is false). -/
structure Entity where
  cfg : Config
  /-- `_attr_is_on` -/
  isOn : Bool
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `__init__` (`config.get(CONF_INITIAL, False)`), then
`async_added_to_hass`: without `initial`, the last state restores it (`on`
or not). -/
def Entity.create (cfg : Config) (lastState : Option String) : Entity :=
  match cfg.initial with
  | some b => { cfg, isOn := b }
  | none => { cfg, isOn := lastState == some "on" }

/-- `ToggleEntity.state` -/
def Entity.state (e : Entity) : String := if e.isOn then "on" else "off"

/-- `extra_state_attributes` (`editable`), then `icon` and `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("editable", .bool false)] ++ tailAttrs none e.cfg.icon e.cfg.name

def write : HM Entity Unit := do
  let e ← getEnt
  emit (.write e.entityId e.state e.attrs false)

/-- `async_turn_on` / `async_turn_off` -/
def turnOn (e : Entity) : Entity := { e with isOn := true }
def turnOff (e : Entity) : Entity := { e with isOn := false }

/-- `ToggleEntity.async_toggle`: off when on, on otherwise. -/
def toggle (e : Entity) : Entity := if e.isOn then turnOff e else turnOn e

/-- The entity services and their schemas (all three take no fields). -/
def services : List (String × List Field) :=
  [("turn_on", []), ("turn_off", []), ("toggle", [])]

/-- Run a service on one entity (the method, then `async_write_ha_state`). -/
def handle (service : String) (_args : List (String × Value)) : HM Entity Unit := do
  let e ← getEnt
  match service with
  | "turn_on" => setEnt (turnOn e)
  | "turn_off" => setEnt (turnOff e)
  | _ => setEnt (toggle e)
  write

end HALean.Helpers.InputBoolean
