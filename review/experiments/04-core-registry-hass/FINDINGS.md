# Findings: service registry (`REG`) and joined core (`HASS`)

Reviewed commit `f638a3779195a42a5162939aa67981b9b501618e`, against Home Assistant 2026.10.4.

Short answer. The order of checks in `async_call`, registration and removal, the event payloads, the log texts and
the task scheduling (eager start, FIFO ready queue, futures, `sleep(0)`, `block_till_done` rounds, the moment a
failed task is logged) matched HA in every case that both sides ran: 800 random core cases and 800 random registry
cases per run, and 96 of the 105 hand-written cases. The 9 hand-written cases that differ have three causes
(REG-1, REG-2, REG-3). None of them is in the scheduler. Five more rows are refusals (`unsupported`); four of those
are listed in the README, one (HASS-2) is not, and for one (HASS-1) the README gives a reason that is not true.

## Counts

| what | number | log |
|---|---|---|
| new hand-written registry cases (`cases/services/registry_review.yaml`) | 42 | `logs/run1-hand-services.log`: "6 failed, 37 passed" (42 cases + the shipped `test_probatio_matches_pin`) |
| new hand-written core cases (`cases/hass/*.yaml`) | 63 | `logs/run1-hand-core.log`: "3 failed, 60 passed" |
| HA-only cases for refused operations (`cases/refused/refused.yaml`) | 8 | `logs/run1-ha-only-refused.log`: "8 passed" (this runner asserts nothing; it prints HA's and HALean's answers) |
| random registry cases per run (seeds 11 and 22, 400 each; 11,271 operations) | 800 | `logs/run1-random-services.log`: "801 passed" (800 + `test_probatio_matches_pin`); operations: `gen/out-run1/services/*.summary.json` |
| random core cases per run (seeds 101 and 202, 400 each; 13,634 operations in the files; 376 of the cases are `manual`) | 800 | `logs/run1-random-core.log`: "800 passed"; operations: `gen/out-run1/core/*.summary.json` |
| runs | 2 | `logs/run1-*.log`, `logs/run2-*.log`; run 2 regenerated the random files from the same seeds, byte-identical (`logs/run2-gen-diff.log`) |
| hand-written cases that diverge | 9 (6 registry, 3 core), the same 9 in both runs | `logs/run1-hand-services.log`, `logs/run1-hand-core.log`, `logs/run2-hand-services.log`, `logs/run2-hand-core.log` |
| random cases that diverge | 0 in both runs | `logs/run1-random-services.log`, `logs/run1-random-core.log`, `logs/run2-random-services.log` ("801 passed"), `logs/run2-random-core.log` ("800 passed") |
| hand-written cases that contain an operation HALean answers `unsupported` | 7 (6 core, 1 registry); they pass because the operation carries `unsupported: true` | same hand logs; HA's answers in `logs/run1-ha-only-refused.log` |
| random core operations HALean answers `unsupported` | 140 of 13,634: 90 "a future resolved twice", 50 "the main task waits with nothing left to run". Both reasons are listed in README:429. | `gen/out-run1/core/random_core_101.summary.json`, `random_core_202.summary.json`; `logs/run1-random-core-coverage.log` |
| random registry operations HALean answers `unsupported` | 0 | `gen/out-run1/services/*.summary.json` |

What the 800 random core cases exercise, counted on the engine (`logs/run1-random-core-coverage.log`): 8,928
deliveries, 211 scripted call outcomes, 114 "Task exception was never retrieved" logs, 79 "Error executing
service" logs, 88 "Error running job" logs, 854 operations whose result is an exception.

## Divergences

