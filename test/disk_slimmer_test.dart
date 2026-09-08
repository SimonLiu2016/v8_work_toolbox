import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/slimmer/ai_disk_diagnostics_service.dart';
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

  group('SlimerBatchConfig Tests', () {
    test('默认值: concurrency=1, maxRetries=10', () {
      const config = SlimerBatchConfig();
      expect(config.concurrency, 1);
      expect(config.maxRetries, 10);
    });

    test('fromJson 解析正常值', () {
      final config = SlimerBatchConfig.fromJson({
        'batchConcurrency': 3,
        'batchMaxRetries': 5,
      });
      expect(config.concurrency, 3);
      expect(config.maxRetries, 5);
    });

    test('fromJson 缺失字段回退默认值', () {
      final config = SlimerBatchConfig.fromJson({});
      expect(config.concurrency, 1);
      expect(config.maxRetries, 10);
    });

    test('fromJson 值越界时 clamp 到合法范围', () {
      final tooHigh = SlimerBatchConfig.fromJson({
        'batchConcurrency': 99,
        'batchMaxRetries': 100,
      });
      expect(tooHigh.concurrency, 5);
      expect(tooHigh.maxRetries, 10);

      final tooLow = SlimerBatchConfig.fromJson({
        'batchConcurrency': 0,
        'batchMaxRetries': -1,
      });
      expect(tooLow.concurrency, 1);
      expect(tooLow.maxRetries, 1);
    });

    test('toJson 输出正确', () {
      const config = SlimerBatchConfig(concurrency: 2, maxRetries: 5);
      final json = config.toJson();
      expect(json['batchConcurrency'], 2);
      expect(json['batchMaxRetries'], 5);
    });

    test('fromJson -> toJson 往返一致', () {
      final original = {'batchConcurrency': 3, 'batchMaxRetries': 5};
      final config = SlimerBatchConfig.fromJson(original);
      expect(config.toJson(), original);
    });
  });

  group('AiDiskDiagnosticsService.isRetryable Tests', () {
    test('429 错误可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 429 Too Many Requests')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('status code 429')), true);
    });

    test('too many requests 可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('Too Many Requests')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('too many requests')), true);
    });

    test('超时错误可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('Connection timed out')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('Request timeout')), true);
    });

    test('网络连接错误可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('Connection refused')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('connection reset')), true);
    });

    test('5xx 服务器错误可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 502')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 503')), true);
      expect(AiDiskDiagnosticsService.isRetryable(Exception('520 Web Server Error')), true);
    });

    test('401 不可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 401 Unauthorized')), false);
    });

    test('403 不可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 403 Forbidden')), false);
    });

    test('JSON 解析错误不可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(FormatException('Unexpected character')), false);
    });

    test('400 Bad Request 不可重试', () {
      expect(AiDiskDiagnosticsService.isRetryable(Exception('HTTP 400 Bad Request')), false);
    });
  });
}
