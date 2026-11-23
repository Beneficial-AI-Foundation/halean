/-
  The event bus: `homeassistant/core.py` `EventBus`, with `Event`,
  `EventOrigin` and `Context` as far as the bus needs them.

  Listener callbacks are abstract. Each listener has an id that records what it
  receives (a `Delivery`), and an optional script of reactions it runs on
  receipt: fire an event, add a listener, remove one, or raise. That is enough
  to observe every ordering decision the bus makes: specific listeners before
  `MATCH_ALL` ones, insertion order, the snapshot taken at the start of a
  dispatch (listeners added during it miss the event, listeners removed during
  it still get it), and the queue of events fired while another is dispatched.

  Every listener is a `@callback`: `async_run_hass_job` runs it at once, so a
  delivery and its reactions happen inside the dispatch loop. Coroutine and
  executor listeners are not modelled.

  The model is pure. Time only enters as the clock reading `now` of each
  operation; contexts that HA would create with a random ULID get a symbolic
  id that records the ULID's millisecond timestamp (`ulid@<ms>#<n>`).
-/
import Lean.Data.Json
import HALean.Template.Time
open Lean

namespace HALean.Core.EventBus

/-! ### Constants (`homeassistant/const.py`, `core.py`) -/

def MATCH_ALL : String := "*"
def MAX_LENGTH_EVENT_EVENT_TYPE : Nat := 64
def EVENT_STATE_REPORTED : String := "state_reported"
def EVENT_HOMEASSISTANT_CLOSE : String := "homeassistant_close"
def EVENT_LOGGING_CHANGED : String := "logging_changed"
/-- `core.py::EVENTS_EXCLUDED_FROM_MATCH_ALL` -/
def EVENTS_EXCLUDED_FROM_MATCH_ALL : List String := [EVENT_HOMEASSISTANT_CLOSE, EVENT_STATE_REPORTED]
/-- `core.py::_MAX_QUEUED_EVENT_DISPATCHES` -/
def MAX_QUEUED_EVENT_DISPATCHES : Nat := 10000

/-! ### Values -/

/-- `core.py::Context` (`id`, `user_id`, `parent_id`; `origin_event` is not
observable through the bus). -/
structure Context where
  id : String
  userId : Option String := none
  parentId : Option String := none
  deriving BEq, Inhabited, Repr

/-- `core.py::EventOrigin` -/
inductive Origin | «local» | remote
  deriving BEq, Inhabited, Repr

def Origin.value : Origin → String
  | .local => "LOCAL"
  | .remote => "REMOTE"

/-- The exceptions the bus can raise or log, by Python class name. -/
inductive Err
  | homeAssistantError | maxLengthExceeded | runtimeError | typeError | valueError | keyError
  deriving BEq, Inhabited, Repr

def Err.name : Err → String
  | .homeAssistantError => "HomeAssistantError"
  | .maxLengthExceeded => "MaxLengthExceeded"
  | .runtimeError => "RuntimeError"
  | .typeError => "TypeError"
  | .valueError => "ValueError"
  | .keyError => "KeyError"

/-- An abstract `event_filter` over the event data. -/
inductive Filter
  /-- always returns this value -/
  | const (b : Bool)
  /-- every key is present and `==` (Python equality) the value -/
  | eq (kvs : List (String × Json))
  /-- the key is present -/
  | has (k : String)
  /-- raises `ValueError` -/
  | raises
  deriving Inhabited

structure FilterSpec where
  filter : Filter
  /-- decorated with `@callback` (`is_callback_check_partial`) -/
  isCallback : Bool := true
  deriving Inhabited

/-- Context argument of a fire: none (HA makes one), a given one, or (inside a
listener) the context of the event being handled. -/
inductive CtxArg | none | given (c : Context) | inherit
  deriving Inhabited

/-- Arguments of `async_fire`. `timeFired` is a clock reading in µs. -/
structure FireArgs where
  eventType : String
  data : Option Json := none
  origin : Origin := .local
  context : CtxArg := .none
  timeFired : Option Nat := none
  deriving Inhabited

