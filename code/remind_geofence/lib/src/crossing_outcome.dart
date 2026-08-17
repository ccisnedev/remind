import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// What happened when a region fired, and why.
///
/// Every crossing produces one of these, including the ones that reach nobody.
/// That is the point.
///
/// A reminder gated on both a place and a condition has a failure mode no
/// ordinary reminder has: it can work perfectly and still stay silent, and the
/// user cannot tell that apart from a geofence that never fired. Every product
/// surveyed while designing this avoided conjunctive rules, and explainability
/// is the most likely reason. Keeping conjunction therefore carries an
/// obligation to make silence legible — so an outcome is produced whether or
/// not anything is shown, and it always carries enough to answer "why did
/// nothing happen when I walked in?".
@immutable
sealed class CrossingOutcome {
  const CrossingOutcome({
    required this.reminderId,
    required this.region,
    required this.event,
    required this.at,
  });

  /// The reminder involved.
  final String reminderId;

  /// The region that fired.
  final GeoRegion region;

  /// How it was crossed.
  final GeoEvent event;

  /// When it fired.
  final tz.TZDateTime at;

  /// Whether the user should be told.
  bool get shouldNotify;

  /// A sentence a person can read.
  ///
  /// Intended for a diagnostics screen and for logs, not for the notification
  /// itself.
  String get explanation;
}

/// The crossing reached the user.
@immutable
final class Delivered extends CrossingOutcome {
  /// Creates a delivered outcome.
  const Delivered({
    required super.reminderId,
    required super.region,
    required super.event,
    required super.at,
  });

  @override
  bool get shouldNotify => true;

  @override
  String get explanation =>
      'Delivered: ${event.name} of ${region.id} fired and every condition held.';

  @override
  String toString() => 'Delivered($reminderId, ${region.id})';
}

/// The crossing fired but was deliberately not shown.
@immutable
final class Suppressed extends CrossingOutcome {
  /// Creates a suppressed outcome.
  const Suppressed({
    required super.reminderId,
    required super.region,
    required super.event,
    required super.at,
    required this.reason,
    this.condition,
  });

  /// The condition that excluded it, when one did.
  ///
  /// `null` when the reminder was suppressed for a reason other than a
  /// condition — most commonly because it is disabled.
  final Condition? condition;

  /// Why, in a form meant to be shown.
  final String reason;

  @override
  bool get shouldNotify => false;

  @override
  String get explanation =>
      'Suppressed: ${event.name} of ${region.id} fired, but $reason';

  @override
  String toString() => 'Suppressed($reminderId, ${region.id}: $reason)';
}

/// The crossing fired but the condition could not be decided.
///
/// Distinct from [Suppressed] on purpose. "The condition did not hold" and "I
/// could not tell whether it held" are different answers to the user's
/// question, and collapsing them would hide a permission problem behind what
/// looks like a working reminder.
@immutable
final class Undetermined extends CrossingOutcome {
  /// Creates an undetermined outcome.
  const Undetermined({
    required super.reminderId,
    required super.region,
    required super.event,
    required super.at,
    required this.condition,
    required this.notified,
    required this.reason,
  });

  /// The condition that could not be resolved.
  final Condition condition;

  /// Why it could not be resolved.
  final String reason;

  /// Whether the configured policy chose to notify anyway.
  final bool notified;

  @override
  bool get shouldNotify => notified;

  @override
  String get explanation =>
      'Undetermined: ${event.name} of ${region.id} fired, but $reason '
      '${notified ? 'Notified anyway.' : 'Stayed quiet.'}';

  @override
  String toString() => 'Undetermined($reminderId, ${region.id})';
}
