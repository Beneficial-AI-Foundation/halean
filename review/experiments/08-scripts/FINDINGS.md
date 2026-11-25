# FINDINGS: 08-scripts (scripts as entities)

Reviewed commit `f638a3779195a42a5162939aa67981b9b501618e`, HA 2026.10.4. Paths: Lean files relative to
`/home/user/halean/`, upstream files relative to `upstream/ha-core/homeassistant/`.

(This file was saved by the lead reviewer from the area reviewer's hand-back text.)

## Counts

| What | Number | Log |
|---|---|---|
| New hand-written scenarios (`cases/h*.yaml`) | 90 | `logs/run1-hand.log` ("25 failed, 65 passed, 1 error") |
| New load-time entries (`config/matrix.yaml`) | 110 | `logs/run1-matrix.log` ("110 passed": every entry gave the verdict recorded in its `expect:`) |
| Random scenarios per run | 600 (300 with seed 101, 300 with seed 202) | `logs/run1-random-seed101.log`, `logs/run1-random-seed202.log` |
| Runs | 2 | `logs/run1-*`, `logs/run2-*` |
| Hand-written scenarios that diverge | 25 (the same 25 in both runs) | `logs/run1-hand.log`, `logs/run2-hand.log` |
| Matrix entries that are not `agree` | 15 (11 Refuses, 4 Accepts; the same in both runs) | `logs/run1-matrix.log`, `logs/run2-matrix.log` (lines `MATRIX <name>: <verdict>`) |
| Random scenarios that diverge, seed 101 | 84 of 300 (the same 84 in both runs) | `logs/run1-random-seed101.log`, `logs/run2-random-seed101.log` |
| Random scenarios that diverge, seed 202 | 73 of 300 (the same 73 in both runs) | `logs/run1-random-seed202.log`, `logs/run2-random-seed202.log` |

The one "error" in the hand-written log is a teardown error of the HA test plugin on a case that passed
(`h71`: a script started with `turn_on` ended with an exception nobody awaited). The random logs have 43
(seed 101) and 39 (seed 202) such teardown errors; they are not counted.

Random failures by signature (`gen/triage.py`; `logs/run1-random-seed101-triage.txt`,
`logs/run1-random-seed202-triage.txt`; run 2 gives the same numbers):

| Signature | seed 101 | seed 202 | Is |
|---|---|---|---|
| `turn_on-not-started` (HALean logged that a turned-on script did not start, at or before the first difference) | 41 | 37 | SCR-13 (documented) |
| `call-to-ha:script.*` (HALean sent a `script.*` call to HA) | 7 | 5 | SCR-15 (tooling) |
| `reload-window` (first difference in a reload step) | 2 | 0 | both looked at: SCR-7 (`current` of a queued script one too high in HA) |
| `ha-indexerror` (a `result: n` step for a call HA did not make) | 8 | 8 | not looked at one by one |
| `other:*` (anything else) | 26 | 23 | see below |

Seed 101, 26 `other` cases: 21 were given to `gen/minimise.py` (against a build with patches SCR-1, 3, 4,
5, 10, so SCR-4 is not among them) or minimised by hand; results in `gen/minimised/m*.yaml`. 18 became
small and each is one of the IDs below: r101_0020 (SCR-17), 0024 (6), 0042 (17), 0063 (6), 0078 (5),
0083 (6), 0089 (6), 0120 (5), 0121 (5), 0149 (5), 0162 (5), 0173 (6), 0182 (6), 0196 (5), 0220 (6),
0222 (17), 0251 (5), 0291 (5). r101_0221, 0249 and 0286 did not get small in the time limit. 5 were not
tried.

Seed 202, 23 `other` cases: 12 were given to the minimiser with a 150 s limit (`gen/minimised/r202_*.yaml`).
6 became small: r202_0009 (SCR-5), 0027 (6), 0036 (5), 0074 (19, which is how SCR-19 was found),
0130 (5), 0148 (5). 6 stayed large (r202_0023, 0094, 0096, 0118, 0131, 0154). 11 were not tried.

The `other` cases that were not minimised and the 16 `ha-indexerror` cases have no root cause assigned. A
root cause that only they show cannot be excluded.

The generator had three artefacts, removed before the two runs: scripts using an undeclared name `r`
(HALean refuses them, README line 492); `result` steps without a response for calls that asked for one
(SCR-18); scripts that start each other for ever through `turn_on`, or a parallel script on a call cycle
with `max` > 3 (both sides only stop at an arbitrary bound; the second kind is exponential, see
`side-by-side.md` section 9).

## Divergences

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| SCR-1 | `cases/h06_turn_on_invalid_entity_id.yaml::h06_turn_on_invalid_entity_id` | `turn_on` with `entity_id: "not an id"`: the call fails, kind `invalid` (`vol.Invalid` from the schema) | the call fails, kind `other` | Silent | no | `patches/SCR-1.patch`; yes, `patches/SCR-1-tests.log`. `h06` then passes. |
| SCR-2 | `cases/h07_turn_off_group_target.yaml::h07_turn_off_group_target`, `cases/h08_turn_off_area_target.yaml::h08_turn_off_area_target` | an outside `turn_off`/`turn_on` with `entity_id: group.x`, `area_id` or `device_id` that matches nothing returns normally; other listed scripts are started | the call fails (kind `other`), nothing is started | Refuses | partly. Line 492 lists "device/area/floor/label targets of `turn_on`/`turn_off`/`toggle`" as rejected at load; that is the check on script actions. The run-time failure of an outside call and `group.*` are not mentioned. | no |
| SCR-3 | `cases/h16_turn_on_metadata_key.yaml::h16_turn_on_metadata_key` | `turn_on` with `metadata: 5`: fails, kind `invalid` | the script is started | Accepts | no | `patches/SCR-3.patch`; yes, `patches/SCR-3-tests.log`. `h16` then passes. |
| SCR-4 | `cases/h78_toggle_second_started_by_first.yaml::h78_toggle_second_started_by_first` | `toggle [a, b]`, both idle, `a` starts `b`: `b` is running when its turn comes, so it is turned off; both end off | `b` is started a second time; `a` and `b` stay on (`current: 2`) | Silent | no | `patches/SCR-4.patch`; yes, `patches/SCR-4-tests.log`. `h78` then passes, but `h89` and random cases r202_0196, r202_0229 (which agree unpatched) then fail because of SCR-5 (`patches/all-patches-random-summary.txt`). |
| SCR-5 | `cases/h13_toggle_two_running_and_idle.yaml`, `cases/h80_restart_old_caller_vs_new_run.yaml`, `cases/h81_turn_off_before_parallel_branches_start.yaml`, `cases/h82_toggle_script_still_stopping.yaml`, `cases/h83_restart_stop_yields_to_parallel_sibling.yaml` (each `::<file stem>`) | stopping a run (`turn_off`, `toggle`, `restart`) takes event-loop iterations: callers of the stopped run go on first (`h13`, `h80`), tasks already scheduled still run (`h81`: both `parallel` branches fire their events; `h83`: the sibling branch's service call comes first), and the script is still on meanwhile (`h82`: it is not started again) | the stop is complete at once: other order (`h13`, `h80`, `h83`), two events missing (`h81`), one extra `script_started` and run (`h82`) | Silent (`h81`, `h82`), Order (`h13`, `h80`, `h83`) | no. Lines 513-514 ("When several outside calls end in the same step, the order they finish in (asyncio task wake-ups) is not modelled") cover only the order of `call_done`, which the harness sorts. | partial: `patches/SCR-5.patch` (on top of SCR-4); yes, `patches/SCR-5-tests.log`. `h13` and `h80` then pass; `h81`, `h82`, `h83` do not. |
| SCR-6 | `cases/h85_stopped_inside_own_turn_on_step.yaml::h85_stopped_inside_own_turn_on_step`, `cases/h54_turn_on_restart_recursion_reset.yaml::h54_turn_on_restart_recursion_reset` | a run that is stopped from inside its own `script.turn_on` step ends quietly: its caller gets `None` and goes on (`outer_after` fires) | the caller is cancelled (`call_done` kind `cancelled`; `outer_after` does not fire) | Silent | no | no |
| SCR-7 | `cases/h79_queued_waiting_run_caller_cancelled.yaml::h79_queued_waiting_run_caller_cancelled` | a queued run that waits for the lock goes away when its caller is cancelled; the entity keeps `current: 2` until the next state write | `current: 1` | Silent | no (lines 508-509 are about HA writing on every step) | no |
| SCR-8 | `cases/h21_reload_child_changed_while_awaited.yaml::h21_reload_child_changed_while_awaited` | reload changes a script another script waits for; the waiting script goes on during the reload and its next call of the changed script is `ServiceNotFound` (call fails, kind `invalid`) | the new script is called and runs (`test.new_child` is called) | Silent | no | no |
| SCR-9 | `cases/h41_attributes_listing.yaml::h41_attributes_listing` | `states.script.busy.attributes \| list` of a running script contains `last_action` | no `last_action`; the script is not rejected | Silent | partly. Line 506: "`last_action` is not modelled (rejected in templates, left out of the written state, opaque in `this`)". The rejection only looks for the word. | no |
| SCR-10 | `config/matrix.yaml::alias_bool`, `alias_empty`, `icon_list`, `description_bool`, `field_required_str_true`, `field_required_yes`, `field_required_int`, `field_advanced_str`, `trace_zero`, `trace_str_5`, `trace_float` | the script loads (`cv.string`, `cv.boolean`, `cv.icon`, `cv.positive_int` coerce these values) | rejected at load | Refuses | no. Line 492 lists "invalid configs"; these are valid in HA. | `patches/SCR-10.patch` (all but `alias_empty` and `icon_list`); yes, `patches/SCR-10-tests.log`. |
| SCR-11 | `config/matrix.yaml::sequence_action_extra_key` | `sequence: [{event: e, bogus: 1}]`: validation fails, unavailable entity | loaded, state `off` | Accepts | no | no (the action decoder is the automation area's) |
| SCR-12 | `config/matrix.yaml::field_selector_bogus`, `field_selector_two`, `field_selector_number_bad` | an invalid field selector: unavailable entity | loaded | Accepts | yes, line 515: "Field selectors are not validated." | no |
| SCR-13 | `cases/h75_turn_on_single_running_from_outside.yaml::h75_turn_on_single_running_from_outside` | `turn_on` of a running `single` script waits; it returns `None` when the script next writes its state (here when it ends, 3 s later) | the call fails at once, kind `other`, with a log | Refuses | yes, lines 510-512: "Turning on a script that does not start (`single` and running, at `max`, or a `variables` error) makes HA's `turn_on` wait for the script's next state write, whenever that is. HALean fails the call instead, with a log." | no |
| SCR-14 | `cases/h77_context_passed_by_caller.yaml::h77_context_passed_by_caller` | `{{ context is string }}` renders `False` | a render error (the event is fired with `{}`) | Silent | yes, line 492: "`this` (`state.as_dict()` before the run starts) and `context` (opaque)". That an opaque value is a render error is said only for automations (lines 705-706). | no |
| SCR-15 | `cases/h18_call_removed_script_after_reload.yaml::h18_call_removed_script_after_reload`, `cases/h19_call_unknown_script.yaml::h19_call_unknown_script` | a script calls a `script.*` service that does not exist: `ServiceNotFound` in the step, the run ends (kind `invalid`) | the call is sent to HA as `call_service ['script', 'gone', {}]` and the run waits for the result | Tooling | no. By design (`HALean/Script/Entity.lean:176`: "`none`: the service is not one of HALean's scripts (HA handles it)"); the harness has no HA behind HALean to answer. | no |
| SCR-16 | `cases/h84_reload_true_vs_one.yaml::h84_reload_true_vs_one` | reload with `continue_on_error: true` rewritten as `1`: equal dicts, the entity and its run are kept | the script counts as changed: its run is stopped | Silent | yes, lines 515-516: "Reload compares configs as sent, so reordering a script's `variables` counts as a change (HA compares dicts)." | no |
| SCR-17 | `cases/h86_same_tick_nested_end_vs_turn_off.yaml::h86_same_tick_nested_end_vs_turn_off`, `cases/h87_same_tick_two_delays_order.yaml::h87_same_tick_two_delays_order` | two delays end in the same harness tick: a run that ended its last nested step can still be cancelled by the other run (`h86`); the two runs go on in the order of asyncio's timer heap (`h87`) | the first run ends before the second goes on (`h86`); the runs go on in the order their delays were started (`h87`) | Tooling | no. Lines 513-514 do not cover it (the outcome and the order of events differ, not the order of finished calls). | no |
| SCR-18 | `cases/h88_service_ok_without_response.yaml::h88_service_ok_without_response` | a `result` step without `response` for a call with `response_variable`: the harness's handler returns `None`, `ServiceRegistry.async_call` raises (kind `ha_error`) | the script goes on with an empty response | Tooling | no | no |
| SCR-19 | `cases/h90_turn_off_in_parallel_after_branch_stop.yaml::h90_turn_off_in_parallel_after_branch_stop`, `cases/h91_turn_off_in_parallel_after_branch_error.yaml::h91_turn_off_in_parallel_after_branch_error` | a script is turned off while in a `parallel` step in which one branch already ended with `stop` + response (`h90`) or with a service error (`h91`): the caller gets the response `{'v': 1}`, or the error (kind `ha_error`) | the caller gets `{}` (`h90`) or `None` (`h91`) | Silent | no | `patches/SCR-19.patch`; yes, `patches/SCR-19-tests.log`. `h90` and `h91` then pass. |

Patches and the proofs. Each patch builds `halean-script` and `halean-automation`, and the shipped suites
pass with each of them (`tests/run_script_scenarios.py` 11/11, `tests/run_scenarios.py` 60/60, pytest on
`tests/differential/test_scripts.py` and `test_differential.py` "66 passed, 6 skipped"; logs
`patches/SCR-*-tests.log`). `lake build` of the whole library fails with SCR-1, SCR-3, SCR-4 and SCR-4+5
in `HALean/Script/EntitySpec.lean`, and with SCR-10 in `HALean/Script/ConfigSpec.lean`: theorems there
state the old behaviour of `planCall` and `cvString` (`patches/per-patch-lake-build.log`,
`patches/all-patches-lake-build.log`). The patches do not update those files. With SCR-19 the whole
library builds (`patches/SCR-19-lake-build.log`). With SCR-1, 3, 4, 5 and 10 together the random cases go
from 84 to 77 failures (seed 101) and from 73 to 74 (seed 202): `patches/all-patches-random-seed101.log`,
`patches/all-patches-random-seed202.log`, `patches/all-patches-random-summary.txt`.

## Details

Outputs are the differing keys of the first differing step, copied from `logs/run1-hand.log`
(`logs/run2-hand.log` is the same). Scripts are shown without their `description`.

### SCR-1: an invalid `entity_id` of `turn_on`/`turn_off`/`toggle` is reported as kind `other`

    scripts: {a: {sequence: [{action: test.a}]}}
    steps:
      - {at: 1, call: turn_on, data: {entity_id: "not an id"}}
      - {at: 2, call: turn_off, data: {entity_id: 5}}
      - {at: 3, call: toggle, data: {entity_id: [script.a, "bad id"]}}

    step at=1  call_done  HA: [[0, False, 'invalid']]   HALean: [[0, False, 'other']]
    step at=3  call_done  HA: [[2, False, 'invalid']]   HALean: [[2, False, 'other']]

(Step 2 agrees: `entity_id: 5` is a `TypeError` in HA's `entity_ids`, kind `other`.)

Root cause: `planCall` validates `entity_id` only inside `extractTargets` and maps every error of it to
`.fail .other` (`HALean/Script/Entity.lean:206-207`). Upstream the entity service schema validates
`entity_id` with `comp_entity_ids` (`helpers/config_validation.py:369`, `:1277`), so a bad id is a
`vol.Invalid`, one of `CONFIGURATION_ERRORS` (`helpers/script.py:140`). Seen from a script step the kind
decides whether `continue_on_error` applies.

### SCR-2: outside calls with `group.*` or registry targets fail

    scripts:
      a: {sequence: [{delay: 5}]}
      b: {sequence: [{event: b_ran}]}
    steps:
      - {at: 1, call: a}
      - {at: 2, call: turn_off, data: {entity_id: group.all_scripts}}
      - {at: 3, call: turn_on, data: {entity_id: [group.x, script.b]}}

    step at=2  call_done   HA: [[1, True, None]]   HALean: [[1, False, 'other']]
    step at=3  fire_event  HA: [['script_started', {'name': 'b', 'entity_id': 'script.b'}], ['b_ran', {}]]   HALean: []
               call_done   HA: [[2, True, None]]   HALean: [[2, False, 'other']]

`h08` (`turn_off` with `area_id: kitchen`, then `device_id: abc123`): HA `[[1, True, None]]`,
`[[2, True, None]]`; HALean `[[1, False, 'other']]`, `[[2, False, 'other']]`.

Root cause: `extractTargets` throws for `device_id`/`area_id`/`floor_id`/`label_id` and for any `group.*`
id (`HALean/Script/Entity.lean:161-162`, `:170-171`). Upstream `async_extract_entities`
(`helpers/service.py:362-397`) resolves them and logs what is missing.

### SCR-3: `metadata` of any type is accepted

    scripts: {a: {sequence: [{event: a_ran}]}}
    steps:
      - {at: 1, call: turn_on, data: {entity_id: script.a, metadata: {x: 1}}}
      - {at: 2, call: turn_on, data: {entity_id: script.a, metadata: 5}}

    step at=2  fire_event  HA: []   HALean: [['script_started', {'entity_id': 'script.a', 'name': 'a'}], ['a_ran', {}]]
               call_done   HA: [[1, False, 'invalid']]   HALean: [[1, True, None]]

Root cause: `HALean/Script/Entity.lean:198` lets the key `metadata` through without looking at its value.
Upstream: `probatio.Remove("metadata"): dict` (`helpers/config_validation.py:1366`).

### SCR-4: `toggle` decides for every target before it starts or stops any

    scripts:
      a: {sequence: [{action: script.b}, {event: a_never}]}
      b: {mode: parallel, sequence: [{action: test.b}]}
    steps:
      - {at: 1, call: toggle, data: {entity_id: [script.a, script.b]}}
      - {at: 2}

    step at=1  call_service  HA: [['test', 'b', {}]]   HALean: [['test', 'b', {}], ['test', 'b', {}]]
               fire_event    HA: [script_started a, script_started b]   HALean: [script_started a, script_started b, script_started b]
               states[script.a]  HA: ['off', {... 'current': 0 ...}]   HALean: ['on', {... 'current': 1 ...}]
               states[script.b]  HA: ['off', {... 'current': 0, 'max': 10 ...}]   HALean: ['on', {... 'current': 2, 'max': 10 ...}]

Root cause: `planCall` computes `if running i then .stop i else .start i [] false` for all targets from
the state before the call (`HALean/Script/Entity.lean:212`). Upstream `toggle_service` awaits
`async_toggle` entity by entity (`components/script/__init__.py:263-267`), and `async_toggle` reads
`is_on` then (`helpers/entity.py:1820`).

The patch adds a `LocalOp.toggle` that is resolved in `callLocalH` when its turn comes. It fixes `h78`. It
makes `h89` (and r202_0196, r202_0229) fail: there the earlier target turns the later one off, HA still
sees the later one on (its stop is pending, SCR-5) and turns it off, and the patched HALean sees it off and
starts it. The unpatched plan happens to agree with HA in that case.

### SCR-5: a stop is complete at once

`h13` (toggle of a running and an idle script; a caller waits for the first):

    scripts:
      first: {sequence: [{delay: 10}]}
      second: {sequence: [{event: second_ran}]}
      caller: {sequence: [{action: script.first}, {event: caller_after_first}]}
    steps:
      - {at: 1, call: caller}
      - {at: 2, call: toggle, data: {entity_id: [script.first, script.second]}}

    step at=2  fire_event  HA:     [['caller_after_first', {}], ['script_started', {'name': 'second', ...}], ['second_ran', {}]]
                           HALean: [['script_started', {... 'second'}], ['second_ran', {}], ['caller_after_first', {}]]

`h80` (a restart script awaited by a caller is restarted from outside):

    scripts:
      r: {mode: restart, fields: {n: {}}, sequence: [{event: r_enter, event_data: {n: "{{ n }}"}}, {delay: 5}]}
      caller: {sequence: [{action: script.r, data: {n: 1}}, {event: caller_after}]}
    steps:
      - {at: 1, call: caller}
      - {at: 2, call: r, data: {n: 2}}

    step at=2  fire_event  HA:     [['script_started', {'name': 'r', ...}], ['caller_after', {}], ['r_enter', {'n': 2}]]
                           HALean: [['script_started', {... 'r'}], ['r_enter', {'n': 2}], ['caller_after', {}]]

`h81` (one `turn_on` starts a script whose first step is `parallel`, then a script that turns it off):

    scripts:
      p: {sequence: [{parallel: [{event: p_branch_1}, {event: p_branch_2}]}, {event: p_after}]}
      killer: {sequence: [{action: script.turn_off, target: {entity_id: script.p}}]}
    steps:
      - {at: 1, call: turn_on, data: {entity_id: [script.p, script.killer]}}

    step at=1  fire_event  HA:     [script_started p, script_started killer, ['p_branch_1', {}], ['p_branch_2', {}]]
                           HALean: [script_started p, script_started killer]

`h82` (toggle of a script that turns itself off, and of a second script that toggles the first):

    scripts:
      selfoff: {sequence: [{action: script.turn_off, target: {entity_id: script.selfoff}}]}
      second: {sequence: [{action: script.toggle, target: {entity_id: script.selfoff}}]}
    steps:
      - {at: 1, call: toggle, data: {entity_id: [script.selfoff, script.second]}}

    step at=1  fire_event  HA:     [script_started selfoff, script_started second]
                           HALean: [script_started selfoff, script_started second, script_started selfoff]

`h83` (a `parallel` step: branch one turns on a running restart script, branch two calls a service):

    step at=2  call_service  HA: [['test', 'p', {}], ['test', 'r', {}]]   HALean: [['test', 'r', {}], ['test', 'p', {}]]

Root cause: `stopRunH` removes the run and answers its caller within the same handler call
(`HALean/Automation/Engine.lean:778-792`); the answered caller is only put on `woken` (`:758`) and resumes
after the whole input (`resumeWoken`, `:1037-1049`). `callLocalH` runs all ops of a handler without a break
(`:866-905`), and `startScriptH` stops the old runs of a restart script and drives the new run at once
(`:851`, `:859`). Upstream every stop is awaited: `_ScriptRun.async_stop` waits for `_stopped`
(`helpers/script.py:604-612`), `Script.async_stop` shields an `asyncio.wait` (`:2014-2033`), a restart does
`await self.async_stop(update_state=False, spare=run)` before the new run starts (`:2000`), `toggle`
awaits entity by entity (`components/script/__init__.py:266-267`), `turn_off` awaits `asyncio.wait`
(`:255-260`). During those awaits the stopped run is still in `Script._runs` (`is_on` is true), `gather`'s
branch tasks that were scheduled earlier run (`helpers/script.py:724-727`), and the callers of the stopped
runs resume.

The patch lets the callers of the stopped runs go on (`continueNow`) right after a restart's stops and
after each stop made by `toggle`. It fixes `h13`, `h80`, seven random cases of seed 101 and one of seed 202
(`patches/all-patches-random-summary.txt`); it does not model the pending stop (`h81`, `h82`, `h83`).

### SCR-6: a run stopped from inside its own `script.turn_on` step is reported as cancelled

    scripts:
      a: {sequence: [{action: script.turn_on, target: {entity_id: script.c}}, {event: a_never}]}
      c: {sequence: [{action: script.turn_off, target: {entity_id: script.a}}]}
      outer: {sequence: [{action: script.a}, {event: outer_after}]}
    steps:
      - {at: 1, call: a}
      - {at: 2, call: outer}

    step at=1  call_done   HA: [[0, True, None]]   HALean: [[0, False, 'cancelled']]
    step at=2  fire_event  HA:     [script_started outer, script_started a, script_started c, ['outer_after', {}]]
                           HALean: [script_started outer, script_started a, script_started c]
               call_done   HA: [[1, True, None]]   HALean: [[1, False, 'cancelled']]

`h54` is the same with a restart script: `a` (restart) turns on `b`, `b` calls `a`; the outside call of
`a` ends with `[[0, True, None]]` in HA and `[[0, False, 'cancelled']]` in HALean.

Root cause: `stopRunH` answers `.cancelled` for every run that waits in a service call, unless it is in
`e.starting` (`HALean/Automation/Engine.lean:791`, `stoppedQuietly` `:550-553`). Upstream the stop only
sets the run's `_stop` future (`helpers/script.py:604-606`). `a` is at that moment executing its `turn_on`
step synchronously: `c` was started as an eager task from inside it and suspends in its `turn_off`;
`turn_on` then returns because `c` already wrote its state (`components/script/__init__.py:697-702`). The
long action of `a` is a finished task, `_async_run_long_action` (`helpers/script.py:677-688`) returns
without suspending, so the interrupt never fires. The loop then sees `self._stop.done()` and breaks
(`:513-516`): a normal end, the caller gets `None`. 7 of the 18 minimised random cases of seed 101 are this
one.

### SCR-7: `current` of a queued script after the caller of a waiting run is cancelled

    scripts:
      q: {mode: queued, sequence: [{action: test.q}]}
      outer: {sequence: [{action: script.q}]}
    steps:
      - {at: 1, call: q}
      - {at: 2, call: outer}
      - {at: 3, call: turn_off, data: {entity_id: script.outer}}
      - {at: 4}
      - {at: 5, result: 0}

    step at=3  states[script.q]  HA:     ['on', {'last_triggered': '2023-11-14T22:13:22+00:00', 'mode': 'queued', 'current': 2, 'max': 10, 'friendly_name': 'q'}]
                                 HALean: ['on', {'last_triggered': '2023-11-14T22:13:22+00:00', 'mode': 'queued', 'current': 1, 'max': 10, 'friendly_name': 'q'}]
    step at=4  the same

After step 5 both sides say `off`, `current: 0`.

Root cause: HA's state is stale. `Script.async_run` handles the cancellation with
`await run.async_stop(); self._changed(); raise` (`helpers/script.py:2009-2012`). A queued run that never
started is not awaited by `async_stop` (`:604-612`, `_started` is false), so `_changed()` writes the state
while the run is still in `_runs`. The run's own `_finish` comes later and does not write, because
`_ScriptRun._changed` skips the write once `_stop` is done (`:475-477`). HALean removes the run and writes
the exact count (`HALean/Automation/Engine.lean:785-787`, `writeEntity` `:508-523`). A template that reads
`state_attr('script.q', 'current')` in that window gets different values. Random cases r101_0054 and
r101_0273 show it after a reload.

### SCR-8: a reload is one atomic step

    scripts:
      child: {sequence: [{delay: 10}]}
      parent: {sequence: [{action: script.child}, {event: parent_after}, {action: script.child}, {event: parent_after_2}]}
    steps:
      - {at: 1, call: parent}
      - at: 2
        reload:
          parent: (unchanged)
          child: {sequence: [{action: test.new_child}]}
      - {at: 3}

    step at=2  call_service  HA: []   HALean: [['test', 'new_child', {}]]
               fire_event    HA: [['parent_after', {}]]   HALean: [['parent_after', {}], ['script_started', {'entity_id': 'script.child', 'name': 'child'}]]
               call_done     HA: [[0, False, 'invalid']]   HALean: []
               states[script.parent]  HA: ['off', {... 'current': 0 ...}]   HALean: ['on', {... 'current': 1 ...}]

Root cause: `reloadScripts` stops the runs of the changed scripts, adds the new entities and only then lets
woken runs go on (`HALean/Script/Service.lean:103-119`, `resumeWoken` at `:173`). Upstream
`_async_process_config` first awaits the removal of every changed entity
(`components/script/__init__.py:404-410`; `async_will_remove_from_hass` removes the service at `:775` and
then awaits `async_unload`), and creates the new entities afterwards (`:412-416`). `parent` resumes during
those awaits, when `script.child` is not registered: `ServiceNotFound`.

### SCR-9: `last_action` is readable without naming it

    scripts:
      busy: {sequence: [{delay: 5}]}
      look:
        sequence:
          - event: look
            event_data: {keys: "{{ states.script.busy.attributes | list | sort | join(',') }}"}
    steps:
      - {at: 1, call: look}
      - {at: 2, call: busy}
      - {at: 3, call: look}

    step at=3  fire_event  HA:     [..., ['look', {'keys': 'current,friendly_name,last_action,last_triggered,mode'}]]
                           HALean: [..., ['look', {'keys': 'current,friendly_name,last_triggered,mode'}]]

Root cause: `checkAttributes` rejects a script only when the text `last_action` occurs in it
(`HALean/Script/Config.lean:81-84`); `entityAttributes` leaves the attribute out
(`HALean/Script/Entity.lean:46-55`). Upstream `extra_state_attributes` adds it while the script runs
(`components/script/__init__.py:602-603`).

### SCR-10: values HA coerces are rejected at load

From `logs/run1-matrix.log`:

    MATRIX alias_bool: Refuses
        HA:     ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'friendly_name': 'True'}])
        HALean: ('rejected', 'alias: expected a string, got true')
    MATRIX alias_empty: Refuses
        HA:     ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0}])
        HALean: ('rejected', 'an empty alias is not supported')
    MATRIX icon_list: Refuses
        HA:     ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'icon': "['mdi:x']", 'friendly_name': 'x'}])
        HALean: ('rejected', 'icon: expected a string, got ["mdi:x"]')
    MATRIX field_required_str_true: Refuses
        HA:     ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'friendly_name': 'x'}])
        HALean: ('rejected', 'field f: required must be a boolean')
    MATRIX trace_zero: Refuses
        HA:     ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'friendly_name': 'x'}])
        HALean: ('rejected', 'stored_traces must be a positive integer')

