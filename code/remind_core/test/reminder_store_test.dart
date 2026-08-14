import 'package:remind_core/remind_core.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryReminderStore store;

  setUp(() => store = InMemoryReminderStore());

  Reminder reminder(String id, {bool enabled = true}) => Reminder(
        id: id,
        title: id,
        enabled: enabled,
        triggers: [const DailyTrigger(time: LocalTime(7, 0))],
      );

  group('InMemoryReminderStore', () {
    test('starts empty', () async {
      expect(await store.all(), isEmpty);
      expect(await store.byId('nothing'), isNull);
    });

    test('saves and reads back', () async {
      await store.save(reminder('wake'));

      expect(await store.byId('wake'), reminder('wake'));
      expect(await store.all(), hasLength(1));
    });

    test('saving the same id replaces rather than duplicates', () async {
      await store.save(reminder('wake'));
      await store.save(reminder('wake', enabled: false));

      final all = await store.all();
      expect(all, hasLength(1));
      expect(all.single.enabled, isFalse);
    });

    test('deletes', () async {
      await store.save(reminder('wake'));
      await store.delete('wake');

      expect(await store.all(), isEmpty);
    });

    test('deleting something absent is not an error', () async {
      await expectLater(store.delete('nothing'), completes);
    });

    test('returns reminders in a stable order', () async {
      await store.save(reminder('c'));
      await store.save(reminder('a'));
      await store.save(reminder('b'));

      final first = await store.all();
      final second = await store.all();

      expect(first.map((r) => r.id), second.map((r) => r.id));
    });

    test('the returned list cannot be used to mutate the store', () async {
      await store.save(reminder('wake'));
      final all = await store.all();

      expect(() => all.add(reminder('sneaky')), throwsUnsupportedError);
      expect(await store.all(), hasLength(1));
    });

    test('seeds from an initial set', () async {
      final seeded = InMemoryReminderStore(
        initial: [reminder('a'), reminder('b')],
      );

      expect(await seeded.all(), hasLength(2));
    });
  });

  group('watching', () {
    test('emits the current contents on listen', () {
      expect(store.watch(), emits(isEmpty));
    });

    test('emits again on every change', () async {
      final seen = <int>[];
      final subscription =
          store.watch().listen((reminders) => seen.add(reminders.length));

      await store.save(reminder('a'));
      await store.save(reminder('b'));
      await store.delete('a');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(seen, [0, 1, 2, 1]);
    });

    test('stops emitting once closed', () async {
      final done = expectLater(store.watch(), emitsThrough(emitsDone));
      await store.close();
      await done;
    });
  });
}
