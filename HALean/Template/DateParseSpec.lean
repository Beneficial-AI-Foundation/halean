/-
  `HALean/Template/DateParse.lean`: the parts of date and duration parsing
  that are ordinary total functions.

    * `tdChecked` is `timedelta`'s range check, stated on microseconds;
    * `fromIsoCalendar` follows ISO 8601: week 1 starts on the Monday nearest
      to 1 January, and its errors are the ones CPython raises;
    * `dateOk` is `Civil.valid` for a date; `rstripSpaces`, `isAscii`,
      `isPyWsAscii`, the `TimeRE` directive table and the C-locale names.

  `parseDuration`, `strptimePattern` and `strptime` run the regex matcher
  (`Rx.run`) or `patternGo`, which are `partial def`s; the rounding helpers
  are `Float` arithmetic. Neither can be unfolded in a proof.
-/
import HALean.Template.DateParse

namespace HALean.Template

/-! ## Text helpers -/

theorem isAscii_iff (s : String) : isAscii s = true ↔ ∀ c ∈ s.toList, c.toNat < 128 := by
  simp [isAscii]

theorem isAscii_append (s t : String) : isAscii (s ++ t) = (isAscii s && isAscii t) := by
  simp [isAscii, String.toList_append]

/-- The two "is this text modelled" tests of the template code agree. -/
theorem isAscii_eq_numberTextModelled (s : String) : isAscii s = numberTextModelled s := by
  simp [isAscii, numberTextModelled]

private theorem dropWhile_space (l : List Char) :
    ∃ k, l = List.replicate k ' ' ++ l.dropWhile (· == ' ') ∧ (l.dropWhile (· == ' ')).head? ≠ some ' ' := by
  induction l with
  | nil => exact ⟨0, by simp⟩
  | cons c l ih =>
    by_cases hc : c = ' '
    · obtain ⟨k, h1, h2⟩ := ih
      refine ⟨k + 1, ?_, ?_⟩
      · rw [List.dropWhile_cons_of_pos (by simp [hc]), List.replicate_succ, List.cons_append, ← h1, hc]
      · rw [List.dropWhile_cons_of_pos (by simp [hc])]; exact h2
    · refine ⟨0, ?_, ?_⟩
      · rw [List.dropWhile_cons_of_neg (by simp [hc])]; simp
      · rw [List.dropWhile_cons_of_neg (by simp [hc])]; simp [hc]

/-- **`str.rstrip(" ")`**: the result is the input without some trailing
spaces, and it does not end with a space. -/
theorem rstripSpaces_spec (s : String) :
    (∃ k, s.toList = (rstripSpaces s).toList ++ List.replicate k ' ') ∧
      (rstripSpaces s).toList.getLast? ≠ some ' ' := by
  obtain ⟨k, h1, h2⟩ := dropWhile_space s.toList.reverse
  simp only [rstripSpaces, String.toList_ofList]
  refine ⟨⟨k, ?_⟩, ?_⟩
  · have := congrArg List.reverse h1
    simpa using this
  · rw [List.getLast?_reverse]; exact h2

/-- Text that does not end with a space is left alone. -/
theorem rstripSpaces_of_no_trailing (s : String) (h : s.toList.getLast? ≠ some ' ') : rstripSpaces s = s := by
  rw [String.ext_iff]
  simp only [rstripSpaces, String.toList_ofList]
  have : (s.toList.reverse.dropWhile (· == ' ')) = s.toList.reverse := by
    cases hr : s.toList.reverse with
    | nil => rfl
    | cons c l =>
      rw [← List.head?_reverse, hr] at h
      rw [List.dropWhile_cons_of_neg]
      simpa using h
  rw [this, List.reverse_reverse]

theorem rstripSpaces_idem (s : String) : rstripSpaces (rstripSpaces s) = rstripSpaces s :=
  rstripSpaces_of_no_trailing _ (rstripSpaces_spec s).2

