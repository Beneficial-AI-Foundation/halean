/-
  `halean-core`: the joined core (`HALean.Core.Hass`) over JSON lines.

  One operation per input line, each with the clock `now` (µs since the
  epoch):

    {"op": "set", "entity_id", "state", "attributes"?, "force_update"?, "context"?}
    {"op": "remove", "entity_id", "context"?}
    {"op": "get", "entity_id"}
    {"op": "fire", "event_type", "data"?, "origin"?, "context"?}
    {"op": "listen" | "listen_once", "id", "event_type", "filter"?, "react"?, "react_times"?}
    {"op": "unsub", "id"}
    {"op": "listeners"}
    {"op": "register", "domain", "service", "handler", "schema"?, "supports_response"?}
    {"op": "remove_service", "domain", "service"}
    {"op": "has", "domain", "service"}
    {"op": "call", "domain", "service", "data"?, "target"?, "blocking"?,
     "return_response"?, "context"?}
    {"op": "init", "listeners": [["*", 0], ...]}   -- the listeners HA already has
    {"op": "resolve", "id"}          -- `fut.set_result(None)` on the future `id`
    {"op": "sleep"}                  -- `await asyncio.sleep(0)`
    {"op": "block_till_done"}        -- `await hass.async_block_till_done()`

  A listener with "async": true is an `async def` (otherwise a `@callback`).

  Scripts (a listener's `react`, a handler's `do`) are lists of actions:
    {"fire": {...}}, {"listen": {...}}, {"listen_once": {...}}, {"unsub": "id"},
    {"raise": "ValueError", "message": "..."},
    {"set": {"entity_id", "state", "attributes"?, "force_update"?, "context"?}},
    {"remove": {"entity_id", "context"?}},
    {"call": {"id", "domain", "service", "data"?, "target"?, "blocking"?,
              "return_response"?, "context"?, "catch"?}},
    {"register": {"domain", "service", "handler", "schema"?, "supports_response"?}},
    {"remove_service": {"domain", "service"}},
    {"resolve": "id"},
    and in a coroutine (a handler, an async listener) only:
    {"sleep": 0}  (`await asyncio.sleep(0)`), {"wait": "id"}  (`await` the future `id`)
  where a context is {"id", "user_id"?, "parent_id"?} or, in a script,
  "inherit" (the event's context in a listener, the call's in a handler).
  A handler is {"do"?: [...], "return": value} | {"do"?, "echo": true} |
  {"do"?, "raise": "<exception>", "message"?}; without `return`, `echo` or
  `raise` it returns `None`. Filters: true, false, {"eq": {...}}, {"has": k},
  {"raise": true}. Schemas as in `halean-core-services`.

  One output line per operation:
    {"result": {"ok": <value>} | {"error": {...}},
     "trace": [{"delivery": "<listener id>", "event": <Event.as_dict()>},
               {"log": {"level", "message", "exception"?}},
               {"call": "<id>", "ok": "<repr>"} | {"call": "<id>", "error": {...}}, ...]}
  A call's result is the `repr()` of its response; `get` gives `as_dict()`.
  An operation outside the model is answered with {"unsupported": reason} and
  changes nothing.
-/
import HALean.Core.Hass
import HALean.Core.ServicesJson
open Lean HALean.Template HALean.Core HALean.Core.EventBus HALean.Core.Hass
  HALean.Core.ServicesJson

namespace HALean.Core.HassMain

def toJ (v : Value) : Except String Json :=
  match v.toJson with
  | .ok j => .ok j
  | .error e => .error s!"value without a JSON form: {e}"

def optNat (v : Value) (k : String) : Except String (Option Nat) :=
  match v.get? k with
  | none | some .none => .ok none
  | some (.int n) => if n ≥ 0 then .ok (some n.toNat) else .error s!"'{k}' must be ≥ 0"
  | _ => .error s!"'{k}' must be an integer"

/-- Entity ids: `str.lower()` and the id regex are modelled for ASCII only. -/
def getEntityId (v : Value) : Except String String := do
  let e ← getStr v "entity_id"
  if !isAscii e then throw "non-ASCII entity_id"
  return e

def decodeCtxArg (v : Value) (inScript : Bool) : Except String CtxArg :=
  match v.get? "context" with
  | none | some .none => .ok .none
  | some (.str "inherit") =>
    if inScript then .ok .inherit else .error "context 'inherit' only in a script"
  | some c => do
    let some ctx ← decodeContext (some c) | .ok .none
    if ctx.id.isEmpty then throw "a context needs a non-empty id"
    return .given ctx

/-- Keys whose values are `State` objects or datetimes in HA's event data: an
`eq` filter on them compares objects, which is not modelled. -/
def objectKeys : List String := ["old_state", "new_state", "last_reported", "old_last_reported"]

