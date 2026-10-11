import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/toonflow_studio_state.dart';
import 'process_runner.dart';
import 'toonflow_config_store.dart';
import 'toonflow_override_store.dart';

/// 构建失败模式匹配表（spec: 镜像构建入口与失败诊断）。
///
/// 每条是一个「输出特征 → 失败类别」的映射。匹配大小写不敏感，因为不同
/// docker 版本的文案不完全一致。
///
/// **顺序即优先级**：具体的特征必须排在宽泛的网络特征之前。`tls handshake
/// timeout` 与 `dial tcp` 会把一切网络问题都判成普通超时，而「镜像源不可达」
/// 的用户动作不同（改 Docker 镜像源配置，而不是开 VPN）。
class _BuildFailurePattern {
  const _BuildFailurePattern(this.needle, this.kind);

  final String needle;
  final ToonflowBuildFailureKind kind;
}

const List<_BuildFailurePattern> _kFailurePatterns = [
  // 镜像源问题 —— 必须排在宽泛网络特征之前。
  // spike 实测：Docker Hub 在本机 TLS 握手超时，配置国内 mirror 后解决。
  _BuildFailurePattern(
    'failed to resolve source metadata',
    ToonflowBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    'unexpected status from head request',
    ToonflowBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    '403 forbidden',
    ToonflowBuildFailureKind.registryBlocked,
  ),
  _BuildFailurePattern(
    'toomanyrequests',
    ToonflowBuildFailureKind.registryBlocked,
  ),
  // bun 锁文件不匹配。上游 Dockerfile 用 `bun install --frozen-lockfile`，
  // lock 与 package.json 不同步时它直接失败。
  _BuildFailurePattern(
    'frozen-lockfile',
    ToonflowBuildFailureKind.lockfileMismatch,
  ),
  _BuildFailurePattern(
    'lockfile had changes',
    ToonflowBuildFailureKind.lockfileMismatch,
  ),
  // Docker 守护进程
  _BuildFailurePattern(
    'cannot connect to the docker daemon',
    ToonflowBuildFailureKind.dockerUnavailable,
  ),
  _BuildFailurePattern(
    'is the docker daemon running',
    ToonflowBuildFailureKind.dockerUnavailable,
  ),
  _BuildFailurePattern(
    'docker.sock',
    ToonflowBuildFailureKind.dockerUnavailable,
  ),
  // 网络超时（放最后，作为宽泛兜底）
  _BuildFailurePattern(
    'tls handshake timeout',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'client.timeout exceeded',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'context deadline exceeded',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'request canceled',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'i/o timeout',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'dial tcp',
    ToonflowBuildFailureKind.networkTimeout,
  ),
  _BuildFailurePattern(
    'no such host',
    ToonflowBuildFailureKind.networkTimeout,
  ),
];

/// 纯函数：按构建输出分类失败原因。单独抽出便于测试（spec: 镜像构建入口与
/// 失败诊断）。
@visibleForTesting
ToonflowBuildFailureKind classifyBuildFailure(String output) {
  final lower = output.toLowerCase();
  for (final pattern in _kFailurePatterns) {
    if (lower.contains(pattern.needle)) return pattern.kind;
  }
  return ToonflowBuildFailureKind.unknown;
}

/// 一次构建的结果。
class ToonflowBuildResult {
  const ToonflowBuildResult({
    required this.success,
    this.failureKind,
    this.logTail = const <String>[],
    this.duration = Duration.zero,
  });

  const ToonflowBuildResult.succeeded(this.duration)
    : success = true,
      failureKind = null,
      logTail = const <String>[];

  const ToonflowBuildResult.failed(
    ToonflowBuildFailureKind kind,
    this.logTail,
    this.duration,
  ) : success = false,
      failureKind = kind;

  final bool success;
  final ToonflowBuildFailureKind? failureKind;
  final List<String> logTail;
  final Duration duration;
}

/// 镜像构建服务（spec: 镜像构建入口与失败诊断）。
///
/// 把 `docker compose build` 包成一个可流式观察的操作，并对失败做模式识别
/// 而不是裸抛输出。
///
/// 构建期间重复触发直接返回同一次 Future，不并发跑两个 build——两个
/// `docker compose build` 会互相抢 buildkit 的锁。
class ToonflowImageBuildService extends ChangeNotifier {
  ToonflowImageBuildService({ProcessRunner? runner})
    : _runner = runner ?? const ToonflowRealProcessRunner();

  final ProcessRunner _runner;

  static final ToonflowImageBuildService _instance =
      ToonflowImageBuildService();
  static ToonflowImageBuildService get instance => _instance;

  bool _building = false;
  final List<String> _lines = <String>[];
  ToonflowBuildResult? _lastResult;

  bool get isBuilding => _building;
  List<String> get lines => List.unmodifiable(_lines);
  ToonflowBuildResult? get lastResult => _lastResult;

  /// 触发构建。
  ///
  /// [onLine] 在每条输出行上调用（UI 订阅做实时日志）。
  Future<ToonflowBuildResult> build({
    void Function(String line)? onLine,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _build(onLine);
    _inFlight = future;
    return future;
  }

  Future<ToonflowBuildResult>? _inFlight;

  Future<ToonflowBuildResult> _build(void Function(String line)? onLine) async {
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
      final location = ToonflowConfigStore.instance.locateProject();
      if (!location.ok) {
        return _finish(
          ToonflowBuildResult.failed(
            ToonflowBuildFailureKind.projectNotFound,
            <String>[location.reason ?? ''],
            DateTime.now().difference(startedAt),
          ),
        );
      }
      final projectDir = location.path!;
      final config = ToonflowConfigStore.instance.config;

      final override = ToonflowOverrideStore.instance.pathFor(projectDir);
      final exitCode = await _runner.startStreaming(
        'docker',
        <String>[
          'compose',
          '-f',
          '$projectDir/compose.yaml',
          '-f',
          override,
          'build',
        ],
        workingDirectory: projectDir,
        // bun 镜像站：Docker Hub 与 npm 在国内都需要走镜像（spike 实测）。
        environment: <String, String>{
          'BUN_CONFIG_REGISTRY': config.bunRegistry,
        },
        onLine: emit,
      );

      final duration = DateTime.now().difference(startedAt);
      if (exitCode == 0) {
        return _finish(ToonflowBuildResult.succeeded(duration));
      }
      return _finish(
        ToonflowBuildResult.failed(
          classifyBuildFailure(_lines.join('\n')),
          List.of(_lines),
          duration,
        ),
      );
    } catch (e) {
      return _finish(
        ToonflowBuildResult.failed(
          ToonflowBuildFailureKind.unknown,
          <String>['$e'],
          DateTime.now().difference(startedAt),
        ),
      );
    }
  }

  ToonflowBuildResult _finish(ToonflowBuildResult result) {
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