| ID | reproducer (case file::name) | HA result | HALean result | kind | README lists it? (line) | patch? (file, shipped tests still pass? log) |
|---|---|---|---|---|---|---|
| REG-1 | `cases/services/registry_review.yaml::s_brace_domain_not_found` (also `::s_brace_service_in_domain_uppercase`, `cases/hass/nested_calls.yaml::h_brace_in_names_not_found`, `::h_brace_domain_in_script_call`) | `ServiceNotFound`, message `Action {service}.x not found` | `ServiceNotFound`, message `Action x.x not found` | Silent | no | `patches/REG-1.patch`; yes, 127 passed; `patches/REG-1.test.log`. The patch breaks two theorems of `ServiceRegistrySpec.lean` that state the old behaviour (see Details). |
| REG-2 | `cases/services/registry_review.yaml::s_ctx_empty_id` (also `::s_ctx_empty_id_nonblocking_error_log`) | context id is a fresh ULID (`new`) in the response, the `call_service` event and the log | context id is `''` in all three | Silent | no | `patches/REG-2.patch`; yes, 127 passed; `patches/REG-2.test.log` |
| REG-3 | `cases/services/registry_review.yaml::s_handler_spec_with_raise_and_return` (also `::s_handler_spec_with_echo_and_return`, `cases/hass/nested_calls.yaml::h_handler_spec_with_raise_and_return`) | the handler raises `ValueError: v` (harness: `raise`, then `echo`, then `return`) | the handler returns `{'a': 1}` (driver: `return`, then `echo`, then `raise`) | Tooling | no | `patches/REG-3.patch`; yes, 127 passed; `patches/REG-3.test.log`. The patch breaks `ServicesJsonSpec.decodeHandler_return`. |
| REG-4 | `cases/hass/refusals.yaml::h_refused_falsy_non_dict_data_and_target`; HA's answer: `cases/refused/refused.yaml::refused_call_data_falsy_non_dict` | `data: []` and `target: []` are accepted (`service_data or {}`, `if target:`); the call returns the echo | `unsupported`: `'data' must be a dict`, `'target' must be a dict` | Refuses, documented | yes, README:339: "non-dict `data`/`target`" | no patch |
| HASS-1 | `cases/hass/depth_chain.yaml::h_depth_chain_32_ok_33_41_refused`; HA's answer: `cases/refused/refused.yaml::refused_depth_chain_33_and_41`, `::refused_depth_chain_151`, `::refused_depth_chain_401` | 33, 41 and 151 nested blocking calls return `None` with the full trace; `RecursionError` only at about 191 nested calls | `unsupported`: `call depth` from 33 nested calls on | Refuses, documented; the documented reason is wrong | yes, README:429: "service calls nested deeper than 32 (HA would hit `RecursionError`)". HA does not hit it at 33. | `patches/HASS-1.patch` (limit 150); yes, 127 passed; `patches/HASS-1.test.log`. It moves the limit; it does not model HA's `RecursionError`. |
| HASS-2 | `cases/hass/refusals.yaml::h_refused_context_empty_id`; HA's answer: `cases/refused/refused.yaml::refused_context_empty_id` | `Context(id="")` gets a fresh ULID; the event is delivered with it, `user_id` kept | `unsupported`: `a context needs a non-empty id` | Refuses | no | no patch (not small: the fresh id would have to be drawn each time the scripted action runs, in `Exe/Core.lean`, `Hass.lean` and `EventBus.lean`) |
| HASS-3 | `cases/hass/tasks.yaml::h_resolve_twice_in_callback_listener`, `cases/hass/refusals.yaml::h_refused_resolve_twice_top_level`; HA's answer: `cases/refused/refused.yaml::refused_resolve_twice_in_callback_listener`, `::refused_resolve_twice_top_level` | `asyncio.InvalidStateError: invalid state`: raised to the caller, or logged as `Error running job` when a `@callback` listener does it; the dispatch goes on | `unsupported`: `a future resolved twice (asyncio.InvalidStateError)` | Refuses, documented | yes, README:429: "futures resolved twice (`asyncio.InvalidStateError`, whose name clashes with HA's) or with an exception" | no patch |
| HASS-4 | HA's answer: `cases/refused/refused.yaml::refused_two_failed_tasks_in_one_block_till_done` (the shipped `async_never_returning_rejected` has the model side) | `block_till_done` returns; two `Task exception was never retrieved` logs (`ValueError: one`, then `ValueError: two`, in both runs) | `unsupported`: `two task exceptions logged in set order` | Refuses, documented | yes, README:429: "two failed tasks freed by the same `block_till_done` check (logged in `_tasks`'s set order)" | no patch |

## Details

### REG-1 — a placeholder value that contains another placeholder is substituted twice

Reproducer (`cases/services/registry_review.yaml::s_brace_domain_not_found`):

