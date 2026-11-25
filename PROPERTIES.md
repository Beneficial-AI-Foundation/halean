# Properties worth verifying

A starting list of properties for HALean, for anyone who wants to prove or
model-check them. Contributions and better ideas are very welcome.

## The model in one paragraph

The automation engine is one pure function:

```lean
Engine.step : Engine → Input → Engine × List Cmd      -- HALean/Automation/Engine.lean
```

`Input` is everything Home Assistant tells the engine: initial states and
automations, state changes, events, clock ticks and service-call results.
`Cmd` is everything the engine asks HA to do: call a service, fire an event,
or log. The engine never does I/O and never reads a clock, so any run can be
replayed and reasoned about as a sequence of `Input`s. Automations are parsed
from the user's own `automations.yaml` (`decodeAutomation` in
`HALean/Automation/Config.lean`), the same file HA's visual automation editor
writes.

How faithful the model is: every translated function maps to its upstream
Python function in `manifest.yaml`, and the behaviour is checked against the
real Home Assistant (release 2026.10.4) by differential tests. It is **tested**,
not **proven**, equivalent to HA. The README lists the known gaps.

## Already proved

In `HALean/Automation/Proofs.lean` and `HALean/Template/Proofs.lean`:

| Theorem | Says |
|---|---|
| `single_exclusive` | `single` mode admits a new run only when none is running |
| `restart_never_rejects` | `restart` mode never rejects a trigger |
| `admit_bounded` | `queued` / `parallel` admission never exceeds `max` |
| `queued_waits` | `queued` with a run in flight queues instead of running in parallel |
| `evalAnd_nil`, `evalOr_nil`, `evalNot_disabled`, `evalAnd_all_disabled`, ... | edge cases of HA's three-valued conditions (true / false / `None` for disabled) |
| `match_invert`, `match_all` | `not_to` is exactly the complement of `to`; no `from`/`to` matches everything |
| `render_static`, `templateCond_static` | a template without `{{ }}`/`{% %}` is never evaluated |
| `has_after_register` (`HALean/Core/ServiceRegistryProofs.lean`) | service registration is case-insensitive: after registering `Light.Turn_On`, `has_service` is true for every spelling with the same lowercase form |
| `has_after_remove`, `call_after_remove_not_found` | after `async_remove`, `has_service` is false and `async_call` raises `ServiceNotFound` (lowercased names), fires no event and logs nothing |
| `call_none_return_response_errors`, `call_only_needs_return_response`, `call_return_response_needs_blocking` | the `return_response` rules of `async_call`: each violation raises `ServiceValidationError` before the schema, the event or the handler |
| `wf_register`, `wf_remove` | every reachable registry has only lowercase domain and service keys (the invariant the call theorems assume) |
| `checkIn_ok_iff`, `checkNotIn_ok_iff` (`HALean/Core/ProbatioProofs.lean`) | a schema's `In` accepts exactly the members of its container (Python `==`, so `True` is a member of `[1]`) and returns the value unchanged; `NotIn` exactly the non-members |
| `checkRange_ok`, `checkRange_min`, `checkRange_max`, `checkRange_not_number` | `Range` never accepts a number outside its bounds (inclusive or exclusive), nor a value that is not a number, and returns what it accepts unchanged |
| `ensureList_is_list`, `checkCoerce_int`, `checkPort_range` | `EnsureList` always yields a list; `Coerce(int)` only yields ints; `Port` only ints from 1 to 65535 |

These are about single functions (e.g. the admission decision `admit`). The
first theorem about whole executions of `Engine.step` is in
`HALean/Automation/EngineBound.lean`:

