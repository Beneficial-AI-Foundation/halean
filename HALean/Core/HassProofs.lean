/-
  Properties of the joined core (`HALean/Core/Hass.lean`).

  * `quiet`: while the bus is dispatching, nothing a script does delivers an
    event: firing, setting or removing a state, calling a service (whose
    handler may do all of these again, nested), registering or removing a
    service, listening or unsubscribing. Every event any of these fire is
    queued; the bus stays in its dispatch, and no `_OneTimeListener` is used
    up.
  * `dispatchLoop_deliveries`: a dispatch delivers the one `Event` to exactly
    the listeners of the snapshot that pass their filter (each once, in
    snapshot order, a `listen_once` listener only if it has not run yet),
    whatever those listeners do.
  * `fireInternal_first`, `set_delivers_first`: when nothing is dispatching,
    firing an event (in particular the `state_changed` / `state_reported`
    of a successful `async_set`) first delivers it to exactly those
    listeners, and only then anything else: events the listeners' scripts
    fired, the `call_service` and state changes of the services they called,
    and so on.

  "Not rejected" (no `Entry.unsupported` in the output) is the only
  hypothesis about fuel and call depth.
-/
import HALean.Core.Hass

namespace HALean.Core.Hass
open HALean.Core HALean.Core.EventBus

/-! ## Outputs without deliveries -/

def NoDeliv (out : Out) : Prop := ∀ e ∈ out, e.isDelivery = false

theorem NoDeliv.nil : NoDeliv [] := fun _ h => by cases h

theorem NoDeliv.append {a b : Out} (ha : NoDeliv a) (hb : NoDeliv b) : NoDeliv (a ++ b) := by
  intro e he
  rcases List.mem_append.mp he with he | he
  · exact ha e he
  · exact hb e he

theorem NoDeliv.single_unsup (w : String) : NoDeliv [.unsupported w] := by
  intro e he; simp at he; subst he; rfl

theorem NoDeliv.single_call (id : String) (r : Except PyError HALean.Template.Value) :
    NoDeliv [.callResult id r] := by
  intro e he; simp at he; subst he; rfl

theorem NoDeliv.logs (ls : List LogRecord) : NoDeliv (ls.map .log) := by
  intro e he
  rcases List.mem_map.mp he with ⟨_, _, rfl⟩; rfl

