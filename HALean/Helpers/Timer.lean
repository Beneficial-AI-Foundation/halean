/-
  `timer`: translated from `homeassistant/components/timer/__init__.py`
  (`CONFIG_SCHEMA`, `_format_timedelta`, `Timer`: `async_start`,
  `async_change`, `async_pause`, `async_cancel`, `async_finish`,
  `_async_finished`, `extra_state_attributes`, `_fire_event_and_write_state`).

  Time is explicit: every operation gets the clock `now` (µs since the epoch),
  and `utcnow().replace(microsecond=0)` is `nowSec now`. The callback
  `async_track_point_in_utc_time` schedules is `scheduled` plus `end`: it runs
  (`tick`) at the first clock at or after `end`. The `remaining` attribute is
  only updated on transitions, as upstream.

  Restoring a timer (`restore: true`) is modelled for an idle last state only;
  a paused or active one is refused (`Entity.create`).
-/
import HALean.Helpers.Common

namespace HALean.Helpers.Timer
open HALean.Core HALean.Template HALean.Helpers

def DOMAIN : String := "timer"

def US_PER_SEC : Int := 1000000

/-- `_format_timedelta`: `divmod` of `total_seconds()` by 3600 and 60, each
part truncated by `int()`. With µs this is exact integer arithmetic (the
remainders are non-negative, so `int()` is the floor). -/
def formatTd (us : Int) : String :=
  let h := us / 3600000000      -- `Int.div` rounds toward −∞ for a positive divisor (`Int.ediv`)
  let rem := us - h * 3600000000
  let m := rem / 60000000
  let s := (rem - m * 60000000) / US_PER_SEC
  let two (n : Int) : String := if n < 10 then s!"0{n}" else toString n
  s!"{h}:{two m}:{two s}"

/-- `dt_util.utcnow().replace(microsecond=0)` -/
def nowSec (now : Int) : Int := now - now % US_PER_SEC

inductive Status where
  | idle | active | paused
  deriving DecidableEq, Inhabited

def Status.str : Status → String
  | .idle => "idle" | .active => "active" | .paused => "paused"

structure Config where
  id : String
  name : Option String := none
  icon : Option String := none
  /-- `cv.time_period_str(config[CONF_DURATION])`, µs -/
  duration : Int := 0
  restore : Bool := false
  deriving Inhabited

def fields : List Field :=
  [opt "name" vString, opt "icon" vIcon,
   opt "duration" ServicesJson.timePeriod (some (.int 0)),
   opt "restore" vBoolean (some (.bool false))]

/-- `vol.All(_none_to_empty_dict, {...})`; the duration goes through
`vol.All(cv.time_period, _format_timedelta)` and back through
`cv.time_period_str` (`Timer.__init__`), so it loses its microseconds, and a
negative one comes back as a different value (`-0:00:05` is written
`-1:59:55`, read back as minus 1 h 59 min 55 s). -/
def decode (id : String) (v : Value) : Except VErr Config := do
  let v := match v with | .none => .dict [] | v => v
  let kvs ← runDict fields v
  let dur := match lk kvs "duration" with | some (.timedelta us) => us | _ => 0
  let .timedelta back ← cvTimePeriodStr (.str (formatTd dur))
    | throw (.unsupported "time_period_str")
  return { id, name := lkStr kvs "name", icon := lkStr kvs "icon", duration := back,
           restore := match lk kvs "restore" with | some (.bool b) => b | _ => false }

def decodeConfig (cfg : Value) : Except ConfigError (List Config) := slugKeys DOMAIN cfg decode

structure Entity where
  cfg : Config
  state : Status := .idle
  /-- `_last_transition` -/
  lastTransition : Option String := none
  /-- `_running_duration` (µs) -/
  running : Int
  /-- `_remaining` (µs) -/
  remaining : Option Int := none
  /-- `_end` (µs since the epoch) -/
  end_ : Option Int := none
  /-- `_listener`: the finish callback is scheduled (at `end_`) -/
  scheduled : Bool := false
  deriving Inhabited

def Entity.entityId (e : Entity) : String := s!"{DOMAIN}.{e.cfg.id}"

/-- `__init__` then `async_added_to_hass`. With `restore` and an idle last
state, `last_transition` is restored. `none`: a paused or active last state,
which HALean does not restore. -/
def Entity.create (cfg : Config) (last : Option (String × Attrs)) : Option Entity :=
  let e : Entity := { cfg, running := cfg.duration }
  match cfg.restore, last with
  | true, some (st, attrs) =>
    if st == "idle" then
      some { e with lastTransition := match attrs.lookup "last_transition" with
        | some (.str s) => some s
        | _ => none }
    else none
  | _, _ => some e

/-- `extra_state_attributes`, then `icon` and `friendly_name`. -/
def Entity.attrs (e : Entity) : Attrs :=
  [("duration", .str (formatTd e.running)), ("editable", .bool false),
   ("last_transition", match e.lastTransition with | some s => .str s | none => .none)] ++
  (match e.end_ with | some t => [("finishes_at", Value.str (isoformat t (some 0)))] | none => []) ++
  (match e.remaining with | some r => [("remaining", Value.str (formatTd r))] | none => []) ++
  (if e.cfg.restore then [("restore", .bool true)] else []) ++
  tailAttrs none e.cfg.icon e.cfg.name

