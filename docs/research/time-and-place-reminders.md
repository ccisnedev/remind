# Prior Art for Reminders That Combine Time and Place

## Abstract

This report investigates how shipping products, platform APIs and the
context-aware computing literature model reminders triggered by *time*, by
*location*, or by both, in order to inform the design of `remind_geofence` and
its coordination with `remind_notifications`.

The central finding is that **no widely-used product composes time and location
into a single conjunctive rule** [@apple2024eventkit; @todoist2026location].
Both are offered, but as alternatives. The `Trigger` / `Condition` split already
implemented in `remind_core` is therefore not a reimplementation of an existing
product model — it is a design position, and one with support in the
event-condition-action literature rather than in shipping software
[@wikipedia2024eca].

The second finding materially affects the coordination design. Both platforms
offer *two distinct paths* from a region crossing to a notification: one where
the operating system owns the whole flow and application code never runs, and
one where application code is woken and decides. Only the second can evaluate a
condition [@kodeco2021locationnotifications; @android2026geofencing]. This is
the same distinction that forced `NotificationBackend` to refuse conditional
registrations, and it resolves in `remind_geofence`'s favour — provided the
implementation deliberately chooses the callback path.

## Research Question

What prior art exists for reminder systems that combine temporal and spatial
triggers, and what does it imply for the architecture of a geofence delivery
backend that must evaluate conditions before notifying?

## Scope and Constraints

**In scope.** Data models of shipping reminder products; the Apple and Android
platform APIs for region monitoring and location-triggered notifications; hard
platform limits and their documented workarounds; the event-condition-action
literature; Google Play and Apple permission policy as of August 2026.

**Out of scope.** Continuous background location tracking and trip detection;
indoor positioning and beacons; server-side geofencing; commercial location SDKs
except where they document platform limits; polygon geofences.

**Constraints.** Apple's current documentation site renders client-side and
could not be retrieved directly; Apple claims are therefore taken from its
archived Location Awareness Programming Guide and corroborated by independent
sources. This is flagged in Limitations.

**Success criteria.** Each of the six sub-questions has evidence from at least
one authoritative source; platform limits are stated as concrete numbers; source
disagreements are surfaced rather than averaged.

## Method (Staged Protocol)

Five stages, in order: problem framing; source discovery across platform
documentation, product help centres, policy pages, specialist vendors and
academic summaries; triage by authority and recency; extraction of concrete
claims with attribution; synthesis with explicit confidence levels.

## Findings by Stage

### Stage 1 - Problem Framing

The question decomposes into three genuinely different problems that are easy to
conflate:

1. **A modelling question.** Is "when I arrive at the office, but only on
   weekdays" expressible at all in existing models?
2. **A delivery question.** When a region is crossed, does application code get
   the chance to decide whether to notify?
3. **A capacity question.** How many regions can be watched, and what happens to
   the rest?

The delivery question turns out to be the one that constrains architecture most,
and it is the least discussed in the product literature.

### Stage 2 - Source Discovery

Candidates gathered across five origins: platform documentation (Apple archived
Core Location guide; Android Geofencing API), product documentation (Todoist
help centre), policy (Google Play Console help and its April 2026 announcement),
specialist vendors (Radar), and reference material on ECA rules. Open source
repositories were surveyed for architectural prior art.

### Stage 3 - Source Triage

**Retained.** Apple's archived Region Monitoring guide, as the only primary
Apple source that could be retrieved in full [@apple2024regionmonitoring].
Android's Geofencing API documentation, which is current and unusually specific
about latency and accuracy [@android2026geofencing]. Todoist's help article as a
primary statement of a shipping product's model [@todoist2026location]. Google
Play's location policy pages [@google2026locationpolicy;
@google2020backgroundlocation]. Radar's analysis, retained because a company
selling a geofencing product has both expertise and an obvious incentive to
describe platform limits accurately [@radar2024ioslimits].

