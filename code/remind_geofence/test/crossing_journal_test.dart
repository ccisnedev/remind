import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_core/remind_core.dart';
import 'package:remind_geofence/remind_geofence.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location zone;
  late InMemoryCrossingJournal journal;

  const supermarket = GeoRegion(
    id: 'supermarket',
    center: GeoCoordinate(-33.4372, -70.6506),
    radiusMetres: 200,
  );

  setUp(() {
    zone = tz.getLocation('America/Santiago');
    journal = InMemoryCrossingJournal();
  });

  Delivered delivered(int day) => Delivered(
        reminderId: 'groceries',
        region: supermarket,
        event: GeoEvent.enter,
        at: tz.TZDateTime(zone, 2026, 5, day, 11),
      );

  Suppressed suppressed(int day) => Suppressed(
        reminderId: 'groceries',
        region: supermarket,
        event: GeoEvent.enter,
        at: tz.TZDateTime(zone, 2026, 5, day, 11),
        condition: WeekdaysCondition(Weekday.workdays),
        reason: 'a condition on the reminder did not hold.',
      );

  Undetermined undetermined(int day) => Undetermined(
        reminderId: 'groceries',
        region: supermarket,
        event: GeoEvent.enter,
        at: tz.TZDateTime(zone, 2026, 5, day, 11),
        condition: const InsideRegionCondition(supermarket),
        notified: false,
        reason: 'the device location was unknown.',
      );

  group('recording', () {
    test('starts empty', () async {
      expect(await journal.recent(), isEmpty);
    });

    test('keeps what it is told, newest first', () async {
      await journal.record(delivered(11));
      await journal.record(suppressed(12));
      await journal.record(undetermined(13));

      final recent = await journal.recent();

      expect(recent, hasLength(3));
      expect(recent.first.at.day, 13, reason: 'newest first');
      expect(recent.last.at.day, 11);
    });

    test('records outcomes that reached nobody', () async {
      // The whole point. A crossing that was suppressed leaves no notification
      // and no trace anywhere else; if it is not written here the user has no
      // way to learn it happened.
      await journal.record(suppressed(11));

      expect(await journal.recent(), hasLength(1));
      expect((await journal.recent()).single.shouldNotify, isFalse);
    });

    test('can be filtered to one reminder', () async {
      await journal.record(delivered(11));
      await journal.record(
        Delivered(
          reminderId: 'other',
          region: supermarket,
          event: GeoEvent.exit,
          at: tz.TZDateTime(zone, 2026, 5, 12, 11),
        ),
      );

      expect(await journal.recent(reminderId: 'groceries'), hasLength(1));
      expect(await journal.recent(reminderId: 'nobody'), isEmpty);
    });

    test('honours a limit', () async {
      for (var day = 1; day <= 10; day++) {
        await journal.record(delivered(day));
      }

      expect(await journal.recent(limit: 3), hasLength(3));
    });
  });

  group('bounded growth', () {
    test('discards the oldest beyond its capacity', () async {
      // A journal that grew forever would be a slow leak in an app that may
      // never be opened. Old entries are the ones nobody is asking about.
      final small = InMemoryCrossingJournal(capacity: 5);
      for (var day = 1; day <= 12; day++) {
        await small.record(delivered(day));
      }

      final recent = await small.recent(limit: 100);

      expect(recent, hasLength(5));
      expect(recent.first.at.day, 12);
      expect(recent.last.at.day, 8);
    });
  });

  group('clearing', () {
    test('empties the journal', () async {
      await journal.record(delivered(11));
      await journal.clear();

      expect(await journal.recent(), isEmpty);
    });
  });

  group('encoding', () {
    test('a delivered outcome survives a round trip', () async {
      final original = delivered(11);
      final decoded = CrossingOutcomeCodec.decode(
        jsonDecode(jsonEncode(CrossingOutcomeCodec.encode(original)))
            as Map<String, Object?>,
        zone,
      );

      expect(decoded, isA<Delivered>());
      expect(decoded!.reminderId, 'groceries');
      expect(decoded.region, supermarket);
      expect(decoded.event, GeoEvent.enter);
      expect(decoded.at, original.at);
      expect(decoded.shouldNotify, isTrue);
    });

    test('a suppressed outcome keeps its reason and condition', () async {
      final original = suppressed(11);
      final decoded = CrossingOutcomeCodec.decode(
        CrossingOutcomeCodec.encode(original),
        zone,
      )! as Suppressed;

      expect(decoded.reason, original.reason);
      expect(decoded.condition, original.condition);
      expect(decoded.explanation, original.explanation);
    });

    test('an undetermined outcome keeps whether it notified anyway', () async {
      final original = Undetermined(
        reminderId: 'groceries',
        region: supermarket,
        event: GeoEvent.enter,
        at: tz.TZDateTime(zone, 2026, 5, 11, 11),
        condition: const InsideRegionCondition(supermarket),
        notified: true,
        reason: 'unknown location.',
      );
      final decoded = CrossingOutcomeCodec.decode(
        CrossingOutcomeCodec.encode(original),
        zone,
      )! as Undetermined;

      expect(decoded.notified, isTrue);
      expect(decoded.shouldNotify, isTrue);
      expect(decoded.condition, original.condition);
    });

    test('the instant survives the zone, not just the wall clock', () async {
      final original = delivered(11);
      final decoded = CrossingOutcomeCodec.decode(
        CrossingOutcomeCodec.encode(original),
        zone,
      )!;

      expect(decoded.at.toUtc(), original.at.toUtc());
      expect(decoded.at.location, zone);
    });

    test('rubbish decodes to null rather than throwing', () {
      // The journal is written from a background isolate and read from the UI.
      // A single unreadable entry must not take the diagnostics screen down
      // with it — that screen exists precisely for when things are wrong.
      expect(CrossingOutcomeCodec.decode(const {}, zone), isNull);
      expect(
        CrossingOutcomeCodec.decode(const {'kind': 'nonsense'}, zone),
        isNull,
      );
    });
  });
}
