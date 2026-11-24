/-
  Specs for script runs (`HALean/Automation/Script.lean`, upstream
  `homeassistant/helpers/script.py`).

  The main results: what `continue_on_error` can and cannot swallow
  (`unwindError`, `resumeService`), how a failed `condition` step ends a
  sub-script (`conditionFail`), the scope of the `repeat` variable
  (`currentRepeat`, `Run.scopeVars`), and the behaviour of single steps of
  the run loop (`step`, `exec`).
-/
import HALean.Automation.Script
open Lean

set_option linter.unusedSimpArgs false

namespace HALean.Automation

/-! ### `repeatVar` (`set_repeat_var`) -/

/-- An item that is `None` is not set (`if item is not None`). -/
theorem repeatVar_item_none (i : Nat) (count : Option Nat) :
    repeatVar i count (some .none) = repeatVar i count none := rfl

/-- A count of zero sets no `last` (`if count:`). -/
theorem repeatVar_count_zero (i : Nat) (item : Option Template.Value) :
    repeatVar i (some 0) item = repeatVar i none item := rfl

/-- `repeat.first` and `repeat.index` are always the first two entries. -/
theorem repeatVar_first_index (i : Nat) (count : Option Nat) (item : Option Template.Value) :
    ∃ rest, repeatVar i count item =
      .dict ((.str "first", .bool (i == 1)) :: (.str "index", .int i) :: rest) := by
  unfold repeatVar
  exact ⟨_, by simp only [List.cons_append, List.nil_append]; rfl⟩

/-- `while` / `until` loops (no count, no item) set only `first` and `index`. -/
theorem repeatVar_plain (i : Nat) :
    repeatVar i none none = .dict [(.str "first", .bool (i == 1)), (.str "index", .int i)] := rfl

/-- With a positive count, `repeat.last` is true on the last iteration only. -/
theorem repeatVar_counted (i n : Nat) (hn : 0 < n) :
    repeatVar i (some n) none =
      .dict [(.str "first", .bool (i == 1)), (.str "index", .int i),
             (.str "last", .bool (i == n))] := by
  unfold repeatVar
  simp [hn]

/-! ### `currentRepeat`, `Run.scopeVars` -/

/-- Sub-script (`seq`) frames do not hide the enclosing loop's `repeat`. -/
theorem currentRepeat_seq_prefix (pre rest : List Frame)
    (h : ∀ f ∈ pre, ∃ as c, f = .seq as c) :
    currentRepeat (pre ++ rest) = currentRepeat rest := by
  induction pre with
  | nil => rfl
  | cons f pre ih =>
    obtain ⟨as, c, rfl⟩ := h _ (List.mem_cons_self ..)
    simp only [List.cons_append, currentRepeat]
    exact ih (fun g hg => h g (List.mem_cons_of_mem _ hg))

/-- There is no `repeat` variable exactly when no enclosing frame is a loop. -/
theorem currentRepeat_none_iff (fs : List Frame) :
    currentRepeat fs = none ↔ ∀ f ∈ fs, ∃ as c, f = .seq as c := by
  induction fs with
  | nil => simp [currentRepeat]
  | cons f fs ih =>
    cases f with
    | seq as c =>
      simp only [currentRepeat]
      rw [ih]
      constructor
      · intro h f hf
        rcases List.mem_cons.mp hf with rfl | hf
        · exact ⟨as, c, rfl⟩
        · exact h f hf
      · intro h f hf; exact h f (List.mem_cons_of_mem _ hf)
    | repeatCount i n b c => simp [currentRepeat]
    | repeatWhile i cs b c => simp [currentRepeat]
    | repeatUntil i cs b c => simp [currentRepeat]
    | repeatEach i items b c => simp [currentRepeat]

/-- Inside a counted loop, `repeat` is that loop's, whatever encloses it. -/
theorem currentRepeat_repeatCount (i n : Nat) (body : List Action) (c : Bool) (rest : List Frame) :
    currentRepeat (.repeatCount i n body c :: rest) = some (repeatVar i (some n) none) := rfl

