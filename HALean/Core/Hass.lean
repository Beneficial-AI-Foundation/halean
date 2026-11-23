/-
  The joined core: `homeassistant.core.HomeAssistant` as far as its three core
  services go, with the event loop's tasks. `Hass` holds the state machine
  (`hass.states`), the event bus (`hass.bus`), the service registry
  (`hass.services`) and the tasks of the event loop, and every event the state
  machine and the registry fire goes through the bus model, as upstream
  `StateMachine` and `ServiceRegistry` call `hass.bus.async_fire_internal`.

  Listeners and service handlers are scripts over the whole core (`Action`):
  fire an event, listen / listen once / unsubscribe, raise, set or remove a
  state, call a service, register or remove a service, and (in a coroutine)
  `await asyncio.sleep(0)` or `await` a future, or resolve a future. So a
  listener on `state_changed` can set another state, and a handler can set
  states, fire events and call other services, with HA's ordering:

  * a `@callback` listener runs inline in the dispatch; an event fired while
    one is running (by a listener, or by a service handler a listener called,
    or by a state that handler set) is queued and dispatched after the current
    one, in FIFO order (`EventBus.async_fire_internal`);
  * a coroutine-function listener (`async def`) is started by
    `async_run_hass_job` as an eager task (`create_eager_task`): its
    synchronous prefix runs inside the dispatch, up to its first real
    suspension; then the task is parked (`hass._tasks`) and the dispatch goes
    on. A task that finished with an exception is never awaited: CPython
    finalizes it when its last reference goes, and the loop's exception
    handler (`homeassistant/runner.py::_async_loop_exception_handler`) logs
    `Error doing job: Task exception was never retrieved`;
  * a handler is a coroutine function: a blocking `async_call` awaits it in
    the caller's task (a suspension suspends the caller), a non-blocking one
    runs it in an eager task (`_run_service_call_catch_exceptions`), and a
    service call in a `@callback` listener runs in an eager task
    (`hass.async_create_task`) whose outcome is recorded and never reaches
    the listener;
  * `call_service` is fired before the handler runs; a non-blocking call's
    handler errors are logged, a blocking call's propagate.

  The event loop is explicit (`Hass.ready`, `Hass.tasks`, `Hass.futures`): a
  FIFO of handles (`Task.__step`/`__wakeup`, the done callback
  `hass._tasks.remove`, `asyncio.wait`'s `_on_completion`), as
  `BaseEventLoop._run_once` runs `loop.call_soon` callbacks. The operation
  being run is the main task (id 0, the test's own task): when it awaits
  something that suspends (a blocking call whose handler suspends,
  `asyncio.sleep(0)`, `hass.async_block_till_done()`), the loop runs handles
  until the main task is woken and finishes (`runLoop`).

  Types reused from the separate models: the bus's `Bus`, `Job`, `Event`,
  `Queued`, `FireArgs`, `FilterSpec`, `CtxArg`; the state machine's
  `StateMachine`, `State`, `SMEvent`; the registry's `Registry`, `CallArgs`,
  `HandlerSpec`, `SchemaSpec`, `PyError`, `LogRecord`. One `Context`
  (`State.lean`) is used by all three. The bus's `Event` is the only
  `homeassistant.core.Event`: what the state machine (`SMEvent`) and the
  registry (`FiredEvent`) return are the `async_fire_internal` calls they
  make, which this module turns into bus `Queued` entries.

  A listener's script is kept beside the bus, by job key (`Hass.reacts`, and
  `Hass.asyncJobs` for coroutine functions), and a handler's script beside the
  registry (`Hass.bodies`), so the bus and registry types stay those of the
  separate models.

  Everything is pure: the clock `now` (µs) is an argument; contexts HA would
  make with a random ULID get a symbolic id `ulid@<ms>#<n>` (`genContext`, and
  the bus's own `makeEvent`). Recursion is bounded by fuel, service calls
  nest at most `MAX_CALL_DEPTH` deep and the loop runs at most `LOOP_FUEL`
  handles per operation; running out of any is reported as
  `Entry.unsupported` (HA would raise `RecursionError` somewhere deeper, or
  never return), and the driver rejects the operation. So is a main task
  that waits with nothing left to run (HA would hang).
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
  /-- `hass.bus.async_listen` / `async_listen_once` with a scripted listener
  (`isAsync`: an `async def`, otherwise a `@callback`); the remove callback is
  kept under `id` -/
  | listen (id eventType : String) (once : Bool) (filter : Option FilterSpec)
      (react : List Action) (reactTimes : Option Nat) (isAsync : Bool)
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
  says which). The outcome is recorded under `id`. In a coroutine, an error
  propagates unless `caught`; in a `@callback` listener the call runs in a
  task and its error never reaches the listener. -/
  | call (id : String) (args : CallArgs) (context : CtxArg) (caught : Bool)
  /-- `hass.services.async_register(domain, service, handler, schema,
  supports_response)`: the handler runs `body`, then does what `result` says -/
  | register (domain service : String) (body : List Action) (result : HandlerSpec)
      (schema : Option SchemaSpec) (supportsResponse : SupportsResponse)
  /-- `hass.services.async_remove(domain, service)` -/
  | removeService (domain service : String)
  /-- `await asyncio.sleep(0)` (coroutines only) -/
  | sleep
  /-- `await fut` for the future named `id` (coroutines only) -/
  | wait (id : String)
  /-- `fut.set_result(None)` for the future named `id` -/
  | resolve (id : String)

/-- What an operation leaves behind, in order. -/
inductive Entry
  /-- a listener received an event (`Event.as_dict()`) -/
  | delivery (job : Nat) (listener : String) (event : Event)
  /-- a `homeassistant.core` (or `homeassistant`) log record (warning and above) -/
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

/-- Where a script runs: the clock, the context `inherit` means (the event's
in a listener, the `ServiceCall`'s in a handler), whether it is a `@callback`
listener, and how deep service calls are nested. -/
structure Env where
  now : Nat
  ctx : Option Context := none
  inListener : Bool := false
  depth : Nat := 0

/-! ## Tasks and the event loop -/

/-- What a suspended coroutine waits for. -/
inductive Wait
  /-- `await asyncio.sleep(0)`: a bare `yield`, on which `Task.__step`
  re-schedules the task with `loop.call_soon` -/
  | soon
  /-- `await fut` on a pending future: `fut.add_done_callback(task.__wakeup)` -/
  | fut (id : String)
  /-- the main task in `async_block_till_done`: `await waiter` in
  `asyncio.wait`, woken by `_on_completion` -/
  | round

/-- One frame of a suspended coroutine's stack (innermost first). -/
inductive Frame
  /-- the rest of a script -/
  | script (env : Env) (rest : List Action)
  /-- the end of `_execute_service` and `async_call` for a handler whose
  script ran (its result spec, then `finishCall`; not blocking: inside
  `_run_service_call_catch_exceptions`) -/
  | handlerRet (a : CallArgs) (p : PreparedCall)
  /-- the end of a scripted `call` action: record the outcome; `swallow`: the
  error stops here (`catch`, or the task of a `@callback` listener's call) -/
  | callAct (id : String) (swallow : Bool)
  /-- the `while tasks := [...]` check of `async_block_till_done` -/
  | btdCheck

/-- The outcome of running (part of) a coroutine: a value, an exception, or
suspended on `w` with the frames still to run. -/
inductive Res
  | ok (v : Value)
  | err (e : PyError)
  | susp (w : Wait) (k : List Frame)

def Res.ofExcept : Except PyError Value → Res
  | .ok v => .ok v
  | .error e => .err e

/-- A task in `hass._tasks` (or just removed from it but still referenced by
the `tasks` list of `async_block_till_done`). -/
structure TaskRec where
  id : Nat
  /-- the frames left to run while suspended -/
  cont : List Frame := []
  finished : Bool := false
  /-- finished with this exception (nobody retrieves it) -/
  exc : Option PyError := none
  /-- in `hass._tasks` (its done callback `_tasks.remove` has not run) -/
  inSet : Bool := true
  /-- in the current `tasks` list of `async_block_till_done` -/
  pinned : Bool := false

/-- A callback in the loop's ready queue. -/
inductive Handle
  /-- `Task.__step` / `Task.__wakeup` of task `t` (0: the main task) -/
  | step (t : Nat)
  /-- task `t`'s done callback `hass._tasks.remove` -/
  | done (t : Nat)
  /-- `asyncio.wait`'s `_on_completion` for task `t` -/
  | onc (t : Nat)
  deriving BEq

/-- An `asyncio.Future` made with `loop.create_future()` (on first use). -/
inductive Fut
  /-- pending; the tasks whose `__wakeup` is a done callback, in order -/
  | pending (waiters : List Nat)
  | done

/-! ## The core -/

structure Hass where
  states : StateMachine := {}
  bus : Bus := Bus.new
  services : Registry := []
  /-- each listener's script, by bus job key -/
  reacts : List (Nat × List Action) := []
  /-- the job keys of coroutine-function listeners -/
  asyncJobs : List Nat := []
  /-- each service's handler script, by lowercased `(domain, service)` -/
  bodies : List ((String × String) × List Action) := []
  /-- the tasks (in `hass._tasks`, or pinned by `async_block_till_done`) -/
  tasks : List TaskRec := []
  /-- the loop's ready queue (`loop._ready`) -/
  ready : List Handle := []
  futures : List (String × Fut) := []
  nextTask : Nat := 1
  /-- the main task's frames while it is suspended -/
  mainCont : List Frame := []
  /-- `asyncio.wait`'s `counter` in `async_block_till_done` -/
  roundLeft : Nat := 0

def Hass.new : Hass := {}

/-- Service calls nested deeper than this are not modelled (Python's
recursion limit is reached somewhere around there). -/
def MAX_CALL_DEPTH : Nat := 32

/-- Fuel for one operation. -/
def FUEL : Nat := 1000000

/-- Handles the loop may run in one operation. -/
def LOOP_FUEL : Nat := 100000

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

/-- A synchronous script's outcome (`@callback`s cannot await: a suspension
there is outside the model). -/
def syncOutcome : Res → Out × Option PyError
  | .ok _ => ([], none)
  | .err e => ([], some e)
  | .susp .. => ([.unsupported "await in a @callback"], some exhausted)

/-! ### The loop's primitives -/

def Hass.enqueue (h : Hass) (x : Handle) : Hass := { h with ready := h.ready ++ [x] }

def Hass.futOf (h : Hass) (f : String) : Fut := (h.futures.lookup f).getD (.pending [])

def Hass.setFut (h : Hass) (f : String) (v : Fut) : Hass :=
  { h with futures := (f, v) :: h.futures.filter (·.1 != f) }

def Hass.updTask (h : Hass) (t : Nat) (g : TaskRec → TaskRec) : Hass :=
  { h with tasks := h.tasks.map fun x => if x.id == t then g x else x }

def Hass.findTask (h : Hass) (t : Nat) : Option TaskRec := h.tasks.find? (·.id == t)

/-- Task `t` (0: the main task) suspends on `w`. -/
def Hass.park (h : Hass) (t : Nat) (w : Wait) : Hass :=
  match w with
  | .soon => h.enqueue (.step t)
  | .fut f => match h.futOf f with
    | .pending ws => h.setFut f (.pending (ws ++ [t]))
    | .done => h.enqueue (.step t)
  | .round => h

/-- `logging.getLogger("homeassistant").error("Error doing job: ...")` from
`_async_loop_exception_handler`, when a task that finished with an exception
is finalized. -/
def gcLog (e : PyError) : Entry :=
  .log { level := "error", message := "Error doing job: Task exception was never retrieved",
         exception := some s!"{e.exception}: {e.message}" }

/-- An eager task (`Task(coro, eager_start=True)`) whose first step had
outcome `r`. Done: never added to `hass._tasks`, and dropped at once (an
exception is logged as it is finalized). Suspended: a new task in
`hass._tasks`, parked on what it waits for. -/
def Hass.spawn (h : Hass) (r : Res) : Hass × Out :=
  match r with
  | .ok _ => (h, [])
  | .err e => (h, [gcLog e])
  | .susp w k =>
    let t := h.nextTask
    (({ h with nextTask := t + 1, tasks := h.tasks ++ [{ id := t, cont := k }] } : Hass).park t w, [])

/-- `fut.set_result(None)`: each waiter's `__wakeup` is scheduled, in order.
On a future already done it raises `asyncio.InvalidStateError`, which is not
modelled (its name clashes with HA's own `InvalidStateError`): `none`. -/
def Hass.resolve (h : Hass) (f : String) : Option Hass :=
  match h.futOf f with
  | .done => none
  | .pending ws => some (ws.foldl (fun h t => h.enqueue (.step t)) (h.setFut f .done))

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

/-- The listener records the event and runs its script: a `@callback` inline
(its exception goes to `_async_dispatch`, which logs it), a coroutine function
as an eager task (`_async_add_hass_job`: `create_eager_task`; nothing
reaches `_async_dispatch`). -/
def runListener : Nat → Nat → Hass → Job → Event → Hass × Out × Option PyError
  | 0, _, h, _, _ => (h, [.unsupported "fuel"], some exhausted)
  | n + 1, now, h, job, ev =>
    let isAsync := h.asyncJobs.contains job.key
    let d := recordDelivery h job ev
    if d.2.2 then
      let r := runActions n { now, ctx := some ev.context, inListener := !isAsync } d.1
        (d.1.scriptOf job.key)
      if isAsync then
        let s := r.1.spawn r.2.2
        (s.1, d.2.1 ++ r.2.1 ++ s.2, none)
      else
        let o := syncOutcome r.2.2
        (r.1, d.2.1 ++ r.2.1 ++ o.1, o.2)
    else (d.1, d.2.1, none)

/-- `async_run_hass_job` on a listener: a `_OneTimeListener` removes itself
first (and does nothing if it already ran); then the listener runs. -/
def runJob : Nat → Nat → Hass → Job → Event → Hass × Out × Option PyError
  | 0, _, h, _, _ => (h, [.unsupported "fuel"], some exhausted)
  | n + 1, now, h, job, ev =>
    if job.system then (h, [], none)
    else if job.once then
      if h.bus.onceRemoved.contains job.key then (h, [], none)
      else
        let u := useOnce h job
        let r := runListener n now u.1 job ev
        (r.1, u.2 ++ r.2.1, r.2.2)
    else runListener n now h job ev

/-- A script: the actions in order, stopping at the first exception or
suspension (which keeps the rest of the script as a frame). -/
def runActions : Nat → Env → Hass → List Action → Hass × Out × Res
  | 0, _, h, _ => (h, [.unsupported "fuel"], .err exhausted)
  | _ + 1, _, h, [] => (h, [], .ok .none)
  | n + 1, env, h, a :: as =>
    let r1 := runAction n env h a
    match r1.2.2 with
    | .err e => (r1.1, r1.2.1, .err e)
    | .susp w k => (r1.1, r1.2.1, .susp w (k ++ [.script env as]))
    | .ok _ =>
      let r2 := runActions n env r1.1 as
      (r2.1, r1.2.1 ++ r2.2.1, r2.2.2)

/-- One action; the result is what the Python call returns, the exception
it raises, or the suspension it awaits. -/
def runAction : Nat → Env → Hass → Action → Hass × Out × Res
  | 0, _, h, _ => (h, [.unsupported "fuel"], .err exhausted)
  | n + 1, env, h, a =>
    match a with
    | .fire f =>
      let r := fireInternal n env.now h (mkQueued env.now f (resolveCtx env f.context))
      (r.1, r.2.1, match r.2.2 with | some e => .err e | none => .ok .none)
    | .listen id et once filter react rt isAsync =>
      match listenOp h.bus id et once filter none [] rt with
      | .ok b => ({ h with bus := b, reacts := (h.bus.nextKey, react) :: h.reacts,
                           asyncJobs := if isAsync then h.bus.nextKey :: h.asyncJobs
                                        else h.asyncJobs }, [], .ok .none)
      | .error e => (h, [], .err (busError e))
    | .unsub id =>
      match h.bus.handles.lookup id with
      | none => (h, [], .err { exception := "KeyError", message := strRepr id })
      | some (et, k) =>
        let r := removeListener h et k
        (r.1, r.2, .ok .none)
    | .raise exc msg => (h, [], .err { exception := exc, message := msg })
    | .set eid st attrs force c =>
      -- `async_set`: `timestamp or time.time()`; `async_set_internal` makes
      -- `Context(id=ulid_at_time(timestamp))` when none is given
      let ts := timestampOf env.now
      let hc := h.ctxOr (resolveCtx env c) env.now
      match hc.1.states.asyncSet eid st attrs force (some hc.2) (utcMicrosOfTimestamp ts) with
      | .error e => match smError e with
        | some pe => (hc.1, [], .err pe)
        | none => (hc.1, [.unsupported "state machine"], .err exhausted)
      | .ok (sm, evs) =>
        let r := fireList n env.now { hc.1 with states := sm }
          (evs.map fun e => smQueued env.now e (some hc.2))
        (r.1, r.2.1, match r.2.2 with | some e => .err e | none => .ok .none)
    | .remove eid c =>
      let ctx := resolveCtx env c
      match h.states.asyncRemove eid ctx (utcMicrosOfTimestamp (timestampOf env.now)) with
      | .error e => match smError e with
        | some pe => (h, [], .err pe)
        | none => (h, [.unsupported "state machine"], .err exhausted)
      | .ok (removed, sm, evs) =>
        let r := fireList n env.now { h with states := sm } (evs.map fun e => smQueued env.now e ctx)
        (r.1, r.2.1, match r.2.2 with | some e => .err e | none => .ok (.bool removed))
    | .call id args c caught =>
      let r := callService n env h { args with context := resolveCtx env c }
      match r.2.2 with
      | .ok v => (r.1, r.2.1 ++ [.callResult id (.ok v)], .ok v)
      | .err e => (r.1, r.2.1 ++ [.callResult id (.error e)],
          if caught || env.inListener then .ok .none else .err e)
      | .susp w k =>
        if env.inListener then
          -- `hass.async_create_task(...)`: the call's own task goes on later
          let s := r.1.spawn (.susp w (k ++ [.callAct id true]))
          (s.1, r.2.1 ++ s.2, .ok .none)
        else (r.1, r.2.1, .susp w (k ++ [.callAct id caught]))
    | .register d s body result schema sr =>
      let rr := h.services.register d s { handler := result, schema, supportsResponse := sr }
        (env.now / 1000)
      let key := (d.toLower, s.toLower)
      let h1 := { h with services := rr.1, bodies := (key, body) :: bodyErase h.bodies key }
      match rr.2.mapM (firedQueued env.now) with
      | none => (h1, [.unsupported "event data"], .err exhausted)
      | some qs =>
        let r := fireList n env.now h1 qs
        (r.1, r.2.1, match r.2.2 with | some e => .err e | none => .ok .none)
    | .removeService d s =>
      let rr := h.services.remove d s (env.now / 1000)
      let h1 := { h with services := rr.1,
                         bodies := if rr.2.1.isEmpty then h.bodies
                                   else bodyErase h.bodies (d.toLower, s.toLower) }
      match rr.2.1.mapM (firedQueued env.now) with
      | none => (h1, [.unsupported "event data"], .err exhausted)
      | some qs =>
        let r := fireList n env.now h1 qs
        (r.1, rr.2.2.map .log ++ r.2.1, match r.2.2 with | some e => .err e | none => .ok .none)
    | .sleep => (h, [], .susp .soon [])
    | .wait f => match h.futOf f with
      | .done => (h, [], .ok .none)
      | .pending _ => (h, [], .susp (.fut f) [])
    | .resolve f => match h.resolve f with
      | some h' => (h', [], .ok .none)
      | none => (h, [.unsupported "a future resolved twice (asyncio.InvalidStateError)"], .err exhausted)

/-- `ServiceRegistry.async_call` with a scripted handler: `context or
Context()`, `prepareCall`, `call_service` through the bus, the handler's
script (with the call's context), then its result spec, then `finishCall`.
A handler that suspends suspends a blocking call; a non-blocking one goes on
in its task (`_run_service_call_catch_exceptions`) and returns `None`. -/
def callService : Nat → Env → Hass → CallArgs → Hass × Out × Res
  | 0, _, h, _ => (h, [.unsupported "fuel"], .err exhausted)
  | n + 1, env, h, a =>
    if env.depth ≥ MAX_CALL_DEPTH then (h, [.unsupported "call depth"], .err exhausted)
    else
      let hc := h.ctxOr a.context env.now
      match hc.1.services.prepareCall a hc.2 with
      | .error e => (hc.1, [], .err e)
      | .ok p =>
        let body := bodyLookup hc.1.bodies (p.domain, p.service)
        match firedQueued env.now (p.event (env.now / 1000)) with
        | none => (hc.1, [.unsupported "event data"], .err exhausted)
        | some q =>
          let r1 := fireInternal n env.now hc.1 q
          match r1.2.2 with
          | some e => (r1.1, r1.2.1, .err e)
          | none =>
            let r2 := runActions n { now := env.now, ctx := some hc.2, inListener := false,
                                     depth := env.depth + 1 } r1.1 body
            match r2.2.2 with
            | .susp w k =>
              if a.blocking then (r2.1, r1.2.1 ++ r2.2.1, .susp w (k ++ [.handlerRet a p]))
              else
                let s := r2.1.spawn (.susp w (k ++ [.handlerRet a p]))
                (s.1, r1.2.1 ++ r2.2.1 ++ s.2, .ok .none)
            | .ok _ =>
              let fin := finishCall a p.call (runHandler p.svc.handler p.call)
              (r2.1, r1.2.1 ++ r2.2.1 ++ fin.2.map .log, Res.ofExcept fin.1)
            | .err e =>
              let fin := finishCall a p.call (.error e)
              (r2.1, r1.2.1 ++ r2.2.1 ++ fin.2.map .log, Res.ofExcept fin.1)

end

/-! ## Resuming tasks and running the loop -/

/-- `async_block_till_done`, when the main task resumes in its
`while tasks := [...]` loop: the new `tasks` list replaces the old one, so a
task only the old list still held is finalized (its exception logged). The
list's order is `hass._tasks`'s set order, so two such exceptions would be
logged in an order the model cannot know: `none`. -/
def endRound (h : Hass) : Option (Hass × Out) :=
  let gone := h.tasks.filter fun t => t.pinned && !t.inSet
  let logs := gone.filterMap fun t => t.exc.map gcLog
  if logs.length ≥ 2 then none
  else
    let kept := (h.tasks.filter fun t => !(t.pinned && !t.inSet)).map (fun t => { t with pinned := false })
    some ({ h with tasks := kept }, logs)

/-- `asyncio.wait(tasks)`: every task of `hass._tasks` gets `_on_completion`
as a done callback (scheduled at once for a task already done), and the main
task waits until the counter reaches 0. -/
def startRound (h : Hass) : Hass :=
  let live := h.tasks.filter (·.inSet)
  let h1 := { h with tasks := h.tasks.map (fun t => if t.inSet then { t with pinned := true } else t),
                     roundLeft := live.length }
  (live.filter (·.finished)).foldl (fun h t => h.enqueue (.onc t.id)) h1

/-- Run a suspended coroutine's frames (innermost first) from the outcome of
what it awaited. -/
def resume (n now : Nat) : Hass → List Frame → Except PyError Value → Hass × Out × Res
  | h, [], r => (h, [], Res.ofExcept r)
  | h, .script env rest :: k, r =>
    match r with
    | .error e => resume n now h k (.error e)
    | .ok _ =>
      let r1 := runActions n { env with now } h rest
      match r1.2.2 with
      | .susp w k' => (r1.1, r1.2.1, .susp w (k' ++ k))
      | .ok v =>
        let r2 := resume n now r1.1 k (.ok v)
        (r2.1, r1.2.1 ++ r2.2.1, r2.2.2)
      | .err e =>
        let r2 := resume n now r1.1 k (.error e)
        (r2.1, r1.2.1 ++ r2.2.1, r2.2.2)
  | h, .handlerRet a p :: k, r =>
    let res := match r with
      | .error e => .error e
      | .ok _ => runHandler p.svc.handler p.call
    let fin := finishCall a p.call res
    let r2 := resume n now h k fin.1
    (r2.1, fin.2.map .log ++ r2.2.1, r2.2.2)
  | h, .callAct id swallow :: k, r =>
    let r' := match r with
      | .error e => if swallow then .ok .none else .error e
      | .ok v => .ok v
    let r2 := resume n now h k r'
    (r2.1, .callResult id r :: r2.2.1, r2.2.2)
  | h, .btdCheck :: k, _ =>
    match endRound h with
    | none => (h, [.unsupported "two task exceptions logged in set order"], .err exhausted)
    | some (h1, logs) =>
      if h1.tasks.any (·.inSet) then (startRound h1, logs, .susp .round (.btdCheck :: k))
      else
        let r2 := resume n now h1 k (.ok .none)
        (r2.1, logs ++ r2.2.1, r2.2.2)

/-- Task `t` finished: its done callbacks are scheduled (`_tasks.remove`, then
`_on_completion` if `async_block_till_done` waits for it). -/
def finishTask (h : Hass) (t : TaskRec) (exc : Option PyError) : Hass :=
  let h1 := (h.updTask t.id fun x => { x with finished := true, exc, cont := [] }).enqueue (.done t.id)
  if t.pinned then h1.enqueue (.onc t.id) else h1

/-- Run one handle of the ready queue (not the main task's step). -/
def runHandle (n now : Nat) (h : Hass) : Handle → Hass × Out
  | .step t => match h.findTask t with
    | none => (h, [])
    | some task =>
      let r := resume n now h task.cont (.ok .none)
      match r.2.2 with
      | .susp w k => ((r.1.updTask t fun x => { x with cont := k }).park t w, r.2.1)
      | .ok _ => (finishTask r.1 task none, r.2.1)
      | .err e => (finishTask r.1 task (some e), r.2.1)
  | .done t => match h.findTask t with
    | none => (h, [])
    | some task =>
      if task.pinned then (h.updTask t fun x => { x with inSet := false }, [])
      else ({ h with tasks := h.tasks.filter (·.id != t) }, (task.exc.map gcLog).toList)
  | .onc _ =>
    if h.roundLeft ≤ 1 then ({ h with roundLeft := 0 }.enqueue (.step 0), [])
    else ({ h with roundLeft := h.roundLeft - 1 }, [])

/-- The main task suspends on `w` with frames `k`. -/
def parkMain (h : Hass) (w : Wait) (k : List Frame) : Hass :=
  ({ h with mainCont := k } : Hass).park 0 w

/-- `BaseEventLoop._run_once`, while the main task is suspended: the ready
queue's head runs (FIFO), until the main task's own step finishes it. `acc`
is the output so far, reversed. -/
def runLoop : Nat → Nat → Hass → Out → Hass × Out × Except PyError Value
  | 0, _, h, acc => (h, (Entry.unsupported "loop fuel" :: acc).reverse, .error exhausted)
  | n + 1, now, h, acc =>
    match h.ready with
    | [] => (h, (Entry.unsupported "the main task waits with nothing left to run" :: acc).reverse,
             .error exhausted)
    | .step 0 :: rest =>
      let r := resume FUEL now { h with ready := rest, mainCont := [] } h.mainCont (.ok .none)
      match r.2.2 with
      | .ok v => (r.1, (r.2.1.reverse ++ acc).reverse, .ok v)
      | .err e => (r.1, (r.2.1.reverse ++ acc).reverse, .error e)
      | .susp w k => runLoop n now (parkMain r.1 w k) (r.2.1.reverse ++ acc)
    | x :: rest =>
      let r := runHandle FUEL now { h with ready := rest } x
      runLoop n now r.1 (r.2.reverse ++ acc)

/-- The main task's outcome: done, or suspended and run to the end by the
loop. -/
def drive (now : Nat) (r : Hass × Out × Res) : Hass × Out × Except PyError Value :=
  match r.2.2 with
  | .ok v => (r.1, r.2.1, .ok v)
  | .err e => (r.1, r.2.1, .error e)
  | .susp w k => runLoop LOOP_FUEL now (parkMain r.1 w k) r.2.1.reverse

/-! ## Operations (one per input line) -/

inductive Op
  /-- `set`, `remove`, `fire`, `listen`, `listen_once`, `unsub`, `register`,
  `remove_service`, `resolve`: the same calls a script makes -/
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
  /-- `await asyncio.sleep(0)` -/
  | sleep
  /-- `await hass.async_block_till_done()` -/
  | blockTillDone

inductive Result
  | value (v : Value)
  | state (s : Option State)
  | listeners (counts : List (String × Nat))
  | bool (b : Bool)

def step (now : Nat) (h : Hass) : Op → Hass × Out × Except PyError Result
  | .act a =>
    let r := drive now (runAction FUEL { now } h a)
    (r.1, r.2.1, r.2.2.map .value)
  | .call a =>
    let r := drive now (callService FUEL { now } h a)
    (r.1, r.2.1, r.2.2.map .value)
  | .get e => match h.states.get e with
    | .ok s => (h, [], .ok (.state s))
    | .error _ => (h, [.unsupported "entity id"], .error exhausted)
  | .listeners => (h, [], .ok (.listeners (asyncListeners h.bus)))
  | .has d s => (h, [], .ok (.bool (h.services.hasService d s)))
  | .init counts =>
    let (t, next) := initTable h.bus.nextKey counts
    ({ h with bus := { h.bus with listeners := t, nextKey := next, handles := [] } }, [], .ok (.value .none))
  | .sleep =>
    let r := drive now (h, [], .susp .soon [])
    (r.1, r.2.1, r.2.2.map .value)
  | .blockTillDone =>
    -- `await asyncio.sleep(0)`, then the `while tasks := [...]` loop
    let r := drive now (h, [], .susp .soon [.btdCheck])
    (r.1, r.2.1, r.2.2.map .value)

end HALean.Core.Hass
