/-
  `counter`: translated from `homeassistant/components/counter/__init__.py`
  (`CONFIG_SCHEMA`, `Counter`: `compute_next_state`, `async_added_to_hass`,
  the `increment` / `decrement` / `reset` / `set_value` entity services).
  The counter has no `reload` service.

  Upstream does not check `initial` against `minimum`/`maximum`, so a counter
  can start (and stay, until it is changed) outside its bounds. Every service
  that changes it leaves it within them (`Proofs.lean`), when
  `minimum ≤ maximum`. A `step` of 0 is allowed; `set_value` then raises
  `ZeroDivisionError` (`value % step`).
-/
import HALean.Helpers.Common

namespace HALean.Helpers.Counter
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "counter"

structure Config where
  id : String
  name : Option String := none
  icon : Option String := none
  initial : Int := 0
  maximum : Option Int := none
  minimum : Option Int := none
  restore : Bool := true
  step : Int := 1
  deriving Inhabited

/-- `cv.positive_int` -/
def positiveInt : Validator := .all [.coerce .int, .range (some (.int 0)) none true true]

def fields : List Field :=
  [opt "icon" vIcon, opt "initial" (.coerce .int) (some (.int 0)), opt "name" vString,
   opt "maximum" (.any [.literal .none, .coerce .int]) (some .none),
   opt "minimum" (.any [.literal .none, .coerce .int]) (some .none),
   opt "restore" vBoolean (some (.bool true)),
   opt "step" positiveInt (some (.int 1))]

def optInt (kvs : List (String × Value)) (k : String) : Option Int :=
  match lk kvs k with
  | some (.int i) => some i
  | _ => none

/-- `vol.All(_none_to_empty_dict, {...})` -/
def decode (id : String) (v : Value) : Except VErr Config := do
  let v := match v with | .none => .dict [] | v => v
  let kvs ← runDict fields v
  return { id, name := lkStr kvs "name", icon := lkStr kvs "icon",
           initial := (optInt kvs "initial").getD 0, maximum := optInt kvs "maximum",
           minimum := optInt kvs "minimum",
           restore := match lk kvs "restore" with | some (.bool b) => b | _ => true,
           step := (optInt kvs "step").getD 1 }

def decodeConfig (cfg : Value) : Except ConfigError (List Config) := slugKeys DOMAIN cfg decode

structure Entity where
  cfg : Config
  /-- `_state` -/
  value : Int
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `compute_next_state`: `max(minimum, state)`, then `min(maximum, state)`. -/
def clamp (c : Config) (v : Int) : Int :=
  let v := match c.minimum with | some m => Max.max m v | none => v
  match c.maximum with | some m => Min.min m v | none => v

/-- `__init__` (`initial`) then `async_added_to_hass`: with `restore`, the
last state's `int()` brought within the bounds. `none` when `int()` fails
(the `ValueError` makes the entity fail to be added). -/
def Entity.create (cfg : Config) (lastState : Option String) : Option Entity :=
  match cfg.restore, lastState with
  | true, some s => (pyIntOfStr? s).map fun i => { cfg, value := clamp cfg i }
  | _, _ => some { cfg, value := cfg.initial }

def Entity.state (e : Entity) : String := toString e.value

/-- `extra_state_attributes` (`editable`, `initial`, `step`, `minimum` and
`maximum` when set), `icon`, `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("editable", .bool false), ("initial", .int e.cfg.initial), ("step", .int e.cfg.step)] ++
  (match e.cfg.minimum with | some m => [("minimum", .int m)] | none => []) ++
  (match e.cfg.maximum with | some m => [("maximum", .int m)] | none => []) ++
  tailAttrs none e.cfg.icon e.cfg.name

def write : HM Entity Unit := do
  let e ← getEnt
  emit (.write e.entityId e.state e.attrs false)

def increment (e : Entity) : Entity := { e with value := clamp e.cfg (e.value + e.cfg.step) }
def decrement (e : Entity) : Entity := { e with value := clamp e.cfg (e.value - e.cfg.step) }
def reset (e : Entity) : Entity := { e with value := clamp e.cfg e.cfg.initial }

/-- `async_set_value`: above `maximum`, below `minimum`, or not a multiple of
`step` is a `ValueError`. -/
def setValue (e : Entity) (v : Int) : Except PyErr Entity :=
  match e.cfg.maximum with
  | some m =>
    if v > m then .error (pyErr "ValueError" s!"Value {v} for {e.entityId} exceeding the maximum value of {m}")
    else rest
  | none => rest
where
  rest : Except PyErr Entity :=
    match e.cfg.minimum with
    | some m =>
      if v < m then .error (pyErr "ValueError" s!"Value {v} for {e.entityId} exceeding the minimum value of {m}")
      else stepCheck
    | none => stepCheck
  stepCheck : Except PyErr Entity :=
    if e.cfg.step == 0 then .error (pyErr "ZeroDivisionError" "division by zero")
    else if v % e.cfg.step != 0 then
      .error (pyErr "ValueError" s!"Value {v} for {e.entityId} is not a multiple of the step size {e.cfg.step}")
    else .ok { e with value := v }

def services : List (String × List Field) :=
  [("increment", []), ("decrement", []), ("reset", []), ("set_value", [req "value" (.coerce .int)])]

def handle (service : String) (args : List (String × Value)) : HM Entity Unit := do
  let e ← getEnt
  match service with
  | "increment" => setEnt (increment e); write
  | "decrement" => setEnt (decrement e); write
  | "reset" => setEnt (reset e); write
  | _ =>
    let v := match lk args "value" with | some (.int i) => i | _ => 0
    match setValue e v with
    | .ok e' => setEnt e'; write
    | .error err => throw err

end HALean.Helpers.Counter
