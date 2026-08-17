# remind_geofence

Delivers [`remind_core`](../remind_core) reminders when the device enters,
leaves or dwells in a region, over
[`native_geofence`](https://pub.dev/packages/native_geofence).

**You probably do not need this package.** It requires background location
permission, which Google Play grants only after a manual review including a
video demonstration. An application that needs date-and-time reminders should
depend on `remind_notifications` alone and never link this one.

## What makes it different from a notification backend

`NotificationBackend` **refuses** registrations that still carry a condition.
This one **accepts** them. That is a platform fact rather than a difference of
ambition.

A scheduled local notification is displayed by the operating system with no
chance for application code to intervene — on iOS the service extension that
could intercept it fires only for remote push. A region crossing is the
opposite: it wakes application code *before* anything is shown, on Android
through the geofencing broadcast and on iOS through Core Location region
monitoring. So the condition can be checked, and the reminder can stay quiet.

The consequence is that this package owns the *decision* and hands you the
*mechanism*: you supply a `CrossingDelivery` function that actually shows the
notification. Posting it here would tie this package to a notification backend
and force every consumer of one to take the other.

> **Do not reach for `UNLocationNotificationTrigger` on iOS.** It is simpler and
> the OS does the monitoring, but no application code runs, so it silently
> reintroduces exactly the limitation this package exists to avoid.

## Making silence legible

Every crossing produces a `CrossingOutcome`, **including the ones that reach
nobody**:

| Outcome | Meaning |
|---|---|
| `Delivered` | Fired, every condition held, the user was told |
| `Suppressed` | Fired, but a condition excluded it — and it says which |
| `Undetermined` | Fired, but a condition could not be decided |

`Suppressed` and `Undetermined` are separate types on purpose. "The condition
did not hold" and "I could not tell whether it held" are different answers to
the user's question, and collapsing them would hide a permission problem behind
something that looks like a working reminder.

This is the obligation that comes with conjunctive reminders. Surveying how
other products model time-and-place reminders found that **none of them** allow
a rule to require both — and explainability is the most likely reason. A
reminder gated on a place *and* a condition can work perfectly and stay silent,
and the user cannot tell that apart from a geofence that never fired. Keeping
conjunction means owing them an answer.

`CrossingJournal` is where those answers live. It is not a logging convenience:
the crossing callback runs in a background isolate with no access to the app's
memory and no return value, so the journal is the **only** channel through which
any of this is observable at all.

## The crossing is its own evidence

`GeofenceCallbackParams.location` is never populated on iOS and frequently null
on Android. A naive evaluation would therefore find every location condition
undecidable — including the obvious one, "remind me at the shop", evaluated at
the instant the shop's geofence fired.

`CrossingEvaluator` treats the crossing as evidence about itself. Entering or
dwelling proves the device is inside that region; leaving proves it is outside.
Conditions about *that* region are decidable with no coordinates at all.
Conditions about any *other* region stay undecided rather than guessed —
inventing evidence would be worse than admitting ignorance.

## Use

```dart
// A top-level function. It runs in a background isolate, so it can see nothing
// the app built — no store instance, no runtime, no singletons. Everything is
// rebuilt from storage here.
@pragma('vm:entry-point')
Future<void> onCrossing(GeofenceCallbackParams params) async {
  DartPluginRegistrant.ensureInitialized();

  final handler = CrossingHandler(
    store: await YourReminderStore.open(),
    journal: await YourCrossingJournal.open(),
    deliver: (crossing) => showNotification(crossing),
  );

  await handler.handle(
    firedRegionIds: {for (final g in params.geofences) g.id},
    event: params.event,
    zone: zone,
    at: tz.TZDateTime.now(zone),
    deviceLocation: params.location == null
        ? null
        : GeoCoordinate(params.location!.latitude, params.location!.longitude),
  );
}
```

Wiring the backend is ordinary:

```dart
final scheduler = NativeGeofenceScheduler(
  callback: onCrossing,
  hasLocationPermission: () async => /* your permission check */,
);
await scheduler.initialize();
await scheduler.recreateAfterReboot();

final runtime = RemindRuntime(
  store: store,
  backends: [notificationBackend, GeofenceBackend(scheduler: scheduler)],
  zone: zone,
);
```

## Platform limits this respects

| | iOS | Android |
|---|---|---|
| Regions monitored | **20 per app** | ~100 per app |
| Survives reboot | Yes | **No** — call `recreateAfterReboot()` at launch |
| Dwell | Not supported | Native, via loitering delay |
| Latency | Exits are not instant | <2 min typical, up to 6 min when stationary |
| Minimum useful radius | ~200 m | 100–150 m |

`GeofenceBackend` budgets **16** regions, below the iOS ceiling of 20. Apple
describes regions as a shared system resource, so taking the whole allowance
would be fragile and antisocial. `Reconciler` prioritises by proximity to the
device and reports what it dropped — which is exactly the workaround Apple
documents for wanting more regions than the limit allows.

**Location triggers cannot be precise.** Android publishes latencies up to six
minutes when the device is stationary. If a reminder needs to arrive at an exact
moment, it needs a time trigger, not a place.

## Licence

MIT
