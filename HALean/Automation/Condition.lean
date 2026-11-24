/-
  Condition evaluation. Translated from
  `homeassistant/helpers/condition.py`.

  Python's three outcomes are kept exactly:
    * `ok (some b)`  – the checker returned `b`
    * `ok none`      – the checker returned `None` (only `DisabledConditionChecker`)
    * `err msg`      – the checker raised `ConditionError`
-/
import HALean.Automation.Config
import HALean.Automation.Location
import HALean.Automation.Sun
open Lean

namespace HALean.Automation

inductive CondResult where
  | ok (r : Option Bool)
  | err (msg : String)
  deriving Repr, Inhabited, BEq

/-- What a condition can see: the state machine, the clock and the run
variables (only `trigger.id` matters to the supported subset). -/
structure CondEnv where
  states : States
  now : Instant
  triggerId : Option String := none
  /-- The run variables templates see (`trigger`, `variables`, `repeat`),
  innermost first. -/
  vars : List (String × Template.Value) := []
  /-- HA's location, for the `sun` condition. -/
  location : Option Sun.Observer := none

def CondEnv.tmplCtx (env : CondEnv) : Template.Ctx :=
  { states := env.states, vars := env.vars, now := env.now }

/-- Set a variable: replace it where it is, or add it (`ScriptRunVariables`
assigns to the scope that defines it, else to the top level). -/
def setVar (vs : List (String × Template.Value)) (k : String) (v : Template.Value) :
    List (String × Template.Value) :=
  if vs.any (·.1 == k) then vs.map fun (k', v') => if k' == k then (k, v) else (k', v')
  else vs ++ [(k, v)]

/-- `condition.async_template`: render without parsing the result, then
`value.lower() == "true"`. A `TemplateError` is a `ConditionError`. -/
def templateCond (env : CondEnv) (t : Template.Tmpl) : Except String Bool :=
  match Template.render t env.tmplCtx false with
  | .ok (.str s) => .ok (s.toLower == "true")
  | .ok _ => .ok false
  | .error e => .error s!"Error in 'template' condition: {e}"

/-- `template.render_complex(value, variables)` (parse_result=True), as the
JSON HA would send on. -/
partial def renderComplex (env : CondEnv) : Complex → Except String Json
  | .lit j => pure j
  | .tmpl t => do
    let v ← Template.render t env.tmplCtx true
    v.toJson
  | .arr xs => do pure (.arr (← xs.mapM (renderComplex env)).toArray)
  | .obj kvs => do
    let fields ← kvs.mapM fun (k, v) => do
      let key ← match k with
        | .lit (.str s) => pure s
        | .tmpl t => do
          let kv ← Template.render t env.tmplCtx true
          match kv with
          | .str s => pure s
          | kv => Template.pyStr kv
        | other => match renderComplex env other with
          | .ok j => pure j.compress
          | .error e => throw e
      pure (key, ← renderComplex env v)
    pure (Json.mkObj fields)

/-- `render_complex` as a template value (for variables). -/
partial def renderComplexV (env : CondEnv) : Complex → Except String Template.Value
  | .lit j => pure (Template.Value.ofJson j)
  | .tmpl t => Template.render t env.tmplCtx true
  | .arr xs => do pure (.list (← xs.mapM (renderComplexV env)))
  | .obj kvs => do
    pure (.dict (← kvs.mapM fun (k, v) => do pure (← renderComplexV env k, ← renderComplexV env v)))

/-- `ScriptVariables.async_render`: render in order, each seeing the ones
before it; keys that already exist are skipped (run variables win). -/
def renderVariables (env : CondEnv) (defs : List (String × Complex)) :
    Except String (List (String × Template.Value)) :=
  defs.foldlM (fun vs (k, c) =>
    if vs.any (·.1 == k) then pure vs
    else do
      let v ← renderComplexV { env with vars := vs } c
      pure (vs ++ [(k, v)])) env.vars

