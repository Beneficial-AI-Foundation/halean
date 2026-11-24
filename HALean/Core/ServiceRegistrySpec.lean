/-
  More specifications for `HALean/Core/ServiceRegistry.lean` (what
  `ServiceRegistryProofs.lean` does not cover): `SupportsResponse`, the
  protocol's `error_kind`, the translated exception messages, the
  `return_response` rules, `target` merging, `prepareCall` / `finishCall` /
  `runHandler` (the two halves of `async_call`), and the read operations
  (`supports_response`, `async_services`, `async_services_for_domain`).
-/
import HALean.Core.ServiceRegistry
import HALean.Core.ServiceRegistryProofs

namespace HALean.Core
open HALean.Template

/-! ## `SupportsResponse` -/

/-- `SupportsResponse(value)` inverts `.value`. -/
theorem SupportsResponse.ofString?_value (s : SupportsResponse) :
    SupportsResponse.ofString? s.value = some s := by
  cases s <;> rfl

/-- ... and only the three enum values parse. -/
theorem SupportsResponse.ofString?_eq_some_iff (str : String) (s : SupportsResponse) :
    SupportsResponse.ofString? str = some s ↔ str = s.value := by
  constructor
  · intro h
    unfold SupportsResponse.ofString? at h
    split at h <;> simp_all [SupportsResponse.value] <;> (subst h; rfl)
  · rintro rfl; exact SupportsResponse.ofString?_value s

theorem SupportsResponse.value_injective (a b : SupportsResponse) (h : a.value = b.value) :
    a = b := by
  have := SupportsResponse.ofString?_value a
  rw [h, SupportsResponse.ofString?_value] at this
  exact (Option.some.inj this).symm

/-! ## `error_kind` -/

/-- `invalid` is exactly `vol.Invalid` and `vol.MultipleInvalid`. -/
theorem errorKind_invalid_iff (e : String) :
    errorKind e = "invalid" ↔ e = "Invalid" ∨ e = "MultipleInvalid" := by
  unfold errorKind
  split
  · simp_all
  · split <;> simp_all

/-- `ha_error` is exactly `HomeAssistantError` and its four subclasses the
core raises. -/
theorem errorKind_ha_error_iff (e : String) :
    errorKind e = "ha_error" ↔
      e ∈ ["HomeAssistantError", "ServiceValidationError", "ServiceNotFound",
           "InvalidEntityFormatError", "InvalidStateError"] := by
  unfold errorKind
  split
  · rename_i h
    simp only [Bool.or_eq_true, beq_iff_eq] at h
    rcases h with rfl | rfl <;> simp
  · split
    · rename_i h
      simp only [Bool.or_eq_true, beq_iff_eq] at h
      simp only [List.mem_cons, List.not_mem_nil, or_false, true_iff]
      rcases h with (((h | h) | h) | h) | h <;> simp [h]
    · rename_i h
      simp only [Bool.or_eq_true, beq_iff_eq, not_or] at h
      simp [h]

/-- There are only three kinds. -/
theorem errorKind_range (e : String) : errorKind e ∈ ["invalid", "ha_error", "other"] := by
  unfold errorKind
  split
  · simp
  · split <;> simp

