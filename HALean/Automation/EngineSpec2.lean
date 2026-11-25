/-
  Specs for the engine's state operations (HALean/Automation/Engine.lean):
  `runsOf`, `replaceRun`, `cleanupWait`, `removeRun`, `syncFamily`.

  The theorems about `removeRun` and `syncFamily` hold for whatever family
  `familyOf` returns ("every run in the family is removed, with the
  listeners of its wait; nothing else is").
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

private theorem owner_beq_iff (a b : Owner) : (a == b) = true ↔ a = b := by
  cases a <;> cases b <;> simp [BEq.beq, instBEqOwner.beq]

private instance : LawfulBEq Owner where
  eq_of_beq := fun h => (owner_beq_iff _ _).1 h
  rfl := (owner_beq_iff _ _).2 rfl

private theorem find?_map_fix {α : Type} (f : α → α) (p : α → Bool) (l : List α)
    (hp : ∀ x, p (f x) = p x) (hf : ∀ x, p x = true → f x = x) :
    (l.map f).find? p = l.find? p := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    rw [List.map_cons, List.find?_cons, List.find?_cons, hp x]
    cases h : p x
    · exact ih
    · simp only []; rw [hf x h]

/-! ### `runsOf` -/

/-- The automation's runs: its top-level runs, not `parallel` branches. -/
theorem mem_runsOf_iff (e : Engine) (ai : Nat) (r : Run) :
    r ∈ runsOf e ai ↔ r ∈ e.runs ∧ r.autoIdx = ai ∧ r.parent = none := by
  simp [runsOf, Option.isNone_iff_eq_none]

/-- In the engine's order (oldest first). -/
theorem runsOf_sublist (e : Engine) (ai : Nat) : (runsOf e ai).Sublist e.runs :=
  List.filter_sublist

theorem runsOf_length_le (e : Engine) (ai : Nat) : (runsOf e ai).length ≤ e.runs.length :=
  (runsOf_sublist e ai).length_le

/-- Adding a run of automation `ai` adds one run to `ai` and none to others. -/
theorem runsOf_append_top (e : Engine) (r : Run) (ai : Nat) (hp : r.parent = none) :
    runsOf { e with runs := e.runs ++ [r] } ai =
      if r.autoIdx = ai then runsOf e ai ++ [r] else runsOf e ai := by
  by_cases h : r.autoIdx = ai <;> simp [runsOf, List.filter_append, h, hp]

/-- `parallel` branches never count as runs of the automation. -/
theorem runsOf_append_branches (e : Engine) (kids : List Run) (ai : Nat)
    (hp : ∀ k ∈ kids, k.parent ≠ none) :
    runsOf { e with runs := e.runs ++ kids } ai = runsOf e ai := by
  simp only [runsOf, List.filter_append]
  have : kids.filter (fun r => r.autoIdx == ai && r.parent.isNone) = [] := by
    rw [List.filter_eq_nil_iff]
    intro k hk
    have := hp k hk
    cases hpk : k.parent <;> simp_all
  rw [this, List.append_nil]

/-! ### `replaceRun` -/

theorem replaceRun_length (e : Engine) (r : Run) :
    (replaceRun e r).runs.length = e.runs.length := by
  simp [replaceRun]

/-- Run ids, and their order, are unchanged. -/
theorem replaceRun_ids (e : Engine) (r : Run) :
    (replaceRun e r).runs.map (·.id) = e.runs.map (·.id) := by
  simp only [replaceRun, List.map_map]
  apply List.map_congr_left
  intro x _
  by_cases h : x.id = r.id <;> simp [h]

/-- Replacing a run that is not live changes nothing. -/
theorem replaceRun_absent (e : Engine) (r : Run) (h : ∀ x ∈ e.runs, x.id ≠ r.id) :
    replaceRun e r = e := by
  have : e.runs.map (fun x => if x.id == r.id then { r with autoIdx := x.autoIdx, parent := x.parent }
      else x) = e.runs := by
    conv => rhs; rw [← List.map_id e.runs]
    apply List.map_congr_left
    intro x hx
    simp [h x hx]
  unfold replaceRun
  rw [this]

/-- Looking the run up afterwards gives the new version, in the stored
run's automation and under its parent. -/
theorem replaceRun_find (e : Engine) (r : Run) :
    (replaceRun e r).runs.find? (·.id == r.id) =
      (e.runs.find? (·.id == r.id)).map fun x => { r with autoIdx := x.autoIdx, parent := x.parent } := by
  simp only [replaceRun]
  generalize e.runs = l
  induction l with
  | nil => simp
  | cons x xs ih =>
    by_cases hx : x.id = r.id
    · simp [hx]
    · have hb : (x.id == r.id) = false := by simp [hx]
      simp only [List.map_cons, List.find?_cons, hb, Bool.false_eq_true, ite_false]
      exact ih

/-- When the stored run has the same automation and parent (it does when
`r` is a stepped copy of it), looking it up gives exactly `r`. -/
theorem replaceRun_find_same (e : Engine) (r x : Run) (hx : e.runs.find? (·.id == r.id) = some x)
    (ha : x.autoIdx = r.autoIdx) (hp : x.parent = r.parent) :
    (replaceRun e r).runs.find? (·.id == r.id) = some r := by
  rw [replaceRun_find, hx]
  simp [ha, hp]

/-- Other runs are untouched. -/
theorem replaceRun_find_other (e : Engine) (r : Run) (id : Nat) (h : id ≠ r.id) :
    (replaceRun e r).runs.find? (·.id == id) = e.runs.find? (·.id == id) := by
  simp only [replaceRun]
  apply find?_map_fix
  · intro x
    by_cases hx : x.id = r.id
    · have h1 : (r.id == id) = false := by simp [Ne.symm h]
      have h2 : (x.id == id) = false := by rw [hx]; exact h1
      simp [hx, h1]
    · simp [hx]
  · intro x hx
    have : x.id ≠ r.id := by
      have := beq_iff_eq.1 hx
      rw [this]; exact h
    simp [this]

theorem replaceRun_idem (e : Engine) (r : Run) :
    replaceRun (replaceRun e r) r = replaceRun e r := by
  simp only [replaceRun, List.map_map]
  congr 1
  apply List.map_congr_left
  intro x _
  by_cases h : x.id = r.id <;> simp [h]

/-- Updating a run in place keeps every automation's number of runs: resuming or blocking a run never affects
admission (`admit`). -/
theorem replaceRun_runsOf_length (e : Engine) (r : Run) (ai : Nat) :
    (runsOf (replaceRun e r) ai).length = (runsOf e ai).length := by
  simp only [runsOf, replaceRun, List.filter_map, List.length_map]
  congr 1
  apply List.filter_congr
  intro x hx
  by_cases hid : x.id = r.id <;> simp [hid]

/-- Only `runs` changes. -/
theorem replaceRun_rest (e : Engine) (r : Run) :
    (replaceRun e r).automations = e.automations ∧ (replaceRun e r).states = e.states ∧
    (replaceRun e r).now = e.now ∧ (replaceRun e r).pendings = e.pendings ∧
    (replaceRun e r).waitTrigs = e.waitTrigs ∧ (replaceRun e r).tmplTrigs = e.tmplTrigs ∧
    (replaceRun e r).nextRunId = e.nextRunId ∧ (replaceRun e r).woken = e.woken :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-! ### `cleanupWait` -/

/-- A wait's cleanup touches listeners only. -/
theorem cleanupWait_rest (e : Engine) (rid : Nat) :
    (cleanupWait e rid).runs = e.runs ∧ (cleanupWait e rid).automations = e.automations ∧
    (cleanupWait e rid).states = e.states ∧ (cleanupWait e rid).now = e.now ∧
    (cleanupWait e rid).nextRunId = e.nextRunId ∧ (cleanupWait e rid).nextCallId = e.nextCallId ∧
    (cleanupWait e rid).nextPendingId = e.nextPendingId ∧ (cleanupWait e rid).woken = e.woken ∧
    (cleanupWait e rid).lastTriggered = e.lastTriggered ∧ (cleanupWait e rid).scripts = e.scripts :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- Afterwards nothing is left that belongs to the wait. -/
theorem cleanupWait_none_left (e : Engine) (rid : Nat) :
    let e' := cleanupWait e rid
    (∀ x ∈ e'.tmplTrigs, x.owner ≠ .wait rid) ∧ (∀ x ∈ e'.waitTrigs, x.runId ≠ rid) ∧
    (∀ x ∈ e'.pendings, x.owner ≠ .wait rid) ∧ (∀ x ∈ e'.sunNext, x.1.1 ≠ .wait rid) ∧
    (∀ x ∈ e'.timeEnt, x.1.1 ≠ .wait rid) ∧ (∀ x ∈ e'.armed, x.1 ≠ .wait rid) ∧
    (∀ x ∈ e'.periods, x.1.1 ≠ .wait rid) := by
  simp only [cleanupWait]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
    (intro x hx; simpa using (List.mem_filter.1 hx).2)

private theorem filter_keep {α : Type} (l : List α) (f : α → Owner) (o o' : Owner) (h : o ≠ o') :
    (l.filter (fun x => f x != o')).filter (fun x => f x == o) = l.filter (fun x => f x == o) := by
  rw [List.filter_filter]
  apply List.filter_congr
  intro x _
  by_cases hx : f x = o
  · simp [hx, h]
  · simp [hx]

/-- Everybody else's listeners stay, in order. -/
theorem cleanupWait_keeps (e : Engine) (rid : Nat) (o : Owner) (h : o ≠ .wait rid) :
    let e' := cleanupWait e rid
    e'.tmplTrigs.filter (·.owner == o) = e.tmplTrigs.filter (·.owner == o) ∧
    e'.pendings.filter (·.owner == o) = e.pendings.filter (·.owner == o) ∧
    e'.sunNext.filter (·.1.1 == o) = e.sunNext.filter (·.1.1 == o) ∧
    e'.timeEnt.filter (·.1.1 == o) = e.timeEnt.filter (·.1.1 == o) ∧
    e'.armed.filter (·.1 == o) = e.armed.filter (·.1 == o) ∧
    e'.periods.filter (·.1.1 == o) = e.periods.filter (·.1.1 == o) := by
  simp only [cleanupWait]
  exact ⟨filter_keep _ _ _ _ h, filter_keep _ _ _ _ h, filter_keep _ _ _ _ h,
    filter_keep _ _ _ _ h, filter_keep _ _ _ _ h, filter_keep _ _ _ _ h⟩

/-- The wait no longer listens. -/
theorem cleanupWait_not_listening (e : Engine) (rid : Nat) :
    (cleanupWait e rid).listening (.wait rid) = false := by
  simp [Engine.listening, cleanupWait]

/-- Other waits listen as before; automations always do. -/
theorem cleanupWait_listening_other (e : Engine) (rid : Nat) (o : Owner) (h : o ≠ .wait rid) :
    (cleanupWait e rid).listening o = e.listening o := by
  cases o with
  | auto ai => rfl
  | wait rid' =>
    have hne : rid' ≠ rid := fun hh => h (by rw [hh])
    simp only [Engine.listening, cleanupWait, List.any_filter]
    congr 1
    funext w
    by_cases hw : w.runId = rid'
    · simp [hw, hne]
    · simp [hw]

/-- The registry loses exactly the wait's entry. -/
theorem cleanupWait_owners (e : Engine) (rid : Nat) :
    (cleanupWait e rid).owners = e.owners.filter (·.1 != .wait rid) := by
  simp only [Engine.owners, cleanupWait, List.filter_append, List.filter_map]
  congr 1
  congr 1
  symm
  rw [List.filter_eq_self]
  intro x _
  simp

theorem cleanupWait_idem (e : Engine) (rid : Nat) :
    cleanupWait (cleanupWait e rid) rid = cleanupWait e rid := by
  simp [cleanupWait, List.filter_filter]

theorem cleanupWait_comm (e : Engine) (a b : Nat) :
    cleanupWait (cleanupWait e a) b = cleanupWait (cleanupWait e b) a := by
  simp only [cleanupWait, List.filter_filter]
  simp only [Bool.and_comm]

/-! ### `removeRun` -/

private theorem foldl_cleanup_rest (fam : List Nat) (e : Engine) :
    (fam.foldl cleanupWait e).runs = e.runs ∧ (fam.foldl cleanupWait e).automations = e.automations ∧
    (fam.foldl cleanupWait e).states = e.states ∧ (fam.foldl cleanupWait e).now = e.now ∧
    (fam.foldl cleanupWait e).nextRunId = e.nextRunId ∧
    (fam.foldl cleanupWait e).nextCallId = e.nextCallId ∧
    (fam.foldl cleanupWait e).nextPendingId = e.nextPendingId ∧
    (fam.foldl cleanupWait e).woken = e.woken ∧
    (fam.foldl cleanupWait e).lastTriggered = e.lastTriggered ∧
    (fam.foldl cleanupWait e).scripts = e.scripts := by
  induction fam generalizing e with
  | nil => exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  | cons a fam ih => exact ih (cleanupWait e a)

private theorem foldl_cleanup_list {α : Type} (proj : Engine → List α) (key : α → Nat → Bool)
    (h : ∀ e rid, proj (cleanupWait e rid) = (proj e).filter (fun x => key x rid)) :
    ∀ (fam : List Nat) (e : Engine),
      proj (fam.foldl cleanupWait e) = (proj e).filter (fun x => fam.all (key x)) := by
  intro fam
  induction fam with
  | nil => intro e; exact (List.filter_eq_self.2 (fun _ _ => rfl)).symm
  | cons a fam ih =>
    intro e
    rw [List.foldl_cons, ih, h, List.filter_filter]
    apply List.filter_congr
    intro x _
    simp [Bool.and_comm]

/-- The runs that remain: those outside the family, in order. -/
theorem removeRun_runs (e : Engine) (id : Nat) :
    (removeRun e id).runs = e.runs.filter (fun r => !(familyOf e id).contains r.id) := by
  unfold removeRun
  exact (foldl_cleanup_rest _ _).1

/-- Removing a run never adds one. -/
theorem removeRun_runs_sublist (e : Engine) (id : Nat) : (removeRun e id).runs.Sublist e.runs := by
  rw [removeRun_runs]; exact List.filter_sublist

/-- No run of the family is left. -/
theorem removeRun_family_gone (e : Engine) (id : Nat) (r : Run) (h : r ∈ (removeRun e id).runs) :
    r.id ∉ familyOf e id := by
  rw [removeRun_runs] at h
  simpa using (List.mem_filter.1 h).2

/-- Runs outside the family survive. -/
theorem removeRun_keeps_others (e : Engine) (id : Nat) (r : Run) (h : r ∈ e.runs)
    (hf : r.id ∉ familyOf e id) : r ∈ (removeRun e id).runs := by
  rw [removeRun_runs]
  exact List.mem_filter.2 ⟨h, by simpa using hf⟩

/-- No automation gains a run: removal can only free room under `max`. -/
theorem removeRun_runsOf_le (e : Engine) (id ai : Nat) :
    (runsOf (removeRun e id) ai).length ≤ (runsOf e ai).length := by
  unfold runsOf
  exact ((removeRun_runs_sublist e id).filter _).length_le

/-- Removal touches runs and listeners only; ids are never reused. -/
theorem removeRun_rest (e : Engine) (id : Nat) :
    (removeRun e id).automations = e.automations ∧ (removeRun e id).states = e.states ∧
    (removeRun e id).now = e.now ∧ (removeRun e id).nextRunId = e.nextRunId ∧
    (removeRun e id).nextCallId = e.nextCallId ∧
    (removeRun e id).nextPendingId = e.nextPendingId ∧ (removeRun e id).woken = e.woken ∧
    (removeRun e id).lastTriggered = e.lastTriggered ∧ (removeRun e id).scripts = e.scripts := by
  unfold removeRun
  exact (foldl_cleanup_rest _ _).2

/-- The listeners after removal: exactly those not owned by a wait of a
run in the family. -/
theorem removeRun_listeners (e : Engine) (id : Nat) :
    let fam := familyOf e id
    let e' := removeRun e id
    e'.tmplTrigs = e.tmplTrigs.filter (fun x => fam.all fun rid => x.owner != .wait rid) ∧
    e'.waitTrigs = e.waitTrigs.filter (fun x => fam.all fun rid => x.runId != rid) ∧
    e'.pendings = e.pendings.filter (fun x => fam.all fun rid => x.owner != .wait rid) ∧
    e'.sunNext = e.sunNext.filter (fun x => fam.all fun rid => x.1.1 != .wait rid) ∧
    e'.timeEnt = e.timeEnt.filter (fun x => fam.all fun rid => x.1.1 != .wait rid) ∧
    e'.armed = e.armed.filter (fun x => fam.all fun rid => x.1 != .wait rid) ∧
    e'.periods = e.periods.filter (fun x => fam.all fun rid => x.1.1 != .wait rid) := by
  simp only [removeRun]
  exact ⟨foldl_cleanup_list (·.tmplTrigs) (fun x rid => x.owner != .wait rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.waitTrigs) (fun x rid => x.runId != rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.pendings) (fun x rid => x.owner != .wait rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.sunNext) (fun x rid => x.1.1 != .wait rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.timeEnt) (fun x rid => x.1.1 != .wait rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.armed) (fun x rid => x.1 != .wait rid) (fun _ _ => rfl) _ _,
    foldl_cleanup_list (·.periods) (fun x rid => x.1.1 != .wait rid) (fun _ _ => rfl) _ _⟩

/-- Stopping a run stops the waits of its whole family: none of them
listens any more, and no timer of theirs is pending. -/
theorem removeRun_family_silent (e : Engine) (id rid : Nat) (h : rid ∈ familyOf e id) :
    (removeRun e id).listening (.wait rid) = false ∧
    (∀ p ∈ (removeRun e id).pendings, p.owner ≠ .wait rid) ∧
    (∀ x ∈ (removeRun e id).tmplTrigs, x.owner ≠ .wait rid) := by
  obtain ⟨h1, h2, h3, _⟩ := removeRun_listeners e id
  refine ⟨?_, ?_, ?_⟩
  · simp only [Engine.listening, h2, Bool.eq_false_iff, ne_eq, List.any_eq_true, not_exists, not_and]
    intro w hw
    have := (List.mem_filter.1 hw).2
    rw [List.all_eq_true] at this
    simpa using this rid h
  · intro p hp
    rw [h3] at hp
    have := (List.mem_filter.1 hp).2
    rw [List.all_eq_true] at this
    simpa using this rid h
  · intro p hp
    rw [h1] at hp
    have := (List.mem_filter.1 hp).2
    rw [List.all_eq_true] at this
    simpa using this rid h

/-- The automations' own listeners (timers, trackers, armed entities) are
never removed with a run. -/
theorem removeRun_keeps_auto (e : Engine) (id ai : Nat) :
    (removeRun e id).pendings.filter (·.owner == .auto ai) = e.pendings.filter (·.owner == .auto ai) ∧
    (removeRun e id).tmplTrigs.filter (·.owner == .auto ai) = e.tmplTrigs.filter (·.owner == .auto ai) ∧
    (removeRun e id).armed.filter (·.1 == .auto ai) = e.armed.filter (·.1 == .auto ai) := by
  obtain ⟨h1, _, h3, _, _, h6, _⟩ := removeRun_listeners e id
  rw [h1, h3, h6]
  refine ⟨?_, ?_, ?_⟩ <;>
  · rw [List.filter_filter]
    apply List.filter_congr
    intro x _
    simp only [Bool.and_eq_left_iff_imp, beq_iff_eq]
    intro hx
    simp [hx]

/-! ### `syncFamily` -/

private theorem setVar_find_ne (vs : List (String × Template.Value)) (k k' : String)
    (v : Template.Value) (h : k' ≠ k) :
    (setVar vs k v).find? (·.1 == k') = vs.find? (·.1 == k') := by
  have hkk : (k == k') = false := by simp [Ne.symm h]
  unfold setVar
  split
  · apply find?_map_fix
    · rintro ⟨a, b⟩
      by_cases ha : a = k
      · have : (a == k') = false := by rw [ha]; exact hkk
        simp [ha, hkk]
      · simp [ha]
    · rintro ⟨a, b⟩ hx
      have : a ≠ k := by
        have := beq_iff_eq.1 hx
        simp only at this
        rw [this]; exact h
      simp [this]
  · simp [List.find?_append, hkk]

private theorem foldl_setVar_find (shared : List (String × Template.Value)) (k' : String)
    (h : ∀ p ∈ shared, p.1 ≠ k') (vs : List (String × Template.Value)) :
    (shared.foldl (fun vs (p : String × Template.Value) => setVar vs p.1 p.2) vs).find? (·.1 == k')
      = vs.find? (·.1 == k') := by
  induction shared generalizing vs with
  | nil => rfl
  | cons p ps ih =>
    rw [List.foldl_cons, ih (fun q hq => h q (List.mem_cons_of_mem _ hq)),
      setVar_find_ne _ _ _ _ (Ne.symm (h p List.mem_cons_self))]

/-- Sharing variables changes nothing but `vars`: ids, order, automation,
position (`frames`), wait and parent of every run stay. -/
theorem syncFamily_only_vars (e : Engine) (r : Run) :
    (syncFamily e r).runs.map (fun x => { x with vars := [] })
      = e.runs.map (fun x => { x with vars := [] }) := by
  unfold syncFamily
  simp only
  split
  · rfl
  · simp only [List.map_map]
    apply List.map_congr_left
    intro x _
    simp only [Function.comp]
    split <;> rfl

theorem syncFamily_length (e : Engine) (r : Run) :
    (syncFamily e r).runs.length = e.runs.length := by
  have := congrArg List.length (syncFamily_only_vars e r)
  simpa using this

/-- Every automation keeps its number of runs. -/
theorem syncFamily_runsOf_length (e : Engine) (r : Run) (ai : Nat) :
    (runsOf (syncFamily e r) ai).length = (runsOf e ai).length := by
  unfold syncFamily
  simp only
  split
  · rfl
  · simp only [runsOf, List.filter_map, List.length_map]
    congr 1
    apply List.filter_congr
    intro x _
    simp only [Function.comp]
    split <;> rfl

/-- The stopping branch itself is not rewritten. -/
theorem syncFamily_self (e : Engine) (r x : Run) (hx : x ∈ e.runs) (hid : x.id = r.id) :
    x ∈ (syncFamily e r).runs := by
  unfold syncFamily
  simp only
  split
  · exact hx
  · exact List.mem_map.2 ⟨x, hx, by simp [hid]⟩

/-- `wait` and `repeat` are never copied between branches
(`assign_parallel_protected`, and the loop variable of the branch's own
`repeat`). -/
theorem syncFamily_branch_local (e : Engine) (r : Run) (k : String) (hk : k ∈ BRANCH_LOCAL) :
    (syncFamily e r).runs.map (fun x => x.vars.find? (·.1 == k))
      = e.runs.map (fun x => x.vars.find? (·.1 == k)) := by
  unfold syncFamily
  simp only
  split
  · rfl
  · simp only [List.map_map]
    apply List.map_congr_left
    intro x _
    simp only [Function.comp]
    split
    · rfl
    · apply foldl_setVar_find
      intro p hp heq
      have := (List.mem_filter.1 hp).2
      rw [heq] at this
      simp [hk] at this

/-- Only `runs` changes. -/
theorem syncFamily_rest (e : Engine) (r : Run) :
    (syncFamily e r).automations = e.automations ∧ (syncFamily e r).states = e.states ∧
    (syncFamily e r).now = e.now ∧ (syncFamily e r).pendings = e.pendings ∧
    (syncFamily e r).waitTrigs = e.waitTrigs ∧ (syncFamily e r).tmplTrigs = e.tmplTrigs ∧
    (syncFamily e r).nextRunId = e.nextRunId ∧ (syncFamily e r).woken = e.woken := by
  unfold syncFamily
  simp only
  split <;> exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

end HALean.Automation
