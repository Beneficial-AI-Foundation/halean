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

These are about single functions (e.g. the admission decision `admit`), not
yet about whole executions of `Engine.step`.

## Engine properties (true for every configuration)

The main obstacle for most of these: `drive`, `finishRun` and `fireDue` in
`Engine.lean` are `partial`. Making them total, with an explicit measure, is
probably the first step.

1. **`single` really is single.** For any input sequence, an automation with
   `mode: single` never has two live runs (`runsOf`: the runs in
   `Engine.runs` that are not `parallel` branches). Lifts
   `single_exclusive` from `admit` to all reachable states.
2. **`max` is respected.** For `queued` / `parallel`, the number of live runs
   of an automation never exceeds `max`.
3. **`queued` is first-in, first-out.** Queued runs start in the order their
   triggers arrived.
4. **`restart` leaves one run.** After a restart, only the newest run of that
   automation is live.
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
services, listen, unsubscribe). Everything runs inside one fuel-bounded mutual
recursion (`fireInternal`, `dispatchLoop`, `drain`, `runJob`, `runActions`,
`runAction`, `callService`); "not rejected" means the output has no
`Entry.unsupported` (fuel or call depth). Proved in
`HALean/Core/HassProofs.lean`:

| Theorem | Says |
|---|---|
| `quiet` | while the bus is dispatching, nothing a script does delivers an event, at any nesting: fires, state writes and removals, service calls (with their `call_service`, their handlers' state writes and nested calls), service (un)registration are all queued; the bus stays in its dispatch and no `listen_once` listener is used up |
| `runJob_deliveries` | a listener run during a dispatch delivers the event to itself only (unless opaque or a `listen_once` that already ran), and only uses up its own `listen_once` |
| `dispatchLoop_deliveries` | a dispatch delivers the one `Event` to exactly the `deliverable` listeners of the snapshot (filter passes; not a used-up `listen_once`), once each, in snapshot order |
| `fireInternal_first` | when nothing is dispatching, the deliveries of a fire start with exactly those deliveries (the event has the fired type, data and context); everything the listeners caused comes after |
| `set_delivers_first` | the same for a successful `async_set`: its `state_changed` (or `state_reported`) reaches each matching listener present when it is fired exactly once, before any cascade |

Next candidates: a handler's state write called (blocking) when nothing is
dispatching is delivered before `async_call` returns; FIFO order of the queue
across services (the events queued during a dispatch are delivered in the
order their `async_fire_internal` calls happened, including those of nested
handlers); the bus well-formedness invariant (`reachable_wf`) for every
reachable core, which would drop the opaque-listener caveats.


```bash
lake build                          # builds the engine and checks all proofs
uv run tests/run_scenarios.py       # engine scenarios
uv run tests/differential/run.py    # the same scenarios against real Home Assistant
```

See the README for setup (Lean toolchain path, upstream checkout).
