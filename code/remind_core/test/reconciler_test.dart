import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late tz.TZDateTime now;
  const reconciler = Reconciler();

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    // A Monday.
    now = tz.TZDateTime(zone, 2026, 5, 11, 6);
  });

  Reminder daily(String id, LocalTime time) => Reminder(
        id: id,
        title: id,
        triggers: [DailyTrigger(time: time)],
      );

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

  group('planning from nothing', () {
    test('registers the upcoming window and cancels nothing', () {
      final plan = reconciler.plan(
        reminders: [daily('wake', const LocalTime(7, 0))],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 3),
      );

      expect(plan.toRegister, hasLength(3));
      expect(plan.toCancel, isEmpty);
      expect(plan.retained, isEmpty);
      expect(plan.isEmpty, isFalse);
    });

    test('never schedules more timed registrations than the budget allows', () {
      final reminders = [
        for (var i = 0; i < 40; i++) daily('r$i', const LocalTime(7, 0)),
      ];

      final plan = reconciler.plan(
        reminders: reminders,
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 64),
      );

      // 40 weekly reminders would be hundreds of occurrences; iOS keeps 64.
      expect(plan.toRegister, hasLength(64));
    });

    test('gives every reminder a slot before giving any a second one', () {
      // The fairness property. Taking the globally soonest N would hand all 4
      // slots to the 06:30 reminder and leave the others silent.
      final reminders = [
        daily('early', const LocalTime(6, 30)),
        daily('noon', const LocalTime(12, 0)),
        daily('evening', const LocalTime(20, 0)),
      ];

      final plan = reconciler.plan(
        reminders: reminders,
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 4),
      );

      final byReminder = <String, int>{};
      for (final registration in plan.toRegister) {
        byReminder.update(
          registration.reminderId,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }

      expect(byReminder.keys, containsAll(['early', 'noon', 'evening']));
      expect(byReminder['early'], 2);
      expect(byReminder['noon'], 1);
      expect(byReminder['evening'], 1);
    });

    test('registrations come out in chronological order', () {
      final plan = reconciler.plan(
        reminders: [
          daily('evening', const LocalTime(20, 0)),
          daily('early', const LocalTime(6, 30)),
        ],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 4),
      );

      final instants = plan.toRegister
          .whereType<TimedRegistration>()
          .map((r) => r.occurrence.instant)
          .toList();

      final sorted = [...instants]..sort();
      expect(instants, orderedEquals(sorted));
    });
  });

  group('planning against existing registrations', () {
    test('retains what is already registered and still wanted', () {
      final reminder = daily('wake', const LocalTime(7, 0));
      const budget = SchedulingBudget(maxTimed: 3);

      final first = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: budget,
      );
      final registered = first.toRegister.map((r) => r.key).toSet();

      final second = reconciler.plan(
        reminders: [reminder],
        registered: registered,
        zone: zone,
        now: now,
        budget: budget,
      );

      expect(second.toRegister, isEmpty);
      expect(second.toCancel, isEmpty);
      expect(second.retained, hasLength(3));
      expect(second.isEmpty, isTrue, reason: 'a settled state needs no work');
    });

    test('cancels registrations that are no longer wanted', () {
      final reminder = daily('wake', const LocalTime(7, 0));
      const budget = SchedulingBudget(maxTimed: 2);

      final first = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: budget,
      );
      final registered = first.toRegister.map((r) => r.key).toSet();

      // The user turns it off.
      final second = reconciler.plan(
        reminders: [reminder.copyWith(enabled: false)],
        registered: registered,
        zone: zone,
        now: now,
        budget: budget,
      );

      expect(second.toRegister, isEmpty);
      expect(second.toCancel, hasLength(2));
      expect(second.toCancel.toSet(), registered);
    });

    test('cancels a reminder that has disappeared entirely', () {
      final reminder = daily('wake', const LocalTime(7, 0));
      const budget = SchedulingBudget(maxTimed: 2);

      final first = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: budget,
      );

      final second = reconciler.plan(
        reminders: const [],
        registered: first.toRegister.map((r) => r.key).toSet(),
        zone: zone,
        now: now,
        budget: budget,
      );

      expect(second.toCancel, hasLength(2));
    });

    test('advances the window as occurrences are consumed', () {
      final reminder = daily('wake', const LocalTime(7, 0));
      const budget = SchedulingBudget(maxTimed: 2);

      final first = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: budget,
      );
      final registered = first.toRegister.map((r) => r.key).toSet();

      // The first occurrence has fired and fallen out of the window; a new one
      // at the far end must take its place, and the middle one stays put.
      final later = reconciler.plan(
        reminders: [reminder],
        registered: registered,
        zone: zone,
        now: tz.TZDateTime(zone, 2026, 5, 11, 8),
        budget: budget,
      );

      expect(later.toRegister, hasLength(1));
      expect(later.retained, hasLength(1));
      expect(
        later.toCancel,
        isEmpty,
        reason: 'a fired occurrence is gone, not cancellable',
      );
    });

    test('ignores registrations it does not recognise', () {
      // Something else scheduled this, or it survived an older version of the
      // app. Cancelling it is the reconciler's job only if it owns the key.
      final foreign = RegistrationKey.raw('someone-elses-notification');

      final plan = reconciler.plan(
        reminders: [daily('wake', const LocalTime(7, 0))],
        registered: {foreign},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 2),
      );

      expect(plan.toCancel, isEmpty);
      expect(plan.unknown, {foreign});
    });
  });

  group('region registrations', () {
    Reminder atRegion(String id, GeoRegion region) => Reminder(
          id: id,
          title: id,
          triggers: [LocationTrigger(region: region, event: GeoEvent.enter)],
        );

    test('a location trigger produces a region registration', () {
      final plan = reconciler.plan(
        reminders: [atRegion('groceries', supermarket)],
        registered: const {},
        zone: zone,
        now: now,
      );

      expect(plan.toRegister, hasLength(1));
      final registration = plan.toRegister.single;
      expect(registration, isA<RegionRegistration>());
      expect((registration as RegionRegistration).region, supermarket);
      expect(registration.event, GeoEvent.enter);
    });

    test('region and timed budgets are counted separately', () {
      final plan = reconciler.plan(
        reminders: [
          daily('wake', const LocalTime(7, 0)),
          atRegion('groceries', supermarket),
        ],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 2, maxRegions: 1),
      );

      expect(plan.toRegister.whereType<TimedRegistration>(), hasLength(2));
      expect(plan.toRegister.whereType<RegionRegistration>(), hasLength(1));
    });

    test('regions beyond the budget are dropped, and reported', () {
      final plan = reconciler.plan(
        reminders: [
          atRegion('groceries', supermarket),
          atRegion('work', office),
        ],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxRegions: 1),
      );

      expect(plan.toRegister.whereType<RegionRegistration>(), hasLength(1));
      expect(
        plan.droppedRegions,
        hasLength(1),
        reason: 'silently dropping a region would look like a bug in the app',
      );
    });

    test('the nearest regions win when the device location is known', () {
      // Standing next to the office, so the office region matters more than
      // the supermarket across town.
      final plan = reconciler.plan(
        reminders: [
          atRegion('groceries', supermarket),
          atRegion('work', office),
        ],
        registered: const {},
        zone: zone,
        now: now,
        deviceLocation: office.center,
        budget: const SchedulingBudget(maxRegions: 1),
      );

      final kept = plan.toRegister.whereType<RegionRegistration>().single;
      expect(kept.region, office);
    });

    test('a reminder with both trigger kinds registers both', () {
      final reminder = Reminder(
        id: 'groceries',
        title: 'Buy milk',
        triggers: [
          const LocationTrigger(region: supermarket, event: GeoEvent.enter),
          WeeklyTrigger(
            days: {Weekday.saturday},
            time: const LocalTime(11, 0),
          ),
        ],
      );

      final plan = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 1, maxRegions: 1),
      );

      expect(plan.toRegister.whereType<TimedRegistration>(), hasLength(1));
      expect(plan.toRegister.whereType<RegionRegistration>(), hasLength(1));
    });
  });

  group('registration keys', () {
    test('are stable across identical plans', () {
      final reminder = daily('wake', const LocalTime(7, 0));

      Set<RegistrationKey> keysFrom() => reconciler
          .plan(
            reminders: [reminder],
            registered: const {},
            zone: zone,
            now: now,
            budget: const SchedulingBudget(maxTimed: 3),
          )
          .toRegister
          .map((r) => r.key)
          .toSet();

      expect(keysFrom(), keysFrom());
    });

    test('differ per reminder and per instant', () {
      final plan = reconciler.plan(
        reminders: [
          daily('a', const LocalTime(7, 0)),
          daily('b', const LocalTime(7, 0)),
        ],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 4),
      );

      final keys = plan.toRegister.map((r) => r.key).toSet();
      expect(keys, hasLength(4));
    });

    test('expose a stable non-negative platform id', () {
      // Platforms key notifications by 32-bit int, so the string key has to
      // survive being squeezed into one.
      final key = RegistrationKey.raw('wake@2026-05-11T07:00:00Z');

      expect(key.platformId, key.platformId);
      expect(key.platformId, isNonNegative);
      expect(key.platformId, lessThan(1 << 31));
    });

    test('round-trip through their string form', () {
      final plan = reconciler.plan(
        reminders: [daily('wake', const LocalTime(7, 0))],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 1),
      );
      final key = plan.toRegister.single.key;

      expect(RegistrationKey.raw(key.value), key);
    });
  });

  group('conditions ride along', () {
    test('a pending condition reaches the registration', () {
      final reminder = Reminder(
        id: 'groceries',
        title: 'Buy milk',
        triggers: [
          WeeklyTrigger(days: Weekday.all, time: const LocalTime(11, 0)),
        ],
        condition: const InsideRegionCondition(supermarket),
      );

      final plan = reconciler.plan(
        reminders: [reminder],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(maxTimed: 1),
      );

      final registration = plan.toRegister.single as TimedRegistration;
      expect(
        registration.occurrence.pendingCondition,
        const InsideRegionCondition(supermarket),
      );
    });
  });

  group('horizon', () {
    test('nothing is scheduled beyond it', () {
      final plan = reconciler.plan(
        reminders: [daily('wake', const LocalTime(7, 0))],
        registered: const {},
        zone: zone,
        now: now,
        budget: const SchedulingBudget(
          maxTimed: 64,
          horizon: Duration(days: 3),
        ),
      );

      expect(plan.toRegister, hasLength(3));
      final last = (plan.toRegister.last as TimedRegistration).occurrence;
      expect(last.instant.isBefore(now.add(const Duration(days: 3))), isTrue);
    });
  });
}
