# Claims in `manifest.yaml`: the 349 `translated` entries

Reviewed commit f638a37. Scope: every entry with `status: translated`. The 53 `proven` entries are another reviewer's.
`M-<n>` is the position of the entry in `manifest.yaml` (1 to 402), so the ids of the two reviews do not collide.
Paths: `up:` is `upstream/ha-core/homeassistant/`; `logs-manifest/` is `review/experiments/12-claims/logs-manifest/`;
`sbs NN` is `review/experiments/NN-*/side-by-side.md`; finding ids (`AUT-6`, `TPL-18`, ...) are those of `review/experiments/NN-*/FINDINGS.md`
(`SCR-n` ids are in `08-scripts/side-by-side.md`; that directory had no `FINDINGS.md` when this was written).

## What was checked, and how

* (a) Structure, by script (`probes-manifest/structure.py`, `overload_stubs.py`): every `python:` ref resolves with the drift tool's `find_node` logic
  (0 missing, 0 stale: `logs-manifest/overload-stubs.log`, `logs-manifest/drift-check.log`); every `lean:` name was looked up in
  `10-theorems/logs/defs.tsv` and in the Lean sources.
* (b) Notes: each note was checked against the Lean source lines cited or, where the evidence column says `sbs NN`, against that reviewer's comparison row. Where a note states a concrete behaviour, a probe of a shipped executable
  or of real Python was run (`logs-manifest/probe-*.log`, `py-direct.log`, `probe-ha.log`). The evidence column says which.
* (c) Status: `translated` was judged against the upstream function body.

How the evidence column reads: `upstream lines; first Lean declaration; method`. Methods:
`read: Lean and upstream` = both sides read for this review; `read: Lean; upstream by sbs NN` = the Lean file was read here, the upstream side is taken from
that reviewer's comparison row; `sbs NN` = both sides taken from that comparison, plus the probes named.

Verdict rules used:

* `stale`: true of an earlier commit (a Lean name since removed; a note about behaviour since changed). The commit is named.
* `false`: a statement in the note is contradicted by the code or by a probe.
* `overstated`: the note states a behaviour that holds only for part of the inputs (a probe or a finding of an area review shows the rest),
  or the Lean definition covers a part of the upstream function and the note does not say so.
* `correct for the wrong reason`: the entry checks out, but its hash watches an `@overload` stub, not the implementation.
* `correct`: none of the above. A divergence found by an area review does not by itself change `correct`;
  it does when it concerns the very thing the note asserts. Such findings are cited in the evidence column either way.

Limits. `HALean/Automation/{Condition,Config,Script,Engine}.lean` and `HALean/Script/{Entity,Service}.lean` were read in full; `HALean/Template/Render.lean`,
`HALean/Core/Hass.lean` and the helper files were read only at the lines cited. For entries without a note in the template, core, schema and helper areas the
verdict rests on the structure checks and on the area reviewer's comparison row. M-167 (vincenty) and M-50 (paho matcher) were not compared with the libraries themselves.
Probes are deterministic; `probes-manifest/rerun_manifest.sh` runs each twice and compares (`logs-manifest/two-runs.log`).

## Counts

| verdict | with notes | without notes | total |
|---|---|---|---|
| correct | 178 | 138 | 316 |
| correct for the wrong reason | 2 | 1 | 3 |
| overstated | 17 | 1 | 18 |
| false | 2 | 0 | 2 |
| stale | 7 | 3 | 10 |
| all | 206 | 143 | 349 |

## All entries

