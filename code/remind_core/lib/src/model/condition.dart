import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'calendar_date.dart';
import 'geo.dart';
import 'local_time.dart';
import 'trigger.dart';
import 'weekday.dart';

/// A gate on whether a reminder that has been triggered should actually fire.
///
/// Triggers answer *when* to look; conditions answer *whether to act*. Keeping
/// them apart is what makes mixed time-and-place reminders expressible at all,
/// because neither platform offers a combined primitive. "When I get to the
/// office, but only on weekdays" becomes a [LocationTrigger] gated by a
/// [WeekdaysCondition]; the OS reports the arrival and the gate is evaluated
/// here.
///
/// Conditions divide by *when they can be evaluated*:
///
/// * [TemporalCondition] depends only on a moment in time, so the occurrence
///   engine can evaluate it while enumerating and simply skip the occurrences
///   that fail. Nothing needs to reach the device.
/// * [AmbientCondition] depends on runtime state the engine cannot know in
///   advance, such as where the device is. It has to be carried along with the
///   occurrence and evaluated at the moment of firing.
///
/// `ConditionPartition` performs that split.
@immutable
sealed class Condition {
  const Condition();
}

/// A condition that is a pure function of a moment in time.
@immutable
sealed class TemporalCondition extends Condition {
  const TemporalCondition();

  /// Whether this condition holds at [local], a wall-clock time already
  /// resolved into the reminder's zone.
  bool holdsAt(DateTime local);
}

/// A condition that depends on device state and can only be evaluated at the
/// moment the reminder would fire.
@immutable
sealed class AmbientCondition extends Condition {
  const AmbientCondition();
}

/// Restricts a reminder to a window of calendar dates.
///
/// Both bounds are inclusive, and either may be omitted for an open-ended
/// window. This is how "every weekday, but only during the school term" is
/// expressed.
@immutable
final class DateRangeCondition extends TemporalCondition {
  /// Creates a date window. At least one bound should be supplied for the
  /// condition to mean anything.
  const DateRangeCondition({this.from, this.until});

  /// The first date on which the reminder may fire, inclusive.
  final CalendarDate? from;

  /// The last date on which the reminder may fire, inclusive.
  final CalendarDate? until;

  @override
  bool holdsAt(DateTime local) {
    final date = CalendarDate.fromDateTime(local);
    if (from != null && date < from!) return false;
    if (until != null && date > until!) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is DateRangeCondition && other.from == from && other.until == until;

  @override
  int get hashCode => Object.hash(from, until);

  @override
  String toString() => 'DateRangeCondition(${from ?? '-'}..${until ?? '-'})';
}

/// Suppresses a reminder on specific dates.
///
/// The holiday-and-vacation escape hatch: keep the weekly rule, punch holes in
/// it, without having to enumerate every date the rule does cover.
@immutable
final class ExcludedDatesCondition extends TemporalCondition {
  /// Creates an exclusion set.
  ExcludedDatesCondition(Set<CalendarDate> dates)
      : dates = Set.unmodifiable(dates);

  /// The dates on which the reminder must not fire.
  final Set<CalendarDate> dates;

  @override
  bool holdsAt(DateTime local) =>
      !dates.contains(CalendarDate.fromDateTime(local));

  @override
  bool operator ==(Object other) =>
      other is ExcludedDatesCondition &&
      const SetEquality<CalendarDate>().equals(other.dates, dates);

  @override
  int get hashCode => const SetEquality<CalendarDate>().hash(dates);

  @override
  String toString() => 'ExcludedDatesCondition(${dates.length} dates)';
}

/// Restricts a reminder to particular days of the week.
///
/// Redundant on a [WeeklyTrigger], which already carries its own days. Its
/// purpose is to narrow triggers that have no notion of weekday — chiefly
/// [LocationTrigger] and [DailyTrigger].
@immutable
final class WeekdaysCondition extends TemporalCondition {
  /// Creates a weekday restriction.
  WeekdaysCondition(Set<Weekday> days) : days = Set.unmodifiable(days);

  /// The days on which the reminder may fire.
  final Set<Weekday> days;

  @override
  bool holdsAt(DateTime local) => days.contains(Weekday.of(local));

