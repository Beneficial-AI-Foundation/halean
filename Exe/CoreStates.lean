/-
  `halean-core-states`: the state machine (`hass.states`) as a JSON-lines
  service, used by the differential test (`tests/differential/test_states.py`).

  One operation per line on stdin; the machine persists between lines.
  Times (`now`) are microseconds since the Unix epoch, UTC: the clock is an
  input, never read.

    {"op": "set", "entity_id": "light.a", "state": "on", "attributes": {...},
     "force_update": false, "context": {"id": "c1", "user_id": null, "parent_id": null},
     "now": 1763656245123456}                         -- async_set(..., timestamp=now/1e6)
    {"op": "set_internal", ...same, "state" must be a string}   -- async_set_internal
    {"op": "remove", "entity_id": "...", "context": {...}?, "now": ...}   -- async_remove
    {"op": "get", "entity_id": "..."}                 -- get → as_dict() or null
    {"op": "is_state", "entity_id": "...", "state": "on"}
    {"op": "entity_ids" | "entity_ids_count" | "all", "domain_filter": null | "light" | ["light", ...]}
    {"op": "reserve", "entity_id": "..."}             -- async_reserve
    {"op": "available", "entity_id": "..."}           -- async_available
    {"op": "inspect", "entity_id": "..."}             -- name, domain, object_id, timestamps,
                                                          as_compressed_state
    {"op": "reset"}                                   -- a new, empty state machine

  One line per operation on stdout:
    {"result": ..., "events": [...]}                  -- events fired, in order
    {"error": {"type": "InvalidEntityFormatError", "message": "..."}, "events": []}
    {"unsupported": "..."}                            -- not translated: rejected
-/
import HALean.Core.StateMachine
import HALean.Core.PyJson
open Lean HALean HALean.Core HALean.Core.StateMachine

def getStr (j : Json) (k : String) : Except String String :=
  match j.getObjVal? k with
  | .ok (.str s) => pure s
  | _ => throw s!"'{k}' must be a string"

def getNow (j : Json) : Except String Int :=
  match j.getObjVal? "now" with
  | .ok (.num n) => if n.exponent == 0 then pure n.mantissa else throw "'now' must be whole microseconds"
  | _ => throw "'now' (microseconds) is required"

def optStr (j : Json) (k : String) : Except String (Option String) :=
  match j.getObjVal? k with
  | .ok (.str s) => pure (some s)
  | .ok .null | .error _ => pure none
  | _ => throw s!"'{k}' must be a string or null"

def getContext (j : Json) : Except String (Option Context) :=
  match j.getObjVal? "context" with
  | .ok .null | .error _ => pure none
  | .ok c@(.obj _) => do
    let id ← match c.getObjVal? "id" with
      | .ok (.str s) => if s.isEmpty then throw "a context id must not be empty (Context() would make a random one)" else pure s
      | _ => throw "a context needs an 'id' (Context() would make a random one)"
    pure (some { id, userId := ← optStr c "user_id", parentId := ← optStr c "parent_id" })
  | _ => throw "'context' must be an object"

def getAttributes (j : Json) : Except String (Option Json) :=
  match j.getObjVal? "attributes" with
  | .ok .null | .error _ => pure none
  | .ok a@(.obj _) => pure (some a)
  | _ => throw "'attributes' must be a mapping or null"

def getFilter (j : Json) : Except String DomainFilter :=
  match j.getObjVal? "domain_filter" with
  | .ok .null | .error _ => pure .all
  | .ok (.str d) => pure (.one d)
  | .ok (.arr ds) => do
    let ds ← ds.toList.mapM fun
      | .str d => pure d
      | _ => throw "'domain_filter' entries must be strings"
    pure (.many ds)
  | _ => throw "'domain_filter' must be null, a string or a list of strings"

/-- JSON text as Python's `json.dumps` writes numbers: a number with a
fractional part in the input (`1.0`) stays a float (`repr(float)`), so the
test can tell `1` from `1.0`. Lean's own printer drops the trailing `.0`. -/
partial def pyJson : Json → String
  | .num n =>
    if n.exponent == 0 then toString n.mantissa
    else HALean.Template.floatRepr
      (HALean.Template.ratToFloat (n.mantissa < 0) n.mantissa.natAbs (10 ^ n.exponent))
  | .arr xs => "[" ++ ", ".intercalate (xs.toList.map pyJson) ++ "]"
  | .obj kvs => "{" ++ ", ".intercalate (kvs.toList.map fun (k, v) =>
      (Json.str k).compress ++ ": " ++ pyJson v) ++ "}"
  | j => j.compress