def decodeFilter (v : Value) : Except String (Option FilterSpec) := do
  match v.get? "filter_callback" with
  | some (.bool false) => throw "a filter that is not a @callback (raises; message not modelled)"
  | _ => pure ()
  let f ← match v.get? "filter" with
    | none | some .none => return none
    | some (.bool b) => pure (Filter.const b)
    | some f => match f.get? "eq", f.get? "has", f.get? "raise" with
      | some e, _, _ => match e.strItems? with
        | some kvs => do
          if kvs.any (objectKeys.contains ·.1) then throw "eq filter on a state or datetime"
          pure (.eq (← kvs.mapM fun (k, x) => do pure (k, ← toJ x)))
        | none => throw "eq filter must be a dict"
      | _, some (.str k), _ => pure (.has k)
      | _, _, some (.bool true) => pure .raises
      | _, _, _ => throw "unknown filter"
  return some { filter := f }

def decodeFire (v : Value) (inScript : Bool) : Except String FireArgs := do
  let et ← getStr v "event_type"
  if et.length > MAX_LENGTH_EVENT_EVENT_TYPE then
    throw "event type longer than 64 (MaxLengthExceeded message not modelled)"
  if (v.get? "time_fired").isSome then throw "time_fired is not modelled in the core"
  let data ← match v.get? "data" with
    | none | some .none => pure none
    | some d@(.dict _) => pure (some (← toJ d))
    | _ => throw "event data must be a dict or null"
  let origin ← match ← getOptStr v "origin" with
    | none | some "local" => pure Origin.local
    | some "remote" => pure .remote
    | some o => throw s!"unknown origin {o}"
  return { eventType := et, data, origin, context := ← decodeCtxArg v inScript }

def decodeCallArgs (v : Value) : Except String CallArgs := do
  return { domain := ← getName v "domain", service := ← getName v "service",
           data := ← getDict? v "data", target := ← getDict? v "target",
           blocking := ← getBool v "blocking" false,
           returnResponse := ← getBool v "return_response" false }

def decodeSupports (v : Value) : Except String SupportsResponse :=
  match v.get? "supports_response" with
  | none => .ok .none
  | some (.str s) => match SupportsResponse.ofString? s with
    | some sr => .ok sr
    | none => .error s!"unknown supports_response {s}"
  | _ => .error "'supports_response' must be a string"

def decodeSet (v : Value) (inScript : Bool) : Except String Action := do
  let attrs ← match v.get? "attributes" with
    | none | some .none => pure none
    | some a@(.dict _) => pure (some (← toJ a))
    | _ => throw "attributes must be a dict or null"
  let st ← match v.get? "state" with
    | some s => toJ s
    | none => throw "missing 'state'"
  return .set (← getEntityId v) st attrs (← getBool v "force_update" false) (← decodeCtxArg v inScript)

/-- Where a script runs: a `@callback` listener's `react`, or a coroutine (an
`async def` listener's `react`, a handler's `do`), which may await. -/
inductive ScriptKind | callback | coroutine
  deriving BEq

mutual
partial def decodeListen (v : Value) (once : Bool) : Except String Action := do
  let id ← getStr v "id"
  let et ← getStr v "event_type"
  let isAsync ← getBool v "async" false
  if (v.get? "run_immediately").isSome then throw "run_immediately (raises; message not modelled)"
  let filter ← decodeFilter v
  if once && filter.isSome then throw "listen_once with a filter (TypeError; message not modelled)"
  if et == EVENT_STATE_REPORTED && filter.isNone then
    throw "state_reported without a filter (raises; message not modelled)"
  let react ← match v.get? "react" with
    | some (.list rs) => rs.mapM (decodeAction · (if isAsync then .coroutine else .callback))
    | none | some .none => pure []
    | _ => throw "react must be a list"
  return .listen id et once filter react (← optNat v "react_times") isAsync

partial def decodeRegister (v : Value) : Except String Action := do
  let some h := v.get? "handler" | throw "missing 'handler'"
  let body ← match h.get? "do" with
    | some (.list as) => as.mapM (decodeAction · .coroutine)
    | none | some .none => pure []
    | _ => throw "'do' must be a list"
  let result ← if (h.get? "return").isSome || (h.get? "echo").isSome || (h.get? "raise").isSome
    then decodeHandler (some h) else pure (HandlerSpec.ret .none)
  return .register (← getName v "domain") (← getName v "service") body result
    (← decodeSchema (v.get? "schema")) (← decodeSupports v)

