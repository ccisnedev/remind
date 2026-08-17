# Changelog

## 0.1.0

First release. The decision layer and its observability; the wiring into an
application is not yet exercised on a device.

### Added

- **`GeofenceBackend`** — a `ReminderBackend` that monitors regions. Accepts
  registrations carrying a condition, unlike a notification backend, because a
  crossing wakes application code before anything is shown. Budgets 16 regions,
  under the iOS ceiling of 20.
- **`CrossingEvaluator`** — decides whether a crossing should reach the user,
  treating the crossing as evidence about itself: entering or dwelling proves
  the device is inside that region, leaving proves it is outside. Necessary
  because iOS never reports the device location with a crossing and Android
  frequently omits it.
- **`CrossingOutcome`** — `Delivered`, `Suppressed` or `Undetermined`, each
  carrying the reminder, region, event, instant, the condition responsible and a
  readable explanation. The last two are distinct types deliberately: "did not
  hold" and "could not tell" are different answers.
- **`CrossingJournal`** and **`CrossingOutcomeCodec`** — where outcomes are kept
  and how they cross the isolate boundary. The only channel through which a
  crossing is observable at all.
- **`CrossingHandler`** — what a geofence callback calls. Matches fired regions
  to reminders by recomputing keys rather than parsing them, journals before
  attempting delivery, and never throws.
- **`NativeGeofenceScheduler`** — the adapter over `native_geofence`, with
  permission checking injected rather than owned.

### Deliberate limits

- **Delivery is not implemented here.** The package owns the decision and calls
  a `CrossingDelivery` you supply. Posting a notification would couple this to a
  notification backend.
- **Undetermined conditions stay quiet by default.** Configurable through
  `UndeterminedPolicy`, but the default respects a user who asked to be
  interrupted only somewhere specific.
- **Not verified on a device yet.** The logic is fully tested; the callback
  wiring, permissions and manifest belong to the host application and have not
  been exercised end to end.