The other six (`description_bool`, `field_required_yes`, `field_required_int`, `field_advanced_str`,
`trace_str_5`, `trace_float`) have the same shape. Configs: `alias: true`; `alias: ""`;
`icon: ["mdi:x"]`; `description: false`; `fields: {f: {required: "true" | "yes" | 1}}`;
`fields: {f: {advanced: "on"}}`; `trace: {stored_traces: 0 | "5" | 2.5}`; each with `sequence: []`.

Root cause: `cvString` takes strings and numbers only (`HALean/Script/Config.lean:37-40`); upstream
`cv.string` is `str()` of anything but `None`, a list or a dict (`helpers/config_validation.py:653-668`)
and `cv.icon` is `str(value)` (`:450-457`). `decodeFields` wants JSON booleans (`Config.lean:116-117`);
upstream `cv.boolean` (`:218-231`). `stored_traces` must be a JSON integer ≥ 1 (`Config.lean:156-158`);
upstream `cv.positive_int` is `Coerce(int)`, `Range(min=0)` (`:185`). The empty alias is refused on purpose
(`Config.lean:140-141`). The patch adds the bool case to `cvString`, a `cvBoolean`, and the integer
coercion; with it only `alias_empty` and `icon_list` remain (`patches/SCR-10-tests.log`).

