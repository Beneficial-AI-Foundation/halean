# 07-automation: findings

Reviewed: `HALean/Automation/*.lean`, `Exe/Automation.lean` at commit `f638a37`, against Home Assistant 2026.10.4
in-process. Harness: `harness/test_differential.py` (copy of the shipped test, changes listed in `README.md`).

Short answer to the question. For valid automations inside the supported subset, the random runs agree with HA except
in `restart` mode (AUT-1, AUT-26) and in cases the harness cannot decide (AUT-23). Hand-written cases found eleven more
silent differences in corner cases (AUT-2 to AUT-12). The engine does not reject at load most configurations that HA
rejects: it runs them (AUT-14, AUT-15, AUT-16). It refuses a few valid ones that the README does not list (AUT-13,
AUT-17 to AUT-20).

## Counts

| What | Number | Log |
|---|---|---|
| New hand-written cases (`cases/*.yaml`) | 150 | `logs/run1-cases.log` (`51 failed, 100 passed, 2 skipped`: 150 scenarios + the pin test; the 2 skips are the empty mqtt/webhook parametrisations) |
| Random cases per run | 800 (seed 101: 300, seed 202: 300, seed 303 with `--profile modes`: 200) | `logs/run1-gen.log`, `logs/run1-random-101.log`, `-202.log`, `-303.log` |
| Runs | 2, with identical scenario sets and identical failing ids | `logs/gen-determinism.txt`, `logs/run1-failing.txt`, `logs/run2-failing.txt` |
| Cases that diverge (per run, same in both) | 65: 51 hand-written, 14 random (seed 101: 1, seed 202: 2, seed 303: 11) | `logs/run1-summary.txt`, `logs/run2-summary.txt`; per-step results in `logs/run1-divergences.txt`, `logs/run2-divergences.txt` |
| Random cases that pass the comparison but error at teardown (not divergences, see harness notes) | 4 (`r101_037`, `r101_106`, `r101_281`, `r303_031`) | `logs/run1-failing.txt` (lines starting with `ERROR`) |
| Distinct root causes | 26: 21 in the Lean model (AUT-1 to AUT-20, AUT-26), 5 in the harness / test driver (AUT-21 to AUT-25) | this file |
| Ids still failing with all patches applied | 43 (29 hand-written, 10 random, 4 teardown errors) | `patches/patched-failing.txt`, `patches/patched-*.log` |

The 51 failing hand-written cases by ID: AUT-1: 3, AUT-2: 2, AUT-3: 2, AUT-4: 3, AUT-5: 3, AUT-6: 1, AUT-7: 1, AUT-8: 1,
AUT-9: 2, AUT-10: 1, AUT-11: 2, AUT-12: 1, AUT-13: 2, AUT-14: 12, AUT-15: 2, AUT-16: 1, AUT-17: 1, AUT-18: 1, AUT-19: 1,
AUT-20: 1, AUT-21: 2, AUT-22: 1, AUT-23: 2, AUT-24: 1, AUT-25: 1, AUT-26: 1.
The 14 failing random cases: AUT-1: `r303_027`, `r303_037`, `r303_097`, `r303_160`, `r303_188`; AUT-26 (with AUT-1):
`r202_090`, `r303_032`, `r303_126`; AUT-23: `r101_148`, `r202_201`, `r303_035`, `r303_058`, `r303_069`, `r303_136`.
The other 99 hand-written cases and 786 random cases agree with HA.

## Divergences

