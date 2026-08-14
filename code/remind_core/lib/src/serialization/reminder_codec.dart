import '../model/calendar_date.dart';
import '../model/condition.dart';
import '../model/geo.dart';
import '../model/local_time.dart';
import '../model/reminder.dart';
import '../model/trigger.dart';
import '../model/weekday.dart';

/// Thrown when a stored reminder cannot be read back.
///
/// Always thrown rather than returning a partially-built reminder: a reminder
/// that decoded *almost* correctly would schedule at the wrong time, which is
/// far worse than one that visibly failed to load.
final class ReminderCodecException implements Exception {
  /// Creates an exception describing what could not be decoded.
  const ReminderCodecException(this.message, {this.field});

  /// What went wrong.
  final String message;

  /// The field it went wrong in, when that is known.
  final String? field;

  @override
  String toString() => field == null
      ? 'ReminderCodecException: $message'
      : 'ReminderCodecException: $message (at "$field")';
}

/// Converts reminders to and from plain JSON-compatible maps.
///
/// The format lives here, in one place, rather than as `toJson` methods spread
/// across the model. Storage implementations, export files and any future
/// synchronisation all have to agree on it, and a single definition is the only
/// way that agreement survives a change.
///
/// The shape is deliberately readable — `"2026-03-08"` rather than an epoch
/// count, `[1, 3, 5]` for weekdays — because these end up in databases and
/// backup files that people eventually have to look at by hand.
abstract final class ReminderCodec {
  /// The version stamped into every encoded reminder.
  ///
  /// Present so that a future format change can be detected instead of
  /// misread. Decoding refuses anything newer than it understands.
  static const int version = 1;

  static const String _versionField = 'v';

  /// Encodes [reminder] as a JSON-compatible map.
  static Map<String, Object?> encode(Reminder reminder) => {
        _versionField: version,
        'id': reminder.id,
        'title': reminder.title,
        if (reminder.body != null) 'body': reminder.body,
        'enabled': reminder.enabled,
        'triggers': [
          for (final trigger in reminder.triggers) _encodeTrigger(trigger),
        ],
        if (reminder.condition != null)
          'condition': _encodeCondition(reminder.condition!),
        if (reminder.payload.isNotEmpty) 'payload': reminder.payload,
      };

  /// Encodes a list of reminders.
  static List<Map<String, Object?>> encodeAll(Iterable<Reminder> reminders) =>
      [for (final reminder in reminders) encode(reminder)];

