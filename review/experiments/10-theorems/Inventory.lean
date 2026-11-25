/-
Inventory of every source-written declaration in HALean.* modules, from the compiled environment.
Run from the repository root:  lake env lean review/experiments/10-theorems/Inventory.lean
Writes logs/decls.tsv:
  kind <TAB> module <TAB> name <TAB> startLine <TAB> endLine <TAB> HALean constants used in the type <TAB> HALean constants used in the value
kind is theorem | def | partial | opaque | inductive | structure | instance | other.  "partial" = `partial def` (opaqueInfo with an unsafe implementation).
For theorems the value column is left empty (proof terms are not needed).
-/
import HALean
import Lean
open Lean Elab Command

def inHALean (m : Name) : Bool := m == `HALean || (`HALean).isPrefixOf m

run_cmd do
  let env ← getEnv
  let modOf (n : Name) : Option Name := (env.getModuleIdxFor? n).map (env.header.moduleNames[·.toNat]!)
  let userName (n : Name) : Name := (privateToUserName? n).getD n
  let isSrc (n : Name) : CommandElabM Bool := do
    if (userName n).isInternalDetail then return false
    return (← liftCoreM (findDeclarationRanges? n)).isSome
  -- map auxiliary constants (match_1, _proof_3, eq_1 ...) to nothing; keep only source constants
  let mut srcSet : NameSet := {}
  let mut all : Array (Name × ConstantInfo × Name) := #[]
  for (n, ci) in env.constants.toList do
    let some m := modOf n | continue
    unless inHALean m do continue
    if ← isSrc n then
      srcSet := srcSet.insert n
      all := all.push (n, ci, m)
  -- direct uses, looking through auxiliary (non-source) HALean constants
  let rec expand (fuel : Nat) (seen : NameSet) (ns : Array Name) : NameSet := Id.run do
    let mut seen := seen
    let mut next : Array Name := #[]
    for c in ns do
      if seen.contains c then continue
      let some m := modOf c | continue
      unless inHALean m do continue
      seen := seen.insert c
      if !srcSet.contains c then
        if let some ci := env.find? c then
          next := next ++ ci.type.getUsedConstants ++ (ci.value?.map (·.getUsedConstants)).getD #[]
          -- unsafe implementation of partial defs
    if fuel == 0 || next.isEmpty then return seen
    return expand (fuel - 1) seen next
  let uses (e : Expr) : String :=
    let s := expand 6 {} e.getUsedConstants
    " ".intercalate ((s.toArray.filter srcSet.contains).qsort Name.lt |>.toList.map (fun n => toString (userName n)))
  let mut lines : Array String := #[]
  for (n, ci, m) in all do
    let some r ← liftCoreM (findDeclarationRanges? n) | continue
    let isInst ← liftCoreM (Meta.isInstance n)
    let implName := Compiler.mkUnsafeRecName n
    let kind := match ci with
      | .thmInfo _ => "theorem"
      | .defnInfo _ => if isInst then "instance" else "def"
      | .opaqueInfo _ => if (env.find? implName).isSome || (env.find? (n ++ `_unsafe_rec)).isSome then "partial" else "opaque"
      | .inductInfo _ => if isStructure env n then "structure" else "inductive"
      | _ => "other"
    if kind == "other" then continue
    let ty := uses ci.type
    let val := match ci with
      | .thmInfo _ => ""
      | .opaqueInfo _ =>
          -- a partial def's real body is in the unsafe implementation
          match env.find? implName with
          | some ici => (ici.value?.map uses).getD ""
          | none => (ci.value?.map uses).getD ""
      | _ => (ci.value?.map uses).getD ""
    lines := lines.push s!"{kind}\t{m}\t{userName n}\t{r.range.pos.line}\t{r.range.endPos.line}\t{ty}\t{val}"
  IO.FS.writeFile "review/experiments/10-theorems/logs/decls.tsv" ("\n".intercalate (lines.qsort (· < ·)).toList ++ "\n")
  logInfo s!"declarations: {lines.size}"
