import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/audio_cache_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/document_parser.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';
import 'package:V8WorkToolbox/tools/reader/ui/doc_audio_reader_page.dart';
import 'package:V8WorkToolbox/tools/registry.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ParagraphChunker Tests', () {
    test('普通段落智能切分与偏移量计算', () {
      const sample = '''第一段内容测试。
第二段内容测试，包含更多说明。

第三段内容独立成段。''';

      final chunks = ParagraphChunker.chunkText(sample);
      expect(chunks.length, 3);
      expect(chunks[0].text, '第一段内容测试。');
      expect(chunks[1].text, '第二段内容测试，包含更多说明。');
      expect(chunks[2].text, '第三段内容独立成段。');
      expect(chunks[0].index, 0);
      expect(chunks[1].index, 1);
      expect(chunks[2].index, 2);
    });

    test('长段落按中英文标点自适应断句切分', () {
      final longParagraph = '这是很长的一段话。' * 40; // 360字以上，超出单片上限 260
      final chunks = ParagraphChunker.chunkText(longParagraph);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(ParagraphChunker.maxChunkChars + 10));
      }
    });

    test('空白文本或空行处理', () {
      expect(ParagraphChunker.chunkText(''), isEmpty);
      expect(ParagraphChunker.chunkText('   \n\n\t  \n  '), isEmpty);
    });
  });

  group('Reader Models & Serialization Tests', () {
    test('ReadingDocument JSON 往返序列化对称性', () {
      final chunk = ReadingChunk(
        index: 0,
        text: '测试文本',
        startChar: 0,
        endChar: 4,
        status: ChunkSynthesisStatus.cached,
        audioCachePath: '/tmp/test.mp3',
      );

      final doc = ReadingDocument(
        id: 'doc_123',
        title: '测试文档',
        source: '/path/to/test.txt',
        sourceType: DocumentSourceType.txt,
        chunks: [chunk],
        totalWordCount: 480,
      );

      expect(doc.estimatedDuration.inMinutes, 2);

      final json = doc.toJson();
      final parsed = ReadingDocument.fromJson(json);

      expect(parsed.id, 'doc_123');
      expect(parsed.title, '测试文档');
      expect(parsed.sourceType, DocumentSourceType.txt);
      expect(parsed.chunks.length, 1);
      expect(parsed.chunks.first.status, ChunkSynthesisStatus.cached);
      expect(parsed.chunks.first.audioCachePath, '/tmp/test.mp3');
    });

    test('TtsSynthesisConfig 默认值与 copyWith', () {
      const config = TtsSynthesisConfig();
      expect(config.mode, TtsMode.edge);
      expect(config.voiceId, 'zh-CN-XiaoxiaoNeural');
      expect(config.speed, 1.0);
      expect(config.useSystemAiConfig, isTrue);
      expect(config.systemProviderId, isNull);
      expect(config.customVoiceId, isNull);
      expect(config.effectiveVoiceId, 'zh-CN-XiaoxiaoNeural');

      final modified = config.copyWith(
        speed: 1.5,
        voiceId: 'zh-CN-YunxiNeural',
        useSystemAiConfig: false,
        systemProviderId: 'test_provider_1',
        customVoiceId: 'fishaudio-special',
      );
      expect(modified.speed, 1.5);
      expect(modified.voiceId, 'zh-CN-YunxiNeural');
      expect(modified.mode, TtsMode.edge);
      expect(modified.useSystemAiConfig, isFalse);
      expect(modified.systemProviderId, 'test_provider_1');
      expect(modified.customVoiceId, 'fishaudio-special');

      // 仅在 customAi 模态下 customVoiceId 生效
      final customAiConfig = modified.copyWith(mode: TtsMode.customAi);
      expect(customAiConfig.effectiveVoiceId, 'fishaudio-special');
    });

    test('TtsSynthesisConfig JSON 往返序列化支持系统 AI 配置字段', () {
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        voiceId: 'alloy',
        speed: 1.25,
        pitch: 1.0,
        useSystemAiConfig: true,
        systemProviderId: 'prov_openai_1',
        customVoiceId: 'my-custom-voice',
        customEndpoint: 'https://api.test.com/v1',
        customApiKey: 'sk-test-secret',
        customModel: 'tts-1-hd',
      );

      final json = config.toJson();
      final parsed = TtsSynthesisConfig.fromJson(json);

      expect(parsed.mode, TtsMode.customAi);
      expect(parsed.voiceId, 'alloy');
      expect(parsed.speed, 1.25);
      expect(parsed.useSystemAiConfig, isTrue);
      expect(parsed.systemProviderId, 'prov_openai_1');
      expect(parsed.customVoiceId, 'my-custom-voice');
      expect(parsed.customEndpoint, 'https://api.test.com/v1');
      expect(parsed.customApiKey, 'sk-test-secret');
      expect(parsed.customModel, 'tts-1-hd');
    });

    test('TtsVoiceOption 预设音色完整性', () {
      expect(TtsVoiceOption.defaultEdgeVoices, isNotEmpty);
      expect(TtsVoiceOption.defaultEdgeVoices.any((v) => v.id.contains('Xiaoxiao')), isTrue);
      expect(TtsVoiceOption.defaultOpenAiVoices.any((v) => v.id == 'alloy'), isTrue);
      expect(TtsVoiceOption.defaultMacOsVoices.any((v) => v.id == 'Tingting'), isTrue);
    });
  });

  group('DocumentParser Cleaning & Extraction Tests', () {
    test('Markdown 格式清洗测试 (图片、链接、粗体、标题)', () {
      const md = '''# 核心标题
这里是段落正文，包含了[点击跳转链接](https://example.com)与图片![徽章图片](https://badge.com/img.png)。
**粗体说明**与*斜体标注*，以及`代码块标记`。''';

      final clean = DocumentParser.cleanMarkdownFormatting(md);
      expect(clean, contains('核心标题'));
      expect(clean, contains('点击跳转链接'));
      expect(clean, contains('粗体说明与斜体标注'));
      expect(clean.contains('https://badge.com'), isFalse);
      expect(clean.contains('![徽章图片]'), isFalse);
      expect(clean.contains('`'), isFalse);
    });

    test('HTML 标签清洗与实体反转义测试', () {
      const html = '<p>第一段文章&nbsp;&mdash;&ldquo;双引号测试&rdquo;&amp;&lt;标签&gt;</p><p>第二段正文</p>';
      final text = DocumentParser.stripHtmlTags(html);

      expect(text, contains('第一段文章 —“双引号测试”&<标签>'));
      expect(text, contains('第二段正文'));
      expect(text.contains('<p>'), isFalse);
    });

    test('本地 TXT 文件解析', () async {
      final tempDir = Directory.systemTemp.createTempSync('doc_parser_test_');
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('第一行内容。\n\n第二行内容。', encoding: utf8);

      final doc = await DocumentParser.parseFile(file.path);
      expect(doc.title, 'test');
      expect(doc.sourceType, DocumentSourceType.txt);
      expect(doc.chunks.length, 2);

      tempDir.deleteSync(recursive: true);
    });
  });

  group('AudioCacheManager Tests', () {
    late Directory tempDir;
    late AudioCacheManager cacheManager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('audio_cache_test_');
      cacheManager = AudioCacheManager(customBasePath: tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('保存切片、检查缓存存在并读取音频', () async {
      const docId = 'doc_test_1';
      final dummyBytes = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x44, 0x00]); // 伪 MP3 帧头

      expect(cacheManager.isChunkCached(docId, 0), isFalse);

      final savedFile = await cacheManager.saveChunkAudio(docId, 0, dummyBytes);
      expect(savedFile.existsSync(), isTrue);
      expect(cacheManager.isChunkCached(docId, 0), isTrue);

      final readBytes = await cacheManager.getChunkAudio(docId, 0);
      expect(readBytes, isNotNull);
      expect(readBytes!.length, dummyBytes.length);

      final totalSize = await cacheManager.calculateTotalCacheSize();
      expect(totalSize, dummyBytes.length);

      await cacheManager.clearDocCache(docId);
      expect(cacheManager.isChunkCached(docId, 0), isFalse);
    });
  });

  group('Tool Registry & Widget Tests', () {
    test('ToolRegistry 正确注册 doc-audio-reader', () {
      final tool = ToolRegistry.findById('doc-audio-reader');
      expect(tool, isNotNull);
      expect(tool!.title, '文档语音朗读');
      expect(tool.category, ToolCategory.file);
      expect(tool.subtitle, contains('实时 AI 语音朗读'));
    });

    testWidgets('DocAudioReaderPage 初始状态渲染空状态引导与操作按钮', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DocAudioReaderPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('文档与网页 AI 语音朗读助手'), findsOneWidget);
      expect(find.text('导入文档'), findsOneWidget);
      expect(find.text('网页链接'), findsOneWidget);
      expect(find.text('导出 MP3'), findsOneWidget);
      expect(find.text('用耳朵听文档与长文'), findsOneWidget);
      expect(find.text('选择本地文件'), findsOneWidget);
    });

    testWidgets('TTS 设置弹窗支持选择商用 AI TTS 并展示系统 AI 配置选项', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DocAudioReaderPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 点击右上角设置按钮打开底部设置 Sheet
      final settingsBtn = find.byTooltip('TTS 模态与音色设置');
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      expect(find.text('TTS 语音合成与音色配置'), findsOneWidget);
      expect(find.text('商用 AI TTS'), findsOneWidget);

      // 切换到商用 AI TTS 模态
      await tester.tap(find.text('商用 AI TTS'));
      await tester.pumpAndSettle();

      // 验证“商用 AI 配置来源”、“跟随系统 AI 配置 (推荐)”与“自定义独立配置”
      expect(find.text('商用 AI 配置来源：'), findsOneWidget);
      expect(find.text('跟随系统 AI 配置 (推荐)'), findsOneWidget);
      expect(find.text('自定义独立配置'), findsOneWidget);
      expect(find.text('自定义音色 ID (可选)'), findsOneWidget);
    });
  });

  group('System AI Configuration & OpenAiTtsEngine Resolution Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('doc_reader_ai_test_');
      await KeychainService.instance.init(customRootDir: tempDir);
      await AiConfigStore.instance.init(customRootDir: tempDir);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('当未配置任何 AI 供应商且未输入端点时，抛出明确指引异常', () async {
      final engine = OpenAiTtsEngine();
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: true,
      );

      expect(
        () => engine.synthesize('测试文本', config),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('系统「AI能力配置」中尚未找到可用的 TTS 槽位或 OpenAI 兼容供应商'),
        )),
      );
    });

    test('当指定有效供应商并录入 Keychain 密钥时，正确组装并发出请求 (捕获网络调用异常)', () async {
      const provider = AiProviderConfig(
        id: 'siliconflow_tts_test',
        name: '硅基流动',
        protocol: AiProtocolType.openai,
        baseUrl: 'http://127.0.0.1:54321/v1',
        keychainKeyId: 'key_siliconflow_test',
        enabled: true,
        ttsModels: ['fishaudio/fish-speech-1.5'],
      );

      await AiConfigStore.instance.saveProvider(provider, apiKey: 'sk-siliconflow-secret-888');
      await AiConfigStore.instance.addSlotCandidate('tts', provider.id, 'fishaudio/fish-speech-1.5');

      final engine = OpenAiTtsEngine();
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: true,
        customVoiceId: 'voice_custom_special',
      );

      try {
        await engine.synthesize('测试语音', config);
      } catch (e) {
        expect(e.toString(), isNot(contains('系统「AI能力配置」中尚未找到可用的 TTS 槽位')));
      }
    });

    test('指定特定 systemProviderId 时精准覆盖默认 TTS 槽位', () async {
      const p1 = AiProviderConfig(
        id: 'prov_default_tts',
        name: '默认供应商',
        protocol: AiProtocolType.openai,
        baseUrl: 'http://127.0.0.1:54321/v1',
        keychainKeyId: 'key_p1',
        enabled: true,
      );
      const p2 = AiProviderConfig(
        id: 'prov_override_tts',
        name: '覆写供应商',
        protocol: AiProtocolType.openai,
        baseUrl: 'http://127.0.0.1:54322/v1',
        keychainKeyId: 'key_p2',
        enabled: true,
      );

      await AiConfigStore.instance.saveProvider(p1, apiKey: 'sk-p1');
      await AiConfigStore.instance.saveProvider(p2, apiKey: 'sk-p2');
      await AiConfigStore.instance.addSlotCandidate('tts', p1.id, 'tts-1');

      final engine = OpenAiTtsEngine();
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: true,
        systemProviderId: 'prov_override_tts',
      );

      try {
        await engine.synthesize('测试覆盖', config);
      } catch (e) {
        expect(e.toString(), isNot(contains('系统「AI能力配置」中尚未找到可用的 TTS 槽位')));
      }
    });

    test('Chat Audio Completions 模型与 MiMo 供应商类型判定', () {
      expect(OpenAiTtsEngine.isChatAudioModel('mimo-v2.5-tts'), isTrue);
      expect(OpenAiTtsEngine.isChatAudioModel('tts-1', baseUrl: 'https://token-plan-sgp.xiaomimimo.com'), isTrue);
      expect(OpenAiTtsEngine.isChatAudioModel('gpt-4o-audio-preview'), isTrue);
      expect(OpenAiTtsEngine.isChatAudioModel('tts-1', baseUrl: 'https://api.openai.com/v1'), isFalse);

      expect(OpenAiTtsEngine.isMimoModel('mimo-v2.5-tts'), isTrue);
      expect(OpenAiTtsEngine.isMimoModel('tts-1', providerName: 'mimo'), isTrue);
      expect(OpenAiTtsEngine.isMimoModel('tts-1', baseUrl: 'https://token-plan-sgp.xiaomimimo.com'), isTrue);
      expect(OpenAiTtsEngine.isMimoModel('tts-1', baseUrl: 'https://api.openai.com/v1'), isFalse);
    });

    test('MiMo 官方音色集合覆盖与校验', () {
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('mimo_default'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('冰糖'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('茉莉'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('苏打'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('白桦'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('Mia'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('Chloe'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('Milo'), isTrue);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('Dean'), isTrue);

      // 非法音色不属于 MiMo 音色
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('zh-CN-XiaoxiaoNeural'), isFalse);
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains('alloy'), isFalse);
    });

    test('AudioCacheManager 智能音频扩展名嗅探与多格式文件持久化', () async {
      final tempDir = await Directory.systemTemp.createTemp('v8_audio_cache_test_');
      final cacheMgr = AudioCacheManager(customBasePath: tempDir.path);

      // 1. WAV 头字节 (RIFF .... WAVE)
      final wavHeaderBytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x24, 0xD0, 0x02, 0x00, // Size
        0x57, 0x41, 0x56, 0x45, // WAVE
        0x66, 0x6D, 0x74, 0x20, // fmt 
      ]);
      expect(AudioCacheManager.detectAudioExtension(wavHeaderBytes), 'wav');

      // 2. MP3 假定字节
      final mp3Bytes = Uint8List.fromList([
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]);
      expect(AudioCacheManager.detectAudioExtension(mp3Bytes), 'mp3');

      // 3. 保存 WAV 并验证文件路径与缓存读取
      final savedWav = await cacheMgr.saveChunkAudio('doc_wav_test', 0, wavHeaderBytes);
      expect(savedWav.path.endsWith('chunk_0000.wav'), isTrue);
      expect(cacheMgr.isChunkCached('doc_wav_test', 0), isTrue);
      expect(cacheMgr.getChunkFilePath('doc_wav_test', 0), savedWav.path);

      final readBytes = await cacheMgr.getChunkAudio('doc_wav_test', 0);
      expect(readBytes, isNotNull);
      expect(readBytes!.length, wavHeaderBytes.length);

      final files = await cacheMgr.getCachedChunkFiles('doc_wav_test');
      expect(files.length, 1);
      expect(files.first.path.endsWith('.wav'), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('OpenAiTtsEngine.resolveSystemModel 智能解析与 MiMo 防御回退测试', () async {
      const mimoProvider = AiProviderConfig(
        id: 'prov_mimo_test',
        name: 'mimo',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.xiaomimimo.com/v1',
        keychainKeyId: 'key_mimo_test',
        enabled: true,
        ttsModels: [], // 模拟用户在 text 模型列表中配置，ttsModels 为空
        textModels: ['mimo-v2.5-tts', 'mimo-v2-chat'],
      );

      await AiConfigStore.instance.saveProvider(mimoProvider, apiKey: 'sk-dummy-key');
      await AiConfigStore.instance.addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

      // 1. 正常从 slot 绑定候选人中获取到 mimo-v2.5-tts
      final resolvedFromSlot = OpenAiTtsEngine.resolveSystemModel(
        provider: mimoProvider,
        store: AiConfigStore.instance,
      );
      expect(resolvedFromSlot, 'mimo-v2.5-tts');

      // 2. 若没有 slot 绑定，但模型列表包含 tts 模型
      await AiConfigStore.instance.setSlotBinding('tts', '', '');
      final resolvedFromModels = OpenAiTtsEngine.resolveSystemModel(
        provider: mimoProvider,
        store: AiConfigStore.instance,
      );
      expect(resolvedFromModels, 'mimo-v2.5-tts');

      // 3. 即使 configuredModel 误传为 'tts-1'，针对 MiMo 仍强制防御修正为 'mimo-v2.5-tts'
      final resolvedDefensive = OpenAiTtsEngine.resolveSystemModel(
        provider: mimoProvider,
        configuredModel: 'tts-1',
        store: AiConfigStore.instance,
      );
      expect(resolvedDefensive, 'mimo-v2.5-tts');
    });

    test('指定 systemProviderId 且 provider.ttsModels 为空时，正确从槽位解析 mimo-v2.5-tts 而非 tts-1', () async {
      const mimoProvider = AiProviderConfig(
        id: 'prov_mimo_slot_test',
        name: 'Xiaomi MiMo',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.xiaomimimo.com/v1',
        keychainKeyId: 'key_mimo_slot_test',
        enabled: true,
        ttsModels: [],
      );

      await AiConfigStore.instance.saveProvider(mimoProvider, apiKey: 'sk-mimo-slot');
      await AiConfigStore.instance.addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

      final engine = OpenAiTtsEngine();
      const config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: true,
        systemProviderId: 'prov_mimo_slot_test',
      );

      try {
        await engine.synthesize('槽位模型解析测试', config);
      } catch (e) {
        // 请求发往不存在的假 key / 外部连接，确保错误不是不支持 tts-1
        expect(e.toString(), isNot(contains('tts-1')));
      }
    });

    test('OpenAiTtsEngine 针对小米 MiMo 真实凭证进行端到端合成与防 400 音色自动兜底测试', () async {
      final key = await KeychainService.instance.readSecret('key_provider_1788370161938');
      if (key == null || key.isEmpty) {
        return;
      }

      final engine = OpenAiTtsEngine();
      // 传入故意不兼容的 Edge 音色 'zh-CN-XiaoxiaoNeural'，测试防 400 自动兜底为 mimo_default 以及 Chat Audio 合成
      final config = TtsSynthesisConfig(
        mode: TtsMode.customAi,
        voiceId: 'zh-CN-XiaoxiaoNeural',
        useSystemAiConfig: false,
        customEndpoint: 'https://token-plan-sgp.xiaomimimo.com',
        customApiKey: key,
        customModel: 'mimo-v2.5-tts',
      );

      final audioBytes = await engine.synthesize('语音合成测试。', config);
      expect(audioBytes, isNotEmpty);
      expect(AudioCacheManager.detectAudioExtension(audioBytes), 'wav');
    });
  });
}
