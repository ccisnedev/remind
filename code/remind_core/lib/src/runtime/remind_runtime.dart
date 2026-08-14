import 'dart:async';

import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import '../engine/occurrence_engine.dart';
import '../model/geo.dart';
import '../model/occurrence.dart';
import '../model/reminder.dart';
import '../ports/reminder_backend.dart';
import '../ports/reminder_store.dart';
import '../scheduling/reconciler.dart';
import '../scheduling/registration.dart';
import '../scheduling/scheduling_budget.dart';

/// Something that went wrong while applying a plan.
///
/// Collected rather than thrown. One backend refusing one reminder must not
/// cost the user every other reminder in the same pass, and a runtime that
/// aborted on the first error would do exactly that.
@immutable
final class ReconcileFailure {
  /// Creates a failure record.
  const ReconcileFailure({
    required this.error,
    required this.stackTrace,
    this.registration,
    this.key,
    this.backend,
  });

  /// What was thrown.
  final Object error;

  /// Where it was thrown.
  final StackTrace stackTrace;

  /// The registration being applied, when the failure happened during one.
  final Registration? registration;

  /// The key involved, whether registering or cancelling.
  final RegistrationKey? key;

  /// The backend that failed, when it is known.
  final ReminderBackend? backend;

  @override
  String toString() => 'ReconcileFailure(${key ?? 'query'}: $error)';
}

/// What a reconcile actually did.
@immutable
final class ReconcileResult {
  /// Creates a result.
  const ReconcileResult({
    required this.plan,
    required this.unroutable,
    required this.failures,
    required this.at,
  });

  /// The plan that was computed.
  final ReconciliationPlan plan;

  /// Registrations no available backend was willing to take.
  ///
  /// The case that matters is a reminder gated by a geofence with only a
  /// notification backend installed: nothing can deliver it. Reporting that
  /// beats letting it disappear.
  final List<Registration> unroutable;

  /// Everything that failed while applying the plan.
  final List<ReconcileFailure> failures;

  /// When the reconcile ran.
  final tz.TZDateTime at;

  /// Whether the plan called for any work at all.
  bool get changedAnything => !plan.isEmpty;

  /// Whether the platform now holds exactly what was wanted.
  bool get isClean => failures.isEmpty && unroutable.isEmpty;

  @override
  String toString() => 'ReconcileResult($plan'
      '${unroutable.isEmpty ? '' : ', unroutable:${unroutable.length}'}'
      '${failures.isEmpty ? '' : ', failed:${failures.length}'})';
}

/// Ties a store, a reconciler and one or more backends together.
///
/// The reconciler computes what should happen; this is what makes it happen.
/// It is the piece an application actually calls, and the rule it enforces is
/// simple: **reconcile whenever the world may have moved underneath the
/// schedule** — on launch, on resume, after a reboot, after a time zone change,
/// and after every edit. The platform holds only a window, and that window has
/// to be refilled as it drains.
///
/// ```dart
/// final runtime = RemindRuntime(
///   store: store,
///   backends: [notificationBackend],
///   zone: tz.getLocation('America/Lima'),
/// );
///
/// final result = await runtime.reconcile();
/// if (!result.isClean) {
///   // Something could not be delivered. Say so rather than hoping.
/// }
/// ```
final class RemindRuntime {
  /// Creates a runtime.
  RemindRuntime({
    required this.store,
    required List<ReminderBackend> backends,
    required this.zone,
    this.reconciler = const Reconciler(),
    this.engine = const OccurrenceEngine(),
  }) : _backends = List.unmodifiable(backends);

  /// The zone the user's wall-clock times are interpreted in.
  ///
  /// Mutable because it genuinely changes: a user who flies from Lima to Tokyo
  /// still means 07:00 wherever they are now. Set it and reconcile — every
  /// registered instant moves, so the plan will replace all of them.
  tz.Location zone;

  /// Where reminders are kept.
  final ReminderStore store;

  /// Plans the work.
  final Reconciler reconciler;

  /// Resolves triggers into instants.
  final OccurrenceEngine engine;

  final List<ReminderBackend> _backends;
  Future<void> _queue = Future<void>.value();

  /// The backends this runtime routes to.
  List<ReminderBackend> get backends => _backends;

  /// Brings every available backend in line with the stored reminders.
  ///
  /// Calls are serialised. Two overlapping reconciles would each read the
  /// platform's state before the other had written it, and both would register
  /// the same window — so a second call waits for the first rather than racing
  /// it.
  ///
  /// Never throws for a backend's sake. Anything that goes wrong is collected
  /// into [ReconcileResult.failures], because the alternative is one
  /// misbehaving backend silently costing the user every reminder they have.
  ///
  /// Set [refreshAll] to re-register everything, including what is already in
  /// place. Normally that would be wasted work — the key matches, so the
  /// platform already holds the right instant. It is necessary when something
  /// about *how* a registration is delivered has changed while *when* has not:
  /// the user granting permission for exact alarms, a backend being
  /// reconfigured, a channel changing. A registration's key encodes its
  /// instant, not its delivery, so nothing else would notice, and reminders
  /// registered under the old settings would keep the old behaviour forever.
  Future<ReconcileResult> reconcile({bool refreshAll = false}) =>
      _serialised(() => _reconcile(refreshAll: refreshAll));

