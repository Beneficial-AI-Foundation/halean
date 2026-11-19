/-
  Automation configuration AST and its JSON decoder.

  The I/O shell loads `automations.yaml` (or asks HA for it) and sends it to the
  engine as JSON. Decoding normalises HA's many shorthands into one AST, the way
  `config_validation` + the platform schemas do upstream. Anything outside the
  supported subset is rejected with a message, never silently approximated.
-/
import HALean.Core.Types
import HALean.Template
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
      (attr : Option String)
  | time (before after : Option TimeBound) (weekday : Option (List String))
  | trigger (ids : List String)
  /-- `condition: template` and the string shorthand. -/
  | template (t : Template.Tmpl)
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

inductive TriggerKind where
  /-- `matchAll` is true iff none of from/not_from/to/not_to was *present*
  in the config (`to: ~` is present-but-null and so is not match-all). -/
  | state (entityIds : List String) (fromM toM : StateMatch) (matchAll : Bool)
      (attr : Option String) (forMs : Option Nat)
      (fromKeyOnly : Bool)  -- `from` present and `to` absent (for `_check_same_state`)
  | numericState (entityIds : List String) (below above : Option Bound)
      (attr : Option String) (forMs : Option Nat)
  /-- Fixed local times of day, in whole seconds. -/
  | time (ats : List Nat) (weekday : Option (List String))
  | timePattern (hours minutes seconds : Pattern)
  /-- Flat `event_data` only: every pair must be present and equal. -/
  | event (eventTypes : List String) (data : List (String × Json))
  deriving Repr, Inhabited

structure Trigger where
  id : String
  idx : Nat
  alias : Option String := none
  kind : TriggerKind
  deriving Repr, Inhabited

inductive Action where
  | service (domain service : String) (data target : Complex)
  | delay (ms : Nat)
  | condition (c : Condition)
  | choose (options : List (List Condition × List Action)) (default : Option (List Action))
  | ifThen (conds : List Condition) (thenA : List Action) (elseA : Option (List Action))
  | repeatCount (n : Nat) (body : List Action)
  | repeatWhile (conds : List Condition) (body : List Action)
  | repeatUntil (conds : List Condition) (body : List Action)
  | stop (reason : String) (error : Bool)
  | event (eventType : String) (data : Complex)
  | sequence (body : List Action)
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
    if s.contains '{' then throw s!"templated durations are not supported: {s}" else
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

/-- "HH:MM[:SS]" → seconds since midnight. -/
def timeOfDaySec (s : String) : Option Nat :=
  match (s.splitOn ":").map String.toNat? with
  | [some h, some m] => if h < 24 && m < 60 then some (h * 3600 + m * 60) else none
  | [some h, some m, some sec] =>
      if h < 24 && m < 60 && sec < 60 then some (h * 3600 + m * 60 + sec) else none
  | _ => none

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
  | some s => match timeOfDaySec s with
    | some sec => pure (some (.fixed (sec * 1000000)))
    | none => if s.contains '.' then pure (some (.entity s))
              else throw s!"invalid {k}: {s}"

def weekday? (j : Json) : D (Option (List String)) :=
  match field? j "weekday" with
  | none => pure none
  | some v => some <$> strList v

/-- The variables HALean passes to templates. Templates using anything else
(`this`, `now()`, ...) are rejected at load time. -/
def TEMPLATE_VARS : List String := ["trigger"]

def compileTemplate (s : String) : D Template.Tmpl := do
  let t ← match Template.compile s with
    | .ok t => pure t
    | .error e => throw s!"invalid template ({e}): {s}"
  match Template.check t TEMPLATE_VARS with
  | .ok () => pure t
  | .error e => throw e

/-- `cv.template_complex` -/
partial def decodeComplex (j : Json) : D Complex := do
  match j with
  | .str s => if Template.isTemplateString s then return .tmpl (← compileTemplate s) else return .lit j
  | .arr xs => return .arr (← xs.toList.mapM decodeComplex)
  | .obj kvs => return .obj (← kvs.toList.mapM fun (k, v) => do pure (← decodeComplex (.str k), ← decodeComplex v))
  | _ => return .lit j

def noTemplate (j : Json) (k : String) : D Unit :=
  if has j k then throw s!"'{k}' (templates) is not supported" else pure ()

partial def decodeCondition (j : Json) : D Condition := do
  if !(← isEnabled j) then return .disabled
  -- shorthand `- and: [...]`, `- or: [...]`, `- not: [...]`
  for k in ["and", "or", "not"] do
    if !has j "condition" then
      if let some cs := field? j k then
        let cs ← (ensureList cs).mapM decodeCondition
        return match k with | "and" => .and cs | "or" => .or cs | _ => .not cs
  match j with
  | .str s =>
    -- `dynamic_template_condition`: the shorthand must be a real template
    if !Template.isTemplateString s then throw s!"invalid condition: {s}"
    return .template (← compileTemplate s)
  | _ => pure ()
  let some kind := str? j "condition" | throw s!"condition without 'condition' key: {j.compress}"
  let sub : D (List Condition) :=
    (ensureList ((field? j "conditions").getD .null)).mapM decodeCondition
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
    noTemplate j "value_template"
    return .numericState (← entityIds j) (← bound? j "below") (← bound? j "above")
      (str? j "attribute")
  | "time" => return .time (← timeBound? j "before") (← timeBound? j "after") (← weekday? j)
  | "trigger" => return .trigger (← strList ((field? j "id").getD .null))
  | "template" =>
    match field? j "value_template" with
    | some (.str s) => return .template (← compileTemplate s)
    | _ => throw "template condition needs a value_template string"
  | other => throw s!"condition '{other}' is not supported"

