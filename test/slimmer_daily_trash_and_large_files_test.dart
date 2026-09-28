import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/system_service.dart';
import 'package:V8WorkToolbox/tools/slimmer/daily_app_cache_detector.dart';
import 'package:V8WorkToolbox/tools/slimmer/installer_detector.dart';
import 'package:V8WorkToolbox/tools/slimmer/large_file_scanner.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';

void main() {
  group('废纸篓指标与清空测试', () {
    test('TrashMetrics 空状态与非空状态判定', () {
      const empty = TrashMetrics(totalBytes: 0, itemCount: 0);
      expect(empty.isEmpty, isTrue);

      const non = TrashMetrics(totalBytes: 1024 * 1024 * 50, itemCount: 12);
      expect(non.isEmpty, isFalse);
      expect(non.totalBytes, 1024 * 1024 * 50);
      expect(non.itemCount, 12);
    });

    test('getTrashMetrics 能够安全执行并返回有效指标', () async {
      final metrics = await SystemService.instance.getTrashMetrics();
      expect(metrics.totalBytes, greaterThanOrEqualTo(0));
      expect(metrics.itemCount, greaterThanOrEqualTo(0));
    });
  });

  group('活跃日常应用缓存与系统日志探测测试', () {
    late Directory tempDir;
    late Directory mockAppDir;
    late Directory mockHome;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8_cache_test_');
      mockAppDir = Directory(p.join(tempDir.path, 'Applications'))..createSync(recursive: true);
      mockHome = Directory(p.join(tempDir.path, 'Home'))..createSync(recursive: true);

      // 创建 Mock 微信 App
      final wechatApp = Directory(p.join(mockAppDir.path, 'WeChat.app', 'Contents'))..createSync(recursive: true);
      File(p.join(wechatApp.path, 'Info.plist')).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.tencent.xinWeChat</string>
  <key>CFBundleDisplayName</key>
  <string>微信</string>
</dict>
</plist>
''');

      // 创建 Mock Chrome App
      final chromeApp = Directory(p.join(mockAppDir.path, 'Google Chrome.app', 'Contents'))..createSync(recursive: true);
      File(p.join(chromeApp.path, 'Info.plist')).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.google.Chrome</string>
  <key>CFBundleDisplayName</key>
  <string>Google Chrome</string>
</dict>
</plist>
''');

      // 创建 Mock Caches 目录（超过 500KB）
      final wechatCache = Directory(p.join(mockHome.path, 'Library', 'Caches', 'com.tencent.xinWeChat'))..createSync(recursive: true);
      File(p.join(wechatCache.path, 'cached_image.dat')).writeAsBytesSync(List.filled(600 * 1024, 0));

      final chromeCache = Directory(p.join(mockHome.path, 'Library', 'Caches', 'com.google.Chrome'))..createSync(recursive: true);
      File(p.join(chromeCache.path, 'web_cache.dat')).writeAsBytesSync(List.filled(800 * 1024, 0));

      // 创建 Mock Logs 目录（大于 10MB）
      final logsDir = Directory(p.join(mockHome.path, 'Library', 'Logs'))..createSync(recursive: true);
      File(p.join(logsDir.path, 'system.log')).writeAsBytesSync(List.filled(11 * 1024 * 1024, 0));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('动态识别微信与 Chrome 缓存，且敏感即时通讯工具默认不勾选', () async {
      final detector = DailyAppCacheDetector(
        customHome: mockHome.path,
        customAppDirs: [mockAppDir],
      );

      await detector.initialize();
      final items = await detector.scanDailyCaches();

      expect(items, isNotEmpty);

      // 验证微信项
      final wechat = items.firstWhere((it) => it.path.contains('com.tencent.xinWeChat'));
      expect(wechat.title, contains('微信'));
      expect(wechat.category, SlimmerCategory.dailyAppCache);
      expect(wechat.safety, SafetyRating.caution);
      expect(wechat.isSelected, isFalse, reason: '敏感通讯软件缓存默认不可自动勾选');

      // 验证 Chrome 项
      final chrome = items.firstWhere((it) => it.path.contains('com.google.Chrome'));
      expect(chrome.title, contains('Google Chrome'));
      expect(chrome.category, SlimmerCategory.dailyAppCache);
      expect(chrome.safety, SafetyRating.safe);
      expect(chrome.isSelected, isTrue, reason: '浏览器临时网络缓存默认勾选');

      // 验证系统日志项
      final logs = items.firstWhere((it) => it.id == 'system_logs');
      expect(logs.title, contains('系统与应用运行日志'));
      expect(logs.category, SlimmerCategory.dailyAppCache);
      expect(logs.safety, SafetyRating.safe);
      expect(logs.isSelected, isTrue);
    });
  });

  group('废弃安装包探测器测试', () {
    late Directory tempDir;
    late Directory downloadsDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8_installer_test_');
      downloadsDir = Directory(p.join(tempDir.path, 'Downloads'))..createSync(recursive: true);

      // 1. 旧安装包 (>7 天，15MB)
      final oldFile = File(p.join(downloadsDir.path, 'Docker_old.dmg'));
      oldFile.writeAsBytesSync(List.filled(15 * 1024 * 1024, 0));
      oldFile.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 15)));

      // 2. 近期安装包 (<=7 天，12MB)
      final recentFile = File(p.join(downloadsDir.path, 'VSCode_recent.pkg'));
      recentFile.writeAsBytesSync(List.filled(12 * 1024 * 1024, 0));
      recentFile.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));

      // 3. 小文件 (小于 10MB 忽略)
      final smallFile = File(p.join(downloadsDir.path, 'small.dmg'));
      smallFile.writeAsBytesSync(List.filled(1024, 0));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('根据天数区分推荐勾选，并忽略小安装包', () async {
      final detector = InstallerDetector(
        customHome: tempDir.path,
        customTargetDirs: [downloadsDir],
      );

      final items = await detector.scanInstallers();
      expect(items.length, 2);

      final oldItem = items.firstWhere((it) => it.title == 'Docker_old.dmg');
      expect(oldItem.category, SlimmerCategory.installers);
      expect(oldItem.isSelected, isTrue, reason: '15天前下载的安装包应默认勾选');

      final recentItem = items.firstWhere((it) => it.title == 'VSCode_recent.pkg');
      expect(recentItem.category, SlimmerCategory.installers);
      expect(recentItem.isSelected, isFalse, reason: '2天前下载的近期安装包应默认不勾选');
    });
  });

  group('超大单体文件发现探测器测试', () {
    late Directory tempDir;
    late File videoFile;
    late File isoFile;
    late File smallFile;
    late File gitObjectFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8_large_file_test_');

      videoFile = File(p.join(tempDir.path, 'demo_presentation.mp4'))..writeAsBytesSync(List.filled(150 * 1024, 0)); // mock file
      isoFile = File(p.join(tempDir.path, 'ubuntu_server.iso'))..writeAsBytesSync(List.filled(300 * 1024, 0));
      smallFile = File(p.join(tempDir.path, 'readme.txt'))..writeAsBytesSync(List.filled(1024, 0));

      final gitDir = Directory(p.join(tempDir.path, '.git', 'objects'))..createSync(recursive: true);
      gitObjectFile = File(p.join(gitDir.path, 'pack-123.pack'))..writeAsBytesSync(List.filled(200 * 1024, 0));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('体积降序排列，排除 git 内部对象并识别类型标签', () async {
      final scanner = LargeFileScanner(
        minSizeBytes: 100 * 1024, // 为测试设置 100KB 阈值
        mockFiles: [videoFile, isoFile, smallFile, gitObjectFile],
      );

      final items = await scanner.scanLargeFiles();
      expect(items.length, 2);

      // 第一名是体积最大的 iso
      expect(items[0].title, 'ubuntu_server.iso');
      expect(items[0].appName, '磁盘镜像/固件');
      expect(items[0].category, SlimmerCategory.largeFiles);
      expect(items[0].safety, SafetyRating.caution);
      expect(items[0].isSelected, isFalse);

      // 第二名是视频
      expect(items[1].title, 'demo_presentation.mp4');
      expect(items[1].appName, '高清视频');

      // 验证降序
      expect(items[0].sizeBytes, greaterThan(items[1].sizeBytes));
    });
  });
}
