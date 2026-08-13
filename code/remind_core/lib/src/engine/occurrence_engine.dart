import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/calendar_date.dart';
import '../model/local_time.dart';
import '../model/occurrence.dart';
import '../model/reminder.dart';
import '../model/trigger.dart';
import 'condition_evaluator.dart';

/// What to do when a reminder's wall-clock time falls inside a daylight-saving
/// gap — a time that simply does not exist on that date, because the clocks
/// jumped over it.
enum DstGapPolicy {
  /// Fire anyway, at the instant the requested time maps to once the
  /// transition is applied. A 02:30 alarm on a spring-forward night rings at
  /// 03:30.
  ///
  /// The default, because a missed alarm is a worse failure than a late one,
  /// and because it matches what platform alarm clocks do.
  shiftForward,

  /// Skip the occurrence entirely on that date.
  ///
  /// Appropriate when firing late would be actively wrong — a medication
  /// interval, a market open.
  skip,
}

/// Resolves the rules on a [Reminder] into concrete instants.
///
/// This is the part of the library that has to be right, and the reason it is
/// pure Dart: none of it needs a device, so all of it can be tested in
/// milliseconds against any zone and any date in history.
///
/// Occurrences are always rebuilt from calendar fields — year, month, day plus
/// a wall-clock time — never by adding a [Duration] to the previous one.
/// Adding `Duration(days: 1)` adds exactly 24 hours of absolute time, so an
/// alarm crossing a daylight-saving boundary would drift by an hour and stay
/// drifted. Rebuilding from the calendar keeps 07:00 at 07:00 and lets the UTC
/// offset move instead, which is what the user meant.
@immutable
final class OccurrenceEngine {
  /// Creates an engine.
  const OccurrenceEngine({
    this.gapPolicy = DstGapPolicy.shiftForward,
    this.maxLookaheadDays = 732,
  }) : assert(maxLookaheadDays > 0, 'maxLookaheadDays must be positive');

  /// How to resolve wall-clock times that a DST transition erased.
  final DstGapPolicy gapPolicy;

  /// How far ahead the day-walking generators will search before giving up.
  ///
  /// Bounds the cost of a rule that turns out to match nothing — for example a
  /// weekly reminder whose date-range condition has already expired. Two years
  /// by default, which comfortably covers any repeating rule that still has a
  /// future, while keeping a pathological case from spinning.
  final int maxLookaheadDays;

  /// The next [limit] occurrences of [reminder] at or after [from].
  ///
  /// [zone] is the time zone the reminder's wall-clock times are interpreted
  /// in; it is supplied per call rather than stored, because a reminder that
  /// says "07:00" means 07:00 wherever the user currently is, and that can
  /// change while the reminder lives.
  ///
  /// Results are sorted ascending, de-duplicated across triggers, and never
  /// extend past [until] when it is given. A disabled reminder yields nothing.
  ///
  /// Occurrences ruled out by the time-only part of the reminder's condition
  /// are dropped here. Whatever remains of that condition travels on the
  /// returned [Occurrence.pendingCondition] to be evaluated when it fires.
  ///
  /// The caller is responsible for having initialised the time zone database
  /// (`initializeTimeZones()` from `package:timezone/data/latest.dart`) before
  /// obtaining [zone].
  List<Occurrence> occurrencesOf(
    Reminder reminder, {
    required tz.Location zone,
    required tz.TZDateTime from,
    int limit = 16,
    tz.TZDateTime? until,
  }) {
    if (limit <= 0) return const [];
    if (!reminder.enabled) return const [];

    // `from` may arrive in a different zone than the one we are resolving in.
    final start = tz.TZDateTime.from(from, zone);
    final partition = partitionCondition(reminder.condition);

    final collected = <Occurrence>[];
    for (final trigger in reminder.timeTriggers) {
      // Taking `limit` from every trigger is enough: the first `limit` of the
      // merged sequence cannot contain more than `limit` from any one of them.
      collected.addAll(
        _occurrencesOfTrigger(
          reminder: reminder,
          trigger: trigger,
          zone: zone,
          from: start,
          until: until,
          limit: limit,
          partition: partition,
        ),
      );
    }

    collected.sort((a, b) => a.instant.compareTo(b.instant));

    final seen = <DateTime>{};
    final merged = <Occurrence>[];
    for (final occurrence in collected) {
      if (!seen.add(occurrence.instant)) continue;
      merged.add(occurrence);
      if (merged.length == limit) break;
    }
    return List.unmodifiable(merged);
  }

  /// The single next occurrence of [reminder] at or after [from], if any.
  Occurrence? nextOccurrence(
    Reminder reminder, {
    required tz.Location zone,
    required tz.TZDateTime from,
    tz.TZDateTime? until,
  }) =>
      occurrencesOf(
        reminder,
        zone: zone,
        from: from,
        limit: 1,
        until: until,
      ).firstOrNull;

