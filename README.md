# remind

Embeddable reminder infrastructure for Flutter.

Set a reminder for a time, for selected days of the week, for a list of specific
dates, for arriving somewhere — or for a combination the platforms cannot
express on their own, like *"when I reach the office, but only on weekdays"*.

`remind` is not an alarm clock app. It is the layer underneath one: the part
every reminder feature has to get right and that almost every project rewrites
from scratch.

## Why

Flutter already has good packages for *delivering* an alarm — [`alarm`][alarm]
rings on both platforms, [`flutter_alarmkit`][alarmkit] wraps Apple's iOS 26
AlarmKit, [`flutter_local_notifications`][fln] is the standard for
notifications. What none of them own is the scheduling layer above:

- **Daylight saving drift.** Computing the next occurrence as
  `previous + Duration(days: 7)` adds 168 absolute hours. Cross a transition and
  the 07:00 alarm becomes an 06:00 alarm, permanently.
- **The iOS 64-notification ceiling.** iOS keeps only the 64 soonest pending
  notifications. Forty weekly reminders is 280 occurrences, so most are silently
  dropped. Someone has to register a sliding window and refresh it.
- **The 20-region ceiling.** iOS monitors at most 20 geofences per app, Android
  around 100. Beyond that, regions have to be swapped by proximity.
- **Mixed time-and-place rules.** No OS API combines them. The geofence goes to
  the platform and the rest has to be evaluated in your own code.
- **Reboots, timezone changes, and coming back from the background.** Everything
  has to be recomputed and re-registered, or reminders quietly stop arriving.

Those are scheduling problems, not platform problems — which is why the core
that solves them is plain Dart with no device in sight.

## Packages

| Package | What it does | Status |
|---|---|---|
| [`remind_core`](code/remind_core) | Model and occurrence engine. Pure Dart, no Flutter. | **0.1.0** |
| `remind_notifications` | Delivery via `flutter_local_notifications`. | Planned |
| `remind_alarm` | Delivery via `alarm` / AlarmKit, for reminders that must ring. | Planned |
| `remind_geofence` | Region monitoring on Android and iOS. | Planned |
| `remind` | Umbrella: core plus notification delivery, preconfigured. | Planned |

Adapters are separate packages on purpose. If geofencing lived in the main
package, the Android manifest merger would inject `ACCESS_BACKGROUND_LOCATION`
into every app that depends on it — and each of those apps would then have to
justify to Google Play a permission it never asked for.

## Design

```
        your app
            │
┌───────────▼────────────────────────────────────────┐
│  remind_core            pure Dart, no platform     │
│                                                    │
│  Trigger  ── generative (time) │ reactive (place)  │
│  Condition ── temporal (now)   │ ambient (at fire) │
│  OccurrenceEngine ── rules ──► instants            │
└───┬──────────────┬──────────────────┬──────────────┘
    │              │                  │
┌───▼──────────┐ ┌─▼────────────┐ ┌───▼─────────────┐
│_notifications│ │_alarm        │ │_geofence        │
│ FLN          │ │ alarm/       │ │ GeofencingClient│
│              │ │ AlarmKit     │ │ CLLocationMgr   │
└──────────────┘ └──────────────┘ └─────────────────┘
```

Two distinctions carry the design, and both are imposed by the operating systems
rather than chosen:

**Triggers are generative or reactive.** A time trigger can be enumerated — ask
it for its next ten occurrences and it will tell you. A location trigger cannot;
nobody can list the next ten times a user will walk into a building. The region
is registered with the OS and the OS calls back.

**Conditions are temporal or ambient.** A temporal condition is a function of a
moment, so the engine resolves it while enumerating and drops the occurrences
that fail. An ambient condition needs device state that does not exist yet, so
it travels with the occurrence and is evaluated when it fires.

See [`docs/architecture.md`](docs/architecture.md) for the reasoning in full.

## Repository layout

The root stays clean; everything buildable lives under `code/`, and each
directory there is **self-contained** — its own manifest, lints, licence and
tests, movable into a repository of its own without editing a line. There is no
pub workspace and no shared configuration to inherit, which also means `code/`
is free to hold things that are not Dart packages.

```
remind/
├── code/
│   ├── remind_core/      the engine
│   └── app/              demo surface
└── docs/
    ├── architecture.md   decision record
    ├── roadmap.md
    └── adr/
```

Work on a package from inside it:

```sh
cd code/remind_core
dart pub get
dart test
```

## Status

Early. `remind_core` has a complete, tested model and occurrence engine;
reconciliation and every delivery adapter are still to come. The API may shift
before 1.0.

## Licence

MIT

[alarm]: https://pub.dev/packages/alarm
[alarmkit]: https://pub.dev/packages/flutter_alarmkit
[fln]: https://pub.dev/packages/flutter_local_notifications
