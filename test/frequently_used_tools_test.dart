import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/shell/app_shell.dart';
import 'package:V8WorkToolbox/tools/registry.dart';

/// 「常用软件」入口（capability: `frequently-used-tools`）。
///
/// 这里验的是排名规则本身：按**累计使用次数**降序取前 5、过滤已下线的 id、
/// 排除隐私分类工具、无记录时为空。AppShell 里的 `_frequentTools()` 是私有方法，
/// 因此用同一套规则的可测复现来断言——两边的一致性由接线保证，本文件守的是
/// 规则不回归。
///
/// 排序由 `SettingsStore.getMostUsedToolIds` 单点持有，这里直接用真实实现，
/// 不再另抄一份（早前抄过一份，后来两边漂移过）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frequently used selection rules', () {
    test('ranks by usage count, most used first', () {
      // 同样的 7 个工具，用次数决定次序——不是最近使用次序。
      final result = pickFrequent({
        'batch-rename': 1,
        'notebook': 9,
        'ai-assistant': 4,
        'vocab-book': 7,
        'ops-tool': 6,
        'bc-config': 5,
        'folder-compare': 2,
      });

      expect(result.map((t) => t.id), [
        'notebook', // 9
        'vocab-book', // 7
        'ops-tool', // 6
        'bc-config', // 5
        'ai-assistant', // 4
      ]);
    });

    test('stops at 5 even when more tools have counts', () {
      final result = pickFrequent({
        'notebook': 10,
        'ai-assistant': 9,
        'vocab-book': 8,
        'ops-tool': 7,
        'bc-config': 6,
        'batch-rename': 5,
        'folder-compare': 4,
      });

      expect(result.length, 5);
      expect(result.map((t) => t.id), isNot(contains('batch-rename')));
      expect(result.map((t) => t.id), isNot(contains('folder-compare')));
    });

    test('excludes private-category tools without shrinking the list below 5', () {
      // 隐私分类工具不进常用软件（该入口无需解锁即可见）。但过滤之后仍要凑满
      // 5 个——只取前 5 再过滤会让入口因为一个隐私工具而只剩 4 个。
      final result = pickFrequent({
        'private-media-player': 20,
        'notebook': 9,
        'ai-assistant': 8,
        'vocab-book': 7,
        'ops-tool': 6,
        'bc-config': 5,
        'batch-rename': 4,
      });

      expect(result.length, 5);
      expect(result.map((t) => t.id), isNot(contains('private-media-player')));
      expect(result.every((t) => t.category != ToolCategory.privacy), isTrue);
    });

    test('counts only — a tool used once does not outrank one used twice', () {
      // 这条守的是「累计次数」而非「最近用过」：前者用一次不会翻盘。
      final result = pickFrequent({'batch-rename': 1, 'notebook': 2});
      expect(result.map((t) => t.id), ['notebook', 'batch-rename']);
    });

    test('no counts yields empty list, so the entry stays hidden', () {
      expect(pickFrequent(const {}), isEmpty);
    });

    test('counts of only private tools yields empty list', () {
      expect(pickFrequent(const {'private-media-player': 12}), isEmpty);
    });

    test('counts for retired ids are ignored', () {
      final result = pickFrequent({'retired-tool-id': 99, 'notebook': 1});
      expect(result.map((t) => t.id), ['notebook']);
    });
  });

  group('category membership', () {
    test('every category has at least one tool', () {
      for (final cat in ToolCategory.values) {
        expect(
          ToolRegistry.getByCategory(cat),
          isNotEmpty,
          reason: '分类 ${cat.label} 为空——活动栏会出现点进去什么都没有的入口',
        );
      }
    });

    test('系统与配置 holds system/configuration tools plus the vault', () {
      // password-vault 有意留在 system：移进 privacy 会让它从「全部工具」掉到
      // 「只在隐私空间可见」，那是本次未要求的可见性变更。名实不符是已知遗留
      // 项（记于 change 的 tasks），不是漏改。
      final titles =
          ToolRegistry.getByCategory(ToolCategory.system).map((t) => t.id).toSet();
      expect(titles, {
        'smart-disk-slimmer',
        'bc-config',
        'bc-shell',
        'app-shortcut',
        'password-vault',
      });
    });

    test('AI, note and ops categories hold their migrated tools', () {
      // ai 分类含 ai-video-studio（2026-10 接入时漏改这条断言，导致它从
      // 接入起就是红的——全量跑还会因并发把失败推成稳定失败）。
      // 改为 toSet 与另两类一致：分类成员顺序不是本断言要保证的东西。
      expect(
        ToolRegistry.getByCategory(ToolCategory.ai).map((t) => t.id).toSet(),
        {'ai-assistant', 'ai-video-studio', 'toonflow-studio'},
      );
      expect(
        ToolRegistry.getByCategory(ToolCategory.note).map((t) => t.id).toSet(),
        {'notebook', 'vocab-book'},
      );
      expect(
        ToolRegistry.getByCategory(ToolCategory.ops).map((t) => t.id).toSet(),
        {'ops-tool', 'unattended-approver', 'auto-registrar'},
      );
    });

    test('privacy category excludes nothing that publicTools expects', () {
      final privacyIds =
          ToolRegistry.getByCategory(ToolCategory.privacy).map((t) => t.id).toSet();
      for (final tool in ToolRegistry.publicTools) {
        expect(
          privacyIds.contains(tool.id),
          isFalse,
          reason: '${tool.id} 同时出现在 publicTools 与隐私分类——锁定态会看到它',
        );
      }
    });

    test('security category holds both the CLI toolbox and the artex engine', () {
      // artex-engine 接入时补上：这条断言之前不存在，所以漏改不会被发现
      // （ai/ops 两类正是这样红了很久）。两个工具并存是刻意设计——
      // 旧工具箱退役与否由用户决定，不由注册表决定。
      expect(
        ToolRegistry.getByCategory(ToolCategory.security).map((t) => t.id).toSet(),
        {'security-toolbox', 'artex-engine'},
      );
    });
  });
}

/// AppShell._frequentTools() 规则的可测复现：把计数灌进 SettingsStore，
/// 走与产品代码同一条排序入口，再施加同样的过滤。
List pickFrequent(Map<String, int> counts) {
  SettingsStore.instance.setToolUsageCountsForTest(counts);
  final out = <ToolDefinition>[];
  for (final id in SettingsStore.instance
      .getMostUsedToolIds(limit: kFrequentToolLimit * 2)) {
    final tool = ToolRegistry.findById(id);
    if (tool == null) continue;
    if (tool.category == ToolCategory.privacy) continue;
    out.add(tool);
    if (out.length >= kFrequentToolLimit) break;
  }
  return out;
}