**Dropped.** Tutorial blog posts duplicating platform documentation without
adding measurements. Open source reminder apps found in Stage 2 were examined
and dropped as architectural prior art: each implements a single trigger family,
and none exhibits a composition mechanism worth studying. Commercial SDK
marketing claims were used only where they concern documented platform
behaviour.

### Stage 4 - Evidence Extraction

#### 4.1 How shipping products model it

Apple's EventKit is the most structured model available. An `EKReminder` holds
`EKAlarm` objects, and an alarm is *either* absolute, *or* relative to a due
date, *or* location-based via `structuredLocation` with an `EKAlarmProximity` of
enter or leave. One trigger kind per alarm [@apple2024eventkit]. Multiple alarms
may be attached to one reminder, but they combine **disjunctively** — each fires
independently. There is no conjunction operator.

Todoist's documentation describes location reminders as an independent feature:
an address plus arrival or departure. It "doesn't describe combining location
triggers with time conditions" and treats the two as separate features
[@todoist2026location]. Location reminders are additionally gated behind paid
tiers and exist only on mobile.

Microsoft To Do has no location reminders at all; the feature remains an open
user request [@microsoft2024feature].

**Fact:** no product surveyed expresses "arrive at X *and* it is a weekday" as a
single rule.

**Interpretation:** this is likely a deliberate product simplification rather
than an oversight. Conjunctive rules are hard to explain in a UI and hard to
debug when they do not fire — a user cannot tell whether the geofence failed or
the condition excluded it. Any design adopting conjunction inherits that
explainability burden.

#### 4.2 The coordination problem

Both platforms expose two paths, and the difference between them is precisely
whether application code runs.

**iOS path A — `UNLocationNotificationTrigger`.** The notification content and
the region are declared together and handed to `UNUserNotificationCenter`; iOS
"handles the monitoring" and delivers a fixed notification on entry. Use it
"when all you need is to show a fixed notification on entry"
[@kodeco2021locationnotifications]. No application code runs, so no condition
can be evaluated.

**iOS path B — Core Location region monitoring.** The app monitors regions
itself, and "when `didEnterRegion` fires, you schedule a local notification (or
do anything else you need)". Use it "when entry needs to trigger additional work
beyond displaying a notification" [@kodeco2021locationnotifications]. Critically,
"regions associated with your app are tracked at all times, including when the
app isn't running. If a region boundary is crossed while an app isn't running,
that app is relaunched into the background to handle the event"
[@apple2024regionmonitoring].

**Android.** The Geofencing API has only path B. A transition delivers
`GEOFENCE_TRANSITION_ENTER`, `_EXIT` or `_DWELL` to the application's own
receiver, which then decides what to do [@android2026geofencing].

**Fact:** on both platforms, the region-monitoring path wakes application code
before anything is shown to the user.

**Interpretation:** this is the exact inverse of the scheduled-local-notification
case that forced `NotificationBackend` to refuse conditional registrations. A
geofence backend *can* evaluate a condition and stay silent. The architectural
consequence is that such a backend must post the notification itself, rather
than delegating to a notification backend — because by the time it knows the
condition holds, it is already inside the callback.

#### 4.3 Established terminology

The event-condition-action pattern is long-established in active databases and
event-driven architecture: "the event part specifies the signal that triggers the
rule, the condition part is a logical test that causes the action if satisfied,
and the action part consists of updates or invocations" [@wikipedia2024eca]. The
same structure recurs in context-aware computing, where "the ECA pattern provides
a high-level structure that helps in the design of context-aware applications"
[@researchgate2011eca].

**Fact:** `Trigger` / `Condition` / action maps one-to-one onto event / condition
/ action.

**Interpretation:** the vocabulary already exists and is decades old. Adopting it
in documentation would connect the design to established literature at no cost.
The generative-versus-reactive distinction, however, has no standard name in that
literature; its closest analogue is the active-database separation between
*temporal* events, which are computable in advance, and *primitive external*
events, which are not.

