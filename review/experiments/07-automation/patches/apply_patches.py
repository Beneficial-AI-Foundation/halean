"""Apply the review patches one by one in the throwaway copy, committing each (HALean/ only),
and write patches/<ID>.patch (the diff of that commit). Patches are cumulative, in this order."""
import subprocess, sys, pathlib
C = pathlib.Path("/tmp/claude-0/halean-copies/07-automation-p")
OUT = pathlib.Path("/home/user/halean/review/experiments/07-automation/patches")
CFG, ENG, CND = "HALean/Automation/Config.lean", "HALean/Automation/Engine.lean", "HALean/Automation/Condition.lean"

def edit(path, old, new, count=1):
    p = C / path; s = p.read_text()
    assert s.count(old) == count, (path, old[:60], s.count(old))
    p.write_text(s.replace(old, new))

def commit(pid):
    subprocess.run(["git", "add", "HALean"], cwd=C, check=True)
    subprocess.run(["git", "commit", "-q", "-m", pid], cwd=C, check=True)
    d = subprocess.run(["git", "diff", "HEAD~1", "HEAD", "--", "HALean"], cwd=C, check=True, capture_output=True, text=True).stdout
    (OUT / f"{pid}.patch").write_text(d)
    print(pid, len(d.splitlines()), "lines")

# ---- AUT-1: restart awaits the old runs' stop before the new run starts
edit(ENG, "  mqttRetained : List ((Owner × Nat) × List String) := []\n  deriving Inhabited",
     "  mqttRetained : List ((Owner × Nat) × List String) := []\n"
     "  /-- `restart` runs whose `started_action` (`automation_triggered`) is still to come:\n"
     "  `Script.async_run` awaits the old runs' stop first, which takes a loop iteration. -/\n"
     "  deferredTriggered : List (Nat × Cmd) := []\n  deriving Inhabited")
edit(ENG, """    for old in existing do e := removeRun e old.id
  setE e
  emit [.automationTriggered a.id a.alias tv.description]
  if wait == .ready then drive run
""", """    for old in existing do e := removeRun e old.id
    -- `await self.async_stop(update_state=False, spare=run)`: the old runs stop in the next
    -- loop iteration; only then `started_action()` fires and the new run starts (unless a
    -- later trigger of the same event restarted it before it ran a step)
    setE { e with woken := e.woken ++ [run.id],
                  deferredTriggered := e.deferredTriggered ++
                    [(run.id, Cmd.automationTriggered a.id a.alias tv.description)] }
    return
  setE e
  emit [.automationTriggered a.id a.alias tv.description]
  if wait == .ready then drive run
""")
edit(ENG, """    for rid in ws do
      setE (cleanupWait (← getE) rid)
""", """    for rid in ws do
      let e ← getE
      if let some (_, c) := e.deferredTriggered.find? (·.1 == rid) then
        setE { e with deferredTriggered := e.deferredTriggered.filter (·.1 != rid) }
        emit [c]
      setE (cleanupWait (← getE) rid)
""")
commit("AUT-1")

# ---- AUT-2: `to: "*"` / `from: "*"` is MATCH_ALL (`process_state_match`)
edit(CFG, """def stateMatch (j : Json) (pos neg : String) : StateMatch :=
  match field? j pos with
  | some .null | none =>
    match field? j neg with
    | some .null | none => {}
    | some v => { values := some (ensureList v), invert := true }
  | some v => { values := some (ensureList v) }
""", """def stateMatch (j : Json) (pos neg : String) : StateMatch :=
  -- `if parameter is None or parameter == MATCH_ALL: return lambda _: not invert`
  let mk (v : Json) (invert : Bool) : StateMatch :=
    if v == .str "*" then { invert } else { values := some (ensureList v), invert }
  match field? j pos with
  | some .null | none =>
    match field? j neg with
    | some .null | none => {}
    | some v => mk v true
  | some v => mk v false
""")
commit("AUT-2")

