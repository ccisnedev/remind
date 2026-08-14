# Changelog

## 0.1.0

First release.

### Added

- **`NotificationBackend`** — a `ReminderBackend` that delivers timed
  registrations as local notifications.
- **`NotificationScheduler`** — a four-method interface over
  `flutter_local_notifications`, so the backend's behaviour can be tested with a
  fake instead of a device.
- **`FlutterLocalNotificationsScheduler`** — the real implementation.
- **`NotificationPayload`** — carries the registration key and the reminder's
  own payload through the platform, since the platform reports only an integer
  id and a payload string and the integer is a lossy hash.

### Deliberate limits

- **No location.** No permission is declared or requested, and `maxRegions` is
  reported as 0. Applications needing only date-and-time reminders depend on
  this package alone.
- **Registrations with an outstanding condition are refused.** A scheduled local
  notification is displayed without running application code first — on iOS the
  service extension that could intercept it fires only for remote push — so
  there is no moment at which an ambient condition could be evaluated. Only
  ambient conditions are affected; time-based ones are resolved before
  scheduling.
- **Android defaults to inexact scheduling.** Exact alarms require
  `SCHEDULE_EXACT_ALARM`, denied by default on Android 14 and restricted by
  Google Play to clock, alarm and calendar applications. Opt in via
  `androidScheduleMode` if your application qualifies.
- **iOS availability is assumed.** iOS grants or refuses notification permission
  during initialisation and offers no equivalent query, so `isAvailable` reports
  `true` there. Check with the plugin's own permission API if you need certainty.
