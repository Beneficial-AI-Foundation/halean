/-
  `homeassistant.core.StateMachine` (and its `States` container), translated
  from the pinned upstream release (see `manifest.yaml`).

  Pure: every operation takes the machine and its arguments, including the
  clock (`timestamp`, microseconds), and returns the new machine plus the
  events it fired, in order. No I/O, no clock, no randomness: a context the
  caller does not pass is a fresh symbolic ULID (`freshContext`).
-/
import HALean.Core.State
open Lean HALean.Template

namespace HALean.Core

/-- `homeassistant.const.EVENT_STATE_CHANGED` / `EVENT_STATE_REPORTED` -/
def EVENT_STATE_CHANGED := "state_changed"
def EVENT_STATE_REPORTED := "state_reported"

/-- The events the state machine fires (`EventBus.async_fire_internal`, origin
`LOCAL`). `timeFired` is the event's `time_fired_timestamp`, in microseconds. -/
inductive SMEvent where
  /-- `EventStateChangedData`: `{entity_id, old_state, new_state}` -/
  | stateChanged (entityId : String) (oldState newState : Option State)
      (context : Context) (timeFired : Int)
  /-- `{entity_id, last_reported, old_last_reported, new_state}` -/
  | stateReported (entityId : String) (lastReported oldLastReported : Int)
      (newState : State) (context : Context) (timeFired : Int)
  deriving Repr, BEq

def SMEvent.eventType : SMEvent → String
  | .stateChanged .. => EVENT_STATE_CHANGED
  | .stateReported .. => EVENT_STATE_REPORTED

/-- The event as the differential test sees it: data with states as
`as_dict()` and datetimes as `isoformat()`, plus `Event.context`,
`Event.time_fired` and `Event.origin`. -/
def SMEvent.toJson (e : SMEvent) : Json :=
  let (data, ctx, t) := match e with
    | .stateChanged eid o n c t =>
      (Json.mkObj [("entity_id", .str eid),
                   ("old_state", (o.map State.asDict).getD .null),
                   ("new_state", (n.map State.asDict).getD .null)], c, t)
    | .stateReported eid lr olr n c t =>
      (Json.mkObj [("entity_id", .str eid), ("last_reported", .str (isoUtc lr)),
                   ("old_last_reported", .str (isoUtc olr)), ("new_state", n.asDict)], c, t)
  Json.mkObj [("event_type", .str e.eventType), ("data", data), ("context", ctx.asDict),
              ("time_fired", .str (isoUtc t)), ("origin", .str "LOCAL")]

/-- `StateMachine` with its `States` dict. The dict is an insertion-ordered
association list, like Python's dict: overwriting keeps the position,
deleting and adding again moves the key to the end. -/
structure StateMachine where
  states : List (String × State) := []
  /-- `_reservations` (a set) -/
  reservations : List String := []
  /-- How many fresh contexts have been made (to name the next one). -/
  freshCount : Nat := 0
  deriving Inhabited

namespace StateMachine

/-- `self._states_data[entity_id]` -/
def lookup (sm : StateMachine) (entityId : String) : Option State :=
  (sm.states.find? (·.1 == entityId)).map (·.2)

/-- `States.__setitem__`: `data[key] = entry` (and the domain index). -/
def setItem (st : List (String × State)) (key : String) (s : State) : List (String × State) :=
  if st.any (·.1 == key) then st.map fun p => if p.1 == key then (key, s) else p
  else st ++ [(key, s)]

/-- `States.__delitem__` -/
def delItem (st : List (String × State)) (key : String) : List (String × State) :=
  st.filter (·.1 != key)

/-- `States.domain_entity_ids(domain)`. Upstream keeps a separate per-domain
dict that receives the same insertions and deletions as the main dict, so it
lists a domain's entities in the main dict's order; this filters the main
dict. -/
def domainEntityIds (sm : StateMachine) (domain : String) : List String :=
  (sm.states.filter (·.2.domain == domain)).map (·.1)