#### 4.4 Platform capacity limits

| Constraint | iOS | Android |
|---|---|---|
| Regions monitored | **20 per app** [@apple2024regionmonitoring] | **100 per app, per device user** [@android2026geofencing] |
| Survives app termination | Yes — app is relaunched [@apple2024regionmonitoring] | Yes |
| Survives device reboot | Yes | **No** — must re-register on boot [@android2026geofencing] |
| Dwell support | Not native | `GEOFENCE_TRANSITION_DWELL` with `setLoiteringDelay` [@android2026geofencing] |
| Recommended minimum radius | ~200 m for testing [@apple2024regionmonitoring] | 100–150 m [@android2026geofencing] |
| Typical latency | Exit events "might not be instantly triggered" [@radar2024ioslimits] | <2 min typical; 2–3 min under background limits; **up to 6 min when stationary** [@android2026geofencing] |
| Accuracy | Degraded "in urban environments with tall buildings" [@radar2024ioslimits] | 20–50 m with Wi-Fi; hundreds of metres to kilometres without [@android2026geofencing] |

Apple documents the workaround for exceeding 20 explicitly: "consider registering
only those regions in the user's immediate vicinity. As the user's location
changes, you can remove regions that are now farther away and add regions coming
up on the user's path" [@apple2024regionmonitoring]. Exceeding the limit is not
silent on iOS — it fails through
`locationManager:monitoringDidFailForRegion:withError:` with
`kCLErrorRegionMonitoringFailure` [@apple2024regionmonitoring].

Android documents a hierarchical variant: "an app wants to track a large number
of retailer options, the app may want to register large geofence (at the city
level) and dynamically register smaller geofences for stores within the larger
geofence" [@android2026geofencing].

**Source disagreement.** One secondary source asserts the iOS limit is "across
all apps on the device — not just your app". Apple's own guide says "20 the
number of regions that may be simultaneously monitored by a single app"
[@apple2024regionmonitoring], and Radar independently describes it as "a per-app
restriction, not system-wide" [@radar2024ioslimits]. Two sources including the
primary agree on per-app; the outlier is treated as mistaken. Apple's guide does
separately note that regions are "a shared system resource" whose total is
limited system-wide, which plausibly explains the confusion.

#### 4.5 Permission and policy reality

Background location is gated behind a manual review. The Play Console "notifies
developers to complete a permissions declaration form that must answer two
questions and include a link to a video demonstration", and the video must
demonstrate the background feature "as core functionality"
[@google2020backgroundlocation]. Without approval, "app updates may be blocked
and the app may be removed from Google Play" [@google2020backgroundlocation].

A policy update effective 15 April 2026 introduces "the location button as the
recommended minimum scope for precise location", with at least 30 days to comply
[@google2026locationpolicy]. This does not directly change background location
rules but signals continued tightening.

On iOS, background region monitoring requires "Always Allow" authorization
[@radar2024ioslimits].

**Fact:** background location approval is discretionary, manual, and revocable.

**Not found:** no authoritative figure for what fraction of users grant
background location, nor for Play declaration approval rates. Vendor blog posts
cite numbers without methodology and were not retained.

### Stage 5 - Synthesis and Limits

| Conclusion | Confidence | Rationale |
|---|---|---|
| No shipping product ANDs time and location | **High** | Primary sources for EventKit and Todoist; no counterexample found |
| The region-monitoring path runs app code before notifying, on both platforms | **High** | Android documentation is explicit; iOS corroborated by two sources |
| A geofence backend must post its own notification | **High** | Follows directly from the above |
| iOS 20 regions is per-app | **High** | Primary source plus independent corroboration; one dissenting secondary source |
| Android requires boot re-registration, iOS does not | **High** | Both stated in primary documentation |
| ECA is the correct established vocabulary | **Medium** | Structural match is clear; no source applies it specifically to reminders |
| Geofence latency makes sub-minute precision unattainable | **High** | Android publishes concrete figures up to 6 minutes |
| Background location approval rates | **Unknown** | No credible source found |

