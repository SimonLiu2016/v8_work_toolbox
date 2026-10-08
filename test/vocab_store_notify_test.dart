import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/vocab_book/models/vocab_entry.dart';
import 'package:V8WorkToolbox/tools/vocab_book/services/vocab_store.dart';

void main() {
  group('VocabStore onEntriesChanged 变更通知测试', () {
    late NoteDatabase db;
    late VocabStore store;

    setUp(() {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      store = VocabStore.instance;
      store.testDb = db;
    });

    tearDown(() async {
      store.testDb = null;
      await db.close();
    });

    test('insertEntry 触发 onEntriesChanged', () async {
      var notified = false;
      final sub = store.onEntriesChanged.listen((_) => notified = true);

      final entry = VocabEntryModel(
        id: 'test-1',
        word: 'serendipity',
        definitions: const ['意外发现珍奇事物的本领'],
        examples: const [],
        masteryLevel: 0,
        tags: const [],
        addedAt: DateTime.now(),
      );

      await store.insertEntry(entry);
      await pumpEventQueue();

      expect(notified, isTrue);
      await sub.cancel();
    });

    test('insertFromDictionary 触发 onEntriesChanged', () async {
      var notified = false;
      final sub = store.onEntriesChanged.listen((_) => notified = true);

      await store.insertFromDictionary(
        word: 'ephemeral',
        definitions: const ['短暂的'],
        examples: const ['ephemeral pleasure'],
      );
      await pumpEventQueue();

      expect(notified, isTrue);
      await sub.cancel();
    });

    test('deleteEntry 触发 onEntriesChanged', () async {
      final id = await store.insertFromDictionary(
        word: 'temp',
        definitions: const ['临时'],
        examples: const [],
      );

      var notified = false;
      final sub = store.onEntriesChanged.listen((_) => notified = true);

      await store.deleteEntry(id);
      await pumpEventQueue();

      expect(notified, isTrue);
      await sub.cancel();
    });

    test('deleteEntries 批量删除触发 onEntriesChanged', () async {
      final id1 = await store.insertFromDictionary(
        word: 'word1',
        definitions: const ['w1'],
        examples: const [],
      );
      final id2 = await store.insertFromDictionary(
        word: 'word2',
        definitions: const ['w2'],
        examples: const [],
      );

      var notified = false;
      final sub = store.onEntriesChanged.listen((_) => notified = true);

      await store.deleteEntries([id1, id2]);
      await pumpEventQueue();

      expect(notified, isTrue);
      await sub.cancel();
    });

    test('updateMasteryLevel 与 updateTags 触发 onEntriesChanged', () async {
      final id = await store.insertFromDictionary(
        word: 'persistent',
        definitions: const ['坚持不懈的'],
        examples: const [],
      );

      var count = 0;
      final sub = store.onEntriesChanged.listen((_) => count++);

      await store.updateMasteryLevel(id, 3);
      await pumpEventQueue();
      expect(count, equals(1));

      await store.updateTags(id, ['gre', 'favorite']);
      await pumpEventQueue();
      expect(count, equals(2));

      await sub.cancel();
    });
  });
}
