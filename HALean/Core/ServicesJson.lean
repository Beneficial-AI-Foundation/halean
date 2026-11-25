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

/-! ## Schemas

A schema spec is `{"fields": [<field>, ...], "extra": "prevent"|"allow"|"remove"}`.
A field is `{"key", "type"}` (a type name) or `{"key", "value": <validator>}`,
with `"required": true`, `"default": <value>`, `"exclusive": <group>` (and
`"group_required": true`) or `"inclusive": <group>`. A validator is a type
name (`int`, `float`, `str`, `bool`, `any`/`object`, `list`, `dict`) or a
one-key object:

    {"type": t}  {"literal": <scalar>}  {"dict": [<field>, ...]}
    {"list": [<validator>, ...]}  {"all": [...]}  {"any": [...]}
    {"in": [<scalar>, ...]}  {"not_in": [...]}
    {"range": {"min", "max", "min_included", "max_included"}}
    {"clamp": {"min", "max"}}  {"length": {"min", "max"}}
    {"coerce": "int"|"float"|"str"}  {"lower": null}  {"upper": null}
    {"ensure_list": null}  {"port": null}  {"at_least_one": [<key>, ...]}
    {"cv": <name>}  {"cv": "entity_domain", "domain": <str or list>}

Anything else (`msg=`, other validators and `cv.*`) is rejected. -/

def isScalar : Value → Bool
  | .none | .bool _ | .int _ | .float _ | .str _ => true
  | _ => false

/-- Strings in a spec must be text the model handles (`safeText`). -/
def specText (v : Value) : Except String Unit :=
  if safeValue v then pure () else throw "schema text outside printable ASCII is not modelled"

def getNum? (v : Value) (k : String) : Except String (Option Value) :=
  match v.get? k with
  | none | some .none => pure none
  | some n@(.int _) | some n@(.float _) => pure (some n)
  | _ => throw s!"'{k}' must be a number"

def getInt? (v : Value) (k : String) : Except String (Option Int) :=
  match v.get? k with
  | none | some .none => pure none
  | some (.int i) => pure (some i)
  | _ => throw s!"'{k}' must be an int"

def onlyKeys (v : Value) (allowed : List String) (what : String) : Except String Unit := do
  let some kvs := v.strItems? | throw s!"{what} must be a dict"
  for (k, _) in kvs do
    if !allowed.contains k then throw s!"{what}: '{k}' is not modelled"

/-- `cv.time_period_dict`: `All(dict, Schema({<unit>: Coerce(float)}),
AtLeastOne(<units>), lambda value: timedelta(**value))`. -/
def timePeriodDict : Validator :=
  let units := ["days", "hours", "minutes", "seconds", "milliseconds"]
  .all [.type .dict, .schema (units.map fun u => .mk u .optional none (.coerce .float)) .prevent,
        .atLeastOne units, .cv .timedeltaKwargs]

/-- `cv.time_period` -/
def timePeriod : Validator :=
  .any [.cv .timePeriodStr, .cv .timePeriodSeconds, .type .timedelta, timePeriodDict]

/-- The `cv.*` names (`cv.entity_domain` takes `domain`). -/
def decodeCv (name : String) (spec : Value) : Except String Validator :=
  let posRange (max : Option Value) : Validator := .range (some (.int 0)) max true true
  match name with
  | "string" => pure (.cv .string)
  | "boolean" => pure (.cv .boolean)
  | "entity_id" => pure (.cv .entityId)
  | "entity_ids" => pure (.cv .entityIds)
  | "color_hex" => pure (.cv .colorHex)
  | "slug" => pure (.cv .slug)
  | "icon" => pure (.cv .icon)
  -- probatio objects in config_validation.py
  | "positive_int" => pure (.all [.coerce .int, posRange none])
  | "positive_float" => pure (.all [.coerce .float, posRange none])
  | "small_float" => pure (.all [.coerce .float, posRange (some (.int 1))])
  | "byte" => pure (.all [.coerce .int, posRange (some (.int 255))])
  | "port" => pure .port
  | "ensure_list" => pure .ensureList
  | "time_period_str" => pure (.cv .timePeriodStr)
  | "time_period_seconds" => pure (.cv .timePeriodSeconds)
  | "time_period_dict" => pure timePeriodDict
  | "time_period" => pure timePeriod
  | "positive_time_period" => pure (.all [timePeriod, .cv .positiveTimedelta])
  | "positive_time_period_dict" => pure (.all [timePeriodDict, .cv .positiveTimedelta])
  | "comp_entity_ids" =>
    pure (.any [.all [.lower, .any [.literal (.str "all"), .literal (.str "none")]], .cv .entityIds])
  | "entity_domain" => do
    match spec.get? "domain" with
    | some d@(.str s) => specText d; pure (.cv (.entityDomain (.one s)))
    | some d@(.list ds) => do
      specText d
      let ss ← ds.mapM fun x => match x with
        | .str s => pure s
        | _ => throw "cv.entity_domain: domains must be strings"
      pure (.cv (.entityDomain (.many ss)))
    | _ => throw "cv.entity_domain needs 'domain'"
  | n => throw s!"cv.{n} is not modelled"