# ---- AUT-3: values are compared with Python's `==`
edit(CFG, "/-- `process_state_match`: `values = none` is MATCH_ALL. -/",
     "/-- Python's `==` between two JSON values (`1 == 1.0 == True`, `\"1\" != 1`). -/\n"
     "def jsonPyEq (a b : Json) : Bool :=\n"
     "  Template.pyEq (Template.Value.ofJson a) (Template.Value.ofJson b)\n\n"
     "/-- `process_state_match`: `values = none` is MATCH_ALL. -/")
edit(ENG, "  | some vs => m.invert != vs.contains v", "  | some vs => m.invert != vs.any (jsonPyEq · v)")
edit(ENG, "  if attr.isSome && oldV == newV then return\n  if !fromM.matches oldV || !toM.matches newV || (!matchAll && oldV == newV) then return",
     "  if attr.isSome && jsonPyEq oldV newV then return\n  if !fromM.matches oldV || !toM.matches newV || (!matchAll && jsonPyEq oldV newV) then return")
edit(ENG, "    | .equalNew attr v => valueOf attr (some s) == v\n    | .notEqualOld attr v => valueOf attr (some s) != v",
     "    | .equalNew attr v => jsonPyEq (valueOf attr (some s)) v\n    | .notEqualOld attr v => !jsonPyEq (valueOf attr (some s)) v")
edit(CND, "    isState := value == sv", "    isState := jsonPyEq value sv")
commit("AUT-3")

# ---- AUT-4: entity ids are lower-cased and validated (`cv.entity_ids_or_uuids`)
edit(CFG, """    let xs ← strList v
    pure (xs.flatMap fun s => (s.splitOn ",").map String.trim |>.filter (· ≠ ""))
""", """    let xs ← strList v
    let ids := (xs.flatMap fun s => (s.splitOn ",").map String.trim |>.filter (· ≠ "")).map String.toLower
    for e in ids do
      -- `entity_id_or_uuid`: a valid entity id, or 32 lower-case hex digits
      let isUuid := e.length == 32 && e.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')
      if !Template.validEntityId e && !isUuid then throw s!"Entity ID {e} is an invalid entity ID"
    pure ids
""")
commit("AUT-4")

# ---- AUT-5: one listener per entry of a trigger's list
edit(ENG, """        if ats.contains tod && dayOk then
          fire o {
            id := t.id, idx := t.idx, platform := "time",
            description := "time",
            value := triggerValue t "time" [("now", nowV),
              ("description", .str "time"), ("entity_id", .none)] }
""", """        if dayOk then
          -- one `async_track_time_change` listener per entry of `at`
          for _ in ats.filter (· == tod) do
            fire o {
              id := t.id, idx := t.idx, platform := "time",
              description := "time",
              value := triggerValue t "time" [("now", nowV),
                ("description", .str "time"), ("entity_id", .none)] }
""")
edit(ENG, """        if types.contains ty && eventDataMatches want data then
          fire o {
            id := t.id, idx := t.idx, platform := "event",
            description := s!"event '{ty}'",
            value := triggerValue t "event" [("event", ev), ("description", .str s!"event '{ty}'")] }
""", """        if eventDataMatches want data then
          -- one `bus.async_listen` per entry of `event_type`
          for _ in types.filter (· == ty) do
            fire o {
              id := t.id, idx := t.idx, platform := "event",
              description := s!"event '{ty}'",
              value := triggerValue t "event" [("event", ev), ("description", .str s!"event '{ty}'")] }
""")
edit(ENG, "      | .state .. => onStateTrigger o t eid old new\n",
     "      | .state eids .. =>\n"
     "        -- `async_track_state_change_event` adds the listener once per entry of `entity_id`\n"
     "        for _ in eids.filter (· == eid) do onStateTrigger o t eid old new\n")
commit("AUT-5")

