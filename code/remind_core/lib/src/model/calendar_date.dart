import 'package:meta/meta.dart';

import 'local_time.dart';
import 'weekday.dart';

/// A date on the civil calendar, with no time and no time zone attached.
///
/// Like [LocalTime], this is not an instant. "3 March 2026" names a different
/// span of absolute time in Santiago than it does in Tokyo, and the engine only
/// resolves it once a zone is supplied.
///
/// All internal arithmetic runs in UTC so that it can never be perturbed by the
/// host's local daylight-saving rules — a real hazard in zones such as
/// `America/Santiago`, which has historically shifted the clocks at midnight.
@immutable
final class CalendarDate implements Comparable<CalendarDate> {
  /// Creates a calendar date.
  ///
  /// Out-of-range values are normalised the same way [DateTime] normalises
  /// them, so `CalendarDate(2026, 13, 1)` is January 2027 and
  /// `CalendarDate(2026, 3, 0)` is the last day of February 2026.
  factory CalendarDate(int year, int month, int day) {
    final normalised = DateTime.utc(year, month, day);
    return CalendarDate._(normalised.year, normalised.month, normalised.day);
  }

  const CalendarDate._(this.year, this.month, this.day);

  /// The calendar date that [dateTime] falls on, in the zone of [dateTime].
  factory CalendarDate.fromDateTime(DateTime dateTime) =>
      CalendarDate._(dateTime.year, dateTime.month, dateTime.day);

  /// The year, including the century.
  final int year;

  /// The month, from 1 (January) to 12 (December).
  final int month;

  /// The day of the month, starting at 1.
  final int day;

  /// The day of the week this date falls on.
  Weekday get weekday => Weekday.fromIso(_asUtc.weekday);

  DateTime get _asUtc => DateTime.utc(year, month, day);

  /// This date shifted by [days], which may be negative.
  CalendarDate addDays(int days) {
    final shifted = _asUtc.add(Duration(days: days));
    return CalendarDate._(shifted.year, shifted.month, shifted.day);
  }

  /// The number of whole days from this date to [other].
  ///
  /// Positive when [other] is later.
  int daysUntil(CalendarDate other) => other._asUtc.difference(_asUtc).inDays;

  @override
  int compareTo(CalendarDate other) => _asUtc.compareTo(other._asUtc);

  /// Whether this date falls strictly before [other].
  bool operator <(CalendarDate other) => compareTo(other) < 0;

  /// Whether this date falls before or on [other].
  bool operator <=(CalendarDate other) => compareTo(other) <= 0;

  /// Whether this date falls strictly after [other].
  bool operator >(CalendarDate other) => compareTo(other) > 0;

  /// Whether this date falls on or after [other].
  bool operator >=(CalendarDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// Formats as an ISO-8601 calendar date, `YYYY-MM-DD`.
  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
