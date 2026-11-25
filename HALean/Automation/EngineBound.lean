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
theorem Inv.mk {e : Engine} (h : Inv e) {st now pend armed nri nci npi ls tt lt per wt wk loc sun te} :
    Inv ⟨e.automations, st, now, pend, armed, e.runs, nri, nci, npi, ls, tt, lt, per, wt, wk, loc, sun,
      te, e.scripts⟩ :=
  h.upd rfl rfl rfl

/-- A record update that adds `parallel` branches. -/
theorem Inv.mkBranches {e : Engine} (h : Inv e) {kids : List Run} (hp : ∀ k ∈ kids, k.parent ≠ none)
    {st now pend armed nri nci npi ls tt lt per wt wk loc sun te} :
    Inv ⟨e.automations, st, now, pend, armed, e.runs ++ kids, nri, nci, npi, ls, tt, lt, per, wt, wk, loc,
      sun, te, e.scripts⟩ :=
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
        | (refine Inv.mkBranches ?_ ?_; inv_tac))
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

end HALean.Automation
