import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/settings_store.dart';
import '../models/infinite_canvas_config.dart';

/// 工具配置的持久化键（`SettingsStore` 的 `config/<toolId>.json`）。
const String kInfiniteCanvasToolId = 'infinite-canvas';

/// 受支持的 compose 文件名，按探测顺序排列。
///
/// 上游实际提供的是 `docker-compose.yml`——只认 `compose.yaml` 会让定位
/// 直接失败（design D6）。
const List<String> kComposeFileNames = <String>[
  'compose.yaml',
  'compose.yml',
  'docker-compose.yml',
];

/// Dockerfile 文件名。定位校验必需。
const String kDockerfileName = 'Dockerfile';

/// 无限画布工具的配置存取与工程目录定位校验。
///
/// 与 [SettingsStore] 的关系：这里是薄封装，负责默认值、类型宽容与失败
/// 兜底；真正落盘由 `SettingsStore.writeToolConfig` 的原子写完成。
/// 读失败一律回退默认配置而不是抛异常——配置损坏不该让工具打不开。
class InfiniteCanvasConfigStore extends ChangeNotifier {
  InfiniteCanvasConfigStore._();
  static final InfiniteCanvasConfigStore instance =
      InfiniteCanvasConfigStore._();

  InfiniteCanvasConfig _config = const InfiniteCanvasConfig();
  bool _loaded = false;

  InfiniteCanvasConfig get config => _config;
  bool get isLoaded => _loaded;

  /// 加载配置。重复调用安全。
  Future<void> load() async {
    try {
      final data = await SettingsStore.instance.readToolConfig(
        kInfiniteCanvasToolId,
      );
      _config = data.isEmpty
          ? const InfiniteCanvasConfig()
          : InfiniteCanvasConfig.fromJson(data);
    } catch (e) {
      debugPrint('[InfiniteCanvasConfigStore] 读取配置失败，使用默认值: $e');
      _config = const InfiniteCanvasConfig();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存配置。
  Future<void> save(InfiniteCanvasConfig next) async {
    _config = next;
    try {
      await SettingsStore.instance.writeToolConfig(
        kInfiniteCanvasToolId,
        next.toJson(),
      );
    } catch (e) {
      debugPrint('[InfiniteCanvasConfigStore] 保存配置失败: $e');
    }
    notifyListeners();
  }

  /// 定位 Compose 工程目录。
  ///
  /// 区分三种失败，因为用户的动作不同（spec: Compose 工程定位）：
  /// - 目录不存在 → 改路径
  /// - 缺 `Dockerfile` → 仓库没克隆完整
  /// - 缺 compose 文件 → 同上，但要把探测过的三个名字列出来
  ProjectLocationResult locateProject([String? dir]) {
    final target = (dir ?? _config.projectDir).trim();
    if (target.isEmpty) {
      return const ProjectLocationResult.failed('工程目录未配置');
    }
    final directory = Directory(target);
    if (!directory.existsSync()) {
      return ProjectLocationResult.failed('工程目录不存在：$target');
    }
    if (!File(p.join(target, kDockerfileName)).existsSync()) {
      return ProjectLocationResult.failed(
        '目录中未找到 $kDockerfileName：$target',
      );
    }
    for (final name in kComposeFileNames) {
      if (File(p.join(target, name)).existsSync()) {
        return ProjectLocationResult.found(target, name);
      }
    }
    return ProjectLocationResult.failed(
      '目录中未找到 ${kComposeFileNames.join(' 或 ')}：$target',
    );
  }

  /// 测试用：直接替换配置（绕过 SettingsStore 的异步落盘）。
  @visibleForTesting
  void setConfigForTesting(InfiniteCanvasConfig c) {
    _config = c;
    _loaded = true;
    notifyListeners();
  }

  /// 测试用：恢复默认配置。
  @visibleForTesting
  void resetForTesting() {
    _config = const InfiniteCanvasConfig();
    _loaded = false;
  }
}