/-- What a listener does when it receives an event, and the top-level
listen/unsub operations (the same calls). -/
inductive Reaction
  /-- `hass.bus.async_fire(...)` -/
  | fire (f : FireArgs)
  /-- `async_listen` (`once = false`) or `async_listen_once`; the remove
  callback is stored under `id`. -/
  | listen (id eventType : String) (once : Bool) (filter : Option FilterSpec)
      (runImmediately : Option Bool) (react : List Reaction) (reactTimes : Option Nat)
  /-- call the remove callback stored under `id` -/
  | unsub (id : String)
  /-- raise an exception -/
  | raise (e : Err)
  deriving Inhabited

/-! ### Clock and time -/

/-- `time.time()` when the clock reads `us` microseconds: whole seconds plus
the fraction, the float freezegun's `time.time()` returns. -/
def timestampOf (us : Nat) : Float :=
  (us / 1000000).toFloat + (us % 1000000).toFloat / 1000000.0

/-- CPython's `_PyTime_Round` with `_PyTime_ROUND_HALF_EVEN`. -/
def roundHalfEven (x : Float) : Float :=
  let r := x.round
  if (x - r).abs == 0.5 then 2.0 * (x / 2.0).round else r

/-- `dt_util.utc_from_timestamp(ts)` as microseconds since the epoch
(`datetime.fromtimestamp`: `modf`, then the fraction rounded half-even to µs). -/
def utcMicrosOfTimestamp (ts : Float) : Int :=
  let ip := ts.floor
  let us := roundHalfEven ((ts - ip) * 1000000.0)
  let (ip, us) := if us ≥ 1000000.0 then (ip + 1.0, us - 1000000.0) else (ip, us)
  (ip.toUInt64.toNat : Int) * 1000000 + us.toUInt64.toNat

/-- Milliseconds encoded in `ulid_at_time(ts)`: `int(ts * 1000)`. -/
def ulidMillis (ts : Float) : Nat := (ts * 1000.0).floor.toUInt64.toNat

/-! ### Events, listeners and the bus -/

/-- `core.py::Event` as far as `as_dict` shows it. `data` is already
`data or {}`. -/
structure Event where
  eventType : String
  data : Json
  origin : Origin
  timeFiredTimestamp : Float
  context : Context
  deriving Inhabited

/-- `Event.time_fired`, as `isoformat()` prints it. -/
def Event.timeFiredIso (e : Event) : String :=
  HALean.Template.isoformat (utcMicrosOfTimestamp e.timeFiredTimestamp) (some 0)

/-- `Context._as_dict` -/
def Context.asDict (c : Context) : Json :=
  let opt : Option String → Json := fun | some s => .str s | none => .null
  Json.mkObj [("id", .str c.id), ("parent_id", opt c.parentId), ("user_id", opt c.userId)]

/-- `Event._as_dict` / `Event.as_dict` -/
def Event.asDict (e : Event) : Json :=
  Json.mkObj [("event_type", .str e.eventType), ("data", e.data), ("origin", .str e.origin.value),
    ("time_fired", .str e.timeFiredIso), ("context", e.context.asDict)]

/-- One entry of a listener list: the `(HassJob, event_filter)` tuple. Python
compares these by identity; `key` is that identity. A `once` job is the
`_OneTimeListener` wrapper. `system` jobs stand for listeners that exist
before the model starts (`init`): they receive events but record nothing. -/
structure Job where
  key : Nat
  eventType : String
  listener : String
  once : Bool := false
  filter : Option FilterSpec := none
  react : List Reaction := []
  reactTimes : Option Nat := none
  system : Bool := false
  deriving Inhabited

/-- An event delivered to a listener (in delivery order). -/
structure Delivery where
  job : Nat
  once : Bool
  listener : String
  event : Event
  deriving Inhabited

/-- Records `_LOGGER.exception` calls in the bus. -/
inductive LogEntry
  /-- "Error in event filter" -/
  | filterError (e : Err)
  /-- "Error running job" -/
  | jobError (e : Err)
  /-- "Unable to remove unknown job listener" -/
  | removeUnknown (eventType : String)
  deriving Inhabited

/-- An event waiting in `EventBus._event_queue`. `timeFired` is already
`time_fired or time.time()`. -/
structure Queued where
  eventType : String
  data : Option Json
  origin : Origin
  context : Option Context
  timeFired : Float
  deriving Inhabited