def stateMatch (j : Json) (pos neg : String) : StateMatch :=
  match field? j pos with
  | some .null | none =>
    match field? j neg with
    | some .null | none => {}
    | some v => { values := some (ensureList v), invert := true }
  | some v => { values := some (ensureList v) }

def decodeTrigger (idx : Nat) (j : Json) : D (Option Trigger) := do
  if !(← isEnabled j) then return none
  let platform := (str? j "trigger").orElse (fun _ => str? j "platform") |>.getD ""
  let id := (str? j "id").getD (toString idx)
  noTemplate j "variables"
  let kind ← match platform with
    | "state" =>
      let ids ← entityIds j
      let keys := ["from", "not_from", "to", "not_to"]
      pure <| TriggerKind.state ids (stateMatch j "from" "not_from") (stateMatch j "to" "not_to")
        (keys.all fun k => !has j k) (str? j "attribute") (← optDuration j "for")
        (has j "from" && !has j "to")
    | "numeric_state" => do
      noTemplate j "value_template"
      let below ← bound? j "below"
      let above ← bound? j "above"
      if below.isNone && above.isNone then throw "numeric_state needs below or above"
      pure <| TriggerKind.numericState (← entityIds j) below above (str? j "attribute")
        (← optDuration j "for")
    | "time" => do
      let ats ← (ensureList ((field? j "at").getD .null)).mapM fun v => match v with
        | .str s => match timeOfDaySec s with
          | some sec => pure sec
          | none => throw s!"time trigger 'at: {s}' (entities/offsets) is not supported"
        | _ => throw s!"unsupported time trigger 'at': {v.compress}"
      pure <| TriggerKind.time ats (← weekday? j)
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
    | p => throw s!"trigger platform '{p}' is not supported"
  return some { id, idx, alias := str? j "alias", kind }

partial def decodeAction (j : Json) : D (Option Action) := do
  if !(← isEnabled j) then return none
  let coe := match field? j "continue_on_error" with | some (.bool true) => true | _ => false
  let wrap (a : Action) : Option Action := some (if coe then .continueOnError a else a)
  let seq (k : String) : D (List Action) := do
    let xs ← (ensureList ((field? j k).getD .null)).mapM decodeAction
    pure (xs.filterMap (fun x => x))
  let seqOf (v : Json) : D (List Action) := do
    let xs ← (ensureList v).mapM decodeAction
    pure (xs.filterMap (fun x => x))
  let conds (v : Json) : D (List Condition) := (ensureList v).mapM decodeCondition
  if let some svc := (str? j "action").orElse (fun _ => str? j "service") then
    if Template.isTemplateString svc then throw s!"templated action names are not supported: {svc}"
    match svc.splitOn "." with
    | [d, s] =>
      noTemplate j "data_template"
      noTemplate j "response_variable"
      let data ← match field? j "data" with
        | none => pure (Json.mkObj [])
        | some d@(.obj _) => pure d
        | some _ => throw "service data must be a mapping (a whole-data template is not supported)"
      let target ← match field? j "target" with
        | none => pure (Json.mkObj [])
        | some t@(.obj _) => pure t
        | some _ => throw "target must be a mapping (a whole-target template is not supported)"
      return wrap (.service d s (← decodeComplex data) (← decodeComplex target))
    | _ => throw s!"bad service name {svc}"
  if let some d := field? j "delay" then return wrap (.delay (← durationMs d))
  if has j "condition" then return wrap (.condition (← decodeCondition j))
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
      | _ => throw "templated repeat count is not supported"
    if let some c := field? r "while" then return wrap (.repeatWhile (← conds c) body)
    if let some c := field? r "until" then return wrap (.repeatUntil (← conds c) body)
    throw "repeat for_each is not supported"
  if let some s := str? j "stop" then
    noTemplate j "response_variable"
    let err := match field? j "error" with | some (.bool true) => true | _ => false
    return wrap (.stop s err)
  if let some e := str? j "event" then
    noTemplate j "event_data_template"
    let data ← match field? j "event_data" with
      | none => pure (Json.mkObj [])
      | some d@(.obj _) => pure d
      | some _ => throw "event_data must be a mapping"
    return wrap (.event e (← decodeComplex data))
  if has j "sequence" then return wrap (.sequence (← seq "sequence"))
  throw s!"action not supported: {j.compress}"

def decodeAutomation (j : Json) : D Automation := do
  let id := (str? j "id").getD ""
  let alias := (str? j "alias").getD id
  noTemplate j "variables"
  noTemplate j "trigger_variables"
  let pick (a b : String) := (field? j a).orElse (fun _ => field? j b) |>.getD .null
  let trigs ← ((ensureList (pick "triggers" "trigger")).zipIdx).mapM fun (t, i) => decodeTrigger i t
  let conds ← (ensureList (pick "conditions" "condition")).mapM decodeCondition
  let acts ← (ensureList (pick "actions" "action")).mapM decodeAction
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
           actions := acts.filterMap (fun x => x), mode, maxRuns }

end HALean.Automation
