/-
  The service registry: `homeassistant/core.py::ServiceRegistry` (with
  `Service`, `ServiceCall`, `SupportsResponse` and the exceptions it raises from
  `homeassistant/exceptions.py`).

  A pure model. Handlers and schemas are specs, so a call's behaviour is
  observable and comparable with Home Assistant:

  * a handler returns a given value, echoes the `ServiceCall` it received, or
    raises a given exception;
  * a schema is a flat probatio mapping schema (`HALean.Core.Probatio`).

  Every operation takes the clock (`now`) explicitly and returns the events it
  fires (`EVENT_SERVICE_REGISTERED`, `EVENT_SERVICE_REMOVED`,
  `EVENT_CALL_SERVICE`) and what it logs. Contexts are `HALean.Core.Context`
  (`State.lean`), shared with the state machine and the event bus. A fresh
  `Context()` draws a random ULID upstream; the standalone registry writes it
  `new` (`Registry.freshContext`), the joined core (`HALean/Core/Hass.lean`)
  passes a symbolic one in.

  `async_call` is split in two so the core can run a handler that acts on the
  whole of `hass`: `Registry.prepareCall` (everything before `call_service` is
  fired) and `finishCall` (what happens with the handler's outcome).
  `Registry.asyncCall` composes them with a handler spec.
-/
import HALean.Core.Probatio
import HALean.Core.State

namespace HALean.Core
open HALean.Template

/-! ## Types -/

/-- `homeassistant.core.SupportsResponse` -/
inductive SupportsResponse where
  | none | optional | only
  deriving DecidableEq, Repr, Inhabited

def SupportsResponse.value : SupportsResponse → String
  | .none => "none" | .optional => "optional" | .only => "only"

def SupportsResponse.ofString? : String → Option SupportsResponse
  | "none" => some .none
  | "optional" => some .optional
  | "only" => some .only
  | _ => Option.none

/-- What a registered handler does when it is called. -/
inductive HandlerSpec where
  /-- `return <value>` -/
  | ret (v : Value)
  /-- returns `{"domain", "service", "data", "return_response", "context_id"}`
  of the `ServiceCall` it received -/
  | echo
  /-- `raise <exception>(<message>)` -/
  | raise (exception : String) (message : String)
  deriving Inhabited

/-- `homeassistant.core.Service`: the job, the schema and `supports_response`. -/
structure Service where
  handler : HandlerSpec
  schema : Option SchemaSpec := none
  supportsResponse : SupportsResponse := .none
  deriving Inhabited

/-- `ServiceRegistry._services`: `dict[str, dict[str, Service]]`, as
insertion-ordered association lists. -/
abbrev Registry := List (String × List (String × Service))

/-- A fresh `Context()` in the standalone registry: its id is a random ULID
upstream, written `new` here (the differential test renames HA's the same
way). -/
def Registry.freshContext : Context := { id := "new" }

/-- An `EventBus.async_fire_internal` call the registry makes: event type,
data, and the context it passes (`none`: no context, so the bus's `Event`
makes one). `timeFired` is the clock when it is fired (ms). The joined core
(`HALean/Core/Hass.lean`) hands these to the bus model. -/
structure FiredEvent where
  eventType : String
  data : List (String × Value)
  timeFired : Millis
  context : Option Context := none
  deriving Inhabited

structure LogRecord where
  level : String
  message : String
  /-- `exc_info`, as `"<class>: <message>"` -/
  exception : Option String := none
  deriving Inhabited

/-- An exception raised to the caller. `translation` is
`(translation_domain, translation_key, translation_placeholders)` for the
`HomeAssistantError`s built from a translation key. -/
structure PyError where
  exception : String
  message : String
  translation : Option (String × String × List (String × String)) := none
  deriving Inhabited

/-- The automation protocol's `error_kind` (`protocol/schema.json`):
`invalid` for `vol.Invalid` (here `probatio.Invalid`), `ha_error` for
`HomeAssistantError` and its subclasses, `other` for anything else. -/
def errorKind (exception : String) : String :=
  if exception == "Invalid" || exception == "MultipleInvalid" then "invalid"
  else if exception == "HomeAssistantError" || exception == "ServiceValidationError"
    || exception == "ServiceNotFound" || exception == "InvalidEntityFormatError"
    || exception == "InvalidStateError" then "ha_error"
  else "other"

/-- The handler exceptions a `HandlerSpec.raise` may name. -/
def handlerExceptions : List String :=
  ["HomeAssistantError", "ServiceValidationError", "Invalid", "ValueError", "RuntimeError"]

/-- `homeassistant/components/homeassistant/strings.json` (English), the
exception messages `async_get_exception_message` looks up. -/
def exceptionTemplate : String → Option String
  | "service_not_found" => some "Action {domain}.{service} not found."
  | "service_should_be_blocking" =>
    some "A non-blocking action call with argument {non_blocking_argument} can't be used together with argument {return_response}."
  | "service_does_not_support_response" =>
    some "An action which does not return responses can't be called with {return_response}."
  | "service_lacks_response_request" =>
    some "The action requires responses and must be called with {return_response}."
  | "service_reponse_invalid" =>
    some "Failed to process the returned action response data, expected a dictionary, but got {response_data_type}."
  | _ => none

/-- `str.format(**placeholders)` for templates whose fields are plain names. -/
def formatPlaceholders (tpl : String) (ph : List (String × String)) : String :=
  ph.foldl (fun acc (k, v) => acc.replace ("{" ++ k ++ "}") v) tpl

/-- `str.rstrip(".")` -/
def rstripDots (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (· == '.')).reverse

/-- `helpers/translation.py::async_get_exception_message` (translations
cached, English). -/
def exceptionMessage (key : String) (ph : List (String × String)) : String :=
  match exceptionTemplate key with
  | some tpl => if ph.isEmpty then rstripDots tpl else formatPlaceholders (rstripDots tpl) ph
  | none => key

/-- `HomeAssistantError(translation_domain="homeassistant", translation_key=..., ...)`
and its subclasses: `str()` is the translated message. -/
def translatedError (exception key : String) (ph : List (String × String)) : PyError :=
  { exception, message := exceptionMessage key ph, translation := some ("homeassistant", key, ph) }

/-- `homeassistant/exceptions.py::ServiceNotFound` -/
def serviceNotFound (domain service : String) : PyError :=
  translatedError "ServiceNotFound" "service_not_found" [("domain", domain), ("service", service)]

/-! ## Dict helpers (Python `dict` semantics on association lists) -/

def assocGet? {α} (xs : List (String × α)) (k : String) : Option α :=
  (xs.find? (·.1 == k)).map (·.2)

/-- `d[k] = v`: replace in place or append. -/
def assocSet {α} (xs : List (String × α)) (k : String) (v : α) : List (String × α) :=
  if xs.any (·.1 == k) then xs.map fun p => if p.1 == k then (k, v) else p
  else xs ++ [(k, v)]

/-- `d.pop(k)` -/
def assocErase {α} (xs : List (String × α)) (k : String) : List (String × α) :=
  xs.filter (·.1 != k)

/-- `self._services[domain][service]` -/
def Registry.lookup (r : Registry) (domain service : String) : Option Service :=
  (assocGet? r domain).bind fun svcs => assocGet? svcs service

/-! ## Registry operations -/

/-- `ServiceRegistry.has_service` -/
def Registry.hasService (r : Registry) (domain service : String) : Bool :=
  match assocGet? r domain.toLower with
  | some svcs => svcs.any (·.1 == service.toLower)
  | none => false

/-- `ServiceRegistry.supports_response`: a missing domain or service raises
`KeyError` (only a falsy `Service` would return `NONE`, and a `Service` is
always truthy). -/
def Registry.supportsResponse (r : Registry) (domain service : String) :
    Except PyError SupportsResponse :=
  match assocGet? r domain.toLower with
  | none => .error { exception := "KeyError", message := strRepr domain.toLower }
  | some svcs => match assocGet? svcs service.toLower with
    | none => .error { exception := "KeyError", message := strRepr service.toLower }
    | some h => .ok h.supportsResponse

/-- `ServiceRegistry.async_services`: a copy of the whole registry. -/
def Registry.asyncServices (r : Registry) : Registry := r

/-- `ServiceRegistry.async_services_for_domain`. The domain is **not**
lowercased here, unlike everywhere else. -/
def Registry.asyncServicesForDomain (r : Registry) (domain : String) : List (String × Service) :=
  (assocGet? r domain).getD []

/-- `ServiceRegistry._async_register` (called by `async_register`): lowercase
domain and service, replace or add the service, fire `service_registered`. -/
def Registry.register (r : Registry) (domain service : String) (svc : Service)
    (now : Millis) : Registry × List FiredEvent :=
  let domain := domain.toLower
  let service := service.toLower
  let r := match assocGet? r domain with
    | some svcs => assocSet r domain (assocSet svcs service svc)
    | none => assocSet r domain [(service, svc)]
  (r, [{ eventType := "service_registered", timeFired := now,
         data := [("domain", .str domain), ("service", .str service)] }])

/-- `ServiceRegistry._async_remove` (called by `async_remove`): removing an
unknown service only logs a warning; a domain left empty is dropped. -/
def Registry.remove (r : Registry) (domain service : String) (now : Millis) :
    Registry × List FiredEvent × List LogRecord :=
  let domain := domain.toLower
  let service := service.toLower
  match assocGet? r domain with
  | some svcs =>
    if svcs.any (·.1 == service) then
      let svcs := assocErase svcs service
      let r := if svcs.isEmpty then assocErase r domain else assocSet r domain svcs
      (r, [{ eventType := "service_removed", timeFired := now,
             data := [("domain", .str domain), ("service", .str service)] }], [])
    else (r, [], [unknown domain service])
  | none => (r, [], [unknown domain service])
where
  unknown (d s : String) : LogRecord :=
    { level := "warning", message := s!"Unable to remove unknown service {d}/{s}" }

/-! ## Calling a service -/

/-- `ServiceCall` -/
structure ServiceCall where
  domain : String
  service : String
  data : List (String × Value)
  context : Context
  returnResponse : Bool

/-- `homeassistant/util/__init__.py::repr_helper` -/
partial def reprHelper : Value → Except String String
  | .dict kvs => do
    let parts ← kvs.mapM fun (k, v) => do pure ((← reprHelper k) ++ "=" ++ (← reprHelper v))
    pure (", ".intercalate parts)
  | v => pyStr v

/-- `ServiceCall.__repr__` -/
def ServiceCall.repr (c : ServiceCall) : Except String String := do
  let ctx := c.context.id
  if c.data.isEmpty then return s!"<ServiceCall {c.domain}.{c.service} (c:{ctx})>"
  return s!"<ServiceCall {c.domain}.{c.service} (c:{ctx}): {← reprHelper (dictOf c.data)}>"

/-- Run the handler on a call (`ServiceRegistry._execute_service`). -/
def runHandler (h : HandlerSpec) (c : ServiceCall) : Except PyError Value :=
  match h with
  | .ret v => .ok v
  | .echo => .ok <| dictOf [("domain", .str c.domain), ("service", .str c.service),
      ("data", dictOf c.data), ("return_response", .bool c.returnResponse),
      ("context_id", .str c.context.id)]
  | .raise exc msg => .error { exception := exc, message := msg }

/-- The arguments of `ServiceRegistry.async_call`. `data`/`target` `none`
is `None`. -/
structure CallArgs where
  domain : String
  service : String
  data : Option (List (String × Value)) := none
  blocking : Bool := false
  context : Option Context := none
  target : Option (List (String × Value)) := none
  returnResponse : Bool := false

/-- What `async_call` did: its result (the response, `None`, or the exception
it raised), the events it fired and what it logged. -/
structure CallOutcome where
  result : Except PyError Value
  events : List FiredEvent := []
  logs : List LogRecord := []

/-- The handler lookup of `async_call`: `self._services[domain][service]` with
the names as given, then (on `KeyError`) with the names lowercased. Returns
the names the call goes on with. -/
def Registry.find (r : Registry) (domain service : String) : Option (String × String × Service) :=
  match r.lookup domain service with
  | some h => some (domain, service, h)
  | none => (r.lookup domain.toLower service.toLower).map
      fun h => (domain.toLower, service.toLower, h)

/-- Python's `type(x)` as `str()` prints it. -/
def pyTypeStr : Value → String
  | .none => "<class 'NoneType'>"
  | .bool _ => "<class 'bool'>"
  | .int _ => "<class 'int'>"
  | .float _ => "<class 'float'>"
  | .str _ => "<class 'str'>"
  | .list _ => "<class 'list'>"
  | .tuple _ => "<class 'tuple'>"
  | .dict _ => "<class 'dict'>"
  | _ => "<class 'object'>"

def serviceValidationError (key : String) (ph : List (String × String)) : PyError :=
  translatedError "ServiceValidationError" key ph

/-- What `async_call` has worked out when it fires `call_service` and runs the
handler: the names it goes on with, the `Service` it found, the
`ServiceCall`, and the merged, unvalidated data that `call_service` carries. -/
structure PreparedCall where
  domain : String
  service : String
  svc : Service
  call : ServiceCall
  serviceData : List (String × Value)

/-- The `return_response` rules of `async_call`: `return_response=True` needs
`blocking=True` and a service that supports responses; a
`SupportsResponse.ONLY` service needs `return_response=True`. -/
def responseCheck (a : CallArgs) (sr : SupportsResponse) : Option PyError :=
  let rr := [("return_response", "return_response=True")]
  if a.returnResponse then
    if !a.blocking then
      some (serviceValidationError "service_should_be_blocking"
        [("return_response", "return_response=True"), ("non_blocking_argument", "blocking=False")])
    else if sr == .none then some (serviceValidationError "service_does_not_support_response" rr)
    else none
  else if sr == .only then some (serviceValidationError "service_lacks_response_request" rr)
  else none

/-- `if target: service_data.update(target)` -/
def mergeTarget (data : List (String × Value)) : Option (List (String × Value)) → List (String × Value)
  | some t@(_ :: _) => t.foldl (fun d (k, v) => assocSet d k v) data
  | _ => data

/-- `ServiceRegistry.async_call` up to `call_service` (`context` is already
`context or Context()`):

* The lookup tries the names as given, then lowercased (`ServiceNotFound`
  carries the lowercased names).
* The `return_response` rules (`responseCheck`), all `ServiceValidationError`.
* `target` is merged into the data, then the schema validates it
  (`probatio.Invalid` propagates). -/
def Registry.prepareCall (r : Registry) (a : CallArgs) (context : Context) :
    Except PyError PreparedCall :=
  match r.find a.domain a.service with
  | none => .error (serviceNotFound a.domain.toLower a.service.toLower)
  | some (domain, service, handler) =>
    match responseCheck a handler.supportsResponse with
    | some e => .error e
    | none =>
      -- `service_data = service_data or {}`, then the target
      let serviceData := mergeTarget (a.data.getD []) a.target
      let validated := match handler.schema with
        | some sch => sch.validate serviceData
        | none => .ok serviceData
      match validated with
      | .error errs => .error { exception := "MultipleInvalid", message := multipleInvalidStr errs }
      | .ok processed =>
        .ok { domain, service, svc := handler, serviceData,
              call := { domain, service, data := processed, context, returnResponse := a.returnResponse } }

/-- The `call_service` event `async_call` fires (with the call's context). -/
def PreparedCall.event (p : PreparedCall) (now : Millis) : FiredEvent :=
  { eventType := "call_service", timeFired := now, context := some p.call.context,
    data := [("domain", .str p.domain), ("service", .str p.service),
             ("service_data", dictOf p.serviceData)] }

/-- `async_call` after the handler ran (`res` is its outcome). Not blocking:
its errors are logged by `_run_service_call_catch_exceptions`, never raised,
and the result is `None`. Blocking: its errors propagate, and a response is
returned only when asked for, and must be a dict (`HomeAssistantError`
otherwise). -/
def finishCall (a : CallArgs) (call : ServiceCall) (res : Except PyError Value) :
    Except PyError Value × List LogRecord :=
  if !a.blocking then
    let logs := match res with
      | .ok _ => []
      | .error e =>
        let callRepr := match call.repr with | .ok s => s | .error m => m
        [{ level := "error", message := s!"Error executing service: {callRepr}",
           exception := some s!"{e.exception}: {e.message}" }]
    (.ok .none, logs)
  else match res with
    | .error e => (.error e, [])
    | .ok resp =>
      if !a.returnResponse then (.ok .none, [])
      else match resp with
        | .dict _ => (.ok resp, [])
        | v => (.error (translatedError "HomeAssistantError" "service_reponse_invalid"
            [("response_data_type", pyTypeStr v)]), [])

/-- `ServiceRegistry.async_call` (with `_execute_service` and
`_run_service_call_catch_exceptions`) for a handler spec:
`prepareCall`, `call_service` with the merged, unvalidated data, the
handler, `finishCall`. -/
def Registry.asyncCall (r : Registry) (a : CallArgs) (now : Millis) : CallOutcome :=
  match r.prepareCall a (a.context.getD Registry.freshContext) with
  | .error e => { result := .error e }
  | .ok p =>
    let (result, logs) := finishCall a p.call (runHandler p.svc.handler p.call)
    { result, events := [p.event now], logs }

end HALean.Core
