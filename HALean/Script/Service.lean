/-
  The script service: one pure step function from an input to the new state
  and commands for the I/O shell.

    `Service.step : Service → Input → Service × List Cmd`

  It wraps the automation engine (`HALean/Automation/Engine.lean`), which
  runs the script entities with the same executor (`helpers/script.py`).
  Translated from `homeassistant/components/script/__init__.py`:
  `async_setup` / `_async_process_config` (load and reload), the services,
  and `ScriptEntity.async_added_to_hass` (restoring `last_triggered`).
-/
import HALean.Automation.Engine
import HALean.Script.Config
open Lean

namespace HALean.Script
open HALean.Automation

structure Service where
  engine : Engine := {}
  /-- `RestoreStateData.last_states`: the `last_triggered` (UTC µs) of script
  entities that were removed, by entity id, for when they come back. -/
  restored : List (String × Int) := []
  deriving Inhabited

inductive Input where
  /-- Load `scripts.yaml` (ordered `object_id`, config pairs). `states` are
  HA's states; a `script.*` state there restores that script's
  `last_triggered` (`async_get_last_state`). -/
  | init (scripts : List (String × Json)) (states : List EntityState) (now : Instant)
      (location : Option Sun.Observer := none)
  /-- A call of `script.<service>` from outside (HA, a user, an automation):
  `ServiceRegistry.async_call(..., blocking=True)`. -/
  | call (callId : Nat) (service : String) (data : Json) (returnResponse : Bool) (now : Instant)
  /-- `script.reload` with the new `scripts.yaml`. -/
  | reload (scripts : List (String × Json)) (now : Instant)
  /-- A state change, event, tick or service result, as for automations. -/
  | engine (i : Automation.Input)

/-- Decode every script; the names other scripts pass are allowed in all. -/
def decodeAll (scripts : List (String × Json)) :
    List (String × Except String (ScriptEntity × Automation)) :=
  let extra := passedNames scripts
  scripts.map fun (k, j) => (k, decodeScript k j extra)

/-- `parse_datetime(state.attributes["last_triggered"])` of a state. -/
def lastTriggeredOf (s : EntityState) : Option Int :=
  match s.attr? "last_triggered" with
  | some (.str t) =>
    match (Template.parseDatetime t).run.run' {} with
    | .ok (some (.datetime us (some _))) => some us
    | _ => none
  | _ => none

/-- `EntityComponent.async_add_entities` for new script entities: append
them, restore `last_triggered`, write their states. -/
def addScripts (new : List (ScriptEntity × Automation)) (restored : List (String × Int)) : EM Unit := do
  for (s, a) in new do
    let e ← getE
    let ai := e.automations.length
    let lt := (restored.find? (·.1 == s.entityId)).map (·.2)
    setE { e with automations := e.automations ++ [a], scripts := e.scripts ++ [s],
                  lastTriggered := match lt with
                    | some us => e.lastTriggered ++ [(ai, us)]
                    | none => e.lastTriggered }
    writeEntity ai

def unsupportedCmds (bad : List (String × String)) : List Cmd :=
  bad.map fun (k, why) => .log "unsupported" s!"{k}\t{why}"