  /// The plan that *would* be applied, without applying any of it.
  ///
  /// Being able to look before acting is most of the reason [Reconciler]
  /// returns data rather than performing the work itself. When a reminder does
  /// not arrive, this answers whether it was ever scheduled.
  Future<ReconciliationPlan> preview() => _serialised(() async {
        final (usable, registered, _) = await _survey();
        return reconciler.plan(
          reminders: await store.all(),
          registered: registered,
          zone: zone,
          now: tz.TZDateTime.now(zone),
          budget: combinedBudget(usable),
        );
      });

  /// The next [limit] occurrences of [reminder], for showing a user what the
  /// engine worked out.
  List<Occurrence> upcoming(
    Reminder reminder, {
    int limit = 5,
    GeoCoordinate? deviceLocation,
  }) =>
      engine.occurrencesOf(
        reminder,
        zone: zone,
        from: tz.TZDateTime.now(zone),
        limit: limit,
      );

  /// What [backends] are collectively able to hold.
  ///
  /// Capacities add, because each registration is routed to exactly one
  /// backend. Horizons do not: the shortest wins, since scheduling past a
  /// backend's horizon hands it work it will not keep.
  ///
  /// Exposed for diagnostics — an application showing why a reminder was not
  /// scheduled needs to be able to show the ceiling it hit.
  SchedulingBudget combinedBudget(List<ReminderBackend> backends) {
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

  Future<ReconcileResult> _reconcile({required bool refreshAll}) async {
    final (usable, registered, failures) = await _survey();

    final now = tz.TZDateTime.now(zone);
    final plan = reconciler.plan(
      reminders: await store.all(),
      registered: registered,
      zone: zone,
      now: now,
      budget: combinedBudget(usable),
    );

    // Cancel first, so a tight platform allowance is freed before more is
    // asked of it. Backends are required to be idempotent, so offering a key
    // to one that does not hold it is harmless — and cheaper than tracking
    // which backend owns what.
    for (final key in plan.toCancel) {
      for (final backend in usable) {
        try {
          await backend.cancel(key);
        } on Object catch (error, stackTrace) {
          failures.add(
            ReconcileFailure(
              error: error,
              stackTrace: stackTrace,
              key: key,
              backend: backend,
            ),
          );
        }
      }
    }

    final unroutable = <Registration>[];
    // Backends are idempotent, so re-registering a key the platform already
    // holds replaces it — which is exactly what a refresh needs.
    final toApply =
        refreshAll ? [...plan.toRegister, ...plan.retained] : plan.toRegister;
    for (final registration in toApply) {
      final backend =
          usable.where((b) => b.canHandle(registration)).firstOrNull;
      if (backend == null) {
        unroutable.add(registration);
        continue;
      }
      try {
        await backend.register(registration);
      } on Object catch (error, stackTrace) {
        failures.add(
          ReconcileFailure(
            error: error,
            stackTrace: stackTrace,
            registration: registration,
            key: registration.key,
            backend: backend,
          ),
        );
      }
    }

    return ReconcileResult(
      plan: plan,
      unroutable: List.unmodifiable(unroutable),
      failures: List.unmodifiable(failures),
      at: now,
    );
  }

  /// Works out which backends can be used this pass, and what they hold.
  ///
  /// A backend is usable only if it reports itself available **and** can say
  /// what it is currently holding. The second condition is not fussiness: the
  /// whole model is a diff between desired and actual state, so a backend that
  /// cannot report its actual state would look empty on every pass and be
  /// handed the same registrations again and again, duplicating them forever.
  /// Skipping it costs one backend; using it corrupts the schedule.
  ///
  /// One broken backend never disables the others.
  Future<(List<ReminderBackend>, Set<RegistrationKey>, List<ReconcileFailure>)>
      _survey() async {
    final usable = <ReminderBackend>[];
    final registered = <RegistrationKey>{};
    final failures = <ReconcileFailure>[];

    for (final backend in _backends) {
      try {
        if (!await backend.isAvailable) continue;
        registered.addAll(await backend.pendingRegistrations());
        usable.add(backend);
      } on Object catch (error, stackTrace) {
        failures.add(
          ReconcileFailure(
            error: error,
            stackTrace: stackTrace,
            backend: backend,
          ),
        );
      }
    }
    return (usable, registered, failures);
  }

  /// Runs [action] after anything already queued, whether that succeeded or
  /// not, so one failure cannot wedge every later call.
  Future<T> _serialised<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
