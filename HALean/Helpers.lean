/-
  Service 4: the helper integrations (`input_boolean`, `input_number`,
  `input_select`, `input_text`, `counter`, `timer`), as pure state machines
  driven by their services. `HALean.Helpers.Component` joins them (setup,
  service calls, the timers' callbacks); proofs in `HALean.Helpers.Proofs`.
-/
import HALean.Helpers.Common
import HALean.Helpers.Pattern
import HALean.Helpers.InputBoolean
import HALean.Helpers.InputNumber
import HALean.Helpers.InputSelect
import HALean.Helpers.InputText
import HALean.Helpers.Counter
import HALean.Helpers.Timer
import HALean.Helpers.Component
import HALean.Helpers.Proofs
