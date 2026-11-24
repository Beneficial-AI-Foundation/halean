/-
  Specifications for `HALean/Automation/Location.lean` (zones and
  coordinates, as the `zone` trigger and condition use them).

  The geodesic arithmetic of `vincenty` is IEEE double arithmetic, which
  Lean's `Float` keeps opaque; what is proved here is the control flow
  around it.
-/
import HALean.Automation.Location
open Lean

namespace HALean.Automation

/-! ### Attributes as numbers -/

/-- `isinstance(x, (int, float))`: JSON numbers and booleans, nothing else. -/
theorem pyNumber?_isSome (j : Json) :
    (pyNumber? j).isSome ↔ (∃ n, j = .num n) ∨ (∃ b, j = .bool b) := by
  cases j <;> simp [pyNumber?]

theorem pyNumber?_eq_none (j : Json) :
    pyNumber? j = none ↔ (∀ n, j ≠ .num n) ∧ (∀ b, j ≠ .bool b) := by
  cases j <;> simp [pyNumber?]

/-- `numAttr` succeeds exactly on an attribute that is present and a number. -/
theorem numAttr_ok (s : EntityState) (k : String) (f : Float) :
    numAttr s k = .ok f ↔ ∃ v, s.attr? k = some v ∧ pyNumber? v = some f := by
  unfold numAttr
  cases s.attr? k with
  | none => simp [throw, throwThe, MonadExceptOf.throw]
  | some v =>
    cases hp : pyNumber? v with
    | none => simp [hp, throw, throwThe, MonadExceptOf.throw]
    | some g => simp [hp, pure, Except.pure]

theorem numAttr_missing (s : EntityState) (k : String) (h : s.attr? k = none) :
    numAttr s k = .error s!"{s.entityId} has no '{k}' attribute" := by
  simp [numAttr, h, throw, throwThe, MonadExceptOf.throw]

/-- `get_state_coordinates(state) is not None`: both coordinates are numbers. -/
theorem hasLocation_iff (s : EntityState) :
    hasLocation s = true ↔
      ∃ lat lon, numAttr s "latitude" = .ok lat ∧ numAttr s "longitude" = .ok lon := by
  simp only [hasLocation, Bool.and_eq_true, Option.isSome_iff_exists, Option.bind_eq_some_iff,
    numAttr_ok]
  constructor
  · rintro ⟨⟨a, v, h1, h2⟩, ⟨b, w, h3, h4⟩⟩; exact ⟨a, b, ⟨v, h1, h2⟩, ⟨w, h3, h4⟩⟩
  · rintro ⟨a, b, ⟨v, h1, h2⟩, ⟨w, h3, h4⟩⟩; exact ⟨⟨a, v, h1, h2⟩, ⟨b, w, h3, h4⟩⟩

/-! ### `in_zones` -/

/-- `get_in_zones_attribute` only ever names `in_zones`. -/
theorem inZonesAttribute_eq_some (s : EntityState) (a : String) :
    inZonesAttribute s = some a ↔
      a = "in_zones" ∧ (s.domain = "person" ∨ s.domain = "device_tracker") := by
  unfold inZonesAttribute EntityState.domain
  generalize (s.entityId.splitOn ".").headD "" = dom
  by_cases h1 : dom = "person" <;> by_cases h2 : dom = "device_tracker" <;>
    simp [h1, h2] <;> exact eq_comm

theorem inZonesAttribute_eq_none (s : EntityState) :
    inZonesAttribute s = none ↔ s.domain ≠ "person" ∧ s.domain ≠ "device_tracker" := by
  unfold inZonesAttribute EntityState.domain
  generalize (s.entityId.splitOn ".").headD "" = dom
  by_cases h1 : dom = "person" <;> by_cases h2 : dom = "device_tracker" <;> simp [h1, h2]

/-- `_state_has_zone_info`: coordinates, or (for a person or device tracker)
an `in_zones` attribute, whatever its value. -/
theorem stateHasZoneInfo_iff (s : EntityState) :
    stateHasZoneInfo s = true ↔ hasLocation s = true ∨
      ((s.domain = "person" ∨ s.domain = "device_tracker") ∧ (s.attr? "in_zones").isSome) := by
  unfold stateHasZoneInfo
  cases h : inZonesAttribute s with
  | none =>
    have := (inZonesAttribute_eq_none s).mp h
    simp [this.1, this.2]
  | some a =>
    obtain ⟨rfl, hd⟩ := (inZonesAttribute_eq_some s a).mp h
    simp [hd]

/-! ### Distances -/

