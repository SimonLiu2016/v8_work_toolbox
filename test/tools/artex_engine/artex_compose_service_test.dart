import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/artex_engine/models/artex_engine_config.dart';
import 'package:V8WorkToolbox/tools/artex_engine/models/artex_engine_state.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_config_store.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_compose_service.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/process_runner.dart';

/// 容器生命周期服务的单测（task 5.9）。
///
/// 关键：这些场景全部依赖 [FakeProcessRunner] 与 [ArtexComposeService.decodeOverride]
/// 两个注入点——没有它们，「端口冲突时未调用 docker」「HTML 响应判未就绪」
/// 这类核心行为无法验证。
void main() {
  late Directory tempDir;
  late Directory appRoot;
  late FakeProcessRunner runner;
  late ArtexComposeService service;

  ArtexProcessResult ok([String out = '']) =>
      ArtexProcessResult(exitCode: 0, stdout: out, stderr: '');

  ArtexProcessResult fail([String err = 'boom']) =>
      ArtexProcessResult(exitCode: 1, stdout: '', stderr: err);

  /// 把配置指向临时工程目录，并预置 compose 文件。
  ///
  /// 默认端口取 18787/18788 这类高位口：本机跑着真实的 artex 容器，
  /// 占着 8787/8788，用默认值会让端口预检误判冲突。
  void useTempProject({int httpPort = 18787, int proxyPort = 18788, bool stopOnAppExit = true}) {
    File('${tempDir.path}/docker-compose.yml').writeAsStringSync(
      'services: {}',
    );
    ArtexConfigStore.instance.setConfigForTesting(
      ArtexEngineConfig(
        projectDir: tempDir.path,
        httpPort: httpPort,
        proxyPort: proxyPort,
        stopOnAppExit: stopOnAppExit,
      ),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('artex_svc');
    appRoot = Directory.systemTemp.createTempSync('artex_approot');
    AppPaths.overrideRootForTesting(appRoot);
    runner = FakeProcessRunner();
    service = ArtexComposeService.forTesting(runner);
    // 压缩健康预算：否则每个超时用例都要跑满 60 秒真实时间。
    service.debugHealthBudgetOverride = const Duration(milliseconds: 300);
  });

  tearDown(() {
    ArtexConfigStore.instance.resetForTesting();
    AppPaths.resetForTesting();
    service.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (appRoot.existsSync()) appRoot.deleteSync(recursive: true);
  });

  group('健康判定：必须校验响应体（design D2 / spec）', () {
    test('引擎 JSON 判定就绪', () {
      expect(
        service.debugClassifyHealthBody('{"ok":true,"service":"artex","version":"dev"}'),
        HealthVerdict.ready,
      );
    });

    test('200 的 nginx 欢迎页判为门控拦截，不是就绪', () {
      // spike 实测：门控开启时 /api/health 返回这个页面，状态码 200。
      const page =
          '<!DOCTYPE html>\n<html>\n<head><title>Welcome to nginx!</title>';
      expect(
        service.debugClassifyHealthBody(page),
        HealthVerdict.gateBlocked,
      );
    });

    test('无 service 字段的 JSON 不算就绪', () {
      expect(
        service.debugClassifyHealthBody('{"ok":true}'),
        HealthVerdict.pending,
      );
    });

    test('非 JSON 非 HTML 的正文不算就绪', () {
      expect(service.debugClassifyHealthBody('ok'), HealthVerdict.pending);
    });

    test('解析抛异常时不算就绪', () {
      service.decodeOverride = (_) => throw const FormatException('bad');
      expect(
        service.debugClassifyHealthBody('{"service":"artex"}'),
        HealthVerdict.pending,
      );
    });
  });

  group('端口预检（task 5.3 / design D3）', () {
    test('空闲端口返回 null', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final busyPort = socket.port;
      addTearDown(socket.close);
      // 用一个肯定空闲的高端口
      final free = busyPort + 1;
      expect(await service.findConflictingPort([free]), isNull);
      expect(busyPort, greaterThan(0));
    });

    test('被占用的端口被报告出来', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socket.close);
      expect(await service.findConflictingPort([socket.port]), socket.port);
    });

    test('第一个冲突端口优先报告', () async {
      final s1 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final s2 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() {
        s1.close();
        s2.close();
      });
      expect(await service.findConflictingPort([s1.port, s2.port]), s1.port);
    });
  });

  group('启动流程（task 5.4 / 5.5）', () {
    test('工程目录缺失时失败，且不调用 docker', () async {
      // 不指向有效工程
      ArtexConfigStore.instance.setConfigForTesting(
        const ArtexEngineConfig(projectDir: '/nonexistent-artex-dir-xyz'),
      );
      await service.start();
      expect(service.state.status, ArtexEngineStatus.failed);
      expect(service.state.failureKind, ArtexEngineFailureKind.projectNotFound);
      expect(runner.called('docker'), isFalse);
    });

    test('Docker 不可达时失败，且不到端口预检那一步', () async {
      useTempProject();
      runner.script('docker', fail('Cannot connect to the Docker daemon'));
      await service.start();
      expect(service.state.failureKind, ArtexEngineFailureKind.dockerUnavailable);
      expect(service.state.failure, contains('Docker 未运行'));
    });

    test('端口冲突时失败，且不执行 up', () async {
      useTempProject();
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(s.close);
      ArtexConfigStore.instance.setConfigForTesting(
        ArtexEngineConfig(projectDir: tempDir.path, httpPort: s.port),
      );
      runner.script('docker', ok());
      await service.start();
      expect(service.state.failureKind, ArtexEngineFailureKind.portConflict);
      expect(service.state.failure, contains('${s.port}'));
      expect(runner.callsTo('docker'), isNotEmpty); // info 调过
      expect(
        runner.callsTo('docker').any((a) => a.contains('up')),
        isFalse,
        reason: '端口冲突必须在 up 之前拦住',
      );
    });

    test('up -d 失败时带容器输出作为详情', () async {
      useTempProject();
      runner
        ..script('docker', ok()) // info
        ..script('docker', fail('Bind for 0.0.0.0:8787 failed: port is already allocated'));
      await service.start();
      expect(service.state.failureKind, ArtexEngineFailureKind.composeFailed);
      expect(service.state.failureDetail, contains('port is already allocated'));
    });

    test('就绪后进入 running', () async {
      useTempProject();
      runner
        ..script('docker', ok()) // info
        ..script('docker', ok('Container started')); // up -d
      service.debugHealthResponseOverride = () async =>
          '{"ok":true,"service":"artex","version":"dev"}';
      await service.start();
      expect(service.state.status, ArtexEngineStatus.running);
      expect(service.state.isRunning, isTrue);
      expect(service.state.canOpenWorkspace, isTrue);
    });

    test('启动中重复触发是空操作', () async {
      useTempProject();
      runner.script('docker', ok());
      service.debugHealthResponseOverride = () async =>
          '{"ok":true,"service":"artex"}';
      final f1 = service.start();
      final f2 = service.start();
      await Future.wait([f1, f2]);
      // info 只被调一次（第二次 start 直接返回）
      expect(runner.callsTo('docker').where((a) => a == 'info').length, 1);
    });

    test('门控拦截时给定向提示而不是泛泛超时', () async {
      useTempProject();
      runner
        ..script('docker', ok()) // info
        ..script('docker', ok()) // up -d
        ..script('docker', ok('nginx log line')); // logs --tail
      service.debugHealthResponseOverride = () async =>
          '<html><head><title>Welcome to nginx!</title></head></html>';
      await service.start();
      expect(service.state.failureKind, ArtexEngineFailureKind.gateBlocked);
      expect(service.state.failureDetail, contains('ARTEX_GATE'));
      expect(service.state.containerLogTail, contains('nginx log line'));
    });
  });

  group('停止（task 5.6）', () {
    test('stop 成功进入 stopped', () async {
      useTempProject();
      runner.script('docker', ok());
      await service.stop();
      expect(service.state.status, ArtexEngineStatus.stopped);
    });

    test('stop 失败上报而不是假装已停止', () async {
      useTempProject();
      runner.script('docker', fail('error while removing network'));
      await service.stop();
      expect(service.state.status, ArtexEngineStatus.failed);
      expect(service.state.failure, contains('停止失败'));
      expect(service.state.failureDetail, contains('error while removing'));
    });

    test('已是 stopped 时不再调 docker', () async {
      useTempProject();
      runner.script('docker', ok());
      await service.stop();
      final callsBefore = runner.calls.length;
      await service.stop();
      expect(runner.calls.length, callsBefore);
    });
  });

  group('退出处置（task 5.7 / spec 应用退出时的容器处置）', () {
    test('退出即停开启时停止容器', () async {
      useTempProject(stopOnAppExit: true);
      runner
        ..script('docker', ok())
        ..script('docker', ok())
        ..script('docker', ok());
      service.debugHealthResponseOverride = () async =>
          '{"service":"artex"}';
      await service.start();
      expect(service.state.isRunning, isTrue);
      await service.disposeOnExit();
      expect(service.state.status, ArtexEngineStatus.stopped);
    });

    test('退出即停关闭时不动容器', () async {
      useTempProject(stopOnAppExit: false);
      runner
        ..script('docker', ok())
        ..script('docker', ok());
      service.debugHealthResponseOverride = () async =>
          '{"service":"artex"}';
      await service.start();
      final callsBefore = runner.calls.length;
      await service.disposeOnExit();
      expect(runner.calls.length, callsBefore);
      expect(service.state.isRunning, isTrue);
    });

    test('清理抛异常不向外抛（MUST NOT block exit）', () async {
      useTempProject();
      ArtexConfigStore.instance.setConfigForTesting(
        ArtexEngineConfig(projectDir: tempDir.path),
      );
      runner
        ..script('docker', ok())
        ..script('docker', ok());
      service.debugHealthResponseOverride = () async =>
          '{"service":"artex"}';
      await service.start();
      runner.throwOnCall = StateError('docker died');
      await expectLater(service.disposeOnExit(), completes);
    });
  });

  group('compose 命令构造（design D1）', () {
    test('始终带上 override 文件', () {
      final args = service.debugComposeArgs('/proj', 'up', ['-d']);
      expect(args, contains('-f'));
      expect(args, contains('/proj/docker-compose.yml'));
      expect(args, contains('/proj/docker-compose.override.yml'));
      expect(args.first, 'compose');
      expect(args.last, '-d');
    });
  });
}
