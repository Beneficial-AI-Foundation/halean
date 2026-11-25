# core-states-bus-hass

Modules: `HALean.Core.{EventBusProofs, EventBusSpec2, HassProofs, HassSchedProofs, HassSpec, Proofs,
StateMachineSpec, StateSpec, StateSpec2, TypesSpec}`. Implementation files: `HALean/Core/{Types, State,
StateMachine, EventBus, Hass}.lean`.

389 theorems. Classes (from `core-states-bus-hass.tsv`): C 6, O 130, E 28, H 225.

| module | C | O | E | H | total |
|---|---|---|---|---|---|
| EventBusProofs | 0 | 9 | 0 | 86 | 95 |
| EventBusSpec2 | 0 | 24 | 7 | 15 | 46 |
| HassProofs | 0 | 6 | 0 | 34 | 40 |
| HassSchedProofs | 0 | 4 | 0 | 22 | 26 |
| HassSpec | 0 | 14 | 5 | 27 | 46 |
| Proofs | 0 | 16 | 0 | 3 | 19 |
| StateMachineSpec | 3 | 16 | 7 | 10 | 36 |
| StateSpec | 3 | 0 | 0 | 14 | 17 |
| StateSpec2 | 0 | 20 | 3 | 8 | 31 |
| TypesSpec | 0 | 21 | 6 | 6 | 33 |

Checks run (read-only, `class/scratch/core_states_bus_hass_check.lean`): `#print axioms` of `unsub_silent`,
`blockTillDone_no_tasks`, `set_delivers_first`, `validEntityId_iff`, `set_same_only_reports` gives
`propext, Classical.choice, Quot.sound` only. No `sorry`, `axiom`, `native_decide` in the ten modules (grep).
Four `#eval` counterexamples used below were run there.

## What the theorems constrain

