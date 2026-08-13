import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'condition.dart';
import 'trigger.dart';

/// A single thing the user wants to be reminded of, and the rules that decide
/// when they are reminded of it.
///
/// A reminder carries a list of [triggers] combined with OR semantics — it
/// fires when *any* of them fires — narrowed by an optional [condition] that
/// must hold at the moment of firing. That shape covers the cases users
/// actually ask for without inventing a boolean algebra over triggers:
///
/// ```dart
/// // Weekdays at 07:00, but not on holidays.
/// Reminder(
///   id: 'standup',
///   title: 'Daily standup',
///   triggers: [WeeklyTrigger(days: Weekday.workdays, time: LocalTime(7, 0))],
///   condition: ExcludedDatesCondition(holidays),
/// );
///
/// // On arriving at the supermarket, but only at a civilised hour.
/// Reminder(
///   id: 'groceries',
///   title: 'Buy milk',
///   triggers: [LocationTrigger(region: supermarket, event: GeoEvent.enter)],
///   condition: TimeRangeCondition(
///     from: LocalTime(8, 0),
///     until: LocalTime(22, 0),
///   ),
/// );
/// ```
@immutable
final class Reminder {
  /// Creates a reminder.
  ///
  /// [triggers] must not be empty; a reminder that can never fire is a bug in
  /// the calling code rather than a meaningful state.
  Reminder({
    required this.id,
    required this.title,
    required List<Trigger> triggers,
    this.body,
    this.condition,
    this.enabled = true,
    Map<String, Object?> payload = const {},
  })  : assert(triggers.isNotEmpty, 'triggers must not be empty'),
        triggers = List.unmodifiable(triggers),
        payload = Map.unmodifiable(payload);

  /// A stable identifier, chosen by the calling application.
  ///
  /// It is the key the reconciler uses to correlate this reminder with the
  /// registrations the operating system is holding, so it must survive process
  /// restarts and must not be reused for a different reminder.
  final String id;

  /// The headline shown to the user when the reminder fires.
  final String title;

  /// Optional supporting text shown beneath [title].
  final String? body;

  /// The triggers that can fire this reminder, combined with OR.
  final List<Trigger> triggers;

  /// An optional gate that must hold for a fired trigger to reach the user.
  final Condition? condition;

  /// Whether the reminder is currently active.
  ///
  /// A disabled reminder produces no occurrences and holds no platform
  /// registrations, but is kept in storage so the user can switch it back on
  /// without reconstructing it.
  final bool enabled;

  /// Arbitrary application data carried alongside the reminder.
  ///
  /// Round-tripped through storage and handed back when the reminder fires, so
  /// the host application can route it — an entity id, a deep link, a category.
  /// The core never inspects it.
  final Map<String, Object?> payload;

  /// The subset of [triggers] whose occurrences can be enumerated ahead of
  /// time.
  Iterable<TimeTrigger> get timeTriggers => triggers.whereType<TimeTrigger>();

  /// The subset of [triggers] that the platform must watch for.
  Iterable<LocationTrigger> get locationTriggers =>
      triggers.whereType<LocationTrigger>();

  /// Returns a copy of this reminder with the given fields replaced.
  ///
  /// Passing `null` leaves a field unchanged. To clear [body] or [condition],
  /// construct a new [Reminder] directly.
  Reminder copyWith({
    String? id,
    String? title,
    String? body,
    List<Trigger>? triggers,
    Condition? condition,
    bool? enabled,
    Map<String, Object?>? payload,
  }) =>
      Reminder(
        id: id ?? this.id,
        title: title ?? this.title,
        body: body ?? this.body,
        triggers: triggers ?? this.triggers,
        condition: condition ?? this.condition,
        enabled: enabled ?? this.enabled,
        payload: payload ?? this.payload,
      );

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      const ListEquality<Trigger>().equals(other.triggers, triggers) &&
      other.condition == condition &&
      other.enabled == enabled &&
      const MapEquality<String, Object?>().equals(other.payload, payload);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        body,
        const ListEquality<Trigger>().hash(triggers),
        condition,
        enabled,
        const MapEquality<String, Object?>().hash(payload),
      );

  @override
  String toString() => 'Reminder($id, "$title", ${triggers.length} trigger(s)'
      '${enabled ? '' : ', disabled'})';
}
