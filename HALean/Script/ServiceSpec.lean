/-
  Specifications of the script service's step function
  (`HALean/Script/Service.lean`), proved against
  `homeassistant/components/script/__init__.py`
  (`async_setup`, `_async_process_config`, `async_added_to_hass`):

  * `decodeAll`: one verdict per script, in order
  * `lastTriggeredOf`: only a string `last_triggered` restores anything
  * `addScripts`: `scripts` stays aligned with `automations`
  * `Service.owns`, and that HA's echo of an owned state is only a tick
  * what each kind of input can and cannot change in the `Service`
-/
import HALean.Script.Service
open Lean

namespace HALean.Script
open HALean.Automation

/-! ### `decodeAll` -/

/-- Every script gets exactly one verdict, under its own key and in the
order of `scripts.yaml`. -/
theorem decodeAll_keys (scripts : List (String × Json)) (autos : List Json) :
    (decodeAll scripts autos).map (·.1) = scripts.map (·.1) := by
  simp [decodeAll, Function.comp_def]

/-- A verdict is `decodeScript`'s on that script's own config; only the
names other configs pass (`passedNames`) come from the rest of the file. -/
theorem decodeAll_mem (scripts : List (String × Json)) (autos : List Json) (k : String)
    (r : Except String (ScriptEntity × Automation)) (h : (k, r) ∈ decodeAll scripts autos) :
    ∃ j extra, (k, j) ∈ scripts ∧ r = decodeScript k j extra := by
  simp only [decodeAll, List.mem_map] at h
  obtain ⟨⟨k', j⟩, hm, he⟩ := h
  cases he
  exact ⟨j, _, hm, rfl⟩

/-! ### `last_triggered` of a restored state -/

/-- Only a string `last_triggered` attribute restores anything: a state
without the attribute, or with `null` there (never run), restores nothing. -/
theorem lastTriggeredOf_some (s : EntityState) (us : Int) (h : lastTriggeredOf s = some us) :
    ∃ t, s.attr? "last_triggered" = some (.str t) := by
  unfold lastTriggeredOf at h
  split at h
  · rename_i t ht; exact ⟨t, ht⟩
  · cases h

/-! ### `addScripts` -/

/-- `async_write_ha_state` only writes the state machine and tells the
shell: everything else in the engine is as it was. -/
theorem writeEntity_frame (ai : Nat) (e : Engine) (c : List Cmd) :
    ∃ st cs, ((writeEntity ai).run (e, c)).2 = ({ e with states := st }, c ++ cs) := by
  unfold writeEntity
  simp only [getE, setE, emit, bind, StateT.bind, StateT.run, pure, StateT.pure, get, getThe,
    MonadStateOf.get, StateT.get, modify, modifyGet, MonadStateOf.modifyGet]
  rcases h1 : e.scripts[ai]? with _ | s <;> rcases h2 : e.automations[ai]? with _ | a <;>
    simp only []
  · exact ⟨e.states, [], by rw [List.append_nil]; rfl⟩
  · exact ⟨e.states, [], by rw [List.append_nil]; rfl⟩
  · exact ⟨e.states, [], by rw [List.append_nil]; rfl⟩
  · by_cases ha : (!s.alive) = true
    · exact ⟨e.states, [], by rw [List.append_nil]; simp only [ha, ite_true]; rfl⟩
    · simp only [ha]
      rcases h3 : e.states.get? s.entityId with _ | o <;> simp only []
      · exact ⟨_, _, rfl⟩
      · generalize (o.state == entityState (runsOf e ai).length && _) = b
        cases b
        · exact ⟨_, _, rfl⟩
        · exact ⟨e.states, [], by rw [List.append_nil]; rfl⟩

/-- One round of `addScripts`: the state before `writeEntity`. -/
def added (restored : List (String × Int)) (s : ScriptEntity) (a : Automation) (e : Engine) :
    Engine :=
  { e with
    automations := e.automations ++ [a],
    scripts := e.scripts ++
      (List.range (e.automations.length - e.scripts.length)).map (fun _ =>
        ({ objectId := "", entityId := "", alive := false } : ScriptEntity)) ++ [s],
    lastTriggered := match (restored.find? (·.1 == s.entityId)).map (·.2) with
      | some us => e.lastTriggered ++ [(e.automations.length, us)]
      | none => e.lastTriggered }

theorem addScripts_cons (restored : List (String × Int)) (s : ScriptEntity) (a : Automation)
    (new : List (ScriptEntity × Automation)) (e : Engine) (c : List Cmd) :
    (addScripts ((s, a) :: new) restored).run (e, c) =
      (addScripts new restored).run
        ((writeEntity e.automations.length).run (added restored s a e, c)).2 := by
  simp only [addScripts, forIn, List.forIn'_cons, getE, setE, bind, StateT.bind, StateT.run, pure,
    StateT.pure, get, getThe, MonadStateOf.get, StateT.get, modify, modifyGet,
    MonadStateOf.modifyGet, StateT.modifyGet]
  rfl

