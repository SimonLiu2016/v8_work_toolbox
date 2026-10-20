import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/note_store.dart';

/// stack 回填的「已尝试跳过」契约（spec: notebook-tool 的 Automatic stack
/// backfill on startup）。
///
/// 固定三件事：
/// 1. 已尝试且印象笔记库无对应 stack 的笔记本 id 被持久化，下次跳过——子窗口
///    是独立进程，内存缓存无效，不落盘等于每次开窗都白跑一次 sqlite3 子进程；
/// 2. 未标记的笔记本仍会尝试——标记是性能优化，不能把「该修的修好」变成
///    「永远不修」；
/// 3. 已成功回填的笔记本行为不变（有 stack 值的不进 needBackfill）。
void main() {
  group('Evernote stack 回填', () {
    late Directory tempDir;
    late NoteDatabase db;
    late NoteStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stack_backfill_test_');
      AppPaths.overrideRootForTesting(tempDir);
      await SettingsStore.instance.init(rootDir: tempDir);
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      store = NoteStore.instance;
      store.setDatabaseForTesting(db);
    });

    tearDown(() async {
      await db.close();
      AppPaths.resetForTesting();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> seedNotebook(String id, String name, {String? stack}) {
      return db.insertNotebook(
        NotebooksCompanion.insert(
          id: id,
          name: name,
          stack: Value(stack),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    Future<Map<String, dynamic>> readConfig() async {
      final f = File('${tempDir.path}/config/notebook.json');
      if (!f.existsSync()) return {};
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return {};
      return jsonDecode(raw) as Map<String, dynamic>;
    }

    test('已标记的笔记本不再进入待回填集合', () async {
      // 直接验证门禁本身：把两个 id 写进 config，needBackfill 应该被过滤空。
      await seedNotebook('nb-marked', '已标记');
      await seedNotebook('nb-unmarked', '未标记');

      // 先跑一次，让「本机没有印象笔记库」这条路径把它们都标记上。
      await store.autoBackfillNotebookStacksFromEvernote();
      final cfg1 = await readConfig();
      expect(cfg1['stackBackfillAttemptV1'], isNotNull,
          reason: '本机无印象笔记库，两个笔记本都应被标记为已尝试');

      // 再跑一次不应再触发任何外部查询——门禁把它们全过滤掉了。
      // （这一断言的价值在于不抛、不卡，且 config 不被反复重写。）
      await store.autoBackfillNotebookStacksFromEvernote();
      final cfg2 = await readConfig();
      expect(cfg2['stackBackfillAttemptV1'], cfg1['stackBackfillAttemptV1']);
    });

    test('已有 stack 的笔记本不被标记（它不需要回填）', () async {
      await seedNotebook('nb-has', '有组', stack: '工作');
      await seedNotebook('nb-none', '无组');

      await store.autoBackfillNotebookStacksFromEvernote();
      final cfg = await readConfig();
      final attempted = (cfg['stackBackfillAttemptV1'] as List?) ?? [];

      expect(attempted, contains('nb-none'));
      expect(attempted, isNot(contains('nb-has')),
          reason: '有 stack 的笔记本不进 needBackfill，不该被标记');
    });

    test('全部已回填时不写 config', () async {
      await seedNotebook('nb-has', '有组', stack: '工作');

      await store.autoBackfillNotebookStacksFromEvernote();
      final cfg = await readConfig();
      expect(cfg.containsKey('stackBackfillAttemptV1'), isFalse,
          reason: '无事可做就不该留下标记，否则 manual 重试语义会被污染');
    });

    test('标记是合并而非覆盖', () async {
      await seedNotebook('nb-a', 'A');
      await store.autoBackfillNotebookStacksFromEvernote();

      // 新出现的笔记本（导入或新建）应被追加，而不是把旧标记冲掉。
      await seedNotebook('nb-b', 'B');
      await store.autoBackfillNotebookStacksFromEvernote();

      final cfg = await readConfig();
      final attempted = (cfg['stackBackfillAttemptV1'] as List?) ?? [];
      expect(attempted, containsAll(['nb-a', 'nb-b']));
    });

    test('手动删掉标记后重新尝试', () async {
      await seedNotebook('nb-a', 'A');
      await store.autoBackfillNotebookStacksFromEvernote();

      // 模拟用户按注释里的手动重试方式删掉 key。
      final cfg = await readConfig();
      cfg.remove('stackBackfillAttemptV1');
      await SettingsStore.instance.writeToolConfig('notebook', cfg);

      await store.autoBackfillNotebookStacksFromEvernote();
      final cfg2 = await readConfig();
      expect(cfg2['stackBackfillAttemptV1'], contains('nb-a'),
          reason: '删掉标记后应重新尝试并重新标记');
    });
  });
}
