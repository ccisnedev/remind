import 'package:flutter_test/flutter_test.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_notifications/remind_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Records what the backend asks of the platform, so the backend's behaviour
/// can be asserted without a device, a channel, or a running Flutter engine.
final class FakeScheduler implements NotificationScheduler {
  final List<ScheduledNotification> scheduled = [];
  final List<int> cancelled = [];
  bool enabled = true;
  bool exact = true;
  int exactPermissionRequests = 0;

  @override
  Future<bool> areNotificationsEnabled() async => enabled;

  @override
  Future<bool> canDeliverExactly() async => exact;

  @override
  Future<bool> requestExactPermission() async {
    exactPermissionRequests++;
    return exact;
  }

  @override
  Future<void> schedule(ScheduledNotification notification) async {
    scheduled
      ..removeWhere((n) => n.id == notification.id)
      ..add(notification);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.removeWhere((n) => n.id == id);
  }

  @override
  Future<List<PendingNotification>> pending() async => [
        for (final n in scheduled)
          PendingNotification(id: n.id, payload: n.payload),
      ];
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late FakeScheduler scheduler;
  late NotificationBackend backend;

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    scheduler = FakeScheduler();
    backend = NotificationBackend(scheduler: scheduler);
  });

  Reminder reminderOf({Condition? condition, Map<String, Object?>? payload}) =>
      Reminder(
        id: 'wake',
        title: 'Wake up',
        body: 'Time to get moving',
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
        condition: condition,
        payload: payload ?? const {},
      );

  TimedRegistration timedAt(
    int day, {
    Condition? pendingCondition,
    Map<String, Object?>? payload,
  }) {
    final reminder = reminderOf(condition: pendingCondition, payload: payload);
    return TimedRegistration(
      reminder: reminder,
      occurrence: Occurrence(
        reminderId: reminder.id,
        instant: tz.TZDateTime(zone, 2026, 5, day, 7),
        trigger: reminder.triggers.first as TimeTrigger,
        pendingCondition: pendingCondition,
      ),
    );
  }

  group('canHandle', () {
    test('accepts an unconditional timed registration', () {
      expect(backend.canHandle(timedAt(11)), isTrue);
    });

    test('refuses a registration with an outstanding condition', () {
      // A scheduled local notification is displayed by the operating system
      // without running any of the application's code first — on iOS the
      // service extension that could intercept it only fires for remote push.
      // There is therefore no moment at which this backend could evaluate a
      // geofence condition and decide to stay silent, so it declines the work
      // rather than delivering a reminder whose condition may not hold.
      const office = GeoRegion(
        id: 'office',
        center: GeoCoordinate(-33.4489, -70.6693),
        radiusMetres: 150,
      );

      expect(
        backend.canHandle(
          timedAt(11, pendingCondition: const InsideRegionCondition(office)),
        ),
        isFalse,
      );
    });

    test('refuses a region registration', () {
      expect(
        backend.canHandle(
          RegionRegistration(
            reminder: reminderOf(),
            region: const GeoRegion(
              id: 'shop',
              center: GeoCoordinate(-33.4, -70.6),
              radiusMetres: 200,
            ),
            event: GeoEvent.enter,
          ),
        ),
        isFalse,
      );
    });
  });

  group('budget', () {
    test('declares no region capacity at all', () {
      expect(
        backend.budget.maxRegions,
        0,
        reason: 'this backend cannot watch regions, and saying so keeps the '
            'reconciler from handing it any',
      );
    });

    test('leaves headroom below the iOS ceiling of 64', () {
      expect(backend.budget.maxTimed, lessThan(64));
    });

    test('accepts an explicit budget', () {
      final tight = NotificationBackend(
        scheduler: scheduler,
        budget: const SchedulingBudget(maxTimed: 4, maxRegions: 0),
      );

      expect(tight.budget.maxTimed, 4);
    });
  });

  group('availability', () {
    test('follows the platform', () async {
      expect(await backend.isAvailable, isTrue);

      scheduler.enabled = false;
      expect(await backend.isAvailable, isFalse);
    });
  });

  group('precision', () {
    test('reports what the platform will actually do', () async {
      expect(await backend.deliversExactly, isTrue);

      scheduler.exact = false;
      expect(await backend.deliversExactly, isFalse);
    });

    test('losing exactness does not make the backend unavailable', () async {
      // Degrading is the platform's business; deciding whether a late reminder
      // is acceptable is the application's. Conflating them would leave an app
      // that tolerates lateness with nothing scheduled at all.
      scheduler.exact = false;

      expect(await backend.isAvailable, isTrue);
      expect(await backend.deliversExactly, isFalse);
    });

    test('permission can be requested through the backend', () async {
      expect(await backend.requestExactPermission(), isTrue);
      expect(scheduler.exactPermissionRequests, 1);
    });

    test('reminders still schedule when exactness is unavailable', () async {
      // Refusing to schedule would turn "possibly late" into "definitely
      // never", which is strictly worse whatever the application's policy.
      scheduler.exact = false;
      await backend.register(timedAt(11));

      expect(scheduler.scheduled, hasLength(1));
    });
  });

  group('register', () {
    test('schedules at the occurrence instant with the reminder text',
        () async {
      final registration = timedAt(11);
      await backend.register(registration);

      final scheduled = scheduler.scheduled.single;
      expect(scheduled.id, registration.key.platformId);
      expect(scheduled.title, 'Wake up');
      expect(scheduled.body, 'Time to get moving');
      expect(scheduled.when, registration.occurrence.instant);
    });

    test('refuses work it declared it cannot handle', () async {
      const office = GeoRegion(
        id: 'office',
        center: GeoCoordinate(-33.4489, -70.6693),
        radiusMetres: 150,
      );

      await expectLater(
        backend.register(
          timedAt(11, pendingCondition: const InsideRegionCondition(office)),
        ),
        throwsArgumentError,
      );
      expect(scheduler.scheduled, isEmpty);
    });

    test('registering the same key twice replaces rather than duplicates',
        () async {
      await backend.register(timedAt(11));
      await backend.register(timedAt(11));

      expect(scheduler.scheduled, hasLength(1));
    });
  });

  group('pendingRegistrations', () {
    test('recovers the exact keys that were registered', () async {
      final first = timedAt(11);
      final second = timedAt(12);
      await backend.register(first);
      await backend.register(second);

      expect(await backend.pendingRegistrations(), {first.key, second.key});
    });

    test('survives a round trip through the platform payload', () async {
      // The platform hands back an int id and a payload string, never our key,
      // so the key has to be recoverable from the payload alone.
      final registration = timedAt(11);
      await backend.register(registration);

      final recovered = (await backend.pendingRegistrations()).single;
      expect(recovered, registration.key);
      expect(recovered.value, registration.key.value);
    });

    test('reports notifications it did not schedule as foreign', () async {
      scheduler.scheduled.add(
        ScheduledNotification(
          id: 4242,
          title: 'Someone else',
          when: tz.TZDateTime(zone, 2026, 5, 11, 9),
          payload: 'not-ours',
        ),
      );

      final pending = await backend.pendingRegistrations();

      expect(pending, hasLength(1));
      expect(
        pending.single.isOwned,
        isFalse,
        reason: 'an unrecognised notification must not look cancellable',
      );
    });

    test('treats a missing payload as foreign rather than guessing', () async {
      scheduler.scheduled.add(
        ScheduledNotification(
          id: 99,
          title: 'No payload',
          when: tz.TZDateTime(zone, 2026, 5, 11, 9),
          payload: '',
        ),
      );

      expect((await backend.pendingRegistrations()).single.isOwned, isFalse);
    });
  });

  group('cancel', () {
    test('cancels by the platform id derived from the key', () async {
      final registration = timedAt(11);
      await backend.register(registration);
      await backend.cancel(registration.key);

      expect(scheduler.cancelled, [registration.key.platformId]);
      expect(await backend.pendingRegistrations(), isEmpty);
    });

    test('cancelling something absent is quiet', () async {
      await expectLater(
        backend.cancel(RegistrationKey.raw('remind:t:ghost:1')),
        completes,
      );
    });
  });

  group('payload', () {
    test('carries the application payload through to delivery', () async {
      await backend.register(timedAt(11, payload: {'route': '/gym'}));

      final decoded = NotificationPayload.decode(
        scheduler.scheduled.single.payload,
      );

      expect(decoded, isNotNull);
      expect(decoded!.reminderId, 'wake');
      expect(decoded.data, {'route': '/gym'});
    });

    test('decoding rubbish yields null instead of throwing', () {
      expect(NotificationPayload.decode('{not json'), isNull);
      expect(NotificationPayload.decode(''), isNull);
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode('{"unexpected":true}'), isNull);
    });
  });

  group('a full reconcile cycle', () {
    test('drives the platform from empty to settled and back', () async {
      const reconciler = Reconciler();
      final store = InMemoryReminderStore();
      await store.save(reminderOf());

      final now = tz.TZDateTime(zone, 2026, 5, 11, 6);

      Future<ReconciliationPlan> reconcile() async {
        final plan = reconciler.plan(
          reminders: await store.all(),
          registered: await backend.pendingRegistrations(),
          zone: zone,
          now: now,
          budget: backend.budget,
        );
        for (final key in plan.toCancel) {
          await backend.cancel(key);
        }
        for (final registration in plan.toRegister) {
          await backend.register(registration);
        }
        return plan;
      }

      final first = await reconcile();
      expect(first.toRegister, isNotEmpty);
      expect(scheduler.scheduled, hasLength(first.toRegister.length));

      // Running again against an unchanged store must be a no-op.
      final second = await reconcile();
      expect(second.isEmpty, isTrue);
      expect(second.retained, hasLength(first.toRegister.length));

      // Disabling the reminder must clear the platform.
      await store.save(reminderOf().copyWith(enabled: false));
      final third = await reconcile();
      expect(third.toCancel, isNotEmpty);
      expect(scheduler.scheduled, isEmpty);
    });
  });
}
