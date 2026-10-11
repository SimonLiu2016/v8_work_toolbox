import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/toonflow_studio_config.dart';
import '../models/toonflow_studio_state.dart';
import 'process_runner.dart';
import 'toonflow_config_store.dart';
import 'toonflow_override_store.dart';

/// 健康探测的总预算与间隔。
///
/// spike 实测容器 4 秒内就绪（`/api/workspaces/list` 立即可用）。首次启动要
/// 做插件初始化，给 60 秒总预算更稳。
const Duration kHealthTotalBudget = Duration(seconds: 60);
const Duration kHealthPollInterval = Duration(seconds: 1);

/// 单次探测的超时。容器刚拉起时连接会被拒，这个超时只覆盖"连上但不回"。
const Duration kHealthProbeTimeout = Duration(seconds: 3);

/// 健康探测判定结果。
enum HealthVerdict { ready, pending }

/// 就绪判定要求的字段。
///
/// Toonflow 业务 API 与静态资源由同一进程服务：API 没就绪时任意路径也会
/// 返回 200 的 HTML（SPA 的 index.html）。只看状态码会把「服务未就绪」误判
/// 成「已就绪」，把用户送到一个打不开的工作台——所以必须校验响应体是业务
/// 接口的 JSON 信封（spec: 健康就绪判定必须校验响应体）。
const String kHealthCodeField = 'code';

/// 探测用的业务端点。无鉴权、无参数、 cheapest（spec: 健康就绪判定）。
const String kHealthPath = '/api/workspaces/list';

/// Toonflow 容器生命周期服务。
///
/// **本服务不实现任何 Toonflow 能力**，只负责：
/// - 守护进程探活
/// - 启动前端口预检
/// - 生成 override 并 `up -d`，然后等健康探测通过
/// - 就绪超时时附容器日志
/// - `stop` 与退出时按配置处置
///
/// 进程执行走可注入的 [ProcessRunner]，使上述行为可在测试中驱动。
class ToonflowComposeService extends ChangeNotifier {
  ToonflowComposeService._(this._runner, [this._httpClient]);

  /// 生产单例。
  static final ToonflowComposeService instance = ToonflowComposeService._(
    const ToonflowRealProcessRunner(),
    http.Client(),
  );

  /// 测试用实例：注入假进程执行器，并共用同一个配置存储。
  ///
  /// 不复用单例是为了让每个测试从干净状态开始（`_state` / `_starting` 是
  /// 进程级可变状态）。
  @visibleForTesting
  factory ToonflowComposeService.forTesting(
    ProcessRunner runner, [
    http.Client? httpClient,
  ]) = ToonflowComposeService._;

  final ProcessRunner _runner;

  /// 生产用真实客户端；测试经 `debugHealthResponseOverride` 绕过 HTTP，
  /// 所以这个字段在测试里可以传 null。
  final http.Client? _httpClient;

  ToonflowStudioState _state = const ToonflowStudioState.initial();
  bool _starting = false;
  bool _stopping = false;

  ToonflowStudioState get state => _state;

  ToonflowStudioConfig get _config => ToonflowConfigStore.instance.config;

  /// 测试用：压缩健康预算，避免每个用例等 60 秒。
  @visibleForTesting
  Duration debugHealthBudgetOverride = kHealthTotalBudget;

  /// 测试用：注入健康响应体，绕过真实 HTTP。
  @visibleForTesting
  Future<String> Function()? debugHealthResponseOverride;

  void _emit(ToonflowStudioState next) {
    _state = next;
    notifyListeners();
  }

  void _fail(
    ToonflowFailureKind kind,
    String summary,
    String detail, {
    List<String> logTail = const <String>[],
  }) {
    _starting = false;
    _stopping = false;
    _emit(
      _state.copyWith(
        status: ToonflowStatus.failed,
        failureKind: kind,
        failure: summary,
        failureDetail: detail,
        containerLogTail: logTail,
      ),
    );
  }

  /// compose 命令的统一入口：始终带上 override。
  List<String> _composeArgs(String projectDir, String sub, List<String> rest) => [
    'compose',
    '-f',
    '$projectDir/compose.yaml',
    '-f',
    ToonflowOverrideStore.instance.pathFor(projectDir),
    sub,
    ...rest,
  ];

  // -------------------------------------------------------------------------
  // 守护进程探活
  // -------------------------------------------------------------------------

  /// Docker 守护进程是否可达。
  Future<bool> isDockerAvailable() async {
    try {
      final result = await _runner.run('docker', ['info']);
      return result.success;
    } catch (e) {
      debugPrint('[ToonflowComposeService] docker info 异常: $e');
      return false;
    }
  }

