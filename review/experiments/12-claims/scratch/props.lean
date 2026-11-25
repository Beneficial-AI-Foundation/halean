import HALean.Automation.Config
open HALean.Automation Lean
def show1 (s : String) : String :=
  match Json.parse s with
  | .ok j => (match maxRunsOf j with | .ok n => s!"{s} -> {n}" | .error e => s!"{s} refused: {e}")
  | .error e => s!"{s} parse error {e}"
#eval ["2.5", "\"3\"", "0", "1", "-4", "true", "null", "\"2.5\"", "10.0", "2", "1e1"].map show1
