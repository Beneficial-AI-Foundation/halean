/-
  Rendering. Translated from:
    * `helpers/template/__init__.py`  – `Template.async_render`, `_parse_result`,
      `_cached_parse_result`, `render_complex`, `is_template_string`
    * `helpers/template/states.py`    – `AllStates`, `DomainStates`,
      `TemplateStateBase.__getitem__`, `_get_state_if_valid`
    * `helpers/template/extensions/state.py` – `is_state`, `state_attr`,
      `is_state_attr`, `has_value`
    * `helpers/template/extensions/type_cast.py` – `float`, `int`, `is_number`
    * `helpers/template/extensions/math.py` – `round` (`forgiving_round`)
    * `helpers/template/extensions/functional.py` – `iif`
    * `helpers/template/extensions/math.py` – `min`/`max` (`min_max_from_filter`)
    * `helpers/template/extensions/state.py` – `expand`
    * `core.py` – `StateMachine.get` (case-insensitive fallback, for `expand`)
    * `helpers/template/helpers.py` – `forgiving_boolean`, `result_as_boolean`
  and from Jinja2 itself (the evaluator, builtin filters and tests, sandboxed
  `getattr`/`getitem`, `Undefined`).

  Every name, filter and test a template uses is checked at load time
  (`check`); anything outside the supported set is rejected, never guessed.
-/
import HALean.Template.Syntax
open Lean

namespace HALean.Template

/-- What a template can see. -/
structure Ctx where
  states : States
  /-- Variables passed to the render (`trigger`, ...), innermost first. -/
  vars : List (String × Value) := []
  /-- The clock, for `now()` (the engine's time, never a real clock). -/
  now : Instant := { utc := 0 }

inductive Signal where
  | normal | brk | cont
  deriving BEq, Inhabited

/-- `RenderInfo`: what a render read, so the template tracker knows when to
render again (`helpers/template/render_info.py`). -/
structure RInfo where
  entities : List String := []
  domains : List String := []
  domainsLifecycle : List String := []
  allStates : Bool := false
  allStatesLifecycle : Bool := false
  hasTime : Bool := false
  exception : Bool := false
  isStatic : Bool := false
  deriving Repr, Inhabited

def ALL_STATES_RATE_LIMIT : Nat := 60
def DOMAIN_STATES_RATE_LIMIT : Nat := 1

/-- `RenderInfo._freeze`: the rate limit in seconds. -/
def RInfo.rateLimit (i : RInfo) : Option Nat :=
  if i.isStatic then none
  else if i.allStates || i.exception then some ALL_STATES_RATE_LIMIT
  else if !i.domains.isEmpty || !i.domainsLifecycle.isEmpty then some DOMAIN_STATES_RATE_LIMIT
  else none

def domainOf (eid : String) : String := (eid.splitOn ".").headD ""

/-- `RenderInfo.filter` after `_freeze`. -/
def RInfo.filter (i : RInfo) (eid : String) : Bool :=
  if i.isStatic || i.exception || i.allStates then true
  else if !i.domains.isEmpty then i.domains.contains (domainOf eid) || i.entities.contains eid
  else i.entities.contains eid

/-- `RenderInfo.filter_lifecycle` after `_freeze`. -/
def RInfo.filterLifecycle (i : RInfo) (eid : String) : Bool :=
  if i.isStatic || i.exception || i.allStatesLifecycle then true
  else i.domainsLifecycle.contains (domainOf eid)

/-- Whether the tracker's state listeners (`_render_infos_to_track_states`)
deliver a change of `eid` at all. While a rate-limit timer is pending the
domain and all-states listeners are suppressed. -/
def RInfo.listens (i : RInfo) (eid : String) (rateLimited : Bool) : Bool :=
  if rateLimited then i.entities.contains eid
  else i.allStates || i.allStatesLifecycle || i.entities.contains eid
    || i.domains.contains (domainOf eid) || i.domainsLifecycle.contains (domainOf eid)

structure RS where
  info : RInfo := {}
  /-- `namespace()` objects. -/
  heap : Array (List (String × Value)) := #[]
  out : String := ""
  /-- Loop iterations and calls, to bound runaway templates. -/
  steps : Nat := 0

abbrev R := ExceptT String (StateM RS)

/-- HA's `MAX_TEMPLATE_OUTPUT` -/
def MAX_TEMPLATE_OUTPUT : Nat := 256 * 1024

/-- Upper bound on loop iterations per render. HA has a render timeout
instead; a template hitting this would be rejected by HA's own checks. -/
def MAX_STEPS : Nat := 1000000

def collect (eid : String) : R Unit :=
  modify fun s => if s.info.entities.contains eid then s
    else { s with info := { s.info with entities := s.info.entities ++ [eid] } }

def collectDomain (d : String) (lifecycle : Bool) : R Unit :=
  modify fun s => if lifecycle then
      { s with info := { s.info with domainsLifecycle := s.info.domainsLifecycle ++ [d] } }
    else { s with info := { s.info with domains := s.info.domains ++ [d] } }

def collectAll (lifecycle : Bool) : R Unit :=
  modify fun s => if lifecycle then { s with info := { s.info with allStatesLifecycle := true } }
    else { s with info := { s.info with allStates := true } }

def collectTime : R Unit := modify fun s => { s with info := { s.info with hasTime := true } }

def tick : R Unit := do
  let s ← get
  if s.steps ≥ MAX_STEPS then throw "template exceeded HALean's step budget"
  set { s with steps := s.steps + 1 }

/-! ## Names -/

/-- Globals HALean implements, with HA's semantics. -/
def GLOBALS : List String :=
  ["states", "is_state", "state_attr", "is_state_attr", "has_value", "float", "int", "bool",
   "is_number", "iif", "namespace", "dict", "range",
   "now", "utcnow", "today_at", "as_timestamp", "as_datetime", "as_local", "timedelta",
   "timestamp_local", "timestamp_utc", "timestamp_custom",
   "min", "max", "expand"]

/-- Functions whose result depends on the clock. HA re-renders trigger
templates using them on a timer, which HALean does not model yet, so they
are rejected in trigger templates. -/
def TIME_NAMES : List String := ["now", "utcnow", "today_at"]

def FILTERS : List String :=
  ["float", "int", "bool", "is_number", "iif", "has_value", "state_attr", "states", "round",
   "default", "d", "lower", "upper", "capitalize", "title", "trim", "replace", "length", "count",
   "first", "last", "join", "list", "string", "abs", "sum",
   "map", "select", "reject", "selectattr", "rejectattr", "reverse",
   "as_timestamp", "as_datetime", "as_local", "timestamp_local", "timestamp_utc", "timestamp_custom",
   "today_at",
   "sort", "min", "max", "unique", "expand"]

def TESTS : List String :=
  ["defined", "undefined", "none", "number", "string", "boolean", "integer", "float",
   "mapping", "sequence", "iterable", "true", "false", "eq", "equalto", "==", "ne", "!=",
   "lt", "<", "lessthan", "le", "<=", "gt", ">", "greaterthan", "ge", ">=", "in",
   "divisibleby", "even", "odd", "is_state", "is_state_attr", "has_value", "is_number"]

/-- `[\da-z_]+` without a leading/trailing `_` and without `__`. -/
def validSlug (s : String) : Bool :=
  !s.isEmpty && s.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'z') || c == '_')
    && !s.startsWith "_" && !s.endsWith "_" && (s.splitOn "__").length == 1

/-- `homeassistant.core.valid_domain` -/
def validDomain (s : String) : Bool := validSlug s

/-- `homeassistant.core.valid_entity_id` -/
def validEntityId (s : String) : Bool :=
  match s.splitOn "." with
  | [d, o] => validSlug d && validSlug o
  | _ => false

/-! ## Errors and conversions -/

def undefErr (v : Value) : R α :=
  match v with
  | .undef n => throw s!"UndefinedError: {n} is undefined"
  | _ => throw "UndefinedError"

def strOf (v : Value) : R String :=
  match pyStr v with
  | .ok s => pure s
  | .error e => throw e

/-- `float(x)`: `none` = ValueError/TypeError (the caller decides). -/
def toFloat? (v : Value) : R (Option Float) :=
  match v with
  | .float f => pure (some f)
  | .int i => pure (some (intToFloat i))
  | .bool b => pure (some (if b then 1.0 else 0.0))
  | .str s => pure (parseFloatStr s)
  | .undef _ => undefErr v
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | _ => pure none

def noDefault (fn : String) (v : Value) : R α := do
  let s := (pyStr v).toOption.getD (typeName v)
  throw s!"Template error: {fn} got invalid input '{s}' but no default was specified"

/-- `cv.boolean` (`none` = `vol.Invalid`). -/
def cvBoolean (v : Value) : Option Bool :=
  match v with
  | .bool b => some b
  | .str s =>
    let s := s.trim.toLower
    if ["1", "true", "yes", "on", "enable"].contains s then some true
    else if ["0", "false", "no", "off", "disable"].contains s then some false
    else none
  | .int i => some (i != 0)
  | .float f => some (f != 0)
  | _ => none

/-- `result_as_boolean` -/
def resultAsBoolean (v : Value) : Bool :=
  match v with
  | .none => false
  | v => (cvBoolean v).getD false

/-- `jinja2.filters.do_int` with `base=10`; `none` = the default. -/
def doInt (v : Value) : R (Option Int) := do
  match v with
  | .int i => return some i
  | .bool b => return some (if b then 1 else 0)
  | .float f =>
    if f.isInf then throw "OverflowError: cannot convert float infinity to integer"
    return floatToInt? f
  | .str s =>
    match parseIntStr s with
    | some i => return some i
    | none => return (parseFloatStr s).bind floatToInt?
  | .undef _ => undefErr v
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | _ => return none

/-- Python's `round(x, n)` on floats: correctly rounded, half to even on the
exact binary value (so `round(2.675, 2) == 2.67`). -/
def pyRound (f : Float) (n : Int) : Float :=
  if !Float.isFinite' f then f else
  let (neg, num, den) := floatFrac f
  -- q = round_half_even(num/den * 10^n)
  let (nn, dd) := if n ≥ 0 then (num * 10 ^ n.toNat, den) else (num, den * 10 ^ (-n).toNat)
  let q0 := nn / dd
  let r := nn % dd
  let q := if 2 * r > dd || (2 * r == dd && q0 % 2 == 1) then q0 + 1 else q0
  if n ≥ 0 then ratToFloat neg q (10 ^ n.toNat) else ratToFloat neg (q * 10 ^ (-n).toNat) 1

/-- `math.floor` / `math.ceil` of a float, as an int. -/
def floorF (f : Float) : Option Int := do
  let i ← floatToInt? f
  if intToFloat i > f then some (i - 1) else some i
def ceilF (f : Float) : Option Int := do
  let i ← floatToInt? f
  if intToFloat i < f then some (i + 1) else some i

/-! ## Attribute and item access (sandboxed, as Jinja's `getattr`/`getitem`) -/

