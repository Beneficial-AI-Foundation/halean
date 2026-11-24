/-
  Specifications for `HALean/Automation/Protocol.lean`, the JSON-lines wire
  protocol between the I/O shell and the engine: what each decoder accepts,
  and that the encoded commands can be told apart and read back.
-/
import HALean.Automation.Protocol
open Lean

namespace HALean.Automation

/-! ### Numbers -/

/-- `getNat` fails exactly when the field is missing or not a number. -/
theorem getNat_isOk (j : Json) (k : String) :
    (∃ n, getNat j k = .ok n) ↔ ∃ x, field? j k = some (.num x) := by
  unfold getNat
  split
  · rename_i n hn
    constructor
    · intro _; exact ⟨n, hn⟩
    · intro _; split <;> exact ⟨_, rfl⟩
  · rename_i hn
    constructor
    · rintro ⟨n, h⟩; cases h
    · rintro ⟨x, hx⟩; exact absurd hx (hn x)

/-- A non-negative integer is read exactly. -/
theorem getNat_int (j : Json) (k : String) (m : Int) (hm : 0 ≤ m)
    (h : field? j k = some (.num ⟨m, 0⟩)) : getNat j k = .ok m.toNat := by
  simp [getNat, h, hm, pure, Except.pure]

theorem getNat_missing (j : Json) (k : String) (h : field? j k = none) :
    getNat j k = .error s!"missing or invalid '{k}'" := by
  simp [getNat, h, throw, throwThe, MonadExceptOf.throw]

/-- `optInt` reads exactly the numbers written without a fraction or exponent. -/
theorem optInt_eq_some (j : Json) (k : String) (i : Int) :
    optInt j k = some i ↔ ∃ n : JsonNumber, field? j k = some (.num n) ∧ n.exponent = 0 ∧
      n.mantissa = i := by
  unfold optInt
  split
  · rename_i n hn
    constructor
    · intro h
      split at h
      · rename_i he; cases h; exact ⟨n, hn, by simpa using he, rfl⟩
      · cases h
    · rintro ⟨n', hn', he, rfl⟩
      rw [hn] at hn'; cases hn'
      simp [he]
  · rename_i hn
    constructor
    · intro h; cases h
    · rintro ⟨n, h, _⟩; exact absurd h (hn n)

/-- `getInt` agrees with `optInt` wherever `optInt` reads a value... -/
theorem getInt_of_optInt (j : Json) (k : String) (i d : Int) (h : optInt j k = some i) :
    getInt j k d = i := by
  obtain ⟨n, hn, he, rfl⟩ := (optInt_eq_some j k i).mp h
  simp [getInt, hn, he]

/-- ...and `getNat` does too, for the non-negative ones. -/
theorem getNat_of_optInt (j : Json) (k : String) (i : Int) (hi : 0 ≤ i)
    (h : optInt j k = some i) : getNat j k = .ok i.toNat := by
  obtain ⟨n, hn, he, rfl⟩ := (optInt_eq_some j k _).mp h
  simp [getNat, hn, he, hi, pure, Except.pure]

/-- The default is used for a missing field. -/
theorem getInt_missing (j : Json) (k : String) (d : Int) (h : field? j k = none) :
    getInt j k d = d := by
  simp [getInt, h]

/-! ### `decodeErrKind` -/

theorem decodeErrKind_invalid (s : Option String) :
    decodeErrKind s = .invalid ↔ s = some "invalid" := by
  unfold decodeErrKind
  split <;> simp_all

theorem decodeErrKind_haError (s : Option String) :
    decodeErrKind s = .haError ↔ s = some "ha_error" := by
  unfold decodeErrKind
  split <;> simp_all

/-- Anything else, a missing kind included, is `other`. -/
theorem decodeErrKind_other (s : Option String) :
    decodeErrKind s = .other ↔ s ≠ some "invalid" ∧ s ≠ some "ha_error" := by
  unfold decodeErrKind
  split <;> simp_all