private theorem getElem?_append_singleton {α : Type} {l : List α} {a : α} {n : Nat}
    (h : l.length = n) : (l ++ [a])[n + 0]? = some a := by
  subst h; simp

theorem addScripts_nil (restored : List (String × Int)) (st : Engine × List Cmd) :
    (addScripts [] restored).run st = ((), st) := rfl

/-- **`scripts` stays indexed like `automations`.** After `addScripts`,
the new automations are appended in order, the script entities that were
there are untouched, `scripts` is as long as `automations` (dead
placeholders fill the gap that automations without an entity left), and
each new script entity sits at the index of its own automation. -/
theorem addScripts_aligned (restored : List (String × Int)) :
    ∀ (new : List (ScriptEntity × Automation)) (e : Engine) (c : List Cmd),
      e.scripts.length ≤ e.automations.length →
      let r := ((addScripts new restored).run (e, c)).2.1
      r.automations = e.automations ++ new.map (·.2) ∧
      (∀ (i : Nat) x, e.scripts[i]? = some x → r.scripts[i]? = some x) ∧
      r.scripts.length ≤ r.automations.length ∧
      (new ≠ [] → r.scripts.length = r.automations.length) ∧
      (∀ (i : Nat) x, new[i]? = some x → r.scripts[e.automations.length + i]? = some x.1)
  | [], e, c, h => by simp [addScripts_nil, h]
  | (s, a) :: new, e, c, h => by
    intro r
    obtain ⟨st, cs, hw⟩ := writeEntity_frame e.automations.length (added restored s a e) c
    have hr : r = ((addScripts new restored).run
        ({ added restored s a e with states := st }, c ++ cs)).2.1 := by
      show ((addScripts ((s, a) :: new) restored).run (e, c)).2.1 = _
      rw [addScripts_cons, hw]
    have hlen : (added restored s a e).scripts.length = e.automations.length + 1 := by
      simp [added]; omega
    obtain ⟨h1, h2, h3, h4, h5⟩ := addScripts_aligned restored new
      { added restored s a e with states := st } (c ++ cs) (by simp [added]; omega)
    rw [← hr] at h1 h2 h3 h4 h5
    simp only [added] at h1 h2 h5
    refine ⟨by simp [h1], ?_, h3, ?_, ?_⟩
    · intro i x hx
      apply h2
      have hi : i < e.scripts.length := by
        rcases Nat.lt_or_ge i e.scripts.length with h | h
        · exact h
        · rw [List.getElem?_eq_none h] at hx; cases hx
      rw [List.append_assoc, List.getElem?_append_left hi]; exact hx
    · intro _
      by_cases hn : new = []
      · subst hn
        have : r = { added restored s a e with states := st } := by rw [hr]; rfl
        rw [this]; simp [added]; omega
      · exact h4 hn
    · intro i x hx
      cases i with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at hx
        subst hx
        apply h2
        exact getElem?_append_singleton (by simp; omega)
      | succ i =>
        simp only [List.getElem?_cons_succ] at hx
        have := h5 i x hx
        simpa [Nat.add_assoc, Nat.add_comm 1 i] using this

/-! ### Rejected scripts -/

/-- One `unsupported` log line per rejected script, in order. -/
theorem unsupportedCmds_spec (bad : List (String × String)) :
    (unsupportedCmds bad).length = bad.length ∧
    ∀ c ∈ unsupportedCmds bad, ∃ msg, c = .log "unsupported" msg := by
  refine ⟨by simp [unsupportedCmds], ?_⟩
  intro c hc
  simp only [unsupportedCmds, List.mem_map] at hc
  obtain ⟨p, _, rfl⟩ := hc
  exact ⟨_, rfl⟩

/-! ### Ownership -/

/-- The service owns an entity id exactly when a live script entity has it. -/
theorem Service.owns_iff (sv : Service) (eid : String) :
    sv.owns eid = true ↔ ∃ s ∈ sv.engine.scripts, s.alive = true ∧ s.entityId = eid := by
  simp [Service.owns]

/-- **HALean owns its script entities**: HA's echo of an owned entity's
state changes nothing but the clock (it is handled as a tick). -/
theorem Service.step_owned_echo (sv : Service) (eid : String) (old new : Option EntityState)
    (now : Instant) (h : sv.owns eid = true) :
    sv.step (.engine (.stateChanged eid old new now)) = sv.step (.engine (.tick now)) := by
  simp [Service.step, h]

