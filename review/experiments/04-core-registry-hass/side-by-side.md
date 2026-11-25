# Side-by-side reading: service registry and joined core

Upstream: `upstream/ha-core/homeassistant/core.py` (tag 2026.10.4) unless another file is named.
Lean: `HALean/Core/ServiceRegistry.lean` (SR), `HALean/Core/Hass.lean` (H), `HALean/Core/ServicesJson.lean` (SJ),
drivers `Exe/CoreServices.lean`, `Exe/Core.lean`.
The entries are the 39 `manifest.yaml` entries whose `lean:` names are defined in SR, H or SJ.
"REG-n" / "HASS-n" refer to `FINDINGS.md`.

## Service registry

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `SupportsResponse` | core.py:2541-2551 | SR:36-47 | none found |
| `Service` | core.py:2554-2585 | SR:50-65 | The job is a `HandlerSpec`. `job_type`, `description_placeholders` and the job name are not modelled (manifest says so). |
| `ServiceCall` (`__init__`, `__repr__`) | core.py:2588-2619 | SR:234-252 | `ReadOnlyDict(data or {})`: Lean keeps the list as is, same content. `context or Context()` is done by the caller in both. `__repr__`: `if self.data` ↔ `c.data.isEmpty` (SR:251), after validation in both (case `s_validated_data_empty_after_remove_extra`). No difference found. |
| `ServiceRegistry.async_services` | core.py:2638-2646 | SR:193 | none found (a copy upstream, a value in Lean) |
| `ServiceRegistry.async_services_for_domain` | core.py:2649-2656 | SR:197-198 | none found; the domain is not lowercased on either side |
| `ServiceRegistry.has_service` | core.py:2671-2676 | SR:176-179 | `str.lower()` is ASCII only in Lean (`String.toLower`); the drivers refuse non-ASCII names (SJ:19-23). Documented, README:339. |
| `ServiceRegistry.supports_response` | core.py:2678-2687 | SR:184-190 | none found; `KeyError(domain.lower())` first, then `KeyError(service.lower())` |
| `ServiceRegistry.async_register` / `_async_register` | core.py:2715-2791 | SR:202-210; H:569-578 | none found. Lowercase, replace in place or append, a new domain appended, `service_registered` with `{domain, service}` and no context. `verify_event_loop_thread` not modelled (no threads). In H the handler script is stored beside the registry (`bodies`, H:573), replaced on re-registration. |
| `ServiceRegistry.async_remove` / `_async_remove` | core.py:2800-2827 | SR:214-229; H:579-588 | none found. Warning text `Unable to remove unknown service %s/%s` with lowercased names (SR:229), domain dropped when empty, `service_removed`. |
| `ServiceRegistry.async_call` | core.py:2857-2974 | SR:284-417; H:602-633 | Order of checks is the same: `context or Context()` (H:608; SR:413), lookup as given then lowercased (SR:284-288), `ServiceNotFound` with lowercased names (SR:345), the three `return_response` rules in upstream order (SR:318-327), `if target: update` (SR:330-332), schema (SR:352-357), `call_service` with the merged unvalidated data and the call's context (SR:379-382), handler, response check (SR:399-406). Differences: (1) `service_data or {}` and `if target:` accept any falsy value upstream (`[]`, `0`, `""`); the drivers accept only a dict or null (SJ:31-37) and answer `unsupported`. Documented, README:339. (2) The debug log `Invalid data for service call` is below warning level, not compared. (3) Message of `ServiceNotFound`: see `async_get_exception_message` below (REG-1). (4) In H a call nested deeper than 32 is refused (H:605), HASS-1. |
| `ServiceRegistry._run_service_call_catch_exceptions` | core.py:2976-2993 | SR:389-398; H:626-633, 678-684 | `except Exception` → `Error executing service: <ServiceCall ...>` with `exc_info`; same text (SR:396). `Unauthorized` and `CancelledError` branches are not modelled (handlers cannot raise them; manifest and README:346 say so). After a suspension the log is written when the task resumes (H:682), as upstream. |
| `ServiceRegistry._execute_service` | core.py:2995-3012 | SR:255-261; H:620-633 | Only the `Coroutinefunction` branch exists in H (scripted `async def`). `Callback` and `Executor` handlers are not modelled (README:429). In SR the handler never suspends. |
| `exceptions.py::HomeAssistantError` | exceptions.py:33-90 | SR:97-111, 148-149 | `str()` of a translated error is `async_get_exception_message(...)`; of a plain one, the message. `errorKind` (SR:106-111) lists five HA classes by name; the harness uses `isinstance`. Same result for the classes the model can raise. |
| `exceptions.py::ServiceValidationError`, `ServiceNotFound` | exceptions.py:110-111, 415-427 | SR:302-303, 152-153 | none found (placeholders `domain`, `service` in that order) |
| `helpers/translation.py::async_get_exception_message` | translation.py:432-458 | SR:119-144 | The five English strings equal `components/homeassistant/strings.json` (checked against the installed file). `rstrip(".")` ↔ `rstripDots`. **Differs:** upstream does one `str.format(**placeholders)`; Lean replaces `{key}` once per placeholder, one after the other (SR:132-133), so a value that contains a later placeholder is substituted again. Reachable with a domain that contains `{service}`: REG-1. `ServiceRegistrySpec.lean:99-101` (`formatPlaceholders_append`) states the sequential behaviour as a theorem. |
| `util/__init__.py::repr_helper` | util/__init__.py:47-56 | SR:242-246 | none found for JSON values (datetimes not modelled, manifest says so) |
| `Context.__init__` | core.py:1287-1298 | `State.lean` `Context`; SR:74; H:262-270 | **Differs:** `self.id = id or ulid_now()`: an empty id is replaced by a fresh ULID. `decodeContext` (SJ:257-261) keeps `""`. The registry driver passes it on (REG-2); the core driver refuses it (`Exe/Core.lean:86`, HASS-2). |
| `probatio:_compile.py::_make_candidate` | (schema reviewer's area) | SJ:215-246 | not reviewed here |

Driver `Exe/CoreServices.lean` before the model sees the input: `parsePyJson` (dict order kept, int/float kept);
`now` required (lines 48-50); names must be ASCII (`getName`); `data`/`target` dict or null; `decodeHandler`
(SJ:43-55) takes `return` first, then `echo: true`, then `raise` — the harness (`test_services.py:62-73`,
`test_core.py:202-209`) takes `raise` first, then `echo`, then `return` (REG-3); `unsupportedCall?` (SR:367-376) is
asked before `asyncCall` and turns a schema the model cannot run into `unsupported` (line 85).

## Joined core

| manifest entry | upstream | Lean | difference |
|---|---|---|---|
| `StateMachine.async_set` / `async_set_internal` / `async_remove` (the `Hass.runAction`, `smQueued` part) | core.py:2313-2540 | H:298-300, 535-556 | Only the wiring was read here: the state machine's events go to `fireList` → `fireInternal` with the context the state machine passes and `time_fired` = the clock. No difference found. The state machine itself is another reviewer's area. |
| `EventBus.async_fire` / `async_fire_internal` | core.py:1567-1640 | H:410-433, 519-521 | none found. Queue while dispatching (H:413-416), 10,000 limit raising in the firing script, `_dispatching` reset (H:421; upstream `finally`, the Lean dispatch cannot raise). |
| `EventBus._async_dispatch` | core.py:1643-1680 | H:438-463 | none found. Snapshot `listeners + match_all_listeners` (H:419, 461), filter errors logged and skipped, the `Event` made on the first job that passes, `Error running job` for a `@callback` that raises. |
| `EventBus.async_listen` / `async_listen_once` | core.py:1703-1823 | H:522-527 | none found for what the driver lets through. `run_immediately`, non-callback filters, `listen_once` + filter, `state_reported` without filter are refused by the driver (`Exe/Core.lean:160-164`), README:429. |
| `EventBus._async_remove_listener` | core.py:1825-1845 | H:315-320 | The Lean log always carries `ValueError: list.remove(x): x not in list` (H:319). Upstream catches `KeyError, ValueError`; `_listeners` is a `defaultdict(list)`, so the `KeyError` branch is not reached. No difference found (case `h_unsub_twice_logs`). |
| `_OneTimeListener.__call__` | core.py:1471-1478 | H:323-325, 487-497 | none found (cases `h_once_listener_unsub_after_it_ran`, `h_once_listener_unsubbed_by_earlier_listener`) |
| `HomeAssistant.async_run_hass_job`, `_async_add_hass_job`, `HassJobType`, `get_hassjob_callable_job_type` | core.py:288-294, 349-362, 730-771, 913-938 | H:469-497, 385-391 | `Callback` → inline (H:481-482). `Coroutinefunction` → `create_eager_task`, `if task.done(): return task` (the caller drops it), else `_tasks.add` + done callback (H:385-391). `Executor` and partials not modelled (README:429). No difference found. |
| `HomeAssistant.async_create_task` / `async_create_task_internal` | core.py:788-836 | H:557-568, 385-391, 626-627 | Eager start only (`eager_start=False` not modelled, README:429). No difference found. |
| `HomeAssistant.async_block_till_done` | core.py:995-1025 | H:801-804, 691-698, 644-659 | `await asyncio.sleep(0)` (H:803), then `while tasks := [...]` (H:691-698). `wait_background_tasks`, the `cancelling` filter and the debug logs are not modelled. The list `tasks` keeps finished tasks referenced until it is rebuilt: `endRound` (H:644-650). Two failed tasks in one list are refused (`unsupported`, H:647), README:429. No difference found. |
| `HomeAssistant._await_and_log_pending` | core.py:1027-1040 | H:655-659, 721-723 | One `asyncio.wait` round; the 60 s timeout never fires. `_on_completion` is scheduled at once for a task that is already done (H:659), in line with `Future.add_done_callback`. No difference found. |
| asyncio (not a manifest entry; the model's claim) | CPython 3.14 `asyncio/tasks.py`, `futures.py`, `base_events.py` | H:353-399, 702-754 | Ready queue FIFO (H:353, 735-746). `sleep(0)` = bare yield → `call_soon(step)` (H:368). `await fut` → done callback, woken in order by `set_result` (H:369-371, 396-399). Task end → done callbacks in registration order: `_tasks.remove`, then `_on_completion` (H:702-704). A failed task is logged when its last reference goes: at `spawn` for an eager task that is already done (H:388), at its `.done` handle otherwise (H:720), at `endRound` if pinned (H:646). 800 random core cases per run and 63 hand-written core cases found no difference in this part (FINDINGS, Counts). |

Driver `Exe/Core.lean` before the model sees the input: `parsePyJson`; `now` required (line 211); entity ids,
domains and services ASCII only; a context needs a non-empty id (line 86, HASS-2); `inherit` only inside scripts;
`catch` only in a coroutine (line 195); `sleep` only with the integer 0 (lines 203-204); a `@callback` cannot await
(line 202); handler specs through `decodeHandler` when one of `return`/`echo`/`raise` is present (line 177-178,
REG-3); the whole operation is answered `unsupported` and the state is left unchanged when any trace entry is
`unsupported` (lines 264-265). Results of `call` are `repr()` strings (line 254).

## Guards that HA does not have

| guard | Lean | upstream | README |
|---|---|---|---|
| `MAX_CALL_DEPTH = 32` | H:241, 605 | none; Python's recursion limit is reached at about 191 nested calls in the harness (logs/run1-ha-only-refused.log, case `refused_depth_chain_401`: the first `RecursionError` is recorded for call `c190`) | README:429 lists the refusal and says "HA would hit `RecursionError`". Between 33 and about 190 HA returns normally (HASS-1). |
| `FUEL = 1000000` | H:244 | none | README:429 ("endless rescheduling") |
| `LOOP_FUEL = 100000` handles | H:247, 733 | none | README:429 |
| a future resolved twice | H:396-399, 595 | `asyncio.InvalidStateError` raised in the script | README:429 |
| the main task waits with nothing to run | H:736-737 | HA hangs | README:429 |
