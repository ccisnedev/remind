import '../scheduling/registration.dart';
import '../scheduling/scheduling_budget.dart';

/// Something that can hand a registration to the operating system.
///
/// A port, not an implementation. `remind_notifications` implements it over
/// local notifications, `remind_alarm` over a native alarm, `remind_geofence`
/// over region monitoring — and an application that needs only date-and-time
/// reminders depends on exactly one of them and never links the others.
///
/// A backend is expected to be idempotent: registering a key that is already
/// registered replaces it rather than duplicating it, and cancelling a key that
/// is not registered succeeds quietly. The reconciler already avoids both, but
/// platforms fire late, processes die mid-plan, and neither case should be an
/// error.
abstract interface class ReminderBackend {
  /// Whether this backend is the one that should deliver [registration].
  ///
  /// Lets several backends run side by side — notifications for timed
  /// reminders, geofences for regions — with the caller routing by asking
  /// rather than by type-checking.
  bool canHandle(Registration registration);

  /// The ceilings this platform imposes on this backend.
  ///
  /// Reported rather than assumed, because they differ by platform and by
  /// delivery mechanism: 64 pending notifications on iOS, 20 monitored regions,
  /// effectively no limit on Android alarms.
  SchedulingBudget get budget;

  /// Whether the backend is usable right now.
  ///
  /// False when a permission was refused, a capability is missing, or the OS
  /// version is too old — `remind_alarmkit` on iOS 25, for instance. A caller
  /// should treat this as "route elsewhere", not as an error.
  Future<bool> get isAvailable;

  /// What the platform reports it currently holds for this backend.
  ///
  /// The reconciler compares against this rather than against a ledger of its
  /// own, so that a reinstall, a reboot or a user clearing notifications is
  /// simply observed rather than having to be predicted.
  ///
  /// Keys the backend does not recognise should still be returned; the
  /// reconciler reports them and leaves them alone.
  Future<Set<RegistrationKey>> pendingRegistrations();

  /// Hands [registration] to the platform.
  Future<void> register(Registration registration);

  /// Withdraws the registration identified by [key].
  Future<void> cancel(RegistrationKey key);
}
