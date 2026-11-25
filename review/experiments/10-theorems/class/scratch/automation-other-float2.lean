import HALean.Automation.TimePeriodSpec
import HALean.Automation.LocationSpec
import HALean.Automation.SunSpec
open HALean.Automation
theorem g5 (l : List (Nat × Int)) (us : Int) :
    timedeltaNew (l.map fun p => (p.1, TdArg.int p.2)) = .ok us ↔
      us = (l.map fun p => p.2 * (p.1 : Int)).sum ∧ InTimedeltaRange us := timedeltaNew_ints l (by decide) us
theorem g6 : distance 1.0 2.0 1.0 2.0 = some 0.0 := by
  rw [distance_coincident 1.0 2.0 1.0 2.0 (by decide)]; rfl
theorem g7 : Sun.adjustToHorizon 0.0 = 0 := Sun.adjustToHorizon_nonpos 0.0 (by decide)
theorem g8 : ¬ ((90 : Float) - (90.0 + Sun.SUN_APPARENT_RADIUS) ≥ 85.0) := by decide
theorem g9 : cvTimePeriod (.int 5) = .ok 5000000 := by decide
#print axioms g5
#print axioms g6
#print axioms g7
#print axioms g8
