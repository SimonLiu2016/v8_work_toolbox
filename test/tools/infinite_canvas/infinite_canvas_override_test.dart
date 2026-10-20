import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_config.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_override_store.dart';

/// override 生成的契约测试（spec: 运行时配置以 override 注入）。
///
/// 与 Toonflow 版的差异：只剩两件事——回环端口与可选镜像覆盖。没有 bind
/// mount、没有 `user:` 对齐（nginx 不写盘）。
///
/// 固定四件事：
/// 1. 只绑 `127.0.0.1`，不对局域网暴露（上游默认 `"3000:3000"` 绑全部网卡）；
/// 2. `!override` 标签带上了（不带 compose 的默认合并行为是追加，3000 会同时
///    绑两个端口）；
/// 3. 服务名是上游的 `app`；
/// 4. 非本工具生成的文件先备份而不是直接覆盖。
void main() {
  late Directory tempDir;
  late Directory projectDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ic_override');
    AppPaths.overrideRootForTesting(tempDir);
    projectDir = Directory(p.join(tempDir.path, 'infinite-canvas'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('render', () {
    test('回环端口与服务名', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(httpPort: 3177),
      );
      final decoded = InfiniteCanvasOverrideStore.decodeOverride(yaml);
      expect(decoded['service'], 'app', reason: '上游服务名是 app');
      expect(decoded['hostPort'], '3177');
      expect(yaml, contains('127.0.0.1:3177:3000'));
    });

    test('端口带 !override 标签', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
      );
      // 不带 !override 时 compose 的默认合并行为是追加：3000 会同时绑两个
      // 端口（上游的 "3000:3000" 还在）。
      expect(yaml, contains('ports: !override'));
    });

    test('不含 bind mount 与 user 对齐', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
      );
      // nginx 不写数据目录，这两项在这里是无意义噪音。
      expect(yaml, isNot(contains('volumes')));
      expect(yaml, isNot(contains('user:')));
      expect(yaml, isNot(contains('bind mount')));
    });

    test('不传 image 时不写 image 行', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
      );
      expect(yaml, isNot(contains('image:')));
      expect(
        InfiniteCanvasOverrideStore.decodeOverride(yaml).containsKey('image'),
        isFalse,
      );
    });

    test('传 image 时覆盖上游镜像引用', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
        image: 'infinite-canvas:local',
      );
      expect(
        InfiniteCanvasOverrideStore.decodeOverride(yaml)['image'],
        'infinite-canvas:local',
      );
    });

    test('image 为空串时不当成覆盖', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
        image: '   ',
      );
      expect(yaml, isNot(contains('image:')));
    });

    test('useLocalImage 打开时覆盖成本地镜像 tag', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(useLocalImage: true),
      );
      expect(
        InfiniteCanvasOverrideStore.decodeOverride(yaml)['image'],
        InfiniteCanvasConfig.localImageName,
      );
    });

    test('useLocalImage 关闭时不碰上游镜像引用', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(useLocalImage: false),
      );
      expect(yaml, isNot(contains('image:')));
    });

    test('显式 image 参数优先于 useLocalImage', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(useLocalImage: true),
        image: 'custom:tag',
      );
      expect(
        InfiniteCanvasOverrideStore.decodeOverride(yaml)['image'],
        'custom:tag',
      );
    });

    test('首行是托管标记', () {
      final yaml = InfiniteCanvasOverrideStore.instance.render(
        const InfiniteCanvasConfig(),
      );
      expect(yaml.trimLeft().startsWith(kOverrideMarker), isTrue);
    });

    test('用的是独立文件名而不是 compose 隐式加载的那个', () {
      // compose 会在用户手敲 `docker compose up` 时隐式自动加载
      // docker-compose.override.yml，而我们的命令又显式 -f 了一次。
      expect(kOverrideFileName, 'docker-compose.v8box.yml');
      expect(kOverrideFileName, isNot('docker-compose.override.yml'));
    });
  });

  group('write / isManaged / remove', () {
    test('写出的文件被识别为托管', () {
      final wrote = InfiniteCanvasOverrideStore.instance.write(
        projectDir.path,
        const InfiniteCanvasConfig(),
      );
      expect(wrote, isFalse, reason: '首次写入不该有备份');
      expect(
        InfiniteCanvasOverrideStore.instance.isManaged(projectDir.path),
        isTrue,
      );
    });

    test('托管文件可被重复重写而不产生备份', () {
      final store = InfiniteCanvasOverrideStore.instance;
      store.write(
        projectDir.path,
        const InfiniteCanvasConfig(httpPort: 3177),
      );
      final again = store.write(
        projectDir.path,
        const InfiniteCanvasConfig(httpPort: 4177),
      );
      expect(again, isFalse);
      expect(
        InfiniteCanvasOverrideStore.decodeOverride(
          store.read(projectDir.path)!,
        )['hostPort'],
        '4177',
      );
    });

    test('非托管文件先备份再覆盖', () {
      final file = File(p.join(projectDir.path, kOverrideFileName));
      file.writeAsStringSync('# 我的手写配置\nservices:\n  app: {}\n');

      final backedUp = InfiniteCanvasOverrideStore.instance.write(
        projectDir.path,
        const InfiniteCanvasConfig(),
      );

      expect(backedUp, isTrue, reason: '用户文件被替换必须报告');
      // 备份落在本工具自己的目录里。
      final backups = AppPaths.infiniteCanvasDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.bak-'));
      expect(backups, isNotEmpty);
      // 原内容还在备份里。
      expect(backups.first.readAsStringSync(), contains('我的手写配置'));
    });

    test('remove 只删托管文件', () {
      final store = InfiniteCanvasOverrideStore.instance;
      store.write(projectDir.path, const InfiniteCanvasConfig());
      expect(store.remove(projectDir.path), isTrue);
      expect(
        File(p.join(projectDir.path, kOverrideFileName)).existsSync(),
        isFalse,
      );

      // 非托管文件不动。
      final file = File(p.join(projectDir.path, kOverrideFileName));
      file.writeAsStringSync('# 手写\n');
      expect(store.remove(projectDir.path), isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('文件不存在时 remove 返回 false 而不抛', () {
      expect(
        InfiniteCanvasOverrideStore.instance.remove(projectDir.path),
        isFalse,
      );
    });
  });
}
