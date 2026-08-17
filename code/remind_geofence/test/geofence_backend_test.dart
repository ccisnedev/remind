import 'package:flutter_test/flutter_test.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Records what the backend asks of the platform.
final class FakeGeofenceScheduler implements GeofenceScheduler {
  final Map<String, MonitoredRegion> registered = {};
  final List<String> removed = [];
  bool available = true;
  Object? registerError;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Set<String>> registeredIds() async => registered.keys.toSet();

  @override
  Future<void> register(MonitoredRegion region) async {
    if (registerError != null) {
      // ignore: only_throw_errors -- scaffolding rethrows what it is given
      throw registerError!;
    }
    registered[region.id] = region;
  }

  @override
  Future<void> remove(String id) async {
    registered.remove(id);
    removed.add(id);
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late FakeGeofenceScheduler scheduler;
  late GeofenceBackend backend;

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

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    scheduler = FakeGeofenceScheduler();
    backend = GeofenceBackend(scheduler: scheduler);
  });

  Reminder reminderOf({Condition? condition, GeoRegion region = supermarket}) =>
      Reminder(
        id: 'groceries',
        title: 'Buy milk',
        body: 'You are near the shop',
        triggers: [LocationTrigger(region: region, event: GeoEvent.enter)],
        condition: condition,
      );

  RegionRegistration registrationOf({
    Condition? condition,
    GeoRegion region = supermarket,
    GeoEvent event = GeoEvent.enter,
    Duration? dwellTime,
  }) =>
      RegionRegistration(
        reminder: reminderOf(condition: condition, region: region),
        region: region,
        event: event,
        dwellTime: dwellTime,
        pendingCondition: condition,
      );

  group('canHandle', () {
    test('accepts a region registration', () {
      expect(backend.canHandle(registrationOf()), isTrue);
    });

    test('accepts one carrying an outstanding condition', () {
      // The opposite posture to NotificationBackend, and for a platform reason
      // rather than a preference: a region crossing wakes application code
      // before anything is shown, so the condition can still be evaluated.
      expect(
        backend.canHandle(
          registrationOf(condition: WeekdaysCondition(Weekday.workdays)),
        ),
        isTrue,
      );
    });

    test('refuses a timed registration', () {
      final reminder = Reminder(
        id: 'wake',
        title: 'Wake',
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );
      final timed = TimedRegistration(
        reminder: reminder,
        occurrence: Occurrence(
          reminderId: reminder.id,
          instant: tz.TZDateTime(zone, 2026, 5, 11, 7),
          trigger: reminder.triggers.first as TimeTrigger,
        ),
      );

      expect(backend.canHandle(timed), isFalse);
    });
  });

  group('budget', () {
    test('declares no timed capacity', () {
      expect(backend.budget.maxTimed, 0);
    });

    test('stays below the iOS ceiling of 20 monitored regions', () {
      // Regions are a shared system resource on iOS and the app-wide limit is
      // 20, so consuming all of it would be antisocial as well as fragile.
      expect(backend.budget.maxRegions, lessThan(20));
      expect(backend.budget.maxRegions, greaterThan(0));
    });
  });

  group('register', () {
    test('monitors the region under the registration key', () async {
      final registration = registrationOf();
      await backend.register(registration);

      final monitored = scheduler.registered.values.single;
      expect(monitored.id, registration.key.value);
      expect(monitored.region, supermarket);
      expect(monitored.events, {GeoEvent.enter});
    });

    test('carries dwell time through', () async {
      await backend.register(
        registrationOf(
          event: GeoEvent.dwell,
          dwellTime: const Duration(minutes: 3),
        ),
      );

      expect(
        scheduler.registered.values.single.dwellTime,
        const Duration(minutes: 3),
      );
    });

    test('refuses work it declared it cannot handle', () async {
      final reminder = Reminder(
        id: 'wake',
        title: 'Wake',
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );

      await expectLater(
        backend.register(
          TimedRegistration(
            reminder: reminder,
            occurrence: Occurrence(
              reminderId: reminder.id,
              instant: tz.TZDateTime(zone, 2026, 5, 11, 7),
              trigger: reminder.triggers.first as TimeTrigger,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('pendingRegistrations', () {
    test('recovers the keys it registered', () async {
      final a = registrationOf();
      final b = registrationOf(region: office);
      await backend.register(a);
      await backend.register(b);

      expect(await backend.pendingRegistrations(), {a.key, b.key});
    });

    test('reports regions it did not register as foreign', () async {
      scheduler.registered['someone-elses-fence'] = const MonitoredRegion(
        id: 'someone-elses-fence',
        region: office,
        events: {GeoEvent.enter},
      );

      final pending = await backend.pendingRegistrations();

      expect(pending, hasLength(1));
      expect(pending.single.isOwned, isFalse);
    });
  });

  group('cancel', () {
    test('removes by key', () async {
      final registration = registrationOf();
      await backend.register(registration);
      await backend.cancel(registration.key);

      expect(scheduler.removed, [registration.key.value]);
      expect(await backend.pendingRegistrations(), isEmpty);
    });
  });

  group('availability', () {
    test('follows the platform', () async {
      expect(await backend.isAvailable, isTrue);

      scheduler.available = false;
      expect(await backend.isAvailable, isFalse);
    });
  });
}
