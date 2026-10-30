import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_settings_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('engine_matrix_test_');
    AppPaths.overrideRootForTesting(tempDir);
    await AiConfigStore.instance.init();
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StudioCapability Engine Matrix Tests', () {
    test('StudioCapability covers all 6 dimensions', () {
      expect(StudioCapability.values.length, 6);
      expect(StudioCapability.values.map((c) => c.id).toList(), [
        'text',
        'vision',
        'image',
        'video',
        'tts',
        'stt',
      ]);
    });

    test('StudioCapability labels are human-readable and describe roles', () {
      expect(StudioCapability.text.label, contains('剧本'));
      expect(StudioCapability.vision.label, contains('多模态视觉审片'));
      expect(StudioCapability.image.label, contains('图像生成'));
      expect(StudioCapability.video.label, contains('视频生成'));
      expect(StudioCapability.tts.label, contains('配音'));
      expect(StudioCapability.stt.label, contains('识别'));
    });

    test('Unconfigured slots report informative fallback messages', () {
      final textSummary = StudioCapability.text;
      expect(textSummary.id, 'text');
      expect(AiConfigStore.instance.slotBindings['text'], isNotNull);
    });
  });
}
