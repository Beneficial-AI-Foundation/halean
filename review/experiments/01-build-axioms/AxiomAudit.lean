/-
Axiom audit. Collects the axioms of every theorem whose module is `HALean` or `HALean.*`,
including compiler-generated theorems (equation lemmas, `_proof_` auxiliaries, ...).
Run from the repository root after `lake build HALean`:
  lake env lean review/experiments/01-build-axioms/AxiomAudit.lean
Writes review/experiments/01-build-axioms/logs/axioms.tsv with one line per theorem:
  module <TAB> name <TAB> kind(source|generated) <TAB> comma-separated axioms
and prints a table of axiom sets.
-/
import HALean
import Lean
open Lean Elab Command

abbrev Memo := Std.HashMap Name (Array Name)

/-- Axioms a constant depends on, memoised over the whole environment. -/
partial def axiomsOf (env : Environment) (n : Name) : StateM Memo (Array Name) := do
  if let some r := (← get)[n]? then return r
  -- mark first: constants cannot be cyclic, but mutual inductives reference each other
  modify (·.insert n #[])
  let some ci := env.find? n | return #[]
  let deps : Array Name := match ci with
    | .axiomInfo _ => #[]
    | .defnInfo v => (v.type.getUsedConstants ++ v.value.getUsedConstants)
    | .thmInfo v => (v.type.getUsedConstants ++ v.value.getUsedConstants)
    | .opaqueInfo v => (v.type.getUsedConstants ++ v.value.getUsedConstants)
    | .quotInfo v => v.type.getUsedConstants
    | .ctorInfo v => v.type.getUsedConstants
    | .recInfo v => v.type.getUsedConstants
    | .inductInfo v => v.type.getUsedConstants ++ v.ctors.toArray
  let mut acc : NameSet := {}
  if ci matches .axiomInfo _ then acc := acc.insert n
  for d in deps do
    for a in (← axiomsOf env d) do acc := acc.insert a
  let r := acc.toArray.qsort Name.lt
  modify (·.insert n r)
  return r

def inHALean (m : Name) : Bool := m == `HALean || (`HALean).isPrefixOf m

run_cmd do
  let env ← getEnv
  let mut memo : Memo := {}
  let mut lines : Array String := #[]
  let mut table : Std.HashMap String (Nat × Nat) := {}
  let mut perMod : Std.HashMap Name (Nat × Nat) := {}
  let mut nAxiomDecl := 0
  let mut nOpaque := 0
  let mut sorryUsers : Array Name := #[]
  for (n, ci) in env.constants.toList do
    let some mi := env.getModuleIdxFor? n | continue
    let m := env.header.moduleNames[mi.toNat]!
    unless inHALean m do continue
    if ci matches .axiomInfo _ then nAxiomDecl := nAxiomDecl + 1
    if ci matches .opaqueInfo _ then nOpaque := nOpaque + 1
    unless ci matches .thmInfo _ do continue
    let (ax, memo') := (axiomsOf env n).run memo
    memo := memo'
    let hasRange := (← liftCoreM (findDeclarationRanges? n)).isSome
    let user := (privateToUserName? n).getD n
    let src := hasRange && !user.isInternalDetail
    let key := ", ".intercalate (ax.toList.map toString)
    let key := if key.isEmpty then "(none)" else key
    lines := lines.push s!"{m}\t{n}\t{if src then "source" else "generated"}\t{key}"
    let (a, b) := table.getD key (0, 0)
    table := table.insert key (if src then (a + 1, b) else (a, b + 1))
    let (a, b) := perMod.getD m (0, 0)
    perMod := perMod.insert m (if src then (a + 1, b) else (a, b + 1))
    if ax.contains ``sorryAx then sorryUsers := sorryUsers.push n
  let dir := "review/experiments/01-build-axioms/logs"
  IO.FS.writeFile s!"{dir}/axioms.tsv" ("\n".intercalate (lines.qsort (· < ·)).toList ++ "\n")
  let mut out := s!"theorems total: {lines.size}\naxiom declarations in HALean modules: {nAxiomDecl}\nopaque constants in HALean modules: {nOpaque}\ntheorems depending on sorryAx: {sorryUsers.size}\n\naxiom set\tsource theorems\tgenerated theorems\n"
  for (k, (a, b)) in table.toArray.qsort (fun x y => x.1 < y.1) do
    out := out ++ s!"{k}\t{a}\t{b}\n"
  out := out ++ "\nmodule\tsource theorems\tgenerated theorems\n"
  for (k, (a, b)) in perMod.toArray.qsort (fun x y => x.1.toString < y.1.toString) do
    out := out ++ s!"{k}\t{a}\t{b}\n"
  IO.FS.writeFile s!"{dir}/axioms-summary.txt" out
  logInfo out
