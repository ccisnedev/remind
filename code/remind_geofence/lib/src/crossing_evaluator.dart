import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';

import 'crossing.dart';
import 'crossing_outcome.dart';

/// What to do when a condition cannot be decided.
enum UndeterminedPolicy {
  /// Stay quiet.
  ///
  /// The default. A user who asked to be reminded only somewhere specific has
  /// said something about where they want to be interrupted, and firing on a
  /// condition nobody could evaluate ignores that.
  stayQuiet,

  /// Notify anyway.
  ///
  /// For reminders where being told at the wrong moment beats not being told —
  /// and for applications willing to explain the uncertainty in the
  /// notification itself.
  notify,
}

/// Decides what a boundary crossing should do, and records why.
///
/// The evaluation is ordinary three-valued condition logic from `remind_core`,
/// with one addition: **the crossing is evidence about itself**. iOS never
/// reports the device's coordinates alongside a region event and Android
/// often omits them, so a naive evaluation would find every location condition
/// undecidable — including the obvious one, "remind me when I am at the shop",
/// evaluated at the exact moment the shop's geofence fired.
///
/// Entering or dwelling in a region proves the device is inside it; leaving
/// proves it is outside. Conditions about *that* region are therefore decidable
/// with no coordinates at all. Conditions about any *other* region are not, and
/// are left undecided rather than guessed.
@immutable
final class CrossingEvaluator {
  /// Creates an evaluator.
  const CrossingEvaluator({
    this.whenUndetermined = UndeterminedPolicy.stayQuiet,
  });

  /// What to do when a condition cannot be decided.
  final UndeterminedPolicy whenUndetermined;

  /// Decides the fate of [crossing].
  CrossingOutcome evaluate(Crossing crossing) {
    if (!crossing.reminder.enabled) {
      return Suppressed(
        reminderId: crossing.reminder.id,
        region: crossing.region,
        event: crossing.event,
        at: crossing.at,
        reason: 'the reminder is disabled.',
      );
    }

    final condition = crossing.pendingCondition;
    if (condition == null) {
      return Delivered(
        reminderId: crossing.reminder.id,
        region: crossing.region,
        event: crossing.event,
        at: crossing.at,
      );
    }

    final outcome = evaluateCondition(
      _withCrossingAsEvidence(condition, crossing),
      EvaluationContext(
        localTime: crossing.at,
        deviceLocation: crossing.deviceLocation,
      ),
    );

    return switch (outcome) {
      ConditionOutcome.holds => Delivered(
          reminderId: crossing.reminder.id,
          region: crossing.region,
          event: crossing.event,
          at: crossing.at,
        ),
      ConditionOutcome.fails => Suppressed(
          reminderId: crossing.reminder.id,
          region: crossing.region,
          event: crossing.event,
          at: crossing.at,
          condition: condition,
          reason: 'a condition on the reminder did not hold: $condition',
        ),
      ConditionOutcome.undetermined => Undetermined(
          reminderId: crossing.reminder.id,
          region: crossing.region,
          event: crossing.event,
          at: crossing.at,
          condition: condition,
          notified: whenUndetermined == UndeterminedPolicy.notify,
          reason: 'a condition could not be decided without knowing where the '
              'device is: $condition.',
        ),
    };
  }

  /// Rewrites [condition], replacing what the crossing already settles.
  ///
  /// Conditions about the region that fired are resolved here and substituted
  /// with a trivially true or false stand-in. Everything else is left alone and
  /// evaluated normally.
  ///
  /// Substitution rather than a bespoke recursive evaluator, deliberately: the
  /// Kleene logic that combines `AllOf`, `AnyOf` and `Not` around unknowns is
  /// subtle and already tested in `remind_core`. Reimplementing it here to
  /// intercept two leaf types would duplicate the delicate part in order to
  /// change the trivial one. This walk only rewrites leaves; the reasoning
  /// stays where it is tested.
  Condition _withCrossingAsEvidence(Condition condition, Crossing crossing) {
    switch (condition) {
      case InsideRegionCondition(:final region):
        if (region != crossing.region) return condition;
        return crossing.provesInsideRegion ? _alwaysHolds : _neverHolds;

      case OutsideRegionCondition(:final region):
        if (region != crossing.region) return condition;
        return crossing.provesInsideRegion ? _neverHolds : _alwaysHolds;

      case AllOfCondition(:final conditions):
        return AllOfCondition([
          for (final child in conditions)
            _withCrossingAsEvidence(child, crossing),
        ]);

      case AnyOfCondition(:final conditions):
        return AnyOfCondition([
          for (final child in conditions)
            _withCrossingAsEvidence(child, crossing),
        ]);

      case NotCondition(:final condition):
        return NotCondition(_withCrossingAsEvidence(condition, crossing));

      case TemporalCondition():
        return condition;
    }
  }

  /// A date range with no bounds, which holds at every instant.
  static const Condition _alwaysHolds = DateRangeCondition();

  /// Its negation.
  static const Condition _neverHolds = NotCondition(DateRangeCondition());
}
