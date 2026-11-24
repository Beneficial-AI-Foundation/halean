/-
  Specifications of the script service's wire protocol
  (`HALean/Script/Protocol.lean`; `protocol/schema.json`, `script` section):

  * `decodeScripts`: the pairs `bridge/protocol.py` sends decode to
    themselves (round trip), and what else is accepted
  * `decodeInput`: every message needs a `type` and a `now`; what `reload`
    and `call` messages decode to
  * `processLine`: a line that does not decode never changes the service,
    and the answer is always one `error` or one `batch` object
-/
import HALean.Script.Protocol
import Std.Data.TreeMap.Raw.Lemmas
import Std.Data.TreeMap.Raw.WF
open Lean

namespace HALean.Script
open HALean.Automation

/-! ### `decodeScripts` -/

private theorem mapM_pairs (f : Json → Except String (String × Json))
    (hf : ∀ k v, f (.arr #[.str k, v]) = .ok (k, v)) (pairs : List (String × Json)) :
    (pairs.map fun (k, v) => Json.arr #[.str k, v]).mapM f = .ok pairs := by
  induction pairs with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨k, v⟩ := p
    simp only [List.map_cons, List.mapM_cons, hf, bind, Except.bind, pure, Except.pure] at ih ⊢
    rw [ih]

/-- **Round trip**: the ordered `[object_id, config]` pairs the bridge
sends decode to exactly those pairs, in order. -/
theorem decodeScripts_pairs (pairs : List (String × Json)) :
    decodeScripts (.arr (pairs.map fun (k, v) => Json.arr #[.str k, v]).toArray) = .ok pairs :=
  mapM_pairs _ (fun _ _ => rfl) pairs

/-- No scripts at all (`null`, as when `scripts:` is absent) is the empty
list. -/
theorem decodeScripts_null : decodeScripts .null = .ok [] := rfl

/-- A mapping gives its entries, in the mapping's (sorted) key order. -/
theorem decodeScripts_obj (kvs : Std.TreeMap.Raw String Json compare) :
    decodeScripts (.obj kvs) = .ok kvs.toList := by
  simp [decodeScripts, pure, Except.pure]

private theorem mapM_pairs_inv (f : Json → Except String (String × Json))
    (hf : ∀ x p, f x = .ok p → x = .arr #[.str p.1, p.2]) :
    ∀ (l : List Json) (pairs : List (String × Json)), l.mapM f = .ok pairs →
      l = pairs.map fun (k, v) => Json.arr #[.str k, v]
  | [], pairs, h => by cases h; rfl
  | x :: l, pairs, h => by
    simp only [List.mapM_cons, bind, Except.bind, pure, Except.pure] at h
    split at h
    · cases h
    · rename_i p hp
      split at h
      · cases h
      · rename_i ps hps
        cases h
        simp [hf x p hp, mapM_pairs_inv f hf l ps hps]

/-- A list decodes only if every item is an `[object_id, config]` pair with
a string id; nothing is dropped or reordered. -/
theorem decodeScripts_arr_ok (xs : Array Json) (pairs : List (String × Json))
    (h : decodeScripts (.arr xs) = .ok pairs) :
    xs.toList = pairs.map fun (k, v) => Json.arr #[.str k, v] := by
  refine mapM_pairs_inv _ ?_ xs.toList pairs h
  intro x p hp
  cases x with
  | arr elems =>
    obtain ⟨l⟩ := elems
    match l, hp with
    | [], hp => cases hp
    | [_], hp => cases hp
    | [a, b], hp => cases a <;> first | (cases hp; rfl) | cases hp
    | _ :: _ :: _ :: _, hp => cases hp
  | _ => cases hp

/-- A string, number or boolean is not a script list. -/
theorem decodeScripts_scalar (j : Json)
    (h : (∃ s, j = .str s) ∨ (∃ n, j = .num n) ∨ ∃ b, j = .bool b) :
    ∃ m, decodeScripts j = .error m := by
  rcases h with ⟨s, rfl⟩ | ⟨n, rfl⟩ | ⟨b, rfl⟩ <;> exact ⟨_, rfl⟩

/-! ### `decodeInput` -/

/-- Every message needs a string `type`. -/
theorem decodeInput_no_type (j : Json) (h : str? j "type" = none) :
    decodeInput j = .error "message without type" := by
  simp [decodeInput, h, throw, throwThe, MonadExceptOf.throw]

/-- Every message needs a valid `now`, whatever its type. -/
theorem decodeInput_no_now (j : Json) (m : String) (h : decodeInstant j = .error m) :
    ∃ m', decodeInput j = .error m' := by
  cases ht : str? j "type" with
  | none => exact ⟨_, decodeInput_no_type j ht⟩
  | some ty => exact ⟨m, by simp [decodeInput, ht, h, bind, Except.bind]⟩

/-- A `reload` message is `Input.reload` with its `scripts` (none when the
key is absent) at its `now`. -/
theorem decodeInput_reload (j : Json) (now : Instant) (scripts : List (String × Json))
    (ht : str? j "type" = some "reload") (hn : decodeInstant j = .ok now)
    (hs : decodeScripts ((field? j "scripts").getD .null) = .ok scripts) :
    ∃ i, decodeInput j = .ok i ∧ i matches .reload .. ∧
      (match i with | .reload s n => s = scripts ∧ n = now | _ => False) := by
  refine ⟨.reload scripts now, ?_, rfl, rfl, rfl⟩
  simp [decodeInput, ht, hn, hs, bind, Except.bind, pure, Except.pure]

/-- A `call` message needs a string `service`. -/
theorem decodeInput_call_no_service (j : Json) (ht : str? j "type" = some "call")
    (hs : str? j "service" = none) : ∃ m, decodeInput j = .error m := by
  cases hn : decodeInstant j with
  | error m => exact decodeInput_no_now j m hn
  | ok now =>
    exact ⟨_, by simp [decodeInput, ht, hn, hs, bind, Except.bind, throw, throwThe,
      MonadExceptOf.throw]; rfl⟩

/-! ### `processLine` -/

/-- **A line that is not JSON, or not a message, never changes the
service.** -/
theorem processLine_error (sv : Service) (line : String) (err : String)
    (h : (Json.parse line >>= decodeInput) = .error err) :
    (processLine sv line).1 = sv := by
  simp [processLine, h]

/-- A decoded message is one step of the service. -/
theorem processLine_ok (sv : Service) (line : String) (i : Input)
    (h : (Json.parse line >>= decodeInput) = .ok i) :
    (processLine sv line).1 = (sv.step i).1 := by
  simp only [processLine, h]

private theorem getElem?_insertMany' (t : Std.TreeMap.Raw String Json compare) (h : t.WF)
    (l : List (String × Json)) (k : String) :
    (t.insertMany l)[k]? = l.foldl (fun acc p => if p.1 = k then some p.2 else acc) t[k]? := by
  induction l generalizing t with
  | nil => simp
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    rw [Std.TreeMap.Raw.insertMany_cons, ih _ h.insert, Std.TreeMap.Raw.getElem?_insert h]
    simp

private theorem field?_mkObj' (l : List (String × Json)) (k : String) :
    field? (Json.mkObj l) k =
      l.foldl (fun acc p => if p.1 = k then some p.2 else acc) none := by
  have h := getElem?_insertMany' ∅ Std.TreeMap.Raw.WF.emptyc l k
  simp only [field?, Json.mkObj, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?,
    Std.TreeMap.Raw.ofList_eq_insertMany_empty, h]
  simp only [Std.TreeMap.Raw.getElem?_emptyc]
  cases List.foldl (fun acc p => if p.fst = k then some p.snd else acc) none l <;> rfl

/-- The answer to a line that does not decode is one `error` object with
the reason. -/
theorem processLine_error_output (sv : Service) (line : String) (err : String)
    (h : (Json.parse line >>= decodeInput) = .error err) :
    field? (processLine sv line).2 "type" = some (.str "error") ∧
    field? (processLine sv line).2 "message" = some (.str err) := by
  simp only [processLine, h, field?_mkObj']
  constructor <;> simp <;> rfl

/-- The answer to a decoded message is one `batch` object: an
`unsupported` entry per rejected script, then the step's commands. -/
theorem processLine_ok_output (sv : Service) (line : String) (i : Input)
    (h : (Json.parse line >>= decodeInput) = .ok i) :
    field? (processLine sv line).2 "type" = some (.str "batch") ∧
    ∃ cmds : Array Json, field? (processLine sv line).2 "cmds" = some (.arr cmds) ∧
      cmds.size = (sv.step i).2.2.length + (sv.step i).2.1.length := by
  simp only [processLine, h, field?_mkObj']
  constructor
  · simp
  · refine ⟨((sv.step i).2.2.map fun (x : String × String) =>
        Json.mkObj [("type", Json.str "unsupported"), ("id", Json.str x.1),
          ("reason", Json.str x.2)]) ++ (sv.step i).2.1.map Cmd.toJson |>.toArray, ?_, by simp⟩
    simp

end HALean.Script