/-- Python's `str.isspace()` on ASCII: space, `\t \n \v \f \r` and the four
separators `\x1c`–`\x1f`. -/
theorem isPyWsAscii_iff (c : Char) : isPyWsAscii c = true ↔
    c.toNat = 32 ∨ (9 ≤ c.toNat ∧ c.toNat ≤ 13) ∨ (28 ≤ c.toNat ∧ c.toNat ≤ 31) := by
  have key : ∀ d : Char, c = d ↔ c.toNat = d.toNat := fun d =>
    ⟨fun h => by rw [h], fun h => Char.ext (UInt32.toNat_inj.1 h)⟩
  have le1 : ('\x1c' ≤ c) ↔ 28 ≤ c.toNat := by
    rw [Char.le_def, UInt32.le_iff_toNat_le]; rfl
  have le2 : (c ≤ '\x1f') ↔ c.toNat ≤ 31 := by
    rw [Char.le_def, UInt32.le_iff_toNat_le]; rfl
  simp only [isPyWsAscii, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, key, le1, le2]
  have e1 : ' '.toNat = 32 := rfl
  have e2 : '\t'.toNat = 9 := rfl
  have e3 : '\n'.toNat = 10 := rfl
  have e4 : '\r'.toNat = 13 := rfl
  have e5 : '\x0b'.toNat = 11 := rfl
  have e6 : '\x0c'.toNat = 12 := rfl
  rw [e1, e2, e3, e4, e5, e6]
  omega

/-! ## `timedelta` -/

private theorem us_day : US_PER_DAY = 86400000000 := by decide

/-- **`timedelta`'s range**: accepted exactly from `timedelta.min`
(−999999999 days) up to, not including, 1000000000 days; the value is
returned unchanged. -/
theorem tdChecked_ok_iff (us : Int) :
    tdChecked us = .ok us ↔ -999999999 * 86400000000 ≤ us ∧ us < 1000000000 * 86400000000 := by
  have hD : (0 : Int) < 86400000000 := by decide
  have h1 : -999999999 ≤ us / 86400000000 ↔ -999999999 * 86400000000 ≤ us := Int.le_ediv_iff_mul_le hD
  have h2 : us / 86400000000 < 1000000000 ↔ us < 1000000000 * 86400000000 := Int.ediv_lt_iff_lt_mul hD
  rw [← h1, ← h2]
  simp only [tdChecked, us_day, Int.fdiv_eq_ediv_of_nonneg us (Int.le_of_lt hD)]
  generalize us / 86400000000 = q
  split
  · rename_i hc
    simp only [Bool.or_eq_true, decide_eq_true_eq] at hc
    constructor
    · intro h; cases h
    · omega
  · rename_i hc
    simp only [Bool.or_eq_true, decide_eq_true_eq] at hc
    constructor
    · intro _; omega
    · intro _; rfl

/-- `tdChecked` never changes the value. -/
theorem tdChecked_eq_ok (us v : Int) (h : tdChecked us = .ok v) : v = us := by
  simp only [tdChecked] at h
  split at h
  · cases h
  · cases h; rfl

/-- A `timedelta` argument that is not a number is a `TypeError`. -/
theorem timedeltaNew_str (tag s : String) (f : Nat) (rest : List (String × Nat × Value)) :
    timedeltaNew ((tag, f, .str s) :: rest) =
      .error (.valueError s!"unsupported type for timedelta {tag} component: {typeName (.str s)}") := by
  simp [timedeltaNew, bind, Except.bind, throw, throwThe, MonadExceptOf.throw]

/-- `timedelta(days=float("nan"))` is a `ValueError`. -/
theorem timedeltaNew_nan (tag : String) (d : Float) (f : Nat) (rest : List (String × Nat × Value))
    (h : d.isNaN = true) :
    timedeltaNew ((tag, f, .float d) :: rest) = .error (.valueError "cannot convert float NaN to integer") := by
  simp [timedeltaNew, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, h]

/-- `timedelta(days=float("inf"))` is an `OverflowError`. -/
theorem timedeltaNew_inf (tag : String) (d : Float) (f : Nat) (rest : List (String × Nat × Value))
    (hn : d.isNaN = false) (h : d.isInf = true) :
    timedeltaNew ((tag, f, .float d) :: rest) =
      .error (.error "OverflowError: cannot convert float infinity to integer") := by
  simp [timedeltaNew, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, hn, h]

/-- `_get_timestring(0, precision)` is `"0 seconds"` whatever the precision. -/
theorem getTimestring_zero (precision : Value) : getTimestring 0 precision = "0 seconds" := rfl

/-! ## The `strptime` directive table -/

/-- The C-locale names `strptime` reads are the lower-cased names `strftime`
prints. -/
theorem locale_names :
    A_WEEKDAY.map String.toList = DAY_ABBR.map (fun s => s.toList.map Char.toLower) ∧
    F_WEEKDAY.map String.toList = DAY_FULL.map (fun s => s.toList.map Char.toLower) ∧
    (A_MONTH.drop 1).map String.toList = MON_ABBR.map (fun s => s.toList.map Char.toLower) ∧
    (F_MONTH.drop 1).map String.toList = MON_FULL.map (fun s => s.toList.map Char.toLower) := by decide

