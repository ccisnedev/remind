import 'package:native_geofence/native_geofence.dart' as ng;
import 'package:remind_core/remind_core.dart';

import 'monitored_region.dart';

/// What runs, in a background isolate, when a region is crossed.
///
/// Declared here because `native_geofence` keeps its own equivalent typedef
/// private, so consumers have no name to write against.
typedef GeofenceCrossingCallback = Future<void> Function(
  ng.GeofenceCallbackParams params,
);

/// The real [GeofenceScheduler], over `native_geofence`.
///
/// A thin adapter: every decision about *which* regions to watch has already
/// been made by the reconciler before a call reaches here.
final class NativeGeofenceScheduler implements GeofenceScheduler {
  /// Creates a scheduler.
  ///
  /// [hasLocationPermission] is supplied by the application rather than checked
  /// here. Permission handling differs enough between applications — which
  /// package, when to ask, what to do on refusal — that owning it would force a
  /// choice on every consumer. This package asks a question and believes the
  /// answer.
  ///
  /// [callback] must be a **top-level or static** function annotated
  /// `@pragma('vm:entry-point')`. It is resolved by handle and executed in a
  /// separate background isolate, which has no access to the memory of the
  /// isolate that registered it: no store instance, no runtime, no widgets.
  /// Everything it needs must be re-read from persistent storage.
  const NativeGeofenceScheduler({
    required GeofenceCrossingCallback callback,
    required Future<bool> Function() hasLocationPermission,
  })  : _callback = callback,
        _hasLocationPermission = hasLocationPermission;

  final GeofenceCrossingCallback _callback;
  final Future<bool> Function() _hasLocationPermission;

  /// Prepares the plugin. Must be called before anything else.
  Future<void> initialize() => ng.NativeGeofenceManager.instance.initialize();

  /// Re-registers everything after a reboot.
  ///
  /// Android does not restore geofences across a restart, and some OEMs do not
  /// reliably autostart the app to do it. iOS does restore them, so this is a
  /// no-op there. Call it at launch.
  Future<void> recreateAfterReboot() =>
      ng.NativeGeofenceManager.instance.reCreateAfterReboot();

  @override
  Future<bool> isAvailable() => _hasLocationPermission();

  @override
  Future<Set<String>> registeredIds() async =>
      (await ng.NativeGeofenceManager.instance.getRegisteredGeofenceIds())
          .toSet();

  @override
  Future<void> register(MonitoredRegion region) =>
      ng.NativeGeofenceManager.instance.createGeofence(
        ng.Geofence(
          id: region.id,
          location: ng.Location(
            latitude: region.region.center.latitude,
            longitude: region.region.center.longitude,
          ),
          radiusMeters: region.region.radiusMetres,
          triggers: {for (final event in region.events) _toNative(event)},
          iosSettings: const ng.IosGeofenceSettings(),
          androidSettings: ng.AndroidGeofenceSettings(
            initialTriggers: const {},
            loiteringDelay: region.dwellTime ?? const Duration(minutes: 5),
          ),
        ),
        _callback,
      );

  @override
  Future<void> remove(String id) =>
      ng.NativeGeofenceManager.instance.removeGeofenceById(id);

  static ng.GeofenceEvent _toNative(GeoEvent event) => switch (event) {
        GeoEvent.enter => ng.GeofenceEvent.enter,
        GeoEvent.exit => ng.GeofenceEvent.exit,
        GeoEvent.dwell => ng.GeofenceEvent.dwell,
      };
}
