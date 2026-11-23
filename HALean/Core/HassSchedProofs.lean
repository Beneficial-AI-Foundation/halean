/-
  Properties of the joined core's event loop (`HALean/Core/Hass.lean`).

  * `keeps`: nothing the synchronous part of the core does (firing,
    dispatching, running a listener or a script, calling a service) reorders
    the loop's ready queue: it only appends to it, and the main task's
    frames are untouched.
  * `runHandle_fifo`, `runLoop_fifo`: **FIFO.** Running a handle of the ready
    queue (a task's step, a done callback, `_on_completion`) leaves the
    handles queued before it in front of everything it queues, so a handle
    queued earlier (e.g. a task resumed by `asyncio.sleep(0)` or by a
    resolved future) runs before every handle queued later, as
    `BaseEventLoop._run_once` runs `loop._ready`.
  * `blockTillDone_no_tasks`: when `hass.async_block_till_done()` returns, no
    task is left in `hass._tasks` (the ones it waited for are done and
    removed).
-/
import HALean.Core.HassProofs

namespace HALean.Core.Hass
open HALean.Core HALean.Core.EventBus

/-! ## The ready queue only grows at its end -/

structure Keeps (h h' : Hass) : Prop where
  ready : h.ready <+: h'.ready
  main : h'.mainCont = h.mainCont

theorem Keeps.refl (h : Hass) : Keeps h h := ⟨List.prefix_refl _, rfl⟩

theorem Keeps.trans {a b c : Hass} (k1 : Keeps a b) (k2 : Keeps b c) : Keeps a c :=
  ⟨k1.ready.trans k2.ready, k2.main.trans k1.main⟩

/-- `c` has `b`'s ready queue and main frames (another field changed). -/
theorem Keeps.congr {a b c : Hass} (k : Keeps a b) (hr : c.ready = b.ready)
    (hm : c.mainCont = b.mainCont) : Keeps a c :=
  ⟨hr ▸ k.ready, hm.trans k.main⟩

/-- `b` has `a`'s ready queue and main frames. -/
theorem Keeps.mid {a b c : Hass} (k : Keeps b c) (hr : b.ready = a.ready)
    (hm : b.mainCont = a.mainCont) : Keeps a c :=
  ⟨hr ▸ k.ready, k.main.trans hm⟩

theorem Keeps.same {a c : Hass} (hr : c.ready = a.ready) (hm : c.mainCont = a.mainCont) :
    Keeps a c := (Keeps.refl a).congr hr hm

theorem Keeps.enqueue (h : Hass) (x : Handle) : Keeps h (h.enqueue x) :=
  ⟨List.prefix_append _ _, rfl⟩

theorem Keeps.park (h : Hass) (t : Nat) (w : Wait) : Keeps h (h.park t w) := by
  unfold Hass.park
  cases w with
  | soon => exact Keeps.enqueue h _
  | fut f =>
    dsimp only
    split
    · exact Keeps.same rfl rfl
    · exact Keeps.enqueue h _
  | round => exact Keeps.refl h

theorem Keeps.spawn (h : Hass) (r : Res) : Keeps h (h.spawn r).1 := by
  cases r with
  | ok => exact Keeps.refl h
  | err => exact Keeps.refl h
  | susp w k => simp only [Hass.spawn]; exact (Keeps.park _ _ _).mid rfl rfl

theorem Keeps.foldl_enqueue (ws : List Nat) (h : Hass) :
    Keeps h (ws.foldl (fun h t => h.enqueue (.step t)) h) := by
  induction ws generalizing h with
  | nil => exact Keeps.refl h
  | cons w ws ih => exact (Keeps.enqueue h _).trans (ih _)

theorem Keeps.resolve {h h' : Hass} {f : String} (hr : h.resolve f = some h') : Keeps h h' := by
  unfold Hass.resolve at hr
  split at hr
  · cases hr
  · cases hr; exact (Keeps.foldl_enqueue _ _).mid rfl rfl

theorem Keeps.ctxOr (h : Hass) (c : Option Context) (now : Nat) : Keeps h (h.ctxOr c now).1 := by
  cases c <;> exact Keeps.same rfl rfl

theorem Keeps.removeListener (h : Hass) (et : String) (k : Nat) :
    Keeps h (removeListener h et k).1 := Keeps.same rfl rfl

theorem Keeps.useOnce (h : Hass) (job : Job) : Keeps h (useOnce h job).1 := Keeps.same rfl rfl

theorem Keeps.recordDelivery (h : Hass) (job : Job) (ev : Event) :
    Keeps h (recordDelivery h job ev).1 := Keeps.same rfl rfl

/-- **The synchronous core never reorders the ready queue**: firing,
dispatching, running listeners, scripts and service calls (which start eager
tasks, park suspended ones and resolve futures) only append to it, and leave
the main task's frames alone. -/
theorem keeps (n : Nat) :
    (∀ now h q, Keeps h (fireInternal n now h q).1) ∧
    (∀ now h qs, Keeps h (fireList n now h qs).1) ∧
    (∀ now q h ev js, Keeps h (dispatchLoop n now q h ev js).1) ∧
    (∀ now h, Keeps h (drain n now h).1) ∧
    (∀ now h job ev, Keeps h (runListener n now h job ev).1) ∧
    (∀ now h job ev, Keeps h (runJob n now h job ev).1) ∧
    (∀ env h as, Keeps h (runActions n env h as).1) ∧
    (∀ env h a, Keeps h (runAction n env h a).1) ∧
    (∀ env h a, Keeps h (callService n env h a).1) := by
  induction n with
  | zero =>
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      simp only [fireInternal, fireList, dispatchLoop, drain, runListener, runJob, runActions,
        runAction, callService] <;> exact Keeps.refl _
  | succ n ih =>
    obtain ⟨ihF, ihL, ihD, ihDr, ihRL, ihJ, ihAs, ihA, ihC⟩ := ih
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro now h q
      simp only [fireInternal]
      split
      · split <;> exact Keeps.same rfl rfl
      · have k := ((ihD now q { h with bus := { h.bus with dispatching := true, queuedCount := 0 } }
          none (snapshot h.bus.listeners q.eventType)).mid (a := h) rfl rfl).trans (ihDr now _)
        exact k.congr rfl rfl
    · intro now h qs
      cases qs with
      | nil => simp only [fireList]; exact Keeps.refl h
      | cons q qs =>
        simp only [fireList]
        split
        · exact ihF _ _ _
        · exact (ihF _ _ _).trans (ihL _ _ _)
    · intro now q h ev js
      cases js with
      | nil => simp only [dispatchLoop]; exact Keeps.refl h
      | cons j js =>
        simp only [dispatchLoop]
        split
        · exact ihD _ _ _ _ _
        · exact ihD _ _ _ _ _
        · refine Keeps.trans ?_ (ihD _ _ _ _ _)
          exact (ihJ _ _ _ _).mid rfl rfl
    · intro now h
      simp only [drain]
      split
      · exact Keeps.refl h
      · refine Keeps.trans ?_ (ihDr _ _)
        exact (ihD _ _ _ _ _).mid rfl rfl
    · intro now h job ev
      simp only [runListener]
      split
      · split
        · refine Keeps.trans ?_ (Keeps.spawn _ _)
          exact (Keeps.recordDelivery _ _ _).trans (ihAs _ _ _)
        · exact (Keeps.recordDelivery _ _ _).trans (ihAs _ _ _)
      · exact Keeps.recordDelivery h job ev
    · intro now h job ev
      simp only [runJob]
      split
      · exact Keeps.refl h
      · split
        · split
          · exact Keeps.refl h
          · exact (Keeps.useOnce _ _).trans (ihRL _ _ _ _)
        · exact ihRL _ _ _ _
    · intro env h as
      cases as with
      | nil => simp only [runActions]; exact Keeps.refl h
      | cons a as =>
        simp only [runActions]
        split
        · exact ihA _ _ _
        · exact ihA _ _ _
        · exact (ihA _ _ _).trans (ihAs _ _ _)
    · intro env h a
      cases a with
      | fire f => simp only [runAction]; exact ihF _ _ _
      | listen id et once filter react rt isAsync =>
        simp only [runAction]
        split
        · exact Keeps.same rfl rfl
        · exact Keeps.refl h
      | unsub id =>
        simp only [runAction]
        split
        · exact Keeps.refl h
        · exact Keeps.removeListener _ _ _
      | raise => simp only [runAction]; exact Keeps.refl h
      | set eid st attrs force c =>
        simp only [runAction]
        split
        · split <;> exact Keeps.ctxOr _ _ _
        · refine (Keeps.ctxOr h (resolveCtx env c) env.now).trans ?_
          exact (ihL _ _ _).mid rfl rfl
      | remove eid c =>
        simp only [runAction]
        split
        · split <;> exact Keeps.refl h
        · exact (ihL _ _ _).mid rfl rfl
      | call id args c caught =>
        simp only [runAction]
        split
        · exact ihC _ _ _
        · exact ihC _ _ _
        · split
          · exact (ihC _ _ _).trans (Keeps.spawn _ _)
          · exact ihC _ _ _
      | register d s body result schema sr =>
        simp only [runAction]
        split
        · exact Keeps.same rfl rfl
        · exact (ihL _ _ _).mid rfl rfl
      | removeService d s =>
        simp only [runAction]
        split
        · exact Keeps.same rfl rfl
        · exact (ihL _ _ _).mid rfl rfl
      | sleep => simp only [runAction]; exact Keeps.refl h
      | wait f =>
        simp only [runAction]
        split <;> exact Keeps.refl h
      | resolve f =>
        simp only [runAction]
        split
        · rename_i h' hr
          exact Keeps.resolve hr
        · exact Keeps.refl h
    · intro env h a
      simp only [callService]
      split
      · exact Keeps.refl h
      · have k0 := Keeps.ctxOr h a.context env.now
        split
        · exact k0
        · split
          · exact k0
          · rename_i q _
            have k1 := k0.trans (ihF env.now _ q)
            split
            · exact k1
            · have k2 := fun env' as => k1.trans (ihAs env' _ as)
              split
              · split
                · exact k2 _ _
                · exact (k2 _ _).trans (Keeps.spawn _ _)
              · exact k2 _ _
              · exact k2 _ _

/-! ## Resuming, and running handles -/

theorem Keeps.endRound {h h' : Hass} {logs : Out} (he : endRound h = some (h', logs)) :
    Keeps h h' := by
  unfold HALean.Core.Hass.endRound at he
  dsimp only at he
  split at he
  · cases he
  · cases he; exact Keeps.same rfl rfl

