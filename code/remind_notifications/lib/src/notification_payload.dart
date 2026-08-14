import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:remind_core/remind_core.dart';

/// What travels with a notification so that it can be identified when it comes
/// back.
///
/// The platform reports a pending notification as an integer id, a title, a
/// body and a payload string — and the integer is a lossy hash of the
/// registration key, not the key itself. The payload is therefore the only
/// place the key can survive, and reconstructing the platform's actual state
/// depends entirely on it.
///
/// It also carries the reminder's own [Reminder.payload] through to delivery,
/// so that an application tapping a notification can route on it without
/// another database read.
@immutable
final class NotificationPayload {
  /// Creates a payload.
  const NotificationPayload({
    required this.key,
    required this.reminderId,
    this.data = const {},
  });

  /// Reads a payload back from its encoded form.
  ///
  /// Returns `null` for anything that is not one of ours — absent, empty,
  /// malformed, or simply a payload some other part of the application wrote.
  /// Never throws: a foreign notification is an ordinary thing to encounter,
  /// not an error, and the caller treats `null` as "leave it alone".
  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (parsed is! Map<String, Object?>) return null;

    final key = parsed[_keyField];
    final reminderId = parsed[_reminderField];
    if (key is! String || reminderId is! String) return null;
    if (!RegistrationKey.raw(key).isOwned) return null;

    final data = parsed[_dataField];
    return NotificationPayload(
      key: RegistrationKey.raw(key),
      reminderId: reminderId,
      data: data is Map<String, Object?> ? Map.unmodifiable(data) : const {},
    );
  }

  static const String _keyField = 'k';
  static const String _reminderField = 'r';
  static const String _dataField = 'd';

  /// The registration this notification belongs to.
  final RegistrationKey key;

  /// The reminder it came from.
  final String reminderId;

  /// The host application's own data, carried through untouched.
  final Map<String, Object?> data;

  /// Encodes for storage on the platform.
  String encode() => jsonEncode({
        _keyField: key.value,
        _reminderField: reminderId,
        if (data.isNotEmpty) _dataField: data,
      });

  @override
  bool operator ==(Object other) =>
      other is NotificationPayload &&
      other.key == key &&
      other.reminderId == reminderId &&
      _sameData(other.data, data);

  static bool _sameData(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(key, reminderId, data.length);

  @override
  String toString() => 'NotificationPayload($reminderId, $key)';
}