/-- `States.domain_states(domain)` -/
def domainStates (sm : StateMachine) (domain : String) : List State :=
  (sm.states.filter (·.2.domain == domain)).map (·.2)

/-- `Context(id=ulid_at_time(timestamp))` (or `Context()` in `Event`): a
new ULID. Its value is random upstream, so HALean names the n-th fresh one
`ulid:n`; the differential test renames HA's ULIDs the same way, in the order
they first appear. -/
def freshContext (sm : StateMachine) : Context × StateMachine :=
  ({ id := s!"ulid:{sm.freshCount}" }, { sm with freshCount := sm.freshCount + 1 })

/-- `domain_filter`: `None`, a `str`, or an iterable of `str`. -/
inductive DomainFilter where
  | all
  | one (domain : String)
  | many (domains : List String)

def checkAscii (what s : String) : Except SMError Unit :=
  if isAscii s then pure () else throw (.unsupported s!"non-ASCII {what} (Python's str.lower() is Unicode-aware): {s}")

/-- `StateMachine.async_entity_ids`: a `str` filter is lower-cased, the
domains of an iterable are not. -/
def asyncEntityIds (sm : StateMachine) : DomainFilter → Except SMError (List String)
  | .all => pure (sm.states.map (·.1))
  | .one d => do checkAscii "domain" d; pure (sm.domainEntityIds (lowerAscii d))
  | .many ds => pure (ds.flatMap sm.domainEntityIds)

/-- `StateMachine.async_entity_ids_count` -/
def asyncEntityIdsCount (sm : StateMachine) : DomainFilter → Except SMError Nat
  | .all => pure sm.states.length
  | .one d => do checkAscii "domain" d; pure (sm.domainEntityIds (lowerAscii d)).length
  | .many ds => pure ((ds.map fun d => (sm.domainEntityIds d).length).foldl (· + ·) 0)

/-- `StateMachine.async_all` -/
def asyncAll (sm : StateMachine) : DomainFilter → Except SMError (List State)
  | .all => pure (sm.states.map (·.2))
  | .one d => do checkAscii "domain" d; pure (sm.domainStates (lowerAscii d))
  | .many ds => pure (ds.flatMap sm.domainStates)

/-- `StateMachine.get`: the id as given, then lower-cased. -/
def get (sm : StateMachine) (entityId : String) : Except SMError (Option State) := do
  checkAscii "entity_id" entityId
  pure ((sm.lookup entityId).orElse fun _ => sm.lookup (lowerAscii entityId))

/-- `StateMachine.is_state` -/
def isState (sm : StateMachine) (entityId state : String) : Except SMError Bool := do
  pure (match ← sm.get entityId with
    | some s => s.state == state
    | none => false)

/-- `StateMachine.async_remove`. Without a context, the `state_changed`
event makes a fresh one (`Event.__init__`); `now` is its `time.time()`. -/
def asyncRemove (sm : StateMachine) (entityId : String) (context : Option Context) (now : Int) :
    Except SMError (Bool × StateMachine × List SMEvent) := do
  checkAscii "entity_id" entityId
  let entityId := lowerAscii entityId
  let old := sm.lookup entityId
  let sm := { sm with states := delItem sm.states entityId,
                      reservations := sm.reservations.filter (· != entityId) }
  match old with
  | none => pure (false, sm, [])
  | some o =>
    let (ctx, sm) := match context with
      | some c => (c, sm)
      | none => sm.freshContext
    pure (true, sm, [.stateChanged entityId (some o) none ctx now])

/-- `StateMachine.async_reserve` (the id is not lower-cased upstream). -/
def asyncReserve (sm : StateMachine) (entityId : String) : Except SMError StateMachine :=
  if (sm.lookup entityId).isSome || sm.reservations.contains entityId then
    throw (.homeAssistant "async_reserve must not be called once the state is in the state machine.")
  else pure { sm with reservations := sm.reservations ++ [entityId] }

