/-
  What the helper integrations (`input_boolean`, `input_number`,
  `input_select`, `input_text`, `counter`, `timer`) share: the YAML
  collection's config schema (`cv.schema_with_slug_keys`), the entity
  service schema (`cv.make_entity_service_schema`) and target resolution
  (`helpers/service.py::entity_service_call`), how `Entity` turns a state
  into a string (`Entity._stringify_state`), and what a service handler
  does to the outside world (`Effect`: it writes the entity's state, or
  fires an event).

  Values are Python values (`HALean.Template.Value`), validated with the
  probatio model of the service registry (`HALean.Core.Schema`), so
  error messages and `int`/`float` are those of HA.
-/
import HALean.Core.Schema
import HALean.Core.ServicesJson
import HALean.Core.ServiceRegistry
open Lean

namespace HALean.Helpers
open HALean.Core HALean.Template

/-- An entity's state attributes, in the order `async_write_ha_state`
builds them. -/
abbrev Attrs := List (String × Value)

/-- What a service handler (or a timer's callback) does outside its entity,
in order. -/
inductive Effect where
  /-- `async_write_ha_state()`: the entity's state and attributes as written
  (`force`: `force_update`, a `state_changed` even when nothing changed) -/
  | write (entityId : String) (state : String) (attrs : Attrs) (force : Bool)
  /-- `hass.bus.async_fire(event_type, data)` -/
  | fire (eventType : String) (data : Attrs)
  /-- a log record (`_LOGGER.warning(...)`) -/
  | log (level : String) (message : String)
  deriving Inhabited

/-- An exception raised to the caller of a service. -/
abbrev PyErr := PyError

def pyErr (exception message : String) : PyErr := { exception, message }

/-- A handler runs on its entity, may write states and fire events, and may
raise. When it raises, the entity keeps the changes made before the raise
(Python mutates the entity in place), and the effects before it stay. -/
abbrev HM (σ : Type) := EStateM PyErr (σ × List Effect)

def emit {σ} (e : Effect) : HM σ Unit :=
  modify fun (s, es) => (s, es ++ [e])

def getEnt {σ} : HM σ σ := do return (← get).1

def setEnt {σ} (x : σ) : HM σ Unit := modify fun (_, es) => (x, es)

def raise {σ α} (exception message : String) : HM σ α := throw (pyErr exception message)

/-- Run a handler: the entity after it, its effects, and its error. -/
def HM.exec {σ} (m : HM σ Unit) (s : σ) : σ × List Effect × Option PyErr :=
  match m.run (s, []) with
  | .ok _ (s', es) => (s', es, none)
  | .error e (s', es) => (s', es, some e)

/-! ## `Entity._stringify_state` -/

/-- The 15 significant digits of `|f|` (finite, nonzero), rounded half-even
from its exact binary value, and the decimal exponent of the first digit. -/
def digits15 (f : Float) : Nat × Int := Id.run do
  let (_, num, den) := floatFrac f
  let mut k : Int := (natDigits num : Int) - natDigits den
  let ge (k : Int) : Bool :=
    if k ≥ 0 then num ≥ den * 10 ^ k.toNat else num * 10 ^ (-k).toNat ≥ den
  while !ge k do k := k - 1
  while ge (k + 1) do k := k + 1
  let s : Int := 14 - k
  let n := if s ≥ 0 then num * 10 ^ s.toNat else num
  let d := if s < 0 then den * 10 ^ (-s).toNat else den
  let mut q := n / d
  let r := n % d
  if 2 * r > d || (2 * r == d && q % 2 == 1) then q := q + 1
  if q ≥ 10 ^ 15 then
    q := q / 10
    k := k + 1
  return (q, k)

/-- `f"{x:.15}"` (`FLOAT_PRECISION` is 15 for IEEE doubles): like `%.15g`,
but `Py_DTSF_ADD_DOT_0` keeps `.0` on whole numbers in fixed notation, and
exponent notation starts one decade earlier (`decpt > precision - 1`). -/
def floatPrec15 (x : Float) : String :=
  if x.isNaN then "nan"
  else if x.isInf then (if x > 0 then "inf" else "-inf")
  else
    let (neg, _, _) := decodeFloat x
    let sign := if neg then "-" else ""
    if x == 0 then sign ++ "0.0" else
    let (q, k) := digits15 x
    let ds := String.ofList ((toString q).toList.reverse.dropWhile (· == '0')).reverse
    let decpt := k + 1
    if decpt ≤ -4 || decpt > 14 then
      let mant := match ds.toList with
        | [c] => String.singleton c
        | c :: cs => String.singleton c ++ "." ++ String.ofList cs
        | [] => "0"
      let e := k.natAbs
      let es := (if e < 10 then "0" else "") ++ toString e
      sign ++ mant ++ "e" ++ (if k < 0 then "-" else "+") ++ es
    else if decpt ≤ 0 then
      sign ++ "0." ++ String.ofList (List.replicate decpt.natAbs '0') ++ ds
    else if decpt.toNat ≥ ds.length then
      sign ++ ds ++ String.ofList (List.replicate (decpt.toNat - ds.length) '0') ++ ".0"
    else
      sign ++ (ds.take decpt.toNat).toString ++ "." ++ (ds.drop decpt.toNat).toString

/-- `Entity._stringify_state` for an available entity: `None` is `unknown`,
a float is `f"{state:.15}"`, anything else is `str(state)`. -/
def stringifyState : Value → String
  | .none => STATE_UNKNOWN
  | .str s => s
  | .float f => floatPrec15 f
  | .int i => toString i
  | .bool b => boolStr b
  | v => (pyStr v).toOption.getD "?"

/-- The attributes every helper writes after its own: `unit_of_measurement`,
`icon`, `friendly_name` (when the name is not empty). -/
def tailAttrs (unit : Option String) (icon : Option String) (name : Option String) : Attrs :=
  (match unit with | some u => [("unit_of_measurement", Value.str u)] | none => []) ++
  (match icon with | some i => [("icon", Value.str i)] | none => []) ++
  (match name with | some n => if n.isEmpty then [] else [("friendly_name", Value.str n)] | none => [])

/-! ## Config validation -/

/-- A `vol.Invalid` with a message and no path. -/
def invalid {α} (msg : String) : Except VErr α := throw (inv msg)

/-- Prefix every error's path with `seg`. -/
def withPath {α} (seg : PathSeg) (r : Except VErr α) : Except VErr α :=
  match r with
  | .error (.invalid errs) => .error (.invalid (prependAll seg errs))
  | r => r

/-- `str(MultipleInvalid)` of a failed validation, or why it is not modelled. -/
inductive ConfigError where
  | invalid (message : String)
  | unsupported (why : String)
  deriving Inhabited

def ConfigError.ofVErr : VErr → ConfigError
  | .invalid errs => .invalid (multipleInvalidStr errs)
  | .raise exc msg => .invalid s!"{exc}: {msg}"
  | .unsupported why => .unsupported why

/-- `CONFIG_SCHEMA = Schema({DOMAIN: cv.schema_with_slug_keys(value_schema)},
extra=ALLOW_EXTRA)` on the domain's config: a dict whose keys are all slugs
(the first that is not raises at once), then `Schema({str: value_schema})`,
whose errors are collected in key order (the first is reported). `decode`
validates one value and builds the item (`{CONF_ID: id_, **conf}`). -/
def slugKeys {α} (domain : String) (cfg : Value) (decode : String → Value → Except VErr α) :
    Except ConfigError (List α) := do
  let fail (e : VErr) : ConfigError := ConfigError.ofVErr (match e with
    | .invalid errs => .invalid (prependAll (.key domain) errs)
    | e => e)
  let .dict kvs := cfg | throw (fail (inv "expected dictionary"))
  let mut items : List (String × Value) := []
  for (k, v) in kvs do
    match k with
    | .str s => items := items ++ [(s, v)]
    | _ => throw (.unsupported "a config key that is not a string")
  for (k, _) in items do
    match cvSlug (.str k) with
    | .ok _ => pure ()
    | .error e => throw (fail e)
  let mut out : List α := []
  let mut errs : List SchemaError := []
  for (k, v) in items do
    match decode k v with
    | .ok a => out := out ++ [a]
    | .error (.invalid es) => errs := errs ++ prependAll (.key k) es
    | .error e => throw (fail e)
  if !errs.isEmpty then throw (fail (.invalid errs))
  return out

/-- Run a mapping schema (`Schema({...})`, extra keys not allowed, as
`Schema({str: value_schema})` compiles nested mappings) and return its
string-keyed output. -/
def runDict (fields : List Field) (v : Value) : Except VErr (List (String × Value)) := do
  match ← runMapping .prevent fields v with
  | .dict kvs => kvs.mapM fun (k, x) => match k with
    | .str s => pure (s, x)
    | _ => throw (.unsupported "a non-string key")
  | _ => throw (.unsupported "a mapping schema returned a non-dict")

def opt (k : String) (v : Validator) (dflt : Option Value := none) : Field := .mk k .optional dflt v
def req (k : String) (v : Validator) : Field := .mk k .required none v

/-- `cv.string` -/
def vString : Validator := .cv .string
/-- `cv.boolean` -/
def vBoolean : Validator := .cv .boolean
/-- `cv.icon` -/
def vIcon : Validator := .cv .icon

/-- Look a key up in validated config. -/
def lk (kvs : List (String × Value)) (k : String) : Option Value := kvs.lookup k

def lkStr (kvs : List (String × Value)) (k : String) : Option String :=
  match kvs.lookup k with
  | some (.str s) => some s
  | _ => none

/-! ## Entity services -/

/-- `cv.ENTITY_SERVICE_FIELDS` -/
def ENTITY_SERVICE_FIELDS : List String := ["entity_id", "device_id", "area_id", "floor_id", "label_id"]

/-- `cv.comp_entity_ids` -/
def compEntityIds : Validator :=
  .any [.all [.lower, .any [.literal (.str "all"), .literal (.str "none")]], .cv .entityIds]

/-- `vol.Any(ENTITY_MATCH_NONE, vol.All(cv.ensure_list, [str]))` -/
def idList : Validator := .any [.literal (.str "none"), .all [.ensureList, .seq [.type .str]]]

/-- `cv._make_entity_service_schema(schema, PREVENT_EXTRA)`:
`All(Schema({Remove("metadata"): dict, **schema, **ENTITY_SERVICE_FIELDS}),
AtLeastOne(*ENTITY_SERVICE_FIELDS))`, without the `Remove` key (see
`validateEntityCall`). -/
def entityServiceFields (fields : List Field) : List Field :=
  fields ++
  [opt "entity_id" compEntityIds, opt "device_id" idList, opt "area_id" idList,
   opt "floor_id" idList, opt "label_id" idList]

/-- Validate an entity service call's data (target merged in). probatio's
`Remove("metadata"): dict` drops a `metadata` dict; a `metadata` that is not
a dict leaves the key unmatched, so it is an extra key (and `Remove` keys are
not suggested). -/
def validateEntityCall (fields : List Field) (data : List (String × Value)) :
    Except VErr (List (String × Value)) := do
  let data := data.filter fun (k, v) => !(k == "metadata" && v matches .dict _)
  let out ← (SchemaSpec.validate { fields := entityServiceFields fields } data)
  discard (checkAtLeastOne ENTITY_SERVICE_FIELDS (dictOf out))
  return out

/-- Which entities a call targets: all of them, or these ids. -/
inductive Target where
  | all
  | ids (ids : List String)
  deriving Inhabited

/-- `TargetSelection` + `async_extract_referenced_entity_ids` for validated
data: `entity_id: all` is every entity of the component; `none` is none;
device, area, floor and label targets need the registries, which HALean
does not model (`none` there selects nothing). -/
def targetOf (data : List (String × Value)) : Except String Target := do
  for k in ["device_id", "area_id", "floor_id", "label_id"] do
    match data.lookup k with
    | none | some (.str "none") => pure ()
    | some (.list []) => pure ()
    | some _ => throw s!"'{k}' targets are not supported (HALean has no device/area/floor/label registry)"
  match data.lookup "entity_id" with
  | some (.str "all") => return .all
  | some (.str "none") | none => return .ids []
  | some (.list xs) => return .ids (xs.filterMap fun x => match x with | .str s => some s | _ => none)
  | some _ => throw "entity_id"

/-- `remove_entity_service_fields`: the data the entity method gets. -/
def serviceArgs (data : List (String × Value)) : List (String × Value) :=
  data.filter fun (k, _) => !ENTITY_SERVICE_FIELDS.contains k

/-- The entities a call runs on, in the component's order for `all`.
For explicit ids, HA iterates a `set` (hash order, random per process):
HALean runs them in the order given, which is one of HA's possible orders. -/
def selectTargets (entityIds : List String) : Target → List Nat
  | .all => List.range entityIds.length
  | .ids ids =>
    (ids.eraseDups).filterMap fun id => entityIds.idxOf? id

end HALean.Helpers
