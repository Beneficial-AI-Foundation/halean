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
import HALean.Template.PyIntSpec
import HALean.Template.ParseTimeSpec
import HALean.Template.SyntaxSpec
import HALean.Template.CvBooleanSpec
import HALean.Automation.SlugifySpec
import HALean.Core.ServiceRegistry
import HALean.Core.ServiceRegistryProofs
import HALean.Core.ServicesJson
import HALean.Core.ProbatioProofs
import HALean.Core.Hass
import HALean.Core.HassProofs
import HALean.Core.HassSchedProofs
import HALean.Script
import HALean.Automation.ConditionSpec
import HALean.Automation.ConfigSpec
import HALean.Automation.EngineSpec
import HALean.Automation.EngineSpec2
import HALean.Automation.EngineSpec3
import HALean.Automation.EngineSpec4
import HALean.Automation.EngineBound
import HALean.Automation.LocationSpec
import HALean.Automation.ProtocolSpec
import HALean.Automation.ScriptSpec
import HALean.Automation.SunSpec
import HALean.Automation.TimePeriodSpec
import HALean.Core.ConfigValidationSpec
import HALean.Core.EventBusSpec2
import HALean.Core.HassSpec
import HALean.Core.ProbatioSpec
import HALean.Core.PyJsonSpec
import HALean.Core.SchemaSpec
import HALean.Core.ServiceRegistrySpec
import HALean.Core.ServicesJsonSpec
import HALean.Core.StateMachineSpec
import HALean.Core.StateSpec2
import HALean.Core.TypesSpec
import HALean.Script.ConfigSpec
import HALean.Script.EntitySpec
import HALean.Script.ProtocolSpec
import HALean.Script.ServiceSpec
import HALean.Template.DateParseSpec
import HALean.Template.RegexSpec
import HALean.Template.RenderSpec
import HALean.Template.RenderSpec2
import HALean.Template.RenderSpec3
import HALean.Template.SyntaxSpec2
import HALean.Template.TimeSpec
import HALean.Template.ValueSpec
