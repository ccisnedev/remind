import 'dart:async';
import 'dart:convert';

import 'package:remind_core/remind_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ReminderStore] backed by `shared_preferences`.
///
/// Deliberately the simplest thing that survives a restart. A real application
/// would put this over whatever database it already has; the point here is that
/// `ReminderCodec` is all that is needed to do so, and that the reconciler
/// cannot tell the difference.
final class PrefsReminderStore implements ReminderStore {
  PrefsReminderStore._(this._prefs, this._reminders);

  /// Loads the store, reading whatever is already on disk.
  ///
  /// A reminder that fails to decode is dropped rather than taking the whole
  /// store down with it: one corrupt row should not cost the user every other
  /// reminder they have. What was dropped is reported in [loadFailures].
  static Future<PrefsReminderStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final reminders = <String, Reminder>{};
    final failures = <String>[];

    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final entries = jsonDecode(raw) as List<Object?>;
        for (final entry in entries) {
          try {
            final reminder =
                ReminderCodec.decode(entry! as Map<String, Object?>);
            reminders[reminder.id] = reminder;
          } on Object catch (error) {
            failures.add('$error');
          }
        }
      } on Object catch (error) {
        failures.add('$error');
      }
    }

    final store = PrefsReminderStore._(prefs, reminders);
    store.loadFailures.addAll(failures);
    return store;
  }

  static const String _key = 'remind_app.reminders.v1';

  final SharedPreferences _prefs;
  final Map<String, Reminder> _reminders;

  // The store is opened once at startup and lives as long as the process, so
  // there is no point at which closing this would be correct. `close()` exists
  // for tests.
  final _changes = StreamController<List<Reminder>>.broadcast();

  /// Anything that could not be decoded when the store was opened.
  final List<String> loadFailures = [];

  @override
  Future<List<Reminder>> all() async => _snapshot();

  @override
  Future<Reminder?> byId(String id) async => _reminders[id];

  @override
  Future<void> save(Reminder reminder) async {
    _reminders[reminder.id] = reminder;
    await _flush();
  }

  @override
  Future<void> delete(String id) async {
    _reminders.remove(id);
    await _flush();
  }

  @override
  Stream<List<Reminder>> watch() {
    late StreamController<List<Reminder>> controller;
    StreamSubscription<List<Reminder>>? subscription;
    controller = StreamController<List<Reminder>>(
      onListen: () {
        controller.add(_snapshot());
        subscription = _changes.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async => subscription?.cancel(),
      sync: true,
    );
    return controller.stream;
  }

  /// Releases the change stream.
  Future<void> close() => _changes.close();

  List<Reminder> _snapshot() => List.unmodifiable(_reminders.values);

  Future<void> _flush() async {
    await _prefs.setString(
      _key,
      jsonEncode(ReminderCodec.encodeAll(_reminders.values)),
    );
    if (!_changes.isClosed) _changes.add(_snapshot());
  }
}
