/-
  An engine-wide bound on live runs (HALean/Automation/Engine.lean).

  For an engine with no script entities, started by `.init` with automations
  whose `max` is at least 1, after any sequence of inputs:
  * a `single` or `restart` automation has at most one live run;
  * a `queued` or `parallel` automation has at most `max` live runs
    (running or queued; `parallel` branches are not runs of the automation).

  The proof is an invariant: `Inv e` (no scripts, and every automation within
  its bound) holds after every handler, every timer loop and every input.
  `Pres m` says that `m` keeps `Inv`. Only `triggerAutomation` adds runs of an
  automation (`startScript` does too, but has nothing to start without
  script entities), and its admission (`admit`) keeps the bound.
-/
import HALean.Automation.EngineSpec2
import Lean.Elab.Tactic.Basic
open Lean

namespace HALean.Automation

/-- How many live runs an automation may have. -/
def cap (a : Automation) : Nat :=
  match a.mode with
  | .single | .restart => 1
  | .queued | .parallel => a.maxRuns

/-- Every automation has `max ≥ 1` and at most `cap` live runs. -/
def Bounded (e : Engine) : Prop :=
  ∀ ai a, e.automations[ai]? = some a → 1 ≤ a.maxRuns ∧ (runsOf e ai).length ≤ cap a

/-- The invariant: no script entities, and `Bounded`. -/
def Inv (e : Engine) : Prop := e.scripts = [] ∧ Bounded e

/-- `m` keeps the invariant (whatever it returns). Irreducible, so that
`intro` never looks inside. -/
@[irreducible] def Pres {α : Type} (m : EM α) : Prop := ∀ s, Inv s.1 → Inv (m.run s).2.1

/-! ## The invariant under state operations -/

theorem Inv.mono {e e' : Engine} (h : Inv e) (ha : e'.automations = e.automations)
    (hs : e'.scripts = e.scripts) (hr : ∀ ai, (runsOf e' ai).length ≤ (runsOf e ai).length) :
    Inv e' := by
  refine ⟨hs.trans h.1, fun ai a hai => ?_⟩
  rw [ha] at hai
  obtain ⟨h1, h2⟩ := h.2 ai a hai
  exact ⟨h1, Nat.le_trans (hr ai) h2⟩

/-- An update that keeps runs, automations and scripts (any record update
of the other fields). -/
theorem Inv.upd {e e' : Engine} (h : Inv e) (hr : e'.runs = e.runs)
    (ha : e'.automations = e.automations) (hs : e'.scripts = e.scripts) : Inv e' :=
  h.mono ha hs fun ai => by simp only [runsOf, hr]; exact Nat.le_refl _

theorem Inv.replaceRun {e : Engine} (h : Inv e) (r : Run) : Inv (replaceRun e r) :=
  h.mono rfl rfl fun ai => by rw [replaceRun_runsOf_length]; exact Nat.le_refl _

theorem Inv.removeRun {e : Engine} (h : Inv e) (id : Nat) : Inv (removeRun e id) :=
  h.mono (removeRun_rest e id).1 (removeRun_rest e id).2.2.2.2.2.2.2.2 fun ai =>
    removeRun_runsOf_le e id ai

theorem Inv.cleanupWait {e : Engine} (h : Inv e) (rid : Nat) : Inv (cleanupWait e rid) :=
  h.upd rfl rfl rfl

theorem syncFamily_scripts (e : Engine) (r : Run) : (syncFamily e r).scripts = e.scripts := by
  unfold syncFamily; simp only; split <;> rfl

theorem Inv.syncFamily {e : Engine} (h : Inv e) (r : Run) : Inv (syncFamily e r) :=
  h.mono (syncFamily_rest e r).1 (syncFamily_scripts e r) fun ai => by
    rw [syncFamily_runsOf_length]; exact Nat.le_refl _

