import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRootDir;
  late Directory tempOldFilesDir;

  setUp(() async {
    tempRootDir = await Directory.systemTemp.createTemp('v8_settings_test_');
    tempOldFilesDir = await Directory.systemTemp.createTemp('v8_old_files_test_');
  });

  tearDown(() async {
    if (await tempRootDir.exists()) {
      await tempRootDir.delete(recursive: true);
    }
    if (await tempOldFilesDir.exists()) {
      await tempOldFilesDir.delete(recursive: true);
    }
  });

  group('SettingsStore Migration & Persistence Tests', () {
    test('首次启动：旧配置文件迁移到 config/ 并记录在 app.json 中，旧文件保持完好', () async {
      final oldFilePath = p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      final oldConfigContent = jsonEncode({
        'targetDirectory': '/Users/test/workspace',
        'buildDirs': ['build', '.dart_tool'],
      });
      await File(oldFilePath).writeAsString(oldConfigContent);

      final migrations = [
        MigrationEntry(toolId: 'clean-builds', oldFilePath: oldFilePath),
      ];

      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir, customMigrations: migrations);

      // 验证目标文件生成
      final migratedFile = File(p.join(tempRootDir.path, 'config', 'clean-builds.json'));
      expect(await migratedFile.exists(), isTrue);

      final migratedMap = await store.readToolConfig('clean-builds');
      expect(migratedMap['targetDirectory'], '/Users/test/workspace');
      expect(migratedMap['buildDirs'], ['build', '.dart_tool']);

      // 验证旧文件未被删除
      expect(await File(oldFilePath).exists(), isTrue);

      // 验证 app.json 记录了迁移源
      final appJsonFile = File(p.join(tempRootDir.path, 'app.json'));
      expect(await appJsonFile.exists(), isTrue);
      final appJson = jsonDecode(await appJsonFile.readAsString());
      expect(appJson['migratedFrom'], contains(oldFilePath));
    });

    test('二次启动：不会重复迁移，用户修改的配置不会被覆盖', () async {
      final oldFilePath = p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      final oldConfigContent = jsonEncode({'val': 'original'});
      await File(oldFilePath).writeAsString(oldConfigContent);

      final migrations = [
        MigrationEntry(toolId: 'clean-builds', oldFilePath: oldFilePath),
      ];

      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir, customMigrations: migrations);

      // 用户更新配置
      await store.writeToolConfig('clean-builds', {'val': 'modified_by_user'});

      // 二次启动再次调用 init
      await store.init(rootDir: tempRootDir, customMigrations: migrations);

      // 验证用户配置保持未变
      final currentConfig = await store.readToolConfig('clean-builds');
      expect(currentConfig['val'], 'modified_by_user');
    });

    test('损坏配置容错：损坏的 app.json 或 tool json 回退到安全默认值而不崩溃', () async {
      final appJsonFile = File(p.join(tempRootDir.path, 'app.json'));
      await appJsonFile.create(recursive: true);
      await appJsonFile.writeAsString('{ invalid json syntax !!! @@');

      final store = SettingsStore.instance;
      // 初始化不应该抛出异常崩溃
      await store.init(rootDir: tempRootDir);

      // 验证回退到默认设置
      expect(store.getRecentToolIds(), isEmpty);

      // 写入损坏的工具配置
      final badToolFile = File(p.join(tempRootDir.path, 'config', 'bad-tool.json'));
      await badToolFile.create(recursive: true);
      await badToolFile.writeAsString('not a valid json content');

      final badToolConfig = await store.readToolConfig('bad-tool');
      expect(badToolConfig, isEmpty);
    });

    test('近期工具记录与原子保存', () async {
      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir);

      await store.recordToolUsed('bc-config');
      await store.recordToolUsed('batch-rename');
      await store.recordToolUsed('bc-config');

      expect(store.getRecentToolIds().first, 'bc-config');
      expect(store.getRecentToolIds().length, 2);

      // 重新读取持久化状态
      await store.init(rootDir: tempRootDir);
      expect(store.getRecentToolIds(), ['bc-config', 'batch-rename']);
    });
  });
}
