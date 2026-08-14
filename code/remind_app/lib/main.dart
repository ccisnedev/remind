import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:remind_notifications/remind_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'runtime/prefs_reminder_store.dart';
import 'runtime/remind_runtime.dart';
import 'ui/app.dart';

/// The channel reminders are delivered on.
///
/// `Importance.max` so Android shows a heads-up notification rather than a
/// silent entry in the shade — without it a reminder that fires perfectly looks
/// exactly like one that never fired.
const NotificationDetails _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Scheduled reminders from remind_app',
    importance: Importance.max,
    priority: Priority.high,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final zone = await _deviceZone();
  tz.setLocalLocation(zone);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  final store = await PrefsReminderStore.open();
  final runtime = RemindRuntime(
    store: store,
    zone: zone,
    backends: [
      NotificationBackend(
        scheduler: FlutterLocalNotificationsScheduler(
          plugin: plugin,
          details: _details,
        ),
      ),
    ],
  );

  // The platform holds only a window, so it has to be refilled every launch.
  await runtime.reconcile();

  runApp(RemindApp(runtime: runtime));
}

/// The device's own time zone, falling back to UTC if the platform will not
/// say.
///
/// Getting this wrong is not a cosmetic problem: every wall-clock time in every
/// reminder is interpreted in this zone, so a wrong guess moves every alarm.
Future<tz.Location> _deviceZone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return tz.getLocation(info.identifier);
  } on Object {
    return tz.getLocation('UTC');
  }
}