/-- `_async_process_config` on reload: a script whose key and raw config
are unchanged keeps its entity (and its runs); the others are removed
(stopping their runs: `async_will_remove_from_hass` → `async_unload`), then
the new and changed ones are added. A removed entity's state becomes
`unavailable`. -/
def reloadScripts (ok : List (ScriptEntity × Automation)) (restored : List (String × Int)) :
    EM (List (String × Int)) := do
  let e ← getE
  -- `find_matches`: each script and each config matches at most once
  let mut matched : List Nat := []
  let mut fresh : List (ScriptEntity × Automation) := []
  for (s, a) in ok do
    let hit := e.scripts.zipIdx.find? fun (p : ScriptEntity × Nat) =>
      p.1.alive && !matched.contains p.2 && p.1.objectId == s.objectId && p.1.raw == s.raw
    match hit with
    | some (_, i) => matched := matched ++ [i]
    | none => fresh := fresh ++ [(s, a)]
  let mut restored := restored
  for (s, i) in e.scripts.zipIdx do
    if !s.alive || matched.contains i then continue
    for r in runsOf (← getE) i do stopRun r.id false
    let e ← getE
    -- `RestoreEntity` keeps the removed entity's last state
    if let some st := e.states.get? s.entityId then
      if let some us := lastTriggeredOf st then
        restored := (restored.filter (·.1 != s.entityId)) ++ [(s.entityId, us)]
    -- `Entity.async_remove`: the entity keeps its registry entry, so its state
    -- becomes `unavailable` (`RegistryEntry.write_unavailable_state`)
    let a := e.automations.getD i default
    let attrs := HALean.Script.unavailableAttributes s a
    setE { e with states := e.states.set { entityId := s.entityId, state := "unavailable",
                                           attributes := attrs, lastChanged := e.now.utc },
                  scripts := e.scripts.set i { s with alive := false } }
    emit [.setState s.entityId "unavailable" attrs]
  addScripts fresh restored
  return restored

/-- Whether `eid` is one of the script entities the service owns. -/
def Service.owns (sv : Service) (eid : String) : Bool :=
  sv.engine.scripts.any fun s => s.alive && s.entityId == eid

/-- One input. Returns the new state, the commands, and the scripts that
were not loaded (object id, reason). -/
def Service.step (sv : Service) (i : Input) : Service × List Cmd × List (String × String) :=
  match i with
  | .init scripts states now loc =>
    let decoded := decodeAll scripts
    let ok := decoded.filterMap fun (_, r) => r.toOption
    let bad := decoded.filterMap fun (k, r) => match r with | .error m => some (k, m) | .ok _ => none
    let restored := states.filterMap fun s =>
      if s.entityId.startsWith "script." then (lastTriggeredOf s).map (s.entityId, ·) else none
    let e0 : Engine := { states := states.map (fun s => (s.entityId, s)), now,
                         lastSec := now.utc / 1000, location := loc }
    let ((), (e, cmds)) := (addScripts ok restored).run (e0, [])
    ({ sv with engine := e, restored }, cmds, bad)
  | .call cid service data rr now =>
    let act : EM Unit := do
      advanceTo now
      let e ← getE
      let svc := service.toLower
      if rr && (svc == "turn_on" || svc == "turn_off" || svc == "toggle") then
        -- `ServiceRegistry.async_call`: `ServiceValidationError` for a
        -- service that supports no response (a script step raises
        -- `vol.Invalid` before it gets there, see `planCall`)
        emit [.callDone cid false .null "ha_error" "An action which does not return responses can't be called with return_response=True"]
        return
      match planCall e.scripts (fun i => !(runsOf e i).isEmpty) service data rr with
      | none =>
        -- `ServiceNotFound`, one of `CONFIGURATION_ERRORS`
        emit [.callDone cid false .null "invalid" s!"Action script.{service} not found"]
      | some ops =>
        callLocal (.external cid rr) ops
        resumeWoken
    let ((), (e, cmds)) := act.run (sv.engine, [])
    ({ sv with engine := e }, cmds, [])
  | .reload scripts now =>
    let decoded := decodeAll scripts
    let ok := decoded.filterMap fun (_, r) => r.toOption
    let bad := decoded.filterMap fun (k, r) => match r with | .error m => some (k, m) | .ok _ => none
    let act : EM (List (String × Int)) := do
      advanceTo now
      let r ← reloadScripts ok sv.restored
      resumeWoken
      return r
    let (restored, (e, cmds)) := act.run (sv.engine, [])
    ({ sv with engine := e, restored }, cmds, bad)
  | .engine ev =>
    -- HALean owns its script entities: HA's echo of their states is ignored
    let ev := match ev with
      | .stateChanged eid _ _ now => if sv.owns eid then .tick now else ev
      | _ => ev
    let (e, cmds) := sv.engine.step ev
    ({ sv with engine := e }, cmds, [])

end HALean.Script
