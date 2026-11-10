import 'dart:convert';
import 'dart:io';

import '../../../services/app_paths.dart';
import '../models/recording_models.dart';

/// 会议录音配置存储服务
class MeetingRecorderStore {
  final File? _customConfigFile;

  MeetingRecorderStore({File? customConfigFile})
      : _customConfigFile = customConfigFile;

  File get configFile =>
      _customConfigFile ?? AppPaths.meetingRecorderConfigFile;

  /// 加载录音配置。若配置文件不存在或内容损坏，返回默认配置并初始化目录。
  Future<MeetingRecorderConfig> loadConfig() async {
    final file = configFile;
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          final config = MeetingRecorderConfig.fromJson(json);
          // 确保输出目录存在
          if (config.outputDirectory.isNotEmpty) {
            final dir = Directory(config.outputDirectory);
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
          }
          return config;
        }
      } catch (_) {}
    }

    // 默认配置
    final defaultDir = AppPaths.defaultMeetingRecordingsDir;
    if (!await defaultDir.exists()) {
      try {
        await defaultDir.create(recursive: true);
      } catch (_) {}
    }

    final defaultConfig = MeetingRecorderConfig(
      outputDirectory: defaultDir.path,
    );
    await saveConfig(defaultConfig);
    return defaultConfig;
  }

  /// 保存录音配置并确保目标目录存在。
  Future<void> saveConfig(MeetingRecorderConfig config) async {
    final file = configFile;
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    if (config.outputDirectory.isNotEmpty) {
      final dir = Directory(config.outputDirectory);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (_) {}
      }
    }

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config.toJson()), flush: true);
  }
}