  @override
  bool operator ==(Object other) =>
      other is WeekdaysCondition &&
      const SetEquality<Weekday>().equals(other.days, days);

  @override
  int get hashCode => const SetEquality<Weekday>().hash(days);

  @override
  String toString() =>
      'WeekdaysCondition(${days.map((d) => d.name).join(', ')})';
}

/// Restricts a reminder to a window within the day.
///
/// Chiefly useful for gating a [LocationTrigger]: "when I arrive at the
/// supermarket, but only between 08:00 and 22:00".
///
/// A window whose [from] is later than its [until] wraps around midnight, so
/// `22:00`–`06:00` is the overnight window rather than an empty one.
@immutable
final class TimeRangeCondition extends TemporalCondition {
  /// Creates a within-the-day window. Both bounds are inclusive.
  const TimeRangeCondition({required this.from, required this.until});

  /// The start of the window.
  final LocalTime from;

  /// The end of the window.
  final LocalTime until;

  /// Whether this window spans midnight.
  bool get wrapsMidnight => from > until;

  @override
  bool holdsAt(DateTime local) {
    final at = LocalTime.fromDateTime(local);
    if (wrapsMidnight) return at >= from || at <= until;
    return at >= from && at <= until;
  }

  @override
  bool operator ==(Object other) =>
      other is TimeRangeCondition && other.from == from && other.until == until;

  @override
  int get hashCode => Object.hash(from, until);

  @override
  String toString() => 'TimeRangeCondition($from..$until)';
}

/// Holds while the device is inside [region].
@immutable
final class InsideRegionCondition extends AmbientCondition {
  /// Creates an inside-the-region gate.
  const InsideRegionCondition(this.region);

  /// The area the device must be inside of.
  final GeoRegion region;

  @override
  bool operator ==(Object other) =>
      other is InsideRegionCondition && other.region == region;

  @override
  int get hashCode => region.hashCode;

  @override
  String toString() => 'InsideRegionCondition(${region.id})';
}

/// Holds while the device is outside [region].
@immutable
final class OutsideRegionCondition extends AmbientCondition {
  /// Creates an outside-the-region gate.
  const OutsideRegionCondition(this.region);

  /// The area the device must be outside of.
  final GeoRegion region;

  @override
  bool operator ==(Object other) =>
      other is OutsideRegionCondition && other.region == region;

  @override
  int get hashCode => region.hashCode;

  @override
  String toString() => 'OutsideRegionCondition(${region.id})';
}

/// Holds only when every one of [conditions] holds.
///
/// An empty list holds vacuously, matching the usual convention for a universal
/// quantifier over nothing.
@immutable
final class AllOfCondition extends Condition {
  /// Creates a conjunction.
  AllOfCondition(List<Condition> conditions)
      : conditions = List.unmodifiable(conditions);

  /// The conditions that must all hold.
  final List<Condition> conditions;

  @override
  bool operator ==(Object other) =>
      other is AllOfCondition &&
      const ListEquality<Condition>().equals(other.conditions, conditions);

  @override
  int get hashCode => const ListEquality<Condition>().hash(conditions);

  @override
  String toString() => 'AllOfCondition(${conditions.join(' && ')})';
}

/// Holds when at least one of [conditions] holds.
///
/// An empty list never holds.
@immutable
final class AnyOfCondition extends Condition {
  /// Creates a disjunction.
  AnyOfCondition(List<Condition> conditions)
      : conditions = List.unmodifiable(conditions);

  /// The conditions of which at least one must hold.
  final List<Condition> conditions;

  @override
  bool operator ==(Object other) =>
      other is AnyOfCondition &&
      const ListEquality<Condition>().equals(other.conditions, conditions);

  @override
  int get hashCode => const ListEquality<Condition>().hash(conditions);

  @override
  String toString() => 'AnyOfCondition(${conditions.join(' || ')})';
}

/// Holds exactly when [condition] does not.
@immutable
final class NotCondition extends Condition {
  /// Creates a negation.
  const NotCondition(this.condition);

  /// The condition being negated.
  final Condition condition;

  @override
  bool operator ==(Object other) =>
      other is NotCondition && other.condition == condition;

  @override
  int get hashCode => condition.hashCode;

  @override
  String toString() => 'NotCondition($condition)';
}
