import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:remind_notifications/remind_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'runtime/geofence_callback.dart';
import 'runtime/notifications.dart';
import 'runtime/prefs_crossing_journal.dart';
import 'runtime/prefs_reminder_store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final zone = await _deviceZone();
  tz.setLocalLocation(zone);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: notificationInitialisation);
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  final store = await PrefsReminderStore.open();
  final journal = await PrefsCrossingJournal.open(zone);

  // Exactness is a hard requirement here: a reminder that arrives fifteen
  // minutes late is worse than one that never arrives at all.
  final notifications = NotificationBackend(
    scheduler: FlutterLocalNotificationsScheduler(
      plugin: plugin,
      details: reminderNotificationDetails,
      exactness: ExactnessPolicy.requireExact,
    ),
  );

  // Android 14 denies the permission by default, so ask once at startup. If
  // the user refuses, the app keeps working and says so rather than delivering
  // late without mentioning it.
  if (!await notifications.deliversExactly) {
    await notifications.requestExactPermission();
  }

  final geofences = NativeGeofenceScheduler(
    callback: onGeofenceCrossing,
    hasLocationPermission: _hasBackgroundLocation,
  );
  await geofences.initialize();
  // Android drops every geofence on reboot and some OEMs do not reliably
  // autostart the app to restore them. iOS keeps them, so this is a no-op
  // there. Calling it at launch costs nothing and covers the gap.
  await geofences.recreateAfterReboot();

  final runtime = RemindRuntime(
    store: store,
    zone: zone,
    backends: [notifications, GeofenceBackend(scheduler: geofences)],
  );

  // The platform holds only a window, so it has to be refilled every launch.
  await runtime.reconcile();

  runApp(
    RemindApp(
      runtime: runtime,
      plugin: plugin,
      details: reminderNotificationDetails,
      journal: journal,
    ),
  );
}

/// Whether the app may watch regions while it is not in the foreground.
///
/// Background location is the strictest permission either platform offers, and
/// on Android it cannot be requested in one step: the user has to grant
/// foreground location first, and only then can "Allow all the time" be asked
/// for — which opens system settings rather than a dialog.
///
/// Reported rather than demanded. An app that only uses date-and-time reminders
/// should never reach this code at all.
Future<bool> _hasBackgroundLocation() async =>
    Permission.locationAlways.isGranted;

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
