/// 无限画布工具的持久化配置。
///
/// 全部经 [SettingsStore] 的 `config/infinite-canvas.json` 存放。
/// 无限画布自己的数据（AI 渠道密钥、画布、素材、生成记录）不在这里——它
/// 们只存在于浏览器本地存储里，宿主机文件系统上一个字节都没有（design D1）。
library;

import 'package:flutter/foundation.dart';

/// Compose 工程定位结果。
///
/// 区分「目录不存在」与「缺少文件」两种失败，因为两者的用户动作不同
/// （改路径 vs 检查仓库是否克隆完整）。[composeFile] 是实际命中的 compose
/// 文件名——上游提供的是 `docker-compose.yml` 而非 `compose.yaml`，override
/// 与 `-f` 参数都必须与它对齐（design D6）。
@immutable
class ProjectLocationResult {
  const ProjectLocationResult({
    required this.ok,
    this.path,
    this.composeFile,
    this.reason,
  });

  const ProjectLocationResult.found(String path, String composeFile)
    : this(ok: true, path: path, composeFile: composeFile);

  const ProjectLocationResult.failed(String reason)
    : this(ok: false, reason: reason);

  final bool ok;

  /// 定位成功时的工程目录。
  final String? path;

  /// 定位成功时实际命中的 compose 文件名。
  final String? composeFile;

  /// 定位失败时的可读原因。
  final String? reason;
}

/// 工具配置。
///
/// 全部字段都有默认值——配置文件缺失或损坏时工具必须还能打开，不能白屏
/// （与 `SettingsStore.readToolConfig` 的容错语义一致）。
@immutable
class InfiniteCanvasConfig {
  const InfiniteCanvasConfig({
    this.projectDir = defaultProjectDir,
    this.httpPort = defaultHttpPort,
    this.bridgePort = defaultBridgePort,
    this.stopOnAppExit = true,
    this.useLocalImage = false,
  });

  /// 本地构建镜像的 tag。
  ///
  /// 对应上游 `docker-compose.local.yml` 里的 `infinite-canvas:local`。
  static const String localImageName = 'infinite-canvas:local';

  /// 默认工程目录。用户机上的无限画布仓库位置。
  static const String defaultProjectDir =
      '/Users/simon/Workspace/github/infinite-canvas';

  /// 默认 HTTP 端口（spike 2026-10-11 实测 3000/8787/8797/3177 中它最空）。
  static const int defaultHttpPort = 3177;

  /// 资产桥 loopback 服务默认端口。
  ///
  /// 避开已占用的 8787/8788（ARTEX）与 8797（本地词典桥）。
  static const int defaultBridgePort = 8798;

  /// Compose 工程目录（含 `Dockerfile` 与一个 compose 文件）。
  final String projectDir;

  /// 工作台 HTTP 端口（宿主机侧，只绑 127.0.0.1）。
  final int httpPort;

  /// 资产桥 loopback 服务端口。
  final int bridgePort;

  /// 应用退出时是否停止容器（默认 true——安全默认值）。
  final bool stopOnAppExit;

  /// 是否改用本地构建的镜像而不是 ghcr.io 上的发布版。
  ///
  /// 默认 false：拉发布版不需要本地有仓库。只有在改过无限画布源码（例如给插件
  /// SDK 加了 `uploadReference`）时才打开——此时必须先在本机构建出
  /// [localImageName]。
  final bool useLocalImage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfiniteCanvasConfig &&
          runtimeType == other.runtimeType &&
          projectDir == other.projectDir &&
          httpPort == other.httpPort &&
          bridgePort == other.bridgePort &&
          stopOnAppExit == other.stopOnAppExit;

  @override
  int get hashCode =>
      Object.hash(projectDir, httpPort, bridgePort, stopOnAppExit);

  static const String _keyProjectDir = 'projectDir';
  static const String _keyHttpPort = 'httpPort';
  static const String _keyBridgePort = 'bridgePort';
  static const String _keyStopOnAppExit = 'stopOnAppExit';
  static const String _keyUseLocalImage = 'useLocalImage';

  factory InfiniteCanvasConfig.fromJson(Map<String, dynamic> json) {
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

    return InfiniteCanvasConfig(
      projectDir: readString(_keyProjectDir, defaultProjectDir),
      httpPort: readPort(_keyHttpPort, defaultHttpPort),
      bridgePort: readPort(_keyBridgePort, defaultBridgePort),
      // 缺省 true：退出即停是安全默认值，避免用户以为关了应用容器也停了。
      stopOnAppExit: json[_keyStopOnAppExit] as bool? ?? true,
      useLocalImage: json[_keyUseLocalImage] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    _keyProjectDir: projectDir,
    _keyHttpPort: httpPort,
    _keyBridgePort: bridgePort,
    _keyStopOnAppExit: stopOnAppExit,
    _keyUseLocalImage: useLocalImage,
  };

  InfiniteCanvasConfig copyWith({
    String? projectDir,
    int? httpPort,
    int? bridgePort,
    bool? stopOnAppExit,
    bool? useLocalImage,
  }) {
    return InfiniteCanvasConfig(
      projectDir: projectDir ?? this.projectDir,
      httpPort: httpPort ?? this.httpPort,
      bridgePort: bridgePort ?? this.bridgePort,
      stopOnAppExit: stopOnAppExit ?? this.stopOnAppExit,
      useLocalImage: useLocalImage ?? this.useLocalImage,
    );
  }
}
