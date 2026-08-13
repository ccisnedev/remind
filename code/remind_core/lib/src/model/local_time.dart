import 'package:meta/meta.dart';

/// A wall-clock time of day, with no date and no time zone attached.
///
/// This is deliberately *not* an instant. `07:00` means "whatever moment the
/// clock on the wall reads 07:00", which is the thing users actually configure
/// when they set an alarm. Turning it into an instant requires a calendar date
/// and a time zone, and that resolution is the job of the occurrence engine.
///
/// The distinction matters across daylight-saving transitions: an alarm set for
/// `07:00` should keep ringing at `07:00` after the clocks move, not one hour
/// earlier or later.
@immutable
final class LocalTime implements Comparable<LocalTime> {
  /// Creates a time of day.
  ///
  /// [hour] must be in 0–23, [minute] and [second] in 0–59.
  const LocalTime(this.hour, this.minute, [this.second = 0])
      : assert(hour >= 0 && hour <= 23, 'hour must be in 0..23'),
        assert(minute >= 0 && minute <= 59, 'minute must be in 0..59'),
        assert(second >= 0 && second <= 59, 'second must be in 0..59');

  /// The wall-clock time that [dateTime] reads in its own zone.
  factory LocalTime.fromDateTime(DateTime dateTime) =>
      LocalTime(dateTime.hour, dateTime.minute, dateTime.second);

  /// Midnight, `00:00:00`.
  static const LocalTime midnight = LocalTime(0, 0);

  /// Midday, `12:00:00`.
  static const LocalTime noon = LocalTime(12, 0);

  /// The hour, from 0 to 23.
  final int hour;

  /// The minute, from 0 to 59.
  final int minute;

  /// The second, from 0 to 59.
  final int second;

  /// How many seconds past midnight this time falls.
  ///
  /// Useful as a total ordering key. Note that it is *not* a duration since
  /// midnight on a DST transition day, where the day is 23 or 25 hours long.
  int get secondsSinceMidnight => hour * 3600 + minute * 60 + second;

  @override
  int compareTo(LocalTime other) =>
      secondsSinceMidnight.compareTo(other.secondsSinceMidnight);

  /// Whether this time is strictly earlier in the day than [other].
  bool operator <(LocalTime other) => compareTo(other) < 0;

  /// Whether this time is earlier than or the same as [other].
  bool operator <=(LocalTime other) => compareTo(other) <= 0;

  /// Whether this time is strictly later in the day than [other].
  bool operator >(LocalTime other) => compareTo(other) > 0;

  /// Whether this time is later than or the same as [other].
  bool operator >=(LocalTime other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is LocalTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);

  /// Formats as `HH:mm`, or `HH:mm:ss` when [second] is non-zero.
  @override
  String toString() {
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    if (second == 0) return '$hh:$mm';
    return '$hh:$mm:${second.toString().padLeft(2, '0')}';
  }
}
