/-
  `halean-template`: renders templates for the differential tests.

  One JSON object per line on stdin:
    {"template": "...", "states": [...], "variables": {...}, "parse_result": true,
     "condition": false}
  One per line on stdout:
    {"ok": true, "type": "int", "repr": "3"}   -- repr() of the rendered value
    {"ok": false, "error": "..."}               -- HA would raise TemplateError
    {"unsupported": "..."}                      -- rejected at load time
-/
import HALean.Template
open Lean HALean HALean.Template

def decodeState (j : Json) : Except String EntityState := do
  let eid ← j.getObjValAs? String "entity_id"
  let st ← j.getObjValAs? String "state"
  let attrs := (j.getObjVal? "attributes").toOption.getD (Json.mkObj [])
  let us (k : String) : Option Int := match j.getObjVal? k with
    | .ok (.num n) => if n.exponent == 0 then some n.mantissa else none
    | _ => none
  return { entityId := eid, state := st, attributes := attrs,
           lastChangedUs := us "last_changed_us", lastUpdatedUs := us "last_updated_us" }

def handleLine (line : String) : Json :=
  match Json.parse line with
  | .error e => Json.mkObj [("unsupported", s!"bad input: {e}")]
  | .ok j =>
    let src := (j.getObjValAs? String "template").toOption.getD ""
    let states := match j.getObjVal? "states" with
      | .ok (.arr xs) => (xs.toList.filterMap fun x => (decodeState x).toOption).map fun s => (s.entityId, s)
      | _ => []
    let vars : List (String × Value) := match j.getObjVal? "variables" with
      | .ok (.obj kvs) => kvs.toList.map fun (k, v) => (k, Value.ofJson v)
      | _ => []
    let parse := match j.getObjVal? "parse_result" with | .ok (.bool b) => b | _ => true
    let cond := match j.getObjVal? "condition" with | .ok (.bool b) => b | _ => false
    match compile src with
    | .error e => Json.mkObj [("unsupported", e)]
    | .ok t =>
      match check t (vars.map (·.1)) with
      | .error e => Json.mkObj [("unsupported", e)]
      | .ok () =>
        let tz : Int := match j.getObjVal? "tz" with
          | .ok (.num t) => t.mantissa
          | _ => 0
        let now : Instant := match j.getObjVal? "now" with
          | .ok (.num n) => { utc := n.mantissa.toNat, tzOffsetSec := tz }
          | _ => { utc := 0, tzOffsetSec := tz }
        let ctx : Ctx := { states, vars, now }
        if cond then
          -- `condition.async_template`: render without parsing, compare to "true"
          match render t ctx false with
          | .ok (.str s) => Json.mkObj [("ok", true), ("type", "bool"), ("repr", boolStr (s.toLower == "true"))]
          | .ok _ => Json.mkObj [("ok", false), ("error", "unexpected result")]
          | .error e => Json.mkObj [("ok", false), ("error", e)]
        else
          match render t ctx parse with
          | .error e => Json.mkObj [("ok", false), ("error", e)]
          | .ok v =>
            match pyRepr v with
            | .ok r => Json.mkObj [("ok", true), ("type", typeName v), ("repr", r)]
            | .error e => Json.mkObj [("ok", false), ("error", e)]

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let line := line.trim
  if !line.isEmpty then
    stdout.putStrLn (handleLine line).compress
    stdout.flush
  loop stdin stdout

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout)
