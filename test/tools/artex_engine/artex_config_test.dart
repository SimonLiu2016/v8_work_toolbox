import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/artex_engine/models/artex_engine_config.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_config_store.dart';

void main() {
  group('ArtexEngineConfig 默认值与解析', () {
    test('默认值为 spike 验证过的取值', () {
      const c = ArtexEngineConfig();
      expect(c.projectDir, '/Users/simon/Workspace/github/artex-ymh');
      expect(c.httpPort, 8787);
      expect(c.proxyPort, 8788);
      expect(c.stopOnAppExit, isTrue);
      expect(c.gateOff, isTrue);
      expect(c.npmRegistry, 'https://registry.npmmirror.com');
      expect(c.goProxy, 'https://goproxy.cn,direct');
      expect(c.aptMirror, 'mirrors.aliyun.com');
    });

    test('空 JSON 得到默认配置', () {
      expect(ArtexEngineConfig.fromJson({}).httpPort, 8787);
    });

    test('端口接受字符串形式（手改配置文件时常见）', () {
      final c = ArtexEngineConfig.fromJson({'httpPort': '9090'});
      expect(c.httpPort, 9090);
    });

    test('端口非法时回退默认值而不是抛异常', () {
      expect(ArtexEngineConfig.fromJson({'httpPort': 'abc'}).httpPort, 8787);
      expect(ArtexEngineConfig.fromJson({'httpPort': null}).httpPort, 8787);
    });

    test('空字符串字段回退默认值', () {
      final c = ArtexEngineConfig.fromJson({
        'projectDir': '   ',
        'npmRegistry': '',
      });
      expect(c.projectDir, ArtexEngineConfig.defaultProjectDir);
      expect(c.npmRegistry, ArtexEngineConfig.defaultNpmRegistry);
    });

    test('布尔缺省为 true（退出即停与关门控都是安全默认）', () {
      final c = ArtexEngineConfig.fromJson({});
      expect(c.stopOnAppExit, isTrue);
      expect(c.gateOff, isTrue);
    });

    test('toJson / fromJson 往返不丢字段', () {
      const original = ArtexEngineConfig(
        projectDir: '/tmp/x',
        httpPort: 18000,
        proxyPort: 18001,
        stopOnAppExit: false,
        gateOff: false,
        npmRegistry: 'r',
        goProxy: 'g',
        aptMirror: 'a',
      );
      final round = ArtexEngineConfig.fromJson(original.toJson());
      expect(round.projectDir, original.projectDir);
      expect(round.httpPort, original.httpPort);
      expect(round.proxyPort, original.proxyPort);
      expect(round.stopOnAppExit, original.stopOnAppExit);
      expect(round.gateOff, original.gateOff);
      expect(round.npmRegistry, original.npmRegistry);
      expect(round.goProxy, original.goProxy);
      expect(round.aptMirror, original.aptMirror);
    });
  });

  group('工程目录定位（spec: Compose 工程定位）', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('artex_locate');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('目录不存在时报「目录不存在」', () {
      final r = ArtexConfigStore.instance.locateProject(
        '${tempDir.path}/nope',
      );
      expect(r.ok, isFalse);
      expect(r.reason, contains('工程目录不存在'));
    });

    test('目录存在但缺 compose 文件时报另一条原因', () {
      final r = ArtexConfigStore.instance.locateProject(tempDir.path);
      expect(r.ok, isFalse);
      expect(r.reason, contains('docker-compose.yml'));
    });

    test('目录与 compose 文件都在时定位成功', () {
      File('${tempDir.path}/docker-compose.yml').writeAsStringSync(
        'services: {}',
      );
      final r = ArtexConfigStore.instance.locateProject(tempDir.path);
      expect(r.ok, isTrue);
      expect(r.path, tempDir.path);
    });

    test('空路径给出未配置提示', () {
      final r = ArtexConfigStore.instance.locateProject('   ');
      expect(r.ok, isFalse);
      expect(r.reason, contains('未配置'));
    });
  });
}