"Patch?" names the patch file. All patches were applied together in one throwaway copy
(`patches/apply_patches.py`), `halean-automation` and `halean-script` were rebuilt (`patches/all-patches.build.log`)
and the shipped suites pass there: `patches/all-patches.shipped.scenarios.log` (60/60),
`.script_scenarios.log` (11/11), `.test_differential.log` (56 passed, 5 skipped), `.test_scripts.log` (10 passed,
1 skipped). They were not built one by one. With the patches, `lake build HALean` (the proof files) fails in
`ConfigSpec`, `ConditionSpec`, `EngineSpec`, `EngineSpec3`, `EngineSpec4`, `EngineBound` (33 errors,
`patches/all-patches.lib-build.log`): theorems there state the old definitions and would have to be updated.

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| AUT-1 | `cases/mode_restart_two_triggers.yaml::rst`, `cases/mode_restart_other_automation_order.yaml::rst` | `restart` with a live run: the new run starts one loop iteration later, after the other listeners of the event; a second trigger of the same event replaces it before it ran a step | new run starts at once and runs its first steps | Silent (and Order) | no. Lines 672-674 say only "Callbacks run in a fixed order ... Timing races between separate HA tasks are not modelled." | `patches/AUT-1.patch` (partial, see details); yes, `patches/all-patches.shipped.*.log` |
| AUT-2 | `cases/state_to_star.yaml::star`, `cases/state_not_to_star.yaml::notstar` | `to: "*"` matches any state; `not_to: "*"` matches none | `"*"` is the literal state text | Silent | no | `patches/AUT-2.patch`; yes, same logs |
| AUT-3 | `cases/state_attr_bool_int.yaml::attr1`, `cases/state_attr_int_float_same.yaml::attrsame` | attribute values compared with Python `==` (`1 == True == 1.0`) | JSON structural equality | Silent | no | `patches/AUT-3.patch`; yes, same logs |
| AUT-4 | `cases/state_entity_uppercase.yaml::upper`, `cases/cond_entity_uppercase.yaml::upcond`, `cases/state_invalid_entity_id.yaml::badid` | entity ids are lower-cased; an invalid id rejects the automation | id used as written (never matches); invalid id accepted | Silent / Accepts | no | `patches/AUT-4.patch`; yes, same logs |
| AUT-5 | `cases/state_entity_duplicate.yaml::dupent`, `cases/time_duplicate_at.yaml::dupat`, `cases/ev_type_list_and_dup.yaml::evlist` | one listener per list entry: a duplicate entry triggers twice | triggers once | Silent | no | `patches/AUT-5.patch`; yes, same logs |
| AUT-6 | `cases/act_repeat_count_float.yaml::floatcount` | `count: 2.5` runs 2 times, `3.0` 3 times | 25 and 30 times | Silent | no | `patches/AUT-6.patch`; yes, same logs |
| AUT-7 | `cases/coe_string_forms.yaml::coestr` | `continue_on_error: "true"` / `1` continue after a failed call | run ends with the error | Silent | no (line 234 lists `continue_on_error` as supported) | `patches/AUT-7.patch`; yes, same logs |
| AUT-8 | `cases/act_repeat_var_shadow.yaml::shadow` | assigning `repeat` in a loop changes the loop's local variable; undefined after the loop | loop keeps its own `repeat`; the assignment leaks to the run's variables | Silent | no | no |
| AUT-9 | `cases/time_at_load_second.yaml::atload`, `cases/tp_every_n_seconds.yaml::every5` | a time / time_pattern trigger for the second the automations load in fires | never fires for that second | Silent | no. Lines 666-669 cover only `trigger.now` being 500 ms in | no (see details) |
| AUT-10 | `cases/cfg_initial_state_false.yaml::off_at_start` | `initial_state: false`: no trigger | triggers | Silent | no | `patches/AUT-10.patch`; yes, same logs |
| AUT-11 | `cases/cond_cache_same_text.yaml::cache` | two conditions of one script with equal `str()` of their values share the first one's checker | each condition evaluated as written | Silent | no | no |
| AUT-12 | `cases/num_float_strings.yaml::floats` | state `"1_1"` and `"１２"` are numbers (Python `float()`) | "cannot be processed as a number": no trigger | Silent | no (lines 248-256 document number text for templates only) | `patches/AUT-12.patch` (underscores only); yes, same logs |
| AUT-13 | `cases/tmpl_undefined_variable.yaml::undef`, `cases/tmpl_context_variable.yaml::ctx` | an undefined name renders empty / takes `default`; `context` is defined | automation `unsupported` | Refuses | no | no |
| AUT-14 | `cases/cfg_unknown_keys.yaml`, `cases/cfg_missing_required.yaml`, `cases/cfg_both_trigger_keys.yaml`, `cases/cond_invalid_configs.yaml`, `cases/cond_numeric_no_bounds.yaml`, `cases/cond_time_empty.yaml`, `cases/num_above_gt_below.yaml`, `cases/num_bound_entity_domain.yaml`, `cases/state_from_and_not_from.yaml`, `cases/state_to_yaml_bool.yaml`, `cases/time_weekday_invalid.yaml`, `cases/trigger_id_int.yaml` (every automation in them) | automation rejected by the schema and disabled | automation runs | Accepts | no | no |
| AUT-15 | `cases/act_delay_static_invalid.yaml::unit`, `::empty`, `::floathours`, `::weeks`; `cases/act_delay_string_forms.yaml::bool` | static periods `{secs: 1}`, `{}`, `"0.5:00"`, `{weeks: 1}` rejected; `delay: true` is 1 s | first four run; `true` is `unsupported` | Accepts / Refuses | no | `patches/AUT-15.patch`; yes, same logs |
| AUT-16 | `cases/cfg_duplicate_ids.yaml::second` | second automation with the same `id` is ignored | both run | Accepts | no | no |
| AUT-17 | `cases/par_list_branch.yaml::parlist` | a `parallel` branch written as a list of actions runs | `unsupported` | Refuses | no | `patches/AUT-17.patch`; yes, same logs |
| AUT-18 | `cases/act_stop_null.yaml::stopnull` | `stop:` (null) stops the run | `unsupported` | Refuses | no | `patches/AUT-18.patch`; yes, same logs |
| AUT-19 | `cases/tp_number_forms.yaml::spaces`, `::plus`, `::float` | `seconds: " 26 "`, `"+27"`, `28.0` are valid (`int()`) | `unsupported` ("bad seconds") | Refuses | no | `patches/AUT-19.patch`; yes, same logs |
| AUT-20 | `cases/trigger_nested_list.yaml::nestedtr` | a nested `triggers:` list is flattened | `unsupported` | Refuses | no (line 231 lists "other new-style triggers", not this) | `patches/AUT-20.patch`; yes, same logs |
| AUT-21 | `cases/svc_target_over_data.yaml::tod` | `entity_id` from `target` wins over `data` | the engine's command is right; the harness merges data over target | Tooling | no | no (harness) |
| AUT-22 | `cases/tooling_walk_actions_mapping.yaml::mapping` | call made in real HA; in the harness `ServiceNotFound` because the service was never registered | call | Tooling | no | no (harness) |
| AUT-23 | `cases/timer_same_tick_delay_vs_pattern.yaml::tick`, `cases/time_two_triggers_same_time.yaml::twotime` | timers due in one tick fire in an order that is not by due time and not stable between sessions; timers fire up to 0.5 s early | by due time, then creation order; whole-second ticks | Tooling | partly: lines 675-677 (delays end on whole seconds) | no (harness) |
| AUT-24 | `cases/svc_response_none.yaml::respnone` | a call with `response_variable` answered without a mapping raises in HA's `ServiceRegistry` | engine continues | Tooling | no | no (scenario format) |
| AUT-25 | `cases/tooling_noop_set.yaml::noop` | a `set` that changes nothing fires no `state_changed` | the driver sends `state_changed`; the engine triggers | Tooling | no | no (test driver) |
| AUT-26 | `cases/mode_restart_parallel_not_started.yaml::rstpar` | a run stopped (restart) while its `parallel` branches are scheduled but not started: each branch still runs to its first wait | branches dropped | Silent | no | no |

## Details

Outputs are copied from `logs/run1-divergences.txt` (run 2 has the same lines in `logs/run2-divergences.txt`).
Scenario time starts at 2023-11-14 22:13:20 UTC.

### AUT-1: `restart` starts the new run at once

