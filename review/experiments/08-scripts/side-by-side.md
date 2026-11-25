# Side by side: scripts as entities

Upstream paths are relative to `upstream/ha-core/homeassistant/` (tag 2026.10.4). Lean paths are relative
to `/home/user/halean/`. "Case" names are files in `cases/`; "matrix" names are entries of
`config/matrix.yaml`. IDs refer to `FINDINGS.md`.

## 1. `components/script/config.py::_async_validate_config_item` → `HALean.Script.decodeScript`, `decodeFields`, `isSlug`

| Upstream | Lean | Difference |
|---|---|---|
| `_SCRIPT_OBJECT_ID_SCHEMA` (`config.py:71`): `cv.slug`, not in `_INVALID_OBJECT_IDS` (`config.py:64`). A bad id raises; `_try_async_validate_config_item` (`config.py:273`) returns `None`: no entity at all. | `decodeScript` (`HALean/Script/Config.lean:130-132`), `isSlug` (`:43`), `INVALID_OBJECT_IDS` (`:20`). | No difference found (matrix `slug_*`, `reserved_*`: 15 entries agree). |
| `SCRIPT_ENTITY_SCHEMA` (`config.py:82`): `alias`: `cv.string` (`helpers/config_validation.py:653`: `str()` of everything but `None`, list, dict). | `cvString` (`Config.lean:37-40`): strings and numbers only. An empty alias is refused (`Config.lean:140`). | `alias: true` loads in HA (friendly name `True`) and is refused by HALean; `alias: ""` loads in HA (no `friendly_name`) and is refused. SCR-10. |
| `icon`: `cv.icon` (`config_validation.py:450`): `str(value)` must contain `:`. | `Config.lean:143-149`: `cvString`, then `:`. | `icon: ["mdi:x"]` loads in HA (icon `"['mdi:x']"`), refused by HALean. SCR-10. |
| `description`: `cv.string`, default `""`. | `Config.lean:150`. | `description: false` loads in HA, refused by HALean. SCR-10. |
| `trace`: `TRACE_CONFIG_SCHEMA` (`components/trace/__init__.py:32`): `stored_traces: cv.positive_int` = `Coerce(int)`, `Range(min=0)`. | `Config.lean:151-158`: a JSON integer ≥ 1. | `stored_traces: 0`, `"5"`, `2.5` load in HA, refused by HALean. SCR-10. |
| `mode`: `In(SCRIPT_MODE_CHOICES)`; `max`: `Coerce(int)`, `Range(min=2)`; `max_exceeded`: `Upper`, `In(...)` (`helpers/script.py:298-319`). | `Config.lean:159-174`, `pyIntOfJson?` (`HALean/Automation/Config.lean:1183`). | No difference found (matrix `mode_*`, `max_*`, `max_exceeded_*`: 24 entries agree, including `max: 2.7`, `"3"`, `true`). |
| `fields`: `{cv.string: {advanced: cv.boolean, default, description/example/name: cv.string, required: cv.boolean, selector: validate_selector}}` (`config.py:90-100`). `cv.boolean` (`config_validation.py:218`) takes `"true"`, `"yes"`, `1`, ... | `decodeFields` (`Config.lean:109-123`): `advanced`/`required` must be JSON booleans; a selector must be a mapping or null and is not looked at. | `required: "true"`, `"yes"`, `1`, `advanced: "on"` load in HA, refused by HALean (SCR-10). A selector HA refuses (`{bogus_selector: {}}`, two selectors, `number: {min: a}`) is loaded by HALean (SCR-12, README line 515 says selectors are not validated). |
| `variables`: `cv.SCRIPT_VARIABLES_SCHEMA` (`config_validation.py:1399`). | `orderedMapping` (`Config.lean:178-180`), `decodeComplex` (`:190`). | No difference found (matrix `variables_*`). |
| `sequence`: `cv.SCRIPT_SCHEMA`, then `async_validate_actions_config` (`config.py:266`). | `Config.lean:181-191`, `decodeAction` (automation area). | `sequence: [{event: e, bogus: 1}]` is refused by HA (extra key) and loaded by HALean (matrix `sequence_action_extra_key`, SCR-11; the decoder belongs to the automation area). |
| A schema error gives an `UnavailableScriptEntity` (`__init__.py:335-344`). | Rejected (`unsupported`), README line 492. | Documented. The shipped harness cannot compare this (see `FINDINGS.md`, notes). |
| — | `checkActions` (`Config.lean:64-77`), `checkAttributes` (`:81-87`): text checks for what HALean does not model. | `checkAttributes` looks for the text `last_action`. A template that lists `states.script.x.attributes` reads `last_action` without naming it (case `h41`, SCR-9). |

