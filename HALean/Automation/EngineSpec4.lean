/-
  Specs for the engine's loops over listeners (HALean/Automation/Engine.lean):
  `onEvent`, `attachTriggers`, `initArmed` (through `Engine.step` on `init`)
  and `onWaitTrackers`, in the cases where no listener reacts.
-/
import HALean.Automation.Engine
open Lean

namespace HALean.Automation

/-! ### Loops in the `EM` monad -/

/-- A loop whose steps all leave the state alone leaves the state alone. -/
private theorem forIn_state_inv {α β σ : Type} (l : List α)
    (f : α → β → StateT σ Id (ForInStep β)) (s : σ)
    (h : ∀ x ∈ l, ∀ b, ((f x b) s).2 = s) : ∀ init, ((forIn l init f) s).2 = s := by
  induction l with
  | nil => intro init; rfl
  | cons x xs ih =>
    intro init
    rw [List.forIn_cons]
    have hx := h x List.mem_cons_self init
    show ((f x init >>= _) s).2 = s
    simp only [bind, StateT.bind]
    rcases hfx : f x init s with ⟨r, s'⟩
    rw [hfx] at hx
    simp only at hx
    subst hx
    cases r with
    | done b => rfl
    | yield b => exact ih (fun y hy => h y (List.mem_cons_of_mem _ hy)) b

private theorem bind_state_inv {σ α β : Type} (m : StateT σ Id α) (k : α → StateT σ Id β) (s : σ)
    (h1 : (m s).2 = s) (h2 : ∀ a, (k a s).2 = s) : ((StateT.bind m k) s).2 = s := by
  show (k (m s).1 (m s).2).2 = s
  rw [h1]; exact h2 _

private theorem bind_eq {σ α β : Type} (m : StateT σ Id α) (k : α → StateT σ Id β) (s : σ)
    (a : α) (s' : σ) (h : m s = (a, s')) : StateT.bind m k s = k a s' := by
  show k (m s).1 (m s).2 = _
  rw [h]

