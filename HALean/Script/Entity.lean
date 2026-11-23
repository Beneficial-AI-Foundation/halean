/-
  The script entity and its services, as pure functions. Translated from
  `homeassistant/components/script/__init__.py` (`ScriptEntity`, the
  `turn_on` / `turn_off` / `toggle` service handlers) and the parts of
  `helpers/entity.py` / `helpers/service.py` they use.

  The engine (`HALean/Automation/Engine.lean`) runs script entities with
  the same executor as automations. When a run calls a `script.*` service,
  or the shell calls one, `planCall` says what the handler does, as a list
  of `LocalOp`s that the engine carries out (`Script.async_run`,
  `Script.async_stop`). Nothing here does I/O or reads a clock.
-/
import HALean.Automation.Script
open Lean

namespace HALean.Script
open HALean.Automation

/-- One configured script entity (`ScriptEntity`). Its sequence, mode,
`max`, alias and `variables` live in the engine's `Automation` at the same
index; this is what the script component adds. -/
structure ScriptEntity where
  /-- The key in `scripts.yaml` (`unique_id`, and the service name). -/
  objectId : String
  /-- `ENTITY_ID_FORMAT.format(key)` -/
  entityId : String
  /-- `cfg.get(CONF_ICON)` -/
  icon : Option String := none
  /-- `raw_config`, compressed, to match configurations on reload. -/
  raw : String := ""
  /-- False once the entity was removed by a reload. -/
  alive : Bool := true
  deriving Repr, Inhabited

/-- `Script.supports_max` -/
def supportsMax (m : Mode) : Bool := m == .parallel || m == .queued

def modeStr : Mode → String
  | .single => "single" | .restart => "restart" | .queued => "queued" | .parallel => "parallel"

/-- The state attributes `async_write_ha_state` writes for a script entity:
`extra_state_attributes` (`last_triggered`, `mode`, `current`, `max` when
the mode supports it), then `icon` and `friendly_name`. `last_action` is
not modelled (see the README); `last_triggered` is written as the ISO
string HA's JSON encoder gives it. -/
def entityAttributes (s : ScriptEntity) (a : Automation) (current : Nat)
    (lastTriggered : Option Int) : Json :=
  Json.mkObj <|
    [("last_triggered", match lastTriggered with
        | some us => Json.str (Template.isoformat us (some 0))
        | none => Json.null),
     ("mode", Json.str (modeStr a.mode)), ("current", (current : Json))] ++
    (if supportsMax a.mode then [("max", (a.maxRuns : Json))] else []) ++
    (match s.icon with | some i => [("icon", Json.str i)] | none => []) ++
    [("friendly_name", Json.str a.alias)]

/-- `RegistryEntry.write_unavailable_state`: what is left of a removed script
entity (it keeps its entity registry entry): `restored`, the `icon` and the
name it was registered with. -/
def unavailableAttributes (s : ScriptEntity) (a : Automation) : Json :=
  Json.mkObj <| [("restored", Json.bool true)] ++
    (match s.icon with | some i => [("icon", Json.str i)] | none => []) ++
    [("friendly_name", Json.str a.alias)]

/-- `ScriptEntity.is_on` (`Script.is_running`) as the state string. -/
def entityState (current : Nat) : String := if current > 0 then "on" else "off"

/-- `this` as `ScriptEntity._async_run` builds it: the entity's
`state.as_dict()` before the run is added. `last_triggered` is a datetime
there. `last_action` is set while runs are in flight, to a value HALean
does not model, so it is opaque then. Timestamps and the context are opaque,
as for automations. -/
def scriptThis (s : ScriptEntity) (a : Automation) (current : Nat)
    (lastTriggered : Option Int) : Template.Value :=
  let lt : Template.Value := match lastTriggered with
    | some us => .datetime us (some 0)
    | none => .none
  let attrs : List (String × Template.Value) :=
    [("last_triggered", lt), ("mode", .str (modeStr a.mode)), ("current", .int current)] ++
    (if supportsMax a.mode then [("max", .int a.maxRuns)] else []) ++
    (if current > 0 then [("last_action", .opaque "this.attributes.last_action")] else []) ++
    (match s.icon with | some i => [("icon", .str i)] | none => []) ++
    [("friendly_name", .str a.alias)]
  .dict ([("entity_id", Template.Value.str s.entityId), ("state", .str (entityState current)),
    ("attributes", .dict (attrs.map fun (k, v) => (.str k, v))),
    ("last_changed", .opaque "this.last_changed"), ("last_reported", .opaque "this.last_reported"),
    ("last_updated", .opaque "this.last_updated"), ("context", .opaque "this.context")].map
    fun (k, v) => (.str k, v))