/-- `__seqToRE` gives one named group holding an alternation with one branch
per non-empty name. -/
theorem seqToRE_shape (names : List String) (directive : String) :
    ∃ alts, seqToRE names directive = .group directive (.alt alts) ∧
      alts.length = (names.filter (· != "")).length := by
  refine ⟨_, rfl, ?_⟩
  simp [List.length_mergeSort]

/-- **The keys of `TimeRE`**: exactly these directives are known; any other
is `'x' is a bad directive`. -/
theorem timeRE_isSome_iff (k : String) : (timeRE k).isSome = true ↔
    k ∈ ["d", "e", "f", "H", "k", "I", "l", "G", "j", "m", "M", "S", "U", "W", "w", "u", "V", "y", "Y",
      "z", "A", "a", "B", "b", "p", "P", "%", "T", "R", "Z", "Od", "Om", "Ow", "Oy", "OC", "OH", "OI",
      "OM", "OS", "Oe", "Op", "r", "X", "x", "c"] := by
  constructor
  · unfold timeRE
    split <;> simp
  · intro h
    simp only [List.mem_cons, List.not_mem_nil, or_false] at h
    repeat (rcases h with rfl | h; · rfl)

/-- The directives whose meaning depends on the host's locale or time zone
are refused with an error rather than guessed. -/
theorem timeRE_unsupported (k : String)
    (h : k ∈ ["Z", "Od", "Om", "Ow", "Oy", "OC", "OH", "OI", "OM", "OS", "Oe", "Op", "r", "X", "x", "c"]) :
    ∃ e, timeRE k = some (.error e) := by
  simp only [List.mem_cons, List.not_mem_nil, or_false] at h
  repeat (rcases h with rfl | h; · exact ⟨_, rfl⟩)

/-- glibc's aliases: `%e` is `%d`, `%k` is `%H`, `%l` is `%I`, `%P` is `%p`,
and `%U` and `%W` read the same digits. -/
theorem timeRE_aliases : timeRE "e" = timeRE "d" ∧ timeRE "k" = timeRE "H" ∧ timeRE "l" = timeRE "I" ∧
    timeRE "P" = timeRE "p" :=
  ⟨rfl, rfl, rfl, rfl⟩

/-! ## Dates -/

/-- `datetime.date(y, m, d)` is valid: the year is in 1..9999, the month in
1..12 and the day exists in that month. -/
theorem dateOk_iff (y m d : Int) : dateOk y m d = true ↔
    1 ≤ y ∧ y ≤ 9999 ∧ 1 ≤ m ∧ m ≤ 12 ∧ 1 ≤ d ∧ d ≤ (daysInMonth y m.toNat : Int) := by
  simp [dateOk, and_assoc]

/-- `dateOk` agrees with the `datetime` constructor's check (`Civil.valid`)
at midnight. -/
theorem dateOk_iff_valid (y m d : Int) : dateOk y m d = true ↔
    ({ year := y, month := m.toNat, day := d.toNat, hour := 0, minute := 0, second := 0, micro := 0 } :
      Civil).valid = none := by
  rw [dateOk_iff]
  unfold Civil.valid
  repeat' split
  all_goals simp_all
  all_goals omega

/-- A valid date has at most 31 days in its month. -/
theorem dateOk_day_le (y m d : Int) (h : dateOk y m d = true) : d ≤ 31 := by
  rw [dateOk_iff] at h
  have : daysInMonth y m.toNat ≤ 31 := by unfold daysInMonth; split <;> (try split) <;> omega
  omega

theorem dayNum_epoch : dayNum 1970 1 1 = 0 := by decide

/-- Consecutive days of a month have consecutive ordinals. -/
theorem dayNum_succ (y m d : Int) (hd : 0 ≤ d) : dayNum y m (d + 1) = dayNum y m d + 1 := by
  simp only [dayNum, daysFromCivil]
  have : (d + 1).toNat = d.toNat + 1 := by omega
  rw [this]; omega

/-! ## `date.fromisocalendar` -/

private theorem emod_eq (a b : Int) : Int.emod a b = a % b := rfl

