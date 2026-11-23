/-
  Small facts about the script service's pure parts.
-/
import HALean.Automation.Engine
open HALean.Automation

namespace HALean.Script

/-- A caller that did not ask for a response gets `None`, whatever the run
returned (`_service_handler` / `ServiceRegistry.async_call`). -/
theorem callResponse_no_response (v : Template.Value) : callResponse false v = .ok .none := by
  simp [callResponse]

/-- A caller that asked for a response gets a dict or an error, never
anything else. -/
theorem callResponse_dict (v r : Template.Value) (h : callResponse true v = .ok r) :
    ∃ kvs, r = .dict kvs := by
  unfold callResponse at h
  simp only [Bool.not_true, Bool.false_eq_true, ↓reduceIte] at h
  generalize (if Template.truthy v = true then v else Template.Value.dict []) = x at h
  cases x with
  | dict kvs => exact ⟨kvs, by simp_all⟩
  | _ => simp_all

/-- `ScriptEntity.is_on`: the entity is `on` exactly while it has runs. -/
theorem entityState_on (n : Nat) : entityState n = "on" ↔ n > 0 := by
  unfold entityState
  split <;> simp_all <;> omega

/-- A run stopped inside a sub-script (`choose`, `if`, `repeat`, `sequence`)
is always cancelled: only top-level waits return on the stop future. -/
theorem stopped_nested_cancels (r : Run) (h : r.frames.length > 1) : stoppedQuietly r = false := by
  unfold stoppedQuietly
  simp
  omega

/-- `max` is an attribute exactly in the modes that support it. -/
theorem supportsMax_iff (m : Mode) : supportsMax m = true ↔ m = .parallel ∨ m = .queued := by
  cases m <;> simp [supportsMax] <;> decide

end HALean.Script
