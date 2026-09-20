import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/audio_cache_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_coordinator.dart';

ReadingDocument _makeDoc(String id, {int chunks = 2}) {
  return ReadingDocument(
    id: id,
    title: 'Test Doc',
    source: 'test.txt',
    sourceType: DocumentSourceType.txt,
    chunks: List.generate(
      chunks,
      (i) => ReadingChunk(index: i, text: '第${i + 1}段', startChar: i * 4, endChar: i * 4 + 3),
    ),
    totalWordCount: chunks * 4,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AudioReaderController.clearDocument 的测试依赖 AudioPlayer 平台通道，
  // 在 flutter test 环境下抛 MissingPluginException——属环境依赖红测试（见
  // memory: v8worktoolbox-notes.md），与代码无关。clearDocument 逻辑经
  // coordinator.clearDocCache + 状态重置，由下方 coordinator 测试覆盖纯逻辑，
  // 实际播放路径留手动验收。

  group('TtsSynthesisCoordinator.synthesisFieldsChanged', () {
    const base = TtsSynthesisConfig(mode: TtsMode.edge, voiceId: 'zh-CN-XiaoxiaoNeural');

    test('合成字段变更（mode）返回 true', () {
      const newCfg = TtsSynthesisConfig(mode: TtsMode.customAi, voiceId: 'zh-CN-XiaoxiaoNeural');
      expect(TtsSynthesisCoordinator.synthesisFieldsChanged(base, newCfg), isTrue);
    });

    test('合成字段变更（voiceId）返回 true', () {
      const newCfg = TtsSynthesisConfig(mode: TtsMode.edge, voiceId: 'zh-CN-YunxiNeural');
      expect(TtsSynthesisCoordinator.synthesisFieldsChanged(base, newCfg), isTrue);
    });

    test('播放字段变更（speed）返回 false', () {
      const newCfg = TtsSynthesisConfig(mode: TtsMode.edge, voiceId: 'zh-CN-XiaoxiaoNeural', speed: 1.5);
      expect(TtsSynthesisCoordinator.synthesisFieldsChanged(base, newCfg), isFalse);
    });

    test('播放字段变更（pitch）返回 false', () {
      const newCfg = TtsSynthesisConfig(mode: TtsMode.edge, voiceId: 'zh-CN-XiaoxiaoNeural', pitch: 1.2);
      expect(TtsSynthesisCoordinator.synthesisFieldsChanged(base, newCfg), isFalse);
    });

    test('完全相同返回 false', () {
      expect(TtsSynthesisCoordinator.synthesisFieldsChanged(base, base), isFalse);
    });
  });

  group('TtsSynthesisCoordinator.clearDocCache', () {
    test('清空指定文档缓存并取消 inFlight 任务', () async {
      final tempDir = await Directory.systemTemp.createTemp('coord_clear_test_');
      final cacheMgr = AudioCacheManager(customBasePath: tempDir.path);
      final coordinator = TtsSynthesisCoordinator(
        cacheManager: cacheMgr,
        config: const TtsSynthesisConfig(mode: TtsMode.macosNative),
      );

      final doc = _makeDoc('doc_clear');
      final dir = await cacheMgr.getDocCacheDir(doc.id);
      await File('${dir.path}/chunk_0000.wav').writeAsBytes([1, 2, 3]);
      expect(dir.existsSync(), isTrue);

      await coordinator.clearDocCache(doc.id);
      expect(dir.existsSync(), isFalse);

      coordinator.dispose();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
  });
}