## Discussion

Three consequences follow for `remind_geofence`.

**The condition can be evaluated, but only on one of the two paths.** The
temptation is to reach for `UNLocationNotificationTrigger` on iOS, since it is
simpler and the OS does the work. That choice would silently reintroduce the
exact limitation that `NotificationBackend` already documents: no application
code runs, so no condition can be checked. The design must commit to the
region-monitoring path on both platforms. `native_geofence` uses a Dart
background isolate callback, which is that path.

**This forces an asymmetry between the two backends, and the asymmetry is real
rather than accidental.** `NotificationBackend` refuses conditional
registrations because it cannot evaluate them; `remind_geofence` accepts them
because it can, and consequently must own the act of notifying. Two backends,
opposite postures, both correct — and the reason is a platform fact, not a
preference. Documenting it that way is worth more than making them look
symmetric.

**The capacity design already in `remind_core` is validated by Apple's own
advice.** `Reconciler` prioritises regions by proximity to the device and reports
what it dropped; Apple recommends exactly "registering only those regions in the
user's immediate vicinity" and removing distant ones as the user moves
[@apple2024regionmonitoring]. The existing `SchedulingBudget.maxRegions` default
of 16 sits below the iOS ceiling of 20 with headroom, which is the right side to
err on given that regions are a shared system resource.

Two things the current model does not yet handle. Android does not restore
geofences after a reboot [@android2026geofencing], which means a region backend
needs a boot hook that a notification backend does not — the reconciler's
existing "reconcile after boot" rule covers it, but only if something actually
runs at boot. And dwell is native on Android but absent on iOS, so
`GeoEvent.dwell` will need emulation on one platform, exactly as the
`LocationTrigger` documentation already anticipates.

Finally, a product observation that sits uncomfortably beside the engineering.
Every surveyed product declined to offer conjunctive rules. The most likely
reason is explainability: when a conjunctive reminder does not fire, the user
cannot distinguish a geofence that failed from a condition that excluded it. If
`remind` keeps conjunction as its differentiator, it inherits an obligation to
make non-firing legible — which the existing `ReconciliationPlan` and
three-valued `ConditionOutcome` are unusually well placed to satisfy, and which
should probably become an explicit design goal rather than a happy accident.

## Conclusion

The `Trigger` / `Condition` split has no equivalent in shipping reminder
products, and matches the established event-condition-action pattern rather than
any product model. It is defensible, but it is a bet, and the bet is on
explainability.

`remind_geofence` should be built on region monitoring rather than
OS-managed location notifications, must post its own notifications after
evaluating conditions, needs a boot hook on Android, and must emulate dwell on
iOS. The 20-region iOS ceiling, not the 100-region Android one, is the binding
constraint, and the existing proximity-prioritised reconciler already implements
the workaround Apple itself recommends.

The dominant risk is not technical. Background location is gated behind a manual,
discretionary, revocable review whose approval rate is undocumented — which
argues for `remind_geofence` remaining strictly optional, and for the
notification-only configuration continuing to be a first-class supported path.

## Limitations

- **Apple's current documentation could not be retrieved.** `developer.apple.com`
  renders client-side and returned only page titles for
  `UNLocationNotificationTrigger` and the current region-monitoring page. Apple
  claims here rest on the archived Location Awareness Programming Guide, which
  predates `CLMonitor` (iOS 17+) and `CLCircularGeographicCondition`. Those newer
  APIs appeared in search results with an apparently identical 20-condition
  limit, but this could not be confirmed from a primary source and should be
  verified before implementation.
- **No measured data on user grant rates** for background location, nor on Play
  declaration approval rates. Claims about "most users decline" are widely
  repeated but were not traceable to methodology and are excluded.
- **Product models were inferred from user-facing documentation**, not from APIs,
  except for EventKit. Todoist and Google Keep may support conjunction internally
  without exposing it.
