import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/tools/slimmer/ai_disk_diagnostics_service.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_ai_rate_limit_test_');
    AiService.instance.clearResolvedChatEndpoints();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HTTP 429 Backoff Retry & Cooldown Exemption Tests', () {
    test('遇到 429 时自动等待退避并重试成功', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        // 第一次请求返回 429
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'error': {'code': '429', 'message': 'Too many requests'}
            }),
            429,
          );
        }
        // 第二次重试返回 200
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Success after 429 retry!'}
              }
            ]
          }),
          200,
        );
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'p_429_test',
        name: '429 Test Provider',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_429',
      );

      await AiConfigStore.instance.init(customRootDir: tempDir);
      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-test');
      await AiConfigStore.instance.addSlotCandidate('text', provider.id, 'gpt-4o');

      final result = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
      );

      expect(result.text, 'Success after 429 retry!');
      expect(requestCount, 2); // 证实触发了自动重试
    });

    test('429 错误不触发 60 秒硬冷却锁定', () {
      final service = AiService.instance;
      service.cooldownDuration = const Duration(seconds: 60);

      // 模拟触发 429
      service.markProviderUnhealthy('p_rate_limited', 'Exception: HTTP 429, Too many requests');

      // 验证未被标记为冷冻状态
      expect(service.isProviderHealthy('p_rate_limited'), isTrue);

      // 对比：普通 500 错误会被标记为不健康
      service.markProviderUnhealthy('p_server_down', 'Exception: HTTP 500, Server error');
      expect(service.isProviderHealthy('p_server_down'), isFalse);
    });
  });

  group('diagnoseBatch Pacing Delay Tests', () {
    test('批量诊断在条目间执行步频延迟', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '```json\n{"id":"1","inferredApp":"App","safety":"safe","advice":"keep"}\n```'
                }
              }
            ]
          }),
          200,
        );
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'p_batch',
        name: 'Batch Provider',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_batch',
      );

      await AiConfigStore.instance.init(customRootDir: tempDir);
      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-test');
      await AiConfigStore.instance.addSlotCandidate('text', provider.id, 'gpt-4o');

      final diagService = AiDiskDiagnosticsService.instance;
      // 串行模式下条目间存在默认步频延迟（800ms），此处以最小阈值断言其行为存在

      final items = [
        const SlimCandidateItem(
          id: 'item_1',
          title: 'Item 1',
          subtitle: 'sub 1',
          path: '/path/1',
          category: SlimmerCategory.orphanApp,
          sizeBytes: 100,
        ),
        const SlimCandidateItem(
          id: 'item_2',
          title: 'Item 2',
          subtitle: 'sub 2',
          path: '/path/2',
          category: SlimmerCategory.orphanApp,
          sizeBytes: 200,
        ),
      ];

      final sw = Stopwatch()..start();
      final results = await diagService.diagnoseBatch(items);
      sw.stop();

      expect(results.length, 2);
      // 两个条目之间至少有 100ms 步频延迟
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(100));
    });
  });
}
