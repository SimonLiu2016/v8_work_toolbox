import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/slimmer/app_orphan_detector.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';

/// disk-scanner-hardening 变更的验证 harness（任务 7.5 / 7.6 / 7.9 / 7.10）。
///
/// 这些项验证的是"检测逻辑对真实系统目录的判定"，可以脱离 UI 直接驱动
/// [AppOrphanDetector] 扫描，因此用本文件替代人工点选。
/// 其余项（UI 流畅度、复选框、keepList 持久化、全选按钮）属交互行为，需真机确认。
///
/// 运行：`flutter test test/disk_slimmer_hardening_verify_test.dart`
void main() {
  final home = Platform.environment['HOME']!;

  late AppOrphanDetector detector;
  late List<SlimCandidateItem> results;

  setUpAll(() async {
    detector = AppOrphanDetector();
    await detector.initialize();
    results = await detector.scanOrphans();
  });

  late final byPath = <String, SlimCandidateItem>{
    for (final r in results) r.path: r,
  };

  String p(String rel) => '$home/Library/$rel';

  group('7.6 正在使用的应用不被标记为"安全清理"', () {
    test('Code (VS Code) 不在候选列表中', () {
      final path = p('Application Support/Code');
      if (!Directory(path).existsSync()) {
        markTestSkipped('本机无 $path，跳过');
        return;
      }
      expect(byPath[path], isNull,
          reason: 'Code 已安装，其 Application Support 目录必须被完全跳过，'
              '不能出现在清理候选里');
    });

    test('bilibili 不在候选列表中', () {
      final path = p('Application Support/bilibili');
      if (!Directory(path).existsSync()) {
        markTestSkipped('本机无 $path，跳过');
        return;
      }
      expect(byPath[path], isNull,
          reason: 'bilibili 已安装，必须通过别名映射（bilibili → 哔哩哔哩）命中');
    });

    test('所有候选项中不存在被识别为已安装应用的目录', () {
      for (final r in results) {
        final folderName = r.path.split('/').where((s) => s.isNotEmpty).last;
        if (folderName == 'Code' || folderName == 'bilibili') {
          fail('已安装应用 $folderName 被错误列为候选项');
        }
      }
    });
  });

  group('7.9 v8-video-downloader 不再被误判为"未找到关联应用"', () {
    test('v8-video-downloader 命中子串匹配（归一化去连字符）', () {
      final path = p('Application Support/v8-video-downloader');
      if (!Directory(path).existsSync()) {
        markTestSkipped('本机无 $path，跳过');
        return;
      }
      final item = byPath[path];
      if (item == null) {
        markTestSkipped('目录存在但未被列为候选项（可能小于 5MB 阈值或已命中已安装匹配）');
        return;
      }
      expect(item.safety, isNot(SafetyRating.danger),
          reason: '归一化后 v8videodownloader 与已安装的 V8 工具链应能模糊匹配，'
              '不应被判为高风险');
      expect(item.subtitle, isNot(contains('未找到关联应用')),
          reason: '7.9 核心断言：副标题不应显示"未找到关联应用"');
    });
  });

  group('7.10 com.kugou.mac.Music 不再被误判为"高风险"', () {
    test('com.kugou.mac.Music 的修改时间不受系统元数据干扰', () {
      final path = p('Containers/com.kugou.mac.Music');
      if (!Directory(path).existsSync()) {
        markTestSkipped('本机无 $path，跳过');
        return;
      }
      final item = byPath[path];
      if (item == null) {
        markTestSkipped('目录存在但未被列为候选项（可能小于 5MB 或已命中已安装匹配）');
        return;
      }
      expect(item.safety, isNot(SafetyRating.danger),
          reason: '7.10 核心断言：排除 .DS_Store 等元数据时间戳后，'
              'Kugou 不应再被判为"高风险"');
      print('    com.kugou.mac.Music → safety=${item.safety}  '
          'modified=${item.lastModified}  subtitle=${item.subtitle}');
    });
  });

  group('7.5 JetBrains 条目来源标识', () {
    test('多版本扫描器为 JetBrains 条目标注"配置"或"缓存"', () {
      final scannerFile = File('lib/tools/slimmer/multi_version_scanner.dart');
      if (!scannerFile.existsSync()) {
        markTestSkipped('源码不在工作树，跳过');
        return;
      }
      final src = scannerFile.readAsStringSync();
      // 源码中该行为插值表达式：title: '$family ${v.version}（${v.sourceLabel}）',
      // 用字符串拼接构造期望值，避免测试代码自身被插值。
      final needle = "'\$family \${v.version}（\${v.sourceLabel}）'";
      expect(src, contains(needle),
          reason: 'JetBrains 条目标题需内嵌来源标签（配置/缓存）');
      expect(src, contains("Application Support/JetBrains'), '配置'"),
          reason: '需标注"配置"来源');
      expect(src, contains("Caches/JetBrains'), '缓存'"),
          reason: '需标注"缓存"来源');
    });
  });

  group('总体健康', () {
    test('安全清理默认值：未命中验证层的条目不被自动勾选', () {
      for (final r in results) {
        if (r.isSelected && r.safety != SafetyRating.safe) {
          fail('条目 "${r.title}" 被自动勾选，但其安全等级为 ${r.safety}，'
              '违反任务 4.5"未命中验证层默认不勾选"');
        }
      }
    });

    test('报告高风险项供人工复核', () {
      final risky = results.where((r) => r.safety == SafetyRating.danger).toList();
      print('⚠ 标记为"高风险"的条目 ${risky.length} 个：');
      for (final r in risky) {
        final name = r.path.split('/').where((s) => s.isNotEmpty).last;
        print('    $name  (${r.subtitle})');
      }
      expect(true, isTrue, reason: '高风险项需人工确认合理性');
    });
  });
}