| Theorem | Says |
|---|---|
| `runs_bounded` | start the engine with `init` (automations with `max ≥ 1`, no script entities) and feed it any inputs: a `single` or `restart` automation has at most one live run, a `queued` or `parallel` automation at most `max` (live = running or queued, `parallel` branches excluded) |
| `Inv.step`, `Inv.steps` | the invariant behind it (no script entities, every automation within its bound) holds after any input and any sequence of inputs |
| `HPres.engine` | every run handler (`drive`, `finishRun`, `releaseQueue`, `finishBranch`, `answer`, `continueNow`, `stopRun`, `cancelRun`, `startScript`, `callLocal`) keeps the invariant, at every nesting depth |
| `Inv.admitted`, `Inv.restarted` | `triggerAutomation`'s admission keeps the bound: without `restart` one run is added below the bound; with `restart` the new run is added and every older run of the automation removed |

The bound needs `max ≥ 1`. HALean did not enforce that until the proof was
attempted: the automation decoder took the JSON number's mantissa, so `max: 0`
or `max: -4` gave 0, with no limit at all (`admit` only rejects at
`existing = max`, which a running automation never reaches). `max: 2.5` gave 25,
`10.0` gave 100, and a string such as `"3"` was ignored (10). HA validates `max`
with `probatio.All(probatio.Coerce(int), probatio.Range(min=2))`
(`helpers/script.py` `make_script_schema`), and both the automation and the
script decoders now do the same (`maxRunsOf`, `pyIntOfJson?` in
`Automation/Config.lean`): 2.5 → 2, `"3"` → 3, and 0, 1, -4, `true`, `null` and
`"2.5"` are refused. This matches HA 2026.10.4's schema on each of those values
(checked by running `make_script_schema`). The script decoder had refused 2.5,
which HA accepts as 2.

The proof needed the engine to be total. The ten mutually recursive run
handlers take one another as a `Handlers` record, one level down; `handlers n`
nests them `n` levels deep and `engine = handlers ENGINE_FUEL` (opaque, so the
kernel never unfolds it). The timer and wake-up loops take fuel
(`LOOP_FUEL`), and `familyOf` / `rootOf` take `runs.length + 1`. When fuel runs
out, the engine logs an error and does nothing more.

## Functions proved to compute what upstream computes