/-! ### Instants and states -/

theorem decodeInstant_ok (j : Json) (i : Instant) :
    decodeInstant j = .ok i ↔
      ∃ n, getNat j "now" = .ok n ∧ i = { utc := n, tzOffsetSec := getInt j "tz" 0 } := by
  unfold decodeInstant
  cases getNat j "now" with
  | error e => simp [bind, Except.bind]
  | ok n => simp [bind, Except.bind, pure, Except.pure, eq_comm]

/-- A state needs `entity_id` and `state` as text; everything else has a
default. -/
theorem decodeEntityState_ok (j : Json) (s : EntityState) :
    decodeEntityState j = .ok s ↔ ∃ eid st, str? j "entity_id" = some eid ∧
      str? j "state" = some st ∧
      s = { entityId := eid, state := st,
            attributes := (field? j "attributes").getD (Json.mkObj []),
            lastChanged := (getNat j "last_changed").toOption.getD 0,
            lastChangedUs := optInt j "last_changed_us",
            lastUpdatedUs := optInt j "last_updated_us" } := by
  unfold decodeEntityState
  cases str? j "entity_id" with
  | none => simp [throw, throwThe, MonadExceptOf.throw]
  | some eid =>
    cases str? j "state" with
    | none => simp [throw, throwThe, MonadExceptOf.throw]
    | some st => simp [pure, Except.pure, eq_comm]

theorem decodeEntityState_no_entity_id (j : Json) (h : str? j "entity_id" = none) :
    decodeEntityState j = .error "state without entity_id" := by
  simp [decodeEntityState, h, throw, throwThe, MonadExceptOf.throw]