| id | python ref | lean names | verdict | evidence |
|---|---|---|---|---|
| M-5 | `helpers/condition.py::state` | `Automation.stateOne`, `Automation.isInputEntityId` | correct | up:helpers/condition.py:1870-1941; HALean/Automation/Condition.lean:124; read: Lean and upstream. Note: Condition.lean:145-152, up:helpers/condition.py:1930; logs-manifest/probe-automation.log [M-5]. Known divergences in the same function: AUT-3, AUT-4 |
| M-6 | `helpers/config_validation.py::STATE_CONDITION_SCHEMA` | `Automation.decodeCondition` (partial) | correct | up:helpers/config_validation.py:1542-1568; HALean/Automation/Config.lean:474; read: Lean; upstream by sbs 07. Note: Config.lean:500-507, up:helpers/config_validation.py:1551-1567; logs-manifest/probe-automation.log [M-6]. The two schema objects the function calls are not enforced (AUT-14) |
| M-7 | `helpers/condition.py::async_numeric_state` | `Automation.numericStateOf`, `Automation.numericStateOne`, `Automation.resolveBound` | correct | up:helpers/condition.py:1698-1821; HALean/Automation/Condition.lean:180; read: Lean and upstream. Note: Condition.lean:194-201, up:helpers/condition.py:1733-1748. Number parsing differs (AUT-12) |
| M-8 | `helpers/condition.py::time` | `Automation.timeCond`, `Automation.resolveTimeBound` | overstated | up:helpers/condition.py:2034-2130; HALean/Automation/Condition.lean:260; read: Lean and upstream. a date-only sensor state is not reported as unsupported: the condition is silently false, HA says true. See below |
| M-9 | `helpers/condition.py::state_from_config` | `Automation.entityLoop`, `Automation.evalCond` | correct | up:helpers/condition.py:1944-1992; HALean/Automation/Condition.lean:283; read: Lean and upstream |
| M-10 | `helpers/condition.py::async_numeric_state_from_config` | `Automation.entityLoop`, `Automation.evalCond` | correct | up:helpers/condition.py:1824-1867; HALean/Automation/Condition.lean:283; read: Lean and upstream |
| M-11 | `helpers/condition.py::async_trigger_from_config` | `Automation.evalCond` | correct | up:helpers/condition.py:2146-2160; HALean/Automation/Condition.lean:347; read: Lean and upstream |
| M-12 | `helpers/condition.py::async_from_config` | `Automation.decodeCondition` (partial) | correct | up:helpers/condition.py:1507-1569; HALean/Automation/Config.lean:474; read: Lean and upstream. Note: Config.lean:361-381, 475-543; logs-manifest/probe-automation.log [M-12] |
| M-15 | `helpers/script.py::_ScriptRun.async_run` | `Automation.exec`, `Automation.conditionFail`, `Automation.finishRun`, `Automation.finishBranch` (missing) | stale | up:helpers/script.py:496-549; HALean/Automation/Script.lean:476; read: Lean and upstream. `HALean.Automation.finishBranch` does not exist; removed in bf053c0. See below |
| M-16 | `helpers/script.py::_ScriptRun._async_step` | `Automation.step` | correct | up:helpers/script.py:551-595; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Config.lean:1001, 361-381, up:helpers/script.py:561-571; logs-manifest/probe-automation.log [M-16]. continue_on_error read as a literal only (AUT-7) |
| M-17 | `helpers/script.py::_ScriptRun._handle_exception` | `Automation.unwindError`, `Automation.resumeService` | overstated | up:helpers/script.py:614-641; HALean/Automation/Script.lean:206; read: Lean and upstream. ServiceNotFound is treated as an error `continue_on_error` may swallow; upstream never swallows it. See below |
| M-18 | `helpers/script.py::_ScriptRun._async_run_script` | `Automation.step`, `Automation.drive` | correct | up:helpers/script.py:690-707; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:300-308, 378 (push of a `seq` frame) |
| M-19 | `helpers/script.py::_ScriptRun._async_step_choose` | `Automation.step` | correct | up:helpers/script.py:776-799; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-20 | `helpers/script.py::_ScriptRun._async_step_condition` | `Automation.step` | correct | up:helpers/script.py:801-824; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-21 | `helpers/script.py::_ScriptRun._async_step_if` | `Automation.step` | correct | up:helpers/script.py:826-845; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-22 | `helpers/script.py::_ScriptRun._async_do_step_repeat` | `Automation.step`, `Automation.REPEAT_TERMINATE_ITERATIONS` | overstated | up:helpers/script.py:847-1006; HALean/Automation/Script.lean:218; read: Lean and upstream. a float `count` and an assignment to `repeat` are not handled as upstream (AUT-6, AUT-8). See below |
| M-23 | `helpers/script.py::_ScriptRun._async_step_stop` | `Automation.step` | correct | up:helpers/script.py:1019-1039; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:362-366, up:helpers/script.py:1029-1036; logs-manifest/probe-automation.log [M-23] |
| M-24 | `helpers/script.py::_ScriptRun._async_step_call_service` | `Automation.step`, `Automation.resumeService` | correct | up:helpers/script.py:1052-1103; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:276-279, bridge/bridge.py:87-90, 241-252 |
| M-25 | `helpers/script.py::_ScriptRun._async_step_event` | `Automation.step` | correct | up:helpers/script.py:1112-1132; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:368-377, up:helpers/script.py:1116-1128; logs-manifest/probe-automation.log [M-25] |
| M-26 | `helpers/script.py::_ScriptRun._async_step_delay` | `Automation.step`, `Automation.fireDue` | correct | up:helpers/script.py:1209-1233; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:283-290, up:helpers/script.py:1194-1211; logs-manifest/probe-automation.log [M-26]. Static delays use another parser (AUT-15) |
| M-27 | `helpers/script.py::_ScriptRun._async_step_sequence` | `Automation.step` | correct | up:helpers/script.py:733-736; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-29 | `helpers/script.py::_QueuedScriptRun.async_run` | `Automation.triggerAutomation`, `Automation.finishRun` | correct | up:helpers/script.py:1398-1412; HALean/Automation/Engine.lean:963; read: Lean and upstream |
| M-30 | `helpers/script.py::_QueuedScriptRun._finish` | `Automation.finishRun` | correct | up:helpers/script.py:1415-1419; HALean/Automation/Engine.lean:933; read: Lean and upstream |
| M-32 | `helpers/event.py::async_track_same_state` | `Automation.PendingFor`, `Automation.sameStillHolds`, `Automation.fireDue` | correct | up:helpers/event.py:1353-1413; HALean/Automation/Engine.lean:147; read: Lean; upstream by sbs 07 |
| M-33 | `components/homeassistant/triggers/state.py::async_attach_trigger` | `Automation.addPeriodPending`, `Automation.decodeTrigger`, `Automation.onStateTrigger`, `Automation.renderPeriod` | stale | up:components/homeassistant/triggers/state.py:97-248; HALean/Automation/Engine.lean:1086; read: Lean; upstream by sbs 07. note says "templated 'for' rejected"; a templated `for` loads and runs. See below |
| M-34 | `components/homeassistant/triggers/numeric_state.py::async_attach_trigger` | `Automation.addPeriodPending`, `Automation.initArmed`, `Automation.onNumericTrigger`, `Automation.renderPeriod` | correct | up:components/homeassistant/triggers/numeric_state.py:96-241; HALean/Automation/Engine.lean:1086; read: Lean; upstream by sbs 07. Note: Engine.lean:74-78, 1136, up:components/homeassistant/triggers/numeric_state.py:119-130, 210-211; logs-manifest/probe-automation.log [M-34] |
| M-35 | `components/homeassistant/triggers/time.py::async_attach_trigger` | `Automation.fireTimeTriggers`, `Automation.decodeTrigger`, `Automation.attachTriggers`, `Automation.updateTimeEntity`, `Automation.fireTimePoints`, `Automation.onStateChanged` | correct | up:components/homeassistant/triggers/time.py:101-314; HALean/Automation/Engine.lean:1589; read: Lean; upstream by sbs 07. Note: Config.lean:751-770, Engine.lean:380-438, up:components/homeassistant/triggers/time.py:261; logs-manifest/probe-automation.log [M-35]. AUT-5, AUT-9 |
| M-36 | `components/homeassistant/triggers/time_pattern.py::async_attach_trigger` | `Automation.fireTimeTriggers`, `Automation.Pattern.matches`, `Automation.decodeTrigger` | correct | up:components/homeassistant/triggers/time_pattern.py:66-102; HALean/Automation/Engine.lean:1589; read: Lean; upstream by sbs 07 |
| M-37 | `components/homeassistant/triggers/event.py::async_attach_trigger` | `Automation.onEvent` | correct | up:components/homeassistant/triggers/event.py:116-249; HALean/Automation/Engine.lean:1418; read: Lean; upstream by sbs 07. Note: Config.lean:808-853, Engine.lean:1410-1415, up:components/homeassistant/triggers/event.py:128-166; logs-manifest/probe-automation.log [M-37]. AUT-5 |
| M-38 | `components/homeassistant/triggers/homeassistant.py::async_attach_trigger` | `Automation.attachTriggers`, `Automation.onEvent` | correct | up:components/homeassistant/triggers/homeassistant.py:24-75; HALean/Automation/Engine.lean:444; read: Lean and upstream. Note: Config.lean:884-889, Engine.lean:472-474, 1433-1442, up:components/homeassistant/triggers/homeassistant.py:34-71; logs-manifest/probe-automation.log [M-38] |
| M-39 | `components/tag/trigger.py::async_attach_trigger` | `Automation.onEvent` | correct | up:components/tag/trigger.py:22-72; HALean/Automation/Engine.lean:1418; read: Lean and upstream. Note: Engine.lean:1443-1452, up:components/tag/trigger.py:30-45; logs-manifest/probe-automation.log [M-39] |
| M-40 | `components/mqtt/trigger.py::async_attach_trigger` | `Automation.decodeTrigger`, `Automation.onMqtt`, `Automation.mqttPayloadMatches`, `Automation.mqttTriggerVars` | correct | up:components/mqtt/trigger.py:59-120; HALean/Automation/Config.lean:709; read: Lean and upstream. Note: Config.lean:905-963, Engine.lean:1497-1502, up:components/mqtt/trigger.py:80-84; logs-manifest/probe-automation.log [M-40..M-50] |
| M-41 | `components/mqtt/util.py::valid_topic` | `Automation.mqttValidTopic` | correct | up:components/mqtt/util.py:240-279; HALean/Automation/Config.lean:626; read: Lean and upstream |
| M-42 | `components/mqtt/util.py::valid_subscribe_topic` | `Automation.mqttValidSubscribeTopic` | correct | up:components/mqtt/util.py:283-307; HALean/Automation/Config.lean:639; read: Lean and upstream |
| M-43 | `components/mqtt/util.py::valid_subscribe_topic_template` | `Automation.decodeTrigger` | correct | up:components/mqtt/util.py:310-317; HALean/Automation/Config.lean:709; read: Lean and upstream. Note: Config.lean:909-921, up:components/mqtt/util.py:310-317; logs-manifest/probe-automation.log [M-40..M-50] (badtopic, badtmpltopic) |
| M-44 | `components/mqtt/models.py::MqttCommandTemplate.async_render` | `Automation.decodeTrigger` | correct | up:components/mqtt/models.py:255-291; HALean/Automation/Config.lean:709; read: Lean and upstream. Note: Config.lean:925-941, up:components/mqtt/models.py:255-291; logs-manifest/probe-automation.log [M-40..M-50] (payload 'x' when value is none) |
| M-45 | `components/mqtt/models.py::convert_outgoing_mqtt_payload` | `Automation.decodeTrigger` | correct | up:components/mqtt/models.py:119-132; HALean/Automation/Config.lean:709; read: Lean and upstream. Note: Config.lean:944-945, up:components/mqtt/models.py:119-132; logs-manifest/probe-automation.log [M-40..M-50] (bytes) |
| M-46 | `components/mqtt/models.py::MqttValueTemplate.async_render_with_possible_json_value` | `Automation.mqttPayloadMatches` | correct | up:components/mqtt/models.py:348-424; HALean/Automation/Engine.lean:1483; read: Lean and upstream. Note: Engine.lean:1483-1494, up:components/mqtt/models.py:348-424, helpers/template/__init__.py:630-640; logs-manifest/probe-automation.log [M-40..M-50] (not json) |
| M-47 | `helpers/template/__init__.py::Template.async_render_with_possible_json_value` | `Automation.mqttPayloadMatches`, `Core.orjsonLoads` | correct | up:helpers/template/__init__.py:602-648; HALean/Automation/Engine.lean:1483; read: Lean; upstream by sbs 07. Note: Engine.lean:1516, 1490-1493, up:helpers/template/__init__.py:614-626; logs-manifest/probe-automation.log [M-40..M-50] (vt) |
| M-48 | `components/mqtt/client.py::MQTT._async_mqtt_on_message` | `Automation.onMqtt` | correct | up:components/mqtt/client.py:1306-1400; HALean/Automation/Engine.lean:1509; read: Lean and upstream. Note: Engine.lean:1509-1529, up:components/mqtt/client.py:1361-1367; logs-manifest/probe-automation.log [M-40..M-50] (second retained message) |
| M-49 | `components/mqtt/client.py::MQTT._matching_subscriptions` | `Automation.onMqtt` | correct | up:components/mqtt/client.py:1285-1303; HALean/Automation/Engine.lean:1509; read: Lean and upstream. Note: Engine.lean:1513-1517, up:components/mqtt/client.py:490, 1285-1303; logs-manifest/probe-automation.log [M-40..M-50] (simple before wild) |
| M-50 | `components/mqtt/client.py::_matcher_for_topic` | `Automation.mqttTopicMatches`, `Automation.mqttLevelsMatch` | correct | up:components/mqtt/client.py:1536-1540; HALean/Automation/Engine.lean:1474; read: Lean and upstream. Note: Engine.lean:1460-1475; logs-manifest/probe-automation.log [M-40..M-50] ($SYS/b). paho is not installed in the venv: not compared with paho itself |
| M-51 | `components/webhook/trigger.py::async_attach_trigger` | `Automation.decodeTrigger`, `Automation.onWebhook` | correct | up:components/webhook/trigger.py:81-126; HALean/Automation/Config.lean:709; read: Lean and upstream. Note: Config.lean:964-980, Engine.lean:1541-1554, up:components/webhook/trigger.py:91-114; logs-manifest/probe-automation.log [M-51..M-54] |
| M-52 | `components/webhook/trigger.py::_handle_webhook` | `Automation.onWebhook`, `Automation.multiDictValue` | correct | up:components/webhook/trigger.py:57-78; HALean/Automation/Engine.lean:1541; read: Lean and upstream. Note: Engine.lean:1534-1567, up:components/webhook/trigger.py:57-78; logs-manifest/probe-automation.log [M-51..M-54] |
| M-53 | `components/webhook/__init__.py::async_handle_webhook` | `Automation.onWebhook` | correct | up:components/webhook/__init__.py:140-216; HALean/Automation/Engine.lean:1541; read: Lean and upstream. Note: Engine.lean:1545-1563, up:components/webhook/__init__.py:163-216; logs-manifest/probe-automation.log [M-51..M-54] |
| M-54 | `components/webhook/__init__.py::async_register` | `Automation.onWebhook` | correct | up:components/webhook/__init__.py:54-93; HALean/Automation/Engine.lean:1541; read: Lean and upstream. Note: a statement about the model (Engine.lean:1542-1545 looks at triggers only); up:components/webhook/__init__.py:54-93 raises ValueError for a taken id |
| M-55 | `components/automation/__init__.py::AutomationEntity.async_trigger` | `Automation.thisValue`, `Automation.triggerAutomation` | correct | up:components/automation/__init__.py:681-822; HALean/Automation/Engine.lean:945; read: Lean; upstream by sbs 07. Note: Engine.lean:963-1008; logs-manifest/probe-automation.log [M-55]. AUT-1, AUT-13 |
| M-56 | `helpers/template/__init__.py::Template.__init__` | `Template.compile` | overstated | up:helpers/template/__init__.py:354-369; HALean/Template/Syntax.lean:621; sbs 06. the strip is ASCII-only (TPL-18). See below |
| M-57 | `helpers/template/__init__.py::Template.async_render` | `Template.render`, `Template.renderString` | correct | up:helpers/template/__init__.py:435-479; HALean/Template/Render.lean:2168; sbs 06. Note: logs-manifest/probe-template.log [M-57]; sbs 06 row `Template.async_render` |
| M-58 | `helpers/template/__init__.py::_parse_result` | `Template.parseResult`, `Template.isNumericStr` | correct | up:helpers/template/__init__.py:244-264; HALean/Template/Render.lean:2134; sbs 06. Note: logs-manifest/probe-template.log [M-58]. TPL-17, TPL-32 |
| M-59 | `helpers/template/__init__.py::_cached_parse_result` | `Template.parseResult`, `Template.literalEval` | overstated | up:helpers/template/__init__.py:268-301; HALean/Template/Render.lean:2134; sbs 06. string escapes, duplicate dict keys, `set()`, `...` and nested signs differ from `ast.literal_eval` (TPL-1, TPL-2, TPL-28, TPL-29). See below |
| M-60 | `helpers/template/__init__.py::render_complex` | `Automation.renderComplex` (partial) | correct | up:helpers/template/__init__.py:141-162; HALean/Automation/Condition.lean:55; read: Lean; upstream by sbs 07. Note: Condition.lean:55-74, up:helpers/template/__init__.py:141-162 |
| M-62 | `helpers/template/states.py::AllStates.__getattr__` | `Template.getattrV` | correct | up:helpers/template/states.py:112-123; HALean/Template/Render.lean:299; sbs 06 |
| M-63 | `helpers/template/states.py::AllStates.__call__` | `Template.callV` (partial) | correct | up:helpers/template/states.py:147-161; HALean/Template/Render.lean:1307; sbs 06. Note: logs-manifest/probe-template.log [M-63] (a render error, not a load error; TPL-41) |
| M-64 | `helpers/template/states.py::DomainStates.__getattr__` | `Template.getattrV` | correct | up:helpers/template/states.py:256-258; HALean/Template/Render.lean:299; sbs 06 |
| M-65 | `helpers/template/states.py::TemplateStateBase.__getitem__` | `Template.stateAttr` | stale | up:helpers/template/states.py:321-336; HALean/Template/Render.lean:258; sbs 06. note says last_changed/last_updated are render errors; they render. See below |
| M-66 | `helpers/template/states.py::_get_state_if_valid` | `Template.stateIfValid` | correct | up:helpers/template/states.py:515-519; HALean/Template/Render.lean:281; sbs 06 |
| M-67 | `helpers/template/extensions/state.py::StateExtension.is_state` | `Template.isState` | correct | up:helpers/template/extensions/state.py:323-329; HALean/Template/Render.lean:830; sbs 06 |
| M-68 | `helpers/template/extensions/state.py::StateExtension.is_state_attr` | `Template.callV` (partial) | correct | up:helpers/template/extensions/state.py:331-338; HALean/Template/Render.lean:1307; sbs 06 |
| M-69 | `helpers/template/extensions/state.py::StateExtension.state_attr` | `Template.stateAttrFn` | correct | up:helpers/template/extensions/state.py:340-344; HALean/Template/Render.lean:840; sbs 06 |
| M-70 | `helpers/template/extensions/state.py::StateExtension.has_value` | `Template.hasValue` | correct | up:helpers/template/extensions/state.py:346-352; HALean/Template/Render.lean:848; sbs 06 |
| M-71 | `helpers/template/extensions/type_cast.py::TypeCastExtension.forgiving_float` | `Template.forgivingFloat` | correct | up:helpers/template/extensions/type_cast.py:60-67; HALean/Template/Render.lean:858; sbs 06 |
| M-72 | `helpers/template/extensions/type_cast.py::TypeCastExtension.forgiving_int` | `Template.forgivingInt`, `Template.doInt` | correct | up:helpers/template/extensions/type_cast.py:70-75; HALean/Template/Render.lean:866; sbs 06. Note: logs-manifest/probe-template.log [M-72] (a render error; TPL-41) |
| M-73 | `helpers/template/extensions/type_cast.py::TypeCastExtension.is_number` | `Template.isNumber` | correct | up:helpers/template/extensions/type_cast.py:78-86; HALean/Template/Render.lean:886; sbs 06 |
| M-74 | `helpers/template/extensions/math.py::MathExtension.forgiving_round` | `Template.forgivingRound`, `Template.pyRound` | correct | up:helpers/template/extensions/math.py:363-386; HALean/Template/Render.lean:892; sbs 06. Note: logs-manifest/probe-template.log [M-74]; sbs 06 row `forgiving_round` |
| M-75 | `helpers/template/extensions/functional.py::FunctionalExtension.iif` | `Template.iif` | correct | up:helpers/template/extensions/functional.py:125-144; HALean/Template/Render.lean:920; sbs 06 |
| M-76 | `helpers/template/helpers.py::forgiving_boolean` | `Template.forgivingBool`, `Template.cvBoolean` | correct for the wrong reason | up:helpers/template/helpers.py:73-73; HALean/Template/Render.lean:877; sbs 06. the ref resolves to an `@overload` stub; the hash does not watch the implementation. See below |
| M-77 | `helpers/template/helpers.py::result_as_boolean` | `Template.resultAsBoolean` | correct | up:helpers/template/helpers.py:92-102; HALean/Template/Render.lean:200; sbs 06 |
| M-78 | `helpers/condition.py::async_template` | `Automation.templateCond` | correct | up:helpers/condition.py:2004-2020; HALean/Automation/Condition.lean:47; read: Lean and upstream. Note: Condition.lean:47-51, up:helpers/condition.py:2004-2020; logs-manifest/probe-template.log [M-78] |
| M-79 | `helpers/condition.py::async_template_from_config` | `Automation.evalCond` | correct | up:helpers/condition.py:2023-2031; HALean/Automation/Condition.lean:347; read: Lean and upstream |
| M-80 | `helpers/service.py::async_prepare_call_from_config` | `Automation.step`, `Automation.normalizeTarget` | overstated | up:helpers/service.py:260-347; HALean/Automation/Script.lean:218; read: Lean; upstream by sbs 07. a static target's `entity_id` is passed on as written; upstream normalises and validates it. See below |
| M-81 | `helpers/config_validation.py::service` | `Automation.decodeAction` (partial) | correct | up:helpers/config_validation.py:592-599; HALean/Automation/Config.lean:1000; read: Lean; upstream by sbs 07. Note: Config.lean:1019-1029, Script.lean:239-253, up:helpers/config_validation.py:592-599; logs-manifest/probe-automation.log [M-81/M-82] |
| M-82 | `helpers/config_validation.py::_backward_compat_service_schema` | `Automation.decodeAction` (partial) | correct | up:helpers/config_validation.py:1440-1454; HALean/Automation/Config.lean:1000; read: Lean; upstream by sbs 07. Note: Config.lean:1011-1016, up:helpers/config_validation.py:1440-1454; logs-manifest/probe-automation.log [M-81/M-82] |
| M-83 | `helpers/config_validation.py::template_complex` | `Automation.decodeComplex` (partial) | correct | up:helpers/config_validation.py:728-743; HALean/Automation/Config.lean:384; read: Lean; upstream by sbs 07 |
| M-87 | `components/template/trigger.py::async_attach_trigger` | `Automation.onTemplateTrigger`, `Automation.initArmed` | stale | up:components/template/trigger.py:41-167; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07. note says "static for: only" and "trigger_variables unsupported"; both are supported. See below |
| M-88 | `helpers/event.py::TrackTemplateResultInfo._render_template_if_ready` | `Automation.onTemplateTrigger`, `Automation.templateRefresh` | correct | up:helpers/event.py:1098-1160; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07. Note: Engine.lean:135-140, 1250-1278; not read line by line against up:helpers/event.py:1098-1160 (sbs 07 says the same) |
| M-89 | `helpers/template/states.py::_state_generator` | `Template.statesOf` | correct | up:helpers/template/states.py:493-512; HALean/Template/Render.lean:420; sbs 06. Note: sbs 06 row `_state_generator` (cases st_domain_order_insertion, st_all_order) |
| M-90 | `helpers/template/states.py::DomainStates.__iter__` | `Template.iterV` | correct | up:helpers/template/states.py:276-279; HALean/Template/Render.lean:426; sbs 06 |
| M-91 | `helpers/template/states.py::AllStates.__iter__` | `Template.iterV` | correct | up:helpers/template/states.py:137-140; HALean/Template/Render.lean:426; sbs 06 |
| M-92 | `helpers/template/states.py::AllStates.__len__` | `Template.lenV` | correct | up:helpers/template/states.py:142-145; HALean/Template/Render.lean:440; sbs 06 |
| M-93 | `helpers/script_variables.py::ScriptVariables.async_render` | `Automation.renderVariables` | correct | up:helpers/script_variables.py:22-59; HALean/Automation/Condition.lean:86; read: Lean; upstream by sbs 07. Note: Condition.lean:86-92, Config.lean:1222-1226; logs-manifest/probe-automation.log [M-93/M-97] |
| M-94 | `helpers/script_variables.py::ScriptVariables.async_simple_render` | `Automation.step` | correct | up:helpers/script_variables.py:62-83; HALean/Automation/Script.lean:218; read: Lean; upstream by sbs 07. Note: Script.lean:342-351 |
| M-95 | `helpers/script_variables.py::ScriptRunVariables._assign` | `Automation.setVar` | overstated | up:helpers/script_variables.py:212-238; HALean/Automation/Condition.lean:40; read: Lean; upstream by sbs 07. an assignment to `repeat` inside a loop should hit the local variable (AUT-8). See below |
| M-96 | `helpers/script.py::_ScriptRun._async_step_variables` | `Automation.step` | correct | up:helpers/script.py:1043-1048; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:352-355, up:helpers/script.py:140-147; logs-manifest/probe-automation.log [M-96] |
| M-97 | `components/automation/__init__.py::AutomationEntity._async_attach_triggers` | `Automation.tmplCtxOf` | correct | up:components/automation/__init__.py:951-977; HALean/Automation/Engine.lean:271; read: Lean; upstream by sbs 07. Note: Config.lean:1212-1221, 576-586, Engine.lean:271-275; logs-manifest/probe-automation.log [M-93/M-97] |
| M-98 | `helpers/template/extensions/datetime.py::DateTimeExtension.now` | `Template.callV` (partial) | correct | up:helpers/template/extensions/datetime.py:235-240; HALean/Template/Render.lean:1307; sbs 06. Note: Engine.lean:1613-1617; logs-manifest/probe-template.log [M-98] |
| M-99 | `helpers/template/extensions/datetime.py::DateTimeExtension.utcnow` | `Template.callV` (partial) | correct | up:helpers/template/extensions/datetime.py:242-247; HALean/Template/Render.lean:1307; sbs 06 |
| M-100 | `helpers/template/extensions/datetime.py::DateTimeExtension.today_at` | `Template.callV` (partial), `Template.parseTime` | correct | up:helpers/template/extensions/datetime.py:249-263; HALean/Template/Render.lean:1307; sbs 06 |
| M-101 | `helpers/template/extensions/datetime.py::DateTimeExtension.as_timestamp` | `Template.callV` (partial), `Template.timestampOf` | correct | up:helpers/template/extensions/datetime.py:180-187; HALean/Template/Render.lean:1307; sbs 06. Note: logs-manifest/probe-template.log [M-101]. TPL-42, TPL-43 |
| M-102 | `helpers/template/extensions/datetime.py::DateTimeExtension.as_datetime` | `Template.callV` (partial), `Template.utcFromTimestamp` | correct | up:helpers/template/extensions/datetime.py:189-212; HALean/Template/Render.lean:1307; sbs 06 |
| M-103 | `helpers/template/extensions/datetime.py::DateTimeExtension.as_local` | `Template.asLocal` | correct | up:helpers/template/extensions/datetime.py:227-229; HALean/Template/Render.lean:504; sbs 06. Note: logs-manifest/probe-template.log [M-103]. TPL-25 |
| M-104 | `helpers/template/extensions/datetime.py::DateTimeExtension.timestamp_custom` | `Template.callV` (partial), `Template.strftime` (partial) | overstated | up:helpers/template/extensions/datetime.py:139-158; HALean/Template/Render.lean:1307; sbs 06. CPython's `strftime` is not glibc's for years below 1000 (TPL-24); the default format is wrong (TPL-22). See below |
| M-105 | `helpers/template/extensions/datetime.py::DateTimeExtension.timestamp_local` | `Template.callV` (partial) | correct | up:helpers/template/extensions/datetime.py:160-168; HALean/Template/Render.lean:1307; sbs 06 |
| M-106 | `helpers/template/extensions/datetime.py::DateTimeExtension.timestamp_utc` | `Template.callV` (partial) | correct | up:helpers/template/extensions/datetime.py:170-178; HALean/Template/Render.lean:1307; sbs 06 |
| M-107 | `util/dt.py::parse_datetime` | `Template.parseDatetime` | overstated | up:util/dt.py:207-207; HALean/Template/Render.lean:515; sbs 06. `T24:00:00` gives None, not an error (TPL-23); the ref resolves to an `@overload` stub. See below |
| M-109 | `util/dt.py::as_local` | `Template.asLocal` | correct | up:util/dt.py:175-182; HALean/Template/Render.lean:504; sbs 06 |
| M-110 | `util/dt.py::start_of_local_day` | `Template.callV` (partial) | correct | up:util/dt.py:191-200; HALean/Template/Render.lean:1307; sbs 06 |
| M-111 | `util/dt.py::as_timestamp` | `Template.timestampOf` | correct | up:util/dt.py:163-172; HALean/Template/Render.lean:575; sbs 06 |
| M-112 | `helpers/event.py::async_track_utc_time_change` | `Automation.TIME_CHANGE_MICROSECOND` | correct | up:helpers/event.py:1806-1846; HALean/Automation/Engine.lean:1586; read: Lean; upstream by sbs 07. Note: Engine.lean:1582-1599, up:helpers/event.py:87-88; logs-manifest/probe-automation.log [M-112]. AUT-9 |
| M-113 | `helpers/template/render_info.py::RenderInfo._freeze` | `Template.RInfo.rateLimit`, `Template.RInfo.filter`, `Template.RInfo.filterLifecycle` | correct | up:helpers/template/render_info.py:133-159; HALean/Template/Render.lean:60; sbs 06 |
| M-114 | `helpers/template/__init__.py::Template.async_render_to_info` | `Template.renderWithInfo` | correct | up:helpers/template/__init__.py:543-584; HALean/Template/Render.lean:2159; sbs 06 |
| M-115 | `helpers/template/states.py::TemplateStateBase._collect_state` | `Template.collect`, `Template.stateAttr` | correct | up:helpers/template/states.py:311-317; HALean/Template/Render.lean:104; sbs 06. Note: logs-manifest/probe-template.log [M-115] |
| M-116 | `helpers/event.py::_event_triggers_rerender` | `Automation.onTemplateTrigger` | correct | up:helpers/event.py:1923-1935; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07 |
| M-117 | `helpers/event.py::_rate_limit_for_event` | `Automation.onTemplateTrigger` | correct | up:helpers/event.py:1939-1954; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07 |
| M-118 | `helpers/event.py::_render_infos_to_track_states` | `Template.RInfo.listens` | correct | up:helpers/event.py:1914-1919; HALean/Template/Render.lean:82; sbs 06. Note: Engine.lean:1268 (`listens eid st.rlTimer.isSome`); the suppression is `_suppress_domain_all_in_render_info`, not the function of this entry (up:helpers/event.py:1914-1919) |
| M-119 | `helpers/event.py::TrackTemplateResultInfo._refresh` | `Automation.onTemplateTrigger`, `Automation.templateRefresh` | correct | up:helpers/event.py:1189-1282; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07. Note: Engine.lean:1250-1260 (one template per tracker) |
| M-120 | `helpers/event.py::TrackTemplateResultInfo._setup_time_listener` | `Automation.fireTimeTriggers` | correct | up:helpers/event.py:1055-1077; HALean/Automation/Engine.lean:1589; read: Lean; upstream by sbs 07. Note: Engine.lean:1613-1617, 1627-1632 |
| M-121 | `helpers/ratelimit.py::KeyedRateLimit.async_schedule_action` | `Automation.onTemplateTrigger`, `Automation.fireDue` | correct | up:helpers/ratelimit.py:50-97; HALean/Automation/Engine.lean:1332; read: Lean; upstream by sbs 07. Note: Engine.lean:1273-1277, 1680-1694 |
| M-122 | `helpers/template/extensions/math.py::MathExtension.min_max_from_filter` | `Template.minOrMax`, `Template.callV` (partial) | correct | up:helpers/template/extensions/math.py:293-313; HALean/Template/Render.lean:1019; sbs 06 |
| M-123 | `helpers/template/extensions/math.py::MathExtension.min_max_min` | `Template.callV` (partial) | correct | up:helpers/template/extensions/math.py:315-319; HALean/Template/Render.lean:1307; sbs 06 |
| M-124 | `helpers/template/extensions/math.py::MathExtension.min_max_max` | `Template.callV` (partial) | correct | up:helpers/template/extensions/math.py:321-325; HALean/Template/Render.lean:1307; sbs 06 |
| M-125 | `helpers/template/extensions/state.py::StateExtension.expand` | `Template.expand` | correct | up:helpers/template/extensions/state.py:145-186; HALean/Template/Render.lean:1084; sbs 06. Note: up:helpers/template/extensions/state.py:145-186; logs-manifest/probe-template.log [M-125] |
| M-126 | `core.py::StateMachine.get` | `Template.hassStatesGet`, `Core.StateMachine.get` | correct | up:core.py:2286-2293; HALean/Template/Render.lean:1061; sbs 06. Note: logs-manifest/probe-template.log [M-126]. TPL-6 |
| M-127 | `helpers/template/extensions/datetime.py::DateTimeExtension.strptime` | `Template.callDateTime`, `Template.strptime` | correct | up:helpers/template/extensions/datetime.py:218-225; HALean/Template/Render.lean:1158; sbs 06. Note: logs-manifest/probe-template.log [M-127] |
| M-128 | `helpers/template/extensions/datetime.py::DateTimeExtension.as_timedelta` | `Template.callDateTime`, `Template.parseDuration` | correct | up:helpers/template/extensions/datetime.py:214-216; HALean/Template/Render.lean:1158; sbs 06 |
| M-129 | `helpers/template/extensions/datetime.py::DateTimeExtension._datetime_as_string` | `Template.datetimeAsString` | correct | up:helpers/template/extensions/datetime.py:265-288; HALean/Template/Render.lean:1141; sbs 06 |
| M-130 | `helpers/template/extensions/datetime.py::DateTimeExtension.relative_time` | `Template.callDateTime` | correct | up:helpers/template/extensions/datetime.py:290-305; HALean/Template/Render.lean:1158; sbs 06 |
| M-131 | `helpers/template/extensions/datetime.py::DateTimeExtension.time_since` | `Template.callDateTime` | correct | up:helpers/template/extensions/datetime.py:307-317; HALean/Template/Render.lean:1158; sbs 06 |
| M-132 | `helpers/template/extensions/datetime.py::DateTimeExtension.time_until` | `Template.callDateTime` | correct | up:helpers/template/extensions/datetime.py:319-329; HALean/Template/Render.lean:1158; sbs 06 |
| M-133 | `helpers/template/extensions/datetime.py::DateTimeExtension.timedelta_string` | `Template.callDateTime` | correct | up:helpers/template/extensions/datetime.py:331-345; HALean/Template/Render.lean:1158; sbs 06 |
| M-134 | `helpers/template/extensions/datetime.py::DateTimeExtension.is_datetime` | `Template.applyTest` (partial) | correct | up:helpers/template/extensions/datetime.py:231-233; HALean/Template/Render.lean:1698; sbs 06 |
| M-135 | `util/dt.py::parse_duration` | `Template.parseDuration` | correct | up:util/dt.py:270-293; HALean/Template/DateParse.lean:145; sbs 06. Note: the three regexes are in HALean/Template/DateParse.lean:104-136, built with the matcher of Regex.lean; logs-manifest/probe-template.log [M-135] |
| M-136 | `util/dt.py::_get_timestring` | `Template.getTimestring` | correct | up:util/dt.py:314-346; HALean/Template/DateParse.lean:174; sbs 06 |
| M-137 | `util/dt.py::get_age` | `Template.roundedSeconds`, `Template.getTimestring` | correct | up:util/dt.py:349-366; HALean/Template/DateParse.lean:196; sbs 06 |
| M-138 | `util/dt.py::get_time_remaining` | `Template.roundedSeconds`, `Template.getTimestring` | correct | up:util/dt.py:369-387; HALean/Template/DateParse.lean:196; sbs 06 |
| M-139 | `util/dt.py::timedelta_string` | `Template.getTimestring` | correct | up:util/dt.py:390-401; HALean/Template/DateParse.lean:174; sbs 06 |
| M-140 | `components/automation/__init__.py::AutomationEntity.extra_state_attributes` | `Automation.thisValue` | correct | up:components/automation/__init__.py:519-530; HALean/Automation/Engine.lean:945; read: Lean; upstream by sbs 07 |
| M-141 | `components/automation/__init__.py::BaseAutomationEntity.capability_attributes` | `Automation.thisValue` | correct | up:components/automation/__init__.py:338-342; HALean/Automation/Engine.lean:945; read: Lean; upstream by sbs 07 |
| M-142 | `components/automation/__init__.py::_automation_name` | `Automation.automationName` | correct | up:components/automation/__init__.py:1025-1029; HALean/Automation/Config.lean:1138; read: Lean; upstream by sbs 07. Note: Config.lean:1138-1141; logs-manifest/probe-automation.log [M-142/M-144/M-145] |
| M-143 | `util/__init__.py::slugify` | `Automation.slugify?`, `Automation.slugifyChars`, `Automation.subRuns`, `Automation.delDigitCommas` | overstated | up:util/__init__.py:39-44; HALean/Automation/Slugify.lean:49; read: Lean; upstream by sbs 07. the refusal is wider than "HTML entities" (SCH-5). See below |
| M-144 | `helpers/entity_registry.py::EntityRegistry.async_get_available_entity_id` | `Automation.availableEntityId` | correct | up:helpers/entity_registry.py:1402-1434; HALean/Automation/Config.lean:1148; read: Lean; upstream by sbs 07. Note: Config.lean:1148-1157; logs-manifest/probe-automation.log [M-142/M-144/M-145] |
| M-145 | `helpers/entity_platform.py::EntityPlatform._async_add_entity` | `Automation.automationEntityIds` | overstated | up:helpers/entity_platform.py:854-925; HALean/Automation/Config.lean:1165; read: Lean; upstream by sbs 07. the Lean definition does not translate this function. See below |
| M-146 | `helpers/config_validation.py::_positive_time_period_template_complex` | `Automation.forPeriod?`, `Automation.cvPositiveTimePeriod`, `Automation.timePeriodDict` | overstated | up:helpers/config_validation.py:746-759; HALean/Automation/Config.lean:410; read: Lean; upstream by sbs 07. static periods do not go through the translated validators (AUT-15). See below |
| M-147 | `helpers/config_validation.py::time_period_str` | `Automation.timePeriodStr`, `Core.cvTimePeriodStr` | correct | up:helpers/config_validation.py:523-555; HALean/Automation/TimePeriod.lean:85; read: Lean; upstream by sbs 07 |
| M-148 | `helpers/config_validation.py::time_period_seconds` | `Automation.timePeriodSeconds`, `Core.cvTimePeriodSeconds` | correct | up:helpers/config_validation.py:558-563; HALean/Automation/TimePeriod.lean:112; read: Lean; upstream by sbs 07 |
| M-149 | `helpers/script.py::_ScriptRun._async_step_wait_template` | `Automation.step`, `Automation.setupWait`, `Automation.waitRefresh`, `Automation.resumeRuns` | correct | up:helpers/script.py:1331-1375; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Engine.lean:1286-1309, 1397-1402; logs-manifest/probe-automation.log [M-149/M-154] |
| M-150 | `helpers/script.py::_ScriptRun._get_timeout_seconds_from_action` | `Automation.step` | correct | up:helpers/script.py:1235-1239; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-151 | `helpers/script.py::_ScriptRun._get_pos_time_period_template` | `Automation.step`, `Automation.cvPositiveTimePeriod` | correct | up:helpers/script.py:1194-1207; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:283-290, 384-388, 414-418 |
| M-152 | `helpers/script.py::_ScriptRun._async_handle_timeout` | `Automation.step`, `Automation.fireDue` | correct | up:helpers/script.py:1241-1247; HALean/Automation/Script.lean:218; read: Lean and upstream |
| M-153 | `helpers/script.py::_ScriptRun._async_wait_with_optional_timeout` | `Automation.fireDue`, `Automation.cleanupWait`, `Automation.removeRun` | correct | up:helpers/script.py:1249-1264; HALean/Automation/Engine.lean:1697; read: Lean and upstream. Note: Engine.lean:348-357, 1044, 1668, 361-363 |
| M-154 | `helpers/script.py::_ScriptRun._async_set_remaining_time_var` | `Automation.waitRefresh` | correct | up:helpers/script.py:1266-1274; HALean/Automation/Engine.lean:1286; read: Lean and upstream. Note: Engine.lean:1306, up:helpers/script.py:1266-1274; logs-manifest/probe-automation.log [M-149/M-154] |
| M-155 | `helpers/event.py::async_track_template` | `Automation.waitRefresh`, `Automation.trackerGate` | correct | up:helpers/event.py:868-948; HALean/Automation/Engine.lean:1286; read: Lean; upstream by sbs 07. Note: Engine.lean:1300-1302 |
| M-156 | `helpers/script.py::_ScriptRun._async_step_wait_for_trigger` | `Automation.step`, `Automation.attachTriggers`, `Automation.fire`, `Automation.resumeWoken`, `Automation.cleanupWait` | correct | up:helpers/script.py:1276-1329; HALean/Automation/Script.lean:218; read: Lean and upstream. Note: Script.lean:424-431, Engine.lean:1014-1025, up:helpers/script.py:1280-1304; logs-manifest/probe-automation.log [M-156] |
| M-157 | `helpers/trigger/__init__.py::async_initialize_triggers` | `Automation.attachTriggers`, `Automation.initArmed` | correct | up:helpers/trigger/__init__.py:645-741; HALean/Automation/Engine.lean:444; read: Lean; upstream by sbs 07. Note: Engine.lean:41-44, Config.lean:713-715. AUT-14, AUT-20 |
| M-158 | `helpers/script.py::_ScriptRun._async_step_parallel` | `Automation.step`, `Automation.drive`, `Automation.finishBranch` (missing), `Automation.resumeWoken` | stale | up:helpers/script.py:714-730; HALean/Automation/Script.lean:218; read: Lean and upstream. `HALean.Automation.finishBranch` does not exist; removed in bf053c0. See below |
| M-159 | `helpers/script.py::Script._async_prep_parallel_scripts` | `Automation.decodeAction` (partial) | correct | up:helpers/script.py:2232-2255; HALean/Automation/Config.lean:1000; read: Lean; upstream by sbs 07. Note: Config.lean:1105-1111; logs-manifest/probe-automation.log [M-158/M-159]. AUT-17 |
| M-160 | `helpers/script_variables.py::ScriptRunVariables.enter_scope` | `Automation.syncFamily`, `Automation.BRANCH_LOCAL` | correct | up:helpers/script_variables.py:157-187; HALean/Automation/Engine.lean:330; read: Lean; upstream by sbs 07. Note: Engine.lean:323-337 |
| M-161 | `helpers/script_variables.py::ScriptRunVariables.assign_parallel_protected` | `Automation.BRANCH_LOCAL`, `Automation.syncFamily` | correct | up:helpers/script_variables.py:208-210; HALean/Automation/Engine.lean:325; read: Lean; upstream by sbs 07 |
| M-162 | `components/zone/trigger.py::LegacyZoneTrigger.async_attach_runner` | `Automation.onZoneTrigger` | correct | up:components/zone/trigger.py:136-188; HALean/Automation/Engine.lean:1340; read: Lean; upstream by sbs 07 |
| M-163 | `components/zone/trigger.py::_state_has_zone_info` | `Automation.stateHasZoneInfo` | correct | up:components/zone/trigger.py:59-69; HALean/Automation/Location.lean:99; read: Lean; upstream by sbs 07 |
| M-164 | `components/zone/condition.py::zone` | `Automation.zoneCondition`, `Automation.zoneById` | correct | up:components/zone/condition.py:55-112; HALean/Automation/Location.lean:126; read: Lean; upstream by sbs 07. Note: Condition.lean:303-312, Engine.lean (none); logs-manifest/probe-automation.log [M-164] |
| M-165 | `components/zone/__init__.py::in_zone` | `Automation.inZone` | correct | up:components/zone/__init__.py:284-303; HALean/Automation/Location.lean:114; read: Lean; upstream by sbs 07 |
| M-166 | `components/zone/helpers.py::get_in_zones_attribute` | `Automation.inZonesAttribute` | correct | up:components/zone/helpers.py:14-24; HALean/Automation/Location.lean:94; read: Lean; upstream by sbs 07. Note: Location.lean:94-96, up:components/zone/helpers.py:14-24 |
| M-167 | `util/location.py::vincenty` | `Automation.vincenty` | correct | up:util/location.py:78-157; HALean/Automation/Location.lean:32; read: Lean; upstream by sbs 07. Note: not probed (the 100 m claim was not rerun); Location.lean:32-79 read against up:util/location.py:78-157 by sbs 07 only as 'not re-read in depth' |
| M-168 | `util/location.py::distance` | `Automation.distance` | correct | up:util/location.py:60-72; HALean/Automation/Location.lean:79; read: Lean; upstream by sbs 07 |
| M-169 | `helpers/location.py::get_state_coordinates` | `Automation.hasLocation` | correct | up:helpers/location.py:21-36; HALean/Automation/Location.lean:89; read: Lean; upstream by sbs 07 |
| M-170 | `helpers/trigger/__init__.py::_async_attach_trigger_cls` | `Automation.triggerValue` | correct | up:helpers/trigger/__init__.py:554-642; HALean/Automation/Engine.lean:41; read: Lean; upstream by sbs 07. Note: Engine.lean:41-44; only the payload of an 88-line function is modelled, as the note says |
| M-171 | `components/sun/trigger.py::SunEventTrigger.async_attach_runner` | `Automation.attachTriggers`, `Automation.fireSun` | correct | up:components/sun/trigger.py:212-254; HALean/Automation/Engine.lean:444; read: Lean; upstream by sbs 07. Note: Engine.lean:1701-1721; logs-manifest/probe-automation.log [M-171/M-173] |
| M-172 | `components/sun/trigger.py::LegacySunTrigger._action_payload` | `Automation.fireSun` | correct | up:components/sun/trigger.py:587-588; HALean/Automation/Engine.lean:1723; read: Lean; upstream by sbs 07 |
| M-173 | `components/sun/trigger.py::SunEventTrigger.__init__` | `Automation.decodeTrigger` | correct | up:components/sun/trigger.py:187-194; HALean/Automation/Config.lean:709; read: Lean; upstream by sbs 07. Note: Config.lean:873-883, up:components/sun/trigger.py:187-194; logs-manifest/probe-automation.log [M-171/M-173] |
| M-174 | `helpers/sun.py::get_observer_astral_event_next` | `Automation.Sun.nextEvent` | correct | up:helpers/sun.py:83-125; HALean/Automation/Sun.lean:182; read: Lean; upstream by sbs 07. Note: tests/sun/compare.py exists; HALean/Automation/Sun.lean:176-191 |
| M-175 | `helpers/sun.py::get_astral_observer` | `Automation.decodeInput` | correct | up:helpers/sun.py:41-45; HALean/Automation/Protocol.lean:62; read: Lean; upstream by sbs 07. Note: Protocol.lean:77-83 (the Lean name is the whole input decoder) |
| M-176 | `components/zone/condition.py::ZoneCondition._async_check` | `Automation.zoneCond` | correct | up:components/zone/condition.py:148-177; HALean/Automation/Condition.lean:303; read: Lean; upstream by sbs 07 |
| M-177 | `components/sun/condition.py::sun` | `Automation.sunCond` | correct | up:components/sun/condition.py:83-158; HALean/Automation/Condition.lean:317; read: Lean; upstream by sbs 07 |
| M-178 | `components/sun/condition.py::SunCondition._async_check` | `Automation.sunCond` | correct | up:components/sun/condition.py:196-204; HALean/Automation/Condition.lean:317; read: Lean; upstream by sbs 07 |
| M-179 | `helpers/sun.py::get_astral_event_date` | `Automation.sunCond`, `Automation.Sun.sunEvent` | correct | up:helpers/sun.py:129-150; HALean/Automation/Condition.lean:317; read: Lean; upstream by sbs 07 |
| M-181 | `core.py::validate_state` | `Core.StateMachine.validateState` | correct | up:core.py:201-208; HALean/Core/StateMachine.lean:223; sbs 03 |
| M-182 | `core.py::Context._as_dict` | `Core.Context.asDict` | correct | up:core.py:1314-1324; HALean/Core/State.lean:41; sbs 03. Note: logs-manifest/probe-core.log [M-182/M-223] |
| M-183 | `core.py::State.__init__` | `Core.State.new` | correct | up:core.py:1907-1955; HALean/Core/State.lean:139; sbs 03. Note: theorem State.new_ok HALean/Core/Proofs.lean:114; sbs 03 row `State.__init__`. ST-7 |
| M-184 | `core.py::State.name` | `Core.State.name` | correct | up:core.py:1958-1962; HALean/Core/State.lean:156; sbs 03 |
| M-185 | `core.py::State.last_changed_timestamp` | `Core.State.lastChangedTimestamp` | correct | up:core.py:1965-1967; HALean/Core/State.lean:172; sbs 03 |
| M-186 | `core.py::State.last_reported_timestamp` | `Core.State.lastReportedTimestamp` | correct | up:core.py:1970-1985; HALean/Core/State.lean:177; sbs 03 |
| M-187 | `core.py::State._as_dict` | `Core.State.asDict` | correct | up:core.py:1988-2014; HALean/Core/State.lean:184; sbs 03 |
| M-188 | `core.py::State.as_dict` | `Core.State.asDict` | correct | up:core.py:2016-2026; HALean/Core/State.lean:184; sbs 03. Note: tests/differential/test_states.py:216; logs-manifest/probe-core.log [M-188] |
| M-189 | `core.py::State.as_compressed_state` | `Core.State.asCompressedState` | correct | up:core.py:2054-2080; HALean/Core/State.lean:196; sbs 03 |
| M-190 | `core.py::State.expire` | `Core.StateMachine.asyncSetInternal`, `Core.StateMachine.asyncRemove` | correct | up:core.py:2128-2144; HALean/Core/StateMachine.lean:188; sbs 03. Note: sbs 03 row `State.expire` |
| M-191 | `core.py::States.__setitem__` | `Core.StateMachine.setItem` | correct | up:core.py:2175-2178; HALean/Core/StateMachine.lean:76; sbs 03 |
| M-192 | `core.py::States.__delitem__` | `Core.StateMachine.delItem` | correct | up:core.py:2181-2185; HALean/Core/StateMachine.lean:81; sbs 03 |
| M-194 | `core.py::States.domain_states` | `Core.StateMachine.domainStates` | correct | up:core.py:2194-2199; HALean/Core/StateMachine.lean:92; sbs 03 |
| M-195 | `core.py::StateMachine.async_entity_ids` | `Core.StateMachine.asyncEntityIds` | correct | up:core.py:2225-2241; HALean/Core/StateMachine.lean:113; sbs 03 |
| M-196 | `core.py::StateMachine.async_entity_ids_count` | `Core.StateMachine.asyncEntityIdsCount` | correct | up:core.py:2244-2259; HALean/Core/StateMachine.lean:119; sbs 03 |
| M-197 | `core.py::StateMachine.async_all` | `Core.StateMachine.asyncAll` | correct | up:core.py:2268-2284; HALean/Core/StateMachine.lean:125; sbs 03 |
| M-198 | `core.py::StateMachine.is_state` | `Core.StateMachine.isState` | correct | up:core.py:2295-2301; HALean/Core/StateMachine.lean:136; sbs 03 |
| M-201 | `core.py::StateMachine.async_available` | `Core.StateMachine.asyncAvailable` | correct | up:core.py:2383-2388; HALean/Core/StateMachine.lean:165; sbs 03 |
| M-202 | `core.py::StateMachine.async_set` | `Core.StateMachine.asyncSet`, `Core.Hass.runAction` | correct | up:core.py:2391-2420; HALean/Core/StateMachine.lean:231; sbs 03. Note: logs-manifest/probe-core.log [M-202]; sbs 03 row `StateMachine.async_set`. ST-1, ST-2, ST-4, ST-5, ST-6 |
| M-204 | `core.py::SupportsResponse` | `Core.SupportsResponse` | correct | up:core.py:2541-2551; HALean/Core/ServiceRegistry.lean:36; sbs 04; a class |
| M-205 | `core.py::Service` | `Core.Service`, `Core.HandlerSpec` | correct | up:core.py:2554-2585; HALean/Core/ServiceRegistry.lean:61; sbs 04; a class. Note: ServiceRegistry.lean:50-65; sbs 04 row `Service` |
| M-206 | `core.py::ServiceCall` | `Core.ServiceCall`, `Core.ServiceCall.repr` | correct | up:core.py:2588-2619; HALean/Core/ServiceRegistry.lean:234; sbs 04; a class |
| M-207 | `core.py::ServiceRegistry.async_services` | `Core.Registry.asyncServices` | correct | up:core.py:2638-2646; HALean/Core/ServiceRegistry.lean:193; sbs 04 |
| M-208 | `core.py::ServiceRegistry.async_services_for_domain` | `Core.Registry.asyncServicesForDomain` | correct | up:core.py:2649-2656; HALean/Core/ServiceRegistry.lean:197; sbs 04. Note: review/experiments/12-claims/logs/core-probes.log group V4; sbs 04 |
| M-210 | `core.py::ServiceRegistry.supports_response` | `Core.Registry.supportsResponse` | correct | up:core.py:2678-2687; HALean/Core/ServiceRegistry.lean:184; sbs 04. Note: logs-manifest/probe-core.log [M-208/M-210] |
| M-211 | `core.py::ServiceRegistry.async_register` | `Core.Registry.register` | correct | up:core.py:2715-2747; HALean/Core/ServiceRegistry.lean:202; sbs 04 |
| M-213 | `core.py::ServiceRegistry.async_remove` | `Core.Registry.remove` | correct | up:core.py:2800-2806; HALean/Core/ServiceRegistry.lean:214; sbs 04 |
| M-216 | `core.py::ServiceRegistry._run_service_call_catch_exceptions` | `Core.Registry.asyncCall`, `Core.finishCall`, `Core.Hass.callService`, `Core.Hass.resume` | correct | up:core.py:2976-2993; HALean/Core/ServiceRegistry.lean:412; sbs 04. Note: sbs 04 row `_run_service_call_catch_exceptions` |
| M-217 | `core.py::ServiceRegistry._execute_service` | `Core.runHandler`, `Core.Hass.callService`, `Core.Hass.resume`, `Core.Hass.Frame` | correct | up:core.py:2995-3013; HALean/Core/ServiceRegistry.lean:255; sbs 04. Note: sbs 04 row `_execute_service` |
| M-218 | `exceptions.py::HomeAssistantError` | `Core.PyError`, `Core.translatedError`, `Core.errorKind` | correct | up:exceptions.py:33-87; HALean/Core/ServiceRegistry.lean:97; sbs 04; a class |
| M-219 | `exceptions.py::ServiceValidationError` | `Core.serviceValidationError` | correct | up:exceptions.py:110-111; HALean/Core/ServiceRegistry.lean:302; sbs 04; a class |
| M-220 | `exceptions.py::ServiceNotFound` | `Core.serviceNotFound` | correct | up:exceptions.py:415-427; HALean/Core/ServiceRegistry.lean:152; sbs 04; a class |
| M-221 | `helpers/translation.py::async_get_exception_message` | `Core.exceptionMessage`, `Core.exceptionTemplate` | correct | up:helpers/translation.py:433-458; HALean/Core/ServiceRegistry.lean:141; sbs 04. Note: ServiceRegistry.lean:119-131 (five strings). Formatting differs from str.format (REG-1) |
| M-222 | `util/__init__.py::repr_helper` | `Core.reprHelper` (partial) | correct | up:util/__init__.py:47-56; HALean/Core/ServiceRegistry.lean:242; sbs 04. Note: ServiceRegistry.lean:242-246; sbs 04 |
| M-223 | `core.py::Context.__init__` | `Core.Context`, `Core.Registry.freshContext`, `Core.Hass.Hass.genContext`, `Core.Hass.Hass.ctxOr` | correct | up:core.py:1287-1298; HALean/Core/State.lean:34; sbs 03. Note: logs-manifest/probe-core.log [M-182/M-223], [M-223/M-225], [M-223]. An empty id is not replaced (REG-2, HASS-2) |
| M-224 | `core.py::EventOrigin` | `Core.EventBus.Origin`, `Core.EventBus.Origin.value` | correct | up:core.py:1341-1355; HALean/Core/EventBus.lean:45; sbs 03; a class |
| M-225 | `core.py::Event.__init__` | `Core.EventBus.makeEvent` | correct | up:core.py:1371-1389; HALean/Core/EventBus.lean:419; sbs 03. Note: EventBus.lean:319, 419; logs-manifest/probe-core.log [M-223/M-225]. BUS-1 |
| M-226 | `core.py::Event.time_fired` | `Core.EventBus.Event.timeFiredIso`, `Core.EventBus.utcMicrosOfTimestamp` | correct | up:core.py:1392-1394; HALean/Core/EventBus.lean:148; sbs 03. Note: sbs 03 row `Event.time_fired` |
| M-227 | `core.py::Event._as_dict` | `Core.EventBus.Event.asDict` | correct | up:core.py:1397-1412; HALean/Core/EventBus.lean:152; sbs 03 |
| M-229 | `core.py::_verify_event_type_length_or_raise` | `Core.EventBus.asyncFire`, `Core.EventBus.react1` | correct | up:core.py:1494-1497; HALean/Core/EventBus.lean:481; sbs 03. Note: review/experiments/12-claims/logs/core-probes.log group E1 |
| M-230 | `core.py::EventBus.__init__` | `Core.EventBus.Bus.new` | correct | up:core.py:1519-1533; HALean/Core/EventBus.lean:227; sbs 03. Note: EventBus.lean:225-231, up:core.py:1519-1533 |
| M-231 | `core.py::EventBus.async_listeners` | `Core.EventBus.asyncListeners` | correct | up:core.py:1541-1546; HALean/Core/EventBus.lean:257; sbs 03 |
| M-232 | `core.py::EventBus.async_fire` | `Core.EventBus.asyncFire`, `Core.EventBus.react1`, `Core.Hass.runAction` | correct | up:core.py:1567-1586; HALean/Core/EventBus.lean:481; sbs 03. Note: sbs 03, sbs 04 |
| M-233 | `core.py::EventBus.async_fire_internal` | `Core.EventBus.asyncFire`, `Core.EventBus.fireNested`, `Core.EventBus.drain`, `Core.Hass.fireInternal`, `Core.Hass.fireList`, `Core.Hass.drain`, `Core.Hass.queueFull` | correct | up:core.py:1589-1640; HALean/Core/EventBus.lean:481; sbs 03. Note: EventBus.lean:468-477 (no theorem that `drain` empties the queue: grep `theorem.*drain` gives drain_onceInv, drain_quiet, drain_wf); theorems quiet HassProofs.lean:178, fireInternal_first :534 |
| M-235 | `core.py::EventBus.async_listen` | `Core.EventBus.asyncListen`, `Core.Hass.runAction` | correct | up:core.py:1703-1744; HALean/Core/EventBus.lean:282; sbs 03. Note: up:core.py:1722-1727; logs-manifest/probe-core.log [M-235/M-237] |
| M-236 | `core.py::EventBus._async_listen_filterable_job` | `Core.EventBus.listenFilterableJob` | correct | up:core.py:1747-1756; HALean/Core/EventBus.lean:262; sbs 03 |
| M-237 | `core.py::EventBus.async_listen_once` | `Core.EventBus.asyncListenOnce`, `Core.Hass.runAction` | correct | up:core.py:1781-1822; HALean/Core/EventBus.lean:293; sbs 03. Note: up:core.py:1781-1786; logs-manifest/probe-core.log [M-235/M-237] |
| M-239 | `core.py::HomeAssistant.async_run_hass_job` | `Core.EventBus.runJob`, `Core.Hass.runJob`, `Core.Hass.recordDelivery`, `Core.Hass.runListener`, `Core.Hass.Hass.spawn` | correct for the wrong reason | up:core.py:896-901; HALean/Core/EventBus.lean:378; sbs 03. the ref resolves to an `@overload` stub; the hash does not watch the implementation. See below |
| M-240 | `components/script/config.py::_async_validate_config_item` | `Script.decodeScript`, `Script.decodeFields`, `Script.isSlug` | overstated | up:components/script/config.py:106-252; HALean/Script/Config.lean:128; read: Lean; upstream by sbs 08. values `SCRIPT_ENTITY_SCHEMA` accepts are refused and invalid action keys accepted (SCR-10, SCR-11). See below |
| M-241 | `components/script/config.py::async_validate_config` | `Script.decodeAll`, `Script.passedNames` | correct | up:components/script/config.py:294-311; HALean/Script/Service.lean:50; read: Lean; upstream by sbs 08 |
| M-242 | `components/script/__init__.py::async_setup.turn_on_service` | `Script.planCall`, `Automation.callLocal` | correct | up:components/script/__init__.py:236-243; HALean/Script/Entity.lean:188; read: Lean; upstream by sbs 08. Note: Engine.lean:887-898; sbs 08 §3 (SCR-13) |
| M-243 | `components/script/__init__.py::async_setup.turn_off_service` | `Script.planCall`, `Automation.callLocal` | correct | up:components/script/__init__.py:245-261; HALean/Script/Entity.lean:188; read: Lean; upstream by sbs 08 |
| M-244 | `components/script/__init__.py::async_setup.toggle_service` | `Script.planCall`, `Automation.callLocal` | correct | up:components/script/__init__.py:263-267; HALean/Script/Entity.lean:188; read: Lean; upstream by sbs 08 |
| M-245 | `components/script/__init__.py::async_setup.reload_service` | `Script.Service.step` | correct | up:components/script/__init__.py:230-234; HALean/Script/Service.lean:128; read: Lean; upstream by sbs 08. Note: HALean/Script/Service.lean:166-176 |
| M-246 | `components/script/__init__.py::_async_process_config` | `Script.reloadScripts`, `Script.addScripts`, `Script.Service.step` | correct | up:components/script/__init__.py:358-417; HALean/Script/Service.lean:90; read: Lean; upstream by sbs 08 |
| M-247 | `components/script/__init__.py::ScriptEntity.__init__` | `Script.decodeScript` | correct | up:components/script/__init__.py:554-588; HALean/Script/Config.lean:128; read: Lean; upstream by sbs 08 |
| M-248 | `components/script/__init__.py::ScriptEntity.extra_state_attributes` | `Script.entityAttributes`, `Script.scriptThis` | correct | up:components/script/__init__.py:592-604; HALean/Script/Entity.lean:46; read: Lean; upstream by sbs 08. Note: HALean/Script/Entity.lean:46-55, 81 |
| M-249 | `components/script/__init__.py::ScriptEntity.is_on` | `Script.entityState` | correct | up:components/script/__init__.py:608-610; HALean/Script/Entity.lean:66; read: Lean; upstream by sbs 08 |
| M-250 | `components/script/__init__.py::ScriptEntity.async_change_listener` | `Automation.writeEntity` | correct | up:components/script/__init__.py:652-655; HALean/Automation/Engine.lean:508; read: Lean; upstream by sbs 08. Note: Engine.lean:675, 787, 856. SCR-7 |
| M-251 | `components/script/__init__.py::ScriptEntity.async_turn_on` | `Automation.callLocal` | correct | up:components/script/__init__.py:658-667; HALean/Automation/Engine.lean:935; read: Lean; upstream by sbs 08 |
| M-252 | `components/script/__init__.py::ScriptEntity._async_start_run` | `Automation.startScript` (missing), `Automation.callLocal`, `Automation.continueNow` (missing) | stale | up:components/script/__init__.py:669-703; HALean/Automation/Engine.lean:935; read: Lean; upstream by sbs 08. `startScript` and `continueNow` do not exist; removed in bf053c0. See below |
| M-253 | `components/script/__init__.py::ScriptEntity._async_run` | `Automation.startScript` (missing), `Script.scriptThis` | stale | up:components/script/__init__.py:705-723; HALean/Script/Entity.lean:73; read: Lean; upstream by sbs 08. `HALean.Automation.startScript` does not exist; removed in bf053c0. See below |
| M-254 | `components/script/__init__.py::ScriptEntity.async_turn_off` | `Automation.callLocal`, `Automation.stopRun` | correct | up:components/script/__init__.py:726-731; HALean/Automation/Engine.lean:935; read: Lean; upstream by sbs 08 |
| M-255 | `components/script/__init__.py::ScriptEntity._service_handler` | `Script.planCall`, `Script.callResponse`, `Automation.answer` (missing) | stale | up:components/script/__init__.py:733-740; HALean/Script/Entity.lean:188; read: Lean; upstream by sbs 08. `HALean.Automation.answer` does not exist; removed in bf053c0. See below |
| M-256 | `components/script/__init__.py::ScriptEntity.async_added_to_hass` | `Script.addScripts`, `Script.lastTriggeredOf` | correct | up:components/script/__init__.py:743-770; HALean/Script/Service.lean:68; read: Lean; upstream by sbs 08. Note: HALean/Script/Service.lean:68-80, 107-110, 134-135 |
| M-257 | `components/script/__init__.py::ScriptEntity.async_will_remove_from_hass` | `Script.reloadScripts` | correct | up:components/script/__init__.py:773-781; HALean/Script/Service.lean:90; read: Lean; upstream by sbs 08 |
| M-258 | `helpers/script.py::Script.async_stop` | `Automation.callLocal`, `Automation.stopRun` | correct | up:helpers/script.py:2021-2033; HALean/Automation/Engine.lean:935; read: Lean; upstream by sbs 07 |
| M-259 | `helpers/script.py::_ScriptRun.async_stop` | `Automation.stopRun`, `Automation.stoppedQuietly` | overstated | up:helpers/script.py:604-612; HALean/Automation/Engine.lean:934; read: Lean; upstream by sbs 07. a run stopped from inside its own `script.turn_on` step ends quietly in HA (SCR-6). See below |
| M-260 | `helpers/script.py::_ScriptRun._finish` | `Automation.finishRun`, `Automation.writeEntity`, `Automation.releaseQueue` (missing) | stale | up:helpers/script.py:597-602; HALean/Automation/Engine.lean:933; read: Lean and upstream. `HALean.Automation.releaseQueue` does not exist; removed in bf053c0. See below |
| M-261 | `helpers/script.py::_ScriptRun._async_run_long_action` | `Automation.cancelRun` (missing), `Automation.stoppedQuietly` | stale | up:helpers/script.py:677-688; HALean/Automation/Engine.lean:550; read: Lean and upstream. `HALean.Automation.cancelRun` does not exist; removed in bf053c0. See below |
| M-262 | `helpers/script.py::Script.is_running` | `Script.entityState` | correct | up:helpers/script.py:1644-1646; HALean/Script/Entity.lean:66; read: Lean; upstream by sbs 08 |
| M-263 | `helpers/script.py::Script.runs` | `Automation.writeEntity`, `Automation.runsOf` | correct | up:helpers/script.py:1649-1651; HALean/Automation/Engine.lean:508; read: Lean; upstream by sbs 07 |
| M-264 | `helpers/script.py::Script.supports_max` | `Script.supportsMax` | correct | up:helpers/script.py:1654-1656; HALean/Script/Entity.lean:36; read: Lean; upstream by sbs 08 |
| M-265 | `helpers/service.py::async_extract_entities` | `Script.extractTargets`, `Script.compEntityIds` | correct | up:helpers/service.py:362-397; HALean/Script/Entity.lean:160; read: Lean; upstream by sbs 08. Note: HALean/Script/Entity.lean:160-172. SCR-2 |
| M-266 | `helpers/entity.py::Entity.__async_remove_impl` | `Script.reloadScripts` | correct | up:helpers/entity.py:1479-1510; HALean/Script/Service.lean:90; read: Lean; upstream by sbs 08 |
| M-267 | `helpers/entity_registry.py::RegistryEntry.write_unavailable_state` | `Script.unavailableAttributes` | correct | up:helpers/entity_registry.py:476-501; HALean/Script/Entity.lean:60; read: Lean; upstream by sbs 08 |
| M-268 | `helpers/restore_state.py::RestoreStateData.async_restore_entity_removed` | `Script.reloadScripts` | correct | up:helpers/restore_state.py:270-289; HALean/Script/Service.lean:90; read: Lean; upstream by sbs 08 |
| M-269 | `core.py::HomeAssistant.async_create_task` | `Core.Hass.runAction`, `Core.Hass.Hass.spawn`, `Core.Hass.Frame` | correct | up:core.py:788-805; HALean/Core/Hass.lean:515; sbs 04. Note: sbs 04 row `async_create_task`; not re-read |
| M-270 | `core.py::HomeAssistant.async_create_task_internal` | `Core.Hass.runAction`, `Core.Hass.callService`, `Core.Hass.Hass.spawn`, `Core.Hass.Hass.park`, `Core.Hass.TaskRec` | correct | up:core.py:808-836; HALean/Core/Hass.lean:515; sbs 04. Note: sbs 04 row `async_create_task`; not re-read |
| M-273 | `core.py::HomeAssistant._await_and_log_pending` | `Core.Hass.startRound`, `Core.Hass.runHandle` | correct | up:core.py:1027-1038; HALean/Core/Hass.lean:655; sbs 04. Note: sbs 04 row `_await_and_log_pending`; not re-read |
| M-274 | `core.py::HassJobType` | `Core.Hass.Hass`, `Core.Hass.Action` | false | up:core.py:288-293; HALean/Core/Hass.lean:216; sbs 04; a class. note says "Executor is rejected"; nothing rejects it. See below |
| M-275 | `core.py::get_hassjob_callable_job_type` | `Core.Hass.runListener` | correct | up:core.py:349-362; HALean/Core/Hass.lean:469; sbs 04. Note: Exe/Core.lean:24, 159; logs-manifest/probe-core.log [M-274/M-275/M-239] |
| M-276 | `probatio:schema.py::Schema.__call__` | `Core.SchemaSpec.validate`, `Core.multipleInvalidStr` | correct | site-packages/probatio/schema.py:314-349; HALean/Core/Schema.lean:187; sbs 05. Note: site-packages/probatio/schema.py:340-349. The generated code is not translated (SCH-3) |
| M-277 | `probatio:_compile.py::_make_candidate` | `Core.ServicesJson.decodeField` (partial), `Core.Field`, `Core.KeyMarker` | correct | site-packages/probatio/_compile.py:434-558; HALean/Core/ServicesJson.lean:211; sbs 05. Note: ServicesJson.lean:211-234 |
| M-278 | `probatio:_compile.py::_TypeCheck.__call__` | `Core.checkType` | correct | site-packages/probatio/_compile.py:197-205; HALean/Core/Probatio.lean:401; sbs 05. Note: Probatio.lean:401-412 |
| M-279 | `probatio:_compile.py::_FloatCheck.__call__` | `Core.checkType` | correct | site-packages/probatio/_compile.py:231-248; HALean/Core/Probatio.lean:401; sbs 05. Note: Probatio.lean:409-411 |
| M-280 | `probatio:_compile.py::_compile_literal` | `Core.checkLiteral` | correct | site-packages/probatio/_compile.py:659-668; HALean/Core/Probatio.lean:415; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-281 | `probatio:_compile.py::_compile_callable` | `Core.CvFn.run` | false | site-packages/probatio/_compile.py:632-656; HALean/Core/ConfigValidation.lean:204; sbs 05. note says no translated cv function raises ValueError; `cv.time_period_str` and `cv.time_period_dict` do. See below |
| M-282 | `probatio:_engine.py::_MappingValidator.__call__` | `Core.runMapping` (partial) | correct | site-packages/probatio/_engine.py:213-288; HALean/Core/Schema.lean:114; sbs 05. Note: sbs 05 rows `_MappingValidator.__call__`, extra-policy inheritance |
| M-283 | `probatio:_engine.py::_MappingValidator._collect` | `Core.runMapping` (partial), `Core.prependAll` | correct | site-packages/probatio/_engine.py:441-455; HALean/Core/Schema.lean:114; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-284 | `probatio:_engine.py::_MappingValidator._unmatched` | `Core.runMapping` (partial) | correct | site-packages/probatio/_engine.py:457-491; HALean/Core/Schema.lean:114; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-285 | `probatio:_engine.py::_MappingValidator._extra_key_error` | `Core.extraKeyError` | correct | site-packages/probatio/_engine.py:493-508; HALean/Core/Probatio.lean:219; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-286 | `probatio:_engine.py::_MappingValidator._finalize` | `Core.runMapping` (partial) | correct | site-packages/probatio/_engine.py:510-562; HALean/Core/Schema.lean:114; sbs 05. Note: sbs 05 row `_finalize` |
| M-287 | `probatio:_engine.py::_MappingValidator._check_groups` | `Core.runMapping` (partial), `Core.groupsOf` | correct | site-packages/probatio/_engine.py:610-650; HALean/Core/Schema.lean:114; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-288 | `probatio:_engine.py::_MappingValidator._empty_exclusive_group` | `Core.runMapping` (partial) | correct | site-packages/probatio/_engine.py:564-601; HALean/Core/Schema.lean:114; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-289 | `probatio:_engine.py::_SequenceValidator.__call__` | `Core.runSequence` (partial) | correct | site-packages/probatio/_engine.py:717-778; HALean/Core/Schema.lean:87; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-290 | `probatio:_engine.py::_SequenceValidator._validate_item` | `Core.runSequence` (partial) | correct | site-packages/probatio/_engine.py:780-816; HALean/Core/Schema.lean:87; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-291 | `probatio:validators/combinators.py::All.__call__` | `Core.runAll` (partial) | correct | site-packages/probatio/validators/combinators.py:293-321; HALean/Core/Schema.lean:56; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-292 | `probatio:validators/combinators.py::Any.__call__` | `Core.runAny` (partial) | correct | site-packages/probatio/validators/combinators.py:500-509; HALean/Core/Schema.lean:66; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-293 | `probatio:validators/combinators.py::_run_any` | `Core.runAny` (partial) | correct | site-packages/probatio/validators/combinators.py:160-196; HALean/Core/Schema.lean:66; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-294 | `probatio:validators/combinators.py::_branch_label` | `Core.Validator.label?` | correct | site-packages/probatio/validators/combinators.py:125-138; HALean/Core/Probatio.lean:383; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-295 | `probatio:validators/combinators.py::_expected_label` | `Core.expectedLabel` | correct | site-packages/probatio/validators/combinators.py:141-157; HALean/Core/Probatio.lean:392; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-296 | `probatio:validators/comparison.py::Range.__call__` | `Core.checkRange`, `Core.rangeOk`, `Core.rangeError` | correct | site-packages/probatio/validators/comparison.py:180-219; HALean/Core/Probatio.lean:509; sbs 05. Note: theorems in HALean/Core/ProbatioProofs.lean:33-71 |
| M-297 | `probatio:validators/comparison.py::Clamp.__call__` | `Core.checkClamp` | correct | site-packages/probatio/validators/comparison.py:240-252; HALean/Core/Probatio.lean:518; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-298 | `probatio:validators/comparison.py::Length.__call__` | `Core.checkLength` | correct | site-packages/probatio/validators/comparison.py:855-895; HALean/Core/Probatio.lean:537; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-299 | `probatio:validators/comparison.py::In.__call__` | `Core.checkIn` | correct | site-packages/probatio/validators/comparison.py:952-977; HALean/Core/Probatio.lean:451; sbs 05. Note: theorem checkIn_ok_iff ProbatioProofs.lean:11 |
| M-300 | `probatio:validators/comparison.py::NotIn.__call__` | `Core.checkNotIn` | correct | site-packages/probatio/validators/comparison.py:992-1005; HALean/Core/Probatio.lean:459; sbs 05. Note: theorem checkNotIn_ok_iff ProbatioProofs.lean:20 |
| M-301 | `probatio:validators/comparison.py::_sorted_for_message` | `Core.sortedForMessage` | correct | site-packages/probatio/validators/comparison.py:36-46; HALean/Core/Probatio.lean:423; sbs 05. Note: logs-manifest/py-direct.log [M-301] |
| M-302 | `probatio:validators/coerce.py::Coerce.__call__` | `Core.checkCoerce`, `Core.pyInt?`, `Core.pyFloat?` | correct | site-packages/probatio/validators/coerce.py:66-108; HALean/Core/Probatio.lean:564; sbs 05. Note: theorem checkCoerce_int ProbatioProofs.lean:86. SCH-1, SCH-3 |
| M-303 | `probatio:validators/strings.py::Lower` | `Core.checkLower` | correct | site-packages/probatio/validators/strings.py:279-281; HALean/Core/Probatio.lean:579; sbs 05. Note: logs-manifest/py-direct.log [M-303] |
| M-304 | `probatio:validators/strings.py::Upper` | `Core.checkUpper` | correct | site-packages/probatio/validators/strings.py:284-286; HALean/Core/Probatio.lean:582; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-305 | `probatio:validators/structural.py::EnsureList.__call__` | `Core.ensureList` | correct for the wrong reason | site-packages/probatio/validators/structural.py:297-297; HALean/Core/Probatio.lean:586; sbs 05. the ref resolves to a `typing.overload` stub; the hash does not watch the implementation. See below |
| M-306 | `probatio:validators/network.py::Port.__call__` | `Core.checkPort` | correct | site-packages/probatio/validators/network.py:219-239; HALean/Core/Probatio.lean:600; sbs 05. Note: theorem checkPort_range ProbatioProofs.lean:97 |
| M-307 | `probatio:validators/conditional.py::AtLeastOne.__call__` | `Core.checkAtLeastOne` | correct | site-packages/probatio/validators/conditional.py:326-335; HALean/Core/Probatio.lean:593; sbs 05. Note: sbs 05. The decoder accepts an empty key list (SCH-6) |
| M-308 | `probatio:error.py::render_path` | `Core.renderPath` | correct | site-packages/probatio/error.py:81-113; HALean/Core/Probatio.lean:173; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry); the other clause by the sbs 05 row of this function |
| M-309 | `probatio:error.py::_format_candidates` | `Core.formatCandidates` | correct | site-packages/probatio/error.py:39-44; HALean/Core/Probatio.lean:197; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-310 | `probatio:error.py::_SuggestionInvalid.candidates` | `Core.suggestionSuffix`, `Core.getCloseMatches` | correct | site-packages/probatio/error.py:384-400; HALean/Core/Probatio.lean:209; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-311 | `probatio:error.py::MultipleInvalid.__str__` | `Core.multipleInvalidStr` | correct | site-packages/probatio/error.py:529-531; HALean/Core/Probatio.lean:224; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-312 | `probatio:error.py::Invalid.__str__` | `Core.SchemaError.str` | correct | site-packages/probatio/error.py:277-284; HALean/Core/Probatio.lean:193; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-313 | `probatio:_messages.py::_display` | `Core.displayList` | correct | site-packages/probatio/_messages.py:160-165; HALean/Core/Probatio.lean:437; sbs 05. Note: probatio 0.13.0 is the pinned and the installed version (logs-manifest/py-direct.log, first entry) |
| M-314 | `helpers/config_validation.py::string` | `Core.cvString` | correct | up:helpers/config_validation.py:653-668; HALean/Core/ConfigValidation.lean:25; sbs 05 |
| M-315 | `helpers/config_validation.py::entity_id` | `Core.cvEntityId` | correct | up:helpers/config_validation.py:317-323; HALean/Core/ConfigValidation.lean:50; sbs 05. Note: by the comparison row named here |
| M-316 | `helpers/config_validation.py::_entity_ids` | `Core.cvEntityIds`, `Core.pyIter` | correct | up:helpers/config_validation.py:348-356; HALean/Core/ConfigValidation.lean:68; sbs 05. Note: logs-manifest/py-direct.log [M-316]. SCH-4 |
| M-317 | `helpers/config_validation.py::entity_ids` | `Core.cvEntityIds` | correct | up:helpers/config_validation.py:359-361; HALean/Core/ConfigValidation.lean:68; sbs 05. Note: ServicesJson.lean:136-137, up:helpers/config_validation.py:369-372 |
| M-318 | `helpers/config_validation.py::entity_domain` | `Core.cvEntityDomain` | correct | up:helpers/config_validation.py:406-417; HALean/Core/ConfigValidation.lean:94; sbs 05 |
| M-319 | `helpers/config_validation.py::entities_domain` | `Core.cvEntitiesDomain` | correct | up:helpers/config_validation.py:420-442; HALean/Core/ConfigValidation.lean:79; sbs 05 |
| M-320 | `helpers/config_validation.py::color_hex` | `Core.cvColorHex` | correct | up:helpers/config_validation.py:463-470; HALean/Core/ConfigValidation.lean:105; sbs 05 |
| M-322 | `helpers/config_validation.py::positive_timedelta` | `Core.cvPositiveTimedelta` | correct | up:helpers/config_validation.py:576-580; HALean/Core/ConfigValidation.lean:198; sbs 05. Note: ServicesJson.lean:113-135 (all nine names present) |
| M-323 | `helpers/config_validation.py::icon` | `Core.cvIcon` | correct | up:helpers/config_validation.py:450-457; HALean/Core/ConfigValidation.lean:125; sbs 05. Note: ServicesJson.lean:122, HALean/Helpers/Common.lean:201 |
| M-324 | `helpers/config_validation.py::schema_with_slug_keys` | `Helpers.slugKeys` | correct | up:helpers/config_validation.py:620-640; HALean/Helpers/Common.lean:158; sbs 09. Note: logs-manifest/probe-helpers.log [M-324]; sbs 09. HLP-4, HLP-16 |
| M-325 | `helpers/config_validation.py::_make_entity_service_schema` | `Helpers.entityServiceFields`, `Helpers.validateEntityCall` | correct | up:helpers/config_validation.py:1360-1378; HALean/Helpers/Common.lean:227; sbs 09. Note: logs-manifest/probe-helpers.log [M-325/M-326] |
| M-326 | `probatio:_engine.py::_MappingValidator._apply` | `Helpers.validateEntityCall` | correct | site-packages/probatio/_engine.py:368-415; HALean/Helpers/Common.lean:236; sbs 09. Note: logs-manifest/probe-helpers.log [M-325/M-326] |
| M-327 | `helpers/service.py::entity_service_call` | `Helpers.Helpers.call` | correct | up:helpers/service.py:886-926; HALean/Helpers/Component.lean:238; sbs 09. Note: logs-manifest/probe-helpers.log [M-327/M-329/M-330] |
| M-328 | `helpers/service.py::_resolve_entity_service_call_entities` | `Helpers.targetOf`, `Helpers.selectTargets` | correct | up:helpers/service.py:679-772; HALean/Helpers/Common.lean:253; sbs 09. Note: logs-manifest/probe-helpers.log [M-328]. `all` selects entities of other helper domains too (HLP-1) |
| M-329 | `helpers/service.py::_get_permissible_entity_candidates` | `Helpers.selectTargets` | correct | up:helpers/service.py:632-676; HALean/Helpers/Common.lean:272; sbs 09. Note: logs-manifest/probe-helpers.log [M-327/M-329/M-330] |
| M-330 | `helpers/service.py::_async_handle_entity_calls` | `Helpers.Helpers.call` | correct | up:helpers/service.py:775-827; HALean/Helpers/Component.lean:238; sbs 09. Note: logs-manifest/probe-helpers.log [M-327/M-329/M-330] |
| M-331 | `helpers/entity.py::Entity._stringify_state` | `Helpers.stringifyState`, `Helpers.floatPrec15` | correct | up:helpers/entity.py:1069-1082; HALean/Helpers/Common.lean:116; sbs 09. Note: logs-manifest/probe-helpers.log [M-331], logs-manifest/py-direct.log [M-331] |
| M-332 | `helpers/entity.py::Entity.__async_calculate_state` | `Helpers.tailAttrs` | correct | up:helpers/entity.py:1090-1185; HALean/Helpers/Common.lean:126; sbs 09. Note: sbs 09 row `__async_calculate_state` |
| M-334 | `helpers/entity.py::ToggleEntity.state` | `Helpers.InputBoolean.Entity.state` | correct | up:helpers/entity.py:1779-1783; HALean/Helpers/InputBoolean.lean:56; sbs 09 |
| M-335 | `helpers/event.py::_TrackPointUTCTime.__call__` | `Helpers.Timer.Entity.due`, `Helpers.Helpers.tick` | correct | up:helpers/event.py:1469-1488; HALean/Helpers/Timer.lean:195; sbs 09. Note: logs-manifest/probe-helpers.log [M-402/M-335]. HLP-21 |
| M-336 | `components/input_boolean/__init__.py::async_setup` | `Helpers.InputBoolean.decodeConfig`, `Helpers.InputBoolean.services`, `Helpers.Helpers.setup` | correct | up:components/input_boolean/__init__.py:91-145; HALean/Helpers/InputBoolean.lean:36; sbs 09. Note: logs-manifest/probe-helpers.log [M-336] |
| M-337 | `components/input_boolean/__init__.py::InputBoolean.__init__` | `Helpers.InputBoolean.Entity.create` | correct | up:components/input_boolean/__init__.py:156-160; HALean/Helpers/InputBoolean.lean:50; sbs 09 |
| M-338 | `components/input_boolean/__init__.py::InputBoolean.async_added_to_hass` | `Helpers.InputBoolean.Entity.create` | correct | up:components/input_boolean/__init__.py:198-206; HALean/Helpers/InputBoolean.lean:50; sbs 09. Note: logs-manifest/probe-helpers.log [M-338] |
| M-339 | `components/input_boolean/__init__.py::InputBoolean.extra_state_attributes` | `Helpers.InputBoolean.Entity.attrs` | correct | up:components/input_boolean/__init__.py:193-195; HALean/Helpers/InputBoolean.lean:59; sbs 09 |
| M-342 | `components/input_number/__init__.py::_cv_input_number` | `Helpers.InputNumber.checkConfig` | correct | up:components/input_number/__init__.py:52-65; HALean/Helpers/InputNumber.lean:58; sbs 09. Note: logs-manifest/probe-helpers.log [M-342], logs-manifest/py-direct.log [M-342] |
| M-343 | `components/input_number/__init__.py::async_setup` | `Helpers.InputNumber.decodeConfig`, `Helpers.InputNumber.services`, `Helpers.Helpers.setup` | correct | up:components/input_number/__init__.py:112-167; HALean/Helpers/InputNumber.lean:75; sbs 09. Note: logs-manifest/probe-helpers.log [M-336] (same code path) |
| M-344 | `components/input_number/__init__.py::InputNumber.__init__` | `Helpers.InputNumber.Entity.create` | correct | up:components/input_number/__init__.py:219-223; HALean/Helpers/InputNumber.lean:88; sbs 09 |
| M-345 | `components/input_number/__init__.py::InputNumber._update_config_attributes` | `Helpers.InputNumber.Entity.attrs` | correct | up:components/input_number/__init__.py:225-234; HALean/Helpers/InputNumber.lean:102; sbs 09 |
| M-346 | `components/input_number/__init__.py::InputNumber.async_added_to_hass` | `Helpers.InputNumber.Entity.create` | overstated | up:components/input_number/__init__.py:263-281; HALean/Helpers/InputNumber.lean:88; sbs 09. the parser is not `float()` for Unicode digits and `\x0b`/`\x0c` padding (HLP-11). See below |
| M-347 | `components/input_number/__init__.py::InputNumber.extra_state_attributes` | `Helpers.InputNumber.Entity.attrs` | correct | up:components/input_number/__init__.py:255-260; HALean/Helpers/InputNumber.lean:102; sbs 09 |
| M-351 | `components/number/__init__.py::NumberEntity.capability_attributes` | `Helpers.InputNumber.Entity.attrs` | correct | up:components/number/__init__.py:218-234; HALean/Helpers/InputNumber.lean:102; sbs 09. Note: sbs 09 row `NumberEntity.capability_attributes` |
| M-352 | `components/number/__init__.py::NumberEntity.state` | `Helpers.InputNumber.Entity.state` | correct | up:components/number/__init__.py:338-340; HALean/Helpers/InputNumber.lean:97; sbs 09 |
| M-353 | `components/number/__init__.py::NumberEntity._calculate_step` | `Helpers.InputNumber.Entity.attrs` | correct | up:components/number/__init__.py:312-321; HALean/Helpers/InputNumber.lean:102; sbs 09. Note: sbs 09 |
| M-354 | `components/input_select/__init__.py::_cv_input_select` | `Helpers.InputSelect.decode` | correct | up:components/input_select/__init__.py:85-94; HALean/Helpers/InputSelect.lean:49; sbs 09. Note: logs-manifest/probe-helpers.log [M-354/M-355] |
| M-355 | `components/input_select/__init__.py::_remove_duplicates` | `Helpers.InputSelect.dedup`, `Helpers.InputSelect.decode` | overstated | up:components/input_select/__init__.py:68-82; HALean/Helpers/InputSelect.lean:45; sbs 09. the warning text differs for `name: ""` and warnings are lost when another item is invalid (HLP-15, HLP-4). See below |
| M-356 | `components/input_select/__init__.py::async_setup` | `Helpers.InputSelect.decodeConfig`, `Helpers.InputSelect.services`, `Helpers.Helpers.setup` | correct | up:components/input_select/__init__.py:136-223; HALean/Helpers/InputSelect.lean:63; sbs 09. Note: logs-manifest/probe-helpers.log [M-336] (same code path) |
| M-359 | `components/input_select/__init__.py::InputSelect.extra_state_attributes` | `Helpers.InputSelect.Entity.attrs` | correct | up:components/input_select/__init__.py:306-308; HALean/Helpers/InputSelect.lean:94; sbs 09 |
| M-363 | `components/select/__init__.py::SelectEntity.capability_attributes` | `Helpers.InputSelect.Entity.attrs` | correct | up:components/select/__init__.py:108-112; HALean/Helpers/InputSelect.lean:94; sbs 09 |
| M-370 | `components/input_text/__init__.py::_cv_input_text` | `Helpers.InputText.decode` | correct | up:components/input_text/__init__.py:71-84; HALean/Helpers/InputText.lean:65; sbs 09. Note: logs-manifest/probe-helpers.log [M-370/M-371], logs-manifest/py-direct.log [M-370] |
| M-371 | `components/input_text/__init__.py::async_setup` | `Helpers.InputText.decodeConfig`, `Helpers.InputText.services`, `Helpers.Helpers.setup` | correct | up:components/input_text/__init__.py:117-166; HALean/Helpers/InputText.lean:84; sbs 09. Note: logs-manifest/probe-helpers.log [M-370/M-371]. HLP-23 |
| M-372 | `components/input_text/__init__.py::InputText.__init__` | `Helpers.InputText.Entity.create` | correct | up:components/input_text/__init__.py:203-206; HALean/Helpers/InputText.lean:96; sbs 09 |
| M-373 | `components/input_text/__init__.py::InputText._update_config_attributes` | `Helpers.InputText.Entity.attrs` | correct | up:components/input_text/__init__.py:208-217; HALean/Helpers/InputText.lean:127; sbs 09 |
| M-374 | `components/input_text/__init__.py::InputText.async_added_to_hass` | `Helpers.InputText.Entity.create` | correct | up:components/input_text/__init__.py:243-254; HALean/Helpers/InputText.lean:96; sbs 09. Note: logs-manifest/probe-helpers.log [M-374/M-376/M-377] |
| M-375 | `components/input_text/__init__.py::InputText.extra_state_attributes` | `Helpers.InputText.Entity.attrs` | correct | up:components/input_text/__init__.py:238-240; HALean/Helpers/InputText.lean:127; sbs 09 |
| M-376 | `components/input_text/__init__.py::InputText.async_set_value` | `Helpers.InputText.setValue`, `Helpers.InputText.handle` | correct | up:components/input_text/__init__.py:257-268; HALean/Helpers/InputText.lean:140; sbs 09. Note: logs-manifest/probe-helpers.log [M-374/M-376/M-377] |
| M-377 | `components/text/__init__.py::TextEntity.state` | `Helpers.InputText.Entity.state` | correct | up:components/text/__init__.py:134-153; HALean/Helpers/InputText.lean:111; sbs 09. Note: logs-manifest/probe-helpers.log [M-374/M-376/M-377] |
| M-378 | `components/text/__init__.py::TextEntity.capability_attributes` | `Helpers.InputText.Entity.attrs` | correct | up:components/text/__init__.py:122-129; HALean/Helpers/InputText.lean:127; sbs 09 |
| M-379 | `components/text/__init__.py::TextEntity.min` | `Helpers.InputText.Entity.minLen` | correct | up:components/text/__init__.py:175-177; HALean/Helpers/InputText.lean:106; sbs 09 |
| M-380 | `components/text/__init__.py::TextEntity.max` | `Helpers.InputText.Entity.maxLen` | correct | up:components/text/__init__.py:190-192; HALean/Helpers/InputText.lean:107; sbs 09 |
| M-381 | `components/text/__init__.py::TextEntity.pattern_cmp` | `Helpers.Pattern.parse`, `Helpers.Pattern.isMatch` | overstated | up:components/text/__init__.py:196-203; HALean/Helpers/Pattern.lean:178; sbs 09. `\s` misses four ASCII characters; the parser accepts patterns `re` rejects (HLP-5 to HLP-9, HLP-17). See below |
| M-382 | `components/counter/__init__.py::async_setup` | `Helpers.Counter.decodeConfig`, `Helpers.Counter.services`, `Helpers.Helpers.setup` | correct | up:components/counter/__init__.py:98-136; HALean/Helpers/Counter.lean:56; sbs 09. Note: sbs 09 |
| M-383 | `components/counter/__init__.py::Counter.__init__` | `Helpers.Counter.Entity.create` | correct | up:components/counter/__init__.py:168-171; HALean/Helpers/Counter.lean:74; sbs 09. Note: logs-manifest/probe-helpers.log [M-383/M-386] |
| M-384 | `components/counter/__init__.py::Counter.extra_state_attributes` | `Helpers.Counter.Entity.attrs` | correct | up:components/counter/__init__.py:210-221; HALean/Helpers/Counter.lean:83; sbs 09 |
| M-386 | `components/counter/__init__.py::Counter.async_added_to_hass` | `Helpers.Counter.Entity.create` | overstated | up:components/counter/__init__.py:239-248; HALean/Helpers/Counter.lean:74; sbs 09. a last state `int()` can read is also answered unsupported (HLP-12). See below |
| M-391 | `components/timer/__init__.py::_format_timedelta` | `Helpers.Timer.formatTd` | correct | up:components/timer/__init__.py:77-81; HALean/Helpers/Timer.lean:28; sbs 09. Note: logs-manifest/probe-helpers.log [M-391/M-393], logs-manifest/py-direct.log [M-391] |
| M-392 | `components/timer/__init__.py::async_setup` | `Helpers.Timer.decodeConfig`, `Helpers.Timer.services`, `Helpers.Helpers.setup` | correct | up:components/timer/__init__.py:114-171; HALean/Helpers/Timer.lean:74; sbs 09. Note: logs-manifest/probe-helpers.log [M-336] (same code path) |
| M-393 | `components/timer/__init__.py::Timer.__init__` | `Helpers.Timer.Entity.create`, `Helpers.Timer.decode` | correct | up:components/timer/__init__.py:208-221; HALean/Helpers/Timer.lean:96; sbs 09. Note: logs-manifest/probe-helpers.log [M-391/M-393] |
| M-394 | `components/timer/__init__.py::Timer.async_added_to_hass` | `Helpers.Timer.Entity.create` | correct | up:components/timer/__init__.py:287-327; HALean/Helpers/Timer.lean:96; sbs 09. Note: Timer.lean:96-104; logs-manifest/probe-helpers.log [M-394]. Every non-idle last state gets the same refusal text (HLP-24); HLP-14 |
| M-395 | `components/timer/__init__.py::Timer.extra_state_attributes` | `Helpers.Timer.Entity.attrs` | correct | up:components/timer/__init__.py:260-278; HALean/Helpers/Timer.lean:108; sbs 09 |
| M-396 | `components/timer/__init__.py::Timer.async_start` | `Helpers.Timer.start` | correct | up:components/timer/__init__.py:330-355; HALean/Helpers/Timer.lean:135; sbs 09 |
| M-397 | `components/timer/__init__.py::Timer.async_change` | `Helpers.Timer.change` | correct | up:components/timer/__init__.py:358-386; HALean/Helpers/Timer.lean:148; sbs 09 |
| M-398 | `components/timer/__init__.py::Timer.async_pause` | `Helpers.Timer.pause` | correct | up:components/timer/__init__.py:389-399; HALean/Helpers/Timer.lean:164; sbs 09 |
| M-402 | `components/timer/__init__.py::Timer._fire_event_and_write_state` | `Helpers.Timer.fireAndWrite` | correct | up:components/timer/__init__.py:469-478; HALean/Helpers/Timer.lean:123; sbs 09. Note: logs-manifest/probe-helpers.log [M-402/M-335] |