partial def Complex.hasTemplate : Complex → Bool
  | .lit _ => false
  | .tmpl _ => true
  | .arr xs => xs.any Complex.hasTemplate
  | .obj kvs => kvs.any fun (k, v) => k.hasTemplate || v.hasTemplate

/-- `cv.comp_entity_ids_or_uuids` on a rendered target's `entity_id`
(`ensure_list_csv`, lower-case, validate). -/
def normalizeTarget (j : Json) : Except String Json := do
  let .obj _ := j | throw "Error rendering service target template: not a mapping"
  match field? j "entity_id" with
  | none => pure j
  | some v =>
    let items ← match v with
      | .str s =>
        if s.toLower == "all" || s.toLower == "none" then pure none
        else pure (some ((s.splitOn ",").map String.trim))
      | .arr xs => some <$> xs.toList.mapM fun x => match x with
        | .str s => pure s
        | x => throw s!"Template rendered invalid entity IDs: {x.compress}"
      | x => throw s!"Template rendered invalid entity IDs: {x.compress}"
    match items with
    | none => pure (j.setObjVal! "entity_id" (.str (match v with | .str s => s.toLower | _ => "")))
    | some ids =>
      let ids := ids.map String.toLower
      for e in ids do
        if !Template.validEntityId e then throw s!"Template rendered invalid entity IDs: {e}"
      pure (j.setObjVal! "entity_id" (.arr (ids.map Json.str).toArray))

/-- `cv.INPUT_ENTITY_ID`:
`^input_(?:select|text|number|boolean|datetime)\.(?!.+__)(?!_)[\da-z_]+(?<!_)$` -/
def isInputEntityId (s : String) : Bool :=
  match s.splitOn "." with
  | [dom, obj] =>
    ["input_select", "input_text", "input_number", "input_boolean", "input_datetime"].contains dom
      && !obj.isEmpty
      && obj.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'z') || c == '_')
      && !obj.startsWith "_" && !obj.endsWith "_"
      -- `(?!.+__)`; a leading "__" is already excluded by `(?!_)`
      && (obj.splitOn "__").length == 1
  | _ => false

/-- `conditions.state` for a single entity. -/
def stateOne (env : CondEnv) (eid : String) (req : List Json) (forMs : Option Nat)
    (attr : Option String) : Except String Bool := do
  let some ent := env.states.get? eid | throw s!"unknown entity {eid}"
  if let some a := attr then
    if !ent.hasAttr a then return false
  let value : Json := match attr with
    | none => .str ent.state
    | some a => (ent.attr? a).getD .null
  let mut isState := false
  for r in req do
    let mut sv := r
    if let .str s := r then
      if isInputEntityId s then
        let some se := env.states.get? s | throw s!"the 'state' entity {s} is unavailable"
        sv := .str se.state
    isState := value == sv
    if isState then break
  match forMs with
  | none => return isState
  | some p =>
    if !isState then return false
    -- `duration = utcnow() - for_period; duration > entity.last_changed`
    return (env.now.utc : Int) - p > ent.lastChanged

/-- Resolve a numeric `below`/`above` bound. `none` = the Python code returns
False early (entity unavailable/unknown). -/
def resolveBound (env : CondEnv) (which : String) : Bound → Except String (Option Float)
  | .num v => pure (some v)
  | .entity e => do
    let some be := env.states.get? e | throw s!"unknown '{which}' entity {e}"
    if be.state == STATE_UNAVAILABLE || be.state == STATE_UNKNOWN then return none
    match parsePyFloatStr be.state with
    | some f => return some f
    | none => throw s!"the '{which}' entity {e} state '{be.state}' cannot be processed as a number"

/-- Python `float(x)` on a template result; `none` = ValueError/TypeError. -/
def pyFloatV : Template.Value → Option Float
  | .float f => some f
  | .int i => some (Template.intToFloat i)
  | .bool b => some (if b then 1.0 else 0.0)
  | .str s => Template.parseFloatStr s
  | _ => none

