import HALean.Automation
open HALean HALean.Automation

/-- JSON-lines service: reads inputs on stdin, writes one batch per input on
stdout. All I/O lives here; everything it calls is pure. -/
partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (e : Engine) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return  -- EOF
  let line := line.trim
  if line.isEmpty then loop stdin stdout e else
  let (e', out) := processLine e line
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout e'

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout) default
