/-
  HALean: Home Assistant's core, rewritten in Lean one service at a time.

  * `HALean.Core`        – types shared by every service (states, time, JSON)
  * `HALean.Automation`  – service 1: the automation engine
  * `HALean.Template`    – service 2: Jinja templates (used by automations)
  * `HALean.Core.StateMachine` – the state machine (`hass.states`)
  * `HALean.Core.ServiceRegistry` – the service registry (`hass.services`)
-/
import HALean.Core.Types
import HALean.Automation
import HALean.Template
import HALean.Core.StateMachine
import HALean.Core.Proofs
import HALean.Core.ServiceRegistry
import HALean.Core.ServiceRegistryProofs
