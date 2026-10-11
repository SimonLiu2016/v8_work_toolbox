/// Toonflow 漫剧工坊工具的持久化配置。
///
/// 全部经 [SettingsStore] 的 `config/toonflow-studio.json` 存放。
/// Toonflow 自己的数据（`data/workspaces`、`data/assets`、`data/settings.json`）
/// 不在这里，而归 [AppPaths.toonflowDataDir]——那是 bind mount 给容器的。
library;

import 'package:flutter/foundation.dart';

/// Compose 工程定位结果。区分「目录不存在」与「缺少文件」两种失败，因为
/// 两者的用户动作不同（改路径 vs 检查仓库是否克隆完整）。
@immutable
class ProjectLocationResult {
  const ProjectLocationResult({required this.ok, this.path, this.reason});

  const ProjectLocationResult.found(String path) : this(ok: true, path: path);

  const ProjectLocationResult.failed(String reason)
    : this(ok: false, reason: reason);

  final bool ok;

  /// 定位成功时的工程目录。
  final String? path;

  /// 定位失败时的可读原因。
  final String? reason;
}

/// 工具配置。
///
/// 全部字段都有默认值——配置文件缺失或损坏时工具必须还能打开，不能白屏
/// （与 `SettingsStore.readToolConfig` 的容错语义一致）。
@immutable
class ToonflowStudioConfig {
  const ToonflowStudioConfig({
    this.projectDir = defaultProjectDir,
    this.httpPort = defaultHttpPort,
    this.stopOnAppExit = true,
    this.bunRegistry = defaultBunRegistry,
    this.autoStartOnOpen = false,
  });

  /// 默认工程目录。用户机上的 Toonflow 仓库位置。
  static const String defaultProjectDir =
      '/Users/simon/Workspace/github/Toonflow-app';

  /// 默认 HTTP 端口（spike 2026-10-11 实测 3000/8787/8797/3177 中它最空）。
  static const int defaultHttpPort = 3177;

  /// bun 镜像站默认值。Docker Hub 在本机不可直连（spike 实测 TLS 超时），
  /// 构建期走国内源能显著提高首次构建成功率。
  static const String defaultBunRegistry = 'https://registry.npmmirror.com';

  /// Compose 工程目录（含 `Dockerfile` 与 `compose.yaml`）。
  final String projectDir;

  /// HTTP 端口（宿主机侧）。
  final int httpPort;

  /// 应用退出时是否停止容器（默认 true——安全默认值）。
  final bool stopOnAppExit;

  /// bun 包管理器镜像站。注入到构建环境的 `BUN_CONFIG_REGISTRY`。
  final String bunRegistry;

  /// 打开工具页时是否自动启动容器。
  final bool autoStartOnOpen;

  static const String _keyProjectDir = 'projectDir';
  static const String _keyHttpPort = 'httpPort';
  static const String _keyStopOnAppExit = 'stopOnAppExit';
  static const String _keyBunRegistry = 'bunRegistry';
  static const String _keyAutoStart = 'autoStartOnOpen';

  factory ToonflowStudioConfig.fromJson(Map<String, dynamic> json) {
    int readPort(String key, int fallback) {
      final raw = json[key];
      if (raw is int) return raw;
      // 用户可能手工把端口写成字符串。
      if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
      return fallback;
    }

    String readString(String key, String fallback) {
      final raw = json[key];
      if (raw is! String) return fallback;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? fallback : trimmed;
    }

    return ToonflowStudioConfig(
      projectDir: readString(_keyProjectDir, defaultProjectDir),
      httpPort: readPort(_keyHttpPort, defaultHttpPort),
      // 缺省 true：退出即停是安全默认值，避免用户以为关了应用容器也停了。
      stopOnAppExit: json[_keyStopOnAppExit] as bool? ?? true,
      bunRegistry: readString(_keyBunRegistry, defaultBunRegistry),
      autoStartOnOpen: json[_keyAutoStart] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    _keyProjectDir: projectDir,
    _keyHttpPort: httpPort,
    _keyStopOnAppExit: stopOnAppExit,
    _keyBunRegistry: bunRegistry,
    _keyAutoStart: autoStartOnOpen,
  };

  ToonflowStudioConfig copyWith({
    String? projectDir,
    int? httpPort,
    bool? stopOnAppExit,
    String? bunRegistry,
    bool? autoStartOnOpen,
  }) {
    return ToonflowStudioConfig(
      projectDir: projectDir ?? this.projectDir,
      httpPort: httpPort ?? this.httpPort,
      stopOnAppExit: stopOnAppExit ?? this.stopOnAppExit,
      bunRegistry: bunRegistry ?? this.bunRegistry,
      autoStartOnOpen: autoStartOnOpen ?? this.autoStartOnOpen,
    );
  }
}
