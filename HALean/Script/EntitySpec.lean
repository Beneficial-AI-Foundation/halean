/-
  Specifications of the script entity's pure parts (`HALean/Script/Entity.lean`),
  proved against what `homeassistant/components/script/__init__.py` and the
  helpers it uses compute:

  * the state attributes (`entityAttributes`, `unavailableAttributes`), key
    by key, and that they have no other key
  * `this` of a run (`scriptThis`): its entity id, state and `last_action`
  * `cv.comp_entity_ids` (`compEntityIds`): `all`, `none`, valid ids only
  * `async_extract_entities` (`extractTargets`): only live entities, in the
    component's order
  * the service handlers (`planCall`): which operations each service plans
-/
import HALean.Script.Entity
import HALean.Core.StateSpec
import Std.Data.TreeMap.Raw.Lemmas
import Std.Data.TreeMap.Raw.WF
open Lean

namespace HALean.Script
open HALean.Automation

/-! ### Lookup in `Json.mkObj` -/

/-- The value the last pair with key `k` gives (`dict(pairs)[k]`). -/
def lastValue (l : List (String × Json)) (k : String) : Option Json :=
  l.foldl (fun acc p => if p.1 = k then some p.2 else acc) none

private theorem getElem?_insertMany (t : Std.TreeMap.Raw String Json compare) (h : t.WF)
    (l : List (String × Json)) (k : String) :
    (t.insertMany l)[k]? = l.foldl (fun acc p => if p.1 = k then some p.2 else acc) t[k]? := by
  induction l generalizing t with
  | nil => simp
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    rw [Std.TreeMap.Raw.insertMany_cons, ih _ h.insert, Std.TreeMap.Raw.getElem?_insert h]
    simp

/-- A key of `Json.mkObj pairs` has the value of the last pair with that key. -/
theorem field?_mkObj (l : List (String × Json)) (k : String) :
    field? (Json.mkObj l) k = lastValue l k := by
  have h := getElem?_insertMany ∅ Std.TreeMap.Raw.WF.emptyc l k
  simp only [field?, Json.mkObj, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?,
    Std.TreeMap.Raw.ofList_eq_insertMany_empty, h, lastValue]
  simp only [Std.TreeMap.Raw.getElem?_emptyc]
  cases List.foldl (fun acc p => if p.fst = k then some p.snd else acc) none l <;> rfl

/-! ### `modeStr`, `entityState` -/

/-- The four modes have four different names. -/
theorem modeStr_injective (a b : Mode) (h : modeStr a = modeStr b) : a = b := by
  cases a <;> cases b <;> first | rfl | (exact absurd h (by decide))

/-- `modeStr` gives one of `SCRIPT_MODE_CHOICES`. -/
theorem modeStr_mem (m : Mode) : modeStr m ∈ ["parallel", "queued", "restart", "single"] := by
  cases m <;> simp [modeStr]

/-- `ScriptEntity.is_on`: the entity is `off` exactly when it has no run. -/
theorem entityState_off (n : Nat) : entityState n = "off" ↔ n = 0 := by
  unfold entityState
  split <;> simp_all <;> omega

/-! ### State attributes -/