## Not correct

### stale (10)

**M-15** `helpers/script.py::_ScriptRun.async_run` → `Automation.exec`, `Automation.conditionFail`, `Automation.finishRun`, `Automation.finishBranch` (missing)

Note: "sub-scripts re-raise everything but _ConditionFail (RunEnd.raises)"

`lean:` lists `HALean.Automation.finishBranch`. There is no such declaration. Until commit bf053c0 ("Engine: no partial definitions left") `Engine.lean` had `partial def finishBranch`; the commit replaced it by the structure field `Handlers.finishBranch` and the implementation `finishBranchH` (`HALean/Automation/Engine.lean:589`, `:701`). logs-manifest/git-history.log. The note (sub-scripts re-raise everything but `_ConditionFail`, `RunEnd.raises`) is correct: `Script.lean:79-81`, `up:helpers/script.py:520-538`.

**M-33** `components/homeassistant/triggers/state.py::async_attach_trigger` → `Automation.addPeriodPending`, `Automation.decodeTrigger`, `Automation.onStateTrigger`, `Automation.renderPeriod`

Note: "templated 'for' rejected; matchAll is by key presence (so an explicit null 'to' works as upstream); templated for: rendered when the trigger matches (cv.positive_time_period_template)"

The note has two clauses that contradict each other: "templated 'for' rejected" and "templated for: rendered when the trigger matches". The first was written in commit 5761000 (2026-11-20); commit 20e6a22 ("Templates part 6: this, templated for, ...") added the second and left the first (logs-manifest/git-history.log). At the reviewed commit `forPeriod?` accepts a template (`Config.lean:410-431`, called at `:730`) and `onStateTrigger` renders it (`Engine.lean:1121-1127`). Probe: `for: "{{ 2 }}"` loads, the automation triggers 2 s after the change with `trigger.for` = `0:00:02` (logs-manifest/probe-automation.log [M-33], first block). The other clauses are correct: match-all is decided by key presence (`Config.lean:730`, `up:components/homeassistant/triggers/state.py:125`; logs-manifest/probe-automation.log [M-33], second and third block).

