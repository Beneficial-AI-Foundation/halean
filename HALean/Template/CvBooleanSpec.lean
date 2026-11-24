/-
  `cv.boolean` on strings, proved against upstream: `value.lower().strip()`
  is one of the true or false words.
-/
import HALean.Template.CvBoolean
import HALean.Template.PyIntSpec

namespace HALean.Template

/-- Upstream on an ASCII string `s`: `s.lower()` is a word of `b`'s list with
whitespace around it (so `.strip()` gives the word). -/
def CvBooleanSpec (s : String) (b : Bool) : Prop :=
  ∃ w w1 w2, (b = true ∧ w ∈ CV_TRUE_WORDS ∨ b = false ∧ w ∈ CV_FALSE_WORDS) ∧
    s.toList.map Char.toLower = w1 ++ w.toList ++ w2 ∧
    (∀ c ∈ w1, pyIsSpace c) ∧ (∀ c ∈ w2, pyIsSpace c)

theorem words_ends (w : String) (h : w ∈ CV_TRUE_WORDS ∨ w ∈ CV_FALSE_WORDS) :
    w.toList ≠ [] ∧ (w.toList.head?.all fun c => !pyIsSpace c) ∧
      (w.toList.getLast?.all fun c => !pyIsSpace c) := by
  simp only [CV_TRUE_WORDS, CV_FALSE_WORDS, List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with h | h <;> rcases h with rfl | rfl | rfl | rfl | rfl <;> decide

/-- **`cv.boolean` on strings** (ASCII text, where `lower()` is
`Char.toLower`): `cvBooleanText s = some b` exactly when upstream returns
`b`; `none` is upstream's `Invalid`. -/
theorem cvBooleanText_iff (s : String) (b : Bool) : cvBooleanText s = some b ↔ CvBooleanSpec s b := by
  unfold cvBooleanText CvBooleanSpec
  constructor
  · intro h
    obtain ⟨w1, w2, hs, h1, h2⟩ := stripBy_split pyIsSpace (s.toList.map Char.toLower)
    have key : ∀ w, cvBooleanCore s = w → (s.toList.map Char.toLower) = w1 ++ w.toList ++ w2 := by
      intro w hw
      rw [← hw]; unfold cvBooleanCore; rw [String.toList_ofList]; exact hs
    dsimp only at h
    split at h
    · rename_i ht
      simp only [Option.some.injEq] at h; subst h
      exact ⟨_, w1, w2, .inl ⟨rfl, List.contains_iff_mem.mp ht⟩, key _ rfl, h1, h2⟩
    · split at h
      · rename_i _ hf
        simp only [Option.some.injEq] at h; subst h
        exact ⟨_, w1, w2, .inr ⟨rfl, List.contains_iff_mem.mp hf⟩, key _ rfl, h1, h2⟩
      · cases h
  · rintro ⟨w, w1, w2, hw, hs, h1, h2⟩
    have hw' : w ∈ CV_TRUE_WORDS ∨ w ∈ CV_FALSE_WORDS := by
      rcases hw with ⟨-, h⟩ | ⟨-, h⟩
      · exact .inl h
      · exact .inr h
    obtain ⟨hne, hh, hl⟩ := words_ends w hw'
    have hc : cvBooleanCore s = w := by
      unfold cvBooleanCore
      rw [hs, stripBy_eq h1 h2 hh hl hne, String.ofList_toList]
    dsimp only
    rw [hc]
    rcases hw with ⟨rfl, ht⟩ | ⟨rfl, hf⟩
    · simp [List.contains_iff_mem.mpr ht]; exact ht
    · have : ¬ w ∈ CV_TRUE_WORDS := by
        intro ht
        simp only [CV_TRUE_WORDS, CV_FALSE_WORDS, List.mem_cons, List.not_mem_nil, or_false] at ht hf
        rcases hf with rfl | rfl | rfl | rfl | rfl <;> simp at ht
      simp [List.contains_iff_mem.mpr hf, this]; exact hf

end HALean.Template
