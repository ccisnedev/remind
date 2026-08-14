import 'dart:async';

import '../model/reminder.dart';

/// Where reminders live between runs of the application.
///
/// A port, not an implementation. The core keeps no opinion about databases:
/// an application already using Drift, Isar, Hive or a plain JSON file
/// implements this against what it has, and the reconciler works the same way
/// either side of that choice.
///
/// Implementations are expected to be safe to call concurrently and to make
/// [all] reflect every [save] and [delete] that has completed.
abstract interface class ReminderStore {
  /// Every reminder held, enabled or not.
  ///
  /// Disabled reminders are included: they still belong to the user, and the
  /// reconciler is what decides they produce no registrations.
  Future<List<Reminder>> all();

  /// The reminder with [id], or `null` if there is none.
  Future<Reminder?> byId(String id);

  /// Inserts [reminder], replacing any existing one with the same
  /// [Reminder.id].
  Future<void> save(Reminder reminder);

  /// Removes the reminder with [id]. Absent ids are not an error.
  Future<void> delete(String id);

  /// The contents of the store, emitted now and again on every change.
  ///
  /// Reminder interfaces are inherently reactive — a list the user edits while
  /// looking at it — so this is part of the port rather than something every
  /// application has to rebuild on top of it.
  Stream<List<Reminder>> watch();
}

/// A [ReminderStore] that keeps everything in memory.
///
/// Intended for tests, for examples, and for applications that persist by some
/// other route and only need somewhere to hold the working set. Nothing here
/// survives the process.
final class InMemoryReminderStore implements ReminderStore {
  /// Creates a store, optionally pre-populated with [initial].
  InMemoryReminderStore({Iterable<Reminder> initial = const []}) {
    for (final reminder in initial) {
      _reminders[reminder.id] = reminder;
    }
  }

  // Insertion-ordered, so `all()` is stable across calls. A store whose order
  // wobbled would make the reconciler's region selection wobble with it.
  final Map<String, Reminder> _reminders = {};
  final StreamController<List<Reminder>> _changes =
      StreamController<List<Reminder>>.broadcast();

  bool _closed = false;

  @override
  Future<List<Reminder>> all() async => _snapshot();

  @override
  Future<Reminder?> byId(String id) async => _reminders[id];

  @override
  Future<void> save(Reminder reminder) async {
    _reminders[reminder.id] = reminder;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _reminders.remove(id);
    _emit();
  }

  @override
  Stream<List<Reminder>> watch() {
    if (_closed) return const Stream.empty();

    late StreamController<List<Reminder>> controller;
    StreamSubscription<List<Reminder>>? subscription;
    controller = StreamController<List<Reminder>>(
      onListen: () {
        // Replay the current contents, so a listener does not have to wait for
        // the next edit to learn what is already there.
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

  /// Releases the change stream. The store is unusable afterwards.
  Future<void> close() async {
    _closed = true;
    await _changes.close();
  }

  List<Reminder> _snapshot() => List.unmodifiable(_reminders.values);

  void _emit() {
    if (_closed || _changes.isClosed) return;
    _changes.add(_snapshot());
  }
}
