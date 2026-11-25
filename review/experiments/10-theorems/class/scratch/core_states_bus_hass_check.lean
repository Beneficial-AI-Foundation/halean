import HALean.Core.EventBusProofs
import HALean.Core.HassSchedProofs
import HALean.Core.HassSpec
import HALean.Core.Proofs
import HALean.Core.StateSpec2
open HALean.Core HALean.Core.EventBus
-- duplicate event types on a reachable bus
#eval (run Bus.new [(0, .init [("a", 1), ("a", 1)])]).listeners.map (·.1)
-- reserve of a mixed-case id, then available
#eval match (({} : StateMachine).asyncReserve "Light.X") with
  | .ok sm => (match sm.asyncAvailable "Light.X" with | .ok b => toString b | .error _ => "err")
  | .error _ => "err"
-- get on a non-ASCII id outputs an unsupported entry
#eval (HALean.Core.Hass.step 0 HALean.Core.Hass.Hass.new (.get "é")).2.1.any HALean.Core.Hass.Entry.isUnsupported
-- block_till_done on a new core
#eval match (HALean.Core.Hass.step 0 HALean.Core.Hass.Hass.new .blockTillDone).2.2 with | .ok _ => "ok" | .error _ => "error"
#print axioms HALean.Core.EventBus.unsub_silent
#print axioms HALean.Core.Hass.blockTillDone_no_tasks
#print axioms HALean.Core.Hass.set_delivers_first
#print axioms HALean.Core.validEntityId_iff
#print axioms HALean.Core.StateMachine.set_same_only_reports
#check @HALean.Core.Hass.runHandle_fifo
