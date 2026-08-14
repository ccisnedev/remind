import 'package:meta/meta.dart';

/// How much the platform will let you register at once.
///
/// These are hard ceilings imposed by the operating systems, not tuning knobs:
///
/// * iOS keeps only the **64** soonest pending notifications and silently
///   discards the rest. Forty weekly reminders is 280 occurrences, so without a
///   budget most of them never arrive.
/// * iOS monitors at most **20** regions per application, Android roughly 100.
///
/// The defaults leave deliberate headroom below both ceilings, because the host
/// application almost certainly schedules notifications of its own and this
/// library has no way to see them. Consuming the entire allowance would push
/// the application's own notifications out, which would look like a bug in the
/// application rather than in its reminder library.
@immutable
final class SchedulingBudget {
  /// Creates a budget.
  const SchedulingBudget({
    this.maxTimed = 48,
    this.maxRegions = 16,
    this.horizon = const Duration(days: 60),
  })  : assert(maxTimed >= 0, 'maxTimed cannot be negative'),
        assert(maxRegions >= 0, 'maxRegions cannot be negative');

  /// The number of scheduled instants that may be registered at once.
  final int maxTimed;

  /// The number of regions that may be monitored at once.
  final int maxRegions;

  /// How far ahead to schedule.
  ///
  /// Registering further out buys nothing — the window is refreshed every time
  /// the application reconciles — and costs slots that nearer occurrences need.
  final Duration horizon;

  /// A budget with no ceilings, for tests and for backends that impose none.
  static const SchedulingBudget unlimited = SchedulingBudget(
    maxTimed: 1 << 20,
    maxRegions: 1 << 20,
    horizon: Duration(days: 3650),
  );

  @override
  bool operator ==(Object other) =>
      other is SchedulingBudget &&
      other.maxTimed == maxTimed &&
      other.maxRegions == maxRegions &&
      other.horizon == horizon;

  @override
  int get hashCode => Object.hash(maxTimed, maxRegions, horizon);

  @override
  String toString() =>
      'SchedulingBudget(timed: $maxTimed, regions: $maxRegions, '
      'horizon: ${horizon.inDays}d)';
}