  /// Decodes a reminder previously produced by [encode].
  ///
  /// Throws [ReminderCodecException] for anything malformed, unrecognised, or
  /// stamped with a newer [version] than this build understands.
  static Reminder decode(Map<String, Object?> json) {
    final storedVersion = json[_versionField];
    if (storedVersion != null) {
      if (storedVersion is! int) {
        throw const ReminderCodecException(
          'Version must be an integer',
          field: _versionField,
        );
      }
      if (storedVersion > version) {
        throw ReminderCodecException(
          'Encoded with format version $storedVersion, but this build '
          'understands at most $version',
          field: _versionField,
        );
      }
    }

    final triggers = _list(json, 'triggers');
    if (triggers.isEmpty) {
      throw const ReminderCodecException(
        'A reminder must have at least one trigger',
        field: 'triggers',
      );
    }

    final condition = json['condition'];
    final payload = json['payload'];

    return Reminder(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      body: json['body'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      triggers: [
        for (final trigger in triggers)
          _decodeTrigger(_map(trigger, 'trigger')),
      ],
      condition: condition == null
          ? null
          : _decodeCondition(_map(condition, 'condition')),
      payload: payload is Map<String, Object?> ? payload : const {},
    );
  }

  /// Decodes a list of reminders.
  static List<Reminder> decodeAll(List<Object?> json) =>
      [for (final entry in json) decode(_map(entry, 'reminder'))];

  // --- triggers ------------------------------------------------------------

  static Map<String, Object?> _encodeTrigger(Trigger trigger) =>
      switch (trigger) {
        OneShotTrigger(:final date, :final time) => {
            'type': 'one_shot',
            'date': date.toString(),
            'time': _encodeTime(time),
          },
        DailyTrigger(:final time, :final intervalDays, :final anchor) => {
            'type': 'daily',
            'time': _encodeTime(time),
            if (intervalDays != 1) 'interval_days': intervalDays,
            if (anchor != null) 'anchor': anchor.toString(),
          },
        WeeklyTrigger(:final days, :final time) => {
            'type': 'weekly',
            'days': _encodeWeekdays(days),
            'time': _encodeTime(time),
          },
        DateListTrigger(:final dates, :final time) => {
            'type': 'date_list',
            'dates': [
              for (final date in _sortedDates(dates)) date.toString(),
            ],
            'time': _encodeTime(time),
          },
        LocationTrigger(:final region, :final event, :final dwellTime) => {
            'type': 'location',
            'region': _encodeRegion(region),
            'event': event.name,
            if (dwellTime != null) 'dwell_seconds': dwellTime.inSeconds,
          },
      };

  static Trigger _decodeTrigger(Map<String, Object?> json) {
    final type = _string(json, 'type');
    return switch (type) {
      'one_shot' => OneShotTrigger(
          date: _date(json, 'date'),
          time: _time(json, 'time'),
        ),
      'daily' => DailyTrigger(
          time: _time(json, 'time'),
          intervalDays: json['interval_days'] as int? ?? 1,
          anchor: json['anchor'] == null ? null : _date(json, 'anchor'),
        ),
      'weekly' => WeeklyTrigger(
          days: _weekdays(json, 'days'),
          time: _time(json, 'time'),
        ),
      'date_list' => DateListTrigger(
          dates: {
            for (final entry in _list(json, 'dates'))
              _parseDate(entry, 'dates'),
          },
          time: _time(json, 'time'),
        ),
      'location' => LocationTrigger(
          region: _region(_map(json['region'], 'region')),
          event: _enum(GeoEvent.values, json, 'event'),
          dwellTime: json['dwell_seconds'] == null
              ? null
              : Duration(seconds: _int(json, 'dwell_seconds')),
        ),
      _ => throw ReminderCodecException(
          'Unknown trigger type "$type"',
          field: 'triggers',
        ),
    };
  }

  // --- conditions ----------------------------------------------------------

  static Map<String, Object?> _encodeCondition(Condition condition) =>
      switch (condition) {
        DateRangeCondition(:final from, :final until) => {
            'type': 'date_range',
            if (from != null) 'from': from.toString(),
            if (until != null) 'until': until.toString(),
          },
        ExcludedDatesCondition(:final dates) => {
            'type': 'excluded_dates',
            'dates': [
              for (final date in _sortedDates(dates)) date.toString(),
            ],
          },
        WeekdaysCondition(:final days) => {
            'type': 'weekdays',
            'days': _encodeWeekdays(days),
          },
        TimeRangeCondition(:final from, :final until) => {
            'type': 'time_range',
            'from': _encodeTime(from),
            'until': _encodeTime(until),
          },
        InsideRegionCondition(:final region) => {
            'type': 'inside_region',
            'region': _encodeRegion(region),
          },
        OutsideRegionCondition(:final region) => {
            'type': 'outside_region',
            'region': _encodeRegion(region),
          },
        AllOfCondition(:final conditions) => {
            'type': 'all_of',
            'conditions': [
              for (final child in conditions) _encodeCondition(child),
            ],
          },
        AnyOfCondition(:final conditions) => {
            'type': 'any_of',
            'conditions': [
              for (final child in conditions) _encodeCondition(child),
            ],
          },
        NotCondition(:final condition) => {
            'type': 'not',
            'condition': _encodeCondition(condition),
          },
      };

  static Condition _decodeCondition(Map<String, Object?> json) {
    final type = _string(json, 'type');
    return switch (type) {
      'date_range' => DateRangeCondition(
          from: json['from'] == null ? null : _date(json, 'from'),
          until: json['until'] == null ? null : _date(json, 'until'),
        ),
      'excluded_dates' => ExcludedDatesCondition({
          for (final entry in _list(json, 'dates')) _parseDate(entry, 'dates'),
        }),
      'weekdays' => WeekdaysCondition(_weekdays(json, 'days')),
      'time_range' => TimeRangeCondition(
          from: _time(json, 'from'),
          until: _time(json, 'until'),
        ),
      'inside_region' =>
        InsideRegionCondition(_region(_map(json['region'], 'region'))),
      'outside_region' =>
        OutsideRegionCondition(_region(_map(json['region'], 'region'))),
      'all_of' => AllOfCondition(_decodeConditions(json)),
      'any_of' => AnyOfCondition(_decodeConditions(json)),
      'not' => NotCondition(_decodeCondition(_map(json['condition'], 'not'))),
      _ => throw ReminderCodecException(
          'Unknown condition type "$type"',
          field: 'condition',
        ),
    };
  }

  static List<Condition> _decodeConditions(Map<String, Object?> json) => [
        for (final entry in _list(json, 'conditions'))
          _decodeCondition(_map(entry, 'conditions')),
      ];

  // --- value types ---------------------------------------------------------

  static String _encodeTime(LocalTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';

  static List<int> _encodeWeekdays(Set<Weekday> days) =>
      [for (final day in days) day.iso]..sort();

  static List<CalendarDate> _sortedDates(Set<CalendarDate> dates) =>
      dates.toList()..sort();

  static Map<String, Object?> _encodeRegion(GeoRegion region) => {
        'id': region.id,
        'lat': region.center.latitude,
        'lon': region.center.longitude,
        'radius_m': region.radiusMetres,
      };

  static GeoRegion _region(Map<String, Object?> json) => GeoRegion(
        id: _string(json, 'id'),
        center: GeoCoordinate(_double(json, 'lat'), _double(json, 'lon')),
        radiusMetres: _double(json, 'radius_m'),
      );

  // --- primitives ----------------------------------------------------------

  static String _string(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw ReminderCodecException(
        'Expected a string, found ${value.runtimeType}',
        field: field,
      );
    }
    return value;
  }

  static int _int(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! int) {
      throw ReminderCodecException(
        'Expected an integer, found ${value.runtimeType}',
        field: field,
      );
    }
    return value;
  }