/-- Any other engine input is the automation engine's step, unchanged. -/
theorem Service.step_engine (sv : Service) (ev : Automation.Input)
    (h : ∀ eid old new now, ev = .stateChanged eid old new now → sv.owns eid = false) :
    sv.step (.engine ev) =
      ({ sv with engine := (sv.engine.step ev).1 }, (sv.engine.step ev).2, []) := by
  cases ev with
  | stateChanged eid old new now => simp [Service.step, h eid old new now rfl]
  | _ => simp [Service.step]

/-! ### What an input can change -/

private theorem mem_errors {α : Type} (l : List (String × Except String α))
    (f : String × Except String α → Option (String × String))
    (hf1 : ∀ k m, f (k, .error m) = some (k, m)) (hf2 : ∀ k a, f (k, .ok a) = none)
    (k why : String) : (k, why) ∈ l.filterMap f ↔ (k, Except.error why) ∈ l := by
  simp only [List.mem_filterMap]
  constructor
  · rintro ⟨⟨k', r⟩, hm, he⟩
    cases r with
    | error m =>
      simp only [hf1, Option.some.injEq, Prod.mk.injEq] at he; obtain ⟨rfl, rfl⟩ := he; exact hm
    | ok _ => simp [hf2] at he
  · intro hm
    exact ⟨_, hm, hf1 _ _⟩

/-- Engine inputs and service calls never touch the restore data or the
remembered automation configs, and reject nothing. -/
theorem Service.step_engine_call_frame (sv : Service) (i : Input)
    (h : (∃ ev, i = .engine ev) ∨ ∃ cid svc data rr now, i = .call cid svc data rr now) :
    (sv.step i).1.restored = sv.restored ∧
    (sv.step i).1.automationConfigs = sv.automationConfigs ∧
    (sv.step i).2.2 = [] := by
  rcases h with ⟨ev, rfl⟩ | ⟨cid, svc, data, rr, now, rfl⟩
  · simp [Service.step]
  · simp only [Service.step]
    split
    exact ⟨rfl, rfl, rfl⟩

/-- A reload keeps the automation configs it was loaded with. -/
theorem Service.step_reload_configs (sv : Service) (scripts : List (String × Json))
    (now : Instant) :
    (sv.step (.reload scripts now)).1.automationConfigs = sv.automationConfigs := by
  simp only [Service.step]
  split
  rfl

/-- A reload rejects exactly the scripts `decodeAll` refuses, each under
its own key. -/
theorem Service.step_reload_rejected (sv : Service) (scripts : List (String × Json))
    (now : Instant) (k why : String) :
    (k, why) ∈ (sv.step (.reload scripts now)).2.2 ↔
      (k, Except.error why) ∈ decodeAll scripts sv.automationConfigs := by
  simp only [Service.step]
  split
  exact mem_errors _ _ (fun _ _ => rfl) (fun _ _ => rfl) k why

/-- `init` reports the automations that were rejected before, then exactly
the scripts `decodeAll` refuses; it remembers the automation configs, and
restores `last_triggered` only from `script.*` states. -/
theorem Service.step_init (sv : Service) (scripts : List (String × Json))
    (states : List EntityState) (now : Instant) (loc : Option Sun.Observer)
    (autos : List Automation) (badAutos : List (String × String)) (cfgs : List Json)
    (r : Service × List Cmd × List (String × String))
    (hr : sv.step (.init scripts states now loc autos badAutos cfgs) = r) :
    (∀ k why, (k, why) ∈ r.2.2 ↔
      (k, why) ∈ badAutos ∨ (k, Except.error why) ∈ decodeAll scripts cfgs) ∧
    r.1.automationConfigs = cfgs ∧
    (∀ eid us, (eid, us) ∈ r.1.restored →
      eid.startsWith "script." = true ∧
      ∃ s ∈ states, s.entityId = eid ∧ lastTriggeredOf s = some us) := by
  simp only [Service.step] at hr
  split at hr
  subst hr
  refine ⟨?_, rfl, ?_⟩
  · intro k why
    simp only [List.mem_append]
    exact or_congr Iff.rfl (mem_errors _ _ (fun _ _ => rfl) (fun _ _ => rfl) k why)
  · intro eid us hm
    simp only [List.mem_filterMap] at hm
    obtain ⟨s, hs, he⟩ := hm
    split at he
    · rename_i hp
      cases hl : lastTriggeredOf s with
      | none => simp [hl] at he
      | some u =>
        simp only [hl, Option.map_some, Option.some.injEq, Prod.mk.injEq] at he
        obtain ⟨rfl, rfl⟩ := he
        exact ⟨hp, s, hs, rfl, hl⟩
    · cases he

end HALean.Script
