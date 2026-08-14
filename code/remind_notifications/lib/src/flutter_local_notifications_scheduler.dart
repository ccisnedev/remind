import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_scheduler.dart';

/// The real [NotificationScheduler], over `flutter_local_notifications`.
///
/// A thin adapter and nothing more: every scheduling decision has already been
/// made by the time a call reaches here.
///
/// The plugin must be initialised by the application before this is used.
/// Initialisation carries icons, channels and tap callbacks that are entirely
/// the application's business, and taking them over would be presumptuous.
final class FlutterLocalNotificationsScheduler
    implements NotificationScheduler {
  /// Creates a scheduler over an initialised [plugin].
  const FlutterLocalNotificationsScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required NotificationDetails details,
    this.androidScheduleMode = AndroidScheduleMode.inexactAllowWhileIdle,
  })  : _plugin = plugin,
        _details = details;

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationDetails _details;

  /// How precisely Android should honour the scheduled time.
  ///
  /// Defaults to [AndroidScheduleMode.inexactAllowWhileIdle], which needs no
  /// permission at all and still fires in low-power idle, within a window the
  /// system chooses.
  ///
  /// The exact modes are **not** the default on purpose. They require
  /// `SCHEDULE_EXACT_ALARM`, which Android 14 denies by default and which
  /// Google Play restricts to applications whose core function is a clock,
  /// alarm or calendar. An embedded reminder rarely qualifies, so an exact
  /// default would fail on most installations — and fail quietly, which is
  /// worse. Applications that genuinely need to the minute should opt in and
  /// request the permission themselves.
  final AndroidScheduleMode androidScheduleMode;

  @override
  Future<bool> areNotificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    // iOS grants or refuses during initialisation, and offers no equivalent
    // query here. Applications needing certainty should ask the plugin's own
    // permission API and decide before wiring this backend up.
    return true;
  }

  @override
  Future<void> schedule(ScheduledNotification notification) =>
      _plugin.zonedSchedule(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        scheduledDate: notification.when,
        notificationDetails: _details,
        androidScheduleMode: androidScheduleMode,
        payload: notification.payload,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<List<PendingNotification>> pending() async {
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final request in requests)
        PendingNotification(id: request.id, payload: request.payload),
    ];
  }
}
