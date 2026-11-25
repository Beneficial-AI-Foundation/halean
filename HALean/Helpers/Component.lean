/-
  The helper integrations joined: what `async_setup` of each domain sets up
  (an `EntityComponent` of YAML entities and its entity services), how a
  service call reaches the entities (`ServiceRegistry.async_call` →
  `entity_service_call`), the state machine's view of the entities (which
  writes fire `state_changed`), and the timers' scheduled callbacks.

  Why a separate model rather than services of the joined core
  (`HALean/Core/Hass.lean`): the core's handlers are scripts over the core
  (fire, set, call, ...), chosen to test the core's ordering, and none of them
  holds the state of an entity object. A helper's handler is a method of an
  entity object whose fields (`_attr_is_on`, `_remaining`, ...) are not in
  the state machine. So, like the script component (`HALean/Script/`), the
  helpers are their own pure model with the same shape: an explicit state
  (`Helpers`), one step per input with the clock as an argument, and the
  effects on the outside world as data (`Effect`: state writes, events,
  logs). Connecting it to the automation engine is a matter of routing the
  engine's `input_*`/`counter`/`timer` calls here and feeding the writes and
  events back (see the README).
-/
import HALean.Helpers.InputBoolean
import HALean.Helpers.InputNumber
import HALean.Helpers.InputSelect
import HALean.Helpers.InputText
import HALean.Helpers.Counter
import HALean.Helpers.Timer

namespace HALean.Helpers
open HALean.Core HALean.Template

/-- One helper entity. -/
inductive Ent where
  | inputBoolean (e : InputBoolean.Entity)
  | inputNumber (e : InputNumber.Entity)
  | inputSelect (e : InputSelect.Entity)
  | inputText (e : InputText.Entity)
  | counter (e : Counter.Entity)
  | timer (e : Timer.Entity)
  deriving Inhabited

def Ent.domain : Ent → String
  | .inputBoolean _ => InputBoolean.DOMAIN | .inputNumber _ => InputNumber.DOMAIN
  | .inputSelect _ => InputSelect.DOMAIN | .inputText _ => InputText.DOMAIN
  | .counter _ => Counter.DOMAIN | .timer _ => Timer.DOMAIN

def Ent.entityId : Ent → String
  | .inputBoolean e => e.entityId | .inputNumber e => e.entityId
  | .inputSelect e => e.entityId | .inputText e => e.entityId
  | .counter e => e.entityId | .timer e => e.entityId

/-- The domains modelled. -/
def DOMAINS : List String :=
  [InputBoolean.DOMAIN, InputNumber.DOMAIN, InputSelect.DOMAIN, InputText.DOMAIN,
   Counter.DOMAIN, Timer.DOMAIN]

/-- The entity services each domain registers, with their schemas. -/
def servicesOf : String → List (String × List Field)
  | "input_boolean" => InputBoolean.services
  | "input_number" => InputNumber.services
  | "input_select" => InputSelect.services
  | "input_text" => InputText.services
  | "counter" => Counter.services
  | "timer" => Timer.services
  | _ => []

/-- What the state machine holds for an entity: state and attributes. -/
abbrev Written := String × Attrs

/-- The joined helpers. -/
structure Helpers where
  /-- every entity, in the order it was added -/
  entities : List Ent := []
  /-- the domains set up (`async_setup_component` succeeded) -/
  loaded : List String := []
  /-- the state machine's view of the helper entities -/
  states : List (String × Written) := []
  deriving Inhabited

/-- What an operation does that can be observed, in order. -/
inductive Out where
  /-- the state machine fired `state_changed` for this write -/
  | stateChanged (entityId : String) (state : String) (attrs : Attrs)
  /-- an event a helper fired -/
  | event (eventType : String) (data : Attrs)
  | log (level message : String)
  deriving Inhabited

/-- `attributes == old_state.attributes`. Python compares dict values with
`is` first: a helper writes the very same float objects from its config each
time, so a NaN bound equals itself there. Equal `repr`s stand for that. -/
def attrsEq (a b : Attrs) : Bool :=
  pyEq (dictOf a) (dictOf b) || (pyRepr (dictOf a)).toOption == (pyRepr (dictOf b)).toOption

