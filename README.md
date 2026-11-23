# HALean

Home Assistant's core, rewritten in Lean 4 one service at a time and translated
function by function, so it can be formally verified and still track upstream.

| Service | Lean | Executable | Status |
|---|---|---|---|
| Automation engine (triggers → conditions → actions, run modes) | `HALean/Automation/` | `halean-automation` | done, tested against real HA |
| Templates (Jinja) | `HALean/Template/` | `halean-template` (test driver) | subset done, used by automations, tested against real HA |
| Scripts | `HALean/Script/` | | planned |
| State machine (`hass.states`) | `HALean/Core/StateMachine.lean` | `halean-core-states` (test driver) | done, tested against real HA |
| Event bus (`hass.bus`) | `HALean/Core/EventBus.lean` | `halean-core-events` (test driver) | subset done (callback listeners), tested against real HA |
| Service registry (`hass.services`) | `HALean/Core/ServiceRegistry.lean` | `halean-core-services` | subset done, tested against real HA |

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
lake build                       # engine + all proofs
uv run tests/run_scenarios.py    # behaviour scenarios (engine only)
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
  /homeassistant/components/zone/ /homeassistant/components/sun/
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
| Triggers | `state` (from/to/not_from/not_to, attribute, `for`, explicit null `to`), `numeric_state` (below/above, entity bounds, attribute, `value_template`, `for`, arming), `template` (arming, `for`, re-rendered like HA's template tracker: only for what the last render read, every minute when it used `now()`, rate limits for loops over states), `time` (fixed or templated `at`: a limited template rendered with the static `trigger_variables`; `input_datetime` entities with a date or only a time, timestamp/uptime sensors, `offset`, weekday; rescheduled when the entity changes), `time_pattern`, `event` (flat `event_data`), legacy `zone` (enter/leave by coordinates, Vincenty distance like HA's, or a person's/device tracker's `in_zones`), legacy `sun` (sunrise/sunset with `offset`, astral's NOAA calculation at HA's location and elevation); `for:` static or templated (a template string or a mapping of templates, rendered with the trigger variables when the trigger matches, then `cv.positive_time_period`; an error means no trigger) | `this` in trigger templates (its value depends on HA's startup phase), other sun events (dawn, dusk, noon, elevation, ...), `zone.entered`/`zone.left` and other new-style triggers, `homeassistant`, `mqtt`, `webhook`, device triggers, a templated `time` `at` that reads states, the clock or the time zone, or is in a `wait_for_trigger` |
| Conditions | `and`/`or`/`not` (incl. shorthand), `state` (match any/all, `for`, attribute, `input_*` references), `numeric_state` (incl. `value_template`), `time` (fixed, `input_datetime`, `time` entities, timestamp/uptime sensors, midnight crossing, weekday), `trigger`, `template` (incl. the `"{{ ... }}"` shorthand), `zone` (several entities and zones), `sun` (before/after sunrise/sunset with offsets, the night as before sunrise or after sunset, polar days), `enabled: false` | platform conditions |
| Automations | automation `variables` (rendered in order before conditions) and static `trigger_variables`; `this` in variables, conditions and actions (the automation entity's `state.as_dict()`: `entity_id` derived from the name like HA, `state`, `attributes` `id`/`last_triggered`/`mode`/`current`/`max`/`friendly_name`); names default to `automation <n>` like HA | `this` when the entity id needs transliteration (non-ASCII names, also for every later automation) or HTML entities, templated `trigger_variables`, per-trigger `variables` |
| Actions | service call (blocking; templates in `data` and `target`; `response_variable`), `stop` with `response_variable`, `delay` (static or templated), `condition`, `choose`, `if`/`else`, `repeat` count (incl. templated)/for_each/while/until with the `repeat` variable, `variables`, `stop` (+`error`), `event` (templates in `event_data`), `sequence`, `wait_template` (`timeout`, static or templated, `continue_on_timeout`, the `wait` variable; tracked like HA's `async_track_template`), `wait_for_trigger` (any supported trigger, seeing the run's variables; `timeout`, `continue_on_timeout`, `wait.trigger`), `parallel` (branches share variables except `wait`; errors and `stop` are raised once every branch is done), `continue_on_error`, static `enabled` | templated action names, a whole-`data` template, device actions, `scene` |
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
`homeassistant.core` log records (format in `HALean/Core/ServicesMain.lean`).
Handlers are specs (return a value, echo the `ServiceCall`, raise an exception)
and schemas are flat `probatio` mapping schemas, so behaviour is observable.
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
0.13.0, checked by `test_probatio_matches_pin`).

| Supported | Rejected (`unsupported`, nothing changes) |
|---|---|
| `async_register` (names lowercased, a service replaced in place, `service_registered`), `async_remove` (`service_removed`, empty domains dropped, a warning for an unknown service), `has_service`, `supports_response` (`KeyError` for a missing domain or service), `async_services` and `async_services_for_domain` (insertion order; the latter does not lowercase, like HA); `async_call`: lookup as given then lowercased, `ServiceNotFound`, the `return_response` rules (`blocking` needed, `NONE` refuses it, `ONLY` requires it), `target` merged into the data, schema validation (`Required`/`Optional` with defaults, `int`/`float`/`str`/`bool`/`object`, `PREVENT`/`ALLOW`/`REMOVE_EXTRA`, probatio's error order and messages including the difflib "did you mean" hint and path rendering), `call_service` with the unvalidated data, handler errors raised when blocking and logged (with the `ServiceCall` repr) when not, the response must be a dict | non-ASCII domain or service names (`str.lower()` is modelled for ASCII), handler exceptions other than `HomeAssistantError`, `ServiceValidationError`, `Invalid`, `ValueError`, `RuntimeError`; schema types and validators beyond the five types (`cv.*`, `Coerce`, `In`, nested schemas, `Exclusive`, ...); non-dict `data`/`target` |

Known gaps: handlers run to completion when called (job types, awaiting, and
handlers that fire events or call services are not modelled; a non-blocking
call's handler finishes before `async_call` returns, as HA's eager task does
for a handler that never awaits); `Unauthorized` and cancellation in
background calls; the thread-safe wrappers (`register`, `remove`, `call`,
`services`) and `description_placeholders`; `repr()` of strings with
non-printable non-ASCII characters (Python escapes them, HALean does not);
`NaN`/`Infinity` in the input JSON.

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
(format in `HALean/Core/EventsMain.lean`). `tests/differential/test_events.py`
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

## Proved so far (`HALean/Automation/Proofs.lean`)

`evalAnd_nil`, `evalOr_nil`, `evalCond_disabled`, `evalNot_disabled`,
`evalAnd_all_disabled`, `checkAutomationConditions_nil`, `testConditions_nil`,
`match_invert`, `match_all`, `single_exclusive`, `restart_never_rejects`,
`admit_bounded` (queued/parallel never exceed `max`), `queued_waits`, `templateCond_static`.

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

`HALean/Core/EventBusProofs.lean` (event bus): `once_at_most_once` (over any
sequence of operations, with any listener reactions, a `listen_once` listener
is delivered at most once), `gone_silent` (a listener that is out of the table
never receives anything again), `unsub_gone` (running a remove callback takes
the listener out of the table, given that it is stored once under its event
type), `snapshot_match_all` / `snapshot_excluded` (a dispatch iterates over the
event type's listeners, then the `MATCH_ALL` ones unless the type is excluded).

## Known gaps and deviations

* **The translation is tested against Python, not proven equivalent.** All differential
  scenarios and all template cases match real HA at the pinned
  release, but they cover only the paths they exercise.
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
* `drive`/`finishRun`/`fireDue` are `partial`, so nothing has been proved about
  them yet. Making them total with explicit measures is the next proof step.
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
* The bridge is unverified. It subscribes to events after `get_states`, so a
  change in that window can be missed at startup.

## Next steps

Properties worth proving or model-checking are collected in
[PROPERTIES.md](PROPERTIES.md).


1. Generate differential scenarios automatically (random automations within the supported
   subset plus random event sequences) to cover far more paths than hand-written ones.
2. Make the run loop total and prove run-level properties: a `single` automation never has
   two live runs, and a `queued` one runs in arrival order.
3. User-level properties over a whole `automations.yaml`: conflicting commands to the
   same entity, and trigger loops (an action that re-triggers itself).
4. Widen the subset: the other sun events and conditions (dawn, dusk, elevation), templated `trigger_variables`.
