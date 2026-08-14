import 'dart:convert';

import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';

void main() {
  const office = GeoRegion(
    id: 'office',
    center: GeoCoordinate(-33.4489, -70.6693),
    radiusMetres: 150,
  );

  /// Round-trips through an actual JSON string, not just a map, so that
  /// anything unencodable is caught here rather than in somebody's database.
  Reminder roundTrip(Reminder reminder) {
    final text = jsonEncode(reminder.toJson());
    final decoded = jsonDecode(text) as Map<String, Object?>;
    return ReminderCodec.decode(decoded);
  }

  Reminder wrapping(Trigger trigger, {Condition? condition}) => Reminder(
        id: 'r1',
        title: 'Title',
        body: 'Body',
        triggers: [trigger],
        condition: condition,
        payload: const {'route': '/gym', 'count': 3, 'flag': true},
      );

  group('triggers survive a round trip', () {
    test('one-shot', () {
      final trigger = OneShotTrigger(
        date: CalendarDate(2026, 3, 8),
        time: const LocalTime(2, 30),
      );

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('daily', () {
      const trigger = DailyTrigger(time: LocalTime(7, 0));

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('daily with an interval and an anchor', () {
      final trigger = DailyTrigger(
        time: const LocalTime(8, 0),
        intervalDays: 3,
        anchor: CalendarDate(2026, 5, 1),
      );

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('weekly', () {
      final trigger = WeeklyTrigger(
        days: {Weekday.monday, Weekday.wednesday, Weekday.friday},
        time: const LocalTime(7, 15),
      );

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('a list of dates', () {
      final trigger = DateListTrigger(
        dates: {
          CalendarDate(2026, 9, 3),
          CalendarDate(2026, 10, 1),
        },
        time: const LocalTime(18, 30),
      );

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('location', () {
      const trigger = LocationTrigger(
        region: office,
        event: GeoEvent.dwell,
        dwellTime: Duration(minutes: 5),
      );

      expect(roundTrip(wrapping(trigger)).triggers.single, trigger);
    });

    test('several at once, in order', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Title',
        triggers: [
          const DailyTrigger(time: LocalTime(7, 0)),
          const LocationTrigger(region: office, event: GeoEvent.enter),
          WeeklyTrigger(days: Weekday.weekend, time: const LocalTime(10, 0)),
        ],
      );

      expect(roundTrip(reminder).triggers, reminder.triggers);
    });
  });

  /// A reminder whose only interesting part is its condition.
  Reminder gatedBy(Condition condition) => wrapping(
        const DailyTrigger(time: LocalTime(7, 0)),
        condition: condition,
      );

  group('conditions survive a round trip', () {
    test('date range, including an open end', () {
      final bounded = DateRangeCondition(
        from: CalendarDate(2026, 1, 1),
        until: CalendarDate(2026, 12, 31),
      );
      final open = DateRangeCondition(from: CalendarDate(2026, 1, 1));

      expect(roundTrip(gatedBy(bounded)).condition, bounded);
      expect(roundTrip(gatedBy(open)).condition, open);
    });

    test('excluded dates', () {
      final condition = ExcludedDatesCondition({
        CalendarDate(2026, 9, 18),
        CalendarDate(2026, 9, 19),
      });

      expect(roundTrip(gatedBy(condition)).condition, condition);
    });

    test('weekdays', () {
      final condition = WeekdaysCondition(Weekday.workdays);

      expect(roundTrip(gatedBy(condition)).condition, condition);
    });

    test('a time window that wraps midnight', () {
      const condition = TimeRangeCondition(
        from: LocalTime(22, 0),
        until: LocalTime(6, 0),
      );

      final decoded = roundTrip(gatedBy(condition)).condition;

      expect(decoded, condition);
      expect((decoded! as TimeRangeCondition).wrapsMidnight, isTrue);
    });

    test('inside and outside a region', () {
      for (final condition in [
        const InsideRegionCondition(office),
        const OutsideRegionCondition(office),
      ]) {
        expect(roundTrip(gatedBy(condition)).condition, condition);
      }
    });

    test('a nested composition', () {
      final condition = AllOfCondition([
        WeekdaysCondition(Weekday.workdays),
        NotCondition(ExcludedDatesCondition({CalendarDate(2026, 9, 18)})),
        AnyOfCondition([
          const TimeRangeCondition(
            from: LocalTime(9, 0),
            until: LocalTime(12, 0),
          ),
          const InsideRegionCondition(office),
        ]),
      ]);

      expect(roundTrip(gatedBy(condition)).condition, condition);
    });
  });

  group('the reminder itself', () {
    test('keeps every field', () {
      final original = wrapping(const DailyTrigger(time: LocalTime(7, 0)));
      final decoded = roundTrip(original);

      expect(decoded, original);
      expect(decoded.id, 'r1');
      expect(decoded.title, 'Title');
      expect(decoded.body, 'Body');
      expect(decoded.payload, {'route': '/gym', 'count': 3, 'flag': true});
    });

    test('keeps a null body and an empty payload', () {
      final original = Reminder(
        id: 'r1',
        title: 'Title',
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );
      final decoded = roundTrip(original);

      expect(decoded.body, isNull);
      expect(decoded.payload, isEmpty);
      expect(decoded, original);
    });

    test('keeps the disabled flag', () {
      final original = Reminder(
        id: 'r1',
        title: 'Title',
        enabled: false,
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );

      expect(roundTrip(original).enabled, isFalse);
    });

    test('encodes a list of reminders', () {
      final reminders = [
        wrapping(const DailyTrigger(time: LocalTime(7, 0))),
        Reminder(
          id: 'r2',
          title: 'Second',
          triggers: [const DailyTrigger(time: LocalTime(9, 0))],
        ),
      ];

      final text = jsonEncode(ReminderCodec.encodeAll(reminders));
      final decoded = ReminderCodec.decodeAll(
        jsonDecode(text) as List<Object?>,
      );

      expect(decoded, reminders);
    });
  });

  group('the format is versioned', () {
    test('encodes the current version', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson();

      expect(json['v'], ReminderCodec.version);
    });

    test('a payload from the future is refused rather than misread', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson()
        ..['v'] = ReminderCodec.version + 1;

      expect(
        () => ReminderCodec.decode(json),
        throwsA(isA<ReminderCodecException>()),
        reason: 'silently reading a newer format would corrupt data',
      );
    });

    test('a missing version is treated as version 1', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson()
        ..remove('v');

      expect(ReminderCodec.decode(json).id, 'r1');
    });
  });

  group('malformed input', () {
    test('an unknown trigger type is refused', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson();
      (json['triggers']! as List<Object?>)[0] = {'type': 'moon_phase'};

      expect(
        () => ReminderCodec.decode(json),
        throwsA(isA<ReminderCodecException>()),
      );
    });

    test('an unknown condition type is refused', () {
      final json = wrapping(
        const DailyTrigger(time: LocalTime(7, 0)),
        condition: WeekdaysCondition(Weekday.workdays),
      ).toJson();
      json['condition'] = {'type': 'vibes'};

      expect(
        () => ReminderCodec.decode(json),
        throwsA(isA<ReminderCodecException>()),
      );
    });

    test('a missing required field is refused', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson()
        ..remove('id');

      expect(
        () => ReminderCodec.decode(json),
        throwsA(isA<ReminderCodecException>()),
      );
    });

    test('a malformed time is refused', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson();
      ((json['triggers']! as List<Object?>)[0]!
          as Map<String, Object?>)['time'] = 'half past seven';

      expect(
        () => ReminderCodec.decode(json),
        throwsA(isA<ReminderCodecException>()),
      );
    });

    test('the exception says what went wrong', () {
      final json = wrapping(const DailyTrigger(time: LocalTime(7, 0))).toJson();
      (json['triggers']! as List<Object?>)[0] = {'type': 'moon_phase'};

      expect(
        () => ReminderCodec.decode(json),
        throwsA(
          isA<ReminderCodecException>().having(
            (e) => e.toString(),
            'message',
            contains('moon_phase'),
          ),
        ),
      );
    });
  });

  group('the encoded shape is human-readable', () {
    test('dates and times are ISO strings, not epoch numbers', () {
      final json = wrapping(
        OneShotTrigger(
          date: CalendarDate(2026, 3, 8),
          time: const LocalTime(2, 30),
        ),
      ).toJson();
      final trigger =
          (json['triggers']! as List<Object?>).single! as Map<String, Object?>;

      expect(trigger['date'], '2026-03-08');
      expect(trigger['time'], '02:30:00');
    });

    test('weekdays are ISO numbers', () {
      final json = wrapping(
        WeeklyTrigger(
          days: {Weekday.monday, Weekday.sunday},
          time: const LocalTime(7, 0),
        ),
      ).toJson();
      final trigger =
          (json['triggers']! as List<Object?>).single! as Map<String, Object?>;

      expect(trigger['days'], [1, 7]);
    });
  });
}