### SCR-11: an action with an extra key is loaded

    MATRIX sequence_action_extra_key: Accepts
        HA:     ('rejected', 'unavailable entity')
        HALean: ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'friendly_name': 'x'}])

Config: `x: {sequence: [{event: e, bogus: 1}]}`. Root cause: the `event` branch of `decodeAction` reads its
keys and ignores the rest (`HALean/Automation/Config.lean:1092-1099`); upstream the event action schema
refuses extra keys (`async_validate_actions_config`, called at `components/script/config.py:266`).
Reported here because the script loader shows it; the decoder belongs to the automation area.

### SCR-12 (documented): field selectors are not validated

    MATRIX field_selector_bogus: Accepts
        HA:     ('rejected', 'unavailable entity')
        HALean: ('loaded', ['script.x', 'off', {'last_triggered': None, 'mode': 'single', 'current': 0, 'friendly_name': 'x'}])

Same for `field_selector_two` (`{text: {}, number: {}}`) and `field_selector_number_bad`
(`{number: {min: a}}`). `decodeFields` (`HALean/Script/Config.lean:120-121`); upstream `validate_selector`
(`components/script/config.py:98`).

### SCR-13 (documented): `turn_on` of a script that does not start

    scripts: {s: {sequence: [{delay: 3}, {event: s_done}]}}
    steps:
      - {at: 1, call: s}
      - {at: 2, call: turn_on, data: {entity_id: script.s}}
      - {at: 5}

    step at=2  call_done  HA: []                                  HALean: [[1, False, 'other']]
    step at=5  call_done  HA: [[0, True, None], [1, True, None]]   HALean: [[0, True, None]]

