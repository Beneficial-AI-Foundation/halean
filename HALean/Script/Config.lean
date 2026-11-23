/-
  Script configuration: one entry of `scripts.yaml` (`object_id: config`)
  decoded into the engine's `Automation` (the sequence, mode, `max`, alias,
  `variables`) plus the `ScriptEntity`. Translated from
  `homeassistant/components/script/config.py` (`SCRIPT_ENTITY_SCHEMA`,
  `_async_validate_config_item`) and `ScriptEntity.__init__`.

  HA turns a config that fails validation into an unavailable entity; HALean
  rejects it (`unsupported`), and also everything it does not translate, so
  those scripts stay in HA.
-/
import HALean.Automation.Config
import HALean.Script.Entity
open Lean

namespace HALean.Script
open HALean.Automation

/-- `_INVALID_OBJECT_IDS` -/
def INVALID_OBJECT_IDS : List String := ["reload", "turn_off", "turn_on", "toggle"]

/-- The keys `SCRIPT_ENTITY_SCHEMA` allows (`make_script_schema` adds
`mode`, `max` and `max_exceeded`; extra keys are an error). -/
def SCRIPT_KEYS : List String :=
  ["alias", "trace", "icon", "sequence", "description", "variables", "fields",
   "mode", "max", "max_exceeded"]

/-- The keys of a field (`CONF_FIELDS` schema). -/
def FIELD_KEYS : List String :=
  ["advanced", "default", "description", "example", "name", "required", "selector"]

/-- `_MAX_EXCEEDED_CHOICES`: `LOGSEVERITY` keys and `SILENT`. -/
def MAX_EXCEEDED_CHOICES : List String :=
  ["CRITICAL", "FATAL", "ERROR", "WARNING", "WARN", "INFO", "DEBUG", "NOTSET", "SILENT"]

/-- `cv.string` for the values HALean accepts: strings and numbers. -/
def cvString (what : String) : Json → D String
  | .str s => pure s
  | .num n => pure (toString n)
  | v => throw s!"{what}: expected a string, got {v.compress}"

/-- `cv.slug`: the object id must be its own slug. -/
def isSlug (s : String) : Bool := !s.isEmpty && slugify? s == some s

/-- Every JSON object below `j` (actions are found wherever they nest). -/
partial def objects (j : Json) : List Json :=
  match j with
  | .obj kvs => j :: kvs.toList.flatMap fun (_, v) => objects v
  | .arr xs => xs.toList.flatMap objects
  | _ => []

/-- `action:`/`service:` of an action object. -/
def actionName (j : Json) : Option String :=
  (str? j "action").orElse fun _ => str? j "service"

/-- What HALean does not translate inside a script's actions, beyond what
`decodeAction` rejects:
  * `script.reload` (it re-reads `scripts.yaml`),
  * device/area/floor/label targets of `script.turn_on`/`turn_off`/`toggle`
    (registries are not modelled),
  * waits that may depend on a script entity's state (HALean writes those
    states without notifying listeners),
  * the `trigger` condition (scripts have no trigger). -/
def checkActions (seq : Json) : D Unit := do
  for o in objects seq do
    if let some a := actionName o then
      if a == "script.reload" then throw "'script.reload' is not supported in scripts"
      if a == "script.turn_on" || a == "script.turn_off" || a == "script.toggle" then
        for part in [o, (field? o "data").getD .null, (field? o "target").getD .null] do
          for k in ["device_id", "area_id", "floor_id", "label_id"] do
            if (field? part k).isSome then throw s!"'{k}' targets of {a} are not supported"
    if has o "wait_template" || has o "wait_for_trigger" then
      if (o.compress.splitOn "script").length > 1 then
        throw "waits that refer to script entities are not supported"
    if str? o "condition" == some "trigger" then
      throw "the 'trigger' condition is not supported in scripts"

/-- Text checks on everything templates in a script may read: HALean does
not model `last_action`, and writes `last_triggered` of other script
entities as text, so only `this.attributes.last_triggered` may be read. -/
def checkAttributes (j : Json) : D Unit := do
  let s := j.compress
  if (s.splitOn "last_action").length > 1 then
    throw "the 'last_action' attribute is not supported"
  let rest := "".intercalate (s.splitOn "this.attributes.last_triggered")
  if (rest.splitOn "last_triggered").length > 1 then
    throw "'last_triggered' is supported only as this.attributes.last_triggered"

/-- The variable names calls in `scripts` pass to scripts: the data keys
(and target keys, merged into the data) of `script.<object_id>` calls and the
`variables` keys of `script.turn_on`. Templates of a script may use them. -/
def passedNames (scripts : List (String × Json)) : List String :=
  scripts.flatMap fun (_, cfg) => (objects ((field? cfg "sequence").getD .null)).flatMap fun o =>
    match actionName o with
    | some a =>
      if !a.startsWith "script." then [] else
      let keys (j : Option Json) : List String := match j with
        | some (.obj kvs) => kvs.toList.map (·.1)
        | _ => []
      if a == "script.turn_on" then
        match field? o "data" with
        | some d => keys (field? d "variables")
        | none => []
      else keys (field? o "data") ++ keys (field? o "target")
    | none => []