**M-65** `helpers/template/states.py::TemplateStateBase.__getitem__` → `Template.stateAttr`

Note: "last_changed/last_updated/context are opaque: using them is a render error"

Written in commit 5761000. Since commit 06e09f6 `EntityState` carries `lastChangedUs` / `lastUpdatedUs` (logs-manifest/git-history.log) and `stateAttr` returns datetimes (`HALean/Template/Render.lean:266-269`). Probe: `states.sensor.a.last_changed` and `.last_updated` render `2023-11-14 22:13:20+00:00`; for a state sent without timestamps `last_changed` renders `1970-01-01 00:00:00+00:00` (no error); `context` and `last_reported` are render errors (logs-manifest/probe-template.log [M-65]). HA renders a datetime (logs-manifest/probe-ha.log [M-65]).

**M-87** `components/template/trigger.py::async_attach_trigger` → `Automation.onTemplateTrigger`, `Automation.initArmed`

Note: "static for: only; trigger templates may not use variables (trigger_variables unsupported); templated for: supported"

"static for: only; trigger templates may not use variables (trigger_variables unsupported)" dates from commit 5761000. "templated for: supported" was appended later (logs-manifest/git-history.log); trigger_variables arrived with commit 0148bce ("Templated trigger_variables and a trigger's own variables"). At the reviewed commit the template is checked against the trigger-variable names (`Config.lean:862`, `tnm` from `:1242`) and `for` goes through `forPeriod?` (`:865`). The code comment at `Config.lean:857-858` is stale in the same way. Probe: a template trigger that uses the trigger variable `lim` and `for: "{{ 1 }}"` loads and fires with `trigger.for` = `0:00:01` (logs-manifest/probe-automation.log [M-87]).

