# remind_app

Demonstration app for the `remind` ecosystem. Android only — adding iOS would
need a Mac to build on, so it stays out until there is one.

Its purpose is not to be a product. It is the pressure test: unit tests prove
the packages are *correct*, and only building something real proves they are
*usable*.

## What it proves

**The no-location configuration works end to end.** This app depends on
`remind_core` and `remind_notifications` and nothing else. Its manifest declares
`POST_NOTIFICATIONS` and no location permission whatsoever — the configuration
most applications embedding reminders actually want, and the one that has to
work without the rest of the ecosystem installed.

**The reconciler is visible.** The plan screen shows what *would* be registered,
cancelled, retained, or dropped, without applying any of it. When a reminder
does not arrive, that screen answers whether it was ever scheduled, whether it
fell past the budget, or whether nothing installed could deliver it. Being able
to look before acting is most of the reason `Reconciler.plan` returns data
instead of just doing the work.

**Daylight saving is legible.** Each reminder lists its next occurrences with
the UTC offset shown, so a transition is visible as the offset moving while the
wall clock stays put. Occurrences that a transition erased or duplicated are
flagged.

## The manifest is not boilerplate

`android/app/src/main/AndroidManifest.xml` declares
`ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver`. Since
`flutter_local_notifications` v16 the plugin no longer declares them, and
without them **nothing ever fires** — silently. The alarm registers, fires on
time, the system logs the broadcast to a component that does not exist, and
that is the end of it. No exception, no error, no notification.

This app was built without them at first and lost an hour to it, which is why
the requirement is documented loudly in the `remind_notifications` README.

Note what the manifest still does *not* contain: any location permission, and
`SCHEDULE_EXACT_ALARM`.

## Exactness

The app uses `ExactnessPolicy.requireExact` and declares
`SCHEDULE_EXACT_ALARM`, because for a reminder a quarter of an hour late is
often worse than one that never came.

Android 14 denies that permission by default, so the app asks at startup —
which opens system settings, since it cannot be granted in-app. If the user
declines, the app keeps working and says so: a banner across the top of the
list explains that reminders may arrive late, with an action that reopens the
settings page. Nothing degrades quietly.

`SCHEDULE_EXACT_ALARM` rather than `USE_EXACT_ALARM` on purpose. The latter is
granted silently at install, but Google Play restricts it to apps whose *core*
function is a clock, alarm or calendar. A reminder feature inside an app that
does something else does not qualify — so this demo shows the flow those apps
will actually face rather than the easy path it cannot use.

One trap worth knowing: `adb shell dumpsys package` reports this permission as
`granted=false` even once the user has allowed it. It is backed by an app op,
so the real answer comes from:

```sh
adb shell cmd appops get your.package.name SCHEDULE_EXACT_ALARM
```

## Running it

```sh
cd code/remind_app
flutter pub get
flutter run
```

The timer button on the main screen schedules a one-shot reminder two minutes
out, so delivery can be checked on a real device without waiting until morning.

## The orchestration layer

`RemindRuntime` ties store, reconciler and backends together and re-runs on
launch and on resume. It lives here rather than in `remind_core` on purpose:
designing an orchestrator before a real backend existed would have been
guesswork. It is a candidate for promotion into the core once its shape has been
proven against enough backends to be sure of it.

What it does that the core cannot:

- **Routes registrations** to whichever backend declares it `canHandle` them,
  and reports anything nothing will take. A reminder gated by a geofence with
  only the notification backend installed is unroutable, and saying so is better
  than letting it disappear.
- **Combines budgets** across backends. Capacities add, because each
  registration goes to exactly one backend. Horizons do not — the shortest wins,
  since scheduling past a backend's horizon hands it work it will not keep.
- **Cancels before registering,** so a tight platform allowance is freed before
  more is asked of it.

## Storage

`PrefsReminderStore` is a `ReminderStore` over `shared_preferences`, using
`ReminderCodec` for the format. Deliberately the simplest thing that survives a
restart — the point is that the codec is all you need to put reminders in
whatever database you already have, and that the reconciler cannot tell the
difference.

A reminder that fails to decode is dropped rather than taking the whole store
down with it. One corrupt row should not cost the user every other reminder.
