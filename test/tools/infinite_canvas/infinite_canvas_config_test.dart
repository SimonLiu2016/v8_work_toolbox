import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_config.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_config_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ic_config');
    AppPaths.overrideRootForTesting(tempDir);
    // SettingsStore 的 configDir 在 init() 时才定；重新 init 让它跟随覆盖后的
    // AppPaths.root，否则测试会写进真实配置目录。
    await SettingsStore.instance.init();
    InfiniteCanvasConfigStore.instance.resetForTesting();
  });

  tearDown(() {
    InfiniteCanvasConfigStore.instance.resetForTesting();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('InfiniteCanvasConfig 序列化', () {
    test('缺省即默认值', () {
      const c = InfiniteCanvasConfig();
      expect(c.projectDir, InfiniteCanvasConfig.defaultProjectDir);
      expect(c.httpPort, 3177);
      expect(c.bridgePort, 8798);
      // 退出即停是安全默认值。
      expect(c.stopOnAppExit, isTrue);
    });

    test('toJson 只写五个键', () {
      final json = const InfiniteCanvasConfig().toJson();
      expect(json.keys.toSet(), <String>{
        'projectDir',
        'httpPort',
        'bridgePort',
        'stopOnAppExit',
        'useLocalImage',
      });
    });

    test('useLocalImage 缺省 false——默认走 ghcr.io 发布版', () {
      expect(const InfiniteCanvasConfig().useLocalImage, isFalse);
      expect(InfiniteCanvasConfig.fromJson(const {}).useLocalImage, isFalse);
    });

    test('端口被手写成字符串时宽容解析', () {
      final c = InfiniteCanvasConfig.fromJson(<String, dynamic>{
        'httpPort': '4000',
        'bridgePort': '5000',
      });
      expect(c.httpPort, 4000);
      expect(c.bridgePort, 5000);
    });

    test('端口是垃圾值时回落默认', () {
      final c = InfiniteCanvasConfig.fromJson(<String, dynamic>{
        'httpPort': 'not-a-port',
        'bridgePort': <dynamic>[],
      });
      expect(c.httpPort, InfiniteCanvasConfig.defaultHttpPort);
      expect(c.bridgePort, InfiniteCanvasConfig.defaultBridgePort);
    });

    test('空字符串路径回落默认', () {
      final c = InfiniteCanvasConfig.fromJson(<String, dynamic>{
        'projectDir': '   ',
      });
      expect(c.projectDir, InfiniteCanvasConfig.defaultProjectDir);
    });

    test('stopOnAppExit 缺省 true', () {
      final c = InfiniteCanvasConfig.fromJson(<String, dynamic>{});
      expect(c.stopOnAppExit, isTrue);
    });

    test('round-trip 保持值', () {
      const original = InfiniteCanvasConfig(
        projectDir: '/tmp/somewhere',
        httpPort: 4001,
        bridgePort: 4002,
        stopOnAppExit: false,
      );
      final restored = InfiniteCanvasConfig.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored, original);
    });

    test('copyWith 只改指定字段', () {
      const original = InfiniteCanvasConfig();
      final next = original.copyWith(httpPort: 4003);
      expect(next.httpPort, 4003);
      expect(next.bridgePort, original.bridgePort);
      expect(next.projectDir, original.projectDir);
      expect(next.stopOnAppExit, original.stopOnAppExit);
    });
  });

  group('locateProject', () {
    test('三种 compose 文件名各自命中', () {
      for (final name in const <String>[
        'compose.yaml',
        'compose.yml',
        'docker-compose.yml',
      ]) {
        final dir = Directory.systemTemp.createTempSync('ic_locate');
        try {
          File('${dir.path}/Dockerfile').writeAsStringSync('FROM scratch');
          File('${dir.path}/$name').writeAsStringSync('services: {}');
          final result = InfiniteCanvasConfigStore.instance.locateProject(
            dir.path,
          );
          expect(result.ok, isTrue, reason: name);
          expect(result.path, dir.path);
          expect(result.composeFile, name, reason: '必须回传实际命中的名字');
        } finally {
          dir.deleteSync(recursive: true);
        }
      }
    });

    test('多个 compose 文件同时存在时按探测顺序取第一个', () {
      final dir = Directory.systemTemp.createTempSync('ic_locate');
      try {
        File('${dir.path}/Dockerfile').writeAsStringSync('FROM scratch');
        File('${dir.path}/compose.yaml').writeAsStringSync('services: {}');
        File('${dir.path}/docker-compose.yml').writeAsStringSync('services: {}');
        final result = InfiniteCanvasConfigStore.instance.locateProject(
          dir.path,
        );
        expect(result.composeFile, 'compose.yaml');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('目录不存在与缺 Dockerfile 给出不同原因', () {
      final missing = InfiniteCanvasConfigStore.instance.locateProject(
        '/nonexistent/path/xyz',
      );
      expect(missing.ok, isFalse);
      expect(missing.reason, contains('工程目录不存在'));

      final dir = Directory.systemTemp.createTempSync('ic_locate');
      try {
        File('${dir.path}/docker-compose.yml').writeAsStringSync(
          'services: {}',
        );
        final noDockerfile = InfiniteCanvasConfigStore.instance.locateProject(
          dir.path,
        );
        expect(noDockerfile.ok, isFalse);
        expect(noDockerfile.reason, contains('Dockerfile'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('缺 compose 文件时把探测过的名字列出来', () {
      final dir = Directory.systemTemp.createTempSync('ic_locate');
      try {
        File('${dir.path}/Dockerfile').writeAsStringSync('FROM scratch');
        final result = InfiniteCanvasConfigStore.instance.locateProject(
          dir.path,
        );
        expect(result.ok, isFalse);
        expect(result.reason, contains('docker-compose.yml'));
        expect(result.reason, contains('compose.yaml'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('未配置目录时报未配置而不是崩溃', () {
      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        const InfiniteCanvasConfig(projectDir: '  '),
      );
      final result = InfiniteCanvasConfigStore.instance.locateProject();
      expect(result.ok, isFalse);
      expect(result.reason, '工程目录未配置');
    });
  });

  group('配置持久化', () {
    test('保存后可读回', () async {
      final store = InfiniteCanvasConfigStore.instance;
      await store.load();
      await store.save(
        const InfiniteCanvasConfig(httpPort: 4321, bridgePort: 8765),
      );
      expect(store.config.httpPort, 4321);

      // 重新读盘，验证真的落盘了而不是只在内存里。
      InfiniteCanvasConfigStore.instance.resetForTesting();
      await store.load();
      expect(store.config.httpPort, 4321);
      expect(store.config.bridgePort, 8765);
    });

    test('配置损坏时回落默认而不是抛异常', () async {
      final file = File(
        '${tempDir.path}/config/$kInfiniteCanvasToolId.json',
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ not valid json');
      final store = InfiniteCanvasConfigStore.instance;
      await store.load();
      expect(store.config.httpPort, InfiniteCanvasConfig.defaultHttpPort);
    });
  });
}
