import 'package:flutter_test/flutter_test.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late InMemoryReminderStore store;
  late InMemoryCrossingJournal journal;
  late List<Crossing> delivered;
  late CrossingHandler handler;

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

  /// A Monday at 11:00.
  tz.TZDateTime monday() => tz.TZDateTime(zone, 2026, 5, 11, 11);

  /// A Saturday at 11:00.
  tz.TZDateTime saturday() => tz.TZDateTime(zone, 2026, 5, 9, 11);

  CrossingHandler handlerWith({
    CrossingEvaluator evaluator = const CrossingEvaluator(),
    Future<void> Function(Crossing)? deliver,
  }) =>
      CrossingHandler(
        store: store,
        journal: journal,
        evaluator: evaluator,
        deliver: deliver ??
            (crossing) async {
              delivered.add(crossing);
            },
      );

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    store = InMemoryReminderStore();
    journal = InMemoryCrossingJournal();
    delivered = [];
    handler = handlerWith();
  });

  Reminder reminderOf({
    String id = 'groceries',
    Condition? condition,
    GeoRegion region = supermarket,
    GeoEvent event = GeoEvent.enter,
    bool enabled = true,
  }) =>
      Reminder(
        id: id,
        title: 'Buy milk',
        enabled: enabled,
        triggers: [LocationTrigger(region: region, event: event)],
        condition: condition,
      );

  /// The id the platform would report for a reminder's only region trigger.
  String regionIdOf(Reminder reminder) {
    final trigger = reminder.locationTriggers.single;
    return RegistrationKey.forRegion(
      reminderId: reminder.id,
      region: trigger.region,
      event: trigger.event,
    ).value;
  }

  group('a crossing with nothing to check', () {
    test('is delivered and journalled', () async {
      final reminder = reminderOf();
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single, isA<Delivered>());
      expect(delivered, hasLength(1));
      expect(delivered.single.reminder.id, 'groceries');
      expect(await journal.recent(), hasLength(1));
    });
  });

  group('a crossing the condition excludes', () {
    test('is journalled but never delivered', () async {
      // The case the journal exists for. Nothing reaches the user, so without
      // this entry there is no evidence anywhere that they were ever there.
      final reminder = reminderOf(
        condition: WeekdaysCondition(Weekday.workdays),
      );
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: saturday(),
      );

      expect(report.outcomes.single, isA<Suppressed>());
      expect(delivered, isEmpty);

      final recorded = await journal.recent();
      expect(recorded, hasLength(1));
      expect(recorded.single.explanation, isNotEmpty);
    });

    test('a disabled reminder is journalled too', () async {
      final reminder = reminderOf(enabled: false);
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single, isA<Suppressed>());
      expect(await journal.recent(), hasLength(1));
      expect(delivered, isEmpty);
    });
  });

  group('a crossing that cannot be decided', () {
    test('is journalled and stays quiet by default', () async {
      final reminder = reminderOf(
        condition: const InsideRegionCondition(office),
      );
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single, isA<Undetermined>());
      expect(delivered, isEmpty);
      expect(await journal.recent(), hasLength(1));
    });

    test('is delivered when the policy says so', () async {
      final reminder = reminderOf(
        condition: const InsideRegionCondition(office),
      );
      await store.save(reminder);

      final report = await handlerWith(
        evaluator: const CrossingEvaluator(
          whenUndetermined: UndeterminedPolicy.notify,
        ),
      ).handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single, isA<Undetermined>());
      expect(delivered, hasLength(1));
    });
  });

  group('matching regions to reminders', () {
    test('matches by recomputing keys, not by parsing them', () async {
      // Reminder ids are chosen by the host application and can contain
      // anything, colons included. Recomputing each reminder's key and
      // comparing is robust where splitting the string would not be.
      final awkward = reminderOf(id: 'user:42:groceries');
      await store.save(awkward);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(awkward)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single.reminderId, 'user:42:groceries');
    });

    test('an id belonging to no reminder is skipped, not fatal', () async {
      // A geofence left behind by a deleted reminder. The next reconcile
      // removes it; crashing the isolate over it would be worse.
      final report = await handler.handle(
        firedRegionIds: {'remind:r:ghost:nowhere:enter'},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes, isEmpty);
      expect(report.unmatched, hasLength(1));
      expect(delivered, isEmpty);
    });

    test('several regions can fire at once', () async {
      // Android reports a list; more than one boundary can be crossed in the
      // same movement.
      final groceries = reminderOf();
      final work = reminderOf(id: 'work', region: office);
      await store.save(groceries);
      await store.save(work);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(groceries), regionIdOf(work)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes, hasLength(2));
      expect(delivered, hasLength(2));
    });
  });

  group('the crossing carries what the platform gave us', () {
    test('a device location reaches the evaluator', () async {
      final reminder = reminderOf(
        condition: const InsideRegionCondition(office),
      );
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
        deviceLocation: office.center,
      );

      expect(
        report.outcomes.single,
        isA<Delivered>(),
        reason: 'a real fix decides a condition about another region',
      );
    });

    test('no location still decides a condition about the fired region',
        () async {
      final reminder = reminderOf(
        condition: const InsideRegionCondition(supermarket),
      );
      await store.save(reminder);

      final report = await handler.handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.outcomes.single, isA<Delivered>());
    });
  });

  group('delivery failures', () {
    test('are reported without losing the journal entry', () async {
      // An uncaught exception here would kill a background isolate and take
      // every other pending crossing with it.
      final reminder = reminderOf();
      await store.save(reminder);

      final report = await handlerWith(
        deliver: (_) async => throw StateError('no notification channel'),
      ).handle(
        firedRegionIds: {regionIdOf(reminder)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(report.deliveryFailures, hasLength(1));
      expect(report.outcomes.single, isA<Delivered>());
      expect(await journal.recent(), hasLength(1));
    });

    test('one failure does not stop the others', () async {
      final first = reminderOf();
      final second = reminderOf(id: 'work', region: office);
      await store.save(first);
      await store.save(second);

      var calls = 0;
      final report = await handlerWith(
        deliver: (crossing) async {
          calls++;
          if (calls == 1) throw StateError('the first one fails');
        },
      ).handle(
        firedRegionIds: {regionIdOf(first), regionIdOf(second)},
        event: GeoEvent.enter,
        zone: zone,
        at: monday(),
      );

      expect(calls, 2);
      expect(report.deliveryFailures, hasLength(1));
      expect(await journal.recent(), hasLength(2));
    });
  });
}