`callLocalH`, `HALean/Automation/Engine.lean:891-898`; upstream `await self._changed.wait()`
(`components/script/__init__.py:699-702`). The README text describes exactly this. 78 of the 157 failing
random cases have this as their first difference.

### SCR-14 (documented): the run variable `context` is opaque

    scripts: {v: {sequence: [{event: v, event_data: {ctx_is_string: "{{ context is string }}"}}]}}
    steps:
      - {at: 1, call: v}
      - {at: 2, call: v, data: {context: mine}}

    step at=1  fire_event  HA: [..., ['v', {'ctx_is_string': False}]]   HALean: [..., ['v', {}]]

`startScriptH` sets `context` to `.opaque "context"` (`HALean/Automation/Engine.lean:842`); every use of an
opaque value throws in the renderer (`HALean/Template/Render.lean:183`). In an event the error is logged
and the event is fired without data, as HA does for a template error; in a service call the run would end.

### SCR-15 (tooling): a `script.*` service HALean does not own is sent to HA

    scripts: {runner: {sequence: [{action: script.does_not_exist, continue_on_error: true}, {event: never}]}}
    steps:
      - {at: 1, call: runner}

    step at=1  call_service  HA: []   HALean: [['script', 'does_not_exist', {}]]
               call_done     HA: [[0, False, 'invalid']]   HALean: []
               states[script.runner]  HA: ['off', {... 'current': 0 ...}]   HALean: ['on', {... 'current': 1 ...}]

