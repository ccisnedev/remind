import 'package:remind_core/remind_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'crossing_outcome.dart';

/// Where crossing outcomes are kept so somebody can read them later.
///
/// This is not a logging convenience. It is the **only channel** through which
/// a crossing can be observed at all: the callback that handles one runs in a
/// background isolate with no access to the application's memory and no return
/// value, and a suppressed crossing shows nothing to the user by definition.
/// Whatever is not written here did not happen as far as anyone can tell.
///
/// It is also what makes conjunctive reminders honest. A reminder gated on both
/// a place and a condition can be working perfectly and still stay silent; the
/// journal is what lets an application answer "you were there on Saturday, and
/// this only fires on weekdays" instead of leaving the user to guess whether
/// the geofence is broken.
abstract interface class CrossingJournal {
  /// Records what happened, whether or not the user was told.
  Future<void> record(CrossingOutcome outcome);

  /// The most recent outcomes, newest first.
  ///
  /// Optionally narrowed to one reminder, which is the question a user actually
  /// asks: "why didn't *this* one go off?"
  Future<List<CrossingOutcome>> recent({int limit = 50, String? reminderId});

  /// Forgets everything.
  Future<void> clear();
}

/// A [CrossingJournal] held in memory.
///
/// Useful in tests and in the foreground. It is **not** suitable as the real
/// journal for geofencing: the crossing callback runs in a separate isolate, so
/// anything it records here is invisible to the application and dies with the
/// isolate. A real deployment needs a journal backed by storage both isolates
/// can see, which is what [CrossingOutcomeCodec] exists to make easy.
final class InMemoryCrossingJournal implements CrossingJournal {
  /// Creates a journal holding at most [capacity] entries.
  InMemoryCrossingJournal({this.capacity = 200});

  /// How many outcomes to keep before discarding the oldest.
  ///
  /// Bounded because an application may go a long time without being opened,
  /// and an unbounded journal would be a slow leak. Old entries are the ones
  /// nobody is asking about.
  final int capacity;

  final List<CrossingOutcome> _entries = [];

  @override
  Future<void> record(CrossingOutcome outcome) async {
    _entries.insert(0, outcome);
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
  }

  @override
  Future<List<CrossingOutcome>> recent({
    int limit = 50,
    String? reminderId,
  }) async {
    final matching = reminderId == null
        ? _entries
        : _entries.where((e) => e.reminderId == reminderId).toList();
    return List.unmodifiable(matching.take(limit));
  }

  @override
  Future<void> clear() async => _entries.clear();
}

/// Converts crossing outcomes to and from JSON-compatible maps.
///
/// Needed because the journal has to cross an isolate boundary through storage.
/// Kept beside the journal rather than on the outcome types so that the model
/// stays free of any opinion about persistence, matching how `ReminderCodec`
/// is arranged in `remind_core`.
abstract final class CrossingOutcomeCodec {
  /// Encodes [outcome] as a JSON-compatible map.
  static Map<String, Object?> encode(CrossingOutcome outcome) => {
        'kind': switch (outcome) {
          Delivered() => _delivered,
          Suppressed() => _suppressed,
          Undetermined() => _undetermined,
        },
        'reminder': outcome.reminderId,
        'region': _encodeRegion(outcome.region),
        'event': outcome.event.name,
        'at': outcome.at.toUtc().microsecondsSinceEpoch,
        if (outcome is Suppressed) ...{
          'reason': outcome.reason,
          if (outcome.condition != null)
            'condition': _encodeCondition(outcome.condition!),
        },
        if (outcome is Undetermined) ...{
          'reason': outcome.reason,
          'notified': outcome.notified,
          'condition': _encodeCondition(outcome.condition),
        },
      };

  /// Reads an outcome back, in [zone].
  ///
  /// Returns `null` for anything unreadable rather than throwing. The journal
  /// is written from a background isolate and read by a diagnostics screen that
  /// exists precisely for when something is wrong; one corrupt entry must not
  /// take that screen down.
  static CrossingOutcome? decode(Map<String, Object?> json, tz.Location zone) {
    try {
      final kind = json['kind'];
      final reminderId = json['reminder'];
      final micros = json['at'];
      final eventName = json['event'];
      final region = json['region'];
      if (kind is! String ||
          reminderId is! String ||
          micros is! int ||
          eventName is! String ||
          region is! Map<String, Object?>) {
        return null;
      }

      final event =
          GeoEvent.values.where((e) => e.name == eventName).firstOrNull;
      final decodedRegion = _decodeRegion(region);
      if (event == null || decodedRegion == null) return null;

      final at = tz.TZDateTime.from(
        DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
        zone,
      );

      return switch (kind) {
        _delivered => Delivered(
            reminderId: reminderId,
            region: decodedRegion,
            event: event,
            at: at,
          ),
        _suppressed => Suppressed(
            reminderId: reminderId,
            region: decodedRegion,
            event: event,
            at: at,
            reason: json['reason'] as String? ?? '',
            condition: _decodeCondition(json['condition']),
          ),
        _undetermined => () {
            final condition = _decodeCondition(json['condition']);
            if (condition == null) return null;
            return Undetermined(
              reminderId: reminderId,
              region: decodedRegion,
              event: event,
              at: at,
              condition: condition,
              notified: json['notified'] as bool? ?? false,
              reason: json['reason'] as String? ?? '',
            );
          }(),
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  static const String _delivered = 'delivered';
  static const String _suppressed = 'suppressed';
  static const String _undetermined = 'undetermined';

  static Map<String, Object?> _encodeRegion(GeoRegion region) => {
        'id': region.id,
        'lat': region.center.latitude,
        'lon': region.center.longitude,
        'radius_m': region.radiusMetres,
      };

  static GeoRegion? _decodeRegion(Map<String, Object?> json) {
    final id = json['id'];
    final lat = json['lat'];
    final lon = json['lon'];
    final radius = json['radius_m'];
    if (id is! String || lat is! num || lon is! num || radius is! num) {
      return null;
    }
    return GeoRegion(
      id: id,
      center: GeoCoordinate(lat.toDouble(), lon.toDouble()),
      radiusMetres: radius.toDouble(),
    );
  }

  /// Conditions ride along inside a reminder, so their encoding already exists
  /// in `remind_core`. Reaching it means wrapping the condition in a throwaway
  /// reminder, which is cheap and keeps exactly one definition of the format.
  static Map<String, Object?> _encodeCondition(Condition condition) =>
      ReminderCodec.encode(
        Reminder(
          id: '_',
          title: '_',
          triggers: [const DailyTrigger(time: LocalTime(0, 0))],
          condition: condition,
        ),
      )['condition']! as Map<String, Object?>;

  static Condition? _decodeCondition(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      return ReminderCodec.decode({
        'v': ReminderCodec.version,
        'id': '_',
        'title': '_',
        'triggers': [
          {'type': 'daily', 'time': '00:00:00'},
        ],
        'condition': json,
      }).condition;
    } on Object {
      return null;
    }
  }
}