**M-158** `helpers/script.py::_ScriptRun._async_step_parallel` → `Automation.step`, `Automation.drive`, `Automation.finishBranch` (missing), `Automation.resumeWoken`

Note: "gather: branches start after the current callbacks, all run to the end, then the first branch (in order) that raised re-raises in the parent, which also resumes later"

Same missing name as M-15 (`finishBranchH`, `Engine.lean:701`). logs-manifest/git-history.log. The note is correct: `Engine.lean:632-644, 701-726`; logs-manifest/probe-automation.log [M-158/M-159] (branch 3 runs to its service call, the abort of branch 1 reaches the parent after it).

**M-252** `components/script/__init__.py::ScriptEntity._async_start_run` → `Automation.startScript` (missing), `Automation.callLocal`, `Automation.continueNow` (missing)

Note: "script_stack: copied for wait=True, fresh for turn_on"

`lean:` lists `HALean.Automation.startScript` and `HALean.Automation.continueNow`. Both were `partial def`s until bf053c0; now `Handlers.startScript` / `startScriptH` (`Engine.lean:594`, `:817`) and `Handlers.continueNow` / `continueNowH` (`:591`, `:763`). logs-manifest/git-history.log. The file header of `Engine.lean` (lines 13-14) still names `startScript`. The note (script_stack copied for wait=True, fresh for turn_on) is correct: `Engine.lean:877-881, 889`.