`planCall` returns `none` (`HALean/Script/Entity.lean:213-216`) and `driveH` then leaves the `call_service`
command in the output (`HALean/Automation/Engine.lean:621-630`). That is how scripts HALean rejected, which
stay in HA, are reached. The harness gives HALean no HA to answer; with the bridge HA would answer "not
found". `h18` is the same after a reload removed the script.

### SCR-16 (documented): reload compares the config text

    scripts: {a: {sequence: [{delay: 3}, {event: a_done, continue_on_error: true}]}}
    steps:
      - {at: 1, call: a}
      - at: 2
        reload: {a: {sequence: [{delay: 3}, {event: a_done, continue_on_error: 1}]}}
      - {at: 4}

    step at=2  call_done  HA: []   HALean: [[0, True, None]]
               states[script.a]  HA: ['on', {... 'current': 1 ...}]   HALean: ['off', {... 'current': 0 ...}]
    step at=4  fire_event  HA: [['a_done', {}]]   HALean: []

`reloadScripts` compares `raw`, the compressed JSON (`HALean/Script/Service.lean:97-98`); upstream compares
dicts (`components/script/__init__.py:366-369`), and `True == 1` in Python. `delay: 5` → `5.0` agrees
(case `h20`).

### SCR-17 (tooling): two delays that end in the same harness tick

