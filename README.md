# HALean

Home Assistant's core, rewritten in Lean 4 one service at a time and translated
function by function, so it can be formally verified and still track upstream.

| Service | Lean | Executable | Status |
|---|---|---|---|
| Automation engine (triggers → conditions → actions, run modes) | `HALean/Automation/` | `halean-automation` | done, tested against real HA |
| Templates (Jinja) | `HALean/Template/` | | next |
| Scripts | `HALean/Script/` | | planned |
| State machine, event bus, service registry | `HALean/Core/` | | planned |

`HALean/Core/` holds what every service shares (states, time, JSON). All
services share one `manifest.yaml`, one pinned HA release, one bridge and one
test setup. Integrations (devices, cloud services) stay in Python.

## See it running

```bash
cd demo && docker compose up --build
```

Then open <http://localhost:8124/halean-demo>. The login is in
`demo/.run/login.txt`, created on the first start. This starts a separate Home
Assistant (2026.10.4) with dummy devices: a motion sensor, two lights, a heater
and a temperature sensor. HA has **no automations of its own**. All six in
[`demo/automations.yaml`](demo/automations.yaml) run in the Lean engine. A
simulator walks through the hallway and lets the room cool, so the engine keeps
reacting. The "Lean engine" card and the logbook card show each run as it
happens. Your own Home Assistant is not touched; the demo has its own
containers, volume and port. To stop it, run `docker compose down`. To start
over, add `-v`.

```
Home Assistant ──WebSocket──▶ bridge/bridge.py ──JSON lines──▶ halean-automation (Lean)
  (unchanged)   ◀─call_service── (unverified shell) ◀─commands── pure Engine.step
```

* **`HALean/Automation/`**: the engine. `Engine.step : Engine → Input → Engine × List Cmd`
  is pure. It never reads a clock or does I/O, so every run can be replayed.
* **`bridge/bridge.py`**: a thin shell that talks to a stock HA over its
  WebSocket API, the same way AppDaemon and Node-RED do. No fork is needed.
* **`manifest.yaml` + `tools/drift.py`**: map each upstream Python function to
  the Lean definitions that translate it, with an AST hash. After an upstream
  pull this shows exactly which translations need revisiting.
* **`protocol/schema.json`**: the versioned wire protocol.

## Setup

```bash
export ELAN_HOME=/Volumes/MacStorage/AppData/elan
export PATH=$ELAN_HOME/bin:$PATH
lake build                       # engine + all proofs
uv run tests/run_scenarios.py    # behaviour scenarios (engine only)
uv run tests/differential/run.py # same scenarios through a real Home Assistant vs the engine
uv run tests/bridge_e2e.py       # bridge against a fake HA WebSocket server
uv run tests/live/docker_e2e.py  # bridge + engine driving the pinned HA release in a throwaway Docker container
```

## Live test against Home Assistant in Docker

`tests/live/docker_e2e.py` starts `ghcr.io/home-assistant/home-assistant:<tag>`, where
`<tag>` is the release pinned in `manifest.yaml`, in a container named `halean-e2e`.
The container runs on port 18123 with its own config in `tests/live/.run/`, and
is removed afterwards (`--keep` leaves it running). It never touches any other
Home Assistant. The test onboards a test user (random password, never printed),
runs the real bridge and engine with three automations, and checks on HA's real
clock that:

1. a state trigger turns another `input_boolean` on and fires an event,
2. `continue_on_error` carries on past a call to a service that doesn't exist,
3. a `for: 2s` trigger fires after 2 s and not before.

## Differential testing against real Home Assistant

`tests/differential/` replays every scenario in `tests/scenarios/` through a real
Home Assistant, running in-process via `pytest-homeassistant-custom-component`
at the same release the translation is pinned to (**2026.10.4**). The same
inputs go through the Lean engine, and the two must produce identical:

* `automation_triggered` (which automations fired, in order),
* service calls (domain, service, target and data, in order; each call blocks
  until the scenario reports its result, like the bridge protocol),
* events fired by `event:` actions (in order).

The clock is frozen and advanced one second at a time, like the bridge's ticks.
A scenario can opt out with `differential: false` (e.g. `unsupported.yaml`).

The three streams are compared separately because HA queues an event fired
while another event is being dispatched (`EventBus.async_fire_internal`). Inside
a `state_changed` handler, HA's own `automation_triggered` event and `event:`
actions reach listeners after service calls that ran later. The calls happen in
the same order either way; only delivery on the bus is deferred.

The harness can catch subtle differences: changing the engine so a failing
nested `condition` ends the whole run fails `nested_condition` against real HA.

**One pinned release.** The translation, the differential harness and the Docker
image all use the release tag recorded in `manifest.yaml` (`upstream.tag`), so
every test exercises exactly the code that was translated.
`test_harness_matches_pin` fails if the harness and the pin ever diverge.
Releases are used instead of `dev` because `pytest-homeassistant-custom-component`
is published only for releases.

Upstream source (read-only, sparse checkout of the relevant files):

```bash
git clone --depth 1 --filter=blob:none --sparse --branch 2026.10.4 \
  https://github.com/home-assistant/core upstream/ha-core
git -C upstream/ha-core sparse-checkout set --no-cone /homeassistant/components/automation/ \
  /homeassistant/helpers/ /homeassistant/components/homeassistant/triggers/ \
  /homeassistant/const.py /homeassistant/core.py
```

