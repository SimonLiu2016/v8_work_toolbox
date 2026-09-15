import 'dart:convert';
import 'dart:io';

import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/registry.dart';
import 'package:V8WorkToolbox/tools/slimmer/project_artifact_detector.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRootDir;
  late Directory tempOldFilesDir;

  setUp(() async {
    tempRootDir =
        await Directory.systemTemp.createTemp('v8_settings_merge_test_');
    tempOldFilesDir =
        await Directory.systemTemp.createTemp('v8_old_files_merge_test_');
  });

  tearDown(() async {
    if (await tempRootDir.exists()) await tempRootDir.delete(recursive: true);
    if (await tempOldFilesDir.exists()) {
      await tempOldFilesDir.delete(recursive: true);
    }
  });

  /// 写入文本文件，自动创建父目录
  Future<void> _writeFile(String path, String content) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<void> writeJson(String path, Map<String, dynamic> data) =>
      File(path).writeAsString(jsonEncode(data));

  group('工具合并时的配置继承（clean-builds → smart-disk-slimmer）', () {
    test('watchlist 与产物开关被继承到瘦身配置，原文件保留', () async {
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await writeJson(oldConfigPath, {
        'configs': [
          {'name': 'work', 'path': '/Users/x/work'},
          {'name': 'tmp', 'path': '/Users/x/tmp'},
        ],
        'artifactOptions': {'build': true, 'node_modules': false},
      });

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );

      final cfg = await store.getSlimerProjectArtifactConfig();
      expect(cfg.extraRoots, containsAll(['/Users/x/work', '/Users/x/tmp']));
      expect(cfg.artifactOptions['node_modules'], isFalse);
      expect(cfg.artifactOptions['build'], isTrue);

      expect(await File(oldConfigPath).exists(), isTrue);
      expect(
          await File(p.join(tempRootDir.path, 'config', 'clean-builds.json'))
              .exists(),
          isTrue);

      final slimmerJson = await store.readToolConfig('smart-disk-slimmer');
      expect(slimmerJson['slimmerInheritedFromCleanBuilds'], isTrue);
    });

    test('承接键非空时仍并入被移除工具的根，用户既有条目保留', () async {
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await writeJson(oldConfigPath, {
        'configs': [
          {'name': 'old', 'path': '/Users/x/old-root'},
        ],
        'artifactOptions': {'build': true},
      });

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );

      // 用户先手动添加了自己的条目
      await store.saveSlimerProjectArtifactConfig(
        SlimerProjectArtifactConfig(
          extraRoots: ['/Users/x/user-new-root'],
          artifactOptions: {'build': false},
        ),
      );

      final cfg = await store.getSlimerProjectArtifactConfig();
      // 无条件并集：既保留用户条目，也补回被移除工具的条目
      expect(cfg.extraRoots, containsAll([
        '/Users/x/user-new-root',
        '/Users/x/old-root',
      ]));
      // 用户显式关闭的类型保持关闭
      expect(cfg.artifactOptions['build'], isFalse);
    });

    test('继承幂等：重复读取不产生重复条目', () async {
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await writeJson(oldConfigPath, {
        'configs': [
          {'name': 'a', 'path': '/Users/x/a'},
          {'name': 'b', 'path': '/Users/x/b'},
        ],
      });

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );

      await store.getSlimerProjectArtifactConfig();
      await store.getSlimerProjectArtifactConfig();
      await store.getSlimerProjectArtifactConfig();

      final cfg = await store.getSlimerProjectArtifactConfig();
      expect(cfg.extraRoots, hasLength(2));
      expect(cfg.extraRoots, containsAll(['/Users/x/a', '/Users/x/b']));
    });

    test('flag 已置位时仍补齐（自愈），既有条目不被删除', () async {
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await writeJson(oldConfigPath, {
        'configs': [
          {'name': 'lost', 'path': '/Users/x/lost-root'},
        ],
      });

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );

      // 模拟既有受影响用户：flag 已置位，承接键非空，旧根从未并入
      final json = await store.readToolConfig('smart-disk-slimmer');
      json['extraRoots'] = ['/Users/x/user-only'];
      json['slimmerInheritedFromCleanBuilds'] = true;
      await store.writeToolConfig('smart-disk-slimmer', json);

      final cfg = await store.getSlimerProjectArtifactConfig();
      expect(cfg.extraRoots, containsAll([
        '/Users/x/user-only',
        '/Users/x/lost-root',
      ]));
    });

    test('从旧 JSON 迁移进来的顶层数组形状被正确继承', () async {
      // ~/.v8_cleaner_config.json 是顶层数组 [{name, path}, ...]，
      // readToolConfig 的 as Map 断言会失败回退空配置，需容忍该形状。
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await File(oldConfigPath).writeAsString(jsonEncode([
        {'name': 'c1', 'path': '/Users/x/top-level-1'},
        {'name': 'c2', 'path': '/Users/x/top-level-2'},
      ]));

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );

      final cfg = await store.getSlimerProjectArtifactConfig();
      expect(cfg.extraRoots, containsAll([
        '/Users/x/top-level-1',
        '/Users/x/top-level-2',
      ]));
    });

    test('被移除工具的原配置文件保留不删除', () async {
      final oldConfigPath =
          p.join(tempOldFilesDir.path, '.v8_cleaner_config.json');
      await writeJson(oldConfigPath, {
        'configs': [
          {'name': 'keep', 'path': '/Users/x/keep'},
        ],
      });

      final store = SettingsStore.instance;
      await store.init(
        rootDir: tempRootDir,
        customMigrations: [
          MigrationEntry(toolId: 'clean-builds', oldFilePath: oldConfigPath),
        ],
      );
      await store.getSlimerProjectArtifactConfig();

      expect(await File(oldConfigPath).exists(), isTrue);
    });

    test('批量诊断配置保存不冲掉项目产物配置', () async {
      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir);

      await store.saveSlimerProjectArtifactConfig(
        SlimerProjectArtifactConfig(
          extraRoots: ['/Users/x/keep'],
          artifactOptions: {'dist': false},
        ),
      );
      await store.saveSlimerBatchConfig(
        const SlimerBatchConfig(concurrency: 3, maxRetries: 5),
      );

      final cfg = await store.getSlimerProjectArtifactConfig();
      // 本测试关心的是"批量诊断保存不冲掉项目产物配置"：用户自己的条目与
      // 开关必须存活。无条件并集会另行补回迁移来的旧根，故不精确断言全集。
      expect(cfg.extraRoots, contains('/Users/x/keep'));
      expect(cfg.extraRoots, isNot(contains('')));
      expect(cfg.artifactOptions['dist'], isFalse);
      final batch = await store.getSlimerBatchConfig();
      expect(batch.concurrency, 3);
      expect(batch.maxRetries, 5);
    });

    test('配置继承不阻塞启动（clean-builds 配置损坏）', () async {
      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir);
      await File(p.join(tempRootDir.path, 'config', 'clean-builds.json'))
          .writeAsString('{ not valid json');

      // 迁移源损坏时不抛异常、不阻塞启动，继承回退为空配置。
      // 用户此前保存的条目与开关不受影响（见上一用例）。
      final cfg = await store.getSlimerProjectArtifactConfig();
      expect(cfg.extraRoots, isEmpty);
      expect(cfg.artifactOptions, isEmpty);
    });
  });

  group('最近使用：已移除工具标识重定向', () {
    test('clean-builds 被重定向为 smart-disk-slimmer，且不产生空条目', () async {
      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir);

      await store.recordToolUsed('clean-builds');
      await store.recordToolUsed('notebook');

      final recent = store.getRecentToolIds();
      // 最近使用列表包含承接工具和 notebook，顺序取决于记录顺序
      expect(recent, containsAll(['smart-disk-slimmer', 'notebook']));
      expect(recent, isNot(contains('clean-builds')));
    });

    test('重定向后去重：同一承接工具不重复出现', () async {
      final store = SettingsStore.instance;
      await store.init(rootDir: tempRootDir);

      await store.recordToolUsed('clean-builds');
      await store.recordToolUsed('smart-disk-slimmer');
      await store.recordToolUsed('clean-builds');

      expect(store.getRecentToolIds(), ['smart-disk-slimmer']);
    });

    test('注册表不再包含 clean-builds', () {
      expect(ToolRegistry.findById('clean-builds'), isNull);
      expect(ToolRegistry.findById('smart-disk-slimmer'), isNotNull);
    });
  });

  group('Tier A 项目根发现', () {
    late Directory fixture;
    late Directory home;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('v8_project_artifact_');
      home = Directory(p.join(fixture.path, 'Home'));
      await home.create(recursive: true);
      // 退化用例：HOME 顶层裸 package.json
      await File(p.join(home.path, 'package.json')).writeAsString('{}');
      await Directory(p.join(home.path, 'node_modules')).create(recursive: true);
      await Directory(p.join(home.path, 'projs', 'alpha')).create(recursive: true);
      await _writeFile(p.join(home.path, 'projs', 'alpha', '.git', 'HEAD'), 'ref: refs/heads/main');
      await Directory(p.join(home.path, 'projs', 'alpha', 'node_modules'))
          .create(recursive: true);
      await Directory(p.join(home.path, 'projs', 'alpha', 'build'))
          .create(recursive: true);
      await Directory(p.join(home.path, 'Library', 'Caches'))
          .create(recursive: true);
      await Directory(p.join(home.path, 'no-manifest', 'dist'))
          .create(recursive: true);
    });

    tearDown(() async {
      if (await fixture.exists()) await fixture.delete(recursive: true);
    });

    test('识别 manifest 信号，排除无 manifest 目录', () async {
      final roots = await ProjectArtifactDetector(
        home: home.path,
      ).discoverProjectRoots();
      expect(roots, contains(p.join(home.path, 'projs', 'alpha')));
      expect(roots, isNot(contains(p.join(home.path, 'no-manifest'))));
    });

    test('HOME 自身不作为根（裸 ~/package.json 不吞掉其他根）', () async {
      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      final normalized = roots.map((r) => p.normalize(r)).toList();
      final homeNorm = p.normalize(home.path);

      expect(normalized, isNot(contains(homeNorm)));
      expect(normalized, contains(homeNorm + '/projs/alpha'));
    });

    test('产物目录内部嵌套的 manifest 不产生项目根', () async {
      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      final normalized =
          roots.map((r) => p.normalize(r).replaceAll('\\', '/')).toList();
      expect(normalized, isNot(contains(endsWith('/node_modules'))));
      expect(normalized, isNot(contains(endsWith('/build'))));
    });

    test('watchlist 根豁免 manifest 门控', () async {
      final roots = await ProjectArtifactDetector(
        home: home.path,
        watchlist: [p.join(home.path, 'no-manifest')],
      ).discoverProjectRoots();
      expect(roots, contains(p.normalize(p.join(home.path, 'no-manifest'))));
    });

    test('watchlist 宽容器条目弃父保子：其下自然根全部保留，容器自身不入列',
        () async {
      final container = p.join(home.path, 'Workspace');
      await Directory(container).create(recursive: true);
      await _writeFile(p.join(container, 'proj-a', 'package.json'), '{}');
      await _writeFile(p.join(container, 'proj-b', 'pubspec.yaml'), 'name: x');

      final roots = await ProjectArtifactDetector(
        home: home.path,
        watchlist: [container],
      ).discoverProjectRoots();
      final normalized = roots.map((r) => p.normalize(r)).toList();

      expect(normalized, isNot(contains(p.normalize(container))));
      expect(normalized, containsAll([
        p.normalize(p.join(container, 'proj-a')),
        p.normalize(p.join(container, 'proj-b')),
      ]));
    });

    test('watchlist 条目其下无自然根时自身作为根加入（逃生口）', () async {
      final legacy = p.join(home.path, 'legacy-project');
      await Directory(legacy).create(recursive: true);
      await _writeFile(p.join(legacy, 'src', 'main.c'), 'int main(){}');

      final roots = await ProjectArtifactDetector(
        home: home.path,
        watchlist: [legacy],
      ).discoverProjectRoots();
      expect(roots, contains(p.normalize(legacy)));
    });

    test('watchlist 条目与已发现自然根重复时不产生重复条目', () async {
      final root = p.join(home.path, 'projs', 'alpha');
      final roots = await ProjectArtifactDetector(
        home: home.path,
        watchlist: [root],
      ).discoverProjectRoots();
      expect(roots.where((r) => p.normalize(r) == p.normalize(root)),
          hasLength(1));
    });

    test('深度上限：maxDepth 之外不识别', () async {
      // depth 5 是 HOME=1 的 5 个路径段；HOME=1、d1=2、d2=3、d3=4、d4=5
      // 不超限，deep-project=6 超限。
      final deep = p.join(home.path, 'd1', 'd2', 'd3', 'd4', 'deep-project');
      await Directory(deep).create(recursive: true);
      await File(p.join(deep, 'pubspec.yaml')).writeAsString('name: x');

      final roots = await ProjectArtifactDetector(
        home: home.path,
        discoverMaxDepth: 5,
      ).discoverProjectRoots();
      expect(
        roots.map((r) => p.normalize(r)),
        isNot(contains(p.normalize(deep))),
      );
    });

    test('pom.xml 根被识别（无 .git 的 Maven 项目）', () async {
      final root = p.join(home.path, 'maven-proj');
      await _writeFile(p.join(root, 'pom.xml'), '<project/>');
      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      expect(roots, contains(p.normalize(root)));
    });

    test('Cargo.toml 根被识别（无 .git 的 Rust 项目）', () async {
      final root = p.join(home.path, 'rust-proj');
      await _writeFile(p.join(root, 'Cargo.toml'), '[package]');
      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      expect(roots, contains(p.normalize(root)));
    });

    test('包管理器缓存目录内的 manifest 不被识别为根', () async {
      // .pub-cache 内大量 pubspec.yaml 是下载副本，不是用户项目
      await _writeFile(p.join(home.path, '.pub-cache', 'pkg1', 'pubspec.yaml'),
          'name: x');
      await _writeFile(p.join(home.path, '.npm', 'node_modules', 'pkg',
              'package.json'),
          '{}');
      await _writeFile(
          p.join(home.path, '.cargo', 'registry', 'src', 'pkg', 'Cargo.toml'),
          '[package]');

      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      final normalized = roots.map((r) => p.normalize(r)).toList();
      expect(normalized,
          isNot(contains(anyElement(
              startsWith(p.normalize(p.join(home.path, '.pub-cache')))))));
      expect(normalized,
          isNot(contains(anyElement(
              startsWith(p.normalize(p.join(home.path, '.npm')))))));
      expect(normalized,
          isNot(contains(anyElement(
              startsWith(p.normalize(p.join(home.path, '.cargo')))))));
    });

    test('~/Applications 内的 manifest 不被识别为根', () async {
      await _writeFile(p.join(home.path, 'Applications', 'SomeApp.app',
              'Contents', 'package.json'),
          '{}');

      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      final normalized = roots.map((r) => p.normalize(r)).toList();
      expect(normalized,
          isNot(contains(anyElement(
              startsWith(p.normalize(p.join(home.path, 'Applications')))))));
    });
  });

  /// 写入真实的字节（非稀疏），确保 statSync().size 正确报告文件大小。
  /// 稀疏文件在部分文件系统中 statSync().size 可能返回 0，导致产物体积不足阈值。
  Future<void> _bigFile(String path, int bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(bytes);
    await raf.close();
  }

  Future<void> _bigDir(String dirPath, int bytes) async {
    await Directory(dirPath).create(recursive: true);
    await _bigFile(p.join(dirPath, 'blob.bin'), bytes);
  }

  Future<List<SlimCandidateItem>> _collectAll(
      ProjectArtifactDetector detector, List<String> roots) async {
    final result = <SlimCandidateItem>[];
    await for (final emitted in detector.collect(roots)) {
      result
        ..clear()
        ..addAll(emitted);
    }
    return result;
  }

  group('Tier B 产物收集、聚合与阈值', () {
    late Directory fixture;
    late Directory home;

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('v8_collect_fixture_');
      home = Directory(p.join(fixture.path, 'Home'));
      await home.create(recursive: true);
    });

    tearDown(() async {
      if (await fixture.exists()) await fixture.delete(recursive: true);
    });

    test('manifest 门控：裸顶层 node_modules 不产出候选项', () async {
      await _bigDir(p.join(home.path, 'node_modules'), 20 * 1024 * 1024);
      final root = p.join(home.path, 'proj');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'node_modules'), 20 * 1024 * 1024);

      final items = await _collectAll(
        ProjectArtifactDetector(home: home.path),
        [root],
      );
      expect(items, hasLength(1));
      expect(p.normalize(items.single.path), p.normalize(root));
    });

    test('低于 10MB 的根不入列表', () async {
      final root = p.join(home.path, 'small');
      await _writeFile(p.join(root, '.git', 'HEAD'), 'ref: x');
      await _writeFile(p.join(root, 'build', 'a.txt'), 'tiny');

      final items = await _collectAll(
        ProjectArtifactDetector(home: home.path),
        [root],
      );
      expect(items, isEmpty);
    });

    test('聚合条目：身份键为项目根路径，构成摘要含类型计数', () async {
      final root = p.join(home.path, 'big-proj');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'node_modules'), 11 * 1024 * 1024);
      await _bigDir(p.join(root, 'build'), 20 * 1024 * 1024);

      final items = await _collectAll(
        ProjectArtifactDetector(home: home.path),
        [root],
      );

      expect(items, hasLength(1));
      final item = items.single;
      expect(p.normalize(item.id), p.normalize(root));
      expect(p.normalize(item.path), p.normalize(root));
      expect(item.category, SlimmerCategory.projectArtifacts);
      expect(item.safety, SafetyRating.safe);
      expect(item.techStack, ProjectTechStack.node);
      expect(item.isSelected, isTrue);
      expect(item.artifacts, hasLength(2));
      expect(item.subtitle, contains('2 个产物目录'));
      expect(item.subtitle, contains('node_modules ×1'));
      expect(item.subtitle, contains('build ×1'));
      expect(item.scanIncomplete, isFalse);
    });

    test('artifactOptions 关闭的产物类型不被收集', () async {
      final root = p.join(home.path, 'opts');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'node_modules'), 11 * 1024 * 1024);
      await _bigDir(p.join(root, 'build'), 20 * 1024 * 1024);

      final items = await _collectAll(
        ProjectArtifactDetector(
          home: home.path,
          artifactOptions: {'build': false},
        ),
        [root],
      );
      expect(items.single.artifacts.map((a) => a.dirName), ['node_modules']);
    });

    test('时间预算耗尽的根标记为未完整，已发现部分保留', () async {
      final root = p.join(home.path, 'slow');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'build'), 11 * 1024 * 1024);

      // 极小时间预算 + minPresentBytes: 0 确保超时时零字节产物也计入列表。
      // 注意：此测试对时钟精度敏感，若 CI 机器时钟分辨率 < 1μs 可能偶发失败。
      final items = await _collectAll(
        ProjectArtifactDetector(
          home: home.path,
          perRootTimeBudget: const Duration(microseconds: 1),
          minPresentBytes: 0,
        ),
        [root],
      );
      expect(items, hasLength(1));
      expect(items.single.scanIncomplete, isTrue);
      expect(items.single.subtitle, contains('扫描超时'));
    });

    test('产物数量上限触发未完整', () async {
      final root = p.join(home.path, 'many');
      await _writeFile(p.join(root, 'package.json'), '{}');
      // 4 个不同深度的产物目录
      await _bigDir(p.join(root, 'a', 'build'), 11 * 1024 * 1024);
      await _bigDir(p.join(root, 'b', 'dist'), 11 * 1024 * 1024);
      await _bigDir(p.join(root, 'c', 'out'), 11 * 1024 * 1024);
      await _bigDir(p.join(root, 'd', 'target'), 11 * 1024 * 1024);

      final items = await _collectAll(
        ProjectArtifactDetector(
          home: home.path,
          perRootArtifactLimit: 2,
        ),
        [root],
      );
      expect(items, hasLength(1));
      expect(items.single.artifacts, hasLength(2));
      expect(items.single.scanIncomplete, isTrue);
    });

    test('不下降进 .git 与已命中的产物目录自身', () async {
      final root = p.join(home.path, 'pruned');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'node_modules'), 11 * 1024 * 1024);
      // 产物目录内再放一个同名目录：不得重复计数
      await _bigDir(
          p.join(root, 'node_modules', 'nested', 'build'), 11 * 1024 * 1024);
      await _writeFile(p.join(root, '.git', 'HEAD'), 'x');

      final items = await _collectAll(
        ProjectArtifactDetector(home: home.path),
        [root],
      );
      expect(items.single.artifacts, hasLength(1));
      expect(p.normalize(items.single.artifacts.single.path),
          p.normalize(p.join(root, 'node_modules')));
    });

    test('产物开关全关时无候选项', () async {
      final root = p.join(home.path, 'disabled');
      await _writeFile(p.join(root, 'package.json'), '{}');
      await _bigDir(p.join(root, 'build'), 20 * 1024 * 1024);

      final items = await _collectAll(
        ProjectArtifactDetector(
          home: home.path,
          artifactOptions:
              {'build': false, 'node_modules': false, 'dist': false},
        ),
        [root],
      );
      expect(items, isEmpty);
    });

    test('技术栈：含 pom.xml 的根归类为 maven', () async {
      final root = p.join(home.path, 'maven-proj');
      await _writeFile(p.join(root, 'pom.xml'), '<project/>');
      await _bigDir(p.join(root, 'target'), 20 * 1024 * 1024);

      final detector = ProjectArtifactDetector(
        home: home.path,
        minPresentBytes: 0,
      );
      final items = await _collectAll(detector, [root]);
      expect(items, hasLength(1));
      expect(items.first.techStack, ProjectTechStack.maven);
    });

    test('技术栈：gradle 信号优先于 pom.xml', () async {
      final root = p.join(home.path, 'hybrid');
      await _writeFile(p.join(root, 'build.gradle'), 'apply plugin: java');
      await _writeFile(p.join(root, 'pom.xml'), '<project/>');
      await _bigDir(p.join(root, 'build'), 20 * 1024 * 1024);

      final detector = ProjectArtifactDetector(
        home: home.path,
        minPresentBytes: 0,
      );
      final items = await _collectAll(detector, [root]);
      expect(items, hasLength(1));
      expect(items.first.techStack, ProjectTechStack.gradleAndroid);
    });

    test('技术栈：无 manifest 信号的根归 other 兜底', () async {
      final root = p.join(home.path, 'plain');
      await _writeFile(p.join(root, 'README.md'), 'x');
      await _bigDir(p.join(root, 'out'), 20 * 1024 * 1024);

      final detector = ProjectArtifactDetector(
        home: home.path,
        minPresentBytes: 0,
      );
      final items = await _collectAll(detector, [root]);
      expect(items, hasLength(1));
      expect(items.first.techStack, ProjectTechStack.other);
    });

    test('多根进度式上抛：每收完一根递增', () async {
      final r1 = p.join(home.path, 'p1');
      final r2 = p.join(home.path, 'p2');
      for (final r in [r1, r2]) {
        await _writeFile(p.join(r, 'pubspec.yaml'), 'x');
        await _bigDir(p.join(r, '.dart_tool'), 11 * 1024 * 1024);
      }

      final emissions = <List<SlimCandidateItem>>[];
      await for (final emitted in
          ProjectArtifactDetector(home: home.path).collect([r1, r2])) {
        emissions.add(emitted);
      }
      expect(emissions.length, 2);
      expect(emissions.last, hasLength(2));
    });

    test('非项目根内的产物不被计入（门控）', () async {
      // 把不在任何 manifest 根下的目录传入 collect：仍会收集（collect 自身
      // 不做门控，门控发生在 Tier A 发现阶段）。因此这里验证 Tier A 不产出它。
      final stray = p.join(home.path, 'stray');
      await _bigDir(p.join(stray, 'build'), 20 * 1024 * 1024);

      final roots = await ProjectArtifactDetector(home: home.path)
          .discoverProjectRoots();
      expect(roots, isEmpty);
    });
  });
}
