/-
  `dt_util.parse_time` (`HALean.Template.parseTimeSeconds`), proved against what
  upstream computes: `str.split(":")` (here `List.splitOn ':'`, which splits
  the same way: `"a::b"` → `["a", "", "b"]`, `""` → `[""]`), Python's `int()`
  of the parts (`PyIntSpec`, proved in `HALean/Template/PyIntSpec.lean`) and
  `datetime.time`'s ranges.
-/
import HALean.Template.ParseTime
import HALean.Template.PyIntSpec

namespace HALean.Template

/-- `parse_time(s)` is the time `t` seconds after midnight. -/
def ParseTimeSpec (s : String) (t : Nat) : Prop :=
  ∃ p0 p1 rest h m sec, s.toList.splitOn ':' = p0 :: p1 :: rest ∧
    PyIntSpec p0 h ∧ PyIntSpec p1 m ∧
    ((rest = [] ∧ sec = 0) ∨ ∃ p2 r, rest = p2 :: r ∧ PyIntSpec p2 sec) ∧
    0 ≤ h ∧ h < 24 ∧ 0 ≤ m ∧ m < 60 ∧ 0 ≤ sec ∧ sec < 60 ∧
    (t : Int) = h * 3600 + m * 60 + sec

/-- **`parse_time`**: `parseTimeSeconds s = some t` exactly when upstream's
`parse_time(s)` returns the time `t` seconds after midnight (for ASCII text;
`none` is upstream's `None`). -/
theorem parseTimeSeconds_iff (s : String) (t : Nat) : parseTimeSeconds s = some t ↔ ParseTimeSpec s t := by
  unfold parseTimeSeconds ParseTimeSpec
  constructor
  · intro hp
    split at hp
    · rename_i p0 p1 rest hs
      simp only [Option.bind_eq_bind, Option.bind_eq_some_iff] at hp
      obtain ⟨h, hh, m, hm, sec, hsec, hr⟩ := hp
      split at hr
      · rename_i hrange
        simp only [Option.some.injEq] at hr
        refine ⟨p0, p1, rest, h, m, sec, hs, (parseIntChars_iff _ _).mp hh,
          (parseIntChars_iff _ _).mp hm, ?_, hrange.1, hrange.2.1, hrange.2.2.1, hrange.2.2.2.1,
          hrange.2.2.2.2.1, hrange.2.2.2.2.2, ?_⟩
        · cases rest with
          | nil => simp [parseTimeSecond] at hsec; exact .inl ⟨rfl, hsec.symm⟩
          | cons p2 r => exact .inr ⟨p2, r, rfl, (parseIntChars_iff _ _).mp hsec⟩
        · rw [← hr]; omega
      · cases hr
    · cases hp
  · rintro ⟨p0, p1, rest, h, m, sec, hs, h0, h1, hrest, r1, r2, r3, r4, r5, r6, ht⟩
    rw [hs]
    simp only [Option.bind_eq_bind, Option.bind_eq_some_iff]
    refine ⟨h, (parseIntChars_iff _ _).mpr h0, m, (parseIntChars_iff _ _).mpr h1, sec, ?_, ?_⟩
    · rcases hrest with ⟨rfl, rfl⟩ | ⟨p2, r, rfl, h2⟩
      · rfl
      · exact (parseIntChars_iff _ _).mpr h2
    · rw [if_pos ⟨r1, r2, r3, r4, r5, r6⟩]
      simp only [Option.some.injEq]
      omega

end HALean.Template
