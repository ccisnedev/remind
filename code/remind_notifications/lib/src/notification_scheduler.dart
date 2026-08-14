import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

/// One notification handed to the platform.
@immutable
final class ScheduledNotification {
  /// Creates a notification to be scheduled.
  const ScheduledNotification({
    required this.id,
    required this.title,
    required this.when,
    required this.payload,
    this.body,
  });

  /// The platform's integer identifier, derived from a `RegistrationKey`.
  final int id;

  /// The headline shown to the user.
  final String title;

  /// Optional supporting text.
  final String? body;

  /// The instant the notification should be delivered, carrying its zone.
  final tz.TZDateTime when;

  /// The encoded payload, which carries the registration key home again.
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is ScheduledNotification &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.when == when &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, title, body, when, payload);

  @override
  String toString() => 'ScheduledNotification($id, "$title" @ $when)';
}

/// A notification the platform says it is still holding.
@immutable
final class PendingNotification {
  /// Creates a record of a pending notification.
  const PendingNotification({required this.id, this.payload});

  /// The platform's integer identifier.
  final int id;

  /// The payload it was scheduled with, if any.
  ///
  /// The only place a registration key can be recovered from: the platform
  /// reports ids, titles, bodies and payloads, and nothing else.
  final String? payload;

  @override
  bool operator ==(Object other) =>
      other is PendingNotification &&
      other.id == id &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, payload);

  @override
  String toString() => 'PendingNotification($id)';
}

/// The narrow slice of a notification plugin that this package actually uses.
///
/// `flutter_local_notifications` has a large, platform-bound surface, and a
/// backend written directly against it could only be tested on a device. Four
/// methods is all the backend needs, and behind an interface they can be faked,
/// which is what lets the scheduling behaviour be tested without a running
/// engine.
///
/// `FlutterLocalNotificationsScheduler` is the real implementation.
abstract interface class NotificationScheduler {
  /// Whether the user has allowed notifications.
  Future<bool> areNotificationsEnabled();

  /// Schedules [notification], replacing any existing one with the same id.
  Future<void> schedule(ScheduledNotification notification);

  /// Cancels the notification with [id]. Absent ids are not an error.
  Future<void> cancel(int id);

  /// Everything the platform is currently holding for this application.
  Future<List<PendingNotification>> pending();
}