theorem decodeEntityState_no_state (j : Json) (eid : String) (h : str? j "entity_id" = some eid)
    (h' : str? j "state" = none) : decodeEntityState j = .error "state without state" := by
  simp [decodeEntityState, h, h', throw, throwThe, MonadExceptOf.throw]

/-- A missing or `null` state is "no state" (the entity did not exist, or
was removed). -/
theorem decodeOptState_none (j : Json) (k : String)
    (h : field? j k = none ∨ field? j k = some .null) : decodeOptState j k = .ok none := by
  rcases h with h | h <;> simp [decodeOptState, h, pure, Except.pure]

/-- Any other value must decode as a state. -/
theorem decodeOptState_some (j : Json) (k : String) (v : Json) (h : field? j k = some v)
    (hv : v ≠ .null) : decodeOptState j k = (decodeEntityState v).map some := by
  unfold decodeOptState
  rw [h]
  cases v <;> first | exact absurd rfl hv | rfl

/-! ### Commands on the wire -/

/-- The `type` tag of each command. -/
def Cmd.tag : Cmd → String
  | .callService .. => "call_service"
  | .fireEvent .. => "fire_event"
  | .automationTriggered .. => "automation_triggered"
  | .log .. => "log"
  | .setState .. => "set_state"
  | .callDone .. => "call_done"

theorem Cmd.toJson_type (c : Cmd) : str? c.toJson "type" = some c.tag := by
  cases c with
  | callDone id ok resp kind msg => cases ok <;> rfl
  | _ => rfl

/-- Commands other than `call_done` are encoded without loss: the JSON
determines the command. -/
theorem Cmd.toJson_injective (c₁ c₂ : Cmd) (h : c₁.toJson = c₂.toJson)
    (hd : c₁.tag ≠ "call_done") : c₁ = c₂ := by
  have ht : c₁.tag = c₂.tag := by
    have := congrArg (fun j => str? j "type") h
    simp only [Cmd.toJson_type] at this
    exact Option.some.inj this
  cases c₁ <;> cases c₂ <;> simp [Cmd.tag] at ht hd
  · rename_i a1 b1 c1 d1 e1 f1 g1 a2 b2 c2 d2 e2 f2 g2
    have h1 : some (a1 : Json) = some (a2 : Json) := congrArg (fun j => field? j "call_id") h
    have h2 : some (b1 : Json) = some (b2 : Json) := congrArg (fun j => field? j "run_id") h
    have h3 : some (c1 : Json) = some (c2 : Json) := congrArg (fun j => field? j "domain") h
    have h4 : some (d1 : Json) = some (d2 : Json) := congrArg (fun j => field? j "service") h
    have h5 : some e1 = some e2 := congrArg (fun j => field? j "data") h
    have h6 : some f1 = some f2 := congrArg (fun j => field? j "target") h
    have h7 : some (g1 : Json) = some (g2 : Json) :=
      congrArg (fun j => field? j "return_response") h
    simp only [Option.some.injEq, Json.num.injEq, Json.str.injEq, Json.bool.injEq,
      JsonNumber.fromNat, JsonNumber.mk.injEq, Int.natCast_inj, and_true] at h1 h2 h3 h4 h5 h6 h7
    simp [h1, h2, h3, h4, h5, h6, h7]
  · rename_i a1 b1 a2 b2
    have h1 : some (a1 : Json) = some (a2 : Json) := congrArg (fun j => field? j "event_type") h
    have h2 : some b1 = some b2 := congrArg (fun j => field? j "data") h
    simp only [Option.some.injEq, Json.str.injEq] at h1 h2
    simp [h1, h2]
  · rename_i a1 b1 c1 a2 b2 c2
    have h1 : some (a1 : Json) = some (a2 : Json) := congrArg (fun j => field? j "id") h
    have h2 : some (b1 : Json) = some (b2 : Json) := congrArg (fun j => field? j "name") h
    have h3 : some (c1 : Json) = some (c2 : Json) := congrArg (fun j => field? j "source") h
    simp only [Option.some.injEq, Json.str.injEq] at h1 h2 h3
    simp [h1, h2, h3]
  · rename_i a1 b1 a2 b2
    have h1 : some (a1 : Json) = some (a2 : Json) := congrArg (fun j => field? j "level") h
    have h2 : some (b1 : Json) = some (b2 : Json) := congrArg (fun j => field? j "message") h
    simp only [Option.some.injEq, Json.str.injEq] at h1 h2
    simp [h1, h2]
  · rename_i a1 b1 c1 a2 b2 c2
    have h1 : some (a1 : Json) = some (a2 : Json) := congrArg (fun j => field? j "entity_id") h
    have h2 : some (b1 : Json) = some (b2 : Json) := congrArg (fun j => field? j "state") h
    have h3 : some c1 = some c2 := congrArg (fun j => field? j "attributes") h
    simp only [Option.some.injEq, Json.str.injEq] at h1 h2 h3
    simp [h1, h2, h3]

/-- A successful `call_done` carries the call id and the response, and no
error fields. -/
theorem Cmd.toJson_callDone_ok (id : Nat) (resp : Json) (kind msg : String) :
    let j := (Cmd.callDone id true resp kind msg).toJson
    field? j "call_id" = some (id : Json) ∧ field? j "ok" = some (.bool true) ∧
    field? j "response" = some resp ∧ field? j "error_kind" = none ∧ field? j "message" = none :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- A failed `call_done` carries the call id, the kind and the message, and
no response. -/
theorem Cmd.toJson_callDone_error (id : Nat) (resp : Json) (kind msg : String) :
    let j := (Cmd.callDone id false resp kind msg).toJson
    field? j "call_id" = some (id : Json) ∧ field? j "ok" = some (.bool false) ∧
    field? j "error_kind" = some (.str kind) ∧ field? j "message" = some (.str msg) ∧
    field? j "response" = none :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

/-! ### `decodeInput` -/

theorem decodeInput_no_type (j : Json) (h : str? j "type" = none) :
    decodeInput j = .error "message without type" := by
  simp [decodeInput, h, throw, throwThe, MonadExceptOf.throw]

/-- Every message needs a valid `now`. -/
theorem decodeInput_bad_instant (j : Json) (ty e : String) (h : str? j "type" = some ty)
    (hi : decodeInstant j = .error e) : decodeInput j = .error e := by
  simp [decodeInput, h, hi, bind, Except.bind]

theorem decodeInput_tick (j : Json) (h : str? j "type" = some "tick") :
    decodeInput j = (decodeInstant j).map fun now => (.tick now, []) := by
  simp only [decodeInput, h, bind, Except.bind, pure, Except.pure]
  cases decodeInstant j <;> rfl

theorem decodeInput_event (j : Json) (now : Instant) (h : str? j "type" = some "event")
    (hi : decodeInstant j = .ok now) :
    decodeInput j = match str? j "event_type" with
      | some et => .ok (.event et ((field? j "data").getD (Json.mkObj [])) now, [])
      | none => .error "event without event_type" := by
  simp only [decodeInput, h, hi, bind, Except.bind, pure, Except.pure]
  cases str? j "event_type" <;> rfl

theorem decodeInput_unknown (j : Json) (ty : String) (now : Instant)
    (h : str? j "type" = some ty) (hi : decodeInstant j = .ok now)
    (hty : ty ∉ ["init", "state_changed", "event", "tick", "service_result"]) :
    decodeInput j = .error s!"unknown message type {ty}" := by
  simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hty
  simp only [decodeInput, h, hi, bind, Except.bind, pure, Except.pure]
  split <;> first | (exfalso; simp_all; done) | rfl

/-- Only `init` can report rejected automations. -/
theorem decodeInput_rejected (j : Json) (i : Input) (bad : List (String × String))
    (h : decodeInput j = .ok (i, bad)) (hty : str? j "type" ≠ some "init") : bad = [] := by
  unfold decodeInput at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · rename_i ty hs
    split at h
    · cases h
    · split at h
      · exact absurd hs hty
      · repeat' split at h
        all_goals first | (cases h; done) | (cases h; rfl)
      · repeat' split at h
        all_goals first | (cases h; done) | (cases h; rfl)
      · cases h; rfl
      · repeat' split at h
        all_goals first | (cases h; done) | (cases h; rfl)
      · cases h
  · cases h

/-! ### `processLine` -/

/-- A line that does not parse or decode leaves the engine untouched and is
answered with an `error` message. -/
theorem processLine_error (e : Engine) (line err : String)
    (h : Json.parse line >>= decodeInput = .error err) :
    processLine e line = (e, Json.mkObj [("type", "error"), ("message", err)]) := by
  simp [processLine, h]

/-- A decoded line is one engine step; the reply is a `batch`. -/
theorem processLine_ok (e : Engine) (line : String) (i : Input) (rejected : List (String × String))
    (h : Json.parse line >>= decodeInput = .ok (i, rejected)) :
    (processLine e line).1 = (e.step i).1 ∧
      str? (processLine e line).2 "type" = some "batch" := by
  refine ⟨?_, ?_⟩ <;>
    first | (simp only [processLine, h]; done) | (simp only [processLine, h]; rfl)

/-- The reply lists the rejected automations first, then the commands of
the step, in order. -/
theorem processLine_cmds (e : Engine) (line : String) (i : Input)
    (rejected : List (String × String))
    (h : Json.parse line >>= decodeInput = .ok (i, rejected)) :
    field? (processLine e line).2 "cmds" = some (Json.arr
      ((rejected.map fun (id, why) =>
          Json.mkObj [("type", "unsupported"), ("id", Json.str id), ("reason", Json.str why)]) ++
        (e.step i).2.map Cmd.toJson).toArray) := by
  first | (simp only [processLine, h]; done) | (simp only [processLine, h]; rfl)

/-- Every line gets exactly one reply, an `error` or a `batch`. -/
theorem processLine_reply_type (e : Engine) (line : String) :
    str? (processLine e line).2 "type" = some "error" ∨
      str? (processLine e line).2 "type" = some "batch" := by
  unfold processLine
  split
  · exact .inl rfl
  · exact .inr rfl

end HALean.Automation
