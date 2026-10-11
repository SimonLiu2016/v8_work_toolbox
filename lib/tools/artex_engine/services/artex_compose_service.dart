import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/artex_engine_config.dart';
import '../models/artex_engine_state.dart';
import 'artex_config_store.dart';
import 'artex_override_store.dart';
import 'process_runner.dart';

/// 健康探测的总预算与间隔（task 5.4）。
///
/// spike 实测容器起来后 2 秒内就绪，但首次运行要做 PostgreSQL schema
/// 初始化（49 张表），所以给 60 秒总预算更稳。
const Duration kHealthTotalBudget = Duration(seconds: 60);
const Duration kHealthPollInterval = Duration(seconds: 1);

/// 健康探测判定结果。
enum HealthVerdict { ready, pending, gateBlocked }

/// 就绪判定要求的字段（design D2）。
///
/// `/api/health` 在 `server/auth.go:147` 的 `requireAuth` 中显式豁免，
/// 无 token 可探测；返回形如 `{"ok":true,"service":"artex","version":"dev"}`。
const String kHealthServiceField = 'service';

/// ARTEX 引擎容器生命周期服务。
///
/// **本服务不实现任何渗透能力**，只负责：
/// - 守护进程探活（5.2）
/// - 启动前端口预检（5.3）
/// - 生成 override 并 `up -d`，然后等健康探测通过（5.4）
/// - 就绪超时时附容器日志与门控定向提示（5.5）
/// - `stop`（5.6）
/// - 退出时按配置处置（5.7）
///
/// 进程执行走可注入的 [ProcessRunner]，使上述行为可在测试中驱动（5.9）。
class ArtexComposeService extends ChangeNotifier {
  ArtexComposeService._(this._runner);

  /// 生产单例。
  static final ArtexComposeService instance = ArtexComposeService._(
    const RealProcessRunner(),
  );

  /// 测试用实例：注入假进程执行器，并共用同一个配置存储。
  ///
  /// 不复用单例是为了让每个测试从干净状态开始（`_state` / `_starting` 是
  /// 进程级可变状态）。
  @visibleForTesting
  factory ArtexComposeService.forTesting(ProcessRunner runner) =
      ArtexComposeService._;

  final ProcessRunner _runner;

  ArtexEngineState _state = const ArtexEngineState.initial();

  /// 当前状态快照。
  ArtexEngineState get state => _state;

  /// 端口预检与健康探测的 HTTP 客户端。
  ///
  /// 用短超时：探测失败要快速重试，60 秒预算不能被单次慢请求吃掉。
  final http.Client _httpClient = http.Client();

  bool _starting = false;

  /// 测试用：压缩健康探测预算，避免每个超时用例跑满 60 秒真实时间。
  @visibleForTesting
  Duration debugHealthBudgetOverride = kHealthTotalBudget;


  // -------------------------------------------------------------------------
  // 测试注入点
  // -------------------------------------------------------------------------

  /// 测试用：直接分类健康响应体。
  @visibleForTesting
  HealthVerdict debugClassifyHealthBody(String body) =>
      _classifyHealthBody(body);

  /// 测试用：替换真实 HTTP 探测。
  ///
  /// 返回 null 表示「走真实 _probeOnce」（本组测试不覆盖该路径，因为
  /// 真发 HTTP 会让测试依赖本机是否起了容器）。
  @visibleForTesting
  Future<String?> Function()? debugHealthResponseOverride;

  /// 测试用：查看 compose 参数构造。
  @visibleForTesting
  List<String> debugComposeArgs(String dir, String sub, List<String> rest) =>
      _composeArgs(dir, sub, rest);

  // -------------------------------------------------------------------------
  // 内部工具
  // -------------------------------------------------------------------------

  ArtexEngineConfig get _config => ArtexConfigStore.instance.config;

  void _emit(ArtexEngineState next) {
    _state = next;
    notifyListeners();
  }

  /// compose 命令的统一入口：始终带上 override（design D1）。
  List<String> _composeArgs(String projectDir, String sub, List<String> rest) => [
    'compose',
    '-f',
    '$projectDir/docker-compose.yml',
    '-f',
    ArtexOverrideStore.instance.pathFor(projectDir),
    sub,
    ...rest,
  ];