`h86`:

    scripts:
      nested: {sequence: [{repeat: {count: 1, sequence: [{delay: 2}]}}]}
      stopper: {sequence: [{delay: 1}, {action: script.turn_off, target: {entity_id: script.nested}}]}
    steps:
      - {at: 1, call: nested}
      - {at: 2, call: stopper}
      - {at: 3}

    step at=3  call_done  HA: [[0, False, 'cancelled'], [1, True, None]]   HALean: [[0, True, None], [1, True, None]]

`h87` (two runs of a parallel script with `delay 3`, started in one step at t=16):

    step at=20  fire_event  HA: [['p_done', {'v': 0}], ['p_done', {'v': 10}]]   HALean: [['p_done', {'v': 10}], ['p_done', {'v': 0}]]

Cause: the harness advances a frozen clock one second at a time and calls `async_fire_time_changed`, which
runs every due timer in one go, in the order of `loop._scheduled`
(`pytest_homeassistant_custom_component/common.py:543-563`), a heap. In `h86` the first run needs one more
event-loop iteration to return from `repeat` and is stopped in between; in `h87` the heap order is not the
order the delays were started in (with `at: 1` instead of `at: 16` the case agrees). On a real event loop
the two delays have different deadlines. HALean's order is the order the delays were started in.

### SCR-18 (tooling): an ok result without a response for a call that asked for one

    scripts: {s: {sequence: [{action: test.get, response_variable: r}, {event: s_after}]}}
    steps:
      - {at: 1, call: s}
      - {at: 2, result: 0}

    step at=2  fire_event  HA: []   HALean: [['s_after', {}]]
               call_done   HA: [[0, False, 'ha_error']]   HALean: [[0, True, None]]