/-- `value_template` plus the variables it sees (without `state`). -/
abbrev ValueTmpl := Option (Template.Tmpl × List (String × Template.Value))

/-- `conditions.async_numeric_state`. Takes the entity state directly so
triggers can reuse it with `to_s`. -/
def numericStateOf (env : CondEnv) (ent : EntityState) (below above : Option Bound)
    (attr : Option String) (vt : ValueTmpl := none) : Except String Bool := do
  if let some a := attr then
    if !ent.hasAttr a then return false
  let fv ← match vt with
    | none => do
      let value : Json := match attr with
        | none => .str ent.state
        | some a => (ent.attr? a).getD .null
      if value == .null || value == .str STATE_UNAVAILABLE || value == .str STATE_UNKNOWN then
        return false
      let some fv := pyFloat? value
        | throw s!"entity {ent.entityId} state '{value.compress}' cannot be processed as a number"
      pure fv
    | some (t, vars) => do
      let ctx : Template.Ctx := { states := env.states, vars := ("state", .state ent false) :: vars }
      let value ← match Template.render t ctx true with
        | .ok v => pure v
        | .error e => throw s!"template error: {e}"
      -- `if value in (None, STATE_UNAVAILABLE, STATE_UNKNOWN)`
      if [Template.Value.none, .str STATE_UNAVAILABLE, .str STATE_UNKNOWN].any (Template.pyEq value) then
        return false
      let some fv := pyFloatV value
        | throw s!"entity {ent.entityId} state '{(Template.pyStr value).toOption.getD "?"}' cannot be processed as a number"
      pure fv
  if let some b := below then
    match ← resolveBound env "below" b with
    | none => return false
    | some bv => if fv >= bv then return false
  if let some a := above then
    match ← resolveBound env "above" a with
    | none => return false
    | some av => if fv <= av then return false
  return true

def numericStateOne (env : CondEnv) (eid : String) (below above : Option Bound)
    (attr : Option String) (vt : ValueTmpl := none) : Except String Bool := do
  let some ent := env.states.get? eid | throw s!"unknown entity {eid}"
  numericStateOf env ent below above attr vt

/-- Resolve a `before`/`after` entity bound to µs since midnight.
`.ok none` = the Python code returns False. -/
def resolveTimeBound (env : CondEnv) (which : String) (eid : String) (isAfter : Bool) :
    Except String (Option Nat) := do
  let some e := env.states.get? eid | throw s!"unknown '{which}' entity {eid}"
  if e.domain == "input_datetime" then
    let g (k : String) (d : Nat) : Nat := match e.attr? k with
      | some (.num n) => n.mantissa.toNat
      | _ => d
    return some ((g "hour" 23 * 3600 + g "minute" 59 * 60 + g "second" 59) * 1000000)
  let unavail := e.state == STATE_UNAVAILABLE || e.state == STATE_UNKNOWN
  -- `after`: an unavailable `time` entity falls through to the sensor check
  if e.domain == "time" && !(isAfter && unavail) then
    -- `datetime.strptime(state, "%H:%M:%S").time()`
    match Template.strptime e.state "%H:%M:%S" with
    | .ok (.datetime us _) =>
      let c := Template.toCivil us
      return some (((c.hour * 60 + c.minute) * 60 + c.second) * 1000000 + c.micro)
    | .ok _ => throw "strptime returned no datetime"
    | .error (.valueError m) =>
      -- `after`: the ValueError is not caught upstream; `before`: returns False
      if isAfter then throw s!"ValueError: {m}" else return none
    | .error (.error m) => throw m
  match e.attr? "device_class" with
  | some (.str "timestamp") | some (.str "uptime") =>
    if unavail then return none
    -- `dt_util.as_local(dt_util.parse_datetime(state)).time()`; a naive
    -- datetime is taken as local time
    match (Template.parseDatetime e.state).run.run' {} with
    | .error m => throw m
    | .ok (some (.datetime us off)) =>
      let c := Template.toCivil (match off with
        | some _ => Template.wallOf us (some env.now.tzOffsetSec)
        | none => us)
      if c.year < 1 || c.year > 9999 then throw "OverflowError: date value out of range"
      return some (((c.hour * 60 + c.minute) * 60 + c.second) * 1000000 + c.micro)
    | .ok _ => return none
  | _ => return none

