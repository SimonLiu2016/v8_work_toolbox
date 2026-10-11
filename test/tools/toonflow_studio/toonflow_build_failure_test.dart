import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/models/toonflow_studio_config.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/models/toonflow_studio_state.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/process_runner.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_config_store.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_image_build_service.dart';

/// 构建失败诊断的匹配表（spec: 镜像构建入口与失败诊断）。
///
/// 这些用例里的字符串**不是编的**——来自 2026-10-11 spike 的真实输出或
/// docker 的标准错误文案。测试为验证诊断逻辑，不为适配实现。
void main() {
  group('已知失败模式各归其类', () {
    test('Docker 守护进程不可达', () {
      const out =
          'Cannot connect to the Docker daemon at unix:///Users/simon/.docker/run/docker.sock. '
          'Is the docker daemon running?';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.dockerUnavailable);
      expect(
        ToonflowBuildFailureKind.dockerUnavailable.hint,
        contains('Docker Desktop'),
      );
    });

    test('镜像源解析失败（spike 真实遇到）', () {
      const out =
          'failed to solve: oven/bun:1.3.14: failed to resolve source metadata for docker.io/oven/bun:1.3.14: '
          'failed to do request: Head "https://registry-1.docker.io/v2/oven/bun/manifests/1.3.14": EOF';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.registryBlocked);
      expect(
        ToonflowBuildFailureKind.registryBlocked.hint,
        contains('registry-mirrors'),
      );
    });

    test('镜像源 403', () {
      const out = 'failed to solve: failed to resolve source metadata: 403 Forbidden';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.registryBlocked);
    });

    test('TLS 握手超时判为网络不通', () {
      const out =
          'Error response from daemon: Get "https://registry-1.docker.io/v2/": net/http: TLS handshake timeout';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.networkTimeout);
    });

    test('bun 锁文件不匹配', () {
      const out =
          '#9 [5/6] RUN bun install --frozen-lockfile\n'
          '#9 7.412 error: lockfile had changes, but lockfile is frozen';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.lockfileMismatch);
      expect(
        ToonflowBuildFailureKind.lockfileMismatch.hint,
        contains('bun install'),
      );
    });

    test('无法识别的失败回退 unknown', () {
      expect(
        classifyBuildFailure('some totally unexpected failure text'),
        ToonflowBuildFailureKind.unknown,
      );
    });

    test('镜像源特征优先于宽泛的网络特征', () {
      // 这条同时含 'failed to resolve source metadata' 与 'tls handshake
      // timeout'。前者更具体（改镜像源），后者只让用户开 VPN——必须判成前者。
      const out =
          'failed to solve: failed to resolve source metadata for docker.io/library/alpine\n'
          'net/http: TLS handshake timeout';
      expect(classifyBuildFailure(out), ToonflowBuildFailureKind.registryBlocked);
    });
  });

  group('build() 流程', () {
    late Directory tempDir;
    late Directory projectDir;
    late ToonflowFakeProcessRunner runner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tf_build');
      AppPaths.overrideRootForTesting(tempDir);
      projectDir = Directory(p.join(tempDir.path, 'Toonflow-app'))
        ..createSync(recursive: true);
      File(p.join(projectDir.path, 'compose.yaml')).writeAsStringSync('services: {}\n');
      File(p.join(projectDir.path, 'Dockerfile')).writeAsStringSync('FROM alpine\n');
      runner = ToonflowFakeProcessRunner();
      ToonflowConfigStore.instance.resetForTesting();
      ToonflowConfigStore.instance.setConfigForTesting(
        ToonflowStudioConfig(projectDir: projectDir.path),
      );
    });

    tearDown(() {
      ToonflowConfigStore.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('工程缺失时不启动构建', () async {
      ToonflowConfigStore.instance.setConfigForTesting(
        const ToonflowStudioConfig(projectDir: '/nonexistent'),
      );
      final service = ToonflowImageBuildService(runner: runner);
      final result = await service.build();
      expect(result.success, isFalse);
      expect(result.failureKind, ToonflowBuildFailureKind.projectNotFound);
      expect(runner.called('docker'), isFalse);
    });

    test('构建命令带上 compose 文件与 override', () async {
      final service = ToonflowImageBuildService(runner: runner);
      await service.build();
      // callsTo 返回的是 join 后的整条命令行。
      final args = runner.callsTo('docker').single;
      expect(args, contains('compose'));
      expect(args, contains('build'));
      expect(args, contains('compose.yaml'));
      expect(args, contains('docker-compose.override.yml'));
    });

    test('流式日志逐行透出', () async {
      runner.streamingLines = ['#1 [2/6] RUN apt-get update', '#1 DONE 0.0s'];
      final service = ToonflowImageBuildService(runner: runner);
      final seen = <String>[];
      await service.build(onLine: seen.add);
      expect(seen, hasLength(2));
      expect(service.lines, hasLength(2));
    });

    test('退出码非 0 时分类失败并附日志', () async {
      runner.streamingExitCode = 1;
      runner.streamingLines = ['#9 ERROR: TLS handshake timeout'];
      final service = ToonflowImageBuildService(runner: runner);
      final result = await service.build();
      expect(result.success, isFalse);
      expect(result.failureKind, ToonflowBuildFailureKind.networkTimeout);
      expect(result.logTail, isNotEmpty);
    });

    test('构建期间重复触发复用同一次 Future（不并发跑两个 build）', () async {
      final service = ToonflowImageBuildService(runner: runner);
      final first = service.build();
      final second = service.build();
      expect(identical(first, second), isTrue,
          reason: '两个 docker compose build 会互抢 buildkit 的锁');
      await first;
    });

    test('isBuilding 在构建期间为 true，结束后回 false', () async {
      runner.streamingLines = ['line'];
      final service = ToonflowImageBuildService(runner: runner);
      final future = service.build();
      expect(service.isBuilding, isTrue);
      await future;
      expect(service.isBuilding, isFalse);
    });
  });
}