/-- `async_write_ha_state` (`force_update` is set). -/
def write : HM Entity Unit := do
  let e ← getEnt
  emit (.write e.entityId e.state.str e.attrs true)

/-- `_fire_event_and_write_state`: `last_transition` is the event's name
after `timer.`; the state is written, then the event fired. -/
def fireAndWrite (event : String) (extra : Attrs := []) : HM Entity Unit := do
  let e ← getEnt
  setEnt { e with lastTransition := some ((event.drop 6).toString) }
  write
  emit (.fire event ([("entity_id", .str e.entityId)] ++ extra))

/-- A `timedelta` is truthy when it is not zero. -/
def tdTruthy : Option Int → Bool
  | some r => r != 0
  | none => false

/-- `async_start(duration)` (`duration` 0, the default, is "none"). -/
def start (now : Int) (duration : Int) : HM Entity Unit := do
  let e ← getEnt
  let event := if e.state == .active || e.state == .paused then "timer.restarted" else "timer.started"
  let start := nowSec now
  let (remaining, running) :=
    if duration != 0 then (duration, duration)
    else if !tdTruthy e.remaining then (e.running, e.running)
    else (e.remaining.getD 0, e.running)
  setEnt { e with state := .active, remaining := some remaining, running,
                  end_ := some (start + remaining), scheduled := true }
  fireAndWrite event

/-- `async_change(duration)` -/
def change (now : Int) (duration : Int) : HM Entity Unit := do
  let e ← getEnt
  let some end_ := e.end_
    | raise "HomeAssistantError" s!"Timer {e.entityId} is not running, only active timers can be changed"
  if !e.scheduled then
    raise "HomeAssistantError" s!"Timer {e.entityId} is not running, only active timers can be changed"
  let newRemaining := (end_ + duration) - nowSec now
  if tdTruthy e.remaining && newRemaining > e.running then
    raise "HomeAssistantError" s!"Not possible to change timer {e.entityId} beyond duration"
  if tdTruthy e.remaining && (e.remaining.getD 0) + duration < 0 then
    raise "HomeAssistantError" s!"Not possible to change timer {e.entityId} to negative time remaining"
  setEnt { e with end_ := some (end_ + duration), remaining := some newRemaining, scheduled := true }
  write
  emit (.fire "timer.changed" [("entity_id", .str e.entityId)])

/-- `async_pause` (nothing happens unless the timer is running). -/
def pause (now : Int) : HM Entity Unit := do
  let e ← getEnt
  match e.end_, e.scheduled with
  | some end_, true =>
    setEnt { e with remaining := some (end_ - nowSec now), state := .paused, end_ := none,
                    scheduled := false }
    fireAndWrite "timer.paused"
  | _, _ => pure ()

/-- The common reset of `async_cancel`, `async_finish` and `_async_finished`. -/
def toIdle (e : Entity) : Entity :=
  { e with state := .idle, end_ := none, remaining := none, running := e.cfg.duration,
           scheduled := false }

/-- `async_cancel` (nothing happens when idle). -/
def cancel : HM Entity Unit := do
  let e ← getEnt
  if e.state == .idle then return
  setEnt (toIdle e)
  fireAndWrite "timer.cancelled"

/-- `async_finish` (nothing happens when idle; a paused timer finishes
"now"). -/
def finish (now : Int) : HM Entity Unit := do
  let e ← getEnt
  if e.state == .idle then return
  let end_ := e.end_.getD (nowSec now)
  setEnt (toIdle e)
  fireAndWrite "timer.finished" [("finished_at", .str (isoformat end_ (some 0)))]

/-- Whether the scheduled callback is due at `now`. -/
def Entity.due (e : Entity) (now : Int) : Bool :=
  e.scheduled && match e.end_ with | some t => t ≤ now | none => false

/-- `_async_finished`, run by the scheduled callback. -/
def finished : HM Entity Unit := do
  let e ← getEnt
  let e := { e with scheduled := false }
  setEnt e
  if e.state != .active then return
  let some end_ := e.end_ | return
  setEnt (toIdle e)
  fireAndWrite "timer.finished" [("finished_at", .str (isoformat end_ (some 0)))]

def services : List (String × List Field) :=
  [("start", [opt "duration" ServicesJson.timePeriod (some (.int 0))]),
   ("pause", []), ("cancel", []), ("finish", []),
   ("change", [opt "duration" ServicesJson.timePeriod (some (.int 0))])]

def handle (service : String) (args : List (String × Value)) (now : Int) : HM Entity Unit := do
  let dur := match lk args "duration" with | some (.timedelta us) => us | _ => 0
  match service with
  | "start" => start now dur
  | "pause" => pause now
  | "cancel" => cancel
  | "finish" => finish now
  | _ => change now dur

end HALean.Helpers.Timer