/-- `StateMachine.async_set_internal`: a write fires `state_changed` unless
state and attributes are unchanged and it is not forced. -/
def applyEffects (h : Helpers) (es : List Effect) : Helpers × List Out :=
  es.foldl (fun (h, outs) e =>
    match e with
    | .write eid st attrs force =>
      let same := match h.states.lookup eid with
        | some (st', attrs') => st' == st && attrsEq attrs' attrs
        | none => false
      let states := if h.states.any (·.1 == eid)
        then h.states.map fun p => if p.1 == eid then (eid, (st, attrs)) else p
        else h.states ++ [(eid, (st, attrs))]
      ({ h with states }, if same && !force then outs else outs ++ [.stateChanged eid st attrs])
    | .fire t d => (h, outs ++ [.event t d])
    | .log l m => (h, outs ++ [.log l m])) (h, [])

/-- Run a handler on one entity (a sub-state of `Ent`). -/
def runOn {σ} (wrap : σ → Ent) (m : HM σ Unit) (x : σ) : Ent × List Effect × Option PyErr :=
  let (x', es, err) := m.exec x
  (wrap x', es, err)

/-- The initial write of an entity being added; `none` when computing its
state raises (the entity is then not added). -/
def initialWrite (e : Ent) : Except PyErr Effect :=
  match e with
  | .inputBoolean x => .ok (.write x.entityId x.state x.attrs false)
  | .inputNumber x => .ok (.write x.entityId x.state x.attrs false)
  | .inputSelect x => .ok (.write x.entityId x.state x.attrs false)
  | .inputText x => x.state.map fun s => .write x.entityId s x.attrs false
  | .counter x => .ok (.write x.entityId x.state x.attrs false)
  | .timer x => .ok (.write x.entityId x.state.str x.attrs true)

/-- The result of setting up a domain. -/
inductive SetupResult where
  | ok (h : Helpers) (outs : List Out)
  /-- `CONFIG_SCHEMA` failed: `async_setup_component` returns False -/
  | invalid (message : String)
  | unsupported (why : String)
  deriving Inhabited

/-- `async_setup_component(hass, domain, {domain: cfg})` for a helper
domain: validate the config, create the entities in config order (each
restored from `restored`, the restore cache: entity id, state, attributes)
and add them, writing their states. An entity whose
`async_added_to_hass` or first write raises is not added (upstream logs the
error and goes on). -/
def Helpers.setup (h : Helpers) (domain : String) (cfg : Value)
    (restored : List (String × Written)) : SetupResult := Id.run do
  if !DOMAINS.contains domain then return .unsupported s!"{domain} is not a modelled helper"
  if h.loaded.contains domain then return .unsupported s!"{domain} is already set up"
  let last (eid : String) : Option String := (restored.lookup eid).map (·.1)
  let made : Except ConfigError (List (Except String Ent) × List Effect) :=
    match domain with
    | "input_boolean" => (InputBoolean.decodeConfig cfg).map fun cs =>
      (cs.map fun c => .ok (.inputBoolean (InputBoolean.Entity.create c (last s!"input_boolean.{c.id}"))), [])
    | "input_number" => (InputNumber.decodeConfig cfg).map fun cs =>
      (cs.map fun c => .ok (.inputNumber (InputNumber.Entity.create c (last s!"input_number.{c.id}"))), [])
    | "input_select" => (InputSelect.decodeConfig cfg).map fun cs =>
      (cs.map fun (c, _) => .ok (.inputSelect (InputSelect.Entity.create c (last s!"input_select.{c.id}"))),
       cs.filterMap fun (_, w) => w.map (.log "warning"))
    | "input_text" => (InputText.decodeConfig cfg).map fun cs =>
      (cs.map fun c => .ok (.inputText (InputText.Entity.create c (last s!"input_text.{c.id}"))), [])
    | "counter" => (Counter.decodeConfig cfg).map fun cs =>
      (cs.map fun c => match Counter.Entity.create c (last s!"counter.{c.id}") with
        | some e => .ok (.counter e)
        | none => .error s!"counter.{c.id}: the last state is not an integer (int() raises ValueError)", [])
    | _ => (Timer.decodeConfig cfg).map fun cs =>
      (cs.map fun c => match Timer.Entity.create c (restored.lookup s!"timer.{c.id}") with
        | some e => .ok (.timer e)
        | none => .error s!"timer.{c.id}: restoring a paused or active timer is not supported", [])
  match made with
  | .error (.invalid m) => return .invalid m
  | .error (.unsupported why) => return .unsupported why
  | .ok (ents, warnings) =>
    let mut h := { h with loaded := h.loaded ++ [domain] }
    let (h1, outs1) := applyEffects h warnings
    h := h1
    let mut outs := outs1
    for r in ents do
      match r with
      | .error why => return .unsupported why
      | .ok e =>
        match initialWrite e with
        | .ok w =>
          let (h2, o) := applyEffects { h with entities := h.entities ++ [e] } [w]
          h := h2
          outs := outs ++ o
        | .error err =>
          outs := outs ++ [.log "error" s!"Error adding entity {e.entityId} for domain {domain} with platform {domain}: {err.exception}: {err.message}"]
    return .ok h outs

/-- What a service call does. -/
inductive CallResult where
  | ok (h : Helpers) (outs : List Out) (error : Option PyErr)
  | unsupported (why : String)
  deriving Inhabited

/-- Run the service on the entity at index `i`. -/
def runService (domain service : String) (args : List (String × Value)) (now : Int) (e : Ent) :
    Ent × List Effect × Option PyErr :=
  match e with
  | .inputBoolean x => runOn .inputBoolean (InputBoolean.handle service args) x
  | .inputNumber x => runOn .inputNumber (InputNumber.handle service args) x
  | .inputSelect x => runOn .inputSelect (InputSelect.handle service args) x
  | .inputText x => runOn .inputText (InputText.handle service args) x
  | .counter x => runOn .counter (Counter.handle service args) x
  | .timer x => let _ := domain; runOn .timer (Timer.handle service args now) x

/-- The timers' scheduled callbacks that are due at `now`, in entity order
(`_async_finished`). -/
def Helpers.tick (h : Helpers) (now : Int) : Helpers × List Out := Id.run do
  let mut h := h
  let mut outs : List Out := []
  for i in List.range h.entities.length do
    match h.entities[i]? with
    | some (.timer t) =>
      if t.due now then
        let (t', es, _) := Timer.finished.exec t
        let (h', o) := applyEffects { h with entities := h.entities.set i (.timer t') } es
        h := h'
        outs := outs ++ o
    | _ => pure ()
  return (h, outs)

/-- What HALean cannot run exactly for this call (checked before it runs). -/
def unsupportedArgs (h : Helpers) (domain service : String) (args : List (String × Value))
    (targets : List Nat) : Option String :=
  if domain == "input_text" && service == "set_value" then
    let v := (lkStr args "value").getD ""
    if v.toList.all (·.toNat < 128) then none
    else targets.findSome? fun i => match (h.entities[i]? : Option Ent) with
      | some (.inputText x) => match x.cfg.pattern with
        | some (p, _) => if Pattern.usesClassEscape p
            then some "matching non-ASCII text against \\d, \\w or \\s is not modelled" else none
        | none => none
      | _ => none
  else none

/-- `hass.services.async_call(domain, service, data, blocking=True)` for a
helper service: look the service up (`ServiceNotFound`), validate the data
with the entity service schema (`probatio.Invalid`), resolve the targets
(the domain's entities, see `selectTargets`), run the method on each one (all
of them run, as `asyncio.gather(return_exceptions=True)`; the first error is
raised), then let the event loop run the timers' callbacks that are now due. -/
def Helpers.call (h : Helpers) (domain service : String) (data : List (String × Value))
    (now : Int) : CallResult := Id.run do
  let domainL := domain.toLower
  let serviceL := service.toLower
  if !h.loaded.contains domainL then
    return .ok h [] (some (serviceNotFound domainL serviceL))
  if serviceL == "reload" && domainL != Counter.DOMAIN then
    return .unsupported s!"{domainL}.reload re-reads configuration.yaml, which HALean does not model"
  let some (_, fields) := (servicesOf domainL).find? (·.1 == serviceL)
    | return .ok h [] (some (serviceNotFound domainL serviceL))
  match validateEntityCall fields data with
  | .error (.invalid errs) =>
    return .ok h [] (some { exception := "MultipleInvalid", message := multipleInvalidStr errs })
  | .error (.raise exc msg) => return .ok h [] (some { exception := exc, message := msg })
  | .error (.unsupported why) => return .unsupported why
  | .ok validated =>
    match targetOf validated with
    | .error why => return .unsupported why
    | .ok target =>
      let ids := h.entities.map fun e => if e.domain == domainL then e.entityId else ""
      let targets := selectTargets ids target
      let args := serviceArgs validated
      if let some why := unsupportedArgs h domainL serviceL args targets then return .unsupported why
      let mut h := h
      let mut outs : List Out := []
      let mut firstErr : Option PyErr := none
      for i in targets do
        let some e := h.entities[i]? | continue
        let (e', es, err) := runService domainL serviceL args now e
        let (h', o) := applyEffects { h with entities := h.entities.set i e' } es
        h := h'
        outs := outs ++ o
        if firstErr.isNone then firstErr := err
      let (h', o) := h.tick now
      return .ok h' (outs ++ o) firstErr

end HALean.Helpers
