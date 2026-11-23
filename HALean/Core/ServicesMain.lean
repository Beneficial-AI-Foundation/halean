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
  `{"fields": [{"key", "type", "required"?, "default"?}], "extra"?}`.

  Each output line is `{"ok": true, "result", "events", "logs"}` or
  `{"ok": false, "error": {...}, "events", "logs"}`. Python values (responses,
  event data) are written as their `repr()`, so dict order and int/float are
  compared exactly. An operation outside the modelled subset is answered with
  `{"unsupported": reason}` and changes nothing.
-/
import HALean.Core.ServiceRegistry
open Lean HALean HALean.Core HALean.Template

namespace HALean.Core.ServicesMain

def isAscii (s : String) : Bool := s.toList.all fun (c : Char) => c.toNat < 128

def getStr (v : Value) (k : String) : Except String String :=
  match v.get? k with
  | some (.str s) => .ok s
  | _ => .error s!"'{k}' must be a string"

/-- Domain and service names: `str.lower()` is modelled for ASCII only. -/
def getName (v : Value) (k : String) : Except String String := do
  let s ← getStr v k
  if !isAscii s then throw s!"non-ASCII '{k}' (str.lower() is modelled for ASCII only)"
  return s

def getBool (v : Value) (k : String) (dflt : Bool) : Except String Bool :=
  match v.get? k with
  | none => .ok dflt
  | some (.bool b) => .ok b
  | _ => .error s!"'{k}' must be a boolean"

def getDict? (v : Value) (k : String) : Except String (Option (List (String × Value))) :=
  match v.get? k with
  | none | some .none => .ok none
  | some d => match d.strItems? with
    | some kvs => .ok (some kvs)
    | none => .error s!"'{k}' must be a dict"

def getOptStr (v : Value) (k : String) : Except String (Option String) :=
  match v.get? k with
  | none | some .none => .ok none
  | some (.str s) => .ok (some s)
  | _ => .error s!"'{k}' must be a string or null"

def decodeHandler : Option Value → Except String HandlerSpec
  | some h =>
    if let some v := h.get? "return" then .ok (.ret v)
    else if (match h.get? "echo" with | some (.bool true) => true | _ => false) then .ok .echo
    else match h.get? "raise" with
      | some (.str exc) =>
        if handlerExceptions.contains exc then do
          let msg := match h.get? "message" with | some (.str m) => m | _ => ""
          .ok (.raise exc msg)
        else .error s!"handler exception {exc} is not modelled"
      | _ => .error "handler must be {\"return\": ...}, {\"echo\": true} or {\"raise\": ...}"
  | none => .error "missing 'handler'"

def decodeField (f : Value) : Except String FieldSpec := do
  let key ← getStr f "key"
  let tname ← getStr f "type"
  let some type := FieldType.ofString? tname
    | throw s!"schema type {tname} is not modelled (int, float, str, bool, any)"
  return { key, type, required := ← getBool f "required" false, default := f.get? "default" }

def decodeSchema : Option Value → Except String (Option SchemaSpec)
  | none | some .none => .ok none
  | some s => do
    let fields ← match s.get? "fields" with
      | some (.list fs) => fs.mapM decodeField
      | _ => throw "schema 'fields' must be a list"
    let keys := fields.map (·.key)
    if keys.eraseDups.length != keys.length then throw "duplicate schema keys"
    let extra ← match s.get? "extra" with
      | none | some (.str "prevent") => pure Extra.prevent
      | some (.str "allow") => pure .allow
      | some (.str "remove") => pure .remove
      | _ => throw "schema 'extra' must be prevent, allow or remove"
    return some { fields, extra }

def decodeContext : Option Value → Except String (Option ServiceContext)
  | none | some .none => .ok none
  | some c => do
    return some { id := some (← getStr c "id"), userId := ← getOptStr c "user_id",
                  parentId := ← getOptStr c "parent_id" }

/-! ## Output -/

def reprOr (v : Value) : String :=
  match pyRepr v with | .ok s => s | .error m => s!"<{m}>"

def optStr : Option String → Json
  | some s => .str s
  | none => .null

def contextJson (c : ServiceContext) : Json :=
  Json.mkObj [("id", .str (c.id.getD "new")), ("user_id", optStr c.userId),
              ("parent_id", optStr c.parentId)]

def eventJson (e : Event) : Json :=
  Json.mkObj [("event_type", .str e.eventType), ("data", .str (reprOr (dictOf e.data))),
              ("time_fired", .num (JsonNumber.fromNat e.timeFired)), ("context", contextJson e.context)]

def logJson (l : LogRecord) : Json :=
  Json.mkObj ([("level", .str l.level), ("message", .str l.message)] ++
    match l.exception with | some e => [("exception", .str e)] | none => [])

def errorJson (e : PyError) : Json :=
  Json.mkObj ([("exception", .str e.exception), ("error_kind", .str (errorKind e.exception)),
               ("message", .str e.message)] ++
    match e.translation with
    | some (d, k, ph) => [("translation_domain", .str d), ("translation_key", .str k),
        ("translation_placeholders", Json.mkObj (ph.map fun (k, v) => (k, Json.str v)))]
    | none => [])

def reply (result : Except PyError Json) (events : List Event := []) (logs : List LogRecord := []) : Json :=
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
    let out := r.asyncCall args now
    return (r, reply (out.result.map fun v => .str (reprOr v)) out.events out.logs)
  | op => throw s!"unknown op {op}"

/-- One input line to the new registry and one output line. -/
def processLine (r : Registry) (line : String) : Registry × Json :=
  match parsePyJson line with
  | .error e => (r, Json.mkObj [("type", .str "error"), ("message", .str s!"invalid JSON: {e}")])
  | .ok msg => match step r msg with
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

end HALean.Core.ServicesMain

def main : IO Unit := do
  HALean.Core.ServicesMain.loop (← IO.getStdin) (← IO.getStdout) []
