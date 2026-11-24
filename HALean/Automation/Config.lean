/-
  Automation configuration AST and its JSON decoder.

  The I/O shell loads `automations.yaml` (or asks HA for it) and sends it to the
  engine as JSON. Decoding normalises HA's many shorthands into one AST, the way
  `config_validation` + the platform schemas do upstream. Anything outside the
  supported subset is rejected with a message, never silently approximated.
-/
import HALean.Core.Types
import HALean.Template
import HALean.Automation.TimePeriod
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

/-- Conditions. Mirrors `helpers/condition`. -/
inductive Condition where
  | and (cs : List Condition)
  | or (cs : List Condition)
  | not (cs : List Condition)
  /-- `match: any` is `matchAny = true`. `forMs` is the static `for:` period. -/
  | state (entityIds : List String) (states : List Json) (forMs : Option Nat)
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
inductive ForPeriod where
  | fixed (ms : Nat)
  | tmpl (c : Complex)
  deriving Repr, Inhabited

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
  /-- Flat `event_data` only: every pair must be present and equal. -/
  | event (eventTypes : List String) (data : List (String × Json))
  /-- `template` trigger (`components/template/trigger.py`). -/
  | template (t : Template.Tmpl) (forP : Option ForPeriod)
  deriving Repr, Inhabited

structure Trigger where
  id : String
  idx : Nat
  alias : Option String := none
  kind : TriggerKind
  deriving Repr, Inhabited

inductive Action where
  /-- `respVar`: `response_variable`, assigned the service's response. -/
  | service (domain service : String) (data target : Complex) (respVar : Option String)
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
  | event (eventType : String) (data : Complex)
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

def entityIds (j : Json) : D (List String) :=
  match field? j "entity_id" with
  | some v => do
    -- `entity_id: "a.b, c.d"` is accepted by cv.entity_ids
    let xs ← strList v
    pure (xs.flatMap fun s => (s.splitOn ",").map String.trim |>.filter (· ≠ ""))
  | none => throw "missing entity_id"

def isEnabled (j : Json) : D Bool :=
  match field? j "enabled" with
  | none => pure true
  | some (.bool b) => pure b
  | some v => throw s!"templated 'enabled' is not supported: {v.compress}"

def jsonNumToFloat (v : Json) : Option Float :=
  match v with
  | .num n => some n.toFloat
  | .str s => parsePyFloatStr s
  | _ => none

/-- `cv.time_period`: "HH:MM[:SS[.fff]]", seconds, or a dict. Returns ms. -/
def durationMs (v : Json) : D Nat := do
  let ofSec (f : Float) : D Nat :=
    if f < 0 then throw "negative time period" else pure (f * 1000).round.toUInt64.toNat
  match v with
  | .num n => ofSec n.toFloat
  | .str s =>
    if Template.isTemplateString s then throw s!"templated durations are not supported here: {s}" else
    let (neg, s) := if s.startsWith "-" then (true, s.dropS 1) else (false, s)
    if neg then throw "negative time period" else
    let parts := s.splitOn ":"
    let nums := parts.map parsePyFloatStr
    match nums with
    | [some h, some m] => ofSec (h * 3600 + m * 60)
    | [some h, some m, some sec] => ofSec (h * 3600 + m * 60 + sec)
    | [some sec] => ofSec sec
    | _ => throw s!"invalid time period: {s}"
  | .obj _ => do
    let g (k : String) : D Float := match field? v k with
      | none => pure 0
      | some x => match jsonNumToFloat x with
        | some f => pure f
        | none => throw s!"invalid {k} in time period"
    let d ← g "days"; let h ← g "hours"; let m ← g "minutes"
    let sec ← g "seconds"; let ms ← g "milliseconds"
    ofSec (d * 86400 + h * 3600 + m * 60 + sec + ms / 1000)
  | _ => throw s!"invalid time period: {v.compress}"

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
    let forMs ← optDuration j "for"
    let matchAny := str? j "match" == some "any"
    return .state ids states forMs (str? j "attribute") matchAny
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
    let zones := (← strList ((field? j "zone").getD .null)).flatMap fun s =>
      (s.splitOn ",").map String.trim |>.filter (· ≠ "")
    if zones.isEmpty then throw "zone condition needs a zone"
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

def stateMatch (j : Json) (pos neg : String) : StateMatch :=
  match field? j pos with
  | some .null | none =>
    match field? j neg with
    | some .null | none => {}
    | some v => { values := some (ensureList v), invert := true }
  | some v => { values := some (ensureList v) }