```yaml
- name: s_brace_domain_not_found
  ops:
    - {op: call, domain: "{service}", service: x, blocking: true}
```

`logs/run1-hand-services.log` (the same in `logs/run2-hand-services.log`):

```
HA:     {'ok': False, 'error': {'exception': 'ServiceNotFound', 'error_kind': 'ha_error', 'message': 'Action {service}.x not found', 'translation_domain': 'homeassistant', 'translation_key': 'service_not_found', 'translation_placeholders': {'domain': '{service}', 'service': 'x'}}, 'events': [], 'logs': []}
HALean: {'error': {'error_kind': 'ha_error', 'exception': 'ServiceNotFound', 'message': 'Action x.x not found', 'translation_domain': 'homeassistant', 'translation_key': 'service_not_found', 'translation_placeholders': {'domain': '{service}', 'service': 'x'}}, 'events': [], 'logs': [], 'ok': False}
```

The same through the joined core, from a handler's nested call
(`cases/hass/nested_calls.yaml::h_brace_domain_in_script_call`, `logs/run1-hand-core.log`, the same in run 2):

```
HA:     {'call': 'c', 'error': {'error_kind': 'ha_error', 'exception': 'ServiceNotFound', 'message': 'Action {service}.y not found', 'translation_domain': 'homeassistant', 'translation_key': 'service_not_found', 'translation_placeholders': {'domain': '{service}', 'service': 'y'}}}
HALean: {'call': 'c', 'error': {'error_kind': 'ha_error', 'exception': 'ServiceNotFound', 'message': 'Action y.y not found', 'translation_domain': 'homeassistant', 'translation_key': 'service_not_found', 'translation_placeholders': {'domain': '{service}', 'service': 'y'}}}
```

Root cause. Upstream `helpers/translation.py:454` does one `message.format(**translation_placeholders)`.
`HALean/Core/ServiceRegistry.lean:132-133` (`formatPlaceholders`) folds `String.replace` over the placeholders, so
after `{domain}` has been replaced by `{service}`, the next step replaces that text too. Only `ServiceNotFound`
(`core.py:2896`, `exceptions.py:418-424`) puts caller text into placeholders; the names are lowercased first, so
`X{SERVICE}` is hit too. `HALean/Core/ServiceRegistrySpec.lean:96` (`formatPlaceholders_nil`) and `:99-101`
(`formatPlaceholders_append`: formatting with `a ++ b` equals formatting with `a`, then with `b`) are stated for the
sequential replacement; the second is false for Python's `str.format`. With the patch (one pass over the template)
both executables build, the shipped suites pass and the reproducers pass (`patches/REG-1.test.log`), but
`lake build HALean.Core.ServiceRegistrySpec` fails at these two theorems.

### REG-2 — `Context(id="")` in the registry driver

Reproducer (`cases/services/registry_review.yaml::s_ctx_empty_id`):

```yaml
- name: s_ctx_empty_id
  ops:
    - {op: register, domain: test_a, service: echo, handler: {echo: true}, supports_response: optional}
    - {op: call, domain: test_a, service: echo, blocking: true, return_response: true, context: {id: ""}}
```

`logs/run1-hand-services.log` (the same in run 2):

```
HA:     {'ok': True, 'result': "{'domain': 'test_a', 'service': 'echo', 'data': {}, 'return_response': True, 'context_id': 'new'}", 'events': [{'event_type': 'call_service', 'data': "{'domain': 'test_a', 'service': 'echo', 'service_data': {}}", 'time_fired': 1795192246000, 'context': {'id': 'new', 'user_id': None, 'parent_id': None}}], 'logs': []}
HALean: {'events': [{'context': {'id': '', 'parent_id': None, 'user_id': None}, 'data': "{'domain': 'test_a', 'service': 'echo', 'service_data': {}}", 'event_type': 'call_service', 'time_fired': 1795192246000}], 'logs': [], 'ok': True, 'result': "{'domain': 'test_a', 'service': 'echo', 'data': {}, 'return_response': True, 'context_id': ''}"}
```

