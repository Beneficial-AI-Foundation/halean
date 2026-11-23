/-
  The joined core: `homeassistant.core.HomeAssistant` as far as its three core
  services go. `Hass` holds the state machine (`hass.states`), the event bus
  (`hass.bus`) and the service registry (`hass.services`), and every event the
  state machine and the registry fire goes through the bus model, as upstream
  `StateMachine` and `ServiceRegistry` call `hass.bus.async_fire_internal`.

  Listeners and service handlers are scripts over the whole core (`Action`):
  fire an event, listen / listen once / unsubscribe, raise, set or remove a
  state, call a service, register or remove a service. So a listener on
  `state_changed` can set another state, and a handler can set states, fire
  events and call other services, with HA's ordering:

  * every listener is a `@callback`; a dispatch runs them inline, and an
    event fired while one is running (by a listener, or by a service handler
    a listener called, or by a state that handler set) is queued and
    dispatched after the current one, in FIFO order
    (`EventBus.async_fire_internal`);
  * a handler is a coroutine function that never suspends, so a service call
    runs to completion where it is made: `await hass.services.async_call(...)`
    in a handler, and in a listener a task created with
    `hass.async_create_task(...)`, which starts eagerly and so also finishes
    before the listener goes on (its outcome is caught and recorded; the
    listener never sees an exception from it);
  * `call_service` is fired before the handler runs; a non-blocking call's
    handler errors are logged, a blocking call's propagate.

  Types reused from the separate models: the bus's `Bus`, `Job`, `Event`,
  `Queued`, `FireArgs`, `FilterSpec`, `CtxArg`; the state machine's
  `StateMachine`, `State`, `SMEvent`; the registry's `Registry`, `CallArgs`,
  `HandlerSpec`, `SchemaSpec`, `PyError`, `LogRecord`. One `Context`
  (`State.lean`) is used by all three. The bus's `Event` is the only
  `homeassistant.core.Event`: what the state machine (`SMEvent`) and the
  registry (`FiredEvent`) return are the `async_fire_internal` calls they
  make, which this module turns into bus `Queued` entries.

  A listener's script is kept beside the bus, by job key (`Hass.reacts`), and
  a handler's script beside the registry (`Hass.bodies`), so the bus and
  registry types stay those of the separate models.

  Everything is pure: the clock `now` (µs) is an argument; contexts HA would
  make with a random ULID get a symbolic id `ulid@<ms>#<n>` (`genContext`, and
  the bus's own `makeEvent`). Recursion is bounded by fuel and service calls
  nest at most `MAX_CALL_DEPTH` deep; running out of either is reported as
  `Entry.unsupported` (HA would raise `RecursionError` somewhere deeper), and
  the driver rejects the operation.
-/
import HALean.Core.EventBus
import HALean.Core.StateMachine
import HALean.Core.ServiceRegistry
open Lean HALean.Template

namespace HALean.Core.Hass
open HALean.Core HALean.Core.EventBus

/-! ## Scripts -/

/-- What a listener does on receipt, or a service handler does before it
returns (in order; an exception ends the script). -/
inductive Action
  /-- `hass.bus.async_fire(event_type, data, origin, context)` -/
  | fire (f : FireArgs)
  /-- `hass.bus.async_listen` / `async_listen_once` with a scripted listener;
  the remove callback is kept under `id` -/
  | listen (id eventType : String) (once : Bool) (filter : Option FilterSpec)
      (react : List Action) (reactTimes : Option Nat)
  /-- call the remove callback kept under `id` (`KeyError` if none) -/
  | unsub (id : String)
  /-- `raise <exception>(<message>)` -/
  | raise (exception message : String)
  /-- `hass.states.async_set(entity_id, state, attributes, force_update, context)` -/
  | set (entityId : String) (state : Json) (attributes : Option Json) (forceUpdate : Bool)
      (context : CtxArg)
  /-- `hass.states.async_remove(entity_id, context)` -/
  | remove (entityId : String) (context : CtxArg)
  /-- `hass.services.async_call(...)` (`args.context` is ignored; `context`
  says which). The outcome is recorded under `id`. In a handler, an error
  propagates unless `caught`; in a listener the call runs in a task and its
  error never reaches the listener. -/
  | call (id : String) (args : CallArgs) (context : CtxArg) (caught : Bool)
  /-- `hass.services.async_register(domain, service, handler, schema,
  supports_response)`: the handler runs `body`, then does what `result` says -/
  | register (domain service : String) (body : List Action) (result : HandlerSpec)
      (schema : Option SchemaSpec) (supportsResponse : SupportsResponse)
  /-- `hass.services.async_remove(domain, service)` -/
  | removeService (domain service : String)

/-- What an operation leaves behind, in order. -/
inductive Entry
  /-- a listener received an event (`Event.as_dict()`) -/
  | delivery (job : Nat) (listener : String) (event : Event)
  /-- a `homeassistant.core` log record (warning and above) -/
  | log (r : LogRecord)
  /-- the outcome of a script's service call -/
  | callResult (id : String) (res : Except PyError Value)
  /-- outside the model (fuel, call depth, a value it cannot represent) -/
  | unsupported (why : String)

abbrev Out := List Entry

def Entry.isDelivery : Entry → Bool
  | .delivery .. => true
  | _ => false

def Entry.isUnsupported : Entry → Bool
  | .unsupported _ => true
  | _ => false

/-! ## The core -/

structure Hass where
  states : StateMachine := {}
  bus : Bus := Bus.new
  services : Registry := []
  /-- each listener's script, by bus job key -/
  reacts : List (Nat × List Action) := []
  /-- each service's handler script, by lowercased `(domain, service)` -/
  bodies : List ((String × String) × List Action) := []

def Hass.new : Hass := {}

/-- Where a script runs: the clock, the context `inherit` means (the event's
in a listener, the `ServiceCall`'s in a handler), whether it is a listener,
and how deep service calls are nested. -/
structure Env where
  now : Nat
  ctx : Option Context := none
  inListener : Bool := false
  depth : Nat := 0

/-- Service calls nested deeper than this are not modelled (Python's
recursion limit is reached somewhere around there). -/
def MAX_CALL_DEPTH : Nat := 32

/-- Fuel for one operation. -/
def FUEL : Nat := 1000000

def Hass.scriptOf (h : Hass) (k : Nat) : List Action := (h.reacts.lookup k).getD []

def bodyLookup : List ((String × String) × List Action) → String × String → List Action
  | [], _ => []
  | (k, b) :: rest, key => if k == key then b else bodyLookup rest key

def bodyErase (bs : List ((String × String) × List Action)) (key : String × String) :
    List ((String × String) × List Action) :=
  bs.filter (·.1 != key)

/-- `Context(id=ulid_at_time(time.time()))`, `Context()`: a fresh symbolic id
(the bus's counter, so ids from the bus's `Event` and from here never
clash). -/
def Hass.genContext (h : Hass) (now : Nat) : Hass × Context :=
  ({ h with bus := { h.bus with genCount := h.bus.genCount + 1 } },
   { id := s!"ulid@{ulidMillis (timestampOf now)}#{h.bus.genCount}" })

/-- `context or Context()` -/
def Hass.ctxOr (h : Hass) (c : Option Context) (now : Nat) : Hass × Context :=
  match c with
  | some ctx => (h, ctx)
  | none => h.genContext now

def resolveCtx (env : Env) : CtxArg → Option Context
  | .none => none
  | .given c => some c
  | .inherit => env.ctx

/-- The exception a state machine error is (or `none`: not modelled). -/
def smError : SMError → Option PyError
  | .invalidEntityFormat m => some { exception := "InvalidEntityFormatError", message := m }
  | .invalidState m => some { exception := "InvalidStateError", message := m }
  | .homeAssistant m => some { exception := "HomeAssistantError", message := m }
  | .unsupported _ => none

/-- The exceptions of the bus's listen operations. -/
def busError : Err → PyError
  | e => { exception := e.name, message := "" }

/-- `async_fire_internal` while dispatching, once the queue is full. -/
def queueFull (eventType : String) : PyError :=
  { exception := "HomeAssistantError",
    message := s!"Event {eventType} not fired: more than {MAX_QUEUED_EVENT_DISPATCHES} events were queued by event listeners while dispatching a single event; event listeners are likely firing events in an endless loop" }

def exhausted : PyError := { exception := "RecursionError", message := "fuel" }

/-- What the state machine passes to `async_fire_internal`: its event data,
the context it passes (`ctx`), and `time_fired` (`timestamp` in
`async_set`; `None` in `async_remove`, i.e. `time.time()`: the same clock). -/
def smQueued (now : Nat) (e : SMEvent) (ctx : Option Context) : Queued :=
  { eventType := e.eventType, data := some e.dataJson, origin := .local, context := ctx,
    timeFired := timestampOf now }

def valuesJson (kvs : List (String × Value)) : Option Json :=
  match (dictOf kvs).toJson with
  | .ok j => some j
  | .error _ => none

/-- What the registry passes to `async_fire_internal` (`time_fired` is
`None`: `time.time()`). `none` when the data has no JSON form. -/
def firedQueued (now : Nat) (e : FiredEvent) : Option Queued :=
  (valuesJson e.data).map fun d =>
    { eventType := e.eventType, data := some d, origin := .local, context := e.context,
      timeFired := timestampOf now }

/-- `EventBus._async_remove_listener`, with what it logs. -/
def removeListener (h : Hass) (et : String) (k : Nat) : Hass × Out :=
  let b := asyncRemoveListener { h.bus with logs := [] } et k
  let out := b.logs.reverse.map fun _ => Entry.log
    { level := "error", message := "Unable to remove unknown job listener",
      exception := some "ValueError: list.remove(x): x not in list" }
  ({ h with bus := { b with logs := [] } }, out)

/-- `_OneTimeListener.__call__`: `self.remove()`, `self.remove = None`. -/
def useOnce (h : Hass) (job : Job) : Hass × Out :=
  let hr := removeListener h job.eventType job.key
  ({ hr.1 with bus := { hr.1.bus with onceRemoved := job.key :: hr.1.bus.onceRemoved } }, hr.2)

/-- The listener records the delivery; it runs its script up to
`reactTimes` receipts. -/
def recordDelivery (h : Hass) (job : Job) (ev : Event) : Hass × Out × Bool :=
  let n := h.bus.receivedOf job.key + 1
  ({ h with bus := { h.bus with received := (job.key, n) :: h.bus.received } },
   [.delivery job.key job.listener ev], job.reactTimes.all (n ≤ ·))

def filterLog (e : Err) : Entry :=
  .log { level := "error", message := "Error in event filter",
         exception := some s!"{e.name}: filter" }

/-- `_LOGGER.exception("Error running job: %s", job)` -/
def jobErrorLog : Option PyError → Out
  | some e => [.log { level := "error", message := "Error running job",
                      exception := some s!"{e.exception}: {e.message}" }]
  | none => []

def errOf : Except PyError Value → Option PyError
  | .error e => some e
  | .ok _ => none

/-! ## Running scripts, dispatching, calling services

One mutual block, structurally recursive on the fuel. -/

mutual

/-- `EventBus.async_fire_internal`. While dispatching, the event is queued (or
`HomeAssistantError` once 10,000 were queued in this dispatch); otherwise it
is dispatched, then everything queued meanwhile, in order. -/
def fireInternal : Nat → Nat → Hass → Queued → Hass × Out × Option PyError
  | 0, _, h, _ => (h, [.unsupported "fuel"], some exhausted)
  | n + 1, now, h, q =>
    if h.bus.dispatching then
      match fireNested h.bus q with
      | (b, none) => ({ h with bus := b }, [], none)
      | (b, some _) => ({ h with bus := b }, [], some (queueFull q.eventType))
    else
      let h1 := { h with bus := { h.bus with dispatching := true, queuedCount := 0 } }
      let r1 := dispatchLoop n now q h1 none (snapshot h1.bus.listeners q.eventType)
      let r2 := drain n now r1.1
      ({ r2.1 with bus := { r2.1.bus with dispatching := false } }, r1.2.1 ++ r2.2, none)

/-- Fire events one after the other; an exception stops at that event. -/
def fireList : Nat → Nat → Hass → List Queued → Hass × Out × Option PyError
  | 0, _, h, _ => (h, [.unsupported "fuel"], some exhausted)
  | _ + 1, _, h, [] => (h, [], none)
  | n + 1, now, h, q :: qs =>
    let r1 := fireInternal n now h q
    match r1.2.2 with
    | some e => (r1.1, r1.2.1, some e)
    | none =>
      let r2 := fireList n now r1.1 qs
      (r2.1, r1.2.1 ++ r2.2.1, r2.2.2)

/-- The `for job, event_filter in listeners + match_all_listeners` loop of
`EventBus._async_dispatch` (the `Event` is made on the first job that passes
its filter). -/
def dispatchLoop : Nat → Nat → Queued → Hass → Option Event → List Job → Hass × Out × Option Event
  | 0, _, _, h, ev?, _ => (h, [.unsupported "fuel"], ev?)
  | _ + 1, _, _, h, ev?, [] => (h, [], ev?)
  | n + 1, now, q, h, ev?, job :: js =>
    match filterPasses job q.data with
    | .error e =>
      let r := dispatchLoop n now q h ev? js
      (r.1, filterLog e :: r.2.1, r.2.2)
    | .ok false => dispatchLoop n now q h ev? js
    | .ok true =>
      let be := ensureEvent h.bus q ev?
      let r1 := runJob n now { h with bus := be.1 } job be.2
      let r2 := dispatchLoop n now q r1.1 (some be.2) js
      (r2.1, r1.2.1 ++ jobErrorLog r1.2.2 ++ r2.2.1, r2.2.2)

/-- `while event_queue: self._async_dispatch(*event_queue.popleft())` -/
def drain : Nat → Nat → Hass → Hass × Out
  | 0, _, h => (h, [.unsupported "fuel"])
  | n + 1, now, h =>
    match h.bus.queue with
    | [] => (h, [])
    | q :: qs =>
      let h1 := { h with bus := { h.bus with queue := qs } }
      let r1 := dispatchLoop n now q h1 none (snapshot h1.bus.listeners q.eventType)
      let r2 := drain n now r1.1
      (r2.1, r1.2.1 ++ r2.2)

/-- `async_run_hass_job` on a listener: a `_OneTimeListener` removes itself
first (and does nothing if it already ran); then the listener records the
event and runs its script. -/
def runJob : Nat → Nat → Hass → Job → Event → Hass × Out × Option PyError
  | 0, _, h, _, _ => (h, [.unsupported "fuel"], some exhausted)
  | n + 1, now, h, job, ev =>
    if job.system then (h, [], none)
    else if job.once then
      if h.bus.onceRemoved.contains job.key then (h, [], none)
      else
        let u := useOnce h job
        let d := recordDelivery u.1 job ev
        if d.2.2 then
          let r := runActions n { now, ctx := some ev.context, inListener := true } d.1 (d.1.scriptOf job.key)
          (r.1, u.2 ++ d.2.1 ++ r.2.1, r.2.2)
        else (d.1, u.2 ++ d.2.1, none)
    else
      let d := recordDelivery h job ev
      if d.2.2 then
        let r := runActions n { now, ctx := some ev.context, inListener := true } d.1 (d.1.scriptOf job.key)
        (r.1, d.2.1 ++ r.2.1, r.2.2)
      else (d.1, d.2.1, none)

/-- A script: the actions in order, stopping at the first exception. -/
def runActions : Nat → Env → Hass → List Action → Hass × Out × Option PyError
  | 0, _, h, _ => (h, [.unsupported "fuel"], some exhausted)
  | _ + 1, _, h, [] => (h, [], none)
  | n + 1, env, h, a :: as =>
    let r1 := runAction n env h a
    match errOf r1.2.2 with
    | some e => (r1.1, r1.2.1, some e)
    | none =>
      let r2 := runActions n env r1.1 as
      (r2.1, r1.2.1 ++ r2.2.1, r2.2.2)

/-- One action; the result is what the Python call returns, or the exception
it raises. -/
def runAction : Nat → Env → Hass → Action → Hass × Out × Except PyError Value
  | 0, _, h, _ => (h, [.unsupported "fuel"], .error exhausted)
  | n + 1, env, h, a =>
    match a with
    | .fire f =>
      let r := fireInternal n env.now h (mkQueued env.now f (resolveCtx env f.context))
      (r.1, r.2.1, match r.2.2 with | some e => .error e | none => .ok .none)
    | .listen id et once filter react rt =>
      match listenOp h.bus id et once filter none [] rt with
      | .ok b => ({ h with bus := b, reacts := (h.bus.nextKey, react) :: h.reacts }, [], .ok .none)
      | .error e => (h, [], .error (busError e))
    | .unsub id =>
      match h.bus.handles.lookup id with
      | none => (h, [], .error { exception := "KeyError", message := strRepr id })
      | some (et, k) =>
        let r := removeListener h et k
        (r.1, r.2, .ok .none)
    | .raise exc msg => (h, [], .error { exception := exc, message := msg })
    | .set eid st attrs force c =>
      -- `async_set`: `timestamp or time.time()`; `async_set_internal` makes
      -- `Context(id=ulid_at_time(timestamp))` when none is given
      let ts := timestampOf env.now
      let hc := h.ctxOr (resolveCtx env c) env.now
      match hc.1.states.asyncSet eid st attrs force (some hc.2) (utcMicrosOfTimestamp ts) with
      | .error e => match smError e with
        | some pe => (hc.1, [], .error pe)
        | none => (hc.1, [.unsupported "state machine"], .error exhausted)
      | .ok (sm, evs) =>
        let r := fireList n env.now { hc.1 with states := sm }
          (evs.map fun e => smQueued env.now e (some hc.2))
        (r.1, r.2.1, match r.2.2 with | some e => .error e | none => .ok .none)
    | .remove eid c =>
      let ctx := resolveCtx env c
      match h.states.asyncRemove eid ctx (utcMicrosOfTimestamp (timestampOf env.now)) with
      | .error e => match smError e with
        | some pe => (h, [], .error pe)
        | none => (h, [.unsupported "state machine"], .error exhausted)
      | .ok (removed, sm, evs) =>
        let r := fireList n env.now { h with states := sm } (evs.map fun e => smQueued env.now e ctx)
        (r.1, r.2.1, match r.2.2 with | some e => .error e | none => .ok (.bool removed))
    | .call id args c caught =>
      let r := callService n env h { args with context := resolveCtx env c }
      let out := r.2.1 ++ [.callResult id r.2.2]
      match r.2.2 with
      | .error e => if caught || env.inListener then (r.1, out, .ok .none) else (r.1, out, .error e)
      | .ok v => (r.1, out, .ok v)
    | .register d s body result schema sr =>
      let rr := h.services.register d s { handler := result, schema, supportsResponse := sr }
        (env.now / 1000)
      let key := (d.toLower, s.toLower)
      let h1 := { h with services := rr.1, bodies := (key, body) :: bodyErase h.bodies key }
      match rr.2.mapM (firedQueued env.now) with
      | none => (h1, [.unsupported "event data"], .error exhausted)
      | some qs =>
        let r := fireList n env.now h1 qs
        (r.1, r.2.1, match r.2.2 with | some e => .error e | none => .ok .none)
    | .removeService d s =>
      let rr := h.services.remove d s (env.now / 1000)
      let h1 := { h with services := rr.1,
                         bodies := if rr.2.1.isEmpty then h.bodies
                                   else bodyErase h.bodies (d.toLower, s.toLower) }
      match rr.2.1.mapM (firedQueued env.now) with
      | none => (h1, [.unsupported "event data"], .error exhausted)
      | some qs =>
        let r := fireList n env.now h1 qs
        (r.1, rr.2.2.map .log ++ r.2.1, match r.2.2 with | some e => .error e | none => .ok .none)

/-- `ServiceRegistry.async_call` with a scripted handler: `context or
Context()`, `prepareCall`, `call_service` through the bus, the handler's
script (with the call's context), then its result spec, then `finishCall`. -/
def callService : Nat → Env → Hass → CallArgs → Hass × Out × Except PyError Value
  | 0, _, h, _ => (h, [.unsupported "fuel"], .error exhausted)
  | n + 1, env, h, a =>
    if env.depth ≥ MAX_CALL_DEPTH then (h, [.unsupported "call depth"], .error exhausted)
    else
      let hc := h.ctxOr a.context env.now
      match hc.1.services.prepareCall a hc.2 with
      | .error e => (hc.1, [], .error e)
      | .ok p =>
        let body := bodyLookup hc.1.bodies (p.domain, p.service)
        match firedQueued env.now (p.event (env.now / 1000)) with
        | none => (hc.1, [.unsupported "event data"], .error exhausted)
        | some q =>
          let r1 := fireInternal n env.now hc.1 q
          match r1.2.2 with
          | some e => (r1.1, r1.2.1, .error e)
          | none =>
            let r2 := runActions n { now := env.now, ctx := some hc.2, inListener := false,
                                     depth := env.depth + 1 } r1.1 body
            let res := match r2.2.2 with
              | some e => .error e
              | none => runHandler p.svc.handler p.call
            let fin := finishCall a p.call res
            (r2.1, r1.2.1 ++ r2.2.1 ++ fin.2.map .log, fin.1)

end

/-! ## Operations (one per input line) -/

inductive Op
  /-- `set`, `remove`, `fire`, `listen`, `listen_once`, `unsub`, `register`,
  `remove_service`: the same calls a script makes -/
  | act (a : Action)
  /-- `await hass.services.async_call(...)` -/
  | call (a : CallArgs)
  /-- `hass.states.get(entity_id)` -/
  | get (entityId : String)
  /-- `hass.bus.async_listeners()` -/
  | listeners
  /-- `hass.services.has_service(domain, service)` -/
  | has (domain service : String)
  /-- the listeners HA already has (counts per event type, dict order) -/
  | init (counts : List (String × Nat))

inductive Result
  | value (v : Value)
  | state (s : Option State)
  | listeners (counts : List (String × Nat))
  | bool (b : Bool)

def step (now : Nat) (h : Hass) : Op → Hass × Out × Except PyError Result
  | .act a =>
    let r := runAction FUEL { now } h a
    (r.1, r.2.1, r.2.2.map .value)
  | .call a =>
    let r := callService FUEL { now } h a
    (r.1, r.2.1, r.2.2.map .value)
  | .get e => match h.states.get e with
    | .ok s => (h, [], .ok (.state s))
    | .error _ => (h, [.unsupported "entity id"], .error exhausted)
  | .listeners => (h, [], .ok (.listeners (asyncListeners h.bus)))
  | .has d s => (h, [], .ok (.bool (h.services.hasService d s)))
  | .init counts =>
    let (t, next) := initTable h.bus.nextKey counts
    ({ h with bus := { h.bus with listeners := t, nextKey := next, handles := [] } }, [], .ok (.value .none))

end HALean.Core.Hass
