/// Delivers [`remind_core`](https://pub.dev/packages/remind_core) reminders
/// when the device enters, leaves or dwells in a region.
///
/// Unlike a notification backend, this one **can evaluate a condition before
/// deciding to notify**, because a region crossing wakes application code
/// before anything is shown to the user. It therefore accepts registrations
/// that still carry a condition, and posts its own notification once it has
/// decided.
///
/// Every crossing produces a `CrossingOutcome`, including the ones that reach
/// nobody. A reminder gated on both a place and a condition can work perfectly
/// and still stay silent, and a user cannot tell that apart from a geofence
/// that never fired — so silence is recorded and explained rather than left to
/// be guessed at.
///
/// This package requires background location permission, which Google Play
/// grants only after a manual review including a video demonstration. An
/// application that needs date-and-time reminders should depend on
/// `remind_notifications` alone and never link this.
library;

export 'src/crossing.dart' show Crossing;
export 'src/crossing_evaluator.dart' show CrossingEvaluator, UndeterminedPolicy;
export 'src/crossing_handler.dart'
    show CrossingDelivery, CrossingHandler, CrossingReport;
export 'src/crossing_journal.dart'
    show CrossingJournal, CrossingOutcomeCodec, InMemoryCrossingJournal;
export 'src/crossing_outcome.dart'
    show CrossingOutcome, Delivered, Suppressed, Undetermined;
export 'src/geofence_backend.dart' show GeofenceBackend;
export 'src/monitored_region.dart' show GeofenceScheduler, MonitoredRegion;
export 'src/native_geofence_scheduler.dart'
    show GeofenceCrossingCallback, NativeGeofenceScheduler;
