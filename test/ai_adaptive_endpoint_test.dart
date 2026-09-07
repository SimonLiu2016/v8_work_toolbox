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
    tempDir = await Directory.systemTemp.createTemp('v8_ai_adaptive_test_');
    AiService.instance.clearResolvedChatEndpoints();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Anthropic Gateway Route Adaptation Tests', () {
    test('模拟网关挂载在 /anthropic/v1/messages 场景：自动自适应探测成功并缓存端点', () async {
      final requestedUrls = <String>[];
      final requestedHeaders = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        requestedHeaders.add(request.headers);

        // 如果请求标准 /v1/messages，返回 404（模拟小米等网关 OpenResty）
        if (request.url.path == '/v1/messages') {
          return http.Response('<html>404 Not Found openresty</html>', 404);
        }

        // 如果请求 /anthropic/v1/messages，返回 200 OK
        if (request.url.path == '/anthropic/v1/messages') {
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Hello from adaptive Anthropic gateway!'}
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('Not Found', 404);
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      final provider = const AiProviderConfig(
        id: 'mimo_anthropic_test',
        name: 'Xiaomi MiMo',
        protocol: AiProtocolType.anthropic,
        baseUrl: 'https://gateway.example.com',
        keychainKeyId: 'key_test',
      );

      // 配置到存储
      await AiConfigStore.instance.init(customRootDir: tempDir);
      await AiConfigStore.instance.saveProvider(provider, apiKey: 'test-api-key-123');
      await AiConfigStore.instance.addSlotCandidate('text', provider.id, 'mimo-v2.5-pro');

      // 第一次调用：应自动探测并命中 /anthropic/v1/messages
      final result = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
      );

      expect(result.text, 'Hello from adaptive Anthropic gateway!');
      expect(requestedUrls, contains('https://gateway.example.com/anthropic/v1/messages'));

      // 验证双鉴权头注入：同时包含 x-api-key 和 api-key
      final anthropicReqHeaders = requestedHeaders.firstWhere(
        (h) => h['anthropic-version'] == '2023-06-01',
      );
      expect(anthropicReqHeaders['x-api-key'], 'test-api-key-123');
      expect(anthropicReqHeaders['api-key'], 'test-api-key-123');

      // 第二次调用：直接使用已缓存端点，不重复探测 404
      requestedUrls.clear();
      final result2 = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'hi again'}
        ],
      );
      expect(result2.text, 'Hello from adaptive Anthropic gateway!');
      expect(requestedUrls.length, 1);
      expect(requestedUrls.first, 'https://gateway.example.com/anthropic/v1/messages');
    });
  });

  group('OpenAI Base URL Normalization Tests', () {
    test('URL 不带 /v1 时自动尝试 /v1/models 和 /v1/chat/completions', () async {
      final requestedUrls = <String>[];
      final requestedHeaders = <Map<String, String>>[];

      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        requestedHeaders.add(request.headers);

        // 如果裸访问 /models，返回 404
        if (request.url.path == '/models') {
          return http.Response('Not Found', 404);
        }
        // 如果访问 /v1/models，返回 200
        if (request.url.path == '/v1/models') {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'gpt-4o'},
                {'id': 'gpt-4o-mini'}
              ]
            }),
            200,
          );
        }
        // 如果访问 /v1/chat/completions，返回 200
        if (request.url.path == '/v1/chat/completions') {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'OpenAI completion success!'}
                }
              ]
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      // 用户输入的 Base URL 结尾没有 /v1
      const provider = AiProviderConfig(
        id: 'openai_no_v1',
        name: 'OpenAI Without V1',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai-gateway.com',
        keychainKeyId: 'key_openai',
      );

      // 1. 探测模型应自动回退并命中 /v1/models
      final models = await service.discoverModels(provider, apiKey: 'sk-test');
      expect(models, containsAll(['gpt-4o', 'gpt-4o-mini']));
      expect(requestedUrls, contains('https://api.openai-gateway.com/v1/models'));

      // 验证 Header 注入了 api-key 兼容头
      final lastHeader = requestedHeaders.last;
      expect(lastHeader['Authorization'], 'Bearer sk-test');
      expect(lastHeader['api-key'], 'sk-test');

      // 2. 对话调用应自动命中 /v1/chat/completions
      await AiConfigStore.instance.init(customRootDir: tempDir);
      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-test');
      await AiConfigStore.instance.addSlotCandidate('text', provider.id, 'gpt-4o');

      final result = await service.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
      );
      expect(result.text, 'OpenAI completion success!');
      expect(requestedUrls, contains('https://api.openai-gateway.com/v1/chat/completions'));
    });
  });

  group('Two-Phase Connection Test Verification Tests', () {
    test('阶段 1 成功（模型返回 200）但阶段 2 失败（对话返回 404）：testConnection 抛出异常而非假阳性', () async {
      final mockClient = MockClient((request) async {
        // 模型探测成功
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'test-model'}
              ]
            }),
            200,
          );
        }
        // 对话接口全部 404
        return http.Response('<html>404 Not Found openresty</html>', 404);
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'false_positive_prov',
        name: 'Broken Provider',
        protocol: AiProtocolType.anthropic,
        baseUrl: 'https://broken.example.com',
        keychainKeyId: 'key_broken',
      );

      // testConnection 必须检测出对话不可用并抛出异常
      expect(
        () async => await service.testConnection(provider, apiKey: 'test-key'),
        throwsA(isA<Exception>()),
      );
    });

    test('阶段 1 与阶段 2 均成功：testConnection 返回 true', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'test-model'}
              ]
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'pong'}
              }
            ]
          }),
          200,
        );
      });

      final service = AiService.instance;
      service.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'good_prov',
        name: 'Good Provider',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_good',
      );

      final ok = await service.testConnection(provider, apiKey: 'test-key');
      expect(ok, isTrue);
    });
  });
}