theorem Keeps.startRound (h : Hass) : Keeps h (startRound h) := by
  unfold HALean.Core.Hass.startRound
  dsimp only
  generalize (List.filter (fun x => x.finished) (List.filter (fun x => x.inSet) h.tasks)) = l
  suffices ∀ (l : List TaskRec) (g : Hass), Keeps h g →
      Keeps h (l.foldl (fun h t => h.enqueue (.onc t.id)) g) from this l _ (Keeps.same rfl rfl)
  intro l
  induction l with
  | nil => intro g k; exact k
  | cons t l ih => intro g k; exact ih _ (k.trans (Keeps.enqueue _ _))

/-- Resuming a coroutine's frames never reorders the ready queue. -/
theorem keeps_resume (n now : Nat) :
    ∀ (k : List Frame) (h : Hass) (r : Except PyError HALean.Template.Value),
      Keeps h (resume n now h k r).1 := by
  intro k
  induction k with
  | nil => intro h r; exact Keeps.refl h
  | cons f k ih =>
    intro h r
    cases f with
    | script env rest =>
      simp only [resume]
      split
      · exact ih _ _
      · have k1 := (keeps n).2.2.2.2.2.2.1 { env with now } h rest
        split
        · exact k1
        · exact k1.trans (ih _ _)
        · exact k1.trans (ih _ _)
    | handlerRet a p => exact ih _ _
    | callAct id sw => exact ih _ _
    | btdCheck =>
      simp only [resume]
      split
      · exact Keeps.refl h
      · rename_i h1 logs he
        split
        · exact (Keeps.endRound he).trans (Keeps.startRound _)
        · exact (Keeps.endRound he).trans (ih _ _)