/-- `fromisocalendar` with a year outside 1..9999 is a `ValueError`. -/
theorem fromIsoCalendar_bad_year (year week day : Int) (h : year < 1 ∨ 9999 < year) :
    fromIsoCalendar year week day = .error (.valueError s!"Year is out of range: {year}") := by
  simp [fromIsoCalendar, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, h]

/-- A week number that is not in 1..53 is a `ValueError`. -/
theorem fromIsoCalendar_bad_week (year week day : Int) (hy : 1 ≤ year ∧ year ≤ 9999)
    (h : week ≤ 0 ∨ 54 ≤ week) :
    fromIsoCalendar year week day = .error (.valueError s!"Invalid week: {week}") := by
  have h1 : ¬ (year < 1 ∨ 9999 < year) := by omega
  have h2 : week ≤ 0 ∨ 53 ≤ week := by omega
  have h3 : week ≠ 53 := by omega
  simp [fromIsoCalendar, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, h1, h2, h3]

/-- A weekday that is not in 1..7 is a `ValueError`. -/
theorem fromIsoCalendar_bad_weekday (year week day : Int) (hy : 1 ≤ year ∧ year ≤ 9999)
    (hw : 1 ≤ week ∧ week ≤ 52) (h : day ≤ 0 ∨ 8 ≤ day) :
    fromIsoCalendar year week day =
      .error (.valueError s!"Invalid weekday: {day} (range is [1, 7])") := by
  have h1 : ¬ (year < 1 ∨ 9999 < year) := by omega
  have h2 : ¬ (week ≤ 0 ∨ 53 ≤ week) := by omega
  simp [fromIsoCalendar, bind, Except.bind, throw, throwThe, MonadExceptOf.throw, h1, h2, h]

/-- **ISO 8601 week dates.** When `fromisocalendar(year, week, day)`
succeeds, the arguments were in range and the result is the date of day
number `mon + 7 * (week - 1) + (day - 1)`, where `mon` is a Monday at most
three days from 1 January of `year` (so week 1 is the week with the year's
first Thursday); the resulting year is one Python has. -/
theorem fromIsoCalendar_ok (year week day : Int) (r : Int × Int × Int)
    (h : fromIsoCalendar year week day = .ok r) :
    1 ≤ year ∧ year ≤ 9999 ∧ 1 ≤ week ∧ week ≤ 53 ∧ 1 ≤ day ∧ day ≤ 7 ∧ 1 ≤ r.1 ∧ r.1 ≤ 9999 ∧
    ∃ mon : Int, (mon + 3) % 7 = 0 ∧ dayNum year 1 1 - 3 ≤ mon ∧ mon ≤ dayNum year 1 1 + 3 ∧
      r = ((civilFromDays (mon + 7 * (week - 1) + (day - 1))).1,
           ((civilFromDays (mon + 7 * (week - 1) + (day - 1))).2.1 : Int),
           ((civilFromDays (mon + 7 * (week - 1) + (day - 1))).2.2 : Int)) := by
  have hmon : ∀ first : Int, (first - (first + 3) % 7 + (if (first + 3) % 7 > 3 then 7 else 0) + 3) % 7 = 0 ∧
      first - 3 ≤ first - (first + 3) % 7 + (if (first + 3) % 7 > 3 then 7 else 0) ∧
      first - (first + 3) % 7 + (if (first + 3) % 7 > 3 then 7 else 0) ≤ first + 3 := by
    intro first; split <;> omega
  have harg : ∀ first w d : Int, first - (first + 3) % 7 + (if (first + 3) % 7 > 3 then 7 else 0) + (w - 1) * 7 + d - 1
      = first - (first + 3) % 7 + (if (first + 3) % 7 > 3 then 7 else 0) + 7 * (w - 1) + (d - 1) := by
    intro first w d; omega
  unfold fromIsoCalendar at h
  simp only [bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, emod_eq, harg] at h
  obtain ⟨m1, m2, m3⟩ := hmon (dayNum year 1 1)
  generalize (dayNum year 1 1 - (dayNum year 1 1 + 3) % 7 + if (dayNum year 1 1 + 3) % 7 > 3 then 7 else 0)
    = mon at h m1 m2 m3
  repeat' (split at h)
  all_goals first
    | (cases h; done)
    | (injection h with h
       subst h
       refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, mon, m1, m2, m3, rfl⟩
       all_goals first
         | omega
         | (simp_all; omega)
         | (simp_all; done))

end HALean.Template