/-- What a call to a `script.*` service does, step by step. -/
inductive LocalOp where
  /-- `ScriptEntity._async_start_run`: fire `script_started`, then
  `Script.async_run` of the entity at `idx` with these run variables. With
  `wait`, the caller waits for the run's end and gets its response. -/
  | start (idx : Nat) (vars : List (String × Template.Value)) (wait : Bool)
  /-- `ScriptEntity.async_turn_off` (`Script.async_stop`) -/
  | stop (idx : Nat)
  /-- The call raises before the handler runs (schema errors, ...). -/
  | fail (k : ErrKind) (msg : String)
  deriving Repr, Inhabited

/-- The services `async_setup` registers for the domain itself. -/
def DOMAIN_SERVICES : List String := ["turn_on", "turn_off", "toggle", "reload"]

/-- `cv.ENTITY_SERVICE_FIELDS` -/
def ENTITY_SERVICE_FIELDS : List String := ["entity_id", "device_id", "area_id", "floor_id", "label_id"]

/-- A JSON object as run variables (`service.data`). -/
def jsonVars (j : Json) : List (String × Template.Value) :=
  match j with
  | .obj kvs => kvs.toList.map fun (k, v) => (k, Template.Value.ofJson v)
  | _ => []

/-- `cv.comp_entity_ids`: `all` / `none` (any case), or a comma-separated
string or list of entity ids, lower-cased. `none` in the result is
`ENTITY_MATCH_ALL`. -/
def compEntityIds (j : Json) : Except String (Option (List String)) := do
  let one (x : Json) : Except String String := match x with
    | .str s =>
      let s := s.trim.toLower
      if Template.validEntityId s then pure s else throw s!"Entity ID {s} is an invalid entity ID"
    | x => throw s!"Entity ID {x.compress} is an invalid entity ID"
  match j with
  | .str s =>
    if s.toLower == "all" then return none
    if s.toLower == "none" then return some []
    -- `ensure_list_csv`
    return some (← (s.splitOn ",").mapM (one ∘ Json.str))
  | .arr xs => return some (← xs.toList.mapM one)
  | x => throw s!"Entity ID {x.compress} is an invalid entity ID"

