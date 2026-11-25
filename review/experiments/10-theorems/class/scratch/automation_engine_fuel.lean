import HALean.Automation.Engine
open HALean HALean.Automation
def showRes (x : ExecRes × List Cmd × ExecCtx) : String :=
  match x.1 with
  | .done _ e => s!"done {repr e}"
  | .blocked _ => "blocked"
  | .spawn .. => "spawn"
def mk (as : List Action) : Run := { id := 0, autoIdx := 0, triggerId := "", frames := [.seq as false] }
def ctx : ExecCtx := { env := { states := [], now := {utc := 0} }, nextCallId := 0 }
#eval showRes (exec ctx (mk [.repeatCount 300000 [.delay 0]]))
#eval showRes (exec ctx (mk [.repeatCount 400000 [.delay 0]]))
#eval showRes (exec ctx (mk [.repeatWhile [] [.delay 0]]))
#eval showRes (exec ctx (mk [.repeatWhile [] (List.replicate 100 (.delay 0))]))