  /// 端口预检。
  ///
  /// 在 `up -d` **之前**做：compose 的绑定失败会留下半启动状态（容器已建、
  /// 网络已配），且错误信息是 `Bind for 0.0.0.0:3000 failed: port is already
  /// allocated` 这种难读形式。
  Future<int?> findConflictingPort(List<int> ports) async {
    for (final port in ports) {
      try {
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
        await socket.close();
      } on SocketException {
        return port;
      } catch (e) {
        debugPrint('[ToonflowComposeService] 端口探测异常 ($port): $e');
        return port;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // 启动与健康探测
  // -------------------------------------------------------------------------

  /// 启动 Toonflow。
  ///
  /// 顺序：工程目录校验 → 守护进程探活 → 端口预检 → 生成 override →
  /// `up -d` → 健康探测。任一步失败都留下可读原因。
  Future<void> start() async {
    if (_starting || _state.status == ToonflowStatus.running) return;
    _starting = true;
    _emit(
      _state.copyWith(
        status: ToonflowStatus.starting,
        clearFailure: true,
        containerLogTail: const <String>[],
      ),
    );

    final config = _config;

    // 1. 工程目录定位
    final location = ToonflowConfigStore.instance.locateProject(config.projectDir);
    if (!location.ok) {
      _fail(
        ToonflowFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }
    final projectDir = location.path!;

    // 2. 守护进程探活
    if (!await isDockerAvailable()) {
      _fail(
        ToonflowFailureKind.dockerUnavailable,
        'Docker 未运行',
        '无法连接 Docker 守护进程。若刚启动 Docker Desktop，请等待其完全就绪后重试。',
      );
      return;
    }

    // 3. 端口预检
    final conflict = await findConflictingPort([config.httpPort]);
    if (conflict != null) {
      _fail(
        ToonflowFailureKind.portConflict,
        '端口 $conflict 被占用',
        '宿主机端口 $conflict 已被其他进程监听。请在设置中修改端口后重试。',
      );
      return;
    }

    // 4. 生成 override（端口 + bind mount + user 对齐）
    try {
      final ids = await _resolveUidGid();
      ToonflowOverrideStore.instance.write(
        projectDir,
        config,
        uid: ids.$1,
        gid: ids.$2,
      );
    } catch (e) {
      _fail(
        ToonflowFailureKind.composeFailed,
        '生成 override 失败',
        '$e',
      );
      return;
    }

    // 5. 拉起容器
    final up = await _runner
        .run('docker', _composeArgs(projectDir, 'up', ['-d']))
        .catchError((Object e) {
          debugPrint('[ToonflowComposeService] up -d 异常: $e');
          return ToonflowProcessResult(exitCode: -1, stdout: '', stderr: '$e');
        });
    if (!up.success) {
      _classifyComposeFailure(up.combined, projectDir);
      return;
    }

    // 6. 健康探测
    final verdict = await _waitUntilHealthy(config.httpPort);
    if (verdict == HealthVerdict.ready) {
      _starting = false;
      _emit(_state.copyWith(status: ToonflowStatus.running));
      return;
    }

    final logs = await _containerLogTail(projectDir);
    _fail(
      ToonflowFailureKind.healthTimeout,
      '服务未就绪',
      '在 ${kHealthTotalBudget.inSeconds} 秒内未收到预期的健康响应。',
      logTail: logs,
    );
  }

  /// 把 `up -d` 的失败归类。
  ///
  /// 「镜像不存在」单独一类：它的用户动作是「去点构建」，而不是重试启动。
  ///
  /// 「服务名找不到」单独一类：上游 `compose.yaml` 把服务从 `toonflow` 改名时
  /// override 会静默失效（compose 不会因为 override 引用了个不存在的服务而
  /// 报错，`up` 时才发现）。这时让用户去重试没有意义，必须告诉他去核对服务名
  /// （design Risk：上游仓库升级导致 compose 结构变化）。
  void _classifyComposeFailure(String combined, String projectDir) {
    final lower = combined.toLowerCase();
    if (lower.contains('no such image') ||
        lower.contains('image.*not found') ||
        lower.contains('unable to find image')) {
      _fail(
        ToonflowFailureKind.buildRequired,
        '镜像未构建',
        'Toonflow 镜像不存在，请先点击「构建镜像」。首次构建可能需要 10–20 分钟。',
      );
      return;
    }
    if (lower.contains('cannot connect to the docker daemon')) {
      _fail(
        ToonflowFailureKind.dockerUnavailable,
        'Docker 未运行',
        '无法连接 Docker 守护进程。',
      );
      return;
    }
    if (lower.contains('no such service') ||
        RegExp(r'service .* not found').hasMatch(lower)) {
      _fail(
        ToonflowFailureKind.composeFailed,
        'Compose 服务名不匹配',
        '上游 compose.yaml 里找不到本工具使用的服务名「toonflow」。'
        'Toonflow 仓库可能已升级并改了服务名——请打开 '
        '$projectDir/compose.yaml 核对 services 下的名字，'
        '并同步修正本工具生成的 docker-compose.override.yml。',
      );
      return;
    }
    _fail(
      ToonflowFailureKind.composeFailed,
      '容器启动失败',
      combined.trim(),
      logTail: _tailLines(combined),
    );
  }

  /// 轮询直到就绪、超时。
  Future<HealthVerdict> _waitUntilHealthy(int port) async {
    final deadline = DateTime.now().add(debugHealthBudgetOverride);
    while (DateTime.now().isBefore(deadline)) {
      final verdict = await _probeOnce(port, _httpClient);
      if (verdict == HealthVerdict.ready) return HealthVerdict.ready;
      await Future.delayed(kHealthPollInterval);
    }
    return HealthVerdict.pending;
  }

  /// 单次探测。
  ///
  /// [client] 为 null 时只走 `debugHealthResponseOverride` 分支——测试不需要
  /// 真实 HTTP，生产单例总会传客户端。
  Future<HealthVerdict> _probeOnce(int port, http.Client? client) async {
    final override = debugHealthResponseOverride;
    if (override != null) {
      // override 的类型是 `Future<String> Function()?`，所以 body 非空——
      // 不需要像 artex 那样再判一次 null。
      final body = await override();
      return classifyHealthBody(body);
    }
    if (client == null) return HealthVerdict.pending;
    try {
      final response = await client
          .get(Uri.parse('http://127.0.0.1:$port$kHealthPath'))
          .timeout(kHealthProbeTimeout);
      if (response.statusCode != 200) return HealthVerdict.pending;
      return classifyHealthBody(response.body);
    } on TimeoutException {
      return HealthVerdict.pending;
    } catch (e) {
      // 连接拒绝等：容器还没起来。
      return HealthVerdict.pending;
    }
  }

  /// 按响应体分类（静态，便于测试直接调用）。
  ///
  /// - 可解析 JSON 且含 `code` 字段 → 业务接口真身
  /// - HTML → 未就绪（API 没起来，静态服务返回了 SPA 的 index.html）
  /// - 其他 → 未就绪
  static HealthVerdict classifyHealthBody(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<')) return HealthVerdict.pending;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded.containsKey(kHealthCodeField)) {
        return HealthVerdict.ready;
      }
    } catch (_) {
      // 不是 JSON。
    }
    return HealthVerdict.pending;
  }

  /// 取容器日志尾部（启动失败时附上）。
  Future<List<String>> _containerLogTail(String projectDir) async {
    try {
      final result = await _runner.run(
        'docker',
        _composeArgs(projectDir, 'logs', ['--tail', '30']),
      );
      return _tailLines(result.combined, 15);
    } catch (e) {
      debugPrint('[ToonflowComposeService] 取日志异常: $e');
      return const <String>[];
    }
  }

  // -------------------------------------------------------------------------
  // 停止与退出
  // -------------------------------------------------------------------------

  /// 停止容器组。
  ///
  /// 失败必须上报而不是假装已停止（spec: 容器启停与状态呈现的停止场景）。
  Future<void> stop() async {
    if (_stopping || _state.status == ToonflowStatus.stopped) return;
    _stopping = true;
    _emit(_state.copyWith(status: ToonflowStatus.stopping, clearFailure: true));

    final location = ToonflowConfigStore.instance.locateProject();
    if (!location.ok) {
      _fail(
        ToonflowFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }

    final down = await _runner
        .run('docker', _composeArgs(location.path!, 'down', []))
        .catchError((Object e) {
          debugPrint('[ToonflowComposeService] down 异常: $e');
          return ToonflowProcessResult(exitCode: -1, stdout: '', stderr: '$e');
        });
    _stopping = false;
    if (!down.success) {
      _fail(
        ToonflowFailureKind.composeFailed,
        '容器停止失败',
        down.combined.trim(),
      );
      return;
    }
    _emit(_state.copyWith(status: ToonflowStatus.stopped));
  }

  /// 按配置在应用退出时处置容器。
  ///
  /// 抛异常时仍必须让调用方继续退出——卡在清理上比放弃清理更糟。
  Future<void> disposeOnExit() async {
    if (!_config.stopOnAppExit) return;
    if (_state.status != ToonflowStatus.running &&
        _state.status != ToonflowStatus.starting) {
      return;
    }
    try {
      await stop();
    } catch (e) {
      debugPrint('[ToonflowComposeService] 退出时停止容器失败: $e');
    }
  }

  /// 解析宿主机当前用户的 uid/gid（override 的 `user:` 用）。
  ///
  /// 取不到时回退 501:20（macOS 首个真实用户的常见值）而不是让启动失败——
  /// 用户对齐缺失只会让容器内进程以 `bun` 身份写文件，Docker Desktop 的
  /// VirtioFS 仍然放行（spike 实测）。
  Future<(String, String)> _resolveUidGid() async {
    try {
      final uid = await _runner.run('id', ['-u']);
      final gid = await _runner.run('id', ['-g']);
      if (uid.success && gid.success) {
        final u = uid.stdout.trim();
        final g = gid.stdout.trim();
        if (u.isNotEmpty && g.isNotEmpty) return (u, g);
      }
    } catch (e) {
      debugPrint('[ToonflowComposeService] 取 uid/gid 失败: $e');
    }
    return ('501', '20');
  }

  List<String> _tailLines(String text, [int count = 20]) {
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length <= count) return lines;
    return lines.sublist(lines.length - count);
  }
}
