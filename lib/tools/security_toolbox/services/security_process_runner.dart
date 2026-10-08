/// 进程执行与 PATH 解析的公共工具。
///
/// Homebrew 的可执行文件在 Apple Silicon 上落在 `/opt/homebrew/bin`、Intel 上落在
/// `/usr/local/bin`，而 GUI 应用继承的 PATH 通常只有 `/usr/bin:/bin`——直接用
/// `Process.run('nmap')` 会稳定地 "command not found"，而错误信息读起来像是
/// 工具没装。这里把所有受管工具的调用统一收口：先按清单找到绝对路径，找不到再
/// 回落到裸名，让上层拿到的是工具真实的存在性结论。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// GUI 应用 PATH 里常见的可执行目录（不含 Homebrew）。
const List<String> kSystemBinDirs = ['/usr/bin', '/bin', '/usr/sbin', '/sbin'];

/// Homebrew 的默认前缀，按架构排列。
const List<String> kBrewBinDirs = ['/opt/homebrew/bin', '/usr/local/bin'];

/// 用户主目录下的常见 CLI 工具安装目录（pipx, cargo 等）。
List<String> get kUserBinDirs {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return const [];
  return [
    p.join(home, '.local', 'bin'),
    p.join(home, 'bin'),
    p.join(home, '.cargo', 'bin'),
  ];
}

/// 官方独立安装包常见安全框架与套件目录（如 Metasploit Framework）。
const List<String> kSecurityAppBinDirs = [
  '/opt/metasploit-framework/bin',
  '/opt/metasploit-framework/embedded/bin',
];

/// 给子进程用的 PATH：系统目录 + Homebrew 目录 + 用户目录 + 安全框架目录 + 继承值。
String get augmentedPath {
  final inherited = Platform.environment['PATH'] ?? '';
  final parts = <String>{
    ...kSystemBinDirs,
    ...kBrewBinDirs,
    ...kUserBinDirs,
    ...kSecurityAppBinDirs,
    ...inherited.split(':').where((s) => s.isNotEmpty),
  };
  return parts.join(':');
}

/// 子进程环境变量：PATH 加固 + UTF-8 强制 + Homebrew 自动化保护。
///
/// 不对的工具 locale 会让 nuclei/sqlmap 输出非 UTF-8 字节，`utf8.decoder` 直接抛
/// 异常把流打断，所以显式钉住。
/// 注入 HOMEBREW_NO_AUTO_UPDATE 与 NONINTERACTIVE 避免 brew 在子进程中长时间自动更新或挂起等待输入。
Map<String, String> get processEnvironment => {
  ...Platform.environment,
  'PATH': augmentedPath,
  'LC_ALL': 'en_US.UTF-8',
  'LANG': 'en_US.UTF-8',
  'HOMEBREW_NO_AUTO_UPDATE': '1',
  'NONINTERACTIVE': '1',
  'HOMEBREW_NO_INSTALL_CLEANUP': '1',
};

/// 解析可执行文件的绝对路径；找不到返回 null。
String? resolveExecutable(String executable) {
  // 已是绝对/相对路径（含目录分隔符）时不参与 PATH 搜索。
  if (p.isAbsolute(executable) || executable.contains('/')) {
    return File(executable).existsSync() ? executable : null;
  }
  for (final dir in [
    ...kBrewBinDirs,
    ...kUserBinDirs,
    ...kSecurityAppBinDirs,
    ...kSystemBinDirs,
  ]) {
    final candidate = p.join(dir, executable);
    if (File(candidate).existsSync()) return candidate;
  }
  final inherited = Platform.environment['PATH'] ?? '';
  for (final dir in inherited.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, executable);
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// 启动子进程并收集全部 stdout/stderr，带超时。
///
/// 超时不抛异常——返回 `timedOut: true` 与已捕获的部分输出；进程被 kill，
/// 否则 `which` 卡死时会挂住整个状态探测。
class ProcessResult2 {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const ProcessResult2({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  bool get success => !timedOut && exitCode == 0;
}

/// 启动并等待结束。
Future<ProcessResult2> runCaptured(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(seconds: 20),
  String? workingDirectory,
}) async {
  final resolved = resolveExecutable(executable) ?? executable;
  try {
    final process = await Process.start(
      resolved,
      args,
      workingDirectory: workingDirectory,
      environment: processEnvironment,
      includeParentEnvironment: false,
    );
    // 立即向标准输入发送 EOF 并关闭，避免交互式 CLI 挂起等待键盘输入
    try {
      await process.stdin.close();
    } catch (_) {}
    final outBuf = StringBuffer();
    final errBuf = StringBuffer();
    final outDone = process.stdout
        .transform(utf8.decoder)
        .listen(outBuf.write)
        .asFuture<void>();
    final errDone = process.stderr
        .transform(utf8.decoder)
        .listen(errBuf.write)
        .asFuture<void>();

    var timedOut = false;
    final exitCode = await process.exitCode
        .timeout(
          timeout,
          onTimeout: () {
            timedOut = true;
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        )
        // 被 kill 的进程可能永远不关流；最多再等 2 秒就拿已捕获的部分返回。
        .then((code) async {
          await Future.wait([outDone, errDone]).timeout(
            const Duration(seconds: 2),
            onTimeout: () => <void>[],
          );
          return code;
        });
    return ProcessResult2(
      exitCode: exitCode,
      stdout: outBuf.toString(),
      stderr: errBuf.toString(),
      timedOut: timedOut,
    );
  } on ProcessException catch (e) {
    // 可执行文件不存在（沙盒/权限/路径）——对调用方表现为一次失败的探测。
    return ProcessResult2(
      exitCode: 127,
      stdout: '',
      stderr: e.message,
    );
  }
}