The theorems above are properties. These go further: for a whole function,
what the upstream Python returns is written down as a Lean predicate (a
regex clause by clause, a string method's documented result), and the
translation is proved to decide exactly that predicate. The manifest marks
these entries `proven`. The remaining trust is in the predicate matching
Python, which is short enough to check by eye.

| Upstream function | Theorem (`HALean/Core/StateSpec.lean`) | Spec |
|---|---|---|
| `core.py::valid_entity_id` | `validEntityId_iff` | `EntityIdRe`: `^(?!.+__)(?!_)[\da-z_]+(?<!_)\.(?!_)[\da-z_]+(?<!_)$`, `$` also before one final newline |
| `core.py::valid_domain` | `validDomain_iff` | `DomainRe`: `^(?!.+__)(?!_)[\da-z_]+(?<!_)$` |
| `core.py::split_entity_id` | `splitEntityId_some` | `str.partition(".")`, `ValueError` (here `none`) when either side is empty |
| Python's `int(str)` (base 10), used by the `int` filter, `Coerce(int)`, `cv.time_period`, `repeat` counts | `parseIntChars_iff` (`HALean/Template/PyIntSpec.lean`) | whitespace (`Py_ISSPACE`), an optional sign, `digit (["_"] digit)*`, whitespace; ASCII text (non-ASCII is refused with an error) |
| `util/dt.py::parse_time` (`cv.time`: time triggers, time conditions, templates) | `parseTimeSeconds_iff` (`HALean/Template/ParseTimeSpec.lean`) | `str.split(":")`, `int()` of the first two or three parts (later ones ignored), `datetime.time`'s ranges |
| `helpers/template/__init__.py::is_template_string` (decides which config strings are templates) | `isTemplateString_iff` (`HALean/Template/SyntaxSpec.lean`) | `"{" in s and ("{%" in s or "{{" in s or "{#" in s)` |
| `helpers/config_validation.py::boolean` on strings (service schemas, template trigger results) | `cvBooleanText_iff` (`HALean/Template/CvBooleanSpec.lean`) | `value.lower().strip()` is one of the true / false words; `str.isspace` is the exact Unicode set |
| `helpers/config_validation.py::slug` (what it accepts) | `slugify_fixed_iff` (`HALean/Automation/SlugifySpec.lean`) | `""`, or non-empty `[0-9a-z_]` text without a leading, trailing or double `_`. Relative to `util.slugify` transcribed step by step from python-slugify's legacy pipeline (`slugifyChars`); also `slugifyChars_valid` (every non-empty slugify result is such a slug) |

`\d` is read as the ASCII digits; Python's class also has other Unicode
digits, which is why callers reject non-ASCII ids. The template engine uses
the same proved functions.

## Engine properties (true for every configuration)

`Engine.lean` has no `partial` definitions any more (see above), so these
can now be stated about `Engine.step`. Properties 1 and 2, and the "one run"
part of 4, are proved (`runs_bounded`) for engines without script entities.

1. **`single` really is single** (proved: `runs_bounded`). For any input sequence, an automation with
   `mode: single` never has two live runs (`runsOf`: the runs in
   `Engine.runs` that are not `parallel` branches). Lifts
   `single_exclusive` from `admit` to all reachable states.
2. **`max` is respected** (proved: `runs_bounded`). For `queued` / `parallel`, the number of live runs
   of an automation never exceeds `max`.
3. **`queued` is first-in, first-out.** Queued runs start in the order their
   triggers arrived.
4. **`restart` leaves one run.** After a restart, only the newest run of that
   automation is live. At most one run is proved (`runs_bounded`); that it is
   the newest is not.
5. **Every step terminates.** `Engine.step` returns for every input. Today a
   step budget (`STEP_FUEL`) guarantees this; the goal is to prove that the
   budget is never reached when `repeat` loops are bounded (HA stops `repeat`
   after 10,000 iterations).
6. **`parallel` joins.** A run waiting on its `parallel` branches continues
   only after every branch has ended, and stopping a run removes all of its
   branches and their listeners (`removeRun`, `finishBranch`).
7. **`continue_on_error` only swallows what HA says.** Errors of kind
   `haError` are swallowed by the nearest enclosing `continue_on_error`;
   `invalid` errors never are (`unwindError`, `resumeService` in `Script.lean`).
8. **Timers fire when they should.** A `for: N` trigger fires at the first
   clock tick at least `N` seconds after its condition became true (ticks are
   whole seconds), unless the condition broke in between, in which case it
   never fires.
9. **Determinism.** Two engines in the same state given the same input
   produce the same commands. This holds by construction (pure functions); it
   matters because it makes every recorded run replayable.
10. **Conditions.** Algebraic laws of the three-valued `and` / `or` / `not`,
   and where the usual laws fail. For example, a disabled condition counts as
   true inside `and` but as false inside `not` (`evalAnd_all_disabled`,
   `evalNot_disabled`), so De Morgan-style rewrites can change meaning.

## Setup properties (for one user's automations)

These are about a particular `automations.yaml`, the way a user would ask:

* "The heater is never on while the window is open."
* "No two automations send conflicting commands to the same light at the same
  time."
* "If motion stops, the hallway light is off within 10 minutes."
* "The battery never drops below 5%", even with several systems drawing from it.

The engine side is already a formal model: parse the user's automations and
run `Engine.step`. What is missing is a model of the **environment**: how
devices respond to commands and how the world changes (a battery draining, a
room cooling). Composing that with the engine gives a closed system whose
traces can be model-checked. The demo in `demo/` has a tiny, informal example
of such an environment: `demo/simulator.py` cools the room while the heater is
off and warms it while it is on.

## Templates

HA's Jinja templates (`HALean/Template/`) are translated too, with Python's
own semantics for numbers, strings and comparisons. Candidate properties:

* **Rendering always terminates** (today a step budget enforces it).
* **Results round-trip.** HA re-parses rendered text into values
  (`parseResult`); for example, rendering an integer and parsing it back gives
  the same integer.
* **Errors, not wrong answers.** Every value HALean does not model yet
  (datetimes, for instance) leads to an error, never to a different result.

## State machine

`HALean/Core/StateMachine.lean` is pure too: each operation maps a
`StateMachine` (and the clock) to a new one plus the events fired. Proved in
`HALean/Core/Proofs.lean`:

| Theorem | Says |
|---|---|
| `set_same_only_reports` | same state and Python-equal attributes (no `force_update`): the stored state is the old one with only `last_reported` moved, and the only event is `state_reported` |
| `set_same_state_keeps_last_changed` | setting the same state never moves `last_changed`, whatever the attributes |
| `set_frame` | a set stores the entity and changes no other entity |
| `set_keys`, `remove_keys`, `mem_domainEntityIds` | the entity ids (of a domain) are exactly those set and not removed since |
| `remove_then_get_none` | remove, then `get`, is `None` |
| `reserve_then_unavailable` | a reserved id is not available |

Next candidates: every stored entity id is valid and lower case (an invariant
of all operations); the domain index agrees with a separately maintained
per-domain dict, as upstream keeps it; event-level properties once the event
bus is translated (every `state_changed` carries the previous `new_state` as
its `old_state`).

## Service schemas

`HALean/Core/Schema.lean` runs a probatio schema (`Validator.run`, `partial`
for now); the leaf validators are total and proved in
`HALean/Core/ProbatioProofs.lean` (table above). Next candidates, once
`Validator.run` is total (structural recursion over the nested `Validator`):
a schema accepts its own output (idempotence; it fails upstream too when an
`Inclusive` key's default fills only part of its group, so the statement needs
that side condition); with `ALLOW_EXTRA` and only `Optional` keys without defaults, a
schema accepts every dict whose values pass (and returns it unchanged when no
validator coerces); `Any` with a single branch behaves exactly like that branch;
the error list of a failed mapping is ordered by data order, then schema order,
then groups.

## Event bus

`HALean/Core/EventBus.lean`: `step : now → Bus → Op → Bus × Result`, with
abstract listeners whose scripted reactions (fire, listen, unsubscribe, raise)
run inside the dispatch. Every delivery is recorded in `Bus.deliveries`.
Proved in `HALean/Core/EventBusProofs.lean`:

| Theorem | Says |
|---|---|
| `once_at_most_once` | from a new bus, after any sequence of operations, every `async_listen_once` listener has been delivered at most once (including when it is unsubscribed mid-dispatch, re-fires its own type, or the event type is `*`) |
| `gone_silent` | a listener that is not in the table (and whose key is never reused) receives nothing more, whatever happens next |
| `unsub_gone` | after its remove callback runs, a listener stored once under its own event type is out of the table |
| `reachable_wf` | every bus reachable from `Bus.new` satisfies `WF`: table keys were handed out already, no listener list repeats a key, and every stored remove callback `(et, k)` names a handed-out key whose listener sits only in the entry for `et` that `Table.get` finds (event types need not be distinct: `init` may repeat them) |
| `unsub_gone_reachable`, `unsub_gone_wf` | on any reachable (or well-formed) bus, running the remove callback stored under `id` takes its listener out of the table, with no further hypotheses |
| `unsub_silent` | from a new bus, after any operations, unsubscribing `id` means its listener receives nothing more and stays out of the table over any later operations |
| `snapshot_match_all`, `snapshot_excluded` | a dispatch iterates over the type's listeners, then the `MATCH_ALL` ones, except for `homeassistant_close` / `state_reported` |

Next candidates: (done: the well-formedness invariant behind `unsub_gone`
holds for every reachable bus, `reachable_wf` / `unsub_gone_reachable` /
`unsub_silent`); `drain` always empties the queue within
`_MAX_QUEUED_EVENT_DISPATCHES` rounds (so the fuel is never the reason it
stops); events fired during a dispatch are delivered in FIFO order after it.


## The joined core

`HALean/Core/Hass.lean` joins the three: the state machine and the registry
fire through the bus model, and listeners and service handlers are scripts
over the whole core (set or remove states, fire, call services, register
services, listen, unsubscribe, and in a coroutine `await asyncio.sleep(0)`
or a future). Everything synchronous runs inside one fuel-bounded mutual
recursion (`fireInternal`, `dispatchLoop`, `drain`, `runJob`,
`runListener`, `runActions`, `runAction`, `callService`); a coroutine that
suspends returns its remaining frames (`Res.susp`), which become a task
(`Hass.tasks`) or suspend the main task, and the event loop is explicit: a
FIFO ready queue of handles (`Hass.ready`: task steps and wakeups, the done
callback `_tasks.remove`, `asyncio.wait`'s `_on_completion`) run by
`runLoop` while the main task (the operation) is suspended. "Not rejected"
means the output has no `Entry.unsupported` (fuel, call depth, loop fuel, a
main task left waiting). Proved in `HALean/Core/HassProofs.lean`:

| Theorem | Says |
|---|---|
| `quiet` | while the bus is dispatching, nothing a script does delivers an event, at any nesting: fires, state writes and removals, service calls (with their `call_service`, their handlers' state writes and nested calls, and the tasks they start), service (un)registration, futures resolved are all queued; the bus stays in its dispatch and no `listen_once` listener is used up |
| `runListener_deliveries` | **eager start**: a listener run during a dispatch, `@callback` or `async def` alike, delivers the event to itself before the dispatch goes on, and nothing else; a coroutine's synchronous prefix runs at once, the rest waits in its task |
| `runJob_deliveries` | a listener run during a dispatch delivers the event to itself only (unless opaque or a `listen_once` that already ran), and only uses up its own `listen_once` |
| `dispatchLoop_deliveries` | a dispatch delivers the one `Event` to exactly the `deliverable` listeners of the snapshot (filter passes; not a used-up `listen_once`), once each, in snapshot order, coroutine listeners included |
| `fireInternal_first` | when nothing is dispatching, the deliveries of a fire start with exactly those deliveries (the event has the fired type, data and context); everything the listeners caused comes after |
| `set_delivers_first` | the same for a successful `async_set`: its `state_changed` (or `state_reported`) reaches each matching listener present when it is fired exactly once, before any cascade |

The statements are those of the core without tasks; none needed a new
hypothesis ("no async jobs" was not required). In
`HALean/Core/HassSchedProofs.lean`, about the scheduler:

| Theorem | Says |
|---|---|
| `keeps` | nothing synchronous (firing, dispatching, listeners, scripts, service calls, starting eager tasks, parking suspended ones, resolving futures) reorders the ready queue: it only appends to it, and the main task's frames are untouched |
| `runHandle_fifo`, `resume_main_fifo` | **FIFO**: when the loop pops a handle (a task's step, a done callback, `_on_completion`, or the main task's step) and runs it, the handles behind it stay in front of everything it queues, so a task resumed (by `sleep(0)` or a resolved future) runs before every handle queued later |
| `blockTillDone_no_tasks` | when `hass.async_block_till_done()` returns, no task is left in `hass._tasks` |

Next candidates: a handler's state write called (blocking) when nothing is
dispatching is delivered before `async_call` returns; FIFO order of the queue
across services (the events queued during a dispatch are delivered in the
order their `async_fire_internal` calls happened, including those of nested
handlers); the bus well-formedness invariant (`reachable_wf`) for every
reachable core, which would drop the opaque-listener caveats; after
`block_till_done` the ready queue is empty (needs the invariant "every step
or done handle names a task in `_tasks`"); every task's frames end in a
frame that swallows its error, except a coroutine listener's (so only those
log `Error doing job`).


```bash
lake build                          # builds the engine and checks all proofs
lake build halean-automation        # the executable the scenarios drive
uv run tests/run_scenarios.py       # engine scenarios
uv run tests/differential/run.py    # the same scenarios against real Home Assistant
```

See the README for setup (Lean toolchain path, upstream checkout).
