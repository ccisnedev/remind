import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:native_geofence/native_geofence.dart' as ng;
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notifications.dart';
import 'prefs_crossing_journal.dart';
import 'prefs_reminder_store.dart';

/// Runs when the device crosses a monitored region.
///
/// **This executes in a background isolate**, not the one the application runs
/// in. It gets a fresh Dart heap: no store, no runtime, no plugin registry, and
/// nothing any earlier code set up. Everything below is rebuilt from scratch,
/// and it has to be — reaching for a singleton here would work in a test and
/// find `null` on a device.
///
/// It must be a top-level or static function annotated `@pragma('vm:entry-point')`
/// so the plugin can resolve it by handle across that boundary, and it must not
/// close over anything.
///
/// Nothing is allowed to escape. An uncaught exception in a background isolate
/// gives no stack anybody will read and silently loses the crossing.
@pragma('vm:entry-point')
Future<void> onGeofenceCrossing(ng.GeofenceCallbackParams params) async {
  try {
    // Without this the isolate has no plugins at all: no shared_preferences to
    // read reminders from, no notifications to post with.
    DartPluginRegistrant.ensureInitialized();

    tzdata.initializeTimeZones();
    final zone = await _deviceZone();

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: notificationInitialisation);

    final handler = CrossingHandler(
      store: await PrefsReminderStore.open(),
      journal: await PrefsCrossingJournal.open(zone),
      deliver: (crossing) => _show(plugin, crossing),
    );

    await handler.handle(
      firedRegionIds: {for (final fence in params.geofences) fence.id},
      event: _toGeoEvent(params.event),
      zone: zone,
      at: tz.TZDateTime.now(zone),
      deviceLocation: params.location == null
          ? null
          : GeoCoordinate(
              params.location!.latitude,
              params.location!.longitude,
            ),
    );
  } on Object catch (error, stackTrace) {
    // Last resort. There is nowhere useful to report from here, but crashing
    // the isolate would lose every crossing in the same batch as well.
    // ignore: avoid_print
    print('remind_geofence callback failed: $error\n$stackTrace');
  }
}

Future<void> _show(
  FlutterLocalNotificationsPlugin plugin,
  Crossing crossing,
) => plugin.show(
  id: RegistrationKey.forRegion(
    reminderId: crossing.reminder.id,
    region: crossing.region,
    event: crossing.event,
  ).platformId,
  title: crossing.reminder.title,
  body: crossing.reminder.body,
  notificationDetails: reminderNotificationDetails,
);

GeoEvent _toGeoEvent(ng.GeofenceEvent event) => switch (event) {
  ng.GeofenceEvent.enter => GeoEvent.enter,
  ng.GeofenceEvent.exit => GeoEvent.exit,
  ng.GeofenceEvent.dwell => GeoEvent.dwell,
};

/// The device's zone, falling back to UTC.
///
/// Read again here rather than passed in, because nothing can be passed in.
Future<tz.Location> _deviceZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return tz.getLocation(info.identifier);
  } on Object {
    return tz.getLocation('UTC');
  }
}