/-- A `_listeners` table: a dict from event type to listener list, in
insertion order. -/
abbrev Table := List (String × List Job)

/-- The state of `EventBus` plus the trace of what listeners received. -/
structure Bus where
  listeners : Table
  dispatching : Bool := false
  queue : List Queued := []
  queuedCount : Nat := 0
  /-- next job identity -/
  nextKey : Nat
  /-- keys of `_OneTimeListener`s whose `remove` is `None` (already ran) -/
  onceRemoved : List Nat := []
  /-- remove callbacks by listener id, newest first: `(event_type, job key)` -/
  handles : List (String × (String × Nat)) := []
  /-- receipts per job key (for `reactTimes`) -/
  received : List (Nat × Nat) := []
  /-- contexts created by `Event.__init__` so far -/
  genCount : Nat := 0
  /-- everything delivered so far, newest first -/
  deliveries : List Delivery := []
  /-- everything logged so far, newest first -/
  logs : List LogEntry := []
  deriving Inhabited

/-- `EventBus.__init__`: `_listeners = {MATCH_ALL: [], EVENT_LOGGING_CHANGED:
[_async_logging_changed]}`. -/
def Bus.new : Bus :=
  { listeners := [(MATCH_ALL, []),
      (EVENT_LOGGING_CHANGED, [{ key := 0, eventType := EVENT_LOGGING_CHANGED,
                                 listener := "", system := true }])],
    nextKey := 1 }

/-! ### The `_listeners` dict -/

/-- `self._listeners.get(event_type, EMPTY_LIST)` -/
def Table.get (t : Table) (et : String) : List Job := (t.lookup et).getD []

/-- `self._listeners[event_type]` on the `defaultdict`: inserts an empty list
at the end when the key is missing. -/
def Table.touch (t : Table) (et : String) : Table :=
  if t.any (·.1 == et) then t else t ++ [(et, [])]

def Table.set (t : Table) (et : String) (l : List Job) : Table :=
  t.map fun p => if p.1 == et then (et, l) else p

/-- `self._listeners.pop(event_type)` -/
def Table.pop (t : Table) (et : String) : Table := t.filter (·.1 != et)

/-- `list.remove(x)`: drop the first entry with this identity, or `none`
(`ValueError`). -/
def removeFirst (k : Nat) : List Job → Option (List Job)
  | [] => none
  | j :: js => if j.key == k then some js else (removeFirst k js).map (j :: ·)

/-- `EventBus.async_listeners`: number of listeners per event type, in dict
order. -/
def asyncListeners (b : Bus) : List (String × Nat) :=
  b.listeners.map fun (et, l) => (et, l.length)

/-- `EventBus._async_listen_filterable_job`: append to the list of the event
type and return the remove callback (`(event_type, key)`). -/
def listenFilterableJob (b : Bus) (job : Job) : Bus × (String × Nat) :=
  let job := { job with key := b.nextKey }
  let t := b.listeners.touch job.eventType
  let t := t.set job.eventType (t.get job.eventType ++ [job])
  ({ b with listeners := t, nextKey := b.nextKey + 1 }, (job.eventType, job.key))

/-- `EventBus._async_remove_listener`. A listener that is not there (removed
twice) is logged, not raised; the `defaultdict` access leaves an empty list
for its event type behind. -/
def asyncRemoveListener (b : Bus) (et : String) (k : Nat) : Bus :=
  let t := b.listeners.touch et
  match removeFirst k (t.get et) with
  | none => { b with listeners := t, logs := .removeUnknown et :: b.logs }
  | some l =>
    let t := t.set et l
    let t := if l.isEmpty && et != MATCH_ALL then t.pop et else t
    { b with listeners := t }

/-- `EventBus.async_listen`. The `run_immediately` argument is reported with
`ReportBehavior.ERROR` for every caller, which raises. -/
def asyncListen (b : Bus) (id et : String) (filter : Option FilterSpec)
    (runImmediately : Option Bool) (react : List Reaction) (reactTimes : Option Nat) :
    Except Err (Bus × (String × Nat)) :=
  if runImmediately.isSome then .error .runtimeError
  else if filter.any (!·.isCallback) then .error .homeAssistantError
  else if et == EVENT_STATE_REPORTED && filter.isNone then .error .homeAssistantError
  else .ok (listenFilterableJob b
    { key := 0, eventType := et, listener := id, filter, react, reactTimes })

