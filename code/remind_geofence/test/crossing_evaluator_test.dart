import 'package:flutter_test/flutter_test.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  const evaluator = CrossingEvaluator();

  const supermarket = GeoRegion(
    id: 'supermarket',
    center: GeoCoordinate(-33.4372, -70.6506),
    radiusMetres: 200,
  );
  const office = GeoRegion(
    id: 'office',
    center: GeoCoordinate(-33.4489, -70.6693),
    radiusMetres: 150,
  );

  setUp(() => zone = tz.getLocation('America/Santiago'));

  Reminder reminderOf({Condition? condition}) => Reminder(
        id: 'groceries',
        title: 'Buy milk',
        triggers: [
          const LocationTrigger(region: supermarket, event: GeoEvent.enter),
        ],
        condition: condition,
      );

  /// A Monday at 11:00.
  tz.TZDateTime monday() => tz.TZDateTime(zone, 2026, 5, 11, 11);

  /// A Saturday at 11:00.
  tz.TZDateTime saturday() => tz.TZDateTime(zone, 2026, 5, 9, 11);

  Crossing crossingAt(
    tz.TZDateTime when, {
    Condition? condition,
    GeoCoordinate? deviceLocation,
    GeoRegion region = supermarket,
  }) =>
      Crossing(
        reminder: reminderOf(condition: condition),
        region: region,
        event: GeoEvent.enter,
        at: when,
        deviceLocation: deviceLocation,
        pendingCondition: condition,
      );

  group('delivering', () {
    test('an unconditional crossing is delivered', () {
      final outcome = evaluator.evaluate(crossingAt(monday()));

      expect(outcome, isA<Delivered>());
      expect(outcome.shouldNotify, isTrue);
    });

    test('a satisfied condition is delivered', () {
      final outcome = evaluator.evaluate(
        crossingAt(monday(), condition: WeekdaysCondition(Weekday.workdays)),
      );

      expect(outcome, isA<Delivered>());
    });
  });

  group('suppressing, legibly', () {
    test('a failed condition suppresses and says which one', () {
      // Saturday, so the weekday gate excludes it. The user who wonders why
      // nothing happened when they walked into the shop deserves this answer.
      final condition = WeekdaysCondition(Weekday.workdays);
      final outcome = evaluator.evaluate(
        crossingAt(saturday(), condition: condition),
      );

      expect(outcome, isA<Suppressed>());
      expect(outcome.shouldNotify, isFalse);
      expect((outcome as Suppressed).condition, condition);
    });

    test('the outcome explains itself in words', () {
      final outcome = evaluator.evaluate(
        crossingAt(
          saturday(),
          condition: WeekdaysCondition(Weekday.workdays),
        ),
      );

      expect(outcome.explanation, isNotEmpty);
      expect(outcome.explanation.toLowerCase(), contains('condition'));
    });

    test('every outcome carries when and what it was about', () {
      final at = saturday();
      final outcome = evaluator.evaluate(
        crossingAt(at, condition: WeekdaysCondition(Weekday.workdays)),
      );

      expect(outcome.at, at);
      expect(outcome.reminderId, 'groceries');
      expect(outcome.region, supermarket);
      expect(outcome.event, GeoEvent.enter);
    });
  });

  group('the crossing is its own evidence', () {
    test('being inside the region that fired is known without a fix', () {
      // iOS never reports the device location with a crossing, and Android
      // sometimes omits it. But a geofence firing on entry *is* the evidence
      // that the device is inside that region, so the condition is decidable
      // even with no location at all.
      final outcome = evaluator.evaluate(
        crossingAt(
          monday(),
          condition: const InsideRegionCondition(supermarket),
        ),
      );

      expect(
        outcome,
        isA<Delivered>(),
        reason: 'entering the region proves the device is in it',
      );
    });

    test('an exit proves the device is outside the region that fired', () {
      final outcome = evaluator.evaluate(
        Crossing(
          reminder: reminderOf(
            condition: const OutsideRegionCondition(supermarket),
          ),
          region: supermarket,
          event: GeoEvent.exit,
          at: monday(),
          pendingCondition: const OutsideRegionCondition(supermarket),
        ),
      );

      expect(outcome, isA<Delivered>());
    });

    test('a condition about a different region stays undecidable', () {
      // Walking into the supermarket says nothing about whether you are also
      // inside the office. Guessing here would be inventing evidence.
      final outcome = evaluator.evaluate(
        crossingAt(monday(), condition: const InsideRegionCondition(office)),
      );

      expect(outcome, isA<Undetermined>());
    });

    test('a real device fix decides a condition about another region', () {
      final outcome = evaluator.evaluate(
        crossingAt(
          monday(),
          condition: const InsideRegionCondition(office),
          deviceLocation: office.center,
        ),
      );

      expect(outcome, isA<Delivered>());
    });
  });

  group('undetermined is not silence', () {
    test('an undecidable condition is reported, not swallowed', () {
      final condition = const InsideRegionCondition(office);
      final outcome = evaluator.evaluate(
        crossingAt(monday(), condition: condition),
      );

      expect(outcome, isA<Undetermined>());
      expect((outcome as Undetermined).condition, condition);
      expect(outcome.explanation, isNotEmpty);
    });

    test('the default is to stay quiet when it cannot be decided', () {
      // Deliberate and arguable. Firing on an undecidable condition would
      // reach a user who explicitly asked to be reminded only somewhere else.
      final outcome = evaluator.evaluate(
        crossingAt(monday(), condition: const InsideRegionCondition(office)),
      );

      expect(outcome.shouldNotify, isFalse);
    });

    test('the policy can be inverted for reminders better late than never', () {
      const noisy = CrossingEvaluator(
        whenUndetermined: UndeterminedPolicy.notify,
      );

      final outcome = noisy.evaluate(
        crossingAt(monday(), condition: const InsideRegionCondition(office)),
      );

      expect(outcome, isA<Undetermined>());
      expect(outcome.shouldNotify, isTrue);
    });
  });

  group('mixed conditions', () {
    test('a conjunction fails outright on its temporal half', () {
      // The differentiator, and the case that has to be explainable: Saturday
      // plus a location gate. It fails on the weekday half without ever
      // needing to know where the device is.
      final condition = AllOfCondition([
        WeekdaysCondition(Weekday.workdays),
        const InsideRegionCondition(office),
      ]);

      final outcome = evaluator.evaluate(
        crossingAt(saturday(), condition: condition),
      );

      expect(outcome, isA<Suppressed>());
    });

    test('a conjunction whose location half is unknown is undetermined', () {
      final outcome = evaluator.evaluate(
        crossingAt(
          monday(),
          condition: AllOfCondition([
            WeekdaysCondition(Weekday.workdays),
            const InsideRegionCondition(office),
          ]),
        ),
      );

      expect(outcome, isA<Undetermined>());
    });

    test('a conjunction gated on the region that fired resolves fully', () {
      final outcome = evaluator.evaluate(
        crossingAt(
          monday(),
          condition: AllOfCondition([
            WeekdaysCondition(Weekday.workdays),
            const InsideRegionCondition(supermarket),
            const TimeRangeCondition(
              from: LocalTime(8, 0),
              until: LocalTime(22, 0),
            ),
          ]),
        ),
      );

      expect(outcome, isA<Delivered>());
    });
  });

  group('a disabled reminder', () {
    test('never fires, and says so', () {
      final outcome = evaluator.evaluate(
        Crossing(
          reminder: reminderOf().copyWith(enabled: false),
          region: supermarket,
          event: GeoEvent.enter,
          at: monday(),
        ),
      );

      expect(outcome, isA<Suppressed>());
      expect(outcome.shouldNotify, isFalse);
      expect(outcome.explanation.toLowerCase(), contains('disabled'));
    });
  });
}