/-- What a script does while the bus is dispatching: the bus stays in the
dispatch, no once-listener is used up, nothing is delivered. -/
structure Quiet (h h' : Hass) (out : Out) : Prop where
  disp : h'.bus.dispatching = true
  once : h'.bus.onceRemoved = h.bus.onceRemoved
  nod : NoDeliv out

theorem Quiet.trans {a b c : Hass} {o1 o2 : Out} (h1 : Quiet a b o1) (h2 : Quiet b c o2) :
    Quiet a c (o1 ++ o2) :=
  ⟨h2.disp, h2.once.trans h1.once, h1.nod.append h2.nod⟩

theorem Quiet.trans0 {a b c : Hass} {o : Out} (h1 : Quiet a b []) (h2 : Quiet b c o) :
    Quiet a c o :=
  ⟨h2.disp, h2.once.trans h1.once, h2.nod⟩

theorem Quiet.append_logs {a b : Hass} {o : Out} (h : Quiet a b o) (ls : List LogRecord) :
    Quiet a b (o ++ ls.map .log) :=
  ⟨h.disp, h.once, h.nod.append (NoDeliv.logs ls)⟩

theorem Quiet.congr_bus {a b c : Hass} {o : Out} (h : Quiet a b o) (hb : c.bus = b.bus) :
    Quiet a c o :=
  ⟨hb ▸ h.disp, hb ▸ h.once, h.nod⟩

theorem Quiet.start {a b c d : Hass} {o : Out} (q : Quiet a b []) (hb : c.bus = b.bus)
    (hq : Quiet c d o) : Quiet a d o :=
  ⟨hq.disp, by rw [hq.once, hb, q.once], hq.nod⟩

theorem Quiet.mk' {h h' : Hass} {out : Out} (hd : h'.bus.dispatching = true)
    (ho : h'.bus.onceRemoved = h.bus.onceRemoved) (hn : NoDeliv out) : Quiet h h' out :=
  ⟨hd, ho, hn⟩

/-! ## The bus helpers keep the dispatch state -/

theorem fireNested_keeps (b : Bus) (q : Queued) :
    (fireNested b q).1.dispatching = b.dispatching ∧
      (fireNested b q).1.onceRemoved = b.onceRemoved := by
  unfold fireNested; split <;> simp

theorem asyncRemoveListener_keeps (b : Bus) (et : String) (k : Nat) :
    (asyncRemoveListener b et k).dispatching = b.dispatching ∧
      (asyncRemoveListener b et k).onceRemoved = b.onceRemoved := by
  unfold asyncRemoveListener; dsimp only; split <;> simp

theorem removeListener_keeps (h : Hass) (et : String) (k : Nat) :
    (removeListener h et k).1.bus.dispatching = h.bus.dispatching ∧
      (removeListener h et k).1.bus.onceRemoved = h.bus.onceRemoved ∧
      NoDeliv (removeListener h et k).2 := by
  have := asyncRemoveListener_keeps { h.bus with logs := [] } et k
  refine ⟨by simpa [removeListener] using this.1, by simpa [removeListener] using this.2, ?_⟩
  intro e he
  simp only [removeListener, List.mem_map] at he
  obtain ⟨_, _, rfl⟩ := he; rfl

theorem listenOp_keeps {b b' : Bus} {id et once filter ri react rt}
    (h : listenOp b id et once filter ri react rt = .ok b') :
    b'.dispatching = b.dispatching ∧ b'.onceRemoved = b.onceRemoved := by
  unfold listenOp at h
  split at h
  · rename_i b2 hh heq
    cases h
    cases once <;> simp only [asyncListen, asyncListenOnce, Bool.false_eq_true, ↓reduceIte] at heq
    all_goals (split at heq <;> (try split at heq) <;> (try split at heq) <;>
      (try cases heq) <;> simp)
  · cases h

theorem genContext_keeps (h : Hass) (now : Nat) :
    (h.genContext now).1.bus.dispatching = h.bus.dispatching ∧
      (h.genContext now).1.bus.onceRemoved = h.bus.onceRemoved := by
  simp [Hass.genContext]

theorem ctxOr_quiet (h : Hass) (c : Option Context) (now : Nat) (hd : h.bus.dispatching = true) :
    Quiet h (h.ctxOr c now).1 [] := by
  cases c with
  | some => exact ⟨hd, rfl, NoDeliv.nil⟩
  | none =>
    have k := genContext_keeps h now
    exact ⟨k.1.trans hd, k.2, NoDeliv.nil⟩

/-! ## Nothing is delivered while dispatching -/

theorem quiet (n : Nat) :
    (∀ now h q, h.bus.dispatching = true →
      Quiet h (fireInternal n now h q).1 (fireInternal n now h q).2.1) ∧
    (∀ now h qs, h.bus.dispatching = true →
      Quiet h (fireList n now h qs).1 (fireList n now h qs).2.1) ∧
    (∀ env h as, h.bus.dispatching = true →
      Quiet h (runActions n env h as).1 (runActions n env h as).2.1) ∧
    (∀ env h a, h.bus.dispatching = true →
      Quiet h (runAction n env h a).1 (runAction n env h a).2.1) ∧
    (∀ env h a, h.bus.dispatching = true →
      Quiet h (callService n env h a).1 (callService n env h a).2.1) := by
  induction n with
  | zero =>
    refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | exact ⟨by assumption, rfl, NoDeliv.single_unsup _⟩
      | (simp only [fireInternal, fireList, runActions, runAction, callService]
         exact ⟨by assumption, rfl, NoDeliv.single_unsup _⟩)
  | succ n ih =>
    obtain ⟨ihF, ihL, ihAs, ihA, ihC⟩ := ih
    have hF : ∀ now h q, h.bus.dispatching = true →
        Quiet h (fireInternal (n + 1) now h q).1 (fireInternal (n + 1) now h q).2.1 := by
      intro now h q hd
      have k := fireNested_keeps h.bus q
      simp only [fireInternal, hd, ↓reduceIte]
      split
      all_goals (rename_i heq; rw [heq] at k; exact ⟨k.1.trans hd, k.2, NoDeliv.nil⟩)
    have hL : ∀ now h qs, h.bus.dispatching = true →
        Quiet h (fireList (n + 1) now h qs).1 (fireList (n + 1) now h qs).2.1 := by
      intro now h qs hd
      cases qs with
      | nil => simp only [fireList]; exact ⟨hd, rfl, NoDeliv.nil⟩
      | cons q qs =>
        have q1 := ihF now h q hd
        simp only [fireList]
        split
        · exact q1
        · exact q1.trans (ihL now _ qs q1.disp)
    have hAs : ∀ env h as, h.bus.dispatching = true →
        Quiet h (runActions (n + 1) env h as).1 (runActions (n + 1) env h as).2.1 := by
      intro env h as hd
      cases as with
      | nil => simp only [runActions]; exact ⟨hd, rfl, NoDeliv.nil⟩
      | cons a as =>
        have q1 := ihA env h a hd
        simp only [runActions]
        split
        · exact q1
        · exact q1.trans (ihAs env _ as q1.disp)
    have hC : ∀ env h a, h.bus.dispatching = true →
        Quiet h (callService (n + 1) env h a).1 (callService (n + 1) env h a).2.1 := by
      intro env h a hd
      simp only [callService]
      split
      · exact ⟨hd, rfl, NoDeliv.single_unsup _⟩
      · have q0 := ctxOr_quiet h a.context env.now hd
        split
        · exact q0
        · split
          · exact ⟨q0.disp, q0.once, NoDeliv.single_unsup _⟩
          · rename_i q _
            have q1 := ihF env.now _ q q0.disp
            split
            · exact q0.trans0 q1
            · dsimp only
              exact Quiet.append_logs ((q0.trans0 q1).trans (ihAs _ _ _ q1.disp)) _
    have hA : ∀ env h a, h.bus.dispatching = true →
        Quiet h (runAction (n + 1) env h a).1 (runAction (n + 1) env h a).2.1 := by
      intro env h a hd
      have q00 : Quiet h h [] := ⟨hd, rfl, NoDeliv.nil⟩
      cases a with
      | fire f => simp only [runAction]; exact ihF _ _ _ hd
      | listen id et once filter react rt =>
        simp only [runAction]
        split
        · rename_i b hb
          have k := listenOp_keeps hb
          exact ⟨k.1.trans hd, k.2, NoDeliv.nil⟩
        · exact q00
      | unsub id =>
        simp only [runAction]
        split
        · exact q00
        · rename_i et k _
          have k := removeListener_keeps h et k
          exact ⟨k.1.trans hd, k.2.1, k.2.2⟩
      | raise => simp only [runAction]; exact q00
      | set eid st attrs force c =>
        simp only [runAction]
        have q0 := ctxOr_quiet h (resolveCtx env c) env.now hd
        split
        · split
          · exact q0
          · exact ⟨q0.disp, q0.once, NoDeliv.single_unsup _⟩
        · dsimp only
          refine q0.start ?_ (ihL _ _ _ ?_)
          · rfl
          · exact q0.disp
      | remove eid c =>
        simp only [runAction]
        split
        · split
          · exact q00
          · exact ⟨hd, rfl, NoDeliv.single_unsup _⟩
        · dsimp only
          refine q00.start ?_ (ihL _ _ _ ?_)
          · rfl
          · exact hd
      | call id args c caught =>
        simp only [runAction]
        have q := ihC env h { args with context := resolveCtx env c } hd
        have q' := (⟨q.disp, q.once, q.nod.append (NoDeliv.single_call id _)⟩ :
          Quiet h _ ((callService n env h { args with context := resolveCtx env c }).2.1 ++
            [.callResult id (callService n env h { args with context := resolveCtx env c }).2.2]))
        split
        · split <;> exact q'
        · exact q'
      | register d s body result schema sr =>
        simp only [runAction]
        split
        · exact ⟨hd, rfl, NoDeliv.single_unsup _⟩
        · dsimp only
          refine q00.start ?_ (ihL _ _ _ ?_)
          · rfl
          · exact hd
      | removeService d s =>
        simp only [runAction]
        split
        · exact ⟨hd, rfl, NoDeliv.single_unsup _⟩
        · dsimp only
          refine (fun q => ⟨q.disp, q.once, (NoDeliv.logs _).append q.nod⟩ : Quiet h _ _ → _)
            (q00.start ?_ (ihL _ _ _ ?_))
          · rfl
          · exact hd
    exact ⟨hF, hL, hAs, hA, hC⟩

/-! ## What a dispatch delivers -/

/-- The deliveries in an output, in order: (job key, listener id, event). -/
def deliveries (out : Out) : List (Nat × String × Event) :=
  out.filterMap fun e => match e with
    | .delivery k l ev => some (k, l, ev)
    | _ => none

/-- The output has no `unsupported` entry: the operation is not rejected. -/
def NoUnsup (out : Out) : Prop := ∀ e ∈ out, e.isUnsupported = false

/-- The listeners of a snapshot that a dispatch delivers to: those whose
filter passes, except the opaque ones HA already had (`system`) and
`listen_once` listeners that already ran (`rm`, which grows as the dispatch
runs one). -/
def deliverable (data : Option Lean.Json) : List Nat → List Job → List Job
  | _, [] => []
  | rm, j :: js =>
    match filterPasses j data with
    | .ok true =>
      if j.system then deliverable data rm js
      else if j.once then
        if rm.contains j.key then deliverable data rm js
        else j :: deliverable data (j.key :: rm) js
      else j :: deliverable data rm js
    | _ => deliverable data rm js

theorem deliveries_append (a b : Out) : deliveries (a ++ b) = deliveries a ++ deliveries b := by
  simp [deliveries, List.filterMap_append]

theorem deliveries_nil_of_noDeliv {out : Out} (h : NoDeliv out) : deliveries out = [] := by
  induction out with
  | nil => rfl
  | cons e es ih =>
    have he := h e (List.mem_cons_self ..)
    have := ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
    cases e <;> simp_all [deliveries, Entry.isDelivery]

theorem NoUnsup.left {a b : Out} (h : NoUnsup (a ++ b)) : NoUnsup a :=
  fun e he => h e (List.mem_append_left _ he)

theorem NoUnsup.right {a b : Out} (h : NoUnsup (a ++ b)) : NoUnsup b :=
  fun e he => h e (List.mem_append_right _ he)

theorem NoUnsup.not_unsup {w : String} {o : Out} (h : NoUnsup (.unsupported w :: o)) : False := by
  have := h _ (List.mem_cons_self ..); simp [Entry.isUnsupported] at this

theorem ensureEvent_some (b : Bus) (q : Queued) (e : Event) : (ensureEvent b q (some e)).2 = e := rfl

theorem ensureEvent_keeps (b : Bus) (q : Queued) (ev? : Option Event) :
    (ensureEvent b q ev?).1.dispatching = b.dispatching ∧
      (ensureEvent b q ev?).1.onceRemoved = b.onceRemoved := by
  cases ev? with
  | some => simp [ensureEvent]
  | none => simp only [ensureEvent, makeEvent]; split <;> simp

theorem useOnce_keeps (h : Hass) (job : Job) :
    (useOnce h job).1.bus.dispatching = h.bus.dispatching ∧
    (useOnce h job).1.bus.onceRemoved = job.key :: h.bus.onceRemoved ∧
    NoDeliv (useOnce h job).2 := by
  have k := removeListener_keeps h job.eventType job.key
  exact ⟨by simpa [useOnce] using k.1, by simpa [useOnce] using k.2.1, by simpa [useOnce] using k.2.2⟩

theorem recordDelivery_keeps (h : Hass) (job : Job) (ev : Event) :
    (recordDelivery h job ev).1.bus.dispatching = h.bus.dispatching ∧
    (recordDelivery h job ev).1.bus.onceRemoved = h.bus.onceRemoved ∧
    (recordDelivery h job ev).2.1 = [.delivery job.key job.listener ev] := by
  simp [recordDelivery]

/-- A listener run during a dispatch delivers the event to itself (unless it
is opaque or a `listen_once` that already ran) and nothing else. -/
theorem runJob_deliveries (n now : Nat) (h : Hass) (job : Job) (ev : Event)
    (hd : h.bus.dispatching = true) (hu : NoUnsup (runJob n now h job ev).2.1) :
    (runJob n now h job ev).1.bus.dispatching = true ∧
    (runJob n now h job ev).1.bus.onceRemoved =
      (if !job.system && job.once && !h.bus.onceRemoved.contains job.key
       then job.key :: h.bus.onceRemoved else h.bus.onceRemoved) ∧
    deliveries (runJob n now h job ev).2.1 =
      (if !job.system && !(job.once && h.bus.onceRemoved.contains job.key)
       then [(job.key, job.listener, ev)] else []) := by
  cases n with
  | zero => exact (NoUnsup.not_unsup (by simpa [runJob] using hu)).elim
  | succ n =>
    have qA := (quiet n).2.2.1
    cases hs : job.system
    · cases ho : job.once
      · have rd := recordDelivery_keeps h job ev
        simp only [runJob, hs, ho, Bool.false_eq_true, ↓reduceIte] at hu ⊢
        by_cases hr : (recordDelivery h job ev).2.2 = true
        · simp only [hr, ↓reduceIte] at hu ⊢
          have q := qA { now := now, ctx := some ev.context, inListener := true } _
            ((recordDelivery h job ev).1.scriptOf job.key) (rd.1.trans hd)
          refine ⟨q.disp, q.once.trans rd.2.1, ?_⟩
          rw [deliveries_append, deliveries_nil_of_noDeliv q.nod, rd.2.2]; simp [deliveries]
        · simp only [hr, Bool.false_eq_true, ↓reduceIte] at hu ⊢
          exact ⟨rd.1.trans hd, rd.2.1, by rw [rd.2.2]; simp [deliveries]⟩
      · cases hc : h.bus.onceRemoved.contains job.key
        · have k := useOnce_keeps h job
          have rd := recordDelivery_keeps (useOnce h job).1 job ev
          simp only [runJob, hs, ho, hc, Bool.false_eq_true, ↓reduceIte] at hu ⊢
          by_cases hr : (recordDelivery (useOnce h job).1 job ev).2.2 = true
          · simp only [hr, ↓reduceIte] at hu ⊢
            have q := qA { now := now, ctx := some ev.context, inListener := true }
              (recordDelivery (useOnce h job).1 job ev).1
              ((recordDelivery (useOnce h job).1 job ev).1.scriptOf job.key) (rd.1.trans (k.1.trans hd))
            refine ⟨q.disp, ?_, ?_⟩
            · rw [q.once, rd.2.1, k.2.1]; simp
            · rw [deliveries_append, deliveries_append, deliveries_nil_of_noDeliv k.2.2,
                deliveries_nil_of_noDeliv q.nod, rd.2.2]; simp [deliveries]
          · simp only [hr, Bool.false_eq_true, ↓reduceIte] at hu ⊢
            refine ⟨rd.1.trans (k.1.trans hd), by rw [rd.2.1, k.2.1]; simp, ?_⟩
            rw [deliveries_append, deliveries_nil_of_noDeliv k.2.2, rd.2.2]; simp [deliveries]
        · have hc' : job.key ∈ h.bus.onceRemoved := by simpa using hc
          simp [runJob, hs, ho, hc, hc', hd, deliveries]
    · simp [runJob, hs, hd, deliveries]

/-- A dispatch delivers the event to exactly the `deliverable` listeners of
the snapshot, in order, whatever their scripts do (their own fires, state
writes and service calls are only queued: `quiet`). The event is the one
`ensureEvent` makes for the first listener that passes its filter. -/
theorem dispatchLoop_deliveries (now : Nat) (q : Queued) (js : List Job) :
    ∀ n h ev?, h.bus.dispatching = true →
      NoUnsup (dispatchLoop n now q h ev? js).2.1 →
      deliveries (dispatchLoop n now q h ev? js).2.1 =
        (deliverable q.data h.bus.onceRemoved js).map
          fun j => (j.key, j.listener, (ensureEvent h.bus q ev?).2) := by
  induction js with
  | nil =>
    intro n h ev? _ hu
    cases n with
    | zero => exact (NoUnsup.not_unsup (by simpa [dispatchLoop] using hu)).elim
    | succ n => simp [dispatchLoop, deliveries, deliverable]
  | cons j js ih =>
    intro n h ev? hd hu
    cases n with
    | zero => exact (NoUnsup.not_unsup (by simpa [dispatchLoop] using hu)).elim
    | succ n =>
      simp only [dispatchLoop] at hu ⊢
      cases hf : filterPasses j q.data with
      | error e =>
        simp only [hf] at hu ⊢
        have hu' : NoUnsup (dispatchLoop n now q h ev? js).2.1 :=
          fun x hx => hu x (List.mem_cons_of_mem _ hx)
        rw [show deliveries (filterLog e :: (dispatchLoop n now q h ev? js).2.1) =
            deliveries (dispatchLoop n now q h ev? js).2.1 by simp [deliveries, filterLog]]
        rw [ih n h ev? hd hu']
        simp [deliverable, hf]
      | ok b =>
        cases b with
        | false =>
          simp only [hf] at hu ⊢
          rw [ih n h ev? hd hu]
          simp [deliverable, hf]
        | true =>
          simp only [hf] at hu ⊢
          have ke := ensureEvent_keeps h.bus q ev?
          have hd1 : ({ h with bus := (ensureEvent h.bus q ev?).1 } : Hass).bus.dispatching = true := by
            simpa using ke.1.trans hd
          have hu1 := hu.left.left
          have hu2 := hu.right
          obtain ⟨jd, jo, jdel⟩ := runJob_deliveries n now _ j _ hd1 hu1
          rw [deliveries_append, deliveries_append, jdel, ih n _ _ jd hu2, jo]
          have hlog : deliveries (jobErrorLog (runJob n now { h with bus := (ensureEvent h.bus q ev?).1 }
              j (ensureEvent h.bus q ev?).2).2.2) = [] := by
            unfold jobErrorLog; split <;> simp [deliveries]
          rw [hlog]
          simp only [ensureEvent_some]
          have ke2 : ({ h with bus := (ensureEvent h.bus q ev?).1 } : Hass).bus.onceRemoved =
              h.bus.onceRemoved := ke.2
          rw [ke2]
          cases hs : j.system <;> cases ho : j.once <;>
            by_cases hc : j.key ∈ h.bus.onceRemoved <;>
            simp [deliverable, hf, hs, ho, hc]

theorem makeEvent_event (b : Bus) (q : Queued) :
    (makeEvent b q).2.eventType = q.eventType ∧
    (makeEvent b q).2.data = q.data.getD (Lean.Json.mkObj []) ∧
    (∀ c, q.context = some c → (makeEvent b q).2.context = c) := by
  unfold makeEvent; cases hq : q.context <;> simp

/-- **No preemption.** When nothing is dispatching, firing an event delivers
it first to exactly the `deliverable` listeners of the snapshot (each once,
in order); everything else the operation delivers (events those listeners
fired, the `call_service` and `state_changed` events of services they called,
and so on) comes after. -/
theorem fireInternal_first (n now : Nat) (h : Hass) (q : Queued)
    (hd : h.bus.dispatching = false) (hu : NoUnsup (fireInternal (n + 1) now h q).2.1) :
    ∃ E : Event,
      E.eventType = q.eventType ∧ E.data = q.data.getD (Lean.Json.mkObj []) ∧
      (∀ c, q.context = some c → E.context = c) ∧
      (deliverable q.data h.bus.onceRemoved (snapshot h.bus.listeners q.eventType)).map
          (fun j => (j.key, j.listener, E)) <+: deliveries (fireInternal (n + 1) now h q).2.1 := by
  simp only [fireInternal, hd, Bool.false_eq_true, ↓reduceIte] at hu ⊢
  have hdl := dispatchLoop_deliveries now q _ n
    { h with bus := { h.bus with dispatching := true, queuedCount := 0 } } none rfl hu.left
  obtain ⟨e1, e2, e3⟩ := makeEvent_event { h.bus with dispatching := true, queuedCount := 0 } q
  refine ⟨_, e1, e2, e3, ?_⟩
  rw [deliveries_append, hdl]
  exact List.prefix_append _ _

/-- The `async_fire_internal` of a successful `async_set` (given a context,
when nothing is dispatching): its `state_changed` (or `state_reported`)
reaches exactly the `deliverable` listeners of the snapshot taken when it is
fired, once each, before anything else is delivered: a listener that sets
another state, fires an event or calls a service only queues what follows. -/
theorem set_delivers_first (n : Nat) (env : Env) (h : Hass) (eid : String) (st : Lean.Json)
    (attrs : Option Lean.Json) (force : Bool) (c : CtxArg) (ctx : Context)
    (sm : StateMachine) (ev : SMEvent)
    (hd : h.bus.dispatching = false) (hc : resolveCtx env c = some ctx)
    (hs : h.states.asyncSet eid st attrs force (some ctx)
      (utcMicrosOfTimestamp (timestampOf env.now)) = .ok (sm, [ev]))
    (hu : NoUnsup (runAction (n + 3) env h (.set eid st attrs force c)).2.1) :
    ∃ E : Event,
      E.eventType = ev.eventType ∧ E.data = ev.dataJson ∧ E.context = ctx ∧
      (deliverable (some ev.dataJson) h.bus.onceRemoved
          (snapshot h.bus.listeners ev.eventType)).map (fun j => (j.key, j.listener, E)) <+:
        deliveries (runAction (n + 3) env h (.set eid st attrs force c)).2.1 := by
  simp only [runAction, hc, Hass.ctxOr, hs, List.map_cons, List.map_nil] at hu ⊢
  generalize hh : ({ h with states := sm } : Hass) = h' at hu ⊢
  have hb : h'.bus = h.bus := by rw [← hh]
  have hd' : h'.bus.dispatching = false := by rw [hb]; exact hd
  simp only [fireList] at hu ⊢
  split at hu
  · rename_i e he
    simp only [he] at hu ⊢
    obtain ⟨E, e1, e2, e3, e4⟩ := fireInternal_first n env.now h' _ hd' hu
    refine ⟨E, e1, by simpa [smQueued] using e2, e3 ctx rfl, ?_⟩
    rw [hb] at e4; simpa [smQueued] using e4
  · rename_i he
    simp only [he] at hu ⊢
    obtain ⟨E, e1, e2, e3, e4⟩ := fireInternal_first n env.now h' _ hd' hu.left
    refine ⟨E, e1, by simpa [smQueued] using e2, e3 ctx rfl, ?_⟩
    rw [deliveries_append]
    rw [hb] at e4
    exact (by simpa [smQueued] using e4 : _ <+: _).trans (List.prefix_append _ _)

end HALean.Core.Hass
