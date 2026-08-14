/// Delivers [`remind_core`](https://pub.dev/packages/remind_core) reminders as
/// local notifications on Android and iOS.
///
/// This package handles **date and time reminders only**. It declares no
/// location permission, requests none, and cannot watch a region — which is the
/// point: an application that only needs "remind me on Tuesdays at 09:00"
/// depends on this and nothing else, and never has to justify a location
/// permission to an app store.
///
/// ```dart
/// final plugin = FlutterLocalNotificationsPlugin();
/// await plugin.initialize(settings: yourSettings);
///
/// final backend = NotificationBackend(
///   scheduler: FlutterLocalNotificationsScheduler(
///     plugin: plugin,
///     details: yourNotificationDetails,
///   ),
/// );
///
/// const reconciler = Reconciler();
/// final plan = reconciler.plan(
///   reminders: await store.all(),
///   registered: await backend.pendingRegistrations(),
///   zone: zone,
///   now: tz.TZDateTime.now(zone),
///   budget: backend.budget,
/// );
///
/// for (final key in plan.toCancel) {
///   await backend.cancel(key);
/// }
/// for (final registration in plan.toRegister) {
///   await backend.register(registration);
/// }
/// ```
library;

export 'src/flutter_local_notifications_scheduler.dart'
    show FlutterLocalNotificationsScheduler;
export 'src/notification_backend.dart' show NotificationBackend;
export 'src/notification_payload.dart' show NotificationPayload;
export 'src/notification_scheduler.dart'
    show NotificationScheduler, PendingNotification, ScheduledNotification;
