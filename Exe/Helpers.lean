/-
  `halean-helpers`: the helper integrations (`HALean.Helpers`) as a
  JSON-lines service, the test driver of `tests/differential/test_helpers.py`.

  Each input line is one operation, with the clock given explicitly (`now`,
  µs since the epoch); input is read as Python's `json.loads` reads it
  (`parsePyJson`: `1` is an int, `1.0` a float, dict order kept):

    {"op": "reset"}
    {"op": "setup", "domain", "config", "restore"?: [[entity_id, state, attributes], ...], "now"}
    {"op": "call", "domain", "service", "data", "now"}
    {"op": "tick", "now"}

  Each output line has `outs` (what was observed, in order:
  `["state_changed", entity_id, state, repr(attributes)]`,
  `["event", event_type, repr(data)]`), `logs` (`[level, message]`) and
  `states` (`[entity_id, state, repr(attributes)]` for every helper entity).
  `setup` adds `"ok"` and, when the config is invalid, `"error"`
  (`str(MultipleInvalid)`); `call` adds `"error"`: `null` or
  `{"type", "message"}`. An operation outside the model is answered with
  `{"unsupported": reason}` and changes nothing.
-/
import HALean.Helpers
open Lean HALean HALean.Core HALean.Template HALean.Helpers HALean.Core.ServicesJson

namespace Exe.Helpers

def reprOf (attrs : Attrs) : String := (pyRepr (dictOf attrs)).toOption.getD "<unprintable>"

def outsJson (outs : List Out) : Json × Json :=
  let main := outs.filterMap fun o => match o with
    | .stateChanged eid st attrs => some (Json.arr #[.str "state_changed", .str eid, .str st, .str (reprOf attrs)])
    | .event t d => some (Json.arr #[.str "event", .str t, .str (reprOf d)])
    | .log .. => none
  let logs := outs.filterMap fun o => match o with
    | .log l m => some (Json.arr #[.str l, .str m])
    | _ => none
  (.arr main.toArray, .arr logs.toArray)

def statesJson (h : Helpers) : Json :=
  .arr (h.states.map fun (eid, st, attrs) => Json.arr #[.str eid, .str st, .str (reprOf attrs)]).toArray

def reply (h : Helpers) (outs : List Out) (extra : List (String × Json)) : Json :=
  let (o, l) := outsJson outs
  Json.mkObj (extra ++ [("outs", o), ("logs", l), ("states", statesJson h)])

def getNow (msg : Value) : Except String Int :=
  match msg.get? "now" with
  | some (.int n) => pure n
  | _ => throw "missing 'now' (µs since the epoch)"

def decodeRestore : Option Value → Except String (List (String × Written))
  | none => pure []
  | some (.list xs) => xs.mapM fun x => match x with
    | .list [.str eid, .str st, attrs] => do
      let kvs ← match attrs with
        | .dict _ => match attrs.strItems? with
          | some kvs => pure kvs
          | none => throw "restore: attribute keys must be strings"
        | _ => throw "restore: attributes must be a dict"
      pure (eid, (st, kvs))
    | _ => throw "restore: expected [entity_id, state, attributes]"
  | some _ => throw "restore must be a list"

def step (h : Helpers) (msg : Value) : Except String (Helpers × Json) := do
  match ← getStr msg "op" with
  | "reset" => return ({}, reply {} [] [])
  | "setup" =>
    let _ ← getNow msg
    let domain ← getStr msg "domain"
    let restored ← decodeRestore (msg.get? "restore")
    match h.setup domain ((msg.get? "config").getD .none) restored with
    | .ok h' outs => return (h', reply h' outs [("ok", .bool true)])
    | .invalid m => return (h, reply h [] [("ok", .bool false), ("error", .str m)])
    | .unsupported why => return (h, Json.mkObj [("unsupported", .str why)])
  | "call" =>
    let now ← getNow msg
    let data ← match msg.get? "data" with
      | none => pure []
      | some d => match d.strItems? with
        | some kvs => pure kvs
        | none => throw "data must be a dict with string keys"
    match h.call (← getStr msg "domain") (← getStr msg "service") data now with
    | .ok h' outs err =>
      let e := match err with
        | some e => Json.mkObj [("type", .str e.exception), ("message", .str e.message)]
        | none => .null
      return (h', reply h' outs [("error", e)])
    | .unsupported why => return (h, Json.mkObj [("unsupported", .str why)])
  | "tick" =>
    let (h', outs) := h.tick (← getNow msg)
    return (h', reply h' outs [])
  | op => throw s!"unknown op {op}"

end Exe.Helpers

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (h : Helpers) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trim
  if line.isEmpty then loop stdin stdout h else
  let (h', out) := match parsePyJson line >>= Exe.Helpers.step h with
    | .ok r => r
    | .error e => (h, Json.mkObj [("unsupported", .str s!"bad input: {e}")])
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout h'

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout) {}