**M-253** `components/script/__init__.py::ScriptEntity._async_run` → `Automation.startScript` (missing), `Script.scriptThis`

No note.

Same missing name as M-252 (`startScriptH`, `Engine.lean:817`). logs-manifest/git-history.log. No note.

**M-255** `components/script/__init__.py::ScriptEntity._service_handler` → `Script.planCall`, `Script.callResponse`, `Automation.answer` (missing)

No note.

`lean:` lists `HALean.Automation.answer`; now `Handlers.answer` / `answerH` (`Engine.lean:590`, `:732`). logs-manifest/git-history.log. No note.

**M-260** `helpers/script.py::_ScriptRun._finish` → `Automation.finishRun`, `Automation.writeEntity`, `Automation.releaseQueue` (missing)

No note.

`lean:` lists `HALean.Automation.releaseQueue`; now `Handlers.releaseQueue` / `releaseQueueH` (`Engine.lean:588`, `:688`). logs-manifest/git-history.log. No note.

**M-261** `helpers/script.py::_ScriptRun._async_run_long_action` → `Automation.cancelRun` (missing), `Automation.stoppedQuietly`

Note: "CancelledError from an awaited script run ends a parallel branch, or the whole run"

`lean:` lists `HALean.Automation.cancelRun`; now `Handlers.cancelRun` / `cancelRunH` (`Engine.lean:593`, `:799`). logs-manifest/git-history.log. The note is correct: `Engine.lean:799-808`.