/-- `StateMachine.async_available` -/
def asyncAvailable (sm : StateMachine) (entityId : String) : Except SMError Bool := do
  checkAscii "entity_id" entityId
  let e := lowerAscii entityId
  pure ((sm.lookup e).isNone && !sm.reservations.contains e)

/-- `old_state.attributes == attributes`: Python `==` between a dict and the
new mapping (or `None`, which is never equal). -/
def attrsEq (old : Json) (new : Option Json) : Bool :=
  match new with
  | some n => pyEq (Value.ofJson old) (Value.ofJson n)
  | none => false

/-- `StateMachine.async_set_internal`. `entityId` must already be lower case
(the caller's job upstream too). `timestamp` is in microseconds.

* Same state (and no `force_update`) and equal attributes: the existing
  state object is mutated, only `last_reported` changes, and
  `state_reported` fires with that same object.
* Otherwise a new `State` replaces the old one and `state_changed` fires.
  `last_changed` is kept when only the attributes changed; equal attributes
  keep the old attribute object (so `{"a": 1}` stays when `{"a": 1.0}` is
  set). A new state longer than 255 characters becomes `unknown`.
* An invalid entity id raises only for a new entity. -/
def asyncSetInternal (sm : StateMachine) (entityId newState : String) (attributes : Option Json)
    (forceUpdate : Bool) (context : Option Context) (timestamp : Int) :
    Except SMError (StateMachine × List SMEvent) := do
  let old := sm.lookup entityId
  let sameState := match old with
    | some o => o.state == newState && !forceUpdate
    | none => false
  let sameAttr := match old with
    | some o => attrsEq o.attributes attributes
    | none => false
  let lastChanged := match old with
    | some o => if sameState then some o.lastChanged else none
    | none => none
  let now := timestamp
  let (ctx, sm) := match context with
    | some c => (c, sm)
    | none => sm.freshContext
  match old with
  | some o =>
    if sameState && sameAttr then
      let o' := { o with lastReported := now }
      return ({ sm with states := setItem sm.states entityId o' },
              [.stateReported entityId now o.lastReported o' ctx now])
  | none => pure ()
  let attributes := match old with
    | some o => if sameAttr then some o.attributes else attributes
    | none => attributes
  let newState :=
    if !sameState && newState.length > MAX_LENGTH_STATE_STATE then STATE_UNKNOWN else newState
  let state ← State.new entityId newState attributes lastChanged (some now) (some now) ctx
    old.isNone now
  return ({ sm with states := setItem sm.states entityId state },
          [.stateChanged entityId old (some state) ctx now])

/-- `validate_state` -/
def validateState (state : String) : Except SMError Unit :=
  if state.length > MAX_LENGTH_STATE_STATE then
    throw (.invalidState s!"Invalid state with length {state.length}. State max length is 255 characters.")
  else pure ()

/-- `StateMachine.async_set`: `str(new_state)`, `validate_state`, then
`async_set_internal` with the lower-cased id and `attributes or {}`.
`timestamp` is `timestamp or time.time()`, chosen by the caller. -/
def asyncSet (sm : StateMachine) (entityId : String) (newState : Json) (attributes : Option Json)
    (forceUpdate : Bool) (context : Option Context) (timestamp : Int) :
    Except SMError (StateMachine × List SMEvent) := do
  checkAscii "entity_id" entityId
  let state ← match pyStr (Value.ofJson newState) with
    | .ok s => pure s
    | .error e => throw (.unsupported s!"str() of the new state: {e}")
  validateState state
  let attributes := match attributes with
    | some a@(.obj _) => some a
    | _ => some (Json.mkObj [])
  sm.asyncSetInternal (lowerAscii entityId) state attributes forceUpdate context timestamp

end StateMachine
end HALean.Core
