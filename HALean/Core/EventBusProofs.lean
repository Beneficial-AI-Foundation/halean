/-
  Theorems about the event bus (`HALean/Core/EventBus.lean`).

  * `snapshot_match_all`, `snapshot_excluded`: which listeners a dispatch
    iterates over (specific ones first, then `MATCH_ALL` unless excluded).
  * `once_at_most_once`: over any sequence of operations, a listener added
    with `async_listen_once` receives at most one event.
  * `gone_silent`, `unsub_gone`: once a listener is out of the table (e.g.
    after its remove callback ran), it never receives anything again.
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
callback runs, `k` is `Gone`, and by `gone_silent` it receives nothing more. -/
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