### false (2)

**M-274** `core.py::HassJobType` → `Core.Hass.Hass`, `Core.Hass.Action`

Note: "Coroutinefunction (async listeners, Hass.asyncJobs; all handlers) and Callback (other listeners); Executor is rejected"

The protocol of `halean-core` has no way to state a job type other than `"async": true|false` (`Exe/Core.lean:24, 159`). A listener sent with `"executor": true, "job_type": "Executor"` is accepted and runs as a `@callback` (logs-manifest/probe-core.log [M-274]). There is no refusal in `HALean/Core/Hass.lean` either (no occurrence of `executor`). M-275 and M-239 word it correctly ("not modelled"). The mapping is loose: the enum `HassJobType` is mapped to the whole state structure `Hass` and to `Action`; what stands for it is the field `Hass.asyncJobs` (`Hass.lean:223, 472`).

**M-281** `probatio:_compile.py::_compile_callable` → `Core.CvFn.run`

Note: "Invalid passes through, other exceptions escape (VErr.raise); no translated cv function raises ValueError (probatio 0.13.0)"

`cv.time_period_str("0:0:nan")` raises `ValueError: cannot convert float NaN to integer`; under a schema `_compile_callable` turns it into `not a valid value: cannot convert float NaN to integer`. The same for `cv.time_period_dict` with a NaN value (logs-manifest/py-direct.log [M-281]). HALean answers `unsupported` for these inputs (`HALean/Core/ConfigValidation.lean:133-136`; README line 335), so the `ValueError` branch of `_compile_callable` (`probatio/_compile.py:632-656`) is not translated. The first half of the note (Invalid passes through, other exceptions escape) is correct (`ConfigValidation.lean:204-216`). sbs 05 row `_compile_callable` says the same.

### overstated (18)

**M-8** `helpers/condition.py::time` → `Automation.timeCond`, `Automation.resolveTimeBound`

Note: "timestamp/uptime sensor bounds are converted with the shell's tz offset, like the local time; dates only ciso8601 would parse raise 'unsupported'; a time entity is read with the template engine's strptime(state, "%H:%M:%S")"

The note says "dates only ciso8601 would parse raise 'unsupported'". `resolveTimeBound` throws the parser's message (`Condition.lean:248-249`), `evalCond` turns it into a condition error (`:358-361`) and `checkAutomationConditions` counts that as false (`:407-411`). Nothing marked unsupported reaches the shell: the only output is the debug log `conditions not met` (logs-manifest/probe-automation.log [M-8], first block). HA parses `2023-11-14` as midnight and runs the action (logs-manifest/probe-ha.log [M-8]). The other two clauses are correct (logs-manifest/probe-automation.log [M-8], second and third block; `Condition.lean:232-242, 250-253`).

**M-17** `helpers/script.py::_ScriptRun._handle_exception` → `Automation.unwindError`, `Automation.resumeService`

No note.

No note. `_handle_exception` re-raises every `CONFIGURATION_ERRORS` member, and `ServiceNotFound` is one (`up:helpers/script.py:140-147, 633-634`). The Lean side has three kinds; its doc comment puts ServiceNotFound under `haError`, "swallowed by any enclosing step with continue_on_error" (`Script.lean:56-57`), and the shell sends HA's `not_found` as `ha_error` (`bridge/bridge.py:81`). Real HA: a call to a missing service with `continue_on_error: true` ends the run, the following `event` action does not fire (logs-manifest/probe-ha.log [M-17]). `halean-automation` with the result the bridge sends: the run goes on and fires the event (logs-manifest/probe-m17-engine.log). `HALean/Script/Service.lean:159-160` classifies the same error as `invalid` for the script services. Not listed in `07-automation/FINDINGS.md` (its harness chooses the error kind itself).

**M-22** `helpers/script.py::_ScriptRun._async_do_step_repeat` → `Automation.step`, `Automation.REPEAT_TERMINATE_ITERATIONS`

Note: "count (incl. templated), for_each, while, until; the `repeat` variable is local to its loop (currentRepeat)"

The note lists `count` and says the `repeat` variable is local to its loop. AUT-6: a static `count: 2.5` runs 25 times (`Config.lean:1075` takes the mantissa). AUT-8: an assignment to `repeat` inside the loop goes to the run's top-level variables, upstream assigns the local (`07-automation/FINDINGS.md`). Templated count, for_each, while, until and the read side of `repeat` work (logs-manifest/probe-automation.log [M-22]; `Script.lean:45-51, 309-341, 442-463`).

**M-56** `helpers/template/__init__.py::Template.__init__` → `Template.compile`

Note: "source stripped; is_static decided on the unstripped text"

"source stripped": `compile` uses `raw.trim` (`HALean/Template/Syntax.lean:621`), which strips four ASCII characters; `str.strip()` strips every Unicode whitespace character. A static template padded with U+00A0 renders the int `42` in HA and the padded text as a str in HALean (TPL-18, `06-templates/FINDINGS.md`). The second clause (is_static on the unstripped text) is correct (logs-manifest/probe-template.log [M-56]).

**M-59** `helpers/template/__init__.py::_cached_parse_result` → `Template.parseResult`, `Template.literalEval`

Note: "ast.literal_eval translated for numbers, strings, True/False/None, lists, tuples, dicts; sets become lists, bytes stay strings"

The note says `ast.literal_eval` is translated for strings and dicts and names two deviations (sets, bytes). The template review found more: `\ooo`, `\u`, `\U`, `\N{}` escapes are not decoded (TPL-1); a dict literal keeps duplicate keys (TPL-2); `set()` and `...` come back as strings, a list holding a complex number is an error (TPL-28); `[--4]` is accepted (TPL-29). The two deviations the note names are as stated (logs-manifest/probe-template.log [M-59]).

**M-80** `helpers/service.py::async_prepare_call_from_config` → `Automation.step`, `Automation.normalizeTarget`

Note: "static or templated names (cv.service after rendering); data then data_template, each must render to a mapping; a mapping or whole-template target; the action's own entity_id (comp_entity_ids, HALean compEntityIds) written into the target last; templated entity_id normalised like comp_entity_ids_or_uuids (no registry UUIDs)"

The note describes the normalisation for a templated `entity_id` only, and the Lean code does it only then (`Script.lean:259`: `if tgt.hasTemplate`). Upstream applies `cv.comp_entity_ids_or_uuids` to every target that has an `entity_id` (`up:helpers/service.py:303-310`), and the action schema has already done so at load. Probe: `target: {entity_id: "Light.A, light.b"}` is sent as that string, and `entity_id: "not an id"` loads and is sent; HA's schema gives `['light.a', 'light.b']` and rejects the second (logs-manifest/probe-m80-static-target.log). Related to AUT-4. The other clauses hold (logs-manifest/probe-automation.log [M-80]).

**M-95** `helpers/script_variables.py::ScriptRunVariables._assign` → `Automation.setVar`

Note: "only `repeat` is ever defined locally, so assignments go to the run's top level"

The note says "only `repeat` is ever defined locally, so assignments go to the run's top level". The conclusion does not hold for the name `repeat` itself: `_assign` (`up:helpers/script_variables.py:212-238`) assigns to the scope that defines the name. `setVar` (`Condition.lean:40-43`) always works on the run's list, and the loop keeps showing its own `repeat`. AUT-8 (`07-automation/FINDINGS.md`). `wait` in a parallel branch is also local (`BRANCH_LOCAL`, `Engine.lean:325`), which the note does not mention.

**M-104** `helpers/template/extensions/datetime.py::DateTimeExtension.timestamp_custom` → `Template.callV` (partial), `Template.strftime` (partial)

Note: "glibc strftime in the C locale; %Z and unlisted directives are errors"

"glibc strftime in the C locale": `datetime.strftime('%Y')` gives `0999` for year 999, libc's `strftime` gives `999` (logs-manifest/py-direct.log [M-104]); HALean follows libc (TPL-24). The default `date_format` of `timestamp_custom` is `%Y-%m-%d %H:%M:%S` upstream and `%Y-%m-%d` in HALean (logs-manifest/probe-template.log [M-104], TPL-22). `%Z` and unlisted directives are render errors as the note says (logs-manifest/probe-template.log [M-104]). `callV` and `strftime` are `partial def`s.

**M-107** `util/dt.py::parse_datetime` → `Template.parseDatetime`

Note: "DATETIME_RE translated; strings only ciso8601 would accept are errors"

(1) The note says strings only ciso8601 accepts are errors. `2023-11-14T24:00:00` matches `DATETIME_RE` after ciso8601 would have accepted it: HALean returns `None` (logs-manifest/probe-template.log [M-107]), HA returns `2023-11-15 00:00:00` (logs-manifest/py-direct.log [M-107]). Finding TPL-23 (`06-templates/FINDINGS.md`). Date-only and basic-format strings are render errors as the note says (TPL-43). (2) `util/dt.py` defines `parse_datetime` four times; the manifest hash `dbd0af9665451de8` is the hash of the first, a one-line `@overload` stub at line 207, not of the implementation at lines 220-256 (logs-manifest/overload-stubs.log).

**M-143** `util/__init__.py::slugify` → `Automation.slugify?`, `Automation.slugifyChars`, `Automation.subRuns`, `Automation.delDigitCommas`

