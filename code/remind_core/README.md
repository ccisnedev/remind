# remind_core

The scheduling brain of the [`remind`](https://github.com/ccisnedev/remind)
ecosystem: a pure Dart engine that models what a reminder *is* and works out
*when* it is due.

It has no Flutter dependency and touches no platform API. Delivering the
reminder — a notification, a native alarm, a geofence — is the job of the
adapter packages that sit on top.

## Why this exists

Every alarm and reminder app rewrites the same glue, and gets the same things
wrong:

- **Daylight saving drift.** Computing the next occurrence as
  `previous + Duration(days: 7)` adds 168 absolute hours. Cross a transition and
  the 07:00 alarm becomes an 06:00 alarm, permanently.
- **The iOS 64-notification ceiling.** iOS keeps only the 64 soonest pending
  notifications. Forty weekly reminders is 280 occurrences, so most of them are
  silently discarded.
- **Time and place cannot be combined.** Neither platform has a primitive for
  "when I reach the office, but only on weekdays". You have to register the
  geofence and evaluate the rest yourself.
- **Nothing survives a reboot** unless something deliberately recomputes and
  re-registers everything.

Those are scheduling problems, not platform problems. Solving them in Dart means
they can be tested exhaustively, in milliseconds, against any zone and any date.

## Install

```yaml
dependencies:
  remind_core: ^0.1.0
```

## Use

```dart
import 'package:remind_core/remind_core.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();
  final zone = tz.getLocation('America/Santiago');

  final reminder = Reminder(
    id: 'standup',
    title: 'Daily standup',
    triggers: [
      WeeklyTrigger(days: Weekday.workdays, time: const LocalTime(9, 15)),
    ],
    condition: ExcludedDatesCondition({CalendarDate(2026, 9, 18)}),
  );

  const engine = OccurrenceEngine();
  final upcoming = engine.occurrencesOf(
    reminder,
    zone: zone,
    from: tz.TZDateTime.now(zone),
    limit: 5,
  );
}
```

See [`example/`](example/remind_core_example.dart) for a runnable tour.

## The model

### Triggers say when to look

A reminder holds a list of triggers combined with **OR** — it fires when any of
them fires. They come in two families, and the split is imposed by the operating
system rather than chosen:

| Trigger | Fires | Enumerable? |
|---|---|---|
| `OneShotTrigger` | Once, on a given date and time | Yes |
| `DailyTrigger` | Every day, or every *N* days from an anchor | Yes |
| `WeeklyTrigger` | At a time, on selected days of the week | Yes |
| `DateListTrigger` | At a time, on an explicit set of dates | Yes |
| `LocationTrigger` | On entering, leaving or dwelling in a region | **No** |

Time triggers are **generative**: given a zone you can list their next
occurrences, which is what lets a scheduler decide how many to register.
Location triggers are **reactive**: there is no way to enumerate the next ten
times someone will walk into a building. The region is handed to the OS and the
OS calls back.

### Conditions say whether to act

A condition gates a reminder that has already been triggered. Conditions divide
by *when they can be evaluated*:

- **`TemporalCondition`** depends only on a moment in time —
  `DateRangeCondition`, `ExcludedDatesCondition`, `WeekdaysCondition`,
  `TimeRangeCondition`. The engine evaluates these while enumerating and simply
  drops the occurrences that fail.
- **`AmbientCondition`** depends on device state that cannot be known ahead of
  time — `InsideRegionCondition`, `OutsideRegionCondition`. These travel with
  the occurrence and are evaluated when it fires.

`AllOfCondition`, `AnyOfCondition` and `NotCondition` compose them.

This split is what makes mixed reminders expressible:

```dart
Reminder(
  id: 'groceries',
  title: 'Buy milk',
  triggers: [
    LocationTrigger(region: supermarket, event: GeoEvent.enter),
  ],
  condition: AllOfCondition([
    WeekdaysCondition(Weekday.workdays),
    TimeRangeCondition(from: LocalTime(8, 0), until: LocalTime(22, 0)),
  ]),
);
```

`partitionCondition` performs the split. Conjunctions distribute, so the
temporal half of an `AllOf` prunes immediately. Disjunctions and negations do
not — in `AnyOf([temporal, ambient])` a false temporal half proves nothing,
because the ambient half may still hold — so those are deferred whole. That is a
correctness constraint, not a missing optimisation.

## Two decisions worth knowing about

### Occurrences are rebuilt from the calendar, never from durations

`OccurrenceEngine` constructs every occurrence from year, month, day and a
wall-clock time. It never adds a `Duration` to the previous one. Adding
`Duration(days: 1)` adds exactly 24 hours of absolute time, so an alarm crossing
a daylight-saving boundary drifts by an hour and stays drifted:

```
America/Santiago, 07:00 daily, across the September 2026 transition

  2026-09-04 07:00 -0400
  2026-09-05 07:00 -0400
  2026-09-06 07:00 -0300   <- wall clock held, UTC offset moved
```

Times that a transition **erased** are reported rather than silently moved.
`DstGapPolicy.shiftForward` (the default) fires at the shifted instant and flags
the occurrence `DstAnomaly.gapShifted`; `DstGapPolicy.skip` drops it. Times that
happen **twice** resolve to the first instant and are flagged
`DstAnomaly.ambiguousResolvedEarly`. An application that wants to warn the user
can, because the engine says what happened.

### Unknown is not false

`evaluateCondition` returns three values, not two: `holds`, `fails` and
`undetermined`. A geofence condition evaluated while the device's location is
unknown has no truthful boolean answer, and collapsing it to `false` would
silently swallow reminders — the worst failure mode this library could have.

Composition follows Kleene three-valued logic, so an unknown only propagates
when it could still change the answer:

```dart
// Saturday, location unknown. Still a definite no: one failing branch
// settles a conjunction, and the caller is spared a location lookup.
evaluateCondition(
  AllOfCondition([
    WeekdaysCondition(Weekday.workdays),
    InsideRegionCondition(office),
  ]),
  EvaluationContext(localTime: saturday),
); // ConditionOutcome.fails
```

## Reconciliation

`Reconciler` is what makes the platform ceilings survivable. Rather than
registering every occurrence of every reminder, it registers a bounded window
and expects to run again as that window is consumed — on launch, on resume,
after a reboot, after a time zone change, and whenever a reminder is edited.

```dart
const reconciler = Reconciler();

final plan = reconciler.plan(
  reminders: await store.all(),
  registered: await backend.pendingRegistrations(),
  zone: zone,
  now: tz.TZDateTime.now(zone),
  budget: const SchedulingBudget(maxTimed: 48),
);

for (final key in plan.toCancel) await backend.cancel(key);
for (final registration in plan.toRegister) await backend.register(registration);
```

A plan is pure data — it describes work without doing any — so it can be
inspected, logged, or asserted on in a test.

Four properties are worth knowing:

- **Keys are derived, not allocated.** `RegistrationKey` is a deterministic
  function of the reminder and the instant, so desired and actual state can be
  compared without keeping a ledger that could drift, corrupt, or be lost on
  reinstall. The key can even recover its own instant, which is how the
  reconciler avoids asking the platform to cancel something that already fired.
- **Selection is fair, not soonest-first.** Occurrences are taken round-robin
  across reminders. Taking the globally soonest would let one frequent reminder
  consume the whole budget, leaving the user with one reminder that works and
  several that appear broken.
- **Foreign registrations are never cancelled.** Keys the library did not create
  are reported in `plan.unknown` and left alone, so an application scheduling
  its own notifications alongside `remind` keeps them.
- **Dropped regions are reported.** iOS monitors 20 regions; anything beyond the
  budget lands in `plan.droppedRegions` rather than vanishing, because a
  silently dropped geofence is indistinguishable from a broken one.

## Scope

This package deliberately does **not**:

- Show notifications, ring alarms, or register geofences. It describes the work;
  a `ReminderBackend` implementation performs it.
- Persist anything beyond `InMemoryReminderStore`. Implement `ReminderStore`
  over whatever database the application already uses.
- Talk to the platform, request permissions, or depend on Flutter.

## Status

Version 0.1.0. Model, occurrence engine, reconciler and ports are complete and
tested; the API may still shift before 1.0.

No backend implements `ReminderBackend` yet, so nothing reaches a device — that
is what the adapter packages are for. There is deliberately no orchestration
layer wiring store, reconciler and backend together: designing one before a real
backend exists would be guesswork.

## Licence

MIT