/-- A loop whose steps all do nothing does nothing. -/
private theorem forIn_skip {α β σ : Type} (l : List α) (f : α → β → StateT σ Id (ForInStep β))
    (s : σ) (init : β) (h : ∀ x ∈ l, f x init s = (ForInStep.yield init, s)) :
    (forIn l init f) s = (init, s) := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    rw [List.forIn_cons]
    show (match f x init s with
      | (r, s') => (match r with
        | .done b => pure b
        | .yield b => forIn xs b f : StateT σ Id β) s') = _
    rw [h x List.mem_cons_self]
    exact ih (fun y hy => h y (List.mem_cons_of_mem _ hy))

/-! ### Events (`event.py`) -/

/-- An event that matches no event trigger (wrong type, or `event_data`
the event's data does not match, `eventDataMatches`) changes nothing and sends
nothing, whatever else is listening. -/
theorem onEvent_no_match (ty : String) (data : Json) (e : Engine) (acc : List Cmd)
    (h : ∀ p ∈ e.owners, ∀ t ∈ p.2, ∀ types want, t.kind = .event types want →
        (types.contains ty && eventDataMatches want data) = false) :
    (onEvent ty data).run (e, acc) = ((), (e, acc)) := by
  unfold onEvent
  simp only [StateT.run, getE, bind, StateT.bind, get, getThe, MonadStateOf.get, StateT.get, pure,
    StateT.pure]
  split
  rename_i a s heq
  have hs := congrArg Prod.snd heq
  simp only at hs
  rw [← hs]
  congr 1
  apply forIn_state_inv
  intro p hp b
  apply bind_state_inv
  · apply forIn_state_inv
    intro t ht b'
    apply bind_state_inv
    · rfl
    · intro d
      split
      · rfl
      · cases hk : t.kind
        case event types want =>
          have := h p hp t ht types want hk
          simp only [this, Bool.false_eq_true, ite_false]
          rfl
        all_goals rfl
  · intro _; rfl

/-- In particular: an event type no trigger names. -/
theorem onEvent_unknown_type (ty : String) (data : Json) (e : Engine) (acc : List Cmd)
    (h : ∀ p ∈ e.owners, ∀ t ∈ p.2, ∀ types want, t.kind = .event types want → ty ∉ types) :
    (onEvent ty data).run (e, acc) = ((), (e, acc)) := by
  apply onEvent_no_match
  intro p hp t ht types want hk
  have := h p hp t ht types want hk
  simp [this]

/-! ### Attaching triggers (`async_attach_trigger`) -/

/-- Triggers that need no state when attached: state, event, time pattern
and zone triggers. (numeric_state arms entities, time and sun schedule
timers, template renders once.) -/
def Stateless (t : Trigger) : Prop :=
  (∃ a b c d e f g, t.kind = .state a b c d e f g) ∨ (∃ a b, t.kind = .event a b) ∨
  (∃ a b c, t.kind = .timePattern a b c) ∨ (∃ a b c, t.kind = .zone a b c)

/-- Attaching them changes nothing and logs nothing. -/
theorem attachTriggers_stateless (o : Owner) (trigs : List Trigger) (e : Engine) (acc : List Cmd)
    (h : ∀ t ∈ trigs, Stateless t) :
    (attachTriggers o trigs).run (e, acc) = ((), (e, acc)) := by
  unfold attachTriggers
  simp only [StateT.run, getE, setE, emit, bind, StateT.bind, get, getThe, MonadStateOf.get,
    StateT.get, pure, StateT.pure, modify, modifyGet, MonadStateOf.modifyGet, StateT.modifyGet]
  rw [forIn_skip]
  · simp
  · intro t ht
    rcases h t ht with ⟨a, b, c, d, e, f, g, hk⟩ | ⟨a, b, hk⟩ | ⟨a, b, c, hk⟩ | ⟨a, b, c, hk⟩ <;>
      simp only [hk] <;> rfl

/-- `init` with automations that only have such triggers: the engine is
the plain initial one (automations, states, clock, location; no timers,
no armed entities, no trackers, no runs), and nothing is sent. -/
theorem step_init_stateless (e : Engine) (autos : List Automation) (sts : List EntityState)
    (now : Instant) (loc : Option Sun.Observer)
    (h : ∀ a ∈ autos, ∀ t ∈ a.triggers, Stateless t) :
    Engine.step e (.init autos sts now loc) =
      ({ automations := autos, states := sts.map (fun s => (s.entityId, s)), now := now,
         lastSec := now.utc / 1000, location := loc }, []) := by
  unfold Engine.step handle initArmed
  simp only [StateT.run, getE, setE, bind, StateT.bind, get, getThe, MonadStateOf.get,
    StateT.get, pure, StateT.pure, modify, modifyGet, MonadStateOf.modifyGet, StateT.modifyGet]
  rw [forIn_skip]
  intro p hp
  have hmem : p.1 ∈ autos := by
    rcases p with ⟨a, i⟩
    exact (List.mem_zipIdx hp).2.2 ▸ List.getElem_mem _
  have := attachTriggers_stateless (.auto p.2) p.1.triggers
    { automations := autos, states := sts.map (fun s => (s.entityId, s)), now := now,
      lastSec := now.utc / 1000, location := loc } [] (h p.1 hmem)
  exact bind_eq (attachTriggers (.auto p.2) p.1.triggers) _ _ _ _ this

/-! ### `wait_template` trackers -/

/-- With no run in a `wait_template`, a state change completes no wait and
the trackers are left alone. -/
theorem onWaitTrackers_none (eid : String) (old new : Option EntityState) (e : Engine)
    (acc : List Cmd) (h : ∀ st ∈ e.tmplTrigs, st.tmpl = none) :
    (onWaitTrackers eid old new).run (e, acc) = ([], (e, acc)) := by
  unfold onWaitTrackers
  simp only [StateT.run, getE, bind, StateT.bind, get, getThe, MonadStateOf.get,
    StateT.get, pure, StateT.pure]
  rw [forIn_skip]
  · intro st hst
    simp [h st hst]
    rfl

end HALean.Automation
