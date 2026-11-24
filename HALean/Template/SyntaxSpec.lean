/-
  `is_template_string` (`HALean.Template.isTemplateString`), proved against
  upstream's `"{" in s and ("{%" in s or "{{" in s or "{#" in s)`.
-/
import HALean.Template.Syntax

namespace HALean.Template

/-- `is_template_string(s)`: `"{" in s and ("{%" in s or "{{" in s or "{#" in s)`. -/
def TemplateStringSpec (cs : List Char) : Prop :=
  '{' ∈ cs ∧ ∃ a b c, cs = a ++ '{' :: c :: b ∧ (c = '%' ∨ c = '{' ∨ c = '#')

theorem hasJinjaOpen_iff (cs : List Char) :
    hasJinjaOpen cs = true ↔ ∃ a b c, cs = a ++ '{' :: c :: b ∧ (c = '%' ∨ c = '{' ∨ c = '#') := by
  induction cs with
  | nil => simp [hasJinjaOpen]
  | cons x r ih =>
    have step : hasJinjaOpen (x :: r) =
        ((x == '{' && (r.head?.any fun c => c == '%' || c == '{' || c == '#')) || hasJinjaOpen r) := by
      by_cases hx : x = '{'
      · subst hx
        cases r with
        | nil => simp [hasJinjaOpen]
        | cons c r => simp [hasJinjaOpen, Bool.or_assoc]
      · have : (x == '{') = false := by simpa using hx
        rw [this, Bool.false_and, Bool.false_or]
        conv => lhs; unfold hasJinjaOpen
        split
        · rename_i h; simp at h; exact absurd h.1 hx
        · rename_i h; simp at h; obtain ⟨-, rfl⟩ := h; rfl
        · simp at *
    rw [step, Bool.or_eq_true, ih]
    constructor
    · rintro (h | ⟨a, b, c, rfl, hc⟩)
      · simp only [Bool.and_eq_true, beq_iff_eq] at h
        obtain ⟨rfl, h⟩ := h
        cases r with
        | nil => simp at h
        | cons c r => exact ⟨[], r, c, rfl, by simpa [Bool.or_eq_true, or_assoc] using h⟩
      · exact ⟨x :: a, b, c, rfl, hc⟩
    · rintro ⟨a, b, c, h, hc⟩
      cases a with
      | nil =>
        simp only [List.nil_append, List.cons.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        left; rcases hc with rfl | rfl | rfl <;> simp
      | cons y a =>
        simp only [List.cons_append, List.cons.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact .inr ⟨a, b, c, rfl, hc⟩

theorem isTemplateString_iff (s : String) :
    isTemplateString s = true ↔ TemplateStringSpec s.toList := by
  unfold isTemplateString
  rw [hasJinjaOpen_iff]
  constructor
  · rintro ⟨a, b, c, h, hc⟩; exact ⟨by rw [h]; simp, a, b, c, h, hc⟩
  · exact fun h => h.2

end HALean.Template