/-- The innermost loop wins: outer frames do not matter. -/
theorem currentRepeat_innermost (f : Frame) (rest rest' : List Frame)
    (h : ∀ as c, f ≠ .seq as c) :
    currentRepeat (f :: rest) = currentRepeat (f :: rest') := by
  cases f with
  | seq as c => exact absurd rfl (h as c)
  | repeatCount i n b c => rfl
  | repeatWhile i cs b c => rfl
  | repeatUntil i cs b c => rfl
  | repeatEach i items b c => rfl

/-- A step always sees all of the run's variables; the only addition is
`repeat`, in front. -/
theorem Run.scopeVars_suffix (r : Run) : r.vars <:+ r.scopeVars := by
  unfold Run.scopeVars
  split
  · exact List.suffix_cons _ _
  · exact List.suffix_refl _

/-- Outside every loop a step sees exactly the run's variables. -/
theorem Run.scopeVars_no_loop (r : Run) (h : ∀ f ∈ r.frames, ∃ as c, f = .seq as c) :
    r.scopeVars = r.vars := by
  unfold Run.scopeVars
  rw [(currentRepeat_none_iff r.frames).mpr h]

/-- Inside a loop the first variable in scope is `repeat`. -/
theorem Run.scopeVars_in_loop (r : Run) (v : Template.Value) (h : currentRepeat r.frames = some v) :
    r.scopeVars = ("repeat", v) :: r.vars := by
  unfold Run.scopeVars
  rw [h]

/-! ### `RunEnd.raises` -/

/-- A sub-script's end is re-raised by its parent unless it finished or
stopped on a failed condition. -/
theorem RunEnd.raises_false_iff (e : RunEnd) :
    e.raises = false ↔ e = .finished ∨ e = .conditionFailed := by
  cases e <;> simp [RunEnd.raises]

/-! ### `Wait.beq` -/

/-- Comparing a wait with itself is true. -/
theorem Wait.beq_refl (w : Wait) : Wait.beq w w = true := by
  cases w <;> simp [Wait.beq]

/-- The comparison is symmetric. -/
theorem Wait.beq_symm (a b : Wait) : Wait.beq a b = Wait.beq b a := by
  cases a <;> cases b <;> simp only [Wait.beq] <;>
    simp only [Bool.beq_comm (a := _), BEq.comm (a := _)] <;>
    first | rfl | (simp only [Bool.and_comm, BEq.comm]; done) | skip
  all_goals first
    | rfl
    | (rename_i a1 a2 a3 b1 b2 b3
       rw [BEq.comm (a := a1), BEq.comm (a := a2), BEq.comm (a := a3)])
    | (rename_i a1 a2 a3 a4 b1 b2 b3 b4
       rw [BEq.comm (a := a3), BEq.comm (a := a4)])
    | (rename_i a1 b1; rw [BEq.comm (a := a1)])
    | (rename_i a1 a2 a3 b1 b2 b3
       rw [BEq.comm (a := a2), BEq.comm (a := a3)])
    | (rename_i a1 a2 a3 b1 b2 b3
       rw [BEq.comm (a := a1), BEq.comm (a := a3)])

/-- Waits of different kinds are never equal: a ready run is equal to
nothing but a ready run. -/
theorem Wait.beq_ready_iff (w : Wait) : Wait.beq .ready w = true ↔ w = .ready := by
  cases w <;> simp [Wait.beq]

/-- Two delays are equal exactly when they end at the same time. -/
theorem Wait.beq_delay_iff (a b : Millis) :
    Wait.beq (.delayUntil a) (.delayUntil b) = true ↔ a = b := by
  simp [Wait.beq]

/-! ### `waitVar`, `setWaitFields` -/

/-- Updating fields of `wait` never adds, removes or renames a variable. -/
theorem setWaitFields_keys (vars : List (String × Template.Value))
    (fields : List (String × Template.Value)) :
    (setWaitFields vars fields).map (·.1) = vars.map (·.1) := by
  unfold setWaitFields
  rw [List.map_map]
  apply List.map_congr_left
  intro ⟨k, v⟩ _
  simp only [Function.comp]
  split
  · rfl
  · split <;> rfl

/-- Variables other than `wait` are left as they are. -/
theorem setWaitFields_other (vars : List (String × Template.Value))
    (fields : List (String × Template.Value)) (k : String) (v : Template.Value)
    (h : (k, v) ∈ vars) (hk : k ≠ "wait") : (k, v) ∈ setWaitFields vars fields := by
  unfold setWaitFields
  apply List.mem_map.mpr
  refine ⟨(k, v), h, ?_⟩
  simp [hk]

/-- Setting `remaining` on a fresh `wait` variable replaces just that field. -/
theorem setWaitFields_remaining (rem new : Template.Value) (completed : Bool) :
    setWaitFields [("wait", waitVar rem completed)] [("remaining", new)]
      = [("wait", waitVar new completed)] := by
  simp [setWaitFields, waitVar]

/-- Setting a field `wait` does not have changes nothing. -/
theorem setWaitFields_absent_field (rem x : Template.Value) (completed : Bool) :
    setWaitFields [("wait", waitVar rem completed)] [("trigger", x)]
      = [("wait", waitVar rem completed)] := by
  simp [setWaitFields, waitVar]

/-! ### `conditionFail` (`_ConditionFail`) -/

/-- A failed condition in the root sequence ends the run. -/
theorem conditionFail_root (r : Run) (h : r.frames.length ≤ 1) :
    conditionFail r = .done .conditionFailed := by
  unfold conditionFail
  match hf : r.frames, h with
  | [], _ => rfl
  | [_], _ => rfl
  | _ :: _ :: _, h => simp at h

/-- A failed condition in a sub-script ends just that sub-script: the
parent continues, with nothing else about the run changed. -/
theorem conditionFail_sub (r : Run) (f g : Frame) (rest : List Frame)
    (h : r.frames = f :: g :: rest) :
    conditionFail r = .next { r with frames := g :: rest } := by
  unfold conditionFail
  rw [h]

/-! ### `unwindError` (`_handle_exception`) -/

/-- What unwinding leaves on the stack: the frames below the innermost
frame with `continue_on_error`, if that frame is not the root. -/
def resumePoint : List Frame → Option (List Frame)
  | [] => none
  | f :: rest => if f.coe then (if rest.isEmpty then none else some rest) else resumePoint rest

private theorem unwindError_go_haError (r : Run) (msg : String) (fs : List Frame) :
    unwindError.go r .haError msg fs =
      match resumePoint fs with
      | some rest => .next { r with frames := rest }
      | none => .done (.error .haError msg) := by
  induction fs with
  | nil => rfl
  | cons f rest ih =>
    unfold unwindError.go resumePoint
    have hb : (ErrKind.haError == ErrKind.haError) = true := rfl
    by_cases hc : f.coe = true
    · cases rest <;> simp [hc, hb]
    · simp [hc, ih]

/-- A `HomeAssistantError` is swallowed by the innermost enclosing step with
`continue_on_error`, and the run resumes right after that step; with no
such step the run ends with the error. -/
theorem unwindError_haError (r : Run) (msg : String) :
    unwindError r .haError msg =
      match resumePoint r.frames with
      | some rest => .next { r with frames := rest }
      | none => .done (.error .haError msg) :=
  unwindError_go_haError r msg r.frames

private theorem unwindError_go_other (r : Run) (k : ErrKind) (msg : String) (hk : k ≠ .haError)
    (fs : List Frame) : unwindError.go r k msg fs = .done (.error k msg) := by
  have hk' : (k == ErrKind.haError) = false := by cases k <;> first | rfl | exact absurd rfl hk
  induction fs with
  | nil => rfl
  | cons f rest ih =>
    unfold unwindError.go
    simp [hk', ih]

/-- Configuration errors (`vol.Invalid`) and unexpected exceptions are never
swallowed by an enclosing `continue_on_error`: the run ends with the error. -/
theorem unwindError_not_haError (r : Run) (k : ErrKind) (msg : String) (hk : k ≠ .haError) :
    unwindError r k msg = .done (.error k msg) :=
  unwindError_go_other r k msg hk r.frames

/-- Without any `continue_on_error` frame every error ends the run. -/
theorem unwindError_no_coe (r : Run) (k : ErrKind) (msg : String)
    (h : ∀ f ∈ r.frames, f.coe = false) : unwindError r k msg = .done (.error k msg) := by
  unfold unwindError
  generalize r.frames = fs at h
  induction fs with
  | nil => rfl
  | cons f rest ih =>
    unfold unwindError.go
    simp only [h f (List.mem_cons_self ..), Bool.false_and, Bool.false_eq_true, ite_false]
    exact ih (fun g hg => h g (List.mem_cons_of_mem _ hg))

/-- The resume point is always strictly below where the error was raised. -/
theorem resumePoint_suffix (fs rest : List Frame) (h : resumePoint fs = some rest) :
    rest <:+ fs ∧ rest.length < fs.length ∧ rest ≠ [] := by
  induction fs with
  | nil => simp [resumePoint] at h
  | cons f tl ih =>
    unfold resumePoint at h
    by_cases hc : f.coe = true
    · simp only [hc, ite_true] at h
      cases tl with
      | nil => simp at h
      | cons g tl' =>
        simp only [List.isEmpty_cons, Bool.false_eq_true, ite_false, Option.some.injEq] at h
        subst h
        exact ⟨List.suffix_cons _ _, by simp, by simp⟩
    · simp only [hc, ite_false] at h
      obtain ⟨h1, h2, h3⟩ := ih h
      exact ⟨List.IsSuffix.trans h1 (List.suffix_cons _ _), by simp; omega, h3⟩

/-- Unwinding either ends the run with exactly that error, or resumes the
same run on a shorter, non-empty stack. Nothing else about the run changes. -/
theorem unwindError_cases (r : Run) (k : ErrKind) (msg : String) :
    unwindError r k msg = .done (.error k msg) ∨
      ∃ rest, unwindError r k msg = .next { r with frames := rest } ∧
        rest <:+ r.frames ∧ rest.length < r.frames.length ∧ rest ≠ [] := by
  by_cases hk : k = .haError
  · subst hk
    rw [unwindError_haError]
    cases h : resumePoint r.frames with
    | none => exact Or.inl rfl
    | some rest => exact Or.inr ⟨rest, rfl, resumePoint_suffix _ _ h⟩
  · exact Or.inl (unwindError_not_haError r k msg hk)

/-! ### `resumeService` -/

/-- A completion for a run that is not waiting on a service call changes
nothing. -/
theorem resumeService_not_waiting (r : Run) (ok : Bool) (k : ErrKind) (msg : String)
    (resp : Template.Value) (h : ∀ c coe rv, r.wait ≠ .service c coe rv) :
    resumeService r ok k msg resp = .next r := by
  unfold resumeService
  split
  · rename_i c coe rv hw; exact absurd hw (h c coe rv)
  · rfl

/-- A successful call without `response_variable` just makes the run ready. -/
theorem resumeService_ok (r : Run) (c : Nat) (coe : Bool) (k : ErrKind) (msg : String)
    (resp : Template.Value) (h : r.wait = .service c coe none) :
    resumeService r true k msg resp = .next { r with wait := .ready } := by
  unfold resumeService
  rw [h]
  rfl

/-- A successful call with a `response_variable` assigns the response to it. -/
theorem resumeService_ok_response (r : Run) (c : Nat) (coe : Bool) (k : ErrKind) (msg v : String)
    (resp : Template.Value) (h : r.wait = .service c coe (some v)) (hv : v ≠ "") :
    resumeService r true k msg resp =
      .next { r with wait := .ready, vars := setVar r.vars v resp } := by
  unfold resumeService
  rw [h]
  have : v.isEmpty = false := by
    cases hh : v.isEmpty
    · rfl
    · exact absurd (String.isEmpty_iff.mp hh) hv
  simp [this]

/-- A failed call on a step with `continue_on_error` is swallowed by that
step, unless it is a configuration error. -/
theorem resumeService_coe (r : Run) (c : Nat) (rv : Option String) (k : ErrKind) (msg : String)
    (resp : Template.Value) (h : r.wait = .service c true rv) (hk : k ≠ .invalid) :
    resumeService r false k msg resp = .next { r with wait := .ready } := by
  unfold resumeService
  rw [h]
  have : (k != ErrKind.invalid) = true := by cases k <;> first | rfl | exact absurd rfl hk
  simp [this]

/-- A configuration error (`vol.Invalid`) from a service call always ends the
run, whatever `continue_on_error` says, on the step or around it. -/
theorem resumeService_invalid (r : Run) (c : Nat) (coe : Bool) (rv : Option String) (msg : String)
    (resp : Template.Value) (h : r.wait = .service c coe rv) :
    resumeService r false .invalid msg resp = .done (.error .invalid msg) := by
  unfold resumeService
  rw [h]
  have : (ErrKind.invalid != ErrKind.invalid) = false := rfl
  simp only [this, Bool.and_false, Bool.false_eq_true, ite_false]
  exact unwindError_not_haError _ _ _ (by simp)

/-- A failed call on a step without `continue_on_error` unwinds like any
other error of that kind. -/
theorem resumeService_failed (r : Run) (c : Nat) (rv : Option String) (k : ErrKind) (msg : String)
    (resp : Template.Value) (h : r.wait = .service c false rv) :
    resumeService r false k msg resp = unwindError { r with wait := .ready } k msg := by
  unfold resumeService
  rw [h]
  simp

/-! ### `step` -/

/-- A run with no frames left has finished. -/
theorem step_no_frames (ctx : ExecCtx) (r : Run) (h : r.frames = []) :
    step ctx r = (.done .finished, [], ctx) := by
  unfold step
  simp only [h]

/-- The root sequence running out of actions finishes the run. -/
theorem step_root_done (ctx : ExecCtx) (r : Run) (c : Bool) (h : r.frames = [.seq [] c]) :
    step ctx r = (.done .finished, [], ctx) := by
  unfold step
  simp only [h]
  rfl

/-- A sub-script running out of actions returns to its parent. -/
theorem step_sub_done (ctx : ExecCtx) (r : Run) (c : Bool) (f : Frame) (rest : List Frame)
    (h : r.frames = .seq [] c :: f :: rest) :
    step ctx r = (.next { r with frames := f :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  rfl

/-- A counted loop that has iterations left starts its body as a fresh
sub-script and counts the iteration. -/
theorem step_repeatCount_iter (ctx : ExecCtx) (r : Run) (i n : Nat) (body : List Action) (c : Bool)
    (rest : List Frame) (h : r.frames = .repeatCount i n body c :: rest) (hi : i < n) :
    step ctx r =
      (.next { r with frames := .seq body false :: .repeatCount (i + 1) n body c :: rest },
       [], ctx) := by
  unfold step
  simp only [h, hi, ite_true]

/-- A counted loop that has done its `n` iterations is popped. -/
theorem step_repeatCount_done (ctx : ExecCtx) (r : Run) (i n : Nat) (body : List Action) (c : Bool)
    (rest : List Frame) (h : r.frames = .repeatCount i n body c :: rest) (hi : n ≤ i) :
    step ctx r = (.next { r with frames := rest }, [], ctx) := by
  unfold step
  simp only [h, Nat.not_lt.mpr hi, ite_false]

/-- A `for_each` loop runs its body once per item, then is popped. -/
theorem step_repeatEach (ctx : ExecCtx) (r : Run) (i : Nat) (items : List Template.Value)
    (body : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .repeatEach i items body c :: rest) :
    step ctx r =
      (if i < items.length then
        .next { r with frames := .seq body false :: .repeatEach (i + 1) items body c :: rest }
       else .next { r with frames := rest }, [], ctx) := by
  unfold step
  simp only [h]
  split <;> rfl

/-- `repeat ... until` always runs its body once before testing. -/
theorem step_repeatUntil_first (ctx : ExecCtx) (r : Run) (cs : List Condition) (body : List Action)
    (c : Bool) (rest : List Frame) (h : r.frames = .repeatUntil 0 cs body c :: rest) :
    step ctx r =
      (.next { r with frames := .seq body false :: .repeatUntil 1 cs body c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  rfl

/-- A `while` loop with no conditions is stopped by the iteration limit
(`REPEAT_TERMINATE_ITERATIONS`) rather than running for ever. -/
theorem step_repeatWhile_limit (ctx : ExecCtx) (r : Run) (i : Nat) (body : List Action)
    (c : Bool) (rest : List Frame) (h : r.frames = .repeatWhile i [] body c :: rest)
    (hi : REPEAT_TERMINATE_ITERATIONS ≤ i) :
    (step ctx r).1 = .done (.aborted
      s!"While condition terminated because it looped {REPEAT_TERMINATE_ITERATIONS} times") := by
  unfold step
  simp only [h, testConditions]
  have : i + 1 > REPEAT_TERMINATE_ITERATIONS := by omega
  simp [this]

/-- No step other than a service call emits a service call; in particular a
`delay` of zero does nothing and moves on. -/
theorem step_delay_zero (ctx : ExecCtx) (r : Run) (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.delay 0 :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A positive `delay` blocks the run until exactly that much later. -/
theorem step_delay_pos (ctx : ExecCtx) (r : Run) (ms : Nat) (as : List Action) (c : Bool)
    (rest : List Frame) (h : r.frames = .seq (.delay ms :: as) c :: rest) (hms : ms ≠ 0) :
    step ctx r =
      (.blocked { r with frames := .seq as c :: rest, wait := .delayUntil (ctx.env.now.utc + ms) },
       [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run, hms]

/-- `stop` with `error: true` aborts the run with its reason … -/
theorem step_stop_error (ctx : ExecCtx) (r : Run) (reason : String) (rv : Option String)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.stop reason true rv :: as) c :: rest) :
    step ctx r = (.done (.aborted reason), [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- … and `continue_on_error` on the step does not change that. -/
theorem step_stop_error_coe (ctx : ExecCtx) (r : Run) (reason : String) (rv : Option String)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.continueOnError (.stop reason true rv) :: as) c :: rest) :
    step ctx r = (.done (.aborted reason), [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A plain `stop` ends the run as stopped, with no response. -/
theorem step_stop (ctx : ExecCtx) (r : Run) (reason : String)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.stop reason false none :: as) c :: rest) :
    step ctx r = (.done (.stopped reason), [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A `sequence` action starts its body as a sub-script. -/
theorem step_sequence (ctx : ExecCtx) (r : Run) (body : List Action)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.sequence body :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq body false :: .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A `repeat` with a count starts at iteration zero (nothing has run yet). -/
theorem step_repeatCount_start (ctx : ExecCtx) (r : Run) (n : Nat) (body : List Action)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.repeatCount n body :: as) c :: rest) :
    step ctx r =
      (.next { r with frames := .repeatCount 0 n body false :: .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- An empty `parallel` is a no-op; a non-empty one spawns its branches. -/
theorem step_parallel_nil (ctx : ExecCtx) (r : Run)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.parallel [] :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

theorem step_parallel_cons (ctx : ExecCtx) (r : Run) (b : List Action) (bs : List (List Action))
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.parallel (b :: bs) :: as) c :: rest) :
    step ctx r = (.spawn { r with frames := .seq as c :: rest } (b :: bs) false, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A `choose` with no options and no default does nothing. -/
theorem step_choose_empty (ctx : ExecCtx) (r : Run)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.choose [] none :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- A `choose` with no options runs its default. -/
theorem step_choose_default (ctx : ExecCtx) (r : Run) (body : List Action)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.choose [] (some body) :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq body false :: .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run]

/-- `if` with no conditions always takes the `then` branch (`_test_conditions`
of an empty list is true). -/
theorem step_if_no_conditions (ctx : ExecCtx) (r : Run) (th : List Action)
    (el : Option (List Action)) (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.ifThen [] th el :: as) c :: rest) :
    step ctx r = (.next { r with frames := .seq th false :: .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run, testConditions]

/-- A disabled `condition` step returns `None`, which is falsy: it ends the
(sub-)script like a failed condition, without logging. -/
theorem step_condition_disabled (ctx : ExecCtx) (r : Run)
    (as : List Action) (c : Bool) (rest : List Frame)
    (h : r.frames = .seq (.condition .disabled :: as) c :: rest) :
    step ctx r = (conditionFail { r with frames := .seq as c :: rest }, [], ctx) := by
  unfold step
  simp only [h]
  simp [step.run, evalCond]

/-- Service call ids are never reused: handling an action never lowers the
next call id. -/
theorem step_run_callId (ctx : ExecCtx) (r : Run) (env : CondEnv) (push : Frame → List Frame → Run)
    (cur : List Frame) (r' : Run) (coe : Bool) (a : Action) :
    ctx.nextCallId ≤ (step.run ctx r env push cur r' coe a).2.2.nextCallId := by
  fun_induction step.run ctx r env push cur r' coe a <;>
    first | (simp_all; done) | exact Nat.le_succ _

/-- The same for a whole step. -/
theorem step_callId (ctx : ExecCtx) (r : Run) :
    ctx.nextCallId ≤ (step ctx r).2.2.nextCallId := by
  unfold step
  split
  · simp
  · split <;> simp
  · exact step_run_callId ..
  all_goals try simp only []
  all_goals repeat' split
  all_goals simp

/-! ### `exec` -/

/-- With no step budget left the run ends with an error and emits nothing
more. -/
theorem exec_loop_zero (ctx : ExecCtx) (r : Run) (acc : List Cmd) :
    exec.loop 0 ctx r acc = (.done r (.error .other "step budget exhausted"), acc, ctx) := rfl

/-- One iteration of the loop: a step that ends or blocks the run stops the
loop, keeping the commands in order. -/
theorem exec_loop_done (fuel : Nat) (ctx ctx' : ExecCtx) (r : Run) (acc cs : List Cmd) (e : RunEnd)
    (h : step ctx r = (.done e, cs, ctx')) :
    exec.loop (fuel + 1) ctx r acc = (.done r e, acc ++ cs, ctx') := by
  simp only [exec.loop, h]

theorem exec_loop_blocked (fuel : Nat) (ctx ctx' : ExecCtx) (r r' : Run) (acc cs : List Cmd)
    (h : step ctx r = (.blocked r', cs, ctx')) :
    exec.loop (fuel + 1) ctx r acc = (.blocked r', acc ++ cs, ctx') := by
  simp only [exec.loop, h]

/-- A step that moves on keeps the loop going with the commands appended. -/
theorem exec_loop_next (fuel : Nat) (ctx ctx' : ExecCtx) (r r' : Run) (acc cs : List Cmd)
    (h : step ctx r = (.next r', cs, ctx')) :
    exec.loop (fuel + 1) ctx r acc = exec.loop fuel ctx' r' (acc ++ cs) := by
  simp only [exec.loop, h]

/-- Commands already emitted are never dropped or reordered: the result's
commands extend the accumulator. -/
theorem exec_loop_acc_prefix (fuel : Nat) (ctx : ExecCtx) (r : Run) (acc : List Cmd) :
    acc <+: (exec.loop fuel ctx r acc).2.1 := by
  induction fuel generalizing ctx r acc with
  | zero => exact List.prefix_refl _
  | succ n ih =>
    simp only [exec.loop]
    split
    · exact List.IsPrefix.trans (List.prefix_append _ _) (ih _ _ _)
    · exact List.prefix_append _ _
    · exact List.prefix_append _ _
    · exact List.prefix_append _ _

/-- … and for a whole run of the loop: call ids only grow. -/
theorem exec_loop_callId (fuel : Nat) (ctx : ExecCtx) (r : Run) (acc : List Cmd) :
    ctx.nextCallId ≤ (exec.loop fuel ctx r acc).2.2.nextCallId := by
  induction fuel generalizing ctx r acc with
  | zero => exact Nat.le_refl _
  | succ n ih =>
    simp only [exec.loop]
    have hs := step_callId ctx r
    split <;> rename_i heq <;> rw [heq] at hs
    · exact Nat.le_trans hs (ih _ _ _)
    all_goals exact hs

theorem exec_callId (ctx : ExecCtx) (r : Run) : ctx.nextCallId ≤ (exec ctx r).2.2.nextCallId :=
  exec_loop_callId _ _ _ _

/-- Running a run that has no frames finishes at once, with no commands. -/
theorem exec_no_frames (ctx : ExecCtx) (r : Run) (h : r.frames = []) :
    exec ctx r = (.done r .finished, [], ctx) := by
  unfold exec
  have : STEP_FUEL = 999999 + 1 := rfl
  rw [this, exec_loop_done _ _ _ _ _ _ _ (step_no_frames ctx r h)]
  rfl

end HALean.Automation