## Tracking upstream

Move to a new release only when all three are available for it: the git tag, the
`pytest-homeassistant-custom-component` version that ships it, and the Docker image.

```bash
NEW=2026.11.0
git -C upstream/ha-core fetch --depth 1 --filter=blob:none origin tag $NEW
git -C upstream/ha-core checkout $NEW
uv run tools/drift.py check        # lists STALE / MISSING translations, exit 1 if any
# re-translate the stale ones, re-run tests and proofs, then:
uv run tools/drift.py update --only 'helpers/script.py::Script.async_run'
# bump the harness pin in tests/differential/run.py to the version shipping $NEW, then:
uv run tools/drift.py update       # re-hash everything and record the commit and tag
uv run tools/drift.py coverage     # upstream functions in tracked files not mapped yet
```

`uv run tools/drift.py compare --against <dir>/homeassistant` compares the
mapped functions with any other copy of Home Assistant, e.g. a `dev` checkout,
to see what the next release will change.

## Running against a real Home Assistant

```bash
export HA_URL=ws://homeassistant.local:8123/api/websocket
export HA_TOKEN=<long-lived access token>
uv run bridge/bridge.py /path/to/automations.yaml --dry-run   # log calls, change nothing
# --status-entity input_text.x shows each run in HA (as in the demo)
```

Automations outside the supported subset are reported as `unsupported` and stay
in HA. For each automation the engine runs, turn off HA's own copy so it
doesn't run twice.

## What is translated (upstream commit in `manifest.yaml`)

| Area | Supported | Rejected at load, stays in HA |
|---|---|---|
| Triggers | `state` (from/to/not_from/not_to, attribute, `for`, explicit null `to`), `numeric_state` (below/above, entity bounds, attribute, `for`, arming), `time` (fixed `at`, weekday), `time_pattern`, `event` (flat `event_data`) | templates, `template`, `sun`, `zone`, `homeassistant`, `mqtt`, `webhook`, device triggers, entity-based or offset `time` |
| Conditions | `and`/`or`/`not` (incl. shorthand), `state` (match any/all, `for`, attribute, `input_*` references), `numeric_state`, `time` (fixed, `input_datetime`, `time` entities, midnight crossing, weekday), `trigger`, `enabled: false` | `template`, `value_template`, platform conditions, timestamp-sensor bounds (error) |
| Actions | service call (blocking), `delay`, `condition`, `choose`, `if`/`else`, `repeat` count/while/until, `stop` (+`error`), `event`, `sequence`, `continue_on_error`, static `enabled` | templates in data, `response_variable`, `variables`, `wait_template`, `wait_for_trigger`, `parallel`, `repeat for_each`, device actions, `scene` |
| Run modes | `single`, `restart`, `queued` (FIFO), `parallel`, `max`, conditions checked before admission | `max_exceeded` log levels |

Upstream behaviours the translation keeps exactly, each covered by a scenario
in `tests/scenarios/`:

* A failing `condition` step ends only the sub-script it's in. Inside
  `choose`/`if`/`repeat`/`sequence`, the outer sequence carries on.
* `continue_on_error` swallows only `HomeAssistantError`. Config errors always
  stop the run, and other exceptions are converted only by the failing step's
  own flag.
* Conditions return true, false, `None` (disabled) or an error. `and`/`or`
  skip `None`, `not` treats it as false, and `if`/`while` treat an error as false.
* A queued run counts toward `max` while it waits, and `automation_triggered`
  fires on admission, before the run starts.
* `repeat` aborts after 10,000 iterations.

## Proved so far (`HALean/Automation/Proofs.lean`)

`evalAnd_nil`, `evalOr_nil`, `evalCond_disabled`, `evalNot_disabled`,
`evalAnd_all_disabled`, `checkAutomationConditions_nil`, `testConditions_nil`,
`match_invert`, `match_all`, `single_exclusive`, `restart_never_rejects`,
`admit_bounded` (queued/parallel never exceed `max`), `queued_waits`.

## Known gaps and deviations

* **The translation is tested against Python, not proven equivalent.** All 19
  differential scenarios match real HA at the pinned release, but they cover
  only the paths they exercise.
* Callbacks run in a fixed order (automations in config order, then triggers in
  order), which models HA's eager-task scheduling. Timing races between
  separate HA tasks are not modelled.
* Time triggers and the ends of delays happen on whole seconds as ticks
  arrive, so a 0.7 s delay lasts about 1 s. If the bridge stalls,
  catch-up is limited to one day.
* `STEP_FUEL` (1M steps per drive) is a safety net HA doesn't have. HA would
  block its event loop instead.
* `drive`/`finishRun`/`fireDue` are `partial`, so nothing has been proved about
  them yet. Making them total with explicit measures is the next proof step.
* The bridge is unverified. It subscribes to events after `get_states`, so a
  change in that window can be missed at startup.

## Next steps

1. Generate differential scenarios automatically (random automations within the supported
   subset plus random event sequences) to cover far more paths than hand-written ones.
2. Make the run loop total and prove run-level properties: a `single` automation never has
   two live runs, and a `queued` one runs in arrival order.
3. User-level properties over a whole `automations.yaml`: conflicting commands to the
   same entity, and trigger loops (an action that re-triggers itself).
4. Widen the subset: templates, `wait_for_trigger`, `parallel`.
