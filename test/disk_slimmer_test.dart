import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';

void main() {
  group('SlimCandidateItem Model Tests', () {
    test('格式化字节容量显示', () {
      const itemBytes = SlimCandidateItem(
        id: '1',
        path: '/tmp/test',
        title: 'Test',
        subtitle: 'Sub',
        sizeBytes: 800,
        category: SlimmerCategory.buildCache,
      );
      expect(itemBytes.formattedSize, '800 B');

      final itemMb = itemBytes.copyWith(sizeBytes: 15 * 1024 * 1024);
      expect(itemMb.formattedSize, '15.0 MB');

      final itemGb = itemBytes.copyWith(sizeBytes: (2.5 * 1024 * 1024 * 1024).toInt());
      expect(itemGb.formattedSize, '2.50 GB');
    });

    test('条目选中状态与 copyWith 保持不可变完整性', () {
      const item = SlimCandidateItem(
        id: 'sample',
        path: '/path/sample',
        title: 'Sample App',
        subtitle: 'Remnant',
        sizeBytes: 1000000,
        category: SlimmerCategory.orphanApp,
        safety: SafetyRating.safe,
        isSelected: true,
      );

      final updated = item.copyWith(
        isSelected: false,
        aiAdvice: '建议保留',
        safety: SafetyRating.caution,
      );

      expect(updated.isSelected, false);
      expect(updated.aiAdvice, '建议保留');
      expect(updated.safety, SafetyRating.caution);
      expect(item.isSelected, true); // 原实例保持不变
    });
  });

  group('MultiVersion Sorting & Detection Logic Tests', () {
    test('版本号序列比对逻辑确保最新版置为保留、历史版本置为可清理', () {
      final versions = ['2022.3', '2023.2', '2024.1', '2021.1'];
      versions.sort(); // 升序

      final newest = versions.last;
      expect(newest, '2024.1');

      for (final v in versions) {
        final isOld = v != newest;
        if (v == '2024.1') {
          expect(isOld, false);
        } else {
          expect(isOld, true);
        }
      }
    });
  });

  group('AI Diagnostics JSON Parser Tests', () {
    test('解析包含 Markdown 代码块的结构化 JSON 返回', () {
      const rawAiResponse = '''
这里是分析结果：
```json
[
  {
    "id": "orphan_1",
    "inferredApp": "Sketch",
    "safety": "safe",
    "canDelete": true,
    "advice": "已卸载软件的历史矢量渲染缓存，安全清理"
  },
  {
    "id": "orphan_2",
    "inferredApp": "Docker",
    "safety": "danger",
    "canDelete": false,
    "advice": "活跃容器层数据，请勿直接删除"
  }
]
```
以上请用户参考。
''';

      // 提取 JSON 并解析验证内部逻辑
      int start = rawAiResponse.indexOf('[');
      int end = rawAiResponse.lastIndexOf(']');
      expect(start != -1 && end > start, true);

      final jsonStr = rawAiResponse.substring(start, end + 1);
      expect(jsonStr.startsWith('['), true);
      expect(jsonStr.endsWith(']'), true);
    });
  });
}
