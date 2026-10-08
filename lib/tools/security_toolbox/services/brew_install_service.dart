/// Homebrew 安装/更新与 nuclei 模板管理。
///
/// 安装是一次可能跑几分钟的长进程，所以做成流式：每条日志 emit 一次，UI 直接
/// 订阅。同时只允许一个安装在进行中——并发两个 `brew install` 会互相抢
/// Homebrew 的锁，报出来的错很难读。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'security_process_runner.dart';
import 'security_tool_registry.dart';
import 'tool_status_checker.dart';

/// 一次安装任务的状态。
enum InstallPhase { idle, running, succeeded, failed, cancelled }

class InstallProgress {
  final String toolId;
  final InstallPhase phase;

  /// 已收集的日志行（最新在末尾）。
  final List<String> lines;

  /// 失败原因。
  final String? error;

  const InstallProgress({
    required this.toolId,
    required this.phase,
    this.lines = const [],
    this.error,
  });

  const InstallProgress.idle(this.toolId)
    : phase = InstallPhase.idle,
      lines = const [],
      error = null;

  String get logText => lines.join('\n');
}

/// nuclei 模板库状态。
class NucleiTemplateState {
  final bool installed;
  final int templateCount;
  final DateTime? lastUpdated;
  final bool updating;

  const NucleiTemplateState({
    required this.installed,
    required this.templateCount,
    this.lastUpdated,
    this.updating = false,
  });

  static const empty = NucleiTemplateState(
    installed: false,
    templateCount: 0,
  );
}

class BrewInstallService {
  BrewInstallService._();
  static final BrewInstallService instance = BrewInstallService._();

  final _progressController = StreamController<InstallProgress>.broadcast();
  Stream<InstallProgress> get progress => _progressController.stream;

  final _templateController = StreamController<NucleiTemplateState>.broadcast();
  Stream<NucleiTemplateState> get templates => _templateController.stream;

  Process? _current;
  bool _running = false;
  bool get isRunning => _running;

  NucleiTemplateState _templateState = NucleiTemplateState.empty;

  void dispose() {
    _current?.kill(ProcessSignal.sigterm);
    _progressController.close();
    _templateController.close();
  }