## 2. `config.py::async_validate_config` → `decodeAll`, `passedNames`

Upstream `config.py:294-311`: every `object_id: cfg` of every `script:` block; duplicates are skipped.
Lean `HALean/Script/Service.lean:50-55`, `Config.lean:92-105`. `passedNames` exists only in HALean (the
names other scripts pass are allowed in templates). No difference found by reading; scripts whose templates
use other names are refused (README line 492; seen while writing cases `h15`, `h17`).

## 3. `__init__.py::async_setup.turn_on_service` / `turn_off_service` / `toggle_service` → `planCall`, `callLocal`

| Upstream | Lean | Difference |
|---|---|---|
| `SCRIPT_TURN_ONOFF_SCHEMA` (`__init__.py:81`) = `make_entity_service_schema({Optional("variables"): {str: match_all}})` (`config_validation.py:1360-1393`): `Remove("metadata"): dict`, `ENTITY_SERVICE_FIELDS` (`:1276`), at least one of them. `entity_id`: `comp_entity_ids`. | `planCall` (`HALean/Script/Entity.lean:188-216`): key check `:196-199`, at-least-one `:200-201`, `variables` `:202-205`. | (a) `metadata` of any type is accepted (`Entity.lean:198`); HA requires a dict (case `h16`, SCR-3). (b) An invalid `entity_id` is found only in `extractTargets` and becomes `.fail .other` (`Entity.lean:206-207`); in HA it is the schema's `vol.Invalid` (case `h06`, SCR-1). `entity_id: 5` is a `TypeError` in HA (`entity_ids` iterates the value, `config_validation.py:359`), so `other` is right there. |
| `component.async_extract_from_service` → `service.async_extract_entities` (`helpers/service.py:362-397`): `all` gives every available entity; else the referenced ids, groups expanded, registry targets resolved; unknown ids are logged. | `extractTargets` (`Entity.lean:160-172`): `device_id`/`area_id`/`floor_id`/`label_id` and `group.*` are an error. | An outside `turn_off` with `area_id: kitchen` or `entity_id: group.x` returns normally in HA and fails in HALean (cases `h07`, `h08`, SCR-2). In script actions the registry targets are refused at load (`Config.lean:69-72`); `group.*` is not. |
| `turn_on_service` (`__init__.py:236-243`): for each entity, `await async_turn_on(variables, wait=False)`. | `planCall` → `.start i vars false` (`Entity.lean:210`), `callLocalH` (`Engine.lean:887-898`). | A script that does not start: README lines 510-512 (case `h75`, SCR-13). Otherwise no difference found. |
| `turn_off_service` (`__init__.py:245-261`): all entities stopped together (`asyncio.wait` of eager tasks). | `.stop i` for each (`Entity.lean:211`), `callLocalH` `Engine.lean:899-903`. | The stop is immediate in HALean; in HA it takes event-loop iterations (SCR-5: cases `h81`, `h82`). |
| `toggle_service` (`__init__.py:263-267`): for each entity in turn, `await async_toggle` (`helpers/entity.py:1814-1823`): `is_on` is read when its turn comes. | `planCall` decides for every target before any op runs: `if running i then .stop i else .start i [] false` (`Entity.lean:212`). | When an earlier target starts or stops a later one, HALean does the wrong thing with the later one (case `h78`, SCR-4). HA awaits the stop of one entity before going to the next, so whoever waited for the stopped run goes on first (case `h13`, SCR-5). |
| Response: `supports_response` is `NONE`; `ServiceRegistry.async_call` raises `ServiceValidationError` (`core.py:2909-2913`), a script step raises `vol.Invalid` first (`helpers/script.py:1073`). | `Service.step` (`Service.lean:151-156`), `planCall` (`Entity.lean:193-194`). | No difference found (shipped `service_errors`). |

## 4. `__init__.py::ScriptEntity._service_handler`, `_async_start_run`, `_async_run`, `async_turn_on` → `planCall`, `startScript`, `callLocal`, `continueNow`, `callResponse`