(`new` is how the harness writes a random ULID.) Root cause. Upstream `core.py:1294`: `self.id = id or ulid_now()`.
`HALean/Core/ServicesJson.lean:257-261` (`decodeContext`) keeps the empty id and `Exe/CoreServices.lean:84`
passes it to `Registry.asyncCall` (`ServiceRegistry.lean:413`). The core driver has a guard instead
(`Exe/Core.lean:86`), which is HASS-2. The harness is not the cause: it builds `Context(id="", ...)` from the case
as written (`tests/differential/test_services.py:120-122`), which is what a caller of HA would do. The patch maps
an empty id to the registry's fresh id in the driver.

### REG-3 — handler spec with more than one of `return` / `echo` / `raise` (tooling)

Reproducer (`cases/services/registry_review.yaml::s_handler_spec_with_raise_and_return`):

```yaml
- name: s_handler_spec_with_raise_and_return
  ops:
    - {op: register, domain: test_a, service: both, handler: {raise: ValueError, message: v, return: {a: 1}}, supports_response: optional}
    - {op: call, domain: test_a, service: both, blocking: true, return_response: true}
```

`logs/run1-hand-services.log` (the same in run 2):

```
HA:     {'ok': False, 'error': {'exception': 'ValueError', 'error_kind': 'other', 'message': 'v'}, 'events': [{'event_type': 'call_service', 'data': "{'domain': 'test_a', 'service': 'both', 'service_data': {}}", 'time_fired': 1795192246000, 'context': {'id': 'new', 'user_id': None, 'parent_id': None}}], 'logs': []}
HALean: {'events': [{'context': {'id': 'new', 'parent_id': None, 'user_id': None}, 'data': "{'domain': 'test_a', 'service': 'both', 'service_data': {}}", 'event_type': 'call_service', 'time_fired': 1795192246000}], 'logs': [], 'ok': True, 'result': "{'a': 1}"}
```

Core (`cases/hass/nested_calls.yaml::h_handler_spec_with_raise_and_return`, `logs/run1-hand-core.log`):

```
HA:     {'error': {'error_kind': 'other', 'exception': 'ValueError', 'message': 'v'}}
HALean: {'ok': "{'a': 1}"}
```

Root cause. The documented spec format is one of the three (`Exe/CoreServices.lean:16-17`). Neither side checks
it. `HALean/Core/ServicesJson.lean:43-55` (`decodeHandler`) takes `return` first, then `echo: true`, then `raise`.
The harness takes `raise` first, then `echo`, then `return` (`tests/differential/test_services.py:62-73`,
`tests/differential/test_core.py:202-209`). This is a disagreement between test driver and harness, not between the
model and HA. The patch gives the driver the harness order. `ServicesJsonSpec.lean:309-311`
(`decodeHandler_return`) states the driver's order and no longer builds with the patch.

### REG-4 — falsy non-dict `data` / `target` (documented refusal)

`logs/run1-ha-only-refused.log`, case `refused_call_data_falsy_non_dict` (the same in run 2):

```
op 1 {"op": "call", "domain": "test", "service": "e", "blocking": true, "return_response": true, "data": []}
  HA:     {"result": {"ok": "{'domain': 'test', 'service': 'e', 'data': {}, 'return_response': True, 'context_id': 'ctx#0'}"}, "trace": []}
  HALean: {"unsupported": "'data' must be a dict"}
op 2 {"op": "call", "domain": "test", "service": "e", "blocking": true, "return_response": true, "data": {"a": 1}, "target": []}
  HA:     {"result": {"ok": "{'domain': 'test', 'service': 'e', 'data': {'a': 1}, 'return_response': True, 'context_id': 'ctx#1'}"}, "trace": []}
  HALean: {"unsupported": "'target' must be a dict"}
```

Upstream `core.py:2884` (`service_data = service_data or {}`) and `core.py:2923` (`if target:`).
Lean `ServicesJson.lean:31-37` (`getDict?`). README:339 lists "non-dict `data`/`target`" as rejected.

### HASS-1 — call depth 32 (documented refusal; the README's reason does not hold)

Reproducer: `cases/hass/depth_chain.yaml::h_depth_chain_32_ok_33_41_refused`: 41 services `d0`..`d40`, each handler
is `do: [{call: {id: c<i>, domain: test, service: d<i+1>, blocking: true}}]`, `d40` fires `bottom`. No service
calls itself. Calling `d9` (32 nested calls) is accepted and equal on both sides; calling `d8` (33) and `d0` (41)
is refused.