# ---- AUT-6: a static float `count` is truncated (`probatio.Coerce(int)`)
edit(CFG, "      | .num n => return wrap (.repeatCount n.mantissa.toNat body)\n",
     "      | .num _ =>\n"
     "        -- `probatio.Coerce(int)`: `int()` truncates a float\n"
     "        let n : Int := match Template.Value.ofJson c with\n"
     "          | .int i => i\n"
     "          | .float f => (Template.floatToInt? f).getD 0\n"
     "          | _ => 0\n"
     "        return wrap (.repeatCount n.toNat body)\n")
commit("AUT-6")

# ---- AUT-7: `continue_on_error` and stop's `error` are `cv.boolean`
edit(CFG, "/-- `cv.template_complex` -/\npartial def decodeComplex",
     "/-- An optional `cv.boolean` key. -/\n"
     "def cvBooleanKey (j : Json) (k : String) (dflt : Bool) : D Bool :=\n"
     "  match field? j k with\n"
     "  | none => pure dflt\n"
     "  | some (.bool b) => pure b\n"
     "  | some (.num n) => pure (n.mantissa != 0)\n"
     "  | some (.str s) => match Template.cvBooleanText s with\n"
     "    | some b => pure b\n"
     "    | none => throw s!\"invalid boolean value {s} for '{k}'\"\n"
     "  | some v => throw s!\"invalid boolean value {v.compress} for '{k}'\"\n\n"
     "/-- `cv.template_complex` -/\npartial def decodeComplex")
edit(CFG, "  let coe := match field? j \"continue_on_error\" with | some (.bool true) => true | _ => false\n",
     "  let coe ← cvBooleanKey j \"continue_on_error\" false\n")
edit(CFG, "    let err := match field? j \"error\" with | some (.bool true) => true | _ => false\n",
     "    let err ← cvBooleanKey j \"error\" false\n")
commit("AUT-7")

# (AUT-9 has no patch: see FINDINGS.md)

# ---- AUT-10: `initial_state: false`
edit(CFG, "  return { id, alias, triggers := trigs.filterMap (fun x => x), conditions := conds,",
     "  -- `initial_state: false`: the automation starts turned off, its triggers are not attached\n"
     "  let initialOn ← cvBooleanKey j \"initial_state\" true\n"
     "  return { id, alias, triggers := if initialOn then trigs.filterMap (fun x => x) else [], conditions := conds,")
commit("AUT-10")

# ---- AUT-12: numeric_state reads numbers like Python's float() (digit-group underscores)
edit(CND, "    match parsePyFloatStr be.state with", "    match Template.parseFloatStr be.state with")
edit(CND, "      let some fv := pyFloat? value\n", "      let some fv := pyFloatV (Template.Value.ofJson value)\n")
# pyFloatV is defined after resolveBound and before numericStateOf: nothing to move
commit("AUT-12")

# ---- AUT-15: static periods go through cv.positive_time_period
p = C / CFG; s = p.read_text()
a = s.index("/-- `cv.time_period`: \"HH:MM[:SS[.fff]]\", seconds, or a dict. Returns ms. -/")
b = s.index("def optDuration")
s = s[:a] + '''/-- `cv.positive_time_period` of a static value (`cvPositiveTimePeriod`, the
translation of `time_period_str` / `time_period_seconds` / `time_period_dict`),
in whole milliseconds (rounded up, like the engine's timers). -/
def durationMs (v : Json) : D Nat := do
  if let .str s := v then
    if Template.isTemplateString s then throw s!"templated durations are not supported here: {s}"
  match cvPositiveTimePeriod (Template.Value.ofJson v) with
  | .ok us => pure ((us + 999) / 1000).toNat
  | .error e => throw s!"invalid time period {v.compress}: {e}"

''' + s[b:]
p.write_text(s)
commit("AUT-15")

# ---- AUT-17: a parallel branch written as a list of actions
edit(CFG, "    let branches ← (ensureList ps).mapM fun b => do\n      if has b \"sequence\"",
     "    let branches ← (ensureList ps).mapM fun b => do\n"
     "      -- `_parallel_sequence_action`: `SCRIPT_SCHEMA` (a list of actions) wrapped in a sequence\n"
     "      if let .arr _ := b then return (← seqOf b)\n"
     "      if has b \"sequence\"")
