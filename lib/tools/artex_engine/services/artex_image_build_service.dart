import 'dart:async';

import 'package:flutter/foundation.dart';

import 'artex_config_store.dart';
import 'artex_override_store.dart';
import 'process_runner.dart';

/// 构建失败的类别。
///
/// spike（2026-10-10）证明失败诊断是这个按钮存在的核心理由：第一次构建
/// 100% 死在镜像源 403 上，而原始输出对用户毫无指引意义。每一类都对应
/// 一个**用户能执行的动作**，而不是把 docker 的输出转述一遍。
enum ArtexBuildFailureKind {
  /// Docker 守护进程不可达。
  dockerUnavailable(
    'Docker 未运行',
    '请先启动 Docker Desktop 并等待其完全就绪，然后重试。',
  ),

  /// 镜像加速器返回 403。
  ///
  /// spike 实测：`vjqci0ng.mirror.aliyuncs.com` 对 `docker/dockerfile:1`
  /// 返回 403。阿里云个人加速器 2024 年后收紧了可用范围。
  mirrorForbidden(
    'Docker 镜像源失效',
    'Docker 配置的镜像加速器返回了 403。请在 Docker Desktop → Settings → '
    'Docker Engine 中移除或更换 registry-mirrors，然后重试。',
  ),

  /// 网络超时。
  networkTimeout(
    '网络不通',
    '拉取镜像或下载依赖超时。请检查 VPN / 代理后重试——已完成的构建层有缓存，'
    '重试不会从零开始。',
  ),

  /// 缺少 compose 要求的环境变量。
  missingEnv(
    '缺少环境变量配置',
    'Docker Compose 要求的环境变量未设置。请生成默认 .env 后重试。',
  ),

  /// playwright / chromium 下载失败。
  ///
  /// 这三个上游构建参数（NPM_REGISTRY / GOPROXY / APT_MIRROR）管不到
  /// playwright.azureedge.net 与 deb.nodesource.com，所以单独一类。
  chromiumDownload(
    '浏览器组件下载失败',
    '构建 chromium 浏览器组件需要访问 playwright 下载源，该地址不受构建参数'
    '控制。请检查 VPN / 代理后重试——此步之前的层都已缓存。',
  ),

  /// compose 工程定位失败。
  projectNotFound(
    '未找到 Compose 工程',
    '请先在设置中配置正确的 ARTEX 仓库目录。',
  ),

  /// 未分类失败：回退展示原始输出尾部。
  unknown('构建失败', '请查看下方构建日志定位原因。');

  const ArtexBuildFailureKind(this.label, this.hint);

  final String label;

  /// 给用户的可操作建议。
  final String hint;
}

/// 一次构建的结果。
class ArtexBuildResult {
  const ArtexBuildResult({
    required this.success,
    this.failureKind,
    this.logTail = const <String>[],
    this.duration = Duration.zero,
  });

  const ArtexBuildResult.succeeded(this.duration)
    : success = true,
      failureKind = null,
      logTail = const <String>[];

  const ArtexBuildResult.failed(
    ArtexBuildFailureKind kind,
    this.logTail,
    this.duration,
  ) : success = false,
      failureKind = kind;

  final bool success;
  final ArtexBuildFailureKind? failureKind;

  /// 原始输出尾部（未命中已知模式时靠它定位）。
  final List<String> logTail;

  final Duration duration;
}

/// 构建失败模式匹配表（design D4）。
///
/// 每条是一个「输出特征 → 失败类别」的映射。匹配大小写不敏感，
/// 因为不同 docker 版本的文案不完全一致。
class _BuildFailurePattern {
  const _BuildFailurePattern(this.needle, this.kind);

  final String needle;
  final ArtexBuildFailureKind kind;
}

const List<_BuildFailurePattern> _kFailurePatterns = [
  // playwright / chromium —— 必须排在宽泛的网络特征之前：
  // 'dial tcp' / 'no such host' 会抢先把它们判成普通网络超时，
  // 而 playwright.azureedge.net 与 deb.nodesource.com 不受三个
  // 构建参数控制，用户需要的动作不同（检查 VPN 而非换源）。
  _BuildFailurePattern('playwright install', ArtexBuildFailureKind.chromiumDownload),
  _BuildFailurePattern('azureedge', ArtexBuildFailureKind.chromiumDownload),
  _BuildFailurePattern('deb.nodesource.com', ArtexBuildFailureKind.chromiumDownload),
  // 环境变量
  _BuildFailurePattern('postgres_password', ArtexBuildFailureKind.missingEnv),
  _BuildFailurePattern('未提供 database', ArtexBuildFailureKind.missingEnv),
  // Docker 守护进程
  _BuildFailurePattern('cannot connect to the docker daemon', ArtexBuildFailureKind.dockerUnavailable),
  _BuildFailurePattern('docker.sock', ArtexBuildFailureKind.dockerUnavailable),
  _BuildFailurePattern('is the docker daemon running', ArtexBuildFailureKind.dockerUnavailable),
  // 镜像源 403
  _BuildFailurePattern('403 forbidden', ArtexBuildFailureKind.mirrorForbidden),
  _BuildFailurePattern('failed to solve: failed to resolve source metadata', ArtexBuildFailureKind.mirrorForbidden),
  _BuildFailurePattern('unexpected status from head request', ArtexBuildFailureKind.mirrorForbidden),
  // 网络超时
  _BuildFailurePattern('client.timeout exceeded', ArtexBuildFailureKind.networkTimeout),
  _BuildFailurePattern('request canceled', ArtexBuildFailureKind.networkTimeout),
  _BuildFailurePattern('context deadline exceeded', ArtexBuildFailureKind.networkTimeout),
  _BuildFailurePattern('i/o timeout', ArtexBuildFailureKind.networkTimeout),
  _BuildFailurePattern('dial tcp', ArtexBuildFailureKind.networkTimeout),
  _BuildFailurePattern('no such host', ArtexBuildFailureKind.networkTimeout),
];

