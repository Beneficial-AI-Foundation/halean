/-
  Specifications for `HALean/Automation/Sun.lean` (astral's sunrise and
  sunset, and `get_observer_astral_event_next`).

  The solar position itself is IEEE double arithmetic with libm
  transcendentals, which Lean's `Float` keeps opaque: nothing numeric can be
  proved about it. What is proved is everything around it: the search for
  the next event (`nextEvent_eq`: exactly "the first of 368 local dates,
  from yesterday on, whose event plus offset is after now"), the symmetry
  of rising and setting, and the branches that do not depend on arithmetic.
-/
import HALean.Automation.Sun

namespace HALean.Automation.Sun
open HALean.Template

/-! ### `get_observer_astral_event_next` -/

/-- The event of local day `localDay - 1 + k`, shifted by the offset, if it
is after `nowUs`: one step of upstream's `while` loop. -/
def candidate (o : Observer) (sunrise : Bool) (nowUs tzOffsetSec offsetUs : Int) (k : Nat) :
    Option Int :=
  let localDay := Int.fdiv (nowUs + tzOffsetSec * US_PER_SEC) US_PER_DAY
  let ymd := civilFromDays (localDay - 1 + k)
  match sunEvent o sunrise ymd.1 ymd.2.1 ymd.2.2 with
  | some t => if t + offsetUs > nowUs then some (t + offsetUs) else none
  | none => none

/-- A `for` loop that returns from its first hit is `findSome?`. -/
theorem forIn_first (b : Nat → ForInStep (Option (Option Int) × Unit)) (c : Nat → Option Int)
    (hb : ∀ k, b k = match c k with
      | some v => .done (some (some v), ())
      | none => .yield (none, ())) (l : List Nat) :
    (forIn (m := Id) l ((none : Option (Option Int)), ()) (fun k _ => b k)).fst =
      (l.findSome? c).map some := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    rw [List.forIn_cons, hb]
    cases hc : c x with
    | none => simpa [List.findSome?, hc, bind, pure] using ih
    | some v => simp [List.findSome?, hc]; rfl

/-- `get_observer_astral_event_next`: the first candidate among the local
dates yesterday, today, ..., 366 days ahead. -/
theorem nextEvent_eq (o : Observer) (sunrise : Bool) (nowUs tz off : Int) :
    nextEvent o sunrise nowUs tz off =
      (List.range 368).findSome? (candidate o sunrise nowUs tz off) := by
  unfold nextEvent
  simp only [Id.run, bind, pure]
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  rw [forIn_first _ (candidate o sunrise nowUs tz off)]
  · have hr : List.range' [:368].start [:368].size [:368].step = List.range 368 := by
      simp [List.range_eq_range', Std.Legacy.Range.size]
    rw [hr]
    cases List.findSome? (candidate o sunrise nowUs tz off) (List.range 368) <;> rfl
  · intro k
    unfold candidate
    simp only []
    generalize sunEvent o sunrise _ _ _ = e
    cases e with
    | none => rfl
    | some t => by_cases hc : t + off > nowUs <;> simp [hc]

/-- The next event is strictly in the future. -/
theorem nextEvent_gt (o : Observer) (sunrise : Bool) (nowUs tz off t : Int)
    (h : nextEvent o sunrise nowUs tz off = some t) : t > nowUs := by
  rw [nextEvent_eq] at h
  obtain ⟨k, _, hk⟩ := List.exists_of_findSome?_eq_some h
  unfold candidate at hk
  simp only [] at hk
  split at hk
  · split at hk
    · cases hk; assumption
    · cases hk
  · cases hk

/-- The next event is the sunrise/sunset of one of the 368 dates tried,
plus the offset. -/
theorem nextEvent_is_event (o : Observer) (sunrise : Bool) (nowUs tz off t : Int)
    (h : nextEvent o sunrise nowUs tz off = some t) :
    ∃ k : Nat, k < 368 ∧ ∃ y m d, civilFromDays
        (Int.fdiv (nowUs + tz * US_PER_SEC) US_PER_DAY - 1 + k) = (y, m, d) ∧
      sunEvent o sunrise y m d = some (t - off) := by
  rw [nextEvent_eq] at h
  obtain ⟨k, hk', hk⟩ := List.exists_of_findSome?_eq_some h
  refine ⟨k, List.mem_range.mp hk', ?_⟩
  unfold candidate at hk
  simp only [] at hk
  revert hk
  generalize civilFromDays (Int.fdiv (nowUs + tz * US_PER_SEC) US_PER_DAY - 1 + (k : Int)) = ymd
  intro hk
  obtain ⟨y, m, d⟩ := ymd
  refine ⟨y, m, d, rfl, ?_⟩
  simp only [] at hk
  split at hk
  · rename_i t' ht
    split at hk
    · cases hk; rw [ht]; congr 1; omega
    · cases hk
  · cases hk

/-- No next event within a year (polar night or day throughout): every
date tried either has no event or one that is not after `nowUs`. -/
theorem nextEvent_eq_none (o : Observer) (sunrise : Bool) (nowUs tz off : Int) :
    nextEvent o sunrise nowUs tz off = none ↔
      ∀ k, k < 368 → candidate o sunrise nowUs tz off k = none := by
  rw [nextEvent_eq, List.findSome?_eq_none_iff]
  simp [List.mem_range]

/-- The loop stops at the first date that works: if day `k` has a
candidate and no earlier day has, that candidate is the answer. -/
theorem nextEvent_first (o : Observer) (sunrise : Bool) (nowUs tz off t : Int) (k : Nat)
    (hk : k < 368) (hc : candidate o sunrise nowUs tz off k = some t)
    (hfirst : ∀ j, j < k → candidate o sunrise nowUs tz off j = none) :
    nextEvent o sunrise nowUs tz off = some t := by
  rw [nextEvent_eq]
  have : List.range 368 = List.range k ++ k :: List.range' (k + 1) (367 - k) := by
    rw [List.range_eq_range', List.range_eq_range', show 368 = k + ((367 - k) + 1) by omega,
      ← List.range'_append_1, List.range'_succ]
    simp
  rw [this, List.findSome?_append]
  have h0 : List.findSome? (candidate o sunrise nowUs tz off) (List.range k) = none := by
    rw [List.findSome?_eq_none_iff]; intro j hj; exact hfirst j (List.mem_range.mp hj)
  rw [h0]
  simp [List.findSome?, hc]

/-! ### Rising and setting -/

/-- Whether the sun reaches the zenith that day does not depend on the
direction asked for. -/
theorem hourAngle_isSome (lat dec zen : Float) :
    (hourAngle lat dec zen true).isSome = (hourAngle lat dec zen false).isSome := by
  unfold hourAngle
  simp only []
  split <;> rfl

/-- `if direction == SunDirection.SETTING: HA = -HA`. -/
theorem hourAngle_setting (lat dec zen ha : Float) (h : hourAngle lat dec zen true = some ha) :
    hourAngle lat dec zen false = some (-ha) := by
  unfold hourAngle at h ⊢
  simp only [] at h ⊢
  split at h
  · cases h
  · rename_i hc
    cases h
    simp [hc]

theorem hourAngle_rising (lat dec zen ha : Float) (h : hourAngle lat dec zen false = some ha) :
    ∃ a, hourAngle lat dec zen true = some a ∧ ha = -a := by
  unfold hourAngle at h ⊢
  simp only [] at h ⊢
  split at h
  · cases h
  · rename_i hc
    cases h
    simp [hc]

/-- `if elevation <= 0: return 0`. -/
theorem adjustToHorizon_nonpos (elevation : Float) (h : elevation ≤ 0) :
    adjustToHorizon elevation = 0 := by
  simp [adjustToHorizon, h]

/-- `if elevation >= 85.0: return 0`: no refraction near the zenith. -/
theorem refractionAtZenith_high (zenith : Float) (h : 90 - zenith ≥ 85.0) :
    refractionAtZenith zenith = 0 := by
  simp [refractionAtZenith, h]

/-- `if month <= 2: year -= 1; month += 12`: January and February count as
months 13 and 14 of the year before. -/
theorem julianday_jan_feb (y : Int) (m d : Nat) (h : m ≤ 2) :
    julianday y m d = julianday (y - 1) (m + 12) d := by
  have h' : ¬ (m + 12 ≤ 2) := by omega
  simp [julianday, h, h']

/-! ### `time_of_transit`, `sunrise`, `sunset` -/

/-- `if observer.elevation > 0.0` is the only use of the elevation: at or
below sea level it does not matter. -/
theorem timeOfTransit_elevation (o o' : Observer) (y : Int) (m d : Nat) (zenith : Float)
    (rising : Bool) (hlat : o.latitude = o'.latitude) (hlon : o.longitude = o'.longitude)
    (h : ¬ o.elevation > 0.0) (h' : ¬ o'.elevation > 0.0) :
    timeOfTransit o y m d zenith rising = timeOfTransit o' y m d zenith rising := by
  simp [timeOfTransit, h, h', hlat, hlon]

/-- The result is on the requested date's UTC day line: its midnight plus
`minutes_to_timedelta` of the computed minutes. -/
theorem timeOfTransit_some (o : Observer) (y : Int) (m d : Nat) (zenith : Float) (rising : Bool)
    (t : Int) (h : timeOfTransit o y m d zenith rising = some t) :
    ∃ minutes, t = daysFromCivil y m d * US_PER_DAY + minutesToUs minutes := by
  unfold timeOfTransit at h
  simp only [Option.bind_eq_bind, Option.bind_eq_some_iff, Option.pure_def, Option.some.injEq] at h
  obtain ⟨a, _, b, _, rfl⟩ := h
  exact ⟨_, rfl⟩

theorem sunEvent_elevation (o o' : Observer) (sunrise : Bool) (y : Int) (m d : Nat)
    (hlat : o.latitude = o'.latitude) (hlon : o.longitude = o'.longitude)
    (h : ¬ o.elevation > 0.0) (h' : ¬ o'.elevation > 0.0) :
    sunEvent o sunrise y m d = sunEvent o' sunrise y m d :=
  timeOfTransit_elevation o o' y m d _ sunrise hlat hlon h h'

/-- So the next event is the same for two observers at or below sea level
at the same coordinates. -/
theorem nextEvent_elevation (o o' : Observer) (sunrise : Bool) (nowUs tz off : Int)
    (hlat : o.latitude = o'.latitude) (hlon : o.longitude = o'.longitude)
    (h : ¬ o.elevation > 0.0) (h' : ¬ o'.elevation > 0.0) :
    nextEvent o sunrise nowUs tz off = nextEvent o' sunrise nowUs tz off := by
  rw [nextEvent_eq, nextEvent_eq]
  congr 1
  funext k
  simp only [candidate, sunEvent_elevation o o' sunrise _ _ _ hlat hlon h h']

/-- With no offset, the answer is itself a sunrise/sunset of one of the
dates tried, and it is after `nowUs`. -/
theorem nextEvent_no_offset (o : Observer) (sunrise : Bool) (nowUs tz t : Int)
    (h : nextEvent o sunrise nowUs tz 0 = some t) :
    ∃ k : Nat, k < 368 ∧ ∃ y m d, civilFromDays
        (Int.fdiv (nowUs + tz * US_PER_SEC) US_PER_DAY - 1 + k) = (y, m, d) ∧
      sunEvent o sunrise y m d = some t ∧ t > nowUs := by
  obtain ⟨k, hk, y, m, d, hc, he⟩ := nextEvent_is_event o sunrise nowUs tz 0 t h
  exact ⟨k, hk, y, m, d, hc, by simpa using he, nextEvent_gt o sunrise nowUs tz 0 t h⟩

end HALean.Automation.Sun
