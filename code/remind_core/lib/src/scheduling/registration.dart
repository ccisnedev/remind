import 'package:meta/meta.dart';

import '../model/condition.dart';
import '../model/geo.dart';
import '../model/occurrence.dart';
import '../model/reminder.dart';

/// The identity of one thing registered with the operating system.
///
/// Keys are **derived**, not allocated. Given the same reminder and the same
/// instant, the key is always the same string, which is what lets the
/// reconciler compare what it wants against what the platform already holds
/// without keeping a ledger of its own. A ledger would be one more thing to
/// lose on reinstall, corrupt on crash, and drift out of sync.
///
/// Every key this library owns starts with `remind:`. Anything else found
/// registered on the platform belongs to somebody else — the host application's
/// own notifications, another library — and is reported rather than cancelled.
@immutable
final class RegistrationKey {
  /// Wraps an existing key string, such as one read back from the platform.
  const RegistrationKey.raw(this.value);

  /// The key for a scheduled occurrence.
  factory RegistrationKey.forOccurrence(Occurrence occurrence) =>
      RegistrationKey.raw(
        '$_prefix$_timed:${occurrence.reminderId}:'
        '${occurrence.instant.toUtc().microsecondsSinceEpoch}',
      );

  /// The key for a monitored region.
  factory RegistrationKey.forRegion({
    required String reminderId,
    required GeoRegion region,
    required GeoEvent event,
  }) =>
      RegistrationKey.raw(
        '$_prefix$_region:$reminderId:${region.id}:${event.name}',
      );

  static const String _prefix = 'remind:';
  static const String _timed = 't';
  static const String _region = 'r';

  /// The key in its string form, as it should be stored on the platform.
  final String value;

  /// Whether this library created the key.
  ///
  /// Foreign keys are left strictly alone: an application scheduling its own
  /// notifications alongside `remind` must not have them cancelled from
  /// underneath it.
  bool get isOwned => value.startsWith(_prefix);

  /// Whether the key names a scheduled instant rather than a region.
  bool get isTimed => value.startsWith('$_prefix$_timed:');

  /// The instant this key was scheduled for, if it is a timed key.
  ///
  /// Recoverable from the key alone, which is what lets the reconciler tell an
  /// occurrence that has already fired from one still pending — and so avoid
  /// asking the platform to cancel something it no longer holds.
  DateTime? get scheduledInstantUtc {
    if (!isTimed) return null;
    final micros = int.tryParse(value.split(':').last);
    if (micros == null) return null;
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  }

  /// A stable non-negative 31-bit identifier derived from [value].
  ///
  /// Both platforms key notifications and alarms by 32-bit integer, so the
  /// string has to survive being squeezed into one. This is an FNV-1a hash
  /// masked to 31 bits to keep it non-negative.
  ///
  /// Collisions are possible in principle. At the scale these platforms allow —
  /// tens of pending registrations against a space of 2^31 — the probability is
  /// on the order of one in a million, and a collision costs one overwritten
  /// registration rather than corruption. Backends that can key by string
  /// should prefer [value].
  int get platformId {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is RegistrationKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// One unit of work handed to a platform backend.
@immutable
sealed class Registration {
  const Registration();

  /// The reminder this registration serves.
  Reminder get reminder;

  /// Its derived identity.
  RegistrationKey get key;

  /// The condition that must still be checked when this registration fires.
  ///
  /// `null` when nothing is outstanding and the platform can deliver on its
  /// own.
  Condition? get pendingCondition;

  /// Shorthand for `reminder.id`.
  String get reminderId => reminder.id;
}

/// A reminder scheduled to fire at a specific instant.
@immutable
final class TimedRegistration extends Registration {
  /// Creates a timed registration.
  const TimedRegistration({required this.reminder, required this.occurrence});

  @override
  final Reminder reminder;

  /// The resolved instant, carrying its trigger and any DST anomaly.
  final Occurrence occurrence;

  @override
  RegistrationKey get key => RegistrationKey.forOccurrence(occurrence);

  @override
  Condition? get pendingCondition => occurrence.pendingCondition;

  @override
  bool operator ==(Object other) =>
      other is TimedRegistration &&
      other.reminder == reminder &&
      other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(reminder, occurrence);

  @override
  String toString() => 'TimedRegistration($reminderId @ ${occurrence.instant})';
}

/// A region the platform should watch on the reminder's behalf.
@immutable
final class RegionRegistration extends Registration {
  /// Creates a region registration.
  const RegionRegistration({
    required this.reminder,
    required this.region,
    required this.event,
    this.dwellTime,
    this.pendingCondition,
  });

  @override
  final Reminder reminder;

  /// The area being watched.
  final GeoRegion region;

  /// The boundary crossing that fires it.
  final GeoEvent event;

  /// How long the device must remain inside for a [GeoEvent.dwell].
  final Duration? dwellTime;

  @override
  final Condition? pendingCondition;

  @override
  RegistrationKey get key => RegistrationKey.forRegion(
        reminderId: reminder.id,
        region: region,
        event: event,
      );

  @override
  bool operator ==(Object other) =>
      other is RegionRegistration &&
      other.reminder == reminder &&
      other.region == region &&
      other.event == event &&
      other.dwellTime == dwellTime &&
      other.pendingCondition == pendingCondition;

  @override
  int get hashCode =>
      Object.hash(reminder, region, event, dwellTime, pendingCondition);

  @override
  String toString() =>
      'RegionRegistration($reminderId, ${event.name} ${region.id})';
}