def errorJson : SMError → Json
  | .invalidEntityFormat m => Json.mkObj [("type", "InvalidEntityFormatError"), ("message", m)]
  | .invalidState m => Json.mkObj [("type", "InvalidStateError"), ("message", m)]
  | .homeAssistant m => Json.mkObj [("type", "HomeAssistantError"), ("message", m)]
  | .unsupported m => Json.mkObj [("type", "unsupported"), ("message", m)]

def inspectJson (s : State) : Json :=
  Json.mkObj [("name", s.name), ("domain", .str s.domain), ("object_id", .str s.objectId),
    ("last_changed_timestamp", tsJson s.lastChanged),
    ("last_updated_timestamp", tsJson s.lastUpdated),
    ("last_reported_timestamp", tsJson s.lastReported),
    ("compressed", s.asCompressedState)]

/-- The outcome of one operation: a result and events, or an error. -/
abbrev Outcome := Except SMError (Json × StateMachine × List SMEvent)

/-- `pv` is the same line as `json.loads` reads it (`HALean.Core.parsePyJson`):
the new state of `set` comes from it, so `1e+16` stays a float and `-0.0`
keeps its sign (Lean's `Json` has neither distinction). -/
def runOp (sm : StateMachine) (pv : HALean.Template.Value) (j : Json) : Except String Outcome := do
  let op ← getStr j "op"
  let pureR (r : Except SMError Json) : Outcome := r.map fun v => (v, sm, [])
  match op with
  | "reset" => pure (.ok (.null, {}, []))
  | "set" | "set_internal" =>
    let eid ← getStr j "entity_id"
    let attrs ← getAttributes j
    let force := match j.getObjVal? "force_update" with | .ok (.bool b) => b | _ => false
    let ctx ← getContext j
    let now ← getNow j
    if op == "set" then
      let some st := pv.get? "state" | throw "'state' is required"
      pure ((sm.asyncSet eid st attrs force ctx now).map fun (sm, ev) => (.null, sm, ev))
    else
      let st ← getStr j "state"
      pure ((sm.asyncSetInternal eid st attrs force ctx now).map fun (sm, ev) => (.null, sm, ev))
  | "remove" =>
    let eid ← getStr j "entity_id"
    let ctx ← getContext j
    let now ← getNow j
    pure ((sm.asyncRemove eid ctx now).map fun (b, sm, ev) => (.bool b, sm, ev))
  | "get" => do
    let eid ← getStr j "entity_id"
    pure (pureR ((sm.get eid).map fun s => (s.map State.asDict).getD .null))
  | "inspect" => do
    let eid ← getStr j "entity_id"
    pure (pureR ((sm.get eid).map fun s => (s.map inspectJson).getD .null))
  | "is_state" => do
    let eid ← getStr j "entity_id"
    let st ← getStr j "state"
    pure (pureR ((sm.isState eid st).map Json.bool))
  | "entity_ids" => do
    let f ← getFilter j
    pure (pureR ((sm.asyncEntityIds f).map fun ids => .arr (ids.map Json.str).toArray))
  | "entity_ids_count" => do
    let f ← getFilter j
    pure (pureR ((sm.asyncEntityIdsCount f).map fun n => toJson n))
  | "all" => do
    let f ← getFilter j
    pure (pureR ((sm.asyncAll f).map fun ss => .arr (ss.map State.asDict).toArray))
  | "reserve" => do
    let eid ← getStr j "entity_id"
    pure ((sm.asyncReserve eid).map fun sm => (.null, sm, []))
  | "available" => do
    let eid ← getStr j "entity_id"
    pure (pureR ((sm.asyncAvailable eid).map Json.bool))
  | _ => throw s!"unknown op '{op}'"

def handleLine (sm : StateMachine) (line : String) : StateMachine × Json :=
  match (do runOp sm (← parsePyJson line) (← Json.parse line)) with
  | .error e => (sm, Json.mkObj [("unsupported", .str e)])
  | .ok (.error (.unsupported m)) => (sm, Json.mkObj [("unsupported", .str m)])
  | .ok (.error e) => (sm, Json.mkObj [("error", errorJson e), ("events", .arr #[])])
  | .ok (.ok (r, sm', ev)) =>
    (sm', Json.mkObj [("result", r), ("events", .arr (ev.map SMEvent.toJson).toArray)])

partial def loop (stdin stdout : IO.FS.Stream) (sm : StateMachine) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trim
  if line.isEmpty then loop stdin stdout sm else
  let (sm', out) := handleLine sm line
  stdout.putStrLn (pyJson out)
  stdout.flush
  loop stdin stdout sm'

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout) {}
