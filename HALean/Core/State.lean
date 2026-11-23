/-
  `homeassistant.core.State` and `homeassistant.core.Context`, translated from
  the pinned upstream release (see `manifest.yaml`).

  This is the full state object of HA's state machine. The simpler
  `HALean.EntityState` in `HALean/Core/Types.lean` stays what the automation
  engine works on; `State.toEntityState` converts.

  Times are microseconds since the Unix epoch (UTC). Upstream keeps a
  `datetime` and, for `last_updated`, the float `timestamp` it was made from;
  the shell always passes `timestamp = us / 1e6`, so both are determined by
  the microseconds (`tsFloat`).

  Python semantics reused from the template service (`HALean.Template.Value`):
  `==` on attribute values (`1 == 1.0 == True`), `repr(float)`, `str()`,
  truthiness and `datetime.isoformat`.
-/
import HALean.Core.Types
import HALean.Template.Value
open Lean HALean.Template

namespace HALean.Core

/-- `homeassistant.const.MAX_LENGTH_STATE_STATE` -/
def MAX_LENGTH_STATE_STATE : Nat := 255

/-- `homeassistant.const.ATTR_FRIENDLY_NAME` -/
def ATTR_FRIENDLY_NAME : String := "friendly_name"

/-- `homeassistant.core.Context`. Ids are opaque strings: upstream makes them
with `ulid_now()` / `ulid_at_time()`, which are random. The state machine
takes contexts as inputs or makes a fresh one (`StateMachine.freshContext`).
`origin_event` and `_cache` carry no data and are not modelled. -/
structure Context where
  id : String
  userId : Option String := none
  parentId : Option String := none
  deriving Repr, BEq, Inhabited

/-- `Context._as_dict` -/
def Context.asDict (c : Context) : Json :=
  Json.mkObj [("id", .str c.id), ("parent_id", toJson c.parentId), ("user_id", toJson c.userId)]

/-! ## Entity ids -/

/-- `[\da-z_]` for ASCII input (callers reject non-ASCII ids, where Python's
`\d` and `str.lower()` are Unicode-aware). -/
def isSlugChar (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'z') || c == '_'

/-- `(?!_)[\da-z_]+(?<!_)` -/
def validSlug (cs : List Char) : Bool :=
  !cs.isEmpty && cs.all isSlugChar && cs.head? != some '_' && cs.getLast? != some '_'

def hasDoubleUnderscore : List Char → Bool
  | '_' :: '_' :: _ => true
  | _ :: r => hasDoubleUnderscore r
  | [] => false

/-- Split at the first `.`: `str.partition(".")` without the separator flag. -/
def partitionDot (cs : List Char) : List Char × Option (List Char) :=
  match cs.span (· != '.') with
  | (d, _ :: rest) => (d, some rest)
  | (d, []) => (d, none)

/-- `valid_entity_id` on the id without its final newline: no `__` and a
slug, a dot, a slug. -/
def entityIdBody (cs : List Char) : Bool :=
  !hasDoubleUnderscore cs &&
  match partitionDot cs with
  | (d, some o) => validSlug d && validSlug o
  | _ => false

/-- `homeassistant.core.valid_entity_id`:
`VALID_ENTITY_ID.match(entity_id)` with
`^(?!.+__)(?!_)[\da-z_]+(?<!_)\.(?!_)[\da-z_]+(?<!_)$`.
`$` also matches before one trailing newline, so `"light.x\n"` is valid
upstream and here. `(?!.+__)` rules out `__` anywhere after the first
character (the first one cannot be `_` anyway). ASCII input only. -/
def validEntityId (entityId : String) : Bool :=
  let cs := entityId.toList
  entityIdBody (if cs.getLast? == some '\n' then cs.dropLast else cs)

/-- `homeassistant.core.valid_domain`: `VALID_DOMAIN.match(domain)` with
`^(?!.+__)(?!_)[\da-z_]+(?<!_)$` (`$` also before one final newline).
ASCII input only. -/
def validDomain (domain : String) : Bool :=
  let cs := domain.toList
  let cs := if cs.getLast? == some '\n' then cs.dropLast else cs
  !hasDoubleUnderscore cs && validSlug cs

/-- `homeassistant.core.split_entity_id` (`ValueError` → `none`). -/
def splitEntityId (entityId : String) : Option (String × String) :=
  match partitionDot entityId.toList with
  | (d, some o) => if d.isEmpty || o.isEmpty then none else some (String.ofList d, String.ofList o)
  | _ => none

/-- Python's `str.lower()` on ASCII text. -/
def lowerAscii (s : String) : String := s.map Char.toLower

def isAscii (s : String) : Bool := s.toList.all fun c => c.toNat < 128

/-! ## State -/

/-- `homeassistant.core.State` (without `state_info`, which only entities
pass). `attributes` is a JSON object (`ReadOnlyDict`). -/
structure State where
  entityId : String
  state : String
  attributes : Json
  lastChanged : Int
  lastReported : Int
  lastUpdated : Int
  context : Context
  deriving Repr, BEq, Inhabited