  /// 安装或更新单个工具。
  ///
  /// [upgrade] 为 true 时用 `brew upgrade`。返回是否成功。
  Future<bool> install(
    SecurityTool tool, {
    bool upgrade = false,
    void Function(String line)? onLog,
  }) async {
    if (_running) {
      const msg = '另一个安装任务正在进行中，请稍候';
      onLog?.call(msg);
      _emit(
        InstallProgress(
          toolId: tool.id,
          phase: InstallPhase.failed,
          lines: const [msg],
          error: 'busy',
        ),
      );
      return false;
    }

    // 1. 检查是否为需手动安装的工具
    if (tool.installMethod == InstallMethod.manual) {
      final note = tool.installNote ?? '该工具需手动安装';
      onLog?.call('⚠️ ${tool.displayName}：$note');
      if (tool.manualInstallUrl != null) {
        onLog?.call('👉 官方安装指引：${tool.manualInstallUrl}');
      }
      _emit(
        InstallProgress(
          toolId: tool.id,
          phase: InstallPhase.failed,
          lines: [note],
          error: 'manual-install-required',
        ),
      );
      return false;
    }

    // 2. 检查安装渠道环境（pipx 或 Homebrew）
    final String executable;
    final List<String> args;

    if (tool.installMethod == InstallMethod.pipx) {
      final pipxPath = resolveExecutable('pipx');
      if (pipxPath == null) {
        const msg = '未检测到 pipx。请在终端执行 `brew install pipx` 安装后再试';
        onLog?.call('✗ ${tool.displayName}：$msg');
        _emit(
          InstallProgress(
            toolId: tool.id,
            phase: InstallPhase.failed,
            lines: const [msg],
            error: 'pipx-missing',
          ),
        );
        return false;
      }
      executable = pipxPath;
      final pkg = tool.pipxPackage ?? tool.executable;
      args = ['install', pkg];
    } else {
      if (!await HomebrewDetector.isAvailable()) {
        final msg = '未检测到 Homebrew，请先访问 ${HomebrewDetector.installUrl} 安装';
        onLog?.call(msg);
        _emit(
          InstallProgress(
            toolId: tool.id,
            phase: InstallPhase.failed,
            lines: [msg],
            error: 'brew-missing',
          ),
        );
        return false;
      }
      executable = resolveExecutable('brew') ?? 'brew';
      args = upgrade
          ? ['upgrade', tool.brewName]
          : ['install', tool.brewName];
    }

    _running = true;
    final lines = <String>[];
    _emit(InstallProgress(toolId: tool.id, phase: InstallPhase.running));

    try {
      if (tool.installNote != null) {
        onLog?.call('ℹ️ 提示: ${tool.installNote}');
      }
      final cmdLine = '\$ $executable ${args.join(' ')}';
      lines.add(cmdLine);
      onLog?.call(cmdLine);
      _emit(
        InstallProgress(
          toolId: tool.id,
          phase: InstallPhase.running,
          lines: List.of(lines),
        ),
      );

      final process = await Process.start(
        executable,
        args,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      _current = process;

      // 立即关闭标准输入（EOF），防止 Homebrew/交互工具在后台无限期等待 [y/n]
      try {
        await process.stdin.close();
      } catch (_) {}

      final done = <Future>[
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              lines.add(line);
              onLog?.call(line);
              _emit(
                InstallProgress(
                  toolId: tool.id,
                  phase: InstallPhase.running,
                  lines: List.of(lines),
                ),
              );
            })
            .asFuture<void>(),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              lines.add(line);
              onLog?.call(line);
              _emit(
                InstallProgress(
                  toolId: tool.id,
                  phase: InstallPhase.running,
                  lines: List.of(lines),
                ),
              );
            })
            .asFuture<void>(),
      ];

      // 编译/下载大包过程可能耗时较长，等待退出
      final code = await process.exitCode;
      await Future.wait(done);
      final ok = code == 0;

      if (ok) {
        onLog?.call('✓ ${tool.displayName} 安装完成');
      } else {
        final diag = _extractDiagnosis(lines);
        final finishMsg = diag != null
            ? '✗ ${tool.displayName} 安装失败（exit code $code）：$diag'
            : '✗ ${tool.displayName} 安装失败（exit code $code）';
        onLog?.call(finishMsg);
      }

      _emit(
        InstallProgress(
          toolId: tool.id,
          phase: ok ? InstallPhase.succeeded : InstallPhase.failed,
          lines: List.of(lines),
          error: ok ? null : 'exit code $code',
        ),
      );
      return ok;
    } catch (e) {
      final err = '启动失败: $e';
      onLog?.call(err);
      _emit(
        InstallProgress(
          toolId: tool.id,
          phase: InstallPhase.failed,
          lines: List.of(lines)..add(err),
          error: e.toString(),
        ),
      );
      return false;
    } finally {
      _current = null;
      _running = false;
    }
  }

  /// 从错误日志中提取关键排查提示。
  static String? _extractDiagnosis(List<String> lines) {
    for (final line in lines.reversed) {
      if (line.contains('No available formula with the name')) {
        return 'Homebrew 官方仓库无此 formula';
      }
      if (line.contains('already locked')) {
        return '检测到并发下载锁冲突，请等待其他后台下载任务完成';
      }
      if (line.contains('disabled because')) {
        return '该软件包因安全或系统兼容性原因已被官方禁用';
      }
      if (line.contains('Error:')) {
        return line.trim();
      }
    }
    return null;
  }

  /// 依次安装所有未就绪工具（spec 的「一键安装全部」）。
  ///
  /// 返回成功安装的数量。自动跳过手动安装项。
  Future<int> installAllMissing(
    Map<String, ToolProbe> probes, {
    List<SecurityTool>? tools,
    void Function(String line)? onLog,
    Future<void> Function(SecurityTool tool, bool success, int current, int total)? onToolFinished,
  }) async {
    final missing = (tools ?? SecurityToolRegistry.tools)
        .where((t) => !(probes[t.id]?.isReady ?? false))
        .toList();
    if (missing.isEmpty) {
      onLog?.call('所有受管工具均已就绪，无需安装。');
      return 0;
    }

    final manualList = missing.where((t) => t.installMethod == InstallMethod.manual).toList();
    final autoList = missing.where((t) => t.installMethod != InstallMethod.manual).toList();

    if (autoList.isEmpty) {
      onLog?.call('待安装工具均为手动安装项（${manualList.map((t) => t.displayName).join('、')}），请参考对应安装指引。');
      return 0;
    }

    onLog?.call('═══ 开始一键安装，共需处理 ${autoList.length} 个工具 ═══');
    if (manualList.isNotEmpty) {
      onLog?.call('（已跳过需手动安装的工具：${manualList.map((t) => t.displayName).join('、')}）');
    }

    var succeeded = 0;
    var failed = 0;
    for (var i = 0; i < autoList.length; i++) {
      final tool = autoList[i];
      final channelLabel = tool.installMethod == InstallMethod.pipx
          ? 'pipx ${tool.pipxPackage ?? tool.executable}'
          : 'brew ${tool.brewName}';
      onLog?.call('\n[${i + 1}/${autoList.length}] 正在安装 ${tool.displayName}（$channelLabel）…');
      final ok = await install(tool, onLog: onLog);
      if (ok) {
        succeeded++;
      } else {
        failed++;
      }
      if (onToolFinished != null) {
        await onToolFinished(tool, ok, i + 1, autoList.length);
      }
    }

    if (failed == 0) {
      onLog?.call('\n✓ ═══ 批量安装完成：全部 $succeeded 个工具均已安装就绪 ═══');
    } else {
      onLog?.call('\n⚠️ ═══ 批量安装结束：$succeeded 个成功，$failed 个失败。请查看上方日志排查原因 ═══');
    }
    return succeeded;
  }

  /// 取消当前安装。
  void cancel() {
    _current?.kill(ProcessSignal.sigterm);
  }

  /// 检测本地 nuclei 模板目录。
  ///
  /// nuclei 的模板默认在 `~/nuclei-templates`（或 `$HOME/.local/nuclei-templates`）。
  Future<NucleiTemplateState> detectTemplates() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/nuclei-templates',
      '$home/.local/nuclei-templates',
      '$home/Library/Application Support/nuclei/nuclei-templates',
    ];
    for (final dir in candidates) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      final count = await _countYaml(d);
      final state = NucleiTemplateState(
        installed: count > 0,
        templateCount: count,
        lastUpdated: _lastModified(d),
      );
      _templateState = state;
      _templateController.add(state);
      return state;
    }
    _templateState = const NucleiTemplateState(installed: false, templateCount: 0);
    _templateController.add(_templateState);
    return _templateState;
  }

  /// 触发 `nuclei -update-templates`，流式进度通过 [templates] 广播。
  Future<bool> updateTemplates({void Function(String line)? onLog}) async {
    if (resolveExecutable('nuclei') == null) {
      onLog?.call('未检测到 nuclei，请先安装 nuclei');
      return false;
    }
    _templateState = NucleiTemplateState(
      installed: _templateState.installed,
      templateCount: _templateState.templateCount,
      lastUpdated: _templateState.lastUpdated,
      updating: true,
    );
    _templateController.add(_templateState);
    onLog?.call('开始更新 nuclei 模板库：\$ nuclei -update-templates…');

    final lines = <String>[];
    try {
      final nuclei = resolveExecutable('nuclei') ?? 'nuclei';
      final process = await Process.start(
        nuclei,
        ['-update-templates'],
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      _current = process;
      await Future.wait([
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((l) {
              lines.add(l);
              onLog?.call(l);
            })
            .asFuture<void>(),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((l) {
              lines.add(l);
              onLog?.call(l);
            })
            .asFuture<void>(),
      ]);
      final ok = (await process.exitCode) == 0;
      if (ok) {
        final res = (await detectTemplates()).installed;
        onLog?.call('✓ nuclei 模板库更新完成（当前 ${_templateState.templateCount} 个模板）');
        return res;
      }
      onLog?.call('✗ nuclei 模板库更新失败');
      return false;
    } catch (e) {
      onLog?.call('更新模板库异常: $e');
      return false;
    } finally {
      _current = null;
      _templateState = NucleiTemplateState(
        installed: _templateState.installed,
        templateCount: _templateState.templateCount,
        lastUpdated: DateTime.now(),
        updating: false,
      );
      _templateController.add(_templateState);
    }
  }

  Future<int> _countYaml(Directory dir) async {
    var count = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            (entity.path.endsWith('.yaml') || entity.path.endsWith('.yml'))) {
          count++;
        }
      }
    } catch (_) {
      // 遍历被中断时已计数的部分仍然有效。
    }
    return count;
  }

  DateTime? _lastModified(Directory dir) {
    try {
      return dir.statSync().modified;
    } catch (_) {
      return null;
    }
  }

  void _emit(InstallProgress p) => _progressController.add(p);
}

