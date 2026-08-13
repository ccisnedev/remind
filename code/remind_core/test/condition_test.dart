import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';

void main() {
  const office = GeoRegion(
    id: 'office',
    center: GeoCoordinate(-33.4489, -70.6693),
    radiusMetres: 200,
  );
  const atTheOffice = GeoCoordinate(-33.4489, -70.6693);
  const farAway = GeoCoordinate(-33.0, -70.0);

  EvaluationContext at(
    int year,
    int month,
    int day, [
    int hour = 12,
    int minute = 0,
    GeoCoordinate? where,
  ]) =>
      EvaluationContext(
        localTime: DateTime(year, month, day, hour, minute),
        deviceLocation: where,
      );

  group('TimeRangeCondition', () {
    test('an ordinary window holds inside and fails outside', () {
      const window = TimeRangeCondition(
        from: LocalTime(9, 0),
        until: LocalTime(17, 0),
      );

      expect(window.holdsAt(DateTime(2026, 5, 11, 12)), isTrue);
      expect(window.holdsAt(DateTime(2026, 5, 11, 9)), isTrue);
      expect(window.holdsAt(DateTime(2026, 5, 11, 17)), isTrue);
      expect(window.holdsAt(DateTime(2026, 5, 11, 8, 59)), isFalse);
      expect(window.holdsAt(DateTime(2026, 5, 11, 17, 1)), isFalse);
    });

    test('a window whose end precedes its start wraps around midnight', () {
      const overnight = TimeRangeCondition(
        from: LocalTime(22, 0),
        until: LocalTime(6, 0),
      );

      expect(overnight.wrapsMidnight, isTrue);
      expect(overnight.holdsAt(DateTime(2026, 5, 11, 23)), isTrue);
      expect(overnight.holdsAt(DateTime(2026, 5, 11, 2)), isTrue);
      expect(overnight.holdsAt(DateTime(2026, 5, 11, 12)), isFalse);
    });
  });

  group('DateRangeCondition', () {
    test('bounds are inclusive', () {
      final range = DateRangeCondition(
        from: CalendarDate(2026, 5, 10),
        until: CalendarDate(2026, 5, 12),
      );

      expect(range.holdsAt(DateTime(2026, 5, 9)), isFalse);
      expect(range.holdsAt(DateTime(2026, 5, 10)), isTrue);
      expect(range.holdsAt(DateTime(2026, 5, 12, 23, 59)), isTrue);
      expect(range.holdsAt(DateTime(2026, 5, 13)), isFalse);
    });

    test('an omitted bound is open-ended', () {
      final openEnded = DateRangeCondition(from: CalendarDate(2026, 5, 10));

      expect(openEnded.holdsAt(DateTime(2030, 1, 1)), isTrue);
      expect(openEnded.holdsAt(DateTime(2026, 5, 9)), isFalse);
    });
  });

  group('isPurelyTemporal', () {
    test('recognises nested temporal trees', () {
      final tree = AllOfCondition([
        WeekdaysCondition(Weekday.workdays),
        NotCondition(ExcludedDatesCondition({CalendarDate(2026, 5, 11)})),
        AnyOfCondition([
          const TimeRangeCondition(
            from: LocalTime(9, 0),
            until: LocalTime(12, 0),
          ),
          const TimeRangeCondition(
            from: LocalTime(14, 0),
            until: LocalTime(18, 0),
          ),
        ]),
      ]);

      expect(isPurelyTemporal(tree), isTrue);
    });

    test('a single ambient leaf taints the whole tree', () {
      final tree = AllOfCondition([
        WeekdaysCondition(Weekday.workdays),
        const InsideRegionCondition(office),
      ]);

      expect(isPurelyTemporal(tree), isFalse);
    });
  });

  group('partitionCondition', () {
    test('a null condition partitions into nothing', () {
      final partition = partitionCondition(null);

      expect(partition.eager, isNull);
      expect(partition.deferred, isNull);
      expect(partition.hasDeferred, isFalse);
    });

    test('a conjunction splits into both halves', () {
      final weekdays = WeekdaysCondition(Weekday.workdays);
      final partition = partitionCondition(
        AllOfCondition([weekdays, const InsideRegionCondition(office)]),
      );

      expect(partition.eager, weekdays);
      expect(partition.deferred, const InsideRegionCondition(office));
    });

    test('a conjunction of several temporal parts collapses to one AllOf', () {
      final partition = partitionCondition(
        AllOfCondition([
          WeekdaysCondition(Weekday.workdays),
          DateRangeCondition(from: CalendarDate(2026, 1, 1)),
          const InsideRegionCondition(office),
        ]),
      );

      expect(partition.eager, isA<AllOfCondition>());
      expect((partition.eager! as AllOfCondition).conditions, hasLength(2));
      expect(partition.deferred, const InsideRegionCondition(office));
    });

    test('a mixed disjunction is deferred whole', () {
      // The correctness case: a false temporal half proves nothing here,
      // because the ambient half may still hold. Pruning eagerly would drop
      // occurrences the user asked for.
      final mixed = AnyOfCondition([
        WeekdaysCondition(Weekday.workdays),
        const InsideRegionCondition(office),
      ]);
      final partition = partitionCondition(mixed);

      expect(partition.eager, isNull);
      expect(partition.deferred, mixed);
    });

    test('a negated ambient condition is deferred', () {
      final negated = NotCondition(const InsideRegionCondition(office));
      final partition = partitionCondition(negated);

      expect(partition.eager, isNull);
      expect(partition.deferred, negated);
    });

    test('a nested conjunction flattens through recursion', () {
      final partition = partitionCondition(
        AllOfCondition([
          AllOfCondition([
            WeekdaysCondition(Weekday.workdays),
            const InsideRegionCondition(office),
          ]),
          DateRangeCondition(from: CalendarDate(2026, 1, 1)),
        ]),
      );

      expect(isPurelyTemporal(partition.eager!), isTrue);
      expect(partition.deferred, const InsideRegionCondition(office));
    });
  });

  group('evaluateCondition', () {
    test('a null condition holds', () {
      expect(
        evaluateCondition(null, at(2026, 5, 11)),
        ConditionOutcome.holds,
      );
    });

    test('a region condition is undetermined without a location', () {
      expect(
        evaluateCondition(
          const InsideRegionCondition(office),
          at(2026, 5, 11),
        ),
        ConditionOutcome.undetermined,
        reason: 'unknown location must not silently read as false',
      );
    });

    test('a region condition resolves once a location is known', () {
      expect(
        evaluateCondition(
          const InsideRegionCondition(office),
          at(2026, 5, 11, 12, 0, atTheOffice),
        ),
        ConditionOutcome.holds,
      );
      expect(
        evaluateCondition(
          const InsideRegionCondition(office),
          at(2026, 5, 11, 12, 0, farAway),
        ),
        ConditionOutcome.fails,
      );
      expect(
        evaluateCondition(
          const OutsideRegionCondition(office),
          at(2026, 5, 11, 12, 0, farAway),
        ),
        ConditionOutcome.holds,
      );
    });

    test(
        'a conjunction fails outright when one branch fails, even with an '
        'unknown alongside it', () {
      // Saturday, so the weekday branch fails; location is unknown. The answer
      // is still a definite failure, which is what saves the caller a location
      // lookup it does not need.
      final result = evaluateCondition(
        AllOfCondition([
          WeekdaysCondition(Weekday.workdays),
          const InsideRegionCondition(office),
        ]),
        at(2026, 5, 9),
      );

      expect(result, ConditionOutcome.fails);
    });

    test('a conjunction is undetermined when only unknowns remain', () {
      final result = evaluateCondition(
        AllOfCondition([
          WeekdaysCondition(Weekday.workdays),
          const InsideRegionCondition(office),
        ]),
        at(2026, 5, 11),
      );

      expect(result, ConditionOutcome.undetermined);
    });

    test('a disjunction holds outright when one branch holds', () {
      final result = evaluateCondition(
        AnyOfCondition([
          WeekdaysCondition(Weekday.workdays),
          const InsideRegionCondition(office),
        ]),
        at(2026, 5, 11),
      );

      expect(result, ConditionOutcome.holds);
    });

    test(
        'a disjunction is undetermined when no branch holds but one is '
        'unknown', () {
      final result = evaluateCondition(
        AnyOfCondition([
          WeekdaysCondition(Weekday.weekend),
          const InsideRegionCondition(office),
        ]),
        at(2026, 5, 11),
      );

      expect(result, ConditionOutcome.undetermined);
    });

    test('negation preserves the unknown', () {
      expect(
        evaluateCondition(
          NotCondition(const InsideRegionCondition(office)),
          at(2026, 5, 11),
        ),
        ConditionOutcome.undetermined,
      );
    });

    test('an empty conjunction holds and an empty disjunction does not', () {
      expect(
        evaluateCondition(AllOfCondition(const []), at(2026, 5, 11)),
        ConditionOutcome.holds,
      );
      expect(
        evaluateCondition(AnyOfCondition(const []), at(2026, 5, 11)),
        ConditionOutcome.fails,
      );
    });
  });
}
