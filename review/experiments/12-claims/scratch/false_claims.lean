import HALean.Core.EventBusProofs
import HALean.Core.HassSpec
import HALean.Core.StateSpec2
import HALean.Core.ServicesJsonSpec
import HALean.Core.ProbatioSpec
import HALean.Template.ParseTimeSpec
import HALean.Template.RenderSpec2
import HALean.Template.ValueSpec
import HALean.Automation.TimePeriodSpec
open HALean.Core HALean.Template
-- core 2: duplicate event types after init
#eval (EventBus.run EventBus.Bus.new [(0, .init [("a", 1), ("a", 1)])]).listeners.map (·.1)
-- core 3: get on a non-ASCII id outputs an entry
#eval (HALean.Core.Hass.step 0 HALean.Core.Hass.Hass.new (.get "é")).2.1.length
-- registry 3: label of the timedelta branch
#eval (Validator.type .timedelta).label?
-- registry 2: does a float literal have a label
#eval (Validator.literal (.float 1.5)).label?
#eval (Validator.literal (.float (0.0/0.0))).label?
example (f : Float) : ((Validator.literal (.float f)).label?).isSome = true := by
  simp [Validator.label?, pyRepr, Except.toOption, pure, Except.pure]
-- templates 2,3
#eval (parseIntStr (String.mk (List.replicate 4301 '1'))).isSome
#eval parseTimeSeconds (String.mk (List.replicate 4301 '0') ++ "1:00")
-- templates 4
#eval (isNumericStr "١٢", isNumericStr "12\n", isNumericStr "12")
-- automation-other 13
example : ((0 : Float) != 0) = false := by decide
example : ((0 : Float) != 0) = false := by native_decide
example : ((0 : Float) != 0) = false := by rfl
#check @HALean.Template.numEq_int_comm
