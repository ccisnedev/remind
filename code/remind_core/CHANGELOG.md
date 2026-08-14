# Changelog

## 0.1.0

First release. Model, occurrence engine, reconciler and ports — nothing is
delivered to a device yet, because no backend implements the ports.

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
- **`Reconciler`** — diffs a set of reminders against what the platform
  currently holds and returns a `ReconciliationPlan` of registrations to add,
  keys to cancel, and registrations to leave alone. Pure data: it describes work
  without performing any.
- **`SchedulingBudget`** — the platform ceilings made explicit (iOS keeps 64
  pending notifications and monitors 20 regions), with headroom left for the
  host application's own notifications.
- **`RegistrationKey`** — derived, not allocated, so desired and actual state
  can be compared without keeping a ledger that could drift. Carries a stable
  31-bit `platformId` for platforms that key by integer, and can recover its own
  scheduled instant, which is how the reconciler avoids cancelling occurrences
  that have already fired.
- **Fair window selection** — occurrences are chosen round-robin across
  reminders rather than globally soonest-first, so one frequent reminder cannot
  consume the whole budget and leave every other reminder silent.
- **Foreign registrations are left alone** — keys the library did not create are
  reported in `ReconciliationPlan.unknown` and never cancelled, so an
  application scheduling its own notifications alongside `remind` keeps them.
- **Dropped regions are reported** — regions that do not fit the budget appear
  in `ReconciliationPlan.droppedRegions` rather than vanishing.
- **Ports** — `ReminderStore` (with an `InMemoryReminderStore` implementation)
  and `ReminderBackend`.

### Known limitations

- No backend implements `ReminderBackend` yet, so nothing reaches a device.
- No orchestration layer: the caller wires store, reconciler and backend
  together by hand. A service to do that is deliberately deferred until there is
  a real backend to validate its shape against.
- No RFC 5545 recurrence rules; `DateListTrigger` covers irregular schedules in
  the meantime.
- No snooze or skip-next.