### `Types.lean`
* `States.get? / set / remove` (the automation engine's dict): `get?_set_same`, `get?_set_other`, `keys_set`,
  `length_set`, `set_set`, `get?_remove_same`, `get?_remove_other`, `keys_remove`, `remove_absent`,
  `get?_remove_set`. Together they fix lookups and key order after one write or one removal.
* `EntityState.attr? / hasAttr`: `hasAttr_iff` (restates the definition).
* `Instant.localMillis / timeOfDay / weekdayIdx / weekday`: `timeOfDay_eq`, `timeOfDay_lt`, `weekdayIdx_lt`,
  `weekday_mem`, `weekday_getElem`, `localMillis_offset`, `timeOfDay_add_day`, `weekdayIdx_add_day`,
  `weekdayIdx_add_week`, `localMillis_split`. With `epoch_thursday` (E) these fix the weekday for offset 0 by
  induction on days; no theorem states that induction.

### `State.lean`
* `valid_entity_id`, `valid_domain`, `split_entity_id`: `validEntityId_iff`, `validDomain_iff`,
  `splitEntityId_some` (C). The result is determined for every string.
* `State.domain / object_id`: `State.domain_dot_objectId`, `State.new_domain_dot_objectId`.
* `State.name`: `State.name_default`, `State.name_friendly`, `State.name_falsy` cover the three branches (the
  last two in terms of the opaque `truthy (Value.ofJson v)`), `State.name_congr`.
* `State.__init__` (`State.new`): `State.new_ok` (entity id and the `last_changed` default chain of a successful
  call), `State.new_domain_dot_objectId`.
* `Context._as_dict`, `State._as_dict`, `State.as_compressed_state`: `Context.asDict_fields`,
  `State.asDict_fields`, `State.asDict_report`, `State.asCompressedState_fields`,
  `State.asCompressedState_context_bare`, `State.asCompressedState_context_full`, `State.asCompressedState_lu`:
  the value read by `getObjVal?` for each named key. They do not state that there are no other keys, and no
  theorem states that `lu` is absent when the timestamps are equal.
* `State.toEntityState`: `State.toEntityState_fields`, `State.toEntityState_lastChanged`,
  `State.toEntityState_report`.
* `tsJson`: `tsJson_shape` (null or a number).

### `StateMachine.lean`
* `States.__setitem__ / __delitem__`: `lookup_setItem`, `lookup_setItem_other`, `lookup_delItem`, `keys_setItem`,
  `keys_delItem`.
* `async_set_internal`: `set_same_only_reports` (report branch: result and stored state, under
  `attrsEq ... = true`), `set_cases`, `set_same_state_keeps_last_changed`, `set_frame`, `set_keys`,
  `asyncSetInternal_events` (exactly one event, its time and context, one of two types),
  `asyncSetInternal_force_changed`, `asyncSetInternal_new_entity`.
* `async_set`: `asyncSet_too_long`, `asyncSet_non_ascii` (two error cases only).
* `validate_state`: `validateState_ok_iff` (C), `validateState_error`.
* `async_remove`: `remove_then_lookup_none`, `remove_then_get_none`, `remove_keys`, `asyncRemove_events`.
* `async_reserve / async_available`: `reserve_then_unavailable`.
* `domain_entity_ids / domain_states`: `mem_domainEntityIds`, `mem_domainStates`, `domainStates_domain`,
  `domainEntityIds_zip_domainStates`, `domainStates_length`, `domainStates_sublist`.
* `async_entity_ids / async_entity_ids_count / async_all`: `asyncEntityIdsCount_eq` (C, relative to
  `asyncEntityIds`), `asyncAll_length`, `asyncEntityIds_ok_iff`.
* `is_state`: `isState_eq` (C, relative to `get`), `isState_true_iff`, `isState_unique`.

### `EventBus.lean` (the stand-alone bus, driver `Exe/CoreEvents.lean`)
* Over `run Bus.new ops` (any operation list): `once_at_most_once`, `reachable_wf`, `unsub_gone_reachable`,
  `unsub_silent`. Over `run b ops` from any bus: `gone_silent`. On a well-formed bus: `unsub_gone_wf`. With three
  table hypotheses: `unsub_gone`.
* `snapshot`: `snapshot_match_all`, `snapshot_excluded`, `snapshot_eq`.
* `async_listeners`: `asyncListeners_keys`, `mem_asyncListeners`, `asyncListeners_lookup`,
  `asyncListeners_listen`, `asyncListeners_fireNested`.
* Errors of `async_fire`, `async_listen`, `async_listen_once`: `asyncFire_error_iff`, `asyncListen_error_iff`,
  `asyncListenOnce_error_iff`, `react1_fire_too_long`. The successful result is not characterised.
* Queueing during a dispatch (`fireNested`): `fireNested_ok_iff`, `fireNested_queued`, `fireNested_full`.
* `filterPasses`: `filterPasses_no_filter`, `filterPasses_no_data`, `filterPasses_data`, `filterPasses_error`.
* `mkQueued`: `mkQueued_fields`, `mkQueued_timeFired_none`, `mkQueued_timeFired_some`.
* `Event.as_dict`, `makeEvent`: `Event.asDict_fields`, `makeEvent_asDict`.
* `runJob`: `runJob_once_spent` (receipt count only).

All nine O theorems of `EventBusProofs` except the two `snapshot_*` ones are upper bounds or table facts. A bus
that never delivers anything satisfies all of them. No theorem states that a subscribed listener receives a fired
event in the stand-alone bus.

### `Hass.lean` (the joined core, driver `Exe/Core.lean`)
* While `bus.dispatching = true`: `quiet` (five functions deliver nothing, stay in the dispatch, use up no
  once-listener), `runListener_deliveries`, `runJob_deliveries`, `dispatchLoop_deliveries` (the delivery list of
  one dispatch equals the reference function `deliverable` applied to the job list, in order), all under
  `NoUnsup`.
* While `bus.dispatching = false`: `fireInternal_first`, `set_delivers_first` (the first deliveries of the output
  are those of the fired event; prefix only).
* During a dispatch: `fireInternal_nested`, `fireInternal_queue_full`.
* Scheduler: `keeps`, `runHandle_fifo`, `resume_main_fifo`, `blockTillDone_no_tasks` (see next subsection).
* Futures and tasks: `resolve_pending`, `resolve_twice`, `park_fut_pending`, `park_ready`, `spawn_ofExcept`,
  `spawn_susp`.
* Single actions: `runAction_wait`, `runAction_listen_ok`, `runAction_listen_error`,
  `callService_prepare_error`.
* Top level `step`: `step_reads`, `step_call_prepare_error`, `blockTillDone_no_tasks`.

### The scheduler theorems, exactly (`HassSchedProofs.lean`)
* `keeps (n : Nat)` (l. 94-103). No hypotheses. For every fuel `n` and all arguments, each of `fireInternal`,
  `fireList`, `dispatchLoop`, `drain`, `runListener`, `runJob`, `runActions`, `runAction`, `callService`
  returns a core `h'` with `h.ready <+: h'.ready` and `h'.mainCont = h.mainCont`.
* `runHandle_fifo (n now h x rest)` (l. 338-339). No hypotheses. Statement:
  `∃ added, (runHandle n now { h with ready := rest } x).1.ready = rest ++ added`. It is about one call of
  `runHandle`. It says nothing about `added`, and nothing about `runLoop`.
* `resume_main_fifo (n now h rest)` (l. 348-349). No hypotheses. Statement:
  `rest <+: (resume n now { h with ready := rest, mainCont := [] } h.mainCont (.ok .none)).1.ready`.
* There is no theorem named `runLoop_fifo`. The only theorems that mention `runLoop` are `runLoop_btd` and, through
  `step`, `blockTillDone_no_tasks`. No theorem states an execution order of handles over a run of `runLoop`.
  "A handle queued earlier runs before a handle queued later" follows from the three statements above plus the
  definition of `runLoop` (it always takes the head of `ready`); that step is not a theorem.
* `runLoop_btd (now)` (l. 360-364). Hypotheses: `h.mainCont = [.btdCheck]` and
  `runLoop fuel now h acc = (h', out, .ok v)`. Conclusion: `∀ t ∈ h'.tasks, t.inSet = false`.
* `blockTillDone_no_tasks (now h h' out r)` (l. 409-411). Hypothesis:
  `step now h .blockTillDone = (h', out, .ok r)`. Conclusion: `∀ t ∈ h'.tasks, t.inSet = false`.
  The hypothesis is "the operation returned a value". It excludes the three cases in which the model gives up
  (`loop fuel`, `the main task waits with nothing left to run`, `two task exceptions logged in set order`), which
  return `.error exhausted`. The conclusion does not say that the tasks are finished (`TaskRec.finished`), that
  `h'.tasks` is empty, or that `h'.ready` is empty. No theorem says when the operation returns a value. On
  `Hass.new` it does (`#eval` in the scratch file), so the statement is not vacuous.

## What they do not constrain

### `partial def`s
`logs/defs.tsv` lists one in the area: `HALean.Core.EventBus.pyEq` (EventBus.lean:388, Python `==` on JSON, used
by `evalFilter (.eq ..)`). No theorem statement mentions it. `evalFilter_eq_nil`, `evalFilter_eq_cons`,
`evalFilter_eq_has` hold for any function in its place; they say nothing about which values an `eq` filter
treats as equal.

Partial defs of other files that the area's code calls: `HALean.Template.pyEq` and
`HALean.Template.Value.ofJson` (Template/Value.lean). Theorems whose statements depend on them:
* `set_same_only_reports`: hypothesis `attrsEq o.attributes attrs = true` (`attrsEq` unfolds to
  `Template.pyEq (Value.ofJson _) (Value.ofJson _)`). It means: if the compiled comparison returns true, only a
  report happens. It cannot be used to show that setting identical attributes only reports, because
  `attrsEq a (some a) = true` is not provable for an opaque function.
* `asyncSet_too_long`: hypothesis `pyStr (Value.ofJson v) = .ok st`. Not provable for any concrete `v`.
* `State.name_friendly`, `State.name_falsy`: hypothesis on `truthy (Value.ofJson v)`. They restate the `if` of the
  definition; which JSON values are truthy is not constrained.
* `set_delivers_first`: hypothesis `asyncSet ... = .ok (sm, [ev])`; `asyncSet` calls `Value.ofJson`, so the
  hypothesis cannot be established inside Lean for a concrete input.
* Every theorem with a hypothesis `asyncSetInternal ... = .ok ...` for an existing entity holds for whatever
  `attrsEq` returns; none says which branch is taken for given attributes.

### JSON decoders, protocol drivers
The decoders and loops are in `Exe/CoreEvents.lean`, `Exe/Core.lean`, `Exe/CoreStates.lean` (`partial def
decodeListen`, `decodeReaction`, `decodeAction`, `decodeRegister`, `loop`). No theorem of these modules mentions
them. The driver's rejection of an operation whose output has an `unsupported` entry (`Exe/Core.lean:264`) is
code, not a theorem.

### Entry points
* `EventBus.step` / `run`: theorems exist about `run` itself, all of the invariant kind (`once_at_most_once`,
  `gone_silent`, `reachable_wf`, `unsub_gone_reachable`, `unsub_silent`). What `step (.fire f)` delivers, to whom
  and in which order, has no theorem. `dispatch`, `dispatchLoop`, `drain`, `callListener`, `runReactions` appear
  only in H lemmas (invariant preservation).
* `EventBus.drain`: no theorem states that the queue is empty after `asyncFire`, or that 10000 rounds suffice.
  At fuel 0 `drain` returns the bus with the remaining queue and no marker (EventBus.lean:473), unlike
  `Hass.drain`, which emits `unsupported "fuel"`.
* `Hass.step`: `step_reads` (`listeners`, `has`, `get`), `step_call_prepare_error` (one error path of `call`),
  `blockTillDone_no_tasks`. Nothing for `step (.act ..)`, `.sleep`, `.init`. `fireInternal_first` and
  `set_delivers_first` are about `fireInternal` / `runAction` at fuel `n+1` / `n+3` under
  `bus.dispatching = false`; no theorem connects them to `step` (through `drive`, `FUEL`).
* `Hass.runLoop`, `drive`, `runHandle`, `resume`, `endRound`, `startRound`, `finishTask`: only the ready-queue
  prefix property and `runLoop_btd`. What a resumed task does, when a task is finalised, which log entries are
  produced, are not constrained.
* The state machine has no single entry function; `Exe/CoreStates.lean` dispatches to the operations.

### Definitions with no C or O theorem
(From `logs/defs.tsv` joined with the statement constants of C/O theorems, then read by hand.)
* `Types.lean`: `parsePyFloatStr` (Python `float(str)`; no theorem at all), `pyFloat?` on strings (only the
  bool / number / non-scalar constructors, E), `EntityState.domain`, `String.trim`, `String.dropS`.
* `State.lean`: `tsFloat`, `isoUtc`, `lowerAscii`, `isAscii` (appear only as opaque terms or in hypotheses).
  `State.new`: the two error branches and the attribute default have no theorem. `State.asCompressedState`: the
  absence of `lu`.
* `StateMachine.lean`:
  * `asyncSetInternal`, change branch: no theorem states the stored state's `state` or `attributes`. `set_cases`
    quantifies them existentially (`∃ st' a lc v c, State.new eid st' a ...`). So "after a successful set of a
    new value, `get` returns that value", the 255-character replacement by `unknown`, and "equal attributes keep
    the old attribute object" are not theorems. Errors of `asyncSetInternal` (invalid id for a new entity): none.
  * `asyncSet`: nothing about a successful call (lower-casing of the id, `attributes or {}`, `str(new_state)`).
  * `get`: the lower-case retry is used only in `remove_then_get_none`.
  * `asyncRemove`: the returned Boolean is tied to the event count by `asyncRemove_events`; no theorem states
    that other entities' states are unchanged (only their keys, `remove_keys`), or what happens to reservations.
  * `asyncReserve`: when it raises. `asyncAvailable`: only after a reserve.
  * `asyncEntityIds`, `asyncAll`: order of the result (membership only, E theorems per filter constructor).
  * `SMEvent.dataJson`: no theorem. `SMEvent.toJson`: H only.
* `EventBus.lean`: `pyEq`, `roundHalfEven`, `ulidMillis`, `utcMicrosOfTimestamp`, `timestampOf`,
  `Event.timeFiredIso` (the float clock arithmetic: no theorem), `listenFilterableJob` beyond listener counts,
  `asyncRemoveListener`'s log entry and the re-created empty list, `dispatch`, `dispatchLoop`, `drain`,
  `callListener` (delivery order, `reactTimes`), `runReactions`, `initTable`, `step`, `run` (see above).
* `Hass.lean`: `FUEL`, `LOOP_FUEL` (no theorem), `runLoop`, `drive`, `endRound`, `startRound`, `finishTask`,
  `runHandle`, `resume` (queue-prefix facts only), `callService` on the success path (handler script, result,
  `finishCall`), `runAction` for `set` beyond the delivery prefix, for `remove`, `register`, `removeService`,
  `call`, `resolve`, `sleep`; `Hass.drain` (order in which queued events are delivered).

## Assumptions that nothing checks

| theorem | hypothesis | where the value comes from at run time | discharged by a theorem? |
|---|---|---|---|
| `fireInternal_first`, `set_delivers_first` | `h.bus.dispatching = false` | the driver's core: `Hass.new`, then the first component of each `Hass.step` | No. No theorem states that `step` (or `fireInternal`, `runLoop`) returns a core with `dispatching = false`, and no invariant over reachable cores exists. |
| `runListener_deliveries`, `runJob_deliveries`, `dispatchLoop_deliveries`, `fireInternal_first`, `set_delivers_first` | `NoUnsup` of the output (fuel, call depth, model limits not hit) | checked per operation by `Exe/Core.lean:264` (unverified driver code) | No theorem states that `FUEL` or `LOOP_FUEL` suffices for any class of inputs. |
| `quiet`, `runListener_deliveries`, `runJob_deliveries`, `dispatchLoop_deliveries` | `h.bus.dispatching = true` | set by `fireInternal` before the dispatch | Used inside the proof of `fireInternal_first` for the first dispatch. For the dispatches of queued events (`Hass.drain`) no theorem applies them. |
| `set_delivers_first` | `resolveCtx env c = some ctx` (a context is given); `asyncSet ... = .ok (sm, [ev])` | the decoded operation | No. A `set` without a context (the default call) is outside the theorem. The single-event shape follows from `asyncSetInternal_events`, but that link is not stated for `asyncSet`. |
| `blockTillDone_no_tasks` | `step now h .blockTillDone = (h', out, .ok r)` | the driver | No theorem says when this holds. Otherwise the driver rejects the operation. |
| `unsub_gone` | `(b.listeners.map (·.1)).Nodup`, `honly`, `hone` | the bus table | No. `Nodup` is false on a reachable bus after `init [("a",1),("a",1)]` (`#eval` gives `["a","a"]`). `remove_gone` / `unsub_gone_reachable` avoid the hypothesis. |
| `once_at_most_once`, `reachable_wf`, `unsub_gone_reachable`, `unsub_silent` | the bus is `run Bus.new ops` (stand-alone `EventBus.step`) | `Exe/CoreEvents.lean` folds `EventBus.step` from `Bus.new` | Holds for that driver if its `partial def loop` is a fold of `step`. Does not apply to the joined core: `Hass.step` uses its own `dispatchLoop`, `runJob`, `useOnce`, `removeListener`, and no `WF` / once-invariant is proved for reachable `Hass` values (PROPERTIES.md lists this as a next candidate). |
| `gone_silent` | `Gone k b` | the bus | Yes for a top-level unsubscribe on a reachable bus (`unsub_gone_reachable`). No theorem gives `Gone` for a once-listener after it ran. |
| `unsub_silent`, `unsub_gone_reachable` | `handles.lookup id = some (et, k)` | handle stored by `listenOp` | Not linked by a theorem to the listener name recorded in deliveries; `jobCount` counts by job key. `lookup` returns the newest handle for an id used twice. |
| `set_same_only_reports` | `attrsEq o.attributes attrs = true` | opaque `Template.pyEq` on the decoded attributes | No (partial def). |
| `asyncSet_too_long` | `pyStr (Value.ofJson v) = .ok st`, `isAscii eid` | decoded input | No (partial def). |
| `remove_then_get_none` | `lowerAscii eid = eid` | the caller's id | No. |
| `reserve_then_unavailable` | `isAscii eid`, `lowerAscii eid = eid` | the caller's id | No. Without it the conclusion is false: reserve `"Light.X"` on an empty machine, then `asyncAvailable "Light.X"` is `true` (`#eval`). Upstream behaves the same. |
| `mem_domainEntityIds`, `mem_domainStates`, `mem_asyncEntityIds_many` | none, but the domain is that of the stored state's `entityId`, not of the key | `sm.states` | No theorem states that a stored state's `entityId` equals its key, or that stored keys are valid and lower case. `set_internal` in `Exe/CoreStates.lean:119` passes the key unchecked. |
| `State.domain_dot_objectId` | `(splitEntityId s.entityId).isSome` | a stored state | Yes for states made by `State.new` (`State.new_domain_dot_objectId`). |
| `callService_prepare_error`, `step_call_prepare_error` | `a.context = some c` | decoded call | No theorem for a call without a context. |
| `EventBus.drain` (no theorem) | the queue is empty at the start of a top-level fire and at most 10000 events are queued | `queuedCount` reset in `asyncFire` | Not proved (README l. 475-476, manifest, PROPERTIES.md l. 277-279 say so). |

Vacuous or weaker than they read:
* `Context.eq_of_fields`: proves "equal fields give equal dicts" (congruence). The docstring claims the converse.
* `State.lastChangedTimestamp_eq_of_eq`, `State.lastReportedTimestamp_eq_of_eq`, `State.name_congr`: congruence
  facts; they hold for any function of those fields.
* `runHandle_fifo`: `∃ added, ready = rest ++ added`. One call; `added` unconstrained; no loop statement.
* `runListener_deliveries`: the statement is the same for `@callback` and coroutine listeners; it says nothing
  about a synchronous prefix or a parked task.
* `runJob_once_spent`: only the receipt counter of the job; not "does nothing".
* `step_reads`: for `get` only `(step ..).1 = h`; the output is not stated (and is not empty for a non-ASCII id).
* `blockTillDone_no_tasks`: `inSet = false` only (see above).
* `fireInternal_first`, `set_delivers_first`: list prefix (`<+:`); nothing about later deliveries.
* `quiet`, `keeps`: also hold for runs that end in `unsupported`; at fuel 0 they are trivial.
* `fuel_zero_unsupported`: fuel exactly 0; that the entry reaches the top-level output is not a theorem.
* `pyFloat?_num`: `(some _).isSome = true`.
* Restatements of the definition (proved by `rfl` or by unfolding one `if`/`match`): `State.timestamps_eq_tsFloat`,
  `State.toEntityState_fields`, `State.toEntityState_report`, `smQueued_eq_mkQueued`, `firedQueued_eq_mkQueued`,
  `smQueued_timeFired`, `ensureEvent_some`, `pyFloat?_bool`, `pyFloat?_num`, `evalFilter_const`,
  `evalFilter_eq_nil`, `asyncListeners_new`, `receivedOf_new`, `futOf_new`, `findTask_new`, `scriptOf_new`,
  `EVENT_STATE_REPORTED_eq`, `Keeps.removeListener`, `Keeps.useOnce`, `Keeps.recordDelivery`,
  `snapshot_match_all`, `snapshot_excluded`, `snapshot_eq`, `validateState_ok_iff`, `validateState_error`,
  `checkAscii_ok_iff`, `isState_eq`, `filterPasses_no_filter`, `filterPasses_no_data`, `filterPasses_data`,
  `fireNested_ok_iff`, `fireNested_queued`, `fireNested_full`, `mkQueued_fields`, `mkQueued_timeFired_none`,
  `asyncListen_error_iff`, `asyncListenOnce_error_iff`, `asyncFire_error_iff`, `State.name_default`,
  `State.name_friendly`, `State.name_falsy`, `hasAttr_iff`, `timeOfDay_eq`, `fireInternal_nested`,
  `fireInternal_queue_full`, `callService_too_deep`, `runAction_listen_error`.
* No theorem with a `True` conclusion and no theorem with contradictory hypotheses was found.

## Specifications independent of the code?

C theorems: 6.

Independent specification (3):
* `validEntityId_iff`: right-hand side `EntityIdRe`, the regex written clause by clause (`SlugRe`,
  `LaterDoubleUnderscore`, the `$`-before-newline alternative). `SlugRe` uses the implementation's `isSlugChar`
  for the class `[\da-z_]`; `isSlugChar_iff` (H) gives that class by code point. `\d` is ASCII only (stated).
  Checked against `core.py:180-183`.
* `validDomain_iff`: right-hand side `DomainRe`, same remarks.
* `splitEntityId_some`: right-hand side is a list equation (`s = d ++ "." ++ o`, no dot in `d`, both
  non-empty). Checked against `core.py:172-177`.

Not independent (3):
* `validateState_ok_iff`: restates the implementation's `if`.
* `isState_eq`: restates the definition in terms of `get`, which is itself not specified.
* `asyncEntityIdsCount_eq`: relates the count to the length of `asyncEntityIds`, another translated function
  with the same case split; it is a consistency statement between two implementations.

Among the O theorems, `dispatchLoop_deliveries` compares against a separately written function (`deliverable`,
HassProofs.lean:345). `deliverable` repeats the case split of `Hass.runJob` (filter, `system`, `once`,
`onceRemoved`).

## Docstring claims

Checked: 227 (217 theorem docstrings, 10 module headers). correct 212, overstated 11, false 4,
correct for the wrong reason 0, stale 0.

False (4):
1. `HassSchedProofs.lean` header, l. 8: "`runHandle_fifo`, `runLoop_fifo`: **FIFO.**" No theorem `runLoop_fifo`
   exists (grep over the repository: this line is the only occurrence). The file has `resume_main_fifo`. The same
   header, l. 14-16: "(the ones it waited for are done and removed)"; "done" is not in the statement.
2. `unsub_gone` (EventBusProofs.lean:664-669): "a table whose event types are distinct (true of every table the
   bus builds: each job is stored once, under its own event type)". `Op.init` builds tables with repeated event
   types; the same file says so at l. 706-708 ("Event types are *not* assumed distinct: `init` installs whatever
   counts it is given, duplicates included"). `#eval` on `run Bus.new [(0, .init [("a",1),("a",1)])]` gives keys
   `["a","a"]`.
3. `step_reads` (HassSpec.lean:244-245): "The read operations of the top level never change the core and never
   output anything." For `get` the statement is only `(step now h (.get d)).1 = h`, and `step` outputs
   `[.unsupported "entity id"]` for a non-ASCII id (Hass.lean:792; `#eval` confirms).
4. `Context.eq_of_fields` (StateSpec2.lean:192-193): "The dict determines the context: two contexts with the same
   `_as_dict` fields are equal." The statement is `c.id = d.id → c.parentId = d.parentId → c.userId = d.userId →
   c.asDict = d.asDict`, the opposite direction.

Overstated (11):
1. `HassProofs.lean` header, l. 10-13: "`runListener_deliveries` (eager start): ... a coroutine's synchronous
   prefix runs at once and the rest waits in its task". The statement has only `dispatching`, `onceRemoved` and
   the delivery list.
2. `runListener_deliveries` docstring (HassProofs.lean:405-409): same claim.
3. `runHandle_fifo` (HassSchedProofs.lean:334-337): "a handle queued earlier runs before every handle queued
   later". The statement is `ready = rest ++ added` after one `runHandle`.
4. `blockTillDone_no_tasks` (HassSchedProofs.lean:406-408): "every task the loop started is done and its done
   callback has removed it". The statement is `inSet = false` for the tasks still in `h'.tasks`, under "returns
   `.ok`".
5. `set_same_state_keeps_last_changed` (Proofs.lean:157-158): "`async_set` with the same state never moves
   `last_changed`". The theorem is about `asyncSetInternal` with `forceUpdate = false`; with `force_update` the
   code takes a new `last_changed`.
6. `set_cases` (Proofs.lean:124-127): "the old `last_changed` exactly when the state is unchanged". The statement
   has `o.state == st && !force`.
7. `reserve_then_unavailable` (Proofs.lean:248): "A reserved id is no longer available." Needs `isAscii eid` and
   `lowerAscii eid = eid`; false without them (see above).
8. `runJob_once_spent` (EventBusSpec2.lean:428-429): "does nothing: no receipt, no reaction". Only the receipt
   count is stated.
9. `log_entries` (HassSpec.lean:24-26): "The three log entries the core writes". `Hass.lean` writes a fourth
   (`removeListener`, l. 317-319) and forwards the registry's records.
10. `fuel_zero_unsupported` (HassSpec.lean:197-199): "Running out of fuel is never silent ... so the driver
    rejects the operation." The statement is the fuel-0 base case of each function; propagation of the entry to
    the operation's output is not stated.
11. `runAction_wait` (HassSpec.lean:349-351): "goes on at once when the future is done and suspends on it
    otherwise". The statement gives only the unchanged core and the empty output.

## manifest.yaml claims

Entries considered: 18 (15 with status `proven` and a `lean:` name in the area's implementation files; 3 with
status `translated` whose notes name a theorem). correct 6, overstated 12, false 0, stale 0,
correct for the wrong reason 0.

| python | status | theorems named | exist | state what the note says | verdict |
|---|---|---|---|---|---|
| `core.py::valid_entity_id` | proven | `validEntityId_iff` | yes | yes | correct: determines the result |
| `core.py::valid_domain` | proven | `validDomain_iff` | yes | yes | correct |
| `core.py::split_entity_id` | proven | `splitEntityId_some` | yes | yes | correct |
| `core.py::States.domain_entity_ids` | proven | `mem_domainEntityIds` | yes | membership only; the order named in the note is not in the theorem | overstated |
| `core.py::StateMachine.async_remove` | proven | `remove_then_get_none`, `remove_then_lookup_none`, `remove_keys` | yes | yes | overstated: three properties; return value, event, other entities' states not determined by them. Nothing for `Hass.runAction` / `smQueued`. |
| `core.py::StateMachine.async_reserve` | proven | `reserve_then_unavailable` | yes | yes, for ASCII lower-case ids | overstated: one property; when it raises is not stated |
| `core.py::StateMachine.async_set_internal` | proven | `set_same_only_reports`, `set_same_state_keeps_last_changed`, `set_frame`, `set_keys`, `set_delivers_first` | yes | yes | overstated: the stored state and attributes of the change branch are not determined; `set_delivers_first` needs a given context |
| `core.py::ServiceRegistry._async_register` | proven | `has_after_register` (ServiceRegistryProofs) | yes | yes | overstated: one property of `Registry.register`; nothing about `Hass.runAction` / `firedQueued` |
| `core.py::ServiceRegistry._async_remove` | proven | `has_after_remove`, `call_after_remove_not_found` | yes | yes | overstated: two properties; nothing about the joined core |
| `core.py::ServiceRegistry.async_call` | proven | `call_none_return_response_errors`, `call_only_needs_return_response`, `call_return_response_needs_blocking`, `call_after_remove_not_found` | yes | yes (about `Registry.asyncCall`) | overstated: four error cases; no theorem about `Hass.callService`, `Hass.resume`, `Frame` except `callService_prepare_error` |
| `core.py::_OneTimeListener.__call__` | proven | `once_at_most_once` | yes | yes | overstated: an upper bound for the stand-alone bus; `Hass.useOnce`, `Hass.runJob`, `Hass.runListener` (listed under `lean:`) are not covered by it |
| `core.py::EventBus._async_dispatch` | proven | `snapshot_match_all`, `snapshot_excluded`, `gone_silent`, `dispatchLoop_deliveries`, `runListener_deliveries` | yes | yes | overstated: for `Hass.dispatchLoop` the delivery list is determined (under `NoUnsup`), logs and the resulting core are not; for `EventBus.dispatch` / `dispatchLoop` only `snapshot` and safety properties |
| `core.py::EventBus._async_remove_listener` | proven | `unsub_gone`, `unsub_gone_reachable`, `unsub_silent` | yes | yes | overstated: properties of the stand-alone bus; the log entry and the re-created list named in the note have no theorem; `Hass.removeListener` not covered |
| `core.py::HomeAssistant._async_add_hass_job` | proven | `runListener_deliveries`, `keeps` | yes | yes | overstated: two properties; task creation is not characterised |
| `core.py::HomeAssistant.async_block_till_done` | proven | `blockTillDone_no_tasks` | yes | yes | overstated: one conditional property |
| `core.py::State.__init__` | translated | `State.new_ok` | yes (`HALean.Core.StateMachine.State.new_ok`) | n/a (name only) | correct |
| `core.py::EventBus.async_fire_internal` | translated | `quiet`, `fireInternal_first`; "drain ... (not proved yet)" | yes | yes; no theorem bounds `drain` | correct |
| `core.py::HomeAssistant.async_run_hass_job` | translated | `runListener_deliveries` | yes | name only | correct |

## PROPERTIES.md claims

Claims that refer to theorems of these modules: 28. correct 20, overstated 7, stale 1, false 0,
correct for the wrong reason 0.

| line | claim | verdict | evidence |
|---|---|---|---|
| 141 | `valid_entity_id` / `validEntityId_iff` / `EntityIdRe` | correct | StateSpec.lean:220 |
| 142 | `valid_domain` / `validDomain_iff` | correct | StateSpec.lean:281 |
| 143 | `split_entity_id` / `splitEntityId_some` | correct | StateSpec.lean:323 |
| 231 | `set_same_only_reports` | correct | Proofs.lean:95; "Python-equal" is the opaque `attrsEq` |
| 232 | `set_same_state_keeps_last_changed`: "never moves `last_changed`, whatever the attributes" | overstated | the theorem fixes `forceUpdate = false` (Proofs.lean:162) |
| 233 | `set_frame` | correct | Proofs.lean:177 |
| 234 | `set_keys`, `remove_keys`, `mem_domainEntityIds` | correct | one-step statements; the trace reading is their induction |
| 235 | `remove_then_get_none`: "remove, then `get`, is `None`" | overstated | hypothesis `lowerAscii eid = eid` omitted (Proofs.lean:213) |
| 236 | `reserve_then_unavailable`: "a reserved id is not available" | overstated | hypotheses `isAscii`, `lowerAscii eid = eid` omitted; false for `"Light.X"` |
| 240-242 | next candidates: "event-level properties once the event bus is translated" | stale | the bus is translated (`EventBus.lean`, `Hass.lean`); the rest of the paragraph (ids valid and lower case not proved) is correct |
| 267 | `once_at_most_once` | correct | EventBusProofs.lean:367 |
| 268 | `gone_silent` | correct | l. 530 |
| 269 | `unsub_gone`: "a listener stored once under its own event type is out of the table" | overstated | hypothesis `(b.listeners.map (·.1)).Nodup` omitted (l. 672) |
| 270 | `reachable_wf` | correct | l. 895-898, 1186 |
| 271 | `unsub_gone_reachable`, `unsub_gone_wf` | correct | the remaining hypotheses say that the callback is stored and run |
| 272 | `unsub_silent` | correct | l. 1246; top-level unsubscribe |
| 273 | `snapshot_match_all`, `snapshot_excluded` | correct | restate the definition |
| 275-279 | next candidates: `drain` bound and FIFO delivery not proved | correct | no such theorem |
| 301 | `quiet` | correct | HassProofs.lean:178 |
| 302 | `runListener_deliveries`: "a coroutine's synchronous prefix runs at once, the rest waits in its task" | overstated | not in the statement (l. 410-414) |
| 303 | `runJob_deliveries` | correct | l. 437 |
| 304 | `dispatchLoop_deliveries` | correct | l. 469; hypotheses `dispatching = true`, `NoUnsup` |
| 305 | `fireInternal_first` | correct | l. 534; context only when one is given |
| 306 | `set_delivers_first`: "the same for a successful `async_set`" | overstated | needs `resolveCtx env c = some ctx` (l. 557); a set without context is not covered; "exactly once" is a prefix statement |
| 314 | `keeps` | correct | HassSchedProofs.lean:94 |
| 315 | `runHandle_fifo`, `resume_main_fifo`: "so a task resumed ... runs before every handle queued later" | overstated | the theorems state the queue after one handle; no theorem about `runLoop`'s order |
| 316 | `blockTillDone_no_tasks` | correct | l. 409; "returns" means returns a value |
| 318-328 | next candidates: `reachable_wf` for the core, empty ready queue after `block_till_done`, FIFO across services not proved | correct | no such theorems |

## README statements (the two named in the assignment)

* README l. 475-476, "`drain`'s bound ... is justified by the queue limit but not proved yet": correct. No theorem
  mentions the queue being empty after `asyncFire` or `drain`. `drain_onceInv`, `drain_quiet`, `drain_wf` are
  invariant-preservation lemmas for any fuel. If the bound were wrong, `EventBus.drain` would stop without a
  marker.
* README l. 390-391, "The scheduler's theorems (FIFO, `block_till_done` leaves no task) are in
  `HALean/Core/HassSchedProofs.lean`": the theorems are there. "FIFO" is `runHandle_fifo` and
  `resume_main_fifo`: queue-prefix statements for one handle, no hypotheses, no statement about `runLoop`.
  "Leaves no task" is `blockTillDone_no_tasks`: under the hypothesis that the operation returns `.ok`, every task
  record left has `inSet = false`. Verdict: overstated for "FIFO" (per-step property, not an execution-order
  theorem), correct for "leaves no task" with the stated hypothesis.
