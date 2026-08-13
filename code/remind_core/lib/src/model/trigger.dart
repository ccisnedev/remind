import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'calendar_date.dart';
import 'geo.dart';
import 'local_time.dart';
import 'weekday.dart';

/// Something that can cause a reminder to fire.
///
/// Triggers split into two families that behave very differently, and the split
/// is a property of the operating system rather than a modelling preference:
///
/// * [TimeTrigger] is **generative**. Given a zone, you can enumerate its next
///   occurrences ahead of time, which is what lets the reconciler decide how
///   many to register and when to refresh them.
/// * [LocationTrigger] is **reactive**. There is no way to enumerate the next
///   ten times a user will walk into a building. The region is handed to the OS
///   and the OS calls back.
///
/// A reminder may carry several triggers; they combine with OR semantics. To
/// narrow *when* a trigger is allowed to fire, use a condition instead.
@immutable
sealed class Trigger {
  const Trigger();
}

/// A trigger whose future occurrences can be enumerated from a clock and a
/// calendar alone.
@immutable
sealed class TimeTrigger extends Trigger {
  const TimeTrigger();

  /// The wall-clock time of day at which this trigger fires.
  LocalTime get time;
}

/// Fires once, at a specific date and time, and never again.
///
/// This is the "remind me on 3 March at 09:00" case.
@immutable
final class OneShotTrigger extends TimeTrigger {
  /// Creates a one-off trigger for [date] at [time].
  const OneShotTrigger({required this.date, required this.time});

  /// The calendar date on which the trigger fires.
  final CalendarDate date;

  @override
  final LocalTime time;

  @override
  bool operator ==(Object other) =>
      other is OneShotTrigger && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => 'OneShotTrigger($date $time)';
}

/// Fires every day at [time], or every [intervalDays] days.
@immutable
final class DailyTrigger extends TimeTrigger {
  /// Creates a daily trigger.
  ///
  /// [intervalDays] of 1 means every day, 2 means every other day, and so on.
  /// When it is greater than 1 an [anchor] is required, because "every other
  /// day" is meaningless without knowing which day the count starts from.
  const DailyTrigger({
    required this.time,
    this.intervalDays = 1,
    this.anchor,
  })  : assert(intervalDays >= 1, 'intervalDays must be at least 1'),
        assert(
          intervalDays == 1 || anchor != null,
          'An anchor date is required when intervalDays > 1',
        );

  @override
  final LocalTime time;

  /// How many days apart consecutive occurrences fall.
  final int intervalDays;

  /// The date the interval counts from, when [intervalDays] is greater than 1.
  final CalendarDate? anchor;

  @override
  bool operator ==(Object other) =>
      other is DailyTrigger &&
      other.time == time &&
      other.intervalDays == intervalDays &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(time, intervalDays, anchor);

  @override
  String toString() => intervalDays == 1
      ? 'DailyTrigger($time)'
      : 'DailyTrigger($time, every $intervalDays days from $anchor)';
}

/// Fires at [time] on each of the selected [days] of the week.
///
/// This is the ordinary alarm-clock case: pick a time, tick the days it should
/// repeat on. A single day and all seven days are both valid.
@immutable
final class WeeklyTrigger extends TimeTrigger {
  /// Creates a weekly trigger.
  ///
  /// [days] must not be empty — a weekly trigger with no days selected would
  /// never fire, which is almost always a bug in the calling code rather than
  /// an intent, and silently accepting it makes that bug invisible.
  WeeklyTrigger({required Set<Weekday> days, required this.time})
      : assert(days.isNotEmpty, 'days must not be empty'),
        days = Set.unmodifiable(days);

  /// The days of the week on which this trigger fires.
  final Set<Weekday> days;

  @override
  final LocalTime time;

  @override
  bool operator ==(Object other) =>
      other is WeeklyTrigger &&
      const SetEquality<Weekday>().equals(other.days, days) &&
      other.time == time;

  @override
  int get hashCode =>
      Object.hash(const SetEquality<Weekday>().hash(days), time);

  @override
  String toString() {
    final names = days.sortedBy<num>((d) => d.iso).map((d) => d.name);
    return 'WeeklyTrigger($time on ${names.join(', ')})';
  }
}

/// Fires at [time] on each of an explicit list of [dates].
///
/// Use this for irregular schedules that no recurrence rule describes cleanly —
/// a course that meets on twelve scattered dates, a medication taper, a set of
/// deadlines.
@immutable
final class DateListTrigger extends TimeTrigger {
  /// Creates a trigger over an explicit set of dates.
  ///
  /// [dates] must not be empty.
  DateListTrigger({required Set<CalendarDate> dates, required this.time})
      : assert(dates.isNotEmpty, 'dates must not be empty'),
        dates = Set.unmodifiable(dates);

  /// The calendar dates on which this trigger fires.
  final Set<CalendarDate> dates;

  @override
  final LocalTime time;

  @override
  bool operator ==(Object other) =>
      other is DateListTrigger &&
      const SetEquality<CalendarDate>().equals(other.dates, dates) &&
      other.time == time;

  @override
  int get hashCode =>
      Object.hash(const SetEquality<CalendarDate>().hash(dates), time);

  @override
  String toString() => 'DateListTrigger($time on ${dates.length} dates)';
}

/// Fires when the device crosses the boundary of [region].
///
/// Unlike a [TimeTrigger] this cannot be enumerated in advance. The reconciler
/// hands the region to the platform and the platform reports the crossing, so
/// the only thing the core can do ahead of time is decide *which* regions are
/// worth registering when the device has more of them than the platform allows.
@immutable
final class LocationTrigger extends Trigger {
  /// Creates a location trigger.
  ///
  /// [dwellTime] is only meaningful when [event] is [GeoEvent.dwell].
  const LocationTrigger({
    required this.region,
    required this.event,
    this.dwellTime,
  }) : assert(
          event == GeoEvent.dwell || dwellTime == null,
          'dwellTime only applies to GeoEvent.dwell',
        );

  /// The area being watched.
  final GeoRegion region;

  /// The boundary crossing that fires the trigger.
  final GeoEvent event;

  /// How long the device must remain inside [region] before a
  /// [GeoEvent.dwell] fires.
  final Duration? dwellTime;

  @override
  bool operator ==(Object other) =>
      other is LocationTrigger &&
      other.region == region &&
      other.event == event &&
      other.dwellTime == dwellTime;

  @override
  int get hashCode => Object.hash(region, event, dwellTime);

  @override
  String toString() => 'LocationTrigger(${event.name} ${region.id})';
}
