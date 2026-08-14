import 'dart:async';

import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A backend that records what it was asked to do.
final class FakeBackend implements ReminderBackend {
  FakeBackend({
    this.budget = const SchedulingBudget(maxTimed: 4, maxRegions: 0),
    this.handlesTimed = true,
    this.handlesRegions = false,
    this.available = true,
  });

  @override
  SchedulingBudget budget;

  bool handlesTimed;
  bool handlesRegions;
  bool available;

  /// When set, [register] throws this for any registration.
  Object? registerError;

  /// When set, [cancel] throws this.
  Object? cancelError;

  /// Delays every call, to expose interleaving between concurrent reconciles.
  Duration latency = Duration.zero;

  final Set<RegistrationKey> registered = {};
  final List<RegistrationKey> cancelled = [];
  final List<String> calls = [];

  @override
  bool canHandle(Registration registration) => switch (registration) {
        TimedRegistration() => handlesTimed,
        RegionRegistration() => handlesRegions,
      };

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<Set<RegistrationKey>> pendingRegistrations() async {
    await _tick('pending');
    return {...registered};
  }

  @override
  Future<void> register(Registration registration) async {
    await _tick('register');
    // ignore: only_throw_errors -- test scaffolding rethrows whatever it is given
    if (registerError != null) throw registerError!;
    registered.add(registration.key);
  }

  @override
  Future<void> cancel(RegistrationKey key) async {
    await _tick('cancel');
    // ignore: only_throw_errors -- test scaffolding rethrows whatever it is given
    if (cancelError != null) throw cancelError!;
    cancelled.add(key);
    registered.remove(key);
  }

