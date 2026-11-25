/-
  Automation configuration AST and its JSON decoder.

  The I/O shell loads `automations.yaml` (or asks HA for it) and sends it to the
  engine as JSON. Decoding normalises HA's many shorthands into one AST, the way
  `config_validation` + the platform schemas do upstream. Anything outside the
  supported subset is rejected with a message, never silently approximated.
-/
import HALean.Core.Types
import HALean.Template
import HALean.Template.CvBoolean
import HALean.Automation.TimePeriod
import HALean.Automation.Slugify
open Lean

namespace HALean.Automation

instance : Repr Template.Tmpl := ⟨fun t _ => repr t.src⟩

/-- A config value that may contain templates (`cv.template_complex`):
strings that are template strings become templates, everything else stays
as it is. -/
inductive Complex where
  | lit (j : Json)
  | tmpl (t : Template.Tmpl)
  | arr (xs : List Complex)
  | obj (kvs : List (Complex × Complex))
  deriving Repr, Inhabited

/-- A `below`/`above` bound: a literal number or another entity's state. -/
inductive Bound where
  | num (v : Float)
  | entity (eid : String)
  deriving Repr, Inhabited

/-- A `before`/`after` bound of the time condition. Fixed times are in
microseconds since local midnight, like Python's `datetime.time`. -/
inductive TimeBound where
  | fixed (us : Nat)
  | entity (eid : String)
  deriving Repr, Inhabited

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

/-- A `for:` period (`cv.positive_time_period_template`): static, or a
template rendered when it is needed. -/
inductive ForPeriod where
  | fixed (ms : Nat)
  | tmpl (c : Complex)
  deriving Repr, Inhabited

/-- Conditions. Mirrors `helpers/condition`. -/
inductive Condition where
  | and (cs : List Condition)
  | or (cs : List Condition)
  | not (cs : List Condition)
  /-- `match: any` is `matchAny = true`. `forP` is the `for:` period, rendered
  when the condition is checked if it is a template. -/
  | state (entityIds : List String) (states : List Json) (forP : Option ForPeriod)
      (attr : Option String) (matchAny : Bool)
  | numericState (entityIds : List String) (below above : Option Bound)
      (attr : Option String) (valueTemplate : Option Template.Tmpl := none)
  | time (before after : Option TimeBound) (weekday : Option (List String))
  | trigger (ids : List String)
  /-- `condition: template` and the string shorthand. -/
  | template (t : Template.Tmpl)
  /-- Legacy `zone` condition: every entity must be in one of the zones. -/
  | zone (entityIds zones : List String)
  /-- Legacy `sun` condition: `before`/`after` (`true` = sunrise, `false` =
  sunset) with their offsets in µs. -/
  | sun (before after : Option Bool) (beforeOffset afterOffset : Int)
  /-- `enabled: false`: `DisabledConditionChecker`, which returns `None`. -/
  | disabled
  deriving Repr, Inhabited

/-- `process_state_match`: `values = none` is MATCH_ALL. -/
structure StateMatch where
  values : Option (List Json) := none
  invert : Bool := false
  deriving Repr, Inhabited

/-- One field of a time pattern (`parse_time_expression`). -/
inductive Pattern where
  | any
  | every (n : Nat)
  | exact (n : Nat)
  deriving Repr, Inhabited, BEq

/-- A trigger's `for:` (`cv.positive_time_period_template`): a static
period, or a template string / a mapping holding templates, rendered when
the trigger's condition is met. -/
inductive TriggerKind where
  /-- `matchAll` is true iff none of from/not_from/to/not_to was *present*
  in the config (`to: ~` is present-but-null and so is not match-all). -/
  | state (entityIds : List String) (fromM toM : StateMatch) (matchAll : Bool)
      (attr : Option String) (forP : Option ForPeriod)
      (fromKeyOnly : Bool)  -- `from` present and `to` absent (for `_check_same_state`)
  | numericState (entityIds : List String) (below above : Option Bound)
      (attr : Option String) (forP : Option ForPeriod) (valueTemplate : Option Template.Tmpl := none)
  /-- `ats`: fixed local times of day (whole seconds); `entities`: `input_datetime` or
  timestamp `sensor` entities with an offset (µs), each rescheduled when its
  state changes. -/
  | time (ats : List Nat) (entities : List (String × Int)) (weekday : Option (List String))
  | timePattern (hours minutes seconds : Pattern)
  /-- Legacy `zone` trigger (`trigger: zone`): `enter` is `true` for
  `event: enter`, `false` for `leave`. -/
  | zone (entityIds : List String) (zone : String) (enter : Bool)
  /-- Legacy `sun` trigger: `sunrise` (or sunset) plus `offset` (µs). -/
  | sun (sunrise : Bool) (offsetUs : Int)
  /-- `event_type` and `event_data` as rendered when the trigger attached
  (`eventDataMatches`). -/
  | event (eventTypes : List String) (data : List (String × Json))
  /-- `homeassistant` with `event: start`: fires once, on `homeassistant_started`. -/
  | haStart
  /-- `tag`: a `tag_scanned` event whose `tag_id` (and `device_id`, when
  given) is one of these. -/
  | tag (tagIds : List String) (deviceIds : Option (List String))
  /-- `template` trigger (`components/template/trigger.py`). -/
  | template (t : Template.Tmpl) (forP : Option ForPeriod)
  /-- `mqtt` (`components/mqtt/trigger.py`): the subscription's topic filter
  (rendered when the trigger attached), the wanted payload (`none`: any
  message; rendered when the trigger attached), the `value_template` a
  received payload goes through before it is compared, and the
  subscription's `qos`. -/
  | mqtt (topic : String) (payload : Option String) (valueTemplate : Option Template.Tmpl)
      (qos : Nat)
  /-- `webhook` (`components/webhook/trigger.py`): the webhook id (rendered
  when the trigger attached), `allowed_methods` and `local_only`, which
  count only for the trigger that registers the webhook first. -/
  | webhook (webhookId : String) (allowedMethods : List String) (localOnly : Bool)
  deriving Repr, Inhabited

structure Trigger where
  id : String
  idx : Nat
  alias : Option String := none
  kind : TriggerKind
  /-- The trigger's own `variables`, rendered (not limited) when it fires,
  seeing `trigger` and the ones before them (`_trigger_action_wrapper`). -/
  variables : List (String × Complex) := []
  deriving Repr, Inhabited

/-- The service an action calls (`cv.service` or `dynamic_template`). -/
inductive SvcName where
  /-- Validated and lower-cased when the automation loads. -/
  | static (domain service : String)
  /-- Rendered when the step runs, then validated like a static name. -/
  | tmpl (t : Template.Tmpl)
  deriving Repr, Inhabited

inductive Action where
  /-- A service call (`async_prepare_call_from_config`): `data` holds `data`
  then `data_template`, each rendered to a mapping and merged in that order;
  `target` is rendered (a mapping or a whole template); `entityId` is the
  action's own `entity_id` (`comp_entity_ids`), written into the target
  last. `respVar`: `response_variable`, assigned the service's response. -/
  | service (name : SvcName) (data : List Complex) (target : Complex) (entityId : Option Json)
      (respVar : Option String)
  | delay (ms : Nat)
  /-- A templated `delay` (`cv.positive_time_period_template`), rendered
  when the step runs. -/
  | delayT (c : Complex)
  | condition (c : Condition)
  | choose (options : List (List Condition × List Action)) (default : Option (List Action))
  | ifThen (conds : List Condition) (thenA : List Action) (elseA : Option (List Action))
  | repeatCount (n : Nat) (body : List Action)
  /-- `count` given as a template: rendered when the repeat starts. -/
  | repeatCountT (t : Template.Tmpl) (body : List Action)
  /-- `for_each`: rendered when the repeat starts; must give a list. -/
  | repeatEach (items : Complex) (body : List Action)
  /-- `variables` action: rendered in order, then assigned to the run. -/
  | variables (vs : List (String × Complex))
  | repeatWhile (conds : List Condition) (body : List Action)
  | repeatUntil (conds : List Condition) (body : List Action)
  /-- `respVar`: the `response_variable` whose value the stop returns. -/
  | stop (reason : String) (error : Bool) (respVar : Option String)
  /-- `event_data` then `event_data_template`, merged in that order. -/
  | event (eventType : String) (data : List Complex)
  | sequence (body : List Action)
  /-- `wait_template` with an optional `timeout` (`cv.positive_time_period_template`,
  rendered when the step runs) and `continue_on_timeout` (default true). -/
  | waitTemplate (t : Template.Tmpl) (timeout : Option Complex) (continueOnTimeout : Bool)
  /-- `wait_for_trigger`: the triggers (disabled ones dropped), `timeout`,
  `continue_on_timeout`. -/
  | waitForTrigger (triggers : List Trigger) (timeout : Option Complex) (continueOnTimeout : Bool)
  /-- `parallel`: each branch is a sub-script started at the same time. -/
  | parallel (branches : List (List Action))
  /-- `continue_on_error: true` on the wrapped step. -/
  | continueOnError (a : Action)
  deriving Repr, Inhabited

