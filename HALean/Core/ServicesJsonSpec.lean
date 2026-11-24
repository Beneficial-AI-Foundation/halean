/-
  Specifications for `HALean/Core/ServicesJson.lean`: the field readers of
  the service drivers' input (`getStr`, `getBool`, ...), the fixed `cv.*`
  schema objects (`decodeCv`, `timePeriod`, `timePeriodDict`), the handler /
  schema / context decoders, and the JSON output helpers.

  `decodeValidator`, `decodeField` and `decodeFields` are mutually recursive
  `partial def`s and are not covered.
-/
import HALean.Core.ServicesJson

set_option linter.unusedSimpArgs false

namespace HALean.Core.ServicesJsonSpec
open Lean HALean HALean.Core HALean.Template HALean.Core.ServicesJson

theorem ifP {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by simp [h]
theorem ifN {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by simp [h]

theorem bind_ok {ε α β} {x : Except ε α} {f : α → Except ε β} {b : β}
    (h : (x >>= f) = .ok b) : ∃ a, x = .ok a ∧ f a = .ok b := by
  cases x with
  | error e => cases h
  | ok a => exact ⟨a, rfl, h⟩

/-! ## Text -/

theorem isAscii_iff (s : String) : ServicesJson.isAscii s = true ↔ ∀ c ∈ s.toList, c.toNat < 128 := by
  simp [ServicesJson.isAscii]

theorem isAscii_empty : ServicesJson.isAscii "" = true := rfl

theorem isAscii_append (a b : String) : ServicesJson.isAscii (a ++ b) = (ServicesJson.isAscii a && ServicesJson.isAscii b) := by
  simp [ServicesJson.isAscii, String.toList_append]

/-- Text the validators model (`safeText`) is in particular ASCII, so a name
accepted as schema text is also accepted as a domain or service name. -/
theorem isAscii_of_safeText (s : String) (h : safeText s = true) : ServicesJson.isAscii s = true := by
  rw [isAscii_iff]
  intro c hc
  have := List.all_eq_true.mp h c hc
  simp only [safeChar, Bool.and_eq_true, decide_eq_true_eq] at this
  exact this.1.1.1

/-! ## Field readers -/

/-- `getStr` succeeds exactly when the key holds a string. -/
theorem getStr_ok_iff (v : Value) (k s : String) :
    getStr v k = .ok s ↔ v.get? k = some (.str s) := by
  unfold getStr
  cases h : v.get? k with
  | none => simp
  | some x => cases x <;> simp

/-- A missing key or a value of another type is an error naming the key. -/
theorem getStr_error (v : Value) (k : String) (e : String) (h : getStr v k = .error e) :
    e = s!"'{k}' must be a string" := by
  unfold getStr at h
  split at h
  · cases h
  · cases h; rfl

/-- `getName` is `getStr` restricted to ASCII. -/
theorem getName_ok_iff (v : Value) (k s : String) :
    getName v k = .ok s ↔ v.get? k = some (.str s) ∧ ServicesJson.isAscii s = true := by
  unfold getName
  constructor
  · intro h
    obtain ⟨t, hg, h⟩ := bind_ok h
    have ht := (getStr_ok_iff v k t).mp hg
    by_cases ha : ServicesJson.isAscii t = true
    · simp [ha, pure, Except.pure] at h
      subst h; exact ⟨ht, ha⟩
    · simp [ha, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at h
  · rintro ⟨hs, ha⟩
    rw [(getStr_ok_iff v k s).mpr hs]
    simp [bind, Except.bind, ha, pure, Except.pure]

/-- `getBool`: the default when the key is missing, the value when it is a
`bool`, an error otherwise. -/
theorem getBool_ok_iff (v : Value) (k : String) (dflt b : Bool) :
    getBool v k dflt = .ok b ↔ (v.get? k = none ∧ b = dflt) ∨ v.get? k = some (.bool b) := by
  unfold getBool
  cases h : v.get? k with
  | none => simp [eq_comm]
  | some x => cases x <;> simp

theorem getBool_missing (v : Value) (k : String) (dflt : Bool) (h : v.get? k = none) :
    getBool v k dflt = .ok dflt := (getBool_ok_iff v k dflt dflt).mpr (Or.inl ⟨h, rfl⟩)

/-- `getOptStr`: `None` and a missing key both read as `none`. -/
theorem getOptStr_ok_iff (v : Value) (k : String) (o : Option String) :
    getOptStr v k = .ok o ↔
      ((v.get? k = none ∨ v.get? k = some .none) ∧ o = none) ∨
      ∃ s, v.get? k = some (.str s) ∧ o = some s := by
  unfold getOptStr
  cases h : v.get? k with
  | none => simp [eq_comm]
  | some x => cases x <;> simp [eq_comm]

/-- `getInt?`: only an `int` (not a `bool`, not a float). -/
theorem getInt?_ok_iff (v : Value) (k : String) (o : Option Int) :
    getInt? v k = .ok o ↔
      ((v.get? k = none ∨ v.get? k = some .none) ∧ o = none) ∨
      ∃ i, v.get? k = some (.int i) ∧ o = some i := by
  unfold getInt?
  cases h : v.get? k with
  | none => simp [pure, Except.pure, eq_comm]
  | some x => cases x <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- `getNum?`: an `int` or a `float`, returned as it is (so `1` and `1.0`
stay distinguishable in a `Range` bound's message). -/
theorem getNum?_ok_iff (v : Value) (k : String) (o : Option Value) :
    getNum? v k = .ok o ↔
      ((v.get? k = none ∨ v.get? k = some .none) ∧ o = none) ∨
      ∃ n, v.get? k = some n ∧ o = some n ∧ ((∃ i, n = .int i) ∨ ∃ f, n = .float f) := by
  unfold getNum?
  cases h : v.get? k with
  | none => simp [pure, Except.pure, eq_comm]
  | some x => cases x <;> simp [pure, Except.pure, throw, throwThe, MonadExceptOf.throw, eq_comm]

/-- A numeric bound read by `getNum?` is a number for `Range` / `Clamp`. -/
theorem getNum?_num (v : Value) (k : String) (n : Value) (h : getNum? v k = .ok (some n)) :
    n.num?.isSome = true := by
  rcases (getNum?_ok_iff v k (some n)).mp h with ⟨_, h⟩ | ⟨m, _, hm, hk⟩
  · cases h
  · cases hm
    rcases hk with ⟨i, rfl⟩ | ⟨f, rfl⟩ <;> rfl

/-- `getDict?`: a missing key or `None` is no dict; otherwise the value must
be a string-keyed dict. -/
theorem getDict?_ok_iff (v : Value) (k : String) (o : Option (List (String × Value))) :
    getDict? v k = .ok o ↔
      ((v.get? k = none ∨ v.get? k = some .none) ∧ o = none) ∨
      ∃ d kvs, v.get? k = some d ∧ d ≠ .none ∧ d.strItems? = some kvs ∧ o = some kvs := by
  unfold getDict?
  cases h : v.get? k with
  | none => simp [eq_comm]
  | some x =>
    cases x <;> try (simp [Value.strItems?, eq_comm]; done)
    rename_i kvs
    simp only [reduceCtorEq, or_self, false_and, false_or, Option.some.injEq, ne_eq,
      not_false_eq_true, true_and, exists_eq_left']
    cases hs : (Value.dict kvs).strItems? <;> simp [hs, eq_comm]

/-! ## Scalars and schema text -/

theorem isScalar_iff (v : Value) :
    isScalar v = true ↔
      v = .none ∨ (∃ b, v = .bool b) ∨ (∃ i, v = .int i) ∨ (∃ f, v = .float f) ∨ ∃ s, v = .str s := by
  cases v <;> simp [isScalar]

/-- Containers are not scalars. -/
theorem isScalar_list_dict (xs : List Value) (kvs : List (Value × Value)) :
    isScalar (.list xs) = false ∧ isScalar (.dict kvs) = false := ⟨rfl, rfl⟩

/-- A scalar that is not a string always has a `repr`, so it can label an
`Any` branch (`_branch_label`). -/
theorem isScalar_label (v : Value) (h : isScalar v = true) (hf : ∀ f, v ≠ .float f) :
    ((Validator.literal v).label?).isSome = true := by
  cases v <;> first
    | (simp [isScalar] at h; done)
    | exact absurd rfl (hf _)
    | simp [Validator.label?, pyRepr, Except.toOption, pure, Except.pure]

theorem specText_ok_iff (v : Value) : specText v = .ok () ↔ safeValue v = true := by
  unfold specText
  by_cases h : safeValue v = true
  · simp [h, pure, Except.pure]
  · simp [h, throw, throwThe, MonadExceptOf.throw]

/-- Schema text is accepted exactly when the validators can read it
(`requireSafe`). -/
theorem specText_ok_iff_requireSafe (v : Value) : specText v = .ok () ↔ requireSafe v = .ok () := by
  rw [specText_ok_iff]
  unfold requireSafe
  by_cases h : safeValue v = true
  · simp [h, pure, Except.pure]
  · simp [h, throw, throwThe, MonadExceptOf.throw]

/-! ## `onlyKeys` -/

theorem forIn_ok_all {α ε} {f : α → Except ε (ForInStep PUnit)} {P : α → Prop}
    (hP : ∀ a r, f a = .ok r → r = .yield PUnit.unit ∧ P a) :
    ∀ (l : List α) (u : PUnit), forIn l PUnit.unit (fun a _ => f a) = .ok u → ∀ a ∈ l, P a := by
  intro l
  induction l with
  | nil => intro _ _ a ha; cases ha
  | cons x xs ih =>
    intro u h a ha
    rw [List.forIn_cons] at h
    obtain ⟨r, hr, h⟩ := bind_ok h
    obtain ⟨hy, hx⟩ := hP x r hr
    subst hy
    rcases List.mem_cons.mp ha with rfl | ha
    · exact hx
    · exact ih u h a ha

theorem forIn_all_ok {α ε} {f : α → Except ε (ForInStep PUnit.{1})} :
    ∀ (l : List α), (∀ a ∈ l, f a = .ok (.yield PUnit.unit)) →
      (forIn l PUnit.unit (fun a _ => f a) >>= fun _ => (pure PUnit.unit : Except ε PUnit.{1}))
        = .ok PUnit.unit := by
  intro l
  induction l with
  | nil => intro _; rfl
  | cons x xs ih =>
    intro h
    rw [List.forIn_cons, h x (by simp)]
    exact ih (fun a ha => h a (by simp [ha]))

/-- `onlyKeys` accepts exactly the string-keyed dicts all of whose keys are
allowed. -/
theorem onlyKeys_ok_iff (v : Value) (allowed : List String) (what : String) :
    onlyKeys v allowed what = .ok () ↔
      ∃ kvs, v.strItems? = some kvs ∧ ∀ p ∈ kvs, p.1 ∈ allowed := by
  unfold onlyKeys
  cases hs : v.strItems? with
  | none => simp [bind, Except.bind, throw, throwThe, MonadExceptOf.throw]
  | some kvs =>
    simp only [Option.some.injEq, exists_eq_left']
    constructor
    · intro h
      obtain ⟨u, hfor, _⟩ := bind_ok h
      refine forIn_ok_all (P := fun p => p.1 ∈ allowed) ?_ kvs u hfor
      intro a r hr
      obtain ⟨k, x⟩ := a
      by_cases hk : k ∈ allowed
      · simp [hk, pure, Except.pure] at hr
        exact ⟨hr.symm, hk⟩
      · simp [hk, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at hr
    · intro h
      refine forIn_all_ok kvs ?_
      intro a ha
      obtain ⟨k, x⟩ := a
      have hk : k ∈ allowed := h _ ha
      simp [hk, pure, Except.pure]

/-- Something that is not a dict is rejected. -/
theorem onlyKeys_non_dict (v : Value) (allowed : List String) (what : String)
    (h : ∀ kvs, v ≠ .dict kvs) : onlyKeys v allowed what = .error s!"{what} must be a dict" := by
  cases v <;> first | rfl | exact absurd rfl (h _)

/-! ## The fixed `cv.*` schema objects -/

/-- `cv.time_period_dict`: `All(dict, Schema({unit: Coerce(float)}),
AtLeastOne(units), timedelta(**value))` over the five units, every unit
optional, no defaults, extra keys prevented. -/
theorem timePeriodDict_shape :
    ∃ fields, timePeriodDict =
        .all [.type .dict, .schema fields .prevent, .atLeastOne (keyNames fields),
          .cv .timedeltaKwargs] ∧
      keyNames fields = ["days", "hours", "minutes", "seconds", "milliseconds"] ∧
      ∀ f ∈ fields, f.marker = .optional ∧ f.default = none := by
  refine ⟨_, rfl, rfl, ?_⟩
  intro f hf
  simp at hf
  rcases hf with rfl | rfl | rfl | rfl | rfl <;> exact ⟨rfl, rfl⟩

/-- `cv.time_period` is an `Any` of four alternatives, in upstream order,
and none of them has a branch label: a miss reports the deepest branch
error, not "expected ...". -/
theorem timePeriod_shape :
    timePeriod = .any [.cv .timePeriodStr, .cv .timePeriodSeconds, .type .timedelta, timePeriodDict] ∧
    expectedLabel [.cv .timePeriodStr, .cv .timePeriodSeconds, .type .timedelta, timePeriodDict] = none :=
  ⟨rfl, rfl⟩

/-- The probatio objects of `config_validation.py`, as upstream defines them:
`positive_int = All(Coerce(int), Range(min=0))`,
`positive_float = All(Coerce(float), Range(min=0))`,
`small_float = All(Coerce(float), Range(min=0, max=1))`,
`byte = All(Coerce(int), Range(min=0, max=255))`, `port = Port()`,
`ensure_list = EnsureList()`. -/
theorem decodeCv_probatio_objects (spec : Value) :
    decodeCv "positive_int" spec = .ok (.all [.coerce .int, .range (some (.int 0)) none true true]) ∧
    decodeCv "positive_float" spec = .ok (.all [.coerce .float, .range (some (.int 0)) none true true]) ∧
    decodeCv "small_float" spec =
      .ok (.all [.coerce .float, .range (some (.int 0)) (some (.int 1)) true true]) ∧
    decodeCv "byte" spec =
      .ok (.all [.coerce .int, .range (some (.int 0)) (some (.int 255)) true true]) ∧
    decodeCv "port" spec = .ok .port ∧
    decodeCv "ensure_list" spec = .ok .ensureList := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- The time-period family: `positive_time_period = All(time_period,
positive_timedelta)`, `positive_time_period_dict = All(time_period_dict,
positive_timedelta)`. -/
theorem decodeCv_time_periods (spec : Value) :
    decodeCv "time_period" spec = .ok timePeriod ∧
    decodeCv "time_period_dict" spec = .ok timePeriodDict ∧
    decodeCv "positive_time_period" spec = .ok (.all [timePeriod, .cv .positiveTimedelta]) ∧
    decodeCv "positive_time_period_dict" spec = .ok (.all [timePeriodDict, .cv .positiveTimedelta]) :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- `comp_entity_ids = Any(All(Lower, Any('all', 'none')), entity_ids)`. -/
theorem decodeCv_comp_entity_ids (spec : Value) :
    decodeCv "comp_entity_ids" spec =
      .ok (.any [.all [.lower, .any [.literal (.str "all"), .literal (.str "none")]],
        .cv .entityIds]) := rfl

/-- `cv.entity_domain` without a `domain` is rejected. -/
theorem decodeCv_entity_domain_missing (spec : Value) (h : spec.get? "domain" = none) :
    decodeCv "entity_domain" spec = .error "cv.entity_domain needs 'domain'" := by
  simp [decodeCv, h, throw, throwThe, MonadExceptOf.throw]

/-! ## Handlers, schemas, contexts -/

theorem decodeHandler_none : decodeHandler none = .error "missing 'handler'" := rfl

/-- A `"return"` key wins over everything else. -/
theorem decodeHandler_return (h v : Value) (hr : h.get? "return" = some v) :
    decodeHandler (some h) = .ok (.ret v) := by
  simp [decodeHandler, hr]

/-- A decoded `raise` handler only ever names a modelled exception. -/
theorem decodeHandler_raise (o : Option Value) (exc msg : String)
    (h : decodeHandler o = .ok (.raise exc msg)) : exc ∈ handlerExceptions := by
  cases o with
  | none => cases h
  | some hv =>
    simp only [decodeHandler] at h
    repeat' split at h
    all_goals first | (cases h; done) | skip
    all_goals
      simp only [Except.ok.injEq, HandlerSpec.raise.injEq] at h
      rw [← h.1]
      exact List.contains_iff_mem.mp (by assumption)

/-- No schema (`null` or missing) decodes to no schema. -/
theorem decodeSchema_none : decodeSchema none = .ok none ∧ decodeSchema (some .none) = .ok none :=
  ⟨rfl, rfl⟩

/-- No context decodes to no context. -/
theorem decodeContext_none :
    decodeContext none = .ok none ∧ decodeContext (some .none) = .ok none := ⟨rfl, rfl⟩

/-- A decoded context carries exactly the three fields read from the dict. -/
theorem decodeContext_ok (v : Value) (c : Context) (h : decodeContext (some v) = .ok (some c)) :
    getStr v "id" = .ok c.id ∧ getOptStr v "user_id" = .ok c.userId ∧
      getOptStr v "parent_id" = .ok c.parentId := by
  cases v <;> first | (cases h; done) | skip
  all_goals
    unfold decodeContext at h
    obtain ⟨i, hi, h⟩ := bind_ok h
    obtain ⟨u, hu, h⟩ := bind_ok h
    obtain ⟨p, hp, h⟩ := bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq, Option.some.injEq] at h
    subst h
    exact ⟨hi, hu, hp⟩

/-- A context always needs a string `id`. -/
theorem decodeContext_id (v : Value) (c : Context) (h : decodeContext (some v) = .ok (some c)) :
    v.get? "id" = some (.str c.id) :=
  (getStr_ok_iff v "id" c.id).mp (decodeContext_ok v c h).1

/-! ## Output -/

/-- `optStr` is `null` exactly for `None`. -/
theorem optStr_null_iff (o : Option String) : optStr o = .null ↔ o = none := by
  cases o <;> simp [optStr]

theorem optStr_injective (a b : Option String) (h : optStr a = optStr b) : a = b := by
  cases a <;> cases b <;> simp [optStr] at h ⊢
  exact h

/-- `reprOr` is `repr(v)` whenever HALean can print the value. -/
theorem reprOr_ok (v : Value) (s : String) (h : pyRepr v = .ok s) : reprOr v = s := by
  simp [reprOr, h]

/-- What cannot be printed shows up bracketed, never as a silent guess. -/
theorem reprOr_error (v : Value) (m : String) (h : pyRepr v = .error m) :
    reprOr v = "<" ++ m ++ ">" := by
  simp [reprOr, h, toString]

theorem reprOr_none_int (i : Int) : reprOr .none = "None" ∧ reprOr (.int i) = toString i := by
  constructor <;> simp [reprOr, pyRepr, pure, Except.pure]

/-- The context object has exactly the three upstream fields, with `null`
for a missing user or parent. -/
theorem contextJson_fields (c : Context) :
    (contextJson c).getObjVal? "id" = .ok (.str c.id) ∧
    (contextJson c).getObjVal? "user_id" = .ok (optStr c.userId) ∧
    (contextJson c).getObjVal? "parent_id" = .ok (optStr c.parentId) := ⟨rfl, rfl, rfl⟩

/-- Distinct contexts print as distinct objects. -/
theorem contextJson_injective (a b : Context) (h : contextJson a = contextJson b) : a = b := by
  have h1 := congrArg (fun j => j.getObjVal? "id") h
  have h2 := congrArg (fun j => j.getObjVal? "user_id") h
  have h3 := congrArg (fun j => j.getObjVal? "parent_id") h
  simp only [(contextJson_fields a).1, (contextJson_fields b).1, (contextJson_fields a).2.1,
    (contextJson_fields b).2.1, (contextJson_fields a).2.2, (contextJson_fields b).2.2,
    Except.ok.injEq, Json.str.injEq] at h1 h2 h3
  cases a; cases b
  simp only [Context.mk.injEq]
  exact ⟨h1, optStr_injective _ _ h2, optStr_injective _ _ h3⟩

/-- A log record prints its level and message; `exception` is present
exactly when the record has `exc_info`. -/
theorem logJson_fields (l : LogRecord) :
    (logJson l).getObjVal? "level" = .ok (.str l.level) ∧
    (logJson l).getObjVal? "message" = .ok (.str l.message) := by
  cases h : l.exception <;> simp only [logJson, h] <;> exact ⟨rfl, rfl⟩

theorem logJson_exception (l : LogRecord) :
    (logJson l).getObjVal? "exception" =
      match l.exception with
      | some e => .ok (.str e)
      | none => .error "property not found: exception" := by
  cases h : l.exception <;> simp only [logJson, h] <;> rfl

/-- An error prints its class, its protocol `error_kind` (derived from the
class by `errorKind`) and its message. -/
theorem errorJson_fields (e : PyError) :
    (errorJson e).getObjVal? "exception" = .ok (.str e.exception) ∧
    (errorJson e).getObjVal? "error_kind" = .ok (.str (errorKind e.exception)) ∧
    (errorJson e).getObjVal? "message" = .ok (.str e.message) := by
  cases h : e.translation with
  | none => simp only [errorJson, h]; exact ⟨rfl, rfl, rfl⟩
  | some t => obtain ⟨d, k, ph⟩ := t; simp only [errorJson, h]; exact ⟨rfl, rfl, rfl⟩

/-- The translation fields appear only for a translated error. -/
theorem errorJson_translation (e : PyError) :
    (errorJson e).getObjVal? "translation_key" =
      match e.translation with
      | some (_, k, _) => .ok (.str k)
      | none => .error "property not found: translation_key" := by
  cases h : e.translation with
  | none => simp only [errorJson, h]; rfl
  | some t => obtain ⟨d, k, ph⟩ := t; simp only [errorJson, h]; rfl

/-- A fired event prints its type, its data as the `repr` of the dict, its
time, and its context (a fresh one when the event carries none). -/
theorem eventJson_fields (e : FiredEvent) :
    (eventJson e).getObjVal? "event_type" = .ok (.str e.eventType) ∧
    (eventJson e).getObjVal? "data" = .ok (.str (reprOr (dictOf e.data))) ∧
    (eventJson e).getObjVal? "time_fired" = .ok (.num (JsonNumber.fromNat e.timeFired)) ∧
    (eventJson e).getObjVal? "context" =
      .ok (contextJson (e.context.getD Registry.freshContext)) := ⟨rfl, rfl, rfl, rfl⟩

end HALean.Core.ServicesJsonSpec
