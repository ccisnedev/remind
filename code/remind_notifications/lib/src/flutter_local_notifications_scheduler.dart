import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'exactness.dart';
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
    this.exactness = ExactnessPolicy.preferExact,
  })  : _plugin = plugin,
        _details = details;

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationDetails _details;

  /// How precisely delivery should be attempted.
  ///
  /// Exact modes require `SCHEDULE_EXACT_ALARM`, which Android 14 denies by
  /// default and which the user grants from system settings, or
  /// `USE_EXACT_ALARM`, which is granted automatically but is
  /// [restricted by Google Play](https://support.google.com/googleplay/android-developer/answer/16558241)
  /// to applications whose core function is a clock, alarm or calendar.
  ///
  /// Declare whichever your application qualifies for in its manifest.
  final ExactnessPolicy exactness;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> areNotificationsEnabled() async {
    final android = _android;
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    // iOS grants or refuses during initialisation and offers no equivalent
    // query here. Applications needing certainty should ask the plugin's own
    // permission API and decide before wiring this backend up.
    return true;
  }

  @override
  Future<bool> canDeliverExactly() async {
    if (exactness == ExactnessPolicy.inexact) return false;

    final android = _android;
    // iOS honours the scheduled instant without a permission of this kind.
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<bool> requestExactPermission() async {
    if (exactness == ExactnessPolicy.inexact) return false;
    final android = _android;
    if (android == null) return true;
    return await android.requestExactAlarmsPermission() ?? false;
  }

  @override
  Future<void> schedule(ScheduledNotification notification) async =>
      _plugin.zonedSchedule(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        scheduledDate: notification.when,
        notificationDetails: _details,
        androidScheduleMode: await _mode(),
        payload: notification.payload,
      );

  /// The Android mode to schedule with, given the policy and what the platform
  /// currently allows.
  ///
  /// Falls back to inexact rather than throwing when an exact mode is wanted
  /// but not permitted. Throwing would leave the reminder unscheduled entirely,
  /// which is a worse outcome than a late one — and the application already has
  /// [canDeliverExactly] to discover the degradation and say so.
  Future<AndroidScheduleMode> _mode() async {
    if (exactness == ExactnessPolicy.inexact) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    final permitted = await canDeliverExactly();
    return permitted
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

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