Note: "python-slugify 9.1.2 legacy pipeline, one Lean step per line (ASCII, no HTML entities; non-ASCII names reject `this`). Proved about it: slugifyChars_valid (any non-empty result is a valid slug), slugifyChars_of_valid (valid slugs are fixed points), slugify_fixed_iff"

"no HTML entities": `slugify?` returns `none` for any text that holds both `&` and `;` (`HALean/Automation/Slugify.lean:52`); python-slugify only rewrites `&name;`, `&#123;`, `&#x1f;`. `a;&` is refused by HALean and slugified by HA (SCH-5, `05-service-schemas/FINDINGS.md`). The three theorems exist (`SlugifySpec.lean:309, 342, 413`); a non-ASCII alias makes `this` a load error (logs-manifest/probe-automation.log [M-143]).

**M-145** `helpers/entity_platform.py::EntityPlatform._async_add_entity` → `Automation.automationEntityIds`

Note: "entity ids assigned in config order"

`EntityPlatform._async_add_entity` (`up:helpers/entity_platform.py:854-925`) starts and finishes the adding of one entity and rolls back on failure. It does not choose entity ids. `automationEntityIds` (`Config.lean:1165-1178`) models the result of the loop in `_async_add_entities` plus `async_get_available_entity_id` (its own doc comment says so). The hash watches a function none of whose statements are translated.

**M-146** `helpers/config_validation.py::_positive_time_period_template_complex` → `Automation.forPeriod?`, `Automation.cvPositiveTimePeriod`, `Automation.timePeriodDict`

Note: "also translates the schema assignments positive_time_period_template, positive_time_period and time_period_dict (vol.Any/vol.All, not functions, so not hashed)"

The note says the entry also translates `positive_time_period_template`, `positive_time_period` and `time_period_dict`. For a static value `forPeriod?` calls `durationMs` (`Config.lean:269-294, 415, 418, 432`), a second hand-written parser: it accepts `"0.5:00"`, `{secs: 1}`, `{weeks: 1}` and `{}` and refuses `true`; upstream does the opposite in each case (AUT-15, `07-automation/FINDINGS.md`). Rendered periods use `cvPositiveTimePeriod` as stated. The function of the entry itself (templated dict: keys and static values checked) is translated at `Config.lean:419-431`. The note says "vol.Any/vol.All"; upstream uses probatio.

**M-240** `components/script/config.py::_async_validate_config_item` → `Script.decodeScript`, `Script.decodeFields`, `Script.isSlug`

Note: "SCRIPT_ENTITY_SCHEMA and the object id check; an invalid config is rejected (HA makes it an unavailable entity). Also rejected: blueprints, script.reload actions, device/area/floor/label targets of script.turn_on/off/toggle, waits mentioning script entities, the trigger condition, last_action, last_triggered other than this.attributes.last_triggered, templates using names that are not fields, variables or passed by other scripts. Selectors are not validated"

The note says `SCRIPT_ENTITY_SCHEMA` is translated and lists what else is rejected. Not in the list: `alias: true`, `alias: ""`, `icon: ["mdi:x"]`, `description: false`, `stored_traces: 0`, `required: "true"` load in HA and are refused by HALean (`HALean/Script/Config.lean:37-40, 109-123, 140-158`; SCR-10); `sequence: [{event: e, bogus: 1}]` is refused by HA and loaded (SCR-11). Source: `08-scripts/side-by-side.md` §1 (that directory has no `FINDINGS.md` at the reviewed state). The listed rejections are in the code (`Script/Config.lean:64-87`).

**M-259** `helpers/script.py::_ScriptRun.async_stop` → `Automation.stopRun`, `Automation.stoppedQuietly`

Note: "stopping a run stops the script runs it waits for; its caller gets None when it was stopped in a delay, wait or parallel step (_async_futures_with_timeout includes the stop future), CancelledError elsewhere"

The note says the caller gets `CancelledError` everywhere except in a delay, wait or parallel step. `stoppedQuietly` (`Engine.lean:550-553`) implements that rule. HA: when the run's own service step returns without suspending, the loop sees `_stop` before the next step and the caller gets `None`; HALean reports `cancelled` (`08-scripts/side-by-side.md` §4, case `h54`, SCR-6).

**M-346** `components/input_number/__init__.py::InputNumber.async_added_to_hass` → `Helpers.InputNumber.Entity.create`

Note: "restore: float() of the last state within the bounds, else min"

"restore: float() of the last state": `Entity.create` uses `Template.parseFloatStr` (`HALean/Helpers/InputNumber.lean:88-95`). A last state `٤٢` is 42.0 for `float()` and unreadable for HALean, which then restores `min` (HLP-11, `09-helpers/FINDINGS.md`). ASCII input behaves as stated (logs-manifest/probe-helpers.log [M-346]).

**M-355** `components/input_select/__init__.py::_remove_duplicates` → `Helpers.InputSelect.dedup`, `Helpers.InputSelect.decode`

Note: "with its warning"

"with its warning": upstream prints `name or "<unnamed>"`; HALean prints the empty name (HLP-15). When one item of the config is invalid, the warnings logged for the other items are not emitted (HLP-4). `09-helpers/FINDINGS.md`. The plain case is as stated (logs-manifest/probe-helpers.log [M-354/M-355]).

**M-381** `components/text/__init__.py::TextEntity.pattern_cmp` → `Helpers.Pattern.parse`, `Helpers.Pattern.isMatch`

Note: "a subset of re syntax; \d \w \s on ASCII only"

"a subset of re syntax; \d \w \s on ASCII only": `isSpaceChar` (`HALean/Helpers/Pattern.lean:22`) lacks U+001C to U+001F, which `\s` matches (HLP-9). The parser is not a subset parser: a quantifier after `$`, `{m,n}` where an atom is expected, `[\d-z]` and `[]-a]` are accepted or read differently where `re` raises or means something else (HLP-5 to HLP-8); `a{2}{x` is refused though `re` accepts it (HLP-17). `09-helpers/FINDINGS.md`.

**M-386** `components/counter/__init__.py::Counter.async_added_to_hass` → `Helpers.Counter.Entity.create`

Note: "a last state int() cannot read is unsupported"

"a last state int() cannot read is unsupported": the test is `Core.pyIntOfStr?`, which reads ASCII digits only. A last state `٤٢` is 42 for `int()`; HALean answers `unsupported` with the reason "int() raises ValueError" (HLP-12, `09-helpers/FINDINGS.md`). ASCII input behaves as stated (logs-manifest/probe-helpers.log [M-383/M-386]).

### correct for the wrong reason (3)

**M-76** `helpers/template/helpers.py::forgiving_boolean` → `Template.forgivingBool`, `Template.cvBoolean`

No note.

`helpers/template/helpers.py` defines `forgiving_boolean` three times. `find_node` takes the first, the one-line `@overload` signature at line 73. The manifest hash `1dc34205c0a38e69` is the hash of that stub; the implementation at lines 80-89 hashes to `08a01c7afee2fea1` (logs-manifest/overload-stubs.log). `drift.py check` reports the entry as not stale whatever happens to the body. The Lean definitions are the translation of the implementation (sbs 06: no difference found).

**M-239** `core.py::HomeAssistant.async_run_hass_job` → `Core.EventBus.runJob`, `Core.Hass.runJob`, `Core.Hass.recordDelivery`, `Core.Hass.runListener`, `Core.Hass.Hass.spawn`

Note: "callback jobs run at once; coroutine-function listeners go through _async_add_hass_job (eager task); executor jobs (threads) are not modelled; theorem runListener_deliveries (eager start)"

`core.py` defines `HomeAssistant.async_run_hass_job` three times; `find_node` takes the first, the `@overload` signature at lines 896-901. Manifest hash `e6a860ed9b453a87` = hash of the stub; the implementation at lines 913-938 hashes to `e4c55522a675824a` (logs-manifest/overload-stubs.log). The note is correct (sbs 04 row `async_run_hass_job`; theorem `runListener_deliveries`, `HALean/Core/HassProofs.lean:410`; logs-manifest/probe-core.log [M-274/M-275/M-239]).

**M-305** `probatio:validators/structural.py::EnsureList.__call__` → `Core.ensureList`

Note: "theorems ensureList_is_list, ensureList_list (probatio 0.13.0)"

`probatio/validators/structural.py` defines `EnsureList.__call__` four times; `find_node` takes the first, the one-line overload at line 297. Manifest hash `c49de88626b86ce6` = hash of the stub; the implementation at lines 305-309 hashes to `4be47a1d3a7b83f0` (logs-manifest/overload-stubs.log). The theorems named in the note exist (`HALean/Core/ProbatioProofs.lean:80, 83`).

## Entry-level structure facts

All numbers are over the 349 `translated` entries (`logs-manifest/structure-summary.log`, `structure.tsv`).

* Upstream node kinds: 264 `def`, 77 `async def`, 8 classes. No ref is missing.
* Entries that map a class, not a function (8): M-204 `SupportsResponse`, M-205 `Service`, M-206 `ServiceCall`, M-218 `HomeAssistantError`, M-219 `ServiceValidationError`, M-220 `ServiceNotFound`, M-224 `EventOrigin`, M-274 `HassJobType`.
* The entries name 535 Lean names, 355 distinct: 322 def, 13 partial, 7 structure, 7 inductive, 6 missing.
* `partial def`: 13 distinct names in 35 entries: `Template.callV` (14), `Core.runMapping` (6), `Automation.decodeAction` (3), `Automation.decodeCondition` (2), `Core.runAny` (2), `Core.runSequence` (2), `Automation.decodeComplex` (1), `Automation.renderComplex` (1), `Core.ServicesJson.decodeField` (1), `Core.reprHelper` (1), `Core.runAll` (1), `Template.applyTest` (1), `Template.strftime` (1).
  Entries: M-6, M-12, M-60, M-63, M-68, M-81, M-82, M-83, M-98, M-99, M-100, M-101, M-102, M-104, M-105, M-106, M-110, M-122, M-123, M-124, M-134, M-159, M-222, M-277, M-282, M-283, M-284, M-286, M-287, M-288, M-289, M-290, M-291, M-292, M-293.
* Missing Lean names: 6 distinct names in 7 entries, all removed by commit bf053c0 and still present as fields of the structure `Handlers` and as `...H` definitions:
  * `Automation.answer`: M-255
  * `Automation.cancelRun`: M-261
  * `Automation.continueNow`: M-252
  * `Automation.finishBranch`: M-15, M-158
  * `Automation.releaseQueue`: M-260
  * `Automation.startScript`: M-252, M-253
  These are the same six names as in `11-coverage-drift/logs/manifest-names.log`. Outside this scope, 1 `proven` entry carries one of them: M-28 `helpers/script.py::Script.async_run` (`Automation.startScript`).
* Refs that resolve to the first of several same-named definitions, an `@overload` stub (4): M-76, M-107, M-239, M-305 (`logs-manifest/overload-stubs.log`). The drift hash of these entries does not change when the implementation changes.
* Lean names shared by four or more entries (the hash of each of these upstream functions points at one large Lean definition):
  * `Automation.step` (def, HALean/Automation/Script.lean:218): 20 entries: M-16, M-18, M-19, M-20, M-21, M-22, M-23, M-24, M-25, M-26, M-27, M-80, M-94, M-96, M-149, M-150, M-151, M-152, M-156, M-158
  * `Template.callV` (partial, HALean/Template/Render.lean:1307): 14 entries: M-63, M-68, M-98, M-99, M-100, M-101, M-102, M-104, M-105, M-106, M-110, M-122, M-123, M-124
  * `Automation.decodeTrigger` (def, HALean/Automation/Config.lean:709): 9 entries: M-33, M-35, M-36, M-40, M-43, M-44, M-45, M-51, M-173
  * `Automation.callLocal` (def, HALean/Automation/Engine.lean:935): 7 entries: M-242, M-243, M-244, M-251, M-252, M-254, M-258
  * `Automation.onTemplateTrigger` (def, HALean/Automation/Engine.lean:1332): 6 entries: M-87, M-88, M-116, M-117, M-119, M-121
  * `Template.callDateTime` (def, HALean/Template/Render.lean:1158): 6 entries: M-127, M-128, M-130, M-131, M-132, M-133
  * `Core.Hass.runAction` (def, HALean/Core/Hass.lean:515): 6 entries: M-202, M-232, M-235, M-237, M-269, M-270
  * `Core.runMapping` (partial, HALean/Core/Schema.lean:114): 6 entries: M-282, M-283, M-284, M-286, M-287, M-288
  * `Helpers.Helpers.setup` (def, HALean/Helpers/Component.lean:140): 6 entries: M-336, M-343, M-356, M-371, M-382, M-392
  * `Automation.fireDue` (def, HALean/Automation/Engine.lean:1697): 5 entries: M-26, M-32, M-121, M-152, M-153
  * `Automation.attachTriggers` (def, HALean/Automation/Engine.lean:444): 5 entries: M-35, M-38, M-156, M-157, M-171
  * `Automation.evalCond` (def, HALean/Automation/Condition.lean:347): 4 entries: M-9, M-10, M-11, M-79
  * `Automation.finishRun` (def, HALean/Automation/Engine.lean:933): 4 entries: M-15, M-29, M-30, M-260
  * `Automation.onWebhook` (def, HALean/Automation/Engine.lean:1541): 4 entries: M-51, M-52, M-53, M-54
  * `Template.getTimestring` (def, HALean/Template/DateParse.lean:174): 4 entries: M-136, M-137, M-138, M-139
  * `Script.planCall` (def, HALean/Script/Entity.lean:188): 4 entries: M-242, M-243, M-244, M-255
  * `Script.reloadScripts` (def, HALean/Script/Service.lean:90): 4 entries: M-246, M-257, M-266, M-268
  * `Helpers.InputNumber.Entity.attrs` (def, HALean/Helpers/InputNumber.lean:102): 4 entries: M-345, M-347, M-351, M-353
* Entries whose Lean name does the job only in a loose sense (the name is a wider or a different definition; the note, where there is one, says what part is meant):
  * M-54 `components/webhook/__init__.py::async_register` → `Automation.onWebhook`: the webhook dispatcher stands for `async_register`.
  * M-112 `helpers/event.py::async_track_utc_time_change` → `Automation.TIME_CHANGE_MICROSECOND`: a constant stands for `async_track_utc_time_change`.
  * M-126 `core.py::StateMachine.get` → `Template.hassStatesGet`, `Core.StateMachine.get`: the template copy `hassStatesGet` is used by `expand` only; every other template lookup is exact (TPL-6).
  * M-141 `components/automation/__init__.py::BaseAutomationEntity.capability_attributes` → `Automation.thisValue`: `thisValue` stands for `capability_attributes`.
  * M-145 `helpers/entity_platform.py::EntityPlatform._async_add_entity` → `Automation.automationEntityIds`: see Not correct.
  * M-175 `helpers/sun.py::get_astral_observer` → `Automation.decodeInput`: the input decoder stands for `get_astral_observer`.
  * M-190 `core.py::State.expire` → `Core.StateMachine.asyncSetInternal`, `Core.StateMachine.asyncRemove`: `State.expire` is the identity on the model.
  * M-263 `helpers/script.py::Script.runs` → `Automation.writeEntity`, `Automation.runsOf`: `writeEntity` and `runsOf` stand for the property `Script.runs`.
  * M-266 `helpers/entity.py::Entity.__async_remove_impl` → `Script.reloadScripts`: `reloadScripts` holds the one branch of `__async_remove_impl` a script entity takes.
  * M-268 `helpers/restore_state.py::RestoreStateData.async_restore_entity_removed` → `Script.reloadScripts`: `reloadScripts` keeps `last_triggered` of a removed entity.
  * M-274 `core.py::HassJobType` → `Core.Hass.Hass`, `Core.Hass.Action`: see Not correct.

## Differences found here that no area `FINDINGS.md` lists

Each reproduced on two runs (`logs-manifest/two-runs.log`).

| entry | input | HA | HALean | logs |
|---|---|---|---|---|
| M-17 | a call to a service that does not exist, `continue_on_error: true`, then an `event` action; the shell reports the error as the bridge does (`ha_error`, `bridge/bridge.py:81`) | the run ends with ServiceNotFound, no event | the run goes on and fires the event | `logs-manifest/probe-ha.log` [M-17], `logs-manifest/probe-m17-engine.log` |
| M-8 | time condition `after: sensor.ts`, state `2023-11-14`, `device_class: timestamp` | condition true, the action runs | condition false, debug log only | `logs-manifest/probe-ha.log` [M-8], `logs-manifest/probe-automation.log` [M-8] |
| M-80 | action with the static `target: {entity_id: "Light.A, light.b"}`; and with `entity_id: "not an id"` | `['light.a', 'light.b']`; the second is rejected at load | sent as written; the second loads | `logs-manifest/probe-m80-static-target.log` |

