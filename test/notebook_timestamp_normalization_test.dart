import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

/// 时间戳归一化的自愈契约（spec: notebook-storage）。
///
/// 固定两件事：
/// 1. 有 TEXT 时间戳行时仍然归一化——这是自愈，不能因为加了性能门禁就失效；
/// 2. 没有 TEXT 行时不做无谓的全表 UPDATE——笔记本子窗口每次打开都跑
///    beforeOpen，正常库（全是 integer）不该为此付 4 次全表扫描。
void main() {
  group('时间戳归一化', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => await db.close());

    test('TEXT 时间戳被归一化为 unix 秒整数', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'text-ts',
        title: 'T',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
      // 模拟外部工具写入的 TEXT 时间戳（记忆 drift-text-timestamp-pitfall：
      // 这种值会让 drift 的 DateTimeColumn 读抛 FormatException）。
      await db.customStatement(
        "UPDATE notes SET created_at = datetime('now'), updated_at = datetime('now') WHERE id = 'text-ts'",
      );

      await db.normalizeTextTimestampsForTesting();

      final rows = await db.customSelect(
        "SELECT typeof(created_at) AS t FROM notes WHERE id = 'text-ts'",
      ).get();
      expect(rows.first.data['t'], 'integer',
          reason: '归一化后必须是 drift 期望的 unix 秒整数');

      // 归一化的目的是让读取不再抛——读得出来才算真的修好。
      final note = await db.noteById('text-ts');
      expect(note, isNotNull);
    });

    test('notebooks 表的 TEXT 时间戳同样被归一化', () async {
      await db.into(db.notebooks).insert(
            NotebooksCompanion.insert(
              id: 'nb-text',
              name: 'NB',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.customStatement(
        "UPDATE notebooks SET updated_at = datetime('now') WHERE id = 'nb-text'",
      );

      await db.normalizeTextTimestampsForTesting();

      final rows = await db.customSelect(
        "SELECT typeof(updated_at) AS t FROM notebooks WHERE id = 'nb-text'",
      ).get();
      expect(rows.first.data['t'], 'integer');
    });

    test('全是 integer 时归一化不改变任何值', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'int-ts',
        title: 'I',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));

      await db.normalizeTextTimestampsForTesting();

      final note = await db.noteById('int-ts');
      expect(note!.createdAt.millisecondsSinceEpoch ~/ 1000,
          now.millisecondsSinceEpoch ~/ 1000);
    });

    test('空库上执行不抛', () async {
      // beforeOpen 在新建库时也会跑到归一化——空表不能成为启动阻塞。
      await expectLater(
        db.normalizeTextTimestampsForTesting(),
        completes,
      );
    });
  });
}
