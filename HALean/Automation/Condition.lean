/-
  Condition evaluation. Translated from
  `homeassistant/helpers/condition.py`.

  Python's three outcomes are kept exactly:
    * `ok (some b)`  – the checker returned `b`
    * `ok none`      – the checker returned `None` (only `DisabledConditionChecker`)
    * `err msg`      – the checker raised `ConditionError`
-/
import HALean.Automation.Config
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

/-- `conditions.async_numeric_state` (without `value_template`). Takes the
entity state directly so triggers can reuse it with `to_s`. -/
def numericStateOf (env : CondEnv) (ent : EntityState) (below above : Option Bound)
    (attr : Option String) : Except String Bool := do
  if let some a := attr then
    if !ent.hasAttr a then return false
  let value : Json := match attr with
    | none => .str ent.state
    | some a => (ent.attr? a).getD .null
  if value == .null || value == .str STATE_UNAVAILABLE || value == .str STATE_UNKNOWN then
    return false
  let some fv := pyFloat? value
    | throw s!"entity {ent.entityId} state '{value.compress}' cannot be processed as a number"
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
    (attr : Option String) : Except String Bool := do
  let some ent := env.states.get? eid | throw s!"unknown entity {eid}"
  numericStateOf env ent below above attr

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
  if e.domain == "time" then
    if isAfter && (e.state == STATE_UNAVAILABLE || e.state == STATE_UNKNOWN) then return none
    match timeOfDaySec e.state with
    | some s => return some (s * 1000000)
    | none =>
      -- `after`: strptime raises ValueError (uncaught upstream); `before`: returns False
      if isAfter then throw s!"invalid time state '{e.state}'" else return none
  match e.attr? "device_class" with
  | some (.str "timestamp") | some (.str "uptime") =>
    throw "time condition on timestamp sensors is not supported by HALean yet"
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

mutual
/-- `ConditionChecker.async_check` -/
def evalCond (env : CondEnv) : Condition → CondResult
  | .disabled => .ok none
  | .and cs => evalAnd env cs []
  | .or cs => evalOr env cs []
  | .not cs => evalNot env cs []
  | .state eids req forMs attr matchAny =>
      entityLoop eids (fun e => stateOne env e req forMs attr) matchAny
  | .numericState eids below above attr =>
      -- `if_numeric_state` is the matchAll loop
      entityLoop eids (fun e => numericStateOne env e below above attr) false
  | .time before after wd =>
      match timeCond env before after wd with
      | .ok b => .ok (some b)
      | .error e => .err e
  | .trigger ids =>
      .ok (some (match env.triggerId with
        | some t => ids.contains t
        | none => false))

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