The harness's handler returns `st.get("response")`, here `None`; `ServiceRegistry.async_call` refuses that
for `return_response=True` (`core.py:2966-2973`). A scenario has to give a `response` for such a call.

### SCR-19: a run stopped in `parallel` after a branch already raised

`h90`:

    scripts:
      p:
        sequence:
          - variables: {out: {v: 1}}
          - parallel:
              - delay: 5
              - stop: done
                response_variable: out
          - event: p_never
    steps:
      - {at: 1, call: p, return_response: true}
      - {at: 2, call: turn_off, data: {entity_id: script.p}}
      - {at: 7}

    step at=2  call_done  HA: [[0, True, {'v': 1}], [1, True, None]]   HALean: [[0, True, {}], [1, True, None]]

`h91` (branches `delay: 5` and `action: test.fails`; the service call fails with `ha_error` at t=2, the
script is turned off at t=3):

    step at=3  call_done  HA: [[0, False, 'ha_error'], [1, True, None]]   HALean: [[0, True, None], [1, True, None]]

Root cause: `stopRunH` answers the caller of a run stopped in a top-level `parallel` with `.ok .none`
(`HALean/Automation/Engine.lean:791`; `stoppedQuietly`, the `.joinPar` case, `:550-553`) and drops the
results the finished branches already gave. Upstream the stop makes `gather` return; then
`for result in results: if isinstance(result, Exception): raise result` (`helpers/script.py:728-730`)
raises what the finished branch raised: `_StopScript` gives the run its response (`:531-542`), an error
goes to the caller through `_handle_exception` (`:614-641`). The cancelled branches are `CancelledError`,
not `Exception`, and are skipped. The patch makes `stopRunH` look at the recorded branch results of a
top-level `.joinPar` wait, as `finishBranchH` does (`Engine.lean:716-726`).

