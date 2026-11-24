/-
  More specifications for `HALean/Core/State.lean` (the functions
  `StateSpec.lean` does not cover): the slug character class, `State.domain` /
  `State.object_id`, `State.name`, the JSON views (`Context._as_dict`,
  `State._as_dict`, `State.as_compressed_state`), the timestamp accessors and
  the automation engine's view (`State.toEntityState`).

  The JSON views are specified by what a reader of the resulting object sees:
  `getObjVal?` of each documented key.
-/
import Std.Data.TreeMap.Raw.Lemmas
import HALean.Core.State
import HALean.Core.StateSpec
open Lean HALean.Template

namespace HALean.Core

/-- Reading a key of `Json.mkObj l` when the keys of `l` are distinct. -/
private theorem mkObj_getObjVal? {l : List (String × Json)} {k : String} {v : Json}
    (distinct : l.Pairwise (fun a b => ¬ a.1 = b.1)) (mem : (k, v) ∈ l) :
    (Json.mkObj l).getObjVal? k = .ok v := by
  have h : (Std.TreeMap.Raw.ofList l compare)[k]? = some v :=
    Std.TreeMap.Raw.getElem?_ofList_of_mem (k := k) (by simp)
      (by simpa using distinct) mem
  have h' : (Std.TreeMap.Raw.ofList l compare).get? k = some v := h
  simp only [Json.mkObj, Json.getObjVal?]
  rw [h']; rfl

/-! ## `isSlugChar`: the regex class `[\da-z_]` on ASCII -/

private theorem char_le_iff (a b : Char) : a ≤ b ↔ a.toNat ≤ b.toNat := by
  rw [Char.le_def, UInt32.le_iff_toNat_le]; rfl

private theorem char_eq_iff (a b : Char) : a = b ↔ a.toNat = b.toNat := by
  constructor
  · rintro rfl; rfl
  · intro h; exact Char.ext (UInt32.toNat_inj.mp h)

/-- `isSlugChar` is exactly the class `[0-9a-z_]`, by code point. -/
theorem isSlugChar_iff (c : Char) :
    isSlugChar c = true ↔
      (48 ≤ c.toNat ∧ c.toNat ≤ 57) ∨ (97 ≤ c.toNat ∧ c.toNat ≤ 122) ∨ c.toNat = 95 := by
  have hd : c.isDigit = true ↔ 48 ≤ c.toNat ∧ c.toNat ≤ 57 := by
    simp only [Char.isDigit, Bool.and_eq_true, decide_eq_true_eq, ge_iff_le,
      UInt32.le_iff_toNat_le]
    exact Iff.rfl
  have ha : 'a' ≤ c ↔ 97 ≤ c.toNat := char_le_iff _ _
  have hz : c ≤ 'z' ↔ c.toNat ≤ 122 := char_le_iff _ _
  have h95 : c = '_' ↔ c.toNat = 95 := char_eq_iff _ _
  simp only [isSlugChar, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq,
    hd, ha, hz, h95, or_assoc]

/-- Every slug character is ASCII, so the ASCII-only reading of `\d` and
`str.lower()` is the right one on valid ids. -/
theorem isSlugChar_ascii (c : Char) (h : isSlugChar c = true) : c.toNat < 128 := by
  have := (isSlugChar_iff c).mp h; omega

/-- A slug character is never the separator, a newline or an upper-case
letter. -/
theorem isSlugChar_not_special (c : Char) (h : isSlugChar c = true) :
    c ≠ '.' ∧ c ≠ '\n' ∧ c.isUpper = false := by
  have := (isSlugChar_iff c).mp h
  refine ⟨?_, ?_, ?_⟩
  · intro hc; have := (char_eq_iff _ _).mp hc; have h46 : ('.' : Char).toNat = 46 := rfl; omega
  · intro hc; have := (char_eq_iff _ _).mp hc; have h10 : ('\n' : Char).toNat = 10 := rfl; omega
  · have key : ¬ (65 ≤ c.toNat ∧ c.toNat ≤ 90) := by omega
    simp only [Char.isUpper, decide_eq_false_iff_not, ge_iff_le, UInt32.le_iff_toNat_le]
    exact key

/-- Lower-casing leaves a slug character alone (ids of valid entities are
already lower case). -/
theorem isSlugChar_toLower (c : Char) (h : isSlugChar c = true) : c.toLower = c := by
  have := (isSlugChar_iff c).mp h
  have key : ¬ (c.toNat ≥ 65 ∧ c.toNat ≤ 90) := by omega
  simp only [Char.toLower]
  split
  · rename_i hc
    exact absurd ⟨UInt32.le_iff_toNat_le.mp hc.1, UInt32.le_iff_toNat_le.mp hc.2⟩ key
  · rfl

/-! ## `State.domain` and `State.object_id` -/

/-- For an id that splits, `domain` and `object_id` are the two halves:
`domain + "." + object_id` is the id again, and the domain has no dot. -/
theorem State.domain_dot_objectId (s : State) (h : (splitEntityId s.entityId).isSome = true) :
    s.domain ++ "." ++ s.objectId = s.entityId ∧ '.' ∉ s.domain.toList ∧
      s.domain ≠ "" ∧ s.objectId ≠ "" := by
  obtain ⟨⟨d, o⟩, hs⟩ := Option.isSome_iff_exists.mp h
  obtain ⟨hl, hd, hd0, ho0⟩ := (splitEntityId_some _ _ _).mp hs
  simp only [State.domain, State.objectId, hs, Option.map_some, Option.getD_some]
  refine ⟨?_, hd, hd0, ho0⟩
  apply String.toList_inj.mp
  simp [hl]

/-- An id that does not split has an empty domain and object id. -/
theorem State.domain_objectId_of_not_split (s : State) (h : splitEntityId s.entityId = none) :
    s.domain = "" ∧ s.objectId = "" := by
  simp [State.domain, State.objectId, h]

/-- A state made by `State.new` always has an id that splits, so its `domain`
and `object_id` rebuild the id. -/
theorem State.new_domain_dot_objectId (e st : String) (a : Option Json) (lc lr lu : Option Int)
    (c : Context) (v : Bool) (now : Int) (s : State)
    (h : State.new e st a lc lr lu c v now = .ok s) :
    s.domain ++ "." ++ s.objectId = e := by
  unfold State.new at h
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
  repeat' split at h
  all_goals first
    | (cases h; done)
    | (cases h
       rename_i hsp _
       have hsome : (splitEntityId e).isSome = true := by
         cases hx : splitEntityId e <;> simp_all
       exact (State.domain_dot_objectId
         { entityId := e, state := st, attributes := _, lastChanged := _, lastReported := _,
           lastUpdated := _, context := c } hsome).1)

/-! ## `State.name` -/

/-- Without a `friendly_name` attribute the name is the object id with
underscores as spaces. -/
theorem State.name_default (s : State) (e : String)
    (h : s.attributes.getObjVal? ATTR_FRIENDLY_NAME = .error e) :
    s.name = .str (s.objectId.replace "_" " ") := by
  simp [State.name, h]

/-- A truthy `friendly_name` (of any type) is the name, unchanged. -/
theorem State.name_friendly (s : State) (v : Json)
    (h : s.attributes.getObjVal? ATTR_FRIENDLY_NAME = .ok v)
    (ht : truthy (Value.ofJson v) = true) : s.name = v := by
  simp [State.name, h, ht]

/-- A falsy `friendly_name` (`""`, `None`, `0`, ...) falls back to the object
id: Python's `or`. -/
theorem State.name_falsy (s : State) (v : Json)
    (h : s.attributes.getObjVal? ATTR_FRIENDLY_NAME = .ok v)
    (ht : truthy (Value.ofJson v) = false) :
    s.name = .str (s.objectId.replace "_" " ") := by
  simp [State.name, h, ht]

/-- The name only depends on the id and the attributes. -/
theorem State.name_congr (s t : State) (hid : s.entityId = t.entityId)
    (hattr : s.attributes = t.attributes) : s.name = t.name := by
  simp [State.name, State.objectId, hid, hattr]

/-! ## Timestamps -/

/-- The upstream cache: when `last_changed == last_updated` the two
timestamps are the same float. -/
theorem State.lastChangedTimestamp_eq_of_eq (s : State) (h : s.lastChanged = s.lastUpdated) :
    s.lastChangedTimestamp = s.lastUpdatedTimestamp := by
  simp [State.lastChangedTimestamp, State.lastUpdatedTimestamp, h]

/-- A freshly reported state (`last_reported == last_updated`) reports the
update's timestamp. -/
theorem State.lastReportedTimestamp_eq_of_eq (s : State) (h : s.lastReported = s.lastUpdated) :
    s.lastReportedTimestamp = s.lastUpdatedTimestamp := by
  simp [State.lastReportedTimestamp, State.lastUpdatedTimestamp, h]

/-- All three timestamp accessors are `tsFloat` of their field, so they only
depend on the microseconds. -/
theorem State.timestamps_eq_tsFloat (s : State) :
    s.lastChangedTimestamp = tsFloat s.lastChanged ∧
    s.lastUpdatedTimestamp = tsFloat s.lastUpdated ∧
    s.lastReportedTimestamp = tsFloat s.lastReported := ⟨rfl, rfl, rfl⟩

/-- `tsJson` always gives a JSON number, or `null` when the float cannot be
sent (never a string, an array or an object). -/
theorem tsJson_shape (us : Int) : tsJson us = .null ∨ ∃ n, tsJson us = .num n := by
  unfold tsJson
  cases h : floatToJson (tsFloat us) with
  | error e => exact Or.inl rfl
  | ok j =>
    right
    unfold floatToJson at h
    simp only [pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at h
    repeat' split at h
    all_goals first
      | (cases h; done)
      | (cases h; exact ⟨_, rfl⟩)

/-! ## `Context._as_dict` -/

/-- `Context._as_dict` has `id`, `parent_id` and `user_id` (`None` → `null`). -/
theorem Context.asDict_fields (c : Context) :
    c.asDict.getObjVal? "id" = .ok (.str c.id) ∧
    c.asDict.getObjVal? "parent_id" = .ok (toJson c.parentId) ∧
    c.asDict.getObjVal? "user_id" = .ok (toJson c.userId) := by
  refine ⟨?_, ?_, ?_⟩ <;> (apply mkObj_getObjVal? <;> simp)

/-- The dict determines the context: two contexts with the same `_as_dict`
fields are equal. -/
theorem Context.eq_of_fields (c d : Context) (hid : c.id = d.id)
    (hp : c.parentId = d.parentId) (hu : c.userId = d.userId) : c.asDict = d.asDict := by
  cases c; cases d; simp_all

/-! ## `State._as_dict` -/

/-- Every key of `State.as_dict()`: the id, the state, the attributes
unchanged, the three datetimes as UTC `isoformat()` strings, and the
context's dict. -/
theorem State.asDict_fields (s : State) :
    s.asDict.getObjVal? "entity_id" = .ok (.str s.entityId) ∧
    s.asDict.getObjVal? "state" = .ok (.str s.state) ∧
    s.asDict.getObjVal? "attributes" = .ok s.attributes ∧
    s.asDict.getObjVal? "last_changed" = .ok (.str (isoUtc s.lastChanged)) ∧
    s.asDict.getObjVal? "last_reported" = .ok (.str (isoUtc s.lastReported)) ∧
    s.asDict.getObjVal? "last_updated" = .ok (.str (isoUtc s.lastUpdated)) ∧
    s.asDict.getObjVal? "context" = .ok s.context.asDict := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> (apply mkObj_getObjVal? <;> simp)

/-- A report (`async_set_internal`'s same-state branch only moves
`last_reported`) changes nothing in `as_dict()` but `last_reported`. -/
theorem State.asDict_report (s : State) (now : Int) :
    let s' := { s with lastReported := now }
    s'.asDict.getObjVal? "last_reported" = .ok (.str (isoUtc now)) ∧
    ∀ k ∈ ["entity_id", "state", "attributes", "last_changed", "last_updated", "context"],
      s'.asDict.getObjVal? k = s.asDict.getObjVal? k := by
  refine ⟨(State.asDict_fields _).2.2.2.2.1, ?_⟩
  intro k hk
  have h1 := State.asDict_fields s
  have h2 := State.asDict_fields { s with lastReported := now }
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
  rcases hk with rfl | rfl | rfl | rfl | rfl | rfl <;> simp [h1, h2]

/-! ## `State.as_compressed_state` -/

/-- The keys every compressed state has: `s`, `a` and `lc`. -/
theorem State.asCompressedState_fields (s : State) :
    s.asCompressedState.getObjVal? "s" = .ok (.str s.state) ∧
    s.asCompressedState.getObjVal? "a" = .ok s.attributes ∧
    s.asCompressedState.getObjVal? "lc" = .ok (tsJson s.lastChanged) := by
  unfold State.asCompressedState
  refine ⟨?_, ?_, ?_⟩ <;> (simp only []; split <;> (apply mkObj_getObjVal? <;> simp))

/-- The context is a bare id when it has neither a parent nor a user. -/
theorem State.asCompressedState_context_bare (s : State)
    (hp : s.context.parentId = none) (hu : s.context.userId = none) :
    s.asCompressedState.getObjVal? "c" = .ok (.str s.context.id) := by
  unfold State.asCompressedState
  simp only [hp, hu, Option.isNone_none, Bool.and_self, ite_true]
  split <;> (apply mkObj_getObjVal? <;> simp)

/-- Otherwise the context is its full dict. -/
theorem State.asCompressedState_context_full (s : State)
    (h : s.context.parentId.isSome = true ∨ s.context.userId.isSome = true) :
    s.asCompressedState.getObjVal? "c" = .ok s.context.asDict := by
  unfold State.asCompressedState
  have hc : (s.context.parentId.isNone && s.context.userId.isNone) = false := by
    cases hp : s.context.parentId <;> cases hu : s.context.userId <;> simp_all
  simp only [hc]
  split <;> (apply mkObj_getObjVal? <;> simp)

/-- `lu` is there, with the update's timestamp, when the two timestamps
differ. -/
theorem State.asCompressedState_lu (s : State)
    (h : (s.lastChangedTimestamp != s.lastUpdatedTimestamp) = true) :
    s.asCompressedState.getObjVal? "lu" = .ok (tsJson s.lastUpdated) := by
  unfold State.asCompressedState
  simp only [h, ite_true]
  apply mkObj_getObjVal? <;> simp

/-! ## `State.toEntityState` -/

/-- The automation engine sees the same id, state and attributes, and both
microsecond times. -/
theorem State.toEntityState_fields (s : State) :
    s.toEntityState.entityId = s.entityId ∧ s.toEntityState.state = s.state ∧
    s.toEntityState.attributes = s.attributes ∧
    s.toEntityState.lastChangedUs = some s.lastChanged ∧
    s.toEntityState.lastUpdatedUs = some s.lastUpdated := ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- Its millisecond `lastChanged` is the microseconds rounded down, for
times at or after the epoch. -/
theorem State.toEntityState_lastChanged (s : State) (h : 0 ≤ s.lastChanged) :
    (s.toEntityState.lastChanged : Int) * 1000 ≤ s.lastChanged ∧
    s.lastChanged < (s.toEntityState.lastChanged : Int) * 1000 + 1000 := by
  simp only [State.toEntityState]
  have h0 : 0 ≤ s.lastChanged / 1000 := Int.ediv_nonneg h (by decide)
  rw [Int.toNat_of_nonneg h0]
  omega

/-- A time before the epoch is clamped to 0 ms (the engine's clock is a
`Nat`). -/
theorem State.toEntityState_lastChanged_neg (s : State) (h : s.lastChanged < 0) :
    s.toEntityState.lastChanged = 0 := by
  simp only [State.toEntityState]
  have : s.lastChanged / 1000 < 0 := Int.ediv_neg_of_neg_of_pos h (by decide)
  exact Int.toNat_of_nonpos (by omega)

/-- A report does not change what the automation engine sees. -/
theorem State.toEntityState_report (s : State) (now : Int) :
    ({ s with lastReported := now } : State).toEntityState = s.toEntityState := rfl

/-- `MAX_LENGTH_STATE_STATE` is upstream's 255, which `STATE_UNKNOWN` fits. -/
theorem state_unknown_fits : STATE_UNKNOWN.length ≤ MAX_LENGTH_STATE_STATE := by decide

end HALean.Core
