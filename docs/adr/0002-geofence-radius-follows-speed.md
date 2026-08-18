# ADR 0002: A Geofence Radius Is Set By Speed, Not By The Place

**Status:** Accepted

## Context

The product this ecosystem is being built for includes a reminder that wakes a
passenger before their stop — riding a bus across Lima, sleeping, and being
told when the destination zone is near. That use case makes a constraint
visible that the "remind me at the supermarket" case hides.

**Geofences have latency, and it cannot be removed.** Android publishes typical
detection latency of under two minutes, rising to around six when the device
has been stationary for a long period. A moving vehicle avoids the stationary
penalty but not the base latency. iOS is comparable and documents no figure at
all; exit events in particular are described as not instantaneous.

Latency in a moving vehicle is distance:

| Speed | Distance covered in 2 minutes |
|---|---|
| 20 km/h — congested traffic | ~670 m |
| 30 km/h — typical urban bus | ~1,000 m |
| 50 km/h — expressway | ~1,670 m |

A 200-metre geofence around a bus stop therefore fires roughly a kilometre
after the passenger has passed it. The reminder is not late in the way a
notification is late; it is delivered somewhere else entirely.

Note what this is not. Exactness for **time** triggers was solved by asking for
`SCHEDULE_EXACT_ALARM` and measuring delivery at 80 ms. There is no equivalent
permission for location. No amount of configuration makes a geofence precise,
because the imprecision is in how the platform samples position, not in how it
schedules.

## Decision

**Compensate geometrically, not temporally.** For a trigger that must fire
before arrival, the radius has a lower bound:

```
radius >= speed x latency
```

At 30 km/h with two minutes of latency, that is roughly one kilometre — five
times what a stationary destination needs, and far above the 100–150 m minimum
the platforms recommend for accuracy reasons.

**Express it to the user in time, not distance.** Nobody reasons in metres of
radius. They think "wake me five minutes before" or "two stops early". An
application should take that and convert it, and should use the measured speed
where one is available rather than assuming a constant.

**Never present a location trigger as precise.** Where the packages already
report degraded delivery for time triggers — `deliversExactly`, the imprecision
banner — the equivalent honesty for location is to say plainly that arrival
detection is approximate, and how approximate.

`remind_core` and `remind_geofence` stay out of this. Neither imposes a
minimum radius nor infers one from speed: the core models a `GeoRegion` with
whatever radius it is given, and the backend registers it. Speed is a property
of the journey, not of the reminder, and the conversion from "five minutes
early" to metres belongs to the application that knows how its users travel.

## Consequences

- A destination-arrival reminder needs a radius one to two orders of magnitude
  larger than an errand reminder. Radius becomes a function of the journey.
- Large radii consume the platform budget no faster than small ones — the iOS
  ceiling of 20 regions is a count, not an area — so this costs nothing there.
- Overlapping large regions become likely, which makes the `Undetermined`
  outcome more common: a crossing of one region says nothing about another it
  overlaps, and `CrossingEvaluator` deliberately refuses to guess.
- Testing arrival reminders on foot is unrepresentative. Walking crosses a
  boundary slowly enough that latency is invisible. The failure mode this ADR
  describes only appears at vehicle speed, so a bus ride is the only test that
  exercises it.
- Any user-facing "wake me N minutes early" control needs a speed source.
  `geolocator` already supplies `Position.speed`, which the demo app subscribes
  to for other reasons.
