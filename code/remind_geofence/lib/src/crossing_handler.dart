import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'crossing.dart';
import 'crossing_evaluator.dart';
import 'crossing_journal.dart';
import 'crossing_outcome.dart';

/// Shows a crossing to the user.
///
/// Supplied by the application rather than implemented here. This package owns
/// the *decision* — whether a crossing should reach anyone — but deliberately
/// not the *mechanism*. Posting a notification would mean depending on a
/// notification backend, which would tie two packages together that are
/// otherwise independent and force every consumer of one to take the other.
typedef CrossingDelivery = Future<void> Function(Crossing crossing);

/// What handling a batch of crossings produced.
@immutable
final class CrossingReport {
  /// Creates a report.
  const CrossingReport({
    required this.outcomes,
    required this.unmatched,
    required this.deliveryFailures,
  });

  /// One outcome per crossing that belonged to a known reminder.
  final List<CrossingOutcome> outcomes;

  /// Region identifiers that matched no reminder.
  ///
  /// Left behind by a reminder that was deleted while its geofence was still
  /// registered. The next reconcile removes them.
  final List<String> unmatched;

  /// Anything thrown by the delivery function.
  final List<Object> deliveryFailures;

  /// Whether everything was handled cleanly.
  bool get isClean => unmatched.isEmpty && deliveryFailures.isEmpty;

  @override
  String toString() => 'CrossingReport(${outcomes.length} outcomes'
      '${unmatched.isEmpty ? '' : ', ${unmatched.length} unmatched'}'
      '${deliveryFailures.isEmpty ? '' : ', ${deliveryFailures.length} failed'})';
}

/// Turns a reported boundary crossing into a decision, a journal entry and,
/// when warranted, a notification.
///
/// This is what a geofence callback should call. It is written as plain,
/// injectable logic rather than as something that reaches for globals, because
/// the callback that invokes it runs in a **background isolate**: a separate
/// Dart heap with no access to the application's memory. Nothing there can see
/// the store the UI is using, the runtime it built, or any singleton it
/// registered. Everything has to be handed in, having been rebuilt from
/// storage by the callback itself.
///
/// The order of operations is deliberate. The outcome is journalled **before**
/// delivery is attempted, because the decision is a fact whether or not showing
/// it succeeds — and because a delivery that throws must not erase the only
/// record that the crossing ever happened.
@immutable
final class CrossingHandler {
  /// Creates a handler.
  const CrossingHandler({
    required this.store,
    required this.journal,
    required this.deliver,
    this.evaluator = const CrossingEvaluator(),
  });

  /// Where reminders are read from.
  final ReminderStore store;

  /// Where outcomes are written.
  final CrossingJournal journal;

  /// How a crossing is shown to the user.
  final CrossingDelivery deliver;

  /// How the decision is made.
  final CrossingEvaluator evaluator;

  /// Handles every region the platform says was crossed.
  ///
  /// [firedRegionIds] are the identifiers the platform reports, which are
  /// registration keys in string form. [at] should be the moment of the
  /// crossing in [zone]; it is a parameter rather than read from the clock so
  /// that this is testable and so that a delayed callback can be handled with
  /// the time it actually refers to.
  ///
  /// [deviceLocation] is whatever the platform supplied, which is often
  /// nothing: iOS never reports it and Android frequently omits it. Its absence
  /// is not a problem for the common case, since the crossing is itself
  /// evidence about the region that fired.
  ///
  /// Never throws. An exception escaping here would kill the background isolate
  /// and take every other crossing in the same batch with it.
  Future<CrossingReport> handle({
    required Set<String> firedRegionIds,
    required GeoEvent event,
    required tz.Location zone,
    required tz.TZDateTime at,
    GeoCoordinate? deviceLocation,
  }) async {
    final reminders = await store.all();
    final byRegionKey = _indexByRegionKey(reminders);

    final outcomes = <CrossingOutcome>[];
    final unmatched = <String>[];
    final failures = <Object>[];

    for (final id in firedRegionIds) {
      final match = byRegionKey[id];
      if (match == null) {
        unmatched.add(id);
        continue;
      }

      final crossing = Crossing(
        reminder: match.reminder,
        region: match.trigger.region,
        event: event,
        at: at,
        deviceLocation: deviceLocation,
        pendingCondition: match.reminder.condition,
      );

      final outcome = evaluator.evaluate(crossing);
      outcomes.add(outcome);
      await journal.record(outcome);

      if (!outcome.shouldNotify) continue;
      try {
        await deliver(crossing);
      } on Object catch (error) {
        failures.add(error);
      }
    }

    return CrossingReport(
      outcomes: List.unmodifiable(outcomes),
      unmatched: List.unmodifiable(unmatched),
      deliveryFailures: List.unmodifiable(failures),
    );
  }

  /// Indexes every reminder's region triggers by the key they were registered
  /// under.
  ///
  /// Keys are recomputed and compared rather than parsed. A key contains the
  /// reminder's id, and ids are chosen by the host application — they may
  /// contain colons, or anything else that would make splitting the string
  /// wrong. Rebuilding the key is exact by construction.
  Map<String, _RegionMatch> _indexByRegionKey(List<Reminder> reminders) => {
        for (final reminder in reminders)
          for (final trigger in reminder.locationTriggers)
            RegistrationKey.forRegion(
              reminderId: reminder.id,
              region: trigger.region,
              event: trigger.event,
            ).value: _RegionMatch(reminder, trigger),
      };
}

@immutable
final class _RegionMatch {
  const _RegionMatch(this.reminder, this.trigger);

  final Reminder reminder;
  final LocationTrigger trigger;
}