inductive Mode where
  | single | restart | queued | parallel
  deriving Repr, Inhabited, BEq, DecidableEq

structure Automation where
  id : String
  alias : String
  triggers : List Trigger
  conditions : List Condition
  actions : List Action
  mode : Mode := .single
  maxRuns : Nat := 10
  /-- `trigger_variables` merged with `variables` (in that order), rendered
  at every trigger (`ScriptVariables.async_render`). -/
  variables : List (String × Complex) := []
  /-- `trigger_variables` (static only), seen by trigger templates. -/
  triggerVars : List (String × Json) := []
  /-- The automation entity's `entity_id`, when HALean can derive it exactly
  (`none` makes templates using `this` a load-time error). -/
  entityId : Option String := none
  /-- `unique_id`: the configured `id`, if any (the `id` attribute). -/
  uniqueId : Option String := none
  deriving Repr, Inhabited

/-! ## Decoding -/

abbrev D := Except String

def field? (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok v => some v
  | .error _ => none

def has (j : Json) (k : String) : Bool := (field? j k).isSome

def str? (j : Json) (k : String) : Option String :=
  (field? j k).bind fun v => v.getStr?.toOption

/-- A value that may be a single item or a list (`cv.ensure_list`). -/
def ensureList (j : Json) : List Json :=
  match j with
  | .arr a => a.toList
  | .null => []
  | v => [v]

def strList (j : Json) : D (List String) :=
  (ensureList j).mapM fun v => match v with
    | .str s => pure s
    | _ => throw s!"expected string, got {v.compress}"

/-- `cv.entity_id` on one item: `cv.string`, lower-cased, then
`valid_entity_id`. Python lower-cases all of Unicode (the Kelvin sign
becomes `k`), HALean only ASCII, so other text is refused. -/
def cvEntityIdStr (s : String) : D String := do
  if !s.toList.all (fun c => c.toNat < 128) then
    throw s!"non-ASCII entity id '{s}' is not supported by HALean"
  let l := s.toLower
  if Template.validEntityId l then pure l else throw s!"Entity ID {s} is an invalid entity ID"

/-- `cv.entity_ids` / `cv.entity_ids_or_uuids`: `ensure_list_csv` (a
string is split at commas and each piece stripped; a list is taken as it
is), then `cv.entity_id` on each item. An entity registry id (uuid) needs
the registry, which HALean does not have; it is refused like an invalid id. -/
def cvEntityIds (v : Json) : D (List String) := do
  let items : List Json := match v with
    | .str s => (s.splitOn ",").map fun x => Json.str x.trim
    | v => ensureList v
  items.mapM fun x => match x with
    | .str s => cvEntityIdStr s
    | x => throw s!"Entity ID {x.compress} is an invalid entity ID"

def entityIds (j : Json) : D (List String) :=
  match field? j "entity_id" with
  | some .null => throw "Entity IDs can not be None"
  | some v => cvEntityIds v
  | none => throw "missing entity_id"


/-- Python's `int(value)` for a JSON value: an int as is, a float truncated
toward zero, a string read as an integer literal, `True`/`False` as 1/0;
`none` where Python raises. -/
def pyIntOfJson? (v : Json) : Option Int :=
  match v with
  | .num _ => match Template.Value.ofJson v with
    | .int i => some i
    | .float f => Template.floatToInt? f
    | _ => none
  | .str s => Template.parseIntStr s
  | .bool b => some (if b then 1 else 0)
  | _ => none

/-- Python's `==` on two JSON values (`20 == 20.0`, `1 == True`). -/
def pyJsonEq (a b : Json) : Bool := Template.pyEq (Template.Value.ofJson a) (Template.Value.ofJson b)

def jsonNumToFloat (v : Json) : Option Float :=
  match v with
  | .num n => some n.toFloat
  | .str s => parsePyFloatStr s
  | _ => none

/-- A static `cv.positive_time_period` (`time_period_str`,
`time_period_seconds` or `time_period_dict`, then `positive_timedelta`),
in ms (rounded up, like the engine's other periods). -/
def durationMs (v : Json) : D Nat := do
  match v with
  | .null | .arr _ => throw s!"invalid time period: {v.compress}"
  | .str s =>
    if Template.isTemplateString s then throw s!"templated durations are not supported here: {s}"
  | _ => pure ()
  match cvTimePeriod (Template.Value.ofJson v) with
  | .error e => throw s!"invalid time period {v.compress}: {e}"
  | .ok us =>
    if us < 0 then throw "negative time period"
    pure ((us + 999) / 1000).toNat

def optDuration (j : Json) (k : String) : D (Option Nat) :=
  match field? j k with
  | none => pure none
  | some v => some <$> durationMs v


def bound? (j : Json) (k : String) : D (Option Bound) :=
  match field? j k with
  | none | some .null => pure none
  | some (.num n) => pure (some (.num n.toFloat))
  | some (.str s) =>
    match parsePyFloatStr s with
    | some f => pure (some (.num f))  -- vol.Coerce(float) accepts numeric strings
    | none => if s.contains '.' then pure (some (.entity s))
              else throw s!"invalid {k}: {s}"
  | some v => throw s!"invalid {k}: {v.compress}"

def timeBound? (j : Json) (k : String) : D (Option TimeBound) :=
  match str? j k with
  | none => pure none
  | some s => match Template.parseTimeSeconds s with
    | some sec => pure (some (.fixed (sec * 1000000)))
    | none => if s.contains '.' then pure (some (.entity s))
              else throw s!"invalid {k}: {s}"

def weekday? (j : Json) : D (Option (List String)) :=
  match field? j "weekday" with
  | none => pure none
  | some v => some <$> strList v

/-- The variables HALean passes to every template. Run templates also see
`repeat`, the automation's variables and `this` (`decodeAutomation`);
templates using anything else are rejected at load time. -/
def TEMPLATE_VARS : List String := ["trigger"]

def compileTemplate (s : String) (vars : List String := TEMPLATE_VARS) : D Template.Tmpl := do
  let t ← match Template.compile s with
    | .ok t => pure t
    | .error e => throw s!"invalid template ({e}): {s}"
  match Template.check t vars with
  | .ok () => pure t
  | .error e => throw e

/-- Template names a `limited` template may not use (`limited_ok=False`), and
date functions whose result depends on the time zone, which is not known at
load time. -/
def LIMITED_UNSUPPORTED : List String :=
  ["states", "is_state", "state_attr", "is_state_attr", "has_value", "expand",
   "now", "utcnow", "today_at", "relative_time", "time_since", "time_until", "timedelta_string",
   "as_local", "as_datetime", "as_timestamp", "timestamp_local", "timestamp_custom", "strptime"]

/-- How a templated `enabled` is handled where it appears. -/
inductive EnabledTmpl where
  /-- Rendered `limited` with these variables; a render error disables
  (a trigger: logged and skipped) or is refused (`none`). -/
  | render (vars : List (String × Json)) (onError : Option Bool)
  /-- Not rendered: the Template object itself is the value, and it is truthy
  (a `parallel` branch's `sequence:` passes it to `Script(enabled=...)`). -/
  | truthy
  /-- The variables are only known while the run runs (`wait_for_trigger`). -/
  | unsupported

/-- `enabled`: `probatio.Any(cv.boolean, cv.template)`, then `if not enabled`.
`cv.boolean` takes booleans, numbers (`!= 0`) and the words of
`cvBooleanText`; any other string is a template. -/
def isEnabled (j : Json) (how : EnabledTmpl := .render [] none) : D Bool := do
  match field? j "enabled" with
  | none => pure true
  | some (.bool b) => pure b
  | some (.num n) => pure (n.mantissa != 0)
  | some (.str s) =>
    if let some b := Template.cvBooleanText s then return b
    match how with
    | .truthy => pure true
    | .unsupported => throw s!"templated 'enabled' is not supported here: {s}"
    | .render vars onError =>
      let t ← compileTemplate s (vars.map (·.1))
      for n in (t.nodes.map Template.nodeNames).flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
        if LIMITED_UNSUPPORTED.contains n then
          throw s!"'{n}' in a templated 'enabled' is not supported by HALean"
      match Template.render t { states := [], vars := vars.map fun (k, x) => (k, Template.Value.ofJson x) } true with
      | .ok v => pure (Template.truthy v)
      | .error e => match onError with
        | some b => pure b
        | none => throw s!"Error rendering enabled template: {e}"
  | some v => throw s!"invalid enabled {v.compress}"

/-- `cv.template_complex` -/
partial def decodeComplex (j : Json) (nm : List String := TEMPLATE_VARS) : D Complex := do
  match j with
  | .str s => if Template.isTemplateString s then return .tmpl (← compileTemplate s nm) else return .lit j
  | .arr xs => return .arr (← xs.toList.mapM (decodeComplex · nm))
  | .obj kvs => return .obj (← kvs.toList.mapM fun (k, v) => do pure (← decodeComplex (.str k) nm, ← decodeComplex v nm))
  | _ => return .lit j

/-- numeric_state `value_template`: sees `state` (the entity's state object)
next to the run variables. -/
def valueTemplate? (j : Json) (nm : List String := TEMPLATE_VARS) : D (Option Template.Tmpl) :=
  match field? j "value_template" with
  | none => pure none
  | some (.str s) => some <$> compileTemplate s (nm ++ ["state"])
  | some v => throw s!"invalid value_template: {v.compress}"

partial def Complex.hasTemplate' : Complex → Bool
  | .lit _ => false
  | .tmpl _ => true
  | .arr xs => xs.any Complex.hasTemplate'
  | .obj kvs => kvs.any fun (k, v) => k.hasTemplate' || v.hasTemplate'

/-- `cv.positive_time_period_template`: `positive_time_period`, else
`dynamic_template`, else `_positive_time_period_template_complex` (a non-empty
mapping whose static keys are period units and whose static values are
non-negative numbers; it is kept as `template_complex`). Template names are
the trigger-time variables `nm`. -/
def forPeriod? (j : Json) (k : String) (nm : List String) : D (Option ForPeriod) := do
  match field? j k with
  | none => pure none
  | some (.str s) =>
    if Template.isTemplateString s then return some (.tmpl (.tmpl (← compileTemplate s nm)))
    return some (.fixed (← durationMs (.str s)))
  | some v@(.obj kvs) =>
    let c ← decodeComplex v nm
    if !c.hasTemplate' then return some (.fixed (← durationMs v))
    for (key, el) in kvs.toList do
      if !Template.isTemplateString key &&
          !["days", "hours", "minutes", "seconds", "milliseconds"].contains key then
        throw s!"invalid time period key '{key}'"
      let isTmpl := match el with | .str e => Template.isTemplateString e | _ => false
      if !isTmpl then
        let f := match el with
          | .bool b => some (if b then 1.0 else 0.0)
          | _ => jsonNumToFloat el
        match f with
        | some f => if f < 0 || f.isNaN then throw s!"invalid time period {k}: {el.compress}"
        | none => throw s!"invalid time period {k}: {el.compress}"
    return some (.tmpl c)
  | some v => return some (.fixed (← durationMs v))

/-- A wait step's `timeout` (`cv.positive_time_period_template`). A static
value is validated at load; a template is kept and rendered by the step. -/
def timeout? (j : Json) (nm : List String) : D (Option Complex) := do
  match field? j "timeout" with
  | none => pure none
  | some v =>
    let c ← decodeComplex v nm
    if !c.hasTemplate' then
      match cvPositiveTimePeriod (Template.Value.ofJson v) with
      | .ok _ => pure ()
      | .error e => throw s!"invalid timeout {v.compress}: {e}"
    pure (some c)

/-- `continue_on_timeout` (`cv.boolean`; HALean accepts only true/false). -/
def continueOnTimeout? (j : Json) : D Bool :=
  match field? j "continue_on_timeout" with
  | none => pure true
  | some (.bool b) => pure b
  | some v => throw s!"continue_on_timeout must be true or false, got {v.compress}"

/-- `response_variable` (`str`). -/
def responseVariable? (j : Json) : D (Option String) :=
  match field? j "response_variable" with
  | none => pure none
  | some (.str v) => pure (some v)
  | some v => throw s!"response_variable must be a string, got {v.compress}"

/-- A mapping whose order matters (`variables`). Lean's `Json` objects are
sorted by key, so the shell sends these as `[[key, value], ...]`; a plain
object is accepted too, in key order. -/
def orderedMapping (what : String) : Json → D (List (String × Json))
  | .obj kvs => pure kvs.toList
  | .arr xs => xs.toList.mapM fun x => match x with
    | .arr #[.str k, v] => pure (k, v)
    | _ => throw s!"{what}: expected [key, value] pairs"
  | _ => throw s!"{what} must be a mapping"

/-- `attribute`: HALean reads an attribute by its name, a string. HA takes
any key (`cv.match_all` for triggers), which then names no attribute. -/
def attrKey (j : Json) : D Unit :=
  match field? j "attribute" with
  | none | some (.str _) => pure ()
  | some v => throw s!"a non-string attribute name {v.compress} is not supported by HALean"

def noTemplate (j : Json) (k : String) : D Unit :=
  if has j k then throw s!"'{k}' (templates) is not supported" else pure ()

partial def decodeCondition (j : Json) (nm : List String := TEMPLATE_VARS) : D Condition := do
  if !(← isEnabled j) then return .disabled
  -- shorthand `- and: [...]`, `- or: [...]`, `- not: [...]`
  for k in ["and", "or", "not"] do
    if !has j "condition" then
      if let some cs := field? j k then
        let cs ← (ensureList cs).mapM (decodeCondition · nm)
        return match k with | "and" => .and cs | "or" => .or cs | _ => .not cs
  match j with
  | .str s =>
    -- `dynamic_template_condition`: the shorthand must be a real template
    if !Template.isTemplateString s then throw s!"invalid condition: {s}"
    return .template (← compileTemplate s nm)
  | _ => pure ()
  let some kind := str? j "condition" | throw s!"condition without 'condition' key: {j.compress}"
  let sub : D (List Condition) :=
    (ensureList ((field? j "conditions").getD .null)).mapM (decodeCondition · nm)
  match kind with
  | "and" => return .and (← sub)
  | "or" => return .or (← sub)
  | "not" => return .not (← sub)
  | "state" =>
    noTemplate j "value_template"
    let ids ← entityIds j
    let states := ensureList ((field? j "state").getD .null)
    let forP ← forPeriod? j "for" nm
    -- `STATE_CONDITION_SCHEMA`: `key_dependency("for", "state")`, and `for`
    -- is anchored to the entity's `last_changed`
    if forP.isSome then
      if !has j "state" then
        throw "dependency violation - key \"for\" requires key \"state\" to exist"
      if has j "attribute" then throw "Cannot use 'for' with an attribute"
      if states.any (fun v => match v with | .str x => isInputEntityId x | _ => false) then
        throw "Cannot use 'for' with a state referencing an entity"
    -- `STATE_CONDITION_STATE_SCHEMA`: `state: Any(str, [str])` without an
    -- attribute; `match_all` with one
    if !has j "attribute" then
      match field? j "state" with
      | some (.str _) => pure ()
      | some (.arr xs) =>
        if !xs.all (fun x => match x with | .str _ => true | _ => false) then
          throw "expected str for dictionary value @ data['state']"
      | some _ => throw "expected str for dictionary value @ data['state']"
      | none => throw "required key not provided @ data['state']"
    attrKey j
    -- `match`: `probatio.All(probatio.Lower, probatio.Any("all", "any"))`
    let matchAny ← match field? j "match" with
      | none => pure false
      | some (.str m) => match m.toLower with
        | "all" => pure false
        | "any" => pure true
        | _ => throw s!"value must be one of ['all', 'any'] for dictionary value @ data['match']"
      | some v => throw s!"value must be one of ['all', 'any'] for dictionary value @ data['match']: {v.compress}"
    return .state ids states forP (str? j "attribute") matchAny
  | "numeric_state" =>
    return .numericState (← entityIds j) (← bound? j "below") (← bound? j "above")
      (str? j "attribute") (← valueTemplate? j nm)
  | "time" => return .time (← timeBound? j "before") (← timeBound? j "after") (← weekday? j)
  | "trigger" => return .trigger (← strList ((field? j "id").getD .null))
  | "template" =>
    match field? j "value_template" with
    | some (.str s) => return .template (← compileTemplate s nm)
    | _ => throw "template condition needs a value_template string"
  | "zone" =>
    -- `zone: cv.entity_ids` (a list or a comma-separated string)
    let zones ← match field? j "zone" with
      | none | some .null => throw "zone condition needs a zone"
      | some v => cvEntityIds v
    return .zone (← entityIds j) zones
  | "sun" =>
    let ev (k : String) : D (Option Bool) := match field? j k with
      | none => pure none
      | some (.str s) => match s.toLower with
        | "sunrise" => pure (some true)
        | "sunset" => pure (some false)
        | _ => throw s!"sun condition {k} must be sunrise or sunset"
      | some v => throw s!"invalid sun condition {k}: {v.compress}"
    let off (k : String) : D Int := match field? j k with
      | none => pure 0
      | some v => match cvTimePeriod (Template.Value.ofJson v) with
        | .ok us => pure us
        | .error e => throw s!"invalid {k} {v.compress}: {e}"
    let before ← ev "before"
    let after ← ev "after"
    -- `vol.AtLeastOne("before", "after")`
    if !has j "before" && !has j "after" then throw "sun condition needs before or after"
    return .sun before after (← off "before_offset") (← off "after_offset")
  | other => throw s!"condition '{other}' is not supported"

/-- `process_state_match(parameter, invert)`: `None` and `MATCH_ALL`
(`"*"`) match everything (`not invert`); a string or any other
non-iterable is compared with `==`; a list by membership; a mapping
iterates over its keys. -/
def processStateMatch (v : Json) (invert : Bool) : StateMatch :=
  match v with
  | .null | .str "*" => { invert }
  | .arr xs => { values := some xs.toList, invert }
  | .obj kvs => { values := some (kvs.toList.map fun (k, _) => Json.str k), invert }
  | v => { values := some [v], invert }

/-- `if (from_state := config.get(CONF_FROM)) is not None: ... elif
(not_from_state := config.get(CONF_NOT_FROM)) is not None: ... else
MATCH_ALL`. -/
def stateMatch (j : Json) (pos neg : String) : StateMatch :=
  match field? j pos with
  | some .null | none =>
    match field? j neg with
    | some .null | none => {}
    | some v => processStateMatch v true
  | some v => processStateMatch v false

/-- `probatio.Any(str, [str], None)`: the state trigger's `from`, `to`,
`not_from` and `not_to` without an `attribute` ("These are str on purpose.
Want to catch YAML conversions"). -/
def strOrStrListOrNone (j : Json) (k : String) : D Unit :=
  match field? j k with
  | none | some .null | some (.str _) => pure ()
  | some (.arr xs) =>
    if xs.all (fun x => match x with | .str _ => true | _ => false) then pure ()
    else throw s!"expected str at '{k}'"
  | some _ => throw s!"expected str at '{k}'"

/-- `render_complex` of a JSON value: every template string (keys too) is
replaced by what `render` gives it. -/
partial def renderJsonTemplates (render : String → D Json) : Json → D Json
  | .str s => if Template.isTemplateString s then render s else pure (.str s)
  | .arr xs => do pure (.arr (← xs.toList.mapM (renderJsonTemplates render)).toArray)
  | .obj kvs => do
    let mut out := Json.mkObj []
    for (k, x) in kvs.toList do
      let k' ← match ← renderJsonTemplates render (.str k) with
        | .str k' => pure k'
        | kj => pure kj.compress
      out := out.setObjVal! k' (← renderJsonTemplates render x)
    pure out
  | x => pure x

partial def jsonHasList : Json → Bool
  | .arr _ => true
  | .obj m => m.toList.any fun (_, x) => jsonHasList x
  | _ => false

/-- `render_complex(value, variables, limited=True)` of a JSON value at load
time: the variables are known then, and a limited template reads neither
states nor the clock. -/
def limitedRenderJson (vars : List (String × Json)) (what : String) (v : Json) : D Json :=
  renderJsonTemplates (fun s => do
    let t ← compileTemplate s (vars.map (·.1))
    for n in (t.nodes.map Template.nodeNames).flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
      if LIMITED_UNSUPPORTED.contains n then
        throw s!"'{n}' in templated {what} is not supported by HALean"
    match Template.render t { states := [], vars := vars.map fun (k, x) => (k, Template.Value.ofJson x) } true with
    | .ok r => match r.toJson with
      | .ok j => pure j
      | .error e => throw s!"templated {what} '{s}': {e}"
    | .error e => throw s!"Error rendering {what}: {e}") v

/-- `cv.template`'s `str(value)`: a number or a boolean becomes its Python
text (`payload: true` is the template `True`). -/
def cvTemplateText (k : String) (v : Json) : D String :=
  match v with
  | .str s => pure s
  | .num _ | .bool _ => match Template.pyStr (Template.Value.ofJson v) with
    | .ok s => pure s
    | .error e => throw e
  | .null => throw s!"template value is None for dictionary value @ data['{k}']"
  | _ => throw s!"template value should be a string for dictionary value @ data['{k}']"

/-- `cv.string` of a scalar. -/
def cvStringOf (k : String) (v : Json) : D String :=
  match v with
  | .str s => pure s
  | .num _ | .bool _ => match Template.pyStr (Template.Value.ofJson v) with
    | .ok s => pure s
    | .error e => throw e
  | .null => throw s!"string value is None for dictionary value @ data['{k}']"
  | _ => throw s!"expected str for dictionary value @ data['{k}']"

/-- `Template(s).async_render(variables, limited=True, parse_result=False)`
when a trigger attaches: the variables are the static trigger_variables, so
the result is known at load time; a template that reads states or the clock
is refused. -/
def limitedRenderStr (tv : List (String × Json)) (what s : String) : D String := do
  let t ← compileTemplate s (tv.map (·.1))
  for n in (t.nodes.map Template.nodeNames).flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
    if LIMITED_UNSUPPORTED.contains n then
      throw s!"'{n}' in a templated {what} is not supported by HALean"
  match Template.render t { states := [], vars := tv.map fun (k, x) => (k, Template.Value.ofJson x) } false with
  | .ok (.str r) => pure r
  | .ok _ => throw s!"templated {what} '{s}' did not render to a string"
  | .error e => throw s!"templated {what} '{s}' fails to render: {e}"

/-! ### MQTT topics (`components/mqtt/util.py`) -/

/-- `valid_topic` -/
def mqttValidTopic (t : String) : D Unit := do
  if t.isEmpty then throw "MQTT topic name/filter must not be empty."
  if t.utf8ByteSize > 65535 then
    throw "MQTT topic name/filter must not be longer than 65535 encoded bytes."
  for c in t.toList do
    let n := c.toNat
    if n == 0 then throw "MQTT topic name/filter must not contain null character."
    if n ≤ 0x1f || (0x7f ≤ n && n ≤ 0x9f) then
      throw "MQTT topic name/filter must not contain control characters."
    if (0xfdd0 ≤ n && n ≤ 0xfdef) || n % 0x10000 == 0xfffe || n % 0x10000 == 0xffff then
      throw "MQTT topic name/filter must not contain non-characters."

/-- `valid_subscribe_topic` -/
def mqttValidSubscribeTopic (t : String) : D Unit := do
  mqttValidTopic t
  let cs := t.toList
  for (c, i) in cs.zipIdx do
    if c == '+' then
      if (i > 0 && cs[i - 1]? != some '/') || (i + 1 < cs.length && cs[i + 1]? != some '/') then
        throw "Single-level wildcard must occupy an entire level of the filter"
  match cs.idxOf? '#' with
  | none => pure ()
  | some i =>
    if i != cs.length - 1 then
      throw "Multi-level wildcard must be the last character in the topic filter."
    if cs.length > 1 && cs[i - 1]? != some '/' then
      throw "Multi-level wildcard must be after a topic level separator."

/-- `probatio.All(probatio.Coerce(int), probatio.In([0, 1, 2]))` -/
def mqttQos (v : Json) : D Nat := do
  let n : Option Int := match v with
    | .num n => some (n.mantissa.tdiv (10 ^ n.exponent))  -- `int()` truncates
    | .bool b => some (if b then 1 else 0)
    | .str s => s.trim.toInt?
    | _ => none
  match n with
  | some 0 => pure 0
  | some 1 => pure 1
  | some 2 => pure 2
  | some _ => throw "value must be one of [0, 1, 2] for dictionary value @ data['qos']"
  | none => throw "expected int for dictionary value @ data['qos']"

/-- The names Python's codec registry resolves to `utf_8`
(`encodings.normalize_encoding`, then the alias table). -/
def isUtf8Encoding (s : String) : Bool :=
  let n := (s.toLower.map fun c => if c == '-' || c == ' ' then '_' else c)
  ["utf_8", "utf8", "u8", "utf", "utf8_ucs2", "utf8_ucs4", "cp65001"].contains n

/-! ### Webhooks (`components/webhook/__init__.py`) -/

/-- `SUPPORTED_METHODS` -/
def WEBHOOK_METHODS : List String := ["GET", "HEAD", "POST", "PUT"]

/-- `str.upper()` for the strings that can become one of
`WEBHOOK_METHODS`: ASCII letters, plus the non-ASCII characters whose upper
case is ASCII (`ı`, `ſ`, `ﬅ`, `ﬆ`). Anything else stays as it is, so it is
not a method either way. -/
def pyUpperMethod (s : String) : String :=
  String.join (s.toList.map fun c =>
    if c == 'ı' then "I" else if c == 'ſ' then "S"
    else if c == 'ﬅ' || c == 'ﬆ' then "ST"
    else toString c.toUpper)

/-- `allowed_methods`: `probatio.All(probatio.EnsureList(),
[probatio.All(probatio.Upper, probatio.In(SUPPORTED_METHODS))], probatio.Unique())` -/
def webhookMethods (v : Json) : D (List String) := do
  let ms ← (ensureList v).mapM fun x => do
    let s ← match x with
      | .str s => pure s
      | .num _ | .bool _ => match Template.pyStr (Template.Value.ofJson x) with
        | .ok s => pure s
        | .error e => throw e
      | x => throw s!"value must be one of {WEBHOOK_METHODS} for dictionary value @ data['allowed_methods']: {x.compress}"
    let u := pyUpperMethod s
    if !WEBHOOK_METHODS.contains u then
      throw s!"value must be one of ['GET', 'HEAD', 'POST', 'PUT'] for dictionary value @ data['allowed_methods']"
    pure u
  if ms.eraseDups.length != ms.length then
    throw s!"contains duplicate items: {(ms.filter fun m => ms.count m > 1).eraseDups} for dictionary value @ data['allowed_methods']"
  pure ms

/-- `tvals`: the static trigger_variables, when the trigger attaches with
them (an automation's triggers, not `wait_for_trigger`). -/
def decodeTrigger (idx : Nat) (j : Json) (tnm : List String := [])
    (tvals : Option (List (String × Json)) := none) : D (Option Trigger) := do
  -- `async_initialize_triggers`: rendered `limited` with the trigger
  -- variables; a render error is logged and the trigger skipped
  if !(← isEnabled j (match tvals with
      | some tv => .render tv (some false)
      | none => .unsupported)) then return none
  let platform := (str? j "trigger").orElse (fun _ => str? j "platform") |>.getD ""
  let id := (str? j "id").getD (toString idx)
  -- the trigger's own `variables` (`cv.SCRIPT_VARIABLES_SCHEMA`)
  let ownVars ← match field? j "variables" with
    | none => pure []
    | some v => do
      if tvals.isNone then throw "a trigger's variables are not supported in wait_for_trigger"
      (← orderedMapping "variables" v).foldlM (init := []) fun acc (k, x) => do
        pure (acc ++ [(k, ← decodeComplex x (["trigger"] ++ acc.map (·.1)))])
  let kind ← match platform with
    | "state" => do
      let ids ← entityIds j
      let keys := ["from", "not_from", "to", "not_to"]
      -- `TRIGGER_STATE_SCHEMA` without an attribute, `TRIGGER_ATTRIBUTE_SCHEMA`
      -- (`cv.match_all`) with one
      if !has j "attribute" then
        for k in keys do strOrStrListOrNone j k
      attrKey j
      pure <| TriggerKind.state ids (stateMatch j "from" "not_from") (stateMatch j "to" "not_to")
        (keys.all fun k => !has j k) (str? j "attribute") (← forPeriod? j "for" (tnm ++ ["trigger"]))
        (has j "from" && !has j "to")
    | "numeric_state" => do
      let below ← bound? j "below"
      let above ← bound? j "above"
      if below.isNone && above.isNone then throw "numeric_state needs below or above"
      pure <| TriggerKind.numericState (← entityIds j) below above (str? j "attribute")
        (← forPeriod? j "for" (tnm ++ ["trigger"])) (← valueTemplate? j (tnm ++ ["trigger"]))
    | "time" => do
      -- `_TIME_TRIGGER_ENTITY`: an entity of domain input_datetime or sensor
      let timeEntity (s : String) : Bool :=
        match s.splitOn "." with
        | [d, o] => (d == "input_datetime" || d == "sensor") && !o.isEmpty
        | _ => false
      -- `_TIME_AT_SCHEMA`: `cv.time`, else an entity
      let timeAt (s : String) : D (Sum Nat (String × Int)) :=
        match Template.parseTimeSeconds s with
        | some sec => pure (Sum.inl sec)
        | none =>
          if timeEntity s then pure (Sum.inr (s, (0 : Int)))
          else throw s!"invalid time trigger 'at: {s}'"
      let items ← (ensureList ((field? j "at").getD .null)).mapM fun v => match v with
        | .str s =>
          if Template.isTemplateString s then do
            -- `render_complex(at_time, variables, limited=True)` when the
            -- trigger attaches. The variables are the static trigger_variables
            -- (`this` is rejected), so the result is known at load time.
            let some tv := tvals
              | throw s!"templated time trigger 'at: {s}' is not supported here"
            let t ← compileTemplate s (tv.map (·.1))
            let parts := t.nodes.map Template.nodeNames
            for n in parts.flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
              if LIMITED_UNSUPPORTED.contains n then
                throw s!"'{n}' in a templated time trigger 'at' is not supported by HALean"
            let ctx : Template.Ctx :=
              { states := [], vars := tv.map fun (k, x) => (k, Template.Value.ofJson x) }
            match Template.render t ctx true with
            | .ok (.str r) => timeAt r
            | .ok r => throw s!"templated time trigger 'at: {s}' rendered {(Template.pyRepr r).toOption.getD "?"}, not a string"
            | .error e => throw s!"templated time trigger 'at: {s}' fails to render: {e}"
          else timeAt s
        | .obj _ => do
          let some eid := str? v "entity_id" | throw "time trigger 'at' needs an entity_id"
          if !timeEntity eid then throw s!"time trigger entity must be input_datetime or sensor: {eid}"
          let off ← match field? v "offset" with
            | none => pure 0
            | some o => match cvTimePeriod (Template.Value.ofJson o) with
              | .ok us => pure us
              | .error e => throw s!"invalid time trigger offset {o.compress}: {e}"
          pure (Sum.inr (eid, off))
        | _ => throw s!"unsupported time trigger 'at': {v.compress}"
      let ats := items.filterMap fun x => match x with | .inl s => some s | _ => none
      let ents := items.filterMap fun x => match x with | .inr e => some e | _ => none
      pure <| TriggerKind.time ats ents (← weekday? j)
    | "time_pattern" => do
      -- `TimePattern(maximum)`: `"*"`; `"/n"` with `int(n)` in 1..maximum;
      -- else `int(value)` in 0..maximum
      let pat (k : String) (mx : Nat) : D (Option Pattern) := do
        let inRange (n : Int) : D Nat :=
          if 0 ≤ n && n ≤ mx then pure n.toNat
          else throw s!"must be a value between 0 and {mx} at '{k}'"
        let intText (t : String) : D Int := do
          if !Template.numberTextModelled t then
            throw s!"non-ASCII time_pattern value '{t}' is not supported by HALean"
          match Template.parseIntStr t with
          | some n => pure n
          | none => throw s!"invalid time_pattern value at '{k}'"
        match field? j k with
        | none => pure none
        | some (.str "*") => pure (some .any)
        | some (.str s) =>
          if s.startsWith "/" then do
            let n ← intText (s.dropS 1)
            if n == 0 then throw s!"must be a value between 1 and {mx} at '{k}'"
            pure (some (.every (← inRange n)))
          else pure (some (.exact (← inRange (← intText s))))
        | some v@(.num _) => match pyIntOfJson? v with
          | some n => pure (some (.exact (← inRange n)))
          | none => throw s!"invalid time_pattern value at '{k}'"
        | some (.bool b) => pure (some (.exact (if b then 1 else 0)))
        | some v => throw s!"invalid time_pattern value {v.compress} at '{k}'"
      let h ← pat "hours" 23
      let m ← pat "minutes" 59
      let s ← pat "seconds" 59
      if h.isNone && m.isNone && s.isNone then throw "time_pattern needs a field"
      -- "If larger units are specified, default the smaller units to zero"
      let m := if m.isNone && h.isSome then some (.exact 0) else m
      let s := if s.isNone && m.isSome then some (.exact 0) else s
      pure <| TriggerKind.timePattern (h.getD .any) (m.getD .any) (s.getD .any)
    | "event" => do
      -- `render_complex(..., variables, limited=True)` when the trigger
      -- attaches: the variables are the static trigger_variables, so the
      -- result is known at load time
      let limited (s : String) : D Template.Value := do
        let some tv := tvals
          | throw s!"templated event trigger '{s}' is not supported here"
        let t ← compileTemplate s (tv.map (·.1))
        for n in (t.nodes.map Template.nodeNames).flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
          if LIMITED_UNSUPPORTED.contains n then
            throw s!"'{n}' in a templated event trigger is not supported by HALean"
        match Template.render t { states := [], vars := tv.map fun (k, x) => (k, Template.Value.ofJson x) } true with
        | .ok v => pure v
        | .error e => throw s!"templated event trigger '{s}' fails to render: {e}"
      let renderJ := renderJsonTemplates fun s => do
        match (← limited s).toJson with
        | .ok j => pure j
        | .error e => throw s!"templated event trigger '{s}': {e}"
      -- `event_type`: `[cv.template]`; a type that renders to something other
      -- than a string never matches
      let types ← (ensureList ((field? j "event_type").getD .null)).filterMapM fun v => do
        match v with
        | .str s =>
          if Template.isTemplateString s then
            match ← limited s with
            | .str r => pure (some r)
            | _ => pure none
          else pure (some s)
        | .num _ | .bool _ => pure (some v.compress)
        | v => throw s!"invalid event_type {v.compress}"
      if types.isEmpty then throw "event trigger needs an event_type"
      if types.contains "state_reported" then throw "Can't listen to state_reported in event trigger"
      let data ← match field? j "event_data" with
        | none => pure []
        | some d@(.obj _) =>
          let .obj kvs ← renderJ d | throw "event_data must be a mapping"
          let kvs := kvs.toList
          -- with a mapping among the values HA matches with a probatio schema,
          -- where a list is a sequence validator, not a value
          if kvs.any (fun (_, v) => match v with | .obj _ => true | _ => false) &&
              kvs.any (fun (_, v) => jsonHasList v) then
            throw "a list in nested event_data is not supported"
          pure kvs
        | some v => throw s!"invalid event_data {v.compress}"
      noTemplate j "context"
      pure <| TriggerKind.event types data
    | "template" => do
      let some (.str src) := field? j "value_template"
        | throw "template trigger needs a value_template string"
      -- trigger templates only see `trigger_variables`, which HALean does not
      -- support, so they may not use any variables at all
      let t ← match Template.compile src with
        | .ok t => pure t
        | .error e => throw s!"invalid template ({e}): {src}"
      match Template.check t tnm with
      | .ok () => pure ()
      | .error e => throw e
      pure <| TriggerKind.template t (← forPeriod? j "for" (tnm ++ ["trigger"]))
    | "zone" => do
      let some z := str? j "zone" | throw "zone trigger needs a zone entity id"
      let z ← cvEntityIdStr z
      let enter ← match field? j "event" with
        | none | some (.str "enter") => pure true
        | some (.str "leave") => pure false
        | some v => throw s!"zone trigger event must be enter or leave, got {v.compress}"
      pure <| TriggerKind.zone (← entityIds j) z enter
    | "sun" => do
      let sunrise ← match str? j "event" with
        | some "sunrise" => pure true
        | some "sunset" => pure false
        | _ => throw "sun trigger event must be sunrise or sunset"
      let off ← match field? j "offset" with
        | none => pure 0
        | some v => match cvTimePeriod (Template.Value.ofJson v) with
          | .ok us => pure us
          | .error e => throw s!"invalid sun trigger offset {v.compress}: {e}"
      pure <| TriggerKind.sun sunrise off
    | "homeassistant" =>
      match field? j "event" with
      | some (.str "start") => pure TriggerKind.haStart
      | some (.str "shutdown") =>
        throw "the homeassistant shutdown trigger is not supported: HA runs it as a shutdown job, before any event the shell sees"
      | _ => throw "value must be one of ['shutdown', 'start'] for dictionary value @ data['event']"
    | "tag" =>
      -- `probatio.All(probatio.EnsureList(), [cv.string])`
      let strs (k : String) (v : Json) : D (List String) :=
        (ensureList v).mapM fun x => match x with
          | .str s => pure s
          | x@(.num _) | x@(.bool _) => match Template.pyStr (Template.Value.ofJson x) with
            | .ok s => pure s
            | .error e => throw e
          | x => throw s!"expected str for {k}, got {x.compress}"
      let some tagJ := field? j "tag_id" | throw "required key not provided @ data['tag_id']"
      let tags ← strs "tag_id" tagJ
      let devs ← match field? j "device_id" with
        | none => pure none
        | some d => some <$> strs "device_id" d
      pure (TriggerKind.tag tags devs)
    | "mqtt" => do
      -- `TRIGGER_SCHEMA`, then `async_attach_trigger`
      let some topicJ := field? j "topic" | throw "required key not provided @ data['topic']"
      let topicRaw ← cvTemplateText "topic" topicJ
      let topic ← if Template.isTemplateString topicRaw then do
          -- `topic_template.async_render(variables, limited=True, parse_result=False)`,
          -- then `valid_subscribe_topic`; an error fails the attach
          let some tv := tvals
            | throw s!"templated mqtt topic '{topicRaw}' is not supported here"
          let t ← limitedRenderStr tv "mqtt topic" topicRaw
          mqttValidSubscribeTopic t
          pure t
        else do
          -- `valid_subscribe_topic_template`: a static topic is validated as
          -- written; the subscription uses the template's (stripped) text
          mqttValidSubscribeTopic topicRaw
          pure (← compileTemplate topicRaw []).src
      -- `MqttCommandTemplate(config.get(CONF_PAYLOAD)).async_render(None, variables)`:
      -- rendered (not limited, `parse_result=False`) with `value` = None and
      -- the trigger variables, then `convert_outgoing_mqtt_payload`
      let payload ← match field? j "payload" with
        | none => pure none
        | some pj => do
          let raw ← cvTemplateText "payload" pj
          let names := (tvals.getD []).map (·.1) ++ ["value"]
          let t ← compileTemplate raw names
          let s ← if t.isStatic then pure t.src else do
            let some tv := tvals
              | throw s!"templated mqtt payload '{raw}' is not supported here"
            for n in (t.nodes.map Template.nodeNames).flatMap (fun p => p.1.1 ++ p.1.2.1 ++ p.1.2.2) do
              if LIMITED_UNSUPPORTED.contains n then
                throw s!"'{n}' in a templated mqtt payload is not supported by HALean"
            let vars := tv.map (fun (k, x) => (k, Template.Value.ofJson x)) ++ [("value", .none)]
            match Template.render t { states := [], vars } false with
            | .ok (.str r) => pure r
            | .ok _ => throw s!"templated mqtt payload '{raw}' did not render to a string"
            | .error e => throw s!"templated mqtt payload '{raw}' fails to render: {e}"
          -- a Python bytes literal would become `bytes`, which never equals a
          -- received (decoded) payload
          if s.startsWith "b'" || s.startsWith "b\"" then
            throw s!"an mqtt payload that reads as a Python bytes literal is not supported by HALean: {s}"
          pure (some s)
      -- `value_template`: rendered with `value` / `value_json` only
      let vt ← match field? j "value_template" with
        | none => pure none
        | some v => some <$> compileTemplate (← cvTemplateText "value_template" v) ["value", "value_json"]
      -- `encoding`: the protocol delivers payloads as text (UTF-8)
      match field? j "encoding" with
      | none => pure ()
      | some v =>
        let enc ← cvStringOf "encoding" v
        if enc.isEmpty then
          throw "mqtt encoding '' (raw bytes payloads) is not supported by HALean"
        if !isUtf8Encoding enc then
          throw s!"mqtt encoding '{enc}' is not supported by HALean (the shell delivers UTF-8 text)"
      let qos ← match field? j "qos" with
        | none => pure 0
        | some v => mqttQos v
      pure (TriggerKind.mqtt topic payload vt qos)
    | "webhook" => do
      let some idJ := field? j "webhook_id" | throw "required key not provided @ data['webhook_id']"
      let raw ← cvTemplateText "webhook_id" idJ
      -- `webhook_id_template.async_render(variables, limited=True, parse_result=False)`
      let wid ← if Template.isTemplateString raw then do
          let some tv := tvals
            | throw s!"templated webhook_id '{raw}' is not supported here"
          limitedRenderStr tv "webhook_id" raw
        else pure (← compileTemplate raw []).src
      let methods ← match field? j "allowed_methods" with
        | none => pure ["POST", "PUT"]  -- `DEFAULT_METHODS`
        | some v => webhookMethods v
      let localOnly ← match field? j "local_only" with
        | none => pure true
        | some (.bool b) => pure b
        | some _ => throw "expected bool for dictionary value @ data['local_only']"
      pure (TriggerKind.webhook wid methods localOnly)
    | p => throw s!"trigger platform '{p}' is not supported"
  return some { id, idx, alias := str? j "alias", kind, variables := ownVars }

/-- `cv.comp_entity_ids`: `all` / `none` (any case), or entity ids
(`ensure_list_csv`, each lower-cased and validated). -/
def compEntityIds (v : Json) : D Json := do
  let ids ← match v with
    | .str s =>
      if s.toLower == "all" || s.toLower == "none" then return .str s.toLower
      pure ((s.splitOn ",").map String.trim)
    | .arr xs => xs.toList.mapM fun x => match x with
      | .str s => pure s
      | x => throw s!"Entity ID {x.compress} is an invalid entity ID"
    | v => throw s!"Entity ID {v.compress} is an invalid entity ID"
  let ids := ids.map String.toLower
  for e in ids do
    if !Template.validEntityId e then throw s!"Entity ID {e} is an invalid entity ID"
  return .arr (ids.map Json.str).toArray

partial def decodeAction (j : Json) (nm : List String := TEMPLATE_VARS) : D (Option Action) := do
  if !(← isEnabled j) then return none
  let coe := match field? j "continue_on_error" with | some (.bool true) => true | _ => false
  let wrap (a : Action) : Option Action := some (if coe then .continueOnError a else a)
  let seq (k : String) : D (List Action) := do
    let xs ← (ensureList ((field? j k).getD .null)).mapM (decodeAction · nm)
    pure (xs.filterMap (fun x => x))
  let seqOf (v : Json) : D (List Action) := do
    let xs ← (ensureList v).mapM (decodeAction · nm)
    pure (xs.filterMap (fun x => x))
  let conds (v : Json) : D (List Condition) := (ensureList v).mapM (decodeCondition · nm)
  if has j "action" || has j "service" || has j "service_template" then
    -- `_backward_compat_service_schema`: `service` is the old name of `action`
    if has j "action" && has j "service" then
      throw "Cannot specify both 'service' and 'action'. Please use 'action' only."
    if (has j "action" || has j "service") && has j "service_template" then
      throw "two or more values in the same group of exclusion 'service name'"
    let nameJ := ((field? j "action").orElse fun _ => (field? j "service").orElse fun _ =>
      field? j "service_template").getD .null
    let name ← match nameJ with
      | .str svc =>
        if Template.isTemplateString svc then pure (SvcName.tmpl (← compileTemplate svc nm))
        else
          -- `cv.service`: lower-case, then the entity id format
          let svc := svc.toLower
          if !Template.validEntityId svc then
            throw s!"Service {svc} does not match format <domain>.<name>"
          match svc.splitOn "." with
          | [d, sv] => pure (SvcName.static d sv)
          | _ => throw s!"Service {svc} does not match format <domain>.<name>"
      | v => throw s!"invalid service name {v.compress}"
    -- `data` / `data_template`: `Any(template, All(dict, template_complex))`
    let dataOf (k : String) : D (Option Complex) := do
      match field? j k with
      | none => pure none
      | some d@(.obj _) => some <$> decodeComplex d nm
      | some (.str t) => some <$> (Complex.tmpl <$> compileTemplate t nm)
      | some v@(.num _) | some v@(.bool _) => pure (some (.lit v))
      | some v => throw s!"invalid {k}: {v.compress}"
    let data := (← dataOf "data").toList ++ (← dataOf "data_template").toList
    -- `target`: a mapping (templates inside) or one `dynamic_template`
    let target ← match field? j "target" with
      | none => pure (Complex.obj [])
      | some t@(.obj _) => decodeComplex t nm
      | some (.str t) =>
        if Template.isTemplateString t then Complex.tmpl <$> compileTemplate t nm
        else throw s!"target: template value does not contain a dynamic template"
      | some v => throw s!"invalid target {v.compress}"
    -- the action's own `entity_id` (`cv.comp_entity_ids`)
    let entityId ← match field? j "entity_id" with
      | none => pure none
      | some v => some <$> compEntityIds v
    return wrap (.service name data target entityId (← responseVariable? j))
  if has j "delay" then
    match ← forPeriod? j "delay" nm with
    | some (.tmpl c) => return wrap (.delayT c)
    | some (.fixed ms) => return wrap (.delay ms)
    | none => throw "delay needs a period"
  if has j "condition" then
    -- `CONDITION_ACTION_SCHEMA` has no `continue_on_error`
    if has j "continue_on_error" then
      throw "extra keys not allowed @ data['continue_on_error']"
    return wrap (.condition (← decodeCondition j nm))
  if let some opts := field? j "choose" then
    let options ← (ensureList opts).mapM fun o => do
      pure ((← conds ((field? o "conditions").getD .null)), (← seqOf ((field? o "sequence").getD .null)))
    let dflt ← match field? j "default" with
      | none => pure none
      | some v => some <$> seqOf v
    return wrap (.choose options dflt)
  if let some c := field? j "if" then
    let el ← match field? j "else" with
      | none => pure none
      | some v => some <$> seqOf v
    return wrap (.ifThen (← conds c) (← seq "then") el)
  if let some r := field? j "repeat" then
    let body ← seqOf ((field? r "sequence").getD .null)
    if let some c := field? r "count" then
      -- `probatio.Any(probatio.Coerce(int), cv.template)`: `int(count)`
      -- (`2.0` and `2.5` are 2, `true` is 1); text `int()` cannot read is
      -- a template, rendered and passed to `int()` when the step runs
      match c with
      | .num _ | .bool _ => match pyIntOfJson? c with
        | some n => return wrap (.repeatCount n.toNat body)
        | none => throw s!"invalid repeat count {c.compress}"
      | .str s =>
        if !Template.isTemplateString s && Template.numberTextModelled s then do
          if let some n := Template.parseIntStr s then return wrap (.repeatCount n.toNat body)
        return wrap (.repeatCountT (← compileTemplate s nm) body)
      | _ => throw s!"invalid repeat count {c.compress}"
    if let some c := field? r "while" then return wrap (.repeatWhile (← conds c) body)
    if let some c := field? r "until" then return wrap (.repeatUntil (← conds c) body)
    if let some items := field? r "for_each" then return wrap (.repeatEach (← decodeComplex items nm) body)
    throw "repeat needs count, for_each, while or until"
  if let some s := str? j "stop" then
    let err := match field? j "error" with | some (.bool true) => true | _ => false
    let rv ← responseVariable? j
    -- `_stop_action_check_error_response`
    if err && rv.isSome then throw "'response_variable' cannot be used with 'error: true'"
    return wrap (.stop s err rv)
  if let some e := str? j "event" then
    -- `event_data` / `event_data_template`: `probatio.All(dict, template_complex)`
    let src (k : String) : D (List Complex) := do
      match field? j k with
      | none => pure []
      | some d@(.obj _) => pure [← decodeComplex d nm]
      | some _ => throw s!"{k} must be a mapping"
    return wrap (.event e ((← src "event_data") ++ (← src "event_data_template")))
  if has j "sequence" then return wrap (.sequence (← seq "sequence"))
  if let some ps := field? j "parallel" then
    -- each item is a `sequence:` mapping (`_SCRIPT_SEQUENCE_SCHEMA`) or a
    -- single action (`_parallel_sequence_action`); a disabled branch is
    -- skipped (`_async_run_script` with `enabled: false`)
    let branches ← (ensureList ps).mapM fun b => do
      if has b "sequence" && !(has b "action" || has b "service") then
        if !(← isEnabled b .truthy) then return []
        seqOf ((field? b "sequence").getD .null)
      else
        return (← decodeAction b nm).toList
    return wrap (.parallel (branches.filter (!·.isEmpty)))
  if let some w := field? j "wait_template" then
    let .str src := w | throw s!"wait_template must be a template, got {w.compress}"
    return wrap (.waitTemplate (← compileTemplate src nm) (← timeout? j nm) (← continueOnTimeout? j))
  if let some w := field? j "wait_for_trigger" then
    -- trigger templates see the run's variables (and `trigger`)
    let trigs ← (ensureList w).zipIdx.mapM fun (t, i) => decodeTrigger i t nm
    return wrap (.waitForTrigger (trigs.filterMap id) (← timeout? j nm) (← continueOnTimeout? j))
  if let some vs := field? j "variables" then
    return wrap (.variables (← (← orderedMapping "variables" vs).mapM fun (k, v) => do pure (k, ← decodeComplex v nm)))
  throw s!"action not supported: {j.compress}"

/-- Keys of every `variables:` action anywhere in an action list. -/
partial def actionVariableNames (j : Json) : List String :=
  match j with
  | .arr xs => xs.toList.flatMap actionVariableNames
  | .obj kvs =>
    let here := (match field? j "variables" with
      | some v => ((orderedMapping "variables" v).toOption.getD []).map (·.1)
      | none => []) ++ (match field? j "response_variable" with
      | some (.str v) => [v]
      | _ => [])
    here ++ kvs.toList.flatMap fun (k, v) => if k == "variables" then [] else actionVariableNames v
  | _ => []

/-- `automation/__init__.py::_automation_name`: the alias, else
`automation <position in the config list>`. -/
def automationName (j : Json) (listNo : Nat) : String :=
  match str? j "alias" with
  | some a => if a.isEmpty then s!"automation {listNo}" else a
  | none => s!"automation {listNo}"

/-- `MAX_LENGTH_STATE_ENTITY_ID` -/
def MAX_LENGTH_STATE_ENTITY_ID : Nat := 255

/-- `EntityRegistry.async_get_available_entity_id`: `domain.slug`, else
`_2`, `_3`, ... until it is neither registered nor in the state machine. -/
def availableEntityId (domain slug : String) (taken : List String) : String := Id.run do
  let preferred := s!"{domain}.{slug}"
  let mut test := String.ofList (preferred.toList.take MAX_LENGTH_STATE_ENTITY_ID)
  let mut tries := 1
  for _ in [0:taken.length + 1] do
    if !taken.contains test then break
    tries := tries + 1
    let lenSuffix := (toString tries).length + 1
    test := String.ofList (preferred.toList.take (MAX_LENGTH_STATE_ENTITY_ID - lenSuffix)) ++ s!"_{tries}"
  return test

/-- The entity ids HA gives the configured automations: `EntityPlatform`
adds them one by one in config order (`_async_add_entities`), each taking
`async_get_available_entity_id(slugify(name))` against the ids already
taken (`taken`: the state machine's entities). Once one name cannot be
slugified exactly, the ids of it and of every later automation are unknown
(`none`), since they could collide with it. -/
def automationEntityIds (raw : List Json) (taken : List String) : List (Option String) := Id.run do
  let mut taken := taken
  let mut known := true
  let mut out : List (Option String) := []
  for (j, i) in raw.zipIdx do
    match known, slugify? (automationName j i) with
    | true, some slug =>
      let eid := availableEntityId "automation" slug taken
      taken := taken ++ [eid]
      out := out ++ [some eid]
    | _, _ =>
      known := false
      out := out ++ [none]
  return out

/-- `max` of an automation or a script (`helpers/script.py`
`make_script_schema`): `probatio.All(probatio.Coerce(int),
probatio.Range(min=2))`. So `2.5` is 2, `"3"` is 3, and 0, 1, a negative
number or `true` are refused. -/
def maxRunsOf (v : Json) : Except String Nat :=
  match pyIntOfJson? v with
  | none => .error "expected int at 'max'"
  | some i => if i < 2 then .error "value must be at least 2 at 'max'" else .ok i.toNat

/-- Decode one automation, the `listNo`-th in the configuration, whose
entity id is `entityId` (see `automationEntityIds`). -/
def decodeAutomation (j : Json) (listNo : Nat := 0) (entityId : Option String := none) :
    D Automation := do
  let id := (str? j "id").getD ""
  let alias := automationName j listNo
  let mapping (k : String) : D (List (String × Json)) :=
    match field? j k with
    | none => pure []
    | some v => orderedMapping k v
  let tvars ← mapping "trigger_variables"
  -- `_async_attach_triggers`: trigger_variables are rendered `limited` when
  -- the triggers attach, in order, each seeing the ones before it and
  -- `this` (a run variable, so a trigger variable named `this` is skipped).
  -- Limited templates read neither states nor the clock, so the values the
  -- triggers see are known now. (At each trigger they are rendered again
  -- with the automation's variables.)
  let tvals ← tvars.foldlM (init := []) fun acc (k, v) => do
    if k == "this" || acc.any (·.1 == k) then return acc
    pure (acc ++ [(k, ← limitedRenderJson acc "trigger_variables" v)])
  let vars ← mapping "variables"
  -- `ScriptVariables(trigger_variables).variables.update(variables)`
  let merged := vars.foldl (fun acc (k, v) =>
    if acc.any (·.1 == k) then acc.map fun (k', v') => if k' == k then (k, v) else (k', v')
    else acc ++ [(k, v)]) tvars
  let pick (a b : String) := (field? j a).orElse (fun _ => field? j b) |>.getD .null
  -- the names templates may use: `trigger`, `repeat`, `this` (when the
  -- automation's entity id is known), and every variable the automation
  -- defines (anywhere, including `variables` actions)
  -- (and the variables triggers define)
  let trigVarNames := (ensureList (pick "triggers" "trigger")).flatMap fun t =>
    match field? t "variables" with
    | some (.obj kvs) => kvs.toList.map (·.1)
    | some (.arr xs) => xs.toList.filterMap fun x => match x with
      | .arr #[.str k, _] => some k
      | _ => none
    | _ => []
  let nm := TEMPLATE_VARS ++ ["repeat", "wait"] ++ (if entityId.isSome then ["this"] else [])
    ++ merged.map (·.1) ++ trigVarNames ++ actionVariableNames (pick "actions" "action")
  let mvars ← merged.mapM fun (k, v) => do pure (k, ← decodeComplex v nm)
  let tnm := tvals.map (·.1)
  let trigs ← ((ensureList (pick "triggers" "trigger")).zipIdx).mapM fun (t, i) => decodeTrigger i t tnm (some tvals)
  let conds ← (ensureList (pick "conditions" "condition")).mapM (decodeCondition · nm)
  let acts ← (ensureList (pick "actions" "action")).mapM (decodeAction · nm)
  let mode ← match str? j "mode" with
    | none | some "single" => pure Mode.single
    | some "restart" => pure .restart
    | some "queued" => pure .queued
    | some "parallel" => pure .parallel
    | some m => throw s!"unknown mode {m}"
  let maxRuns ← match field? j "max" with
    | none => pure 10
    | some v => match maxRunsOf v with
      | .ok n => pure n
      | .error m => throw m
  return { id, alias, triggers := trigs.filterMap (fun x => x), conditions := conds,
           actions := acts.filterMap (fun x => x), mode, maxRuns,
           variables := mvars, triggerVars := tvals, entityId, uniqueId := str? j "id" }

end HALean.Automation
