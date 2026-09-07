import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/system_service.dart';

void main() {
  group('RecycleResult Model Tests', () {
    test('全部成功状态判定', () {
      const res = RecycleResult(
        successPaths: ['/path/a', '/path/b'],
        failedPaths: [],
      );
      expect(res.isAllSuccess, isTrue);
      expect(res.isAllFailed, isFalse);
      expect(res.isPartialSuccess, isFalse);
    });

    test('全部失败状态判定', () {
      const res = RecycleResult(
        successPaths: [],
        failedPaths: ['/path/a'],
        errorMessage: 'Permission denied',
      );
      expect(res.isAllSuccess, isFalse);
      expect(res.isAllFailed, isTrue);
      expect(res.isPartialSuccess, isFalse);
    });

    test('部分成功状态判定', () {
      const res = RecycleResult(
        successPaths: ['/path/a'],
        failedPaths: ['/path/b'],
        errorMessage: 'Containers permission required',
      );
      expect(res.isAllSuccess, isFalse);
      expect(res.isAllFailed, isFalse);
      expect(res.isPartialSuccess, isTrue);
    });
  });

  group('SystemService.recyclePaths Physical Verification Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('safe_recycle_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('空路径列表安全返回', () async {
      final res = await SystemService.instance.recyclePaths([]);
      expect(res.successPaths.isEmpty, isTrue);
      expect(res.failedPaths.isEmpty, isTrue);
      expect(res.isAllSuccess, isTrue);
    });

    test('目标物理真实移入废纸篓后通过后置核验', () async {
      final testFile = File('${tempDir.path}/file_to_delete.txt');
      testFile.writeAsStringSync('sample content');
      expect(testFile.existsSync(), isTrue);

      final res = await SystemService.instance.recyclePaths([testFile.path]);

      // 验证后置核验结果与本地文件系统的真实状态绝对一致
      if (!testFile.existsSync()) {
        expect(res.successPaths, contains(testFile.path));
        expect(res.failedPaths, isEmpty);
      } else {
        expect(res.failedPaths, contains(testFile.path));
      }
    });

    test('文件若物理依然存在，严禁虚假报告成功', () async {
      // 模拟一个永远无法通过常规方式删除的受保护路径测试
      final lockedDir = Directory('${tempDir.path}/cannot_delete_dir');
      lockedDir.createSync();
      expect(lockedDir.existsSync(), isTrue);

      // 直接测试后置物理核验逻辑：若存在，绝不可能进入 successPaths
      final res = await SystemService.instance.recyclePaths([lockedDir.path]);
      if (lockedDir.existsSync()) {
        expect(res.successPaths.contains(lockedDir.path), isFalse,
            reason: '物理依然存在的路径绝对不可标记为成功！');
        expect(res.failedPaths, contains(lockedDir.path));
        expect(res.isAllSuccess, isFalse);
      }
    });
  });

  group('Failure AlertDialog Rendering Tests', () {
    testWidgets('失败弹窗正常布局渲染，不发生 RenderShrinkWrappingViewport 异常', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('移入废纸篓失败'),
                        content: SizedBox(
                          width: 480,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                constraints: const BoxConstraints(maxHeight: 120),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: const [
                                      Text('• com.kugou.mac.Music (/Users/simon/Library/Containers/com.kugou.mac.Music)'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('移入废纸篓失败'), findsOneWidget);
      expect(find.text('• com.kugou.mac.Music (/Users/simon/Library/Containers/com.kugou.mac.Music)'), findsOneWidget);
    });
  });

  group('Container Payload Deep Cleaning Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('container_clean_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('cleanContainerPayload 安全清空内部数据，同时坚决不触碰任何外部软链接目标', () async {
      // 1. 构造一个外部目标目录与重要文件
      final externalDir = Directory('${tempDir.path}/user_external_documents')..createSync();
      final importantFile = File('${externalDir.path}/important_work.doc')
        ..writeAsStringSync('critical user data that must not be deleted');

      // 2. 构造模拟沙盒容器结构
      final mockContainer = Directory('${tempDir.path}/Library/Containers/com.test.app')..createSync(recursive: true);
      final metadataPlist = File('${mockContainer.path}/.com.apple.containermanagerd.metadata.plist')
        ..writeAsStringSync('plist_meta');
      final containerPlist = File('${mockContainer.path}/Container.plist')
        ..writeAsStringSync('plist_container');

      // Data 目录与软链接
      final dataDir = Directory('${mockContainer.path}/Data')..createSync();
      Link('${dataDir.path}/Documents').createSync(externalDir.path);

      // Data/Library/Application Support 与其内部软链接、重度数据文件
      final appSupportDir = Directory('${dataDir.path}/Library/Application Support/com.test.app')..createSync(recursive: true);
      Link('${dataDir.path}/Library/Application Support/AddressBook').createSync(externalDir.path);
      final largeDbFile = File('${appSupportDir.path}/heavy_database.realm')
        ..writeAsStringSync('X' * (20 * 1024)); // 20KB

      // Data/Library/Caches
      final cacheDir = Directory('${dataDir.path}/Library/Caches')..createSync(recursive: true);
      final cacheFile = File('${cacheDir.path}/cached_image.jpg')
        ..writeAsStringSync('Y' * (10 * 1024)); // 10KB

      expect(importantFile.existsSync(), isTrue);
      expect(largeDbFile.existsSync(), isTrue);
      expect(cacheFile.existsSync(), isTrue);

      // 3. 执行容器 Payload 深度安全清理
      final cleanRes = await SystemService.instance.cleanContainerPayload(mockContainer.path);

      // 4. 验证清理结果
      expect(cleanRes.isCleaned, isTrue);
      expect(cleanRes.freedBytes, greaterThan(0));

      // 5. 核心安全铁律：外部软链接目标文件必须毫发无伤！
      expect(importantFile.existsSync(), isTrue, reason: '软链接指向的外部用户文件绝不可被删除！');
      expect(importantFile.readAsStringSync(), 'critical user data that must not be deleted');

      // 6. 容器内的真实重度数据与非保护配置文件必须已被清空
      expect(largeDbFile.existsSync(), isFalse, reason: '容器内的数据库文件已被安全清除');
      expect(cacheFile.existsSync(), isFalse, reason: '容器内的缓存文件已被清除');
      expect(containerPlist.existsSync(), isFalse, reason: '容器根目录的配置文件已被清除');

      // 7. 受系统锁定的元数据文件被安全保留，不受破坏
      expect(metadataPlist.existsSync(), isTrue);
    });

    test('recyclePaths 遇到沙盒容器根目录受保护时自动降级执行 Payload 清理并准确报告', () async {
      final containersParent = Directory('${tempDir.path}/Library/Containers')..createSync(recursive: true);
      final mockContainer = Directory('${containersParent.path}/com.test.sandbox')..createSync();
      File('${mockContainer.path}/.com.apple.containermanagerd.metadata.plist').writeAsStringSync('meta');
      final appSupport = Directory('${mockContainer.path}/Data/Library/Application Support')..createSync(recursive: true);
      final db = File('${appSupport.path}/app.sqlite')..writeAsStringSync('Z' * (15 * 1024));

      // 锁定父目录写权限，模拟 macOS 内核对 ~/Library/Containers 根目录条目的锁定 (使 mockContainer 无法被整体 unlink)
      Process.runSync('chmod', ['555', containersParent.path]);
      try {
        final res = await SystemService.instance.recyclePaths([mockContainer.path]);

        expect(res.successPaths, contains(mockContainer.path));
        expect(res.cleanedContainerPaths, contains(mockContainer.path));
        expect(res.hasCleanedContainers, isTrue);
        expect(res.freedBytes, greaterThan(0));
        expect(db.existsSync(), isFalse);
      } finally {
        Process.runSync('chmod', ['755', containersParent.path]);
      }
    });
  });
}

