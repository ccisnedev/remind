# Architecture of `remind`

A decision record. It captures **why** the project is built the way it is, not
how to use it — that is what each package's README is for.

---

## 1. The problem

The goal is to **embed reminder functionality into your own applications**:
time, day of the week, several days, specific dates, and location. Not to build
an alarm clock app.

That distinction drives almost everything else.

## 2. What already exists (research, August 2026)

| Package | What it solves | Recurrence |
|---|---|---|
| [`alarm`](https://pub.dev/packages/alarm) | iOS + Android, native audio, foreground service plus AlarmManager. ~10.8k downloads/week | **No.** Its FAQ states that periodic alarms are feasible on Android but not on iOS; you must reschedule by hand |
| [`flutter_alarmkit`](https://pub.dev/packages/flutter_alarmkit) | Apple's AlarmKit (iOS 26). Rings through Do Not Disturb and after termination, with a Live Activity | Yes, by weekday — but **iOS 26+ only**, no Android |
| [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) | The de facto standard for scheduled notifications | `DateTimeComponents.dayOfWeekAndTime`, with a **64-notification pending ceiling on iOS** |
| [`android_alarm_manager_plus`](https://pub.dev/packages/android_alarm_manager_plus) | Raw AlarmManager | Android only |
| [`rrule`](https://pub.dev/packages/rrule), `teno_rrule` | RFC 5545 recurrence in Dart | Yes, but disconnected from delivery |

**Conclusion:** the *delivery* layer is well covered. What does not exist is the
*scheduling* layer above it. Every open source app surveyed
([Awake](https://github.com/adeeteya/Awake-AlarmApp),
[clockee](https://github.com/GiddyNaya/clockee), and others) reimplements the
same glue: persist, compute the next occurrence, re-register on boot, handle
snooze.

## 3. Decision: a pure Dart core

**The core is not a calculation library, it is the brain.** The analogy is a
thermostat: the logic deciding *"it dropped below 20°, fire the boiler"* needs to
know nothing about relays or voltages. The relay is what touches the hardware.

The core does four things, none of which touch the operating system:

1. **Model** what a reminder is: triggers, conditions, action, state.
2. **Resolve occurrences** — given a rule and a time zone, what are the next N
   instants?
3. **Reconcile** desired state against what the OS currently holds, and emit the
   diff. *(pending, see §10)*
4. **React** to boot, resume, time zone change and system clock change by
   reconciling again.

### Why pure Dart matters

- **Testable without a device.** The scenario *"user in Santiago, alarm Tuesdays
  at 07:00, crossing the September transition"* is verified in milliseconds. If
  that logic lives inside a plugin it gets tested by hand on a phone — which is
  to say, not tested.
- **Sustainable maintenance.** No competing with AlarmKit, and no fighting the
  OEMs (Samsung kills alarms through its "Deep Sleeping Apps" list even with
  `exactAllowWhileIdle`).
- **No permission friction.** The central package declares no permissions at all.

The **whole** project is a plugin family; what is pure Dart is the central
package.

## 4. Decision: adapters live in separate packages

This is not purism. If the geofencing code lived in the main package, Android's
manifest merger would inject `ACCESS_BACKGROUND_LOCATION` into **every** app
depending on it — including those that only want time-based reminders. Those
apps would then have to justify to Google Play a permission they never use.

`ACCESS_BACKGROUND_LOCATION` requires a written declaration **and a demo video**,
subject to manual review. That is friction only the apps genuinely using
location should pay.

## 5. Decision: an alarm is a delivery, not an intent

The dilemma initially looked like "should the package be called alarm or
reminder?". They sit at different levels:

- **Reminder** is the *intent*: "I want to be reminded of X under condition Y".
- **Alarm** / **notification** are *deliveries*: how it manifests.

Hence the family root is `remind`, and `alarm` appears only in an adapter's name.
A useful side effect: the central package never says "alarm", which keeps it out
of the `USE_EXACT_ALARM` conversation — a
[restricted permission](https://support.google.com/googleplay/android-developer/answer/16558241)
limited to apps whose core functionality is a clock, alarm or calendar, subject
to manual Play review. An embedded reminder usually does **not** qualify.

## 6. Decision: generative versus reactive triggers

The asymmetry is not a design choice; the operating system imposes it:

| | **TimeTrigger** | **LocationTrigger** |
|---|---|---|
| Nature | Generative | Reactive |
| Enumerable? | Yes — "give me the next 10" | **No** — nobody can list the next 10 times someone will walk into a building |
| How it works | Register a future instant | Register a region; the OS wakes you |
| Budget | iOS: 64 pending notifications | iOS: **20 regions**; Android: ~100 |

Nothing is actively "watched". A loop polling GPS in the background is killed by
the battery and by the OS. You register conditions and the system reports back.

A reminder's triggers combine with **OR**, which is why they are a plain list
rather than an algebra of combinators: the OR is implicit.

## 7. Decision: temporal versus ambient conditions

The AND between time and place is the project's real differentiator, and it
**can only be resolved in Dart**: there is no OS API for *"when I reach the
office, but only on weekdays"*.

Rather than a symmetric AND/OR algebra over triggers — which would be incorrect,
since a `LocationTrigger` cannot be enumerated — the model separates:

> **Trigger** = when to look. **Condition** = whether to act.

And conditions divide by *when they can be evaluated*:

- **`TemporalCondition`** — a pure function of an instant. The engine evaluates
  it while enumerating and drops the occurrences that fail. The device is never
  involved.
- **`AmbientCondition`** — depends on state that does not exist yet (the
  location). It travels with the occurrence and is evaluated at firing time.

`partitionCondition` performs that split. An important correctness rule:

- **Conjunctions distribute**: in `AllOf([temporal, ambient])` the temporal half
  prunes immediately.
- **Disjunctions and negations do not**: in `AnyOf([temporal, ambient])` a false
  temporal half proves nothing, because the ambient half may still hold. Those
  trees are deferred whole.

Pruning disjunctions eagerly would discard valid occurrences. It is a
correctness constraint, not a missing optimisation.

## 8. Decision: never add a `Duration` between occurrences

The classic bug. Verified against the IANA database:

```
America/Santiago, 07:00 daily, September 2026 transition

  2026-09-04 07:00 -0400
  2026-09-05 07:00 -0400
  2026-09-06 07:00 -0300   <- wall clock held, UTC offset moved
```

`previous + Duration(days: 1)` adds exactly 24 absolute hours. Cross the
transition and the 07:00 alarm becomes an 06:00 alarm — and stays that way.

The engine **always** rebuilds from calendar fields (year, month, day plus a
wall-clock time). A test explicitly verifies that the naive arithmetic would
produce a different result, so the test cannot quietly become vacuous.

### Edge cases, verified against `package:timezone`

- **Erased time** (spring forward): `2026-03-08 02:30` does not exist in New
  York. The default `shiftForward` policy fires at 03:30 and flags the
  occurrence `DstAnomaly.gapShifted`. The `skip` alternative exists for cases
  where firing late is worse than not firing at all — a medication interval, a
  market open.
- **Duplicated time** (fall back): `2026-11-01 01:30` happens twice. It resolves
  to the **first** instant and is flagged `DstAnomaly.ambiguousResolvedEarly`.

Both anomalies are **reported** rather than hidden: this is the class of
surprise end users notice and blame the app for, so the application has to be
able to warn them.

## 9. Decision: unknown is not false

`evaluateCondition` returns three values — `holds`, `fails`, `undetermined` —
not two.

A geofence condition evaluated with no location fix has no honest boolean
answer. Collapsing it to `false` would silence reminders the user did ask for:
the worst possible failure mode for this library.

Composition follows Kleene three-valued logic, so an unknown only propagates
when it could still change the answer. An `AllOf` with one failing branch fails
outright — and spares the caller a GPS lookup it never needed.

## 10. Pending

### Reconciler

The piece that justifies the package, and the one still missing. It holds two
states:

- **Desired** — the user's reminders.
- **Actual** — what is currently registered with the OS.

It computes the diff and emits commands. This is what solves the iOS ceiling of
64: you do not register 40 weekly reminders (= 280 occurrences), you register the
upcoming window and re-materialise it as it is consumed. The same mechanism
prioritises geofences by proximity against the iOS budget of 20.

### Others

- Persistence (`ReminderStore`) and delivery (`ReminderBackend`) ports.
- Lifecycle hooks: boot, resume, time zone change.
- Snooze and "skip the next one".
- `RRuleTrigger` over RFC 5545 (`package:rrule`) for rules that
  `DateListTrigger` does not cover gracefully.
- Adapters: `remind_notifications`, `remind_alarm`, `remind_geofence`.

## 11. Conventions

### Every package under `code/` is independent

The repository root stays clean. There is **no** pub workspace, no shared
`pubspec.yaml` and no shared `analysis_options.yaml`. Each directory under
`code/` is self-contained and carries its own manifest, lints, licence and
tests — it should be movable into a repository of its own without editing a
line.

The cost is one `dart pub get` per package instead of one at the root. The
benefit is that `code/` can hold anything, not only Dart packages, and that no
package can quietly acquire a dependency on the shape of the repository around
it.

CI reflects this: one matrix entry per package, each scoped to its own working
directory.

### Language

English throughout — public API, doc comments, READMEs and this document.
pub.dev is an international catalogue. Recorded in `.macss/config.yaml` as
`language: en`.

### Lints

Strict, and deliberately duplicated into each package rather than shared from
the root, with `public_member_api_docs` enabled: these are public libraries and
documenting the API is not optional.
