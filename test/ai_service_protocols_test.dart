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
    tempDir = await Directory.systemTemp.createTemp('v8_ai_protocols_test_');
    await AiConfigStore.instance.init(customRootDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AiService Multi-Protocol Discovery Tests', () {
    test('OpenAI 协议模型探测正常解析 /models', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          expect(request.headers['Authorization'], 'Bearer sk-openai-test');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'gpt-4o'},
                {'id': 'gpt-4o-mini'},
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'openai_p',
        name: 'OpenAI',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_openai',
      );

      final models = await AiService.instance.discoverModels(provider, apiKey: 'sk-openai-test');
      expect(models, containsAll(['gpt-4o', 'gpt-4o-mini']));
    });

    test('Anthropic 协议模型探测正常解析 /v1/models', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          expect(request.headers['x-api-key'], 'sk-ant-test');
          expect(request.headers['anthropic-version'], '2023-06-01');
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'claude-3-7-sonnet-20250219'},
                {'id': 'claude-3-5-haiku-20241022'},
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'anthropic_p',
        name: 'Anthropic',
        protocol: AiProtocolType.anthropic,
        baseUrl: 'https://api.anthropic.com',
        keychainKeyId: 'key_ant',
      );

      final models = await AiService.instance.discoverModels(provider, apiKey: 'sk-ant-test');
      expect(models, containsAll(['claude-3-7-sonnet-20250219', 'claude-3-5-haiku-20241022']));
    });

    test('Gemini 协议模型探测正常解析 /v1beta/models', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/v1beta/models')) {
          expect(request.url.queryParameters['key'], 'gm-key-123');
          return http.Response(
            jsonEncode({
              'models': [
                {'name': 'models/gemini-2.5-flash'},
                {'name': 'models/gemini-2.0-flash'},
                {'name': 'models/text-embedding-004'},
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'gemini_p',
        name: 'Gemini',
        protocol: AiProtocolType.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com',
        keychainKeyId: 'key_gm',
      );

      final models = await AiService.instance.discoverModels(provider, apiKey: 'gm-key-123');
      expect(models, contains('gemini-2.5-flash'));
      expect(models, contains('gemini-2.0-flash'));
      // embedding should be filtered out
      expect(models.any((m) => m.contains('embedding')), isFalse);
    });
  });

  group('AiService Multi-Protocol Chat Tests', () {
    test('Anthropic 协议 chat 消息组装与解析', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/v1/messages')) {
          expect(request.headers['x-api-key'], 'sk-ant-chat');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['system'], contains('Mac expert'));
          expect(body['model'], 'claude-3-5-sonnet-20241022');
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': '{"id":"test1","inferredApp":"Xcode","safety":"safe","canDelete":true,"advice":"建议清理缓存"}'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'ant_chat_prov',
        name: 'Anthropic Claude',
        protocol: AiProtocolType.anthropic,
        baseUrl: 'https://api.anthropic.com',
        keychainKeyId: 'key_ant_chat',
      );

      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-ant-chat');
      await AiConfigStore.instance.setSlotBinding('text', 'ant_chat_prov', 'claude-3-5-sonnet-20241022');

      final result = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': 'Mac expert system prompt'},
          {'role': 'user', 'content': 'Check folder ~/Library/Caches/Xcode'},
        ],
      );

      expect(result.text, contains('Xcode'));
    });

    test('Gemini 协议 chat 消息组装与解析', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains(':generateContent')) {
          expect(request.url.queryParameters['key'], 'gm-chat-key');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['systemInstruction'], isNotNull);
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '{"id":"test2","inferredApp":"Chrome","safety":"safe","canDelete":true,"advice":"建议清理"}'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'gm_chat_prov',
        name: 'Google Gemini',
        protocol: AiProtocolType.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com',
        keychainKeyId: 'key_gm_chat',
      );

      await AiConfigStore.instance.saveProvider(provider, apiKey: 'gm-chat-key');
      await AiConfigStore.instance.setSlotBinding('text', 'gm_chat_prov', 'gemini-2.0-flash');

      final result = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': 'System instruction'},
          {'role': 'user', 'content': 'Query text'},
        ],
      );

      expect(result.text, contains('Chrome'));
    });
  });

  group('AiDiskDiagnosticsService Error Transparency Tests', () {
    test('单条失败时保留 lastError 且不崩溃', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Invalid API Key (401 Unauthorized)', 401);
      });

      AiService.instance.setMockHttpClient(mockClient);

      const provider = AiProviderConfig(
        id: 'error_prov',
        name: 'Error Provider',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_err',
      );

      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-bad-key');
      await AiConfigStore.instance.setSlotBinding('text', 'error_prov', 'gpt-4o');

      final items = [
        SlimCandidateItem(
          id: 'item_1',
          title: 'Test Cache',
          subtitle: 'Caches',
          path: '/Users/test/Library/Caches/com.test',
          sizeBytes: 1024 * 1024,
          category: SlimmerCategory.buildCache,
        ),
      ];

      final results = await AiDiskDiagnosticsService.instance.diagnoseBatch(items);
      expect(results, isEmpty);
      expect(AiDiskDiagnosticsService.instance.lastError, isNotNull);
      expect(AiDiskDiagnosticsService.instance.lastError, contains('401'));
    });
  });
}