/-- One action of a script. -/
partial def decodeAction (v : Value) (kind : ScriptKind) : Except String Action := do
  if let some f := v.get? "fire" then return .fire (← decodeFire f true)
  if let some l := v.get? "listen" then return ← decodeListen l false
  if let some l := v.get? "listen_once" then return ← decodeListen l true
  if let some (.str id) := v.get? "unsub" then return .unsub id
  if let some (.str exc) := v.get? "raise" then
    if !handlerExceptions.contains exc then throw s!"exception {exc} is not modelled"
    return .raise exc ((← getOptStr v "message").getD "")
  if let some s := v.get? "set" then return ← decodeSet s true
  if let some r := v.get? "remove" then return .remove (← getEntityId r) (← decodeCtxArg r true)
  if let some c := v.get? "call" then
    let caught ← getBool c "catch" false
    if kind == .callback && (c.get? "catch").isSome then throw "'catch' only in a coroutine"
    return .call (← getStr c "id") (← decodeCallArgs c) (← decodeCtxArg c true) caught
  if let some r := v.get? "register" then return ← decodeRegister r
  if let some r := v.get? "remove_service" then
    return .removeService (← getName r "domain") (← getName r "service")
  if let some (.str f) := v.get? "resolve" then return .resolve f
  if (v.get? "sleep").isSome || (v.get? "wait").isSome then
    if kind == .callback then throw "a @callback cannot await"
    if let some (.int 0) := v.get? "sleep" then return .sleep
    if (v.get? "sleep").isSome then throw "only asyncio.sleep(0) is modelled"
    if let some (.str f) := v.get? "wait" then return .wait f
    throw "'wait' needs a future id"
  throw "unknown action"
end

def decodeOp (v : Value) : Except String (Nat × Hass.Op) := do
  let some now ← optNat v "now" | throw "missing 'now' (µs since the epoch)"
  let op ← match ← getStr v "op" with
    | "set" => pure (Hass.Op.act (← decodeSet v false))
    | "remove" => pure (.act (.remove (← getEntityId v) (← decodeCtxArg v false)))
    | "get" => pure (.get (← getEntityId v))
    | "fire" => pure (.act (.fire (← decodeFire v false)))
    | "listen" => pure (.act (← decodeListen v false))
    | "listen_once" => pure (.act (← decodeListen v true))
    | "unsub" => pure (.act (.unsub (← getStr v "id")))
    | "listeners" => pure .listeners
    | "register" => pure (.act (← decodeRegister v))
    | "remove_service" => pure (.act (.removeService (← getName v "domain") (← getName v "service")))
    | "has" => pure (.has (← getName v "domain") (← getName v "service"))
    | "call" =>
      let a ← decodeCallArgs v
      let ctx ← match ← decodeCtxArg v false with
        | .given c => pure (some c)
        | _ => pure none
      pure (.call { a with context := ctx })
    | "init" =>
      let some (.list ls) := v.get? "listeners" | throw "'listeners' must be a list"
      let counts ← ls.mapM fun p => match p with
        | .list [.str et, .int n] => if n ≥ 0 then pure (et, n.toNat) else throw "bad count"
        | _ => throw "'listeners' entries must be [event_type, count]"
      pure (.init counts)
    | "resolve" => pure (.act (.resolve (← getStr v "id")))
    | "sleep" => pure .sleep
    | "block_till_done" => pure .blockTillDone
    | o => throw s!"unknown op {o}"
  return (now, op)

/-! ## Output -/

def entryJson : Entry → Json
  | .delivery _ l ev => Json.mkObj [("delivery", .str l), ("event", ev.asDict)]
  | .log r => Json.mkObj [("log", logJson r)]
  | .callResult id (.ok v) => Json.mkObj [("call", .str id), ("ok", .str (reprOr v))]
  | .callResult id (.error e) => Json.mkObj [("call", .str id), ("error", errorJson e)]
  | .unsupported w => Json.mkObj [("unsupported", .str w)]

def resultJson (isCall : Bool) : Except PyError Hass.Result → Json
  | .error e => Json.mkObj [("error", errorJson e)]
  | .ok r => Json.mkObj [("ok", match r with
    | .value v => if isCall then .str (reprOr v) else (v.toJson.toOption.getD .null)
    | .state s => (s.map State.asDict).getD .null
    | .listeners cs => Json.arr (cs.map fun (et, n) => Json.arr #[.str et, (n : Json)]).toArray
    | .bool b => .bool b)]

def handleLine (h : Hass) (line : String) : Hass × Json :=
  match parsePyJson line >>= decodeOp with
  | .error e => (h, Json.mkObj [("unsupported", .str e)])
  | .ok (now, op) =>
    let (h', out, res) := step now h op
    match out.find? Entry.isUnsupported with
    | some (.unsupported w) => (h, Json.mkObj [("unsupported", .str w)])
    | _ =>
      let isCall := match op with | .call _ => true | _ => false
      (h', Json.mkObj [("result", resultJson isCall res),
                       ("trace", Json.arr (out.map entryJson).toArray)])

partial def loop (stdin stdout : IO.FS.Stream) (h : Hass) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trimAscii.toString
  if line.isEmpty then loop stdin stdout h else
  let (h', out) := handleLine h line
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout h'

end HALean.Core.HassMain

def main : IO Unit := do
  HALean.Core.HassMain.loop (← IO.getStdin) (← IO.getStdout) Hass.new
