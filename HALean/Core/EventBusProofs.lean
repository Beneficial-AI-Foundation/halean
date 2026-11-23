/-
  Theorems about the event bus (`HALean/Core/EventBus.lean`).

  * `snapshot_match_all`, `snapshot_excluded`: which listeners a dispatch
    iterates over (specific ones first, then `MATCH_ALL` unless excluded).
  * `once_at_most_once`: over any sequence of operations, a listener added
    with `async_listen_once` receives at most one event.
  * `gone_silent`, `unsub_gone`: once a listener is out of the table (e.g.
    after its remove callback ran), it never receives anything again.
  * `reachable_wf`, `unsub_gone_reachable`, `unsub_silent`: every bus
    reachable from `Bus.new` is well formed (`WF`), so unsubscribing takes the
    listener out of the table with no side conditions, and it receives nothing
    over any later operations.
-/
import HALean.Core.EventBus

namespace HALean.Core.EventBus

/-! ### Which listeners a dispatch iterates over -/

/-- Every `MATCH_ALL` listener is in the snapshot of a dispatch of any event
type that is not excluded, after the listeners of that type. -/
theorem snapshot_match_all (t : Table) (et : String)
    (h : et ∉ EVENTS_EXCLUDED_FROM_MATCH_ALL) :
    snapshot t et = t.get et ++ t.get MATCH_ALL := by
  simp [snapshot, h]

/-- Excluded event types (`homeassistant_close`, `state_reported`) reach only
their own listeners. -/
theorem snapshot_excluded (t : Table) (et : String)
    (h : et ∈ EVENTS_EXCLUDED_FROM_MATCH_ALL) :
    snapshot t et = t.get et := by
  simp [snapshot, h]

/-! ### The listener table -/

/-- `x` is a listener entry somewhere in the table. -/
def InTable (x : Job) (t : Table) : Prop := ∃ p ∈ t, x ∈ p.2

theorem inTable_get {x : Job} {t : Table} {et : String} (h : x ∈ t.get et) : InTable x t := by
  induction t with
  | nil => simp [Table.get, List.lookup] at h
  | cons p t ih =>
    obtain ⟨k, l⟩ := p
    simp only [Table.get, List.lookup] at h
    split at h
    · exact ⟨(k, l), List.mem_cons_self .., by simpa using h⟩
    · obtain ⟨q, hq, hx⟩ := ih h
      exact ⟨q, List.mem_cons_of_mem _ hq, hx⟩

theorem inTable_touch {x : Job} {t : Table} {et : String} (h : InTable x (t.touch et)) :
    InTable x t := by
  obtain ⟨p, hp, hx⟩ := h
  unfold Table.touch at hp
  split at hp
  · exact ⟨p, hp, hx⟩
  · rcases List.mem_append.mp hp with hp | hp
    · exact ⟨p, hp, hx⟩
    · simp at hp; subst hp; simp at hx

theorem inTable_set {x : Job} {t : Table} {et : String} {l : List Job}
    (h : InTable x (t.set et l)) : x ∈ l ∨ InTable x t := by
  obtain ⟨p, hp, hx⟩ := h
  simp only [Table.set, List.mem_map] at hp
  obtain ⟨q, hq, rfl⟩ := hp
  split at hx
  · exact .inl hx
  · exact .inr ⟨q, hq, hx⟩

theorem inTable_pop {x : Job} {t : Table} {et : String} (h : InTable x (t.pop et)) :
    InTable x t := by
  obtain ⟨p, hp, hx⟩ := h
  exact ⟨p, (List.mem_filter.mp hp).1, hx⟩

