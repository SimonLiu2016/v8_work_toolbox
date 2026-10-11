import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一次进程调用的结果快照。
class ArtexProcessResult {
  const ArtexProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;

  /// 合并输出。失败诊断的模式匹配要看全部输出——docker 的错误有时走
  /// stdout、有时走 stderr（design D4）。
  String get combined => '$stdout\n$stderr';
}

/// 进程执行器抽象。
///
/// **为什么要有这一层**：本服务的核心行为（端口冲突时不调 docker、HTML
/// 响应判未就绪、stop 失败要上报）都必须能在测试中驱动。直接
/// `Process.start` 的话这些场景无法验证，只能手工点。设计为窄接口，
/// 生产用 [RealProcessRunner]，测试注入记录型假实现。
abstract class ProcessRunner {
  /// 执行并等待结束。
  Future<ArtexProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  /// 启动并流式读取输出。[onLine] 在每条合并输出行上调用。
  ///
  /// 返回退出码。用于构建这类长任务的实时日志。
  Future<int> startStreaming(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    void Function(String line)? onLine,
  });
}

/// 真实进程执行器。
class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ArtexProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    try {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(timeout ?? const Duration(seconds: 30));
      return ArtexProcessResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on TimeoutException catch (_) {
      return const ArtexProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: '进程执行超时',
      );
    } on ProcessException catch (e) {
      // 命令不存在或无法启动。docker 未安装/未运行时走这里。
      return ArtexProcessResult(exitCode: -1, stdout: '', stderr: e.message);
    } on Object catch (e) {
      // 兜底：绝不把异常抛给 UI 层。
      return ArtexProcessResult(exitCode: -1, stdout: '', stderr: '$e');
    }
  }

  @override
  Future<int> startStreaming(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    void Function(String line)? onLine,
  }) async {
    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      );

      final done = <Future<void>>[
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) => onLine?.call(line)),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) => onLine?.call(line)),
      ];
      await Future.wait(done);
      return await process.exitCode;
    } on ProcessException catch (e) {
      onLine?.call('[启动失败] ${e.message}');
      return -1;
    }
  }
}

/// 测试用：记录调用并按脚本返回结果。
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner();

  final List<(String, List<String>)> calls = [];

  /// 按可执行文件名匹配的返回值队列；未匹配时返回成功空输出。
  final Map<String, List<ArtexProcessResult>> scripted = {};

  /// [startStreaming] 的模拟输出与退出码。
  final List<String> streamingLines = [];
  int streamingExitCode = 0;

  /// 抛出的异常（用于模拟 docker 完全不可用）。
  Object? throwOnCall;

  void script(String executable, ArtexProcessResult result) {
    scripted.putIfAbsent(executable, () => []).add(result);
  }

  List<String> callsTo(String executable) => calls
      .where((c) => c.$1 == executable)
      .map((c) => c.$2.join(' '))
      .toList();

  bool called(String executable) => calls.any((c) => c.$1 == executable);

  @override
  Future<ArtexProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add((executable, List.of(args)));
    if (throwOnCall != null) throw throwOnCall!;
    final queue = scripted[executable];
    if (queue == null || queue.isEmpty) {
      return const ArtexProcessResult(exitCode: 0, stdout: '', stderr: '');
    }
    return queue.removeAt(0);
  }

  @override
  Future<int> startStreaming(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    void Function(String line)? onLine,
  }) async {
    calls.add((executable, List.of(args)));
    for (final line in streamingLines) {
      onLine?.call(line);
    }
    return streamingExitCode;
  }
}

/// 供 [FakeProcessRunner] 与调试使用的日志开关。
///
/// 放在这里而不是 service 里，是因为 fake 需要在没有 Flutter 绑定的环境
/// （纯 dart 测试）下也能编译。
void artexDebugLog(String message) => debugPrint(message);
