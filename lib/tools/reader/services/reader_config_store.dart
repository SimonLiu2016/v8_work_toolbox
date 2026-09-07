import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../services/ai_config_store.dart';
import '../models/reader_models.dart';

/// 朗读助手用户合成配置持久化管理中心
class ReaderConfigStore {
  ReaderConfigStore._();
  static final ReaderConfigStore instance = ReaderConfigStore._();

  static const String _fileName = 'reader_config.json';
  File? _file;
  TtsSynthesisConfig? _cachedConfig;

  TtsSynthesisConfig get config => _cachedConfig ?? const TtsSynthesisConfig();

  Future<File> _resolveConfigFile({Directory? customRootDir}) async {
    if (_file != null && customRootDir == null) return _file!;
    Directory dir;
    if (customRootDir != null) {
      dir = Directory(p.join(customRootDir.path, 'config'));
    } else {
      final home = Platform.environment['HOME'];
      if (Platform.isMacOS && home != null && home.isNotEmpty) {
        dir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox', 'config'));
      } else {
        final appSupport = await getApplicationSupportDirectory();
        dir = Directory(p.join(appSupport.path, 'V8WorkToolbox', 'config'));
      }
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  /// 智能推导初始默认配置（当没有历史配置记录时）
  TtsSynthesisConfig resolveSmartDefault() {
    final aiStore = AiConfigStore.instance;
    final enabledProviders = aiStore.providers.where((p) => p.enabled).toList();

    // 1. 优先寻找 TTS 槽位绑定的候选
    final ttsCandidates = aiStore.slotBindings['tts'] ?? [];
    for (final cand in ttsCandidates) {
      final matched = enabledProviders.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == cand.providerId,
        orElse: () => null,
      );
      if (matched != null) {
        final model = cand.model.isNotEmpty
            ? cand.model
            : (matched.ttsModels.isNotEmpty ? matched.ttsModels.first : 'mimo-v2.5-tts');
        final isMiMo = model.toLowerCase().contains('mimo') || matched.baseUrl.toLowerCase().contains('xiaomi');
        return TtsSynthesisConfig(
          mode: TtsMode.customAi,
          useSystemAiConfig: true,
          systemProviderId: matched.id,
          customModel: model,
          customVoiceId: isMiMo ? 'mimo_default' : null,
          voiceId: isMiMo ? 'mimo_default' : 'zh-CN-XiaoxiaoNeural',
        );
      }
    }

    // 2. 检查是否有包含 ttsModels 的已启用供应商
    final ttsProvider = enabledProviders.cast<AiProviderConfig?>().firstWhere(
      (p) => p != null && p.ttsModels.isNotEmpty,
      orElse: () => null,
    );
    if (ttsProvider != null) {
      final model = ttsProvider.ttsModels.first;
      final isMiMo = model.toLowerCase().contains('mimo') || ttsProvider.baseUrl.toLowerCase().contains('xiaomi');
      return TtsSynthesisConfig(
        mode: TtsMode.customAi,
        useSystemAiConfig: true,
        systemProviderId: ttsProvider.id,
        customModel: model,
        customVoiceId: isMiMo ? 'mimo_default' : null,
        voiceId: isMiMo ? 'mimo_default' : 'zh-CN-XiaoxiaoNeural',
      );
    }

    // 3. 无商用 TTS 供应商时，默认使用 macOS Native (离线可用且稳定)
    return const TtsSynthesisConfig(
      mode: TtsMode.macosNative,
      voiceId: 'zh-CN-Tingting',
    );
  }

  /// 加载配置，若不存在则智能生成并落盘保存
  Future<TtsSynthesisConfig> loadConfig({Directory? customRootDir}) async {
    try {
      final file = await _resolveConfigFile(customRootDir: customRootDir);
      _file = file;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          _cachedConfig = TtsSynthesisConfig.fromJson(json);
          return _cachedConfig!;
        }
      }
    } catch (e) {
      debugPrint('读取 ReaderConfig 异常: $e');
    }

    // 生成智能默认配置并保存
    final defaultConfig = resolveSmartDefault();
    _cachedConfig = defaultConfig;
    await saveConfig(defaultConfig, customRootDir: customRootDir);
    return defaultConfig;
  }

  /// 保存配置并同步内存缓存
  Future<void> saveConfig(TtsSynthesisConfig config, {Directory? customRootDir}) async {
    _cachedConfig = config;
    try {
      final file = await _resolveConfigFile(customRootDir: customRootDir);
      _file = file;
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
    } catch (e) {
      debugPrint('保存 ReaderConfig 失败: $e');
    }
  }
}
