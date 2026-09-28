import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';

/// GitLab 请求日志的文件落盘。
///
/// **为什么不用 `debugPrint` + `kDebugMode`**：tree 列举曾出现「curl 同一 URL
/// 得 100 条、app 得 4 条」的无法解释差异，需要 app 自己说出实情；而 `kDebugMode`
/// 是编译期常量，release 包里这些日志根本不存在——等于在最需要它们的场合失效。
/// debugPrint 还有第二个问题：它的输出落在 stderr，而 app 从 Dock / Finder 启动时
/// stderr 的去向对用户不可见，从命令行启动又与真实使用方式不一致。
///
/// 写文件这两种都不依赖：无论构建模式、无论由谁启动，日志始终在同一个位置：
///
/// ```
/// ~/Library/Application Support/V8WorkToolbox/logs/ops_gitlab.log
/// ```
///
/// 敏感值不进日志：`PRIVATE-TOKEN` 只记前 6 位与长度。
class OpsGitLabLog {
  OpsGitLabLog._();
  static final OpsGitLabLog instance = OpsGitLabLog._();

  static const String fileName = 'ops_gitlab.log';
  static const int maxBytes = 4 * 1024 * 1024; // 4MB 后截断，避免无限增长

  File? _file;
  final List<String> _pending = [];
  bool _failed = false;
  Future<void> _drain = Future.value();

  /// 目录覆写（测试用）。为 null 时走 `AppPaths.logsDir`。
  @visibleForTesting
  Directory? debugOverrideDir;

  Future<File> _ensureFile() async {
    final existing = _file;
    if (existing != null) return existing;

    final dir = debugOverrideDir ?? AppPaths.logsDir;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(dir.path, fileName));
    if (file.existsSync() && file.lengthSync() > maxBytes) {
      // 超限时保留头部一份副本后清空重写，避免无限增长也避免直接丢历史。
      try {
        file.copySync('${file.path}.1');
        file.writeAsStringSync('');
      } catch (_) {}
    }
    _file = file;
    return file;
  }

  /// 异步追加一行日志。失败只静默降级——日志不能影响主流程。
  void write(String message) {
    if (_failed) return;
    final stamp = DateTime.now().toIso8601String();
    _pending.add('[$stamp] $message');
    _drain = _drain.then((_) => _flush()).catchError((_) {});
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    try {
      final file = await _ensureFile();
      final lines = List<String>.from(_pending);
      _pending.clear();
      final sink = file.openWrite(mode: FileMode.append);
      for (final l in lines) {
        sink.writeln(l);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // 磁盘满 / 权限拒绝都不该让运维操作失败。
      _failed = true;
      _pending.clear();
    }
  }

  /// 仅供测试：把挂起的写入立即落盘。
  @visibleForTesting
  Future<void> flushForTesting() => _flush();
}
