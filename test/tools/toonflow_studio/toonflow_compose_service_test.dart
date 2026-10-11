import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/models/toonflow_studio_config.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/models/toonflow_studio_state.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/process_runner.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_compose_service.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_config_store.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_override_store.dart';

/// 容器生命周期服务的单测（spec: 容器启停与状态呈现 / 健康就绪判定）。
///
/// 关键：这些场景全部依赖 [ToonflowFakeProcessRunner] 与
/// `debugHealthResponseOverride` 两个注入点——没有它们，「端口冲突时未调用
/// docker」「HTML 响应判未就绪」这类核心行为无法验证。
void main() {
  late Directory tempDir;
  late Directory projectDir;
  late ToonflowFakeProcessRunner runner;

  ToonflowComposeService serviceFor(ToonflowFakeProcessRunner r) {
    final s = ToonflowComposeService.forTesting(r);
    s.debugHealthBudgetOverride = const Duration(milliseconds: 300);
    return s;
  }

  /// 让 start() 走通的默认脚本：docker info 成功、id 成功、up -d 成功。
  void scriptHappyPath(ToonflowFakeProcessRunner r) {
    r.script('docker', const ToonflowProcessResult(exitCode: 0, stdout: '', stderr: ''));
    r.script('id', const ToonflowProcessResult(exitCode: 0, stdout: '501\n', stderr: ''));
    r.script('id', const ToonflowProcessResult(exitCode: 0, stdout: '20\n', stderr: ''));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tf_compose');
    AppPaths.overrideRootForTesting(tempDir);
    projectDir = Directory(p.join(tempDir.path, 'Toonflow-app'))
      ..createSync(recursive: true);
    File(p.join(projectDir.path, 'compose.yaml')).writeAsStringSync(
      'services:\n  toonflow:\n    build: .\n',
    );
    File(p.join(projectDir.path, 'Dockerfile')).writeAsStringSync(
      'FROM oven/bun:1.3.14\n',
    );
    runner = ToonflowFakeProcessRunner();
    ToonflowConfigStore.instance.resetForTesting();
    ToonflowConfigStore.instance.setConfigForTesting(
      ToonflowStudioConfig(projectDir: projectDir.path, httpPort: 3177),
    );
  });

  tearDown(() {
    ToonflowConfigStore.instance.resetForTesting();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('启动流程', () {
    test('工程目录缺失时不调用 docker', () async {
      ToonflowConfigStore.instance.setConfigForTesting(
        const ToonflowStudioConfig(projectDir: '/nonexistent/path'),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(runner.called('docker'), isFalse,
          reason: '定位失败必须拦在 docker 之前');
      expect(s.state.status, ToonflowStatus.failed);
      expect(s.state.failureKind, ToonflowFailureKind.projectNotFound);
    });

    test('缺 Dockerfile 时报告工程定位失败', () async {
      File(p.join(projectDir.path, 'Dockerfile')).deleteSync();
      final s = serviceFor(runner);
      await s.start();
      expect(s.state.failureKind, ToonflowFailureKind.projectNotFound);
      expect(s.state.failureDetail, contains('Dockerfile'));
    });

    test('守护进程不可达时不调用 up', () async {
      runner.script(
        'docker',
        const ToonflowProcessResult(exitCode: 1, stdout: '', stderr: 'Cannot connect to the Docker daemon'),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isFalse,
        reason: '守护进程不可达必须拦在 up 之前',
      );
      expect(s.state.failureKind, ToonflowFailureKind.dockerUnavailable);
    });

    test('端口冲突时不调用 up', () async {
      // 占用一个真实端口，让预检真的失败。
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, shared: false,
      );
      final busyPort = socket.port;
      addTearDown(() => socket.close());

      ToonflowConfigStore.instance.setConfigForTesting(
        ToonflowStudioConfig(projectDir: projectDir.path, httpPort: busyPort),
      );
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      await s.start();

      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isFalse,
        reason: '端口冲突必须在 up 之前拦住',
      );
      expect(s.state.failureKind, ToonflowFailureKind.portConflict);
      expect(s.state.failure, contains('$busyPort'));
    });

    test('全链路走通后进入运行中', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async =>
          '{"code":200,"data":{},"message":"Success"}';
      await s.start();
      expect(s.state.status, ToonflowStatus.running);
      expect(s.state.canOpenWorkspace, isTrue);
      // override 必须被写出来。
      expect(
        ToonflowOverrideStore.instance.isManaged(projectDir.path),
        isTrue,
      );
    });

    test('重复启动不二次 up', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      final upCount =
          runner.callsTo('docker').where((a) => a.contains('up')).length;
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
        const ToonflowProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Error response from daemon: No such image: toonflow-app-toonflow',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(s.state.failureKind, ToonflowFailureKind.buildRequired);
      expect(s.state.failureDetail, contains('构建镜像'));
    });

    test('服务名找不到时给出核对 compose 的定向提示', () async {
      // 上游把服务从 toonflow 改名后，override 静默失效，up 时才报错。
      // 这类失败让用户「重试」没有意义，必须指向 compose 服务名。
      scriptHappyPath(runner);
      runner.script(
        'docker',
        const ToonflowProcessResult(
          exitCode: 1,
          stdout: '',
          stderr: 'no such service: toonflow-app',
        ),
      );
      final s = serviceFor(runner);
      await s.start();
      expect(s.state.status, ToonflowStatus.failed);
      expect(s.state.failure, contains('服务名'));
      expect(
        s.state.failureDetail,
        contains('compose.yaml'),
        reason: '要告诉用户去核对上游 compose 的服务名',
      );
    });
  });

  group('健康探测判据', () {
    test('业务 JSON（含 code 字段）判为就绪', () {
      expect(
        ToonflowComposeService.classifyHealthBody(
          '{"code":200,"data":{"path":""},"message":"Success"}',
        ),
        HealthVerdict.ready,
      );
    });

    test('HTML 判为未就绪（API 没起来，静态服务返回 SPA 页面）', () {
      expect(
        ToonflowComposeService.classifyHealthBody(
          '<!doctype html><html><head><title>Toonflow</title></head></html>',
        ),
        HealthVerdict.pending,
      );
    });

    test('不含 code 字段的 JSON 判为未就绪', () {
      expect(
        ToonflowComposeService.classifyHealthBody('{"ok":true}'),
        HealthVerdict.pending,
      );
    });

    test('非 JSON 非 HTML 判为未就绪', () {
      expect(
        ToonflowComposeService.classifyHealthBody('Service Unavailable'),
        HealthVerdict.pending,
      );
    });

    test('HTML 响应导致超时，并附上容器日志', () async {
      // happy path 提供 3 条（docker info / id -u / id -g），up -d 与 logs
      // 各需要一条 docker 脚本。
      scriptHappyPath(runner);
      runner.script('docker', const ToonflowProcessResult(exitCode: 0, stdout: '', stderr: ''));
      runner.script(
        'docker',
        const ToonflowProcessResult(
          exitCode: 0,
          stdout: 'toonflow  | Error: listen EADDRINUSE',
          stderr: '',
        ),
      );
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async =>
          '<!doctype html><html></html>';
      await s.start();
      expect(s.state.status, ToonflowStatus.failed);
      expect(s.state.failureKind, ToonflowFailureKind.healthTimeout);
      expect(s.state.containerLogTail, isNotEmpty,
          reason: '超时必须附日志帮用户定位');
    });
  });

  group('停止与退出', () {
    test('停止成功进入 stopped', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      runner.script('docker', const ToonflowProcessResult(exitCode: 0, stdout: '', stderr: ''));
      await s.stop();
      expect(s.state.status, ToonflowStatus.stopped);
    });

    test('停止失败上报而不是假装已停止', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      runner.script(
        'docker',
        const ToonflowProcessResult(exitCode: 1, stdout: '', stderr: 'error removing container'),
      );
      await s.stop();
      expect(s.state.status, ToonflowStatus.failed);
      expect(s.state.failureKind, ToonflowFailureKind.composeFailed);
    });

    test('stopOnAppExit=false 时退出不停容器', () async {
      ToonflowConfigStore.instance.setConfigForTesting(
        ToonflowStudioConfig(
          projectDir: projectDir.path,
          httpPort: 3177,
          stopOnAppExit: false,
        ),
      );
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      final downBefore =
          runner.callsTo('docker').where((a) => a.contains('down')).length;
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
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      runner.script('docker', const ToonflowProcessResult(exitCode: 0, stdout: '', stderr: ''));
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

  group('override 的 uid/gid 注入', () {
    test('从 id -u / id -g 取值写入 override', () async {
      scriptHappyPath(runner);
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      final content =
          ToonflowOverrideStore.instance.read(projectDir.path)!;
      expect(content, contains('user: "501:20"'));
    });

    test('取不到 uid/gid 时回退 501:20 而不失败', () async {
      runner.script('docker', const ToonflowProcessResult(exitCode: 0, stdout: '', stderr: ''));
      // id 命令缺失：FakeProcessRunner 对未 script 的可执行文件返回成功空输出，
      // 这里显式 script 一个失败让它走回退分支。
      runner.script(
        'id',
        const ToonflowProcessResult(exitCode: 1, stdout: '', stderr: 'no id'),
      );
      final s = serviceFor(runner);
      s.debugHealthResponseOverride = () async => '{"code":200}';
      await s.start();
      expect(s.state.status, ToonflowStatus.running,
          reason: 'uid/gid 取不到不该让启动失败');
      expect(
        ToonflowOverrideStore.instance.read(projectDir.path),
        contains('user: "501:20"'),
      );
    });
  });
}
