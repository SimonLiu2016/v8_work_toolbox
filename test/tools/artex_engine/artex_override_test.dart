import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/artex_engine/models/artex_engine_config.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_override_store.dart';

void main() {
  late Directory tempDir;
  late Directory appRoot;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('artex_override');
    appRoot = Directory.systemTemp.createTempSync('artex_approot');
    AppPaths.overrideRootForTesting(appRoot);
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (appRoot.existsSync()) appRoot.deleteSync(recursive: true);
  });

  String projectPath() => '${tempDir.path}/docker-compose.override.yml';

  group('override 内容（design D1 / task 4.1）', () {
    test('含门控关闭与配置端口', () {
      final content = ArtexOverrideStore.instance.render(
        const ArtexEngineConfig(httpPort: 9001, proxyPort: 9002),
      );
      expect(content, contains('ARTEX_GATE: "off"'));
      expect(content, contains('"127.0.0.1:9001:8787"'));
      expect(content, contains('"127.0.0.1:9002:8788"'));
    });

    test('带 !override 标签，否则 compose 会追加合并 ports 导致 8787 双绑', () {
      final content = ArtexOverrideStore.instance.render(
        const ArtexEngineConfig(),
      );
      expect(content, contains('ports: !override'));
    });

    test('只含 artex 服务段，不复制上游其他内容', () {
      final content = ArtexOverrideStore.instance.render(
        const ArtexEngineConfig(),
      );
      expect(content, contains('  artex:'));
      expect(content, isNot(contains('postgres:')));
    });

    test('gateOff=false 时不写 environment 段', () {
      final content = ArtexOverrideStore.instance.render(
        const ArtexEngineConfig(gateOff: false),
      );
      expect(content, isNot(contains('ARTEX_GATE')));
      // ports 仍要写
      expect(content, contains('ports: !override'));
    });
  });

  group('标记识别与安全重写（task 4.2）', () {
    test('本工具生成的文件被识别为可管理', () {
      ArtexOverrideStore.instance.write(
        tempDir.path,
        const ArtexEngineConfig(),
      );
      expect(ArtexOverrideStore.instance.isManaged(tempDir.path), isTrue);
    });

    test('外部文件不被识别为可管理', () {
      File(projectPath()).writeAsStringSync('services:\n  artex: {}\n');
      expect(ArtexOverrideStore.instance.isManaged(tempDir.path), isFalse);
    });

    test('非托管文件被备份到 AppPaths.artexDir 而不是静默覆盖', () {
      File(projectPath()).writeAsStringSync('# 我的手写配置\nservices: {}\n');
      final backedUp = ArtexOverrideStore.instance.write(
        tempDir.path,
        const ArtexEngineConfig(httpPort: 9100),
      );
      expect(backedUp, isTrue);
      // 新内容生效
      expect(
        ArtexOverrideStore.instance.read(tempDir.path),
        contains('"127.0.0.1:9100:8787"'),
      );
      // 原内容备份保留
      final backups = AppPaths.artexDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('docker-compose.override.yml.bak-'));
      expect(backups, hasLength(1));
      expect(backups.single.readAsStringSync(), contains('# 我的手写配置'));
    });

    test('托管文件重写不产生备份', () {
      ArtexOverrideStore.instance.write(
        tempDir.path,
        const ArtexEngineConfig(),
      );
      final backedUp = ArtexOverrideStore.instance.write(
        tempDir.path,
        const ArtexEngineConfig(httpPort: 9200),
      );
      expect(backedUp, isFalse);
    });
  });

  group('端口变化更新（task 4.3）', () {
    test('端口变化后 override 内容随之更新', () {
      final store = ArtexOverrideStore.instance;
      store.write(tempDir.path, const ArtexEngineConfig(httpPort: 8787));
      store.write(tempDir.path, const ArtexEngineConfig(httpPort: 8788));
      final content = store.read(tempDir.path)!;
      expect(content, contains('"127.0.0.1:8788:8787"'));
      expect(content, isNot(contains('"127.0.0.1:8787:8787"')));
    });
  });

  group('删除', () {
    test('只删本工具生成的', () {
      final store = ArtexOverrideStore.instance;
      store.write(tempDir.path, const ArtexEngineConfig());
      expect(store.remove(tempDir.path), isTrue);
      expect(File(projectPath()).existsSync(), isFalse);
    });

    test('不删外部文件', () {
      File(projectPath()).writeAsStringSync('# 手写\n');
      expect(ArtexOverrideStore.instance.remove(tempDir.path), isFalse);
      expect(File(projectPath()).existsSync(), isTrue);
    });

    test('文件不存在时返回 false 而不抛', () {
      expect(ArtexOverrideStore.instance.remove(tempDir.path), isFalse);
    });
  });
}
