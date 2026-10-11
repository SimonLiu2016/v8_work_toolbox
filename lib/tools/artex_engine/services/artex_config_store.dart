import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/settings_store.dart';
import '../models/artex_engine_config.dart';

/// 工具配置的持久化键（`SettingsStore` 的 `config/<toolId>.json`）。
const String kArtexEngineToolId = 'artex-engine';

/// Compose 文件名。定位校验只认这个（spec「Compose 工程定位」）。
const String kArtexComposeFileName = 'docker-compose.yml';

/// ARTEX 引擎工具的配置存取与工程目录定位校验。
///
/// 与 [SettingsStore] 的关系：这里是薄封装，负责默认值、类型宽容与失败
/// 兜底；真正落盘由 `SettingsStore.writeToolConfig` 的原子写完成。
/// 读失败一律回退默认配置而不是抛异常——配置损坏不应让工具打不开
/// （与 `SettingsStore.readToolConfig` 自身的容错语义一致）。
class ArtexConfigStore extends ChangeNotifier {
  ArtexConfigStore._();
  static final ArtexConfigStore instance = ArtexConfigStore._();

  ArtexEngineConfig _config = const ArtexEngineConfig();
  bool _loaded = false;

  ArtexEngineConfig get config => _config;
  bool get isLoaded => _loaded;

  /// 加载配置。重复调用安全。
  Future<void> load() async {
    try {
      final data = await SettingsStore.instance.readToolConfig(
        kArtexEngineToolId,
      );
      _config = data.isEmpty
          ? const ArtexEngineConfig()
          : ArtexEngineConfig.fromJson(data);
    } catch (e) {
      debugPrint('[ArtexConfigStore] 读取配置失败，使用默认值: $e');
      _config = const ArtexEngineConfig();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存配置。
  Future<void> save(ArtexEngineConfig next) async {
    _config = next;
    try {
      await SettingsStore.instance.writeToolConfig(
        kArtexEngineToolId,
        next.toJson(),
      );
    } catch (e) {
      debugPrint('[ArtexConfigStore] 保存配置失败: $e');
    }
    notifyListeners();
  }

  /// 定位 Compose 工程目录。
  ///
  /// 区分「目录不存在」与「目录里没有 docker-compose.yml」：前者用户要改
  /// 路径，后者多半是仓库没克隆完整，提示不同（spec「Compose 工程定位」）。
  ProjectLocationResult locateProject([String? dir]) {
    final target = (dir ?? _config.projectDir).trim();
    if (target.isEmpty) {
      return const ProjectLocationResult.failed('工程目录未配置');
    }
    final directory = Directory(target);
    if (!directory.existsSync()) {
      return ProjectLocationResult.failed('工程目录不存在：$target');
    }
    if (!File(p.join(target, kArtexComposeFileName)).existsSync()) {
      return ProjectLocationResult.failed(
        '目录中未找到 $kArtexComposeFileName：$target',
      );
    }
    return ProjectLocationResult.found(target);
  }

  /// 测试用：直接替换配置（绕过 SettingsStore 的异步落盘）。
  @visibleForTesting
  void setConfigForTesting(ArtexEngineConfig c) {
    _config = c;
    _loaded = true;
    notifyListeners();
  }

  /// 测试用：恢复默认配置。
  @visibleForTesting
  void resetForTesting() {
    _config = const ArtexEngineConfig();
    _loaded = false;
  }
}