/-- `EventBus.async_listen_once`: a `_OneTimeListener` job with no filter. The
method has no `event_filter` parameter, so passing one is a `TypeError`. -/
def asyncListenOnce (b : Bus) (id et : String) (filter : Option FilterSpec)
    (runImmediately : Option Bool) (react : List Reaction) (reactTimes : Option Nat) :
    Except Err (Bus × (String × Nat)) :=
  if filter.isSome then .error .typeError
  else if runImmediately.isSome then .error .runtimeError
  else .ok (listenFilterableJob b
    { key := 0, eventType := et, listener := id, once := true, react, reactTimes })

/-- A listen operation: subscribe and keep the remove callback under `id`. -/
def listenOp (b : Bus) (id et : String) (once : Bool) (filter : Option FilterSpec)
    (runImmediately : Option Bool) (react : List Reaction) (reactTimes : Option Nat) :
    Except Err Bus :=
  match (if once then asyncListenOnce else asyncListen) b id et filter runImmediately react reactTimes with
  | .ok (b, h) => .ok { b with handles := (id, h) :: b.handles }
  | .error e => .error e

/-- Call the remove callback stored under `id` (a `KeyError` if there is none). -/
def unsubOp (b : Bus) (id : String) : Except Err Bus :=
  match b.handles.lookup id with
  | none => .error .keyError
  | some (et, k) => .ok (asyncRemoveListener b et k)

/-! ### Firing and dispatching -/

/-- The event as it enters `async_fire_internal`, with `time_fired or
time.time()` resolved against the clock. -/
def mkQueued (now : Nat) (f : FireArgs) (ctx : Option Context) : Queued :=
  let tf := match f.timeFired with
    | some t => if t == 0 then now else t
    | none => now
  { eventType := f.eventType, data := f.data, origin := f.origin, context := ctx,
    timeFired := timestampOf tf }

/-- `async_fire_internal` while `_dispatching` is set: queue the event, or
raise once `_MAX_QUEUED_EVENT_DISPATCHES` have been queued during this
top-level dispatch. Listeners only run inside a dispatch, so this is the
branch every fire from a listener takes. -/
def fireNested (b : Bus) (q : Queued) : Bus × Option Err :=
  if b.queuedCount ≥ MAX_QUEUED_EVENT_DISPATCHES then (b, some .homeAssistantError)
  else ({ b with queuedCount := b.queuedCount + 1, queue := b.queue ++ [q] }, none)

/-- One reaction of a listener. -/
def react1 (now : Nat) (ev : Event) (b : Bus) : Reaction → Bus × Option Err
  | .fire f =>
    -- `async_fire`: `_verify_event_type_length_or_raise`, then
    -- `async_fire_internal`
    if f.eventType.length > MAX_LENGTH_EVENT_EVENT_TYPE then (b, some .maxLengthExceeded)
    else
      let ctx := match f.context with
        | .none => none
        | .given c => some c
        | .inherit => some ev.context
      fireNested b (mkQueued now f ctx)
  | .listen id et once filter ri react rt =>
    match listenOp b id et once filter ri react rt with
    | .ok b => (b, none)
    | .error e => (b, some e)
  | .unsub id =>
    match unsubOp b id with
    | .ok b => (b, none)
    | .error e => (b, some e)
  | .raise e => (b, some e)