| Upstream | Lean | Difference |
|---|---|---|
| `_service_handler` (`__init__.py:733-740`): `variables=service.data`, `wait=True`; with `return_response`, `response or {}`. `async_call` then requires a dict (`core.py:2966-2973`). | `planCall` `Entity.lean:214-216`, `callResponse` `Entity.lean:221-228`, `answerH` `Engine.lean:732-760`. | No difference found (cases `h02`-`h05`, `h51`, `h67`, `h73`). |
| `_async_start_run` (`__init__.py:669-703`): fires `script_started` before anything else; `wait=True` copies the script stack; `wait=False` sets a fresh stack, starts the run as an eager task and awaits the first state write. | `startScriptH` (`Engine.lean:817-860`): event first (`:821`); `callLocalH` passes the caller's root stack (`:877-881`) or `[]` (`:889`). | No difference found for the stack (cases `h25`-`h29`, `h52`-`h54`) and the event (case `h32`). |
| `_async_run` (`__init__.py:705-723`): `this = state.as_dict()`, `script_vars = {"this": this, **variables}`. | `Engine.lean:823-826`, `scriptThis` (`Entity.lean:73-88`). | No difference found (cases `h37`, `h64`). `last_action` is opaque in `this` (README line 506). |
| `Script.async_run` (`helpers/script.py:1901-2012`): mode check (`:1926-1941`), `variables` rendered (`:1944-1953`), `context` set (`:1956`), recursion check (`:1964-1985`), run added, restart stops the others with `await self.async_stop(update_state=False, spare=run)` (`:2000`), `last_triggered`, `_changed()`, then the run as an eager task under `shield`; on cancellation `await run.async_stop(); self._changed(); raise` (`:2007-2012`). | `admit` (`Engine.lean:494-501`), `startScriptH` (`:827-860`): same order of checks. Restart stops the old runs at once (`:851`) and drives the new run at once (`:859`). | (a) The restart's stop is awaited in HA: who waited for the old run goes on before the new run's first step, and other tasks run in between (cases `h80`, `h83`, SCR-5). (b) `self._changed()` after a cancelled caller writes the state while a queued run that never started is still in `_runs`; its later `_finish` does not write (`_ScriptRun._changed`, `script.py:475-477`), so HA's `current` stays one too high until the next write (case `h79`, SCR-7). |
| `_ScriptRun.async_stop` (`script.py:604-612`) and `_async_run_long_action` (`:677-688`): a run stopped while it awaits a long action is cancelled. The interrupt only fires when the run really suspends. | `stopRunH` (`Engine.lean:778-792`), `stoppedQuietly` (`:550-553`): a run in a service wait is always `cancelled`, except `e.starting`. | A run stopped from inside its own `script.turn_on` step, when that step then returns without suspending, ends quietly in HA (the loop sees `_stop` before the next step) and its caller gets `None`. HALean reports `cancelled` (case `h54`, SCR-6). |
| `_QueuedScriptRun.async_run` / `_finish` (`script.py:1392-1420`). | `releaseQueueH` (`Engine.lean:688-695`), `Wait.queued`. | No difference found in outcomes (cases `h23`, `h30`, `h35`, `h53`, `h74`); see SCR-7 for the state. |
| `async_turn_off` (`__init__.py:726-731`) → `Script.async_stop` (`script.py:2021-2033`). | `.stop` in `callLocalH` (`Engine.lean:899-903`). | SCR-5. |

## 5. `__init__.py::ScriptEntity.__init__`, `extra_state_attributes`, `is_on`, `async_change_listener` → `decodeScript`, `entityAttributes`, `scriptThis`, `entityState`, `writeEntity`

Upstream `__init__.py:554-655`. Lean `Entity.lean:46-88`, `Engine.lean:508-523`. Attributes and their order
agree (cases `h01`, `h43`, `h44`; fractional seconds in `last_triggered` agree). `last_action` is left out
(README line 506). `writeEntity` writes the exact number of runs whenever it changes; HA writes what
`script.runs` is at the moments `_changed()` is called, which can be stale (SCR-7).

## 6. `__init__.py::async_setup.reload_service`, `_async_process_config`, `async_added_to_hass`, `async_will_remove_from_hass` → `Service.step`, `reloadScripts`, `addScripts`