/-- `vincenty` short-circuits coincident points. -/
theorem vincenty_coincident (lat1 lon1 lat2 lon2 : Float)
    (h : (lat1 == lat2 && lon1 == lon2) = true) : vincenty lat1 lon1 lat2 lon2 = some 0.0 := by
  simp [vincenty, h, Id.run, pure]

theorem distance_coincident (lat1 lon1 lat2 lon2 : Float)
    (h : (lat1 == lat2 && lon1 == lon2) = true) :
    distance lat1 lon1 lat2 lon2 = some (0.0 * 1000) := by
  simp [distance, vincenty_coincident _ _ _ _ h]

/-- `distance` is `vincenty` in metres: it fails exactly when `vincenty`
does not converge. -/
theorem distance_eq_some (lat1 lon1 lat2 lon2 d : Float) :
    distance lat1 lon1 lat2 lon2 = some d ↔
      ∃ km, vincenty lat1 lon1 lat2 lon2 = some km ∧ d = km * 1000 := by
  unfold distance
  cases vincenty lat1 lon1 lat2 lon2 <;> simp [eq_comm]

theorem distance_eq_none (lat1 lon1 lat2 lon2 : Float) :
    distance lat1 lon1 lat2 lon2 = none ↔ vincenty lat1 lon1 lat2 lon2 = none := by
  simp [distance]

/-! ### `zone.in_zone` -/

/-- `if zone.state == STATE_UNAVAILABLE: return False` -/
theorem inZone_unavailable (zone : EntityState) (lat lon radius : Float)
    (h : zone.state = "unavailable") : inZone zone lat lon radius = .ok false := by
  simp [inZone, h, pure, Except.pure]

