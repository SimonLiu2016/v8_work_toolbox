import 'dart:io';
import 'package:flutter/services.dart';

/// 系统级原生桥接服务
class SystemService {
  SystemService._();
  static final SystemService instance = SystemService._();

  static const MethodChannel _channel = MethodChannel('app_manager_channel');

  /// 将指定路径集合安全移至 macOS 系统废纸篓 (可撤回)
  /// 优先使用原生 API，失败时回退到 osascript (AppleScript)
  Future<bool> recyclePaths(List<String> paths) async {
    if (paths.isEmpty) return true;

    // 方式 1: 原生 NSWorkspace.shared.recycle (需要 Full Disk Access)
    try {
      if (Platform.isMacOS) {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'recyclePaths',
          {'paths': paths},
        );
        if (result?['success'] == true) return true;
      }
    } catch (_) {}

    // 方式 2: osascript 兜底 (继承终端权限，无需 Full Disk Access)
    try {
      if (Platform.isMacOS) {
        // 构建 AppleScript：将每个文件移至废纸篓
        final posixPaths = paths.map((p) => '"$p"').join(', ');
        final script = '''
          tell application "Finder"
            repeat with p in {$posixPaths}
              try
                move (POSIX file p as alias) to trash
              end try
            end repeat
          end tell
        ''';
        final result = await Process.run('osascript', ['-e', script]);
        return result.exitCode == 0;
      }
    } catch (_) {}

    return false;
  }

  /// 获取主系统磁盘的总容量与可用容量 (字节)
  Future<DiskSpaceInfo> getRootDiskSpace() async {
    try {
      if (Platform.isMacOS) {
        final res = await Process.run('df', ['-k', '/']);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            // Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final totalKb = int.tryParse(parts[1]) ?? 0;
              final freeKb = int.tryParse(parts[3]) ?? 0;
              return DiskSpaceInfo(
                totalBytes: totalKb * 1024,
                freeBytes: freeKb * 1024,
              );
            }
          }
        }
      }
    } catch (_) {}

    return const DiskSpaceInfo(totalBytes: 0, freeBytes: 0);
  }
}

class DiskSpaceInfo {
  final int totalBytes;
  final int freeBytes;

  const DiskSpaceInfo({required this.totalBytes, required this.freeBytes});

  int get usedBytes => (totalBytes > freeBytes) ? (totalBytes - freeBytes) : 0;
  double get usedPercentage => totalBytes > 0 ? (usedBytes / totalBytes) : 0.0;
}
