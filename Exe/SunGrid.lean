import HALean.Automation.Sun
open HALean.Automation

/-- Print `nextEvent` (µs) for each line `lat lon elev sunrise now_us tz offset_us` on stdin. -/
def main : IO Unit := do
  let stdin ← IO.getStdin
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    let ws := (line.trimAscii.toString.splitOn " ").toArray
    let f (i : Nat) : Float := (Lean.Json.parse ws[i]! |>.toOption.bind fun j => match j with
      | .num n => some n.toFloat | _ => none).getD 0
    let i (k : Nat) : Int := (ws[k]!.toInt?).getD 0
    let obs : Sun.Observer := { latitude := f 0, longitude := f 1, elevation := f 2 }
    let r := Sun.nextEvent obs (ws[3]! == "1") (i 4) (i 5) (i 6)
    IO.println (match r with | some t => toString t | none => "none")
