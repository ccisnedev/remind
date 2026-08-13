import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';

void main() {
  group('CalendarDate', () {
    test('normalises out-of-range components the way DateTime does', () {
      expect(CalendarDate(2026, 13, 1).toString(), '2027-01-01');
      expect(CalendarDate(2026, 3, 0).toString(), '2026-02-28');
      expect(CalendarDate(2024, 2, 30).toString(), '2024-03-01');
    });

    test('knows its weekday', () {
      expect(CalendarDate(2026, 9, 7).weekday, Weekday.monday);
      expect(CalendarDate(2026, 9, 5).weekday, Weekday.saturday);
    });

    test('addDays crosses month, year and leap-day boundaries', () {
      expect(CalendarDate(2026, 1, 31).addDays(1).toString(), '2026-02-01');
      expect(CalendarDate(2026, 12, 31).addDays(1).toString(), '2027-01-01');
      expect(CalendarDate(2024, 2, 28).addDays(1).toString(), '2024-02-29');
      expect(CalendarDate(2026, 3, 1).addDays(-1).toString(), '2026-02-28');
    });

    test('daysUntil counts whole days in both directions', () {
      expect(
        CalendarDate(2026, 5, 1).daysUntil(CalendarDate(2026, 5, 11)),
        10,
      );
      expect(
        CalendarDate(2026, 5, 11).daysUntil(CalendarDate(2026, 5, 1)),
        -10,
      );
    });

    test('day arithmetic is immune to the host time zone', () {
      // Computed in UTC on purpose: a host in a zone that shifts its clocks at
      // midnight would otherwise be able to knock this off by a day.
      var date = CalendarDate(2026, 9, 1);
      for (var i = 0; i < 400; i++) {
        date = date.addDays(1);
      }
      expect(date.toString(), '2027-10-06');
    });

    test('orders and compares by calendar position', () {
      expect(CalendarDate(2026, 1, 1) < CalendarDate(2026, 1, 2), isTrue);
      expect(CalendarDate(2026, 2, 1) > CalendarDate(2026, 1, 31), isTrue);
      expect(CalendarDate(2026, 1, 1) <= CalendarDate(2026, 1, 1), isTrue);
      expect(CalendarDate(2026, 1, 1), CalendarDate(2026, 1, 1));
    });
  });

  group('LocalTime', () {
    test('formats without seconds unless they matter', () {
      expect(const LocalTime(7, 5).toString(), '07:05');
      expect(const LocalTime(7, 5, 30).toString(), '07:05:30');
      expect(const LocalTime(0, 0).toString(), '00:00');
    });

    test('orders through the day', () {
      expect(const LocalTime(7, 0) < const LocalTime(7, 1), isTrue);
      expect(const LocalTime(23, 59) > const LocalTime(0, 0), isTrue);
      expect(const LocalTime(12, 0), LocalTime.noon);
    });

    test('rejects impossible values', () {
      expect(() => LocalTime(24, 0), throwsA(isA<AssertionError>()));
      expect(() => LocalTime(0, 60), throwsA(isA<AssertionError>()));
    });
  });

  group('Weekday', () {
    test('matches the ISO numbering used by DateTime', () {
      expect(Weekday.monday.iso, DateTime.monday);
      expect(Weekday.sunday.iso, DateTime.sunday);
      expect(Weekday.of(DateTime(2026, 9, 7)), Weekday.monday);
    });

    test('rejects out-of-range ISO numbers', () {
      expect(() => Weekday.fromIso(0), throwsArgumentError);
      expect(() => Weekday.fromIso(8), throwsArgumentError);
    });

    test('offers the sets people actually pick', () {
      expect(Weekday.all, hasLength(7));
      expect(Weekday.workdays, hasLength(5));
      expect(Weekday.weekend, {Weekday.saturday, Weekday.sunday});
    });
  });

  group('GeoRegion', () {
    const santiagoCentre = GeoCoordinate(-33.4489, -70.6693);

    test('haversine distance is right to within a metre or so', () {
      // Santiago to Buenos Aires is about 1,137 km.
      const buenosAires = GeoCoordinate(-34.6037, -58.3816);
      final metres = santiagoCentre.distanceTo(buenosAires);

      expect(metres, closeTo(1137000, 5000));
    });

    test('distance to itself is zero', () {
      expect(santiagoCentre.distanceTo(santiagoCentre), 0);
    });

    test('containment respects the radius', () {
      const region = GeoRegion(
        id: 'centre',
        center: santiagoCentre,
        radiusMetres: 500,
      );

      expect(region.contains(santiagoCentre), isTrue);
      // Roughly 300 m north.
      expect(region.contains(const GeoCoordinate(-33.4462, -70.6693)), isTrue);
      // Roughly 3 km north.
      expect(region.contains(const GeoCoordinate(-33.4219, -70.6693)), isFalse);
    });

    test('rejects a non-positive radius', () {
      expect(
        () => GeoRegion(id: 'x', center: santiagoCentre, radiusMetres: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Reminder', () {
    test('rejects having no triggers at all', () {
      expect(
        () => Reminder(id: 'x', title: 'x', triggers: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('separates enumerable triggers from reactive ones', () {
      final reminder = Reminder(
        id: 'x',
        title: 'x',
        triggers: [
          const DailyTrigger(time: LocalTime(7, 0)),
          const LocationTrigger(
            region: GeoRegion(
              id: 'r',
              center: GeoCoordinate(0, 0),
              radiusMetres: 100,
            ),
            event: GeoEvent.enter,
          ),
        ],
      );

      expect(reminder.timeTriggers, hasLength(1));
      expect(reminder.locationTriggers, hasLength(1));
    });

    test('copyWith replaces only what it is given', () {
      final original = Reminder(
        id: 'x',
        title: 'Original',
        body: 'Body',
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );
      final updated = original.copyWith(title: 'Updated');

      expect(updated.title, 'Updated');
      expect(updated.body, 'Body');
      expect(updated.id, 'x');
      expect(updated.triggers, original.triggers);
    });

    test('its collections cannot be mutated after construction', () {
      final triggers = <Trigger>[const DailyTrigger(time: LocalTime(7, 0))];
      final reminder = Reminder(id: 'x', title: 'x', triggers: triggers);

      triggers.add(const DailyTrigger(time: LocalTime(8, 0)));

      expect(reminder.triggers, hasLength(1));
      expect(
        () => reminder.triggers.add(const DailyTrigger(time: LocalTime(9, 0))),
        throwsUnsupportedError,
      );
    });

    test('equality is structural', () {
      Reminder build() => Reminder(
            id: 'x',
            title: 'x',
            triggers: [
              WeeklyTrigger(
                days: {Weekday.monday, Weekday.friday},
                time: const LocalTime(7, 0),
              ),
            ],
            payload: const {'kind': 'gym'},
          );

      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });

  group('triggers', () {
    test('a weekly trigger with no days is rejected', () {
      expect(
        () => WeeklyTrigger(days: const {}, time: const LocalTime(7, 0)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('a repeating daily trigger demands an anchor', () {
      expect(
        () => DailyTrigger(time: const LocalTime(7, 0), intervalDays: 2),
        throwsA(isA<AssertionError>()),
      );
    });

    test('dwell time only applies to dwell events', () {
      expect(
        () => LocationTrigger(
          region: const GeoRegion(
            id: 'r',
            center: GeoCoordinate(0, 0),
            radiusMetres: 100,
          ),
          event: GeoEvent.enter,
          dwellTime: const Duration(minutes: 5),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('weekly triggers compare by day set regardless of insertion order',
        () {
      final a = WeeklyTrigger(
        days: {Weekday.friday, Weekday.monday},
        time: const LocalTime(7, 0),
      );
      final b = WeeklyTrigger(
        days: {Weekday.monday, Weekday.friday},
        time: const LocalTime(7, 0),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
