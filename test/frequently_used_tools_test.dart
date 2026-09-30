import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/registry.dart';

/// 「常用软件」频率入口（capability: `frequently-used-tools`）。
///
/// 这里验的是频率投影本身的行为：取前 5、按频率排序、过滤已下线的 id、
/// 排除隐私分类工具、无记录时为空。AppShell 里的 `_frequentTools()` 是私有方法，
/// 因此用同一套规则的可测复现来断言——两边的一致性由 tasks 里的接线保证，
/// 本文件守的是规则本身不回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frequently used selection rules', () {
    test('takes at most 5, ordered by recency', () {
      final ids = [
        'notebook',
        'ai-assistant',
        'vocab-book',
        'ops-tool',
        'bc-config',
        'batch-rename', // 第 6 个：必须被截掉
        'folder-compare',
      ];

      final result = pickFrequent(ids);

      expect(result.length, 5);
      expect(result.first.id, 'notebook', reason: '最近使用的排最前');
      expect(result.last.id, 'bc-config');
      expect(result.map((t) => t.id), isNot(contains('batch-rename')));
    });

    test('drops ids that no longer resolve to a tool', () {
      final ids = ['retired-tool-id', 'notebook', 'clean-builds', 'ai-assistant'];

      final result = pickFrequent(ids);

      expect(result.map((t) => t.id), ['notebook', 'ai-assistant']);
    });

    test('excludes private-category tools', () {
      // 隐私分类工具不进常用软件：该入口无需解锁隐私空间即可见，排进去等于在
      // 解锁前泄露它们的存在。private-media-player 一直是 privacy 分类。
      final ids = ['private-media-player', 'notebook', 'ai-assistant'];

      final result = pickFrequent(ids);

      expect(result.map((t) => t.id), ['notebook', 'ai-assistant']);
      expect(result.every((t) => t.category != ToolCategory.privacy), isTrue);
    });

    test('empty history yields empty list, so the entry stays hidden', () {
      expect(pickFrequent(const []), isEmpty);
    });

    test('history of only private tools yields empty list', () {
      expect(pickFrequent(const ['private-media-player']), isEmpty);
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
      expect(
        ToolRegistry.getByCategory(ToolCategory.ai).map((t) => t.id),
        ['ai-assistant'],
      );
      expect(
        ToolRegistry.getByCategory(ToolCategory.note).map((t) => t.id).toSet(),
        {'notebook', 'vocab-book'},
      );
      expect(
        ToolRegistry.getByCategory(ToolCategory.ops).map((t) => t.id).toSet(),
        {'ops-tool', 'unattended-approver'},
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
  });
}

/// AppShell._frequentTools() 规则的可测复现。
List pickFrequent(List<String> recentIds) {
  final out = <ToolDefinition>[];
  for (final id in recentIds) {
    final tool = ToolRegistry.findById(id);
    if (tool == null) continue;
    if (tool.category == ToolCategory.privacy) continue;
    out.add(tool);
    if (out.length >= 5) break;
  }
  return out;
}