/-- `State.domain` (set from `split_entity_id` in `__init__`). -/
def State.domain (s : State) : String := ((splitEntityId s.entityId).map (·.1)).getD ""

/-- `State.object_id` -/
def State.objectId (s : State) : String := ((splitEntityId s.entityId).map (·.2)).getD ""

/-- Errors the state machine raises, by upstream exception class. -/
inductive SMError where
  /-- `InvalidEntityFormatError` -/
  | invalidEntityFormat (msg : String)
  /-- `InvalidStateError` -/
  | invalidState (msg : String)
  /-- `HomeAssistantError` -/
  | homeAssistant (msg : String)
  /-- not translated: rejected instead of guessed -/
  | unsupported (msg : String)
  deriving Repr, BEq

/-- `State.__init__`, for the arguments the state machine passes.
`last_reported or utcnow()`: the state machine always passes a time, so
`now` is only the fallback. `attributes or {}` → a `ReadOnlyDict`.
`expire()` only replaces the context by a copy with the same fields, so it
is the identity here. -/
def State.new (entityId state : String) (attributes : Option Json)
    (lastChanged lastReported lastUpdated : Option Int) (context : Context)
    (validateEntityId : Bool) (now : Int) : Except SMError State := do
  if validateEntityId && !validEntityId entityId then
    throw (.invalidEntityFormat s!"Invalid entity id encountered: {entityId}. Format should be <domain>.<object_id>")
  if (splitEntityId entityId).isNone then
    throw (.invalidEntityFormat s!"Invalid entity ID {entityId}")  -- ValueError upstream; unreachable after validation
  let attrs := match attributes with
    | some a@(.obj _) => a
    | _ => Json.mkObj []
  let lastReported := lastReported.getD now
  let lastUpdated := lastUpdated.getD lastReported
  let lastChanged := lastChanged.getD lastUpdated
  pure { entityId, state, attributes := attrs, lastChanged, lastReported, lastUpdated, context }

/-- `State.name`: `attributes.get(ATTR_FRIENDLY_NAME) or object_id.replace("_", " ")`.
A truthy friendly name of any type is returned as is. -/
def State.name (s : State) : Json :=
  match s.attributes.getObjVal? ATTR_FRIENDLY_NAME with
  | .ok v => if truthy (Value.ofJson v) then v else .str (s.objectId.replace "_" " ")
  | .error _ => .str (s.objectId.replace "_" " ")

/-- `datetime.timestamp()` of a UTC instant in microseconds, i.e. the
correctly rounded `us / 10**6`. -/
def tsFloat (us : Int) : Float := ratToFloat (us < 0) us.natAbs 1000000

def tsJson (us : Int) : Json :=
  match floatToJson (tsFloat us) with
  | .ok j => j
  | .error _ => .null

/-- `State.last_changed_timestamp` (cached as `last_updated_timestamp` when the
two datetimes are equal, which gives the same float). -/
def State.lastChangedTimestamp (s : State) : Float := tsFloat s.lastChanged
/-- `State.last_updated_timestamp` -/
def State.lastUpdatedTimestamp (s : State) : Float := tsFloat s.lastUpdated
/-- `State.last_reported_timestamp` (kept up to date by `async_set_internal`
when it mutates `last_reported`). -/
def State.lastReportedTimestamp (s : State) : Float := tsFloat s.lastReported

/-- `dt_util.utc_from_timestamp(...).isoformat()` -/
def isoUtc (us : Int) : String := isoformat us (some 0)

/-- `State._as_dict` (what `as_dict()` returns, freshly computed; see the
README for the upstream cache that can make `as_dict()` stale). -/
def State.asDict (s : State) : Json :=
  Json.mkObj [
    ("entity_id", .str s.entityId),
    ("state", .str s.state),
    ("attributes", s.attributes),
    ("last_changed", .str (isoUtc s.lastChanged)),
    ("last_reported", .str (isoUtc s.lastReported)),
    ("last_updated", .str (isoUtc s.lastUpdated)),
    ("context", s.context.asDict)]

/-- `State.as_compressed_state`: the context as a bare id when it has no
parent and no user; `lu` only when it differs from `lc`. -/
def State.asCompressedState (s : State) : Json :=
  let ctx : Json :=
    if s.context.parentId.isNone && s.context.userId.isNone then .str s.context.id
    else s.context.asDict
  let lc := s.lastChangedTimestamp
  let base := [("s", Json.str s.state), ("a", s.attributes), ("c", ctx), ("lc", tsJson s.lastChanged)]
  Json.mkObj (if lc != s.lastUpdatedTimestamp then base ++ [("lu", tsJson s.lastUpdated)] else base)

/-- The automation engine's view of a state. -/
def State.toEntityState (s : State) : EntityState :=
  { entityId := s.entityId, state := s.state, attributes := s.attributes,
    lastChanged := (s.lastChanged / 1000).toNat,
    lastChangedUs := some s.lastChanged, lastUpdatedUs := some s.lastUpdated }

end HALean.Core