/-- A zone without a numeric latitude is an error (Python's `TypeError`). -/
theorem inZone_bad_latitude (zone : EntityState) (lat lon radius : Float) (e : String)
    (h : zone.state ≠ "unavailable") (hl : numAttr zone "latitude" = .error e) :
    inZone zone lat lon radius = .error e := by
  simp [inZone, h, hl, bind, Except.bind]

theorem inZone_bad_longitude (zone : EntityState) (lat lon radius zlat : Float) (e : String)
    (h : zone.state ≠ "unavailable") (hl : numAttr zone "latitude" = .ok zlat)
    (hl' : numAttr zone "longitude" = .error e) :
    inZone zone lat lon radius = .error e := by
  simp [inZone, h, hl, hl', bind, Except.bind]

/-- `if zone_dist is None or zone_radius is None: return False`, then
`zone_dist - radius < zone_radius`. -/
theorem inZone_spec (zone : EntityState) (lat lon radius zlat zlon : Float)
    (h : zone.state ≠ "unavailable") (hlat : numAttr zone "latitude" = .ok zlat)
    (hlon : numAttr zone "longitude" = .ok zlon) :
    inZone zone lat lon radius =
      match distance lat lon zlat zlon with
      | none => .ok false
      | some d =>
        match zone.attr? "radius" with
        | none => .error s!"{zone.entityId} has no 'radius' attribute"
        | some .null => .ok false
        | some _ => (numAttr zone "radius").map fun r => decide (d - radius < r) := by
  have hb : (zone.state == "unavailable") = false := by simpa using h
  simp only [inZone, hb, hlat, hlon, bind, Except.bind, pure, Except.pure]
  cases distance lat lon zlat zlon with
  | none => simp
  | some d =>
    simp only []
    cases hr : zone.attr? "radius" with
    | none => simp [throw, throwThe, MonadExceptOf.throw]
    | some v =>
      cases v <;> simp [Except.map] <;> cases numAttr zone "radius" <;> rfl

/-- When `in_zone` says yes, the zone is available, has coordinates, the
distance was computable and within the radius. -/
theorem inZone_true (zone : EntityState) (lat lon radius : Float)
    (h : inZone zone lat lon radius = .ok true) :
    zone.state ≠ "unavailable" ∧ ∃ zlat zlon d r,
      numAttr zone "latitude" = .ok zlat ∧ numAttr zone "longitude" = .ok zlon ∧
      distance lat lon zlat zlon = some d ∧ numAttr zone "radius" = .ok r ∧ d - radius < r := by
  by_cases hu : zone.state = "unavailable"
  · rw [inZone_unavailable _ _ _ _ hu] at h; cases h
  refine ⟨hu, ?_⟩
  cases hlat : numAttr zone "latitude" with
  | error e => rw [inZone_bad_latitude _ _ _ _ e hu hlat] at h; cases h
  | ok zlat =>
  cases hlon : numAttr zone "longitude" with
  | error e => rw [inZone_bad_longitude _ _ _ _ _ e hu hlat hlon] at h; cases h
  | ok zlon =>
  rw [inZone_spec _ _ _ _ _ _ hu hlat hlon] at h
  cases hd : distance lat lon zlat zlon with
  | none => rw [hd] at h; cases h
  | some d =>
    rw [hd] at h
    simp only [] at h
    split at h
    · cases h
    · cases h
    · cases hr : numAttr zone "radius" with
      | error e => rw [hr] at h; cases h
      | ok r =>
        rw [hr] at h
        simp only [Except.map, Except.ok.injEq, decide_eq_true_eq] at h
        exact ⟨zlat, zlon, d, r, rfl, rfl, hd, rfl, h⟩

/-! ### The `zone` condition -/

/-- `if entity_state.state in (STATE_UNAVAILABLE, STATE_UNKNOWN): return False` -/
theorem zoneCondition_unavailable (zone entity : EntityState)
    (h : entity.state = "unavailable" ∨ entity.state = "unknown") :
    zoneCondition zone entity = .ok false := by
  rcases h with h | h <;> simp [zoneCondition, h, pure, Except.pure]

/-- A person or device tracker with an `in_zones` list is in the zone
exactly when the list names it; coordinates are not looked at. -/
theorem zoneCondition_in_zones (zone entity : EntityState) (xs : Array Json)
    (hs : entity.state ≠ "unavailable") (hs' : entity.state ≠ "unknown")
    (hd : entity.domain = "person" ∨ entity.domain = "device_tracker")
    (ha : entity.attr? "in_zones" = some (.arr xs)) :
    zoneCondition zone entity = .ok (xs.contains (.str zone.entityId)) := by
  have hz : inZonesAttribute entity = some "in_zones" :=
    (inZonesAttribute_eq_some entity _).mpr ⟨rfl, hd⟩
  simp [zoneCondition, hs, hs', hz, ha, pure, Except.pure]

/-- `in_zones` as text: Python's `zone_state.entity_id in in_zones` is a
substring test. -/
theorem zoneCondition_in_zones_str (zone entity : EntityState) (t : String)
    (hs : entity.state ≠ "unavailable") (hs' : entity.state ≠ "unknown")
    (hd : entity.domain = "person" ∨ entity.domain = "device_tracker")
    (ha : entity.attr? "in_zones" = some (.str t)) :
    zoneCondition zone entity = .ok (decide ((t.splitOn zone.entityId).length > 1)) := by
  have hz : inZonesAttribute entity = some "in_zones" :=
    (inZonesAttribute_eq_some entity _).mpr ⟨rfl, hd⟩
  simp [zoneCondition, hs, hs', hz, ha, pure, Except.pure]

/-- Without `in_zones` (other domains, or the attribute missing or null),
a missing latitude is the `ConditionErrorMessage`. -/
theorem zoneCondition_no_latitude (zone entity : EntityState)
    (hs : entity.state ≠ "unavailable") (hs' : entity.state ≠ "unknown")
    (hz : inZonesAttribute entity = none) (hl : entity.attr? "latitude" = none) :
    zoneCondition zone entity =
      .error s!"entity {entity.entityId} has no 'latitude' attribute" := by
  simp [zoneCondition, hs, hs', hz, hl, throw, throwThe, MonadExceptOf.throw]

/-- Without `in_zones`, an entity with numeric coordinates is tested with
`zone.in_zone`, its `gps_accuracy` (default 0) as the radius. (`n1`, `n2`:
Lean's `==` on `Json` is opaque, so "a number is not `null`" is assumed.) -/
theorem zoneCondition_coordinates (zone entity : EntityState) (lat lon : Float) (latJ lonJ : Json)
    (hs : entity.state ≠ "unavailable") (hs' : entity.state ≠ "unknown")
    (hz : inZonesAttribute entity = none)
    (hlat : entity.attr? "latitude" = some latJ) (hlat' : pyNumber? latJ = some lat)
    (hlon : entity.attr? "longitude" = some lonJ) (hlon' : pyNumber? lonJ = some lon)
    (n1 : (latJ == Json.null) = false) (n2 : (lonJ == Json.null) = false)
    (hacc : entity.attr? "gps_accuracy" = none) :
    zoneCondition zone entity = inZone zone lat lon 0.0 := by
  have h1 : numAttr entity "latitude" = .ok lat := (numAttr_ok _ _ _).mpr ⟨_, hlat, hlat'⟩
  have h2 : numAttr entity "longitude" = .ok lon := (numAttr_ok _ _ _).mpr ⟨_, hlon, hlon'⟩
  simp [zoneCondition, hs, hs', hz, hlat, hlon, hacc, h1, h2, n1, n2, pure, Except.pure, bind,
    Except.bind]

end HALean.Automation
