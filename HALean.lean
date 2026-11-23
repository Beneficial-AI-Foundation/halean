/-
  HALean: Home Assistant's core, rewritten in Lean one service at a time.

  * `HALean.Core`        – types shared by every service (states, time, JSON)
  * `HALean.Core.EventBus` – the event bus (`EventBus`), proofs in `EventBusProofs`
  * `HALean.Automation`  – service 1: the automation engine
  * `HALean.Template`    – service 2: Jinja templates (used by automations)
-/
import HALean.Core.Types
import HALean.Core.EventBus
import HALean.Core.EventBusProofs
import HALean.Automation
import HALean.Template