- **Latency figures are Android's own published estimates**, not independent
  measurement. No comparable published figures exist for iOS.
- **Open source survey was shallow.** Repositories were assessed from
  descriptions and READMEs rather than by reading their scheduling code; a
  deeper reading might surface prior art this report missed.

## References

```bibtex
@misc{apple2024regionmonitoring,
  title        = {Region Monitoring and iBeacon --- Location and Maps Programming Guide},
  author       = {{Apple Inc.}},
  year         = {2024},
  howpublished = {Apple Developer Documentation Archive},
  url          = {https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html},
  note         = {Accessed: 2026-08-14. Archived guide; predates CLMonitor}
}
```

```bibtex
@misc{android2026geofencing,
  title        = {Create and monitor geofences},
  author       = {{Google LLC}},
  year         = {2026},
  howpublished = {Android Developers documentation},
  url          = {https://developer.android.com/develop/sensors-and-location/location/geofencing},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{apple2024eventkit,
  title        = {EventKit alarms: absolute, relative and location-based triggers},
  author       = {{Apple Inc.}},
  year         = {2024},
  howpublished = {EventKit documentation and community summaries},
  url          = {https://littlebitesofcocoa.com/97-eventkit-alarms},
  note         = {Accessed: 2026-08-14. EKAlarm, EKStructuredLocation, EKAlarmProximity}
}
```

```bibtex
@misc{todoist2026location,
  title        = {Use location reminders in Todoist},
  author       = {{Doist}},
  year         = {2026},
  howpublished = {Todoist Help Center},
  url          = {https://www.todoist.com/help/articles/use-location-reminders-in-todoist-uGcwH2AJ6},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{microsoft2024feature,
  title        = {Feature request: location based reminders},
  author       = {{Microsoft Tech Community}},
  year         = {2024},
  howpublished = {Microsoft Community Hub discussion},
  url          = {https://techcommunity.microsoft.com/discussions/to-doinsiders_android/feature-request-location-based-reminders/401454},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{kodeco2021locationnotifications,
  title        = {Location Notifications with UNLocationNotificationTrigger},
  author       = {{Kodeco}},
  year         = {2021},
  url          = {https://www.kodeco.com/20690666-location-notifications-with-unlocationnotificationtrigger},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{radar2024ioslimits,
  title        = {Geofencing iOS: Understanding the limitations},
  author       = {{Radar Labs, Inc.}},
  year         = {2024},
  url          = {https://radar.com/blog/limitations-of-ios-geofencing},
  note         = {Accessed: 2026-08-14. Vendor source; corroborates platform limits}
}
```

```bibtex
@misc{google2020backgroundlocation,
  title        = {Understanding location in the background permissions},
  author       = {{Google LLC}},
  year         = {2020},
  howpublished = {Play Console Help},
  url          = {https://support.google.com/googleplay/android-developer/answer/9799150},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{google2026locationpolicy,
  title        = {Policy announcement: April 15, 2026 --- Location Permissions},
  author       = {{Google LLC}},
  year         = {2026},
  howpublished = {Play Console Help},
  url          = {https://support.google.com/googleplay/android-developer/answer/16926792},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@misc{wikipedia2024eca,
  title        = {Event condition action},
  author       = {{Wikipedia contributors}},
  year         = {2024},
  howpublished = {Wikipedia},
  url          = {https://en.wikipedia.org/wiki/Event_condition_action},
  note         = {Accessed: 2026-08-14}
}
```

```bibtex
@article{researchgate2011eca,
  title   = {Modeling Context-Aware Behavior by Interpreted ECA Rules},
  author  = {Beer, Wolfgang and Christian, Volker and Ferscha, Alois and Mehrmann, Lars},
  year    = {2011},
  journal = {Lecture Notes in Computer Science},
  url     = {https://www.researchgate.net/publication/220767969_Modeling_Context-Aware_Behavior_by_Interpreted_ECA_Rules}
}
```
