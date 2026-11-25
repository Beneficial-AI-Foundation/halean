import HALean.Automation.EngineBound
import HALean.Automation.EngineSpec3
import HALean.Automation.EngineSpec4
import HALean.Automation.ScriptSpec
import HALean.Automation.ProtocolSpec
open HALean.Automation
#print axioms runs_bounded
#print axioms HPres.engine
#print axioms step_init_stateless
#print axioms onEvent_no_match
#print axioms unwindError_haError
#print axioms processLine_cmds
#print axioms exec_no_frames
example : ENGINE_FUEL = 10000 := by rfl
example : LOOP_FUEL ≠ 0 := by decide
#print HALean.Automation.eventDataMatches
#eval (default : Engine).now == ({} : Engine).now
