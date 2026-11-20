/-
  Wire protocol between the I/O shell and the engine: JSON lines.
  One input object per line in; one `{"type":"batch","cmds":[...]}` line out.
  See `protocol/schema.json` for the authoritative description.
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

def getNat (j : Json) (k : String) : Except String Nat :=
  match field? j k with
  | some (.num n) => if n.exponent == 0 && n.mantissa ≥ 0 then pure n.mantissa.toNat
                     else pure (n.toFloat.floor.toUInt64.toNat)
  | _ => throw s!"missing or invalid '{k}'"

def getInt (j : Json) (k : String) (d : Int) : Int :=
  match field? j k with
  | some (.num n) => if n.exponent == 0 then n.mantissa else n.toFloat.round.toInt64.toInt
  | _ => d

def decodeInstant (j : Json) : Except String Instant := do
  return { utc := ← getNat j "now", tzOffsetSec := getInt j "tz" 0 }

def optInt (j : Json) (k : String) : Option Int :=
  match field? j k with
  | some (.num n) => if n.exponent == 0 then some n.mantissa else none
  | _ => none

def decodeEntityState (j : Json) : Except String EntityState := do
  let some eid := str? j "entity_id" | throw "state without entity_id"
  let some st := str? j "state" | throw "state without state"
  return { entityId := eid, state := st,
           attributes := (field? j "attributes").getD (Json.mkObj []),
           lastChanged := (getNat j "last_changed").toOption.getD 0,
           lastChangedUs := optInt j "last_changed_us",
           lastUpdatedUs := optInt j "last_updated_us" }

def decodeOptState (j : Json) (k : String) : Except String (Option EntityState) :=
  match field? j k with
  | none | some .null => pure none
  | some v => some <$> decodeEntityState v

def decodeErrKind : Option String → ErrKind
  | some "invalid" => .invalid
  | some "ha_error" => .haError
  | _ => .other

/-- Decode an input. `init` also returns the automations that were rejected. -/
def decodeInput (j : Json) : Except String (Input × List (String × String)) := do
  let some ty := str? j "type" | throw "message without type"
  let now ← decodeInstant j
  match ty with
  | "init" =>
    let raw := ensureList ((field? j "automations").getD .null)
    let mut ok := []
    let mut bad := []
    let sts ← (ensureList ((field? j "states").getD .null)).mapM decodeEntityState
    let eids := automationEntityIds raw (sts.map (·.entityId))
    for (a, i) in raw.zipIdx do
      match decodeAutomation a i (eids.getD i none) with
      | .ok x => ok := ok ++ [x]
      | .error why => bad := bad ++ [((str? a "id").getD "?", why)]
    return (.init ok sts now, bad)
  | "state_changed" =>
    let some eid := str? j "entity_id" | throw "state_changed without entity_id"
    return (.stateChanged eid (← decodeOptState j "old_state") (← decodeOptState j "new_state") now, [])
  | "event" =>
    let some et := str? j "event_type" | throw "event without event_type"
    return (.event et ((field? j "data").getD (Json.mkObj [])) now, [])
  | "tick" => return (.tick now, [])
  | "service_result" =>
    let ok := match field? j "ok" with | some (.bool b) => b | _ => false
    return (.serviceResult (← getNat j "call_id") ok (decodeErrKind (str? j "error_kind"))
      ((str? j "message").getD "") now ((field? j "response").getD .null), [])
  | t => throw s!"unknown message type {t}"

def Cmd.toJson : Cmd → Json
  | .callService cid rid d s data tgt rr => Json.mkObj
      [("type", "call_service"), ("call_id", cid), ("run_id", rid), ("domain", d),
       ("service", s), ("data", data), ("target", tgt), ("return_response", rr)]
  | .fireEvent t data => Json.mkObj [("type", "fire_event"), ("event_type", t), ("data", data)]
  | .automationTriggered id name src => Json.mkObj
      [("type", "automation_triggered"), ("id", id), ("name", name), ("source", src)]
  | .log lvl msg => Json.mkObj [("type", "log"), ("level", lvl), ("message", msg)]

/-- Process one input line. -/
def processLine (e : Engine) (line : String) : Engine × Json :=
  match Json.parse line >>= decodeInput with
  | .error err => (e, Json.mkObj [("type", "error"), ("message", err)])
  | .ok (i, rejected) =>
    let (e', cmds) := e.step i
    let rej := rejected.map fun (id, why) =>
      Json.mkObj [("type", "unsupported"), ("id", id), ("reason", why)]
    (e', Json.mkObj [("type", "batch"),
      ("cmds", Json.arr (rej ++ cmds.map Cmd.toJson).toArray)])

end HALean.Automation
