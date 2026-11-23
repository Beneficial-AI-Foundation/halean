/-
  Wire protocol of the script service: JSON lines, like the automation
  engine's (`protocol/schema.json`, `script` section). One input object per
  line in; one `{"type":"batch","cmds":[...]}` line out.
-/
import HALean.Script.Service
import HALean.Automation.Protocol
open Lean

namespace HALean.Script
open HALean.Automation

/-- `scripts`: ordered `[object_id, config]` pairs (as `bridge/protocol.py`
sends them), or a mapping (its keys are then sorted). -/
def decodeScripts (j : Json) : Except String (List (String × Json)) :=
  match j with
  | .obj kvs => pure (kvs.toList.map fun (k, v) => (k, v))
  | .arr xs => xs.toList.mapM fun x => match x with
    | .arr #[.str k, v] => pure (k, v)
    | _ => throw "scripts must be [object_id, config] pairs"
  | .null => pure []
  | _ => throw "scripts must be a list of [object_id, config] pairs"

def decodeInput (j : Json) : Except String Input := do
  let some ty := str? j "type" | throw "message without type"
  let now ← decodeInstant j
  match ty with
  | "init" =>
    let sts ← (ensureList ((field? j "states").getD .null)).mapM decodeEntityState
    let loc : Option Sun.Observer := match field? j "location" with
      | some l => do
        let lat ← (field? l "latitude").bind pyNumber?
        let lon ← (field? l "longitude").bind pyNumber?
        let el := ((field? l "elevation").bind pyNumber?).getD 0
        pure { latitude := lat, longitude := lon, elevation := el }
      | none => none
    -- automations run in the same engine: decoded as `halean-automation` does
    let (autos, badAutos, cfgs) ← match field? j "automations" with
      | none => pure ([], [], [])
      | some raw =>
        match HALean.Automation.decodeInput j with
        | .ok (.init autos _ _ _, bad) => pure (autos, bad, ensureList raw)
        | .ok _ => throw "init"
        | .error m => throw m
    return .init (← decodeScripts ((field? j "scripts").getD .null)) sts now loc autos badAutos cfgs
  | "call" =>
    let some svc := str? j "service" | throw "call without service"
    let rr := match field? j "return_response" with | some (.bool b) => b | _ => false
    return .call (← getNat j "call_id") svc ((field? j "data").getD (Json.mkObj [])) rr now
  | "reload" => return .reload (← decodeScripts ((field? j "scripts").getD .null)) now
  | _ =>
    -- state_changed, event, tick, service_result: as for automations
    let (i, _) ← HALean.Automation.decodeInput j
    return .engine i

/-- Process one input line. -/
def processLine (sv : Service) (line : String) : Service × Json :=
  match Json.parse line >>= decodeInput with
  | .error err => (sv, Json.mkObj [("type", "error"), ("message", err)])
  | .ok i =>
    let (sv', cmds, rejected) := sv.step i
    let rej := rejected.map fun (id, why) =>
      Json.mkObj [("type", "unsupported"), ("id", id), ("reason", why)]
    (sv', Json.mkObj [("type", "batch"),
      ("cmds", Json.arr (rej ++ cmds.map Cmd.toJson).toArray)])

end HALean.Script