  Iterable<Occurrence> _occurrencesOfTrigger({
    required Reminder reminder,
    required TimeTrigger trigger,
    required tz.Location zone,
    required tz.TZDateTime from,
    required tz.TZDateTime? until,
    required int limit,
    required ConditionPartition partition,
  }) sync* {
    final startDate = CalendarDate.fromDateTime(from);
    var produced = 0;

    for (final date in _candidateDates(trigger, startDate)) {
      if (produced == limit) return;

      final resolved = _resolve(zone, date, trigger.time);
      if (resolved == null) continue; // Erased by the gap policy.

      final instant = resolved.instant;
      if (instant.isBefore(from)) continue;
      if (until != null && instant.isAfter(until)) return;

      if (partition.eager != null) {
        final outcome = evaluateCondition(
          partition.eager,
          EvaluationContext(localTime: instant),
        );
        // A purely temporal condition can never be undetermined, so anything
        // other than `holds` means this date is genuinely excluded.
        if (!outcome.isHolding) continue;
      }

      yield Occurrence(
        reminderId: reminder.id,
        instant: instant,
        trigger: trigger,
        pendingCondition: partition.deferred,
        dstAnomaly: resolved.anomaly,
      );
      produced++;
    }
  }

  /// The dates a trigger could fire on, in ascending order, starting no earlier
  /// than [start].
  ///
  /// Sparse triggers jump straight to their dates; repeating ones walk the
  /// calendar a day at a time, bounded by [maxLookaheadDays].
  Iterable<CalendarDate> _candidateDates(
    TimeTrigger trigger,
    CalendarDate start,
  ) sync* {
    switch (trigger) {
      case OneShotTrigger(:final date):
        if (date >= start) yield date;

      case DateListTrigger(:final dates):
        yield* dates.where((d) => d >= start).sorted();

      case WeeklyTrigger(:final days):
        for (var offset = 0; offset < maxLookaheadDays; offset++) {
          final date = start.addDays(offset);
          if (days.contains(date.weekday)) yield date;
        }

      case DailyTrigger(:final intervalDays, :final anchor):
        if (intervalDays == 1) {
          for (var offset = 0; offset < maxLookaheadDays; offset++) {
            yield start.addDays(offset);
          }
          return;
        }
        // Every N days counted from the anchor, so the phase of the sequence is
        // preserved no matter when it is queried.
        final anchorDate = anchor!;
        final elapsed = anchorDate.daysUntil(start);
        final gapToPhase =
            (intervalDays - elapsed % intervalDays) % intervalDays;
        final first = elapsed <= 0 ? anchorDate : start.addDays(gapToPhase);
        for (var offset = 0;
            offset < maxLookaheadDays;
            offset += intervalDays) {
          yield first.addDays(offset);
        }
    }
  }

  /// Turns a calendar date plus a wall-clock time into an absolute instant,
  /// reporting what daylight saving did to it.
  ///
  /// Returns `null` when the time does not exist and [gapPolicy] says to skip.
  ({tz.TZDateTime instant, DstAnomaly? anomaly})? _resolve(
    tz.Location zone,
    CalendarDate date,
    LocalTime time,
  ) {
    final built = tz.TZDateTime(
      zone,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      time.second,
    );

    // If the wall clock we asked for is not the wall clock we got back, the
    // requested time never happened on that date.
    final survivedIntact = built.year == date.year &&
        built.month == date.month &&
        built.day == date.day &&
        built.hour == time.hour &&
        built.minute == time.minute &&
        built.second == time.second;

    if (!survivedIntact) {
      if (gapPolicy == DstGapPolicy.skip) return null;
      return (instant: built, anomaly: DstAnomaly.gapShifted);
    }

    if (_isAmbiguous(zone, built)) {
      return (instant: built, anomaly: DstAnomaly.ambiguousResolvedEarly);
    }
    return (instant: built, anomaly: null);
  }

  /// Whether [built] names a wall-clock time that occurs twice on its date.
  ///
  /// Probes the offsets a transition might use: one hour is near-universal, two
  /// covers zones such as `America/Havana` historically and Antarctic stations,
  /// and thirty minutes covers Lord Howe Island. If shifting the instant
  /// forward by any of those lands on the same wall clock, the clock read that
  /// time twice.
  bool _isAmbiguous(tz.Location zone, tz.TZDateTime built) {
    const probes = [
      Duration(minutes: 30),
      Duration(hours: 1),
      Duration(hours: 2),
    ];
    final asUtc = built.toUtc();
    for (final probe in probes) {
      final later = tz.TZDateTime.from(asUtc.add(probe), zone);
      if (later.day == built.day &&
          later.hour == built.hour &&
          later.minute == built.minute &&
          later.second == built.second) {
        return true;
      }
    }
    return false;
  }
}
