/-
  `halean-core-events`: the event bus (`HALean.Core.EventBus`) over JSON lines.

  One operation per line on stdin, each with the clock reading `now`
  (microseconds since the epoch):
    {"op": "listen", "now": 0, "id": "a", "event_type": "x",
     "filter": {"eq": {"k": 1}}, "react": [...], "react_times": 1}
    {"op": "listen_once", "now": 0, "id": "b", "event_type": "*"}
    {"op": "unsub", "now": 0, "id": "a"}
    {"op": "fire", "now": 0, "event_type": "x", "data": {...}, "origin": "remote",
     "context": {"id": "c1", "user_id": null, "parent_id": null}, "time_fired": 0}
    {"op": "listeners", "now": 0}
    {"op": "init", "listeners": [["*", 0], ["logging_changed", 1]]}
  Filters: true, false, {"eq": {...}}, {"has": "k"}, {"raise": true}; with
  "filter_callback": false the filter is not a `@callback`.
  Reactions (run in order by a listener on each receipt, up to "react_times"):
    {"fire": {<fire arguments>, "context": "inherit" | {...}}}
    {"listen": {<listen arguments>}}, {"listen_once": {...}}, {"unsub": "id"},
    {"raise": "HomeAssistantError"}
  One line per operation on stdout:
    {"result": {"ok": true} | {"error": "TypeError"} | {"listeners": [["x", 1], ...]},
     "deliveries": [{"listener": "a", "event": <Event.as_dict()>}, ...],
     "logs": ["Error running job: HomeAssistantError", ...]}
    {"unsupported": "..."}   -- input outside the model
-/
import HALean.Core.EventBus
open Lean HALean.Core.EventBus

namespace Exe.CoreEvents
open HALean HALean.Core

def errOfName : String → Except String Err
  | "HomeAssistantError" => .ok .homeAssistantError
  | "ValueError" => .ok .valueError
  | "RuntimeError" => .ok .runtimeError
  | "TypeError" => .ok .typeError
  | "KeyError" => .ok .keyError
  | n => .error s!"unknown exception {n}"

def optStr (j : Json) (k : String) : Except String (Option String) :=
  match j.getObjVal? k with
  | .ok .null | .error _ => .ok none
  | .ok (.str s) => .ok (some s)
  | .ok _ => .error s!"{k} must be a string"

def optNat (j : Json) (k : String) : Except String (Option Nat) :=
  match j.getObjVal? k with
  | .ok .null | .error _ => .ok none
  | .ok (.num n) => if n.exponent == 0 && n.mantissa ≥ 0 then .ok (some n.mantissa.toNat)
                    else .error s!"{k} must be a non-negative integer"
  | .ok _ => .error s!"{k} must be an integer"

def decodeContext (j : Json) : Except String Context := do
  let some id ← optStr j "id" | throw "a context needs an id"
  if id.isEmpty then throw "a context needs a non-empty id"
  return { id, userId := ← optStr j "user_id", parentId := ← optStr j "parent_id" }

def decodeFire (j : Json) (inListener : Bool) : Except String FireArgs := do
  let et ← j.getObjValAs? String "event_type"
  let data ← match j.getObjVal? "data" with
    | .ok .null | .error _ => pure none
    | .ok (.obj kvs) => pure (some (Json.obj kvs))
    | .ok _ => throw "event data must be an object or null"
  let origin ← match ← optStr j "origin" with
    | none | some "local" => pure Origin.local
    | some "remote" => pure .remote
    | some o => throw s!"unknown origin {o}"
  let context ← match j.getObjVal? "context" with
    | .ok .null | .error _ => pure CtxArg.none
    | .ok (.str "inherit") =>
      if inListener then pure .inherit else throw "context 'inherit' only in a listener"
    | .ok c => pure (CtxArg.given (← decodeContext c))
  return { eventType := et, data, origin, context, timeFired := ← optNat j "time_fired" }