/-- A listener's reactions, in order; an exception ends the listener. -/
def runReactions (now : Nat) (ev : Event) : Bus → List Reaction → Bus × Option Err
  | b, [] => (b, none)
  | b, r :: rs =>
    match react1 now ev b r with
    | (b', some e) => (b', some e)
    | (b', none) => runReactions now ev b' rs

def Bus.receivedOf (b : Bus) (k : Nat) : Nat := (b.received.lookup k).getD 0

/-- The listener itself: record the delivery, then react (up to
`reactTimes` receipts). -/
def callListener (now : Nat) (b : Bus) (job : Job) (ev : Event) : Bus × Option Err :=
  let n := b.receivedOf job.key + 1
  let b := { b with
    deliveries := { job := job.key, once := job.once, listener := job.listener, event := ev } :: b.deliveries,
    received := (job.key, n) :: b.received }
  if job.reactTimes.all (n ≤ ·) then runReactions now ev b job.react else (b, none)

/-- `HomeAssistant.async_run_hass_job` on a listener job (a callback, run at
once). For a `_OneTimeListener`: `if not self.remove: return`, then
`self.remove()`, `self.remove = None`, then the listener. -/
def runJob (now : Nat) (b : Bus) (job : Job) (ev : Event) : Bus × Option Err :=
  if job.system then (b, none)
  else if job.once then
    if b.onceRemoved.contains job.key then (b, none)
    else
      let b := asyncRemoveListener b job.eventType job.key
      callListener now { b with onceRemoved := job.key :: b.onceRemoved } job ev
  else callListener now b job ev

/-- Python's `==` on JSON values (`1 == 1.0 == True`). -/
partial def pyEq : Json → Json → Bool
  | .null, .null => true
  | .bool a, .bool b => a == b
  | .str a, .str b => a == b
  | .num a, .num b => numEq a b
  | .bool a, .num n | .num n, .bool a => numEq n (if a then 1 else 0)
  | .arr a, .arr b => a.size == b.size && (a.toList.zip b.toList).all fun (x, y) => pyEq x y
  | .obj a, .obj b =>
    let la := a.toArray.toList
    let lb := b.toArray.toList
    la.length == lb.length && la.all fun (k, v) => match b.get? k with
      | some w => pyEq v w
      | none => false
  | _, _ => false
where
  numEq (a b : JsonNumber) : Bool :=
    a.mantissa * (10 : Int) ^ b.exponent == b.mantissa * (10 : Int) ^ a.exponent

/-- Run an `event_filter` on the event data. -/
def evalFilter (f : Filter) (data : Json) : Except Err Bool :=
  match f with
  | .const v => .ok v
  | .has k => .ok (data.getObjVal? k).toOption.isSome
  | .eq kvs => .ok <| kvs.all fun (k, v) => match data.getObjVal? k with
    | .ok w => pyEq w v
    | .error _ => false
  | .raises => .error .valueError

/-- `Event(event_type, event_data, origin, time_fired, context)`. Without a
context, `Context(id=ulid_at_time(time_fired))`: random, so it gets a
symbolic id carrying the ULID's millisecond timestamp. -/
def makeEvent (b : Bus) (q : Queued) : Bus × Event :=
  let (b, ctx) := match q.context with
    | some c => (b, c)
    | none => ({ b with genCount := b.genCount + 1 },
                { id := s!"ulid@{ulidMillis q.timeFired}#{b.genCount}" })
  (b, { eventType := q.eventType, data := q.data.getD (Json.mkObj []), origin := q.origin,
        timeFiredTimestamp := q.timeFired, context := ctx })

/-- The listeners `_async_dispatch` iterates over: a new list, so the
dispatch does not see listeners added or removed while it runs. -/
def snapshot (t : Table) (et : String) : List Job :=
  t.get et ++ (if EVENTS_EXCLUDED_FROM_MATCH_ALL.contains et then [] else t.get MATCH_ALL)

/-- Should this job run? `event_filter` is skipped (not called) when the
event data is `None`; an exception in it is logged and skips the job. -/
def filterPasses (job : Job) (data : Option Json) : Except Err Bool :=
  match job.filter with
  | none => .ok true
  | some f => match data with
    | none => .ok false
    | some d => evalFilter f.filter d

/-- `if not event: event = Event(...)` -/
def ensureEvent (b : Bus) (q : Queued) : Option Event → Bus × Event
  | some ev => (b, ev)
  | none => makeEvent b q

/-- `except Exception: _LOGGER.exception("Error running job: %s", job)` -/
def logJobError (b : Bus) : Option Err → Bus
  | some e => { b with logs := .jobError e :: b.logs }
  | none => b

/-- The `for job, event_filter in listeners + match_all_listeners` loop of
`EventBus._async_dispatch`. The `Event` is created on the first job that
passes its filter. -/
def dispatchLoop (now : Nat) (q : Queued) : Bus × Option Event → List Job → Bus × Option Event
  | acc, [] => acc
  | (b, ev?), job :: js =>
    match filterPasses job q.data with
    | .error e => dispatchLoop now q ({ b with logs := .filterError e :: b.logs }, ev?) js
    | .ok false => dispatchLoop now q (b, ev?) js
    | .ok true =>
      let (b, ev) := ensureEvent b q ev?
      let (b, err) := runJob now b job ev
      dispatchLoop now q (logJobError b err, some ev) js

/-- `EventBus._async_dispatch` -/
def dispatch (now : Nat) (b : Bus) (q : Queued) : Bus :=
  (dispatchLoop now q (b, none) (snapshot b.listeners q.eventType)).1

/-- `while event_queue: self._async_dispatch(*event_queue.popleft())`. At most
`_MAX_QUEUED_EVENT_DISPATCHES` events are queued per top-level dispatch, so
that many rounds empty the queue. -/
def drain (now : Nat) : Nat → Bus → Bus
  | 0, b => b
  | n + 1, b =>
    match b.queue with
    | [] => b
    | q :: qs => drain now n (dispatch now { b with queue := qs } q)

/-- `EventBus.async_fire` + `async_fire_internal` from outside a dispatch:
dispatch, then the events queued meanwhile, in order. -/
def asyncFire (now : Nat) (b : Bus) (f : FireArgs) (ctx : Option Context) : Except Err Bus :=
  if f.eventType.length > MAX_LENGTH_EVENT_EVENT_TYPE then .error .maxLengthExceeded
  else
    let q := mkQueued now f ctx
    if b.dispatching then
      match fireNested b q with
      | (b, none) => .ok b
      | (_, some e) => .error e
    else
      let b := dispatch now { b with dispatching := true, queuedCount := 0 } q
      let b := drain now MAX_QUEUED_EVENT_DISPATCHES b
      .ok { b with dispatching := false }

/-! ### Operations (one per input line) -/

inductive Op
  /-- Replace the listener table with listeners that already exist (counts
  per event type, in dict order), e.g. those of a running HA. -/
  | init (counts : List (String × Nat))
  /-- `listen` / `listen_once` / `unsub` (a `Reaction.listen` / `.unsub`) -/
  | call (r : Reaction)
  | fire (f : FireArgs)
  /-- `async_listeners()` -/
  | listeners
  deriving Inhabited

inductive Result
  | ok
  | err (e : Err)
  | listeners (counts : List (String × Nat))
  deriving Inhabited

/-- The listener table `init` installs: opaque jobs with fresh keys. -/
def initTable (next : Nat) : List (String × Nat) → Table × Nat
  | [] => ([], next)
  | (et, n) :: rest =>
    let jobs := (List.range n).map fun i =>
      ({ key := next + i, eventType := et, listener := "", system := true } : Job)
    let (t, next') := initTable (next + n) rest
    ((et, jobs) :: t, next')

def step (now : Nat) (b : Bus) : Op → Bus × Result
  | .init counts =>
    let (t, next) := initTable b.nextKey counts
    ({ b with listeners := t, nextKey := next, handles := [] }, .ok)
  | .listeners => (b, .listeners (asyncListeners b))
  | .fire f =>
    let ctx := match f.context with
      | .given c => some c
      | _ => none
    match asyncFire now b f ctx with
    | .ok b => (b, .ok)
    | .error e => (b, .err e)
  | .call r =>
    match react1Top b r with
    | .ok b => (b, .ok)
    | .error e => (b, .err e)
where
  react1Top (b : Bus) : Reaction → Except Err Bus
    | .listen id et once filter ri react rt => listenOp b id et once filter ri react rt
    | .unsub id => unsubOp b id
    | .raise e => .error e
    | .fire _ => .ok b

/-- Run a sequence of operations `(now, op)`. -/
def run (b : Bus) : List (Nat × Op) → Bus
  | [] => b
  | (now, op) :: ops => run (step now b op).1 ops

end HALean.Core.EventBus