/// 纯函数：按构建输出分类失败原因。单独抽出便于测试（task 6.6）。
@visibleForTesting
ArtexBuildFailureKind classifyBuildFailure(String output) {
  final lower = output.toLowerCase();
  for (final pattern in _kFailurePatterns) {
    if (lower.contains(pattern.needle)) return pattern.kind;
  }
  return ArtexBuildFailureKind.unknown;
}

/// 镜像构建服务（task 6）。
///
/// 把 `docker compose build` 包成一个可流式观察的操作，并对失败做模式识别
/// 而不是裸抛输出。构建参数可配——不同网络环境需要的源不同（design D4）。
class ArtexImageBuildService extends ChangeNotifier {
  ArtexImageBuildService({ProcessRunner? runner})
    : _runner = runner ?? const RealProcessRunner();

  final ProcessRunner _runner;

  static final ArtexImageBuildService _instance = ArtexImageBuildService();
  static ArtexImageBuildService get instance => _instance;

  bool _building = false;
  final List<String> _lines = <String>[];
  ArtexBuildResult? _lastResult;

  bool get isBuilding => _building;
  List<String> get lines => List.unmodifiable(_lines);
  ArtexBuildResult? get lastResult => _lastResult;

  /// 触发构建。
  ///
  /// [onLine] 在每条输出行上调用（UI 订阅做实时日志）。
  /// 构建期间重复触发直接返回上一次 Future，不并发跑两个 build
  /// （两个 `docker compose build` 会互相抢 buildkit 的锁）。
  Future<ArtexBuildResult> build({
    void Function(String line)? onLine,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _build(onLine);
    _inFlight = future;
    return future;
  }

  Future<ArtexBuildResult>? _inFlight;

  Future<ArtexBuildResult> _build(void Function(String line)? onLine) async {
    _building = true;
    _lines.clear();
    _lastResult = null;
    notifyListeners();

    void emit(String line) {
      _lines.add(line);
      // 只保留尾部，避免长时间构建把内存吃满。
      if (_lines.length > _kMaxBufferedLines) {
        _lines.removeAt(0);
      }
      onLine?.call(line);
      notifyListeners();
    }

    final startedAt = DateTime.now();

    try {
      final location = ArtexConfigStore.instance.locateProject();
      if (!location.ok) {
        return _finish(
          ArtexBuildResult.failed(
            ArtexBuildFailureKind.projectNotFound,
            <String>[location.reason ?? ''],
            DateTime.now().difference(startedAt),
          ),
        );
      }
      final projectDir = location.path!;

      final config = ArtexConfigStore.instance.config;

      // 三个上游构建参数（design D4）：不同网络环境需要的源不同。
      final environment = <String, String>{
        'NPM_REGISTRY': config.npmRegistry,
        'GOPROXY': config.goProxy,
        'APT_MIRROR': config.aptMirror,
      };

      final exitCode = await _runner.startStreaming(
        'docker',
        <String>[
          'compose',
          '-f',
          '$projectDir/docker-compose.yml',
          '-f',
          ArtexOverrideStore.instance.pathFor(projectDir),
          'build',
          '--build-arg',
          'NPM_REGISTRY=${config.npmRegistry}',
          '--build-arg',
          'GOPROXY=${config.goProxy}',
          '--build-arg',
          'APT_MIRROR=${config.aptMirror}',
        ],
        workingDirectory: projectDir,
        environment: environment,
        onLine: emit,
      );

      final duration = DateTime.now().difference(startedAt);
      if (exitCode == 0) {
        return _finish(ArtexBuildResult.succeeded(duration));
      }
      return _finish(
        ArtexBuildResult.failed(
          classifyBuildFailure(_lines.join('\n')),
          List.of(_lines),
          duration,
        ),
      );
    } catch (e) {
      return _finish(
        ArtexBuildResult.failed(
          ArtexBuildFailureKind.unknown,
          <String>['$e'],
          DateTime.now().difference(startedAt),
        ),
      );
    }
  }

  ArtexBuildResult _finish(ArtexBuildResult result) {
    _lastResult = result;
    _building = false;
    _inFlight = null;
    notifyListeners();
    return result;
  }

  /// 清空日志（重新构建前 UI 调用）。
  void clear() {
    if (_building) return;
    _lines.clear();
    _lastResult = null;
    notifyListeners();
  }
}

/// 构建日志的最大缓冲行数。
const int _kMaxBufferedLines = 2000;
