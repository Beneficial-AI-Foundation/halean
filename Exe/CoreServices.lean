/-
  `halean-core-services`: the service registry as a JSON-lines service.

  Each input line is one operation on the registry, with the clock given
  explicitly (`now`, ms since the epoch):

    {"op": "register", "domain", "service", "handler", "schema"?, "supports_response"?, "now"}
    {"op": "remove", "domain", "service", "now"}
    {"op": "has", "domain", "service", "now"}
    {"op": "supports_response", "domain", "service", "now"}
    {"op": "list", "now"}                       -- async_services()
    {"op": "list_domain", "domain", "now"}      -- async_services_for_domain()
    {"op": "call", "domain", "service", "data"?, "target"?, "blocking"?,
     "return_response"?, "context"?, "now"}

  `handler` is `{"return": <value>}`, `{"echo": true}` or
  `{"raise": "<exception>", "message": "..."}`; `schema` is
  `{"fields": [<field>, ...], "extra"?}` (`HALean.Core.ServicesJson`: fields
  with types or validators, markers and defaults). A call whose data the
  schema model cannot validate exactly is `unsupported`.

  Each output line is `{"ok": true, "result", "events", "logs"}` or
  `{"ok": false, "error": {...}, "events", "logs"}`. Python values (responses,
  event data) are written as their `repr()`, so dict order and int/float are
  compared exactly. An operation outside the modelled subset is answered with
  `{"unsupported": reason}` and changes nothing.
-/
import HALean.Core.ServicesJson
open Lean HALean HALean.Core HALean.Template HALean.Core.ServicesJson

namespace Exe.CoreServices
open HALean HALean.Core

def reply (result : Except PyError Json) (events : List FiredEvent := []) (logs : List LogRecord := []) : Json :=
  let base := match result with
    | .ok r => [("ok", Json.bool true), ("result", r)]
    | .error e => [("ok", .bool false), ("error", errorJson e)]
  Json.mkObj (base ++ [("events", .arr (events.map eventJson).toArray),
                       ("logs", .arr (logs.map logJson).toArray)])

def servicesJson (svcs : List (String × Service)) : Json :=
  .arr (svcs.map fun (s, svc) => Json.arr #[.str s, .str svc.supportsResponse.value,
    .bool svc.schema.isSome]).toArray

/-! ## One operation -/

def step (r : Registry) (msg : Value) : Except String (Registry × Json) := do
  let now ← match msg.get? "now" with
    | some (.int n) => if n ≥ 0 then pure n.toNat else throw "'now' must be a non-negative integer"
    | _ => throw "missing 'now' (ms since the epoch)"
  match ← getStr msg "op" with
  | "register" =>
    let domain ← getName msg "domain"
    let service ← getName msg "service"
    let handler ← decodeHandler (msg.get? "handler")
    let schema ← decodeSchema (msg.get? "schema")
    -- building the schema raises `SchemaError` (the harness builds it before
    -- `async_register`, so nothing is registered)
    if let some m := schema.bind SchemaSpec.buildError? then
      return (r, reply (.error { exception := "SchemaError", message := m }))
    let sr ← match msg.get? "supports_response" with
      | none => pure SupportsResponse.none
      | some (.str s) => match SupportsResponse.ofString? s with
        | some sr => pure sr
        | none => throw s!"unknown supports_response {s}"
      | _ => throw "'supports_response' must be a string"
    let (r, evs) := r.register domain service { handler, schema, supportsResponse := sr } now
    return (r, reply (.ok .null) evs)
  | "remove" =>
    let (r, evs, logs) := r.remove (← getName msg "domain") (← getName msg "service") now
    return (r, reply (.ok .null) evs logs)
  | "has" =>
    return (r, reply (.ok (.bool (r.hasService (← getName msg "domain") (← getName msg "service")))))
  | "supports_response" =>
    let res := r.supportsResponse (← getName msg "domain") (← getName msg "service")
    return (r, reply (res.map fun sr => .str sr.value))
  | "list" =>
    return (r, reply (.ok (.arr (r.asyncServices.map fun (d, svcs) =>
      Json.arr #[.str d, servicesJson svcs]).toArray)))
  | "list_domain" =>
    return (r, reply (.ok (servicesJson (r.asyncServicesForDomain (← getName msg "domain")))))
  | "call" =>
    let args : CallArgs := {
      domain := ← getName msg "domain", service := ← getName msg "service",
      data := ← getDict? msg "data", target := ← getDict? msg "target",
      blocking := ← getBool msg "blocking" false,
      returnResponse := ← getBool msg "return_response" false,
      context := ← decodeContext (msg.get? "context") }
    if let some why := r.unsupportedCall? args then throw why
    let out := r.asyncCall args now
    return (r, reply (out.result.map fun v => .str (reprOr v)) out.events out.logs)
  | op => throw s!"unknown op {op}"

/-- One input line to the new registry and one output line. -/
def processLine (r : Registry) (line : String) : Registry × Json :=
  match parsePyJson line with
  | .error e => (r, Json.mkObj [("type", .str "error"), ("message", .str s!"invalid JSON: {e}")])
  | .ok msg =>
    -- responses and event data are compared as `repr()`s
    if !reprSafeValue msg then
      (r, Json.mkObj [("unsupported", .str "text whose repr() HALean does not model (outside ASCII and U+00A1..U+024F)")])
    else match step r msg with
    | .ok out => out
    | .error e => (r, Json.mkObj [("unsupported", .str e)])

partial def loop (stdin stdout : IO.FS.Stream) (r : Registry) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trim
  if line.isEmpty then loop stdin stdout r else
  let (r', out) := processLine r line
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout r'

end Exe.CoreServices

def main : IO Unit := do
  Exe.CoreServices.loop (← IO.getStdin) (← IO.getStdout) []
