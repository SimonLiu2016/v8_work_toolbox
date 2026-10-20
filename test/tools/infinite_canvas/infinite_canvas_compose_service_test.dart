import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_config.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_state.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_compose_service.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_config_store.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_override_store.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/process_runner.dart';

/// 容器生命周期服务的单测（spec: 容器启停与状态呈现 / 健康就绪判定 / 端口预检）。
///
/// 关键：这些场景全部依赖 [InfiniteCanvasFakeProcessRunner] 与
/// `debugHealthResponseOverride` 两个注入点——没有它们，「端口冲突时未调用
/// docker」「别的服务的 200 判未就绪」这类核心行为无法验证。
void main() {
  late Directory tempDir;
  late Directory projectDir;
  late InfiniteCanvasFakeProcessRunner runner;

  InfiniteCanvasComposeService serviceFor(InfiniteCanvasFakeProcessRunner r) {
    final s = InfiniteCanvasComposeService.forTesting(r);
    s.debugHealthBudgetOverride = const Duration(milliseconds: 300);
    return s;
  }

  /// 让 start() 走通的默认脚本：docker info 成功。
  ///
  /// 与 Toonflow 版的差异：不再需要 `id -u` / `id -g`——override 里没有
  /// `user:` 对齐（nginx 不写盘）。
  void scriptHappyPath(InfiniteCanvasFakeProcessRunner r) {
    r.script(
      'docker',
      const InfiniteCanvasProcessResult(exitCode: 0, stdout: '', stderr: ''),
    );
  }

  /// 无限画布入口页的最小真实形态（`web/index.html` 的两个标识）。
  String healthyPage() =>
      '<!doctype html><html><head><script src="/config.js"></script>'
      '</head><body><div id="root"></div></body></html>';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ic_compose');
    AppPaths.overrideRootForTesting(tempDir);
    // 上游实际提供的是 docker-compose.yml——用它验证探测路径。
    projectDir = Directory(p.join(tempDir.path, 'infinite-canvas'))
      ..createSync(recursive: true);
    File(p.join(projectDir.path, 'docker-compose.yml')).writeAsStringSync(
      'services:\n  app:\n    image: ghcr.io/basketikun/infinite-canvas:latest\n',
    );
    File(
      p.join(projectDir.path, 'Dockerfile'),
    ).writeAsStringSync('FROM nginx:1.27-alpine\n');
    runner = InfiniteCanvasFakeProcessRunner();
    InfiniteCanvasConfigStore.instance.resetForTesting();
    InfiniteCanvasConfigStore.instance.setConfigForTesting(
      InfiniteCanvasConfig(projectDir: projectDir.path, httpPort: 3177),
    );
  });

  tearDown(() {
    InfiniteCanvasConfigStore.instance.resetForTesting();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('启动流程', () {
    test('工程目录缺失时不调用 docker', () async {
      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        const InfiniteCanvasConfig(projectDir: '/nonexistent/path'),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        runner.called('docker'),
        isFalse,
        reason: '定位失败必须拦在 docker 之前',
      );
      expect(s.state.status, InfiniteCanvasStatus.failed);
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.projectNotFound,
      );
    });

    test('缺 Dockerfile 时报告工程定位失败', () async {
      File(p.join(projectDir.path, 'Dockerfile')).deleteSync();
      final s = serviceFor(runner);
      await s.start();
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.projectNotFound,
      );
      expect(s.state.failureDetail, contains('Dockerfile'));
    });

    test('守护进程不可达时不调用 up', () async {
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Cannot connect to the Docker daemon',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isFalse,
        reason: '守护进程不可达必须拦在 up 之前',
      );
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.dockerUnavailable,
      );
    });

    test('端口冲突时不调用 up', () async {
      // 占用一个真实端口，让预检真的失败。
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      final busyPort = socket.port;
      addTearDown(() => socket.close());

      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        InfiniteCanvasConfig(
          projectDir: projectDir.path,
          httpPort: busyPort,
        ),
      );
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      await s.start();

      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isFalse,
        reason: '端口冲突必须在 up 之前拦住',
      );
      expect(s.state.failureKind, InfiniteCanvasFailureKind.portConflict);
      expect(s.state.failure, contains('$busyPort'));
    });

    test('资产桥端口被占不阻塞容器启动', () async {
      // 回归：资产桥端口由本进程的 BridgeServer 自己 listen。曾把它也列进
      // compose 的预检集合，于是只要工具页打开过（bridge 已起），点启动就
      // 必然失败在「端口被占用」上——而那个端口正是自己人持有的。
      //
      // 现在预检只覆盖工作台端口；资产桥的占用检测归 BridgeServer.start()
      // 的 HttpServer.bind（失败时报 lastError）。
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      final busyBridgePort = socket.port;
      addTearDown(() => socket.close());

      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        InfiniteCanvasConfig(
          projectDir: projectDir.path,
          httpPort: 3177,
          bridgePort: busyBridgePort,
        ),
      );
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();

      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isTrue,
        reason: '别人占了资产桥端口也不该挡住工作台启动',
      );
      expect(s.state.status, InfiniteCanvasStatus.running);
      expect(s.state.failureKind, isNull);
    });

    test('全链路走通后进入运行中', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      expect(s.state.status, InfiniteCanvasStatus.running);
      expect(s.state.canOpenWorkspace, isTrue);
      // override 必须被写出来。
      expect(
        InfiniteCanvasOverrideStore.instance.isManaged(projectDir.path),
        isTrue,
      );
      // compose 命令必须带上探测到的上游文件名，而不是硬编码 compose.yaml。
      final upArgs = runner.callsTo('docker').firstWhere(
        (a) => a.contains('up'),
      );
      expect(upArgs, contains('docker-compose.yml'));
      expect(upArgs, contains(kOverrideFileName));
    });

    test('重复启动不二次 up', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      final upCount = runner.callsTo('docker')
          .where((a) => a.contains('up'))
          .length;
      await s.start();
      expect(
        runner.callsTo('docker').where((a) => a.contains('up')).length,
        upCount,
        reason: '已在运行时不该重复启动',
      );
    });

    test('up -d 失败且提示镜像不存在时归类为 buildRequired', () async {
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr:
              'Error response from daemon: manifest unknown: '
              'ghcr.io/basketikun/infinite-canvas:latest',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.buildRequired,
      );
      expect(s.state.failureDetail, contains('ghcr.io'));
    });

    test('pull access denied 同样归类为 buildRequired', () async {
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'pull access denied for infinite-canvas',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.buildRequired,
      );
    });

    test('服务名找不到时给出核对 compose 的定向提示', () async {
      // 上游把服务从 app 改名后，override 静默失效，up 时才报错。
      // 这类失败让用户「重试」没有意义，必须指向 compose 服务名。
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'no such service: infinite-canvas-app',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(s.state.status, InfiniteCanvasStatus.failed);
      expect(s.state.failure, contains('服务名'));
      expect(
        s.state.failureDetail,
        contains('docker-compose.yml'),
        reason: '要告诉用户去核对上游 compose 的服务名',
      );
      expect(s.state.failureDetail, contains('app'));
    });

    test('未分类的 up 失败也上报原始输出而不是静默', () async {
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'some totally unexpected docker error',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.composeFailed,
      );
      expect(s.state.failureDetail, contains('unexpected docker error'));
    });
  });

  group('健康探测判据（方向与 Toonflow 版相反）', () {
    test('同时含挂载点与 /config.js 判为就绪', () {
      expect(
        InfiniteCanvasComposeService.classifyHealthBody(healthyPage()),
        HealthVerdict.ready,
      );
    });

    test('别的服务的 200 判为未就绪', () async {
      // 判据必须反向：无限画布只有静态资源，nginx 的 try_files 回退会对任意
      // 路径返回 200 HTML。只看状态码会把「别的进程占了这个端口」误判成就绪。
      expect(
        InfiniteCanvasComposeService.classifyHealthBody(
          '<!doctype html><html><body><h1>It works</h1></body></html>',
        ),
        HealthVerdict.pending,
      );
    });

    test('有挂载点但无 /config.js 判为未就绪', () {
      // entrypoint 还没跑完时打开工作台会缺运行时配置。
      expect(
        InfiniteCanvasComposeService.classifyHealthBody(
          '<!doctype html><html><body><div id="root"></div></body></html>',
        ),
        HealthVerdict.pending,
      );
    });

    test('非 HTML 响应判为未就绪', () {
      expect(
        InfiniteCanvasComposeService.classifyHealthBody('Service Unavailable'),
        HealthVerdict.pending,
      );
    });

    test('空响应体判为未就绪', () {
      expect(
        InfiniteCanvasComposeService.classifyHealthBody(''),
        HealthVerdict.pending,
      );
    });

    test('非入口页导致超时，并附上容器日志', () async {
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(exitCode: 0, stdout: '', stderr: ''),
      );
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 0,
          stdout: 'app  | 2026/10/15 nginx started',
          stderr: '',
        ),
      );
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async =>
          '<!doctype html><html><body>other service</body></html>';
      await s.start();
      expect(s.state.status, InfiniteCanvasStatus.failed);
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.healthTimeout,
      );
      expect(
        s.state.containerLogTail,
        isNotEmpty,
        reason: '超时必须附日志帮用户定位',
      );
    });
  });

  group('停止与退出', () {
    test('停止成功进入 stopped', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(exitCode: 0, stdout: '', stderr: ''),
      );
      await s.stop();
      expect(s.state.status, InfiniteCanvasStatus.stopped);
    });

    test('停止失败上报而不是假装已停止', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'error removing container',
        ),
      );
      await s.stop();
      expect(s.state.status, InfiniteCanvasStatus.failed);
      expect(
        s.state.failureKind,
        InfiniteCanvasFailureKind.composeFailed,
      );
    });

    test('stopOnAppExit=false 时退出不停容器', () async {
      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        InfiniteCanvasConfig(
          projectDir: projectDir.path,
          httpPort: 3177,
          stopOnAppExit: false,
        ),
      );
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      final downBefore = runner.callsTo('docker')
          .where((a) => a.contains('down'))
          .length;
      await s.disposeOnExit();
      expect(
        runner.callsTo('docker').where((a) => a.contains('down')).length,
        downBefore,
        reason: '用户配置退出不停时不该停',
      );
    });

    test('stopOnAppExit=true 且运行中时退出会停容器', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => healthyPage();
      await s.start();
      runner.script(
        'docker',
        const InfiniteCanvasProcessResult(exitCode: 0, stdout: '', stderr: ''),
      );
      await s.disposeOnExit();
      expect(
        runner.callsTo('docker').any((a) => a.contains('down')),
        isTrue,
      );
    });

    test('未运行时退出不停容器', () async {
      final s = serviceFor(runner);
      await s.disposeOnExit();
      expect(runner.called('docker'), isFalse);
    });
  });
}
