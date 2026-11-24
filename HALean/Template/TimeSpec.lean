/-
  The calendar arithmetic of `HALean/Template/Time.lean`, proved against the
  proleptic Gregorian calendar that Python's `datetime` uses:

    * `civilFromDays` and `daysFromCivil` (Howard Hinnant's algorithms) are
      inverse bijections between day numbers and valid `(year, month, day)`
      triples, for every integer day number and every year (no range limit);
    * `daysFromCivil` agrees with the calendar's month and year lengths
      (`daysInMonth`, `isLeap`) and its 400-year period of 146097 days;
    * `toCivil` / `fromCivil` are inverse on valid `Civil`s (`Civil.valid`);
    * `weekdayOf`, `fdivmod`, `tdParts`, `pad0`, `padYear`, `offsetStr`,
      `isoformat` and the `strftime` name tables.
-/
import HALean.Template.Time

namespace HALean.Template

/-! ## The year-of-era computation

Inside one 400-year era, day `doe` (0 = 1 March of year 0 of the era) lies in
year `yoe = (doe - doe/1460 + doe/36524 - doe/146096) / 365`. Proved by
checking the first and last day of each of the 400 years and monotonicity. -/

private def gg (n : Int) : Int := n - n / 1460 + n / 36524 - n / 146096
private def ff (y : Int) : Int := 365 * y + y / 4 - y / 100
/-- The March-based year `y` of an era ends with a 29 February. -/
private def lp (y : Int) : Bool := y % 4 == 3 && (y % 100 != 99 || y == 399)

private theorem lp_iff (y : Int) : lp y = true ↔ y % 4 = 3 ∧ (y % 100 ≠ 99 ∨ y = 399) := by
  simp [lp]

private theorem gg_step (n : Int) (h0 : 0 ≤ n) (h1 : n < 146096) : gg n ≤ gg (n + 1) := by
  unfold gg; omega

private theorem gg_mono (a : Int) (k : Nat) (h0 : 0 ≤ a) (h1 : a + k ≤ 146096) : gg a ≤ gg (a + k) := by
  induction k with
  | zero => simp
  | succ k ih =>
    have := ih (by omega)
    have := gg_step (a + k) (by omega) (by omega)
    rw [show a + ((k + 1 : Nat) : Int) = a + k + 1 by omega]
    omega

private theorem gg_ends : ∀ y : Nat, y < 400 →
    (gg (ff y) / 365 == (y : Int) && gg (ff y + 364 + (if lp y then 1 else 0)) / 365 == (y : Int)) = true := by
  decide +kernel

private theorem ff_hi (y : Int) (h : 0 ≤ y ∧ y ≤ 399) :
    0 ≤ ff y ∧ ff y + 364 + (if lp y then 1 else 0) ≤ 146096 := by
  unfold ff; split <;> omega

/-- The year of era is recovered from the day of era. -/
private theorem yoe_of (doe yoe doy : Int) (h : 0 ≤ yoe ∧ yoe ≤ 399) (hd : 0 ≤ doy ∧ doy ≤ 365)
    (hl : doy = 365 → lp yoe = true) (he : doe = ff yoe + doy) : gg doe / 365 = yoe := by
  obtain ⟨y, rfl⟩ := Int.eq_ofNat_of_zero_le h.1
  have e := gg_ends y (by omega)
  simp only [Bool.and_eq_true, beq_iff_eq] at e
  have hhi := ff_hi y h
  have m1 := gg_mono (ff y) doy.toNat hhi.1 (by have := hhi.2; split at this <;> simp_all <;> omega)
  have m2 := gg_mono doe (ff y + 364 + (if lp y then 1 else 0) - doe).toNat (by omega)
    (by have := hhi.2; split at this <;> simp_all <;> omega)
  have e1 : ff ↑y + ↑doy.toNat = doe := by omega
  have e2 : doe + ↑(ff ↑y + 364 + (if lp ↑y = true then 1 else 0) - doe).toNat
      = ff ↑y + 364 + (if lp ↑y = true then 1 else 0) := by
    split <;> simp_all <;> omega
  rw [e1] at m1; rw [e2] at m2
  omega

/-- Every day of an era lies in one of its 400 years. -/
private theorem yoe_ex (n : Nat) (h : n ≤ 146096) : ∃ y : Int, 0 ≤ y ∧ y ≤ 399 ∧ ff y ≤ n ∧
    (n : Int) ≤ ff y + 365 ∧ ((n : Int) = ff y + 365 → lp y = true) := by
  induction n with
  | zero => exact ⟨0, by decide⟩
  | succ n ih =>
    obtain ⟨y, h0, h1, h2, h3, h4⟩ := ih (by omega)
    have hl := lp_iff y
    have h399 : y = 399 → ff y = 145731 ∧ lp y = true := by
      intro h; rw [h]; exact ⟨by decide, by decide⟩
    by_cases hlt : (n : Int) + 1 < ff y + 365
    · exact ⟨y, h0, h1, by omega, by omega, by omega⟩
    · by_cases hly : lp y = true
      · by_cases heq : (n : Int) + 1 = ff y + 365
        · exact ⟨y, h0, h1, by omega, by omega, fun _ => hly⟩
        · have := hl.1 hly
          have hy : y ≠ 399 := fun h => by have := (h399 h).1; omega
          have : ff (y + 1) = ff y + 366 := by unfold ff; omega
          exact ⟨y + 1, by omega, by omega, by omega, by omega, by omega⟩
      · have hn : ¬ (y % 4 = 3 ∧ (y % 100 ≠ 99 ∨ y = 399)) := fun h => hly (hl.2 h)
        have hy : y ≠ 399 := fun h => hly (h399 h).2
        have hne : (n : Int) ≠ ff y + 365 := fun h => hly (h4 h)
        have : ff (y + 1) = ff y + 365 := by unfold ff; omega
        exact ⟨y + 1, by omega, by omega, by omega, by omega, by omega⟩

private theorem civil_eq (z : Int) : civilFromDays z =
    (let era := (z + 719468) / 146097
     let doe := z + 719468 - era * 146097
     let yoe := gg doe / 365
     let doy := doe - ff yoe
     let mp := (5 * doy + 2) / 153
     let m := if mp < 10 then mp + 3 else mp - 9
     ((if m ≤ 2 then yoe + era * 400 + 1 else yoe + era * 400), m.toNat,
       (doy - (153 * mp + 2) / 5 + 1).toNat)) := rfl

/-- `civilFromDays` on a day given by its era, year of era and day of year. -/
private theorem civil_of_parts (era yoe doy z : Int) (hy : 0 ≤ yoe ∧ yoe ≤ 399)
    (hd : 0 ≤ doy ∧ doy ≤ 365) (hl : doy = 365 → lp yoe = true)
    (hz : z + 719468 = era * 146097 + ff yoe + doy) :
    civilFromDays z =
      ((if (if (5 * doy + 2) / 153 < 10 then (5 * doy + 2) / 153 + 3 else (5 * doy + 2) / 153 - 9) ≤ 2
          then yoe + era * 400 + 1 else yoe + era * 400),
        (if (5 * doy + 2) / 153 < 10 then (5 * doy + 2) / 153 + 3 else (5 * doy + 2) / 153 - 9).toNat,
        (doy - (153 * ((5 * doy + 2) / 153) + 2) / 5 + 1).toNat) := by
  have hhi := ff_hi yoe hy
  have hb : 0 ≤ ff yoe + doy ∧ ff yoe + doy ≤ 146096 := by
    have := hhi.2
    split at this
    · omega
    · rename_i hn
      have : doy ≠ 365 := fun h => hn (hl h)
      omega
  have e1 : (z + 719468) / 146097 = era := by omega
  have e2 : z + 719468 - era * 146097 = ff yoe + doy := by omega
  have e3 := yoe_of (ff yoe + doy) yoe doy hy hd hl rfl
  have e4 : ff yoe + doy - ff yoe = doy := by omega
  rw [civil_eq]
  simp only [e1, e2, e3, e4]

private theorem civil_spec (z : Int) : ∃ era yoe doy mp : Int, 0 ≤ yoe ∧ yoe ≤ 399 ∧ 0 ≤ doy ∧ doy ≤ 365 ∧
    (doy = 365 → lp yoe = true) ∧ z + 719468 = era * 146097 + ff yoe + doy ∧ mp = (5 * doy + 2) / 153 ∧
    civilFromDays z = ((if (if mp < 10 then mp + 3 else mp - 9) ≤ 2 then yoe + era * 400 + 1 else yoe + era * 400),
      (if mp < 10 then mp + 3 else mp - 9).toNat, (doy - (153 * mp + 2) / 5 + 1).toNat) := by
  have hdoe : 0 ≤ z + 719468 - (z + 719468) / 146097 * 146097 ∧
      z + 719468 - (z + 719468) / 146097 * 146097 ≤ 146096 := by omega
  obtain ⟨y, h0, h1, h2, h3, h4⟩ := yoe_ex (z + 719468 - (z + 719468) / 146097 * 146097).toNat (by omega)
  rw [Int.toNat_of_nonneg hdoe.1] at h2 h3 h4
  refine ⟨(z + 719468) / 146097, y, z + 719468 - (z + 719468) / 146097 * 146097 - ff y, _,
    h0, h1, by omega, by omega, fun h => h4 (by omega), by omega, rfl, ?_⟩
  exact civil_of_parts _ _ _ _ ⟨h0, h1⟩ ⟨by omega, by omega⟩ (fun h => h4 (by omega)) (by omega)

/-! ## `civilFromDays` and `daysFromCivil` -/

/-- **Round trip, days → date → days**: the date `civilFromDays` gives for a
day number has that day number, for every integer `z`. -/
theorem daysFromCivil_civilFromDays (z : Int) :
    daysFromCivil (civilFromDays z).1 (civilFromDays z).2.1 (civilFromDays z).2.2 = z := by
  obtain ⟨era, yoe, doy, mp, h0, h1, h2, h3, h4, hz, hmp, hc⟩ := civil_spec z
  rw [hc]
  have hr : mp = 0 ∨ mp = 1 ∨ mp = 2 ∨ mp = 3 ∨ mp = 4 ∨ mp = 5 ∨ mp = 6 ∨ mp = 7 ∨ mp = 8 ∨ mp = 9 ∨
      mp = 10 ∨ mp = 11 := by omega
  unfold ff at hz
  rcases hr with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [daysFromCivil] <;> omega

/-- The month `civilFromDays` returns is a month, and the day exists in it:
the result is always a valid calendar date. -/
theorem civilFromDays_valid (z : Int) :
    1 ≤ (civilFromDays z).2.1 ∧ (civilFromDays z).2.1 ≤ 12 ∧ 1 ≤ (civilFromDays z).2.2 ∧
      (civilFromDays z).2.2 ≤ daysInMonth (civilFromDays z).1 (civilFromDays z).2.1 := by
  obtain ⟨era, yoe, doy, mp, h0, h1, h2, h3, h4, hz, hmp, hc⟩ := civil_spec z
  rw [hc]
  have hr : mp = 0 ∨ mp = 1 ∨ mp = 2 ∨ mp = 3 ∨ mp = 4 ∨ mp = 5 ∨ mp = 6 ∨ mp = 7 ∨ mp = 8 ∨ mp = 9 ∨
      mp = 10 ∨ mp = 11 := by omega
  have hl : doy = 365 → yoe % 4 = 3 ∧ (yoe % 100 ≠ 99 ∨ yoe = 399) := fun h => (lp_iff yoe).1 (h4 h)
  rcases hr with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [daysInMonth, isLeap] <;> (try split) <;> omega

private theorem month_inv (mp dd : Int) (hmp : 0 ≤ mp ∧ mp ≤ 11) (hd : 0 ≤ dd ∧ dd ≤ 30)
    (h30 : mp = 1 ∨ mp = 3 ∨ mp = 6 ∨ mp = 8 → dd ≤ 29) (h11 : mp = 11 → dd ≤ 28) :
    (5 * ((153 * mp + 2) / 5 + dd) + 2) / 153 = mp ∧ (153 * mp + 2) / 5 + dd ≤ 365 ∧
      ((153 * mp + 2) / 5 + dd = 365 → mp = 11 ∧ dd = 28) := by
  have hr : mp = 0 ∨ mp = 1 ∨ mp = 2 ∨ mp = 3 ∨ mp = 4 ∨ mp = 5 ∨ mp = 6 ∨ mp = 7 ∨ mp = 8 ∨ mp = 9 ∨
      mp = 10 ∨ mp = 11 := by omega
  rcases hr with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> omega

private theorem daysInMonth_facts (y : Int) (m d : Nat) (hd2 : d ≤ daysInMonth y m) :
    d ≤ 31 ∧ (m = 4 ∨ m = 6 ∨ m = 9 ∨ m = 11 → d ≤ 30) ∧
      (m = 2 → d ≤ 29 ∧ (d = 29 → y % 4 = 0 ∧ y % 100 ≠ 0 ∨ y % 400 = 0)) := by
  unfold daysInMonth at hd2
  split at hd2
  · simp only [isLeap, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq] at hd2
    split at hd2 <;> omega
  all_goals exact ⟨by omega, fun h => by first | omega | simp_all, fun h => by first | omega | simp_all⟩

/-- **Round trip, date → days → date**: `civilFromDays` recovers every valid
calendar date from its day number, in every year. -/
theorem civilFromDays_daysFromCivil (y : Int) (m d : Nat) (hm1 : 1 ≤ m) (hm2 : m ≤ 12)
    (hd1 : 1 ≤ d) (hd2 : d ≤ daysInMonth y m) : civilFromDays (daysFromCivil y m d) = (y, m, d) := by
  obtain ⟨f1, f2, f3⟩ := daysInMonth_facts y m d hd2
  by_cases h : m ≤ 2
  · have hl := lp_iff ((y - 1) - (y - 1) / 400 * 400)
    obtain ⟨g1, g2, g3⟩ := month_inv ((m : Int) + 9) ((d : Int) - 1) (by omega) (by omega) (by omega) (by omega)
    rw [civil_of_parts ((y - 1) / 400) ((y - 1) - (y - 1) / 400 * 400)
      ((153 * ((m : Int) + 9) + 2) / 5 + ((d : Int) - 1)) _ (by omega) (by omega)
      (fun h => hl.2 (by omega)) (by simp [daysFromCivil, ff, h]; omega)]
    simp only [g1, Prod.mk.injEq]
    refine ⟨?_, ?_, ?_⟩ <;> (repeat' split) <;> omega
  · obtain ⟨g1, g2, g3⟩ := month_inv ((m : Int) - 3) ((d : Int) - 1) (by omega) (by omega) (by omega) (by omega)
    rw [civil_of_parts (y / 400) (y - y / 400 * 400)
      ((153 * ((m : Int) - 3) + 2) / 5 + ((d : Int) - 1)) _ (by omega) (by omega)
      (fun h => by omega) (by simp [daysFromCivil, ff, h]; omega)]
    simp only [g1, Prod.mk.injEq]
    refine ⟨?_, ?_, ?_⟩ <;> (repeat' split) <;> omega

/-- Two valid dates with the same day number are the same date. -/
theorem daysFromCivil_inj (y y' : Int) (m d m' d' : Nat) (hm : 1 ≤ m ∧ m ≤ 12) (hd : 1 ≤ d ∧ d ≤ daysInMonth y m)
    (hm' : 1 ≤ m' ∧ m' ≤ 12) (hd' : 1 ≤ d' ∧ d' ≤ daysInMonth y' m')
    (h : daysFromCivil y m d = daysFromCivil y' m' d') : y = y' ∧ m = m' ∧ d = d' := by
  have e := civilFromDays_daysFromCivil y m d hm.1 hm.2 hd.1 hd.2
  rw [h, civilFromDays_daysFromCivil y' m' d' hm'.1 hm'.2 hd'.1 hd'.2] at e
  simp only [Prod.mk.injEq] at e
  exact ⟨e.1.symm, e.2.1.symm, e.2.2.symm⟩

/-- Day 0 is 1970-01-01 (the Unix epoch). -/
theorem civilFromDays_zero : civilFromDays 0 = (1970, 1, 1) := by decide

theorem daysFromCivil_epoch : daysFromCivil 1970 1 1 = 0 := by decide

/-- The next day of the month is the next day number. -/
theorem daysFromCivil_succ_day (y : Int) (m d : Nat) :
    daysFromCivil y m (d + 1) = daysFromCivil y m d + 1 := by
  simp only [daysFromCivil]; omega

/-- A month is `daysInMonth` days long: the first of the next month comes
that many days after the first of this one. -/
theorem daysFromCivil_next_month (y : Int) (m : Nat) (hm1 : 1 ≤ m) (hm2 : m ≤ 11) :
    daysFromCivil y (m + 1) 1 = daysFromCivil y m 1 + daysInMonth y m := by
  have hm : m = 1 ∨ m = 2 ∨ m = 3 ∨ m = 4 ∨ m = 5 ∨ m = 6 ∨ m = 7 ∨ m = 8 ∨ m = 9 ∨ m = 10 ∨ m = 11 := by
    omega
  rcases hm with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp [daysFromCivil, daysInMonth, isLeap] <;> (try split) <;> omega

/-- 1 January follows 31 December. -/
theorem daysFromCivil_next_year (y : Int) : daysFromCivil (y + 1) 1 1 = daysFromCivil y 12 31 + 1 := by
  simp [daysFromCivil]; omega

/-- A year is 366 days long when it is a leap year, 365 otherwise. -/
theorem daysFromCivil_year_length (y : Int) :
    daysFromCivil (y + 1) 1 1 = daysFromCivil y 1 1 + (if isLeap y then 366 else 365) := by
  simp [daysFromCivil, isLeap]; split <;> omega

/-- The Gregorian calendar repeats every 400 years = 146097 days. -/
theorem daysFromCivil_add_400 (y : Int) (m d : Nat) :
    daysFromCivil (y + 400) m d = daysFromCivil y m d + 146097 := by
  simp only [daysFromCivil]; split <;> omega

/-! ## `isLeap`, `daysInMonth` -/

/-- The Gregorian leap-year rule. -/
theorem isLeap_iff (y : Int) : isLeap y = true ↔ (y % 4 = 0 ∧ y % 100 ≠ 0) ∨ y % 400 = 0 := by
  simp [isLeap]

theorem isLeap_add_400 (y : Int) : isLeap (y + 400) = isLeap y := by
  rw [Bool.eq_iff_iff, isLeap_iff, isLeap_iff]; omega

/-- A year that is not a multiple of 4 is not a leap year; a multiple of 4
that is not a multiple of 100 is. -/
theorem isLeap_of_not_century (y : Int) (h : y % 100 ≠ 0) : isLeap y = (y % 4 == 0) := by
  rw [Bool.eq_iff_iff, isLeap_iff]; simp only [beq_iff_eq]; omega

theorem daysInMonth_bounds (y : Int) (m : Nat) : 28 ≤ daysInMonth y m ∧ daysInMonth y m ≤ 31 := by
  unfold daysInMonth; split <;> (try split) <;> omega

/-- February has 29 days exactly in leap years. -/
theorem daysInMonth_feb (y : Int) : daysInMonth y 2 = 29 ↔ isLeap y = true := by
  simp only [daysInMonth]; split <;> simp_all

/-- Only February's length depends on the year. -/
theorem daysInMonth_of_ne_feb (y y' : Int) (m : Nat) (h : m ≠ 2) : daysInMonth y m = daysInMonth y' m := by
  unfold daysInMonth; split <;> simp_all

/-! ## `fdivmod` (Python's `divmod`) -/

/-- For a positive divisor, `divmod(a, b) = (q, r)` with `a = q * b + r` and
`0 ≤ r < b`. -/
theorem fdivmod_spec (a b : Int) (hb : 0 < b) :
    a = (fdivmod a b).1 * b + (fdivmod a b).2 ∧ 0 ≤ (fdivmod a b).2 ∧ (fdivmod a b).2 < b := by
  simp only [fdivmod, Int.fdiv_eq_ediv_of_nonneg a (Int.le_of_lt hb),
    Int.fmod_eq_emod_of_nonneg a (Int.le_of_lt hb)]
  refine ⟨?_, Int.emod_nonneg _ (Int.ne_of_gt hb), Int.emod_lt_of_pos _ hb⟩
  rw [Int.mul_comm]; exact (Int.mul_ediv_add_emod a b).symm

/-- The quotient and remainder are the only pair with those properties. -/
theorem fdivmod_unique (a b q r : Int) (hb : 0 < b) (h : a = q * b + r) (hr : 0 ≤ r ∧ r < b) :
    fdivmod a b = (q, r) := by
  simp only [fdivmod, Int.fdiv_eq_ediv_of_nonneg a (Int.le_of_lt hb),
    Int.fmod_eq_emod_of_nonneg a (Int.le_of_lt hb), Prod.mk.injEq]
  subst h
  have h1 : (q * b + r) / b = q := by
    rw [Int.add_comm, Int.add_mul_ediv_right _ _ (Int.ne_of_gt hb), Int.ediv_eq_zero_of_lt hr.1 hr.2]; simp
  have h2 : (q * b + r) % b = r := by
    rw [Int.add_comm, Int.add_mul_emod_self_right, Int.emod_eq_of_lt hr.1 hr.2]
  exact ⟨h1, h2⟩

/-! ## `toCivil`, `fromCivil`, `Civil.valid` -/

private theorem us_sec : US_PER_SEC = 1000000 := rfl
private theorem us_day : US_PER_DAY = 86400000000 := by decide

private theorem fdivmod_day (w : Int) : fdivmod w 86400000000 = (w / 86400000000, w % 86400000000) := by
  simp [fdivmod, Int.fdiv_eq_ediv_of_nonneg, Int.fmod_eq_emod_of_nonneg]

/-- `Civil.valid` accepts exactly the field ranges of Python's `datetime`
constructor. -/
theorem Civil.valid_eq_none_iff (c : Civil) : c.valid = none ↔
    1 ≤ c.year ∧ c.year ≤ 9999 ∧ 1 ≤ c.month ∧ c.month ≤ 12 ∧ 1 ≤ c.day ∧
      c.day ≤ daysInMonth c.year c.month ∧ c.hour ≤ 23 ∧ c.minute ≤ 59 ∧ c.second ≤ 59 ∧
      c.micro ≤ 999999 := by
  unfold Civil.valid
  repeat' split
  all_goals simp_all
  all_goals omega

private theorem time_split (r : Nat) :
    (r / 3600000000 * 3600 + r / 60000000 % 60 * 60 + r / 1000000 % 60) * 1000000 + r % 1000000 = r := by
  have h1 : r / 3600000000 = r / 1000000 / 3600 := by simp [Nat.div_div_eq_div_mul]
  have h2 : r / 60000000 = r / 1000000 / 60 := by simp [Nat.div_div_eq_div_mul]
  rw [h1, h2]
  generalize hq : r / 1000000 = q
  have : q / 3600 * 3600 + q / 60 % 60 * 60 + q % 60 = q := by omega
  rw [this, ← hq]; exact Nat.div_add_mod' r 1000000

private theorem cast_aux (x y r : Nat) (h : x * 1000000 + y = r) :
    (x : Int) * 1000000 + (y : Int) = (r : Int) := by omega

private theorem time_split_int (r : Nat) :
    ((r / 3600000000 * 3600 + r / 60000000 % 60 * 60 + r / 1000000 % 60 : Nat) : Int) * 1000000
      + ((r % 1000000 : Nat) : Int) = (r : Int) := by
  exact cast_aux _ _ _ (time_split r)

private theorem time_join (t u : Nat) (hu : u < 1000000) :
    (t * 1000000 + u) / 3600000000 = t / 3600 ∧ (t * 1000000 + u) / 60000000 = t / 60 ∧
      (t * 1000000 + u) / 1000000 = t ∧ (t * 1000000 + u) % 1000000 = u := by
  have h3 : (t * 1000000 + u) / 1000000 = t := by omega
  refine ⟨?_, ?_, h3, by omega⟩
  · rw [← h3, Nat.div_div_eq_div_mul]; simp [h3]
  · rw [← h3, Nat.div_div_eq_div_mul]; simp [h3]

/-- **Round trip, microseconds → fields → microseconds**, for every instant. -/
theorem fromCivil_toCivil (w : Int) : fromCivil (toCivil w) = w := by
  have h := daysFromCivil_civilFromDays (w / 86400000000)
  simp only [fromCivil, toCivil, us_day, us_sec, fdivmod_day]
  rw [h]
  rw [Int.add_assoc, time_split_int, Int.toNat_of_nonneg (Int.emod_nonneg w (by decide))]
  exact Int.ediv_mul_add_emod w _

/-- The time-of-day fields `toCivil` produces are in range, and so are the
month and the day: only the year can make the result invalid. -/
theorem toCivil_ranges (w : Int) :
    1 ≤ (toCivil w).month ∧ (toCivil w).month ≤ 12 ∧ 1 ≤ (toCivil w).day ∧
      (toCivil w).day ≤ daysInMonth (toCivil w).year (toCivil w).month ∧
      (toCivil w).hour ≤ 23 ∧ (toCivil w).minute ≤ 59 ∧ (toCivil w).second ≤ 59 ∧
      (toCivil w).micro ≤ 999999 := by
  have h := civilFromDays_valid (w / 86400000000)
  simp only [toCivil, us_day, fdivmod_day]
  refine ⟨h.1, h.2.1, h.2.2.1, h.2.2.2, ?_, ?_, ?_, ?_⟩ <;> omega

/-- So `toCivil` gives a valid `Civil` whenever the year is one Python has. -/
theorem toCivil_valid (w : Int) (hy : 1 ≤ (toCivil w).year ∧ (toCivil w).year ≤ 9999) :
    (toCivil w).valid = none := by
  have h := toCivil_ranges w
  rw [Civil.valid_eq_none_iff]
  exact ⟨hy.1, hy.2, h⟩

/-- **Round trip, fields → microseconds → fields**, for every valid `Civil`
(in fact for any year). -/
theorem toCivil_fromCivil (c : Civil) (hm : 1 ≤ c.month ∧ c.month ≤ 12)
    (hd : 1 ≤ c.day ∧ c.day ≤ daysInMonth c.year c.month)
    (ht : c.hour ≤ 23 ∧ c.minute ≤ 59 ∧ c.second ≤ 59 ∧ c.micro ≤ 999999) :
    toCivil (fromCivil c) = c := by
  obtain ⟨y, m, d, hh, mi, s, u⟩ := c
  simp only at hm hd ht
  have hc := civilFromDays_daysFromCivil y m d hm.1 hm.2 hd.1 hd.2
  generalize ht' : hh * 3600 + mi * 60 + s = t at *
  have e1 : (daysFromCivil y m d * 86400000000 + (t : Int) * 1000000 + u) / 86400000000
      = daysFromCivil y m d := by omega
  have e2 : (daysFromCivil y m d * 86400000000 + (t : Int) * 1000000 + u) % 86400000000
      = ((t * 1000000 + u : Nat) : Int) := by omega
  obtain ⟨j1, j2, j3, j4⟩ := time_join t u (by omega)
  simp only [toCivil, fromCivil, us_day, us_sec, fdivmod_day, ht', e1, e2, hc, Int.toNat_natCast,
    j1, j2, j3, j4, Civil.mk.injEq, true_and]
  clear j1 j2 j3 j4 e1 e2 hc
  refine ⟨?_, ?_, ?_, trivial⟩ <;> omega

theorem toCivil_fromCivil_of_valid (c : Civil) (h : c.valid = none) : toCivil (fromCivil c) = c := by
  rw [Civil.valid_eq_none_iff] at h
  exact toCivil_fromCivil c ⟨h.2.2.1, h.2.2.2.1⟩ ⟨h.2.2.2.2.1, h.2.2.2.2.2.1⟩
    ⟨h.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.2⟩

/-- `fromCivil` is injective on valid `Civil`s: a datetime is determined by
its microsecond count. -/
theorem fromCivil_inj (a b : Civil) (ha : a.valid = none) (hb : b.valid = none)
    (h : fromCivil a = fromCivil b) : a = b := by
  rw [← toCivil_fromCivil_of_valid a ha, ← toCivil_fromCivil_of_valid b hb, h]

/-- The Unix epoch. -/
theorem toCivil_zero : toCivil 0 = ⟨1970, 1, 1, 0, 0, 0, 0⟩ := by rfl

/-! ## `wallOf`, `weekdayOf` -/

/-- A naive datetime is its own wall clock. -/
theorem wallOf_none (us : Int) : wallOf us none = us := by simp [wallOf]

/-- An aware datetime's wall clock is the instant shifted by the offset. -/
theorem wallOf_some (us off : Int) : wallOf us (some off) = us + off * 1000000 := by
  simp [wallOf, us_sec]

theorem weekdayOf_lt (w : Int) : weekdayOf w < 7 := by
  simp only [weekdayOf]; omega

/-- 1970-01-01 was a Thursday (`weekday() == 3`). -/
theorem weekdayOf_epoch : weekdayOf 0 = 3 := by decide

/-- The weekday depends only on the day, not on the time of day. -/
theorem weekdayOf_eq_of_day (w : Int) : weekdayOf w = weekdayOf (w / 86400000000 * 86400000000) := by
  simp only [weekdayOf, us_day, Int.fdiv_eq_ediv_of_nonneg _ (by decide : (0 : Int) ≤ 86400000000)]
  congr 2; omega

/-- The next day is the next weekday, Monday after Sunday. -/
theorem weekdayOf_next_day (w : Int) : weekdayOf (w + US_PER_DAY) = (weekdayOf w + 1) % 7 := by
  simp only [weekdayOf, us_day, Int.fdiv_eq_ediv_of_nonneg _ (by decide : (0 : Int) ≤ 86400000000)]
  omega

/-- Weekdays repeat every 7 days. -/
theorem weekdayOf_add_week (w : Int) : weekdayOf (w + 7 * US_PER_DAY) = weekdayOf w := by
  simp only [weekdayOf, us_day, Int.fdiv_eq_ediv_of_nonneg _ (by decide : (0 : Int) ≤ 86400000000)]
  omega

/-- The weekday of a calendar date, from its day number: Monday = 0 and
day 0 was a Thursday. -/
theorem weekdayOf_fromCivil (c : Civil) (ht : c.hour ≤ 23 ∧ c.minute ≤ 59 ∧ c.second ≤ 59 ∧ c.micro ≤ 999999) :
    (weekdayOf (fromCivil c) : Int) = (daysFromCivil c.year c.month c.day + 3) % 7 := by
  simp only [weekdayOf, fromCivil, us_day, us_sec,
    Int.fdiv_eq_ediv_of_nonneg _ (by decide : (0 : Int) ≤ 86400000000)]
  generalize daysFromCivil c.year c.month c.day = dn
  have e : (dn * 86400000000 + ((c.hour * 3600 + c.minute * 60 + c.second : Nat) : Int) * 1000000 + c.micro)
      / 86400000000 = dn := by omega
  rw [e]; omega

/-! ## `timedelta` -/

/-- `timedelta`'s normal form: `0 ≤ seconds < 86400`, `0 ≤ microseconds <
1000000`, and the three parts add up to the duration. -/
theorem tdParts_spec (us : Int) :
    (tdParts us).2.1 < 86400 ∧ (tdParts us).2.2 < 1000000 ∧
      us = (tdParts us).1 * 86400000000 + (tdParts us).2.1 * 1000000 + (tdParts us).2.2 := by
  simp only [tdParts, us_day, us_sec, fdivmod_day]
  omega

/-- The normal form is unique. -/
theorem tdParts_unique (d : Int) (s u : Nat) (hs : s < 86400) (hu : u < 1000000) :
    tdParts (d * 86400000000 + s * 1000000 + u) = (d, s, u) := by
  simp only [tdParts, us_day, us_sec, fdivmod_day, Prod.mk.injEq]
  refine ⟨?_, ?_, ?_⟩ <;> omega

/-- The Python documentation's example: `timedelta(microseconds=-1)` is
`(days=-1, seconds=86399, microseconds=999999)`. -/
theorem tdParts_neg_one : tdParts (-1) = (-1, 86399, 999999) := by decide

/-- `repr(timedelta(0))` -/
theorem tdRepr_zero : tdRepr 0 = "datetime.timedelta(0)" := by decide

/-- `repr(timedelta(microseconds=-1))` -/
theorem tdRepr_neg_one :
    tdRepr (-1) = "datetime.timedelta(days=-1, seconds=86399, microseconds=999999)" := by decide

/-- `str(timedelta(0))` -/
theorem tdStr_zero : tdStr 0 = "0:00:00" := by decide

/-- `str(timedelta(microseconds=-1))` -/
theorem tdStr_neg_one : tdStr (-1) = "-1 day, 23:59:59.999999" := by decide

/-! ## Padding and formatting -/

private theorem toList_pushn (s : String) (c : Char) (n : Nat) :
    (s.pushn c n).toList = s.toList ++ List.replicate n c := by
  rw [String.pushn_eq_repeat_push]
  induction n with
  | zero => simp [Nat.repeat]
  | succ n ih => simp [Nat.repeat, ih, List.replicate_succ']

/-- `pad0 n w` is `n` in decimal with zeros in front. -/
theorem pad0_toList (n w : Nat) :
    (pad0 n w).toList = List.replicate (w - (toString n).length) '0' ++ (toString n).toList := by
  simp [pad0, toList_pushn]

/-- It is at least `w` characters wide, and exactly `w` when `n` fits. -/
theorem pad0_length (n w : Nat) : (pad0 n w).length = max w (toString n).length := by
  simp [pad0]; omega

/-- A number that already fills the width is printed unchanged (`%02d` of 123). -/
theorem pad0_of_le (n w : Nat) (h : w ≤ (toString n).length) : pad0 n w = toString n := by
  rw [String.ext_iff, pad0_toList, Nat.sub_eq_zero_of_le h]; simp

/-- `%04d` of the year for years ≥ 0. -/
theorem padYear_of_nonneg (y : Int) (h : 0 ≤ y) : padYear y = pad0 y.toNat 4 := by
  simp [padYear, Int.not_lt.2 h]

theorem padYear_length (y : Int) (h : 0 ≤ y) : 4 ≤ (padYear y).length := by
  rw [padYear_of_nonneg y h, pad0_length]; omega

/-- The offset starts with its sign; UTC and offsets east of it print `+`. -/
theorem offsetStr_sign (off : Int) (colon : Bool) :
    (offsetStr off colon).toList.head? = some (if off < 0 then '-' else '+') := by
  simp only [offsetStr, String.toList_append]
  split <;> simp

/-- UTC is `+00:00` in `isoformat` and `+0000` for `%z`. -/
theorem offsetStr_zero : offsetStr 0 = "+00:00" ∧ offsetStr 0 false = "+0000" := by decide

/-- An aware datetime prints as its wall clock followed by the offset. -/
theorem isoformat_some (us off : Int) (sep : String) :
    isoformat us (some off) sep = isoformat (us + off * US_PER_SEC) none sep ++ offsetStr off := by
  simp [isoformat, wallOf]

/-- The Unix epoch. -/
theorem isoformat_epoch : isoformat 0 none = "1970-01-01T00:00:00" ∧
    isoformat 0 (some 0) = "1970-01-01T00:00:00+00:00" := by decide

/-! ## The `strftime` name tables -/

/-- The abbreviated names are the first three letters of the full ones, and
there are seven days and twelve months. -/
theorem name_tables :
    DAY_ABBR = DAY_FULL.map (fun s => (s.take 3).toString) ∧
      MON_ABBR = MON_FULL.map (fun s => (s.take 3).toString) ∧
      DAY_FULL.length = 7 ∧ MON_FULL.length = 12 := by decide

end HALean.Template