/-- `conditions.time` -/
def timeCond (env : CondEnv) (before after : Option TimeBound)
    (weekday : Option (List String)) : Except String Bool := do
  let nowUs := env.now.timeOfDay * 1000
  let afterUs ← match after with
    | none => pure (some 0)
    | some (.fixed us) => pure (some us)
    | some (.entity e) => resolveTimeBound env "after" e true
  let some afterUs := afterUs | return false
  let beforeUs ← match before with
    | none => pure (some 86399999999)
    | some (.fixed us) => pure (some us)
    | some (.entity e) => resolveTimeBound env "before" e false
  let some beforeUs := beforeUs | return false
  if afterUs < beforeUs then
    if !(afterUs ≤ nowUs && nowUs < beforeUs) then return false
  else
    if beforeUs ≤ nowUs && nowUs < afterUs then return false
  if let some wd := weekday then
    if !wd.contains env.now.weekday then return false
  return true

/-- Shared loop of `if_state` / `if_numeric_state`: errors are collected and
only raised if no entity decided the result. -/
def entityLoop (eids : List String) (check : String → Except String Bool)
    (matchAny : Bool) : CondResult := Id.run do
  let mut errors : List String := []
  let mut result := !matchAny
  for eid in eids do
    match check eid with
    | .ok true => result := true
    | .ok false => if !matchAny then return .ok (some false)
    | .error e => errors := errors ++ [e]
  if !errors.isEmpty then return .err (String.intercalate "; " errors)
  return .ok (some result)

/-- `zone(hass, zone_entity_id, entity_id)`: look both up, then match. -/
def zoneById (env : CondEnv) (zid eid : String) : Except String Bool := do
  let some z := env.states.get? zid | throw s!"unknown zone {zid}"
  let some ent := env.states.get? eid | throw s!"unknown entity {eid}"
  zoneCondition z ent

/-- `ZoneCondition._async_check`: every entity in some zone; errors are
raised only if no definitive result was found. -/
def zoneCond (env : CondEnv) (eids zones : List String) : CondResult :=
  let (allOk, errs) := eids.foldl (fun (ok, errs) eid =>
    let (entOk, errs) := zones.foldl (fun (eo, errs) zid =>
      match zoneById env zid eid with
      | .ok true => (true, errs)
      | .ok false => (eo, errs)
      | .error m => (eo, errs ++ [s!"error matching {eid} with {zid}: {m}"])) (false, errs)
    (ok && entOk, errs)) (true, [])
  if !errs.isEmpty && !allOk then .err s!"In 'zone' condition: {String.intercalate "; " errs}"
  else .ok (some allOk)

/-- `sun/condition.py::sun`: today's sunrise/sunset (tomorrow's when today's
fell on the previous local date), then the bounds. `before: sunrise` with
`after: sunset` is the dark period around midnight, an OR. -/
def sunCond (env : CondEnv) (before after : Option Bool) (bo ao : Int) : Except String Bool := do
  let some obs := env.location | throw "the sun condition needs HA's location"
  let nowUs : Int := (env.now.utc : Int) * 1000
  let localDay (us : Int) : Int := Int.fdiv (us + env.now.tzOffsetSec * Template.US_PER_SEC) Template.US_PER_DAY
  let today := localDay nowUs
  -- `get_astral_event_date(hass, event, date)`: `None` if it never occurs
  let ev (rise : Bool) (day : Int) : Option Int :=
    let (y, m, d) := Template.civilFromDays day
    Sun.sunEvent obs rise y m d
  let hasRise := before == some true || after == some true
  let hasSet := before == some false || after == some false
  let sr0 := ev true today
  let sr := if hasRise && (sr0.map (fun t => decide (today > localDay t))).getD false then ev true (today + 1) else sr0
  let ss0 := ev false today
  let ss := if hasSet && (ss0.map (fun t => decide (today > localDay t))).getD false then ev false (today + 1) else ss0
  -- polar regions: no sunrise/sunset today
  if sr.isNone && hasRise then return false
  if ss.isNone && hasSet then return false
  let srT := sr.getD 0
  let ssT := ss.getD 0
  if before == some true && after == some false then
    return nowUs < srT + bo || nowUs > ssT + ao
  if before == some true && nowUs > srT + bo then return false
  if before == some false && nowUs > ssT + bo then return false
  if after == some true && nowUs < srT + ao then return false
  if after == some false && nowUs < ssT + ao then return false
  return true

