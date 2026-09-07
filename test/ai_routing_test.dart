import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_ai_routing_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // Task 6.4: chat() 路由降级集成测试
  // ---------------------------------------------------------------------------
  group('Chat Routing Failover Tests', () {
    test('首选失败→备选成功→验证 ChatResult 路由跟踪', () async {
      // 准备：设置两个供应商，首选会失败，备选会成功
      final configFile = File('${tempDir.path}/ai_config.json');
      final config = {
        'providers': [
          {
            'id': 'provider_fail',
            'name': 'Failing Provider',
            'protocol': 'openai',
            'baseUrl': 'https://fail.test.com/v1',
            'keychainKeyId': 'key_fail',
            'enabled': true,
            'models': {'text': ['model-a'], 'multimodal': [], 'tts': [], 'stt': []},
          },
          {
            'id': 'provider_ok',
            'name': 'OK Provider',
            'protocol': 'openai',
            'baseUrl': 'https://ok.test.com/v1',
            'keychainKeyId': 'key_ok',
            'enabled': true,
            'models': {'text': ['model-b'], 'multimodal': [], 'tts': [], 'stt': []},
          },
        ],
        'defaultSlots': {
          'text': [
            {'providerId': 'provider_fail', 'model': 'model-a', 'priority': 0},
            {'providerId': 'provider_ok', 'model': 'model-b', 'priority': 1},
          ],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // Mock HTTP client: fail.test.com → 500, ok.test.com → 200
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('fail.test.com')) {
          return http.Response('{"error": "server down"}', 500);
        }
        if (url.contains('ok.test.com')) {
          return http.Response(jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': 'Hello from fallback!'}}
            ]
          }), 200);
        }
        return http.Response('Not found', 404);
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);
      service.cooldownDuration = const Duration(seconds: 60);

      // 执行 chat
      final result = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'Hello'},
        ],
      );

      // 验证结果
      expect(result.text, 'Hello from fallback!');
      expect(result.usedProviderId, 'provider_ok');
      expect(result.usedModel, 'model-b');

      // 验证路由跟踪
      expect(result.routingTrace.length, 2);
      expect(result.routingTrace[0].providerId, 'provider_fail');
      expect(result.routingTrace[0].outcome, 'failure');
      expect(result.routingTrace[0].error, isNotNull);
      expect(result.routingTrace[1].providerId, 'provider_ok');
      expect(result.routingTrace[1].outcome, 'success');

      // 验证健康状态
      expect(service.getProviderHealth('provider_fail')?.isHealthy, isFalse);
      expect(service.getProviderHealth('provider_ok')?.isHealthy, isTrue);
    });

    test('全部候选失败→抛出 SlotUnavailableException', () async {
      final configFile = File('${tempDir.path}/ai_config.json');
      final config = {
        'providers': [
          {
            'id': 'p1',
            'name': 'Provider 1',
            'protocol': 'openai',
            'baseUrl': 'https://p1.test.com/v1',
            'keychainKeyId': 'k1',
            'enabled': true,
            'models': {'text': ['m1'], 'multimodal': [], 'tts': [], 'stt': []},
          },
          {
            'id': 'p2',
            'name': 'Provider 2',
            'protocol': 'openai',
            'baseUrl': 'https://p2.test.com/v1',
            'keychainKeyId': 'k2',
            'enabled': true,
            'models': {'text': ['m2'], 'multimodal': [], 'tts': [], 'stt': []},
          },
        ],
        'defaultSlots': {
          'text': [
            {'providerId': 'p1', 'model': 'm1', 'priority': 0},
            {'providerId': 'p2', 'model': 'm2', 'priority': 1},
          ],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // 所有请求都返回错误
      final mockClient = MockClient((request) async {
        return http.Response('{"error": "service unavailable"}', 503);
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);
      service.cooldownDuration = const Duration(seconds: 60);

      // 应抛出 SlotUnavailableException
      try {
        await service.chat(
          slot: 'text',
          messages: [
            {'role': 'user', 'content': 'Hello'},
          ],
        );
        fail('Should have thrown SlotUnavailableException');
      } on SlotUnavailableException catch (e) {
        expect(e.slotName, 'text');
        expect(e.candidateCount, 2);
        expect(e.candidateErrors.length, 2);
      }
    });

    test('空槽位→抛出零候选 SlotUnavailableException', () async {
      final configFile = File('${tempDir.path}/ai_config.json');
      final config = {
        'providers': [],
        'defaultSlots': {
          'text': [],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      final service = AiService.instance;

      try {
        await service.chat(
          slot: 'tts',
          messages: [
            {'role': 'user', 'content': 'Hello'},
          ],
        );
        fail('Should have thrown SlotUnavailableException');
      } on SlotUnavailableException catch (e) {
        expect(e.slotName, 'tts');
        expect(e.candidateCount, 0);
        expect(e.candidateErrors, isEmpty);
      }
    });

    test('冷却中的供应商被跳过，直接尝试下一个', () async {
      final configFile = File('${tempDir.path}/ai_config.json');
      final config = {
        'providers': [
          {
            'id': 'cooled',
            'name': 'Cooled Provider',
            'protocol': 'openai',
            'baseUrl': 'https://cooled.test.com/v1',
            'keychainKeyId': 'kc',
            'enabled': true,
            'models': {'text': ['m1'], 'multimodal': [], 'tts': [], 'stt': []},
          },
          {
            'id': 'healthy',
            'name': 'Healthy Provider',
            'protocol': 'openai',
            'baseUrl': 'https://healthy.test.com/v1',
            'keychainKeyId': 'kh',
            'enabled': true,
            'models': {'text': ['m2'], 'multimodal': [], 'tts': [], 'stt': []},
          },
        ],
        'defaultSlots': {
          'text': [
            {'providerId': 'cooled', 'model': 'm1', 'priority': 0},
            {'providerId': 'healthy', 'model': 'm2', 'priority': 1},
          ],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(config));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // 预先将 cooled 标记为不健康
      final service = AiService.instance;
      service.cooldownDuration = const Duration(hours: 1); // 长冷却
      service.markProviderUnhealthy('cooled', 'previous timeout');

      // Mock: healthy.test.com 返回成功
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('cooled.test.com')) {
          fail('Should not have attempted cooled provider');
        }
        if (url.contains('healthy.test.com')) {
          return http.Response(jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': 'skipped cooled!'}}
            ]
          }), 200);
        }
        return http.Response('Not found', 404);
      });
      service.setMockHttpClient(mockClient);

      final result = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'Hello'},
        ],
      );

      expect(result.text, 'skipped cooled!');
      expect(result.usedProviderId, 'healthy');

      // 路由跟踪应包含跳过记录
      expect(result.routingTrace.length, 2);
      expect(result.routingTrace[0].outcome, 'skipped_cooldown');
      expect(result.routingTrace[0].providerId, 'cooled');
      expect(result.routingTrace[1].outcome, 'success');
      expect(result.routingTrace[1].providerId, 'healthy');
    });
  });
}
