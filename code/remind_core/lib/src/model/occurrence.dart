import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import 'condition.dart';
import 'reminder.dart';
import 'trigger.dart';

/// What a daylight-saving transition did to a requested wall-clock time.
///
/// Surfaced rather than hidden because it is the one class of scheduling
/// surprise users notice and blame the app for. An application that wants to
/// warn ("your 02:30 alarm will ring at 03:30 this Sunday") can only do so if
/// the engine says what happened.
enum DstAnomaly {
  /// The requested wall-clock time did not exist, because the clocks jumped
  /// forward over it. The occurrence was moved forward by the transition's
  /// offset delta.
  gapShifted,

  /// The requested wall-clock time existed twice, because the clocks fell back
  /// over it. The occurrence resolved to the first of the two instants.
  ambiguousResolvedEarly,
}

/// A concrete moment at which a reminder is due to fire.
///
/// Produced by the occurrence engine from a [TimeTrigger]. Unlike a trigger,
/// which is a rule, an occurrence is a single instant in absolute time —
/// exactly the thing that can be handed to a platform scheduler.
@immutable
final class Occurrence {
  /// Creates an occurrence.
  const Occurrence({
    required this.reminderId,
    required this.instant,
    required this.trigger,
    this.pendingCondition,
    this.dstAnomaly,
  });

  /// The [Reminder.id] this occurrence belongs to.
  final String reminderId;

  /// The absolute moment the reminder is due, carrying its zone.
  final tz.TZDateTime instant;

  /// The trigger that generated this occurrence.
  ///
  /// A reminder may hold several triggers, so this records which rule is
  /// responsible — useful for diagnostics and for showing the user why a
  /// reminder is scheduled when it is.
  final TimeTrigger trigger;

  /// The part of the reminder's condition that could not be evaluated ahead of
  /// time and must be re-checked when the occurrence fires.
  ///
  /// `null` when nothing is outstanding, which is the common case: an
  /// occurrence with no pending condition can be dispatched by the platform
  /// with no further involvement from the application.
  final Condition? pendingCondition;

  /// How a daylight-saving transition affected this occurrence, if it did.
  final DstAnomaly? dstAnomaly;

  /// Whether firing this occurrence still requires evaluating a condition.
  bool get isConditional => pendingCondition != null;

  @override
  bool operator ==(Object other) =>
      other is Occurrence &&
      other.reminderId == reminderId &&
      other.instant == instant &&
      other.trigger == trigger &&
      other.pendingCondition == pendingCondition &&
      other.dstAnomaly == dstAnomaly;

  @override
  int get hashCode =>
      Object.hash(reminderId, instant, trigger, pendingCondition, dstAnomaly);

  @override
  String toString() => 'Occurrence($reminderId @ $instant'
      '${dstAnomaly == null ? '' : ', ${dstAnomaly!.name}'}'
      '${isConditional ? ', conditional' : ''})';
}