/-- Template names a `limited` template may not use (`limited_ok=False`), and
date functions whose result depends on the time zone, which is not known at
load time. -/
def LIMITED_UNSUPPORTED : List String :=
  ["states", "is_state", "state_attr", "is_state_attr", "has_value", "expand",
   "now", "utcnow", "today_at", "relative_time", "time_since", "time_until", "timedelta_string",
   "as_local", "as_datetime", "as_timestamp", "timestamp_local", "timestamp_custom", "strptime"]

/-- `tvals`: the static trigger_variables, when the trigger attaches with
them (an automation's triggers, not `wait_for_trigger`). -/
def decodeTrigger (idx : Nat) (j : Json) (tnm : List String := [])
    (tvals : Option (List (String × Json)) := none) : D (Option Trigger) := do
  if !(← isEnabled j) then return none
  let platform := (str? j "trigger").orElse (fun _ => str? j "platform") |>.getD ""
  let id := (str? j "id").getD (toString idx)
  noTemplate j "variables"
  let kind ← match platform with
    | "state" =>
      let ids ← entityIds j
      let keys := ["from", "not_from", "to", "not_to"]
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
      let pat (k : String) (mx : Nat) : D (Option Pattern) :=
        match field? j k with
        | none => pure none
        | some (.str "*") => pure (some .any)
        | some (.str s) =>
          if s.startsWith "/" then
            match (s.dropS 1).toNat? with
            | some n => if n == 0 || n > mx then throw s!"bad {k}" else pure (some (.every n))
            | none => throw s!"bad {k}"
          else match s.toNat? with
            | some n => if n > mx then throw s!"bad {k}" else pure (some (.exact n))
            | none => throw s!"bad {k}"
        | some (.num n) => match n.mantissa.toNat with
          | m => if n.exponent == 0 && m ≤ mx then pure (some (.exact m)) else throw s!"bad {k}"
        | some _ => throw s!"bad {k}"
      let h ← pat "hours" 23
      let m ← pat "minutes" 59
      let s ← pat "seconds" 59
      if h.isNone && m.isNone && s.isNone then throw "time_pattern needs a field"
      -- "If larger units are specified, default the smaller units to zero"
      let m := if m.isNone && h.isSome then some (.exact 0) else m
      let s := if s.isNone && m.isSome then some (.exact 0) else s
      pure <| TriggerKind.timePattern (h.getD .any) (m.getD .any) (s.getD .any)
    | "event" => do
      let types ← strList ((field? j "event_type").getD .null)
      let data ← match field? j "event_data" with
        | none => pure []
        | some (.obj kvs) =>
          let kvs := kvs.toList
          if kvs.any (fun (_, v) => match v with | .obj _ => true | _ => false) then
            throw "nested event_data is not supported"
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
    | p => throw s!"trigger platform '{p}' is not supported"
  return some { id, idx, alias := str? j "alias", kind }

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
  if let some svc := (str? j "action").orElse (fun _ => str? j "service") then
    if Template.isTemplateString svc then throw s!"templated action names are not supported: {svc}"
    match svc.splitOn "." with
    | [d, s] =>
      noTemplate j "data_template"
      let data ← match field? j "data" with
        | none => pure (Json.mkObj [])
        | some d@(.obj _) => pure d
        | some _ => throw "service data must be a mapping (a whole-data template is not supported)"
      let target ← match field? j "target" with
        | none => pure (Json.mkObj [])
        | some t@(.obj _) => pure t
        | some _ => throw "target must be a mapping (a whole-target template is not supported)"
      return wrap (.service d s (← decodeComplex data nm) (← decodeComplex target nm) (← responseVariable? j))
    | _ => throw s!"bad service name {svc}"
  if has j "delay" then
    match ← forPeriod? j "delay" nm with
    | some (.tmpl c) => return wrap (.delayT c)
    | some (.fixed ms) => return wrap (.delay ms)
    | none => throw "delay needs a period"
  if has j "condition" then return wrap (.condition (← decodeCondition j nm))
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
      match c with
      | .num n => return wrap (.repeatCount n.mantissa.toNat body)
      | .str s =>
        if Template.isTemplateString s then return wrap (.repeatCountT (← compileTemplate s nm) body)
        match s.toNat? with
        | some n => return wrap (.repeatCount n body)
        | none => throw s!"invalid repeat count {s}"
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
    noTemplate j "event_data_template"
    let data ← match field? j "event_data" with
      | none => pure (Json.mkObj [])
      | some d@(.obj _) => pure d
      | some _ => throw "event_data must be a mapping"
    return wrap (.event e (← decodeComplex data nm))
  if has j "sequence" then return wrap (.sequence (← seq "sequence"))
  if let some ps := field? j "parallel" then
    -- each item is a `sequence:` mapping (`_SCRIPT_SEQUENCE_SCHEMA`) or a
    -- single action (`_parallel_sequence_action`); a disabled branch is
    -- skipped (`_async_run_script` with `enabled: false`)
    let branches ← (ensureList ps).mapM fun b => do
      if has b "sequence" && !(has b "action" || has b "service") then
        if !(← isEnabled b) then return []
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

/-- `util.slugify` (python-slugify's legacy pipeline with separator `_`,
then `""` becomes `"unknown"`), for ASCII text. `none` where the result
would depend on transliteration (non-ASCII) or on HTML entity decoding
(`&...;`), which HALean does not model. -/
def slugify? (text : String) : Option String := do
  if text.isEmpty then return ""
  if !text.toList.all (fun c : Char => c.toNat < 128) then none
  if text.contains '&' && text.contains ';' then none
  -- QUOTE_PATTERN → '-', then lower()
  let arr := (text.toList.map fun c => if c == '\'' then '-' else c.toLower).toArray
  -- NUMBERS_PATTERN `(?<=\d),(?=\d)` → ''
  let cs := (List.range arr.size).filterMap fun i =>
    let c := arr[i]!
    if c == ',' && i > 0 && i + 1 < arr.size && arr[i-1]!.isDigit && arr[i+1]!.isDigit then none
    else some c
  -- DISALLOWED_CHARS_PATTERN `[^-a-zA-Z0-9]+` → '-', DUPLICATE_DASH_PATTERN, strip('-')
  let cs := cs.map fun c => if c == '-' || c.isDigit || (c ≥ 'a' && c ≤ 'z') then c else '-'
  let collapsed := cs.foldl (fun acc c => if c == '-' && acc.head? == some '-' then acc else c :: acc) []
  let slug := String.ofList (collapsed.reverse.dropWhile (· == '-') |>.reverse.dropWhile (· == '-') |>.reverse)
  let slug := slug.replace "-" "_"
  return if slug.isEmpty then "unknown" else slug

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
  -- trigger_variables are rendered `limited` when triggers attach; HALean
  -- supports static values only
  for (k, v) in tvars do
    if (← decodeComplex v []).hasTemplate' then
      throw s!"templated trigger_variables ({k}) are not supported"
  let vars ← mapping "variables"
  -- `ScriptVariables(trigger_variables).variables.update(variables)`
  let merged := vars.foldl (fun acc (k, v) =>
    if acc.any (·.1 == k) then acc.map fun (k', v') => if k' == k then (k, v) else (k', v')
    else acc ++ [(k, v)]) tvars
  let pick (a b : String) := (field? j a).orElse (fun _ => field? j b) |>.getD .null
  -- the names templates may use: `trigger`, `repeat`, `this` (when the
  -- automation's entity id is known), and every variable the automation
  -- defines (anywhere, including `variables` actions)
  let nm := TEMPLATE_VARS ++ ["repeat", "wait"] ++ (if entityId.isSome then ["this"] else [])
    ++ merged.map (·.1) ++ actionVariableNames (pick "actions" "action")
  let mvars ← merged.mapM fun (k, v) => do pure (k, ← decodeComplex v nm)
  let tnm := tvars.map (·.1)
  let trigs ← ((ensureList (pick "triggers" "trigger")).zipIdx).mapM fun (t, i) => decodeTrigger i t tnm (some tvars)
  let conds ← (ensureList (pick "conditions" "condition")).mapM (decodeCondition · nm)
  let acts ← (ensureList (pick "actions" "action")).mapM (decodeAction · nm)
  let mode ← match str? j "mode" with
    | none | some "single" => pure Mode.single
    | some "restart" => pure .restart
    | some "queued" => pure .queued
    | some "parallel" => pure .parallel
    | some m => throw s!"unknown mode {m}"
  let maxRuns := match field? j "max" with
    | some (.num n) => n.mantissa.toNat
    | _ => 10
  return { id, alias, triggers := trigs.filterMap (fun x => x), conditions := conds,
           actions := acts.filterMap (fun x => x), mode, maxRuns,
           variables := mvars, triggerVars := tvars, entityId, uniqueId := str? j "id" }

end HALean.Automation