def lookupKV (kvs : List (Value × Value)) (k : Value) : Option Value :=
  (kvs.find? (fun (k', _) => pyEq k' k)).map (·.2)

def STATE_OPAQUE : List String :=
  ["last_reported", "context", "state_with_unit",
   "format_state", "as_dict", "as_compressed_state", "json_fragment", "expire", "last_changed_timestamp",
   "last_updated_timestamp", "last_reported_timestamp", "as_dict_json", "as_compressed_state_json"]

def COLLECTABLE_STATE_ATTRIBUTES : List String :=
  ["state", "attributes", "last_changed", "last_updated", "context", "domain", "object_id", "name",
   "last_reported"]

/-- `TemplateStateBase` attributes (`__getitem__` + properties). -/
def stateAttr (s : EntityState) (collectIt : Bool) (a : String) : R Value := do
  if collectIt && COLLECTABLE_STATE_ATTRIBUTES.contains a then collect s.entityId
  match a with
  | "state" => pure (.str s.state)
  | "entity_id" => pure (.str s.entityId)
  | "attributes" => pure (Value.ofJson s.attributes)
  | "domain" => pure (.str s.domain)
  | "object_id" => pure (.str ((s.entityId.splitOn ".").getD 1 ""))
  | "last_changed" => pure (.datetime (s.lastChangedUs.getD (s.lastChanged * 1000)) (some 0))
  | "last_updated" => pure (match s.lastUpdatedUs with
      | some u => .datetime u (some 0)
      | none => .opaque "state.last_updated")
  | "name" =>
    match s.attr? "friendly_name" with
    | some j =>
      let v := Value.ofJson j
      if truthy v then pure v
      else pure (.str (((s.entityId.splitOn ".").getD 1 "").replace "_" " "))
    | none => pure (.str (((s.entityId.splitOn ".").getD 1 "").replace "_" " "))
  | a => if STATE_OPAQUE.contains a then pure (.opaque s!"state.{a}")
         else pure (.undef s!"'TemplateState object' has no attribute '{a}'")

/-- `_get_state_if_valid` -/
def stateIfValid (ctx : Ctx) (eid : String) : R Value :=
  match ctx.states.get? eid with
  | some s => pure (.state s true)
  | none =>
    if validEntityId eid then do collect eid; pure .none
    else throw s!"Invalid entity ID '{eid}'"

def RESERVED_NAMES : List String :=
  ["contextfunction", "evalcontextfunction", "environmentfunction", "jinja_pass_arg"]

def STR_METHODS : List String :=
  ["lower", "upper", "strip", "lstrip", "rstrip", "split", "startswith", "endswith", "replace",
   "title", "capitalize"]

def getattrV (ctx : Ctx) (v : Value) (a : String) : R Value := do
  if a.startsWith "_" then throw s!"access to attribute '{a}' is unsafe"
  match v with
  | .undef _ => undefErr v
  | .allStates =>
    if a.contains '.' then stateIfValid ctx a
    else if RESERVED_NAMES.contains a then pure .none
    else if !validDomain a then throw s!"Invalid domain name '{a}'"
    else pure (.domain a)
  | .domain d => stateIfValid ctx s!"{d}.{a}"
  | .state s c => stateAttr s c a
  | .dict kvs =>
    if ["items", "keys", "values", "get"].contains a then pure (.func s!"dict.{a}" (some v))
    else pure ((lookupKV kvs (.str a)).getD (.undef s!"'dict object' has no attribute '{a}'"))
  | .str _ =>
    if STR_METHODS.contains a then pure (.func s!"str.{a}" (some v))
    else throw s!"str.{a} is not supported by HALean"
  | .ns id => do
    let fields := (← get).heap.getD id []
    pure ((fields.find? (·.1 == a)).map (·.2) |>.getD (.undef s!"'Namespace' has no attribute '{a}'"))
  | .none => pure (.undef s!"'None' has no attribute '{a}'")
  | .pyobj c fs => pure ((fs.find? (·.1 == a)).map (·.2) |>.getD (.undef s!"'{c}' has no attribute '{a}'"))
  | .datetime us off =>
    let c := toCivil (wallOf us off)
    match a with
    | "year" => pure (.int c.year)
    | "month" => pure (.int c.month)
    | "day" => pure (.int c.day)
    | "hour" => pure (.int c.hour)
    | "minute" => pure (.int c.minute)
    | "second" => pure (.int c.second)
    | "microsecond" => pure (.int c.micro)
    | "weekday" | "isoweekday" | "timestamp" | "isoformat" | "strftime" | "replace" =>
      pure (.func s!"datetime.{a}" (some v))
    | _ => throw s!"datetime.{a} is not supported by HALean"
  | .timedelta us =>
    let (d, sec, u) := tdParts us
    match a with
    | "days" => pure (.int d)
    | "seconds" => pure (.int sec)
    | "microseconds" => pure (.int u)
    | "total_seconds" => pure (.func "timedelta.total_seconds" (some v))
    | _ => throw s!"timedelta.{a} is not supported by HALean"
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | v => throw s!"attribute '{a}' of {typeName v} is not supported by HALean"

def seqIndex (xs : List α) (i : Int) : Option α :=
  let n : Int := xs.length
  let j := if i < 0 then i + n else i
  if j < 0 || j ≥ n then none else xs[j.toNat]?

/-- Public attributes of `int`, `float` and `bool` (CPython 3.14). -/
def NUMBER_ATTRS : List String :=
  ["as_integer_ratio", "bit_count", "bit_length", "conjugate", "denominator", "from_bytes",
   "from_number", "fromhex", "hex", "imag", "is_integer", "numerator", "real", "to_bytes"]

def getitemV (ctx : Ctx) (v : Value) (k : Value) : R Value := do
  match v with
  | .undef _ => undefErr v
  | .dict kvs =>
    match lookupKV kvs k with
    | some x => pure x
    | none => match k with
      | .str a => if ["items", "keys", "values", "get"].contains a then getattrV ctx v a
                  else pure (.undef s!"'dict object' has no attribute '{a}'")
      | _ => pure (.undef "'dict object' has no such item")
  | .list xs | .tuple xs =>
    match k with
    | .int i => pure ((seqIndex xs i).getD (.undef "list index out of range"))
    | .bool b => pure ((seqIndex xs (if b then 1 else 0)).getD (.undef "list index out of range"))
    | .str a => throw s!"attribute '{a}' of {typeName v} is not supported by HALean"
    | _ => pure (.undef "invalid list index")
  | .str s =>
    match k with
    | .int i => pure ((seqIndex s.toList i).map (fun c => Value.str (toString c)) |>.getD (.undef "string index out of range"))
    | .str a => getattrV ctx v a
    | _ => pure (.undef "invalid string index")
  | .state .. | .allStates | .domain _ | .ns _ | .pyobj _ _ =>
    match k with
    | .str a => getattrV ctx v a
    | _ => pure (.undef "invalid key")
  | .none => pure (.undef "'None' is not subscriptable")
  | .int _ | .float _ | .bool _ =>
    -- `obj[k]` raises TypeError, then the sandbox tries `getattr(obj, k)`
    match k with
    | .str a =>
      if a.startsWith "_" || NUMBER_ATTRS.contains a then
        throw s!"attribute '{a}' of {typeName v} is not supported by HALean"
      else pure (.undef s!"'{typeName v} object' has no attribute '{a}'")
    | _ => pure (.undef s!"'{typeName v}' object is not subscriptable")
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | v => throw s!"indexing {typeName v} is not supported by HALean"

/-- Python slice semantics (`xs[a:b:c]`). -/
def sliceList (xs : List α) (a b c : Option Int) : Except String (List α) := do
  let n : Int := xs.length
  let step := c.getD 1
  if step == 0 then throw "slice step cannot be zero"
  let norm (i : Int) (lo hi : Int) : Int :=
    let i := if i < 0 then i + n else i
    if i < lo then lo else if i > hi then hi else i
  if step > 0 then
    let s := match a with | some i => norm i 0 n | none => 0
    let e := match b with | some i => norm i 0 n | none => n
    let idx := ((List.range ((e - s).toNat)).map Int.ofNat).filterMap fun k =>
      if (k : Int) % step == 0 then some (s + k) else none
    return idx.filterMap fun i => xs[i.toNat]?
  else
    let s := match a with | some i => norm i (-1) (n - 1) | none => n - 1
    let e := match b with | some i => norm i (-1) (n - 1) | none => -1
    let cnt := (s - e).toNat
    let idx := ((List.range cnt).map Int.ofNat).filterMap fun k =>
      if (k : Int) % (-step) == 0 then some (s - k) else none
    return idx.filterMap fun i => if i < 0 then none else xs[i.toNat]?

/-- `hass.states.async_all(domain)` / all states, in insertion order. -/
def statesOf (ctx : Ctx) (dom : Option String) : List Value :=
  (ctx.states.filter fun (_, s) => match dom with
    | some d => s.domain == d
    | none => true).map fun (_, s) => .state s false

/-- Python iteration. -/
def iterV (ctx : Ctx) (v : Value) : R (List Value) :=
  match v with
  | .range a b c => pure ((rangeItems a b c).map Value.int)
  | .gen _ xs => pure xs
  | .domain d => do collectDomain d false; pure (statesOf ctx (some d))
  | .allStates => do collectAll false; pure (statesOf ctx none)
  | .list xs | .tuple xs => pure xs
  | .str s => pure (s.toList.map fun c => .str (toString c))
  | .dict kvs => pure (kvs.map (·.1))
  | .undef _ => pure []
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | v => throw s!"'{typeName v}' object is not iterable"

def lenV (ctx : Ctx) (v : Value) : R Int :=
  match v with
  | .range a b c => pure (rangeItems a b c).length
  | .domain d => do collectDomain d true; pure (statesOf ctx (some d)).length
  | .allStates => do collectAll true; pure ctx.states.length
  | .list xs | .tuple xs => pure xs.length
  | .str s => pure s.length
  | .dict kvs => pure kvs.length
  | .undef _ => pure 0
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | v => throw s!"object of type '{typeName v}' has no len()"

/-- Python `x in c` -/
def containsV (ctx : Ctx) (c x : Value) : R Bool := do
  match c with
  | .str s => match x with
    | .str t => pure ((s.splitOn t).length > 1 || t.isEmpty)
    | _ => throw s!"'in <string>' requires string as left operand, not {typeName x}"
  | .dict kvs => pure ((lookupKV kvs x).isSome)
  | .undef _ => pure false
  | c => do pure ((← iterV ctx c).any (pyEq · x))

/-! ## Dates and times (`helpers/template/extensions/datetime.py`, `util/dt.py`) -/

def Ctx.nowDT (ctx : Ctx) : Value := .datetime (ctx.now.utc * 1000) (some ctx.now.tzOffsetSec)

/-- Round a non-negative fraction half to even. -/
def roundHalfEven (n d : Nat) : Nat :=
  let q := n / d
  let r := n % d
  if 2 * r > d || (2 * r == d && q % 2 == 1) then q + 1 else q

/-- Exact `x * num / den` for an int or float, as microseconds, rounded half
to even (Python's timedelta and fromtimestamp rounding). -/
def scaledUs (x : Value) (num : Nat) (den : Nat := 1) : Option Int :=
  match x with
  | .int i => some (if i < 0 then -((roundHalfEven (i.natAbs * num) den : Nat) : Int) else roundHalfEven (i.natAbs * num) den)
  | .bool b => some (if b then roundHalfEven num den else 0)
  | .float f =>
    if !Float.isFinite' f then none else
    let (neg, n, dd) := floatFrac f
    let q : Int := roundHalfEven (n * num) (dd * den)
    some (if neg then -q else q)
  | _ => none

def checkDate (us : Int) (off : Option Int) : R Value := do
  let c := toCivil (wallOf us off)
  if c.year < 1 || c.year > 9999 then throw "OverflowError: date value out of range"
  pure (.datetime us off)

/-- `datetime.fromtimestamp(value, tz=UTC)`; `none` = TypeError/ValueError. -/
def utcFromTimestamp (v : Value) : Option Value := do
  let us ← match v with
    | .int _ | .bool _ | .float _ => scaledUs v 1000000
    | _ => none
  let c := toCivil us
  if c.year < 1 || c.year > 9999 then none
  pure (.datetime us (some 0))

/-- `dt_util.as_local` (with the engine's current UTC offset). -/
def asLocal (ctx : Ctx) (v : Value) : R Value :=
  match v with
  | .datetime us (some _) => pure (.datetime us (some ctx.now.tzOffsetSec))
  | .datetime wall none => pure (.datetime (wall - ctx.now.tzOffsetSec * US_PER_SEC) (some ctx.now.tzOffsetSec))
  | v => throw s!"as_local expects a datetime, got {typeName v}"

def digitsN (s : String) : Bool := !s.isEmpty && s.all Char.isDigit

/-- `dt_util.parse_datetime`. HA tries the `ciso8601` library first and then
`DATETIME_RE`; HALean translates the regex. A string that only `ciso8601`
might accept (it starts like a date) is an error rather than a guess. -/
def parseDatetime (str : String) : R (Option Value) := do
  let unsupported : R (Option Value) :=
    if str.length ≥ 4 && (str.take 4).toString.all Char.isDigit then
      throw s!"parsing '{str}' as a date/time is not supported by HALean"
    else pure none
  -- (?P<year>\d{4})-(?P<month>\d{1,2})-(?P<day>\d{1,2})[T ]...
  let some sepIdx := (str.toList.findIdx? fun c => c == 'T' || c == ' ') | unsupported
  let datePart := (str.take sepIdx).toString
  let rest := (str.drop (sepIdx + 1)).toString
  let some (y, mo, d) := (match datePart.splitOn "-" with
      | [a, b, c] => if a.length == 4 && digitsN a && b.length ≤ 2 && digitsN b && c.length ≤ 2 && digitsN c
          then some (a.toNat!, b.toNat!, c.toNat!) else none
      | _ => none) | unsupported
  -- time and zone: split off Z / +hh[:mm] / -hh[:mm]
  let (timePart, tz) :=
    if rest.endsWith "Z" then ((rest.dropEnd 1).toString, some "Z")
    else match rest.toList.findIdx? (fun c => c == '+' || c == '-') with
      | some i => ((rest.take i).toString, some (rest.drop i).toString)
      | none => (rest, none)
  let tparts := timePart.splitOn ":"
  let small (x : String) := x.length ≥ 1 && x.length ≤ 2 && digitsN x
  let some (h, mi, sec, micro) := (match tparts with
      | [a, b] => if small a && small b then some (a.toNat!, b.toNat!, 0, 0) else none
      | [a, b, c] =>
        if !(small a && small b) then none else
        match c.splitOn "." with
        | [ss] => if small ss then some (a.toNat!, b.toNat!, ss.toNat!, 0) else none
        | [ss, fr] =>
          if small ss && fr.length ≥ 1 && fr.length ≤ 12 && digitsN fr then
            let f6 := (fr.take 6).toString
            some (a.toNat!, b.toNat!, ss.toNat!, (f6 ++ "".pushn '0' (6 - f6.length)).toNat!)
          else none
        | _ => none
      | _ => none) | unsupported
  let off : Option (Option Int) := match tz with
    | none => some none
    | some "Z" => some (some 0)
    | some z =>
      let sign : Int := if z.startsWith "-" then -1 else 1
      let body := (z.drop 1).toString
      let parse (hh mm : String) : Option (Option Int) :=
        if hh.length == 2 && digitsN hh && (mm.isEmpty || (mm.length == 2 && digitsN mm))
        then some (some (sign * ((hh.toNat! * 3600 + (if mm.isEmpty then 0 else mm.toNat! * 60) : Nat) : Int)))
        else none
      match body.splitOn ":" with
      | [hm] => if hm.length == 4 then parse (hm.take 2).toString (hm.drop 2).toString
                else if hm.length == 2 then parse hm "" else none
      | [hh, mm] => parse hh mm
      | _ => none
  let some off := off | unsupported
  let c : Civil := { year := y, month := mo, day := d, hour := h, minute := mi, second := sec, micro }
  -- `datetime(**kws)` raises ValueError, which every caller catches
  if c.valid.isSome then return none
  let wall := fromCivil c
  pure (some (.datetime (match off with | some o => wall - o * US_PER_SEC | none => wall) off))

/-- `dt_util.parse_time` -/
def parseTime (s : String) : Option (Nat × Nat × Nat) := do
  let parts := s.splitOn ":"
  if parts.length < 2 then none
  let h ← parseIntStr (parts.getD 0 "")
  let m ← parseIntStr (parts.getD 1 "")
  let sec ← if parts.length > 2 then parseIntStr (parts.getD 2 "") else some 0
  if h < 0 || h > 23 || m < 0 || m > 59 || sec < 0 || sec > 59 then none
  pure (h.toNat, m.toNat, sec.toNat)

def timestampOf (v : Value) : R Float :=
  match v with
  | .datetime us (some _) => pure (ratToFloat (us < 0) us.natAbs 1000000)
  | .datetime _ none => throw "timestamps of naive datetimes (system time zone) are not supported by HALean"
  | v => throw s!"{typeName v} has no timestamp"

/-! ## Arithmetic -/

def fracOf (n : Num) : Bool × Nat × Nat :=
  match n with
  | .i v => (v < 0, v.natAbs, 1)
  | .f v => floatFrac v

/-- Exact floor of a/b for finite floats (Python's float `//` and `%`). -/
def floatFloorDivMod (a b : Float) : Float × Float :=
  if !Float.isFinite' a || !Float.isFinite' b then (Float.floor (a / b), a - b * Float.floor (a / b)) else
  let (na, pa, qa) := floatFrac a
  let (nb, pb, qb) := floatFrac b
  -- a/b = (±pa*qb) / (±pb*qa)
  let num : Int := (if na then -(pa : Int) else pa) * qb
  let den : Int := (if nb then -(pb : Int) else pb) * qa
  let q := Int.fdiv num den
  let r : Int := num - q * den  -- a - q*b = r / (qa*qb)
  let modv := ratToFloat (r < 0) r.natAbs (qa * qb)
  -- Python: the remainder takes the sign of b (and -0.0 / 0.0 per sign of b)
  let modv := if modv == 0 then (if nb then -0.0 else 0.0) else modv
  (intToFloat q, modv)

def isOpaqueOrUndef (v : Value) : Bool :=
  match v with | .undef _ | .opaque _ => true | _ => false

def arith (op : String) (a b : Value) : R Value := do
  if let .undef _ := a then undefErr a
  if let .undef _ := b then undefErr b
  if let .opaque w := a then throw s!"{w} values are not supported by HALean"
  if let .opaque w := b then throw s!"{w} values are not supported by HALean"
  let tyErr : R Value := throw s!"unsupported operand type(s) for {op}: '{typeName a}' and '{typeName b}'"
  -- datetime / timedelta arithmetic (Python's rules and rounding)
  let tdScale (us : Int) (x : Value) (divide : Bool) : R Value := do
    match x with
    | .int _ | .bool _ =>
      let k : Int := match x with | .int i => i | .bool b => if b then 1 else 0 | _ => 0
      if divide then
        if k == 0 then throw "ZeroDivisionError: division by zero"
        let q : Int := roundHalfEven us.natAbs k.natAbs
        return .timedelta (if (us < 0) != (k < 0) then -q else q)
      else return .timedelta (us * k)
    | .float f =>
      if !Float.isFinite' f then throw "ValueError: cannot convert float NaN or infinity to integer"
      let (neg, n, d) := floatFrac f
      if divide then
        if n == 0 then throw "ZeroDivisionError: division by zero"
        let q : Int := roundHalfEven (us.natAbs * d) n
        return .timedelta (if (us < 0) != neg then -q else q)
      else
        let q : Int := roundHalfEven (us.natAbs * n) d
        return .timedelta (if (us < 0) != neg then -q else q)
    | _ => tyErr
  match op, a, b with
  | "+", .datetime us off, .timedelta d | "+", .timedelta d, .datetime us off => checkDate (us + d) off
  | "-", .datetime us off, .timedelta d => checkDate (us - d) off
  | "-", .datetime x (some _), .datetime y (some _) => return .timedelta (x - y)
  | "-", .datetime x none, .datetime y none => return .timedelta (x - y)
  | "-", .datetime .., .datetime .. => throw "TypeError: can't subtract offset-naive and offset-aware datetimes"
  | "+", .timedelta x, .timedelta y => return .timedelta (x + y)
  | "-", .timedelta x, .timedelta y => return .timedelta (x - y)
  | "*", .timedelta x, k | "*", k, .timedelta x => tdScale x k false
  | "/", .timedelta x, .timedelta y =>
    if y == 0 then throw "ZeroDivisionError: division by zero"
    return .float (ratToFloat ((x < 0) != (y < 0)) x.natAbs y.natAbs)
  | "/", .timedelta x, k => tdScale x k true
  | "//", .timedelta x, .timedelta y =>
    if y == 0 then throw "ZeroDivisionError: integer division or modulo by zero"
    return .int (Int.fdiv x y)
  | "//", .timedelta x, .int k =>
    if k == 0 then throw "ZeroDivisionError: integer division or modulo by zero"
    return .timedelta (Int.fdiv x k)
  | "%", .timedelta x, .timedelta y =>
    if y == 0 then throw "ZeroDivisionError: integer division or modulo by zero"
    return .timedelta (Int.fmod x y)
  | _, .datetime .., _ | _, _, .datetime .. | _, .timedelta _, _ | _, _, .timedelta _ => tyErr
  | "+", .str x, .str y => return .str (x ++ y)
  | "+", .list x, .list y => return .list (x ++ y)
  | "+", .tuple x, .tuple y => return .tuple (x ++ y)
  | "*", .str s, n | "*", n, .str s =>
    match n with
    | .int k => return .str (String.join (List.replicate k.toNat s))
    | .bool k => return .str (if k then s else "")
    | _ => tyErr
  | "*", .list s, n | "*", n, .list s =>
    match n with
    | .int k => return .list ((List.replicate k.toNat s).flatten)
    | _ => tyErr
  | "%", .str _, _ => throw "string formatting with % is not supported by HALean"
  | _, _, _ =>
  let some x := a.num? | tyErr
  let some y := b.num? | tyErr
  match op, x, y with
  | "+", .i p, .i q => return .int (p + q)
  | "-", .i p, .i q => return .int (p - q)
  | "*", .i p, .i q => return .int (p * q)
  | "/", .i p, .i q =>
    if q == 0 then throw "ZeroDivisionError: division by zero"
    return .float (ratToFloat ((p < 0) != (q < 0)) p.natAbs q.natAbs)
  | "//", .i p, .i q =>
    if q == 0 then throw "ZeroDivisionError: integer division or modulo by zero"
    return .int (Int.fdiv p q)
  | "%", .i p, .i q =>
    if q == 0 then throw "ZeroDivisionError: integer modulo by zero"
    return .int (Int.fmod p q)
  | "**", .i p, .i q =>
    if q ≥ 0 then
      if q > 100000 then throw "exponent too large for HALean" else return .int (p ^ q.toNat)
    else
      if p == 0 then throw "ZeroDivisionError: 0.0 cannot be raised to a negative power"
      return .float (Float.pow (intToFloat p) (intToFloat q))
  | _, _, _ =>
  let p := x.toFloat
  let q := y.toFloat
  match op with
  | "+" => return .float (p + q)
  | "-" => return .float (p - q)
  | "*" => return .float (p * q)
  | "/" => if q == 0 then throw "ZeroDivisionError: float division by zero" else return .float (p / q)
  | "//" => if q == 0 then throw "ZeroDivisionError: float floor division by zero"
            else return .float (floatFloorDivMod p q).1
  | "%" => if q == 0 then throw "ZeroDivisionError: float modulo by zero"
           else return .float (floatFloorDivMod p q).2
  | "**" =>
    if p == 0 && q < 0 then throw "ZeroDivisionError: 0.0 cannot be raised to a negative power"
    if p < 0 && Float.floor q != q then throw "complex results are not supported by HALean"
    return .float (Float.pow p q)
  | _ => tyErr

def cmpOp (ctx : Ctx) (op : String) (a b : Value) : R Bool := do
  let lt (x y : Value) : R Bool :=
    if isOpaqueOrUndef x || isOpaqueOrUndef y then
      throw s!"'{op}' not supported between instances of '{typeName x}' and '{typeName y}'"
    else match pyLt x y with
      | .ok r => pure r
      | .error e => throw e
  if let .opaque w := a then throw s!"{w} values are not supported by HALean"
  if let .opaque w := b then throw s!"{w} values are not supported by HALean"
  match op with
  | "==" => pure (pyEq a b)
  | "!=" => pure (!pyEq a b)
  | "<" => lt a b
  | ">" => lt b a
  | "<=" => do pure ((← lt a b) || (pyEq a b && a.num?.isSome == b.num?.isSome))
  | ">=" => do pure ((← lt b a) || (pyEq a b && a.num?.isSome == b.num?.isSome))
  | "in" => containsV ctx b a
  | "notin" => do pure (!(← containsV ctx b a))
  | _ => throw s!"unknown comparison {op}"

/-! ## Python str methods (ASCII only: anything else is rejected) -/

def asciiOnly (fn : String) (s : String) : R Unit :=
  if s.toList.all (fun (c : Char) => c.toNat < 128) then pure () else throw s!"{fn} on non-ASCII text is not supported by HALean"

def pyTitle (s : String) : String := Id.run do
  let mut out := ""
  let mut prevCased := false
  for c in s.toList do
    if c.isAlpha then
      out := out.push (if prevCased then c.toLower else c.toUpper)
      prevCased := true
    else
      out := out.push c
      prevCased := false
  return out

def pyCapitalize (s : String) : String :=
  match s.toList with
  | [] => ""
  | c :: cs => String.ofList (c.toUpper :: cs.map Char.toLower)

def isPyWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\x0b' || c == '\x0c'

def pyStrip (s : String) (chars : Option String) (left right : Bool) : String :=
  let p : Char → Bool := match chars with
    | some cs => fun c => cs.contains c
    | none => isPyWs
  let l := s.toList
  let l := if left then l.dropWhile p else l
  let l := if right then (l.reverse.dropWhile p).reverse else l
  String.ofList l

/-- `str.split(sep=None, maxsplit=-1)` -/
def pySplit (s : String) (sep : Option String) (maxsplit : Int) : R (List String) := do
  match sep with
  | some "" => throw "ValueError: empty separator"
  | some sp =>
    let parts := s.splitOn sp
    if maxsplit < 0 || parts.length ≤ maxsplit.toNat + 1 then return parts
    let k := maxsplit.toNat
    return parts.take k ++ [sp.intercalate (parts.drop k)]
  | none =>
    -- runs of whitespace, no empty strings
    let mut out : Array String := #[]
    let mut cur := ""
    let mut rest := s.toList.dropWhile isPyWs
    while !rest.isEmpty do
      if maxsplit ≥ 0 && out.size == maxsplit.toNat then
        out := out.push (pyStrip (String.ofList rest) none false true); rest := []; cur := ""; break
      match rest with
      | c :: r =>
        if isPyWs c then
          out := out.push cur; cur := ""; rest := r.dropWhile isPyWs
        else cur := cur.push c; rest := r
      | [] => pure ()
    if !cur.isEmpty then out := out.push cur
    return out.toList

/-- `str.replace(old, new, count=-1)` -/
def pyReplace (s old new : String) (count : Int) : String :=
  if old.isEmpty then
    -- Python inserts `new` between every character (and at both ends)
    let cs := s.toList.map toString
    let n := if count < 0 then cs.length + 1 else min count.toNat (cs.length + 1)
    let rec go : List String → Nat → String
      | [], k => if k > 0 then new else ""
      | c :: r, k => if k > 0 then new ++ c ++ go r (k - 1) else String.join (c :: r)
    go cs n
  else
    let parts := s.splitOn old
    if count < 0 || parts.length ≤ count.toNat + 1 then new.intercalate parts
    else
      let k := count.toNat
      new.intercalate (parts.take (k + 1)) |> fun head =>
        head ++ old ++ old.intercalate (parts.drop (k + 1))

/-! ## Calls -/

structure Args where
  pos : List Value
  kw : List (String × Value)

def Args.get (a : Args) (i : Nat) (k : String) : Option Value :=
  match a.pos[i]? with
  | some v => some v
  | none => (a.kw.find? (·.1 == k)).map (·.2)

def Args.check (a : Args) (fn : String) (names : List String) : R Unit := do
  if a.pos.length > names.length then throw s!"{fn}() takes at most {names.length} arguments"
  for (k, _) in a.kw do
    if !names.contains k then throw s!"{fn}() got an unexpected keyword argument '{k}'"

def needStr (fn : String) (v : Value) : R String :=
  match v with
  | .str s => pure s
  | v => throw s!"{fn} expects a string, got {typeName v}"

/-- `is_state` -/
def isState (ctx : Ctx) (eid state : Value) : R Bool := do
  let .str e := eid | return false
  collect e
  let some s := ctx.states.get? e | return false
  return pyEq (.str s.state) state ||
    (match state with
     | .list xs => xs.any (pyEq (.str s.state))
     | _ => false)

/-- `state_attr` -/
def stateAttrFn (ctx : Ctx) (eid name : Value) : R Value := do
  let .str e := eid | return .none
  collect e
  let .str n := name | return .none
  let some s := ctx.states.get? e | return .none
  return (s.attr? n).map Value.ofJson |>.getD .none

/-- `has_value` -/
def hasValue (ctx : Ctx) (eid : Value) : R Bool := do
  match eid with
  | .str e =>
    collect e
    match ctx.states.get? e with
    | some s => pure (s.state != STATE_UNAVAILABLE && s.state != STATE_UNKNOWN)
    | none => pure false
  | _ => pure false

/-- `forgiving_float` -/
def forgivingFloat (v : Value) (dflt : Option Value) : R Value := do
  match ← toFloat? v with
  | some f => return .float f
  | none => match dflt with
    | some d => return d
    | none => noDefault "float" v

/-- `forgiving_int` -/
def forgivingInt (v : Value) (dflt : Option Value) (base : Option Value) : R Value := do
  match base with
  | none | some (.int 10) => pure ()
  | some _ => throw "int() with a base other than 10 is not supported by HALean"
  match ← doInt v with
  | some i => return .int i
  | none => match dflt with
    | some d => return d
    | none => noDefault "int" v

/-- `forgiving_boolean` -/
def forgivingBool (v : Value) (dflt : Option Value) : R Value := do
  if let .opaque w := v then throw s!"{w} values are not supported by HALean"
  match cvBoolean v with
  | some b => return .bool b
  | none => match dflt with
    | some d => return d
    | none => noDefault "bool" v

/-- `is_number` -/
def isNumber (v : Value) : R Bool := do
  match ← toFloat? v with
  | some f => return Float.isFinite' f
  | none => return false

/-- `forgiving_round` -/
def forgivingRound (v : Value) (precision method dflt : Option Value) : R Value := do
  let prec : Int ← match precision with
    | none => pure 0
    | some (.int p) => pure p
    | some (.bool b) => pure (if b then 1 else 0)
    | some p => throw s!"round precision {typeName p} is not supported by HALean"
  let meth ← match method with
    | none => pure "common"
    | some (.str m) => pure m
    | some _ => pure "common"
  let fail : R Value := match dflt with
    | some d => pure d
    | none => noDefault "round" v
  let some f ← toFloat? v | fail
  -- `multiplier = float(10**precision)`
  let mult : Float := if prec ≥ 0 then intToFloat (10 ^ prec.toNat) else ratToFloat false 1 (10 ^ (-prec).toNat)
  let res? : Option Float := match meth with
    | "ceil" => (ceilF (f * mult)).map fun i => intToFloat i / mult
    | "floor" => (floorF (f * mult)).map fun i => intToFloat i / mult
    | "half" => some (pyRound (f * 2) 0 / 2)
    | _ => some (pyRound f prec)
  let some r := res? | throw "OverflowError: cannot convert float infinity to integer"
  if prec != 0 then return .float r
  match floatToInt? r with
  | some i => return .int i
  | none => if r.isNaN then fail else throw "OverflowError: cannot convert float infinity to integer"

/-- `iif` -/
def iif (v : Value) (t f n : Option Value) : Value :=
  match v, n with
  | .none, some x => x
  | _, _ => if truthy v then t.getD (.bool true) else f.getD (.bool false)

/-! ## Collections: `sort`, `min`/`max`, `unique` (Jinja) and `expand` (HA) -/

def liftExcept (x : Except String α) : R α :=
  match x with
  | .ok v => pure v
  | .error e => throw e

/-- `list(x)` / `sorted(x)` / `xs += x`: like iteration, but CPython first asks
for a length hint, so `DomainStates.__len__` / `AllStates.__len__` also
record the lifecycle listener. -/
def iterVList (ctx : Ctx) (v : Value) : R (List Value) := do
  match v with
  | .domain d => collectDomain d true
  | .allStates => collectAll true
  | _ => pure ()
  iterV ctx v

/-- `jinja2.filters._prepare_attribute_parts`: a dotted path, parts made of
digits (`str.isdigit`) looked up as ints. `isdigit` also accepts non-ASCII
digits, which HALean does not model: such a part is an error. -/
def attrParts (attr : Value) : R (List Value) :=
  match attr with
  | .none => pure []
  | .str path => (path.splitOn ".").mapM fun part =>
    if part.isEmpty then pure (.str part)
    else if part.all fun c => c.isDigit then pure (.int part.toNat!)
    else if part.all fun c => c.isDigit || c.toNat ≥ 128 then
      throw s!"attribute part '{part}' (non-ASCII digits?) is not supported by HALean"
    else pure (.str part)
  | a => pure [a]

/-- The lookup inside `jinja2.filters.make_attrgetter`'s `attrgetter`: each
part through the sandboxed `getitem`, an Undefined replaced by `default`
after every step. -/
def attrPath (ctx : Ctx) (x : Value) (parts : List Value) (dflt : Option Value := none) : R Value :=
  parts.foldlM (fun cur part => do
    let r ← getitemV ctx cur part
    pure (match r, dflt with
      | .undef _, some d => (match d with | .none => r | d => d)
      | r, _ => r)) x

/-- `jinja2.filters.ignore_case`. `str.lower()` is exact for ASCII only, so
lower-casing other text is an error. -/
def ignoreCase (v : Value) : R Value :=
  match v with
  | .str s => do asciiOnly "lower" s; pure (.str s.toLower)
  | v => pure v

/-- `make_attrgetter(environment, attribute, postprocess=ignore_case if not
case_sensitive else None)` applied to one item. -/
def sortKey (ctx : Ctx) (parts : List Value) (caseSensitive : Bool) (x : Value) : R Value := do
  let k ← attrPath ctx x parts
  if caseSensitive then pure k else ignoreCase k

/-- Positional or keyword arguments of a Python function, rejecting unknown
keywords and arguments given twice (`TypeError`). -/
def Args.checkStrict (a : Args) (fn : String) (names : List String) : R Unit := do
  a.check fn names
  for (k, _) in a.kw do
    if names.idxOf k < a.pos.length then throw s!"{fn}() got multiple values for argument '{k}'"
    if (a.kw.filter (·.1 == k)).length > 1 then throw s!"{fn}() got multiple values for argument '{k}'"

/-- `jinja2.filters.do_sort`: `sorted(value, key=make_multi_attrgetter(...),
reverse=reverse)`. Every key is a list (one element per comma-separated
attribute). CPython's timsort compares only some pairs, so HALean compares
all of them first: if some pair cannot be compared (`TypeError`), any
comparison sort, timsort included, has to compare an incomparable pair too
(keys of disjoint comparable classes can only be ordered through a direct
comparison), so it raises; if the keys are not totally preordered (NaN), the
result depends on timsort's exact comparisons, which HALean does not model,
so that is an error. Otherwise the stable sort is unique. -/
def doSort (ctx : Ctx) (items : List Value) (reverse caseSensitive : Bool) (attr : Value) : R Value := do
  let parts ← match attr with
    | .str s => (s.splitOn ",").mapM fun p => attrParts (.str p)
    | a => do pure [← attrParts a]
  let keyed ← items.mapM fun x => do
    pure (Value.list (← parts.mapM fun p => sortKey ctx p caseSensitive x), x)
  let arr := keyed.toArray
  for i in [0:arr.size] do
    for j in [i+1:arr.size] do
      tick
      let a := arr[i]!.1
      let b := arr[j]!.1
      let ab ← liftExcept (pyLt a b)
      let ba ← liftExcept (pyLt b a)
      if !ab && !ba && !pyEq a b then
        throw "sorting values that are not totally ordered (NaN) is not supported by HALean"
  let lt (p q : Value × Value) : Bool := (pyLt p.1 q.1).toOption.getD false
  -- `reverse=True` keeps equal items in their original order, like CPython
  let sorted := keyed.mergeSort fun p q => if reverse then !(lt p q) else !(lt q p)
  pure (.list (sorted.map (·.2)))

/-- `jinja2.filters._min_or_max` with Python's `min`/`max`: one pass keeping
the first item whose key is strictly smaller (`<`) / larger (`>`). -/
def minOrMax (ctx : Ctx) (isMax : Bool) (items : List Value) (caseSensitive : Bool) (attr : Value) : R Value := do
  if items.isEmpty then return .undef "No aggregated item, sequence was empty."
  let parts ← attrParts attr
  let mut best : Option (Value × Value) := none
  for x in items do
    tick
    let k ← sortKey ctx parts caseSensitive x
    match best with
    | none => best := some (k, x)
    | some (bk, _) =>
      -- `k > bk` is `bk < k` for every type HALean compares
      if ← liftExcept (if isMax then pyLt bk k else pyLt k bk) then best := some (k, x)
  pure ((best.map (·.2)).getD .none)

/-- Python's `hash()` succeeds (`none`), raises `TypeError` (`some msg`), or
HALean cannot tell what a set does with the value (an error). -/
partial def hashCheck (v : Value) : R Unit :=
  match v with
  | .none | .undef _ | .bool _ | .int _ | .str _ | .datetime .. | .timedelta _ | .range .. => pure ()
  | .float f => if f.isNaN then throw "NaN in a set is not supported by HALean (identity semantics)" else pure ()
  | .tuple xs => xs.forM hashCheck
  | .list _ | .dict _ | .state .. => throw s!"TypeError: unhashable type: '{typeName v}'"
  | v => throw s!"hashing a {typeName v} is not supported by HALean"

/-- `jinja2.filters.sync_do_unique`: items whose key was not seen yet (a set
membership test: hash + `==`), as a generator. -/
def doUnique (ctx : Ctx) (items : List Value) (caseSensitive : Bool) (attr : Value) : R Value := do
  let parts ← attrParts attr
  let mut seen : Array Value := #[]
  let mut out : Array Value := #[]
  for x in items do
    tick
    let k ← sortKey ctx parts caseSensitive x
    hashCheck k
    if !(seen.any (pyEq · k)) then
      seen := seen.push k
      out := out.push x
  pure (.gen "generator" out.toList)

/-- `StateMachine.get`: the id as given, then `entity_id.lower()`. Valid ids
are ASCII, and only U+212A (Kelvin sign) lower-cases into ASCII, so other
non-ASCII ids cannot match. -/
def hassStatesGet (ctx : Ctx) (eid : String) : R (Option EntityState) :=
  match ctx.states.get? eid with
  | some s => pure (some s)
  | none =>
    if eid.contains 'K' then throw s!"looking up '{eid}' is not supported by HALean"
    else if eid.all (fun (c : Char) => c.toNat < 128) then pure (ctx.states.get? eid.toLower)
    else pure none

/-- Whether `isinstance(v, collections.abc.Iterable)` (a `str` is handled
before this is asked). -/
def isIterable (v : Value) : Bool :=
  match v with
  | .list _ | .tuple _ | .dict _ | .range .. | .gen .. | .domain _ | .allStates | .undef _ | .str _ => true
  | _ => false

/-- `StateExtension.expand`: entity ids, state objects and iterables of them
to a list of states, groups (`entity_id` attribute) and zones (`persons`)
replaced by their members. A stack (`search.pop()` takes the last item), so
the result is in the order the entities are first reached, not sorted.

HA also expands entities whose `entity_sources` say they come from the
`group` integration (light groups, ...). HALean does not know entity
sources: a non-group entity with an `entity_id` attribute is an error. -/
def expand (ctx : Ctx) (args : List Value) : R Value := do
  -- the top of the stack is the head
  let mut stack := args.reverse
  let mut found : Array (String × Value) := #[]
  while true do
    tick
    match stack with
    | [] => break
    | e :: rest =>
      stack := rest
      let (key, s, c) ← match e with
        | .str eid => do
          match ← hassStatesGet ctx eid with
          | none => collect eid; continue
          | some s => pure (eid, s, true)
        | .state s c => pure (s.entityId, s, c)
        | .opaque w => throw s!"{w} values are not supported by HALean"
        | v =>
          if isIterable v then
            stack := (← iterVList ctx v).reverse ++ stack
          continue
      if found.any (·.1 == key) then continue
      -- `entity.domain` collects on a collecting TemplateState
      if c then collect s.entityId
      let members (attrName : String) : R (List Value) := do
        match s.attr? attrName with
        | none => pure []
        | some j =>
          let v := Value.ofJson j
          -- `search += v` extends with any iterable (a str by characters)
          if truthy v then iterV ctx v else pure []
      if s.domain == "group" then
        stack := (← members "entity_id").reverse ++ stack
      else if s.domain == "zone" then
        stack := (← members "persons").reverse ++ stack
      else
        if s.hasAttr "entity_id" then
          throw s!"expand: {s.entityId} has an entity_id attribute; whether HA expands it depends on its entity source, which HALean does not know"
        collect key
        found := found.push (key, .state s c)
  pure (.list (found.toList.map (·.2)))

/-! ## The evaluator -/

mutual
partial def eval (ctx : Ctx) (e : Expr) : R Value := do
  match e with
  | .lit v => pure v
  | .name n =>
    match ctx.vars.find? (·.1 == n) with
    | some (_, v) => pure v
    | none =>
      if n == "states" then pure .allStates
      else if GLOBALS.contains n then pure (.func n none)
      else pure (.undef s!"'{n}'")
  | .list xs => return .list (← xs.mapM (eval ctx))
  | .tuple xs => return .tuple (← xs.mapM (eval ctx))
  | .dict kvs => return .dict (← kvs.mapM fun (k, v) => do pure (← eval ctx k, ← eval ctx v))
  | .getattr x a => getattrV ctx (← eval ctx x) a
  | .getitem x k => getitemV ctx (← eval ctx x) (← eval ctx k)
  | .slice x a b c =>
    let v ← eval ctx x
    let idx (o : Option Expr) : R (Option Int) := do
      match o with
      | none => pure none
      | some ex => match ← eval ctx ex with
        | .int i => pure (some i)
        | .none => pure none
        | v => throw s!"slice indices must be integers, not {typeName v}"
    let (a, b, c) := (← idx a, ← idx b, ← idx c)
    match v with
    | .list xs => match sliceList xs a b c with
      | .ok r => pure (.list r) | .error m => throw m
    | .tuple xs => match sliceList xs a b c with
      | .ok r => pure (.tuple r) | .error m => throw m
    | .str s => match sliceList s.toList a b c with
      | .ok r => pure (.str (String.ofList r)) | .error m => throw m
    | .undef _ => undefErr v
    | v => throw s!"slicing {typeName v} is not supported by HALean"
  | .call f args kwargs =>
    let fv ← eval ctx f
    let a : Args := { pos := ← args.mapM (eval ctx), kw := ← kwargs.mapM fun (k, x) => do pure (k, ← eval ctx x) }
    callV ctx fv a
  | .filter x n args kwargs =>
    -- `default` must see Undefined without failing on it
    let v ← eval ctx x
    let a : Args := { pos := ← args.mapM (eval ctx), kw := ← kwargs.mapM fun (k, x) => do pure (k, ← eval ctx x) }
    applyFilter ctx n v a
  | .test x n args negated =>
    let v ← eval ctx x
    let a ← args.mapM (eval ctx)
    let r ← applyTest ctx n v a
    pure (.bool (if negated then !r else r))
  | .neg x =>
    let v ← eval ctx x
    match v with
    | .int i => pure (.int (-i))
    | .bool b => pure (.int (if b then -1 else 0))
    | .float f => pure (.float (-f))
    | .timedelta us => pure (.timedelta (-us))
    | .undef _ => undefErr v
    | v => throw s!"bad operand type for unary -: '{typeName v}'"
  | .pos x =>
    let v ← eval ctx x
    match v with
    | .int _ | .float _ | .timedelta _ => pure v
    | .bool b => pure (.int (if b then 1 else 0))
    | .undef _ => undefErr v
    | v => throw s!"bad operand type for unary +: '{typeName v}'"
  | .binop op a b => do arith op (← eval ctx a) (← eval ctx b)
  | .concat a b => do pure (.str ((← strOf (← eval ctx a)) ++ (← strOf (← eval ctx b))))
  | .compare first rest =>
    let mut left ← eval ctx first
    for (op, ex) in rest do
      let right ← eval ctx ex
      if !(← cmpOp ctx op left right) then return .bool false
      left := right
    pure (.bool true)
  | .and a b =>
    let x ← eval ctx a
    if let .opaque w := x then throw s!"{w} values are not supported by HALean"
    if truthy x then eval ctx b else pure x
  | .or a b =>
    let x ← eval ctx a
    if let .opaque w := x then throw s!"{w} values are not supported by HALean"
    if truthy x then pure x else eval ctx b
  | .not a =>
    let x ← eval ctx a
    if let .opaque w := x then throw s!"{w} values are not supported by HALean"
    pure (.bool (!truthy x))
  | .cond c a b =>
    let cv ← eval ctx c
    if let .opaque w := cv then throw s!"{w} values are not supported by HALean"
    if truthy cv then eval ctx a
    else match b with
      | some b => eval ctx b
      | none => pure (.undef "the inline if-expression on the else branch")

partial def callV (ctx : Ctx) (f : Value) (a : Args) : R Value := do
  tick
  match f with
  | .undef _ => undefErr f
  | .allStates =>
    -- `states(entity_id, rounded=..., with_unit=...)`
    if a.pos.length > 1 || !a.kw.isEmpty then
      throw "states() with rounded/with_unit is not supported by HALean"
    let some (.str e) := a.get 0 "entity_id" | throw "states() needs an entity id"
    collect e
    match ctx.states.get? e with
    | some s => pure (.str s.state)
    | none => pure (.str STATE_UNKNOWN)
  | .func n self =>
    match n, self with
    | "is_state", _ => do
      a.check n ["entity_id", "state"]
      pure (.bool (← isState ctx ((a.get 0 "entity_id").getD .none) ((a.get 1 "state").getD .none)))
    | "state_attr", _ => do
      a.check n ["entity_id", "name"]
      stateAttrFn ctx ((a.get 0 "entity_id").getD .none) ((a.get 1 "name").getD .none)
    | "is_state_attr", _ => do
      a.check n ["entity_id", "name", "value"]
      let .str e := (a.get 0 "entity_id").getD .none | return .bool false
      collect e
      let .str nm := (a.get 1 "name").getD .none | return .bool false
      let some s := ctx.states.get? e | return .bool false
      match s.attr? nm with
      | none => return .bool false
      | some j => return .bool (pyEq (Value.ofJson j) ((a.get 2 "value").getD .none))
    | "has_value", _ => do
      a.check n ["entity_id"]
      pure (.bool (← hasValue ctx ((a.get 0 "entity_id").getD .none)))
    | "float", _ => do
      a.check n ["value", "default"]
      forgivingFloat ((a.get 0 "value").getD .none) (a.get 1 "default")
    | "int", _ => do
      a.check n ["value", "default", "base"]
      forgivingInt ((a.get 0 "value").getD .none) (a.get 1 "default") (a.get 2 "base")
    | "bool", _ => do
      a.check n ["value", "default"]
      forgivingBool ((a.get 0 "value").getD .none) (a.get 1 "default")
    | "is_number", _ => do
      a.check n ["value"]
      pure (.bool (← isNumber ((a.get 0 "value").getD .none)))
    | "iif", _ => do
      a.check n ["value", "if_true", "if_false", "if_none"]
      pure (iif ((a.get 0 "value").getD .none) (a.get 1 "if_true") (a.get 2 "if_false") (a.get 3 "if_none"))
    | "namespace", _ => do
      if !a.pos.isEmpty then throw "namespace() with positional arguments is not supported by HALean"
      let s ← get
      set { s with heap := s.heap.push a.kw }
      pure (.ns s.heap.size)
    | "now", _ => do a.check n []; collectTime; pure ctx.nowDT
    | "utcnow", _ => do a.check n []; collectTime; pure (.datetime (ctx.now.utc * 1000) (some 0))
    | "today_at", _ => do
      a.check n ["time_str"]
      collectTime
      -- `start_of_local_day()`, then the parsed time of day
      let off := ctx.now.tzOffsetSec
      let wall := ctx.now.utc * 1000 + off * US_PER_SEC
      let midnight := Int.fdiv wall US_PER_DAY * US_PER_DAY
      let ts := (a.get 0 "time_str").getD (.str "")
      if !truthy ts then return .datetime (midnight - off * US_PER_SEC) (some off)
      let tstr ← strOf ts
      match parseTime tstr with
      | some (h, m, sec) =>
        let w := midnight + ((h * 3600 + m * 60 + sec : Nat) : Int) * US_PER_SEC
        pure (.datetime (w - off * US_PER_SEC) (some off))
      | none => throw s!"ValueError: could not convert {typeName ts} to datetime: '{tstr}'"
    | "timedelta", _ => do
      a.check n ["days", "seconds", "microseconds", "milliseconds", "minutes", "hours", "weeks"]
      let factors : List (String × Nat) := [("days", 86400000000), ("seconds", 1000000),
        ("microseconds", 1), ("milliseconds", 1000), ("minutes", 60000000), ("hours", 3600000000),
        ("weeks", 604800000000)]
      -- exact sum of all arguments, rounded half to even once at the end
      let mut num : Int := 0
      let mut den : Nat := 1
      for ((k, f), i) in factors.zipIdx do
        match a.get i k with
        | none => pure ()
        | some (.int x) => num := num + x * f * den
        | some (.bool b) => num := num + (if b then (f : Int) else 0) * den
        | some (.float x) =>
          if !Float.isFinite' x then throw "ValueError: cannot convert float NaN or infinity to integer"
          let (neg, xn, xd) := floatFrac x
          let term : Int := (if neg then -(xn : Int) else xn) * f
          num := num * xd + term * den
          den := den * xd
        | some v => throw s!"TypeError: unsupported type for timedelta {k} component: {typeName v}"
      let q : Int := roundHalfEven num.natAbs den
      let us := if num < 0 then -q else q
      if us.natAbs ≥ 999999999 * 86400000000 then throw "OverflowError: days out of range"
      pure (.timedelta us)
    | "as_timestamp", _ => do
      a.check n ["value", "default"]
      let v := (a.get 0 "value").getD .none
      let fail : R Value := match a.get 1 "default" with
        | some d => pure d
        | none => noDefault "as_timestamp" v
      match v with
      | .datetime .. => pure (.float (← timestampOf v))
      | v =>
        match ← parseDatetime (← strOf v) with
        | some d => pure (.float (← timestampOf d))
        | none => fail
    | "as_datetime", _ => do
      a.check n ["value", "default"]
      let v := (a.get 0 "value").getD .none
      match v with
      | .datetime .. => pure v
      | v =>
        let viaFloat : Option Float := match v with
          | .str s => parseFloatStr s
          | .int _ | .bool _ | .float _ => (match v with
              | .int i => some (intToFloat i) | .bool b => some (if b then 1.0 else 0.0)
              | .float f => some f | _ => none)
          | _ => none
        match viaFloat with
        | some f => match utcFromTimestamp (.float f) with
          | some d => pure d
          | none => throw "ValueError: year is out of range"
        | none =>
          let parsed ← match v with
            | .str s => parseDatetime s
            | _ => pure none
          match parsed, a.get 1 "default" with
          | some d, _ => pure d
          | none, some d => pure d
          | none, none => match v with
            | .str _ => pure .none
            | v => noDefault "as_datetime" v
    | "as_local", _ => do
      a.check n ["value"]
      asLocal ctx ((a.get 0 "value").getD .none)
    | "timestamp_local" , _ | "timestamp_utc", _ | "timestamp_custom", _ => do
      let names := if n == "timestamp_custom" then ["value", "date_format", "local", "default"] else ["value", "default"]
      a.check n names
      let v := (a.get 0 "value").getD .none
      let dflt := a.get (names.length - 1) "default"
      match utcFromTimestamp v with
      | none => match dflt with
        | some d => pure d
        | none => noDefault n v
      | some d =>
        if n == "timestamp_utc" then
          let .datetime us off := d | pure d
          pure (.str (isoformat us off))
        else
          let isLocal := if n == "timestamp_local" then true else truthy ((a.get 2 "local").getD (.bool true))
          let d ← if isLocal then asLocal ctx d else pure d
          let .datetime us off := d | pure d
          if n == "timestamp_local" then pure (.str (isoformat us off))
          else
            let fmt ← strOf ((a.get 1 "date_format").getD (.str "%Y-%m-%d"))
            match strftime us off fmt with
            | .ok r => pure (.str r)
            | .error e => throw e
    | "datetime.weekday", some (.datetime us off) => pure (.int (weekdayOf (wallOf us off)))
    | "datetime.isoweekday", some (.datetime us off) => pure (.int (weekdayOf (wallOf us off) + 1))
    | "datetime.timestamp", some d => pure (.float (← timestampOf d))
    | "datetime.isoformat", some (.datetime us off) => do
      a.check "isoformat" ["sep"]
      pure (.str (isoformat us off (← strOf ((a.get 0 "sep").getD (.str "T")))))
    | "datetime.strftime", some (.datetime us off) => do
      let some f := a.get 0 "format" | throw "strftime() missing required argument 'format'"
      match strftime us off (← strOf f) with
      | .ok r => pure (.str r)
      | .error e => throw e
    | "datetime.replace", some (.datetime us off) => do
      if !a.pos.isEmpty then throw "replace() with positional arguments is not supported by HALean"
      let c := toCivil (wallOf us off)
      let mut c := c
      for (k, v) in a.kw do
        let i ← match v with
          | .int i => pure i
          | v => throw s!"TypeError: '{typeName v}' object cannot be interpreted as an integer"
        let nn := i.toNat
        if i < 0 && k != "year" then throw s!"ValueError: {k} must be non-negative"
        match k with
        | "year" => c := { c with year := i }
        | "month" => c := { c with month := nn }
        | "day" => c := { c with day := nn }
        | "hour" => c := { c with hour := nn }
        | "minute" => c := { c with minute := nn }
        | "second" => c := { c with second := nn }
        | "microsecond" => c := { c with micro := nn }
        | k => throw s!"replace({k}=...) is not supported by HALean"
      if let some e := c.valid then throw s!"ValueError: {e}"
      let wall := fromCivil c
      pure (.datetime (match off with | some o => wall - o * US_PER_SEC | none => wall) off)
    | "timedelta.total_seconds", some (.timedelta us) =>
      pure (.float (ratToFloat (us < 0) us.natAbs 1000000))
    | "range", _ => do
      -- jinja2.sandbox.safe_range
      if !a.kw.isEmpty then throw "range() takes no keyword arguments"
      let ints ← a.pos.mapM fun v => match v with
        | .int i => pure i
        | .bool b => pure (if b then 1 else 0)
        | v => throw s!"'{typeName v}' object cannot be interpreted as an integer"
      let (x, y, z) ← match ints with
        | [b] => pure (0, b, 1)
        | [x, y] => pure (x, y, 1)
        | [x, y, z] => pure (x, y, z)
        | _ => throw "range expected 1 to 3 arguments"
      if z == 0 then throw "range() arg 3 must not be zero"
      if (rangeItems x y z).length > 100000 then
        throw "Range too big. The sandbox blocks ranges larger than MAX_RANGE (100000)."
      pure (.range x y z)
    | "dict", _ => do
      if !a.pos.isEmpty then throw "dict() with positional arguments is not supported by HALean"
      pure (.dict (a.kw.map fun (k, v) => (.str k, v)))
    | "dict.items", some (.dict kvs) => pure (.list (kvs.map fun (k, v) => .tuple [k, v]))
    | "dict.keys", some (.dict kvs) => pure (.list (kvs.map (·.1)))
    | "dict.values", some (.dict kvs) => pure (.list (kvs.map (·.2)))
    | "dict.get", some (.dict kvs) => do
      let some k := (a.pos[0]? : Option Value) | throw "get expected at least 1 argument"
      pure ((lookupKV kvs k).getD ((a.pos[1]?).getD .none))
    | "min", _ | "max", _ => do
      -- `MathExtension.min_max_from_filter` around Jinja's `do_min`/`do_max`
      for (k, _) in a.kw do
        if k != "case_sensitive" && k != "attribute" then
          throw s!"{n}() got an unexpected keyword argument '{k}'"
      let items ← match a.pos with
        | [] => throw s!"{n} expected at least 1 argument, got 0"
        | [x] => iterV ctx x
        | xs => pure xs
      minOrMax ctx (n == "max") items (truthy ((a.kw.lookup "case_sensitive").getD (.bool false)))
        ((a.kw.lookup "attribute").getD .none)
    | "expand", _ => do
      if !a.kw.isEmpty then throw "expand() got an unexpected keyword argument"
      expand ctx a.pos
    | m, some (.str s) => strMethod m s a
    | _, _ => throw s!"calling {n} is not supported by HALean"
  | .opaque w => throw s!"{w} values are not supported by HALean"
  | v => throw s!"'{typeName v}' object is not callable"

partial def strMethod (m : String) (s : String) (a : Args) : R Value := do
  let optStr (i : Nat) (k : String) : R (Option String) := do
    match a.get i k with
    | none | some .none => pure none
    | some (.str x) => pure (some x)
    | some v => throw s!"{m} expects a string argument, got {typeName v}"
  match m with
  | "str.lower" => asciiOnly "lower" s; pure (.str s.toLower)
  | "str.upper" => asciiOnly "upper" s; pure (.str s.toUpper)
  | "str.title" => asciiOnly "title" s; pure (.str (pyTitle s))
  | "str.capitalize" => asciiOnly "capitalize" s; pure (.str (pyCapitalize s))
  | "str.strip" => pure (.str (pyStrip s (← optStr 0 "chars") true true))
  | "str.lstrip" => pure (.str (pyStrip s (← optStr 0 "chars") true false))
  | "str.rstrip" => pure (.str (pyStrip s (← optStr 0 "chars") false true))
  | "str.split" =>
    let mx ← match a.get 1 "maxsplit" with
      | none => pure (-1 : Int)
      | some (.int i) => pure i
      | some v => throw s!"maxsplit must be an int, not {typeName v}"
    pure (.list ((← pySplit s (← optStr 0 "sep") mx).map Value.str))
  | "str.startswith" | "str.endswith" =>
    let test (p : String) : Bool := if m == "str.startswith" then s.startsWith p else s.endsWith p
    match (a.pos[0]? : Option Value) with
    | some (.str p) => pure (.bool (test p))
    | some (.tuple ps) => pure (.bool (ps.any fun (p : Value) => match p with | Value.str q => test q | _ => false))
    | _ => throw s!"{m} expects a string or tuple"
  | "str.replace" =>
    let some (Value.str old) := (a.pos[0]? : Option Value) | throw "replace expects strings"
    let some (Value.str new) := (a.pos[1]? : Option Value) | throw "replace expects strings"
    let cnt ← match a.get 2 "count" with
      | none => pure (-1 : Int)
      | some (.int i) => pure i
      | some v => throw s!"count must be an int, not {typeName v}"
    pure (.str (pyReplace s old new cnt))
  | _ => throw s!"{m} is not supported by HALean"

partial def applyFilter (ctx : Ctx) (n : String) (v : Value) (a : Args) : R Value := do
  tick
  let arg (i : Nat) (k : String) := a.get i k
  match n with
  | "float" => forgivingFloat v (arg 0 "default")
  | "int" => forgivingInt v (arg 0 "default") (arg 1 "base")
  | "bool" => forgivingBool v (arg 0 "default")
  | "is_number" => pure (.bool (← isNumber v))
  | "iif" => pure (iif v (arg 0 "if_true") (arg 1 "if_false") (arg 2 "if_none"))
  | "has_value" => pure (.bool (← hasValue ctx v))
  | "state_attr" => stateAttrFn ctx v ((arg 0 "name").getD .none)
  | "states" => callV ctx .allStates { pos := v :: a.pos, kw := a.kw }
  | "round" => forgivingRound v (arg 0 "precision") (arg 1 "method") (arg 2 "default")
  | "default" | "d" =>
    let dflt := (arg 0 "default_value").getD (.str "")
    let boolean := truthy ((arg 1 "boolean").getD (.bool false))
    match v with
    | .undef _ => pure dflt
    | v => if boolean && !truthy v then pure dflt else pure v
  | "lower" => do let s ← strOf v; asciiOnly "lower" s; pure (.str s.toLower)
  | "upper" => do let s ← strOf v; asciiOnly "upper" s; pure (.str s.toUpper)
  | "capitalize" => do let s ← strOf v; asciiOnly "capitalize" s; pure (.str (pyCapitalize s))
  | "title" =>
    -- jinja's do_title capitalises words split on spaces, brackets and braces
    do let s ← strOf v; asciiOnly "title" s
       let mut out := ""
       let mut start := true
       for c in s.toList do
         if c.isWhitespace || "-([{<".contains c then out := out.push c; start := true
         else if start then out := out.push c.toUpper; start := false
         else out := out.push c.toLower
       pure (.str out)
  | "trim" => do
    let s ← strOf v
    let chars ← match arg 0 "chars" with
      | none | some .none => pure none
      | some (.str c) => pure (some c)
      | some x => throw s!"trim chars must be a string, not {typeName x}"
    pure (.str (pyStrip s chars true true))
  | "replace" => do
    let s ← strOf v
    let some old := arg 0 "old" | throw "replace needs old and new"
    let some new := arg 1 "new" | throw "replace needs old and new"
    let cnt ← match arg 2 "count" with
      | none | some .none => pure (-1 : Int)
      | some (.int i) => pure i
      | some x => throw s!"count must be an int, not {typeName x}"
    pure (.str (pyReplace s (← strOf old) (← strOf new) cnt))
  | "length" | "count" =>
    match v with
    | .gen k _ => throw s!"object of type '{k}' has no len()"
    | _ => pure (.int (← lenV ctx v))
  | "first" =>
    match v with
    | .undef _ => undefErr v
    | _ => pure ((← iterV ctx v).head?.getD (.undef "No first item, sequence was empty."))
  | "last" =>
    match v with
    | .undef _ => undefErr v
    | .dict _ => throw "last on a dict is not supported by HALean"
    | .gen k _ => throw s!"'{k}' object is not reversible"
    | _ => pure ((← iterV ctx v).getLast?.getD (.undef "No last item, sequence was empty."))
  | "join" => do
    if (arg 1 "attribute").isSome then throw "join(attribute=...) is not supported by HALean"
    let sep ← strOf ((arg 0 "d").getD (.str ""))
    let items ← (← iterV ctx v).mapM strOf
    pure (.str (sep.intercalate items))
  | "list" => pure (.list (← iterVList ctx v))
  | "string" => pure (.str (← strOf v))
  | "abs" =>
    match v with
    | .int i => pure (.int i.natAbs)
    | .bool b => pure (.int (if b then 1 else 0))
    | .float f => pure (.float f.abs)
    | .timedelta us => pure (.timedelta us.natAbs)
    | .undef _ => undefErr v
    | v => throw s!"bad operand type for abs(): '{typeName v}'"
  | "sum" => do
    if (arg 0 "attribute").isSome then throw "sum(attribute=...) is not supported by HALean"
    let mut acc := (arg 1 "start").getD (.int 0)
    for x in ← iterV ctx v do acc ← arith "+" acc x
    pure acc
  | "as_timestamp" | "as_datetime" | "as_local" | "timestamp_local" | "timestamp_utc"
  | "timestamp_custom" | "today_at" =>
    callV ctx (.func n none) { pos := v :: a.pos, kw := a.kw }
  | "reverse" =>
    match v with
    | .str s => pure (.str (String.ofList s.toList.reverse))
    | .undef _ => undefErr v
    | v => pure (.gen "list_reverseiterator" (← iterV ctx v).reverse)
  | "map" =>
    let items ← iterV ctx v
    match a.pos, (a.kw.find? (·.1 == "attribute")) with
    | [], some (_, attr) =>
      let dflt := (a.kw.find? (·.1 == "default")).map (·.2)
      let parts ← attrParts attr
      let out ← items.mapM fun x => attrPath ctx x parts dflt
      pure (.gen "generator" out)
    | (.str f) :: rest, _ =>
      let out ← items.mapM fun x => applyFilter ctx f x { pos := rest, kw := a.kw }
      pure (.gen "generator" out)
    | _, _ => throw "map needs a filter name or attribute="
  | "select" | "reject" =>
    let items ← iterV ctx v
    let keep ← items.filterM fun x => do
      let r ← match a.pos with
        | [] => pure (truthy x)
        | (.str tn) :: rest => applyTest ctx tn x rest
        | _ => throw s!"{n} needs a test name"
      pure (if n == "select" then r else !r)
    pure (.gen "generator" keep)
  | "selectattr" | "rejectattr" =>
    let items ← iterV ctx v
    let some attr := a.pos.head? | throw s!"{n} needs an attribute"
    let keep ← items.filterM fun x => do
      let val ← attrGet ctx x attr
      let r ← match a.pos.drop 1 with
        | [] => pure (truthy val)
        | (.str tn) :: rest => applyTest ctx tn val rest
        | _ => throw s!"{n} needs a test name"
      pure (if n == "selectattr" then r else !r)
    pure (.gen "generator" keep)
  -- collections (Jinja's do_sort, do_min, do_max, sync_do_unique; HA's expand)
  | "sort" => do
    a.checkStrict n ["reverse", "case_sensitive", "attribute"]
    doSort ctx (← iterVList ctx v) (truthy ((arg 0 "reverse").getD (.bool false)))
      (truthy ((arg 1 "case_sensitive").getD (.bool false))) ((arg 2 "attribute").getD .none)
  | "min" | "max" => do
    a.checkStrict n ["case_sensitive", "attribute"]
    minOrMax ctx (n == "max") (← iterV ctx v) (truthy ((arg 0 "case_sensitive").getD (.bool false)))
      ((arg 1 "attribute").getD .none)
  | "unique" => do
    a.checkStrict n ["case_sensitive", "attribute"]
    doUnique ctx (← iterV ctx v) (truthy ((arg 0 "case_sensitive").getD (.bool false)))
      ((arg 1 "attribute").getD .none)
  | "expand" => callV ctx (.func "expand" none) { pos := v :: a.pos, kw := a.kw }
  | _ => throw s!"filter '{n}' is not supported by HALean"

partial def applyTest (ctx : Ctx) (n : String) (v : Value) (args : List Value) : R Bool := do
  let a0 := args.headD .none
  if let .opaque w := v then
    if n != "defined" && n != "undefined" then throw s!"{w} values are not supported by HALean"
  match n with
  | "defined" => pure !(isUndef v)
  | "undefined" => pure (isUndef v)
  | "none" => pure (match v with | .none => true | _ => false)
  | "number" => pure v.num?.isSome
  | "string" => pure (match v with | .str _ => true | _ => false)
  | "boolean" => pure (match v with | .bool _ => true | _ => false)
  | "integer" => pure (match v with | .int _ => true | _ => false)
  | "float" => pure (match v with | .float _ => true | _ => false)
  | "mapping" => pure (match v with | .dict _ => true | _ => false)
  | "sequence" => pure (match v with | .list _ | .tuple _ | .str _ | .dict _ => true | _ => false)
  | "iterable" => pure (match v with | .list _ | .tuple _ | .str _ | .dict _ | .undef _ => true | _ => false)
  | "true" => pure (match v with | .bool true => true | _ => false)
  | "false" => pure (match v with | .bool false => true | _ => false)
  | "eq" | "equalto" | "==" => cmpOp ctx "==" v a0
  | "ne" | "!=" => cmpOp ctx "!=" v a0
  | "lt" | "<" | "lessthan" => cmpOp ctx "<" v a0
  | "le" | "<=" => cmpOp ctx "<=" v a0
  | "gt" | ">" | "greaterthan" => cmpOp ctx ">" v a0
  | "ge" | ">=" => cmpOp ctx ">=" v a0
  | "in" => containsV ctx a0 v
  | "divisibleby" => do pure (pyEq (← arith "%" v a0) (.int 0))
  | "even" => do pure (pyEq (← arith "%" v (.int 2)) (.int 0))
  | "odd" => do pure (pyEq (← arith "%" v (.int 2)) (.int 1))
  | "is_state" => isState ctx v a0
  | "is_state_attr" =>
    match (← callV ctx (.func "is_state_attr" none) { pos := v :: args, kw := [] }) with
    | .bool b => pure b
    | _ => pure false
  | "has_value" => hasValue ctx v
  | "is_number" => isNumber v
  | _ => throw s!"test '{n}' is not supported by HALean"

/-- `jinja2.filters.make_attrgetter`: dotted path, digit parts as indexes,
each step through the sandboxed `getitem`. -/
partial def attrGet (ctx : Ctx) (x : Value) (attr : Value) : R Value := do
  attrPath ctx x (← attrParts attr)

partial def isUndef (v : Value) : Bool :=
  match v with | .undef _ => true | _ => false

partial def emitOut (s : String) : R Unit := do
  let st ← get
  let out := st.out ++ s
  if out.length > MAX_TEMPLATE_OUTPUT then
    throw s!"Template output exceeded maximum size of {MAX_TEMPLATE_OUTPUT} characters"
  set { st with out }

/-- Render nodes. `vars` is the current scope; returns the updated scope (set
statements) and the control signal. -/
partial def renderNodes (ctx : Ctx) (nodes : List Node) : R (Ctx × Signal) := do
  let mut ctx := ctx
  for n in nodes do
    match n with
    | .text t => emitOut t
    | .output e => emitOut (← strOf (← eval ctx e))
    | .ifs branches el =>
      let mut taken := false
      for (c, body) in branches do
        let cv ← eval ctx c
        if let .opaque w := cv then throw s!"{w} values are not supported by HALean"
        if truthy cv then
          let (ctx', sig) ← renderNodes ctx body
          ctx := ctx'
          if sig != .normal then return (ctx, sig)
          taken := true
          break
      if !taken then
        let (ctx', sig) ← renderNodes ctx el
        ctx := ctx'
        if sig != .normal then return (ctx, sig)
    | .set ts e =>
      let v ← eval ctx e
      ctx := { ctx with vars := (← bindTargets ts v) ++ ctx.vars }
    | .setAttr obj attr e =>
      let v ← eval ctx e
      match ctx.vars.find? (·.1 == obj) with
      | some (_, .ns id) =>
        modify fun s => { s with heap := s.heap.modify id fun fs => (attr, v) :: fs.filter (·.1 != attr) }
      | _ => throw s!"can only assign attributes of a namespace ('{obj}')"
    | .brk => return (ctx, .brk)
    | .cont => return (ctx, .cont)
    | .for ts it flt body el =>
      let items ← iterV ctx (← eval ctx it)
      -- `for x in xs if cond`: filter first, so `loop` counts filtered items
      let mut kept : Array (Value × List (String × Value)) := #[]
      for x in items do
        tick
        let b ← bindTargets ts x
        match flt with
        | none => kept := kept.push (x, b)
        | some f =>
          if truthy (← eval { ctx with vars := b ++ ctx.vars } f) then kept := kept.push (x, b)
      let len := kept.size
      for h : i in [0:len] do
        tick
        let (_, b) := kept[i]
        let loop : Value := .dict [
          (.str "index", .int (i + 1)), (.str "index0", .int i),
          (.str "revindex", .int (len - i)), (.str "revindex0", .int (len - i - 1)),
          (.str "first", .bool (i == 0)), (.str "last", .bool (i + 1 == len)),
          (.str "length", .int len),
          (.str "previtem", if i == 0 then .undef "there is no previous item" else (kept[i - 1]!).1),
          (.str "nextitem", if i + 1 == len then .undef "there is no next item" else (kept[i + 1]!).1)]
        -- each iteration starts from the outer scope (Jinja's loop scoping)
        let (_, sig) ← renderNodes { ctx with vars := b ++ ("loop", loop) :: ctx.vars } body
        if sig == .brk then break
      if len == 0 then
        let (_, sig) ← renderNodes ctx el
        if sig != .normal then return (ctx, sig)
  return (ctx, .normal)

partial def bindTargets (ts : List String) (v : Value) : R (List (String × Value)) := do
  match ts with
  | [t] => pure [(t, v)]
  | _ =>
    let xs ← iterV {states := []} v
    if xs.length != ts.length then
      throw s!"cannot unpack {xs.length} values into {ts.length} names"
    pure (ts.zip xs)
end

/-! ## Load-time check -/

partial def exprNames : Expr → List String × List String × List String
  -- (names, filters, tests)
  | .lit _ => ([], [], [])
  | .name n => ([n], [], [])
  | .list xs | .tuple xs => cat (xs.map exprNames)
  | .dict kvs => cat (kvs.flatMap fun (k, v) => [exprNames k, exprNames v])
  | .getattr e _ | .neg e | .pos e | .not e => exprNames e
  | .getitem a b | .binop _ a b | .concat a b | .and a b | .or a b => cat [exprNames a, exprNames b]
  | .slice e a b c => cat (exprNames e :: ([a, b, c].filterMap id).map exprNames)
  | .call f args kw => cat (exprNames f :: args.map exprNames ++ kw.map (exprNames ·.2))
  | .filter e n args kw =>
    let (ns, fs, ts) := cat (exprNames e :: args.map exprNames ++ kw.map (exprNames ·.2))
    -- the filter/test a higher-order filter applies is named by a string
    let lit (i : Nat) : String := match args[i]? with
      | some (.lit (.str x)) => x
      | some _ => "<computed name>"
      | none => ""
    let extra : List String × List String := match n with
      | "map" => if args.isEmpty then ([], []) else ([lit 0], [])
      | "select" | "reject" => if args.isEmpty then ([], []) else ([], [lit 0])
      | "selectattr" | "rejectattr" => if args.length < 2 then ([], []) else ([], [lit 1])
      | _ => ([], [])
    (ns, n :: extra.1 ++ fs, extra.2 ++ ts)
  | .test e n args _ =>
    let (ns, fs, ts) := cat (exprNames e :: args.map exprNames)
    (ns, fs, n :: ts)
  | .compare a rest => cat (exprNames a :: rest.map (exprNames ·.2))
  | .cond c a b => cat ([exprNames c, exprNames a] ++ (b.map exprNames).toList)
where
  cat (xs : List (List String × List String × List String)) : List String × List String × List String :=
    (xs.flatMap (·.1), xs.flatMap (·.2.1), xs.flatMap (·.2.2))

partial def nodeNames : Node → (List String × List String × List String) × List String
  -- (used, bound)
  | .text _ => (([], [], []), [])
  | .output e => (exprNames e, [])
  | .ifs bs el =>
    let parts := bs.flatMap (fun (c, body) => (exprNames c, []) :: body.map nodeNames) ++ el.map nodeNames
    merge parts
  | .for ts it f body el =>
    let parts := (exprNames it, ts ++ ["loop"]) :: ((f.map fun f => (exprNames f, [])).toList ++ body.map nodeNames ++ el.map nodeNames)
    merge parts
  | .set ts e => (exprNames e, ts)
  | .setAttr o _ e => let (ns, fs, tss) := exprNames e; ((o :: ns, fs, tss), [])
  | .brk | .cont => (([], [], []), [])
where
  merge (ps : List ((List String × List String × List String) × List String)) :=
    ((ps.flatMap (·.1.1), ps.flatMap (·.1.2.1), ps.flatMap (·.1.2.2)), ps.flatMap (·.2))

/-- Reject templates that use names, filters or tests HALean does not
implement. `vars` are the variables the caller passes (e.g. `trigger`). -/
def check (t : Tmpl) (vars : List String) (allowTime : Bool := true) : Except String Unit := do
  let parts := t.nodes.map nodeNames
  let used := parts.flatMap (·.1.1)
  let filters := parts.flatMap (·.1.2.1)
  let tests := parts.flatMap (·.1.2.2)
  let bound := parts.flatMap (·.2)
  if !allowTime then
    for n in used ++ filters do
      if TIME_NAMES.contains n then
        throw s!"'{n}' in a trigger template is not supported by HALean yet (HA re-renders it on a timer)"
  for n in used do
    if !(GLOBALS.contains n || vars.contains n || bound.contains n
         || ["true", "false", "none", "True", "False", "None"].contains n) then
      throw s!"template uses '{n}', which HALean does not support"
  for f in filters do
    if !FILTERS.contains f then throw s!"template filter '{f}' is not supported by HALean"
  for x in tests do
    if !TESTS.contains x then throw s!"template test '{x}' is not supported by HALean"

/-! ## Results -/

/-- `_IS_NUMERIC = ^[+-]?(?!0\d)\d*(?:\.\d*)?$` -/
def isNumericStr (s : String) : Bool :=
  let cs := s.toList
  let cs := match cs with | '+' :: r | '-' :: r => r | r => r
  let noLeadingZero := match cs with | '0' :: d :: _ => !d.isDigit | _ => true
  let ip := cs.takeWhile Char.isDigit
  let rest := cs.drop ip.length
  let ok := match rest with
    | [] => true
    | '.' :: fs => fs.all Char.isDigit
    | _ => false
  noLeadingZero && ok

/-! ### `ast.literal_eval` -/

inductive LTok where
  | num (v : Value) | cplx | str (s : String) | name (n : String) | op (c : Char)
  deriving Inhabited

/-- Tokenize a Python literal. `none` = SyntaxError. -/
partial def litLex (cs : List Char) (depth : Nat) (acc : Array LTok) : Option (List LTok) :=
  match cs with
  | [] => if depth == 0 then some acc.toList else none
  | c :: rest =>
    if c == ' ' || c == '\t' || c == '\x0c' then litLex rest depth acc
    else if c == '\n' || c == '\r' then
      if depth > 0 || (rest.all fun x => x == '\n' || x == '\r' || x == ' ' || x == '\t') then litLex rest depth acc
      else none
    else if c == '#' then litLex (cs.dropWhile (· != '\n')) depth acc
    else if "([{".contains c then litLex rest (depth + 1) (acc.push (.op c))
    else if ")]}".contains c then (if depth == 0 then none else litLex rest (depth - 1) (acc.push (.op c)))
    else if ",:+-".contains c then litLex rest depth (acc.push (.op c))
    else if c.isDigit || (c == '.' && (rest.headD ' ').isDigit) then
      let word := cs.takeWhile fun x => x.isAlphanum || x == '_' || x == '.'
      -- exponent signs: 1e-5
      let rec grab (w : List Char) (r : List Char) : List Char × List Char :=
        match r with
        | s :: r' => if (s == '+' || s == '-') && (w.getLast?.map (fun x => x == 'e' || x == 'E')).getD false
                       && !(w.take 2 == ['0', 'x'] || w.take 2 == ['0', 'X']) then
                       let more := r'.takeWhile fun x => x.isAlphanum || x == '_' || x == '.'
                       grab (w ++ [s] ++ more) (r'.drop more.length)
                     else (w, r)
        | [] => (w, r)
      let (word, rest') := grab word (cs.drop word.length)
      let w := String.ofList word
      let lw := w.toLower
      if lw.endsWith "j" then litLex rest' depth (acc.push .cplx)
      else if lw.startsWith "0x" || lw.startsWith "0o" || lw.startsWith "0b" then
        let base := if lw.startsWith "0x" then 16 else if lw.startsWith "0o" then 8 else 2
        let ds := (lw.dropS 2).replace "_" ""
        let dv (ch : Char) : Option Nat :=
          if ch.isDigit then some (ch.toNat - '0'.toNat)
          else if 'a' ≤ ch && ch ≤ 'f' then some (ch.toNat - 'a'.toNat + 10) else none
        if ds.isEmpty then none else
        match ds.toList.foldlM (fun (n : Nat) ch => do
            let d ← dv ch
            if d ≥ base then none else some (n * base + d)) 0 with
        | some n => litLex rest' depth (acc.push (.num (.int n)))
        | none => none
      else if w.contains '.' || lw.contains 'e' then
        match parseFloatStr w with
        | some f => litLex rest' depth (acc.push (.num (.float f)))
        | none => none
      else
        -- decimal int: no leading zeros unless all zeros
        let d := w.replace "_" ""
        if d.length > 1 && d.startsWith "0" && !d.all (· == '0') then none
        else match parseIntStr w with
          | some i => litLex rest' depth (acc.push (.num (.int i)))
          | none => none
    else if c.isAlpha || c == '_' then
      let word := cs.takeWhile fun x => x.isAlphanum || x == '_'
      let rest' := cs.drop word.length
      let w := String.ofList word
      match rest' with
      | q :: _ =>
        if (q == '\'' || q == '"') && ["r", "u", "R", "U", "b", "B", "br", "rb", "f", "F", "rf", "fr"].contains w then
          if w.toLower.contains 'u' || w.toLower == "r" then
            match litString rest' (w.toLower.contains 'r') with
            | some (s, r) => litLex r depth (acc.push (.str s))
            | none => none
          else none  -- bytes / f-strings: not a str literal HALean models
        else litLex rest' depth (acc.push (.name w))
      | [] => litLex rest' depth (acc.push (.name w))
    else if c == '\'' || c == '"' then
      match litString cs false with
      | some (s, r) => litLex r depth (acc.push (.str s))
      | none => none
    else none
where
  litString (cs : List Char) (raw : Bool) : Option (String × List Char) := do
    let q ← cs.head?
    let triple := cs.take 3 == [q, q, q]
    let body := if triple then cs.drop 3 else cs.drop 1
    let rec scan (xs : List Char) (out : Array Char) : Option (List Char × List Char) :=
      match xs with
      | [] => none
      | '\\' :: x :: r => scan r (out.push '\\' |>.push x)
      | x :: r =>
        if triple then
          if xs.take 3 == [q, q, q] then some (out.toList, xs.drop 3) else scan r (out.push x)
        else if x == q then some (out.toList, r)
        else if x == '\n' then none
        else scan r (out.push x)
    let (raw', r) ← scan body #[]
    let s ← if raw then some (String.ofList raw') else (unescape raw').toOption
    return (s, r)

mutual
/-- Parse a token list as one literal. -/
partial def litParse (ts : List LTok) : Option (Value × List LTok) := do
  match ts with
  | .op '-' :: rest | .op '+' :: rest =>
    let neg := match ts with | .op '-' :: _ => true | _ => false
    match rest with
    | .num v :: r =>
      let v' ← match v, neg with
        | .int i, true => some (Value.int (-i))
        | .float f, true => some (Value.float (-f))
        | v, false => some v
        | _, _ => none
      complexTail v' r
    | .cplx :: r => some (.opaque "complex", r)
    | .op '-' :: _ | .op '+' :: _ => do
      -- `--1` is UnaryOp(UnaryOp(1)): literal_eval allows nested unary on numbers
      let (v, r) ← litParse rest
      match v, neg with
      | .int i, true => some (.int (-i), r)
      | .float f, true => some (.float (-f), r)
      | .int _, false | .float _, false => some (v, r)
      | _, _ => none
    | _ => none
  | .num v :: r => complexTail v r
  | .cplx :: r => some (.opaque "complex", r)
  | .str s :: r =>
    -- adjacent literals concatenate
    let rec more (acc : String) : List LTok → String × List LTok
      | .str t :: r => more (acc ++ t) r
      | r => (acc, r)
    let (s, r) := more s r
    some (.str s, r)
  | .name "True" :: r => some (.bool true, r)
  | .name "False" :: r => some (.bool false, r)
  | .name "None" :: r => some (.none, r)
  | .op '[' :: r => do
    let (xs, r) ← litItems r ']' #[]
    some (.list xs, r)
  | .op '(' :: .op ')' :: r => some (.tuple [], r)
  | .op '(' :: r => do
    let (first, r1) ← litParse r
    match r1 with
    | .op ')' :: r2 => some (first, r2)
    | .op ',' :: r2 => do
      let (xs, r3) ← litItems r2 ')' #[]
      some (.tuple (first :: xs), r3)
    | _ => none
  | .op '{' :: .op '}' :: r => some (.dict [], r)
  | .op '{' :: r => do
    let (k, r1) ← litParse r
    match r1 with
    | .op ':' :: r2 => do
      let (v, r3) ← litParse r2
      let rec kvs (acc : Array (Value × Value)) : List LTok → Option (List (Value × Value) × List LTok)
        | .op '}' :: r => some (acc.toList, r)
        | .op ',' :: .op '}' :: r => some (acc.toList, r)
        | .op ',' :: r => do
          let (k, r1) ← litParse r
          let .op ':' :: r2 := r1 | none
          let (v, r3) ← litParse r2
          kvs (acc.push (k, v)) r3
        | _ => none
      let (rest, r4) ← kvs #[(k, v)] r3
      some (.dict rest, r4)
    | _ => do
      -- a set: HALean hands it on as a list
      let (xs, r2) ← match r1 with
        | .op '}' :: r => some ([], r)
        | .op ',' :: r => litItems r '}' #[]
        | _ => none
      some (Value.list (k :: xs), r2)
  | _ => none
where
  complexTail (v : Value) (r : List LTok) : Option (Value × List LTok) :=
    match r with
    | .op '+' :: .cplx :: r' | .op '-' :: .cplx :: r' => some (.opaque "complex", r')
    | _ => some (v, r)

/-- Items of a bracketed literal after its first element (or from the start):
`x, y, z]` with an optional trailing comma. -/
partial def litItems (r : List LTok) (close : Char) (acc : Array Value) :
    Option (List Value × List LTok) :=
  match r with
  | .op c :: r' =>
    if c == close then some (acc.toList, r')
    else if ")]}".contains c then none
    else litElem r close acc
  | _ => litElem r close acc

partial def litElem (r : List LTok) (close : Char) (acc : Array Value) :
    Option (List Value × List LTok) := do
  let (v, r1) ← litParse r
  let acc := acc.push v
  match r1 with
  | .op ',' :: r2 => litItems r2 close acc
  | .op c :: r2 => if c == close then some (acc.toList, r2) else none
  | _ => none
end

partial def litTupleRest (acc : Array Value) : List LTok → Option (List Value)
  | [] => some acc.toList
  | [.op ','] => some acc.toList
  | .op ',' :: r => do
    let (x, r') ← litParse r
    litTupleRest (acc.push x) r'
  | _ => none

/-- `ast.literal_eval`: `none` = it raised. A bare `1, 2` is a tuple. -/
def literalEval (s : String) : Option Value := do
  let s := String.ofList (s.toList.dropWhile fun c => c == ' ' || c == '\t')
  let toks ← litLex s.toList 0 #[]
  let (v, rest) ← litParse toks
  match rest with
  | [] => some v
  | .op ',' :: _ =>
    -- top-level tuple without parentheses
    let xs ← litTupleRest #[v] rest
    some (.tuple xs)
  | _ => none

def isComplexOrStr : Value → Bool
  | .opaque "complex" => true
  | .str _ => true
  | _ => false

/-- `_parse_result` (fast numeric path + `_cached_parse_result`). -/
def parseResult (r : String) : Value :=
  let fast : Option Value :=
    if isNumericStr r then
      if r.contains '.' then (parseFloatStr r).map Value.float
      else (parseIntStr r).map Value.int
    else none
  match fast with
  | some v => v
  | none =>
    match literalEval r with
    | none => .str r
    | some v =>
      if isComplexOrStr v then .str r
      else match v with
        | .int _ | .float _ => if isNumericStr r then v else .str r
        | v => v

/-- Render to the stripped output string (`render_with_context` + `.strip()`). -/
def renderString (t : Tmpl) (ctx : Ctx) : Except String String :=
  if t.isStatic then .ok t.src else
  match ((renderNodes ctx t.nodes).run {}).run with
  | (.ok _, st) => .ok (pyStrip st.out none true true)
  | (.error e, _) => .error e

/-- `Template.async_render_to_info`: the result and what the render read. -/
def renderWithInfo (t : Tmpl) (ctx : Ctx) (parse : Bool := true) : Except String Value × RInfo :=
  if t.isStatic then (.ok (if parse then parseResult t.src else .str t.src), { isStatic := true }) else
  match ((renderNodes ctx t.nodes).run {}).run with
  | (.ok _, st) =>
    let out := pyStrip st.out none true true
    (.ok (if parse then parseResult out else .str out), st.info)
  | (.error e, st) => (.error e, { st.info with exception := true })

/-- `Template.async_render(variables, parse_result)` -/
def render (t : Tmpl) (ctx : Ctx) (parse : Bool := true) : Except String Value :=
  if t.isStatic then .ok (if parse then parseResult t.src else .str t.src) else do
  let s ← renderString t ctx
  return if parse then parseResult s else .str s

end HALean.Template
