/-
  Running a probatio schema (`HALean.Core.Probatio`) on service data, as
  `probatio.Schema.__call__` does: the mapping engine
  (`_engine._MappingValidator`), the sequence engine
  (`_engine._SequenceValidator`), the combinators and the leaf validators.
-/
import HALean.Core.ConfigValidation

namespace HALean.Core
open HALean.Template

/-- `_MappingValidator._key_names`: the literal string keys, the pool for
"did you mean". -/
def keyNames (fields : List Field) : List String := fields.map Field.key

/-- The groups of the mapping's `Exclusive` (`true`) or `Inclusive` members,
in the order their first member appears, with the members' indices. -/
def groupsOf (fields : List Field) (excl : Bool) : List (String × List Nat) :=
  (List.range fields.length).zip fields |>.foldl (fun acc (i, f) =>
    let g? := match f.marker, excl with
      | .exclusive g _, true => some g
      | .inclusive g, false => some g
      | _, _ => none
    match g? with
    | none => acc
    | some g =>
      if acc.any (·.1 == g) then acc.map fun (h, ms) => if h == g then (h, ms ++ [i]) else (h, ms)
      else acc ++ [(g, [i])]) []

mutual
/-- Validate a value against a schema node. `extra` is the schema's
extra-key policy, which every nested mapping inherits. -/
partial def Validator.run (extra : Extra) : Validator → Value → VResult
  | .type t, v => checkType t v
  | .literal lit, v => checkLiteral lit v
  | .dict fields, v => runMapping extra fields v
  | .schema fields ex, v => runMapping ex fields v
  | .seq elems, v => runSequence extra elems v
  | .all vs, v => runAll extra vs v
  | .any vs, v => runAny extra vs v
  | .isIn c, v => checkIn c v
  | .notIn c, v => checkNotIn c v
  | .range mn mx mi ma, v => checkRange mn mx mi ma v
  | .clamp mn mx, v => checkClamp mn mx v
  | .length mn mx, v => checkLength mn mx v
  | .coerce t, v => checkCoerce t v
  | .lower, v => checkLower v
  | .upper, v => checkUpper v
  | .ensureList, v => pure (ensureList v)
  | .port, v => checkPort v
  | .atLeastOne ks, v => checkAtLeastOne ks v
  | .cv f, v => compileCallable (f.run v)

/-- `All.__call__`: each validator in turn, the output chained forward; the
first failure is raised (a lone `Invalid` wrapped in `MultipleInvalid`). -/
partial def runAll (extra : Extra) : List Validator → Value → VResult
  | [], v => pure v
  | x :: xs, v => do runAll extra xs (← x.run extra v)

/-- `Any.__call__` (`_run_any`; the typed fast paths decide the same): the
first branch that accepts wins. On a miss, when every branch has a label the
error is "expected <a or b>"; otherwise the error of the branch whose first
leaf reached the deepest path (the first such branch on a tie); with no
branches at all, "no valid value found". Exceptions other than `Invalid`
escape. -/
partial def runAny (extra : Extra) (vs : List Validator) (v : Value) : VResult := do
  let mut best : Option (List SchemaError) := none
  let mut bestDepth : Int := -1
  for b in vs do
    match b.run extra v with
    | .ok r => return r
    | .error (.invalid errs) =>
      let depth : Int := (errs.head?.map (·.path.length)).getD 0
      if depth > bestDepth then
        best := some errs
        bestDepth := depth
    | .error e => throw e
  if let some label := expectedLabel vs then throw (inv s!"expected {label}")
  match best with
  | none => throw (inv "no valid value found")
  | some errs => throw (.invalid errs)

