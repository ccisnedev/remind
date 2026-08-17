import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The channel reminders are delivered on.
///
/// `Importance.max` so Android shows a heads-up notification rather than a
/// silent entry in the shade — without it a reminder that fires perfectly looks
/// exactly like one that never fired.
///
/// Shared rather than declared twice because the background isolate that
/// handles a geofence crossing has to post on the same channel as the
/// foreground. Two definitions that drifted apart would put crossings on a
/// channel the user had never seen, and Android only honours a channel's
/// settings the first time it is created.
const NotificationDetails reminderNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Scheduled reminders from remind_app',
    importance: Importance.max,
    priority: Priority.high,
  ),
);

/// How the plugin is initialised, in either isolate.
const InitializationSettings notificationInitialisation =
    InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