/-- Of the exceptions a handler spec may raise, the two `HomeAssistantError`
classes are `ha_error`, `Invalid` is `invalid`, and the builtins are
`other`. -/
theorem errorKind_handlerExceptions (e : String) (h : e ∈ handlerExceptions) :
    errorKind e =
      if e = "Invalid" then "invalid"
      else if e = "ValueError" ∨ e = "RuntimeError" then "other" else "ha_error" := by
  simp only [handlerExceptions, List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with rfl | rfl | rfl | rfl | rfl <;> decide

/-! ## Translated messages -/

/-- Exactly the five keys the registry uses have an English template. -/
theorem exceptionTemplate_isSome_iff (key : String) :
    (exceptionTemplate key).isSome = true ↔
      key ∈ ["service_not_found", "service_should_be_blocking",
             "service_does_not_support_response", "service_lacks_response_request",
             "service_reponse_invalid"] := by
  unfold exceptionTemplate
  split <;> simp_all

/-- `str.format` with no placeholders is the identity. -/
theorem formatPlaceholders_nil (tpl : String) : formatPlaceholders tpl [] = tpl := rfl

/-- Placeholders are substituted one after the other, in order. -/
theorem formatPlaceholders_append (tpl : String) (a b : List (String × String)) :
    formatPlaceholders tpl (a ++ b) = formatPlaceholders (formatPlaceholders tpl a) b := by
  simp [formatPlaceholders, List.foldl_append]

/-- `rstripDots s` is `s` without some number of trailing dots ... -/
theorem rstripDots_prefix (s : String) :
    ∃ n, s.toList = (rstripDots s).toList ++ List.replicate n '.' := by
  unfold rstripDots
  refine ⟨(s.toList.reverse.takeWhile (· == '.')).length, ?_⟩
  have h := List.takeWhile_append_dropWhile (p := (· == '.')) (l := s.toList.reverse)
  have h2 := congrArg List.reverse h
  simp only [List.reverse_append, List.reverse_reverse] at h2
  have hall : (s.toList.reverse.takeWhile (· == '.')).reverse
      = List.replicate (s.toList.reverse.takeWhile (· == '.')).length '.' := by
    rw [List.eq_replicate_iff]
    refine ⟨by simp, ?_⟩
    intro b hb
    have := List.all_eq_true.mp (List.all_takeWhile (p := (· == '.')) (l := s.toList.reverse)) b
      (List.mem_reverse.mp hb)
    simpa using this
  rw [String.toList_ofList, ← hall]
  exact h2.symm

/-- ... and all of them: the result does not end in a dot. Together with
`rstripDots_prefix` this is Python's `str.rstrip(".")`. -/
theorem rstripDots_no_trailing_dot (s : String) : (rstripDots s).toList.getLast? ≠ some '.' := by
  unfold rstripDots
  rw [String.toList_ofList, List.getLast?_reverse]
  have h := List.head?_dropWhile_not (· == '.') s.toList.reverse
  intro hc
  rw [hc] at h
  simp at h

/-- A string that does not end in a dot is unchanged. -/
theorem rstripDots_of_no_trailing_dot (s : String) (h : s.toList.getLast? ≠ some '.') :
    rstripDots s = s := by
  unfold rstripDots
  have hd : s.toList.reverse.dropWhile (· == '.') = s.toList.reverse := by
    cases hr : s.toList.reverse with
    | nil => rfl
    | cons c rest =>
      have hc : s.toList.getLast? = some c := by
        rw [← List.head?_reverse, hr]; rfl
      have : (c == '.') = false := by
        rw [hc] at h
        simpa using fun e : c = '.' => h (by rw [e])
      simp [this]
  rw [hd, List.reverse_reverse, String.ofList_toList]

theorem rstripDots_idem (s : String) : rstripDots (rstripDots s) = rstripDots s :=
  rstripDots_of_no_trailing_dot _ (rstripDots_no_trailing_dot s)

/-- An unknown translation key is its own message. -/
theorem exceptionMessage_unknown (key : String) (ph : List (String × String))
    (h : exceptionTemplate key = none) : exceptionMessage key ph = key := by
  simp [exceptionMessage, h]

/-- Without placeholders, a known key's message is its template without the
final period. -/
theorem exceptionMessage_no_placeholders (key tpl : String)
    (h : exceptionTemplate key = some tpl) :
    exceptionMessage key [] = rstripDots tpl ∧
    (exceptionMessage key []).toList.getLast? ≠ some '.' := by
  have : exceptionMessage key [] = rstripDots tpl := by simp [exceptionMessage, h]
  exact ⟨this, this ▸ rstripDots_no_trailing_dot tpl⟩

/-- A translated error keeps its class, and records domain `homeassistant`,
the key and the placeholders; its `str()` is the translated message. -/
theorem translatedError_spec (exc key : String) (ph : List (String × String)) :
    (translatedError exc key ph).exception = exc ∧
    (translatedError exc key ph).message = exceptionMessage key ph ∧
    (translatedError exc key ph).translation = some ("homeassistant", key, ph) := ⟨rfl, rfl, rfl⟩

/-- `ServiceNotFound` and `ServiceValidationError` are `ha_error`s. -/
theorem errorKind_registry_errors (d s key : String) (ph : List (String × String)) :
    errorKind (serviceNotFound d s).exception = "ha_error" ∧
    errorKind (serviceValidationError key ph).exception = "ha_error" := by
  constructor
  · show errorKind "ServiceNotFound" = "ha_error"; decide
  · show errorKind "ServiceValidationError" = "ha_error"; decide

/-! ## The `return_response` rules -/

/-- `async_call` accepts the `return_response` / `blocking` combination
exactly when: a response is asked for only from a blocking call to a service
that supports one, and a response-only service is asked for one. -/
theorem responseCheck_none_iff (a : CallArgs) (sr : SupportsResponse) :
    responseCheck a sr = none ↔
      (a.returnResponse = true → a.blocking = true ∧ sr ≠ .none) ∧
      (a.returnResponse = false → sr ≠ .only) := by
  cases hr : a.returnResponse <;> cases hb : a.blocking <;> cases sr <;>
    simp [responseCheck, hr, hb]

/-- Every rejection is a translated `ServiceValidationError`. -/
theorem responseCheck_error (a : CallArgs) (sr : SupportsResponse) (e : PyError)
    (h : responseCheck a sr = some e) :
    e.exception = "ServiceValidationError" ∧
    ∃ key ph, e.translation = some ("homeassistant", key, ph) ∧
      key ∈ ["service_should_be_blocking", "service_does_not_support_response",
             "service_lacks_response_request"] := by
  unfold responseCheck at h
  simp only at h
  repeat' split at h
  all_goals first
    | (cases h; done)
    | (cases h; exact ⟨rfl, _, _, rfl, by simp⟩)

/-- A service that supports optional responses accepts every blocking call,
and every call that does not ask for a response. -/
theorem responseCheck_optional (a : CallArgs) (h : a.returnResponse = true → a.blocking = true) :
    responseCheck a .optional = none := by
  rw [responseCheck_none_iff]
  exact ⟨fun hr => ⟨h hr, by simp⟩, fun _ => by simp⟩

/-! ## `target` merging -/

/-- `if target:` — `None` and `{}` leave the data alone. -/
theorem mergeTarget_falsy (data : List (String × Value)) :
    mergeTarget data none = data ∧ mergeTarget data (some []) = data := ⟨rfl, rfl⟩

private theorem any_assocSet_of_any {α} (xs : List (String × α)) (k k' : String) (v : α)
    (h : xs.any (·.1 == k') = true) : (assocSet xs k v).any (·.1 == k') = true := by
  unfold assocSet
  split
  · obtain ⟨p, hp, hpk⟩ := List.any_eq_true.mp h
    rw [List.any_eq_true]
    by_cases hk : p.1 == k
    · refine ⟨(k, v), List.mem_map.mpr ⟨p, hp, by simp [hk]⟩, ?_⟩
      have : p.1 = k := by simpa using hk
      simpa [← this] using hpk
    · exact ⟨p, List.mem_map.mpr ⟨p, hp, by simp [hk]⟩, hpk⟩
  · simp [h]

private theorem any_assocSet_self {α} (xs : List (String × α)) (k : String) (v : α) :
    (assocSet xs k v).any (·.1 == k) = true :=
  any_of_assocGet?_some (assocGet?_assocSet xs k v)

private theorem any_foldl_assocSet {α} (t : List (String × α)) (d : List (String × α)) (k : String)
    (h : d.any (·.1 == k) = true) :
    (t.foldl (fun d (kv : String × α) => assocSet d kv.1 kv.2) d).any (·.1 == k) = true := by
  induction t generalizing d with
  | nil => exact h
  | cons p rest ih => exact ih _ (any_assocSet_of_any d p.1 k p.2 h)

private theorem mergeTarget_some (data t : List (String × Value)) :
    mergeTarget data (some t) = t.foldl (fun d (kv : String × Value) => assocSet d kv.1 kv.2) data := by
  cases t <;> rfl

/-- `dict.update` never drops a key: every key of the data is still there. -/
theorem mergeTarget_keeps_keys (data : List (String × Value))
    (t : Option (List (String × Value))) (k : String) (h : data.any (·.1 == k) = true) :
    (mergeTarget data t).any (·.1 == k) = true := by
  cases t with
  | none => exact h
  | some t => rw [mergeTarget_some]; exact any_foldl_assocSet t data k h

/-- ... and every key of the target is there afterwards. -/
theorem mergeTarget_has_target_keys (data t : List (String × Value)) (k : String) (v : Value)
    (h : (k, v) ∈ t) : (mergeTarget data (some t)).any (·.1 == k) = true := by
  rw [mergeTarget_some]
  induction t generalizing data with
  | nil => cases h
  | cons p rest ih =>
    simp only [List.foldl_cons]
    rcases List.mem_cons.mp h with rfl | h
    · exact any_foldl_assocSet rest _ _ (any_assocSet_self data _ _)
    · exact ih _ h

/-- A one-key target (the usual `{"entity_id": ...}`) overrides that key of
the data. -/
theorem mergeTarget_single (data : List (String × Value)) (k : String) (v : Value) :
    assocGet? (mergeTarget data (some [(k, v)])) k = some v :=
  assocGet?_assocSet data k v

/-! ## Handlers -/

/-- A handler fails exactly when its spec is `raise`, with that exception. -/
theorem runHandler_error_iff (h : HandlerSpec) (c : ServiceCall) (e : PyError) :
    runHandler h c = .error e ↔
      ∃ exc msg, h = .raise exc msg ∧ e.exception = exc ∧ e.message = msg ∧ e.translation = none := by
  cases h with
  | ret v => simp [runHandler]
  | echo => simp [runHandler]
  | raise exc msg =>
    constructor
    · intro h; simp only [runHandler] at h; cases h; exact ⟨_, _, rfl, rfl, rfl, rfl⟩
    · rintro ⟨_, _, h, h1, h2, h3⟩
      cases h; cases e; simp_all [runHandler]

/-- `return <value>` ignores the call. -/
theorem runHandler_ret (v : Value) (c : ServiceCall) : runHandler (.ret v) c = .ok v := rfl

/-- The echo handler always returns a dict, so it is a valid response. -/
theorem runHandler_echo_dict (c : ServiceCall) : ∃ kvs, runHandler .echo c = .ok (.dict kvs) :=
  ⟨_, rfl⟩

/-- `pyTypeStr` says `dict` exactly for dicts (the one type `async_call`
accepts as a response). -/
theorem pyTypeStr_dict_iff (v : Value) : pyTypeStr v = "<class 'dict'>" ↔ ∃ kvs, v = .dict kvs := by
  cases v <;> simp [pyTypeStr]

/-! ## `finishCall`: after the handler -/

/-- A non-blocking call always returns `None`; the handler's error is logged
(once, at level `error`, with the exception as `exc_info`) and never
raised. -/
theorem finishCall_non_blocking (a : CallArgs) (call : ServiceCall) (res : Except PyError Value)
    (hb : a.blocking = false) :
    (finishCall a call res).1 = .ok .none ∧
    (∀ v, res = .ok v → (finishCall a call res).2 = []) ∧
    (∀ e, res = .error e → ∃ msg, (finishCall a call res).2.map (fun l => (l.level, l.message, l.exception))
        = [("error", msg, some s!"{e.exception}: {e.message}")]) := by
  unfold finishCall
  simp only [hb, Bool.not_false, ite_true]
  refine ⟨trivial, ?_, ?_⟩
  · rintro v rfl; rfl
  · rintro e rfl; exact ⟨_, rfl⟩

/-- A blocking call logs nothing and re-raises the handler's error. -/
theorem finishCall_blocking_error (a : CallArgs) (call : ServiceCall) (e : PyError)
    (hb : a.blocking = true) : finishCall a call (.error e) = (.error e, []) := by
  simp [finishCall, hb]

/-- A blocking call never logs. -/
theorem finishCall_blocking_no_logs (a : CallArgs) (call : ServiceCall)
    (res : Except PyError Value) (hb : a.blocking = true) : (finishCall a call res).2 = [] := by
  unfold finishCall
  simp only [hb, Bool.not_true, Bool.false_eq_true, ite_false]
  repeat' split
  all_goals rfl

/-- Without `return_response` the handler's value is dropped. -/
theorem finishCall_no_response (a : CallArgs) (call : ServiceCall) (v : Value)
    (hb : a.blocking = true) (hr : a.returnResponse = false) :
    finishCall a call (.ok v) = (.ok .none, []) := by
  simp [finishCall, hb, hr]

/-- With `return_response` a dict response is returned as is. -/
theorem finishCall_response_dict (a : CallArgs) (call : ServiceCall) (kvs : List (Value × Value))
    (hb : a.blocking = true) (hr : a.returnResponse = true) :
    finishCall a call (.ok (.dict kvs)) = (.ok (.dict kvs), []) := by
  simp [finishCall, hb, hr]

/-- ... and anything else is a translated `HomeAssistantError` naming the
response's type. -/
theorem finishCall_response_not_dict (a : CallArgs) (call : ServiceCall) (v : Value)
    (hb : a.blocking = true) (hr : a.returnResponse = true) (hv : ∀ kvs, v ≠ .dict kvs) :
    ∃ e, (finishCall a call (.ok v)).1 = .error e ∧ e.exception = "HomeAssistantError" ∧
      e.translation = some ("homeassistant", "service_reponse_invalid",
        [("response_data_type", pyTypeStr v)]) := by
  unfold finishCall
  simp only [hb, hr, Bool.not_true, Bool.false_eq_true, ite_false]
  first
    | exact ⟨_, rfl, rfl, rfl⟩
    | (split
       · rename_i kvs; exact absurd rfl (hv kvs)
       · exact ⟨_, rfl, rfl, rfl⟩)

/-- The echo handler's response always gets through a blocking
`return_response` call. -/
theorem finishCall_echo (a : CallArgs) (call : ServiceCall)
    (hb : a.blocking = true) (hr : a.returnResponse = true) :
    (finishCall a call (runHandler .echo call)).1 = runHandler .echo call := by
  obtain ⟨kvs, h⟩ := runHandler_echo_dict call
  rw [h, finishCall_response_dict a call kvs hb hr]

/-- `ServiceCall.__repr__` of a call without data never fails (no value has
to be printed). -/
theorem ServiceCall.repr_no_data (c : ServiceCall) (h : c.data = []) : ∃ s, c.repr = .ok s := by
  unfold ServiceCall.repr
  simp [h, pure, Except.pure]

/-! ## `prepareCall`: `async_call` up to `call_service` -/

/-- An unknown service: `ServiceNotFound` with the lowercased names. -/
theorem prepareCall_not_found (r : Registry) (a : CallArgs) (c : Context)
    (h : r.find a.domain a.service = none) :
    r.prepareCall a c = .error (serviceNotFound a.domain.toLower a.service.toLower) := by
  simp [Registry.prepareCall, h]

/-- A rejected `return_response` combination is raised before the schema
runs. -/
theorem prepareCall_response_error (r : Registry) (a : CallArgs) (c : Context)
    (d s : String) (svc : Service) (e : PyError)
    (hf : r.find a.domain a.service = some (d, s, svc))
    (hr : responseCheck a svc.supportsResponse = some e) :
    r.prepareCall a c = .error e := by
  simp [Registry.prepareCall, hf, hr]

/-- What a prepared call is: the service the lookup found, a
`return_response` combination that passed, the merged (unvalidated) data, and
a `ServiceCall` under the found names with the caller's context and
`return_response`. Without a schema the call's data is the merged data. -/
theorem prepareCall_ok (r : Registry) (a : CallArgs) (c : Context) (p : PreparedCall)
    (h : r.prepareCall a c = .ok p) :
    r.find a.domain a.service = some (p.domain, p.service, p.svc) ∧
    responseCheck a p.svc.supportsResponse = none ∧
    p.serviceData = mergeTarget (a.data.getD []) a.target ∧
    p.call.domain = p.domain ∧ p.call.service = p.service ∧
    p.call.context = c ∧ p.call.returnResponse = a.returnResponse ∧
    (p.svc.schema = none → p.call.data = p.serviceData) := by
  unfold Registry.prepareCall at h
  split at h
  · cases h
  · rename_i d s svc hf
    split at h
    · cases h
    · rename_i hrc
      simp only at h
      split at h
      · cases h
      · cases h
      · cases h
      · rename_i processed hv
        cases h
        refine ⟨hf, hrc, rfl, rfl, rfl, rfl, rfl, ?_⟩
        intro hs
        simp only at hs
        rw [hs] at hv
        simp only [Except.ok.injEq] at hv
        exact hv.symm

/-- With a schema, the call's data is what the schema returned for the merged
data (while `call_service` still carries the unvalidated data). -/
theorem prepareCall_ok_schema (r : Registry) (a : CallArgs) (c : Context) (p : PreparedCall)
    (sch : SchemaSpec) (h : r.prepareCall a c = .ok p) (hs : p.svc.schema = some sch) :
    sch.validate p.serviceData = .ok p.call.data := by
  unfold Registry.prepareCall at h
  split at h
  · cases h
  · split at h
    · cases h
    · simp only at h
      split at h
      · cases h
      · cases h
      · cases h
      · rename_i processed hv
        cases h
        simp only at hs
        rw [hs] at hv
        exact hv

/-- `unsupportedCall?` is exactly the case where `prepareCall` meets input
the schema model does not cover. -/
theorem prepareCall_of_unsupportedCall (r : Registry) (a : CallArgs) (c : Context) (why : String)
    (h : r.unsupportedCall? a = some why) :
    ∃ e, r.prepareCall a c = .error e ∧ e.exception = "unsupported" ∧ e.message = why := by
  unfold Registry.unsupportedCall? at h
  unfold Registry.prepareCall
  split at h
  · cases h
  · rename_i d s svc hf
    split at h
    · rename_i sch hrc hsch
      simp only [hrc, hsch]
      split at h
      · rename_i why' hv
        cases h
        simp only [hv]
        exact ⟨_, rfl, rfl, rfl⟩
      · cases h
    · cases h

/-- The `call_service` event of a prepared call: fired at `now` with the
call's own context and the found names; `service_data` is the merged data
before validation. -/
theorem prepareCall_event (r : Registry) (a : CallArgs) (c : Context) (p : PreparedCall)
    (now : Millis) (h : r.prepareCall a c = .ok p) :
    (p.event now).eventType = "call_service" ∧ (p.event now).timeFired = now ∧
    (p.event now).context = some c ∧
    (p.event now).data = [("domain", .str p.domain), ("service", .str p.service),
      ("service_data", dictOf (mergeTarget (a.data.getD []) a.target))] := by
  obtain ⟨_, _, hd, _, _, hc, _, _⟩ := prepareCall_ok r a c p h
  simp [PreparedCall.event, hd, hc]

/-! ## `async_call` as a whole -/

/-- `async_call` fires `call_service` exactly when the call got past the
lookup, the `return_response` rules and the schema; an event it fires has
the caller's context, or the fresh `Context()`. -/
theorem asyncCall_events (r : Registry) (a : CallArgs) (now : Millis) :
    (r.asyncCall a now).events.length ≤ 1 ∧
    ((r.asyncCall a now).events = [] ↔
      ∃ e, r.prepareCall a (a.context.getD Registry.freshContext) = .error e) ∧
    ∀ ev ∈ (r.asyncCall a now).events, ev.eventType = "call_service" ∧
      ev.context = some (a.context.getD Registry.freshContext) := by
  unfold Registry.asyncCall
  cases hp : r.prepareCall a (a.context.getD Registry.freshContext) with
  | error e => simp
  | ok p =>
    have := prepareCall_event r a _ p now hp
    simp [this.1, this.2.2.1]

/-- A call that fails before the handler raises that error and logs
nothing. -/
theorem asyncCall_prepare_error (r : Registry) (a : CallArgs) (now : Millis) (e : PyError)
    (h : r.prepareCall a (a.context.getD Registry.freshContext) = .error e) :
    (r.asyncCall a now).result = .error e ∧ (r.asyncCall a now).logs = [] := by
  simp [Registry.asyncCall, h]

/-- A non-blocking call that reaches the handler returns `None`, whatever
the handler does. -/
theorem asyncCall_non_blocking (r : Registry) (a : CallArgs) (now : Millis) (p : PreparedCall)
    (h : r.prepareCall a (a.context.getD Registry.freshContext) = .ok p)
    (hb : a.blocking = false) : (r.asyncCall a now).result = .ok .none := by
  simp only [Registry.asyncCall, h]
  exact (finishCall_non_blocking a p.call _ hb).1

/-- A blocking call never logs: the handler's error goes to the caller. -/
theorem asyncCall_blocking_no_logs (r : Registry) (a : CallArgs) (now : Millis)
    (hb : a.blocking = true) : (r.asyncCall a now).logs = [] := by
  unfold Registry.asyncCall
  cases hp : r.prepareCall a (a.context.getD Registry.freshContext) with
  | error e => rfl
  | ok p => exact finishCall_blocking_no_logs a p.call _ hb

/-! ## Reads -/

/-- `has_service` looks the lowercased service up in
`async_services_for_domain` of the lowercased domain. -/
theorem hasService_eq_asyncServicesForDomain (r : Registry) (d s : String) :
    r.hasService d s = (r.asyncServicesForDomain d.toLower).any (·.1 == s.toLower) := by
  unfold Registry.hasService Registry.asyncServicesForDomain
  cases assocGet? r d.toLower <;> simp

/-- `supports_response` returns the registered service's value ... -/
theorem supportsResponse_ok_iff (r : Registry) (d s : String) (x : SupportsResponse) :
    r.supportsResponse d s = .ok x ↔
      ∃ svc, r.lookup d.toLower s.toLower = some svc ∧ svc.supportsResponse = x := by
  cases hd : assocGet? r d.toLower with
  | none => simp [Registry.supportsResponse, Registry.lookup, hd]
  | some svcs =>
    cases hs : assocGet? svcs s.toLower <;>
      simp [Registry.supportsResponse, Registry.lookup, hd, hs]

/-- ... exactly for the services `has_service` reports; otherwise it is a
`KeyError`. -/
theorem supportsResponse_ok_iff_hasService (r : Registry) (d s : String) :
    (∃ x, r.supportsResponse d s = .ok x) ↔ r.hasService d s = true := by
  cases hd : assocGet? r d.toLower with
  | none => simp [Registry.supportsResponse, Registry.hasService, hd]
  | some svcs =>
    cases hs : assocGet? svcs s.toLower with
    | some svc =>
      simp [Registry.supportsResponse, Registry.hasService, hd, hs, any_of_assocGet?_some hs]
    | none =>
      have : svcs.any (·.1 == s.toLower) = false := by
        cases ha : svcs.any (·.1 == s.toLower) with
        | false => rfl
        | true =>
          obtain ⟨p, hp, hk⟩ := List.any_eq_true.mp ha
          simp [assocGet?] at hs
          exact absurd (by simpa using hk) (hs p.1 p.2 hp)
      simp [Registry.supportsResponse, Registry.hasService, hd, hs, this]

theorem supportsResponse_error (r : Registry) (d s : String) (e : PyError)
    (h : r.supportsResponse d s = .error e) : e.exception = "KeyError" := by
  unfold Registry.supportsResponse at h
  repeat' split at h
  all_goals first
    | (cases h; done)
    | (cases h; rfl)

/-- A service just registered is listed by `async_services()` (under its
lowercased domain) and by `async_services_for_domain`. -/
theorem asyncServices_after_register (r : Registry) (d s : String) (svc : Service) (now : Millis) :
    (r.register d s svc now).1.asyncServices.any (·.1 == d.toLower) = true ∧
    ((r.register d s svc now).1.asyncServicesForDomain d.toLower).any (·.1 == s.toLower) = true := by
  have h := has_after_register r d s d s svc now rfl rfl
  have h2 := h
  rw [hasService_eq_asyncServicesForDomain] at h2
  refine ⟨?_, h2⟩
  unfold Registry.hasService at h
  unfold Registry.asyncServices
  cases hg : assocGet? (r.register d s svc now).1 d.toLower with
  | none => simp [hg] at h
  | some svcs => exact any_of_assocGet?_some hg

/-- `async_services_for_domain` does not lowercase: an unknown (for example
upper-case) domain gives `{}`. -/
theorem asyncServicesForDomain_unknown (r : Registry) (d : String)
    (h : r.asyncServices.any (·.1 == d) = false) : r.asyncServicesForDomain d = [] := by
  unfold Registry.asyncServices at h
  unfold Registry.asyncServicesForDomain
  rw [assocGet?_none_of_not_any h]; rfl

end HALean.Core
