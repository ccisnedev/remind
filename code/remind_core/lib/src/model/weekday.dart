/// A day of the week, numbered according to ISO-8601 (Monday = 1, Sunday = 7).
///
/// The numbering deliberately matches [DateTime.monday] … [DateTime.sunday] so
/// that [iso] can be compared directly against [DateTime.weekday] without any
/// conversion table.
enum Weekday {
  /// Monday — ISO day 1.
  monday(DateTime.monday),

  /// Tuesday — ISO day 2.
  tuesday(DateTime.tuesday),

  /// Wednesday — ISO day 3.
  wednesday(DateTime.wednesday),

  /// Thursday — ISO day 4.
  thursday(DateTime.thursday),

  /// Friday — ISO day 5.
  friday(DateTime.friday),

  /// Saturday — ISO day 6.
  saturday(DateTime.saturday),

  /// Sunday — ISO day 7.
  sunday(DateTime.sunday);

  const Weekday(this.iso);

  /// The ISO-8601 number of this day, from 1 (Monday) to 7 (Sunday).
  final int iso;

  /// Every day, Monday through Sunday.
  static const Set<Weekday> all = {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
  };

  /// Monday through Friday.
  static const Set<Weekday> workdays = {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
  };

  /// Saturday and Sunday.
  static const Set<Weekday> weekend = {saturday, sunday};

  /// The [Weekday] matching an ISO-8601 day number.
  ///
  /// Throws [ArgumentError] if [iso] is outside the range 1–7.
  static Weekday fromIso(int iso) => switch (iso) {
        DateTime.monday => monday,
        DateTime.tuesday => tuesday,
        DateTime.wednesday => wednesday,
        DateTime.thursday => thursday,
        DateTime.friday => friday,
        DateTime.saturday => saturday,
        DateTime.sunday => sunday,
        _ => throw ArgumentError.value(iso, 'iso', 'Must be between 1 and 7'),
      };

  /// The [Weekday] on which [dateTime] falls, in the zone of [dateTime].
  static Weekday of(DateTime dateTime) => fromIso(dateTime.weekday);
}