/-- `mode` is always written, as the mode's name. -/
theorem entityAttributes_mode (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    field? (entityAttributes s a c lt) "mode" = some (.str (modeStr a.mode)) := by
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;> simp [field?_mkObj, lastValue]

/-- `current` is the number of runs. -/
theorem entityAttributes_current (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    field? (entityAttributes s a c lt) "current" = some (c : Json) := by
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;> simp [field?_mkObj, lastValue]

/-- `max` is an attribute exactly in the modes that support it
(`parallel`, `queued`), and then it is the configured `max`. -/
theorem entityAttributes_max (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    field? (entityAttributes s a c lt) "max" =
      if a.mode = .parallel ∨ a.mode = .queued then some (a.maxRuns : Json) else none := by
  unfold entityAttributes
  cases s.icon <;> cases hm : a.mode <;> simp [field?_mkObj, lastValue, supportsMax] <;> rfl

/-- `icon` is an attribute exactly when the script has one. -/
theorem entityAttributes_icon (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    field? (entityAttributes s a c lt) "icon" = s.icon.map Json.str := by
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;> simp [field?_mkObj, lastValue]

/-- `friendly_name` is the alias (the object id when there is none, see
`decodeScript`). -/
theorem entityAttributes_friendly_name (s : ScriptEntity) (a : Automation) (c : Nat)
    (lt : Option Int) :
    field? (entityAttributes s a c lt) "friendly_name" = some (.str a.alias) := by
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;> simp [field?_mkObj, lastValue]

/-- `last_triggered` is always written: `null` before the first run, then
the UTC ISO string. -/
theorem entityAttributes_last_triggered (s : ScriptEntity) (a : Automation) (c : Nat)
    (lt : Option Int) :
    field? (entityAttributes s a c lt) "last_triggered" =
      some (match lt with
        | some us => .str (Template.isoformat us (some 0))
        | none => .null) := by
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;> cases lt <;> simp [field?_mkObj, lastValue]

/-- A script entity has no other attribute (`last_action` is not modelled). -/
theorem entityAttributes_keys (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int)
    (k : String)
    (hk : k ∉ ["last_triggered", "mode", "current", "max", "icon", "friendly_name"]) :
    field? (entityAttributes s a c lt) k = none := by
  simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hk
  unfold entityAttributes
  cases s.icon <;> cases supportsMax a.mode <;>
    simp [field?_mkObj, lastValue, Ne.symm h1, Ne.symm h2, Ne.symm h3, Ne.symm h4, Ne.symm h5,
      Ne.symm h6]

/-- A removed entity is `restored`. -/
theorem unavailableAttributes_restored (s : ScriptEntity) (a : Automation) :
    field? (unavailableAttributes s a) "restored" = some (.bool true) := by
  unfold unavailableAttributes
  cases s.icon <;> simp [field?_mkObj, lastValue]

/-- A removed entity keeps the icon and the name it had. -/
theorem unavailableAttributes_keeps (s : ScriptEntity) (a : Automation) (c : Nat)
    (lt : Option Int) (k : String) (hk : k = "icon" ∨ k = "friendly_name") :
    field? (unavailableAttributes s a) k = field? (entityAttributes s a c lt) k := by
  unfold unavailableAttributes entityAttributes
  rcases hk with rfl | rfl <;> cases s.icon <;> cases supportsMax a.mode <;>
    simp [field?_mkObj, lastValue]

/-- A removed entity has nothing else: no `mode`, `current`, `max`,
`last_triggered`. -/
theorem unavailableAttributes_keys (s : ScriptEntity) (a : Automation) (k : String)
    (hk : k ∉ ["restored", "icon", "friendly_name"]) :
    field? (unavailableAttributes s a) k = none := by
  simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
  obtain ⟨h1, h2, h3⟩ := hk
  unfold unavailableAttributes
  cases s.icon <;> simp [field?_mkObj, lastValue, Ne.symm h1, Ne.symm h2, Ne.symm h3]

/-! ### `this` -/

/-- `this` is the entity's state as a dict: its entity id and its state
(`on` while it has runs). -/
theorem scriptThis_state (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    ∃ kvs, scriptThis s a c lt = .dict kvs ∧
      (.str "entity_id", .str s.entityId) ∈ kvs ∧
      (.str "state", .str (entityState c)) ∈ kvs := by
  refine ⟨_, rfl, ?_, ?_⟩ <;> simp

/-- `this.attributes` has the attributes the state has, with
`last_triggered` as a UTC datetime (or `None`), and `last_action` exactly
while the script has runs. -/
theorem scriptThis_attributes (s : ScriptEntity) (a : Automation) (c : Nat) (lt : Option Int) :
    ∃ kvs attrs, scriptThis s a c lt = .dict kvs ∧ (.str "attributes", .dict attrs) ∈ kvs ∧
      (.str "mode", .str (modeStr a.mode)) ∈ attrs ∧
      (.str "current", .int c) ∈ attrs ∧
      (.str "friendly_name", .str a.alias) ∈ attrs ∧
      (.str "last_triggered",
        match lt with | some us => .datetime us (some 0) | none => .none) ∈ attrs ∧
      ((∃ v, (Template.Value.str "last_action", v) ∈ attrs) ↔ c > 0) ∧
      ((∃ v, (Template.Value.str "max", v) ∈ attrs) ↔ supportsMax a.mode = true) ∧
      (∀ i, (Template.Value.str "icon", .str i) ∈ attrs ↔ s.icon = some i) := by
  refine ⟨_, _, rfl, .tail _ (.tail _ (.head _)), ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  all_goals cases lt <;> cases s.icon <;> cases supportsMax a.mode <;> by_cases hc : c > 0 <;>
    simp [hc] <;> exact fun i => eq_comm

/-! ### Run variables -/

/-- Only a mapping gives run variables. -/
theorem jsonVars_ne_nil (j : Json) (h : jsonVars j ≠ []) : ∃ kvs, j = .obj kvs := by
  cases j <;> simp_all [jsonVars]

/-- The run variables are the mapping's keys, in its order, each with its
JSON value as a template value. -/
theorem jsonVars_obj (kvs : Std.TreeMap.Raw String Json compare) :
    (jsonVars (.obj kvs)).map (·.1) = kvs.toList.map (·.1) ∧
    (jsonVars (.obj kvs)).map (·.2) = kvs.toList.map (fun p => Template.Value.ofJson p.2) := by
  simp [jsonVars, Function.comp_def]

/-! ### `cv.comp_entity_ids` -/

/-- `all`, in any case, is `ENTITY_MATCH_ALL`. -/
theorem compEntityIds_all (s : String) (h : s.toLower = "all") :
    compEntityIds (.str s) = .ok none := by
  simp [compEntityIds, h]
  rfl

/-- `none`, in any case, is no entity. -/
theorem compEntityIds_none (s : String) (h : s.toLower = "none") :
    compEntityIds (.str s) = .ok (some []) := by
  simp [compEntityIds, h]
  rfl

/-- `mapM` in `Except` succeeds item by item. -/
private theorem mapM_ok_spec {α β ε : Type} {f : α → Except ε β} :
    ∀ {l : List α} {r : List β}, l.mapM f = .ok r →
      r.length = l.length ∧ ∀ b ∈ r, ∃ a ∈ l, f a = .ok b
  | [], r, h => by
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at h
    subst h; simp
  | a :: l, r, h => by
    simp only [List.mapM_cons, bind, Except.bind, pure, Except.pure] at h
    split at h
    · simp at h
    · rename_i b hb
      split at h
      · simp at h
      · rename_i bs hbs
        simp only [Except.ok.injEq] at h
        subst h
        have ih := mapM_ok_spec hbs
        refine ⟨by simp [ih.1], ?_⟩
        intro c hc
        rcases List.mem_cons.1 hc with rfl | hc
        · exact ⟨a, by simp, hb⟩
        · obtain ⟨a', ha', h'⟩ := ih.2 c hc
          exact ⟨a', by simp [ha'], h'⟩

private theorem forall_of_mapM_ok {α β ε : Type} {f : α → Except ε β} {P : β → Prop}
    (hf : ∀ a b, f a = .ok b → P b) {l : List α} {r : List β} (h : l.mapM f = .ok r) :
    ∀ b ∈ r, P b := by
  intro b hb
  obtain ⟨a, _, hab⟩ := (mapM_ok_spec h).2 b hb
  exact hf a b hab

/-- A list is never `ENTITY_MATCH_ALL`, and gives one id per item. -/
theorem compEntityIds_arr (xs : Array Json) (r : Option (List String))
    (h : compEntityIds (.arr xs) = .ok r) : ∃ ids, r = some ids ∧ ids.length = xs.size := by
  simp only [compEntityIds, bind, Except.bind, pure, Except.pure] at h
  split at h
  · simp at h
  · rename_i ids hm
    simp only [Except.ok.injEq] at h
    exact ⟨ids, h.symm, by simpa using (mapM_ok_spec hm).1⟩

/-- Only a string or a list is accepted. -/
theorem compEntityIds_other (j : Json) (r : Option (List String))
    (h : compEntityIds j = .ok r) : (∃ s, j = .str s) ∨ ∃ xs, j = .arr xs := by
  cases j <;> simp_all [compEntityIds] <;> cases h

/-- **Every id `cv.comp_entity_ids` lets through matches `valid_entity_id`'s
regex** (`EntityIdRe`, see `Core/StateSpec.lean`). -/
theorem compEntityIds_valid (j : Json) (ids : List String)
    (h : compEntityIds j = .ok (some ids)) : ∀ id ∈ ids, HALean.Core.EntityIdRe id.toList := by
  have one : ∀ (x : Json) (b : String),
      (match x with
        | .str s =>
          if Template.validEntityId s.trim.toLower = true then (pure s.trim.toLower : Except String String)
          else throw s!"Entity ID {s.trim.toLower} is an invalid entity ID"
        | x => throw s!"Entity ID {x.compress} is an invalid entity ID") = .ok b →
      HALean.Core.EntityIdRe b.toList := by
    intro x b hb
    split at hb
    · split at hb
      · rename_i hv
        cases hb
        exact (HALean.Core.validEntityId_iff _).1 hv
      · cases hb
    · cases hb
  cases j with
  | str s =>
    simp only [compEntityIds, bind, Except.bind, pure, Except.pure] at h
    split at h
    · cases h
    · split at h
      · cases h; simp
      · split at h
        · cases h
        · rename_i l hm
          cases h
          exact forall_of_mapM_ok (fun a b hab => one (.str a) b hab) hm
  | arr xs =>
    simp only [compEntityIds, bind, Except.bind, pure, Except.pure] at h
    split at h
    · cases h
    · rename_i l hm
      cases h
      exact forall_of_mapM_ok one hm
  | _ => simp [compEntityIds] at h <;> cases h

/-! ### Targets -/

/-- Anything but a mapping is left as it is. -/
theorem normalizeTargetIds_not_obj (t : Json) (h : ∀ kvs, t ≠ .obj kvs) :
    normalizeTargetIds t = t := by
  cases t <;> simp_all [normalizeTargetIds]

private theorem lastValue_map (g : String × Json → String × Json) (k : String)
    (hk : ∀ p, (g p).1 = p.1) (hv : ∀ p, p.1 = k → (g p).2 = p.2) (l : List (String × Json)) :
    lastValue (l.map g) k = lastValue l k := by
  unfold lastValue
  generalize (none : Option Json) = acc
  induction l generalizing acc with
  | nil => rfl
  | cons p l ih =>
    simp only [List.map_cons, List.foldl_cons, hk]
    by_cases h : p.1 = k
    · simp only [h, ite_true, hv p h]; exact ih _
    · simp only [h, ite_false]; exact ih _

/-- Keys that are not target ids are passed through unchanged. -/
theorem normalizeTargetIds_other (kvs : Std.TreeMap.Raw String Json compare) (k : String)
    (hk : k ∉ ENTITY_SERVICE_FIELDS) :
    field? (normalizeTargetIds (.obj kvs)) k = field? (Json.mkObj kvs.toList) k := by
  simp only [normalizeTargetIds, field?_mkObj]
  apply lastValue_map
  · intro p
    obtain ⟨a, v⟩ := p
    dsimp only
    repeat' split
    all_goals rfl
  · intro p hp
    obtain ⟨a, v⟩ := p
    subst hp
    have h1 : a ≠ "entity_id" := fun h => hk (by simp [h, ENTITY_SERVICE_FIELDS])
    have h2 : ¬ a ∈ ENTITY_SERVICE_FIELDS := hk
    simp [h1, h2]

/-- **`async_extract_entities` for scripts, exactly.** The call succeeds
when it has no device, area, floor or label target, its `entity_id` passes
`cv.comp_entity_ids` and names no group; it then gives the live script
entities (all of them for `all`, else those named), in the component's
order. -/
theorem extractTargets_ok_iff (scripts : List ScriptEntity) (data : Json) (l : List Nat) :
    extractTargets scripts data = .ok l ↔
    (∀ k ∈ ["device_id", "area_id", "floor_id", "label_id"], field? data k = none) ∧
    ∃ ids, (match field? data "entity_id" with
        | some v => compEntityIds v
        | none => .ok (some [])) = .ok ids ∧
      (∀ xs, ids = some xs → xs.any (·.startsWith "group.") = false) ∧
      l = match ids with
        | none => (scripts.zipIdx.filter (·.1.alive)).map (·.2)
        | some ids => ((scripts.zipIdx.filter (·.1.alive)).filter
            fun (p : ScriptEntity × Nat) => ids.contains p.1.entityId).map (·.2) := by
  simp only [extractTargets, bind, Except.bind, pure, Except.pure, forIn, List.forIn'_cons,
    List.forIn'_nil, throw, throwThe, MonadExceptOf.throw]
  cases h1 : field? data "device_id" <;> cases h2 : field? data "area_id" <;>
    cases h3 : field? data "floor_id" <;> cases h4 : field? data "label_id" <;>
    simp [h1, h2, h3, h4]
  cases he : field? data "entity_id" with
  | none => simp [eq_comm]
  | some v =>
    simp only []
    cases hc : compEntityIds v with
    | error e => simp
    | ok ids =>
      cases ids with
      | none => simp [eq_comm]
      | some xs =>
        simp
        split
        · rename_i h
          simp only [reduceCtorEq, false_iff, not_and]
          intro hh
          obtain ⟨x, hx, hp⟩ := h
          exact absurd hp (hh x hx)
        · rename_i h
          simp only [Except.ok.injEq]
          exact ⟨fun e => ⟨fun x hx hp => h ⟨x, hx, hp⟩, e.symm⟩, fun e => e.2.symm⟩

/-- With `entity_id: all` the targets are exactly the live script entities. -/
theorem extractTargets_all {scripts : List ScriptEntity} {data : Json} {l : List Nat} {v : Json}
    (h : extractTargets scripts data = .ok l) (hv : field? data "entity_id" = some v)
    (hall : compEntityIds v = .ok none) (i : Nat) :
    i ∈ l ↔ ∃ s, scripts[i]? = some s ∧ s.alive = true := by
  obtain ⟨_, ids, hids, _, rfl⟩ := (extractTargets_ok_iff _ _ _).1 h
  simp only [hv, hall, Except.ok.injEq] at hids
  subst hids
  simp [List.mem_zipIdx_iff_getElem?]

/-- With a list of entity ids the targets are exactly the live script
entities it names. -/
theorem extractTargets_named {scripts : List ScriptEntity} {data : Json} {l : List Nat} {v : Json}
    {ids : List String}
    (h : extractTargets scripts data = .ok l) (hv : field? data "entity_id" = some v)
    (hids : compEntityIds v = .ok (some ids)) (i : Nat) :
    i ∈ l ↔ ∃ s, scripts[i]? = some s ∧ s.alive = true ∧ s.entityId ∈ ids := by
  obtain ⟨_, ids', hids', _, rfl⟩ := (extractTargets_ok_iff _ _ _).1 h
  simp only [hv, hids, Except.ok.injEq] at hids'
  subst hids'
  simp [List.mem_zipIdx_iff_getElem?, and_comm]

/-- Whatever the target, only live script entities are extracted, each
once, in the component's order (the indices increase). -/
theorem extractTargets_live_sorted {scripts : List ScriptEntity} {data : Json} {l : List Nat}
    (h : extractTargets scripts data = .ok l) :
    (∀ i ∈ l, ∃ s, scripts[i]? = some s ∧ s.alive = true) ∧ l.Pairwise (· < ·) := by
  obtain ⟨_, ids, _, _, rfl⟩ := (extractTargets_ok_iff _ _ _).1 h
  have hs : ∀ (q : ScriptEntity × Nat → Bool),
      ((scripts.zipIdx.filter q).map (·.2)).Pairwise (· < ·) := by
    intro q
    have h1 : ((scripts.zipIdx.filter q).map (·.2)).Sublist (scripts.zipIdx.map Prod.snd) :=
      List.filter_sublist.map _
    rw [List.zipIdx_map_snd] at h1
    exact List.Pairwise.sublist h1 (List.pairwise_lt_range' 1)
  cases ids with
  | none => exact ⟨by simp [List.mem_zipIdx_iff_getElem?], hs _⟩
  | some xs =>
    refine ⟨?_, ?_⟩
    · simp only [List.mem_map, List.mem_filter, List.mem_zipIdx_iff_getElem?]
      rintro i ⟨⟨s, j⟩, ⟨⟨hj, ha⟩, _⟩, rfl⟩
      exact ⟨s, hj, ha⟩
    simp only [List.filter_filter]
    exact hs _

/-- A call without `entity_id` targets nothing. -/
theorem extractTargets_no_entity_id (scripts : List ScriptEntity) (data : Json)
    (hk : ∀ k ∈ ["device_id", "area_id", "floor_id", "label_id"], field? data k = none)
    (he : field? data "entity_id" = none) : extractTargets scripts data = .ok [] := by
  rw [extractTargets_ok_iff]
  exact ⟨hk, some [], by simp [he], by simp, by simp⟩

/-- Device, area, floor and label targets are refused (registries are not
modelled). -/
theorem extractTargets_registry_target (scripts : List ScriptEntity) (data : Json) (k : String)
    (hk : k ∈ ["device_id", "area_id", "floor_id", "label_id"]) (h : field? data k ≠ none) :
    ∃ m, extractTargets scripts data = .error m := by
  cases hr : extractTargets scripts data with
  | error m => exact ⟨m, rfl⟩
  | ok l => exact absurd (((extractTargets_ok_iff _ _ _).1 hr).1 k hk) h

/-- Group targets are refused (HALean has no group model). -/
theorem extractTargets_group (scripts : List ScriptEntity) (data v : Json) (ids : List String)
    (hv : field? data "entity_id" = some v) (hids : compEntityIds v = .ok (some ids))
    (id : String) (hid : id ∈ ids) (hg : id.startsWith "group." = true) :
    ∃ m, extractTargets scripts data = .error m := by
  cases hr : extractTargets scripts data with
  | error m => exact ⟨m, rfl⟩
  | ok l =>
    obtain ⟨_, ids', hids', hno, _⟩ := (extractTargets_ok_iff _ _ _).1 hr
    simp only [hv, hids, Except.ok.injEq] at hids'
    have := hno ids hids'.symm
    simp only [List.any_eq_false] at this
    exact absurd hg (this id hid)

/-! ### The service handlers -/

/-- A `for` loop that returns at the first item with `p` is `find?`. -/
private theorem forIn'_find (l : List String) (p : String → Bool) (f : String → List LocalOp) :
    (forIn' (m := Id) l ((none, ()) : Option (List LocalOp) × PUnit) (fun a _ _ =>
      if p a = true then ForInStep.done (some (f a), ()) else ForInStep.yield (none, ()))).fst
    = (l.find? p).map f := by
  induction l with
  | nil => rfl
  | cons a l ih =>
    simp only [List.forIn'_cons, List.find?_cons]
    cases h : p a
    · simp only [Bool.false_eq_true, ite_false]
      exact ih
    · simp; rfl

/-- The three ways a call of `turn_on` / `turn_off` / `toggle` can go:
the schema refuses it (`vol.Invalid`), the targets cannot be extracted, or
`mk` is applied to every targeted entity. -/
def DomainPlan (scripts : List ScriptEntity) (data : Json) (rr : Bool) (ops : List LocalOp)
    (mk : Nat → LocalOp) : Prop :=
  (∃ m, ops = [.fail .invalid m]) ∨
  (rr = false ∧ ∃ m, extractTargets scripts data = .error m ∧ ops = [.fail .other m]) ∨
  (rr = false ∧ ∃ targets, extractTargets scripts data = .ok targets ∧ ops = targets.map mk)

theorem planCall_domain (scripts : List ScriptEntity) (running : Nat → Bool)
    (service svc : String) (data : Json) (rr : Bool) (ops : List LocalOp)
    (hs : service.toLower = svc) (hd : svc = "turn_on" ∨ svc = "turn_off" ∨ svc = "toggle")
    (h : planCall scripts running service data rr = some ops) :
    DomainPlan scripts data rr ops (fun i =>
      if svc = "turn_on" then
        .start i (match field? data "variables" with | some v => jsonVars v | none => []) false
      else if svc = "turn_off" then .stop i
      else if running i = true then .stop i else .start i [] false) := by
  have hc : (svc == "turn_on" || svc == "turn_off" || svc == "toggle") = true := by
    rcases hd with h | h | h <;> simp [h]
  unfold DomainPlan
  cases data with
  | obj kvs =>
    simp only [planCall, hs, Id.run, bind, pure, forIn, forIn'_find, hc, ite_true,
      Option.some.injEq] at h
    subst h
    split
    · exact .inl ⟨_, rfl⟩
    · rename_i hrr
      have hrr : rr = false := by simpa using hrr
      split
      · rename_i r hr
        obtain ⟨a, _, rfl⟩ := Option.map_eq_some_iff.1 hr
        exact .inl ⟨_, rfl⟩
      · split
        · exact .inl ⟨_, rfl⟩
        · split
          · rename_i hv
            split
            · exact .inr (.inl ⟨hrr, _, ‹_›, rfl⟩)
            · refine .inr (.inr ⟨hrr, _, ‹_›, ?_⟩)
              simp [hv]
          · rename_i hv
            split
            · exact .inr (.inl ⟨hrr, _, ‹_›, rfl⟩)
            · refine .inr (.inr ⟨hrr, _, ‹_›, ?_⟩)
              simp [hv]
          · exact .inl ⟨_, rfl⟩
  | _ =>
    simp only [planCall, hs, Id.run, bind, pure, forIn, forIn'_find, hc, ite_true,
      Option.some.injEq, List.find?_nil, Option.map_none, List.any_nil, Bool.not_false] at h
    subst h
    split <;> exact .inl ⟨_, rfl⟩

/-- `turn_on`, `turn_off` and `toggle` are always HALean's to handle. -/
theorem planCall_domain_isSome (scripts : List ScriptEntity) (running : Nat → Bool)
    (service : String) (data : Json) (rr : Bool)
    (hd : service.toLower = "turn_on" ∨ service.toLower = "turn_off" ∨
      service.toLower = "toggle") :
    (planCall scripts running service data rr).isSome = true := by
  rcases hd with h | h | h <;> simp [planCall, h]

/-- None of the three supports a response: asking for one is `vol.Invalid`. -/
theorem planCall_response_refused (scripts : List ScriptEntity) (running : Nat → Bool)
    (service : String) (data : Json)
    (hd : service.toLower = "turn_on" ∨ service.toLower = "turn_off" ∨
      service.toLower = "toggle") :
    ∃ m, planCall scripts running service data true = some [.fail .invalid m] := by
  rcases hd with h | h | h <;> simp [planCall, h, Id.run] <;> exact ⟨_, rfl⟩

/-- `turn_on_service`: start every targeted entity, without waiting
(`wait=False`), with the call's `variables`. -/
theorem planCall_turn_on (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (rr : Bool) (ops : List LocalOp) (hs : service.toLower = "turn_on")
    (h : planCall scripts running service data rr = some ops) :
    DomainPlan scripts data rr ops fun i =>
      .start i (match field? data "variables" with | some v => jsonVars v | none => []) false := by
  simpa using planCall_domain scripts running service _ data rr ops hs (.inl rfl) h

/-- `turn_off_service`: `async_turn_off` (stop) on every targeted entity. -/
theorem planCall_turn_off (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (rr : Bool) (ops : List LocalOp) (hs : service.toLower = "turn_off")
    (h : planCall scripts running service data rr = some ops) :
    DomainPlan scripts data rr ops .stop := by
  simpa using planCall_domain scripts running service _ data rr ops hs (.inr (.inl rfl)) h

/-- `toggle_service` (`ToggleEntity.async_toggle`): stop the entities that
are on, start the others, never with variables. -/
theorem planCall_toggle (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (rr : Bool) (ops : List LocalOp) (hs : service.toLower = "toggle")
    (h : planCall scripts running service data rr = some ops) :
    DomainPlan scripts data rr ops fun i =>
      if running i = true then .stop i else .start i [] false := by
  simpa using planCall_domain scripts running service _ data rr ops hs (.inr (.inr rfl)) h

/-- `turn_off` never starts a run, and only stops live script entities. -/
theorem planCall_turn_off_ops (scripts : List ScriptEntity) (running : Nat → Bool)
    (service : String) (data : Json) (rr : Bool) (ops : List LocalOp)
    (hs : service.toLower = "turn_off")
    (h : planCall scripts running service data rr = some ops) :
    ∀ op ∈ ops, (∃ k m, op = .fail k m) ∨
      ∃ i s, op = .stop i ∧ scripts[i]? = some s ∧ s.alive = true := by
  rcases planCall_turn_off scripts running service data rr ops hs h with
    ⟨m, rfl⟩ | ⟨_, m, _, rfl⟩ | ⟨_, targets, ht, rfl⟩
  · simp
  · simp
  · intro op hop
    obtain ⟨i, hi, rfl⟩ := List.mem_map.1 hop
    obtain ⟨s, hs, ha⟩ := (extractTargets_live_sorted ht).1 i hi
    exact .inr ⟨i, s, rfl, hs, ha⟩

/-- `turn_on` never stops a run, never waits for the runs it starts, and
only starts live script entities. -/
theorem planCall_turn_on_ops (scripts : List ScriptEntity) (running : Nat → Bool)
    (service : String) (data : Json) (rr : Bool) (ops : List LocalOp)
    (hs : service.toLower = "turn_on")
    (h : planCall scripts running service data rr = some ops) :
    ∀ op ∈ ops, (∃ k m, op = .fail k m) ∨
      ∃ i vars s, op = .start i vars false ∧ scripts[i]? = some s ∧ s.alive = true := by
  rcases planCall_turn_on scripts running service data rr ops hs h with
    ⟨m, rfl⟩ | ⟨_, m, _, rfl⟩ | ⟨_, targets, ht, rfl⟩
  · simp
  · simp
  · intro op hop
    obtain ⟨i, hi, rfl⟩ := List.mem_map.1 hop
    obtain ⟨s, hs, ha⟩ := (extractTargets_live_sorted ht).1 i hi
    exact .inr ⟨i, _, s, rfl, hs, ha⟩

/-- Any other service name is a script's object id: the call runs the live
script with that id and waits for it (`wait=True`), the call data being the
run variables. -/
theorem planCall_script (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (rr : Bool) (ops : List LocalOp)
    (hd : service.toLower ∉ ["turn_on", "turn_off", "toggle"])
    (h : planCall scripts running service data rr = some ops) :
    ∃ i s, ops = [.start i (jsonVars data) true] ∧ scripts[i]? = some s ∧ s.alive = true ∧
      s.objectId = service.toLower := by
  simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hd
  have hc : (service.toLower == "turn_on" || service.toLower == "turn_off" ||
      service.toLower == "toggle") = false := by simp [hd]
  simp only [planCall, hc, Bool.false_eq_true, ite_false] at h
  split at h
  · rename_i s i hf
    have hp := List.find?_some hf
    have hm := List.mem_of_find?_eq_some hf
    simp only [Option.some.injEq] at h
    simp only [Bool.and_eq_true, beq_iff_eq] at hp
    exact ⟨i, s, h.symm, List.mem_zipIdx_iff_getElem?.1 hm, hp.1, hp.2⟩
  · cases h

/-- A service that is neither one of the three nor a live script's object id
is not HALean's (`ServiceNotFound`, or HA's own `script.reload`). -/
theorem planCall_none_iff (scripts : List ScriptEntity) (running : Nat → Bool) (service : String)
    (data : Json) (rr : Bool) :
    planCall scripts running service data rr = none ↔
      service.toLower ∉ ["turn_on", "turn_off", "toggle"] ∧
      ∀ s ∈ scripts, ¬ (s.alive = true ∧ s.objectId = service.toLower) := by
  by_cases hd : service.toLower ∈ ["turn_on", "turn_off", "toggle"]
  · have := planCall_domain_isSome scripts running service data rr (by simpa using hd)
    simp only [hd, not_true_eq_false, false_and, iff_false]
    intro h; simp [h] at this
  · simp only [hd, not_false_eq_true, true_and]
    simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hd
    have hc : (service.toLower == "turn_on" || service.toLower == "turn_off" ||
        service.toLower == "toggle") = false := by simp [hd]
    simp only [planCall, hc, Bool.false_eq_true, ite_false]
    split
    · rename_i s i hf
      have hp := List.find?_some hf
      have hm := List.mem_of_find?_eq_some hf
      simp only [Bool.and_eq_true, beq_iff_eq] at hp
      simp only [reduceCtorEq, false_iff]
      exact fun h => h s (List.mem_of_getElem? (List.mem_zipIdx_iff_getElem?.1 hm)) hp
    · rename_i hf
      simp only [List.find?_eq_none, Bool.and_eq_true, beq_iff_eq, true_iff] at hf ⊢
      intro s hs
      obtain ⟨i, hi⟩ := List.getElem?_of_mem hs
      exact hf (s, i) (List.mem_zipIdx_iff_getElem?.2 hi)

/-! ### The response -/

/-- **`callResponse` with `return_response`, exactly**: a falsy response
becomes `{}`, a dict is passed on, anything else is an error. -/
theorem callResponse_true_iff (v r : Template.Value) :
    callResponse true v = .ok r ↔
      (Template.truthy v = false ∧ r = .dict []) ∨ (∃ kvs, v = .dict kvs ∧ kvs ≠ [] ∧ r = v) := by
  unfold callResponse
  simp only [Bool.not_true, Bool.false_eq_true, ite_false]
  by_cases ht : Template.truthy v = true
  · simp only [ht, ite_true, reduceCtorEq, false_and, false_or]
    cases v with
    | dict kvs =>
      have hne : kvs ≠ [] := by simpa [Template.truthy] using ht
      simp only [Except.ok.injEq]
      exact ⟨fun h => ⟨kvs, rfl, hne, h.symm⟩, fun ⟨_, _, _, h⟩ => h.symm⟩
    | _ => simp
  · have ht : Template.truthy v = false := by simpa using ht
    simp only [ht, Bool.false_eq_true, ite_false, Except.ok.injEq, true_and]
    constructor
    · intro h; exact .inl h.symm
    · rintro (h | ⟨kvs, rfl, hne, rfl⟩)
      · exact h.symm
      · simp [Template.truthy, hne] at ht

end HALean.Script