## Reading findings without a reproducer

* An outside `call` of `script.reload` is answered "not found" (`HALean/Script/Service.lean:157-160`;
  `planCall` knows no `reload`). HA has that service. Not driven: the harness has its own `reload` step,
  and HA's service would read a config file.
* Restoring `last_triggered` at `init` from the `states` HALean is sent
  (`HALean/Script/Service.lean:134-135`). HA restores from its restore-state store. The harness sets initial
  states with `hass.states.async_set`, which does not fill that store, and HA then names the new entity
  `script.a_2`. Tried once (a case with an initial `script.a` state, removed from `cases/`): not comparable.
* `writeEntity` only writes when the state or an attribute changed (`HALean/Automation/Engine.lean:516-518`);
  HA writes on every `_changed()`. The harness does not compare `last_updated`, `last_reported` or
  state-change events, so this cannot be seen (README lines 508-509 say it).
* A parallel script on a call cycle recurses up to `max` runs; with three self-calls per run the work is
  exponential in `max` on both sides. halean-script took more than a minute for `max: 10` in a random
  scenario; timings for `max` 6 and 8 are in `logs/perf-recursion.log` (halean-script alone: 0.12 s for
  1093 events, 4.0 s for 9841). The results agree.
* `Script.async_run` refuses to run after `async_unload` (`helpers/script.py:1907-1910`, `RuntimeError`).
  HALean has no such state; no way was found to reach it through services (the service is removed before
  the unload).

## Notes on the harness

What `tests/differential/test_scripts.py` cannot observe in this area:

* **Load-time rejection.** It asserts that HALean rejects nothing, and `unsupported.yaml` is engine-only.
  Whether HA and HALean agree on which configs are valid is not compared anywhere.
  `harness/test_config_matrix.py` was written for that (new code, not a copy).
* **HALean's logs.** `lean_run` returns them and the test drops them (`k != "logs"`). The documented
  `turn_on` gap (SCR-13) and a delegated `script.*` call (SCR-15) are only recognisable from HALean's
  output; `gen/triage.py` reads them.
* **Calls HALean sends to HA for `script.*` services.** Nobody answers them (SCR-15).
* **State between steps.** States are compared after each step only. Intermediate writes, `last_changed`,
  `last_updated`, `last_reported`, the context and `state_changed` events are not compared. `last_action`
  is not in `ATTRS`.
* **Order of finished outside calls.** `call_done` is sorted by call number on both sides (the README gap
  at lines 513-514), so that order is never compared.
* **Event and call context.** `script_started` is compared by type and data only.
* **`entity_id` shape in service calls.** `norm_data` turns a string into a one-element list on both sides.
* **Restore at start.** HA's restore-state store cannot be filled from a scenario (see above).
* **Time.** The clock is frozen and moves in whole seconds; all timers due in a tick run in one
  `async_fire_time_changed`, in heap order (SCR-17). Two things that are due "in the same second" are
  simultaneous in the harness and not on a real event loop.
* **Service results.** A `result` step without `response` makes HA's handler return `None` (SCR-18), and a
  `result: n` step for a call one side did not make is an `IndexError` in the harness, not a reported
  difference (16 random cases, `logs/run1-random-seed101-triage.txt`, `logs/run1-random-seed202-triage.txt`).
* **Background failures.** A script started by `turn_on` that ends with an exception makes the HA test
  plugin report a teardown error ("Task exception was never retrieved"); the comparison itself is not
  affected (case `h71`).
* **Scripts that never settle.** `_settle` runs 50 event-loop iterations; scripts that keep each other
  running (turn_on cycles) are cut at an arbitrary point on the HA side.
