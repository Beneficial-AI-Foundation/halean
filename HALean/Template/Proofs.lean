/-
  First theorems about the template service.
-/
import HALean.Template.Render
open Lean

namespace HALean.Template

/-- A static template (no `{{`, `{%`, `{#`) renders to its own text when the
result is not parsed: nothing is evaluated (`Template.async_render`'s
`is_static` shortcut). -/
theorem render_static (t : Tmpl) (ctx : Ctx) (h : t.isStatic = true) :
    render t ctx false = .ok (.str t.src) := by
  simp [render, h]

/-- `result_as_boolean(None)` is False. -/
theorem resultAsBoolean_none : resultAsBoolean .none = false := rfl

/-- `cv.boolean` returns a bool unchanged. -/
theorem cvBoolean_bool (b : Bool) : cvBoolean (.bool b) = some b := rfl

/-- `iif` with `if_none` given picks it exactly when the value is None. -/
theorem iif_none (t f : Option Value) (x : Value) :
    iif .none t f (some x) = x := rfl

/-- Without `if_none`, `iif` is a plain truthiness test. -/
theorem iif_truthy (v : Value) (t f : Option Value) :
    iif v t f none = if truthy v then t.getD (.bool true) else f.getD (.bool false) := by
  cases v <;> rfl

end HALean.Template