theorem Keeps.updTask (h : Hass) (t : Nat) (g : TaskRec → TaskRec) : Keeps h (h.updTask t g) :=
  Keeps.same rfl rfl

theorem Keeps.finishTask (h : Hass) (t : TaskRec) (e : Option PyError) :
    Keeps h (finishTask h t e) := by
  unfold HALean.Core.Hass.finishTask
  dsimp only
  split
  · exact ((Keeps.updTask _ _ _).trans (Keeps.enqueue _ _)).trans (Keeps.enqueue _ _)
  · exact (Keeps.updTask _ _ _).trans (Keeps.enqueue _ _)

/-- Running one handle (not the main task's step) keeps the main task's
frames and only appends to the ready queue. -/
theorem keeps_runHandle (n now : Nat) (h : Hass) (x : Handle) : Keeps h (runHandle n now h x).1 := by
  cases x with
  | step t =>
    simp only [runHandle]
    split
    · exact Keeps.refl h
    · rename_i task _
      have k1 := keeps_resume n now task.cont h (.ok .none)
      split
      · exact (k1.trans (Keeps.updTask _ _ _)).trans (Keeps.park _ _ _)
      · exact k1.trans (Keeps.finishTask _ _ _)
      · exact k1.trans (Keeps.finishTask _ _ _)
  | done t =>
    simp only [runHandle]
    split
    · exact Keeps.refl h
    · split
      · exact Keeps.updTask _ _ _
      · exact Keeps.same rfl rfl
  | onc t =>
    simp only [runHandle]
    split
    · exact (Keeps.enqueue _ _).mid rfl rfl
    · exact Keeps.same rfl rfl

/-- **FIFO.** When the loop pops the head `x` of the ready queue (leaving
`rest`) and runs it, the handles that were behind it stay in front of
everything running `x` queues: a handle queued earlier runs before every
handle queued later. -/
theorem runHandle_fifo (n now : Nat) (h : Hass) (x : Handle) (rest : List Handle) :
    ∃ added, (runHandle n now { h with ready := rest } x).1.ready = rest ++ added := by
  have k := keeps_runHandle n now { h with ready := rest } x
  obtain ⟨added, ha⟩ := k.ready
  exact ⟨added, ha.symm⟩

/-- **FIFO**, for the main task's step too: whatever the loop's next round
is, the handles behind the head keep their order at the front of the queue
(`runLoop` resumes the main task with its own frames, which run synchronous
code only, and parks it again only by appending). -/
theorem resume_main_fifo (n now : Nat) (h : Hass) (rest : List Handle) :
    rest <+: (resume n now { h with ready := rest, mainCont := [] } h.mainCont (.ok .none)).1.ready :=
  (keeps_resume n now h.mainCont { h with ready := rest, mainCont := [] } (.ok .none)).ready

/-! ## `block_till_done` -/

theorem keeps_parkMain_main (h : Hass) (w : Wait) (k : List Frame) : (parkMain h w k).mainCont = k :=
  (Keeps.park ({ h with mainCont := k } : Hass) 0 w).main

/-- The loop, while the main task is in `async_block_till_done`'s check
(`mainCont = [btdCheck]`), returns normally only when no task is left in
`hass._tasks`. -/
theorem runLoop_btd (now : Nat) :
    ∀ (fuel : Nat) (h : Hass) (acc : Out) (h' : Hass) (out : Out) (v : HALean.Template.Value),
      h.mainCont = [.btdCheck] →
      runLoop fuel now h acc = (h', out, .ok v) →
      ∀ t ∈ h'.tasks, t.inSet = false := by
  intro fuel
  induction fuel with
  | zero => intro h acc h' out v _ hl; simp [runLoop] at hl
  | succ fuel ih =>
    intro h acc h' out v hm hl
    cases hr : h.ready with
    | nil => simp [runLoop, hr] at hl
    | cons x rest =>
      have hm' : ∀ x, (runHandle FUEL now { h with ready := rest } x).1.mainCont = [.btdCheck] :=
        fun x => (keeps_runHandle _ _ _ x).main.trans hm
      cases x with
      | step t =>
        cases t with
        | zero =>
          simp only [runLoop, hr, hm] at hl
          simp only [resume] at hl
          generalize hg : ({ h with ready := rest, mainCont := [] } : Hass) = g at hl
          cases he : endRound g with
          | none => simp [he] at hl
          | some p =>
            obtain ⟨h1, logs⟩ := p
            simp only [he] at hl
            by_cases hany : h1.tasks.any (·.inSet) = true
            · simp only [hany, ↓reduceIte] at hl
              exact ih _ _ h' out v (keeps_parkMain_main _ _ _) hl
            · simp only [hany, Bool.false_eq_true, ↓reduceIte, Res.ofExcept] at hl
              simp only [Prod.mk.injEq] at hl
              obtain ⟨rfl, -, -⟩ := hl
              intro t ht
              simp only [List.any_eq_true, not_exists, not_and, Bool.not_eq_true] at hany
              exact hany t ht
        | succ t =>
          simp only [runLoop, hr] at hl
          exact ih _ _ h' out v (hm' _) hl
      | done t =>
        simp only [runLoop, hr] at hl
        exact ih _ _ h' out v (hm' _) hl
      | onc t =>
        simp only [runLoop, hr] at hl
        exact ih _ _ h' out v (hm' _) hl

/-- **`async_block_till_done` leaves no task behind.** When the operation
returns normally, every task the loop started is done and its done callback
has removed it from `hass._tasks`. -/
theorem blockTillDone_no_tasks (now : Nat) (h h' : Hass) (out : Out) (r : Result)
    (hs : step now h .blockTillDone = (h', out, .ok r)) :
    ∀ t ∈ h'.tasks, t.inSet = false := by
  simp only [step, drive] at hs
  generalize hl : runLoop LOOP_FUEL now (parkMain h .soon [.btdCheck]) [].reverse = res at hs
  obtain ⟨h2, o2, e2⟩ := res
  cases e2 with
  | error => simp [Except.map] at hs
  | ok v =>
    simp only [Except.map, Prod.mk.injEq] at hs
    obtain ⟨rfl, -, -⟩ := hs
    exact runLoop_btd now _ _ _ _ _ _ (keeps_parkMain_main _ _ _) hl

end HALean.Core.Hass
