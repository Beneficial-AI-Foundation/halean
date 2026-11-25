import HALean.Automation.TimePeriodSpec
import HALean.Automation.LocationSpec
import HALean.Automation.SunSpec
open HALean.Automation
theorem f0 : ((0 : Float) != 0) = false := by decide
theorem f1 : (0.0 : Float) * 1000 = 0.0 := by rfl
theorem f2 : ¬ ((0.0:Float) > 0.0) := by decide
theorem f3 : ((2.5 : Float) + 0.25 == 2.75) = true := by decide
theorem f4 : (HALean.Automation.radians 180.0 == 3.141592653589793) = true := by decide
theorem f5 (l : List (Nat × Int)) (us : Int) := timedeltaNew_ints l (by decide) us
theorem f6 : distance 1.0 2.0 1.0 2.0 = some 0.0 := by
  rw [distance_coincident 1.0 2.0 1.0 2.0 (by decide)]; rfl
theorem f7 : Sun.adjustToHorizon 0.0 = 0 := Sun.adjustToHorizon_nonpos 0.0 (by decide)
theorem f8 : ((1.0:Float) / 3.0 < 0.34) = true := by decide
#print axioms f0
#print axioms f1
#print axioms f3
#print axioms f4
#print axioms f5
#print axioms f6
#print axioms f8
#print Float.cos
#print Float.tan
#print Float.atan
#print Float.atan2
#print Float.acos
#print Float.asin
#print Float.ceil
#print Float.abs
#print Float.isInf
#print Float.toUInt64
#print Float.div
#print Float.sub
example : (Lean.Json.num 1 == Lean.Json.null) = false := by decide
example : (Lean.Json.num 1 == Lean.Json.null) = false := by rfl
example : (Float.floor 1.5 == 1.0) = true := by decide
