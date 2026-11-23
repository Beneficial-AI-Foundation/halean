/-
  JSON (Python-value) decoding and encoding shared by the service registry's
  driver (`halean-core-services`) and the joined core's (`halean-core`):
  handler specs, schemas, contexts, errors and log records.
-/
import HALean.Core.ServiceRegistry
open Lean HALean HALean.Core HALean.Template

namespace HALean.Core.ServicesJson

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

def decodeContext : Option Value → Except String (Option Context)
  | none | some .none => .ok none
  | some c => do
    return some { id := ← getStr c "id", userId := ← getOptStr c "user_id",
                  parentId := ← getOptStr c "parent_id" }

/-! ## Output -/

def reprOr (v : Value) : String :=
  match pyRepr v with | .ok s => s | .error m => s!"<{m}>"

def optStr : Option String → Json
  | some s => .str s
  | none => .null

def contextJson (c : Context) : Json :=
  Json.mkObj [("id", .str c.id), ("user_id", optStr c.userId),
              ("parent_id", optStr c.parentId)]

def eventJson (e : FiredEvent) : Json :=
  Json.mkObj [("event_type", .str e.eventType), ("data", .str (reprOr (dictOf e.data))),
              ("time_fired", .num (JsonNumber.fromNat e.timeFired)), ("context", contextJson (e.context.getD Registry.freshContext))]

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

end HALean.Core.ServicesJson
