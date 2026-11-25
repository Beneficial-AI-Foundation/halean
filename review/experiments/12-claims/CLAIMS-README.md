# Audit of the claims in `README.md` (commit f638a37)

Scope: the README text. Each claim has one verdict. `not checked` marks claims about things outside this machine (a web page, other projects); it is not one of the five requested verdicts and is used 3 times.

Abbreviations in the evidence column: `DV` = `logs/differential-verbose.log` (my verbose run of the shipped differential suite, 611 passed, 6 skipped); `02/` = `review/experiments/02-shipped-tests/logs/`; `01/` = `review/experiments/01-build-axioms/logs/`. "probe" = I ran the built executable or real HA myself; "case" = a shipped test case, by name, that is PASSED in `DV` (the two shipped runs in `02/run1-differential.log` and `02/run2-differential.log` have the same totals but no case names). Paths without a directory prefix are relative to `review/experiments/12-claims/` (`logs/`, `probes/`) or to the repository root.

Lines 115-116 and the mutation counts in lines 410-413 are out of scope (checked by other reviewers).

## Counts

| Verdict | Claims |
|---|---|
| correct | 238 |
| correct for the wrong reason | 0 |
| overstated | 8 |
| false | 2 |
| stale | 2 |
| not checked | 3 |
| total | 253 |

Individual features checked by a probe of my own (one row of a probe log each): 39 templates (`logs/probe-templates.jsonl`), 42 automation configs (`logs/probe-automation-load.log`), 13 script configs (`logs/probe-script-load.log`), 29 probe groups on the core and helper executables (`logs/core-probes.log`), 2 new scenarios (16 automations) through real HA and the engine, two runs each (`logs/harness-own-scenarios-run1.log`, `run2`), 2 direct HA probes (`logs/probe-ha-misc.log`).

## All claims