`logs/run1-ha-only-refused.log` (the same in run 2; long traces cut here with `...`):

```
=== refused_depth_chain_33_and_41
op 42 {"op": "call", "domain": "test", "service": "d8", "blocking": true}
  HA:     {"result": {"ok": "None"}, "trace": [{"delivery": "m", "event": {"context": {"id": "ctx#0", "parent_id": null, "user_id": null}, "data": {}, "event_type": "bottom", "origin": "LOCAL", "time_fired": "2026-11-26T16:30:45.123456+00:00"}}, {"call": "c39", "ok": "None"}, {"call": "c38", "ok": "None"}, ...
  HALean: {"unsupported": "call depth"}
=== refused_depth_chain_151
op 152 {"op": "call", "domain": "test", "service": "d0", "blocking": true}
  HA:     {"result": {"ok": "None"}, "trace": [{"delivery": "m", "event": {...}}, {"call": "c149", "ok": "None"}, {"call": "c148", "ok": "None"}, ...
  HALean: {"unsupported": "call depth"}
=== refused_depth_chain_401
op 402 {"op": "call", "domain": "test", "service": "d0", "blocking": true}
  HA:     {"result": {"error": {"error_kind": "other", "exception": "RecursionError", "message": "maximum recursion depth exceeded"}}, "trace": [{"call": "c190", "error": {"error_kind": "other", "exception": "RecursionError", "message": "maximum recursion depth exceeded"}}, {"call": "c189", "error": ...
  HALean: {"unsupported": "call depth"}
```

Root cause. `HALean/Core/Hass.lean:241` (`MAX_CALL_DEPTH := 32`) and `:605`. Upstream has no limit of its own
(`core.py:2857-2974`); Python's recursion limit is reached at about 191 nested calls in this harness (the deepest
call that records an error is `c190`). README:429 says "service calls nested deeper than 32 (HA would hit
`RecursionError`)" and `Hass.lean:239-240` says "Python's recursion limit is reached somewhere around there".
Between 33 and about 190 nested calls HA returns normally and HALean refuses. `patches/HASS-1.patch` sets the limit
to 150: the chains of 33, 41 and 150 nested calls then pass (`patches/HASS-1.test.log`, cases in
`patches/HASS-1-cases/depth.yaml`) and the shipped suites pass, including `runaway_recursion_rejected`. The exact
depth of HA's `RecursionError` depends on the Python frames of the caller, so no constant is exact.

### HASS-2 — `Context(id="")` in the core driver (refusal, not in the README)

Reproducer: `cases/hass/refusals.yaml::h_refused_context_empty_id`:

```yaml
- name: h_refused_context_empty_id
  ops:
    - {op: listen, id: m, event_type: "*"}
    - {op: fire, event_type: x, context: {id: "", user_id: u}, unsupported: true}
    - {op: set, entity_id: light.a, state: "on", context: {id: ""}, unsupported: true}
    - {op: call, domain: test, service: nope, blocking: true, context: {id: ""}, unsupported: true}
    - {op: fire, event_type: x, context: {id: " "}}
```

`logs/run1-ha-only-refused.log` (the same in run 2):

```
=== refused_context_empty_id
op 1 {"op": "fire", "event_type": "x", "context": {"id": "", "user_id": "u"}}
  HA:     {"result": {"ok": null}, "trace": [{"delivery": "m", "event": {"context": {"id": "ctx#0", "parent_id": null, "user_id": "u"}, "data": {}, "event_type": "x", "origin": "LOCAL", "time_fired": "2026-11-26T16:30:45.123456+00:00"}}]}
  HALean: {"unsupported": "a context needs a non-empty id"}
op 2 {"op": "set", "entity_id": "light.a", "state": "on", "context": {"id": ""}}
  HA:     {"result": {"ok": null}, "trace": [{"delivery": "m", "event": {"context": {"id": "ctx#1", "parent_id": null, "user_id": null}, "data": {"entity_id": "light.a", "new_state": {...}, "old_state": null}, "event_type": "state_changed", ...}}]}
  HALean: {"unsupported": "a context needs a non-empty id"}
```