mutual
/-- `ConditionChecker.async_check` -/
def evalCond (env : CondEnv) : Condition → CondResult
  | .disabled => .ok none
  | .and cs => evalAnd env cs []
  | .or cs => evalOr env cs []
  | .not cs => evalNot env cs []
  | .state eids req forMs attr matchAny =>
      entityLoop eids (fun e => stateOne env e req forMs attr) matchAny
  | .numericState eids below above attr vt =>
      -- `if_numeric_state` is the matchAll loop
      entityLoop eids (fun e => numericStateOne env e below above attr
        (vt.map fun t => (t, env.vars))) false
  | .time before after wd =>
      match timeCond env before after wd with
      | .ok b => .ok (some b)
      | .error e => .err e
  | .trigger ids =>
      .ok (some (match env.triggerId with
        | some t => ids.contains t
        | none => false))
  | .template t =>
      match templateCond env t with
      | .ok b => .ok (some b)
      | .error e => .err e
  | .zone eids zones => zoneCond env eids zones
  | .sun before after bo ao =>
      match sunCond env before after bo ao with
      | .ok b => .ok (some b)
      | .error e => .err e

/-- `AndConditionChecker._async_check` -/
def evalAnd (env : CondEnv) : List Condition → List String → CondResult
  | [], errs => if errs.isEmpty then .ok (some true) else .err (String.intercalate "; " errs)
  | c :: cs, errs =>
    match evalCond env c with
    | .ok (some false) => .ok (some false)
    | .ok _ => evalAnd env cs errs
    | .err e => evalAnd env cs (errs ++ [e])

/-- `OrConditionChecker._async_check` -/
def evalOr (env : CondEnv) : List Condition → List String → CondResult
  | [], errs => if errs.isEmpty then .ok (some false) else .err (String.intercalate "; " errs)
  | c :: cs, errs =>
    match evalCond env c with
    | .ok (some true) => .ok (some true)
    | .ok _ => evalOr env cs errs
    | .err e => evalOr env cs (errs ++ [e])

/-- `NotConditionChecker._async_check`: `if condition.async_check(...)` is a
truthiness test, so `None` counts as false. -/
def evalNot (env : CondEnv) : List Condition → List String → CondResult
  | [], errs => if errs.isEmpty then .ok (some true) else .err (String.intercalate "; " errs)
  | c :: cs, errs =>
    match evalCond env c with
    | .ok (some true) => .ok (some false)
    | .ok _ => evalNot env cs errs
    | .err e => evalNot env cs (errs ++ [e])
end

/-- `ConditionsChecker.async_check`: the automation-level condition list.
Errors are logged and count as `False`. -/
def checkAutomationConditions (env : CondEnv) (cs : List Condition) : Bool :=
  match evalAnd env cs [] with
  | .ok (some false) => false
  | .ok _ => true
  | .err _ => false

/-- `_ScriptRun._test_conditions` (used by choose / if / while / until):
stops at the first error and returns `None`. -/
def testConditions (env : CondEnv) : List Condition → Option Bool
  | [] => some true
  | c :: cs =>
    match evalCond env c with
    | .ok (some false) => some false
    | .ok _ => testConditions env cs
    | .err _ => none

end HALean.Automation
