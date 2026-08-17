import 'package:remind_core/remind_core.dart';

import 'monitored_region.dart';

/// Delivers reminders when the device crosses a region boundary.
///
/// The counterpart to a notification backend, and its opposite in one
/// important way: this one **accepts registrations that still carry a
/// condition**.
///
/// That is not a difference of ambition but of platform. A scheduled local
/// notification is displayed by the operating system with no chance for
/// application code to intervene, so a notification backend genuinely cannot
/// evaluate anything at firing time. A region crossing wakes application code
/// *before* anything is shown — on Android through the geofencing broadcast,
/// on iOS through Core Location region monitoring — so the condition can be
/// checked and the reminder can stay quiet.
///
/// The consequence is that this backend must post its own notification once it
/// decides, rather than handing the work to a notification backend: by the time
/// it knows the condition holds, it is already inside the callback.
final class GeofenceBackend implements ReminderBackend {
  /// Creates a backend over [scheduler].
  GeofenceBackend({
    required GeofenceScheduler scheduler,
    SchedulingBudget budget = defaultBudget,
  })  : _scheduler = scheduler,
        _budget = budget;

  /// No timed capacity, and fewer regions than iOS allows.
  ///
  /// iOS monitors at most 20 regions per app, and Apple describes regions as a
  /// shared system resource, so taking the whole allowance would be both
  /// fragile and antisocial. Android permits around 100, but a budget has to
  /// suit the tighter platform. The reconciler prioritises by proximity, which
  /// is exactly the workaround Apple documents for wanting more regions than
  /// the limit allows.
  static const SchedulingBudget defaultBudget = SchedulingBudget(
    maxTimed: 0,
    maxRegions: 16,
  );

  final GeofenceScheduler _scheduler;
  final SchedulingBudget _budget;

  @override
  SchedulingBudget get budget => _budget;

  @override
  bool canHandle(Registration registration) =>
      registration is RegionRegistration;

  @override
  Future<bool> get isAvailable => _scheduler.isAvailable();

  @override
  Future<Set<RegistrationKey>> pendingRegistrations() async {
    final ids = await _scheduler.registeredIds();
    return {for (final id in ids) RegistrationKey.raw(id)};
  }

  @override
  Future<void> register(Registration registration) async {
    if (registration is! RegionRegistration) {
      throw ArgumentError.value(
        registration,
        'registration',
        'GeofenceBackend monitors regions only. Timed registrations belong to '
            'a notification or alarm backend.',
      );
    }

    await _scheduler.register(
      MonitoredRegion(
        id: registration.key.value,
        region: registration.region,
        events: {registration.event},
        dwellTime: registration.dwellTime,
      ),
    );
  }

  @override
  Future<void> cancel(RegistrationKey key) => _scheduler.remove(key.value);
}
