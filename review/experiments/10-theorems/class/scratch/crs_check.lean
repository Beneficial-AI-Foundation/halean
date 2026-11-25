import HALean.Core.SchemaSpec
import HALean.Core.ProbatioProofs
import HALean.Core.ProbatioSpec
import HALean.Core.ServiceRegistrySpec
import HALean.Core.ConfigValidationSpec
import HALean.Core.ServicesJsonSpec
import HALean.Core.PyJsonSpec
open HALean.Core HALean.Template
#print axioms HALean.Core.checkIn_ok_iff
#print axioms HALean.Core.SchemaLemmas.validate_ok_iff
#print axioms HALean.Core.call_after_remove_not_found
#print axioms HALean.Core.ConfigValidationSpec.cvColorHex_ok
#print axioms HALean.Core.ProbatioSpec.checkLength_ok_iff
#print axioms HALean.Core.ServicesJsonSpec.contextJson_injective
#print HALean.Template.pyEq
#print HALean.Core.safeValue
#print HALean.Core.Validator.run
example : pyEq (.bool true) (.int 1) = true := by rfl
example : pyEq (.bool true) (.int 1) = true := by decide
example : safeValue (.str "a") = true := by rfl
example : safeValue (.str "a") = true := by decide
example : (Validator.type .int).run .prevent (.int 1) = .ok (.int 1) := by rfl
example : checkIn [.int 1] (.int 1) = .ok (.int 1) := by rfl
example : (SchemaSpec.validate {fields := []} []) = .ok [] := by rfl
example : cvString (.int 1) = .ok (.str "1") := by rfl
example : strOf (.int 1) = .ok "1" := by decide
