import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/infinite_canvas_state.dart';
import 'infinite_canvas_config_store.dart';
import 'infinite_canvas_override_store.dart';
import 'process_runner.dart';

/// 构建失败模式匹配表（spec: 镜像入口与失败诊断）。
///
/// 每条是一个「输出特征 → 失败类别」的映射。匹配大小写不敏感，因为不同
/// docker 版本的文案不完全一致。
///
/// **顺序即优先级**：具体的特征必须排在宽泛的网络特征之前。`tls handshake
/// timeout` 与 `dial tcp` 会把一切网络问题都判成普通超时，而「镜像源不可达」
/// 的用户动作不同（改 Docker 的镜像源配置，而不是开 VPN）。
///
/// 与 Toonflow 版的差异：删掉了 bun 锁文件条目（上游 Dockerfile 用 bun，
/// 而本地构建只是可选路径），新增「构建上下文缺失」。
class _BuildFailurePattern {
  const _BuildFailurePattern(this.needle, this.kind);

  final String needle;
  final InfiniteCanvasBuildFailureKind kind;
}

const List<_BuildFailurePattern> _kFailurePatterns = [
  // 镜像源问题 —— 必须排在宽泛网络特征之前。
  _BuildFailurePattern(
    'failed to resolve source metadata',
    InfiniteCanvasBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    'unexpected status from head request',
    InfiniteCanvasBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    '403 forbidden',
    InfiniteCanvasBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    'toomanyrequests',
    InfiniteCanvasBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    'pull access denied',
    InfiniteCanvasBuildFailureKind.registryBlocked,
  ),
  // 构建上下文缺失：本地没有 web/ 时 COPY 会失败。
  _BuildFailurePattern(
    'not found: not found',
    InfiniteCanvasBuildFailureKind.missingContext,
  ),
  _BuildFailurePattern(
    'copy failed',
    InfiniteCanvasBuildFailureKind.missingContext,
  ),
  _BuildFailurePattern(
    'failed to compute cache key',
    InfiniteCanvasBuildFailureKind.missingContext,
  ),
  // Docker 守护进程
  _BuildFailurePattern(
    'cannot connect to the docker daemon',
    InfiniteCanvasBuildFailureKind.dockerUnavailable,
  ),
  _BuildFailurePattern(
    'is the docker daemon running',
    InfiniteCanvasBuildFailureKind.dockerUnavailable,
  ),
  _BuildFailurePattern(
    'docker.sock',
    InfiniteCanvasBuildFailureKind.dockerUnavailable,
  ),
  // 网络超时（放最后，作为宽泛兜底）
  _BuildFailurePattern(
    'tls handshake timeout',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'client.timeout exceeded',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'context deadline exceeded',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'request canceled',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'i/o timeout',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'dial tcp',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'no such host',
    InfiniteCanvasBuildFailureKind.networkTimeout,
  ),
];

/// 纯函数：按构建输出分类失败原因。单独抽出便于测试（spec: 镜像入口与
/// 失败诊断）。
@visibleForTesting
InfiniteCanvasBuildFailureKind classifyBuildFailure(String output) {
  final lower = output.toLowerCase();
  for (final pattern in _kFailurePatterns) {
    if (lower.contains(pattern.needle)) return pattern.kind;
  }
  return InfiniteCanvasBuildFailureKind.unknown;
}

/// 一次构建的结果。
class InfiniteCanvasBuildResult {
  const InfiniteCanvasBuildResult({
    required this.success,
    this.failureKind,
    this.logTail = const <String>[],
    this.duration = Duration.zero,
  });

  const InfiniteCanvasBuildResult.succeeded(this.duration)
    : success = true,
      failureKind = null,
      logTail = const <String>[];

  const InfiniteCanvasBuildResult.failed(
    InfiniteCanvasBuildFailureKind kind,
    this.logTail,
    this.duration,
  ) : success = false,
      failureKind = kind;

  final bool success;
  final InfiniteCanvasBuildFailureKind? failureKind;
  final List<String> logTail;
  final Duration duration;
}

/// 镜像构建服务（spec: 镜像入口与失败诊断）。
///
/// 把 `docker compose build` 包成一个可流式观察的操作，并对失败做模式识别
/// 而不是裸抛输出。
///
/// **默认路径不经过这里**：上游 `docker-compose.yml` 引用 ghcr.io 上已发布
/// 的双架构镜像，`up -d` 时 compose 自己会拉。本服务只在用户要跑自己改过的
/// 代码时才需要。
///
/// 构建期间重复触发直接返回同一次 Future，不并发跑两个 build——两个
/// `docker compose build` 会互相抢 buildkit 的锁。
class InfiniteCanvasImageBuildService extends ChangeNotifier {
  InfiniteCanvasImageBuildService({ProcessRunner? runner})
    : _runner = runner ?? const InfiniteCanvasRealProcessRunner();

  final ProcessRunner _runner;

  static final InfiniteCanvasImageBuildService _instance =
      InfiniteCanvasImageBuildService();
  static InfiniteCanvasImageBuildService get instance => _instance;

  bool _building = false;
  final List<String> _lines = <String>[];
  InfiniteCanvasBuildResult? _lastResult;

  bool get isBuilding => _building;
  List<String> get lines => List.unmodifiable(_lines);
  InfiniteCanvasBuildResult? get lastResult => _lastResult;

  /// 触发构建。
  ///
  /// [onLine] 在每条输出行上调用（UI 订阅做实时日志）。
  Future<InfiniteCanvasBuildResult> build({
    void Function(String line)? onLine,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _build(onLine);
    _inFlight = future;
    return future;
  }

  Future<InfiniteCanvasBuildResult>? _inFlight;

  Future<InfiniteCanvasBuildResult> _build(void Function(String line)? onLine) async {
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
      final location = InfiniteCanvasConfigStore.instance.locateProject();
      if (!location.ok) {
        return _finish(
          InfiniteCanvasBuildResult.failed(
            InfiniteCanvasBuildFailureKind.projectNotFound,
            <String>[location.reason ?? ''],
            DateTime.now().difference(startedAt),
          ),
        );
      }
      final projectDir = location.path!;
      final composeFile = location.composeFile!;

      final override = InfiniteCanvasOverrideStore.instance.pathFor(projectDir);
      final exitCode = await _runner.startStreaming(
        'docker',
        <String>[
          'compose',
          '-f',
          '$projectDir/$composeFile',
          '-f',
          override,
          'build',
        ],
        workingDirectory: projectDir,
        onLine: emit,
      );

      final duration = DateTime.now().difference(startedAt);
      if (exitCode == 0) {
        return _finish(InfiniteCanvasBuildResult.succeeded(duration));
      }
      return _finish(
        InfiniteCanvasBuildResult.failed(
          classifyBuildFailure(_lines.join('\n')),
          List.of(_lines),
          duration,
        ),
      );
    } catch (e) {
      return _finish(
        InfiniteCanvasBuildResult.failed(
          InfiniteCanvasBuildFailureKind.unknown,
          <String>['$e'],
          DateTime.now().difference(startedAt),
        ),
      );
    }
  }

  InfiniteCanvasBuildResult _finish(InfiniteCanvasBuildResult result) {
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
