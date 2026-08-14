# remind_notifications

Delivers [`remind_core`](../remind_core) reminders as local notifications on
Android and iOS, over
[`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications).

**Date and time reminders only.** This package declares no location permission,
requests none, and cannot watch a region. That is the point: an application that
only needs *"remind me on Tuesdays at 09:00"* depends on this and nothing else,
and never has to justify a location permission to an app store.

## Install

```yaml
dependencies:
  remind_core: ^0.1.0
  remind_notifications: ^0.1.0
```

## Use

Initialise the plugin yourself — icons, channels and tap handling are your
application's business, not this package's — then hand it over:

```dart
final plugin = FlutterLocalNotificationsPlugin();
await plugin.initialize(settings: yourSettings);

final backend = NotificationBackend(
  scheduler: FlutterLocalNotificationsScheduler(
    plugin: plugin,
    details: yourNotificationDetails,
  ),
);
```

Then reconcile, whenever the world may have changed — on launch, on resume,
after a reboot, after a time zone change, and after any edit:

```dart
const reconciler = Reconciler();

final plan = reconciler.plan(
  reminders: await store.all(),
  registered: await backend.pendingRegistrations(),
  zone: zone,
  now: tz.TZDateTime.now(zone),
  budget: backend.budget,
);

for (final key in plan.toCancel) {
  await backend.cancel(key);
}
for (final registration in plan.toRegister) {
  await backend.register(registration);
}
```

Reconciling twice in a row is a no-op: the second plan comes back empty.

## What it refuses, and why

`canHandle` returns `false` for two kinds of work, and in both cases it is
reporting a platform limit rather than an unfinished feature.

**Regions.** The backend declares `maxRegions: 0`, so the reconciler never hands
it a geofence. Region monitoring belongs to `remind_geofence`.

**Registrations with an outstanding condition.** A scheduled local notification
is displayed by the operating system without running any of your application's
code first. On iOS the notification service extension that could intercept it
fires only for *remote* push, never for a local notification. So there is no
moment at which this backend could evaluate a geofence condition and decide to
stay quiet. Rather than deliver a reminder whose condition might not hold, it
declines the work — and `register` throws if you force one through anyway.

Note that this only affects **ambient** conditions. Everything time-based —
date ranges, excluded dates, weekdays, time-of-day windows — is resolved by the
occurrence engine before scheduling, so those reminders schedule normally.

## Android exactness

`FlutterLocalNotificationsScheduler` defaults to
`AndroidScheduleMode.inexactAllowWhileIdle`.

This is deliberate. The exact modes require `SCHEDULE_EXACT_ALARM`, which
Android 14 denies by default and which
[Google Play restricts](https://support.google.com/googleplay/android-developer/answer/16558241)
to applications whose core function is a clock, alarm or calendar. An embedded
reminder rarely qualifies, so an exact default would fail on most installations
— and fail quietly, which is worse than firing a few minutes late.

If your application genuinely needs to-the-minute delivery and qualifies for the
permission, opt in and request it yourself:

```dart
FlutterLocalNotificationsScheduler(
  plugin: plugin,
  details: details,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
);
```

## Testing

`NotificationScheduler` is a four-method interface over the plugin, so the
scheduling behaviour can be tested with a fake and no device:

```dart
final class FakeScheduler implements NotificationScheduler { /* … */ }

final backend = NotificationBackend(scheduler: FakeScheduler());
```

## Identity

The platform reports a pending notification as an integer id, a title, a body
and a payload — and the integer is a lossy hash of the registration key, not the
key itself. The key therefore travels inside the payload as JSON, which is how
`pendingRegistrations()` reconstructs what the platform is actually holding.

Notifications whose payload is absent, malformed, or simply not ours are
reported with a key that can never match one of ours, so they are visible to the
reconciler and can never be cancelled by mistake. An application scheduling its
own notifications alongside `remind` keeps them.

## Licence

MIT