```yaml
automations:
  - alias: rst
    mode: restart
    triggers: [{trigger: state, entity_id: sensor.a, id: first}, {trigger: state, entity_id: sensor.a, id: second}]
    actions: [{event: m_step, event_data: {id: "{{ trigger.id }}"}}, {delay: 10}]
states: [{entity_id: sensor.a, state: "0"}]
steps:
  - {at: 1, set: [sensor.a, "1"]}
  - {at: 2, set: [sensor.a, "2"]}
```
```
step 2
  HA:     [['automation_triggered', 'rst'], ['automation_triggered', 'rst'], ['fire_event', 'm_step', {'id': 'second'}]]
  engine: [['automation_triggered', 'rst'], ['fire_event', 'm_step', {'id': 'first'}], ['automation_triggered', 'rst'], ['fire_event', 'm_step', {'id': 'second'}]]
```
With a second automation on the same event (`mode_restart_other_automation_order`), step 2:
```
  HA:     [['automation_triggered', 'other'], ['fire_event', 'm_other', {}], ['automation_triggered', 'rst'], ['fire_event', 'm_rst', {}]]
  engine: [['automation_triggered', 'rst'], ['fire_event', 'm_rst', {}], ['automation_triggered', 'other'], ['fire_event', 'm_other', {}]]
```
Root cause: `helpers/script.py::Script.async_run` lines 1987-1995 do `await self.async_stop(update_state=False,
spare=run)` when runs exist; `_ScriptRun.async_stop` (604-612) waits for the old run's `_stopped` event, which needs a
loop iteration. `started_action()` (1997-1998, the `automation_triggered` event) and `run.async_run()` (2002-2004) come
after it. A second trigger in the same iteration stops the new run before it started (`async_run` 513-515 breaks at
once). `Engine.lean::triggerAutomation` 1003-1008 removes the old runs, emits `automation_triggered` and calls `drive`
in one step. So HALean executes actions HA never executes (first reproducer) and orders automations differently
(second). Found by the random runs (`r1_018` in the first trial, then `r303_027`, `r303_097`, `r303_160`, `r303_188`).

Patch `patches/AUT-1.patch`: a restarted run and its `automation_triggered` are deferred to `resumeWoken`. It fixes the
three hand-written cases and four of the five random cases (`patches/patched-cases.log`, `patches/patched-s303.log`).
It is partial: `r303_037` still differs in the order of two restarted automations (HA: `a0, a2, a1`; patched engine:
`a0, a1, a2`). There the old run of `a1` is blocked in a service call and needs one more loop iteration to stop than
the old run of `a2`, which waits in `wait_for_trigger`. The patch does not model that.

### AUT-2: `"*"` in a state trigger

```yaml
automations:
  - alias: star
    triggers: [{trigger: state, entity_id: sensor.a, to: "*"}]
    actions: [{event: m_star}]
states: [{entity_id: sensor.a, state: "1"}]
steps:
  - {at: 1, set: [sensor.a, "2"]}
```
```
step 1
  HA:     [['automation_triggered', 'star'], ['fire_event', 'm_star', {}]]
  engine: []
```
`not_to: "*"` (`state_not_to_star`): HA `[]` at steps 1 and 3, engine triggers at both.
Root cause: `helpers/event.py::process_state_match` (line 1870): `if parameter is None or parameter == MATCH_ALL:
return lambda _: not invert`. `Config.lean::stateMatch` 545-551 keeps `"*"` as a value.

### AUT-3: values compared with JSON equality

```yaml
automations:
  - alias: attr1
    triggers: [{trigger: state, entity_id: sensor.a, attribute: flag, to: 1}]
    actions: [{event: m_attr1}]
states: [{entity_id: sensor.a, state: "x", attributes: {flag: false}}]
steps:
  - {at: 1, set: [sensor.a, "x"], attributes: {flag: true}}
```
```
step 1
  HA:     [['automation_triggered', 'attr1'], ['fire_event', 'm_attr1', {}]]
  engine: []
```
`state_attr_int_float_same` (trigger on attribute `level`, changed `1` to `1.0`, then to `true`): HA `[]` twice (no
change for Python), engine triggers twice.
Root cause: upstream uses `==` (`triggers/state.py` 151-160 and `process_state_match`; `helpers/condition.py` 1923).
Lean uses `Json` equality: `Engine.lean` 296 (`vs.contains v`), 1109-1110, 1175-1176; `Condition.lean` 139.

### AUT-4: entity ids as written