/-- `_SequenceValidator.__call__` for a list schema: the value must be a list;
with one element schema every item is validated by it, with several an item
must match one of them (the last one's error is reported), with none no item
matches ("invalid value"). Errors are prefixed with the item's index. -/
partial def runSequence (extra : Extra) (elems : List Validator) (v : Value) : VResult := do
  let .list items := v | throw (inv "expected a list")
  let mut out : Array Value := #[]
  let mut errors : Array SchemaError := #[]
  let mut i := 0
  for item in items do
    match elems with
    | [] => errors := errors.push { message := "invalid value", path := [.idx i] }
    | _ =>
      let mut last : Option (List SchemaError) := none
      let mut done := false
      for e in elems do
        if done then continue
        match e.run extra item with
        | .ok r => out := out.push r; done := true
        | .error (.invalid errs) => last := some errs
        | .error err => throw err
      if !done then
        errors := errors ++ (prependAll (.idx i) (last.getD [])).toArray
    i := i + 1
  if errors.isEmpty then return .list out.toList else throw (.invalid errors.toList)

/-- `_MappingValidator.__call__` for a mapping of literal string keys:
the data's keys in order (a value's errors are prefixed with its key; an
unknown key follows the extra-key policy), then `_finalize` (defaults, which
are validated too, and missing required keys, in schema order), then
`_check_groups` (`Exclusive` groups, then `Inclusive` groups). -/
partial def runMapping (extra : Extra) (fields : List Field) (v : Value) : VResult := do
  let .dict kvs := v | throw (inv "expected a mapping")
  let names := keyNames fields
  let mut out : List (Value × Value) := []
  let mut errors : Array SchemaError := #[]
  let mut seen : List Nat := []
  let indexed := (List.range fields.length).zip fields
  let store (out : List (Value × Value)) (k : Value) (x : Value) : List (Value × Value) :=
    if out.any (fun p => pyEq p.1 k) then out.map fun p => if pyEq p.1 k then (k, x) else p
    else out ++ [(k, x)]
  for (k, x) in kvs do
    let field? := match k with
      | .str s => indexed.find? (fun (p : Nat × Field) => p.2.key == s)
      | _ => none
    match field? with
    | some (i, f) =>
      seen := i :: seen
      match f.value.run extra x with
      | .ok r => out := store out k r
      | .error (.invalid errs) => errors := errors ++ (prependAll (.key f.key) errs).toArray
      | .error e => throw e
    | none =>
      match extra with
      | .allow => out := store out k x
      | .remove => pure ()
      | .prevent =>
        match k with
        | .str s =>
          -- the error's path prints `repr(key)`
          if !reprSafeValue (.str s) then
            throw (VErr.unsupported "repr() of a key with characters outside the modelled printable set")
          errors := errors.push (extraKeyError names s)
        | _ => throw (VErr.unsupported "a non-string mapping key")
  -- `_finalize`
  for (i, f) in indexed do
    let isExcl := match f.marker with | .exclusive .. => true | _ => false
    let required := f.marker == .required
    if !(required || (f.default.isSome && !isExcl)) || seen.contains i then continue
    match f.default, isExcl with
    | some d, false =>
      match f.value.run extra d with
      | .ok r => out := store out (.str f.key) r
      | .error (.invalid errs) => errors := errors ++ (prependAll (.key f.key) errs).toArray
      | .error e => throw e
    | _, _ => errors := errors.push { message := "required key not provided", path := [.key f.key] }
  -- `_check_groups`
  for (g, members) in groupsOf fields true do
    let present := (members.filter seen.contains).length
    if present > 1 then
      errors := errors.push { message := s!"two or more values in the same group of exclusion {strRepr g}",
                              path := [.group g] }
    else if present == 0 then
      -- `_empty_exclusive_group`: the first member with a default fills it
      let withDefault := members.findSome? fun i => (fields[i]?).bind fun f => f.default.map (f, ·)
      match withDefault with
      | some (f, d) =>
        match f.value.run extra d with
        | .ok r => out := store out (.str f.key) r
        | .error (.invalid errs) => errors := errors ++ (prependAll (.key f.key) errs).toArray
        | .error e => throw e
      | none =>
        let req := members.any fun i => match (fields[i]?).map Field.marker with
          | some (.exclusive _ true) => true
          | _ => false
        if req then
          let keys ← displayList (members.filterMap fun i => (fields[i]?).map fun f => Value.str f.key)
          errors := errors.push { message := s!"exactly one of {keys} is required", path := [.group g] }
  for (g, members) in groupsOf fields false do
    let missing := (members.filter (!seen.contains ·)).length
    if missing != 0 && missing != members.length then
      errors := errors.push { message := s!"some but not all values in the same group of inclusion {strRepr g}",
                              path := [.group g] }
  if errors.isEmpty then return .dict out else throw (.invalid errors.toList)
end

/-- `Schema.__call__` on service data (a dict of string keys): the validated
dict, or the failure. -/
def SchemaSpec.validate (s : SchemaSpec) (data : List (String × Value)) :
    Except VErr (List (String × Value)) := do
  match ← (Validator.dict s.fields).run s.extra (dictOf data) with
  | .dict kvs => kvs.mapM fun (k, v) => match k with
    | .str k => pure (k, v)
    | _ => throw (.unsupported "a non-string key")
  | _ => throw (.unsupported "a mapping schema returned a non-dict")

end HALean.Core
