import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';

/// One region handed to the platform to watch.
@immutable
final class MonitoredRegion {
  /// Creates a region to monitor.
  const MonitoredRegion({
    required this.id,
    required this.region,
    required this.events,
    this.dwellTime,
  });

  /// The identifier the platform stores it under.
  ///
  /// This is a `RegistrationKey` in string form, which is what lets the
  /// reconciler recognise its own regions when the platform lists them back.
  final String id;

  /// The area being watched.
  final GeoRegion region;

  /// Which boundary crossings to report.
  final Set<GeoEvent> events;

  /// How long the device must remain inside before a dwell fires.
  final Duration? dwellTime;

  @override
  bool operator ==(Object other) =>
      other is MonitoredRegion &&
      other.id == id &&
      other.region == region &&
      other.dwellTime == dwellTime &&
      other.events.length == events.length &&
      other.events.containsAll(events);

  @override
  int get hashCode => Object.hash(id, region, dwellTime, events.length);

  @override
  String toString() => 'MonitoredRegion($id, ${region.id})';
}

/// The narrow slice of a geofencing plugin that this package uses.
///
/// Behind an interface for the same reason as the notification scheduler: the
/// underlying plugin is platform-bound, so a backend written directly against
/// it could only be tested on a device.
abstract interface class GeofenceScheduler {
  /// Whether region monitoring is usable right now.
  ///
  /// False when location permission has not been granted, when background
  /// location is missing, or when the platform cannot monitor regions at all.
  Future<bool> isAvailable();

  /// The identifiers of every region the platform is currently watching.
  Future<Set<String>> registeredIds();

  /// Starts watching [region], replacing any with the same id.
  Future<void> register(MonitoredRegion region);

  /// Stops watching the region with [id]. Unknown ids are not an error.
  Future<void> remove(String id);
}