| ID | README line | claim (short quote) | verdict | evidence |
|---|---|---|---|---|
| R-1 | 3 | rewritten in Lean 4 one service at a time and translated function by function | correct | manifest.yaml: 402 entries, each maps one upstream node to Lean names; logs/manifest-counts.log |
| R-2 | 8 | table: `HALean/Automation/`, `halean-automation` | correct | directory exists; lakefile.toml `halean-automation` root `Exe.Automation`; binary in .lake/build/bin; logs/names-check.log |
| R-3 | 8 | Automation engine: done, tested against real HA | correct | DV: test_scenario 52 passed, test_scenario_mqtt 2, test_scenario_webhook 1; 5 opt out (see R for line 107). "done" = the subset of lines 229-235 |
| R-4 | 9 | table: `HALean/Template/`, `halean-template` (test driver); subset done, used by automations, tested against real HA | correct | Exe/Template.lean; HALean/Automation/Engine.lean imports the template evaluator; DV: test_template 361 passed |
| R-5 | 10 | table: `HALean/Script/`, `halean-script`; subset done, tested against real HA | correct | DV: test_script_scenario 10 passed, 1 skipped (unsupported) |
| R-6 | 10 | scripts: runs with the bridge (`--scripts`) | correct | bridge/bridge.py:333,340; 02/run1-bridge_e2e.log `PASS bridge end-to-end with scripts` |
| R-7 | 11 | table: `HALean/Helpers/`, `halean-helpers` (test driver); YAML helpers and their services done, tested against real HA | correct | DV: test_helpers 57 passed |
| R-8 | 11 | helpers: not yet connected to the engine | correct | no reference to `HALean.Helpers` in HALean/Automation, HALean/Script, Exe/Automation.lean, Exe/Script.lean, bridge/ (logs/structure-checks.log; the one grep hit is a section title in EngineBound.lean:201) |
| R-9 | 12 | table: `HALean/Core/StateMachine.lean`, `halean-core-states` (test driver); done, tested against real HA | correct | DV: test_states 20 passed |
| R-10 | 13 | table: `HALean/Core/EventBus.lean`, `halean-core-events` (test driver); subset done (callback listeners), tested against real HA | correct | DV: test_events 35 passed |
| R-11 | 14 | table: `HALean/Core/ServiceRegistry.lean`, `halean-core-services`; subset done, tested against real HA | correct | DV: test_services 32 passed |
| R-12 | 15 | table: `HALean/Core/Hass.lean`, `halean-core` (test driver); subset done (callback and `async def` listeners, ...), tested against real HA | correct | DV: test_core 38 passed |
| R-13 | 17 | `HALean/Core/` holds what every service shares (states, time, JSON) | correct | HALean/Core/State.lean, Types.lean, PyJson.lean |
| R-14 | 18-20 | The three core services also run joined (`HALean/Core/Hass.lean`) | correct | HALean/Core/Hass.lean:216-229 (`structure Hass`: states, bus, registry, tasks, ready) |
| R-15 | 20-22 | All services share one `manifest.yaml`, one pinned HA release, one bridge and one test setup | overstated | The bridge starts only `halean-automation` or `halean-script` (bridge/bridge.py:73-75, 340). The state machine, bus, registry, joined core and helpers cannot be reached through it. See Not correct |
| R-16 | 26-31 | latest release has `halean-demo.tar.gz`; `curl ... \| tar xz; cd halean-demo && docker compose up -d` | not checked | Needs the GitHub release page. Not fetched. release.yml:186-229 creates that asset on every release |
| R-17 | 34-36 | From a checkout, `cd demo && docker compose up -d` runs the same released image; `--build` builds it from the working tree | correct | demo/docker-compose.yml:25-26 (`build:` context `..`, image `halean:${HALEAN_VERSION:-latest}`). Read, not run |
| R-18 | 38-39 | open http://localhost:8124/halean-demo; the login is in `.run/login.txt` next to `docker-compose.yml` | correct | demo/docker-compose.yml:15 (port 8124), :32 (`./.run:/shared`); demo/setup.py:103-107 |
| R-19 | 39-41 | a separate Home Assistant (2026.10.4) with dummy devices: a motion sensor, two lights, a heater and a temperature sensor | correct | demo/docker-compose.yml:14; demo/ha/configuration.yaml:65-99 (template binary_sensor, sensor, 2 lights, switch Heater) |
| R-20 | 41 | HA has no automations of its own | correct | demo/ha/configuration.yaml has no `automation:` key; `default_config` loads the integration with an empty list |
| R-21 | 41-42 | All seven in `demo/automations.yaml` run in the Lean engine | correct | probe: 7 automations, 0 `unsupported` at load (logs/demo-automations-load.log) |
| R-22 | 42-45 | A simulator walks through the hallway and lets the room cool; "Lean engine" card and logbook card | correct | demo/simulator.py:62-101; demo/ha/ui-lovelace.yaml:22,68 |
| R-23 | 45-47 | the demo has its own containers, volume and port; `docker compose down`, `-v` | correct | demo/docker-compose.yml:10,15,48-49 |
| R-24 | 54-55 | `Engine.step : Engine → Input → Engine × List Cmd` is pure. It never reads a clock or does I/O | correct | HALean/Automation/Engine.lean:1809 (`def Engine.step (e : Engine) (i : Input) : Engine × List Cmd`, no IO in the type); the clock is the `now` field of each input (HALean/Automation/Protocol.lean) |
| R-25 | 56-57 | `bridge/bridge.py`: talks to a stock HA over its WebSocket API ... No fork is needed | correct | bridge/bridge.py:344-362 (auth, get_states, get_config, subscribe_events); 02/run1-live_docker.log runs it against the stock image |
| R-26 | 57 | the same way AppDaemon and Node-RED do | not checked | Statement about other projects. Not checked |
| R-27 | 58-59 | `manifest.yaml` + `tools/drift.py`: map each upstream Python function to the Lean definitions that translate it, with an AST hash | correct | tools/drift.py:89-102 (sha256 of `ast.dump` of the node, 16 hex digits); manifest.yaml entries have `python`, `lean`, `hash` |
| R-28 | 59-60 | After an upstream pull this shows exactly which translations need revisiting | overstated | The hash covers only the mapped def/class node. probe: changing `REPEAT_TERMINATE_ITERATIONS` in a copy of helpers/script.py leaves 363/363 identical (logs/drift-constant-probe.log). See Not correct |
| R-29 | 61 | `protocol/schema.json`: the versioned wire protocol | overstated | The version is the text `v1` in `$id` and `title` (protocol/schema.json:3-4). No message carries a version and no code reads the file. See Not correct |
| R-30 | 66-67 | `export ELAN_HOME=/Volumes/MacStorage/AppData/elan`; `export PATH=$ELAN_HOME/bin:$PATH` | false | A path on the author's macOS volume. `/Volumes` does not exist here (logs/small-checks.log). The build needs `$HOME/.elan/bin` instead (review/CONVENTIONS.md). See Not correct |
| R-31 | 68 | `lake build` # the HALean library: engine + all proofs | correct | lakefile.toml `defaultTargets = ["HALean"]`; 97 .lean files under HALean/, each has a built .olean (logs/structure-checks.log); 01/build-lib.log `Build completed successfully` |
| R-32 | 69-71 | `lake build halean-automation ... halean-helpers` # the executables the tests drive (nine names) | correct | The nine names equal the nine `[[lean_exe]]` in lakefile.toml; 01/build-exe.log exit=0 |
| R-33 | 72 | `uv run tests/run_scenarios.py` # behaviour scenarios (engine only) | correct | tests/run_scenarios.py:47-52 runs only the binary; 02/run1-scenarios.log `60/60 scenarios passed` |
| R-34 | 73 | `uv run tests/run_script_scenarios.py` # script scenarios (halean-script only) | correct | 02/run1-script_scenarios.log `11/11 script scenarios passed` |
| R-35 | 74 | `uv run tests/differential/run.py` # scenarios + template cases through a real Home Assistant vs Lean | correct | tests/differential/run.py:19 runs pytest on the directory. It also runs the states, services, events, core, helpers and scripts tests (DV: 611 passed, 6 skipped) |
| R-36 | 75 | `uv run tests/bridge_e2e.py` # bridge against a fake HA WebSocket server | correct | tests/bridge_e2e.py:6; 02/run1-bridge_e2e.log three PASS lines |
| R-37 | 76 | `uv run --with astral==2.2 tests/sun/compare.py` # sunrise/sunset vs astral, to the microsecond | correct | tests/sun/compare.py:26-52: 3000 random cases (seed 7), integer microseconds compared for equality; 02/run1-sun.log `3000/3000 match`. astral 2.2 is HA's own pin (package_constraints.txt:14) |
| R-38 | 77 | `uv run tests/live/docker_e2e.py` # bridge + engine driving the pinned HA release in a throwaway Docker container | correct | 02/run1-live_docker.log `Home Assistant 2026.10.4 in container halean-e2e`, `3/3 live checks passed` |
| R-39 | 82-83 | starts `ghcr.io/home-assistant/home-assistant:<tag>`, `<tag>` the release pinned in `manifest.yaml`, container `halean-e2e` | correct | tests/live/docker_e2e.py:37,70-75 |
| R-40 | 84-86 | port 18123, own config in `tests/live/.run/`, removed afterwards (`--keep` leaves it running) | correct | tests/live/docker_e2e.py:36-37,214,234 |
| R-41 | 86-87 | onboards a test user (random password, never printed), runs the real bridge and engine with three automations | correct | tests/live/docker_e2e.py:117 (`secrets.token_urlsafe(24)`), :54-67 (three automations) |
| R-42 | 90 | 1. a state trigger turns another `input_boolean` on and fires an event | correct | tests/live/docker_e2e.py:186-190; 02/run1-live_docker.log line 3 |
| R-43 | 91 | 2. `continue_on_error` carries on past a call to a service that doesn't exist | correct | tests/live/docker_e2e.py:62-63,192-195; 02/run1-live_docker.log line 4 |
| R-44 | 92 | 3. a `for: 2s` trigger fires after 2 s and not before | overstated | The test asserts only that the target is still off about 1 s after the trigger (docker_e2e.py:198-200) and on within 5 more seconds (:201). Its own message says `(not before 1s)`. See Not correct |
| R-45 | 96-98 | `tests/differential/` replays every scenario in `tests/scenarios/` through a real Home Assistant, in-process via `pytest-homeassistant-custom-component`, at 2026.10.4 | correct | test_differential.py:42,126-143; logs/ha-direct.log line 1 (HA 2026.10.4). 55 of 60 scenario files run; 5 opt out (line 107) |
| R-46 | 99-101 | the two must produce identical `automation_triggered` (which automations fired, in order) | correct | test_differential.py:92-93,191-192 (compared by `name`), :267-271 |
| R-47 | 102-103 | identical service calls (domain, service, target and data, in order; each call blocks until the scenario reports its result) | correct | test_differential.py:94-96 (`{**target, **data}`), :178-182 (handler awaits a future), :247-257 |
| R-48 | 104 | identical events fired by `event:` actions (in order) | correct | test_differential.py:97-98,193-194 |
| R-49 | 106 | The clock is frozen and advanced one second at a time, like the bridge's ticks | correct | test_differential.py:209-220; bridge/bridge.py:295-298 |
| R-50 | 107 | A scenario can opt out with `differential: false` (e.g. `unsupported.yaml`) | correct | test_differential.py:166-168. Five scenarios do: unsupported, mqtt_unsupported, webhook_unsupported, templated_for_zero, trigger_variables_error (DV, SKIPPED lines) |
| R-51 | 109-113 | The three streams are compared separately because HA queues an event fired while another event is being dispatched | correct | test_differential.py:76-86 (`_streams`); upstream core.py:1615 (queue while dispatching) |
| R-52 | 118-121 | Every case in `tests/templates/*.yaml` is rendered by HA's `Template.async_render` (or `condition.async_template`) and by `halean-template`; type and `repr()` must match, or both must raise | correct | test_templates.py:31-33,93-101,116-120; 361 cases in 3 files (logs/manifest-counts.log), 361 passed (DV). A third mode exists: `expect_error_in_halean_only` (test_templates.py:112-115), described at README 250-252 |
| R-53 | 121-122 | Cases marked `unsupported: true` must be rejected by HALean at load time | correct | test_templates.py:88-91 |
| R-54 | 122-124 | cases marked `render_info: true` must also read the same entities and domains (`async_render_to_info`) | correct | test_templates.py:103-110 |
| R-55 | 126-127 | The translation, the differential harness and the Docker image all use the release tag recorded in `manifest.yaml` (`upstream.tag`) | correct | manifest.yaml:4 `tag: 2026.10.4`; harness: run.py:4 pins `pytest-homeassistant-custom-component==0.13.375`, which ships HA 2026.10.4 (logs/ha-direct.log); live test reads the manifest (docker_e2e.py:72). The demo compose file hard-codes `2026.10.4` (docker-compose.yml:14) and no test checks it |
| R-56 | 127-128 | so every test exercises exactly the code that was translated | overstated | True for the tests that run HA. tests/sun/compare.py compares with its own re-implementation of `get_observer_astral_event_next` (compare.py:12-23), not with HA code. See Not correct |
| R-57 | 129 | `test_harness_matches_pin` fails if the harness and the pin ever diverge | correct | test_differential.py:275-283 (`manifest upstream.tag == homeassistant.const.__version__`); DV: PASSED |
| R-58 | 129-131 | `manifest.yaml` pins Jinja2 (`upstream.jinja2`, 3.1.6), and the same test checks it | correct | manifest.yaml:5; test_differential.py:284-289 |
| R-59 | 132-133 | `pytest-homeassistant-custom-component` is published only for releases | not checked | Statement about PyPI. Not checked |
| R-60 | 138-148 | sparse checkout "of the relevant files": the `git sparse-checkout set` command | stale | 18 manifest entries are in files the command does not check out: components/mqtt/ (10), components/webhook/ (4), components/tag/trigger.py (1), exceptions.py (3). probe: logs/sparse-check.log. It was complete at 5761000 (logs/sparse-history.log). See Not correct |
| R-61 | 160 | `uv run tools/drift.py check` # lists STALE / MISSING translations, exit 1 if any | correct | tools/drift.py:127-147; probe on the reviewed tree: `402 entries, 0 stale, 0 missing`, exit 0 (logs/drift-check.log) |
| R-62 | 162 | `uv run tools/drift.py update --only 'helpers/script.py::Script.async_run'` | correct | tools/drift.py:150-158; the entry exists (manifest.yaml:182) |
| R-63 | 163 | bump the harness pin in `tests/differential/run.py` | correct | tests/differential/run.py:4. tools/drift.py:4 has a second pin (`probatio==0.13.0`) that the text does not mention |
| R-64 | 164 | `uv run tools/drift.py update` # re-hash everything and record the commit and tag | correct | tools/drift.py:159-166 |
| R-65 | 165 | `uv run tools/drift.py coverage` # upstream functions in tracked files not mapped yet | correct | tools/drift.py:169-191 (module-level functions and methods of module-level classes) |
| R-66 | 168-170 | `uv run tools/drift.py compare --against <dir>/homeassistant` compares the mapped functions with any other copy | correct | tools/drift.py:194-205; used in logs/sparse-check.log and logs/drift-constant-probe.log. It skips the 39 `probatio:` entries |
| R-67 | tools/drift.py (58-60, 320) | (drift.py docstring, relied on by README 58-60) the hash ignores docstrings, comments, formatting and line numbers | correct | probe on a copy of util/location.py: comment added, docstring changed, blank lines added give the same hash; a code change gives another (logs/drift-hash-probe.log) |
| R-68 | 175-178 | `HA_URL`, `HA_TOKEN`, `--dry-run` (log calls, change nothing), `--status-entity` | correct | bridge/bridge.py:332-335,344-346,177,190,210,234 |
| R-69 | 181-182 | Automations outside the supported subset are reported as `unsupported` and stay in HA | correct | probe: 30 of 30 out-of-subset automations get an `unsupported` command with a reason (logs/probe-automation-load.log); bridge/bridge.py:206 logs it |
| R-70 | 185-186 | `--scripts /path/to/scripts.yaml` runs scripts in the same engine (`halean-script`) | correct | bridge/bridge.py:75,340,360; 02/run1-bridge_e2e.log |
| R-71 | 186-188 | Their states are written to HA over its REST API (`HA_REST_URL`, by default `HA_URL`'s host) | correct | bridge/bridge.py:219-226 |
| R-72 | 188-190 | HA itself cannot call them; scripts outside the subset are reported as `unsupported` | correct | probe: 9 of 9 out-of-subset scripts rejected at load (logs/probe-script-load.log). The websocket_api command list of the installed HA has no command that registers a service (logs/small-checks.log) |
| R-73 | 194-195 | Every push to `master` is released by CI (`.github/workflows/release.yml`) once it passes | correct | .github/workflows/release.yml:17-21,31-33. "passes" = Lean library build, demo smoke test, engine and script scenario suites. No CI job runs the differential tests against real HA; the README does not say one does |
| R-74 | 195-196 | Pushes that only touch Markdown are skipped | correct | release.yml:20 `paths-ignore: ["**.md", ".claude/**"]` |
| R-75 | 198 | 1. test: the Lean build (engine + all proofs) | correct | release.yml:47-51 (`leanprover/lean-action@v1`, default target = the library) |
| R-76 | 199-200 | 2. image: linux/amd64 and linux/arm64, each on a native runner, pushed by digest only | correct | release.yml:59-63,83 |
| R-77 | 201-203 | 3. smoke-test: `demo/make-bundle.sh` builds the bundle and `demo/smoke-test.sh` runs it ... until the engine triggers an automation | correct | release.yml:120-128; demo/smoke-test.sh:27-34 (waits for `INFO triggered ` in the logs, then checks the dashboard returns 200) |
| R-78 | 204-208 | 4. binaries (`binaries.yml`, in parallel with 2-3): `halean-automation` and `halean-script` for Windows x64, macOS Apple Silicon, Linux x86_64/arm64, each tested with the scenario suites, packaged with the bridge as `halean-<version>-<platform>.{zip,tar.gz}` | correct | release.yml:99-103; binaries.yml:29-33,44,50-53,60-85 |
| R-79 | 209-212 | 5. publish: tags `:<version>`, `:<major>.<minor>`, `:latest`; GitHub release `v<version>` with `halean-demo.tar.gz`, the archives and `SHA256SUMS` | correct | release.yml:159-164,170-229 |
| R-80 | 214-215 | These builds run only after a merge to master; pull requests run just the Lean build (`lean_action_ci.yml`) | correct | release.yml:17-19,32; lean_action_ci.yml:3-6,16-19. Both release.yml and binaries.yml can also be started by hand (`workflow_dispatch`). lean_action_ci.yml builds 8 of the 9 executables: `halean-helpers` is missing from its `build-args`, so no CI job builds it |
| R-81 | 217-218 | The version is `<major>.<minor>` from `lakefile.toml` plus the workflow run number (`0.1.42`) | correct | release.yml:40-44; lakefile.toml `version = "0.1.0"` |
| R-82 | 222-225 | local check: `docker build -f demo/Dockerfile ...`; `demo/make-bundle.sh 0.1.0-local dist && demo/smoke-test.sh dist/halean-demo.tar.gz` | correct | Files and argument order match (demo/make-bundle.sh:9-10, demo/smoke-test.sh:9). Read, not run |
| R-83 | 231 | Triggers, Supported: `state` (from/to/not_from/not_to, attribute, `for`, explicit null `to`) | correct | probe: new scenario `supported_sample` (not_from, not_to) passes on HA and engine, 2 runs (logs/harness-own-scenarios-run1.log, run2). No shipped scenario uses `not_from` (logs/small-checks.log). Cases: state_null_to_and_attribute, state_from_for |
| R-84 | 231 | Triggers, Supported: `numeric_state` (below/above, entity bounds, attribute, `value_template`, `for`, arming) | correct | probe: `supported_sample` automation `num_entity_bound` (entity bound, attribute, arming); cases numeric_arming, numeric_for, numeric_value_template |
| R-85 | 231 | Triggers, Supported: `template` (arming, `for`, re-rendered like HA's template tracker ...) | correct | cases template_trigger, template_tracking (row lists 5 features; checked by case name only) |
| R-86 | 231 | Triggers, Supported: `time` (fixed or templated `at`, `input_datetime`, sensors, `offset`, weekday), `time_pattern` | correct | cases time_entities, time_templated, time_values, time_pattern; probe: `time_pattern` and `numeric_state` with `for` load (logs/probe-automation-load.log) |
| R-87 | 231 | Triggers, Supported: `homeassistant` with `event: start`, `tag` | correct | case ha_start_and_tag; probe: `ha_start`, `tag_trigger` load |
| R-88 | 231 | Triggers, Supported: `event` (templated type and data, nested `event_data`, Python `==`) | correct | cases event_trigger_data, trigger_variables_templates; probe: `event_data_nested_dict` loads |
| R-89 | 231 | Triggers, Supported: legacy `zone`, legacy `sun` (sunrise/sunset with `offset`) | correct | cases zone_trigger, sun_trigger; probe: `zone_legacy` loads; 02/run1-sun.log 3000/3000 |
| R-90 | 231 | Triggers, Supported: `mqtt` (row lists 12 features) | correct | cases test_scenario_mqtt[mqtt_trigger], [mqtt_edges] (2 of 12 features checked by keyword: `payload_json`, `qos`) |
| R-91 | 231 | Triggers, Supported: `webhook` (`allowed_methods`, `local_only`, `trigger.json`/`data`/`query`), fed by the protocol's `webhook` input, which the bridge cannot send | correct | case test_scenario_webhook[webhook_trigger]; bridge/bridge.py:365-370 (warns only) |
| R-92 | 231 | Triggers, Supported: `for:` static or templated | correct | cases templated_for, state_for_cancel |
| R-93 | 231 | Triggers, Rejected: `this` in trigger templates | correct | probe `this_in_trigger_template`: unsupported (logs/probe-automation-load.log) |
| R-94 | 231 | Triggers, Rejected: other sun events (dawn, dusk, noon, elevation, ...) | correct | probe `sun_dawn`, noon: `sun trigger event must be sunrise or sunset` |
| R-95 | 231 | Triggers, Rejected: `zone.entered`/`zone.left` and other new-style triggers | correct | probe `zone_entered_new_style`: unsupported |
| R-96 | 231 | Triggers, Rejected: `homeassistant` with `event: shutdown` | correct | probe `ha_shutdown`: unsupported |
| R-97 | 231 | Triggers, Rejected: device triggers | correct | probe `device_trigger`: unsupported |
| R-98 | 231 | Triggers, Rejected: a `webhook` trigger whose id is templated in a `wait_for_trigger` or reads states or the clock | correct | probe `webhook_templated_in_wait`, `webhook_id_reads_states`: unsupported |
| R-99 | 231 | Triggers, Rejected: an `mqtt` trigger with another `encoding`, a `b'...'` payload, or a templated topic in a `wait_for_trigger` | correct | probe `mqtt_encoding_other`, `mqtt_encoding_empty`, `mqtt_payload_bytes_literal`, `mqtt_topic_templated_in_wait`: unsupported |
| R-100 | 231 | Triggers, Rejected: a templated `time` `at` that reads states | correct | probe `time_at_reads_states`: unsupported |
| R-101 | 231 | Triggers, Rejected: an event trigger's `context`; a list inside nested `event_data` | correct | probe `event_context`, `event_data_nested_list`: unsupported |
| R-102 | 232 | Conditions, Supported: `and`/`or`/`not`, `state` (`for`, attribute, `input_*`), `numeric_state`, `time`, `trigger`, `template`, `zone`, `sun`, `enabled` | correct | cases state_condition_for, state_condition_for_template, time_condition, time_condition_sensors, trigger_id, zone_condition, sun_condition, sun_condition_edges, sun_condition_polar, enabled_forms; probe `kept_behaviours` (and/or/not) passes on HA and engine (row lists 9 condition kinds; 9 checked by case name, 3 by probe) |
| R-103 | 232 | Conditions: `for` with an attribute or an `input_*` state is refused, as HA's schema does | correct | probe `state_condition_for_with_attribute`, `state_condition_for_with_input_state`: unsupported with HA's messages |
| R-104 | 232 | Conditions, Rejected: platform conditions | correct | probe `platform_condition_device`, `platform_condition_new_style`: unsupported |
| R-105 | 233 | Automations, Supported: `variables`, `trigger_variables`, a trigger's own `variables`, `this`, names default to `automation <n>` | correct | cases variables, trigger_variables_templates, this; probe output shows `"name": "automation 0"` (logs/engine-kept_behaviours.log) and HA agrees (harness compares by name) |
| R-106 | 233 | Automations, Rejected: `this` when the entity id needs transliteration or HTML entities | correct | probe `this_non_ascii_alias`, `this_html_entity_alias`: unsupported |
| R-107 | 233 | Automations, Rejected: `trigger_variables` that use `this`, states or the clock | correct | probe `trigger_variables_use_this`, `_use_states`, `_use_now`: unsupported |
| R-108 | 233 | Automations, Rejected: `variables` on a `wait_for_trigger`'s triggers | correct | probe `variables_on_wait_trigger`: unsupported |
| R-109 | 234 | Actions, Supported: service call (templated names, templates in `data` and `target`, `response_variable`), `stop`, `delay`, `condition`, `choose`, `if`/`else`, `repeat`, `variables`, `event`, `sequence` | correct | probe: `supported_sample` automation `actions` (templated name, if/else, choose default, repeat until, sequence, stop + error) passes on HA and engine; cases service_call_forms, response_variable, delay, delay_template, repeat, event_data_template |
| R-110 | 234 | Actions, Supported: `wait_template`, `wait_for_trigger`, `parallel`, `continue_on_error`, `enabled` | correct | cases wait_template, wait_template_edges, wait_for_trigger, parallel, parallel_order, continue_on_error, enabled_forms |
| R-111 | 234 | Actions, Rejected: device actions, `scene` | correct | probe `device_action`, `scene_action`: unsupported |
| R-112 | 235 | Run modes, Supported: `single`, `restart`, `queued` (FIFO), `parallel`, `max`, conditions checked before admission | correct | cases mode_single, mode_restart, mode_queued, mode_parallel_max, queued_max; probe `supported_sample` automation `modes` (restart) |
| R-113 | 235 | Run modes, Rejected at load: `max_exceeded` log levels | false | probe: automations with `max_exceeded: warning`, `silent`, `error` all load (logs/probe-automation-load.log). `max_exceeded` is not read anywhere in HALean/Automation. See Not correct |
| R-114 | 239-240 | `{{ 0.1 + 0.2 }}` prints `0.30000000000000004` | correct | probe T1: HA and HALean both `0.30000000000000004` (logs/probe-templates.jsonl) |
| R-115 | 240 | `round(2.675, 2)` is `2.67` | correct | probe T2b: `{{ 2.675 \| round(2) }}` is 2.67 on both. As a template global, `round(...)` is undefined in HA and rejected at load by HALean (probe T2); the claim holds for the filter and for Python's `round` (logs/ha-direct.log) |
| R-116 | 240 | `1 == 1.0 == True` | correct | probe T3: `True` on both |
| R-117 | 240-242 | `_parse_result`: `"42"` becomes `42`, `"[1, 2]"` becomes a list, `"007"` stays a string | correct | probes T4, T5, T6 |
| R-118 | 246 | Templates, Supported: `{% for %}` with `if`, `else`, `loop.*`, `break`/`continue`; `{% set %}` incl. tuples; `namespace()`; comments; `-` whitespace control | correct | probes T7, T8, T9 |
| R-119 | 246 | Templates, Supported: chained comparisons, `x if c else y`, slices | correct | probe T10 |
| R-120 | 246 | Templates, Supported: iterating `states` / `states.light` (in HA's insertion order) | correct | probes T11 (`['light.b', 'light.a']` on both), T11b |
| R-121 | 246 | Templates, Supported: `is_state`, `state_attr`, `is_state_attr`, `has_value`, `float`, `int`, `bool`, `is_number`, `iif`, `dict` | correct | probes T12, T13 |
| R-122 | 246 | Templates, Supported: filters `round` ... `reverse` (row lists 27 filters) | correct | probes T2b, T14, T36 (9 of 27 checked: round, sort, unique, min, selectattr, reject, sum, reverse, join); cases in tests/templates/cases.yaml and collections.yaml |
| R-123 | 246 | Templates, Supported: `sort` (`reverse`, `case_sensitive`), `min`/`max` filters and globals, `unique`, `expand` (groups) | correct | probes T14, T32 |
| R-124 | 246 | Templates, Supported: dates and times (row lists about 25 features) | correct | probes T15, T16, T35 (11 of 25 checked: now, utcnow, today_at, timedelta, isoformat, strptime, as_timestamp, timestamp_custom, relative_time, as_timedelta, the `datetime` test); cases in tests/templates/datetime2.yaml |
| R-125 | 246 | Templates, Supported: str methods `split`, `strip`, `replace`, `startswith` | correct | probe T17 |
| R-126 | 246 | Templates, Rejected at load: any other global, filter or test | correct | probes T21 (`regex_replace`), T22 (`distance`), T23 (`match` test): `unsupported` |
| R-127 | 246 | Templates, Rejected at load: macros, `include`, `raw` | correct | probes T18, T19, T20: `unsupported` |
| R-128 | 248-251 | `last_reported`, `tzinfo`, `strftime('%Z')`, `strptime`'s `%c` are render errors in HALean, never a silent wrong answer | correct | probes T24, T25, T26, T27: HA renders, HALean returns an error (4 of the 8 listed items checked) |
| R-129 | 250-251 | Printing a generator (`{{ xs \| map('int') }}`) is an error here, where HA prints `<generator object ...>` | correct | probe T28 |
| R-130 | 252-255 | Case-changing filters on non-ASCII text are errors; so are case-insensitive `sort` over non-ASCII strings and NaN sort keys | correct | probes T29, T29b, T30, T31 |
| R-131 | 257-258 | Upstream behaviours the translation keeps exactly, each covered by a scenario in `tests/scenarios/` | overstated | Of the five bullets, one has no scenario (`repeat` limit) and two are covered in part. The behaviours themselves hold in my probes. See Not correct |
| R-132 | 260-261 | A failing `condition` step ends only the sub-script it's in. Inside `choose`/`if`/`repeat`/`sequence`, the outer sequence carries on | correct | choose: case nested_condition. if, repeat, sequence: probe scenario `kept_behaviours` passes on HA and engine, 2 runs (logs/harness-own-scenarios-run1.log, run2; engine output in logs/engine-kept_behaviours.log) |
| R-133 | 262-265 | `continue_on_error` swallows only `HomeAssistantError`; config errors always stop the run; other exceptions are converted only by the failing step's own flag | correct | cases continue_on_error (ids own_coe, no_coe, invalid, enclosing, other_enclosing), wait_template_edges (first_error_coe) |
| R-134 | 266-267 | Conditions return true, false, `None` (disabled) or an error. `and`/`or` skip `None`, `not` treats it as false, `if`/`while` treat an error as false | correct | probe `kept_behaviours` (and_skips_disabled, or_skips_disabled, not_disabled_is_true, while_error_is_false) passes on HA and engine; case condition_errors (if_err) |
| R-135 | 268-269 | A queued run counts toward `max` while it waits, and `automation_triggered` fires on admission, before the run starts | correct | case queued_max (step at=2 expects `automation_triggered` while call 0 is blocked; step at=3 expects nothing) |
| R-136 | 270 | `repeat` aborts after 10,000 iterations | correct | probe: engine fires `loop` x10000 then logs `looped 10000 times`, no `after_limit` (logs/engine-repeat_limit.log); real HA fires `loop` x10000, `after_limit` x0 (logs/probe-ha-misc.log). HALean/Automation/Script.lean:182; upstream helpers/script.py:333 |
| R-137 | 274-275 | `asyncSet : StateMachine → ... → (now : Int) → Except SMError (StateMachine × List SMEvent)` | correct | HALean/Core/StateMachine.lean:231-233 (the last argument is named `timestamp`) |
| R-138 | 276-277 | a context the caller does not pass is a fresh symbolic ULID (`ulid:0`, `ulid:1`, ... in order) | correct | HALean/Core/StateMachine.lean:97-100; probe S1 output (logs/core-probes.log) |
| R-139 | 278-284 | `test_states.py` applies every operation sequence in `tests/core/states/*.yaml` to HA's `hass.states` and to `halean-core-states`, compares results and events with their Python types; ULIDs renamed in order and must encode the operation's clock | correct | test_states.py:82,85-92,97-109,213; 20 cases, 20 passed (DV) |
| R-140 | 288 | States, Supported: equal attributes keep the old object (`{a: 1}` stays when `{a: 1.0}` is set); the report rule | correct | probe S1: second set fires only `state_reported`, attributes stay `{a: 1}`; cases attribute_equality_is_pythons, same_state_and_attributes_only_reports |
| R-141 | 288 | States, Supported: `async_set_internal` (over-long state → `unknown`); `validate_state` | correct | probe S2; case set_internal_long_state_becomes_unknown, state_length_limit |
| R-142 | 288 | States, Supported: lower-cased id, `get` with the lower-case retry, a `str` filter lower-cased, an iterable not | correct | probe S6; cases upper_case_id_is_lowered, domain_index_order |
| R-143 | 288 | States, Supported: `valid_entity_id` incl. the trailing newline `$` allows; `async_remove`; `async_reserve` / `async_available` | correct | cases valid_entity_id_edges, remove_and_get, reservations (row lists about 20 features; 9 checked) |
| R-144 | 288 | States, Rejected: non-ASCII entity ids and domain filters | correct | probe S3: `unsupported`; case non_ascii_rejected |
| R-145 | 290-291 | Known gap: timestamps are whole microseconds (`timestamp = us / 1e6`, which the harness passes explicitly) | correct | test_states.py:139 (`timestamp=ts`) |
| R-146 | 291-293 | HA's `as_dict()` is cached and keeps a stale `last_reported` after a report (`test_as_dict_cache_is_stale_after_report` pins the upstream behaviour) | correct | test_states.py:216-226 (HA only); DV: PASSED |
| R-147 | 294 | attribute dicts print with sorted keys | correct | probe S4: `{"b": 1, "a": 2}` comes back as `{"a": 2, "b": 1}` |
| R-148 | 294-295 | a JSON float written without a fraction or exponent sign (`1e16`) reads as an int | overstated | The gap is wider. `1.0e16`, `1e+16`, `1.5e3` and `1.5e+16` also read as ints (logs/float-probe.log). `1e+16` is what Python's `json.dumps(1e16)` writes. See Not correct |
| R-149 | 299-302 | `halean-core-services` takes one operation per JSON line (`register`, `remove`, `has`, `supports_response`, `list`, `list_domain`, `call`, each with an explicit `now`) | correct | Exe/CoreServices.lean:1-25; probes V1-V7 (logs/core-probes.log) |
| R-150 | 303-305 | Handlers are specs (return a value, echo the `ServiceCall`, raise an exception); schemas are built from a spec | correct | Exe/CoreServices.lean:15-19; tests/differential/schema_spec.py |
| R-151 | 306-308 | Exceptions carry the same `error_kind` as the automation protocol's `service_result`: `invalid`, `ha_error`, `other` | correct | probes V1 (`invalid`), V7 (`ha_error`), V4 (`other`); protocol/schema.json:90 |
| R-152 | 310-316 | `test_services.py` compares result (`repr()`), exception (class, `str()`, `error_kind`, translation key and placeholders), events and warnings/errors logged; random context ids compared structurally (`new`) | correct | test_services.py:59,76-90,133,194; 32 cases, 32 passed (DV) |
| R-153 | 317-319 | probatio's version is pinned too (`upstream.probatio`, 0.13.0, checked by `test_probatio_matches_pin`) | correct | manifest.yaml:6; test_services.py:161-166; DV: PASSED |
| R-154 | 319-321 | its translated functions are in `manifest.yaml` as `probatio:<file>::<name>`, hashed by `tools/drift.py` against the same pinned version | correct | 39 `probatio:` entries (logs/manifest-counts.log); tools/drift.py:4 (`probatio==0.13.0` in the uv script header, a second hard-coded pin; no test ties it to the manifest), :81-93 |
| R-155 | 323-326 | A spec is turned into a real `probatio.Schema` by `schema_spec.py`, with the real `config_validation` objects for `cv.*` | correct | tests/differential/schema_spec.py:14-32 |
| R-156 | 327-330 | `validators.yaml` exercises every validator on accepted, coerced and rejected input, including paths such as `light.color.g`, `rows[2].z`, `['odd key']['x.y']`, `<group>` | correct | Every validator and `cv.*` name of the Supported cell occurs in tests/core/services/*.yaml (keyword counts in logs/small-checks.log); 17 cases in validators.yaml passed (DV) |
| R-157 | 335 | Schemas, Supported: `Coerce(int)` ... incl. the 4300-digit limit | correct | probe V1: 4300 digits accepted, 4301 `expected int at 'a'`; HA the same (logs/ha-direct.log) |
| R-158 | 335 | Schemas, Supported: `In` / `NotIn` (the 40-member cap, "did you mean") | correct | probe V2: `..., 38, 39, ...] (5 more not shown)` and `did you mean 'apple'?`; HA prints the same two messages (logs/ha-direct.log); case val_in_not_in |
| R-159 | 335 | Schemas, Supported: keys, types, list schemas, `All`, `Any`, `Range`, `Clamp`, `Length`, `Lower`, `Upper`, `EnsureList`, `Port`, `AtLeastOne`, 20 `cv.*` validators | correct | cases val_types_literals_any, val_nested_and_sequences, val_all_any_errors, val_range_clamp_length, val_lower_upper_ensure_list_port, val_cv_* (6 cases), val_exclusive_inclusive (row lists about 45 features; 2 checked by probe, the rest by case name) |
| R-160 | 335 | Schemas, Rejected: `msg=` on any validator; `Match`/`cv.matches_regex`; `Coerce` of other types | correct | probe V3: `unsupported` for each |
| R-161 | 335 | Schemas, Rejected: `cv.percentage` (not in HA's `cv`), `cv.time`, `cv.date`, `cv.template`, `cv.url` | correct | probe V3: `unsupported` for each; `hasattr(cv, 'percentage')` is False (logs/ha-direct.log) |
| R-162 | 335 | Schemas, Rejected: `cv.icon` | stale | probe V3: `{cv: icon}` is accepted and validates like HA's `cv.icon`. Added by commit eaee9a4 (2026-11-25); the README row was not updated. See Not correct |
| R-163 | 339 | Registry, Supported: names lowercased; `has_service`; `supports_response` (`KeyError`); `async_services_for_domain` does not lowercase | correct | probe V4; cases register_lowercases_and_fires_event, supports_response_missing |
| R-164 | 339 | Registry, Supported: `ServiceNotFound`, the `return_response` rules (`blocking` needed, `NONE` refuses it, `ONLY` requires it) | correct | probe V7 (four errors with HA's messages); case return_response_rules, call_not_found |
| R-165 | 339 | Registry, Rejected: non-ASCII domain or service names; handler exceptions other than the five listed; non-dict `data`/`target` | correct | probe V5: `unsupported` for each; case unsupported_inputs |
| R-166 | 341-346 | handlers that set states, fire events or call services run in the joined core, where `async_call` is the same `Registry.prepareCall` / `finishCall` | correct | `prepareCall`, `finishCall` in HALean/Core/ServiceRegistry.lean, used in HALean/Core/Hass.lean (logs/names-check.log) |
| R-167 | 349-350 | Known gap: `NaN`/`Infinity` in the input JSON | correct | probe V6: `invalid JSON: unexpected character N` |
| R-168 | 354-364 | `Hass` holds the state machine, the bus and the registry; listeners and handlers are scripts (`Action`) | correct | HALean/Core/Hass.lean:216-229; `Action` defined there (logs/names-check.log) |
| R-169 | 373-376 | `Res.susp`, `Hass.tasks`, `Hass.ready` | correct | HALean/Core/Hass.lean:178 (`susp`), :227 (`tasks`), :229 (`ready`) |
| R-170 | 390-391 | The scheduler's theorems are in `HALean/Core/HassSchedProofs.lean` | correct | file exists; `runHandle_fifo` :338, `resume_main_fifo` :348 (existence only) |
| R-171 | 393-400 | `halean-core` takes one operation per JSON line (15 operation names), answers with the result and one ordered trace | correct | Exe/Core.lean:1-50 lists the same 15 (plus `init`); probes C1-C4 |
| R-172 | 400-409 | `test_core.py`: frozen clock, HA's loop exception handler from `homeassistant.runner`, `block_till_done` after each operation unless `manual`, `engine_only`, `ctx#<n>` | correct | test_core.py:63,121-129,400,413-441,460; 38 cases passed (DV) |
| R-173 | 411 | "all 15 async cases" (the number only; the mutation result is checked elsewhere) | correct | 15 cases in tests/core/hass use `sleep`: 7 in async_listeners.yaml, 6 in async_services.yaml, 2 in unsupported.yaml (logs/small-checks.log) |
| R-174 | 415-425 | one `Context` (`State.lean`); `ServiceContext` is gone; `SMEvent`, `FiredEvent`, `Queued` | correct | no `ServiceContext` in HALean (grep); names exist (logs/names-check.log) |
| R-175 | 429 | Core, Supported: the 10,000-events limit raises `HomeAssistantError` in the firing script, with upstream's message | correct | probe C3: 10001 deliveries, then `Error running job` with `Event x not fired: more than 10000 events ...` (logs/core-event-limit.log); cases endless_cascade_hits_queue_limit, endless_state_cascade_hits_queue_limit |
| R-176 | 429 | Core, Supported: (row lists about 25 behaviours of listeners, handlers, tasks and logs) | correct | cases in tests/core/hass (38 passed, DV); 1 of 25 checked by probe |
| R-177 | 429 | Core, Rejected: `await` in a `@callback`; `asyncio.sleep` with a delay; futures resolved twice | correct | probe C2: `a @callback cannot await`, `only asyncio.sleep(0) is modelled`, `a future resolved twice` |
| R-178 | 429 | Core, Rejected: a `block_till_done` that would never return (more than 100,000 handles per operation) | correct | probe C4: `unsupported: loop fuel`; HALean/Core/Hass.lean:247 (`LOOP_FUEL := 100000`); case async_never_returning_rejected |
| R-179 | 429 | Core, Rejected: `time_fired` on a scripted fire; event types over 64 characters | correct | probe C2: both `unsupported` |
| R-180 | 429 | Core, Rejected: service calls nested deeper than 32 | correct | probe C1: `unsupported: call depth`; HALean/Core/Hass.lean:241 (`MAX_CALL_DEPTH := 32`); case runaway_recursion_rejected |
| R-181 | 450-451 | `step : (now : Nat) → Bus → Op → Bus × Result` | correct | HALean/Core/EventBus.lean:522 |
| R-182 | 456-466 | `halean-core-events` operations; `test_events.py` starts the model from HA's listener table; contexts compared as `ulid@<ms>#<n>` | correct | Exe/CoreEvents.lean:1-25; test_events.py:88,183,211-229; 35 cases passed (DV) |
| R-183 | 470 | Bus, Supported: event type length in code points | correct | probe E1: 64 `x` ok, 65 `MaxLengthExceeded`, 64 `é` ok; case event_type_length |
| R-184 | 470 | Bus, Supported: `MATCH_ALL` never for `homeassistant_close`/`state_reported`, twice for an event of type `*` | correct | probe E2: two deliveries for `*`, none for the two excluded types; case fire_match_all_type |
| R-185 | 470 | Bus, Supported: `run_immediately` raises; `async_listen_once` with a filter is a `TypeError` | correct | probe E3; cases run_immediately_is_an_error, once_with_filter_is_a_type_error |
| R-186 | 470 | Bus, Supported: a double removal is logged and leaves an empty list behind | correct | probe E4: log `Unable to remove unknown job listener`, `["x", 0]` stays in `listeners`; case double_unsub |
| R-187 | 470 | Bus, Supported: queued events dispatched in FIFO order; the 10,000-events limit (row lists about 20 behaviours) | correct | cases queue_is_fifo, nested_fire_is_queued, added_during_dispatch, removed_during_dispatch, endless_loop_is_cut (7 of 20 checked) |
| R-188 | 470 | Bus, Rejected: non-object event data | correct | probe E3: `event data must be an object or null` |
| R-189 | 475-476 | `drain`'s bound is justified by the queue limit but not proved yet | correct | HALean/Core/EventBus.lean:468-476; theorems about `drain` (drain_onceInv, drain_quiet, drain_wf in EventBusProofs.lean) hold for any bound and none states that the bound empties the queue |
| R-190 | 479-488 | `halean-script`; `startScript`, `callLocal`, `stopRun` in `Engine.lean`; inputs `init`, `call`, `reload`; `protocol_scripts` in `bridge/protocol.py` | correct | names found in HALean/Automation/Engine.lean (logs/names-check.log); HALean/Script/Protocol.lean:28,46,50; bridge/protocol.py:49 |
| R-191 | 492 | Scripts, Supported: `alias`, `icon`, `description`, `fields`, `variables`, `mode`/`max`, `max_exceeded` (only logs); calling `script.<object_id>`; `script.turn_on` | correct | probe: script `fine` with all of these loads; `calls_fine` loads (logs/probe-script-load.log); cases call_response, turn_on_off, modes, variables, sub_scripts |
| R-192 | 492 | Scripts, Supported: recursion guard, errors of the called script, reload (row lists about 25 behaviours) | correct | cases restart_reentry, nested_errors, service_errors, reload (10 script scenarios passed, DV; 4 of 25 checked by probe) |
| R-193 | 492 | Scripts, Rejected: invalid configs, blueprints, `script.reload` actions | correct | probe `invalid_extra_key`, `blueprint`, `reload_action`: unsupported |
| R-194 | 492 | Scripts, Rejected: device/area/floor/label targets of `turn_on`/`turn_off`/`toggle` | correct | probe `device_target`, `area_target`: unsupported |
| R-195 | 492 | Scripts, Rejected: waits that mention script entities, the `trigger` condition, `last_action`, templates using names that are not the script's fields or variables | correct | probe `wait_on_script_entity`, `trigger_condition`, `last_action`, `undeclared_name`: unsupported; `action_defined_variable` loads, as the row says |
| R-196 | 494-497 | Every scenario in `tests/script_scenarios/` (except `unsupported.yaml`) also runs through HA's `script` integration | correct | DV: test_script_scenario 10 passed, [unsupported] SKIPPED; test_scripts.py:103-106 |
| R-197 | 500-505 | With `--scripts`, the bridge runs `halean-script` with both files; HA's WebSocket API cannot register services; states written over REST | correct | bridge/bridge.py:340,360,219-226; the installed HA's websocket_api/commands.py has no command that registers a service (logs/small-checks.log) |
| R-198 | 510-512 | Turning on a script that does not start: HALean fails the call instead, with a log | correct | probe: second `turn_on` of a running `single` script gives `call_done` with an error and the log `... which HALean does not model` (logs/probe-script-load.log) |
| R-199 | 520-535 | Helpers: files and names (`Common.lean`, `Component.lean`, `Helpers.setup`, `Helpers.call`, `Helpers.tick`, `HM`, `Pattern.lean`) | correct | logs/names-check.log |
| R-200 | 548 | `input_boolean`: restore (`on` when no `initial`); `reload` refused | correct | probe H7 (restored `on`; with `initial: false` it is `off`), H6 (`reload`: unsupported); case input_boolean_restore |
| R-201 | 549 | `input_number`: `set_value` (`probatio.Invalid` outside the range) | correct | probe H5: `Invalid`, `Invalid value for input_number.n: 11.0 (range 0.0 - 10.0)`; case input_number_services |
| R-202 | 550 | `input_select`: `options` (duplicates removed with a warning); `select_option` (`HomeAssistantError`); `set_options` (duplicates refused) | correct | probe H4; case input_select_services |
| R-203 | 551 | `input_text`: `set_value` (wrong length: a warning, nothing written; a value not matching the pattern ... raises `ValueError` and the state machine keeps the old state) | correct | probe H3; case input_text_patterns |
| R-204 | 551 | `input_text`, Refused: patterns outside the regex subset (lazy quantifiers, ...) | correct | probe H3: `a+?` unsupported; case input_text_unsupported_pattern |
| R-205 | 552 | `counter`: `step` (0 allowed); `set_value` (`ValueError` above/below the bounds or off-step, `ZeroDivisionError` for step 0) | correct | probe H1; case counter_step_zero |
| R-206 | 553 | `timer`: `-0:00:05` becomes minus 1 h 59 min 55 s, as upstream | correct | probe H2: duration attribute `-2:00:05`; real HA: `cv.time_period(_format_timedelta(cv.time_period('-0:00:05')))` = `timedelta(days=-1, seconds=79205)` = -7195 s (logs/ha-direct.log); case timer_zero_and_negative |
| R-207 | 553 | `timer`, Refused: restoring a paused or active timer | correct | probe H8: unsupported; case timer_restore_paused |
| R-208 | 555-562 | `test_helpers.py` runs every case of `tests/helpers/*.yaml` on a real HA (`async_setup_component`, `mock_restore_cache`, frozen clock) and compares config errors, call errors, events, warnings and states after each step | correct | test_helpers.py:112-205; 57 cases passed (DV) |
| R-209 | 566-567 | Not connected to the automation engine yet | correct | see row for line 11 |
| R-210 | 571-573 | Calls naming several entities: HALean runs them in the order given | correct | probe H7: toggles come out in the order of the `entity_id` list. The harness sorts both sides for such calls (test_helpers.py:152,196-198) |
| R-211 | 574 | Device, area, floor and label targets are refused | correct | probe H6: `device_id`, `area_id` unsupported; case input_boolean_device_target |
| R-212 | 575 | `input_datetime`, `group` and `schedule` are not translated yet | correct | probe H6: `input_datetime is not a modelled helper`; no such files in the manifest (logs/manifest-counts.log) |
| R-213 | 577-582 | `HALean/Automation/Proofs.lean`: 14 theorem names | correct | all 14 found in that file (logs/names-check.log) |
| R-214 | 584-595 | `StateSpec.lean`, `PyIntSpec.lean`, `ParseTimeSpec.lean`, `SyntaxSpec.lean`, `CvBooleanSpec.lean`, `SlugifySpec.lean`: 9 theorem names | correct | all 9 found in the named files (logs/names-check.log) |
| R-215 | 597-598 | `HALean/Template/Proofs.lean`: 5 theorem names | correct | all 5 found (logs/names-check.log) |
| R-216 | 600-605 | `HALean/Core/Proofs.lean`: 8 theorem names | correct | all 8 found (logs/names-check.log) |
| R-217 | 607-612 | `HALean/Core/ServiceRegistryProofs.lean`: 8 theorem names | correct | all 8 found (logs/names-check.log) |
| R-218 | 614-620 | `HALean/Core/ProbatioProofs.lean`: 10 theorem names | correct | all 10 found (logs/names-check.log) |
| R-219 | 622-629 | `HALean/Core/EventBusProofs.lean`: 7 theorem names | correct | all 7 found (logs/names-check.log) |
| R-220 | 630-638 | `HALean/Core/HassProofs.lean`: 4 theorem names | correct | all 4 found (logs/names-check.log) |
| R-221 | 639-641 | `HALean/Script/Proofs.lean`: 5 theorem names | correct | all 5 found (logs/names-check.log) |
| R-222 | 645-647 | All differential scenarios and all template cases match real HA at the pinned release | correct | DV and 02/run1-differential.log, 02/run2-differential.log: 611 passed, 6 skipped, 0 failed |
| R-223 | 648-650 | the codegen path probatio switches a schema to after 50 validations (`CompilePolicy.AUTO`) is not translated | correct | probatio/schema.py:142 `_AUTO_COMPILE_THRESHOLD = 50` (logs/ha-direct.log); manifest maps 5 functions of probatio `_compile.py` and 10 of `_engine.py`, none is the code generator (not examined further) |
| R-224 | 651-652 | `Validator.run` is `partial` | correct | HALean/Core/Schema.lean:33 `partial def Validator.run` |
| R-225 | 653-656 | Lean's JSON objects are sorted by key; the shell sends ordered `[key, value]` lists (`bridge/protocol.py`); a dict printed by a template lists its keys sorted | correct | bridge/protocol.py:11-12,43-45; probe T34: HA `{'b': 1, 'a': 2}`, HALean `{'a': 2, 'b': 1}` |
| R-226 | 657-661 | `expand`: a non-group entity with an `entity_id` attribute is a render error | correct | probe T33: HA returns the members, HALean returns an error |
| R-227 | 662-665 | Zone names (`strftime('%Z')`, `tzinfo`) are errors | correct | probes T25, T26 |
| R-228 | 666-669 | HA fires time and time-pattern triggers at a random 50-500 ms into the second; `trigger.now` in HALean is 500 ms in | correct | upstream helpers/event.py:87-88 (50000, 500000 µs); HALean/Automation/Engine.lean:1586 `TIME_CHANGE_MICROSECOND := 500000` |
| R-229 | 670-671 | Floats sent on as JSON lose their trailing `.0` (`20.0` arrives as `20`) | correct | probe: `temperature: 20.0` leaves the engine as `20`, `20.5` as `20.5` (logs/engine-known_gaps.log) |
| R-230 | 675-677 | the ends of delays happen as ticks arrive, so a 0.7 s delay lasts about 1 s; catch-up is limited to one day | correct | probe: the delay ends at the first tick at or after 0.7 s; a tick 3 days late fires an hourly pattern 24 times (logs/engine-known_gaps.log); HALean/Automation/Engine.lean:1761 |
| R-231 | 678-681 | `wait.remaining` after a woken wait with a `timeout` is a render error in HALean; after a timeout it is `0.0` | correct | probe: error log `wait.remaining values are not supported by HALean`; after a timeout the value is 0 (logs/engine-known_gaps.log) |
| R-232 | 693-694 | `STEP_FUEL` (1M steps per drive) | correct | HALean/Automation/Script.lean:466 `STEP_FUEL := 1000000` |
| R-233 | 695-698 | `ENGINE_FUEL`, `LOOP_FUEL`: nested handler calls deeper than 10,000, or more than 100,000 timer rounds within one input | correct | HALean/Automation/Engine.lean:927 (`ENGINE_FUEL := 10000`), :1029 (`LOOP_FUEL := 100000`) |
| R-234 | 699-707 | `this`: its `last_changed`, `last_updated`, `last_reported` and `context` are render errors | correct | shipped engine scenario `unsupported` (automation `opaque`), 02/run1-scenarios.log `PASS  unsupported`. Engine only: the scenario is `differential: false` |
| R-235 | 708-711 | the differential harness cannot check a `for:` of 0, so `templated_for_zero` is engine-only | correct | tests/scenarios/templated_for_zero.yaml:4-5; DV: SKIPPED. The stated cause (frozen monotonic clock) was not tested |
| R-236 | 716-717 | The bridge subscribes to events after `get_states` | correct | bridge/bridge.py:353,362 |
| R-237 | 718-721 | MQTT: the bridge subscribes to `#` (plus `$<level>/#`) with HA's `mqtt/subscribe` command | correct | bridge/bridge.py:316-327,257-266; the command exists in the installed HA (components/mqtt/__init__.py:631); 02/run1-bridge_e2e.log `PASS bridge end-to-end with mqtt` |
| R-238 | 725-726 | the delivered `qos` is capped by the bridge's subscription (the highest `qos` a trigger asks for) | correct | bridge/bridge.py:323-327 |
| R-239 | 731-734 | HA's WebSocket API can only send a webhook in (`webhook/handle`); the bridge warns about automations that have one | correct | installed HA components/webhook/__init__.py:277; bridge/bridge.py:365-370 |
| R-240 | 735-738 | `webhook_input` in `bridge/protocol.py`; multipart bodies are not supported; the query is split with `urllib.parse.parse_qsl` | correct | bridge/protocol.py:82-112 |
| R-241 | 739-742 | `trigger.data` and `trigger.query`: key access, `in` and truthiness work; methods, iterating, `length` and printing are render errors | correct | case test_scenario_webhook[webhook_trigger] (key access); the render errors were not probed |
| R-242 | 746 | HALean covers 402 upstream functions (`manifest.yaml`) | overstated | 402 manifest entries: 394 functions or methods and 8 classes (logs/manifest-node-kinds.log). See Not correct |
| R-243 | 746 | 53 of them proved | correct | 53 entries have `status: proven` (logs/manifest-counts.log). What the theorems establish is audited elsewhere |
| R-244 | 750-757 | Left: trigger platforms `homeassistant` shutdown, `calendar`, `persistent_notification`, `conversation`, `device` | correct | probe: all five are `unsupported` at load (logs/probe-automation-load.log) |
| R-245 | 755-757 | `mqtt` and `webhook` are translated; the bridge feeds MQTT but cannot see webhook requests | correct | see rows for lines 231, 718-721, 731-734 |
| R-246 | 764-765 | Left: event triggers with `context` | correct | probe `event_context`: unsupported |
| R-247 | 766-775 | Left: connecting the helpers to the engine; then `input_datetime`, `schedule` and `group` | correct | see rows for lines 11 and 575 |
| R-248 | 776-779 | Left: `util/color.py`; time zones in `util/dt.py`; probatio's compiled schema path | correct | no `util/color` entry in manifest.yaml (logs/structure-checks.log) |
| R-249 | 780-782 | Left to prove: `queued` runs in arrival order, `restart` leaves the newest run, the run bound with script entities | correct | no theorem with such a statement found by name (logs/structure-checks.log lists the theorems whose names contain queued/restart/fifo; they are about admission and the core's ready queue) |
| R-250 | 790-791 | Next step 1: generate differential scenarios automatically | correct | no generator among the tracked files outside review/ (logs/structure-checks.log) |
| R-251 | 792-794 | the run bound is proved: `runs_bounded` in `HALean/Automation/EngineBound.lean` | correct | theorem found in that file (logs/names-check.log); content audited elsewhere |
| R-252 | 797 | Next step 4: widen the subset: the other sun events and conditions (dawn, dusk, elevation) | correct | probe `sun_dawn`: still rejected |
| R-253 | 801-804 | Apache License 2.0 (`LICENSE`); translates parts of HA Core (Apache 2.0), probatio (MIT), Jinja2 (BSD 3-Clause), astral (Apache 2.0), python-slugify (MIT), CPython (PSF); `NOTICE` lists them; texts in `LICENSES/` | correct | LICENSE line 1-2; NOTICE lists the six; LICENSES/ has six files, one per work (logs/structure-checks.log) |

## Not correct

### R-15 (README line 20-22): overstated

**Claim.** "All services share one `manifest.yaml`, one pinned HA release, one bridge and one test setup."

**Finding.** The manifest, the pin and the pytest setup are shared. The bridge is not. `bridge/bridge.py` starts `halean-automation`, or `halean-script` with `--scripts` (lines 73-75 and 340). No code path in the bridge starts or talks to `halean-core`, `halean-core-states`, `halean-core-services`, `halean-core-events` or `halean-helpers`. The README says so itself for the helpers (line 11, lines 566-567).

### R-28 (README line 59-60): overstated

**Claim.** "After an upstream pull this shows exactly which translations need revisiting."

**Finding.** `tools/drift.py` hashes the AST of the one mapped `def` or `class` (`hash_ref`, lines 89-102; `find_node` accepts only `FunctionDef`, `AsyncFunctionDef`, `ClassDef`, lines 66-71). A change outside that node is not seen. Probe `probes/drift_constant_probe.sh`: in a copy of upstream, `REPEAT_TERMINATE_ITERATIONS = 10000` in `helpers/script.py` was changed to `20000`. `drift.py compare` still reports `363/363 mapped functions identical` (`logs/drift-constant-probe.log`). The Lean engine copies that constant (`HALean/Automation/Script.lean:182`) and README line 270 states it. Module-level constants cannot be manifest entries at all.

### R-29 (README line 61): overstated

**Claim.** "`protocol/schema.json`: the versioned wire protocol."

**Finding.** The file has `"$id": "halean/protocol/v1"` and a title with `v1` (lines 3-4). That is the only version. No input or output message has a version field (`HALean/Automation/Protocol.lean:63-135`, `bridge/bridge.py:354-357`). No file in `HALean/`, `Exe/`, `bridge/`, `tests/`, `tools/`, `demo/` or `.github/` reads `schema.json`; it is mentioned only in comments (`logs/small-checks.log`). So no test checks that the engine or the bridge follow the schema, and neither side can detect a version mismatch. The top-level `oneOf` lists the seven automation inputs only; the script inputs (`script_init`, `script_call`, `script_reload`) are defined under `$defs` and not referenced by it.

### R-30 (README line 66-67): false

**Claim.** The Setup block starts with `export ELAN_HOME=/Volumes/MacStorage/AppData/elan` and `export PATH=$ELAN_HOME/bin:$PATH`.

**Finding.** This is a directory on one macOS machine. On this Linux machine `/Volumes` does not exist, so the two lines put a missing directory on `PATH` and `lake` is not found unless elan is on `PATH` already. The remaining commands of the block work once `$HOME/.elan/bin` is on `PATH`: `01-build-axioms/logs/build-lib.log`, `build-exe.log` and the six logs in `02-shipped-tests/logs/run1-*` end with exit 0.

### R-44 (README line 92): overstated

**Claim.** The live test "checks on HA's real clock that ... a `for: 2s` trigger fires after 2 s and not before."

**Finding.** `tests/live/docker_e2e.py:197-202`: after `input_boolean.c` is turned on and the second check has seen `input_boolean.a` go off (0.10 s in the shipped log), the test sleeps 1.0 s, asserts `input_boolean.d` is still off, then waits up to 5 s for it to turn on. A trigger that fired 1.2 s after the state change would pass. The test's own output says `for: 2s fired after ~2.1s (not before 1s)` (`02-shipped-tests/logs/run1-live_docker.log`). The measured delay was about 2.1 s in both shipped runs; the assertion is weaker than the README sentence.

### R-56 (README line 127-128): overstated

**Claim.** "... all use the release tag recorded in `manifest.yaml` (`upstream.tag`), so every test exercises exactly the code that was translated."

**Finding.** It holds for the tests that run Home Assistant (differential suite, live Docker test). It does not hold for every test of the Setup block:

* `tests/sun/compare.py` does not call HA. It compares `halean-sun-grid` with its own 12-line copy of `get_observer_astral_event_next` (lines 12-23, "with as_local = fixed offset") on top of astral. astral's version comes from the command line in the README (`--with astral==2.2`), not from the manifest; no test checks it.
* `tests/run_scenarios.py`, `tests/run_script_scenarios.py` and `tests/bridge_e2e.py` run no upstream code. Their expectations are written by hand.
* The demo's HA image tag is a literal in `demo/docker-compose.yml:14`. It equals the manifest tag today; nothing checks it.

### R-60 (README line 138-148): stale

**Claim.** "Upstream source (read-only, sparse checkout of the relevant files)" followed by a `git sparse-checkout set --no-cone ...` command.

**Finding.** The command does not check out every file the manifest maps. Probe `probes/sparse_check.sh` copies exactly the listed paths and runs `drift.py compare` against the copy: 345 of 363 HA entries are found, 18 are missing (`logs/sparse-check.log`):

* `components/mqtt/` (client.py, models.py, trigger.py, util.py): 10 entries
* `components/webhook/` (`__init__.py`, trigger.py): 4 entries
* `components/tag/trigger.py`: 1 entry
* `exceptions.py`: 3 entries

With a checkout made by the README command, `drift.py check` reports these 18 as `MISSING` and exits 1, and `drift.py coverage` raises `FileNotFoundError` (it reads every tracked file, `tools/drift.py:175`).

**What changed.** `logs/sparse-history.log`: the command covered the whole manifest at commit 5761000 (2026-11-20). `exceptions.py` entries arrived with 06e09f6 (2026-11-23), `components/tag/trigger.py` with 29b3a98 (2026-11-25), mqtt and webhook with 2052ee0 (2026-11-25). The command was extended for the helper integrations in 3bb96f8 but not for these. The reviewers' own checkout uses a wider set (`git -C upstream/ha-core sparse-checkout list`).

### R-113 (README line 235): false

**Claim.** Table row "Run modes", column "Rejected at load, stays in HA": "`max_exceeded` log levels".

**Finding.** Nothing is rejected. Probe `probes/probe_automation_load.py` sends automations with `mode: queued`, `max: 2` and `max_exceeded: warning`, `silent` and `error`. All three load; the reply has no `unsupported` command for them (`logs/probe-automation-load.log`, the three `DIFF` lines). The string `max_exceeded` does not occur in `HALean/Automation/` (`logs/small-checks.log`); the automation decoder ignores the key. HA accepts the key too (`logs/probe-ha-misc.log`). The effect of the key in HA is the level of one log line, which no harness compares. The row has said this since the README text was written (commit 5761000) and the engine never rejected the key, so this is not a stale claim. For scripts the README (line 492) says "`max_exceeded` (only logs)", which matches `HALean/Script/Config.lean:173-175`.

### R-131 (README line 257-258): overstated

**Claim.** "Upstream behaviours the translation keeps exactly, each covered by a scenario in `tests/scenarios/`", followed by five bullets.

**Finding.** Scenario per bullet:

| Bullet | Scenario in `tests/scenarios/` | Covered |
|---|---|---|
| 1. failing `condition` step, "Inside `choose`/`if`/`repeat`/`sequence`" | `nested_condition` (choose, top level); `parallel` (`condition_in_branch`: a `sequence` branch of `parallel`) | choose: yes. `if`, `repeat`: no scenario has a `condition` step inside them |
| 2. `continue_on_error` | `continue_on_error`, `wait_template_edges` | yes |
| 3. `None` and errors in conditions | `condition_errors` (`if`, `until`, automation conditions, `or` with an error); `enabled_forms` (a disabled automation-level condition) | in part: no scenario has a disabled condition inside `and`, `or` or `not`, and none has a `while` whose condition raises |
| 4. queued run counts toward `max` | `queued_max` | yes |
| 5. `repeat` aborts after 10,000 iterations | none. The only `while` loops are in `repeat.yaml` (ends at once) and `variables.yaml` (2 iterations) | no |

A walk over all 60 scenario files for `condition` steps nested in `if`/`repeat`/`sequence`/`choose` finds two (the ones named above). Only `enabled_forms.yaml` uses `enabled`. No file under `tests/` contains the number 10000 (`logs/small-checks.log`).

The behaviours themselves hold. My scenario `probes/scenarios/kept_behaviours.yaml` (condition step in `if`, `repeat`, `sequence`; disabled conditions in `and`, `or`, `not`; `while` with an error) passes on real HA and on the engine in two runs (`logs/harness-own-scenarios-run1.log`, `run2`). The 10,000 limit: the engine fires the loop event 10000 times and aborts (`logs/engine-repeat_limit.log`); real HA does the same (`logs/probe-ha-misc.log`). The shipped harness cannot observe this case: HA yields to the event loop in each iteration and the harness's `_settle` gives up after 50 loop turns (`logs/harness-repeat-limit-not-observable.log`).

### R-148 (README line 294-295): overstated

**Claim.** State machine, known gaps: "a JSON float written without a fraction or exponent sign (`1e16`) reads as an int."

**Finding.** The stated condition is too narrow. `halean-core-states` treats a number as a float only if Lean's JSON parser keeps a non-zero exponent (`Exe/CoreStates.lean:75-81`). Probe `probes/float_probe.sh` (`logs/float-probe.log`):

| JSON text | Python `json.loads` | `halean-core-states` |
|---|---|---|
| `1e16` | float | int `10000000000000000` |
| `1.0e16` (has a fraction) | float | int `10000000000000000` |
| `1e+16` (has an exponent sign) | float | int `10000000000000000` |
| `1.5e3` | float | int `1500` |
| `1.5e+16` | float | int `15000000000000000` |
| `1e22` | float | int |
| `1.0`, `2.5e-1` | float | float |

So every float written in exponent notation with an integral value reads as an int, with or without a fraction or sign. `1e+16` is the form Python's `json.dumps` writes for every float from 1e16 up, which is the form the test harness and any Python shell send.

### R-162 (README line 335): stale

**Claim.** Schemas table, column "Rejected (`unsupported`)": "`cv.percentage` (not in HA's `cv`), `cv.time`, `cv.date`, `cv.template`, `cv.url`, `cv.icon` and every other `cv.*`".

**Finding.** `cv.icon` is no longer rejected. Probe V3 in `probes/core_probes.py` (`logs/core-probes.log`): registering a service with `{cv: icon}` succeeds; a call with `mdi:lamp` returns it; a call with `lamp` fails with `Icons should be specified in the form "prefix:name" at 'a'`, which is HA's message (`logs/ha-direct.log`). The other five names of the list are rejected.

**What changed.** Commit eaee9a4 ("cv.icon in the probatio model", 2026-11-25) added `CvFn.icon` (`HALean/Core/ConfigValidation.lean:124,212`) and the spec name (`HALean/Core/ServicesJson.lean:122`). The README was edited after that (3bb96f8) without moving `cv.icon`. The test-side spec builder does not know the name (`tests/differential/schema_spec.py:24`, set `CV`), so no service-schema case uses `{cv: icon}`; the validator is exercised through the helpers' config schemas (case `input_boolean_config_bad_icon`).

### R-242 (README line 746): overstated

**Claim.** "HALean covers 402 upstream functions (`manifest.yaml`)".

**Finding.** The manifest has 402 entries. 394 resolve to functions or methods and 8 to classes: `core.py::SupportsResponse`, `Service`, `ServiceCall`, `EventOrigin`, `HassJobType`, and `exceptions.py::HomeAssistantError`, `ServiceValidationError`, `ServiceNotFound` (`logs/manifest-node-kinds.log`). 39 of the 402 are probatio functions, not Home Assistant ones (`logs/manifest-counts.log`).

## Not checked

* R-16 (line 26-31): latest release has `halean-demo.tar.gz`; `curl ... | tar xz; cd halean-demo && docker compose up -d`. Needs the GitHub release page. Not fetched. release.yml:186-229 creates that asset on every release.
* R-26 (line 57): the same way AppDaemon and Node-RED do. Statement about other projects. Not checked.
* R-59 (line 132-133): `pytest-homeassistant-custom-component` is published only for releases. Statement about PyPI. Not checked.

## Notes that are not README claims

* `.github/workflows/lean_action_ci.yml:19` builds eight executables. Its comment says "every executable". `halean-helpers` is missing, and `binaries.yml` builds only two, so no CI job compiles `Exe/Helpers.lean`.
* No CI job runs `tests/differential/`, `tests/bridge_e2e.py`, `tests/sun/compare.py` or `tests/live/docker_e2e.py`. CI runs the Lean build, the two engine-only scenario runners (in `binaries.yml`) and the demo smoke test. The README does not claim more.
* `tests/run_scenarios.py:12-15` (docstring) says the scenarios are "not yet differential tests against a running Home Assistant (see README, \"Next steps\")". That docstring is stale; the README's Next steps no longer says this.
* `tests/differential/schema_spec.py:24` does not know `icon`, although the model accepts `{cv: icon}` (see R for line 335).
* `tools/drift.py:4` pins `probatio==0.13.0` a second time; no test compares it with `manifest.yaml`'s `upstream.probatio`.