  Future<void> _tick(String label) async {
    calls.add(label);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late InMemoryReminderStore store;
  late FakeBackend backend;

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    store = InMemoryReminderStore();
    backend = FakeBackend();
  });

  Reminder daily(String id) => Reminder(
        id: id,
        title: id,
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );

  const supermarket = GeoRegion(
    id: 'supermarket',
    center: GeoCoordinate(-33.4372, -70.6506),
    radiusMetres: 200,
  );

  Reminder atRegion(String id) => Reminder(
        id: id,
        title: id,
        triggers: [
          const LocationTrigger(region: supermarket, event: GeoEvent.enter),
        ],
      );

  RemindRuntime runtimeWith(List<ReminderBackend> backends) =>
      RemindRuntime(store: store, backends: backends, zone: zone);

  group('reconcile', () {
    test('registers what the plan asks for', () async {
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);

      final result = await runtime.reconcile();

      expect(result.plan.toRegister, hasLength(4));
      expect(backend.registered, hasLength(4));
      expect(result.failures, isEmpty);
    });

    test('a second run against an unchanged store is a no-op', () async {
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);

      await runtime.reconcile();
      final second = await runtime.reconcile();

      expect(second.plan.isEmpty, isTrue);
      expect(second.changedAnything, isFalse);
      expect(backend.cancelled, isEmpty);
    });

    test('cancels what is no longer wanted', () async {
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);
      await runtime.reconcile();

      await store.delete('wake');
      final result = await runtime.reconcile();

      expect(result.plan.toCancel, isNotEmpty);
      expect(backend.registered, isEmpty);
    });

    test('cancels before registering, so a tight budget is freed first',
        () async {
      await store.save(daily('a'));
      final runtime = runtimeWith([backend]);
      await runtime.reconcile();

      backend.calls.clear();
      await store.delete('a');
      await store.save(daily('b'));
      await runtime.reconcile();

      final firstCancel = backend.calls.indexOf('cancel');
      final firstRegister = backend.calls.indexOf('register');
      expect(firstCancel, isNonNegative);
      expect(firstRegister, isNonNegative);
      expect(firstCancel, lessThan(firstRegister));
    });

    test('refreshAll re-registers what is already in place', () async {
      // The case this exists for: the user grants permission for exact alarms
      // after reminders were already scheduled inexactly. The keys are
      // unchanged, so an ordinary reconcile sees nothing to do and every
      // existing reminder keeps the old, imprecise delivery forever.
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);
      await runtime.reconcile();

      backend.calls.clear();
      final refreshed = await runtime.reconcile(refreshAll: true);

      expect(refreshed.plan.retained, hasLength(4));
      expect(
        backend.calls.where((c) => c == 'register'),
        hasLength(4),
        reason: 'everything retained must be re-registered, not skipped',
      );
    });

    test('an ordinary reconcile does not re-register', () async {
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);
      await runtime.reconcile();

      backend.calls.clear();
      await runtime.reconcile();

      expect(backend.calls.where((c) => c == 'register'), isEmpty);
    });

    test('skips backends that report themselves unavailable', () async {
      backend.available = false;
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);

      final result = await runtime.reconcile();

      expect(backend.registered, isEmpty);
      expect(result.plan.toRegister, isEmpty);
    });
  });

  group('routing', () {
    test('sends each registration to a backend that will take it', () async {
      final timed = FakeBackend();
      final regions = FakeBackend(
        budget: const SchedulingBudget(maxTimed: 0, maxRegions: 4),
        handlesTimed: false,
        handlesRegions: true,
      );
      await store.save(daily('wake'));
      await store.save(atRegion('groceries'));

      final result = await runtimeWith([timed, regions]).reconcile();

      expect(timed.registered, hasLength(4));
      expect(regions.registered, hasLength(1));
      expect(result.unroutable, isEmpty);
    });

    test('reports registrations no backend will take', () async {
      // Only a notification-style backend installed, but the reminder needs a
      // region watched. Nothing can deliver it, and saying so beats losing it.
      await store.save(atRegion('groceries'));
      final regionCapable = FakeBackend(
        budget: const SchedulingBudget(maxTimed: 0, maxRegions: 4),
        handlesTimed: false,
        handlesRegions: false,
      );

      final result = await runtimeWith([regionCapable]).reconcile();

      expect(result.unroutable, hasLength(1));
      expect(result.unroutable.single, isA<RegionRegistration>());
    });
  });

  group('budgets', () {
    test('capacities add across backends', () async {
      final a = FakeBackend(
        budget: const SchedulingBudget(maxTimed: 3, maxRegions: 0),
      );
      final b = FakeBackend(
        budget: const SchedulingBudget(maxTimed: 0, maxRegions: 5),
        handlesTimed: false,
        handlesRegions: true,
      );

      final runtime = runtimeWith([a, b]);

      expect(runtime.combinedBudget([a, b]).maxTimed, 3);
      expect(runtime.combinedBudget([a, b]).maxRegions, 5);
    });

    test('the shortest horizon wins', () async {
      final near = FakeBackend(
        budget: const SchedulingBudget(horizon: Duration(days: 7)),
      );
      final far = FakeBackend(
        budget: const SchedulingBudget(horizon: Duration(days: 90)),
      );

      final runtime = runtimeWith([near, far]);

      expect(
        runtime.combinedBudget([near, far]).horizon,
        const Duration(days: 7),
        reason: 'scheduling past a backend horizon hands it work it drops',
      );
    });

    test('no backends means no capacity at all', () async {
      final runtime = runtimeWith([]);

      expect(runtime.combinedBudget(const []).maxTimed, 0);
      expect(runtime.combinedBudget(const []).maxRegions, 0);
    });
  });

  group('failures', () {
    test('one failing registration does not abort the rest', () async {
      // The property that matters: a backend that rejects one reminder must
      // not cost the user every other reminder in the same pass.
      final failing = _FailOnceBackend();
      await store.save(daily('a'));

      final result = await runtimeWith([failing]).reconcile();

      expect(result.failures, hasLength(1));
      expect(failing.registered, hasLength(3), reason: '4 attempted, 1 failed');
    });

    test('a failure carries what went wrong and what it was doing', () async {
      backend.registerError = StateError('nope');
      await store.save(daily('a'));

      final result = await runtimeWith([backend]).reconcile();

      expect(result.failures, isNotEmpty);
      final failure = result.failures.first;
      expect(failure.error, isA<StateError>());
      expect(failure.registration, isNotNull);
      expect(failure.key, isNotNull);
    });

    test('a failing cancel is reported, not swallowed', () async {
      await store.save(daily('a'));
      final runtime = runtimeWith([backend]);
      await runtime.reconcile();

      backend.cancelError = StateError('cannot cancel');
      await store.delete('a');
      final result = await runtime.reconcile();

      expect(result.failures, isNotEmpty);
      expect(result.failures.first.error, isA<StateError>());
    });

    test('a backend that throws on query is reported and skipped', () async {
      await store.save(daily('a'));
      final broken = _ThrowOnPendingBackend();
      final healthy = FakeBackend();

      final result = await runtimeWith([broken, healthy]).reconcile();

      expect(result.failures, isNotEmpty);
      expect(
        healthy.registered,
        isNotEmpty,
        reason: 'one broken backend must not disable the others',
      );
    });
  });

  group('concurrency', () {
    test('overlapping reconciles are serialised, not interleaved', () async {
      // Two reconciles racing would each read the platform state before the
      // other wrote it, and both would register the same window twice.
      backend.latency = const Duration(milliseconds: 5);
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);

      final results = await Future.wait([
        runtime.reconcile(),
        runtime.reconcile(),
      ]);

      expect(backend.registered, hasLength(4));
      expect(
        results.last.plan.isEmpty,
        isTrue,
        reason: 'the second pass should find the first already settled',
      );
    });

    test('a failing reconcile does not wedge the queue', () async {
      final broken = _ThrowOnPendingBackend();
      final runtime = RemindRuntime(
        store: store,
        backends: [broken],
        zone: zone,
      );

      await runtime.reconcile();
      await expectLater(runtime.reconcile(), completes);
    });
  });

  group('preview and upcoming', () {
    test('preview plans without touching the backends', () async {
      await store.save(daily('wake'));
      final runtime = runtimeWith([backend]);

      final plan = await runtime.preview();

      expect(plan.toRegister, hasLength(4));
      expect(backend.registered, isEmpty);
      expect(backend.cancelled, isEmpty);
    });

    test('upcoming resolves occurrences in the runtime zone', () {
      final runtime = runtimeWith([backend]);

      final occurrences = runtime.upcoming(daily('wake'), limit: 3);

      expect(occurrences, hasLength(3));
      expect(occurrences.every((o) => o.instant.location == zone), isTrue);
    });
  });

  group('zone changes', () {
    test('a new zone takes effect on the next resolution', () {
      final runtime = runtimeWith([backend]);
      final santiago = runtime.upcoming(daily('wake'), limit: 1).single;

      runtime.zone = tz.getLocation('Asia/Tokyo');
      final tokyo = runtime.upcoming(daily('wake'), limit: 1).single;

      expect(tokyo.instant.location.name, 'Asia/Tokyo');
      expect(tokyo.instant.hour, 7);
      expect(santiago.instant.hour, 7);
      expect(
        tokyo.instant.toUtc(),
        isNot(santiago.instant.toUtc()),
        reason: '07:00 is a different moment in each zone',
      );
    });
  });
}

/// Fails the first registration, then succeeds.
final class _FailOnceBackend extends FakeBackend {
  var _failed = false;

  @override
  Future<void> register(Registration registration) async {
    if (!_failed) {
      _failed = true;
      throw StateError('first one fails');
    }
    await super.register(registration);
  }
}

/// Throws when asked what it is holding.
final class _ThrowOnPendingBackend extends FakeBackend {
  @override
  Future<Set<RegistrationKey>> pendingRegistrations() async =>
      throw StateError('platform unreachable');
}
