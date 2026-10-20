import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_config.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/models/infinite_canvas_state.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_config_store.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_image_build_service.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_override_store.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/process_runner.dart';

/// 构建失败诊断的匹配表（spec: 镜像入口与失败诊断）。
///
/// 这些用例里的字符串**不是编的**——来自 2026-10-11 spike 的真实输出或
/// docker 的标准错误文案。测试为验证诊断逻辑，不为适配实现。
void main() {
  group('已知失败模式各归其类', () {
    test('Docker 守护进程不可达', () {
      const out =
          'Cannot connect to the Docker daemon at unix:///Users/simon/.docker/run/docker.sock. '
          'Is the docker daemon running?';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.dockerUnavailable,
      );
      expect(
        InfiniteCanvasBuildFailureKind.dockerUnavailable.hint,
        contains('Docker Desktop'),
      );
    });

    test('镜像源解析失败（spike 真实遇到）', () {
      const out =
          'failed to solve: nginx:1.27-alpine: failed to resolve source metadata for docker.io/library/nginx:1.27-alpine: '
          'failed to do request: Head "https://registry-1.docker.io/v2/library/nginx/manifests/1.27-alpine": EOF';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.registryBlocked,
      );
      expect(
        InfiniteCanvasBuildFailureKind.registryBlocked.hint,
        contains('registry-mirrors'),
      );
    });

    test('镜像源 403', () {
      const out =
          'failed to solve: failed to resolve source metadata: 403 Forbidden';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.registryBlocked,
      );
    });

    test('TLS 握手超时判为网络不通', () {
      const out =
          'Error response from daemon: Get "https://registry-1.docker.io/v2/": net/http: TLS handshake timeout';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.networkTimeout,
      );
    });

    test('构建上下文缺失', () {
      // 本地没有 web/ 时 Dockerfile 的 COPY 会失败。
      const out =
          '#5 [2/4] COPY web/package.json web/bun.lock ./\n'
          '#5 ERROR: COPY failed: file not found in build context';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.missingContext,
      );
      expect(
        InfiniteCanvasBuildFailureKind.missingContext.hint,
        contains('ghcr.io'),
        reason: '要告诉用户默认路径不需要本地构建',
      );
    });

    test('不再有 bun 锁文件这一类', () {
      // 上游 Dockerfile 用 bun，但本地构建只是可选路径；命中它也只该落到
      // 宽泛类别，不该再给「去跑 bun install」的误导性提示。
      // lockfileMismatch 这个枚举值已随 bunRegistry 配置一起删除。
      const out =
          '#9 [5/6] RUN bun install --frozen-lockfile\n'
          '#9 7.412 error: lockfile had changes, but lockfile is frozen';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.unknown,
      );
    });

    test('无法识别的失败回退 unknown', () {
      expect(
        classifyBuildFailure('some totally unexpected failure text'),
        InfiniteCanvasBuildFailureKind.unknown,
      );
    });

    test('镜像源特征优先于宽泛的网络特征', () {
      // 这条同时含 'failed to resolve source metadata' 与 'tls handshake
      // timeout'。前者更具体（改镜像源），后者只让用户开 VPN——必须判成前者。
      const out =
          'failed to solve: failed to resolve source metadata for docker.io/library/alpine\n'
          'net/http: TLS handshake timeout';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.registryBlocked,
      );
    });

    test('具体特征优先于构建上下文缺失', () {
      // 'not found' 是很宽泛的字符串，pull access denied 必须排在它前面。
      final out =
          'ERROR: pull access denied for infinite-canvas, repository does not exist';
      expect(
        classifyBuildFailure(out),
        InfiniteCanvasBuildFailureKind.registryBlocked,
      );
    });
  });

  group('build() 流程', () {
    late Directory tempDir;
    late Directory projectDir;
    late InfiniteCanvasFakeProcessRunner runner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ic_build');
      AppPaths.overrideRootForTesting(tempDir);
      projectDir = Directory(p.join(tempDir.path, 'infinite-canvas'))
        ..createSync(recursive: true);
      // 上游实际给的是 docker-compose.yml。
      File(
        p.join(projectDir.path, 'docker-compose.yml'),
      ).writeAsStringSync('services: {}\n');
      File(
        p.join(projectDir.path, 'Dockerfile'),
      ).writeAsStringSync('FROM nginx:1.27-alpine\n');
      runner = InfiniteCanvasFakeProcessRunner();
      InfiniteCanvasConfigStore.instance.resetForTesting();
      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        InfiniteCanvasConfig(projectDir: projectDir.path),
      );
    });

    tearDown(() {
      InfiniteCanvasConfigStore.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('工程缺失时不启动构建', () async {
      InfiniteCanvasConfigStore.instance.setConfigForTesting(
        const InfiniteCanvasConfig(projectDir: '/nonexistent'),
      );
      final service = InfiniteCanvasImageBuildService(runner: runner);
      final result = await service.build();
      expect(result.success, isFalse);
      expect(
        result.failureKind,
        InfiniteCanvasBuildFailureKind.projectNotFound,
      );
      expect(runner.called('docker'), isFalse);
    });

    test('构建命令带上探测到的 compose 文件与 override', () async {
      final service = InfiniteCanvasImageBuildService(runner: runner);
      await service.build();
      final args = runner.callsTo('docker').single;
      expect(args, contains('compose'));
      expect(args, contains('build'));
      expect(args, contains('docker-compose.yml'));
      expect(args, contains(kOverrideFileName));
    });

    test('构建不再注入 bun 镜像站环境变量', () async {
      // Toonflow 版要注入 BUN_CONFIG_REGISTRY；这里没有 bunRegistry 配置项。
      final service = InfiniteCanvasImageBuildService(runner: runner);
      await service.build();
      final envless = runner.calls;
      expect(envless, isNotEmpty);
      expect(
        InfiniteCanvasConfigStore.instance.config.toJson().containsKey(
          'bunRegistry',
        ),
        isFalse,
        reason: '配置里不该再有 bun 镜像站',
      );
    });

    test('流式日志逐行透出', () async {
      runner.streamingLines = ['#1 [2/4] RUN bun install', '#1 DONE 0.0s'];
      final service = InfiniteCanvasImageBuildService(runner: runner);
      final seen = <String>[];
      await service.build(onLine: seen.add);
      expect(seen, hasLength(2));
      expect(service.lines, hasLength(2));
    });

    test('退出码非 0 时分类失败并附日志', () async {
      runner.streamingExitCode = 1;
      runner.streamingLines = ['#9 ERROR: TLS handshake timeout'];
      final service = InfiniteCanvasImageBuildService(runner: runner);
      final result = await service.build();
      expect(result.success, isFalse);
      expect(
        result.failureKind,
        InfiniteCanvasBuildFailureKind.networkTimeout,
      );
      expect(result.logTail, isNotEmpty);
    });

    test('构建期间重复触发复用同一次 Future（不并发跑两个 build）', () async {
      final service = InfiniteCanvasImageBuildService(runner: runner);
      final first = service.build();
      final second = service.build();
      expect(
        identical(first, second),
        isTrue,
        reason: '两个 docker compose build 会互抢 buildkit 的锁',
      );
      await first;
    });

    test('isBuilding 在构建期间为 true，结束后回 false', () async {
      runner.streamingLines = ['line'];
      final service = InfiniteCanvasImageBuildService(runner: runner);
      final future = service.build();
      expect(service.isBuilding, isTrue);
      await future;
      expect(service.isBuilding, isFalse);
    });
  });
}
