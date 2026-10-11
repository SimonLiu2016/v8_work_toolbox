import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/settings_store.dart';
import '../models/toonflow_studio_config.dart';

/// 工具配置的持久化键（`SettingsStore` 的 `config/<toolId>.json`）。
const String kToonflowStudioToolId = 'toonflow-studio';

/// Compose 文件名。定位校验只认这两个（spec: Compose 工程定位）。
const String kToonflowComposeFileName = 'compose.yaml';
const String kToonflowDockerfileName = 'Dockerfile';

/// Toonflow 工坊工具的配置存取与工程目录定位校验。
///
/// 与 [SettingsStore] 的关系：这里是薄封装，负责默认值、类型宽容与失败
/// 兜底；真正落盘由 `SettingsStore.writeToolConfig` 的原子写完成。
/// 读失败一律回退默认配置而不是抛异常——配置损坏不该让工具打不开。
class ToonflowConfigStore extends ChangeNotifier {
  ToonflowConfigStore._();
  static final ToonflowConfigStore instance = ToonflowConfigStore._();

  ToonflowStudioConfig _config = const ToonflowStudioConfig();
  bool _loaded = false;

  ToonflowStudioConfig get config => _config;
  bool get isLoaded => _loaded;

  /// 加载配置。重复调用安全。
  Future<void> load() async {
    try {
      final data = await SettingsStore.instance.readToolConfig(
        kToonflowStudioToolId,
      );
      _config = data.isEmpty
          ? const ToonflowStudioConfig()
          : ToonflowStudioConfig.fromJson(data);
    } catch (e) {
      debugPrint('[ToonflowConfigStore] 读取配置失败，使用默认值: $e');
      _config = const ToonflowStudioConfig();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存配置。
  Future<void> save(ToonflowStudioConfig next) async {
    _config = next;
    try {
      await SettingsStore.instance.writeToolConfig(
        kToonflowStudioToolId,
        next.toJson(),
      );
    } catch (e) {
      debugPrint('[ToonflowConfigStore] 保存配置失败: $e');
    }
    notifyListeners();
  }

  /// 定位 Compose 工程目录。
  ///
  /// 区分三种失败，因为用户的动作不同（spec: Compose 工程定位）：
  /// - 目录不存在 → 改路径
  /// - 缺 `compose.yaml` / `Dockerfile` → 仓库没克隆完整
  ProjectLocationResult locateProject([String? dir]) {
    final target = (dir ?? _config.projectDir).trim();
    if (target.isEmpty) {
      return const ProjectLocationResult.failed('工程目录未配置');
    }
    final directory = Directory(target);
    if (!directory.existsSync()) {
      return ProjectLocationResult.failed('工程目录不存在：$target');
    }
    if (!File(p.join(target, kToonflowComposeFileName)).existsSync()) {
      return ProjectLocationResult.failed(
        '目录中未找到 $kToonflowComposeFileName：$target',
      );
    }
    if (!File(p.join(target, kToonflowDockerfileName)).existsSync()) {
      return ProjectLocationResult.failed(
        '目录中未找到 $kToonflowDockerfileName：$target',
      );
    }
    return ProjectLocationResult.found(target);
  }

  /// 测试用：直接替换配置（绕过 SettingsStore 的异步落盘）。
  @visibleForTesting
  void setConfigForTesting(ToonflowStudioConfig c) {
    _config = c;
    _loaded = true;
    notifyListeners();
  }

  /// 测试用：恢复默认配置。
  @visibleForTesting
  void resetForTesting() {
    _config = const ToonflowStudioConfig();
    _loaded = false;
  }
}
