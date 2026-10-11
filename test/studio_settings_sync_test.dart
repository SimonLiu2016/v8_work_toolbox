import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('studio_settings_sync_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('工坊设置与系统 AI 配置同步测试', () {
    test('未绑定系统视频模型时，getSystemVideoConfigSummary 返回 isConfigured: false', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      final summary = VideoGenAdapterFactory.getSystemVideoConfigSummary();
      expect(summary.isConfigured, isFalse);
      expect(summary.description, contains('未配置视频模型'));
    });

    test('绑定系统视频模型后，getSystemVideoConfigSummary 返回正确的供应商与模型名称', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      const provider = AiProviderConfig(
        id: 'prov_senseaudio_sync',
        name: 'SenseAudio 视频中枢',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.senseaudio.cn/v1',
        keychainKeyId: 'key_sync_test',
        videoModels: ['doubao-seedance-2-0-260128'],
      );
      await store.saveProvider(provider);
      await store.addSlotCandidate('video', provider.id, 'doubao-seedance-2-0-260128');

      final summary = VideoGenAdapterFactory.getSystemVideoConfigSummary();
      expect(summary.isConfigured, isTrue);
      expect(summary.providerName, equals('SenseAudio 视频中枢'));
      expect(summary.modelName, equals('doubao-seedance-2-0-260128'));
      expect(summary.description, equals('SenseAudio 视频中枢 (doubao-seedance-2-0-260128)'));
    });

    test('使用 system-video 引擎 ID 调用 VideoGenAdapterFactory.create 能够成功返回 SenseAudio 适配器', () async {
      final adapter = await VideoGenAdapterFactory.create(
        preferredEngineId: 'system-video',
      );

      // 工厂会把适配器包上能力规整（NormalizingVideoAdapter），所以先
      // unwrap 再断言具体类型——这是能力矩阵落地后的新形态（spec: 请求参数
      // 规整）。本地 Ken Burns 不被包装，它对 unwrap 同样成立。
      final inner = adapter is NormalizingVideoAdapter
          ? adapter.unwrap()
          : adapter;
      expect(inner, isA<SenseAudioVideoAdapter>());
      expect(inner.label, contains('doubao-seedance-2-0-260128'));
    });
  });
}