Root cause. Upstream `core.py:1294` (`id or ulid_now()`); Lean `Exe/Core.lean:86`. The README's rejected column
(README:429) does not list it. It is the safe side of REG-2.

### HASS-3 — a future resolved twice (documented refusal)

`logs/run1-ha-only-refused.log` (the same in run 2):

```
=== refused_resolve_twice_in_callback_listener
op 3 {"op": "fire", "event_type": "go"}
  HA:     {"result": {"ok": null}, "trace": [{"delivery": "r", "event": {"context": {"id": "ctx#2", "parent_id": null, "user_id": null}, "data": {}, "event_type": "go", "origin": "LOCAL", "time_fired": "2026-11-26T16:30:45.123456+00:00"}}, {"log": {"exception": "InvalidStateError: invalid state", "level": "error", "message": "Error running job"}}, {"delivery": "m", "event": {...}}]}
  HALean: {"unsupported": "a future resolved twice (asyncio.InvalidStateError)"}
=== refused_resolve_twice_top_level
op 1 {"op": "resolve", "id": "f"}
  HA:     {"result": {"error": {"error_kind": "other", "exception": "InvalidStateError", "message": "invalid state"}}, "trace": []}
  HALean: {"unsupported": "a future resolved twice (asyncio.InvalidStateError)"}
```

Lean `Hass.lean:396-399`, `:595`. README:429 lists it. In the random runs this is 90 of the 140 refused
operations.

### HASS-4 — two failed tasks freed by one `block_till_done` check (documented refusal)

Reproducer (`cases/refused/refused.yaml::refused_two_failed_tasks_in_one_block_till_done`, `manual: true`): two
`async` listeners on `two`, each `react: [{sleep: 0}, {raise: ValueError, message: one|two}]`; `fire two`;
`block_till_done`.

`logs/run1-ha-only-refused.log` (the same order in `logs/run2-ha-only-refused.log`):

```
op 3 {"op": "block_till_done"}
  HA:     {"result": {"ok": null}, "trace": [{"log": {"exception": "ValueError: one", "level": "error", "message": "Error doing job: Task exception was never retrieved"}}, {"log": {"exception": "ValueError: two", "level": "error", "message": "Error doing job: Task exception was never retrieved"}}]}
  HALean: {"unsupported": "two task exceptions logged in set order"}
```

Lean `Hass.lean:644-650` (`endRound`). Upstream `core.py:1001-1009`: the list `tasks` is built from the set
`self._tasks`. README:429 lists it.

## Reading findings without a reproducer

* `ServiceRegistrySpec.lean:99-101` (`formatPlaceholders_append`) is a proved statement about the Lean function
  that is false for the Python function it translates (REG-1). The behaviour has a reproducer (REG-1); the point
  here is that a theorem in a `Spec` file fixes the divergent behaviour, which no differential case shows.
* `_run_service_call_catch_exceptions` (`core.py:2983-2991`): the `Unauthorized` (warning) and `CancelledError`
  (debug) branches have no Lean counterpart (`ServiceRegistry.lean:389-398`). The drivers only let five exception
  classes through (`ServiceRegistry.lean:114-115`), so they cannot be driven. README:346 lists it.
* `_execute_service` (`core.py:3005-3012`): `@callback` and executor handlers are not modelled; the harness only
  builds `async def` handlers, so they cannot be driven. README:429 lists it.
* `errorKind` (`ServiceRegistry.lean:106-111`) decides `ha_error` by a list of five class names; the harness uses
  `isinstance(err, HomeAssistantError)`. A `HomeAssistantError` subclass outside the list (for example
  `MaxLengthExceeded`) would be `other`. No operation the drivers accept raises one.
* `Hass.removeListener` (`Hass.lean:315-320`) always logs `ValueError: list.remove(x): x not in list`. Upstream
  (`core.py:1833-1845`) also catches `KeyError`; `_listeners` is a `defaultdict`, so that branch is not reached
  and no difference could be produced.
* `pyTypeStr` (`ServiceRegistry.lean:291-300`) answers `<class 'object'>` for values it does not name. JSON input
  cannot produce such a value.
* The core driver refuses `sleep: 0.0` (`Exe/Core.lean:203-204`, only the integer 0) and a negative `react_times`
  (`Exe/Core.lean:70`); the harness side would accept both. These are format restrictions of the test driver, not
  of the model, and were not run.