```yaml
automations:
  - alias: upper
    triggers: [{trigger: state, entity_id: Sensor.A}]
    actions: [{event: m_upper}]
states: [{entity_id: sensor.a, state: "1"}]
steps:
  - {at: 1, set: [sensor.a, "2"]}
```
```
step 1
  HA:     [['automation_triggered', 'upper'], ['fire_event', 'm_upper', {}]]
  engine: []
```
`state_invalid_entity_id` (`entity_id: notanentity` plus an event trigger): HA disables the automation ("Entity
notanentity is neither a valid entity ID nor a valid UUID"), the engine runs it on the event.
Root cause: `cv.entity_ids_or_uuids` (`config_validation.py` 364, `entity_id` 317 lower-cases and validates) in
`triggers/state.py` 49 and `STATE_CONDITION_BASE_SCHEMA` 1519. `Config.lean::entityIds` 253-259 only splits on commas.

### AUT-5: duplicate list entries

```yaml
automations:
  - alias: dupat
    triggers: [{trigger: time, at: ["22:13:25", "22:13:25"]}]
    actions: [{event: m_dupat}]
steps:
  - {at: 4, send: {type: event, event_type: tick}}
  - {at: 5, send: {type: event, event_type: tick}}
```
```
step 2
  HA:     [['automation_triggered', 'dupat'], ['fire_event', 'm_dupat', {}], ['automation_triggered', 'dupat'], ['fire_event', 'm_dupat', {}]]
  engine: [['automation_triggered', 'dupat'], ['fire_event', 'm_dupat', {}]]
```
The same with `entity_id: [sensor.a, sensor.a]` in a state trigger and `event_type: [e1, e2, e1]`.
Root cause: upstream registers one listener per entry (`triggers/time.py` 286-296, `triggers/event.py` 235-238,
`async_track_state_change_event` per entity id). Lean tests membership: `Engine.lean` 1600 (`ats.contains tod`), 1428
(`types.contains ty`), 1106 (`eids.contains eid`). Five random cases of the first trial run had this cause; the
generator now avoids duplicate entities.

### AUT-6: static float `count`

```yaml
automations:
  - alias: floatcount
    triggers: [{trigger: event, event_type: e}]
    actions:
      - repeat: {count: 2.5, sequence: [{event: m_25}]}
steps:
  - {at: 1, send: {type: event, event_type: e}}
```
HA fires `m_25` 2 times; the engine 25 times (and 30 times for `count: 3.0`).
Root cause: `_SCRIPT_REPEAT_SCHEMA` (`config_validation.py` 1926: `Any(Coerce(int), template)`). `Config.lean` 1075:
`.num n => .repeatCount n.mantissa.toNat body` reads the mantissa of the JSON number (`2.5` is mantissa 25,
exponent 1).

### AUT-7: `continue_on_error` and `error` are `cv.boolean`

```yaml
automations:
  - alias: coestr
    triggers: [{trigger: event, event_type: e1}]
    actions: [{action: test.fail, continue_on_error: "true"}, {event: m_str}]
steps:
  - {at: 1, send: {type: event, event_type: e1}}
  - {at: 2, send: {type: service_result, call_id: 0, ok: false, error_kind: ha_error}}
```
```
step 2
  HA:     [['fire_event', 'm_str', {}]]
  engine: []
```
Root cause: `SCRIPT_ACTION_BASE_SCHEMA` (`config_validation.py` 1421, `continue_on_error: boolean`; `boolean` at 218
accepts `"true"`, `"yes"`, `"on"`, `"1"`, numbers). `Config.lean` 1002 and 1087 accept only the JSON literal `true`.

### AUT-8: assigning `repeat` inside a loop

```yaml
automations:
  - alias: shadow
    triggers: [{trigger: event, event_type: e}]
    actions:
      - repeat:
          count: 2
          sequence:
            - variables: {repeat: "mine"}
            - {event: m_in, event_data: {r: "{{ repeat }}"}}
      - {event: m_out, event_data: {defined: "{{ repeat is defined }}"}}
steps:
  - {at: 1, send: {type: event, event_type: e}}
```
```
step 1
  HA:     [['automation_triggered', 'shadow'], ['fire_event', 'm_in', {'r': 'mine'}], ['fire_event', 'm_in', {'r': 'mine'}], ['fire_event', 'm_out', {'defined': False}]]
  engine: [['automation_triggered', 'shadow'], ['fire_event', 'm_in', {'r': {'first': True, 'index': 1, 'last': False}}], ['fire_event', 'm_in', {'r': {'first': False, 'index': 2, 'last': True}}], ['fire_event', 'm_out', {'defined': True}]]
```
Root cause: `script_variables.py::ScriptRunVariables._assign` 208-236 assigns to the nearest scope that defines the
name; `repeat` is defined locally by `define_local` (`script.py` 860). `Script.lean::Run.scopeVars` 141-144 always
puts the frame's `repeat` in front, and the `variables` step writes with `setVar` into `r.vars` (350). No patch: the
loop frames would have to carry the overridden value.

### AUT-9: the second the automations load in

```yaml
automations:
  - alias: atload
    triggers: [{trigger: time, at: "22:13:20"}]
    actions: [{event: m_atload}]
steps:
  - {at: 1, send: {type: event, event_type: tick}}
```
```
step 1
  HA:     [['automation_triggered', 'atload'], ['fire_event', 'm_atload', {}]]
  engine: []
```
Root cause: `helpers/event.py::async_track_utc_time_change` (1806-, line 1835) schedules each listener
50 000-500 000 µs into the matching second, so a listener attached in the first part of a matching second still
fires. `Engine.lean::handle` line 1782 sets `lastSec := now.utc / 1000` and `advanceTo` (1761) starts at
`lastSec + 1`. No patch: I tried evaluating the load second with the next input. The shipped scenario `time_values`
then fails against HA, because in the harness HA runs that listener at the next whole-second tick, with `now()` one
second later, while real HA runs it within the same second. The harness cannot check a faithful fix.

### AUT-10: `initial_state: false`

```yaml
automations:
  - alias: off_at_start
    initial_state: false
    triggers: [{trigger: event, event_type: e}]
    actions: [{event: m_off_at_start}]
steps:
  - {at: 1, send: {type: event, event_type: e}}
```
```
step 1
  HA:     [['automation_triggered', 'on_at_start'], ['fire_event', 'm_on_at_start', {}]]
  engine: [['automation_triggered', 'off_at_start'], ['fire_event', 'm_off_at_start', {}], ['automation_triggered', 'on_at_start'], ['fire_event', 'm_on_at_start', {}]]
```
(`on_at_start` is a second automation of the case file, with `initial_state: true`.)
Root cause: `components/automation/__init__.py` 654-655 (`enable_automation = self._initial_state`). Neither
`Config.lean::decodeAutomation` nor `bridge/bridge.py` reads the key.

### AUT-11: HA's condition cache

```yaml
automations:
  - alias: cache
    triggers: [{trigger: event, event_type: e}]
    actions:
      - if: [{condition: state, entity_id: sensor.a, attribute: v, state: 1}]
        then: [{event: m_int_1}]
      - if: [{condition: state, entity_id: sensor.a, attribute: v, state: "1"}]
        then: [{event: m_str_1}]
states: [{entity_id: sensor.a, state: "x", attributes: {v: "1"}}]
steps:
  - {at: 1, send: {type: event, event_type: e}}
```
```
step 1
  HA:     [['automation_triggered', 'cache']]
  engine: [['automation_triggered', 'cache'], ['fire_event', 'm_str_1', {}]]
```
Root cause: `helpers/script.py::Script._async_get_condition` 2097-2102 caches by
`frozenset((k, str(v)) for k, v in config.items())`. The second condition has the same key as the first and gets the
first one's checker (`state: 1`). This is upstream behaviour; HALean evaluates each condition as written. Only
conditions of one script (one sequence) whose values differ in type but not in `str()` are affected.
`cond_state_attr_types` shows the same inside one `choose` (it also needs AUT-3 to pass).

### AUT-12: numbers in states

`cases/num_float_strings.yaml`: trigger `numeric_state`, `above: 10`; the state goes `0` → `"1_1"` (step 5) and
`0` → `"１２"` (fullwidth digits, step 16).
```
step 5
  HA:     [['automation_triggered', 'floats'], ['fire_event', 'm_floats', {'s': '1_1'}]]
  engine: []
step 16
  HA:     [['automation_triggered', 'floats'], ['fire_event', 'm_floats', {'s': 12}]]
  engine: []
  engine: {"level": "warning", "message": "Error in numeric_state trigger: entity sensor.t state '\"1_1\"' cannot be processed as a number", "type": "log"}
```
Root cause: `helpers/condition.py::async_numeric_state` line 1751 `float(value)`. `Condition.lean::numericStateOf` 191
uses `pyFloat?` / `Core/Types.lean::parsePyFloatStr` (line 94), which takes ASCII digits without group underscores.
The template engine has a second parser that takes underscores (`Template/Value.lean::parseFloatStr` 154). The patch
switches to it; non-ASCII digits stay different (step 16 still fails with the patch, `patches/patched-cases.log`).

### AUT-13: undefined names in templates

```yaml
automations:
  - alias: undef
    triggers: [{trigger: event, event_type: e}]
    actions: [{event: m_undef, event_data: {v: "{{ nothing_defines_me | default('fallback') }}", d: "{{ nothing_defines_me is defined }}"}}]
steps:
  - {at: 1, send: {type: event, event_type: e}}
```
```
step 1
  HA:     [['automation_triggered', 'undef'], ['fire_event', 'm_undef', {'v': 'fallback', 'd': False}]]
  engine: []
  engine: {"id": "?", "reason": "template uses 'nothing_defines_me', which HALean does not support", "type": "unsupported"}
```
The same for `{{ context is defined }}` (HA: `True`; `script.py` 1956 sets `variables["context"]`).
Root cause: `Config.lean::compileTemplate` 331-337 runs `Template.check t vars` with the names collected in
`decodeAutomation` 1239-1240. The refusal is safe, but it is not in the README's "Rejected at load" columns, and
`{{ x | default(...) }}` is a common pattern.

### AUT-14: configurations HA rejects and HALean runs

Each automation below is disabled by HA ("could not be validated and has been disabled" / "failed to setup triggers
and has been disabled"; messages in `logs/run1-dump/cases/<case>.json`, field `ha_log`) and runs in the engine. Each
case pairs the invalid element with an event trigger and a marker action, so HA shows `[]` and the engine shows
`automation_triggered` plus the marker, for example (`cond_numeric_no_bounds`):
```
step 1
  HA:     []
  engine: [['automation_triggered', 'nobounds'], ['fire_event', 'm_nobounds', {}]]
  ha_log: ERROR homeassistant.components.automation: Automation with alias 'nobounds' could not be validated and has been disabled: at least one of ['below', 'above'] is required at 'conditions[0]'. Got {'condition': 'numeric_state', 'entity_id': 'sensor.a'}
```

| Case | Invalid element | HA's message |
|---|---|---|
| `cfg_unknown_keys` | unknown key in an action, a trigger, a condition, the automation; two action keys in one step | `not a valid option at 'actions[0].foo'` |
| `cfg_missing_required` | no `actions`; choose option without `sequence` / without `conditions`; `if` without `then`; `repeat` without `sequence` | `required key not provided at 'actions'` |
| `cfg_both_trigger_keys` | `trigger` and `triggers` together | `Cannot specify both 'trigger' and 'triggers'` |
| `cond_invalid_configs` | `match: some`; state condition without `state`; `and` without `conditions`; unknown weekday; trigger condition without `id`; `state: true` | `expected 'all' or 'any' at 'conditions[0].match'` |
| `cond_numeric_no_bounds` | numeric_state condition without `above`/`below` | `at least one of ['below', 'above'] is required` |
| `cond_time_empty` | time condition without keys | `at least one of ['before', 'after', 'weekday'] is required` |
| `num_above_gt_below` | numeric_state trigger with `above: 10, below: 5` | `A value can never be above 10.0 and below 5.0 at the same time` |
| `num_bound_entity_domain` | `above: input_text.limit` | `expected float at 'above'` |
| `state_from_and_not_from` | `from` and `not_from` together | `two or more values in the same group of exclusion 'from'` |
| `state_to_yaml_bool` | `to: true` | `expected str at 'to'` |
| `time_weekday_invalid` | `weekday: tuesday` | `value must be one of ['fri', 'mon', ...]` |
| `trigger_id_int` | trigger `id: 7` | `expected str at 'triggers[0].id'` |

Root cause: `Config.lean` decodes the keys it knows and ignores the rest; it has no counterpart of the probatio
schemas (`config_validation.py` 1421-2037, `components/automation/config.py` 63-83, the trigger platforms' schemas).
The bridge loads `automations.yaml` itself (`bridge/bridge.py` 339), so nothing validates the file first. No small
patch.

### AUT-15: static time periods

`cases/act_delay_static_invalid.yaml`: four automations with `delay: {secs: 1}`, `delay: {}`, `delay: "0.5:00"`,
`delay: {weeks: 1}`, each followed by a marker event.
```
step 1
  HA:     []
  engine: [['automation_triggered', 'unit'], ['fire_event', 'm_unit', {}], ['automation_triggered', 'empty'], ['fire_event', 'm_empty', {}], ['automation_triggered', 'floathours'], ['automation_triggered', 'weeks'], ['fire_event', 'm_weeks', {}]]
  ha_log: ERROR homeassistant.components.automation: Automation with alias 'unit' could not be validated and has been disabled: not a valid option, did you mean 'seconds'? at 'actions[0].delay.secs'. Got 1
```
`cases/act_delay_string_forms.yaml::bool` (`delay: true`): HA triggers and waits 1 s; engine: `{"reason": "invalid
time period: true", "type": "unsupported"}`.
Root cause: static periods go through `Config.lean::durationMs` 269-294, a parser of its own, not through the
translated `TimePeriod.lean::cvPositiveTimePeriod` that rendered periods use. The patch calls `cvPositiveTimePeriod`
for static values too. (`act_delay_string_forms` still fails with the patch because of its fractional delays,
AUT-23.)

### AUT-16: duplicate automation ids

Two automations with `id: same` (`cases/cfg_duplicate_ids.yaml`).
```
step 1
  HA:     [['automation_triggered', 'first'], ['fire_event', 'm_first', {}]]
  engine: [['automation_triggered', 'first'], ['fire_event', 'm_first', {}], ['automation_triggered', 'second'], ['fire_event', 'm_second', {}]]
  ha_log: ERROR homeassistant.components.automation: Platform automation does not generate unique IDs. ID same already exists - ignoring automation.first
```
Root cause: the entity platform refuses a second entity with the same unique id; `Config.lean::decodeAutomation`
(1204-1259) and `automationEntityIds` (1165-1178) do not compare ids.

### AUT-17: list-form `parallel` branch

```yaml
      - parallel:
          - [{event: m_a1}, {event: m_a2}]
          - {event: m_b}
      - {event: m_after}
```
```
step 1
  HA:     [['automation_triggered', 'parlist'], ['fire_event', 'm_a1', {}], ['fire_event', 'm_a2', {}], ['fire_event', 'm_b', {}], ['fire_event', 'm_after', {}]]
  engine: []
  engine: {"id": "?", "reason": "action not supported: [{\"event\":\"m_a1\"},{\"event\":\"m_a2\"}]", "type": "unsupported"}
```
Root cause: `_parallel_sequence_action` (`config_validation.py` 2022-2028) is `SCRIPT_SCHEMA` wrapped in a sequence.
`Config.lean` 1105-1110 handles a `sequence:` mapping or a single action.

### AUT-18: `stop:` without a reason

`actions: [{event: m_before}, {stop: }, {event: m_never}]`.
```
step 1
  HA:     [['automation_triggered', 'stopnull'], ['fire_event', 'm_before', {}]]
  engine: []
  engine: {"id": "?", "reason": "action not supported: {\"stop\":null}", "type": "unsupported"}
```
Root cause: `_SCRIPT_STOP_SCHEMA` (`config_validation.py` 2001-) has `stop: Any(None, cv.string)`. `Config.lean` 1086
tests `str? j "stop"`.

### AUT-19: time_pattern values

`cases/tp_number_forms.yaml`: `seconds: "025"`, `" 26 "`, `"+27"`, `28.0`, `29`, one automation each.
```
step 2
  HA:     [['automation_triggered', 'spaces'], ['fire_event', 'm_spaces', {}]]
  engine: []
step 3
  HA:     [['automation_triggered', 'plus'], ['fire_event', 'm_plus', {}]]
  engine: []
step 4
  HA:     [['automation_triggered', 'float'], ['fire_event', 'm_float', {}]]
  engine: []
  engine: {"id": "?", "reason": "bad seconds", "type": "unsupported"}
```
Root cause: `triggers/time_pattern.py::TimePattern.__call__` 31-49 uses `int(value)`. `Config.lean` 785-799 uses
`String.toNat?` and requires a JSON number with exponent 0.

### AUT-20: nested `triggers:` list

```yaml
    triggers:
      - triggers:
          - {trigger: event, event_type: e0}
          - {trigger: event, event_type: e1}
      - {trigger: event, event_type: e2}
```
```
step 1
  HA:     [['automation_triggered', 'nestedtr'], ['fire_event', 'm_nestedtr', {'idx': 0}]]
  engine: []
  engine: {"id": "?", "reason": "trigger platform '' is not supported", "type": "unsupported"}
```
Root cause: `_base_trigger_list_flatten` (`config_validation.py` 1864). `Config.lean::decodeAutomation` 1243 decodes
each list item as one trigger.

### AUT-21 (Tooling): the harness merges data over target

```yaml
      - action: test.tod
        target: {entity_id: light.from_target}
        data: {entity_id: light.from_data, v: 1}
```
```
step 1
  HA:     [['automation_triggered', 'tod'], ['call_service', 'test', 'tod', {'entity_id': ['light.from_target'], 'v': 1}]]
  engine: [['automation_triggered', 'tod'], ['call_service', 'test', 'tod', {'entity_id': ['light.from_data'], 'v': 1}]]
```
The engine's command has `data.entity_id = light.from_data` and `target.entity_id = [light.from_target]`, as
`async_prepare_call_from_config` returns them. HA's `ServiceRegistry.async_call` then does
`service_data.update(target)`. `tests/differential/test_differential.py::_normalise_engine` (shipped line 96) builds
`{**c["target"], **c["data"]}`, the other way round. The engine's own `mergeTarget` (`Engine.lean` 526-529) has the
right order. Also in `svc_data_merge` (the action's own `entity_id` against `data.entity_id`).

### AUT-22 (Tooling): `_walk_actions` misses some forms

`action: {action: test.single, data: {v: 1}}` (one mapping, valid for HA). The harness's `_walk_actions` (shipped
lines 46-65) iterates a mapping's keys, and for `parallel` it skips branches that are lists. Services there are not
registered and events there are not observed.
```
step 1
  HA:     [['automation_triggered', 'mapping']]
  engine: [['automation_triggered', 'mapping'], ['call_service', 'test', 'single', {'v': 1}]]
  ha_log: ERROR homeassistant.components.automation.mapping: mapping: Error executing script. Service not found for call_service at pos 1: Action test.single not found
```

### AUT-23 (Tooling): timers in the harness

`pytest_homeassistant_custom_component.common.async_fire_time_changed` runs every scheduled timer due up to the tick
plus 0.5 s, in the order of the event loop's `_scheduled` list (the heap array), not by due time.

(a) A delay that ends in the second a time pattern fires (`timer_same_tick_delay_vs_pattern`): the engine ends the
delay first and admits the pattern's trigger; HA ran the pattern's listener first.
```
step 2
  HA:     []
  engine: [['automation_triggered', 'tick'], ['fire_event', 'm_run', {'p': 'time_pattern'}]]
  ha_log: WARNING homeassistant.components.automation.tick: tick: Already running
```
(b) Two time triggers of one automation in the same second (`time_two_triggers_same_time`): HA's order was `b, a` in
run 1 and run 2 and `a, b` in the session of `patches/patched-cases.log`, with the same scenario set.
```
step 1
  HA:     [['automation_triggered', 'twotime'], ['fire_event', 'm_twotime', {'id': 'b'}], ['automation_triggered', 'twotime'], ['fire_event', 'm_twotime', {'id': 'a'}]]
  engine: [['automation_triggered', 'twotime'], ['fire_event', 'm_twotime', {'id': 'a'}], ['automation_triggered', 'twotime'], ['fire_event', 'm_twotime', {'id': 'b'}]]
```
(c) `delay: 1.5` fires after one tick in HA and after two in the engine (`act_delay_string_forms`, steps 2-4).

Real HA orders timers by their real due times, which the whole-second scenario format does not carry. Six random
cases fail for this reason: two timers of different runs due in the same tick (`r101_148`, `r202_201`, `r303_058`,
`r303_069`), a `for:` timer and a wait timeout due together (`r303_136`), two `for:` timers created by one state
change (`r303_035`). They were attributed by reading the scenario around the first differing step; the hand-written
reproducers are (a) and (b).

### AUT-24 (Tooling): `ok` without a response

A call made with `response_variable`, answered by `{type: service_result, call_id: 0, ok: true}` without `response`.
```
step 2
  HA:     []
  engine: [['fire_event', 'm_after', {}]]
  ha_log: ERROR homeassistant.components.automation.respnone: respnone: Error executing script. Error for call_service at pos 1: Failed to process the returned action response data, expected a dictionary, but got <class 'NoneType'>
```
With a real HA behind the bridge this input cannot occur: HA's own `async_call` raises and the bridge would report an
error. The scenario format allows it; the generator always answers such calls with a mapping.

### AUT-25 (Tooling): a `set` step that changes nothing

`states: [{entity_id: light.a, state: "off"}]`, step `{at: 1, set: [light.a, "off"]}`, trigger
`{trigger: state, entity_id: light.a}`.
```
step 1
  HA:     []
  engine: [['automation_triggered', 'noop'], ['fire_event', 'm_noop', {}]]
```
HA's `async_set` with the same state and attributes fires no `state_changed`. `tests/run_scenarios.py::build`
(lines 73-79) sends a `state_changed` input for every `set`. Seven failing cases of the first random trial had this
cause; the generator now avoids such steps.

### AUT-26: restart while `parallel` branches have not started

```yaml
automations:
  - alias: rstpar
    mode: restart
    triggers: [{trigger: state, entity_id: sensor.a, id: first}, {trigger: state, entity_id: sensor.a, id: second}]
    actions:
      - parallel:
          - {event: m_a, event_data: {id: "{{ trigger.id }}"}}
          - sequence: [{event: m_b, event_data: {id: "{{ trigger.id }}"}}, {delay: 5}, {event: m_b_late}]
      - {event: m_after}
states: [{entity_id: sensor.a, state: "0"}]
steps:
  - {at: 1, set: [sensor.a, "1"]}
```
```
step 1
  HA:     [['automation_triggered', 'rstpar'], ['fire_event', 'm_a', {'id': 'first'}], ['fire_event', 'm_b', {'id': 'first'}], ['automation_triggered', 'rstpar'], ['fire_event', 'm_a', {'id': 'second'}], ['fire_event', 'm_b', {'id': 'second'}]]
  engine: [['automation_triggered', 'rstpar'], ['automation_triggered', 'rstpar'], ['fire_event', 'm_a', {'id': 'second'}], ['fire_event', 'm_b', {'id': 'second'}]]
```
Root cause: the first run is suspended in `asyncio.gather` (`script.py` 724-727) with its branch tasks not started.
When it is stopped, each branch task still starts: `_async_run_script` (698-705) creates the sub-script task with
`eager_start=True` as an argument, before `_async_run_long_action` (681-686) looks at `_stop`, so the branch runs to
its first wait. `Engine.lean::triggerAutomation` 1005 calls `removeRun`, which drops the run with its branches
(`removeRun` 361-363). Found by the random runs (`r303_032`, `r303_126`, `r202_090`), shrunk by hand. No patch. With
AUT-1's patch this case still fails (`patches/patched-cases.log`).

## Reading findings without a reproducer

* `Engine.lean::fireDueF` 1642-1654 fires every due `for:` timer before any due delay or wait timeout, whatever was
  created first. asyncio orders timers by due time. With equal durations a wait's timeout is always created before a
  `for:` timer of its own trigger, so in HA the timeout wins. The harness cannot decide this (AUT-23: equal due times
  in a frozen clock fire in heap order).
* The load-second rule (AUT-9) also applies to time triggers of a `wait_for_trigger` attached in the first half of a
  matching second. Not driven: the harness has whole-second steps and the result depends on HA's listener running at
  the next tick.
* `helpers/script.py` 1064-1078: before a call, HA raises `Invalid` when the service supports only responses and the
  step has no `response_variable`, or the reverse. The engine always emits the call. The harness registers every
  service with `SupportsResponse.OPTIONAL`, so this path never runs.
* `this.attributes.current` during a restart: HA counts the old run until it has stopped (`Script.runs`), the engine
  removes it first. Not driven: it needs AUT-1's ordering to be observable first.
* `helpers/condition.py::time` 2052-2056: an `input_datetime` whose `hour` attribute is present but not a number
  raises `TypeError` (not a `ConditionError`). `Condition.lean::resolveTimeBound` 226-229 uses the default 23.
  Not driven (no real `input_datetime` produces it).
* `cv.time_period_seconds` (`config_validation.py` 558): `delay: "inf"` raises `OverflowError` inside
  `timedelta`, which the schema does not catch. Not driven.
* Entity removal (`new_state is None`): `onStateTrigger`, `sameStillHolds` 1172 and `onNumericTrigger` 1134 read as
  upstream, but the scenario format has no step that removes an entity.
* Template triggers (`TrackTemplateResultInfo`, rate limits) and the zone, sun, tag, mqtt, webhook triggers were not
  re-read line by line; only the shipped scenarios exercise them here.

## Notes on the harness

What the shipped differential harness cannot observe in this area:

1. Relative order between the three streams. `automation_triggered`, service calls and fired events are compared
   separately, so "the event before the call" or "triggered before the first action" is not checked.
2. Sub-second timing. The clock moves in whole seconds; HA's timers fire up to 0.5 s early and in heap order within
   one tick, and that order changed between sessions (AUT-23). Any scenario with two timers due in the same tick, or
   with a fractional delay or timeout, can fail or pass for reasons that are not in the engine.
3. Long loops. `_settle()` runs 50 loop iterations per step, and HA's `while`/`until` loops yield with
   `asyncio.sleep(0)` every round. A loop of more than about 50 rounds is spread over later steps on the HA side. The
   10,000-iteration limit can therefore not be compared (see Mutation checks, M4). `cases/act_repeat_until_limit_small.yaml`
   (40 rounds) passes.
4. State between steps, `last_triggered`, context ids, logs and traces are not read. They are visible only where a
   template prints them. The engine's log texts differ from HA's (for example `Error while executing automation
   coestr: ` with an empty message) and nothing checks them.
5. Events fired by actions are not fed back to the engine. HA delivers them to its own event triggers. Scenarios must
   not fire an event that a trigger listens for.
6. The engine's `unsupported` answers and HA's "has been disabled" are not compared with anything. Both only show as
   missing output, and `async_setup_component` still returns true. A config that both sides refuse passes silently.
7. Entities cannot be removed, and a `set` step that changes nothing is sent to the engine anyway (AUT-25).
8. Services are found by `_walk_actions`, which misses list-form parallel branches and a mapping-form `action:`
   (AUT-22), and templated service names. The target/data merge is reversed (AUT-21).
9. A `service_result` for a call HA never made raises `IndexError` in the shipped harness instead of a comparison
   failure (the copy reports both, see `README.md`). A call that asked for a response can be answered without one
   (AUT-24).
10. A restarted run blocked in a service call: in the harness HA cancels the handler. Through the real bridge the
    call has already been sent and cannot be cancelled. Nothing tests that path.
11. Four random cases pass the comparison and then error at teardown (`r101_037`, `r101_106`, `r101_281`,
    `r303_031`): an exception raised by a scenario's failing service result is reported by the test plugin's
    cleanup. They are not divergences.

## Mutation checks

All in the throwaway copy `/tmp/claude-0/halean-copies/07-automation-m` (deleted afterwards); patches and logs are in
`mutations/`. Suites: `tests/run_scenarios.py` (60 scenarios), `tests/run_script_scenarios.py` (11), pytest on
`tests/differential/test_differential.py` (56 run, 5 skipped) and `test_scripts.py` (10 run, 1 skipped).

| Mutation (file, one line) | Build | Shipped scenario suite | Shipped differential suite | Script suites (scenarios / differential) | Logs |
|---|---|---|---|---|---|
| M1: a failing nested `condition` ends the whole run (`Script.lean::conditionFail`, `.next { r with frames := rest }` → `.done .conditionFailed`) | ok | 1 failing (`nested_condition`) | 1 failing (`nested_condition`) | 0 / 0 | `mutations/M1-nested-condition-ends-run.patch`, `M1.*.log` |
| M2: admission compares `existing > maxRuns` instead of `=` (`Engine.lean::admit`) | `halean-automation` does not build: `Automation/Proofs.lean` 79 and 84 (`admit_bounded`, `queued_waits`) fail. `halean-script` builds | not run (no binary) | not run (no binary) | 1 failing (`modes`) / 1 failing (`modes`) | `mutations/M2-admit-max-off-by-one.*` (`M2-stale/` holds two logs made with a stale binary; ignore them) |
| M2b: M2 plus removing `import HALean.Automation.Proofs` from `HALean/Automation.lean`, to see what the tests alone do | ok | 2 failing (`mode_parallel_max`, `queued_max`) | 2 failing (`mode_parallel_max`, `queued_max`) | 1 / 1 (`modes`) | `mutations/M2b-*.patch`, `M2b.*.log` |
| M3: `or` counts a disabled condition as true (`Condition.lean::evalOr`, `.ok (some true)` → `.ok (some true) \| .ok none`) | ok | 0 failing | 0 failing | 0 / 0 | `mutations/M3-or-disabled-counts-true.patch`, `M3-*.log` |
| M4: the repeat limit raised from 10,000 to 1,000,000,000 (`Script.lean::REPEAT_TERMINATE_ITERATIONS`) | ok | 0 failing | 0 failing | 0 / 0 | `mutations/M4-repeat-limit-dropped.patch`, `M4-*.log` |

* The README claim (lines 115-116) holds: with M1, exactly `nested_condition` fails, in the scenario suite and
  against real HA.
* M2 is caught by a proof that the executable imports, and by two scenarios in each automation suite once that import
  is removed.
* M3 is not caught by any shipped test. It is caught by the library build: `HALean/Automation/ConditionSpec.lean`
  705-713 fails (`mutations/M3-or-disabled-counts-true.spec-build.log`). The executables do not import that file. The
  new case `cases/cond_disabled_members.yaml` fails against real HA with M3 (`mutations/M3.review-cases.log`).
* M4 is not caught by any shipped test or by the proof files built here
  (`mutations/M4-repeat-limit-dropped.spec-build.log`, exit 0). README lines 257-270 list "`repeat` aborts after
  10,000 iterations" among behaviours "each covered by a scenario in `tests/scenarios/`"; no scenario there loops that
  often (`grep -l "10000\|looped" tests/scenarios/*.yaml` finds nothing). The differential harness could not compare
  it either (harness note 3).
