import 'package:meta/meta.dart';

import '../model/condition.dart';
import '../model/geo.dart';

/// The result of evaluating a condition.
///
/// Three-valued rather than boolean, and deliberately so. A geofence condition
/// evaluated while the device's location is unknown has no truthful boolean
/// answer, and collapsing that into `false` would silently swallow reminders
/// the user asked for — the worst possible failure for this kind of library.
/// Callers are forced to decide what to do about [undetermined] instead of
/// having the decision made for them.
enum ConditionOutcome {
  /// The condition is satisfied; the reminder should fire.
  holds,

  /// The condition is not satisfied; the reminder should be suppressed.
  fails,

  /// Not enough information to decide, typically a missing device location.
  undetermined;

  /// Whether this outcome is [holds].
  bool get isHolding => this == holds;

  /// Whether this outcome is [undetermined].
  bool get isUndetermined => this == undetermined;
}

/// The runtime facts a condition is evaluated against.
@immutable
final class EvaluationContext {
  /// Creates an evaluation context.
  ///
  /// [localTime] must already be expressed in the reminder's zone, since
  /// temporal conditions read its calendar and clock fields directly.
  const EvaluationContext({required this.localTime, this.deviceLocation});

  /// The moment being evaluated, in the reminder's own time zone.
  final DateTime localTime;

  /// Where the device is, if known.
  ///
  /// `null` when location is unavailable — permission denied, no recent fix, or
  /// simply not requested. Ambient conditions resolve to
  /// [ConditionOutcome.undetermined] rather than failing in that case.
  final GeoCoordinate? deviceLocation;
}

/// A condition tree split by when its parts can be evaluated.
@immutable
final class ConditionPartition {
  /// Creates a partition.
  const ConditionPartition({this.eager, this.deferred});

  /// The part that depends only on time, and can therefore be evaluated while
  /// enumerating occurrences — before anything is registered with the platform.
  final Condition? eager;

  /// The part that needs runtime state, and must travel with the occurrence to
  /// be evaluated at the moment it fires.
  final Condition? deferred;

  /// Whether anything at all has to be re-checked when the reminder fires.
  bool get hasDeferred => deferred != null;
}

/// Splits [condition] into a part evaluable now and a part evaluable only at
/// firing time.
///
/// Conjunctions distribute cleanly, so `AllOf([temporal, ambient])` splits into
/// both halves and the temporal half can prune occurrences immediately.
/// Disjunctions and negations do not: in `AnyOf([temporal, ambient])` a false
/// temporal half says nothing, because the ambient half may still hold. Those
/// trees are therefore deferred whole. This is a correctness constraint, not a
/// missing optimisation — pruning them eagerly would drop valid occurrences.
ConditionPartition partitionCondition(Condition? condition) {
  if (condition == null) return const ConditionPartition();

  switch (condition) {
    case TemporalCondition():
      return ConditionPartition(eager: condition);

    case AmbientCondition():
      return ConditionPartition(deferred: condition);

    case AllOfCondition(:final conditions):
      final eager = <Condition>[];
      final deferred = <Condition>[];
      for (final child in conditions) {
        final part = partitionCondition(child);
        if (part.eager != null) eager.add(part.eager!);
        if (part.deferred != null) deferred.add(part.deferred!);
      }
      return ConditionPartition(
        eager: _collapseAll(eager),
        deferred: _collapseAll(deferred),
      );

    case AnyOfCondition():
    case NotCondition():
      return isPurelyTemporal(condition)
          ? ConditionPartition(eager: condition)
          : ConditionPartition(deferred: condition);
  }
}

Condition? _collapseAll(List<Condition> parts) => switch (parts.length) {
      0 => null,
      1 => parts.single,
      _ => AllOfCondition(parts),
    };

/// Whether every leaf of [condition] is a [TemporalCondition].
///
/// Purely temporal trees can be resolved from a clock alone, with no device
/// involvement at all.
bool isPurelyTemporal(Condition condition) => switch (condition) {
      TemporalCondition() => true,
      AmbientCondition() => false,
      AllOfCondition(:final conditions) => conditions.every(isPurelyTemporal),
      AnyOfCondition(:final conditions) => conditions.every(isPurelyTemporal),
      NotCondition(:final condition) => isPurelyTemporal(condition),
    };

/// Evaluates [condition] against [context].
///
/// Uses Kleene three-valued logic, so an [ConditionOutcome.undetermined] leaf
/// only propagates when it could still change the answer: a conjunction with
/// one failing branch fails outright, and a disjunction with one holding branch
/// holds outright, regardless of what else is unknown.
///
/// A `null` [condition] holds — an ungated reminder always fires.
ConditionOutcome evaluateCondition(
  Condition? condition,
  EvaluationContext context,
) {
  if (condition == null) return ConditionOutcome.holds;

  switch (condition) {
    case TemporalCondition():
      return condition.holdsAt(context.localTime)
          ? ConditionOutcome.holds
          : ConditionOutcome.fails;

    case InsideRegionCondition(:final region):
      final where = context.deviceLocation;
      if (where == null) return ConditionOutcome.undetermined;
      return region.contains(where)
          ? ConditionOutcome.holds
          : ConditionOutcome.fails;

    case OutsideRegionCondition(:final region):
      final where = context.deviceLocation;
      if (where == null) return ConditionOutcome.undetermined;
      return region.contains(where)
          ? ConditionOutcome.fails
          : ConditionOutcome.holds;

    case AllOfCondition(:final conditions):
      var sawUnknown = false;
      for (final child in conditions) {
        switch (evaluateCondition(child, context)) {
          case ConditionOutcome.fails:
            return ConditionOutcome.fails;
          case ConditionOutcome.undetermined:
            sawUnknown = true;
          case ConditionOutcome.holds:
            break;
        }
      }
      return sawUnknown
          ? ConditionOutcome.undetermined
          : ConditionOutcome.holds;

    case AnyOfCondition(:final conditions):
      var sawUnknown = false;
      for (final child in conditions) {
        switch (evaluateCondition(child, context)) {
          case ConditionOutcome.holds:
            return ConditionOutcome.holds;
          case ConditionOutcome.undetermined:
            sawUnknown = true;
          case ConditionOutcome.fails:
            break;
        }
      }
      return sawUnknown
          ? ConditionOutcome.undetermined
          : ConditionOutcome.fails;

    case NotCondition(:final condition):
      return switch (evaluateCondition(condition, context)) {
        ConditionOutcome.holds => ConditionOutcome.fails,
        ConditionOutcome.fails => ConditionOutcome.holds,
        ConditionOutcome.undetermined => ConditionOutcome.undetermined,
      };
  }
}
