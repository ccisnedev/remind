import 'package:remind_core/remind_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// What a reconcile actually did.
final class ReconcileResult {
  /// Creates a result.
  const ReconcileResult({
    required this.plan,
    required this.unroutable,
    required this.at,
  });

  /// The plan that was computed.
  final ReconciliationPlan plan;

  /// Registrations no available backend was willing to take.
  ///
  /// The interesting case is a reminder gated by a geofence with only the
  /// notification backend installed: nothing can deliver it, and the honest
  /// thing is to say so rather than let it disappear.
  final List<Registration> unroutable;

  /// When the reconcile ran.
  final tz.TZDateTime at;

  /// Whether anything at all happened.
  bool get changedAnything => !plan.isEmpty;
}

/// Ties a store, a reconciler and one or more backends together.
///
/// This is the layer deliberately left out of `remind_core`: designing it
/// before a real backend existed would have been guesswork. It lives here while
/// its shape is proven against an actual device, and is a candidate for
/// promotion into the core once it has earned it.
///
/// The rule it enforces is simple. Reconcile whenever the world may have moved
/// underneath the schedule — on launch, on resume, after a reboot, after a time
/// zone change, and after every edit — because the platform holds only a window
/// and that window has to be refilled as it drains.
final class RemindRuntime {
  /// Creates a runtime.
  RemindRuntime({
    required this.store,
    required List<ReminderBackend> backends,
    required this.zone,
    this.reconciler = const Reconciler(),
    this.engine = const OccurrenceEngine(),
  }) : _backends = backends;

  /// Where reminders are kept.
  final ReminderStore store;

  /// The zone the user's wall-clock times are interpreted in.
  final tz.Location zone;

  /// The reconciler used to plan.
  final Reconciler reconciler;

  /// The engine used to preview upcoming occurrences.
  final OccurrenceEngine engine;

  final List<ReminderBackend> _backends;

  /// The backends this runtime can route to.
  List<ReminderBackend> get backends => List.unmodifiable(_backends);

  /// Brings every backend in line with the stored reminders.
  Future<ReconcileResult> reconcile() async {
    final available = <ReminderBackend>[];
    for (final backend in _backends) {
      if (await backend.isAvailable) available.add(backend);
    }

    final registered = <RegistrationKey>{};
    for (final backend in available) {
      registered.addAll(await backend.pendingRegistrations());
    }

    final now = tz.TZDateTime.now(zone);
    final plan = reconciler.plan(
      reminders: await store.all(),
      registered: registered,
      zone: zone,
      now: now,
      budget: _combinedBudget(available),
    );

    // Cancel first, so that a tight platform allowance is freed before it is
    // asked for more. Backends are idempotent, so offering a key to one that
    // does not hold it is harmless — and cheaper than tracking ownership.
    for (final key in plan.toCancel) {
      for (final backend in available) {
        await backend.cancel(key);
      }
    }

    final unroutable = <Registration>[];
    for (final registration in plan.toRegister) {
      final backend = available.where((b) => b.canHandle(registration));
      if (backend.isEmpty) {
        unroutable.add(registration);
        continue;
      }
      await backend.first.register(registration);
    }

    return ReconcileResult(plan: plan, unroutable: unroutable, at: now);
  }

  /// The next [limit] occurrences of [reminder], for showing the user what the
  /// engine worked out.
  List<Occurrence> upcoming(Reminder reminder, {int limit = 5}) =>
      engine.occurrencesOf(
        reminder,
        zone: zone,
        from: tz.TZDateTime.now(zone),
        limit: limit,
      );

  /// The plan that *would* be applied, without applying it.
  ///
  /// Powers the diagnostics screen. Being able to look at the plan before it
  /// runs is most of the reason the reconciler returns data instead of just
  /// doing the work.
  Future<ReconciliationPlan> preview() async {
    final registered = <RegistrationKey>{};
    for (final backend in _backends) {
      if (await backend.isAvailable) {
        registered.addAll(await backend.pendingRegistrations());
      }
    }
    return reconciler.plan(
      reminders: await store.all(),
      registered: registered,
      zone: zone,
      now: tz.TZDateTime.now(zone),
      budget: _combinedBudget(_backends),
    );
  }

  /// Adds up what the installed backends are collectively able to hold.
  ///
  /// Each registration is routed to exactly one backend, so capacities add.
  /// Horizons do not: the shortest one wins, since scheduling past a backend's
  /// horizon would hand it work it will not keep.
  SchedulingBudget _combinedBudget(List<ReminderBackend> backends) {
    if (backends.isEmpty) {
      return const SchedulingBudget(maxTimed: 0, maxRegions: 0);
    }

    var timed = 0;
    var regions = 0;
    var horizon = backends.first.budget.horizon;
    for (final backend in backends) {
      timed += backend.budget.maxTimed;
      regions += backend.budget.maxRegions;
      if (backend.budget.horizon < horizon) horizon = backend.budget.horizon;
    }
    return SchedulingBudget(
      maxTimed: timed,
      maxRegions: regions,
      horizon: horizon,
    );
  }
}
