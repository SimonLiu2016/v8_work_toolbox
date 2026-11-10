import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/models/recording_models.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_recorder_store.dart';

void main() {
  late Directory tempDir;
  late MeetingRecorderStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('meeting_recorder_store_test_');
    AppPaths.overrideRootForTesting(tempDir);
    store = MeetingRecorderStore(
      customConfigFile: File('${tempDir.path}/test_meeting_recorder.json'),
    );
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('默认配置加载自动初始化输出目录并保存配置文件', () async {
    expect(await store.configFile.exists(), isFalse);

    final config = await store.loadConfig();
    expect(config.outputDirectory, isNotEmpty);
    expect(await store.configFile.exists(), isTrue);
    expect(Directory(config.outputDirectory).existsSync(), isTrue);
  });

  test('保存新配置并重新加载能准确还原', () async {
    final customTargetDir = Directory('${tempDir.path}/my_custom_recordings');
    final newConfig = MeetingRecorderConfig(
      outputDirectory: customTargetDir.path,
      selectedDeviceId: 2,
      selectedDeviceName: 'USB 会议麦克风',
      playbackRate: 1.5,
    );

    await store.saveConfig(newConfig);
    expect(customTargetDir.existsSync(), isTrue);

    final loaded = await store.loadConfig();
    expect(loaded.outputDirectory, customTargetDir.path);
    expect(loaded.selectedDeviceId, 2);
    expect(loaded.selectedDeviceName, 'USB 会议麦克风');
    expect(loaded.playbackRate, 1.5);
  });

  test('损坏的 JSON 配置文件能自动自愈重置为默认', () async {
    await store.configFile.writeAsString('{ invalid_json ...');
    final config = await store.loadConfig();
    expect(config.outputDirectory, isNotEmpty);
  });
}
