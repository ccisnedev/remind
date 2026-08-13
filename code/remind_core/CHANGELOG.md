# Changelog

## 0.1.0

First release. Model and occurrence engine only — nothing is delivered to a
device yet.

### Added

- **Value types** — `CalendarDate`, `LocalTime`, `Weekday`, `GeoCoordinate`,
  `GeoRegion`. Calendar arithmetic runs in UTC so the host's own daylight-saving
  rules cannot perturb it.
- **Triggers** — `OneShotTrigger`, `DailyTrigger` (with an optional interval and
  anchor), `WeeklyTrigger`, `DateListTrigger` and `LocationTrigger`, as a sealed
  hierarchy split into generative time triggers and reactive location triggers.
- **Conditions** — `DateRangeCondition`, `ExcludedDatesCondition`,
  `WeekdaysCondition`, `TimeRangeCondition` (which wraps around midnight),
  `InsideRegionCondition`, `OutsideRegionCondition`, composed with
  `AllOfCondition`, `AnyOfCondition` and `NotCondition`.
- **`OccurrenceEngine`** — resolves a `Reminder` into concrete instants for a
  given time zone, merging and de-duplicating across triggers.
- **Daylight-saving handling** — occurrences are rebuilt from calendar fields
  rather than by adding durations, so wall-clock times survive transitions.
  Erased times are reported as `DstAnomaly.gapShifted` and resolved per
  `DstGapPolicy`; times that occur twice resolve to the first instant and are
  reported as `DstAnomaly.ambiguousResolvedEarly`.
- **Three-valued condition evaluation** — `evaluateCondition` returns `holds`,
  `fails` or `undetermined` and composes under Kleene logic, so an unknown
  device location never silently reads as `false`.
- **`partitionCondition`** — splits a condition into the part evaluable during
  enumeration and the part that must be re-checked at firing time.

### Known limitations

- No reconciler yet: nothing diffs the desired schedule against what the
  operating system currently holds.
- No RFC 5545 recurrence rules; `DateListTrigger` covers irregular schedules in
  the meantime.
- `LocationTrigger` is modelled but no adapter registers it with a platform.
