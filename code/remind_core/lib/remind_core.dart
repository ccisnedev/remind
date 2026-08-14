/// The scheduling brain of the `remind` ecosystem.
///
/// This package models what a reminder *is* and works out *when* it is due. It
/// has no Flutter dependency and touches no platform API, which is what lets
/// the hard parts — recurrence, time zones, daylight saving, the three-valued
/// logic around unknown device state — be tested exhaustively without a device.
///
/// Delivering a reminder is somebody else's job. Companion packages adapt this
/// core onto local notifications, native alarms and geofences.
///
/// ```dart
/// import 'package:remind_core/remind_core.dart';
/// import 'package:timezone/data/latest.dart' as tzdata;
/// import 'package:timezone/timezone.dart' as tz;
///
/// void main() {
///   tzdata.initializeTimeZones();
///   final zone = tz.getLocation('America/Santiago');
///
///   final reminder = Reminder(
///     id: 'gym',
///     title: 'Gym',
///     triggers: [
///       WeeklyTrigger(
///         days: {Weekday.monday, Weekday.wednesday, Weekday.friday},
///         time: const LocalTime(7, 0),
///       ),
///     ],
///   );
///
///   const engine = OccurrenceEngine();
///   final upcoming = engine.occurrencesOf(
///     reminder,
///     zone: zone,
///     from: tz.TZDateTime.now(zone),
///     limit: 5,
///   );
///   upcoming.forEach(print);
/// }
/// ```
library;

export 'src/engine/condition_evaluator.dart'
    show
        ConditionOutcome,
        ConditionPartition,
        EvaluationContext,
        evaluateCondition,
        isPurelyTemporal,
        partitionCondition;
export 'src/engine/occurrence_engine.dart' show DstGapPolicy, OccurrenceEngine;
export 'src/model/calendar_date.dart' show CalendarDate;
export 'src/model/condition.dart'
    show
        AllOfCondition,
        AmbientCondition,
        AnyOfCondition,
        Condition,
        DateRangeCondition,
        ExcludedDatesCondition,
        InsideRegionCondition,
        NotCondition,
        OutsideRegionCondition,
        TemporalCondition,
        TimeRangeCondition,
        WeekdaysCondition;
export 'src/model/geo.dart' show GeoCoordinate, GeoEvent, GeoRegion;
export 'src/model/local_time.dart' show LocalTime;
export 'src/model/occurrence.dart' show DstAnomaly, Occurrence;
export 'src/model/reminder.dart' show Reminder;
export 'src/model/trigger.dart'
    show
        DailyTrigger,
        DateListTrigger,
        LocationTrigger,
        OneShotTrigger,
        TimeTrigger,
        Trigger,
        WeeklyTrigger;
export 'src/model/weekday.dart' show Weekday;
export 'src/ports/reminder_backend.dart' show ReminderBackend;
export 'src/ports/reminder_store.dart'
    show InMemoryReminderStore, ReminderStore;
export 'src/scheduling/reconciler.dart' show ReconciliationPlan, Reconciler;
export 'src/scheduling/registration.dart'
    show RegionRegistration, Registration, RegistrationKey, TimedRegistration;
export 'src/scheduling/scheduling_budget.dart' show SchedulingBudget;
