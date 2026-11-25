/-
  Axiom audit: every theorem declared in a `HALean.*` module (private and
  generated ones included, e.g. equation lemmas) may depend only on the
  standard axioms `propext`, `Quot.sound` and `Classical.choice`. Anything
  else (`sorryAx`, `Lean.ofReduceBool` from `native_decide`, a declared
  `axiom`) fails. It also fails when a `.lean` file under `HALean/` is not
  imported by `HALean.lean`, since its theorems would escape the audit (and
  the default build).

    lake build HALean && lake env lean tools/Axioms.lean

  Run by CI (`.github/workflows/lean_action_ci.yml`).
-/
import Lean
import HALean
open Lean Elab Command

namespace HALeanAxioms

def allowed : List Name := [``propext, ``Quot.sound, ``Classical.choice]

/-- The module names of the `.lean` files under `HALean/`. -/
partial def sourceModules (dir : System.FilePath) : IO (Array Name) := do
  let mut out := #[]
  for p in ← System.FilePath.walkDir dir do
    if p.extension == some "lean" then
      let rel := (p.withExtension "").components
      out := out.push (rel.foldl (fun n s => Name.str n s) Name.anonymous)
  return out

def audit : CommandElabM Unit := do
  let env ← getEnv
  let modules := env.header.moduleNames
  -- every source module is in the environment
  let srcs ← liftIO (sourceModules "HALean")
  let missing := srcs.filter (!modules.contains ·)
  unless missing.isEmpty do
    throwError "modules not imported by HALean.lean (their theorems escape the audit): {missing}"
  let mut theorems : Nat := 0
  let mut counts : Std.HashMap (List Name) Nat := {}
  let mut bad : Array (Name × Array Name) := #[]
  for (name, ci) in env.constants.map₁.toList do
    let .thmInfo _ := ci | continue
    let some idx := env.getModuleIdxFor? name | continue
    let some mod := modules[idx.toNat]? | continue
    unless (`HALean).isPrefixOf mod do continue
    theorems := theorems + 1
    let axs ← liftCoreM (collectAxioms name)
    let key := (axs.qsort Name.lt).toList
    counts := counts.insert key (counts.getD key 0 + 1)
    let others := axs.filter (!allowed.contains ·)
    unless others.isEmpty do bad := bad.push (name, others)
  for (axs, n) in counts.toList do
    logInfo m!"{n} theorems use {if axs.isEmpty then "no axioms" else toString axs}"
  unless bad.isEmpty do
    throwError "theorems using axioms beyond propext, Quot.sound, Classical.choice:\n{bad.toList}"
  logInfo m!"{theorems} theorems in HALean.* modules, all within the standard axioms"

elab "#audit_axioms" : command => audit

end HALeanAxioms

#audit_axioms
