import HALean.Script
open HALean HALean.Script

/-- JSON-lines service: reads inputs on stdin, writes one batch per input on
stdout. All I/O lives here; everything it calls is pure. -/
partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (sv : Service) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return  -- EOF
  let line := line.trim
  if line.isEmpty then loop stdin stdout sv else
  let (sv', out) := processLine sv line
  stdout.putStrLn out.compress
  stdout.flush
  loop stdin stdout sv'

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout) default
