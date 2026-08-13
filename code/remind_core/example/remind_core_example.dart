// Run with: dart run example/remind_core_example.dart
import 'package:remind_core/remind_core.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // The core never touches the platform, so the caller decides which zone the
  // reminders live in. In a real app this comes from the device.
  tzdata.initializeTimeZones();
  final zone = tz.getLocation('America/Santiago');
  final now = tz.TZDateTime(zone, 2026, 9, 1, 6);

  const engine = OccurrenceEngine();

  _section('Weekday alarm, holidays excluded');
  final standup = Reminder(
    id: 'standup',
    title: 'Daily standup',
    body: 'Join the call',
    triggers: [
      WeeklyTrigger(days: Weekday.workdays, time: const LocalTime(9, 15)),
    ],
    condition: ExcludedDatesCondition({CalendarDate(2026, 9, 18)}),
    payload: const {'route': '/meetings/standup'},
  );
  _print(engine.occurrencesOf(standup, zone: zone, from: now, limit: 5));

  _section('Specific dates — a course that meets irregularly');
  final course = Reminder(
    id: 'course',
    title: 'Statistics seminar',
    triggers: [
      DateListTrigger(
        dates: {
          CalendarDate(2026, 9, 3),
          CalendarDate(2026, 9, 17),
          CalendarDate(2026, 10, 1),
        },
        time: const LocalTime(18, 30),
      ),
    ],
  );
  _print(engine.occurrencesOf(course, zone: zone, from: now, limit: 5));

  _section('Every third day, anchored so the phase never slips');
  final medication = Reminder(
    id: 'medication',
    title: 'Take the tablet',
    triggers: [
      DailyTrigger(
        time: const LocalTime(8, 0),
        intervalDays: 3,
        anchor: CalendarDate(2026, 9, 1),
      ),
    ],
  );
  _print(engine.occurrencesOf(medication, zone: zone, from: now, limit: 4));

  _section('Time and place together');
  // Neither Android nor iOS can express this as a single primitive. The region
  // goes to the platform; the weekday half is resolved here, and whatever is
  // left rides along on the occurrence to be checked when it fires.
  const supermarket = GeoRegion(
    id: 'supermarket',
    center: GeoCoordinate(-33.4372, -70.6506),
    radiusMetres: 200,
  );
  final groceries = Reminder(
    id: 'groceries',
    title: 'Buy milk',
    triggers: [
      const LocationTrigger(region: supermarket, event: GeoEvent.enter),
      WeeklyTrigger(days: {Weekday.saturday}, time: const LocalTime(11, 0)),
    ],
    condition: AllOfCondition([
      const TimeRangeCondition(from: LocalTime(8, 0), until: LocalTime(22, 0)),
      const InsideRegionCondition(supermarket),
    ]),
  );
  _print(engine.occurrencesOf(groceries, zone: zone, from: now, limit: 2));

  // The location half cannot be answered without a device fix, and the engine
  // says so rather than guessing.
  final atEleven = tz.TZDateTime(zone, 2026, 9, 5, 11);
  for (final (label, location) in [
    ('no location fix ', null),
    ('at the shop     ', supermarket.center),
    ('somewhere else  ', const GeoCoordinate(-33.40, -70.55)),
  ]) {
    final verdict = evaluateCondition(
      groceries.condition,
      EvaluationContext(localTime: atEleven, deviceLocation: location),
    );
    print('  11:00, $label -> ${verdict.name}');
  }

  // Outside the time window the answer is a definite no, even though the
  // location is still unknown — one failing branch settles a conjunction.
  final tooEarly = evaluateCondition(
    groceries.condition,
    EvaluationContext(localTime: tz.TZDateTime(zone, 2026, 9, 5, 6)),
  );
  print('  06:00, no location fix  -> ${tooEarly.name}');

  _section('Daylight saving');
  // Chile moves its clocks on the night of Saturday 5 September 2026.
  final alarm = Reminder(
    id: 'alarm',
    title: 'Wake up',
    triggers: [
      WeeklyTrigger(days: Weekday.all, time: const LocalTime(7, 0)),
    ],
  );
  for (final occurrence in engine.occurrencesOf(
    alarm,
    zone: zone,
    from: tz.TZDateTime(zone, 2026, 9, 4),
    limit: 3,
  )) {
    print('  ${occurrence.instant}  (UTC offset '
        '${occurrence.instant.timeZoneOffset.inHours}h)');
  }
  print('  the wall clock stays at 07:00; the offset is what moves.');

  // A time the clocks jumped over is reported, not silently moved.
  final erased = Reminder(
    id: 'erased',
    title: 'Impossible time',
    triggers: [
      OneShotTrigger(
        date: CalendarDate(2026, 3, 8),
        time: const LocalTime(2, 30),
      ),
    ],
  );
  final shifted = engine.nextOccurrence(
    erased,
    zone: tz.getLocation('America/New_York'),
    from: tz.TZDateTime(tz.getLocation('America/New_York'), 2026, 3, 1),
  )!;
  print('  02:30 on 2026-03-08 in New York never happens; resolved to '
      '${shifted.instant.hour}:${shifted.instant.minute} '
      '(${shifted.dstAnomaly!.name})');
}

void _section(String title) => print('\n$title\n${'-' * title.length}');

void _print(List<Occurrence> occurrences) {
  for (final occurrence in occurrences) {
    final flag = occurrence.isConditional ? '  [conditional]' : '';
    print('  ${occurrence.instant}$flag');
  }
}
