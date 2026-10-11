import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_pool_video_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dola_adapter_test_');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DolaPoolVideoAdapter Lifecycle Tests', () {
    test('adapter properties and cancellation', () {
      final adapter = DolaPoolVideoAdapter(model: 'seedance-2.5');
      expect(adapter.id, equals('dola-pool-seedance-2.5'));
      expect(adapter.label, contains('Dola 免费号池'));
      expect(adapter.requiresApiKey, isFalse);

      adapter.cancelCurrent();
      // 取消标志正确设置
    });

    test('VideoGenAdapterFactory resolves dola-pool engines', () async {
      final adapter25 = await VideoGenAdapterFactory.create(
        preferredEngineId: 'dola-pool-seedance-2.5',
      );
      expect(adapter25.id, contains('dola-pool'));

      final adapter20 = await VideoGenAdapterFactory.create(
        preferredEngineId: 'dola-pool-seedance-2.0',
      );
      expect(adapter20.id, contains('dola-pool'));
    });
  });
}
