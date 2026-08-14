import 'package:flutter/material.dart';
import 'package:remind_core/remind_core.dart';

/// Formatting that follows the device, not the library.
///
/// `remind_core` renders times as `HH:mm` and dates as `YYYY-MM-DD` because
/// those are unambiguous ISO forms meant for logs, storage and debugging. They
/// are the wrong thing to show a person: on a phone set to a 12-hour clock,
/// `01:19` reads as one in the afternoon to anyone not looking carefully, and
/// that is exactly how an a.m./p.m. mistake survives all the way to a reminder
/// that never arrives.
///
/// Everything the user reads goes through here.

/// A time of day in the device's own format — `1:19 p. m.` or `13:19`
/// depending on the phone's clock setting and locale.
String formatTime(BuildContext context, LocalTime time) =>
    TimeOfDay(hour: time.hour, minute: time.minute).format(context);

/// A date in the device's locale, such as `15 ago 2026`.
String formatDate(BuildContext context, CalendarDate date) =>
    MaterialLocalizations.of(
      context,
    ).formatMediumDate(DateTime(date.year, date.month, date.day));

/// A full instant — date and time — in the device's locale.
String formatInstant(BuildContext context, DateTime instant) {
  final localisations = MaterialLocalizations.of(context);
  final date = localisations.formatMediumDate(instant);
  final time = TimeOfDay.fromDateTime(instant).format(context);
  return '$date, $time';
}

/// A full instant with its UTC offset appended.
///
/// The offset is what makes a daylight-saving shift legible: the wall clock
/// stays put while the offset moves. Used where that matters — diagnostics and
/// the list of upcoming occurrences — and left off elsewhere.
String formatInstantWithOffset(BuildContext context, DateTime instant) {
  final offset = instant.timeZoneOffset;
  final sign = offset.isNegative ? '−' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${formatInstant(context, instant)}  UTC$sign$hours:$minutes';
}

/// A one-line summary of what makes a reminder fire.
String describeTriggers(BuildContext context, Reminder reminder) =>
    reminder.triggers.map((t) => describeTrigger(context, t)).join(' · ');

/// A one-line summary of a single trigger.
String describeTrigger(BuildContext context, Trigger trigger) =>
    switch (trigger) {
      OneShotTrigger(:final date, :final time) =>
        'Once on ${formatDate(context, date)} at ${formatTime(context, time)}',
      DailyTrigger(:final time, :final intervalDays) =>
        intervalDays == 1
            ? 'Every day at ${formatTime(context, time)}'
            : 'Every $intervalDays days at ${formatTime(context, time)}',
      WeeklyTrigger(:final days, :final time) =>
        '${describeWeekdays(context, days)} at ${formatTime(context, time)}',
      DateListTrigger(:final dates, :final time) =>
        '${dates.length} dates at ${formatTime(context, time)}',
      LocationTrigger(:final region, :final event) =>
        'On ${event.name} of ${region.id}',
    };

/// Names a set of weekdays the way a person would say it.
String describeWeekdays(BuildContext context, Set<Weekday> days) {
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.containsAll(Weekday.workdays)) return 'Weekdays';
  if (days.length == 2 && days.containsAll(Weekday.weekend)) return 'Weekends';

  final names = MaterialLocalizations.of(context).narrowWeekdays;
  final sorted = days.toList()..sort((a, b) => a.iso.compareTo(b.iso));
  // `narrowWeekdays` is indexed from the locale's first day of the week, so
  // ISO numbering has to be mapped through it rather than used directly.
  return sorted.map((day) => names[day.iso % 7]).join(', ');
}

/// Explains a daylight-saving anomaly in words.
String describeAnomaly(DstAnomaly anomaly) => switch (anomaly) {
  DstAnomaly.gapShifted =>
    'This wall-clock time does not exist on that date — the clocks jump over '
        'it. Shifted forward.',
  DstAnomaly.ambiguousResolvedEarly =>
    'This wall-clock time happens twice on that date. Resolved to the first.',
};
