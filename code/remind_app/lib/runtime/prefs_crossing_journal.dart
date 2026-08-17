import 'dart:convert';

import 'package:remind_geofence/remind_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// A [CrossingJournal] backed by `shared_preferences`.
///
/// Persistent because it has to be: the crossing callback runs in a background
/// isolate with its own heap, so anything it records in memory is invisible to
/// the application and dies when the isolate does. Storage is the only thing
/// both sides can see.
///
/// Nothing is cached in memory here for the same reason. Each read goes back to
/// the platform, because the other isolate may have written since — an
/// in-memory cache would make the UI show a journal that was already stale the
/// moment it was loaded.
final class PrefsCrossingJournal implements CrossingJournal {
  PrefsCrossingJournal._(this._zone, this.capacity);

  /// Opens the journal.
  ///
  /// [zone] is needed to read instants back: the stored form is UTC
  /// microseconds, which is unambiguous, and the zone is what turns it into
  /// something a person recognises.
  static Future<PrefsCrossingJournal> open(
    tz.Location zone, {
    int capacity = 200,
  }) async => PrefsCrossingJournal._(zone, capacity);

  static const String _key = 'remind_app.crossings.v1';

  final tz.Location _zone;

  /// How many outcomes to keep before discarding the oldest.
  final int capacity;

  @override
  Future<void> record(CrossingOutcome outcome) async {
    final prefs = await _prefs();
    final entries = prefs.getStringList(_key) ?? const <String>[];
    final updated = [
      jsonEncode(CrossingOutcomeCodec.encode(outcome)),
      ...entries,
    ];
    await prefs.setStringList(
      _key,
      updated.length > capacity ? updated.sublist(0, capacity) : updated,
    );
  }

  @override
  Future<List<CrossingOutcome>> recent({
    int limit = 50,
    String? reminderId,
  }) async {
    final prefs = await _prefs();
    final raw = prefs.getStringList(_key) ?? const <String>[];

    final outcomes = <CrossingOutcome>[];
    for (final entry in raw) {
      // A single unreadable row must not take the diagnostics screen down.
      // That screen exists for when things are already wrong.
      final decoded = _decode(entry);
      if (decoded == null) continue;
      if (reminderId != null && decoded.reminderId != reminderId) continue;
      outcomes.add(decoded);
      if (outcomes.length == limit) break;
    }
    return List.unmodifiable(outcomes);
  }

  @override
  Future<void> clear() async => (await _prefs()).remove(_key);

  CrossingOutcome? _decode(String entry) {
    try {
      return CrossingOutcomeCodec.decode(
        jsonDecode(entry) as Map<String, Object?>,
        _zone,
      );
    } on Object {
      return null;
    }
  }

  /// Always a fresh read, never a cached instance.
  ///
  /// `SharedPreferences` keeps an in-memory copy per isolate, so a handle held
  /// across a write from the other isolate would go stale silently.
  Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }
}