/-- New `parallel` branches (each has a parent) are not runs of an automation. -/
theorem Inv.branches {e e' : Engine} (h : Inv e) (kids : List Run)
    (hr : e'.runs = e.runs ++ kids) (ha : e'.automations = e.automations)
    (hs : e'.scripts = e.scripts) (hp : ∀ k ∈ kids, k.parent ≠ none) : Inv e' :=
  h.mono ha hs fun ai => by
    have := runsOf_append_branches e kids ai hp
    simp only [runsOf] at this ⊢
    rw [hr, this]; exact Nat.le_refl _

/-- A record update of anything but runs, automations and scripts. -/
theorem Inv.mk {e : Engine} (h : Inv e) {st now pend armed nri nci npi ls tt lt per wt wk loc sun te sg hs} :
    Inv ⟨e.automations, st, now, pend, armed, e.runs, nri, nci, npi, ls, tt, lt, per, wt, wk, loc, sun,
      te, e.scripts, sg, hs⟩ :=
  h.upd rfl rfl rfl

/-- A record update that adds `parallel` branches. -/
theorem Inv.mkBranches {e : Engine} (h : Inv e) {kids : List Run} (hp : ∀ k ∈ kids, k.parent ≠ none)
    {st now pend armed nri nci npi ls tt lt per wt wk loc sun te sg hs} :
    Inv ⟨e.automations, st, now, pend, armed, e.runs ++ kids, nri, nci, npi, ls, tt, lt, per, wt, wk, loc,
      sun, te, e.scripts, sg, hs⟩ :=
  h.branches kids rfl rfl rfl hp

open Lean Elab Tactic Meta in
/-- Succeeds when the goal is `Inv X` with `X` an application of `f`. -/
elab "guard_inv_head" f:ident : tactic => do
  let n ← realizeGlobalConstNoOverloadWithInfo f
  let t ← instantiateMVars (← getMainTarget)
  match t.getAppFnArgs with
  | (``Inv, #[x]) => unless x.consumeMData.isAppOf n do throwError "other head"
  | _ => throwError "not Inv"

theorem Inv.let_ {α : Type} {v : α} {f : α → Engine} (h : Inv (f v)) : Inv (let x := v; f x) := h

open Lean Elab Tactic Meta in
/-- Succeeds when the goal is `Inv X` with `X` a `let`. -/
elab "guard_inv_let" : tactic => do
  let t ← instantiateMVars (← getMainTarget)
  match t.getAppFnArgs with
  | (``Inv, #[x]) => unless x.consumeMData.isLet do throwError "not a let"
  | _ => throwError "not Inv"

/-- Proves `Inv X` from a hypothesis `Inv e`, `X` built from `e` by the
engine's state operations and record updates. -/
syntax "inv_tac" : tactic
macro_rules
  | `(tactic| inv_tac) => `(tactic| first
    | assumption
    | (guard_inv_let; apply Inv.let_; inv_tac)
    | (guard_inv_head Engine.mk; first
        | (refine Inv.mk ?_; inv_tac)
        | (refine Inv.mkBranches ?_ ?_; inv_tac
           -- the new runs are `parallel` branches
           intro k hk; simp only [List.mem_map] at hk; obtain ⟨_, _, rfl⟩ := hk; simp))
    | (guard_inv_head replaceRun; refine Inv.replaceRun ?_ _; inv_tac)
    | (guard_inv_head removeRun; refine Inv.removeRun ?_ _; inv_tac)
    | (guard_inv_head cleanupWait; refine Inv.cleanupWait ?_ _; inv_tac)
    | (guard_inv_head syncFamily; refine Inv.syncFamily ?_ _; inv_tac))

/-! ## Programs that keep the invariant -/

theorem Pres.pure {α : Type} (x : α) : Pres (pure x : EM α) := by unfold Pres; exact fun _ h => h

theorem Pres.bind {α β : Type} {m : EM α} {f : α → EM β} (hm : Pres m) (hf : ∀ x, Pres (f x)) :
    Pres (m >>= f) := by
  unfold Pres at *; exact fun s h => hf _ _ (hm s h)

theorem Pres.getE_bind {β : Type} {f : Engine → EM β} (hf : ∀ e, Inv e → Pres (f e)) :
    Pres (getE >>= f) := by
  unfold Pres at *; exact fun s h => hf s.1 h s h

theorem Pres.getE : Pres getE := by unfold Pres; exact fun _ h => h

theorem Pres.setE {e : Engine} (h : Inv e) : Pres (setE e) := by unfold Pres; exact fun _ _ => h

theorem Pres.emit (cs : List Cmd) : Pres (emit cs) := by unfold Pres; exact fun _ h => h

theorem Pres.forIn {α β : Type} (xs : List α) (b : β) {f : α → β → EM (ForInStep β)}
    (hf : ∀ x b, Pres (f x b)) : Pres (forIn xs b f) := by
  induction xs generalizing b with
  | nil => exact Pres.pure b
  | cons x xs ih =>
    simp only [List.forIn_cons]
    refine Pres.bind (hf x b) fun r => ?_
    cases r with
    | done b' => exact Pres.pure b'
    | yield b' => exact ih b'

theorem Pres.let_ {α β : Type} {v : α} {f : α → EM β} (h : Pres (f v)) :
    Pres (let x := v; f x) := h

open Lean Elab Tactic Meta in
/-- One step on a goal `Pres m`, chosen by the head of `m` (never by
unification, which could unfold the engine's functions). -/
elab "pres_step" : tactic => do
  let t ← instantiateMVars (← getMainTarget)
  if t.isForall then evalTactic (← `(tactic| intro _)); return
  let some m := (match t.getAppFnArgs with
    | (``Pres, #[_, m]) => some m
    | _ => none) | throwError "not Pres"
  let m := m.consumeMData.headBeta
  if m.isLet then evalTactic (← `(tactic| apply Pres.let_)); return
  let fn := m.getAppFn.consumeMData
  if let .const n _ := fn then
    if n == ``Bind.bind then
      let args := m.getAppArgs
      if args.size == 6 && args[4]!.isConstOf ``getE then
        evalTactic (← `(tactic| (apply Pres.getE_bind; intro _ _)))
      else evalTactic (← `(tactic| apply Pres.bind))
      return
    if n == ``Pure.pure then evalTactic (← `(tactic| exact Pres.pure _)); return
    if n == ``emit then evalTactic (← `(tactic| exact Pres.emit _)); return
    if n == ``getE then evalTactic (← `(tactic| exact Pres.getE)); return
    if n == ``setE then evalTactic (← `(tactic| (apply Pres.setE; inv_tac))); return
    if n == ``ForIn.forIn then evalTactic (← `(tactic| apply Pres.forIn)); return
    if n == ``ite || n == ``dite || (← isMatcher n) then evalTactic (← `(tactic| split)); return
  if fn.isFVar then
    -- a join point or local function: inline it
    evalTactic (← `(tactic| (dsimp only; skip))); return
  throwError "pres_step: unknown program head"

/-- Walks a `do` block: binds, reads, writes, loops and branches. `lemmas`
close calls to other programs. -/
syntax "pres" ("[" term,* "]")? : tactic
macro_rules
  | `(tactic| pres) => `(tactic| pres [])
  | `(tactic| pres [$ls,*]) => `(tactic| repeat' (first
    | pres_step
    $[| (apply $ls)]*))

/-! ## Helpers that never touch runs -/

theorem Pres.writeEntity (ai : Nat) : Pres (writeEntity ai) := by
  unfold HALean.Automation.writeEntity; pres

theorem Pres.setupWait (r : Run) (t : Template.Tmpl) : Pres (setupWait r t) := by
  unfold HALean.Automation.setupWait; pres

theorem Pres.updateTimeEntity (o : Owner) (idx : Nat) (eid : String) (off : Int)
    (new : Option EntityState) : Pres (updateTimeEntity o idx eid off new) := by
  unfold HALean.Automation.updateTimeEntity; pres

theorem Pres.attachTriggers (o : Owner) (trigs : List Trigger) : Pres (attachTriggers o trigs) := by
  unfold HALean.Automation.attachTriggers; pres [Pres.updateTimeEntity]

/-! ## The run handlers -/

/-- Every handler of `h` keeps the invariant. -/
structure HPres (h : Handlers) : Prop where
  drive : ∀ r, Pres (h.drive r)
  finishRun : ∀ r x, Pres (h.finishRun r x)
  releaseQueue : ∀ ai, Pres (h.releaseQueue ai)
  finishBranch : ∀ p k x, Pres (h.finishBranch p k x)
  answer : ∀ c x, Pres (h.answer c x)
  continueNow : ∀ c, Pres (h.continueNow c)
  stopRun : ∀ id b, Pres (h.stopRun id b)
  cancelRun : ∀ id, Pres (h.cancelRun id)
  startScript : ∀ ai vs c st, Pres (h.startScript ai vs c st)
  callLocal : ∀ c ops, Pres (h.callLocal c ops)

theorem HPres.out : HPres Handlers.out := by
  constructor <;> intros <;> simp only [Handlers.out] <;> pres

attribute [local irreducible] HALean.Automation.exec

section
variable {h : Handlers} (hh : HPres h)
include hh

theorem Pres.finishRunH (r : Run) (x : RunEnd) : Pres (finishRunH h r x) := by
  unfold HALean.Automation.finishRunH
  pres [hh.finishBranch, hh.answer, hh.releaseQueue, Pres.writeEntity]

theorem Pres.releaseQueueH (ai : Nat) : Pres (releaseQueueH h ai) := by
  unfold HALean.Automation.releaseQueueH; pres [hh.drive]

theorem Pres.finishBranchH (p k : Nat) (x : RunEnd) : Pres (finishBranchH h p k x) := by
  unfold HALean.Automation.finishBranchH; pres [hh.finishRun]

theorem Pres.answerH (c : Caller) (x : CallRes) : Pres (answerH h c x) := by
  unfold HALean.Automation.answerH; pres [hh.finishRun, hh.cancelRun]

theorem Pres.continueNowH (c : Caller) : Pres (continueNowH h c) := by
  unfold HALean.Automation.continueNowH; pres [hh.drive]

theorem Pres.stopRunH (id : Nat) (b : Bool) : Pres (stopRunH h id b) := by
  unfold HALean.Automation.stopRunH
  pres [hh.stopRun, hh.answer, hh.releaseQueue, Pres.writeEntity]

theorem Pres.cancelRunH (id : Nat) : Pres (cancelRunH h id) := by
  unfold HALean.Automation.cancelRunH
  pres [hh.finishBranch, hh.answer, hh.releaseQueue, Pres.writeEntity]

theorem Pres.callLocalH (c : Caller) (ops : List HALean.Script.LocalOp) : Pres (callLocalH h c ops) := by
  unfold HALean.Automation.callLocalH
  pres [hh.stopRun, hh.answer, hh.startScript, hh.continueNow, Pres.writeEntity]

omit hh in
/-- Without script entities, `startScript` has nothing to start. -/
theorem Pres.startScriptH (ai : Nat) (vs : List (String × Template.Value)) (c : Option Caller)
    (st : List Nat) : Pres (startScriptH h ai vs c st) := by
  unfold HALean.Automation.startScriptH
  apply Pres.getE_bind
  intro e he
  split
  · rename_i heq
    simp only [he.1, List.getElem?_nil, Prod.mk.injEq, reduceCtorEq, and_false] at heq
  · exact Pres.pure _

theorem Pres.driveH (r : Run) : Pres (driveH h r) := by
  unfold HALean.Automation.driveH
  apply Pres.getE_bind
  intro e he
  generalize exec { env := e.condEnv, nextCallId := e.nextCallId } r = out
  obtain ⟨res, cmds, ctx⟩ := out
  cases res with
  | spawn r' branches coe =>
    dsimp only
    refine Pres.bind (Pres.setE ((Inv.mk he).syncFamily _)) fun _ => ?_
    refine Pres.bind (Pres.emit _) fun _ => ?_
    apply Pres.getE_bind
    intro e1 he1
    apply Pres.setE
    refine Inv.mkBranches (he1.replaceRun _) ?_
    intro k hk
    simp only [List.mem_map] at hk
    obtain ⟨_, _, rfl⟩ := hk
    simp
  | blocked r' =>
    dsimp only
    pres [hh.callLocal, Pres.setupWait, Pres.attachTriggers]
  | done r' x =>
    dsimp only
    refine Pres.bind (Pres.setE ((Inv.mk he).syncFamily _)) fun _ => ?_
    refine Pres.bind (Pres.emit _) fun _ => ?_
    exact hh.finishRun _ _

end

theorem HPres.next {h : Handlers} (hh : HPres h) : HPres h.next where
  drive := Pres.driveH hh
  finishRun := Pres.finishRunH hh
  releaseQueue := Pres.releaseQueueH hh
  finishBranch := Pres.finishBranchH hh
  answer := Pres.answerH hh
  continueNow := Pres.continueNowH hh
  stopRun := Pres.stopRunH hh
  cancelRun := Pres.cancelRunH hh
  startScript := Pres.startScriptH
  callLocal := Pres.callLocalH hh

theorem HPres.handlers : ∀ n, HPres (handlers n)
  | 0 => HPres.out
  | n + 1 => (HPres.handlers n).next

theorem HPres.engine : HPres engine := HPres.handlers _

theorem Pres.drive (r : Run) : Pres (drive r) := HPres.engine.drive r
theorem Pres.finishRun (r : Run) (x : RunEnd) : Pres (finishRun r x) := HPres.engine.finishRun r x

/-! ## Admission -/

theorem Admit.eq_restart {x : Admit} (h : (x == Admit.restart) = true) : x = .restart := by
  cases x <;> first | rfl | exact (Bool.false_ne_true h).elim

theorem Admit.ne_restart {x : Admit} (h : ¬(x == Admit.restart) = true) : x ≠ .restart :=
  fun hx => by subst hx; exact h rfl

/-- `admit` lets a run start (or queue) only below the bound. -/
theorem admit_room {a : Automation} {n : Nat} (hmax : 1 ≤ a.maxRuns) (hn : n ≤ cap a)
    (hd : ∀ why, admit a.mode a.maxRuns n = .reject why → False)
    (hnr : ¬(admit a.mode a.maxRuns n == .restart) = true) : n + 1 ≤ cap a := by
  have hnr' := Admit.ne_restart hnr
  unfold cap at hn ⊢
  unfold admit at hd hnr'
  by_cases h0 : n = 0
  · subst h0; cases a.mode <;> simp <;> omega
  · cases hm : a.mode <;> simp [hm, h0] at hd hnr' hn ⊢
    · by_cases hx : n = a.maxRuns
      · exact (hd "Maximum number of runs exceeded" (by simp [hx])).elim
      · omega
    · by_cases hx : n = a.maxRuns
      · exact (hd "Maximum number of runs exceeded" (by simp [hx])).elim
      · omega

/-- A `restart` admission only happens in `restart` mode. -/
theorem admit_restart {a : Automation} {n : Nat} (h : (admit a.mode a.maxRuns n == .restart) = true) :
    a.mode = .restart := by
  have h' := Admit.eq_restart h
  unfold admit at h'
  cases hm : a.mode <;> by_cases h0 : n = 0 <;> simp [hm, h0] at h' ⊢
  all_goals (split at h' <;> simp at h')

theorem runsOf_append_run (e e' : Engine) (run : Run) (hr : e'.runs = e.runs ++ [run])
    (hrp : run.parent = none) (ai : Nat) :
    runsOf e' ai = if run.autoIdx = ai then runsOf e ai ++ [run] else runsOf e ai := by
  have := runsOf_append_top e run ai hrp
  simp only [runsOf] at this ⊢
  rw [hr]; exact this

/-- Admission without `restart`: one more run, within the bound. -/
theorem Inv.admitted {e : Engine} {ai : Nat} {a : Automation} (h : Inv e)
    (ha : e.automations[ai]? = some a)
    (hd : ∀ why, admit a.mode a.maxRuns (runsOf e ai).length = .reject why → False)
    (hnr : ¬(admit a.mode a.maxRuns (runsOf e ai).length == .restart) = true)
    (run : Run) {e' : Engine} (hr : e'.runs = e.runs ++ [run]) (hrai : run.autoIdx = ai)
    (hrp : run.parent = none) (ha' : e'.automations = e.automations) (hs' : e'.scripts = e.scripts) :
    Inv e' := by
  refine ⟨hs'.trans h.1, fun ai' a' hai' => ?_⟩
  rw [ha'] at hai'
  obtain ⟨h1, h2⟩ := h.2 ai' a' hai'
  refine ⟨h1, ?_⟩
  rw [runsOf_append_run e e' run hr hrp]
  by_cases hx : run.autoIdx = ai'
  · subst hrai
    simp only [hx, ↓reduceIte]
    subst hx
    rw [ha] at hai'; cases hai'
    simp only [List.length_append, List.length_singleton]
    exact admit_room h1 h2 hd hnr
  · simp only [hx, ↓reduceIte]; exact h2

/-- `l` is a sublist of `A ++ B` with nothing from `A`: a sublist of `B`. -/
theorem sublist_of_append_not_mem {α : Type} {l A B : List α} (h : l.Sublist (A ++ B))
    (hn : ∀ x ∈ l, x ∉ A) : l.Sublist B := by
  induction A generalizing l with
  | nil => simpa using h
  | cons a A ih =>
    cases h with
    | cons _ h => exact ih h fun x hx hA => hn x hx (List.mem_cons_of_mem _ hA)
    | cons_cons _ h => exact absurd (List.mem_cons_self) (hn a (List.mem_cons_self))

theorem mem_familyOf_self (e : Engine) (id : Nat) : id ∈ familyOf e id := by
  unfold familyOf familyOfF; exact List.mem_cons_self

/-- Removing runs one by one: what is left is a sublist, without any of the
removed ids; automations and scripts stay. -/
theorem foldl_removeRun (olds : List Run) (e : Engine) :
    (olds.foldl (fun b a => HALean.Automation.removeRun b a.id) e).runs.Sublist e.runs ∧
    (∀ r ∈ (olds.foldl (fun b a => HALean.Automation.removeRun b a.id) e).runs, ∀ o ∈ olds, r.id ≠ o.id) ∧
    (olds.foldl (fun b a => HALean.Automation.removeRun b a.id) e).automations = e.automations ∧
    (olds.foldl (fun b a => HALean.Automation.removeRun b a.id) e).scripts = e.scripts := by
  induction olds generalizing e with
  | nil => simp
  | cons o olds ih =>
    obtain ⟨ih1, ih2, ih3, ih4⟩ := ih (removeRun e o.id)
    simp only [List.foldl_cons]
    refine ⟨ih1.trans (removeRun_runs_sublist e o.id), fun r hr o' ho' => ?_,
      ih3.trans (removeRun_rest e o.id).1, ih4.trans (removeRun_rest e o.id).2.2.2.2.2.2.2.2⟩
    rcases List.mem_cons.1 ho' with rfl | ho'
    · intro hid
      have hr' := ih1.subset hr
      exact removeRun_family_gone e o'.id r hr' (hid ▸ mem_familyOf_self e o'.id)
    · exact ih2 r hr o' ho'

/-- Admission with `restart`: the new run is added, then every old run of the
automation is removed; one run is left. -/
theorem Inv.restarted {e : Engine} {ai : Nat} {a : Automation} (h : Inv e)
    (ha : e.automations[ai]? = some a)
    (hrs : (admit a.mode a.maxRuns (runsOf e ai).length == .restart) = true)
    (run : Run) {e' : Engine} (hr : e'.runs = e.runs ++ [run]) (hrai : run.autoIdx = ai)
    (hrp : run.parent = none) (ha' : e'.automations = e.automations) (hs' : e'.scripts = e.scripts) :
    Inv ((runsOf e ai).foldl (fun b a => HALean.Automation.removeRun b a.id) e') := by
  obtain ⟨f1, f2, f3, f4⟩ := foldl_removeRun (runsOf e ai) e'
  generalize (runsOf e ai).foldl (fun b a => HALean.Automation.removeRun b a.id) e' = ef at f1 f2 f3 f4
  refine ⟨f4.trans (hs'.trans h.1), fun ai' a' hai' => ?_⟩
  rw [f3, ha'] at hai'
  obtain ⟨h1, h2⟩ := h.2 ai' a' hai'
  refine ⟨h1, ?_⟩
  have hsub : (runsOf ef ai').Sublist (runsOf e' ai') := f1.filter _
  rw [runsOf_append_run e e' run hr hrp] at hsub
  by_cases hx : run.autoIdx = ai'
  · simp only [hx, ↓reduceIte] at hsub
    subst hrai; subst hx
    rw [ha] at hai'; cases hai'
    have hcap : cap a = 1 := by unfold cap; rw [admit_restart hrs]
    rw [hcap]
    have hB := sublist_of_append_not_mem hsub fun x hx hA =>
      f2 x ((List.filter_sublist).subset hx) x hA rfl
    simpa using hB.length_le
  · simp only [hx, ↓reduceIte] at hsub
    exact Nat.le_trans hsub.length_le h2

theorem Pres.triggerAutomation (ai : Nat) (tv : TriggerVars) : Pres (triggerAutomation ai tv) := by
  unfold HALean.Automation.triggerAutomation
  simp only [List.forIn_pure_yield_eq_foldl, pure_bind]
  pres [Pres.drive]
  all_goals
    apply Pres.setE
    first
    | (apply Inv.restarted <;> first | assumption | rfl)
    | (apply Inv.admitted <;> first | assumption | rfl)

/-! ## Triggers, timers and inputs -/

theorem Pres.fire (o : Owner) (tv : TriggerVars) : Pres (fire o tv) := by
  unfold HALean.Automation.fire; pres [Pres.triggerAutomation]

theorem Pres.resumeWokenF : ∀ n, Pres (resumeWokenF n)
  | 0 => by unfold HALean.Automation.resumeWokenF; pres
  | n + 1 => by unfold HALean.Automation.resumeWokenF; pres [Pres.drive, Pres.resumeWokenF n]

theorem Pres.resumeWoken : Pres resumeWoken := Pres.resumeWokenF _

theorem Pres.addPeriodPending (o : Owner) (key : Owner × Nat × String) (us : Int) (check : SameCheck)
    (tv : TriggerVars) : Pres (addPeriodPending o key us check tv) := by
  unfold HALean.Automation.addPeriodPending; pres

theorem Pres.logPeriodError (o : Owner) (msg : String) : Pres (logPeriodError o msg) := by
  unfold HALean.Automation.logPeriodError; pres

theorem Pres.onStateTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    Pres (onStateTrigger o t eid old new) := by
  unfold HALean.Automation.onStateTrigger
  pres [Pres.fire, Pres.addPeriodPending, Pres.logPeriodError]

theorem Pres.onNumericTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    Pres (onNumericTrigger o t eid old new) := by
  unfold HALean.Automation.onNumericTrigger
  pres [Pres.fire, Pres.addPeriodPending, Pres.logPeriodError]

theorem Pres.getTT (o : Owner) (idx : Nat) : Pres (getTT o idx) := by
  unfold HALean.Automation.getTT; pres

theorem Pres.saveTT (st : TmplTrig) : Pres (saveTT st) := by
  unfold HALean.Automation.saveTT; pres

theorem Pres.templateListener (o : Owner) (t : Trigger) (forP : Option ForPeriod) (st : TmplTrig)
    (r : Except String Template.Value) (ev : Option Deferred) :
    Pres (templateListener o t forP st r ev) := by
  unfold HALean.Automation.templateListener
  pres [Pres.fire, Pres.saveTT, Pres.logPeriodError]

theorem Pres.templateRefresh (o : Owner) (t : Trigger) (ev : Option Deferred) :
    Pres (templateRefresh o t ev) := by
  unfold HALean.Automation.templateRefresh
  pres [Pres.getTT, Pres.saveTT, Pres.templateListener]

theorem Pres.trackerGate (st : TmplTrig) (eid : String) (old new : Option EntityState) (replay : Bool) :
    Pres (trackerGate st eid old new replay) := by
  unfold HALean.Automation.trackerGate; pres [Pres.saveTT]

theorem Pres.waitRefresh (st : TmplTrig) : Pres (waitRefresh st) := by
  unfold HALean.Automation.waitRefresh; pres [Pres.saveTT]

theorem Pres.resumeRuns (rids : List Nat) : Pres (resumeRuns rids) := by
  unfold HALean.Automation.resumeRuns; pres [Pres.drive]

theorem Pres.onWaitTrackers (eid : String) (old new : Option EntityState) :
    Pres (onWaitTrackers eid old new) := by
  unfold HALean.Automation.onWaitTrackers; pres [Pres.trackerGate, Pres.waitRefresh]

theorem Pres.onTemplateTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState)
    (replay : Bool) : Pres (onTemplateTrigger o t eid old new replay) := by
  unfold HALean.Automation.onTemplateTrigger
  pres [Pres.getTT, Pres.trackerGate, Pres.templateRefresh]

theorem Pres.onZoneTrigger (o : Owner) (t : Trigger) (eid : String) (old new : Option EntityState) :
    Pres (onZoneTrigger o t eid old new) := by
  unfold HALean.Automation.onZoneTrigger; pres [Pres.fire]

theorem Pres.onStateChanged (eid : String) (old new : Option EntityState) :
    Pres (onStateChanged eid old new) := by
  unfold HALean.Automation.onStateChanged
  pres [Pres.onStateTrigger, Pres.onNumericTrigger, Pres.onTemplateTrigger, Pres.onZoneTrigger,
    Pres.updateTimeEntity, Pres.onWaitTrackers, Pres.resumeRuns, Pres.resumeWoken]

theorem Pres.onEvent (ty : String) (data : Json) : Pres (onEvent ty data) := by
  unfold HALean.Automation.onEvent; pres [Pres.fire]

theorem Pres.fireTimeTriggers (sec : Nat) (tz : Int) : Pres (fireTimeTriggers sec tz) := by
  unfold HALean.Automation.fireTimeTriggers
  pres [Pres.fire, Pres.getTT, Pres.templateRefresh, Pres.waitRefresh, Pres.resumeRuns, Pres.resumeWoken]

theorem Pres.fireDueF (t : Millis) : ∀ n, Pres (fireDueF t n)
  | 0 => by unfold HALean.Automation.fireDueF; pres
  | n + 1 => by
    unfold HALean.Automation.fireDueF
    pres [Pres.fire, Pres.resumeWoken, Pres.drive, Pres.finishRun, Pres.saveTT, Pres.trackerGate,
      Pres.waitRefresh, Pres.resumeRuns, Pres.onTemplateTrigger, Pres.fireDueF t n]

theorem Pres.fireDue (t : Millis) : Pres (fireDue t) := Pres.fireDueF t _

theorem Pres.fireSunF (t : Millis) : ∀ n, Pres (fireSunF t n)
  | 0 => by unfold HALean.Automation.fireSunF; pres
  | n + 1 => by
    unfold HALean.Automation.fireSunF; pres [Pres.fire, Pres.resumeWoken, Pres.fireSunF t n]

theorem Pres.fireSun (t : Millis) : Pres (fireSun t) := Pres.fireSunF t _

theorem Pres.fireTimePointsF (t : Millis) : ∀ n, Pres (fireTimePointsF t n)
  | 0 => by unfold HALean.Automation.fireTimePointsF; pres
  | n + 1 => by
    unfold HALean.Automation.fireTimePointsF; pres [Pres.fire, Pres.resumeWoken, Pres.fireTimePointsF t n]

theorem Pres.fireTimePoints (t : Millis) : Pres (fireTimePoints t) := Pres.fireTimePointsF t _

theorem Pres.advanceTo (now : Instant) : Pres (advanceTo now) := by
  unfold HALean.Automation.advanceTo
  pres [Pres.fireDue, Pres.fireSun, Pres.fireTimePoints, Pres.fireTimeTriggers]

theorem Pres.initArmed : Pres initArmed := by
  unfold HALean.Automation.initArmed; pres [Pres.attachTriggers]

/-- What the theorem asks of an input: an `init` gives every automation a
`max` of at least 1 (the decoder gives at least 2, as HA does). -/
def Input.ok : Input → Prop
  | .init autos .. => ∀ a ∈ autos, 1 ≤ a.maxRuns
  | _ => True

/-- The engine `init` builds: no runs, no scripts. -/
theorem Inv.init (autos : List Automation) (sts : List EntityState) (now : Instant)
    (loc : Option Sun.Observer) (h : ∀ a ∈ autos, 1 ≤ a.maxRuns) :
    Inv { automations := autos, states := sts.map (fun s => (s.entityId, s)), now,
          lastSec := now.utc / 1000, location := loc } := by
  refine ⟨rfl, fun ai a ha => ⟨h a (List.mem_of_getElem? ha), ?_⟩⟩
  simp [runsOf]

theorem Pres.handle (i : Input) (hi : i.ok) : Pres (handle i) := by
  cases i with
  | init autos sts now loc =>
    dsimp only [HALean.Automation.handle]
    exact Pres.bind (Pres.setE (Inv.init autos sts now loc hi)) fun _ => Pres.initArmed
  | stateChanged =>
    dsimp only [HALean.Automation.handle]; pres [Pres.advanceTo, Pres.onStateChanged, Pres.fireDue]
  | event =>
    dsimp only [HALean.Automation.handle]; pres [Pres.advanceTo, Pres.onEvent, Pres.resumeWoken]
  | tick => dsimp only [HALean.Automation.handle]; exact Pres.advanceTo _
  | serviceResult =>
    dsimp only [HALean.Automation.handle]
    pres [Pres.advanceTo, Pres.drive, Pres.finishRun, Pres.resumeWoken]

/-- **One input keeps the bound.** An engine without script entities whose
automations are within their bound stays so after any input (an `init`
needs `max ≥ 1`). -/
theorem Inv.step {e : Engine} (he : Inv e) (i : Input) (hi : i.ok) : Inv (e.step i).1 := by
  have := Pres.handle i hi
  unfold Pres at this
  exact this (e, []) he

/-- The empty engine has nothing to bound. -/
theorem Inv.empty : Inv ({} : Engine) := ⟨rfl, fun ai a ha => by simp at ha⟩

/-- Any sequence of inputs keeps the bound. -/
theorem Inv.steps {e : Engine} (he : Inv e) (is : List Input) (hi : ∀ i ∈ is, i.ok) :
    Inv (is.foldl (fun e i => (e.step i).1) e) := by
  induction is generalizing e with
  | nil => exact he
  | cons i is ih =>
    exact ih (he.step i (hi i List.mem_cons_self)) fun j hj => hi j (List.mem_cons_of_mem _ hj)

/-- **The engine-wide bound.** Start the engine with `init` (automations with
`max ≥ 1`, no script entities), then feed it any inputs (every later `init`
also with `max ≥ 1`). Afterwards a `single` or `restart` automation has at
most one live run, and a `queued` or `parallel` one at most `max`. -/
theorem runs_bounded (autos : List Automation) (sts : List EntityState) (now : Instant)
    (loc : Option Sun.Observer) (hmax : ∀ a ∈ autos, 1 ≤ a.maxRuns)
    (is : List Input) (hi : ∀ i ∈ is, i.ok) (ai : Nat) (a : Automation) :
    let e := is.foldl (fun e i => (e.step i).1) (Engine.step {} (.init autos sts now loc)).1
    e.automations[ai]? = some a →
      ((a.mode = .single ∨ a.mode = .restart) → (runsOf e ai).length ≤ 1) ∧
      ((a.mode = .queued ∨ a.mode = .parallel) → (runsOf e ai).length ≤ a.maxRuns) := by
  intro e ha
  have h := ((Inv.empty.step (.init autos sts now loc) hmax).steps is hi).2 ai a ha
  refine ⟨fun hm => ?_, fun hm => ?_⟩ <;> have h2 := h.2 <;> unfold cap at h2 <;>
    rcases hm with hm | hm <;> rw [hm] at h2 <;> exact h2

end HALean.Automation