  void _fail(
    ArtexEngineFailureKind kind,
    String summary,
    String detail, {
    List<String> logTail = const <String>[],
  }) {
    _starting = false;
    _emit(
      _state.copyWith(
        status: ArtexEngineStatus.failed,
        failureKind: kind,
        failure: summary,
        failureDetail: detail,
        containerLogTail: logTail,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 5.2 守护进程探活
  // -------------------------------------------------------------------------

  /// Docker 守护进程是否可达。
  Future<bool> isDockerAvailable() async {
    try {
      final result = await _runner.run('docker', ['info']);
      return result.success;
    } catch (e) {
      debugPrint('[ArtexComposeService] docker info 异常: $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 5.3 端口预检
  // -------------------------------------------------------------------------

  /// 返回第一个被占用的端口；都空闲返回 null。
  ///
  /// 用 `ServerSocket.bind` 试探后立即关闭。**为什么在启动前做**而不是让
  /// compose 失败后再解析（design D3）：compose 失败会留下半启动状态
  /// （postgres 已起、artex 失败），且错误信息是
  /// `Bind for 0.0.0.0:8787 failed: port is already allocated` 这种难读形式。
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
        debugPrint('[ArtexComposeService] 端口探测异常 ($port): $e');
        return port;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // 5.4 / 5.5 启动与健康探测
  // -------------------------------------------------------------------------

  /// 启动引擎。
  ///
  /// 顺序：工程目录校验 → 守护进程探活 → 端口预检 → 生成 override →
  /// `up -d` → 健康探测。任一步失败都留下可读原因（spec「容器启停与状态呈现」）。
  Future<void> start() async {
    if (_starting || _state.status == ArtexEngineStatus.running) return;
    _starting = true;
    _emit(
      _state.copyWith(
        status: ArtexEngineStatus.starting,
        failureKind: null,
        failure: null,
        failureDetail: null,
        containerLogTail: const <String>[],
      ),
    );

    final config = _config;

    // 工程目录定位
    final location = ArtexConfigStore.instance.locateProject(config.projectDir);
    if (!location.ok) {
      _fail(
        ArtexEngineFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }
    final projectDir = location.path!;

    // 守护进程探活
    if (!await isDockerAvailable()) {
      _fail(
        ArtexEngineFailureKind.dockerUnavailable,
        'Docker 未运行',
        '无法连接 Docker 守护进程。若刚启动 Docker Desktop，请等待其完全就绪后重试。',
      );
      return;
    }

    // 端口预检
    final conflict = await findConflictingPort([config.httpPort, config.proxyPort]);
    if (conflict != null) {
      _fail(
        ArtexEngineFailureKind.portConflict,
        '端口 $conflict 被占用',
        '宿主机端口 $conflict 已被其他进程监听。请在设置中修改端口后重试。',
      );
      return;
    }

    // 生成 override（门控 + 端口）
    try {
      ArtexOverrideStore.instance.write(projectDir, config);
    } catch (e) {
      _fail(
        ArtexEngineFailureKind.composeFailed,
        '生成 override 失败',
        '$e',
      );
      return;
    }

    // 拉起容器
    final up = await _runner
        .run('docker', _composeArgs(projectDir, 'up', ['-d']))
        .catchError((Object e) {
          debugPrint('[ArtexComposeService] up -d 异常: $e');
          return ArtexProcessResult(exitCode: -1, stdout: '', stderr: '$e');
        });
    if (!up.success) {
      _fail(
        ArtexEngineFailureKind.composeFailed,
        '容器启动失败',
        up.combined.trim(),
        logTail: _tailLines(up.combined),
      );
      return;
    }

    // 健康探测
    final health = await _waitUntilHealthy(config.httpPort);
    if (health == HealthVerdict.ready) {
      _starting = false;
      _emit(_state.copyWith(status: ArtexEngineStatus.running));
      return;
    }

    // 超时：附容器日志；若抓到门控特征则给定向提示（design D2 的缓解）
    final logs = await _containerLogTail(projectDir);
    if (health == HealthVerdict.gateBlocked) {
      _fail(
        ArtexEngineFailureKind.gateBlocked,
        '引擎被伪装门控拦截',
        '健康接口返回了门控的固定欢迎页。请检查 override 中 ARTEX_GATE 是否为 off。',
        logTail: logs,
      );
      return;
    }
    _fail(
      ArtexEngineFailureKind.healthTimeout,
      '引擎未就绪',
      '在 ${kHealthTotalBudget.inSeconds} 秒内未收到预期的健康响应。',
      logTail: logs,
    );
  }

  /// 轮询直到就绪、超时或抓到门控特征。
  ///
  /// **判定必须校验响应体**（spec「健康就绪判定必须校验响应体」）：门控开启
  /// 时返回的是逐字节固定的假 nginx 欢迎页，状态码 200。只看状态码会把
  /// 用户送到一个假页面前。
  Future<HealthVerdict> _waitUntilHealthy(int port) async {
    final deadline = DateTime.now().add(debugHealthBudgetOverride);
    var sawGatePage = false;

    while (DateTime.now().isBefore(deadline)) {
      final verdict = await _probeOnce(port);
      if (verdict == HealthVerdict.ready) return HealthVerdict.ready;
      if (verdict == HealthVerdict.gateBlocked) sawGatePage = true;
      await Future.delayed(kHealthPollInterval);
    }
    return sawGatePage ? HealthVerdict.gateBlocked : HealthVerdict.pending;
  }

  /// 单次探测。
  Future<HealthVerdict> _probeOnce(int port) async {
    final override = debugHealthResponseOverride;
    if (override != null) {
      final body = await override();
      if (body == null) return HealthVerdict.pending;
      return _classifyHealthBody(body);
    }
    try {
      final response = await _httpClient
          .get(Uri.parse('http://127.0.0.1:$port/api/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return HealthVerdict.pending;
      return _classifyHealthBody(response.body);
    } on TimeoutException {
      return HealthVerdict.pending;
    } catch (e) {
      // 连接拒绝等：容器还没起来。
      return HealthVerdict.pending;
    }
  }

  /// 按响应体分类。
  ///
  /// - 可解析 JSON 且含 `service` 字段 → 引擎真身
  /// - HTML 且含 nginx 欢迎页特征 → 门控拦截
  /// - 其他 → 未就绪
  HealthVerdict _classifyHealthBody(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('<')) {
      final lower = trimmed.toLowerCase();
      final looksLikeWelcomePage =
          lower.contains('welcome to nginx') ||
          lower.contains('<html') && lower.contains('</html>');
      if (looksLikeWelcomePage) return HealthVerdict.gateBlocked;
      return HealthVerdict.pending;
    }
    final decoded = _tryDecodeJson(body);
    if (decoded != null && decoded.containsKey(kHealthServiceField)) {
      return HealthVerdict.ready;
    }
    return HealthVerdict.pending;
  }

  /// 解析 JSON，失败返回 null。
  ///
  /// [decodeOverride] 只被测试用来注入「解析抛异常」这类行为；生产恒为 null。
  Map<String, dynamic>? Function(String)? decodeOverride;

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = decodeOverride != null
          ? decodeOverride!(body)
          : jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
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

  Future<List<String>> _containerLogTail(String projectDir) async {
    try {
      final result = await _runner.run(
        'docker',
        _composeArgs(projectDir, 'logs', ['--tail', '30']),
      );
      return _tailLines(result.combined, 15);
    } catch (e) {
      debugPrint('[ArtexComposeService] 取日志异常: $e');
      return const <String>[];
    }
  }

  // -------------------------------------------------------------------------
  // 5.6 停止
  // -------------------------------------------------------------------------

  /// 停止引擎容器。
  ///
  /// 失败必须上报而不是假装已停止（spec「容器启停与状态呈现」的停止场景）。
  Future<void> stop() async {
    if (_state.status == ArtexEngineStatus.stopped) return;
    _emit(_state.copyWith(status: ArtexEngineStatus.stopping));

    final location = ArtexConfigStore.instance.locateProject();
    if (!location.ok) {
      _fail(
        ArtexEngineFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }

    try {
      final result = await _runner.run(
        'docker',
        _composeArgs(location.path!, 'stop', <String>[]),
      );
      if (result.success) {
        _emit(_state.copyWith(status: ArtexEngineStatus.stopped));
      } else {
        _fail(
          ArtexEngineFailureKind.composeFailed,
          '停止失败',
          result.combined.trim(),
          logTail: _tailLines(result.combined),
        );
      }
    } catch (e) {
      _fail(ArtexEngineFailureKind.composeFailed, '停止失败', '$e');
    }
  }

  // -------------------------------------------------------------------------
  // 5.7 退出时处置
  // -------------------------------------------------------------------------

  /// 应用退出时调用。
  ///
  /// 按 [ArtexEngineConfig.stopOnAppExit] 决定是否停止容器。清理异常
  /// **不阻止退出**——与 mihomo 那条守卫同一语义（`main.dart` 注释：
  /// 「清理失败 MUST NOT block exit」）。
  ///
  /// 无论开关状态如何都 MUST NOT 删除数据卷或工程目录文件（spec「应用退出时
  /// 的容器处置」）——本方法只调 `stop`，不碰 `down -v`。
  Future<void> disposeOnExit() async {
    if (!_config.stopOnAppExit) {
      debugPrint('[ArtexComposeService] 退出即停已关闭，容器继续运行');
      return;
    }
    if (_state.status != ArtexEngineStatus.running &&
        _state.status != ArtexEngineStatus.starting) {
      return;
    }
    try {
      await stop();
    } catch (e, stack) {
      debugPrint('[ArtexComposeService] 退出清理失败（仍然退出）: $e\n$stack');
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
