import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';

/// 累计使用次数（常用软件的排名依据）。
///
/// 与「最近使用」分成两份数据是本 change 的核心决策：前者答「用得最多」，
/// 后者答「刚才用过」。这里验计数本身的持久化、幂等累积、屏蔽非正数与
/// 已下线 id，以及它与 recentTools 互不干扰。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('v8_counts_test_');
    await SettingsStore.instance.init(rootDir: tempRoot);
    SettingsStore.instance.setToolUsageCountsForTest(const {});
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('usage counts', () {
    test('absent by default', () {
      expect(SettingsStore.instance.getToolUsageCounts(), isEmpty);
    });

    test('bump accumulates and persists across re-init', () async {
      await SettingsStore.instance.recordToolUsed('notebook');
      await SettingsStore.instance.recordToolUsed('ai-assistant');
      await SettingsStore.instance.recordToolUsed('notebook');

      expect(SettingsStore.instance.getToolUsageCounts(), {
        'notebook': 2,
        'ai-assistant': 1,
      });

      await SettingsStore.instance.init(rootDir: tempRoot);
      expect(SettingsStore.instance.getToolUsageCounts(), {
        'notebook': 2,
        'ai-assistant': 1,
      });
    });

    test('recordToolUsed still maintains recency independently', () async {
      await SettingsStore.instance.recordToolUsed('notebook');
      await SettingsStore.instance.recordToolUsed('ai-assistant');
      await SettingsStore.instance.recordToolUsed('notebook');

      // 两份数据互不干扰：notebook 次数 2、ai-assistant 1，而最近使用序由
      // 最后一次点击决定——末次是 notebook，故它在 recent 首位。若把二者混成
      // 一份（早前的 move-to-front 实现），次数信息根本不存在。
      expect(SettingsStore.instance.getRecentToolIds().first, 'notebook');
      expect(SettingsStore.instance.getRecentToolIds(), ['notebook', 'ai-assistant']);
      expect(SettingsStore.instance.getToolUsageCounts(), {
        'notebook': 2,
        'ai-assistant': 1,
      });
    });

    test('ranks by count descending, ties broken by id', () {
      SettingsStore.instance.setToolUsageCountsForTest({
        'batch-rename': 3,
        'notebook': 5,
        'ai-assistant': 5,
        'vocab-book': 3,
        'ops-tool': 1,
      });

      expect(SettingsStore.instance.getMostUsedToolIds(limit: 3), [
        'ai-assistant', // 5，同次数按 id 字典序在 notebook 之前
        'notebook', // 5
        'batch-rename', // 3，同次数按 id 字典序在 vocab-book 之前
      ]);
    });

    test('ignores non-positive and non-int values on read', () {
      // 直接写畸形数据：读取必须静默过滤，而不是把 NaN/负数带进排序。
      SettingsStore.instance.setToolUsageCountsForTest({'notebook': 4});
      SettingsStore.instance.setToolUsageCountsForTest({
        'notebook': 0,
        'batch-rename': -3,
        'ai-assistant': 2,
      });

      expect(SettingsStore.instance.getToolUsageCounts(), {'ai-assistant': 2});
    });

    test('retired ids are redirected on read', () {
      // clean-builds 已迁移到 smart-disk-slimmer；旧计数应并入承接工具，
      // 而不是变成一个点不开的条目。
      SettingsStore.instance.setToolUsageCountsForTest({
        'clean-builds': 6,
        'smart-disk-slimmer': 2,
      });

      expect(SettingsStore.instance.getToolUsageCounts(), {
        'smart-disk-slimmer': 8,
      });
    });
  });
}
