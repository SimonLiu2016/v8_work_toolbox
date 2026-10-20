import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/infinite_canvas_config.dart';
import '../models/infinite_canvas_state.dart';
import 'infinite_canvas_config_store.dart';
import 'infinite_canvas_override_store.dart';
import 'process_runner.dart';

/// 健康探测的总预算与间隔。
///
/// 与 Toonflow 版的 60 秒不同：那个预算要覆盖容器首次启动的插件初始化，
/// 而无限画布的容器只是 nginx，静态产物落盘即就绪——15 秒已经很宽松。
const Duration kHealthTotalBudget = Duration(seconds: 15);
const Duration kHealthPollInterval = Duration(seconds: 1);

/// 单次探测的超时。容器刚拉起时连接会被拒，这个超时只覆盖「连上但不回」。
const Duration kHealthProbeTimeout = Duration(seconds: 3);

/// 健康探测判定结果。
enum HealthVerdict { ready, pending }

/// 就绪判定要求的第一个标识：SPA 挂载点。
///
/// 无限画布的入口页（`web/index.html`）固定含 `<div id="root">`。只凭它
/// 不足以区分「我们的容器」与「别的服务」，所以还要 [kHealthConfigScript]。
const String kHealthRootMarker = '<div id="root">';

/// 就绪判定要求的第二个标识：运行时配置脚本标签。
///
/// `/config.js` 由容器的 `docker-entrypoint.sh` 在启动时按环境变量生成，
/// 而入口页固定引用它。因此它的存在同时证明两件事：这是我们容器的 nginx
/// （宿主机另一个占着端口的服务不会恰好返回引用 `/config.js` 的页面），
/// 且 entrypoint 已执行完毕（spec: 健康就绪判定必须校验静态容器标识）。
const String kHealthConfigScript = '/config.js';

/// 无限画布容器生命周期服务。
///
/// **本服务不实现任何无限画布能力**，只负责：
/// - 守护进程探活
/// - 启动前端口预检（工作台端口与资产桥端口）
/// - 生成 override 并 `up -d`，然后等健康探测通过
/// - 就绪超时时附容器日志
/// - `stop` 与退出时按配置处置
///
/// 进程执行走可注入的 [ProcessRunner]，使上述行为可在测试中驱动。
class InfiniteCanvasComposeService extends ChangeNotifier {
  InfiniteCanvasComposeService._(this._runner, [this._httpClient]);

  /// 生产单例。
  static final InfiniteCanvasComposeService instance =
      InfiniteCanvasComposeService._(
        const InfiniteCanvasRealProcessRunner(),
        http.Client(),
      );

  /// 测试用实例：注入假进程执行器，并共用同一个配置存储。
  ///
  /// 不复用单例是为了让每个测试从干净状态开始（`_state` / `_starting` 是
  /// 进程级可变状态）。
  @visibleForTesting
  factory InfiniteCanvasComposeService.forTesting(
    ProcessRunner runner, [
    http.Client? httpClient,
  ]) = InfiniteCanvasComposeService._;

  final ProcessRunner _runner;

  /// 生产用真实客户端；测试经 `debugHealthResponseOverride` 绕过 HTTP，
  /// 所以这个字段在测试里可以传 null。
  final http.Client? _httpClient;

  InfiniteCanvasState _state = const InfiniteCanvasState.initial();
  bool _starting = false;
  bool _stopping = false;

  /// 上次启动是否备份了用户手工编辑的 override（UI 需告知用户）。
  bool lastWriteBackedUp = false;

  InfiniteCanvasState get state => _state;

  InfiniteCanvasConfig get _config =>
      InfiniteCanvasConfigStore.instance.config;

  /// 测试用：压缩健康预算，避免每个用例等 15 秒。
  @visibleForTesting
  Duration debugHealthBudgetOverride = kHealthTotalBudget;

  /// 测试用：注入健康响应体，绕过真实 HTTP。
  @visibleForTesting
  Future<String> Function()? debugHealthResponseOverride;

  void _emit(InfiniteCanvasState next) {
    _state = next;
    notifyListeners();
  }

  void _fail(
    InfiniteCanvasFailureKind kind,
    String summary,
    String detail, {
    List<String> logTail = const <String>[],
  }) {
    _starting = false;
    _stopping = false;
    _emit(
      _state.copyWith(
        status: InfiniteCanvasStatus.failed,
        failureKind: kind,
        failure: summary,
        failureDetail: detail,
        containerLogTail: logTail,
      ),
    );
  }