commit("AUT-17")

# ---- AUT-18: `stop:` without a reason
edit(CFG, "  if let some s := str? j \"stop\" then\n",
     "  if has j \"stop\" then\n"
     "    -- `probatio.Any(None, cv.string)`\n"
     "    let s ← match field? j \"stop\" with\n"
     "      | some (.str s) => pure s\n"
     "      | some .null | none => pure \"\"\n"
     "      | some v => cvStringOf \"stop\" v\n")
commit("AUT-18")

# ---- AUT-19: time_pattern values go through int()
edit(CFG, """        | some (.str s) =>
          if s.startsWith "/" then
            match (s.dropS 1).toNat? with
            | some n => if n == 0 || n > mx then throw s!"bad {k}" else pure (some (.every n))
            | none => throw s!"bad {k}"
          else match s.toNat? with
            | some n => if n > mx then throw s!"bad {k}" else pure (some (.exact n))
            | none => throw s!"bad {k}"
        | some (.num n) => match n.mantissa.toNat with
          | m => if n.exponent == 0 && m ≤ mx then pure (some (.exact m)) else throw s!"bad {k}"
        | some _ => throw s!"bad {k}"
""", """        | some (.str s) =>
          -- `TimePattern.__call__`: `int(value[1:])` / `int(value)`
          if s.startsWith "/" then
            match Template.parseIntStr (s.dropS 1) with
            | some n => if n ≤ 0 || n > mx then throw s!"bad {k}" else pure (some (.every n.toNat))
            | none => throw s!"bad {k}"
          else match Template.parseIntStr s with
            | some n => if n < 0 || n > mx then throw s!"bad {k}" else pure (some (.exact n.toNat))
            | none => throw s!"bad {k}"
        | some v@(.num _) =>
          let i? : Option Int := match Template.Value.ofJson v with
            | .int i => some i
            | .float f => Template.floatToInt? f
            | _ => none
          match i? with
          | some n => if n < 0 || n > mx then throw s!"bad {k}" else pure (some (.exact n.toNat))
          | none => throw s!"bad {k}"
        | some (.bool b) => pure (some (.exact (if b then 1 else 0)))
        | some _ => throw s!"bad {k}"
""")
commit("AUT-19")

# ---- AUT-20: `triggers:` lists nested in the trigger list are flattened
edit(CFG, "/-- `tvals`: the static trigger_variables, when the trigger attaches with",
     "/-- `_base_trigger_list_flatten`: an item whose only key is `triggers` is replaced by that list. -/\n"
     "def flattenTriggers (ts : List Json) : List Json :=\n"
     "  ts.flatMap fun t => match t with\n"
     "    | .obj kvs => match kvs.toList, field? t \"triggers\" with\n"
     "      | [_], some sub => ensureList sub\n"
     "      | _, _ => [t]\n"
     "    | _ => [t]\n\n"
     "/-- `tvals`: the static trigger_variables, when the trigger attaches with", count=1)
edit(CFG, "  let trigVarNames := (ensureList (pick \"triggers\" \"trigger\")).flatMap fun t =>",
     "  let trigVarNames := (flattenTriggers (ensureList (pick \"triggers\" \"trigger\"))).flatMap fun t =>")
edit(CFG, "  let trigs ← ((ensureList (pick \"triggers\" \"trigger\")).zipIdx).mapM fun (t, i) => decodeTrigger i t tnm (some tvals)",
     "  let trigs ← ((flattenTriggers (ensureList (pick \"triggers\" \"trigger\"))).zipIdx).mapM fun (t, i) => decodeTrigger i t tnm (some tvals)")
edit(CFG, "    let trigs ← (ensureList w).zipIdx.mapM fun (t, i) => decodeTrigger i t nm",
     "    let trigs ← (flattenTriggers (ensureList w)).zipIdx.mapM fun (t, i) => decodeTrigger i t nm")
commit("AUT-20")
