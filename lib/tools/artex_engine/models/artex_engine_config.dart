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
    this.callbackAddr,
    this.tunnelPortMin = defaultTunnelPortMin,
    this.tunnelPortMax = defaultTunnelPortMax,
  });

  /// 默认工程目录。用户机上的 artex 仓库位置（spike 使用的路径）。
  static const String defaultProjectDir =
      '/Users/simon/Workspace/github/artex-ymh';

  static const int defaultHttpPort = 8787;
  static const int defaultProxyPort = 8788;

  /// 隧道端口池默认范围（design D2）。
  ///
  /// 上游 ARTEX 默认 20000-21000（1001 个），单人场景用不上 500 条并发隧道，
  /// 而全量发布会让 `docker compose up -d` 从 3 秒变成 41 秒（实测）。
  /// 100 个端口 = 50 条隧道（每条消耗 2 个端口），单人远够。
  static const int defaultTunnelPortMin = 20000;
  static const int defaultTunnelPortMax = 20099;

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

  // --- 内网回连（add-novel-manager 之后的 fix-artex-internal-network-reachability）---

  /// 平台回连地址。null = 启动时自动探测宿主机物理网卡 IPv4。
  ///
  /// 内网目标机（隧道 / 反弹 shell）回连平台时用它。必须是宿主机上可被
  /// 内网路由到的 IPv4——写 `127.0.0.1` 或 Docker VM 的地址都会让目标机
  /// 连不回来。
  final String? callbackAddr;

  /// 隧道端口池起止端口。
  ///
  /// 与 override 里发布的端口范围必须同源（design D2）：池决定 ARTEX 分配
  /// 哪些端口，发布决定哪些端口有 NAT。两者不一致时，隧道会静默不可用。
  final int tunnelPortMin;
  final int tunnelPortMax;

  static const String _keyProjectDir = 'projectDir';
  static const String _keyHttpPort = 'httpPort';
  static const String _keyProxyPort = 'proxyPort';
  static const String _keyStopOnAppExit = 'stopOnAppExit';
  static const String _keyGateOff = 'gateOff';
  static const String _keyNpmRegistry = 'npmRegistry';
  static const String _keyGoProxy = 'goProxy';
  static const String _keyAptMirror = 'aptMirror';
  static const String _keyCallbackAddr = 'callbackAddr';
  static const String _keyTunnelPortMin = 'tunnelPortMin';
  static const String _keyTunnelPortMax = 'tunnelPortMax';

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
      // null = 未手动指定，走自动探测。空字符串等同未指定（容错）。
      callbackAddr: (json[_keyCallbackAddr] as String?)?.trim().isNotEmpty == true
          ? (json[_keyCallbackAddr] as String).trim()
          : null,
      tunnelPortMin: _readPort(json, _keyTunnelPortMin, defaultTunnelPortMin),
      tunnelPortMax: _readPort(json, _keyTunnelPortMax, defaultTunnelPortMax),
    );
  }

  /// 读端口字段，容忍 int 与字符串两种形态（设置界面存的可能是字符串）。
  static int _readPort(Map<String, dynamic> json, String key, int fallback) {
    final raw = json[key];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
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
    // null 时写空串而不是省掉 key：让 JSON 里能看到这个字段存在，
    // 用户手动编辑配置文件时知道有这一项。
    _keyCallbackAddr: callbackAddr ?? '',
    _keyTunnelPortMin: tunnelPortMin,
    _keyTunnelPortMax: tunnelPortMax,
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
    String? callbackAddr,
    int? tunnelPortMin,
    int? tunnelPortMax,
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
      callbackAddr: callbackAddr ?? this.callbackAddr,
      tunnelPortMin: tunnelPortMin ?? this.tunnelPortMin,
      tunnelPortMax: tunnelPortMax ?? this.tunnelPortMax,
    );
  }
}
