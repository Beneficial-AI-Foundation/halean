# HALean

Home Assistant's core, rewritten in Lean 4 one service at a time and translated
function by function, so it can be formally verified and still track upstream.

| Service | Lean | Executable | Status |
|---|---|---|---|
| Automation engine (triggers → conditions → actions, run modes) | `HALean/Automation/` | `halean-automation` | done, tested against real HA |
| Templates (Jinja) | `HALean/Template/` | `halean-template` (test driver) | subset done, used by automations, tested against real HA |
| Scripts (`script.*` entities and services) | `HALean/Script/` | `halean-script` | subset done, tested against real HA, runs with the bridge (`--scripts`) |
| Helpers (`input_boolean`, `input_number`, `input_select`, `input_text`, `counter`, `timer`) | `HALean/Helpers/` | `halean-helpers` (test driver) | YAML helpers and their services done, tested against real HA; not yet connected to the engine |
| State machine (`hass.states`) | `HALean/Core/StateMachine.lean` | `halean-core-states` (test driver) | done, tested against real HA |
| Event bus (`hass.bus`) | `HALean/Core/EventBus.lean` | `halean-core-events` (test driver) | subset done (callback listeners), tested against real HA |
| Service registry (`hass.services`) | `HALean/Core/ServiceRegistry.lean` | `halean-core-services` | subset done, tested against real HA |
| Core (`hass`: states, bus and services joined) | `HALean/Core/Hass.lean` | `halean-core` (test driver) | subset done (callback and `async def` listeners, handlers that suspend, tasks and the event loop's ready queue, `async_block_till_done`), tested against real HA |

`HALean/Core/` holds what every service shares (states, time, JSON). The three
core services also run joined (`HALean/Core/Hass.lean`): the state machine and
the registry fire through the bus model, and listeners and handlers act on the
whole core. All
services share one `manifest.yaml`, one pinned HA release, one bridge and one
test setup. Integrations (devices, cloud services) stay in Python.

## See it running

With only Docker installed (no checkout, no Lean toolchain), from the
[latest release](https://github.com/Beneficial-AI-Foundation/halean/releases/latest):

```bash
curl -fsSL https://github.com/Beneficial-AI-Foundation/halean/releases/latest/download/halean-demo.tar.gz | tar xz
cd halean-demo && docker compose up -d
```

From a checkout, `cd demo && docker compose up -d` runs the same released image.
To try unreleased engine changes, add `--build` to build it from your working
tree.

Then open <http://localhost:8124/halean-demo>. The login is in `.run/login.txt`
next to `docker-compose.yml`, created on the first start. This starts a separate Home
Assistant (2026.10.4) with dummy devices: a motion sensor, two lights, a heater
and a temperature sensor. HA has **no automations of its own**. All seven in
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
lake build                       # the HALean library: engine + all proofs
lake build halean-automation halean-script halean-template halean-sun-grid \
  halean-core halean-core-states halean-core-services halean-core-events \
  halean-helpers  # the executables the tests drive
uv run tests/run_scenarios.py    # behaviour scenarios (engine only)
uv run tests/run_script_scenarios.py  # script scenarios (halean-script only)
uv run tests/differential/run.py # scenarios + template cases through a real Home Assistant vs Lean
uv run tests/bridge_e2e.py       # bridge against a fake HA WebSocket server
uv run --with astral==2.2 tests/sun/compare.py  # sunrise/sunset vs astral, to the microsecond
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
2. a call to a service that doesn't exist stops the run even with
   `continue_on_error` (`ServiceNotFound` is one of HA's configuration errors),
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
A `set` step that changes neither the state nor the attributes fires no
`state_changed` in HA, so the scenario runners send the engine a `tick` for it.
A scenario can opt out with `differential: false` (e.g. `unsupported.yaml`).

The three streams are compared separately because HA queues an event fired
while another event is being dispatched (`EventBus.async_fire_internal`). Inside
a `state_changed` handler, HA's own `automation_triggered` event and `event:`
actions reach listeners after service calls that ran later. The calls happen in
the same order either way; only delivery on the bus is deferred.

The harness can catch subtle differences: changing the engine so a failing
nested `condition` ends the whole run fails `nested_condition` against real HA.

**Templates** get their own differential test (`tests/differential/test_templates.py`).
Every case in `tests/templates/*.yaml` is rendered by HA's own
`Template.async_render` (or `condition.async_template`) and by `halean-template`.
The result type and `repr()` must match, or both must raise. Cases marked
`unsupported: true` must be rejected by HALean at load time; cases marked
`render_info: true` must also read the same entities and domains
(`async_render_to_info`), which is what template triggers listen to.

**One pinned release.** The translation, the differential harness and the Docker
image all use the release tag recorded in `manifest.yaml` (`upstream.tag`), so
every test exercises exactly the code that was translated.
`test_harness_matches_pin` fails if the harness and the pin ever diverge. Templates
also depend on Jinja2, which is not HA code, so `manifest.yaml` pins its version
too (`upstream.jinja2`, 3.1.6), and the same test checks it.
Releases are used instead of `dev` because `pytest-homeassistant-custom-component`
is published only for releases.

Upstream source (read-only, sparse checkout of the relevant files):

```bash
git clone --depth 1 --filter=blob:none --sparse --branch 2026.10.4 \
  https://github.com/home-assistant/core upstream/ha-core
git -C upstream/ha-core sparse-checkout set --no-cone /homeassistant/components/automation/ \
  /homeassistant/helpers/ /homeassistant/components/homeassistant/triggers/ \
  /homeassistant/const.py /homeassistant/core.py /homeassistant/components/template/trigger.py \
  /homeassistant/util/dt.py /homeassistant/util/__init__.py /homeassistant/util/location.py \
  /homeassistant/components/zone/ /homeassistant/components/sun/ /homeassistant/components/script/ \
  /homeassistant/components/input_boolean/ /homeassistant/components/input_number/ \
  /homeassistant/components/input_select/ /homeassistant/components/input_text/ \
  /homeassistant/components/counter/ /homeassistant/components/timer/ \
  /homeassistant/components/number/ /homeassistant/components/select/ /homeassistant/components/text/
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

`--scripts /path/to/scripts.yaml` runs scripts in the same engine
(`halean-script`): the engine's automations then call these scripts. Their
states are written to HA over its REST API (`HA_REST_URL`, by default
`HA_URL`'s host). HA itself cannot call them (see Known gaps under Scripts),
so remove them from HA's `scripts.yaml`. Scripts outside the subset are
reported as `unsupported`.

## Releasing

Every push to `master` is released by CI (`.github/workflows/release.yml`)
once it passes; there is nothing to do by hand. Pushes that only touch
Markdown are skipped.

1. **test**: the Lean build (engine + all proofs).
2. **image**: the demo image for linux/amd64 and linux/arm64, each on a native
   runner, pushed by digest only (no tag, so nobody pulls it yet).
3. **smoke-test**: `demo/make-bundle.sh` builds the release bundle and
   `demo/smoke-test.sh` runs it like a user would, against the new image and the
   pinned HA release, until the engine triggers an automation.
4. **binaries** (`.github/workflows/binaries.yml`, in parallel with 2–3):
   `halean-automation` and `halean-script` built natively for Windows x64
   (`.exe`), macOS Apple Silicon and Linux x86_64/arm64, each tested with the
   scenario suites, then packaged with the bridge as
   `halean-<version>-<platform>.{zip,tar.gz}`.
5. **publish**: tags the image `ghcr.io/beneficial-ai-foundation/halean:<version>`,
   `:<major>.<minor>` and `:latest`, and creates the GitHub release
   `v<version>` with `halean-demo.tar.gz`, the executable archives and
   `SHA256SUMS`.

These builds run only after a merge to master; pull requests run just the Lean
build (`lean_action_ci.yml`).

The version is `<major>.<minor>` from `lakefile.toml` plus the workflow run
number (`0.1.42`). Bump `version` in `lakefile.toml` to start a new line.

To check a bundle locally against an image you built:

```bash
docker build -f demo/Dockerfile -t ghcr.io/beneficial-ai-foundation/halean:0.1.0-local .
demo/make-bundle.sh 0.1.0-local dist && demo/smoke-test.sh dist/halean-demo.tar.gz
```

## What is translated (upstream commit in `manifest.yaml`)

| Area | Supported | Rejected at load, stays in HA |
|---|---|---|
| Triggers | entity ids lower-cased and validated (`cv.entity_ids`); `state` (from/to/not_from/not_to: strings without an `attribute`, as HA's schema; `"*"` matches anything; values compared by Python's `==`; attribute, `for`, explicit null `to`), `numeric_state` (below/above, entity bounds, attribute, `value_template`, `for`, arming), `template` (arming, `for`, re-rendered like HA's template tracker: only for what the last render read, every minute when it used `now()`, rate limits for loops over states), `time` (fixed or templated `at`: a limited template rendered with the static `trigger_variables`; `input_datetime` entities with a date or only a time, timestamp/uptime sensors, `offset`, weekday; rescheduled when the entity changes), `time_pattern` (values validated like `TimePattern`), `homeassistant` with `event: start` (once, on `homeassistant_started`), `tag` (`tag_id`, optional `device_id`), `event` (templated `event_type` and `event_data`, limited templates rendered with the static `trigger_variables`; nested `event_data`; values compared by Python's `==`; one listener per listed type, so a type listed twice fires twice), legacy `zone` (enter/leave by coordinates, Vincenty distance like HA's, or a person's/device tracker's `in_zones`), legacy `sun` (sunrise/sunset with `offset`, astral's NOAA calculation at HA's location and elevation), `mqtt` (topic filters with `+`/`#` as paho matches them, exact topics before wildcard filters, `payload` and `value_template` with `value`/`value_json`, `qos`, UTF-8 `encoding`, a retained message once per subscription and topic, `trigger.topic`/`payload`/`payload_json`/`qos`; templated topic and payload rendered with the static `trigger_variables`; fed by the protocol's `mqtt` input), `webhook` (`allowed_methods` and `local_only` of the trigger that registered the id first, `trigger.json` for a JSON Content-Type, else `trigger.data` (form fields), `trigger.query`; templated ids rendered with the static `trigger_variables`; fed by the protocol's `webhook` input, which the bridge cannot send); `for:` static or templated (a template string or a mapping of templates, rendered with the trigger variables when the trigger matches, then `cv.positive_time_period`; an error means no trigger) | `this` in trigger templates (its value depends on HA's startup phase), other sun events (dawn, dusk, noon, elevation, ...), `zone.entered`/`zone.left` and other new-style triggers, `homeassistant` with `event: shutdown` (a shutdown job, before any event the shell sees), device triggers, a `webhook` trigger whose id is templated in a `wait_for_trigger` or reads states or the clock, an `mqtt` trigger with another `encoding` (the protocol carries UTF-8 text) or with a payload that reads as a bytes literal (`b'...'`), or whose topic or payload is templated in a `wait_for_trigger`, or whose payload template reads states or the clock, a templated `time` `at` or event trigger that reads states, the clock or the time zone, or is in a `wait_for_trigger`; an event trigger's `context` (the protocol sends no event context), an event trigger on `state_changed` (HA delivers every entity's changes to it, its own automation entities' state writes included), a list inside nested `event_data` |
| Conditions | `and`/`or`/`not` (incl. shorthand), `state` (match any/all in any case, `state` a string or list of strings unless an `attribute` is given, values compared by Python's `==`, `for` (templates too, rendered when checked; `for` with an attribute or an `input_*` state is refused, as HA's schema does), attribute, `input_*` references), `numeric_state` (incl. `value_template`), `time` (fixed, `input_datetime`, `time` entities, timestamp/uptime sensors, midnight crossing, weekday), `trigger`, `template` (incl. the `"{{ ... }}"` shorthand), `zone` (several entities and zones), `sun` (before/after sunrise/sunset with offsets, the night as before sunrise or after sunset, polar days), `enabled` (see Actions) | platform conditions |
| Automations | automation `variables` (rendered in order before conditions), `trigger_variables` (limited templates rendered when the triggers attach, then again with `variables` at each trigger), a trigger's own `variables` (rendered when it fires, seeing `trigger`; they win over the automation's); `this` in variables, conditions and actions (the automation entity's `state.as_dict()`: `entity_id` derived from the name like HA, `state`, `attributes` `id`/`last_triggered`/`mode`/`current`/`max`/`friendly_name`); names default to `automation <n>` like HA | `this` when the entity id needs transliteration (non-ASCII names, also for every later automation) or HTML entities, `trigger_variables` that use `this`, states or the clock, `variables` on a `wait_for_trigger`'s triggers |
| Actions | service call (blocking; static names lower-cased as HA does, or templated names; templates in `data`/`data_template` and `target`, or one template for the whole `data` or `target`; the action's own `entity_id`; `response_variable`, where a response that is not a dict fails the step as HA's `async_call` does), `stop` with `response_variable`, `delay` (static or templated), `condition`, `choose`, `if`/`else`, `repeat` count (`int()` of the value, else a template rendered when the step runs)/for_each/while/until with the `repeat` variable (assigning `repeat` inside a loop changes it until the next iteration, as HA's scoped variables do), `variables` (the run's `context` is set over an automation variable of that name), `stop` (+`error`), `event` (templates in `event_data` and the legacy `event_data_template`), `sequence`, `wait_template` (`timeout`, static or templated, `continue_on_timeout`, the `wait` variable; tracked like HA's `async_track_template`), `wait_for_trigger` (any supported trigger, seeing the run's variables; `timeout`, `continue_on_timeout`, `wait.trigger`), `parallel` (branches share variables except `wait`; errors and `stop` are raised once every branch is done), `continue_on_error`, `enabled` on triggers, conditions and actions (`cv.boolean` words and numbers, or a limited template, decided at load: a trigger's sees the static `trigger_variables` and a render error skips it, a condition's or action's sees no variables; a `parallel` branch's templated `enabled` is never rendered and the branch always runs, as in HA) | device actions, `scene` |
| Run modes | `single`, `restart`, `queued` (FIFO), `parallel`, `max`, conditions checked before admission | `max_exceeded` log levels |

### Templates (`HALean/Template/`)

A Jinja evaluator over Python-faithful values: `{{ 0.1 + 0.2 }}` prints
`0.30000000000000004`, `round(2.675, 2)` is `2.67`, and `1 == 1.0 == True`. Results
go through HA's `_parse_result` (`"42"` becomes `42`, `"[1, 2]"` becomes a list,
`"007"` stays a string).

| Supported | Rejected at load, stays in HA |
|---|---|
| `{{ }}`, `{% if/elif/else %}`, `{% for %}` (with `if`, `else`, `loop.*`, `break`/`continue`), `{% set %}` (incl. tuples), `namespace()`, comments, `-` whitespace control; all operators, chained comparisons, `x if c else y`, slices; `states(...)`, `states.domain.entity` / `states['...']`, iterating `states` / `states.light` (in HA's insertion order), `range` (`state`, `attributes`, `name`, `domain`, `object_id`, `entity_id`), `is_state`, `state_attr`, `is_state_attr`, `has_value`, `float`, `int`, `bool`, `is_number`, `iif`, `dict`; filters `round`, `default`, `lower`, `upper`, `title`, `capitalize`, `trim`, `replace`, `length`, `first`, `last`, `join`, `list`, `string`, `abs`, `sum`, `map` (filter or `attribute=`), `select`, `reject`, `selectattr`, `rejectattr`, `reverse`; `this` (the automation's own state, as `state.as_dict()`); collections: `sort` (`reverse`, `case_sensitive`, dotted and comma-separated `attribute`), `min`/`max` (filters, and HA's globals over several arguments or one iterable), `unique`, `expand` (groups and zones, in HA's stack order, recording what it read for template triggers); dates and times: `now()`, `utcnow()`, `today_at`, `timedelta`, `as_timestamp`, `as_datetime`, `as_local`, `timestamp_local`/`_utc`/`_custom`, datetime attributes, `strftime`, `replace`, `isoformat`, datetime/timedelta arithmetic, `strptime` (CPython's `_strptime` in the C locale), `as_timedelta`, `relative_time`, `time_since`, `time_until`, `timedelta_string`, the `datetime` test, `last_changed`/`last_updated`, `trigger.now`, `trigger.for`; common tests; str methods `split`, `strip`, `replace`, `startswith`, ...; the `trigger` variable for every supported trigger platform | any other global, filter or test, macros, `include`, `raw` |

Some values are reachable but not modelled yet (`last_reported`, `tzinfo`,
`strftime('%Z')`, `strptime`'s `%Z`, `%c`/`%x`/`%X`/`%r` and `%O` directives, `%z` offsets with
fractions of a second, non-ASCII text in `strptime` and `as_timedelta`). Printing a generator (`{{ xs | map('int') }}`) is also an error
here, where HA prints `<generator object ...>`. Using them is a render error in HALean,
so it is never a silent wrong answer. Case-changing filters on non-ASCII text are
also errors for now, and so are case-insensitive `sort`/`min`/`max`/`unique` over
non-ASCII strings (`str.lower()`) and sorting keys that are not totally ordered
(NaN: the result would depend on timsort's exact comparisons).

Upstream behaviours the translation keeps exactly, each covered by a scenario
in `tests/scenarios/`:

* A failing `condition` step ends only the sub-script it's in. Inside
  `choose`/`if`/`repeat`/`sequence`, the outer sequence carries on.
* `continue_on_error` swallows only `HomeAssistantError`. Config errors
  (`CONFIGURATION_ERRORS`: invalid data, template errors, condition errors such
  as a failing `wait_template` check) always stop the run, and other exceptions are converted only by the failing step's
  own flag.
* Conditions return true, false, `None` (disabled) or an error. `and`/`or`
  skip `None`, `not` treats it as false, and `if`/`while` treat an error as false.
* A queued run counts toward `max` while it waits, and `automation_triggered`
  fires on admission, before the run starts.
* `repeat` aborts after 10,000 iterations.

### State machine (`HALean/Core/StateMachine.lean`)

`homeassistant/core.py`'s `State` and `StateMachine` as a pure model:
`asyncSet : StateMachine → ... → (now : Int) → Except SMError (StateMachine × List SMEvent)`.
The clock is an argument (microseconds), and so are contexts; a context the
caller does not pass is a fresh symbolic ULID (`ulid:0`, `ulid:1`, ... in order).
`halean-core-states` runs it as JSON lines (one operation per line, the result
plus the events fired). `tests/differential/test_states.py` applies every
operation sequence in `tests/core/states/*.yaml` to HA's own `hass.states` and to
`halean-core-states`, and compares results and `state_changed`/`state_reported`
events (type, data, context, time fired, origin, in order) with their Python
types; HA's random ULIDs are renamed in order of appearance and must encode the
operation's clock.

| Supported | Rejected (`unsupported`), or not modelled |
|---|---|
| `async_set` (`str()` of the state, `validate_state`, lower-cased id, `attributes or {}`, `force_update`, `context`, `timestamp`), `async_set_internal` (over-long state → `unknown`), the report rule (same state and Python-equal attributes: only `last_reported` moves, the same object is reported, `state_reported` fires with `old_last_reported`), `last_changed` kept on attribute-only changes, equal attributes keep the old object (`{a: 1}` stays when `{a: 1.0}` is set), `valid_entity_id` (incl. the trailing newline `$` allows) for new entities, `async_remove`, `get` (with the lower-case retry), `is_state`, `async_entity_ids` / `_count` / `async_all` (no filter, a `str` filter lower-cased, an iterable not), the dict and domain-index order, `async_reserve` / `async_available`; `State`: `domain`, `object_id`, `name`, `last_*_timestamp`, `as_dict`, `as_compressed_state`, `Context._as_dict` | non-ASCII entity ids and domain filters (`str.lower()` and `\d` are Unicode-aware), `state_info`, non-JSON attribute values, `State.from_dict`, `__repr__`, `as_dict_json`/`json_fragment`, the thread-safe wrappers (`set`, `remove`, `entity_ids`, `all`) |

Known gaps: timestamps are whole microseconds (`timestamp = us / 1e6`, which
the harness passes explicitly); HA's `as_dict()` is cached and keeps a stale
`last_reported` after a report, where HALean's `asDict` is always fresh
(`test_as_dict_cache_is_stale_after_report` pins the upstream behaviour);
attribute dicts print with sorted keys; a JSON float written without a
fraction or exponent sign (`1e16`) reads as an int.
### Service registry (`HALean/Core/ServiceRegistry.lean`)

`hass.services` (`ServiceRegistry` in `homeassistant/core.py`) as a pure model.
`halean-core-services` takes one operation per JSON line (`register`, `remove`,
`has`, `supports_response`, `list`, `list_domain`, `call`, each with an explicit
`now`) and answers with the result or the exception, the events fired and the
`homeassistant.core` log records (format in `Exe/CoreServices.lean`).
Handlers are specs (return a value, echo the `ServiceCall`, raise an exception)
and schemas are `probatio` mapping schemas built from a spec, so behaviour is
observable.
Exceptions carry the same `error_kind` as the automation protocol's
`service_result`: `invalid` (`probatio.Invalid`), `ha_error`
(`HomeAssistantError` and subclasses), `other`.

`tests/differential/test_services.py` runs each case in
`tests/core/services/*.yaml` on a real `hass.services` (frozen clock) with
handlers and schemas built from the same specs, and on `halean-core-services`.
For every operation it compares the result (`repr()`), the exception (class,
`str()`, `error_kind`, translation key and placeholders), the events
(`service_registered`, `service_removed`, `call_service`: type, `repr()` of the
data, time fired, context) and warnings/errors logged. Random context ids are
compared structurally (`new`). Schemas are validated by `probatio`, a
dependency like Jinja2, so its version is pinned too (`upstream.probatio`,
0.13.0, checked by `test_probatio_matches_pin`); its translated functions are
in `manifest.yaml` as `probatio:<file>::<name>`, hashed by `tools/drift.py`
against the same pinned version.

**Schemas** (`HALean/Core/Probatio.lean`, `ConfigValidation.lean`,
`Schema.lean`). A spec (format in `HALean/Core/ServicesJson.lean`) is turned
into a real `probatio.Schema` by `tests/differential/schema_spec.py`, with the
real `config_validation` objects for `cv.*`, and decoded by HALean; both sides
validate the same data. `tests/core/services/validators.yaml` exercises every
validator on accepted, coerced and rejected input (result `repr()`, or the
exception class and `str()`, including paths such as `light.color.g`,
`rows[2].z`, `['odd key']['x.y']`, `<group>`). Errors are kept as probatio's
flattened `MultipleInvalid` leaves, so `Any` picks the deepest one exactly.

| Supported (exact) | Rejected (`unsupported`) |
|---|---|
| keys: `Required`, `Optional`, `Exclusive` (with `required=`, group defaults), `Inclusive`, defaults (validated through the value schema); extra policies, inherited by nested mappings; types `int` (a `bool` is one), `float` (the numeric tower: an `int` becomes a float), `str`, `bool`, `object`, `list`, `dict`, `timedelta`; scalar literals; nested mappings; list schemas `[v, ...]` (one element schema, several (the last error), none); `All`; `Any` (first match; "expected a or b" when every branch has a label, else the deepest error, first on a tie; "no valid value found"); `In` / `NotIn` (Python `==`, sorted member list as `sorted()` gives it or insertion order when it raises, the 40-member cap, "did you mean"); `Range` (`min`/`max`, `min_included`/`max_included`, "invalid value or type" for non-numbers); `Clamp`; `Length`; `Coerce(int)`, `Coerce(float)`, `Coerce(str)` (Python's `int()`/`float()`/`str()`, incl. the 4300-digit limit); `Lower`; `Upper`; `EnsureList`; `Port`; `AtLeastOne`. `cv.string`, `cv.boolean` (all spellings; the message shows the lowered, stripped text), `cv.positive_int`, `cv.positive_float`, `cv.small_float`, `cv.byte`, `cv.port`, `cv.ensure_list`, `cv.entity_id`, `cv.entity_ids` (comma lists, dict keys; a `TypeError` for a scalar escapes the schema, as upstream), `cv.comp_entity_ids`, `cv.entity_domain` (a domain or a list), `cv.color_hex`, `cv.slug`, `cv.time_period` (`_str`, `_seconds`, `_dict`), `cv.positive_time_period`, `cv.positive_time_period_dict` | `msg=` on any validator or marker; `Match`/`cv.matches_regex` (Python regex semantics); `In(fold_case=, space=)`; `Coerce` of other types; non-scalar literals and `In` members; type or callable keys, `Extra`, `Remove`, `Forbidden`, `Alias`, `Secret`, nested `Schema` objects with their own policy (except `time_period_dict`'s); `cv.percentage` (not in HA's `cv`), `cv.time`, `cv.date`, `cv.template`, `cv.url`, `cv.icon` and every other `cv.*`; at call time, data a text-handling validator reads that is not printable ASCII (Python's `str.lower()`, `strip()` and `int()` are Unicode-aware), a `timedelta` that would overflow or be NaN, `util.slugify` of text with HTML entities |

| Supported | Rejected (`unsupported`, nothing changes) |
|---|---|
| `async_register` (names lowercased, a service replaced in place, `service_registered`), `async_remove` (`service_removed`, empty domains dropped, a warning for an unknown service), `has_service`, `supports_response` (`KeyError` for a missing domain or service), `async_services` and `async_services_for_domain` (insertion order; the latter does not lowercase, like HA); `async_call`: lookup as given then lowercased, `ServiceNotFound`, the `return_response` rules (`blocking` needed, `NONE` refuses it, `ONLY` requires it), `target` merged into the data, schema validation (the subset above, probatio's error order and messages including the difflib "did you mean" hint and path rendering; another exception out of a validator propagates), `call_service` with the unvalidated data, handler errors raised when blocking and logged (with the `ServiceCall` repr) when not, the response must be a dict | non-ASCII domain or service names (`str.lower()` is modelled for ASCII), handler exceptions other than `HomeAssistantError`, `ServiceValidationError`, `Invalid`, `ValueError`, `RuntimeError`; validators outside the subset above; non-dict `data`/`target` |

Known gaps: handlers run to completion when called (job types and awaiting
are not modelled; a non-blocking call's handler finishes before `async_call`
returns, as HA's eager task does for a handler that never awaits). Here a
handler is a spec; handlers that set states, fire events or call services run
in the joined core (below), where `async_call` is the same
`Registry.prepareCall` / `finishCall` around a scripted handler; `Unauthorized` and cancellation in
background calls; the thread-safe wrappers (`register`, `remove`, `call`,
`services`) and `description_placeholders`; `repr()` of strings with
non-printable non-ASCII characters (Python escapes them, HALean does not);
`NaN`/`Infinity` in the input JSON.

### Core (`HALean/Core/Hass.lean`)

The three core services joined, as `homeassistant.core.HomeAssistant` wires
them: `Hass` holds the state machine, the bus and the registry, and every
event the state machine (`state_changed`, `state_reported`) and the registry
(`service_registered`, `service_removed`, `call_service`) fire goes through
the bus model, so `MATCH_ALL` and filtered listeners receive them with the
upstream payloads, contexts and order, and events fired during a dispatch are
queued as the bus does. Listeners and handlers are scripts over the whole core
(`Action`): fire, listen / listen once / unsubscribe, raise, set or remove a
state, call a service (blocking or not, nested), register or remove a service,
resolve a future, and in a coroutine `await asyncio.sleep(0)` or `await` a
future.

**Tasks and the event loop.** Listeners are `@callback`s or `async def`s;
handlers are `async def`s. A coroutine runs synchronously until it really
suspends, as upstream's eager tasks do: `async_run_hass_job` starts a
coroutine listener with `create_eager_task` inside the dispatch, a
non-blocking `async_call` starts its handler the same way
(`_run_service_call_catch_exceptions`), a blocking one awaits it in the
caller's own task, and a `@callback` listener's service call runs in an eager
task (`hass.async_create_task`). A suspension returns the coroutine's
remaining frames (`Res.susp`): they become a task in `hass._tasks`
(`Hass.tasks`), or suspend the caller. The loop is explicit and pure: a FIFO
ready queue (`Hass.ready`) of `Task.__step` / `__wakeup` handles,
done callbacks (`_tasks.remove`) and `asyncio.wait`'s `_on_completion`, run in
order (`BaseEventLoop._run_once`) whenever the operation itself, the main
task, is suspended: in a blocking call whose handler suspends, in `sleep`
(`await asyncio.sleep(0)`), or in `block_till_done`
(`hass.async_block_till_done()`: `sleep(0)`, then rounds of `asyncio.wait`
over `_tasks` until none is left). Futures (`loop.create_future()`, by name)
wake their waiters in the order they awaited. A task that ends with an
exception (only a coroutine listener's can: the others catch and record or
log) is never awaited, so CPython frees it when its last reference goes and
HA's loop exception handler logs `Error doing job: Task exception was never
retrieved` (logger `homeassistant`): at once for a task done during its
eager start, when its done callback has run otherwise, or, if
`async_block_till_done`'s `tasks` list holds it, when the next check drops
that list. The scheduler's theorems (FIFO, `block_till_done` leaves no
task) are in `HALean/Core/HassSchedProofs.lean`.

`halean-core` takes one operation per JSON line (`set`, `remove`, `get`,
`fire`, `listen`, `listen_once`, `unsub`, `listeners`, `register`,
`remove_service`, `has`, `call`, `resolve`, `sleep`, `block_till_done`, each
with the clock `now` in µs) and answers
with the result and one ordered trace: deliveries (`Event.as_dict()`, states
as `as_dict()`), the outcome of every scripted service call, and the
`homeassistant.core` and `homeassistant` log records (format in
`Exe/Core.lean`). `tests/differential/test_core.py` runs each
case in `tests/core/hass/*.yaml` on a real in-process `hass` (frozen clock;
`@callback` and `async def` listeners and `async def` handlers built from the
same scripts; HA's own loop exception handler from `homeassistant.runner`)
and on `halean-core`, and requires the same result and trace for every
operation. After each operation both sides run `block_till_done`, unless the
case is `manual` (then only its own `sleep` / `block_till_done` operations
and suspending blocking calls let the loop run, and the case must end with no
task left). Rejections HA cannot show (it would never return) are checked on
the model alone (`engine_only`). Random context ids are renamed `ctx#<n>` in
order of first appearance on both sides. The tests are sensitive to the
scheduler: making the ready queue LIFO fails all 15 async cases; freeing a
failed task at its done callback even while `async_block_till_done` holds it
fails 3; dropping `async_block_till_done`'s initial `sleep(0)` fails 1.

Types: one `Context` (`State.lean`) for states, bus and registry (the
registry's former `ServiceContext` is gone; a fresh `Context()` in the
standalone registry is written `new`). The bus's `Event` is the only
`homeassistant.core.Event`; what the state machine (`SMEvent`) and the
registry (`FiredEvent`, formerly its own `Event`) return are the
`async_fire_internal` calls they make, which the core turns into bus
`Queued` entries. `ServiceRegistry.async_call` is now
`Registry.prepareCall` + handler + `finishCall`, shared by the standalone
registry and the core. Listener and handler scripts are kept beside the bus
(by job key) and the registry (by service), so the separate models, their
executables, tests and proofs are unchanged.

| Supported | Rejected (`unsupported`), or not modelled |
|---|---|
| Everything the three separate models support, joined: `async_set` / `async_remove` fire through the bus (context and `time_fired` as upstream; `async_remove` without a context lets the `Event` make one); registering and removing services fire `service_registered` / `service_removed` (no context); `async_call` fires `call_service` with the call's context before the handler runs; while a dispatch runs, every event fired by a listener, by a handler that listener called, or by a state that handler set is queued and dispatched afterwards in FIFO order (the 10,000-events limit raises `HomeAssistantError` in the firing script, with upstream's message); a handler called when nothing is dispatching delivers its events before the call returns; listener scripts (`@callback`): fire, listen, listen once, unsubscribe, raise, set, remove, call (in a task started eagerly: its outcome is recorded and never reaches the listener; if the handler suspends, the call goes on in that task), register, remove a service, resolve a future; coroutine listeners (`async def`): the same, plus `await asyncio.sleep(0)` and awaiting a future, with calls awaited inline (errors propagate unless `catch`), started as eager tasks (synchronous prefix inside the dispatch; a task survives the listener's removal); handler scripts (`async def`, may suspend): the same, with nested calls awaited, then return a value / echo / raise; blocking calls await a suspended handler (the caller suspends, the loop runs other tasks in FIFO order), non-blocking ones return `None` and the handler goes on in its task; `hass.async_block_till_done()` (`block_till_done`) and `await asyncio.sleep(0)` (`sleep`) as operations; `inherit` passes the event's or the call's context on; listener errors logged as `Error running job`, non-blocking handler errors as `Error executing service` (when they happen, also after a suspension), a coroutine listener's as `Error doing job: Task exception was never retrieved` when the task is freed; filters as in the bus model | executor jobs (threads: their interleaving with the loop is not deterministic) and `@callback` handlers; `await` in a `@callback`; `asyncio.sleep` with a delay (timers); futures resolved twice (`asyncio.InvalidStateError`, whose name clashes with HA's) or with an exception; a `block_till_done` or blocking call that would never return (a task or the main task waiting on a future nobody resolves, endless rescheduling: more than 100,000 handles per operation); two failed tasks freed by the same `block_till_done` check (logged in `_tasks`'s set order); cancellation, `async_create_background_task`, `eager_start=False`, timeouts; the exceptions whose message is not modelled (`run_immediately`, non-`@callback` filters, `listen_once` with a filter, `state_reported` without one, event types over 64 characters); `time_fired` on a scripted fire; `eq` filters on `old_state` / `new_state` / `last_reported` / `old_last_reported` (State objects and datetimes); non-ASCII entity ids, domains and services; service calls nested deeper than 32 (HA would hit `RecursionError`); everything the separate models reject |

Known gaps: event data is compared as JSON (states as `as_dict()` taken
when the event is fired; within one operation the clock does not move, so a
later report cannot change `last_reported` of a state already queued);
Python's `RecursionError` is not modelled (rejected instead, see above); HA
listeners that exist before the model starts (`init`) are opaque, as in the
bus model (in the pinned release they are all `@callback`s, so they start no
tasks). The moment a failed task is logged follows CPython's reference
counting (when its last reference goes), which the model tracks for the
references HA itself holds (`_tasks`, the eager start's return value,
`async_block_till_done`'s list); a caller that kept a reference to the task
would delay the log. Only the main task's own `sleep(0)` and
`block_till_done` are operations: the loop never runs between two operations
on its own (as in the test, whose task does not yield in between), so a
task's resumption can wait across operations. The ready queue's FIFO order is
proved for the handles the model creates; I/O, timers and other HA tasks
that would interleave on a running instance are not modelled.

### Event bus (`HALean/Core/EventBus.lean`)

`hass.bus` (`EventBus`, with `Event`/`EventOrigin`/`Context` as far as the bus
needs them) as a pure model: `step : (now : Nat) → Bus → Op → Bus × Result`.
Listeners are abstract. Each records what it receives (`Event.as_dict()`) and
runs a scripted list of reactions on receipt (fire an event, listen, listen
once, unsubscribe, raise), optionally only for its first `react_times`
receipts, so every ordering decision of the bus can be observed.
`halean-core-events` takes one operation per JSON line (`listen`,
`listen_once`, `unsub`, `fire`, `listeners`, each with the clock `now` in µs)
and answers with the result, the deliveries in order and the errors logged
(format in `Exe/CoreEvents.lean`). `tests/differential/test_events.py`
runs each case in `tests/core/events/*.yaml` on HA's own `hass.bus` (frozen
clock, `async_block_till_done()` after every operation) and on
`halean-core-events`, starting the model from HA's current listener table.
The two must agree exactly on results, deliveries and the `homeassistant.core`
errors logged. Contexts HA creates have random ULIDs. They are compared as
`ulid@<ms>#<n>`: the ULID must encode the same millisecond, and the same events
must share one.

| Supported | Rejected (`unsupported`), or not modelled |
|---|---|
| `async_listen` (with `event_filter`: skipped without calling it when the data is `None`, exceptions logged; a non-`@callback` filter and `state_reported` without a filter raise; `run_immediately` raises), `async_listen_once` (removed before it runs; the `remove is None` guard; a filter is a `TypeError`), `MATCH_ALL` (after the specific listeners, never for `homeassistant_close`/`state_reported`, twice for an event of type `*`), `async_fire`/`async_fire_internal` (event type length in code points; listeners iterate over a snapshot, so listeners added during a dispatch miss that event and removed ones still get it; events fired during a dispatch are queued and dispatched afterwards in FIFO order with their fire time captured; the 10,000-events limit raises in the firing listener), `Event` created once per dispatch on the first listener that runs (`data or {}`, `time_fired or time.time()` with the float's µs rounding, a generated context's ULID millisecond), `as_dict`, `async_listeners` (dict order), unsubscribing (a double removal is logged and leaves an empty list behind through the `defaultdict`; `MATCH_ALL` is never dropped), listener exceptions logged | coroutine and executor listeners (only `@callback` listeners), the thread-safe wrappers (`fire`, `listen`, `listen_once`, `listeners`), `EventType` typing, `json_fragment`, `__repr__`, filters beyond equality / presence / constant / raising, non-object event data, contexts without an id |

Known gaps: the clock is whole microseconds and `time.time()` is
`sec + usec / 1e6` (the float freezegun returns); listeners that HA already had
when the model starts (`init`) receive events but are opaque (they do nothing);
`drain`'s bound (`_MAX_QUEUED_EVENT_DISPATCHES` rounds) is justified by the
queue limit but not proved yet.
### Scripts (`HALean/Script/`)

`halean-script` runs the scripts of a `scripts.yaml` (`object_id: config`)
as `script.<object_id>` entities, with the automation engine's executor: a
script entity is an `Automation` without triggers, and
`HALean/Script/Entity.lean` plans what each `script.*` service does, which
the engine carries out (`startScript`, `callLocal`, `stopRun` in
`Engine.lean`). Inputs are `init` (scripts as ordered `[object_id, config]`
pairs, `bridge/protocol.py` `protocol_scripts`), `call` (a blocking call of
`script.<service>`, answered by `call_done`), `reload`, and the engine's
`state_changed` / `event` / `tick` / `service_result`. Script entity states
come out as `set_state`.

| Supported | Rejected at load, stays in HA |
|---|---|
| `sequence` with every action automations support; `alias`, `icon` (an attribute), `description`, `fields` (metadata only: HA does not apply `default`s either), `variables` (rendered at each start on top of the run variables, which win; they see `this`), `mode`/`max`, `max_exceeded` (only logs); `this` (`state.as_dict()` before the run starts) and `context` (a `Context` whose ids are render errors; it equals no other value); calling `script.<object_id>` (blocking, the call data are the run variables, a target is merged in as HA's schema leaves it; `stop` + `response_variable` is the response, `{}` when falsy, an error for a caller asking for a response when it is not a dict); `script.turn_on` (starts the script, which runs up to its first wait before the call returns; `variables`), `script.turn_off`, `script.toggle` (targets by `entity_id`, `all`, `none`); scripts calling scripts, with the recursion guard (`script_stack`) for `restart`/`queued` scripts; the entity's state (`on` while it has runs) and attributes `last_triggered`, `mode`, `current`, `max`, `icon`, `friendly_name`; `script_started` events; errors of the called script raised in the caller's step (`continue_on_error` by kind), `stop` with `error: true` swallowed by the called script; stopping a run (`turn_off`, `restart`, reload) stops the scripts it waits for, and its caller gets `None` when it was stopped in a top-level delay, wait or `parallel` step and `CancelledError` elsewhere; a cancellation reaching a `parallel` branch ends only that branch; reload (unchanged scripts keep running, changed and removed ones are stopped, removed ones become `unavailable`, `last_triggered` is restored) | invalid configs (HA would make them unavailable entities), blueprints, `script.reload` actions, device/area/floor/label targets of `turn_on`/`turn_off`/`toggle`, `wait_template`/`wait_for_trigger` that mention script entities, the `trigger` condition, `last_action`, `last_triggered` other than `this.attributes.last_triggered`, templates using names that are not the script's fields or variables, a variable an action defines, or a variable another script passes when calling it |

Every scenario in `tests/script_scenarios/` (except `unsupported.yaml`)
also runs through HA's own `script` integration
(`tests/differential/test_scripts.py`), which must give the same service
calls, events, call outcomes and script entity states after every step.
Known gaps:

* **Bridge: scripts are called by HALean's automations, not by HA.** With
  `--scripts`, the bridge runs `halean-script` with both files, so the
  engine's automations call HALean's scripts. HA's WebSocket API cannot
  register services, so the UI and HA's own automations cannot call them
  (remove those scripts from HA's `scripts.yaml`). Script entity states are
  written over the REST API as plain states, without HA's entity registry.
* `last_action` is not modelled (rejected in templates, left out of the
  written state, opaque in `this`), and state writes do not notify
  listeners (waits on script entities are rejected). HA writes the state on
  every step; HALean only when the state or a modelled attribute changes.
* Turning on a script that does not start (`single` and running, at `max`,
  or a `variables` error) makes HA's `turn_on` wait for the script's next
  state write, whenever that is. HALean fails the call instead, with a log.
* When several outside calls end in the same step, the order they finish in
  (asyncio task wake-ups) is not modelled.
* Field selectors are not validated. Reload compares configs as sent, so
  reordering a script's `variables` counts as a change (HA compares dicts).

### Helpers (`HALean/Helpers/`)

`input_boolean`, `input_number`, `input_select`, `input_text`, `counter` and
`timer`, translated as pure state machines driven by their services. Each
helper has a file with its config schema (`CONFIG_SCHEMA` value schema and
its custom check, run with the probatio model of the service registry, so
error messages are HA's), its entity (state, attributes in HA's order, and
`async_added_to_hass` with restore) and its entity services (schema and
method). `Common.lean` holds what they share: `cv.schema_with_slug_keys`,
`cv.make_entity_service_schema`, target resolution, `Entity._stringify_state`
(`f"{x:.15}"` for floats, digit for digit), and the handler monad (`HM`: a
handler mutates its entity, writes states and fires events, and may raise
after a write, as upstream). `Component.lean` joins them: `Helpers.setup`
(`async_setup_component` with a YAML config and a restore cache),
`Helpers.call` (`ServiceRegistry.async_call` → `entity_service_call`: all
targets run, the first error is raised), `Helpers.tick` (the timers'
`async_track_point_in_utc_time` callbacks), and the state machine's view
(a write fires `state_changed` unless nothing changed; timers force it).

**Why a separate model and not services of the joined core (`Hass.lean`).**
The core's handlers are scripts over the core (fire, set, call...), chosen to
test the core's ordering; none holds the fields of an entity object
(`_attr_is_on`, `_remaining`, the input_text value that failed its pattern),
which is where a helper's state lives. So the helpers are, like scripts, their
own pure model with an explicit state, the clock as an argument, and their
effects as data, ready to be driven by the engine (see "What is left to
convert").

| Helper | Supported | Refused (`unsupported`) or not modelled |
|---|---|---|
| `input_boolean` | `name`, `initial`, `icon`; `turn_on`, `turn_off`, `toggle`; restore (`on` when no `initial`) | storage (UI) helpers, `reload` |
| `input_number` | `min`, `max`, `initial`, `step`, `mode`, `unit_of_measurement`, `icon`, `name` (`_cv_input_number`); `set_value` (`probatio.Invalid` outside the range), `increment`, `decrement` (Python's `min`/`max`, float arithmetic); the state as HA formats floats; restore (`float()` of the last state, within the range, else `min`) | storage helpers, `reload` |
| `input_select` | `options` (duplicates removed with a warning), `initial` (checked before), `icon`, `name`; `select_option` (`HomeAssistantError`), `select_first`/`last`, `select_next`/`previous` with `cycle`, `set_options` (duplicates refused; a lost current option falls back to the first, with a warning); restore | storage helpers, `reload` |
| `input_text` | `min`, `max`, `initial`, `pattern`, `mode`, `unit_of_measurement`, `icon`, `name` (`_cv_input_text`); `set_value` (wrong length: a warning, nothing written; a value not matching the pattern is stored, then the write raises `ValueError` and the state machine keeps the old state); an `initial` that does not match: the entity is not added; restore | patterns outside the regex subset of `HALean/Helpers/Pattern.lean` (lazy quantifiers, lookarounds, flags, backreferences, `\b`, ...); non-ASCII values against `\d \w \s`; storage helpers, `reload` |
| `counter` | `initial`, `minimum`, `maximum`, `step` (0 allowed), `restore`, `icon`, `name`; `increment`, `decrement`, `reset` (clamped), `set_value` (`ValueError` above/below the bounds or off-step, `ZeroDivisionError` for step 0); restore (`int()` of the last state, clamped) | a last state `int()` cannot read (HA fails to add the entity); storage helpers |
| `timer` | `duration` (every `cv.time_period` form; it goes through `_format_timedelta` and back, so `-0:00:05` becomes minus 1 h 59 min 55 s, as upstream), `restore`, `icon`, `name`; `start` (with `duration`; restart/resume), `pause`, `cancel`, `finish`, `change` (its three errors); `timer.started/restarted/paused/cancelled/finished/changed` events; attributes `duration`, `remaining`, `finishes_at`, `last_transition`, `restore`; the scheduled finish at the first clock at or after `finishes_at` (and right after a call that leaves it in the past) | restoring a paused or active timer; `reload` |

`halean-helpers` speaks JSON lines (`setup`, `call`, `tick`, see
`Exe/Helpers.lean`). `tests/differential/test_helpers.py` runs every case of
`tests/helpers/*.yaml` on a real HA (the integrations set up from YAML by
`async_setup_component`, `mock_restore_cache` for restores, a frozen clock)
and on `halean-helpers`, and requires after each step the same config errors
(`str()` of `CONFIG_SCHEMA`'s error), call errors (class and message),
`state_changed` events of the helpers and `timer.*` events (with `repr()` of
attributes and data, so `1` is not `1.0`), warnings, and states.

Known gaps:

* **Not connected to the automation engine yet**: an automation calling
  `input_boolean.turn_on` still goes to HA through the bridge.
* Only YAML helpers: storage helpers (created in the UI, `editable: true`),
  their WebSocket CRUD and `reload` are not modelled. Entity registry
  overrides (a name or icon set in the UI) are not either.
* Calls naming several entities: HA runs them in the order of a Python
  `set` (hash order, random per process); HALean runs them in the order
  given. Timers finishing in the same tick finish in entity order.
* Device, area, floor and label targets are refused (no registries).
* `input_datetime`, `group` and `schedule` are not translated yet.

## Proved so far (`HALean/Automation/Proofs.lean`)

`evalAnd_nil`, `evalOr_nil`, `evalCond_disabled`, `evalNot_disabled`,
`evalAnd_all_disabled`, `checkAutomationConditions_nil`, `testConditions_nil`,
`match_invert`, `match_all`, `single_exclusive`, `restart_never_rejects`,
`admit_bounded` (queued/parallel never exceed `max`), `queued_waits`, `templateCond_static`.

`HALean/Core/StateSpec.lean` (functions proved to compute what upstream
computes, see PROPERTIES.md): `validEntityId_iff`, `validDomain_iff`
(each accepts exactly the strings its regex matches), `splitEntityId_some`
(`str.partition(".")` with both sides non-empty).
`HALean/Template/PyIntSpec.lean`: `parseIntChars_iff` (Python's `int(str)` on
ASCII text is exactly its grammar; non-ASCII text is refused with an error).
`HALean/Template/ParseTimeSpec.lean`: `parseTimeSeconds_iff` (`parse_time`, which
`cv.time` uses, built on that `int()`).
`HALean/Template/SyntaxSpec.lean`: `isTemplateString_iff` (`is_template_string`).
`HALean/Template/CvBooleanSpec.lean`: `cvBooleanText_iff` (`cv.boolean` on strings).
`HALean/Automation/SlugifySpec.lean`: `slugify_fixed_iff` (what `cv.slug` accepts),
`slugifyChars_valid` (every non-empty `util.slugify` result is a valid slug).

`HALean/Template/Proofs.lean`: `render_static` (static templates are never
evaluated), `resultAsBoolean_none`, `cvBoolean_bool`, `iif_none`, `iif_truthy`.

`HALean/Core/Proofs.lean` (state machine): `set_same_only_reports` (same state
and attributes: only `last_reported` changes, only `state_reported` fires),
`set_same_state_keeps_last_changed`, `set_frame` (a set touches no other
entity), `set_keys` / `remove_keys` / `mem_domainEntityIds` (the ids of a
domain are exactly those set and not removed since), `remove_then_get_none`,
`reserve_then_unavailable`.

`HALean/Core/ServiceRegistryProofs.lean`: `has_after_register` (registration is
case-insensitive), `has_after_remove` and `call_after_remove_not_found` (after
`async_remove`, `has_service` is false and a call raises `ServiceNotFound`),
`call_none_return_response_errors`, `call_only_needs_return_response`,
`call_return_response_needs_blocking`; `wf_register`/`wf_remove` (keys stay
lowercase).

`HALean/Core/ProbatioProofs.lean` (schemas): `checkIn_ok_iff` / `checkNotIn_ok_iff`
(`In` accepts exactly the members of its container, under Python `==`, and
returns the value unchanged; `NotIn` exactly the non-members),
`checkRange_ok` / `checkRange_min` / `checkRange_max` / `checkRange_not_number`
(`Range` accepts only numbers within its bounds, unchanged, and never a string,
`None`, list or dict), `ensureList_is_list` / `ensureList_list`,
`checkCoerce_int` (`Coerce(int)` only produces ints), `checkPort_range`.

`HALean/Core/EventBusProofs.lean` (event bus): `once_at_most_once` (over any
sequence of operations, with any listener reactions, a `listen_once` listener
is delivered at most once), `gone_silent` (a listener that is out of the table
never receives anything again), `reachable_wf` (every bus reachable from
`Bus.new` is well formed), `unsub_gone_reachable` and `unsub_silent` (on any
reachable bus, unsubscribing takes the listener out of the table, and it
receives nothing over any later operations), `snapshot_match_all` / `snapshot_excluded` (a dispatch iterates over the
event type's listeners, then the `MATCH_ALL` ones unless the type is excluded).
`HALean/Core/HassProofs.lean` (joined core): `quiet` (while the bus is
dispatching, no script delivers anything: firing, setting or removing states,
calling services whose handlers do all of this again, registering services;
everything is queued and no `listen_once` listener is used up),
`dispatchLoop_deliveries` (a dispatch delivers the event to exactly the
snapshot listeners that pass their filter, once each, in order, whatever their
scripts do), `fireInternal_first` / `set_delivers_first` (when nothing is
dispatching, a successful `async_set`'s `state_changed` reaches exactly those
listeners before anything else is delivered).
`HALean/Script/Proofs.lean`: `callResponse_no_response`, `callResponse_dict`
(a caller asking for a response gets a dict or an error), `entityState_on`,
`stopped_nested_cancels`, `supportsMax_iff`.

## Known gaps and deviations

* **The translation is tested against Python, not proven equivalent.** All differential
  scenarios and all template cases match real HA at the pinned
  release, but they cover only the paths they exercise.
* Automation and script configs: HALean validates the keys it reads, as HA's
  schemas do, but mostly ignores keys it does not read, where HA refuses
  them (the exceptions: unknown time period units and `continue_on_error` on
  a `condition` action). Entity ids given as entity registry ids (uuids) are
  refused: HALean has no entity registry.
* Service schemas: the codegen path probatio switches a schema to after 50
  validations (`CompilePolicy.AUTO`) is not translated; it is meant to behave
  like the interpreted engine, which is what HALean follows and what the
  differential tests (few calls per schema) exercise. `Validator.run` is
  `partial`, so the proofs are about the leaf validators, not whole schemas.
* Lean's JSON objects are sorted by key. Where HA depends on the written
  order (`variables`), the shell sends ordered `[key, value]` lists
  (`bridge/protocol.py`). Elsewhere a dict printed by a template, such as
  `{{ trigger.event.data }}`, lists its keys sorted, not in arrival order.
* `expand` also expands entities that the `group` integration provides in other
  domains (light groups, ...), which HA knows from `entity_sources`. HALean
  does not: a non-group entity with an `entity_id` attribute is a render error.
  An unavailable group-platform entity has no such attribute, so HALean returns
  it as a plain entity where HA drops it.
* Time zones: the engine knows the current UTC offset, not the zone
  database. `as_local` and friends use that offset, so instants on the other
  side of a DST change are off by the DST difference. Zone names
  (`strftime('%Z')`, `tzinfo`) are errors.
* HA fires time and time-pattern triggers at a random 50-500 ms into the
  second; `trigger.now` in HALean is 500 ms in, but the run starts at the
  whole-second tick, so `now()` there can be up to 0.5 s earlier than
  `trigger.now`.
* Floats sent on as JSON lose their trailing `.0` (`20.0` arrives as `20`).
  HA's own service schemas coerce these, and Python compares them as equal.
* Callbacks run in a fixed order (automations in config order, then triggers in
  order), which models HA's eager-task scheduling. Timing races between
  separate HA tasks are not modelled.
* Time triggers and the ends of delays happen on whole seconds as ticks
  arrive, so a 0.7 s delay lasts about 1 s. If the bridge stalls,
  catch-up is limited to one day.
* `wait.remaining` after a wait step with a `timeout` was woken up is
  `timeout_handle.when() - loop.time()` in HA, a reading of the event loop's
  clock. Using it is a render error in HALean. Before the wait, without a
  timeout, and after a timeout it is exact (`timeout`, `None`, `0.0`).
* `parallel` branches, and the step after them, start once the callbacks of
  the current input are done (`asyncio.gather` does not start its tasks
  eagerly), so another automation triggered by the same event runs first.
* A run woken by its `wait_template` or `wait_for_trigger` continues after every automation the
  same state change triggered has run up to its first wait, as HA's task
  scheduling does.
* A `sun` trigger fires at the first whole-second tick at or after the
  event (HA's timer fires at the exact microsecond). The event times
  themselves match astral to the microsecond (`tests/sun/compare.py`).
  Only the current UTC offset is known, so near a DST change the local date
  used to look up the next event can differ from HA's.
* `STEP_FUEL` (1M steps per drive) is a safety net HA doesn't have. HA would
  block its event loop instead.
* The run handlers and timer loops are total but run on fuel (`ENGINE_FUEL`,
  `LOOP_FUEL`): a chain of nested handler calls deeper than 10,000, or more than
  100,000 timer rounds within one input, is cut off with an error log. HA has
  no such limits.
* `this` describes the automation entity HA would create for the automation.
  When the bridge runs an automation, HA has no such entity, so HALean derives
  it the way HA would: the entity id comes from the name, de-duplicated only
  against the other configured automations and the states known at startup
  (not against other HA entities or registry entries); the state is always
  `on`; `current` and `last_triggered` come from the engine's own runs. Its
  `last_changed`, `last_updated`, `last_reported` and `context` are render
  errors. `last_triggered` of a run started by a timer is the whole-second
  tick, like `now()` (see above).
* A templated `for:` that renders to 0 starts its run right after the state
  change, as `async_call_later(hass, 0, ...)` does on a real event loop. The
  differential harness cannot check this (its frozen monotonic clock delays
  0 s timers to the next time change), so `templated_for_zero` is engine-only.
* A `homeassistant` start trigger fires on the first `homeassistant_started`
  event the engine gets. The bridge connects to a running HA, so it only sees
  that event if it was connected while HA started; HA itself fires the
  trigger for automations loaded before startup finished.
* The bridge is unverified. It subscribes to events after `get_states`, so a
  change in that window can be missed at startup.
* The bridge learns a failed call's exception from HA's WebSocket error code
  and translation key: `invalid_format` (`probatio.Invalid`), `not_found`
  (`ServiceNotFound`), a nested `ServiceNotFound` and a response-support
  mismatch are configuration errors, which `continue_on_error` never
  swallows; every other `home_assistant_error` is a `HomeAssistantError`. A
  `TemplateError`, `InvalidEntityFormatError` or `NoEntitySpecifiedError`
  raised inside the called service arrives as a plain `home_assistant_error`,
  so `continue_on_error` swallows it where HA would not.
* MQTT through the bridge: when an automation or script has an `mqtt` trigger,
  the bridge subscribes to `#` (plus `$<level>/#` for each `$` topic a trigger
  names) with HA's `mqtt/subscribe` WebSocket command (admin token), so HA's
  broker connection delivers every message, and the engine matches them
  against its triggers. Compared with HA's own subscriptions: retained
  messages arrive once, when the bridge subscribes, so a `wait_for_trigger`
  that subscribes later does not get the retained message HA's broker would
  resend; the delivered `qos` is capped by the bridge's subscription (the
  highest `qos` a trigger asks for), not by each trigger's; and HA forwards a
  payload that is not UTF-8 as the text `b'...'`, which the engine takes as the
  payload where HA's trigger would drop the message. Several triggers on the
  same exact topic run in subscription order; HA keeps them in a set, so its
  order among them is not defined.
* Webhooks through the bridge: HA receives webhook requests itself, and its
  WebSocket API can only send one in (`webhook/handle`), not report them, so
  the bridge cannot feed `webhook` triggers. It warns about automations that
  have one; keep those in HA. A shell that receives the requests itself can
  send the protocol's `webhook` input (`bridge/protocol.py` `webhook_input`
  turns a raw request into it the way aiohttp parses it; multipart bodies are
  not supported, and the query is split with `urllib.parse.parse_qsl`, which
  agrees with yarl on ordinary query strings).
* A webhook's `trigger.data` and `trigger.query` are `MultiDictProxy` objects:
  HALean reads a key (`trigger.query.q`, `trigger.data['a']`: the first
  value), `in` and truthiness; their methods (`get`, `items`, ...),
  iterating, `length` and printing them are render errors.

## What is left to convert

HALean covers 402 upstream functions (`manifest.yaml`), 53 of them proved.
What is still missing, roughly in order of value:

1. **What makes real automations fail to load today.**
   * Trigger platforms: `homeassistant` shutdown,
     `calendar`, `persistent_notification`, `conversation`, `device`
     (device triggers come from each integration, so they are the hardest).
     All of these need input the shell does not send yet: calendar events,
     notifications, conversation sentences, a shutdown signal. (`mqtt` and
     `webhook` are translated, with the protocol inputs `mqtt` and `webhook`;
     the bridge feeds MQTT messages from HA's `mqtt/subscribe`, but it cannot
     see webhook requests, which HA receives itself.)
   * Templates are taken everywhere HA takes them, except in a
     `wait_for_trigger`'s triggers, whose limited templates (`enabled`, an
     event trigger's type and data, a time trigger's `at`) and own
     `variables` see the run's variables, so they cannot be rendered at load,
     and except limited templates that use `this`, states, the clock or the
     time zone.
   * Event triggers with `context`: the shell would have to send each
     event's context (user, parent).
2. **HA's helper entities as state machines.** `input_boolean`,
   `input_number`, `input_select`, `input_text`, `counter` and `timer` are
   translated (`HALean/Helpers/`, above). Left: connecting them to the engine
   (route the engine's calls of their services to `Helpers.call`, and feed the
   writes and `timer.*` events back as the engine's `state_changed` / `event`
   inputs, the way script entities are run in `Engine.lean`), so that an
   `automations.yaml` and the helpers it drives form a closed system, which is
   what user-level properties need (next steps, item 3); then `input_datetime`,
   `schedule` and `group` (which would also let `expand` see groups in other
   domains, known gaps).
3. **Pure utility code.** `util/color.py` (the `light` color conversions, with
   round-trip proofs); time zones in `util/dt.py` (a zone database, to fix the
   DST deviation above); probatio's compiled schema path, so that whole
   schemas can be proved.
4. **Proofs about what is translated** (more in [PROPERTIES.md](PROPERTIES.md)):
   `queued` runs in arrival order, `restart` leaves the newest run, and the run
   bound with script entities.

## Next steps

Properties worth proving or model-checking are collected in
[PROPERTIES.md](PROPERTIES.md).


1. Generate differential scenarios automatically (random automations within the supported
   subset plus random event sequences) to cover far more paths than hand-written ones.
2. Run-level properties: a `queued` automation runs in arrival order. (The run loop is
   total, and the run bound is proved: `runs_bounded` in
   `HALean/Automation/EngineBound.lean`.)
3. User-level properties over a whole `automations.yaml`: conflicting commands to the
   same entity, and trigger loops (an action that re-triggers itself).
4. Widen the subset: the other sun events and conditions (dawn, dusk, elevation).

## License

HALean is licensed under the Apache License 2.0 (`LICENSE`). It translates parts
of Home Assistant Core (Apache 2.0) and of probatio (MIT), Jinja2 (BSD 3-Clause),
astral (Apache 2.0), python-slugify (MIT) and CPython (PSF License). `NOTICE`
lists them, and their license texts are in `LICENSES/`.
