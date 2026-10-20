import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/artex_engine_config.dart';
import '../models/artex_engine_state.dart';
import 'artex_callback_service.dart';
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

/// compose 在 host 网络模式下的警告。出现它说明端口发布已被丢弃——
/// 启动会「成功」但工作台不可达，所以必须单独识别（design D6）。
const String kHostNetworkDiscardWarning =
    'Published ports are discarded when using host network mode';

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

  /// 测试用：替换真实的网卡探测。
  ///
  /// 否则启动流程会跑真的 `ifconfig`，让测试结果依赖运行机器的网络状态
  /// （有没有网卡、是不是多网卡）。返回空列表 = 模拟「探测不到地址」。
  @visibleForTesting
  Future<List<String>> Function()? debugCallbackCandidatesOverride;


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

  /// 解析回连地址。失败时已通过 [_fail] 上报并返回 null。
  ///
  /// 优先级：用户手动填定 > 自动探测。探测到多候选时不上来就取第一个——
  /// 选错网卡（VPN / Docker 网桥）会让目标机回连失败，且现象是「隧道建
  /// 不起来」这种离现场很远的症状。让用户选并记住。
  Future<String?> _resolveCallbackAddr(ArtexEngineConfig config) async {
    final pinned = config.callbackAddr?.trim();
    if (pinned != null && pinned.isNotEmpty) return pinned;

    final override = debugCallbackCandidatesOverride;
    final candidates = override != null
        ? await override()
        : await ArtexCallbackService.detectCandidates();
    if (candidates.isEmpty) {
      _fail(
        ArtexEngineFailureKind.callbackAddrMissing,
        '找不到回连地址',
        '没有探测到可用于内网回连的宿主机 IPv4 地址。'
            '内网目标机（隧道 / 反弹 shell）需要一个能连到本机的地址。'
            '请检查网络连接，或在设置中手动指定回连地址。',
      );
      return null;
    }
    if (candidates.length == 1) return candidates.single;

    _emit(
      _state.copyWith(
        status: ArtexEngineStatus.failed,
        failureKind: ArtexEngineFailureKind.callbackAddrAmbiguous,
        failure: '需要选择回连地址',
        failureDetail:
            '探测到 ${candidates.length} 个候选地址。'
            '内网目标机将回连到选中的地址，请选目标机真正可达的那个。',
        containerLogTail: const <String>[],
        callbackCandidates: candidates,
      ),
    );
    return null;
  }

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
  /// 顺序：工程目录校验 → 守护进程探活 → 回连地址解析 → 端口预检 →
  /// 生成 override → `up -d` → 健康探测。任一步失败都留下可读原因
  /// （spec「容器启停与状态呈现」）。
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

    // 回连地址解析：内网目标机回连平台用。用户填定则用之，否则探测宿主机
    // 物理网卡。解析不出就不继续——没有它隧道功能等于没修。
    final callback = await _resolveCallbackAddr(config);
    if (callback == null) return; // 失败原因已在 _resolveCallbackAddr 里上报

    // 端口预检：引擎端口 + 隧道池两端。
    //
    // 检池两端就够：池是连续范围，两端被占说明范围选得不对（真实错误是
    // 「用户把池选成了与服务重叠的范围」）；中间被占由 ARTEX 的 CanListen
    // 在分配时逐个试绑自然跳过。
    final portsToCheck = <int>[
      config.httpPort,
      config.proxyPort,
      config.tunnelPortMin,
      config.tunnelPortMax,
    ];
    final conflict = await findConflictingPort(portsToCheck);
    if (conflict != null) {
      final isTunnelPort =
          conflict == config.tunnelPortMin || conflict == config.tunnelPortMax;
      _fail(
        ArtexEngineFailureKind.portConflict,
        '端口 $conflict 被占用',
        isTunnelPort
            ? '隧道端口池边界 $conflict 已被其他进程监听。请在设置中修改隧道池范围后重试。'
            : '宿主机端口 $conflict 已被其他进程监听。请在设置中修改端口后重试。',
      );
      return;
    }

    // 生成 override（门控 + 端口 + 隧道池发布 + 回连地址）
    try {
      ArtexOverrideStore.instance.write(
        projectDir,
        config,
        callbackAddr: callback,
      );
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
    // compose 对 host 网络模式只是警告不报错，但端口发布已被它丢弃——
    // 不主动识别的话，用户会看到「启动成功但工作台打不开」。
    if (up.combined.contains(kHostNetworkDiscardWarning)) {
      _fail(
        ArtexEngineFailureKind.hostNetworkRejected,
        '检测到主机网络模式',
        'compose 提示：$kHostNetworkDiscardWarning。'
        '主机网络模式下所有端口发布都会被丢弃，本机将无法访问引擎工作台。'
        '请检查工程目录的 docker-compose.yml 与 override，移除 network_mode: host。',
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