  static double _double(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! num) {
      throw ReminderCodecException(
        'Expected a number, found ${value.runtimeType}',
        field: field,
      );
    }
    return value.toDouble();
  }

  static List<Object?> _list(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! List) {
      throw ReminderCodecException(
        'Expected a list, found ${value.runtimeType}',
        field: field,
      );
    }
    return value;
  }

  static Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map<String, Object?>) {
      throw ReminderCodecException(
        'Expected an object, found ${value.runtimeType}',
        field: field,
      );
    }
    return value;
  }

  static LocalTime _time(Map<String, Object?> json, String field) {
    final raw = _string(json, field);
    final parts = raw.split(':');
    if (parts.length < 2 || parts.length > 3) {
      throw ReminderCodecException('Malformed time "$raw"', field: field);
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (hour == null || minute == null || second == null) {
      throw ReminderCodecException('Malformed time "$raw"', field: field);
    }
    if (hour > 23 ||
        minute > 59 ||
        second > 59 ||
        hour < 0 ||
        minute < 0 ||
        second < 0) {
      throw ReminderCodecException('Time out of range "$raw"', field: field);
    }
    return LocalTime(hour, minute, second);
  }

  static CalendarDate _date(Map<String, Object?> json, String field) =>
      _parseDate(_string(json, field), field);

  static CalendarDate _parseDate(Object? raw, String field) {
    if (raw is! String) {
      throw ReminderCodecException(
        'Expected a date string, found ${raw.runtimeType}',
        field: field,
      );
    }
    final parts = raw.split('-');
    if (parts.length != 3) {
      throw ReminderCodecException('Malformed date "$raw"', field: field);
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      throw ReminderCodecException('Malformed date "$raw"', field: field);
    }
    return CalendarDate(year, month, day);
  }

  static Set<Weekday> _weekdays(Map<String, Object?> json, String field) {
    final values = _list(json, field);
    if (values.isEmpty) {
      throw ReminderCodecException('No weekdays given', field: field);
    }
    return {
      for (final value in values)
        if (value is int)
          _weekdayFrom(value, field)
        else
          throw ReminderCodecException(
            'Expected an ISO weekday number, found ${value.runtimeType}',
            field: field,
          ),
    };
  }

  static Weekday _weekdayFrom(int iso, String field) {
    try {
      return Weekday.fromIso(iso);
    } on ArgumentError {
      throw ReminderCodecException('Not an ISO weekday: $iso', field: field);
    }
  }

  static T _enum<T extends Enum>(
    List<T> values,
    Map<String, Object?> json,
    String field,
  ) {
    final name = _string(json, field);
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw ReminderCodecException('Unknown value "$name"', field: field);
  }
}

/// Adds [toJson] to [Reminder], delegating to [ReminderCodec].
///
/// An extension rather than a method on the class, so that the encoding lives
/// in one file and the model stays free of any opinion about storage.
extension ReminderJson on Reminder {
  /// This reminder as a JSON-compatible map.
  Map<String, Object?> toJson() => ReminderCodec.encode(this);
}
