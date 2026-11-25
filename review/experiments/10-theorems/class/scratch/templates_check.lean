import HALean
open HALean HALean.Template
#eval ("\x0cfoo\x0b".trim).length
#eval (match compile "\x0cfoo\x0b" with | .ok t => (t.src.length, t.isStatic) | .error _ => (0,false))
#eval parseTimeSeconds (String.ofList (List.replicate 4301 '0') ++ "1:00")
#eval (parseIntStr (String.ofList (List.replicate 4301 '1'))).isSome
#eval cvBooleanText "\x1ctrue\x1f"
#eval parseTimeSeconds "1:2:3:zzz"
#eval parseTimeSeconds "\x0b1:02"
#print axioms render_static
#print axioms cvBooleanText_iff
#print axioms parseIntChars_iff
#print axioms isNumericStr_iff
#print axioms daysFromCivil_civilFromDays
#print axioms gg_ends
#print pyEq
#print Rx.run
#print renderNodes
#eval (repr (parseResult "١٢"), repr (parseResult "12\n"), isNumericStr "12\n", isNumericStr "١٢")