def decodeFilter (j : Json) : Except String (Option FilterSpec) := do
  let isCallback := match j.getObjVal? "filter_callback" with
    | .ok (.bool false) => false
    | _ => true
  let f ← match j.getObjVal? "filter" with
    | .error _ | .ok .null => return none
    | .ok (.bool b) => pure (Filter.const b)
    | .ok (.obj _) =>
      let f := j.getObjValD "filter"
      match f.getObjVal? "eq", f.getObjVal? "has", f.getObjVal? "raise" with
      | .ok (.obj kvs), _, _ => pure (.eq (kvs.toArray.toList.map fun ⟨k, v⟩ => (k, v)))
      | _, .ok (.str k), _ => pure (.has k)
      | _, _, .ok (.bool true) => pure .raises
      | _, _, _ => throw "unknown filter"
    | .ok _ => throw "unknown filter"
  return some { filter := f, isCallback }

mutual
partial def decodeListen (j : Json) (once : Bool) : Except String Reaction := do
  let id ← j.getObjValAs? String "id"
  let et ← j.getObjValAs? String "event_type"
  let filter ← decodeFilter j
  let ri ← match j.getObjVal? "run_immediately" with
    | .ok (.bool b) => pure (some b)
    | .ok .null | .error _ => pure none
    | .ok _ => throw "run_immediately must be a bool"
  let react ← match j.getObjVal? "react" with
    | .ok (.arr rs) => rs.toList.mapM decodeReaction
    | .ok .null | .error _ => pure []
    | .ok _ => throw "react must be a list"
  return .listen id et once filter ri react (← optNat j "react_times")

partial def decodeReaction (j : Json) : Except String Reaction := do
  if let .ok f := j.getObjVal? "fire" then return .fire (← decodeFire f true)
  if let .ok l := j.getObjVal? "listen" then return ← decodeListen l false
  if let .ok l := j.getObjVal? "listen_once" then return ← decodeListen l true
  if let .ok (.str id) := j.getObjVal? "unsub" then return .unsub id
  if let .ok (.str e) := j.getObjVal? "raise" then return .raise (← errOfName e)
  throw s!"unknown reaction {j.compress}"
end

def decodeOp (j : Json) : Except String (Nat × Op) := do
  let now := (← optNat j "now").getD 0
  let op ← match ← j.getObjValAs? String "op" with
    | "listen" => pure (Op.call (← decodeListen j false))
    | "listen_once" => pure (.call (← decodeListen j true))
    | "unsub" => pure (.call (.unsub (← j.getObjValAs? String "id")))
    | "fire" => pure (.fire (← decodeFire j false))
    | "listeners" => pure .listeners
    | "init" =>
      let ls ← j.getObjValAs? (Array Json) "listeners"
      let counts ← ls.toList.mapM fun p => do
        let et ← p.getArrVal? 0 >>= (·.getStr?)
        let n ← p.getArrVal? 1 >>= (·.getNat?)
        pure (et, n)
      pure (.init counts)
    | o => throw s!"unknown op {o}"
  return (now, op)

def logStr : LogEntry → String
  | .filterError e => s!"Error in event filter: {e.name}"
  | .jobError e => s!"Error running job: {e.name}"
  | .removeUnknown _ => "Unable to remove unknown job listener"

def resultJson : Result → Json
  | .ok => Json.mkObj [("ok", true)]
  | .err e => Json.mkObj [("error", e.name)]
  | .listeners cs => Json.mkObj [("listeners", Json.arr (cs.map fun (et, n) =>
      Json.arr #[.str et, (n : Json)]).toArray)]

/-- Handle one line; returns the new bus and the output line. -/
def handleLine (b : Bus) (line : String) : Bus × Json :=
  match Json.parse line >>= decodeOp with
  | .error e => (b, Json.mkObj [("unsupported", e)])
  | .ok (now, op) =>
    let (b', res) := step now b op
    let newDeliv := (b'.deliveries.take (b'.deliveries.length - b.deliveries.length)).reverse
    let newLogs := (b'.logs.take (b'.logs.length - b.logs.length)).reverse
    (b', Json.mkObj [
      ("result", resultJson res),
      ("deliveries", Json.arr (newDeliv.map fun d =>
        Json.mkObj [("listener", .str d.listener), ("event", d.event.asDict)]).toArray),
      ("logs", Json.arr (newLogs.map fun l => Json.str (logStr l)).toArray)])

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (b : Bus) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trimAscii.toString
  if line.isEmpty then loop stdin stdout b else
  let (b', out) := handleLine b line
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout b'

end Exe.CoreEvents

def main : IO Unit := do
  Exe.CoreEvents.loop (← IO.getStdin) (← IO.getStdout) Bus.new
