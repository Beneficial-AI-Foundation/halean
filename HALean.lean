/-
  HALean: Home Assistant's core, rewritten in Lean one service at a time.

  * `HALean.Core`        – types shared by every service (states, time, JSON)
  * `HALean.Core.EventBus` – the event bus (`EventBus`), proofs in `EventBusProofs`
  * `HALean.Automation`  – service 1: the automation engine
  * `HALean.Template`    – service 2: Jinja templates (used by automations)
  * `HALean.Core.StateMachine` – the state machine (`hass.states`)
  * `HALean.Core.ServiceRegistry` – the service registry (`hass.services`)
  * `HALean.Core.Hass` – the joined core: states, bus, services and the event
    loop's tasks together, proofs in `HassProofs` and `HassSchedProofs`
  * `HALean.Script`      – service 3: scripts (`script.*` entities and services)
-/
import HALean.Core.Types
import HALean.Core.EventBus
import HALean.Core.EventBusProofs
import HALean.Automation
import HALean.Template
import HALean.Core.StateMachine
import HALean.Core.Proofs
import HALean.Core.StateSpec
import HALean.Core.ServiceRegistry
import HALean.Core.ServiceRegistryProofs
import HALean.Core.ProbatioProofs
import HALean.Core.Hass
import HALean.Core.HassProofs
import HALean.Core.HassSchedProofs
import HALean.Script
