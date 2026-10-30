import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/shell/ai_config_page.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

class _TestMockClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;
  _TestMockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TTS Engine Provider Recognition', () {
    test('identifies Qwen, StepFun, MiMo, and OpenAI accurately', () {
      expect(
        OpenAiTtsEngine.isQwenModel(
          'cosyvoice-v1',
          baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        ),
        isTrue,
      );
      expect(
        OpenAiTtsEngine.isQwenModel(
          'qwen-audio-tts',
          baseUrl: 'https://token-plan.maas.qianwenaiapi.com/compatible-mode/v1',
          providerName: '千问 (Token Plan)',
        ),
        isTrue,
      );
      expect(
        OpenAiTtsEngine.isStepFunModel(
          'stepaudio-2.5-tts',
          baseUrl: 'https://api.stepfun.com/v1',
          providerName: '阶跃星辰',
        ),
        isTrue,
      );
      expect(
        OpenAiTtsEngine.isMimoModel(
          'mimo-v2.5-tts',
          baseUrl: 'https://api.xiaomimimo.com/v1',
          providerName: '小米 MiMo',
        ),
        isTrue,
      );
      expect(
        OpenAiTtsEngine.isOpenAiProvider(
          baseUrl: 'https://api.openai.com/v1',
          providerName: 'OpenAI 官方',
        ),
        isTrue,
      );
    });
  });

  group('TTS Engine Cross-Vendor Voice Adaptation', () {
    test('adapts foreign voices to Qwen native voices correctly', () {
      // StepFun female -> Qwen female default
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'zhixingjiejie',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlingxin'),
      );

      // StepFun male -> Qwen male default
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'cixingnansheng',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlufeng'),
      );

      // OpenAI default -> Qwen default
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'alloy',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlingxin'),
      );

      // OpenAI male -> Qwen male
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'echo',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlufeng'),
      );

      // Valid Qwen voices are preserved
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'longanlingxin',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlingxin'),
      );
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'longanlufeng',
          isQwen: true,
          isMimo: false,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('longanlufeng'),
      );
    });

    test('adapts foreign voices to StepFun native voices correctly', () {
      // Qwen female -> StepFun female default
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'longxiaochun',
          isQwen: false,
          isMimo: false,
          isStepFun: true,
          isOpenAi: false,
        ),
        equals('zhixingjiejie'),
      );

      // Qwen male -> StepFun male default
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'longcheng',
          isQwen: false,
          isMimo: false,
          isStepFun: true,
          isOpenAi: false,
        ),
        equals('cixingnansheng'),
      );

      // Valid StepFun voice is preserved
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'zhixingjiejie',
          isQwen: false,
          isMimo: false,
          isStepFun: true,
          isOpenAi: false,
        ),
        equals('zhixingjiejie'),
      );
    });

    test('adapts foreign voices to OpenAI & MiMo correctly', () {
      // StepFun voice -> OpenAI
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'zhixingjiejie',
          isQwen: false,
          isMimo: false,
          isStepFun: false,
          isOpenAi: true,
        ),
        equals('alloy'),
      );
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'cixingnansheng',
          isQwen: false,
          isMimo: false,
          isStepFun: false,
          isOpenAi: true,
        ),
        equals('echo'),
      );

      // Incompatible voice -> MiMo
      expect(
        OpenAiTtsEngine.adaptVoiceForProvider(
          'zhixingjiejie',
          isQwen: false,
          isMimo: true,
          isStepFun: false,
          isOpenAi: false,
        ),
        equals('mimo_default'),
      );
    });
  });

  group('TTS Engine System Model Resolution & Isolation', () {
    test('enforces strict provider isolation and does not leak candidates across providers', () {
      final qwenProvider = AiProviderConfig(
        id: 'qwen_prov',
        name: '千问测试',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        keychainKeyId: 'k1',
        enabled: true,
        textModels: ['qwen-plus'],
        multimodalModels: [],
        ttsModels: ['qwen-audio-3.0-tts-plus'],
        sttModels: [],
        videoModels: [],
        imageModels: [],
      );

      // candidate 0 is from a different provider (e.g. stepfun)
      final resolved = OpenAiTtsEngine.resolveSystemModel(
        provider: qwenProvider,
      );

      expect(resolved, equals('qwen-audio-3.0-tts-plus'));
    });

    test('normalizes legacy qwen-audio-tts, cosyvoice, or tts-1 to qwen-audio-3.0-tts-plus for Qwen', () {
      final qwenProvider = AiProviderConfig(
        id: 'qwen_prov',
        name: '千问 (Token Plan)',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://token-plan.maas.qianwenaiapi.com/compatible-mode/v1',
        keychainKeyId: 'k1',
        enabled: true,
        textModels: ['qwen3.7-plus'],
        multimodalModels: [],
        ttsModels: ['qwen-audio-tts'],
        sttModels: [],
        videoModels: [],
        imageModels: [],
      );

      final resolved = OpenAiTtsEngine.resolveSystemModel(
        provider: qwenProvider,
        configuredModel: 'qwen-audio-tts',
      );

      expect(resolved, equals('qwen-audio-3.0-tts-plus'));
    });
  });

  group('Presets & Config Self-Healing', () {
    test('QwenPreset.ttsModels contains valid models and excludes qwen-audio-tts', () {
      expect(QwenPreset.ttsModels.contains('qwen-audio-tts'), isFalse);
      expect(QwenPreset.ttsModels.contains('qwen-audio-3.0-tts-plus'), isTrue);
    });

    test('MimoPreset uses API mode, v2.6 text series, and serves mimo-v2.5-tts', () {
      // API 模式地址，绝非 Token Plan 订阅集群地址。
      expect(MimoPreset.baseUrl, equals('https://api.xiaomimimo.com/v1'));
      expect(MimoPreset.baseUrl.contains('token-plan-'), isFalse);

      // TTS 模型必须是当前仍在 /v1/models 且真机出音的型号。
      expect(MimoPreset.ttsModels, contains('mimo-v2.5-tts'));

      // 文本模型用 v2.6 系列，不得包含已下线（2026-10-21）的 v2.5 / v2.5-pro。
      expect(MimoPreset.textModels, contains('mimo-v2.6-flash'));
      expect(MimoPreset.textModels, contains('mimo-v2.6-pro'));
      expect(MimoPreset.textModels.contains('mimo-v2.5'), isFalse);

      // 显示名与 STT 模型一致性。
      expect(MimoPreset.displayName, contains('Mimo'));
      expect(MimoPreset.sttModels, equals('mimo-v2.5-asr'));
    });

    test('AiConfigStore self-heals legacy qwen-audio-tts in slot candidates and providers', () async {
      final tempDir = Directory.systemTemp.createTempSync('ai_config_heal_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final testFile = File('${tempDir.path}/ai_config.json');
      final legacyJson = {
        'providers': [
          {
            'id': 'p_qwen',
            'name': '千问',
            'protocol': 'openai',
            'baseUrl': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
            'keychainKeyId': 'k_test',
            'enabled': true,
            'models': {
              'text': ['qwen-plus'],
              'multimodal': [],
              'tts': ['cosyvoice-v3-flash', 'qwen-audio-tts'],
              'stt': [],
              'video': [],
              'image': [],
            },
          }
        ],
        'defaultSlots': {
          'tts': [
            {'providerId': 'p_qwen', 'model': 'qwen-audio-tts', 'priority': 0}
          ]
        }
      };
      testFile.writeAsStringSync(jsonEncode(legacyJson));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // Verify slot candidate was self-healed
      final ttsCandidates = store.slotBindings['tts'] ?? [];
      expect(ttsCandidates.isNotEmpty, isTrue);
      expect(ttsCandidates.first.model, equals('qwen-audio-3.0-tts-plus'));

      // Verify provider ttsModels list was self-healed
      final provider = store.providers.firstWhere((p) => p.id == 'p_qwen');
      expect(provider.ttsModels.contains('qwen-audio-tts'), isFalse);
      expect(provider.ttsModels.contains('qwen-audio-3.0-tts-plus'), isTrue);

      // Verify file on disk was updated with self-healed values
      final updatedContent = jsonDecode(testFile.readAsStringSync());
      final savedSlotModel = updatedContent['defaultSlots']['tts'][0]['model'];
      expect(savedSlotModel, equals('qwen-audio-3.0-tts-plus'));
    });
  });

  group('MiMo Style Instruction & Speed Translation', () {
    test('injects user style message before assistant and appends speed fragment', () async {
      String? capturedBody;
      final mockClient = _TestMockClient((request) async {
        if (request is http.Request) capturedBody = request.body;
        // 返回合法 base64 WAV（最小 RIFF 头即可，引擎只解 base64）
        final wav = [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45];
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'audio': {'data': base64Encode(wav)},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = OpenAiTtsEngine(client: mockClient);
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: false,
        customEndpoint: 'https://api.xiaomimimo.com/v1',
        customApiKey: 'sk-test',
        customModel: 'mimo-v2.5-tts',
        customVoiceId: 'mimo_default',
        speed: 1.5,
        styleInstruction: '自然、清晰',
      );

      final audio = await engine.synthesize('测试文本', config);
      expect(audio, isNotEmpty);

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages.length, 2);
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'], contains('自然、清晰'));
      expect(messages[0]['content'], contains('语速加快'));
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], '测试文本');
    });

    test('speed 1.0 adds no fragment and no empty user message when instruction absent', () async {
      String? capturedBody;
      final mockClient = _TestMockClient((request) async {
        if (request is http.Request) capturedBody = request.body;
        final wav = [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45];
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'audio': {'data': base64Encode(wav)},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final engine = OpenAiTtsEngine(client: mockClient);
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: false,
        customEndpoint: 'https://api.xiaomimimo.com/v1',
        customApiKey: 'sk-test',
        customModel: 'mimo-v2.5-tts',
        speed: 1.0,
      );

      final audio = await engine.synthesize('测试文本', config);
      expect(audio, isNotEmpty);

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages.length, 1);
      expect(messages[0]['role'], 'assistant');
    });

    test('non-MiMo provider ignores style instruction', () async {
      String? capturedBody;
      final mockClient = _TestMockClient((request) async {
        if (request is http.Request) capturedBody = request.body;
        return http.Response.bytes([0xFF, 0xFB, 0x90, 0x44], 200);
      });

      final engine = OpenAiTtsEngine(client: mockClient);
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: false,
        customEndpoint: 'https://api.openai.com/v1',
        customApiKey: 'sk-test',
        customModel: 'tts-1',
        styleInstruction: '自然、清晰',
      );

      final audio = await engine.synthesize('测试文本', config);
      expect(audio, isNotEmpty);
      // OpenAI speech 规范：不应出现 user 消息
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body.containsKey('messages'), isFalse);
      expect(body['input'], '测试文本');
    });
  });
}
