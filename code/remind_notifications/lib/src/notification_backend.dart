import 'package:remind_core/remind_core.dart';

import 'notification_payload.dart';
import 'notification_scheduler.dart';

/// Delivers reminders as local notifications.
///
/// Handles **timed registrations with nothing left to check**, and nothing
/// else. Two refusals are deliberate, and both are honest about a platform
/// limit rather than papering over one:
///
/// * **Regions.** It declares `maxRegions: 0`, so the reconciler never hands it
///   a geofence. Region monitoring belongs to `remind_geofence`.
/// * **Outstanding conditions.** A scheduled local notification is displayed by
///   the operating system without running any of the application's code first.
///   On iOS the notification service extension that could intercept it fires
///   only for remote push, never for a local notification. There is therefore
///   no moment at which this backend could evaluate a geofence condition and
///   decide to stay quiet, so it refuses the work instead of delivering a
///   reminder whose condition might not hold.
///
/// The practical consequence is worth stating plainly: an application that only
/// needs date-and-time reminders needs this package and nothing else — no
/// location permission is declared, requested, or possible.
final class NotificationBackend implements ReminderBackend {
  /// Creates a backend over [scheduler].
  ///
  /// [budget] defaults to a conservative window below the iOS ceiling of 64
  /// pending notifications, with no region capacity.
  NotificationBackend({
    required NotificationScheduler scheduler,
    SchedulingBudget budget = defaultBudget,
  })  : _scheduler = scheduler,
        _budget = budget;

  /// The default ceiling: comfortably under the 64 iOS keeps, and no regions.
  ///
  /// The headroom is for the host application, which almost certainly schedules
  /// notifications this package cannot see. Consuming the whole allowance would
  /// push those out, and that would look like a bug in the application.
  static const SchedulingBudget defaultBudget = SchedulingBudget(
    maxTimed: 48,
    maxRegions: 0,
  );

  final NotificationScheduler _scheduler;
  final SchedulingBudget _budget;

  @override
  SchedulingBudget get budget => _budget;

  @override
  bool canHandle(Registration registration) =>
      registration is TimedRegistration &&
      registration.pendingCondition == null;

  @override
  Future<bool> get isAvailable => _scheduler.areNotificationsEnabled();

  @override
  Future<Set<RegistrationKey>> pendingRegistrations() async {
    final pending = await _scheduler.pending();
    return {
      for (final notification in pending)
        NotificationPayload.decode(notification.payload)?.key ??
            // Not ours: some other part of the application scheduled it. It is
            // reported so the reconciler can see it, with a key that will never
            // match one of ours and so can never be cancelled by mistake.
            RegistrationKey.raw('foreign:notification:${notification.id}'),
    };
  }

  @override
  Future<void> register(Registration registration) async {
    if (!canHandle(registration)) {
      throw ArgumentError.value(
        registration,
        'registration',
        'NotificationBackend delivers unconditional timed registrations only. '
            'A registration with an outstanding condition cannot be gated: the '
            'system displays a scheduled local notification without running '
            'application code first.',
      );
    }

    final timed = registration as TimedRegistration;
    final reminder = timed.reminder;
    await _scheduler.schedule(
      ScheduledNotification(
        id: timed.key.platformId,
        title: reminder.title,
        body: reminder.body,
        when: timed.occurrence.instant,
        payload: NotificationPayload(
          key: timed.key,
          reminderId: reminder.id,
          data: reminder.payload,
        ).encode(),
      ),
    );
  }

  @override
  Future<void> cancel(RegistrationKey key) => _scheduler.cancel(key.platformId);
}
