import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location santiago;
  late tz.Location newYork;
  const engine = OccurrenceEngine();

  setUp(() {
    santiago = tz.getLocation('America/Santiago');
    newYork = tz.getLocation('America/New_York');
  });

  Reminder reminderWith(List<Trigger> triggers, {Condition? condition}) =>
      Reminder(
        id: 'r1',
        title: 'Test',
        triggers: triggers,
        condition: condition,
      );

  group('WeeklyTrigger', () {
    test('fires only on the selected days, at the requested wall time', () {
      final reminder = reminderWith([
        WeeklyTrigger(
          days: {Weekday.monday, Weekday.wednesday, Weekday.friday},
          time: const LocalTime(7, 0),
        ),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 9, 1),
        limit: 4,
      );

      expect(
        occurrences.map((o) => o.instant.day),
        // Tue 1 Sep is skipped; Wed 2, Fri 4, Mon 7, Wed 9.
        [2, 4, 7, 9],
      );
      expect(
        occurrences.every((o) => o.instant.hour == 7 && o.instant.minute == 0),
        isTrue,
      );
    });

    test('keeps the wall-clock time across a DST transition', () {
      // Chile moves the clocks forward on the night of Sat 5 September 2026.
      // An alarm set for 07:00 must stay at 07:00 on both sides of that, which
      // means the underlying UTC offset has to move instead.
      final reminder = reminderWith([
        WeeklyTrigger(days: Weekday.all, time: const LocalTime(7, 0)),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 9, 4),
        limit: 4,
      );

      expect(
        occurrences.every((o) => o.instant.hour == 7),
        isTrue,
        reason: 'wall-clock time must survive the transition',
      );

      final offsets = occurrences.map((o) => o.instant.timeZoneOffset).toList();
      expect(
        offsets.first,
        isNot(offsets.last),
        reason: 'the UTC offset is what should move, not the wall clock',
      );
    });

    test('does not drift when it would if durations were added', () {
      // The failure this guards against: computing the next occurrence as
      // `previous + Duration(days: 7)`. That adds 168 absolute hours and lands
      // an hour off once a transition intervenes.
      final reminder = reminderWith([
        WeeklyTrigger(days: {Weekday.friday}, time: const LocalTime(7, 0)),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 9, 4),
        limit: 2,
      );

      final naive = occurrences.first.instant.add(const Duration(days: 7));
      expect(occurrences[1].instant.hour, 7);
      expect(
        naive.hour,
        isNot(7),
        reason: 'the naive arithmetic really is wrong here, so the test is '
            'proving something',
      );
    });
  });

  group('daylight saving edge cases', () {
    test('a time erased by a spring-forward gap is shifted and flagged', () {
      // 2026-03-08 02:30 does not exist in New York.
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 3, 8),
          time: const LocalTime(2, 30),
        ),
      ]);

      final occurrence = engine.nextOccurrence(
        reminder,
        zone: newYork,
        from: tz.TZDateTime(newYork, 2026, 3, 1),
      );

      expect(occurrence, isNotNull);
      expect(occurrence!.dstAnomaly, DstAnomaly.gapShifted);
      expect(occurrence.instant.hour, 3);
      expect(occurrence.instant.minute, 30);
    });

    test('DstGapPolicy.skip drops the occurrence instead', () {
      const strict = OccurrenceEngine(gapPolicy: DstGapPolicy.skip);
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 3, 8),
          time: const LocalTime(2, 30),
        ),
      ]);

      expect(
        strict.occurrencesOf(
          reminder,
          zone: newYork,
          from: tz.TZDateTime(newYork, 2026, 3, 1),
        ),
        isEmpty,
      );
    });

    test('a time that happens twice resolves to the first and is flagged', () {
      // 2026-11-01 01:30 occurs twice in New York, once in EDT and once in EST.
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 11, 1),
          time: const LocalTime(1, 30),
        ),
      ]);

      final occurrence = engine.nextOccurrence(
        reminder,
        zone: newYork,
        from: tz.TZDateTime(newYork, 2026, 10, 1),
      )!;

      expect(occurrence.dstAnomaly, DstAnomaly.ambiguousResolvedEarly);
      expect(occurrence.instant.timeZoneOffset, const Duration(hours: -4));
    });

    test('an ordinary time carries no anomaly', () {
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 6, 15),
          time: const LocalTime(9, 0),
        ),
      ]);

      final occurrence = engine.nextOccurrence(
        reminder,
        zone: newYork,
        from: tz.TZDateTime(newYork, 2026, 1, 1),
      )!;

      expect(occurrence.dstAnomaly, isNull);
    });
  });

  group('OneShotTrigger', () {
    test('yields nothing once its moment has passed', () {
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 1, 1),
          time: const LocalTime(9, 0),
        ),
      ]);

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 6, 1),
        ),
        isEmpty,
      );
    });

    test('fires exactly once', () {
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 6, 1),
          time: const LocalTime(9, 0),
        ),
      ]);

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 1, 1),
          limit: 10,
        ),
        hasLength(1),
      );
    });

    test('an occurrence exactly at `from` is included', () {
      final reminder = reminderWith([
        OneShotTrigger(
          date: CalendarDate(2026, 6, 1),
          time: const LocalTime(9, 0),
        ),
      ]);

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 6, 1, 9),
        ),
        hasLength(1),
      );
    });
  });

  group('DateListTrigger', () {
    test('returns future dates in ascending order regardless of set order', () {
      final reminder = reminderWith([
        DateListTrigger(
          dates: {
            CalendarDate(2026, 12, 25),
            CalendarDate(2026, 3, 1),
            CalendarDate(2026, 7, 4),
            CalendarDate(2025, 1, 1),
          },
          time: const LocalTime(8, 0),
        ),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 1, 1),
        limit: 10,
      );

      expect(
        occurrences.map((o) => CalendarDate.fromDateTime(o.instant).toString()),
        ['2026-03-01', '2026-07-04', '2026-12-25'],
      );
    });
  });

  group('DailyTrigger', () {
    test('every day', () {
      final reminder = reminderWith([
        const DailyTrigger(time: LocalTime(6, 30)),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 10),
        limit: 3,
      );

      expect(occurrences.map((o) => o.instant.day), [10, 11, 12]);
    });

    test('every N days keeps its phase no matter when it is queried', () {
      final reminder = reminderWith([
        DailyTrigger(
          time: const LocalTime(6, 30),
          intervalDays: 3,
          anchor: CalendarDate(2026, 5, 1),
        ),
      ]);

      // Anchored on 1 May, so the sequence is 1, 4, 7, 10, 13, 16…
      // Querying from 11 May must resume on 13, not restart on 11.
      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 11),
        limit: 3,
      );

      expect(occurrences.map((o) => o.instant.day), [13, 16, 19]);
    });

    test('every N days starts at the anchor when queried before it', () {
      final reminder = reminderWith([
        DailyTrigger(
          time: const LocalTime(6, 30),
          intervalDays: 2,
          anchor: CalendarDate(2026, 5, 10),
        ),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 1),
        limit: 3,
      );

      expect(occurrences.map((o) => o.instant.day), [10, 12, 14]);
    });
  });

  group('multiple triggers', () {
    test('merge in chronological order', () {
      final reminder = reminderWith([
        WeeklyTrigger(days: {Weekday.monday}, time: const LocalTime(7, 0)),
        WeeklyTrigger(days: {Weekday.friday}, time: const LocalTime(19, 0)),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 9, 1),
        limit: 4,
      );

      expect(
        occurrences.map((o) => '${o.instant.day}@${o.instant.hour}'),
        ['4@19', '7@7', '11@19', '14@7'],
      );
    });

    test('collapse when two triggers land on the same instant', () {
      final reminder = reminderWith([
        WeeklyTrigger(days: {Weekday.monday}, time: const LocalTime(7, 0)),
        DateListTrigger(
          dates: {CalendarDate(2026, 9, 7)},
          time: const LocalTime(7, 0),
        ),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 9, 1),
        limit: 5,
      );

      final onTheSeventh =
          occurrences.where((o) => o.instant.day == 7).toList();
      expect(onTheSeventh, hasLength(1));
    });
  });

  group('conditions', () {
    test('excluded dates prune occurrences during enumeration', () {
      final reminder = reminderWith(
        [WeeklyTrigger(days: Weekday.all, time: const LocalTime(7, 0))],
        condition: ExcludedDatesCondition({
          CalendarDate(2026, 5, 11),
          CalendarDate(2026, 5, 12),
        }),
      );

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 10),
        limit: 3,
      );

      expect(occurrences.map((o) => o.instant.day), [10, 13, 14]);
      expect(occurrences.every((o) => !o.isConditional), isTrue);
    });

    test('a date range bounds the sequence', () {
      final reminder = reminderWith(
        [WeeklyTrigger(days: Weekday.all, time: const LocalTime(7, 0))],
        condition: DateRangeCondition(
          from: CalendarDate(2026, 5, 10),
          until: CalendarDate(2026, 5, 12),
        ),
      );

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 1),
        limit: 10,
      );

      expect(occurrences.map((o) => o.instant.day), [10, 11, 12]);
    });

    test('an ambient condition travels with the occurrence', () {
      const office = GeoRegion(
        id: 'office',
        center: GeoCoordinate(-33.4489, -70.6693),
        radiusMetres: 150,
      );
      final reminder = reminderWith(
        [WeeklyTrigger(days: Weekday.workdays, time: const LocalTime(9, 0))],
        condition: const InsideRegionCondition(office),
      );

      final occurrence = engine.nextOccurrence(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 11),
      )!;

      expect(occurrence.isConditional, isTrue);
      expect(occurrence.pendingCondition, const InsideRegionCondition(office));
    });

    test('a mixed conjunction prunes eagerly and defers the rest', () {
      const office = GeoRegion(
        id: 'office',
        center: GeoCoordinate(-33.4489, -70.6693),
        radiusMetres: 150,
      );
      final reminder = reminderWith(
        [WeeklyTrigger(days: Weekday.all, time: const LocalTime(9, 0))],
        condition: AllOfCondition([
          WeekdaysCondition(Weekday.workdays),
          const InsideRegionCondition(office),
        ]),
      );

      // 2026-05-09 is a Saturday, so the weekday half prunes the weekend even
      // though the location half cannot be decided yet.
      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 9),
        limit: 3,
      );

      expect(occurrences.map((o) => o.instant.day), [11, 12, 13]);
      expect(
        occurrences.every(
          (o) => o.pendingCondition == const InsideRegionCondition(office),
        ),
        isTrue,
      );
    });
  });

  group('bounds and guards', () {
    test('a disabled reminder yields nothing', () {
      final reminder = Reminder(
        id: 'off',
        title: 'Off',
        enabled: false,
        triggers: [
          const DailyTrigger(time: LocalTime(7, 0)),
        ],
      );

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 5, 1),
        ),
        isEmpty,
      );
    });

    test('`until` truncates the sequence', () {
      final reminder = reminderWith([
        const DailyTrigger(time: LocalTime(7, 0)),
      ]);

      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: tz.TZDateTime(santiago, 2026, 5, 1),
        limit: 100,
        until: tz.TZDateTime(santiago, 2026, 5, 4),
      );

      expect(occurrences.map((o) => o.instant.day), [1, 2, 3]);
    });

    test('a non-positive limit yields nothing', () {
      final reminder = reminderWith([
        const DailyTrigger(time: LocalTime(7, 0)),
      ]);

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 5, 1),
          limit: 0,
        ),
        isEmpty,
      );
    });

    test('a location trigger contributes no occurrences', () {
      final reminder = reminderWith([
        const LocationTrigger(
          region: GeoRegion(
            id: 'shop',
            center: GeoCoordinate(-33.4, -70.6),
            radiusMetres: 200,
          ),
          event: GeoEvent.enter,
        ),
      ]);

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 5, 1),
        ),
        isEmpty,
        reason: 'location triggers are reactive and cannot be enumerated',
      );
    });

    test('a `from` in another zone is normalised, not misread', () {
      final reminder = reminderWith([
        const DailyTrigger(time: LocalTime(7, 0)),
      ]);

      final fromNewYork = tz.TZDateTime(newYork, 2026, 5, 10, 20);
      final occurrences = engine.occurrencesOf(
        reminder,
        zone: santiago,
        from: fromNewYork,
        limit: 1,
      );

      // 20:00 in New York is 21:00 in Santiago on the same date, so the next
      // 07:00 in Santiago is the following morning.
      expect(occurrences.single.instant.day, 11);
    });

    test('lookahead is bounded when a rule can never match again', () {
      final reminder = reminderWith(
        [WeeklyTrigger(days: Weekday.all, time: const LocalTime(7, 0))],
        condition: DateRangeCondition(until: CalendarDate(2020, 1, 1)),
      );

      expect(
        engine.occurrencesOf(
          reminder,
          zone: santiago,
          from: tz.TZDateTime(santiago, 2026, 5, 1),
          limit: 5,
        ),
        isEmpty,
      );
    });
  });
}