| Upstream | Lean | Difference |
|---|---|---|
| `find_matches` (`__init__.py:371-396`): `unique_id == key and raw_config == config.raw_config` (Python dict equality). | `reloadScripts` (`Service.lean:96-101`): `objectId` and `raw` (the compressed JSON text). | Text equality is stricter: `continue_on_error: true` → `1` is equal in Python and a change for HALean (case `h84`, SCR-16; README line 515 says configs are compared "as sent"). `5` → `5.0` is the same text after HALean's JSON parser (case `h20` agrees). |
| Removal (`__init__.py:404-410`): `async_remove()` of every unmatched entity, gathered; `async_will_remove_from_hass` (`:773-781`) removes the service, then `async_unload` stops the runs. Only after all removals are the new entities created and added (`:412-416`). | `reloadScripts` (`Service.lean:103-119`): each unmatched script's runs are stopped and it is marked dead; then `addScripts`; then `resumeWoken` (`Service.lean:173`). | The whole reload is one atomic step in HALean. In HA a script that waited for a stopped run goes on while the reload is still awaiting: a call of the changed script at that moment is `ServiceNotFound` (case `h21`, SCR-8). |
| `async_added_to_hass` (`:743-770`) restores `last_triggered` from the stored state; a removed entity leaves an `unavailable` state with `restored: true` (`helpers/entity_registry.py:476`). | `addScripts` (`Service.lean:68-80`), `unavailableAttributes` (`Entity.lean:60-63`). | No difference found (cases `h24`, `h57`, `h58`, `h60`, `h70`). At `init`, HALean restores from the `states` it is sent; the harness cannot give HA the same stored state (notes in `FINDINGS.md`). |
| A script calling `script.<gone>` after the reload: `ServiceNotFound` (`core.py`, `async_call`). | `planCall` returns `none` (`Entity.lean:214-216`), `localCall?` gives up and the engine sends the call to HA (`Engine.lean:626-630`). | By design (scripts HALean refused stay in HA). In the harness nobody answers the call (cases `h18`, `h19`, SCR-15). |

## 7. `helpers/script_variables.py::ScriptVariables.async_render` → `renderVariables` (as used by `startScript`)

Upstream `script_variables.py:21-58`: run variables are kept, script variables whose key is already there
are skipped, the others are rendered in order. Lean `Engine.lean:831-835`. No difference found (shipped
`variables`, case `h37`; a caller-passed `this` replaces the entity's `this` on both sides). The run
variable `context` is opaque in HALean: any use is a render error (case `h77`, SCR-14, README line 492).

## 8. `Exe/Script.lean`, `HALean/Script/Protocol.lean`

`decodeInput` (`Protocol.lean:24-54`): `call` without `data` gives `{}`; `return_response` defaults to false.
An outside `call` of `script.reload` is "not found" in HALean (`Service.lean:157-160`); the shell is meant to
send `reload` instead. No difference found otherwise.

## 9. Engine functions driven by scripts: `startScript`, `callLocal`, `stopRun` (`HALean/Automation/Engine.lean`)

Covered in sections 3, 4 and 6. Summary of what the reading found and the cases confirmed:

* `callLocalH` (`Engine.lean:866-905`) runs every op of a handler in one go. HA's handlers await between
  entities (`toggle`) and inside a stop (`turn_off`, `restart`, reload). SCR-4, SCR-5, SCR-8.
* `stopRunH` (`Engine.lean:778-792`) removes the run and its `parallel` branches at once. HA's branch tasks
  that were scheduled before the stop still run their first steps (case `h81`, SCR-5).
* `stoppedQuietly` (`Engine.lean:550-553`) agrees with HA for delays, waits, `parallel`, nested sequences
  and queued runs (cases `h33`-`h36`, `h62`, `h63`), except SCR-6.
* Performance, not behaviour: a parallel script that calls itself three times recurses until `max` runs
  exist (`perf/perf6.yaml`, `perf/perf8.yaml`; both sides agree on the result). With `max: 8` halean-script
  alone needs 4.0 s for 9841 `script_started` events and 0.12 s for 1093 with `max: 6`; the harness test
  (HA, then halean-script) takes 13.5 s and 1.5 s (`logs/perf-recursion.log`). HALean's time grows faster
  than the number of events. With the default `max: 10` a random scenario kept halean-script busy for more
  than a minute; the generator now leaves such scripts out.