theorem mem_removeFirst {k : Nat} {l l' : List Job} {x : Job}
    (h : removeFirst k l = some l') (hx : x ∈ l') : x ∈ l := by
  induction l generalizing l' with
  | nil => simp [removeFirst] at h
  | cons j js ih =>
    simp only [removeFirst] at h
    split at h
    · cases h; exact List.mem_cons_of_mem _ hx
    · cases hr : removeFirst k js with
      | none => simp [hr] at h
      | some r =>
        simp [hr] at h; subst h
        rcases List.mem_cons.mp hx with rfl | hx
        · exact List.mem_cons_self ..
        · exact List.mem_cons_of_mem _ (ih hr hx)

/-- After `b ↦ b'`, every listener in the table was there before or is new
(its key was not handed out yet), and keys keep counting up. -/
def Fresh (b b' : Bus) : Prop :=
  (∀ x, InTable x b'.listeners → InTable x b.listeners ∨ b.nextKey ≤ x.key) ∧
  b.nextKey ≤ b'.nextKey

theorem Fresh.refl (b : Bus) : Fresh b b := ⟨fun _ h => .inl h, Nat.le_refl _⟩

theorem Fresh.trans {a b c : Bus} (h1 : Fresh a b) (h2 : Fresh b c) : Fresh a c := by
  refine ⟨fun x hx => ?_, Nat.le_trans h1.2 h2.2⟩
  rcases h2.1 x hx with hb | hk
  · exact h1.1 x hb
  · exact .inr (Nat.le_trans h1.2 hk)

theorem Fresh.of_table {b b' : Bus} (ht : ∀ x, InTable x b'.listeners → InTable x b.listeners)
    (hk : b.nextKey ≤ b'.nextKey) : Fresh b b' := ⟨fun x h => .inl (ht x h), hk⟩

/-! ### What reactions change -/

/-- Same deliveries, same fired one-time listeners, and a table that only
lost entries or gained fresh ones. -/
def RStep (b b' : Bus) : Prop :=
  b'.deliveries = b.deliveries ∧ b'.onceRemoved = b.onceRemoved ∧ Fresh b b'

theorem RStep.refl (b : Bus) : RStep b b := ⟨rfl, rfl, Fresh.refl b⟩

theorem RStep.trans {a b c : Bus} (h1 : RStep a b) (h2 : RStep b c) : RStep a c :=
  ⟨h2.1.trans h1.1, h2.2.1.trans h1.2.1, h1.2.2.trans h2.2.2⟩

theorem asyncRemoveListener_rstep (b : Bus) (et : String) (k : Nat) :
    RStep b (asyncRemoveListener b et k) := by
  unfold asyncRemoveListener
  dsimp only
  split
  · exact ⟨rfl, rfl, Fresh.of_table (fun x h => inTable_touch h) (Nat.le_refl _)⟩
  · rename_i l hl
    refine ⟨rfl, rfl, Fresh.of_table (fun x h => ?_) (Nat.le_refl _)⟩
    have hs : InTable x (((b.listeners.touch et).set et l)) := by
      split at h
      · exact inTable_pop h
      · exact h
    rcases inTable_set hs with hx | hx
    · exact inTable_touch (inTable_get (mem_removeFirst hl hx))
    · exact inTable_touch hx

theorem listenFilterableJob_rstep (b : Bus) (j : Job) :
    RStep b (listenFilterableJob b j).1 := by
  refine ⟨rfl, rfl, fun x hx => ?_, Nat.le_succ _⟩
  simp only [listenFilterableJob] at hx
  rcases inTable_set hx with hx | hx
  · rcases List.mem_append.mp hx with hx | hx
    · exact .inl (inTable_touch (inTable_get hx))
    · simp at hx; subst hx; exact .inr (Nat.le_refl _)
  · exact .inl (inTable_touch hx)

theorem listen_ok {once : Bool} {b : Bus} {id et filter ri react rt r}
    (h : (if once then asyncListenOnce else asyncListen) b id et filter ri react rt = .ok r) :
    ∃ j, listenFilterableJob b j = r := by
  cases once <;> simp only [asyncListen, asyncListenOnce, Bool.false_eq_true, ↓reduceIte] at h
  all_goals
    repeat' split at h
    all_goals (cases h; try exact ⟨_, rfl⟩)

theorem listenOp_rstep {b b' : Bus} {id et once filter ri react rt}
    (h : listenOp b id et once filter ri react rt = .ok b') : RStep b b' := by
  unfold listenOp at h
  split at h
  · rename_i b1 h1 heq
    injection h with h; subst h
    obtain ⟨j, hj⟩ := listen_ok heq
    have := listenFilterableJob_rstep b j
    rw [hj] at this
    exact ⟨this.1, this.2.1, this.2.2.1, this.2.2.2⟩
  · cases h

theorem unsubOp_rstep {b b' : Bus} {id} (h : unsubOp b id = .ok b') : RStep b b' := by
  unfold unsubOp at h
  split at h
  · cases h
  · injection h with h; subst h; exact asyncRemoveListener_rstep ..

theorem fireNested_rstep (b : Bus) (q : Queued) : RStep b (fireNested b q).1 := by
  unfold fireNested
  split
  · exact RStep.refl b
  · exact ⟨rfl, rfl, Fresh.refl b⟩

theorem react1_rstep (now : Nat) (ev : Event) (b : Bus) (r : Reaction) :
    RStep b (react1 now ev b r).1 := by
  cases r with
  | fire f =>
    simp only [react1]
    split
    · exact RStep.refl b
    · exact fireNested_rstep ..
  | listen id et once filter ri react rt =>
    simp only [react1]
    split
    · rename_i b' h; exact listenOp_rstep h
    · exact RStep.refl b
  | unsub id =>
    simp only [react1]
    split
    · rename_i b' h; exact unsubOp_rstep h
    · exact RStep.refl b
  | raise e => exact RStep.refl b

theorem runReactions_rstep (now : Nat) (ev : Event) (b : Bus) (rs : List Reaction) :
    RStep b (runReactions now ev b rs).1 := by
  induction rs generalizing b with
  | nil => exact RStep.refl b
  | cons r rs ih =>
    simp only [runReactions]
    have h1 := react1_rstep now ev b r
    split
    · rename_i b' e heq; rw [heq] at h1; exact h1
    · rename_i b' heq; rw [heq] at h1; exact h1.trans (ih b')

theorem ensureEvent_rstep (b : Bus) (q : Queued) (ev? : Option Event) :
    RStep b (ensureEvent b q ev?).1 := by
  cases ev? with
  | some ev => exact RStep.refl b
  | none => simp only [ensureEvent, makeEvent]; split <;> exact ⟨rfl, rfl, Fresh.refl b⟩

theorem logJobError_rstep (b : Bus) (err : Option Err) : RStep b (logJobError b err) := by
  cases err with
  | some e => exact ⟨rfl, rfl, Fresh.refl b⟩
  | none => exact RStep.refl b

/-! ### One-time listeners run at most once -/

/-- Deliveries to the one-time listener job `k`. -/
def onceCount (k : Nat) (ds : List Delivery) : Nat :=
  (ds.filter fun d => d.once && d.job == k).length

/-- Every one-time listener has been delivered at most once, and if it has,
its `remove` is `None` (it is in `onceRemoved`). -/
def OnceInv (b : Bus) : Prop :=
  ∀ k, onceCount k b.deliveries = 0 ∨ (onceCount k b.deliveries = 1 ∧ k ∈ b.onceRemoved)

theorem OnceInv.of_rstep {b b' : Bus} (h : RStep b b') (hi : OnceInv b) : OnceInv b' := by
  intro k; rw [h.1, h.2.1]; exact hi k

theorem OnceInv.of_eq {b b' : Bus} (hd : b'.deliveries = b.deliveries)
    (ho : ∀ k, k ∈ b.onceRemoved → k ∈ b'.onceRemoved) (hi : OnceInv b) : OnceInv b' := by
  intro k; rw [hd]
  rcases hi k with h | ⟨h1, h2⟩
  · exact .inl h
  · exact .inr ⟨h1, ho k h2⟩

theorem callListener_onceInv (now : Nat) (b : Bus) (job : Job) (ev : Event) (hi : OnceInv b)
    (hnew : job.once = true → onceCount job.key b.deliveries = 0 ∧ job.key ∈ b.onceRemoved) :
    OnceInv (callListener now b job ev).1 := by
  unfold callListener
  dsimp only
  have base : OnceInv { b with
      deliveries := { job := job.key, once := job.once, listener := job.listener, event := ev } :: b.deliveries,
      received := (job.key, b.receivedOf job.key + 1) :: b.received } := by
    intro k
    simp only [onceCount, List.filter_cons]
    cases ho : job.once
    · exact hi k
    · by_cases hk : job.key = k
      · subst hk
        obtain ⟨h0, hm⟩ := hnew ho
        simp only [onceCount] at h0
        simp [h0, hm]
      · have : (job.key == k) = false := by simpa using hk
        simp only [this, Bool.true_and, Bool.false_eq_true, ↓reduceIte]
        exact hi k
  split
  · exact OnceInv.of_rstep (runReactions_rstep ..) base
  · exact base

theorem runJob_onceInv (now : Nat) (b : Bus) (job : Job) (ev : Event) (hi : OnceInv b) :
    OnceInv (runJob now b job ev).1 := by
  unfold runJob
  split
  · exact hi
  split
  · split
    · exact hi
    · rename_i hs ho hr
      have hr' := asyncRemoveListener_rstep b job.eventType job.key
      have hi' := OnceInv.of_rstep hr' hi
      apply callListener_onceInv
      · exact OnceInv.of_eq (b := asyncRemoveListener b job.eventType job.key) rfl
          (fun k h => by simp [h]) hi'
      · intro _
        refine ⟨?_, List.mem_cons_self ..⟩
        rcases hi job.key with h | ⟨_, h⟩
        · simp only [onceCount] at h ⊢; rw [hr'.1]; exact h
        · exact absurd (List.elem_iff.mpr h) (by simpa using hr)
  · rename_i hs ho
    exact callListener_onceInv now b job ev hi (fun h => by simp [h] at ho)

theorem dispatchLoop_onceInv (now : Nat) (q : Queued) (acc : Bus × Option Event) (js : List Job)
    (hi : OnceInv acc.1) : OnceInv (dispatchLoop now q acc js).1 := by
  induction js generalizing acc with
  | nil => exact hi
  | cons j js ih =>
    obtain ⟨b, ev?⟩ := acc
    simp only [dispatchLoop]
    split
    · exact ih _ hi
    · exact ih _ hi
    · have h0 := ensureEvent_rstep b q ev?
      generalize ensureEvent b q ev? = m at h0 ⊢
      obtain ⟨b0, ev⟩ := m
      dsimp only
      have h1 := runJob_onceInv now b0 j ev (OnceInv.of_rstep h0 hi)
      generalize runJob now b0 j ev = r at h1 ⊢
      obtain ⟨b1, err⟩ := r
      exact ih _ (OnceInv.of_rstep (logJobError_rstep b1 err) h1)

theorem dispatch_onceInv (now : Nat) (b : Bus) (q : Queued) (hi : OnceInv b) :
    OnceInv (dispatch now b q) := dispatchLoop_onceInv now q (b, none) _ hi

theorem drain_onceInv (now n : Nat) (b : Bus) (hi : OnceInv b) : OnceInv (drain now n b) := by
  induction n generalizing b with
  | zero => exact hi
  | succ n ih =>
    simp only [drain]
    split
    · exact hi
    · exact ih _ (dispatch_onceInv now _ _ hi)

theorem asyncFire_onceInv {now : Nat} {b b' : Bus} {f : FireArgs} {ctx : Option Context}
    (h : asyncFire now b f ctx = .ok b') (hi : OnceInv b) : OnceInv b' := by
  unfold asyncFire at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · generalize hq : fireNested b (mkQueued now f ctx) = r at h
      obtain ⟨b1, e⟩ := r
      cases e with
      | none =>
        injection h with h; subst h
        have := fireNested_rstep b (mkQueued now f ctx)
        rw [hq] at this
        exact OnceInv.of_rstep this hi
      | some e => cases h
    · injection h with h; subst h
      exact drain_onceInv now _ _ (dispatch_onceInv now _ _ hi)

theorem step_onceInv (now : Nat) (b : Bus) (op : Op) (hi : OnceInv b) :
    OnceInv (step now b op).1 := by
  cases op with
  | init counts => exact hi
  | listeners => exact hi
  | fire f =>
    simp only [step]
    split
    · rename_i b' h; exact asyncFire_onceInv h hi
    · exact hi
  | call r =>
    simp only [step]
    split
    · rename_i b' h
      cases r with
      | listen => exact OnceInv.of_rstep (listenOp_rstep h) hi
      | unsub => exact OnceInv.of_rstep (unsubOp_rstep h) hi
      | raise => cases h
      | fire => cases h; exact hi
    · exact hi

theorem run_onceInv (b : Bus) (ops : List (Nat × Op)) (hi : OnceInv b) : OnceInv (run b ops) := by
  induction ops generalizing b with
  | nil => exact hi
  | cons op ops ih => exact ih _ (step_onceInv _ _ _ hi)

/-- **A one-time listener is delivered at most once**: from a new bus, after
any sequence of operations (listens, unsubscribes, fires with arbitrary
listener reactions), every job key has at most one `async_listen_once`
delivery. -/
theorem once_at_most_once (ops : List (Nat × Op)) (k : Nat) :
    onceCount k (run Bus.new ops).deliveries ≤ 1 := by
  have h := run_onceInv Bus.new ops (fun k => .inl (by simp [onceCount, Bus.new]))
  rcases h k with h | ⟨h, _⟩ <;> omega

/-! ### A removed listener stays silent -/

/-- Deliveries to job `k` (any kind). -/
def jobCount (k : Nat) (ds : List Delivery) : Nat := (ds.filter fun d => d.job == k).length

/-- Job `k` is not in the table, and its key is never handed out again. -/
def Gone (k : Nat) (b : Bus) : Prop := (∀ x, InTable x b.listeners → x.key ≠ k) ∧ k < b.nextKey

/-- `b ↦ b'` keeps `k` gone and delivers nothing to it. -/
def Quiet (k : Nat) (b b' : Bus) : Prop :=
  Gone k b' ∧ jobCount k b'.deliveries = jobCount k b.deliveries

theorem Quiet.trans {k : Nat} {a b c : Bus} (h1 : Quiet k a b) (h2 : Quiet k b c) : Quiet k a c :=
  ⟨h2.1, h2.2.trans h1.2⟩

theorem Quiet.of_rstep {k : Nat} {b b' : Bus} (h : RStep b b') (hg : Gone k b) : Quiet k b b' := by
  refine ⟨⟨fun x hx => ?_, Nat.lt_of_lt_of_le hg.2 h.2.2.2⟩, by rw [h.1]⟩
  rcases h.2.2.1 x hx with hb | hk
  · exact hg.1 x hb
  · intro e; rw [e] at hk; exact absurd hg.2 (Nat.not_lt.mpr hk)

theorem callListener_quiet {k now : Nat} {b : Bus} {job : Job} {ev : Event}
    (hj : job.key ≠ k) (hg : Gone k b) : Quiet k b (callListener now b job ev).1 := by
  unfold callListener
  dsimp only
  have base : Quiet k b { b with
      deliveries := { job := job.key, once := job.once, listener := job.listener, event := ev } :: b.deliveries,
      received := (job.key, b.receivedOf job.key + 1) :: b.received } := by
    refine ⟨hg, ?_⟩
    have : (job.key == k) = false := by simpa using hj
    simp [jobCount, this]
  split
  · exact base.trans (Quiet.of_rstep (runReactions_rstep ..) base.1)
  · exact base

theorem runJob_quiet {k now : Nat} {b : Bus} {job : Job} {ev : Event}
    (hj : job.key ≠ k) (hg : Gone k b) : Quiet k b (runJob now b job ev).1 := by
  unfold runJob
  split
  · exact ⟨hg, rfl⟩
  split
  · split
    · exact ⟨hg, rfl⟩
    · have h1 := Quiet.of_rstep (asyncRemoveListener_rstep b job.eventType job.key) hg
      exact h1.trans (callListener_quiet (b := { asyncRemoveListener b job.eventType job.key with
        onceRemoved := job.key :: (asyncRemoveListener b job.eventType job.key).onceRemoved }) hj h1.1)
  · exact callListener_quiet hj hg

theorem dispatchLoop_quiet {k now : Nat} {q : Queued} (acc : Bus × Option Event) (js : List Job)
    (hjs : ∀ j ∈ js, j.key ≠ k) (hg : Gone k acc.1) : Quiet k acc.1 (dispatchLoop now q acc js).1 := by
  induction js generalizing acc with
  | nil => exact ⟨hg, rfl⟩
  | cons j js ih =>
    have hrest : ∀ j ∈ js, j.key ≠ k := fun j' h => hjs j' (List.mem_cons_of_mem _ h)
    have hj : j.key ≠ k := hjs j (List.mem_cons_self ..)
    obtain ⟨b, ev?⟩ := acc
    simp only [dispatchLoop]
    split
    · exact ih _ hrest hg
    · exact ih _ hrest hg
    · have h0 := Quiet.of_rstep (ensureEvent_rstep b q ev?) hg
      generalize ensureEvent b q ev? = m at h0 ⊢
      obtain ⟨b0, ev⟩ := m
      dsimp only
      have h1 := h0.trans (runJob_quiet (now := now) (ev := ev) hj h0.1)
      generalize runJob now b0 j ev = r at h1 ⊢
      obtain ⟨b1, err⟩ := r
      have h2 := h1.trans (Quiet.of_rstep (logJobError_rstep b1 err) h1.1)
      exact h2.trans (ih _ hrest h2.1)

theorem inTable_snapshot {x : Job} {t : Table} {et : String} (h : x ∈ snapshot t et) :
    InTable x t := by
  unfold snapshot at h
  rcases List.mem_append.mp h with h | h
  · exact inTable_get h
  · split at h
    · simp at h
    · exact inTable_get h

theorem dispatch_quiet {k now : Nat} {b : Bus} {q : Queued} (hg : Gone k b) :
    Quiet k b (dispatch now b q) :=
  dispatchLoop_quiet (b, none) _ (fun _ h => hg.1 _ (inTable_snapshot h)) hg

theorem drain_quiet {k now : Nat} (n : Nat) {b : Bus} (hg : Gone k b) : Quiet k b (drain now n b) := by
  induction n generalizing b with
  | zero => exact ⟨hg, rfl⟩
  | succ n ih =>
    simp only [drain]
    split
    · exact ⟨hg, rfl⟩
    · rename_i q qs _
      have h1 := dispatch_quiet (now := now) (q := q) (b := { b with queue := qs }) hg
      exact h1.trans (ih h1.1)

theorem asyncFire_quiet {k now : Nat} {b b' : Bus} {f : FireArgs} {ctx : Option Context}
    (h : asyncFire now b f ctx = .ok b') (hg : Gone k b) : Quiet k b b' := by
  unfold asyncFire at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · generalize hq : fireNested b (mkQueued now f ctx) = r at h
      obtain ⟨b1, e⟩ := r
      cases e with
      | none =>
        injection h with h; subst h
        have := fireNested_rstep b (mkQueued now f ctx)
        rw [hq] at this
        exact Quiet.of_rstep this hg
      | some e => cases h
    · injection h with h; subst h
      have h1 : Quiet k b (dispatch now { b with dispatching := true, queuedCount := 0 } (mkQueued now f ctx)) :=
        dispatch_quiet (b := { b with dispatching := true, queuedCount := 0 }) hg
      have h2 := h1.trans (drain_quiet (now := now) MAX_QUEUED_EVENT_DISPATCHES h1.1)
      exact h2

theorem initTable_fresh (next : Nat) (cs : List (String × Nat)) :
    (∀ x, InTable x (initTable next cs).1 → next ≤ x.key) ∧ next ≤ (initTable next cs).2 := by
  induction cs generalizing next with
  | nil => exact ⟨fun _ ⟨_, hp, _⟩ => by simp [initTable] at hp, Nat.le_refl _⟩
  | cons c cs ih =>
    obtain ⟨et, n⟩ := c
    have ih' := ih (next + n)
    simp only [initTable]
    refine ⟨fun x ⟨p, hp, hx⟩ => ?_, Nat.le_trans (Nat.le_add_right _ _) ih'.2⟩
    rcases List.mem_cons.mp hp with rfl | hp
    · simp only [List.mem_map, List.mem_range] at hx
      obtain ⟨i, _, rfl⟩ := hx
      exact Nat.le_add_right _ _
    · exact Nat.le_trans (Nat.le_add_right _ _) (ih'.1 x ⟨p, hp, hx⟩)

theorem step_quiet {k now : Nat} {b : Bus} (op : Op) (hg : Gone k b) : Quiet k b (step now b op).1 := by
  cases op with
  | init counts =>
    have hf := initTable_fresh b.nextKey counts
    refine ⟨⟨fun x hx => ?_, Nat.lt_of_lt_of_le hg.2 hf.2⟩, rfl⟩
    have := hf.1 x hx
    intro e; rw [e] at this; exact absurd hg.2 (Nat.not_lt.mpr this)
  | listeners => exact ⟨hg, rfl⟩
  | fire f =>
    simp only [step]
    split
    · rename_i b' h; exact asyncFire_quiet h hg
    · exact ⟨hg, rfl⟩
  | call r =>
    simp only [step]
    split
    · rename_i b' h
      cases r with
      | listen => exact Quiet.of_rstep (listenOp_rstep h) hg
      | unsub => exact Quiet.of_rstep (unsubOp_rstep h) hg
      | raise => cases h
      | fire => cases h; exact ⟨hg, rfl⟩
    · exact ⟨hg, rfl⟩

/-- **A listener that is out of the table never hears anything again**: after
any sequence of operations it has received exactly what it had before, and it
is still out of the table (new listeners get new keys). -/
theorem gone_silent (b : Bus) (ops : List (Nat × Op)) (k : Nat) (hg : Gone k b) :
    jobCount k (run b ops).deliveries = jobCount k b.deliveries ∧ Gone k (run b ops) := by
  induction ops generalizing b with
  | nil => exact ⟨rfl, hg⟩
  | cons op ops ih =>
    obtain ⟨now, op⟩ := op
    have h1 := step_quiet (now := now) op hg
    have h2 := ih _ h1.1
    exact ⟨h2.1.trans h1.2, h2.2⟩

/-! ### Unsubscribing takes the listener out of the table -/

theorem removeFirst_none {k : Nat} {l : List Job} (h : removeFirst k l = none) :
    ∀ x ∈ l, x.key ≠ k := by
  induction l with
  | nil => simp
  | cons j js ih =>
    simp only [removeFirst] at h
    split at h
    · cases h
    · rename_i hj
      cases hr : removeFirst k js with
      | none =>
        intro x hx
        rcases List.mem_cons.mp hx with rfl | hx
        · simpa using hj
        · exact ih hr x hx
      | some r => simp [hr] at h

theorem removeFirst_some {k : Nat} {l l' : List Job} (h : removeFirst k l = some l')
    (hone : (l.filter fun x => x.key == k).length ≤ 1) : ∀ x ∈ l', x.key ≠ k := by
  induction l generalizing l' with
  | nil => simp [removeFirst] at h
  | cons j js ih =>
    simp only [removeFirst] at h
    split at h
    · rename_i hj
      cases h
      simp only [List.filter_cons, hj, ↓reduceIte, List.length_cons] at hone
      have h0 : (js.filter fun x => x.key == k).length = 0 := by omega
      intro x hx e
      have : x ∈ js.filter fun x => x.key == k := List.mem_filter.mpr ⟨hx, by simpa using e⟩
      rw [List.length_eq_zero_iff.mp h0] at this
      simp at this
    · rename_i hj
      cases hr : removeFirst k js with
      | none => simp [hr] at h
      | some r =>
        simp [hr] at h; subst h
        simp only [List.filter_cons, hj, Bool.false_eq_true, ↓reduceIte] at hone
        intro x hx
        rcases List.mem_cons.mp hx with rfl | hx
        · simpa using hj
        · exact ih hr hone x hx

theorem mem_set {p : String × List Job} {t : Table} {et : String} {l : List Job}
    (h : p ∈ t.set et l) : (p.1 = et ∧ p.2 = l) ∨ (p ∈ t ∧ p.1 ≠ et) := by
  simp only [Table.set, List.mem_map] at h
  obtain ⟨q, hq, rfl⟩ := h
  split
  · exact .inl ⟨rfl, rfl⟩
  · rename_i hne; exact .inr ⟨hq, by simpa using hne⟩

theorem get_of_mem {p : String × List Job} {t : Table} (hp : p ∈ t)
    (hnd : (t.map (·.1)).Nodup) : t.get p.1 = p.2 := by
  induction t with
  | nil => simp at hp
  | cons q t ih =>
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hnd
    simp only [Table.get, List.lookup]
    rcases List.mem_cons.mp hp with rfl | hp
    · simp
    · have hne : (p.1 == q.1) = false := by
        simp only [beq_eq_false_iff_ne]
        intro e; exact hnd.1 ⟨p, hp, e⟩
      simp only [hne]
      exact ih hp hnd.2

theorem mem_touch {p : String × List Job} {t : Table} {et : String} (h : p ∈ t.touch et) :
    p ∈ t ∨ p = (et, []) := by
  unfold Table.touch at h
  split at h
  · exact .inl h
  · rcases List.mem_append.mp h with h | h
    · exact .inl h
    · simp at h; exact .inr h

theorem nodup_touch {t : Table} {et : String} (hnd : (t.map (·.1)).Nodup) :
    ((t.touch et).map (·.1)).Nodup := by
  unfold Table.touch
  split
  · exact hnd
  · rename_i hn
    simp only [List.map_append, List.map_cons, List.map_nil]
    apply List.nodup_append.mpr
    refine ⟨hnd, by simp, ?_⟩
    intro a ha b hb e
    simp at hb; subst hb; subst e
    simp only [List.mem_map] at ha
    obtain ⟨q, hq, rfl⟩ := ha
    exact hn (List.any_eq_true.mpr ⟨q, hq, by simp⟩)

theorem lookup_append_none {t : Table} {et : String} {v : List Job} (h : t.lookup et = none) :
    (t ++ [(et, v)]).lookup et = some v := by
  induction t with
  | nil => simp
  | cons q t ih =>
    obtain ⟨k, w⟩ := q
    rw [List.cons_append]
    unfold List.lookup at h ⊢
    split at h
    · cases h
    · rename_i hne
      exact ih h

theorem get_touch {t : Table} {et : String} : (t.touch et).get et = t.get et := by
  unfold Table.touch
  split
  · rfl
  · rename_i hn
    have hl : t.lookup et = none := by
      induction t with
      | nil => rfl
      | cons q t ih =>
        simp only [List.any_cons, Bool.or_eq_true, not_or] at hn
        simp only [List.lookup]
        have : (et == q.1) = false := by
          have := hn.1; simp only [beq_iff_eq] at this
          simpa [beq_eq_false_iff_ne] using fun e => this e.symm
        simp only [this]
        exact ih hn.2
    have hl' := lookup_append_none (v := ([] : List Job)) hl
    simp [Table.get, hl, hl']

/-- **Unsubscribing removes the listener for good.** If job `k` is listed
only under the event type its remove callback names, at most once, in a
table whose event types are distinct (true of every table the bus builds:
each job is stored once, under its own event type), then after the remove
callback runs, `k` is `Gone`, and by `gone_silent` it receives nothing more.
`unsub_gone_reachable` below drops the hypotheses for every reachable bus. -/
theorem unsub_gone {b : Bus} {et : String} {k : Nat} (hk : k < b.nextKey)
    (honly : ∀ p ∈ b.listeners, ∀ x ∈ p.2, x.key = k → p.1 = et)
    (hnd : (b.listeners.map (·.1)).Nodup)
    (hone : ((b.listeners.get et).filter fun x => x.key == k).length ≤ 1) :
    Gone k (asyncRemoveListener b et k) := by
  have honly' : ∀ p ∈ b.listeners.touch et, ∀ x ∈ p.2, x.key = k → p.1 = et := by
    intro p hp x hx
    rcases mem_touch hp with hp | rfl
    · exact honly p hp x hx
    · simp at hx
  have hnd' := nodup_touch (et := et) hnd
  unfold asyncRemoveListener
  dsimp only
  split
  · rename_i hr
    refine ⟨fun x ⟨p, hp, hx⟩ e => ?_, hk⟩
    have hpe := honly' p hp x hx e
    have := get_of_mem hp hnd'
    rw [hpe] at this
    rw [← this] at hx
    exact removeFirst_none hr x hx e
  · rename_i l hr
    rw [get_touch] at hr
    refine ⟨fun x ⟨p, hp, hx⟩ e => ?_, hk⟩
    have hp' : p ∈ (b.listeners.touch et).set et l := by
      split at hp
      · exact (List.mem_filter.mp hp).1
      · exact hp
    rcases mem_set hp' with ⟨_, h2⟩ | ⟨hp, hne⟩
    · rw [h2] at hx; exact removeFirst_some hr hone x hx e
    · exact hne (honly' p hp x hx e)

/-! ### Every reachable bus is well formed

`unsub_gone` takes its hypotheses about the table as given. The invariant
`WF` below supplies them for every remove callback the bus hands out, on every
bus reachable from `Bus.new`. Event types are *not* assumed distinct: `init`
installs whatever counts it is given, duplicates included, and `Table.set`
overwrites every entry of a type, so what holds is weaker and enough: every
entry that holds a listener a remove callback names is under that callback's
event type and equal to the entry `Table.get` finds. -/

/-- `t.get e` is empty or the list of an entry for `e`. -/
theorem get_cases (t : Table) (e : String) :
    t.get e = [] ∨ ∃ p ∈ t, p.1 = e ∧ p.2 = t.get e := by
  induction t with
  | nil => simp [Table.get, List.lookup]
  | cons q t ih =>
    obtain ⟨a, l⟩ := q
    simp only [Table.get, List.lookup] at ih ⊢
    split
    · rename_i h
      exact .inr ⟨(a, l), List.mem_cons_self .., (by simpa using h : e = a).symm, rfl⟩
    · rcases ih with h | ⟨p, hp, h1, h2⟩
      · exact .inl h
      · exact .inr ⟨p, List.mem_cons_of_mem _ hp, h1, h2⟩

theorem get_touch_any (t : Table) (e a : String) : (t.touch e).get a = t.get a := by
  unfold Table.touch
  split
  · rfl
  · rename_i hn
    clear hn
    simp only [Table.get]
    induction t with
    | nil => simp only [List.nil_append, List.lookup]; split <;> rfl
    | cons q t ih =>
      simp only [List.cons_append, List.lookup]
      split
      · rfl
      · exact ih

theorem get_set_ne {t : Table} {e a : String} {l : List Job} (h : a ≠ e) :
    (t.set e l).get a = t.get a := by
  induction t with
  | nil => rfl
  | cons q t ih =>
    simp only [Table.set, List.map_cons, Table.get] at ih ⊢
    by_cases hq : q.1 = e
    · have h1 : (q.1 == e) = true := by simpa using hq
      have h2 : (a == e) = false := by simpa using h
      have h3 : (a == q.1) = false := by rw [hq]; exact h2
      simp only [h1, ↓reduceIte, List.lookup, h2, h3]
      exact ih
    · have h1 : (q.1 == e) = false := by simpa using hq
      simp only [h1, Bool.false_eq_true, ↓reduceIte, List.lookup]
      split
      · rfl
      · exact ih

theorem get_set_self {t : Table} {e : String} {l : List Job} (h : ∃ q ∈ t, q.1 = e) :
    (t.set e l).get e = l := by
  induction t with
  | nil => obtain ⟨q, hq, _⟩ := h; simp at hq
  | cons q t ih =>
    simp only [Table.set, List.map_cons, Table.get] at ih ⊢
    by_cases hq : q.1 = e
    · have h1 : (q.1 == e) = true := by simpa using hq
      simp only [h1, ↓reduceIte, List.lookup, beq_self_eq_true, Option.getD_some]
    · have h1 : (q.1 == e) = false := by simpa using hq
      have h2 : (e == q.1) = false := by
        simp only [beq_eq_false_iff_ne]; exact fun h => hq h.symm
      simp only [h1, Bool.false_eq_true, ↓reduceIte, List.lookup, h2]
      obtain ⟨r, hr, hre⟩ := h
      rcases List.mem_cons.mp hr with rfl | hr
      · exact absurd hre hq
      · exact ih ⟨r, hr, hre⟩

theorem get_pop_ne {t : Table} {e a : String} (h : a ≠ e) : (t.pop e).get a = t.get a := by
  induction t with
  | nil => rfl
  | cons q t ih =>
    simp only [Table.pop, Table.get, List.filter_cons] at ih ⊢
    by_cases hq : q.1 = e
    · have h1 : (q.1 != e) = false := by simpa using hq
      have h3 : (a == q.1) = false := by rw [hq]; simpa using h
      simp only [h1, Bool.false_eq_true, ↓reduceIte, List.lookup, h3]
      exact ih
    · have h1 : (q.1 != e) = true := by simpa using hq
      simp only [h1, ↓reduceIte, List.lookup]
      split
      · rfl
      · exact ih

theorem exists_touch (t : Table) (e : String) : ∃ q ∈ t.touch e, q.1 = e := by
  unfold Table.touch
  split
  · rename_i h
    obtain ⟨q, hq, he⟩ := List.any_eq_true.mp h
    exact ⟨q, hq, by simpa using he⟩
  · exact ⟨(e, []), by simp, rfl⟩

theorem mem_of_lookup {β : Type} {l : List (String × β)} {a : String} {v : β}
    (h : l.lookup a = some v) : (a, v) ∈ l := by
  induction l with
  | nil => simp [List.lookup] at h
  | cons q l ih =>
    obtain ⟨b, w⟩ := q
    simp only [List.lookup] at h
    split at h
    · rename_i hb
      cases h
      have : a = b := by simpa using hb
      subst this
      exact List.mem_cons_self ..
    · exact List.mem_cons_of_mem _ (ih h)

theorem removeFirst_sublist {k : Nat} {l l' : List Job} (h : removeFirst k l = some l') :
    l'.Sublist l := by
  induction l generalizing l' with
  | nil => simp [removeFirst] at h
  | cons j js ih =>
    simp only [removeFirst] at h
    split at h
    · cases h; exact List.sublist_cons_self ..
    · cases hr : removeFirst k js with
      | none => simp [hr] at h
      | some r =>
        simp [hr] at h; subst h
        exact (ih hr).cons_cons j

/-- No two listeners in a list share a key. -/
def KeysDistinct (l : List Job) : Prop := l.Pairwise fun x y => x.key ≠ y.key

theorem KeysDistinct.filter_le_one {l : List Job} (h : KeysDistinct l) (k : Nat) :
    (l.filter fun x => x.key == k).length ≤ 1 := by
  induction l with
  | nil => simp
  | cons j js ih =>
    unfold KeysDistinct at h
    rw [List.pairwise_cons] at h
    simp only [List.filter_cons]
    split
    · rename_i hj
      have hk : j.key = k := by simpa using hj
      have : (js.filter fun x => x.key == k) = [] := by
        apply List.filter_eq_nil_iff.mpr
        intro y hy e
        have hy' : y.key = k := by simpa using e
        exact h.1 y hy (hk.trans hy'.symm)
      simp [this]
    · exact ih h.2

/-- Every entry holding job `k` is under `et` and is the entry `Table.get et`
finds. -/
def Canon (t : Table) (et : String) (k : Nat) : Prop :=
  ∀ p ∈ t, ∀ x ∈ p.2, x.key = k → p.1 = et ∧ p.2 = t.get et

theorem Canon.touch {t : Table} {et e : String} {k : Nat} (hc : Canon t et k) :
    Canon (t.touch e) et k := by
  intro p hp x hx hk
  rcases mem_touch hp with hp | rfl
  · obtain ⟨h1, h2⟩ := hc p hp x hx hk
    exact ⟨h1, by rw [get_touch_any]; exact h2⟩
  · simp at hx

theorem Canon.set {t : Table} {et e : String} {k : Nat} {l : List Job} (hc : Canon t et k)
    (hl : ∀ x ∈ l, x.key = k → x ∈ t.get e) : Canon (t.set e l) et k := by
  intro p hp x hx hk
  rcases mem_set hp with ⟨h1, h2⟩ | ⟨hp, hne⟩
  · rw [h2] at hx
    have hg := hl x hx hk
    rcases get_cases t e with h0 | ⟨q, hq, hq1, hq2⟩
    · rw [h0] at hg; simp at hg
    · have hxq : x ∈ q.2 := by rw [hq2]; exact hg
      obtain ⟨he, -⟩ := hc q hq x hxq hk
      have hee : e = et := hq1 ▸ he
      subst hee
      exact ⟨h1, by rw [h2, get_set_self ⟨q, hq, hq1⟩]⟩
  · obtain ⟨h1, h2⟩ := hc p hp x hx hk
    have hne' : et ≠ e := h1 ▸ hne
    exact ⟨h1, by rw [get_set_ne hne']; exact h2⟩

theorem Canon.pop {t : Table} {et e : String} {k : Nat} (hc : Canon t et k) :
    Canon (t.pop e) et k := by
  intro p hp x hx hk
  have hp' := List.mem_filter.mp hp
  obtain ⟨h1, h2⟩ := hc p hp'.1 x hx hk
  have hne : et ≠ e := by rw [← h1]; simpa using hp'.2
  exact ⟨h1, by rw [get_pop_ne hne]; exact h2⟩

/-- **Well-formedness.** Keys in the table were handed out already, no list
holds a key twice, and every stored remove callback `(et, k)` names a key
handed out already whose listener, wherever it is, is in the entry for `et`
that `Table.get` finds. -/
structure WF (b : Bus) : Prop where
  lt : ∀ x, InTable x b.listeners → x.key < b.nextKey
  distinct : ∀ p ∈ b.listeners, KeysDistinct p.2
  handles : ∀ h ∈ b.handles, h.2.2 < b.nextKey ∧ Canon b.listeners h.2.1 h.2.2

theorem WF.same {b b' : Bus} (hw : WF b) (h1 : b'.listeners = b.listeners)
    (h2 : b'.nextKey = b.nextKey) (h3 : b'.handles = b.handles) : WF b' := by
  obtain ⟨a, c, d⟩ := hw
  exact ⟨h1 ▸ h2 ▸ a, h1 ▸ c, h1 ▸ h2 ▸ h3 ▸ d⟩

theorem distinct_get {t : Table} (hd : ∀ p ∈ t, KeysDistinct p.2) (e : String) :
    KeysDistinct (t.get e) := by
  rcases get_cases t e with h | ⟨p, hp, _, h⟩
  · rw [h]; exact List.Pairwise.nil
  · rw [← h]; exact hd p hp

theorem distinct_touch {t : Table} (hd : ∀ p ∈ t, KeysDistinct p.2) (e : String) :
    ∀ p ∈ t.touch e, KeysDistinct p.2 := by
  intro p hp
  rcases mem_touch hp with hp | rfl
  · exact hd p hp
  · exact List.Pairwise.nil

theorem distinct_set {t : Table} (hd : ∀ p ∈ t, KeysDistinct p.2) {e : String} {l : List Job}
    (hl : KeysDistinct l) : ∀ p ∈ t.set e l, KeysDistinct p.2 := by
  intro p hp
  rcases mem_set hp with ⟨_, h⟩ | ⟨hp, _⟩
  · rw [h]; exact hl
  · exact hd p hp

theorem asyncRemoveListener_wf (b : Bus) (e : String) (k : Nat) (hw : WF b) :
    WF (asyncRemoveListener b e k) := by
  have hd1 := distinct_touch hw.distinct e
  unfold asyncRemoveListener
  dsimp only
  split
  · exact ⟨fun x hx => hw.lt x (inTable_touch hx), hd1,
      fun h hh => ⟨(hw.handles h hh).1, (hw.handles h hh).2.touch⟩⟩
  · rename_i l hl
    have hsub := removeFirst_sublist hl
    have hlt : ∀ x, InTable x ((b.listeners.touch e).set e l) → x.key < b.nextKey := by
      intro x hx
      rcases inTable_set hx with hx | hx
      · exact hw.lt x (inTable_touch (inTable_get (hsub.subset hx)))
      · exact hw.lt x (inTable_touch hx)
    have hd2 := distinct_set (e := e) hd1 ((distinct_get hd1 e).sublist hsub)
    have hc2 : ∀ h ∈ b.handles, Canon ((b.listeners.touch e).set e l) h.2.1 h.2.2 :=
      fun h hh => (hw.handles h hh).2.touch.set (fun x hx _ => hsub.subset hx)
    split
    · exact ⟨fun x hx => hlt x (inTable_pop hx),
        fun p hp => hd2 p (List.mem_filter.mp hp).1,
        fun h hh => ⟨(hw.handles h hh).1, (hc2 h hh).pop⟩⟩
    · exact ⟨hlt, hd2, fun h hh => ⟨(hw.handles h hh).1, hc2 h hh⟩⟩

theorem listenFilterableJob_wf (b : Bus) (j : Job) (id : String) (hw : WF b) :
    WF { (listenFilterableJob b j).1 with
      handles := (id, (listenFilterableJob b j).2) :: (listenFilterableJob b j).1.handles } := by
  simp only [listenFilterableJob]
  have hd1 := distinct_touch hw.distinct j.eventType
  have hlt1 : ∀ x, InTable x (b.listeners.touch j.eventType) → x.key < b.nextKey :=
    fun x hx => hw.lt x (inTable_touch hx)
  have hlt2 : ∀ x ∈ (b.listeners.touch j.eventType).get j.eventType, x.key < b.nextKey :=
    fun x hx => hlt1 x (inTable_get hx)
  refine ⟨?_, ?_, ?_⟩
  · intro x hx
    rcases inTable_set hx with hx | hx
    · rcases List.mem_append.mp hx with hx | hx
      · exact Nat.lt_succ_of_lt (hlt2 x hx)
      · simp at hx; subst hx; exact Nat.lt_succ_self _
    · exact Nat.lt_succ_of_lt (hlt1 x hx)
  · apply distinct_set hd1
    unfold KeysDistinct
    rw [List.pairwise_append]
    refine ⟨distinct_get hd1 _, List.pairwise_singleton .., ?_⟩
    intro x hx y hy
    simp at hy; subst hy
    exact Nat.ne_of_lt (hlt2 x hx)
  · intro h hh
    rcases List.mem_cons.mp hh with rfl | hh
    · refine ⟨Nat.lt_succ_self _, ?_⟩
      intro p hp x hx hk
      rcases mem_set hp with ⟨h1, h2⟩ | ⟨hp, _⟩
      · exact ⟨h1, by rw [h2, get_set_self (exists_touch ..)]⟩
      · exact absurd hk (Nat.ne_of_lt (hlt1 x ⟨p, hp, hx⟩))
    · obtain ⟨hk, hc⟩ := hw.handles h hh
      refine ⟨Nat.lt_succ_of_lt hk, hc.touch.set ?_⟩
      intro x hx hxk
      rcases List.mem_append.mp hx with hx | hx
      · exact hx
      · simp at hx; subst hx; simp at hxk; omega

theorem listenOp_wf {b b' : Bus} {id et once filter ri react rt}
    (h : listenOp b id et once filter ri react rt = .ok b') (hw : WF b) : WF b' := by
  unfold listenOp at h
  split at h
  · rename_i b1 h1 heq
    injection h with h; subst h
    obtain ⟨j, hj⟩ := listen_ok heq
    have := listenFilterableJob_wf b j id hw
    rw [hj] at this
    exact this
  · cases h

theorem unsubOp_wf {b b' : Bus} {id} (h : unsubOp b id = .ok b') (hw : WF b) : WF b' := by
  unfold unsubOp at h
  split at h
  · cases h
  · injection h with h; subst h; exact asyncRemoveListener_wf _ _ _ hw

theorem fireNested_wf (b : Bus) (q : Queued) (hw : WF b) : WF (fireNested b q).1 := by
  unfold fireNested
  split
  · exact hw
  · exact WF.same hw rfl rfl rfl

theorem react1_wf (now : Nat) (ev : Event) (b : Bus) (r : Reaction) (hw : WF b) :
    WF (react1 now ev b r).1 := by
  cases r with
  | fire f =>
    simp only [react1]
    split
    · exact hw
    · exact fireNested_wf _ _ hw
  | listen id et once filter ri react rt =>
    simp only [react1]
    split
    · rename_i b' h; exact listenOp_wf h hw
    · exact hw
  | unsub id =>
    simp only [react1]
    split
    · rename_i b' h; exact unsubOp_wf h hw
    · exact hw
  | raise e => exact hw

theorem runReactions_wf (now : Nat) (ev : Event) (b : Bus) (rs : List Reaction) (hw : WF b) :
    WF (runReactions now ev b rs).1 := by
  induction rs generalizing b with
  | nil => exact hw
  | cons r rs ih =>
    simp only [runReactions]
    have h1 := react1_wf now ev b r hw
    split
    · rename_i b' e heq; rw [heq] at h1; exact h1
    · rename_i b' heq; rw [heq] at h1; exact ih b' h1

theorem callListener_wf (now : Nat) (b : Bus) (job : Job) (ev : Event) (hw : WF b) :
    WF (callListener now b job ev).1 := by
  unfold callListener
  dsimp only
  split
  · exact runReactions_wf _ _ _ _ (WF.same hw rfl rfl rfl)
  · exact WF.same hw rfl rfl rfl

theorem runJob_wf (now : Nat) (b : Bus) (job : Job) (ev : Event) (hw : WF b) :
    WF (runJob now b job ev).1 := by
  unfold runJob
  split
  · exact hw
  split
  · split
    · exact hw
    · exact callListener_wf _ _ _ _
        (WF.same (asyncRemoveListener_wf b job.eventType job.key hw) rfl rfl rfl)
  · exact callListener_wf _ _ _ _ hw

theorem ensureEvent_wf (b : Bus) (q : Queued) (ev? : Option Event) (hw : WF b) :
    WF (ensureEvent b q ev?).1 := by
  cases ev? with
  | some ev => exact hw
  | none => simp only [ensureEvent, makeEvent]; split <;> exact WF.same hw rfl rfl rfl

theorem logJobError_wf (b : Bus) (err : Option Err) (hw : WF b) : WF (logJobError b err) := by
  cases err with
  | some e => exact WF.same hw rfl rfl rfl
  | none => exact hw

theorem dispatchLoop_wf (now : Nat) (q : Queued) (acc : Bus × Option Event) (js : List Job)
    (hw : WF acc.1) : WF (dispatchLoop now q acc js).1 := by
  induction js generalizing acc with
  | nil => exact hw
  | cons j js ih =>
    obtain ⟨b, ev?⟩ := acc
    simp only [dispatchLoop]
    split
    · exact ih _ (WF.same hw rfl rfl rfl)
    · exact ih _ hw
    · have h0 := ensureEvent_wf b q ev? hw
      generalize ensureEvent b q ev? = m at h0 ⊢
      obtain ⟨b0, ev⟩ := m
      dsimp only
      have h1 := runJob_wf now b0 j ev h0
      generalize runJob now b0 j ev = r at h1 ⊢
      obtain ⟨b1, err⟩ := r
      exact ih _ (logJobError_wf b1 err h1)

theorem dispatch_wf (now : Nat) (b : Bus) (q : Queued) (hw : WF b) : WF (dispatch now b q) :=
  dispatchLoop_wf now q (b, none) _ hw

theorem drain_wf (now n : Nat) (b : Bus) (hw : WF b) : WF (drain now n b) := by
  induction n generalizing b with
  | zero => exact hw
  | succ n ih =>
    simp only [drain]
    split
    · exact hw
    · exact ih _ (dispatch_wf now _ _ (WF.same hw rfl rfl rfl))

theorem asyncFire_wf {now : Nat} {b b' : Bus} {f : FireArgs} {ctx : Option Context}
    (h : asyncFire now b f ctx = .ok b') (hw : WF b) : WF b' := by
  unfold asyncFire at h
  split at h
  · cases h
  · dsimp only at h
    split at h
    · generalize hq : fireNested b (mkQueued now f ctx) = r at h
      obtain ⟨b1, e⟩ := r
      cases e with
      | none =>
        injection h with h; subst h
        have := fireNested_wf b (mkQueued now f ctx) hw
        rw [hq] at this
        exact this
      | some e => cases h
    · injection h with h; subst h
      have h1 := drain_wf now MAX_QUEUED_EVENT_DISPATCHES _
        (dispatch_wf now { b with dispatching := true, queuedCount := 0 } (mkQueued now f ctx)
          (WF.same hw rfl rfl rfl))
      exact WF.same h1 rfl rfl rfl

theorem initTable_wf (next : Nat) (cs : List (String × Nat)) :
    (∀ x, InTable x (initTable next cs).1 → x.key < (initTable next cs).2) ∧
    ∀ p ∈ (initTable next cs).1, KeysDistinct p.2 := by
  induction cs generalizing next with
  | nil => exact ⟨fun _ ⟨_, hp, _⟩ => by simp [initTable] at hp, fun p hp => by simp [initTable] at hp⟩
  | cons c cs ih =>
    obtain ⟨et, n⟩ := c
    have ih' := ih (next + n)
    have hf := (initTable_fresh (next + n) cs).2
    simp only [initTable]
    refine ⟨fun x ⟨p, hp, hx⟩ => ?_, fun p hp => ?_⟩
    · rcases List.mem_cons.mp hp with rfl | hp
      · simp only [List.mem_map, List.mem_range] at hx
        obtain ⟨i, hi, rfl⟩ := hx
        dsimp only
        omega
      · exact ih'.1 x ⟨p, hp, hx⟩
    · rcases List.mem_cons.mp hp with rfl | hp
      · unfold KeysDistinct
        rw [List.pairwise_map]
        exact (List.nodup_range).imp fun h e => h (by simpa using e)
      · exact ih'.2 p hp

theorem step_wf (now : Nat) (b : Bus) (op : Op) (hw : WF b) : WF (step now b op).1 := by
  cases op with
  | init counts =>
    have h := initTable_wf b.nextKey counts
    exact ⟨h.1, h.2, fun _ hh => by simp [step] at hh⟩
  | listeners => exact hw
  | fire f =>
    simp only [step]
    split
    · rename_i b' h; exact asyncFire_wf h hw
    · exact hw
  | call r =>
    simp only [step]
    split
    · rename_i b' h
      cases r with
      | listen => exact listenOp_wf h hw
      | unsub => exact unsubOp_wf h hw
      | raise => cases h
      | fire => cases h; exact hw
    · exact hw

theorem run_wf (b : Bus) (ops : List (Nat × Op)) (hw : WF b) : WF (run b ops) := by
  induction ops generalizing b with
  | nil => exact hw
  | cons op ops ih => exact ih _ (step_wf _ _ _ hw)

theorem wf_new : WF Bus.new := by
  refine ⟨?_, ?_, fun _ hh => by simp [Bus.new] at hh⟩
  · rintro x ⟨p, hp, hx⟩
    simp only [Bus.new, List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl <;> simp at hx
    subst hx; decide
  · intro p hp
    simp only [Bus.new, List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl <;> simp [KeysDistinct]

/-- Every bus reachable from `Bus.new` is well formed. -/
theorem reachable_wf (ops : List (Nat × Op)) : WF (run Bus.new ops) :=
  run_wf _ ops wf_new

/-- Running the remove callback `(et, k)` of a well-formed bus's table makes
`k` `Gone`. -/
theorem remove_gone {b : Bus} {et : String} {k : Nat} (hk : k < b.nextKey)
    (hc : Canon b.listeners et k) (hd : ∀ p ∈ b.listeners, KeysDistinct p.2) :
    Gone k (asyncRemoveListener b et k) := by
  have hc1 : Canon (b.listeners.touch et) et k := hc.touch
  have hd1 := distinct_touch hd et
  unfold asyncRemoveListener
  dsimp only
  split
  · rename_i hr
    refine ⟨fun x ⟨p, hp, hx⟩ e => ?_, hk⟩
    obtain ⟨_, h2⟩ := hc1 p hp x hx e
    rw [h2] at hx
    exact removeFirst_none hr x hx e
  · rename_i l hr
    refine ⟨fun x ⟨p, hp, hx⟩ e => ?_, hk⟩
    have hp' : p ∈ (b.listeners.touch et).set et l := by
      split at hp
      · exact (List.mem_filter.mp hp).1
      · exact hp
    rcases mem_set hp' with ⟨_, h2⟩ | ⟨hp, hne⟩
    · rw [h2] at hx
      exact removeFirst_some hr ((distinct_get hd1 et).filter_le_one k) x hx e
    · exact hne (hc1 p hp x hx e).1

/-- **Unsubscribing removes the listener, on any well-formed bus.** If the
remove callback stored under `id` is `(et, k)`, running it (top level, or as
a listener's reaction mid-dispatch: every intermediate bus is well formed too)
leaves job `k` `Gone`. -/
theorem unsub_gone_wf {b b' : Bus} {id et : String} {k : Nat} (hw : WF b)
    (hh : b.handles.lookup id = some (et, k)) (hu : unsubOp b id = .ok b') : Gone k b' := by
  obtain ⟨hk, hc⟩ := hw.handles _ (mem_of_lookup hh)
  unfold unsubOp at hu
  rw [hh] at hu
  injection hu with hu
  subst hu
  exact remove_gone hk hc hw.distinct

/-- **Unsubscribing removes the listener for good**, unconditionally: on any
bus reachable from `Bus.new`, running the remove callback `(et, k)` stored
under `id` leaves job `k` `Gone`. -/
theorem unsub_gone_reachable (ops : List (Nat × Op)) {id et : String} {k : Nat} {b' : Bus}
    (hh : (run Bus.new ops).handles.lookup id = some (et, k))
    (hu : unsubOp (run Bus.new ops) id = .ok b') : Gone k b' :=
  unsub_gone_wf (reachable_wf ops) hh hu

theorem run_append (b : Bus) (xs ys : List (Nat × Op)) : run b (xs ++ ys) = run (run b xs) ys := by
  induction xs generalizing b with
  | nil => rfl
  | cons x xs ih => exact ih _

/-- **An unsubscribed listener hears nothing more.** From a new bus, after
any operations `ops`, unsubscribe `id` (whose remove callback names job `k`);
whatever operations `later` follow (fires with arbitrary listener reactions,
listens, unsubscribes, `init`), job `k` receives no further deliveries and
stays out of the table. -/
theorem unsub_silent (ops : List (Nat × Op)) (now : Nat) (id et : String) (k : Nat)
    (hh : (run Bus.new ops).handles.lookup id = some (et, k)) (later : List (Nat × Op)) :
    jobCount k (run Bus.new (ops ++ (now, .call (.unsub id)) :: later)).deliveries =
      jobCount k (run Bus.new (ops ++ [(now, .call (.unsub id))])).deliveries ∧
    Gone k (run Bus.new (ops ++ (now, .call (.unsub id)) :: later)) := by
  have hstep : run Bus.new (ops ++ [(now, .call (.unsub id))]) =
      asyncRemoveListener (run Bus.new ops) et k := by
    rw [run_append]
    simp [run, step, step.react1Top, unsubOp, hh]
  have hg : Gone k (run Bus.new (ops ++ [(now, .call (.unsub id))])) := by
    rw [hstep]
    exact unsub_gone_reachable ops hh (by simp [unsubOp, hh])
  have := gone_silent _ later k hg
  have e : ops ++ (now, .call (.unsub id)) :: later =
      (ops ++ [(now, .call (.unsub id))]) ++ later := by simp
  rw [e, run_append]
  exact this