mutual
partial def decodeValidator (v : Value) : Except String Validator := do
  if let .str t := v then
    let some ty := PyType.ofString? t | throw s!"schema type {t} is not modelled"
    return .type ty
  let some kvs := v.strItems? | throw "a validator must be a type name or a one-key object"
  let some (name, arg) := kvs.head? | throw "empty validator"
  if name != "cv" && kvs.length != 1 then throw s!"validator {name}: extra options are not modelled"
  let scalars (what : String) : Except String (List Value) := do
    let .list xs := arg | throw s!"{what} needs a list"
    if !xs.all isScalar then throw s!"{what}: only scalar members are modelled"
    specText arg
    pure xs
  let list (what : String) : Except String (List Validator) := do
    let .list xs := arg | throw s!"{what} needs a list"
    xs.mapM decodeValidator
  match name with
  | "type" => decodeValidator arg
  | "literal" =>
    if !isScalar arg then throw "only scalar literals are modelled"
    specText arg
    pure (.literal arg)
  | "dict" => do
    let .list fs := arg | throw "dict needs a list of fields"
    pure (.dict (← decodeFields fs))
  | "list" => pure (.seq (← list "list"))
  | "all" => pure (.all (← list "all"))
  | "any" => pure (.any (← list "any"))
  | "in" => pure (.isIn (← scalars "in"))
  | "not_in" => pure (.notIn (← scalars "not_in"))
  | "range" =>
    onlyKeys arg ["min", "max", "min_included", "max_included"] "range"
    pure (.range (← getNum? arg "min") (← getNum? arg "max")
      (← getBool arg "min_included" true) (← getBool arg "max_included" true))
  | "clamp" =>
    onlyKeys arg ["min", "max"] "clamp"
    pure (.clamp (← getNum? arg "min") (← getNum? arg "max"))
  | "length" =>
    onlyKeys arg ["min", "max"] "length"
    pure (.length (← getInt? arg "min") (← getInt? arg "max"))
  | "coerce" => match arg with
    | .str "int" => pure (.coerce .int)
    | .str "float" => pure (.coerce .float)
    | .str "str" => pure (.coerce .str)
    | _ => throw "only Coerce(int), Coerce(float) and Coerce(str) are modelled"
  | "lower" => pure .lower
  | "upper" => pure .upper
  | "ensure_list" => pure .ensureList
  | "port" => pure .port
  | "at_least_one" => do
    let .list ks := arg | throw "at_least_one needs a list of keys"
    specText arg
    pure (.atLeastOne (← ks.mapM fun k => match k with
      | .str s => pure s
      | _ => throw "at_least_one: string keys only"))
  | "cv" => do
    let .str n := arg | throw "cv needs a name"
    if kvs.any (fun (k, _) => k != "cv" && k != "domain") then throw "cv: extra options are not modelled"
    decodeCv n v
  | n => throw s!"validator {n} is not modelled"

partial def decodeField (f : Value) : Except String Field := do
  onlyKeys f ["key", "type", "value", "required", "default", "exclusive", "group_required",
    "inclusive"] "schema field"
  let key ← getStr f "key"
  specText (.str key)
  let value ← match f.get? "type", f.get? "value" with
    | some t, none => decodeValidator t
    | none, some v => decodeValidator v
    | _, _ => throw "a schema field needs exactly one of 'type' and 'value'"
  let required ← getBool f "required" false
  let marker ← match f.get? "exclusive", f.get? "inclusive" with
    | some (.str g), none =>
      if required then throw "Exclusive and required: not modelled"
      specText (.str g)
      pure (KeyMarker.exclusive g (← getBool f "group_required" false))
    | none, some (.str g) =>
      if required then throw "Inclusive and required: not modelled"
      specText (.str g)
      pure (KeyMarker.inclusive g)
    | none, none =>
      if (f.get? "group_required").isSome then throw "group_required needs exclusive"
      pure (if required then KeyMarker.required else .optional)
    | _, _ => throw "a key is Exclusive or Inclusive, not both (and the group is a string)"
  return .mk key marker (f.get? "default") value

partial def decodeFields (fs : List Value) : Except String (List Field) := do
  let fields ← fs.mapM decodeField
  let keys := fields.map Field.key
  if keys.eraseDups.length != keys.length then throw "duplicate schema keys"
  return fields
end

def decodeSchema : Option Value → Except String (Option SchemaSpec)
  | none | some .none => .ok none
  | some s => do
    onlyKeys s ["fields", "extra"] "schema"
    let fields ← match s.get? "fields" with
      | some (.list fs) => decodeFields fs
      | _ => throw "schema 'fields' must be a list"
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
