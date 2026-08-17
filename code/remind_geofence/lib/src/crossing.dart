import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// A boundary crossing the platform has just reported.
///
/// Everything known at the moment a region fires, which is less than one might
/// hope: iOS never reports where the device is, and Android reports it only
/// sometimes. What is always known is *which* region fired and *how*, and that
/// turns out to be enough to decide most conditions.
@immutable
final class Crossing {
  /// Creates a crossing.
  const Crossing({
    required this.reminder,
    required this.region,
    required this.event,
    required this.at,
    this.deviceLocation,
    this.pendingCondition,
  });

  /// The reminder the crossed region belongs to.
  final Reminder reminder;

  /// The region that was crossed.
  final GeoRegion region;

  /// How it was crossed.
  final GeoEvent event;

  /// When, in the reminder's zone.
  final tz.TZDateTime at;

  /// Where the device was, if the platform said.
  ///
  /// `null` on iOS always, and on Android often enough that it cannot be
  /// relied on. Absence is not failure — see [Crossing.region], which is
  /// itself evidence about the device's position relative to that one region.
  final GeoCoordinate? deviceLocation;

  /// The condition still to be checked before notifying.
  final Condition? pendingCondition;

  /// Whether this crossing proves the device is inside [region].
  ///
  /// Entering or dwelling in a region is direct evidence of being inside it,
  /// available even when the platform reports no coordinates at all.
  bool get provesInsideRegion =>
      event == GeoEvent.enter || event == GeoEvent.dwell;

  @override
  String toString() =>
      'Crossing(${reminder.id}, ${event.name} ${region.id} at $at)';
}