  /// compose 命令的统一入口：始终带上上游 compose 文件与本工具的 override。
  ///
  /// 上游 compose 文件名是运行时探测出来的（三种都可能），不是硬编码
  /// （design D6）。
  List<String> _composeArgs(
    String projectDir,
    String composeFile,
    String sub,
    List<String> rest,
  ) => [
    'compose',
    '-f',
    p.join(projectDir, composeFile),
    '-f',
    InfiniteCanvasOverrideStore.instance.pathFor(projectDir),
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
      debugPrint('[InfiniteCanvasComposeService] docker info 异常: $e');
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
        debugPrint('[InfiniteCanvasComposeService] 端口探测异常 ($port): $e');
        return port;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // 启动与健康探测
  // -------------------------------------------------------------------------

  /// 启动无限画布。
  ///
  /// 顺序：工程目录校验 → 守护进程探活 → 端口预检 → 生成 override →
  /// `up -d` → 健康探测。任一步失败都留下可读原因。
  Future<void> start() async {
    if (_starting || _state.status == InfiniteCanvasStatus.running) return;
    _starting = true;
    _emit(
      _state.copyWith(
        status: InfiniteCanvasStatus.starting,
        clearFailure: true,
        containerLogTail: const <String>[],
      ),
    );

    final config = _config;

    // 1. 工程目录定位（同时拿到实际命中的 compose 文件名）
    final location = InfiniteCanvasConfigStore.instance.locateProject(
      config.projectDir,
    );
    if (!location.ok) {
      _fail(
        InfiniteCanvasFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }
    final projectDir = location.path!;
    final composeFile = location.composeFile!;

    // 2. 守护进程探活
    if (!await isDockerAvailable()) {
      _fail(
        InfiniteCanvasFailureKind.dockerUnavailable,
        'Docker 未运行',
        '无法连接 Docker 守护进程。若刚启动 Docker Desktop，请等待其完全就绪后重试。',
      );
      return;
    }

    // 3. 端口预检——只查工作台端口。
    //
    // 资产桥端口**不在这里查**：那个端口由本进程的 InfiniteCanvasBridgeServer
    // 自己 listen（工具页 initState 就会起它），在这里查必然判成「被占用」，
    // 于是每次点启动都失败在端口冲突上。它的占用检测归 start() 里的
    // HttpServer.bind——bind 失败已经有 lastError 报给用户。
    final conflict = await findConflictingPort([config.httpPort]);
    if (conflict != null) {
      _fail(
        InfiniteCanvasFailureKind.portConflict,
        '端口 $conflict 被占用',
        '宿主机端口 $conflict 已被其他进程监听。请在设置中修改端口后重试。',
      );
      return;
    }

    // 4. 生成 override（回环端口 + 可选镜像覆盖）
    try {
      lastWriteBackedUp = InfiniteCanvasOverrideStore.instance.write(
        projectDir,
        config,
      );
    } catch (e) {
      _fail(
        InfiniteCanvasFailureKind.composeFailed,
        '生成 override 失败',
        '$e',
      );
      return;
    }

    // 5. 拉起容器。默认路径不本地构建——compose 自己从 ghcr.io 拉镜像。
    final up = await _runner
        .run('docker', _composeArgs(projectDir, composeFile, 'up', ['-d']))
        .catchError((Object e) {
          debugPrint('[InfiniteCanvasComposeService] up -d 异常: $e');
          return InfiniteCanvasProcessResult(
            exitCode: -1,
            stdout: '',
            stderr: '$e',
          );
        });
    if (!up.success) {
      _classifyComposeFailure(up.combined, projectDir, composeFile);
      return;
    }

    // 6. 健康探测
    final verdict = await _waitUntilHealthy(config.httpPort);
    if (verdict == HealthVerdict.ready) {
      _starting = false;
      _emit(_state.copyWith(status: InfiniteCanvasStatus.running));
      return;
    }

    final logs = await _containerLogTail(projectDir, composeFile);
    _fail(
      InfiniteCanvasFailureKind.healthTimeout,
      '服务未就绪',
      '在 ${kHealthTotalBudget.inSeconds} 秒内未收到预期的健康响应。',
      logTail: logs,
    );
  }

  /// 把 `up -d` 的失败归类。
  ///
  /// 「镜像未拉取」单独一类：它的用户动作是检查网络/镜像源，而不是重试启动。
  ///
  /// 「服务名找不到」单独一类：上游 compose 文件把服务从 `app` 改名时
  /// override 会静默失效（compose 不会因为 override 引用了个不存在的服务而
  /// 报错，`up` 时才发现）。这时让用户去重试没有意义，必须告诉他去核对服务名
  /// （design Risk：上游仓库升级导致 compose 结构变化）。
  ///
  /// [composeFile] 是启动时探测到的上游文件名——错误提示里要指向**实际存在
  /// 的那个**，而不是假设它叫 `compose.yaml`。
  void _classifyComposeFailure(
    String combined,
    String projectDir,
    String composeFile,
  ) {
    final lower = combined.toLowerCase();
    if (lower.contains('no such image') ||
        RegExp(r'image.*not found').hasMatch(lower) ||
        lower.contains('unable to find image') ||
        lower.contains('pull access denied') ||
        lower.contains('manifest unknown')) {
      _fail(
        InfiniteCanvasFailureKind.buildRequired,
        '镜像未拉取',
        '无法从 ghcr.io 拉取无限画布镜像。请检查网络或 Docker 的镜像源配置后重试；'
        '若要改用本地代码，请点击「构建镜像」。',
      );
      return;
    }
    if (lower.contains('cannot connect to the docker daemon')) {
      _fail(
        InfiniteCanvasFailureKind.dockerUnavailable,
        'Docker 未运行',
        '无法连接 Docker 守护进程。',
      );
      return;
    }
    if (lower.contains('no such service') ||
        RegExp(r'service .* not found').hasMatch(lower)) {
      _fail(
        InfiniteCanvasFailureKind.composeFailed,
        'Compose 服务名不匹配',
        '上游 compose 文件里找不到本工具使用的服务名「$kComposeServiceName」。'
        '无限画布仓库可能已升级并改了服务名——请打开 '
        '$projectDir/$composeFile 核对 services 下的名字，'
        '并同步修正本工具生成的 $kOverrideFileName。',
      );
      return;
    }
    _fail(
      InfiniteCanvasFailureKind.composeFailed,
      '容器启动失败',
      combined.trim(),
    );
  }

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
      final body = await override();
      return classifyHealthBody(body);
    }
    if (client == null) return HealthVerdict.pending;
    try {
      final response = await client
          .get(Uri.parse('http://127.0.0.1:$port/'))
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
  /// 判据与 Toonflow 版**方向相反**（spec: 健康就绪判定必须校验静态容器标识）：
  /// Toonflow 要求「必须是业务接口的 JSON 信封」，因为它的 API 与静态资源
  /// 同进程、任意路径都返 200 HTML；无限画布只有静态资源，所以要求「必须
  /// 是这个容器独有的入口页形态」。
  ///
  /// - 同时含挂载点与 `/config.js` → 我们的容器且 entrypoint 已跑完
  /// - 只有挂载点 → entrypoint 还没执行，打开会缺运行时配置
  /// - 其他 200 → 是别的服务占了这个端口，不是无限画布
  static HealthVerdict classifyHealthBody(String body) {
    if (!body.contains(kHealthRootMarker)) return HealthVerdict.pending;
    if (!body.contains(kHealthConfigScript)) return HealthVerdict.pending;
    return HealthVerdict.ready;
  }

  Future<List<String>> _containerLogTail(
    String projectDir,
    String composeFile,
  ) async {
    try {
      final result = await _runner.run(
        'docker',
        _composeArgs(projectDir, composeFile, 'logs', ['--tail', '30']),
      );
      return _tailLines(result.combined, 15);
    } catch (e) {
      debugPrint('[InfiniteCanvasComposeService] 取日志异常: $e');
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
    if (_stopping || _state.status == InfiniteCanvasStatus.stopped) return;
    _stopping = true;
    _emit(
      _state.copyWith(status: InfiniteCanvasStatus.stopping, clearFailure: true),
    );

    final location = InfiniteCanvasConfigStore.instance.locateProject();
    if (!location.ok) {
      _fail(
        InfiniteCanvasFailureKind.projectNotFound,
        '未找到 Compose 工程',
        location.reason ?? '未知原因',
      );
      return;
    }

    final down = await _runner
        .run(
          'docker',
          _composeArgs(location.path!, location.composeFile!, 'down', []),
        )
        .catchError((Object e) {
          debugPrint('[InfiniteCanvasComposeService] down 异常: $e');
          return InfiniteCanvasProcessResult(
            exitCode: -1,
            stdout: '',
            stderr: '$e',
          );
        });
    _stopping = false;
    if (!down.success) {
      _fail(
        InfiniteCanvasFailureKind.composeFailed,
        '容器停止失败',
        down.combined.trim(),
      );
      return;
    }
    _emit(_state.copyWith(status: InfiniteCanvasStatus.stopped));
  }

  /// 按配置在应用退出时处置容器。
  ///
  /// 抛异常时仍必须让调用方继续退出——卡在清理上比放弃清理更糟。
  Future<void> disposeOnExit() async {
    if (!_config.stopOnAppExit) return;
    if (_state.status != InfiniteCanvasStatus.running &&
        _state.status != InfiniteCanvasStatus.starting) {
      return;
    }
    try {
      await stop();
    } catch (e) {
      debugPrint('[InfiniteCanvasComposeService] 退出时停止容器失败: $e');
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
}
