import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import '../engine/occurrence_engine.dart';
import '../model/geo.dart';
import '../model/reminder.dart';
import 'registration.dart';
import 'scheduling_budget.dart';

/// The difference between what a set of reminders wants and what the platform
/// currently holds.
///
/// A plan is pure data and describes work without doing any of it, so it can be
/// inspected, logged, asserted on in tests, or shown to a developer wondering
/// why a reminder never arrived.
@immutable
final class ReconciliationPlan {
  /// Creates a plan.
  const ReconciliationPlan({
    required this.toRegister,
    required this.toCancel,
    required this.retained,
    required this.unknown,
    required this.droppedRegions,
  });

  /// Registrations the platform does not have yet.
  final List<Registration> toRegister;

  /// Keys the platform holds that are no longer wanted.
  ///
  /// Excludes registrations whose instant has already passed: those have fired
  /// and the platform no longer holds them, so asking it to cancel them is a
  /// wasted call.
  final List<RegistrationKey> toCancel;

  /// Registrations that are already in place and should be left alone.
  final List<Registration> retained;

  /// Keys the platform holds that this library did not create.
  ///
  /// Reported rather than cancelled. An application scheduling its own
  /// notifications alongside `remind` must not have them removed.
  final Set<RegistrationKey> unknown;

  /// Regions that did not fit within the budget.
  ///
  /// Surfaced deliberately. A geofence that was silently dropped looks exactly
  /// like a geofence that does not work, and the application is the only thing
  /// that can decide what to do about it.
  final List<RegionRegistration> droppedRegions;

  /// Whether the platform is already in the desired state.
  bool get isEmpty => toRegister.isEmpty && toCancel.isEmpty;

  /// How many registrations the platform should hold once the plan is applied.
  int get desiredCount => toRegister.length + retained.length;

  @override
  String toString() => 'ReconciliationPlan(+${toRegister.length} '
      '-${toCancel.length} =${retained.length}'
      '${droppedRegions.isEmpty ? '' : ' dropped:${droppedRegions.length}'})';
}

/// Works out what to register and what to cancel, given a set of reminders and
/// what the platform is currently holding.
///
/// This is the piece that makes the platform ceilings survivable. Rather than
/// registering every occurrence of every reminder — hundreds, against an iOS
/// allowance of 64 — it registers a bounded window and expects to be run again
/// as that window is consumed: on launch, on resume, after a reboot, after a
/// time zone change, and whenever a reminder is edited.
@immutable
final class Reconciler {
  /// Creates a reconciler.
  const Reconciler({this.engine = const OccurrenceEngine()});

  /// The engine used to resolve time triggers into instants.
  final OccurrenceEngine engine;

  /// Computes the work needed to bring the platform in line with [reminders].
  ///
  /// [registered] is what the platform reports it currently holds. Keys this
  /// library did not create are returned in [ReconciliationPlan.unknown] and
  /// never cancelled.
  ///
  /// [deviceLocation], when known, orders region registrations by proximity so
  /// that the nearest ones survive a tight [SchedulingBudget.maxRegions].
  /// Without it, regions are taken in the order their reminders appear.
  ReconciliationPlan plan({
    required Iterable<Reminder> reminders,
    required Set<RegistrationKey> registered,
    required tz.Location zone,
    required tz.TZDateTime now,
    SchedulingBudget budget = const SchedulingBudget(),
    GeoCoordinate? deviceLocation,
  }) {
    final active = reminders.where((r) => r.enabled).toList(growable: false);

    final (regions, droppedRegions) = _selectRegions(
      active,
      budget: budget,
      deviceLocation: deviceLocation,
    );
    final timed = _selectTimed(active, zone: zone, now: now, budget: budget);

    final desired = <Registration>[...timed, ...regions];
    final desiredKeys = {for (final registration in desired) registration.key};

    final toRegister = <Registration>[];
    final retained = <Registration>[];
    for (final registration in desired) {
      if (registered.contains(registration.key)) {
        retained.add(registration);
      } else {
        toRegister.add(registration);
      }
    }

    final unknown = <RegistrationKey>{};
    final toCancel = <RegistrationKey>[];
    for (final key in registered) {
      if (!key.isOwned) {
        unknown.add(key);
        continue;
      }
      if (desiredKeys.contains(key)) continue;
      // An occurrence whose moment has passed already fired. The platform is
      // not holding it any more, so cancelling would be a wasted call.
      final scheduledFor = key.scheduledInstantUtc;
      if (scheduledFor != null && !scheduledFor.isAfter(now.toUtc())) continue;
      toCancel.add(key);
    }

    return ReconciliationPlan(
      toRegister: List.unmodifiable(toRegister),
      toCancel: List.unmodifiable(toCancel),
      retained: List.unmodifiable(retained),
      unknown: Set.unmodifiable(unknown),
      droppedRegions: List.unmodifiable(droppedRegions),
    );
  }

  /// Chooses which occurrences to register, fairly, within the budget.
  ///
  /// Selection is round-robin across reminders rather than simply the globally
  /// soonest N. Taking the soonest would let one frequent reminder consume the
  /// whole allowance and leave every other reminder completely silent — the
  /// user would see one working reminder and several broken ones, rather than
  /// all of them working a little less far ahead.
  List<TimedRegistration> _selectTimed(
    List<Reminder> reminders, {
    required tz.Location zone,
    required tz.TZDateTime now,
    required SchedulingBudget budget,
  }) {
    if (budget.maxTimed == 0) return const [];

    final horizonEnd = now.add(budget.horizon);
    final perReminder = <List<TimedRegistration>>[];
    for (final reminder in reminders) {
      final occurrences = engine.occurrencesOf(
        reminder,
        zone: zone,
        from: now,
        limit: budget.maxTimed,
        until: horizonEnd,
      );
      if (occurrences.isEmpty) continue;
      perReminder.add([
        for (final occurrence in occurrences)
          TimedRegistration(reminder: reminder, occurrence: occurrence),
      ]);
    }

    final selected = <TimedRegistration>[];
    for (var round = 0; selected.length < budget.maxTimed; round++) {
      var placedAny = false;
      for (final queue in perReminder) {
        if (round >= queue.length) continue;
        selected.add(queue[round]);
        placedAny = true;
        if (selected.length == budget.maxTimed) break;
      }
      if (!placedAny) break;
    }

    selected.sort(
      (a, b) => a.occurrence.instant.compareTo(b.occurrence.instant),
    );
    return selected;
  }

  /// Chooses which regions to monitor, nearest first when that is knowable.
  (List<RegionRegistration>, List<RegionRegistration>) _selectRegions(
    List<Reminder> reminders, {
    required SchedulingBudget budget,
    required GeoCoordinate? deviceLocation,
  }) {
    final candidates = <RegionRegistration>[];
    for (final reminder in reminders) {
      for (final trigger in reminder.locationTriggers) {
        candidates.add(
          RegionRegistration(
            reminder: reminder,
            region: trigger.region,
            event: trigger.event,
            dwellTime: trigger.dwellTime,
            pendingCondition: reminder.condition,
          ),
        );
      }
    }

    if (deviceLocation != null) {
      // A stable sort, so regions at equal distance keep their declared order.
      candidates.sort((a, b) {
        final byDistance = deviceLocation
            .distanceTo(a.region.center)
            .compareTo(deviceLocation.distanceTo(b.region.center));
        return byDistance;
      });
    }

    if (candidates.length <= budget.maxRegions) {
      return (candidates, const []);
    }
    return (
      candidates.sublist(0, budget.maxRegions),
      candidates.sublist(budget.maxRegions),
    );
  }
}
