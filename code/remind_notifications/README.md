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

## Android setup

Three things are required. Read the third one even if you skim the rest: it is
the only one that fails **silently**, and it is the reason most "my scheduled
notification never arrives" reports exist.

### 1. Declare the plugin's receivers — or nothing will ever fire

Since `flutter_local_notifications` v16 the plugin no longer declares its own
receivers, so **your app must**. Add this between the `<application>` tags of
`android/app/src/main/AndroidManifest.xml`:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

and this between the `<manifest>` tags, so reminders survive a reboot — Android
clears every scheduled alarm on restart:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

**What it looks like when you forget.** Everything appears correct. The alarm is
registered, it fires exactly on schedule, and the system logs the broadcast —
addressed to a component that was never declared. Nothing runs. There is no
exception, no error in logcat, and no notification. Permissions check out, the
channel looks fine, `pendingRegistrations()` reports the work as scheduled.

If you are staring at that, confirm it in one command:

```sh
adb shell dumpsys alarm | grep your.package.name
```

An entry naming `ScheduledNotificationReceiver` with an `OW=` in the past means
the alarm fired. If no notification followed and there is no error, the receiver
is not declared.

### 2. Gradle and permissions

Both of these fail loudly, so you will find them on your own.

**Core library desugaring.** `flutter_local_notifications` uses `java.time`,
which is only native from API 26. Without desugaring the build stops with
*"Dependency ':flutter_local_notifications' requires core library desugaring"*.
In `android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**The notification permission.** Android 13+ needs `POST_NOTIFICATIONS` declared
and requested at runtime. Declared in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

and requested before wiring the backend up:

```dart
await plugin
    .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
    ?.requestNotificationsPermission();
```

Note what is *not* required: no location permission of any kind, and no
`SCHEDULE_EXACT_ALARM`.

## Exactness

Android batches alarms to save battery, and the window it allows itself widens
with distance. Measured on a device:

| Scheduled | Window Android allowed | Fired |
|---|---|---|
| 21 seconds out | ~0 | 16 s late |
| 2 minutes out | 61 s | 61 s late |
| 12 hours out | **1 hour** | — |

For a reminder that just needs to land sometime that morning, that is fine and
costs no permission at all. For a medication interval or a meeting, arriving
fifteen minutes late can be worse than never arriving. Only the application
knows which it is, so `ExactnessPolicy` makes it a choice:

```dart
FlutterLocalNotificationsScheduler(
  plugin: plugin,
  details: details,
  exactness: ExactnessPolicy.requireExact,
);
```

| Policy | Permission needed | Behaviour |
|---|---|---|
| `inexact` | none | Always batched. Works everywhere, no prompt |
| `preferExact` (default) | optional | Exact when granted, batched when not |
| `requireExact` | yes | Exact when granted; still schedules when not, and reports the degradation |

**No policy ever fails silently, and none refuses to schedule.** Turning
"possibly late" into "definitely never" would be strictly worse whatever your
policy, so the scheduler always registers the reminder and tells you the truth
about it instead:

```dart
if (!await backend.deliversExactly) {
  // Ask, and tell the user if they decline.
  await backend.requestExactPermission();
}
```

### The permission, and the trap in it

Android offers two, and picking the wrong one can get your app rejected.

**`SCHEDULE_EXACT_ALARM`** — denied by default since Android 14. Only the user
can grant it, from Settings → Apps → your app → Alarms & reminders.
`requestExactPermission()` sends them there; it cannot be granted in-app. Safe
for any application.

**`USE_EXACT_ALARM`** — granted automatically at install with no prompt, but
[Google Play restricts it](https://support.google.com/googleplay/android-developer/answer/16558241)
to applications whose **core** function is a clock, alarm or calendar, and
reviews for it. A reminder feature embedded in an app that does something else
does **not** qualify, and declaring it risks rejection.

So: if reminders are the point of your app, `USE_EXACT_ALARM`. If reminders are
a feature of an app that does something else — the case this ecosystem exists
for — declare `SCHEDULE_EXACT_ALARM`, ask for it, and be honest when the answer
is no.

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
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