* `async_block_till_done(wait_background_tasks=True)`, the `cancelling(task)` filter and the debug logs after
  `BLOCK_LOG_TIMEOUT` (`core.py:1001-1025`) are not modelled, and the harness cannot reach them (no background
  tasks, no cancellation, frozen clock).

## Notes on the harness

* The engine is asked first, and an operation marked `unsupported: true` is never run on HA
  (`tests/differential/test_core.py:425-427`, `test_services.py:197-199`). A refusal of something HA accepts
  cannot fail a shipped test. `harness/test_core_ha_only.py` was added to see HA's answer.
* `engine_only` cases (`test_core.py:400-407`) never run HA.
* Core: results and traces are compared as JSON after `json.dumps(sort_keys=True)` (`test_core.py:130`), so dict
  key order is only visible inside `repr()` strings (call results, the `ServiceCall` repr in a log). The registry
  harness compares `repr(event.data)`, so order is compared there.
* Only log records at warning level and above are compared, from the loggers `homeassistant` and
  `homeassistant.core` (core) or `homeassistant.core` (registry). The debug record `Invalid data for service call`
  (`core.py:2930`) is not compared. For `Error running job` and `Unable to remove unknown job listener` only the
  fixed prefix is compared (`test_core.py:345-351`).
* Any 26-character Crockford-base32 word in HA's output is renamed as a context id (`test_core.py:76`,
  `test_services.py:46`). User data of that shape would produce a false difference. The new cases avoid it.
* In non-manual cases the trace of the operation and of the `block_till_done` after it are joined
  (`test_core.py:434`), so the boundary between the two is not compared.
* A failed task's log is only ordered against other trace entries (deliveries, call outcomes, logs). Loop handles
  that leave no trace entry cannot be told apart as the moment of the log.
* `hass._tasks` is only checked to be empty at the end of a case (`test_core.py:460`).
* Handlers are always `async def`; listeners are `@callback` or `async def`. Executor jobs are never built.
* The random generators pre-screen with the engine (see `README.md`). A random case can therefore not show a
  wrong refusal either. The refusal reasons are counted (`gen/out-run1/*/*.summary.json`); all 140 belong to two
  reasons the README lists.

## Mutation checks

Each mutation is one changed line in `HALean/Core/Hass.lean`, in a throwaway copy
(`/tmp/claude-0/halean-copies/04-core-registry-hass-1`, deleted afterwards), `lake build halean-core`, then the
shipped `tests/differential/test_core.py` (38 cases) in that copy. Unmutated baseline in the same copy:
"38 passed" (`mutations/M0-unmutated-baseline.test_core.log`).

| README claim (lines 410-413) | mutation (patch) | failing cases | log |
|---|---|---|---|
| "making the ready queue LIFO fails all 15 async cases" | `Hass.enqueue`: `ready := x :: h.ready` (`mutations/M1-lifo-ready-queue.patch`) | 15 failed, 23 passed (pytest also reports 3 teardown errors, for 3 of the 15 failed tests). The 15 are the 7 cases of `async_listeners.yaml`, the 6 of `async_services.yaml`, and `async_rejected_inputs` and `async_never_returning_rejected` of `unsupported.yaml`. Claim confirmed: 15. | `mutations/M1-lifo-ready-queue.test_core.log` |
| "freeing a failed task at its done callback even while `async_block_till_done` holds it fails 3" | `runHandle`, `.done`: `if task.pinned && false then` (`mutations/M2-free-failed-task-at-done-callback.patch`) | 3 failed, 35 passed (`async_listener_errors`, `block_till_done_with_task_error`, `async_never_returning_rejected`). Claim confirmed: 3. | `mutations/M2-free-failed-task-at-done-callback.test_core.log` |
| "dropping `async_block_till_done`'s initial `sleep(0)` fails 1" | `step`, `.blockTillDone`: `drive now (resume FUEL now h [.btdCheck] (.ok .none))` (`mutations/M3-drop-initial-sleep0.patch`) | 1 failed, 37 passed (`async_listener_errors`). Claim confirmed: 1. | `mutations/M3-drop-initial-sleep0.test_core.log` |
