import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/models/toonflow_studio_config.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_override_store.dart';

/// override 生成的契约测试（spec: 运行时配置以 override 注入）。
///
/// 固定四件事：
/// 1. 端口、bind mount、user 三项都在；
/// 2. `!override` 标签带上了（不带会导致 3000 绑两个端口、/app/data 挂两个卷）；
/// 3. 含空格的宿主机路径被正确引用（macOS 的 Application Support 一定有空格）；
/// 4. 非本工具生成的文件先备份而不是直接覆盖。
void main() {
  late Directory tempDir;
  late Directory projectDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tf_override');
    AppPaths.overrideRootForTesting(tempDir);
    projectDir = Directory(p.join(tempDir.path, 'Toonflow-app'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('render', () {
    test('端口 / bind mount / user 三项齐全', () {
      final yaml = ToonflowOverrideStore.instance.render(
        const ToonflowStudioConfig(httpPort: 3177),
        uid: '501',
        gid: '20',
      );
      final decoded = ToonflowOverrideStore.decodeOverride(yaml);
      expect(decoded['hostPort'], '3177');
      expect(decoded['user'], '501:20');
      expect(decoded['bindMount'], AppPaths.toonflowDataDir.path);
    });

    test('路径含空格时 decodeOverride 仍能取出（引号被剥掉）', () {
      // 测试用的 tempDir 通常没有空格，这里手工造一个带空格的 root 来验。
      final spaced = Directory.systemTemp.createTempSync('tf override');
      addTearDown(() {
        AppPaths.resetForTesting();
        if (spaced.existsSync()) spaced.deleteSync(recursive: true);
      });
      AppPaths.overrideRootForTesting(spaced);

      final yaml = ToonflowOverrideStore.instance.render(
        const ToonflowStudioConfig(httpPort: 3177),
        uid: '501',
        gid: '20',
      );
      expect(AppPaths.toonflowDataDir.path, contains(' '));

      final decoded = ToonflowOverrideStore.decodeOverride(yaml);
      // 关键：引号不能残留在取值里，否则 bind mount 路径对不上。
      expect(decoded['bindMount'], AppPaths.toonflowDataDir.path);
      expect(decoded['bindMount'], isNot(startsWith('"')));
    });

    test('ports 与 volumes 都带 !override 标签', () {
      final yaml = ToonflowOverrideStore.instance.render(
        const ToonflowStudioConfig(),
        uid: '501',
        gid: '20',
      );
      // 不带 !override 时 compose 的默认合并行为是追加：3000 会同时绑两个
      // 端口、/app/data 会同时挂命名卷和 bind mount。
      expect(yaml, contains('ports: !override'));
      expect(yaml, contains('volumes: !override'));
    });

    test('路径被双引号包裹（空格才不会截断 YAML）', () {
      // macOS 的 ~/Library/Application Support/... 一定有空格，不加引号
      // YAML 会把它解析成两段。这里用带空格的 root 验证。
      final spaced = Directory.systemTemp.createTempSync('tf override');
      addTearDown(() {
        AppPaths.resetForTesting();
        if (spaced.existsSync()) spaced.deleteSync(recursive: true);
      });
      AppPaths.overrideRootForTesting(spaced);

      final yaml = ToonflowOverrideStore.instance.render(
        const ToonflowStudioConfig(),
        uid: '501',
        gid: '20',
      );
      expect(AppPaths.toonflowDataDir.path, contains(' '));
      // 注意断言形态：渲染出来是 `- "<host>:/app/data"`，整条卷字符串被引号
      // 包住。只引 host 段会让 compose v5 的 go-yaml 直接解析失败。
      expect(
        yaml,
        contains('- "${AppPaths.toonflowDataDir.path}:/app/data"'),
      );
    });

    test('首行是托管标记', () {
      final yaml = ToonflowOverrideStore.instance.render(
        const ToonflowStudioConfig(),
        uid: '1',
        gid: '1',
      );
      expect(yaml.trimLeft().startsWith(kToonflowOverrideMarker), isTrue);
    });
  });

  group('write / isManaged / remove', () {
    test('写出的文件被识别为托管', () {
      final wrote = ToonflowOverrideStore.instance.write(
        projectDir.path,
        const ToonflowStudioConfig(),
        uid: '501',
        gid: '20',
      );
      expect(wrote, isFalse, reason: '首次写入不该有备份');
      expect(ToonflowOverrideStore.instance.isManaged(projectDir.path), isTrue);
    });

    test('托管文件可被重复重写而不产生备份', () {
      final store = ToonflowOverrideStore.instance;
      store.write(projectDir.path, const ToonflowStudioConfig(httpPort: 3177),
          uid: '501', gid: '20');
      final again = store.write(projectDir.path,
          const ToonflowStudioConfig(httpPort: 4177), uid: '501', gid: '20');
      expect(again, isFalse);
      expect(
        ToonflowOverrideStore.decodeOverride(
          store.read(projectDir.path)!,
        )['hostPort'],
        '4177',
      );
    });

    test('非托管文件先备份再覆盖', () {
      final file = File(p.join(projectDir.path, kToonflowOverrideFileName));
      file.writeAsStringSync('# 我的手写配置\nservices:\n  toonflow: {}\n');

      final backedUp = ToonflowOverrideStore.instance.write(
        projectDir.path,
        const ToonflowStudioConfig(),
        uid: '501',
        gid: '20',
      );

      expect(backedUp, isTrue, reason: '用户文件被替换必须报告');
      // 备份落在本工具自己的目录里。
      final backups = AppPaths.toonflowDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.bak-'));
      expect(backups, isNotEmpty);
      // 原内容还在备份里。
      expect(
        backups.first.readAsStringSync(),
        contains('我的手写配置'),
      );
    });

    test('remove 只删托管文件', () {
      final store = ToonflowOverrideStore.instance;
      store.write(projectDir.path, const ToonflowStudioConfig(),
          uid: '501', gid: '20');
      expect(store.remove(projectDir.path), isTrue);
      expect(File(p.join(projectDir.path, kToonflowOverrideFileName)).existsSync(),
          isFalse);

      // 非托管文件不动。
      final file = File(p.join(projectDir.path, kToonflowOverrideFileName));
      file.writeAsStringSync('# 手写\n');
      expect(store.remove(projectDir.path), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('文件不存在时 remove 返回 false 而不抛', () {
      expect(ToonflowOverrideStore.instance.remove(projectDir.path), isFalse);
    });
  });
}