/-- A call's `target` as the action schema leaves it
(`_TARGET_SERVICE_FIELDS_TEMPLATED`): `entity_id` through
`cv.comp_entity_ids_or_uuids` (`all`/`none` lower-cased, else a list, from a
comma-separated string), the other ids through `vol.Any("none",
vol.All(cv.ensure_list, [str]))`. A templated target was already rendered
into lists (`normalizeTarget`). The script service sees the target merged
into the call data, so the difference shows. -/
def normalizeTargetIds (target : Json) : Json :=
  match target with
  | .obj kvs => Json.mkObj <| kvs.toList.map fun (k, v) =>
    if k == "entity_id" then
      match v with
      | .str s =>
        if s.toLower == "all" || s.toLower == "none" then (k, .str s.toLower)
        else (k, .arr ((s.splitOn ",").map (fun x => Json.str x.trim.toLower)).toArray)
      | .arr xs => (k, .arr (xs.map fun x => match x with | .str s => .str s.toLower | x => x))
      | v => (k, v)
    else if ENTITY_SERVICE_FIELDS.contains k then
      match v with
      | .str s => if s == "none" then (k, v) else (k, .arr #[v])
      | v => (k, v)
    else (k, v)
  | t => t

/-- `EntityComponent.async_extract_from_service` (`service.async_extract_entities`):
the available script entities the call targets, in the component's order.
Groups would be expanded (`expand_group`); HALean has no group model, so
a `group.*` target is an error. -/
def extractTargets (scripts : List ScriptEntity) (data : Json) : Except String (List Nat) := do
  for k in ["device_id", "area_id", "floor_id", "label_id"] do
    if (field? data k).isSome then throw s!"HALean does not support '{k}' targets for script services"
  let ids ← match field? data "entity_id" with
    | some v => compEntityIds v
    | none => pure (some [])
  let live := scripts.zipIdx.filter (·.1.alive)
  match ids with
  | none => return live.map (·.2)
  | some ids =>
    if ids.any (·.startsWith "group.") then
      throw "HALean does not expand groups in script service targets"
    return (live.filter fun (p : ScriptEntity × Nat) => ids.contains p.1.entityId).map (·.2)

/-- What a call to `script.<service>` with `data` (target merged in, as
`ServiceRegistry.async_call` does) runs. `running i`: whether script `i` is
on. `none`: the service is not one of HALean's scripts (HA handles it).

  * `script.<object_id>`: `ScriptEntity._service_handler` (`wait=True`,
    the call data are the run variables, schema `vol.Schema(dict)`);
  * `turn_on`: `turn_on_service` (`wait=False`, `variables` from the data);
  * `turn_off`: `turn_off_service`;
  * `toggle`: `toggle_service` (`ToggleEntity.async_toggle`, never with
    variables).

`turn_on`/`turn_off`/`toggle` use `SCRIPT_TURN_ONOFF_SCHEMA` and support
no response: asking for one is the `vol.Invalid` that
`_async_step_call_service` raises. -/
def planCall (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (returnResponse : Bool) : Option (List LocalOp) :=
  let service := service.toLower
  if service == "turn_on" || service == "turn_off" || service == "toggle" then
    some <| Id.run do
      if returnResponse then
        return [.fail .invalid s!"Script does not support 'response_variable' for service 'script.{service}' which does not support response data."]
      -- `make_entity_service_schema({vol.Optional(ATTR_VARIABLES): {str: cv.match_all}})`
      let keys : List String := match data with | .obj kvs => kvs.toList.map (fun (k, _) => k) | _ => []
      for k in keys do
        if !(ENTITY_SERVICE_FIELDS.contains k || k == "variables" || k == "metadata") then
          return [.fail .invalid s!"extra keys not allowed @ data['{k}']"]
      if !keys.any ENTITY_SERVICE_FIELDS.contains then
        return [.fail .invalid s!"must contain at least one of {", ".intercalate ENTITY_SERVICE_FIELDS}."]
      let vars ← match field? data "variables" with
        | none => pure []
        | some v@(.obj _) => pure (jsonVars v)
        | some _ => return [.fail .invalid "expected a dictionary for dictionary value @ data['variables']"]
      match extractTargets scripts data with
      | .error m => return [.fail .other m]
      | .ok targets =>
        return targets.map fun i =>
          if service == "turn_on" then .start i vars false
          else if service == "turn_off" then .stop i
          else if running i then .stop i else .start i [] false
  else
    match scripts.zipIdx.find? (fun (p : ScriptEntity × Nat) => p.1.alive && p.1.objectId == service) with
    | some (_, i) => some [.start i (jsonVars data) true]
    | none => none

/-- What a `wait=True` call returns to its caller, as `_service_handler` and
`ServiceRegistry.async_call` shape it: with `return_response`, the run's
response or `{}` when it is falsy, which must be a dict; without, `None`. -/
def callResponse (returnResponse : Bool) (resp : Template.Value) :
    Except String Template.Value :=
  if !returnResponse then .ok .none
  else
    let r := if Template.truthy resp then resp else .dict []
    match r with
    | .dict _ => .ok r
    | v => .error s!"Service response data expected a dictionary, was {Template.typeName v}"

end HALean.Script
