/// ARTEX 引擎工具的持久化配置。
///
/// 全部经 [SettingsStore] 的 `config/artex-engine.json` 存放
/// （task 3.2）。引擎自身的数据（PG 命名卷 + 工程目录下 `data/`）不在
/// 这里，也不进 `AppPaths`——见 `AppPaths.artexDir` 的注释与 design D6。
library;

import 'package:flutter/foundation.dart';

/// Compose 工程定位结果。区分「目录不存在」与「缺少 compose 文件」两种
/// 失败，因为两者的用户动作不同（改路径 vs 检查仓库是否完整）。
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

@immutable
class ArtexEngineConfig {
  const ArtexEngineConfig({
    this.projectDir = defaultProjectDir,
    this.httpPort = defaultHttpPort,
    this.proxyPort = defaultProxyPort,
    this.stopOnAppExit = true,
    this.gateOff = true,
    this.npmRegistry = defaultNpmRegistry,
    this.goProxy = defaultGoProxy,
    this.aptMirror = defaultAptMirror,
  });

  /// 默认工程目录。用户机上的 artex 仓库位置（spike 使用的路径）。
  static const String defaultProjectDir =
      '/Users/simon/Workspace/github/artex-ymh';

  static const int defaultHttpPort = 8787;
  static const int defaultProxyPort = 8788;

  /// 三个上游构建参数默认值（spike 用这三个 9 分钟构建成功，design D4）。
  static const String defaultNpmRegistry = 'https://registry.npmmirror.com';
  static const String defaultGoProxy = 'https://goproxy.cn,direct';
  static const String defaultAptMirror = 'mirrors.aliyun.com';

  /// Compose 工程目录。
  final String projectDir;

  /// 引擎 HTTP 端口（宿主机侧）。
  final int httpPort;

  /// 流量录制代理端口（宿主机侧）。
  final int proxyPort;

  /// 应用退出时是否停止引擎容器（spec「应用退出时的容器处置」）。
  final bool stopOnAppExit;

  /// 是否通过 override 关闭引擎的伪装门控。
  ///
  /// 单机部署必须关闭：容器内绑 `:8787` 会被门控判定为非 loopback 而自动
  /// 开启，导致 `/api/health` 返回假 nginx 欢迎页（spike 实测）。
  final bool gateOff;

  // --- 镜像构建参数（design D4）---

  final String npmRegistry;
  final String goProxy;
  final String aptMirror;

  static const String _keyProjectDir = 'projectDir';
  static const String _keyHttpPort = 'httpPort';
  static const String _keyProxyPort = 'proxyPort';
  static const String _keyStopOnAppExit = 'stopOnAppExit';
  static const String _keyGateOff = 'gateOff';
  static const String _keyNpmRegistry = 'npmRegistry';
  static const String _keyGoProxy = 'goProxy';
  static const String _keyAptMirror = 'aptMirror';

  factory ArtexEngineConfig.fromJson(Map<String, dynamic> json) {
    int readPort(String key, int fallback) {
      final raw = json[key];
      if (raw is int) return raw;
      if (raw is String) return int.tryParse(raw) ?? fallback;
      return fallback;
    }

    return ArtexEngineConfig(
      projectDir: (json[_keyProjectDir] as String?)?.trim().isNotEmpty == true
          ? (json[_keyProjectDir] as String).trim()
          : defaultProjectDir,
      httpPort: readPort(_keyHttpPort, defaultHttpPort),
      proxyPort: readPort(_keyProxyPort, defaultProxyPort),
      // 缺省 true：退出即停是安全默认值，避免用户以为关了应用引擎也停了。
      stopOnAppExit: json[_keyStopOnAppExit] as bool? ?? true,
      gateOff: json[_keyGateOff] as bool? ?? true,
      npmRegistry: (json[_keyNpmRegistry] as String?)?.trim().isNotEmpty == true
          ? (json[_keyNpmRegistry] as String).trim()
          : defaultNpmRegistry,
      goProxy: (json[_keyGoProxy] as String?)?.trim().isNotEmpty == true
          ? (json[_keyGoProxy] as String).trim()
          : defaultGoProxy,
      aptMirror: (json[_keyAptMirror] as String?)?.trim().isNotEmpty == true
          ? (json[_keyAptMirror] as String).trim()
          : defaultAptMirror,
    );
  }

  Map<String, dynamic> toJson() => {
    _keyProjectDir: projectDir,
    _keyHttpPort: httpPort,
    _keyProxyPort: proxyPort,
    _keyStopOnAppExit: stopOnAppExit,
    _keyGateOff: gateOff,
    _keyNpmRegistry: npmRegistry,
    _keyGoProxy: goProxy,
    _keyAptMirror: aptMirror,
  };

  ArtexEngineConfig copyWith({
    String? projectDir,
    int? httpPort,
    int? proxyPort,
    bool? stopOnAppExit,
    bool? gateOff,
    String? npmRegistry,
    String? goProxy,
    String? aptMirror,
  }) {
    return ArtexEngineConfig(
      projectDir: projectDir ?? this.projectDir,
      httpPort: httpPort ?? this.httpPort,
      proxyPort: proxyPort ?? this.proxyPort,
      stopOnAppExit: stopOnAppExit ?? this.stopOnAppExit,
      gateOff: gateOff ?? this.gateOff,
      npmRegistry: npmRegistry ?? this.npmRegistry,
      goProxy: goProxy ?? this.goProxy,
      aptMirror: aptMirror ?? this.aptMirror,
    );
  }
}