/-- Decode the fields' names, checking the `CONF_FIELDS` schema. Selectors
are UI metadata: HALean does not validate them (`validate_selector`). -/
def decodeFields (j : Json) : D (List String) := do
  let fs ← orderedMapping "fields" j
  for (name, f) in fs do
    let .obj kvs := f | throw s!"field {name} must be a mapping"
    for (k, v) in kvs.toList do
      if !FIELD_KEYS.contains k then throw s!"extra keys not allowed @ data['fields']['{name}']['{k}']"
      match k, v with
      | "advanced", .bool _ | "required", .bool _ => pure ()
      | "advanced", _ | "required", _ => throw s!"field {name}: {k} must be a boolean"
      | "description", v | "example", v | "name", v => discard (cvString s!"field {name}: {k}" v)
      | "selector", .obj _ | "selector", .null => pure ()
      | "selector", _ => throw s!"field {name}: invalid selector"
      | _, _ => pure ()
  return fs.map (·.1)

/-- One script: `_SCRIPT_OBJECT_ID_SCHEMA` on the key, `SCRIPT_ENTITY_SCHEMA`
on the config, then the sequence (`async_validate_actions_config`).
`extraNames`: variable names other scripts pass to scripts
(`passedNames`). -/
def decodeScript (key : String) (j : Json) (extraNames : List String := []) :
    D (ScriptEntity × Automation) := do
  if !isSlug key then throw s!"invalid slug {key} (try {(slugify? key).getD "?"})"
  if INVALID_OBJECT_IDS.contains key then
    throw s!"A script's object_id must not be one of {", ".intercalate (INVALID_OBJECT_IDS.mergeSort (· ≤ ·))}"
  let .obj kvs := j | throw "expected a dictionary"
  if has j "use_blueprint" then throw "blueprint scripts are not supported"
  for (k, _) in kvs.toList do
    if !SCRIPT_KEYS.contains k then throw s!"extra keys not allowed @ data['{k}']"
  let alias ← match field? j "alias" with
    | some v => do
      let a ← cvString "alias" v
      -- an empty name leaves out `friendly_name`; not modelled
      if a.isEmpty then throw "an empty alias is not supported"
      pure (some a)
    | none => pure none
  let icon ← match field? j "icon" with
    | none => pure none
    | some v => do
      -- `cv.icon`
      let s ← cvString "icon" v
      if !s.contains ':' then throw "Icons should be specified in the form \"prefix:name\""
      pure (some s)
  if let some d := field? j "description" then discard (cvString "description" d)
  if let some t := field? j "trace" then
    let .obj tk := t | throw "trace must be a mapping"
    for (k, v) in tk.toList do
      if k != "stored_traces" then throw s!"extra keys not allowed @ data['trace']['{k}']"
      match v with
      | .num n => if n.exponent != 0 || n.mantissa < 1 then throw "stored_traces must be a positive integer"
      | _ => throw "stored_traces must be a positive integer"
  let mode ← match field? j "mode" with
    | none | some (.str "single") => pure Mode.single
    | some (.str "restart") => pure .restart
    | some (.str "queued") => pure .queued
    | some (.str "parallel") => pure .parallel
    | some m => throw s!"value must be one of ['parallel', 'queued', 'restart', 'single'] for dictionary value @ data['mode'], got {m.compress}"
  -- `vol.All(vol.Coerce(int), vol.Range(min=2))`
  let maxRuns ← match field? j "max" with
    | none => pure 10
    | some (.num n) =>
      if n.exponent != 0 then throw s!"max must be an integer, got {n}"
      if n.mantissa < 2 then throw "value must be at least 2 for dictionary value @ data['max']"
      pure n.mantissa.toNat
    | some (.str s) => match s.trim.toInt? with
      | some i => if i < 2 then throw "value must be at least 2 for dictionary value @ data['max']" else pure i.toNat
      | none => throw s!"expected int for dictionary value @ data['max'], got {s}"
    | some v => throw s!"expected int for dictionary value @ data['max'], got {v.compress}"
  if let some me := field? j "max_exceeded" then
    let s ← cvString "max_exceeded" me
    if !MAX_EXCEEDED_CHOICES.contains s.toUpper then throw s!"invalid max_exceeded {s}"
  let fields ← match field? j "fields" with
    | none => pure []
    | some f => decodeFields f
  let vars ← match field? j "variables" with
    | none => pure []
    | some v => orderedMapping "variables" v
  let some seqJ := field? j "sequence" | throw "required key not provided @ data['sequence']"
  checkActions seqJ
  checkAttributes (Json.arr #[seqJ, Json.mkObj (vars.map fun (k, v) => (k, v))])
  -- the names templates may use: `this`, `context`, `repeat`, `wait`, the
  -- fields, the script's variables, every variable an action defines, and
  -- what calls from other scripts pass
  let nm := ["this", "context", "repeat", "wait"] ++ fields ++ vars.map (·.1) ++
    actionVariableNames seqJ ++ extraNames
  let mvars ← vars.mapM fun (k, v) => do pure (k, ← decodeComplex v nm)
  let acts ← (ensureList seqJ).mapM (decodeAction · nm)
  let name := alias.getD key
  let eid := s!"script.{key}"
  let auto : Automation := {
    id := key, alias := name, triggers := [], conditions := [],
    actions := acts.filterMap id, mode, maxRuns, variables := mvars,
    entityId := some eid, uniqueId := some key }
  return ({ objectId := key, entityId := eid, icon, raw := j.compress }, auto)

end HALean.Script
