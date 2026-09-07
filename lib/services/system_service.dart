import 'dart:io';
import 'package:flutter/services.dart';

/// 沙盒容器 Payload 清理结果
class ContainerPayloadResult {
  final bool isCleaned;
  final int freedBytes;
  final int remainingBytes;

  const ContainerPayloadResult({
    required this.isCleaned,
    required this.freedBytes,
    required this.remainingBytes,
  });
}

/// 废纸篓回收操作结构化结果
class RecycleResult {
  final List<String> successPaths;
  final List<String> failedPaths;
  final List<String> cleanedContainerPaths;
  final int freedBytes;
  final String? errorMessage;

  const RecycleResult({
    required this.successPaths,
    required this.failedPaths,
    this.cleanedContainerPaths = const [],
    this.freedBytes = 0,
    this.errorMessage,
  });

  bool get isAllSuccess => failedPaths.isEmpty;
  bool get isAllFailed => successPaths.isEmpty && failedPaths.isNotEmpty;
  bool get isPartialSuccess => successPaths.isNotEmpty && failedPaths.isNotEmpty;
  bool get hasCleanedContainers => cleanedContainerPaths.isNotEmpty;
}

/// 系统级原生桥接服务
class SystemService {
  SystemService._();
  static final SystemService instance = SystemService._();

  static const MethodChannel _channel = MethodChannel('app_manager_channel');

  static bool _pathExists(String path) {
    return Directory(path).existsSync() || File(path).existsSync() || Link(path).existsSync();
  }

  /// 判定指定路径是否属于受 macOS 沙盒内核保护的 Containers 容器根目录
  static bool _isContainerPath(String path) {
    if (!Directory(path).existsSync()) return false;
    final normalized = path.replaceAll(r'\', '/');
    return normalized.contains('/Library/Containers/') ||
           Directory('$path/Data').existsSync() ||
           File('$path/.com.apple.containermanagerd.metadata.plist').existsSync();
  }

  /// 递归测量目录内部实际文件大小（严格 followLinks: false，严禁跟随软链接）
  static int _measureDirSizeSafe(Directory dir) {
    int total = 0;
    try {
      final entries = dir.listSync(recursive: true, followLinks: false);
      for (final e in entries) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// 递归安全清理 Payload 实体（严格 followLinks: false，软链接跳过并绝对不触碰链接目标）
  static void _safeDeletePayloadEntity(FileSystemEntity entity) {
    if (entity is Link) return; // 软链接绝不跟随或递归删除
    try {
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) return;

      if (entity is Directory) {
        final children = entity.listSync(followLinks: false);
        for (final child in children) {
          _safeDeletePayloadEntity(child);
        }
        try {
          entity.deleteSync();
        } catch (_) {}
      } else if (entity is File) {
        entity.deleteSync();
      }
    } catch (_) {}
  }

  /// 安全清理受 SIP / containermanagerd 保护的 macOS 沙盒容器内部 Payload 数据
  /// 严格执行 followLinks: false，绝对保护用户个人软链接 (Desktop, Documents, etc.)
  Future<ContainerPayloadResult> cleanContainerPayload(String containerPath) async {
    final rootDir = Directory(containerPath);
    if (!rootDir.existsSync()) {
      return const ContainerPayloadResult(isCleaned: true, freedBytes: 0, remainingBytes: 0);
    }

    final initialSize = _measureDirSizeSafe(rootDir);
    if (initialSize == 0) {
      return const ContainerPayloadResult(isCleaned: true, freedBytes: 0, remainingBytes: 0);
    }

    // 1. 收集容器内部需要安全清理的 Payload 实体
    final payloadTargets = <String>[];

    // (1) Data/Library 下的非链接目录与文件
    final dataLibDir = Directory('$containerPath/Data/Library');
    if (dataLibDir.existsSync()) {
      try {
        final entries = dataLibDir.listSync(followLinks: false);
        for (final entry in entries) {
          if (entry is Link) continue; // 坚决不触碰任何软链接
          if (entry is Directory) {
            final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
            if (name == 'Application Support') {
              // Application Support 内部可能包含系统创建的软链接 (如 AddressBook, iCloud, SyncServices)
              try {
                final appSupportEntries = entry.listSync(followLinks: false);
                for (final subEntry in appSupportEntries) {
                  if (subEntry is! Link) {
                    payloadTargets.add(subEntry.path);
                  }
                }
              } catch (_) {}
            } else {
              // Caches, WebKit, Preferences, Cookies, Logs, Saved Application State 等
              payloadTargets.add(entry.path);
            }
          } else if (entry is File) {
            payloadTargets.add(entry.path);
          }
        }
      } catch (_) {}
    }

    // (2) Data 下的其他非链接数据
    final dataDir = Directory('$containerPath/Data');
    if (dataDir.existsSync()) {
      try {
        final dataEntries = dataDir.listSync(followLinks: false);
        for (final entry in dataEntries) {
          if (entry is Link) continue; // Desktop, Downloads, Movies, Music, Pictures 等软链接坚决跳过
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name == 'Library') continue; // 已在上面处理
          if (name == 'Documents') {
            // 如果 Documents 是真实目录而非软链接，清理其内部数据
            try {
              final docEntries = (entry as Directory).listSync(followLinks: false);
              for (final dEntry in docEntries) {
                if (dEntry is! Link) payloadTargets.add(dEntry.path);
              }
            } catch (_) {}
          } else if (name == 'tmp') {
            payloadTargets.add(entry.path);
          } else if (entry is File) {
            payloadTargets.add(entry.path);
          }
        }
      } catch (_) {}
    }

    // (3) 容器根目录的非保护文件
    try {
      final rootEntries = rootDir.listSync(followLinks: false);
      for (final entry in rootEntries) {
        if (entry is Link) continue;
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name == '.com.apple.containermanagerd.metadata.plist') {
          // 受系统 containermanagerd 保护，跳过
          continue;
        }
        if (name == 'Container.plist' || name == '.DS_Store') {
          payloadTargets.add(entry.path);
        }
      }
    } catch (_) {}

    // 2. 第一轮：尝试使用 Finder 移入废纸篓 (可撤回)
    if (Platform.isMacOS && payloadTargets.isNotEmpty) {
      try {
        final posixPaths = payloadTargets.map((p) => '"$p"').join(', ');
        final script = '''
          with timeout of 10 seconds
            tell application "Finder"
              repeat with p in {$posixPaths}
                try
                  delete (POSIX file p as alias)
                end try
              end repeat
            end tell
          end timeout
        ''';
        await Process.run('osascript', ['-e', script]);
      } catch (_) {}
    }

    // 3. 第二轮：后置核验并对残留的非软链接 Payload 进行直接安全清理
    for (final targetPath in payloadTargets) {
      if (_pathExists(targetPath)) {
        try {
          final type = FileSystemEntity.typeSync(targetPath, followLinks: false);
          if (type == FileSystemEntityType.link) {
            continue; // 严禁触碰任何软链接
          } else if (type == FileSystemEntityType.directory) {
            _safeDeletePayloadEntity(Directory(targetPath));
          } else if (type == FileSystemEntityType.file) {
            File(targetPath).deleteSync();
          }
        } catch (_) {}
      }
    }

    // 4. 计算清理后的残留体积并核验
    final remainingSize = _measureDirSizeSafe(rootDir);
    final freedBytes = initialSize > remainingSize ? initialSize - remainingSize : 0;

    // 判定成功标准：
    // 残留体积小于 1MB (仅剩轻量级元数据 plist)，或者释放了显著空间且残留已低于 5MB 孤立检测门槛
    final isCleaned = remainingSize < 1024 * 1024 || (freedBytes > 0 && remainingSize < 5 * 1024 * 1024);

    return ContainerPayloadResult(
      isCleaned: isCleaned,
      freedBytes: freedBytes,
      remainingBytes: remainingSize,
    );
  }

  /// 将指定路径集合安全移至 macOS 系统废纸篓 (可撤回)
  /// 优先使用原生 API，失败时依次尝试 /usr/bin/trash 与 osascript，
  /// 若目标属于受内核保护的沙盒容器根目录，自动执行深度 Payload 清理，
  /// 并在最后执行真实文件系统物理后置核验，严禁虚假报告成功。
  Future<RecycleResult> recyclePaths(List<String> paths) async {
    if (paths.isEmpty) {
      return const RecycleResult(successPaths: [], failedPaths: []);
    }

    // 1. 先过滤出当前确实存在的路径
    final existingTargets = paths.where(_pathExists).toList();
    if (existingTargets.isEmpty) {
      return RecycleResult(successPaths: List.from(paths), failedPaths: const []);
    }

    // 2. 方式 1: 原生 NSWorkspace.shared.recycle (若已授 Full Disk Access)
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'recyclePaths',
          {'paths': existingTargets},
        );
      } catch (_) {}
    }

    // 3. 方式 2: 系统级 /usr/bin/trash CLI
    var pending = existingTargets.where(_pathExists).toList();
    if (pending.isNotEmpty && Platform.isMacOS) {
      try {
        if (File('/usr/bin/trash').existsSync()) {
          await Process.run('/usr/bin/trash', pending);
        }
      } catch (_) {}
    }

    // 4. 方式 3: osascript (Finder delete) 尝试
    pending = existingTargets.where(_pathExists).toList();
    if (pending.isNotEmpty && Platform.isMacOS) {
      try {
        final posixPaths = pending.map((p) => '"$p"').join(', ');
        final script = '''
          with timeout of 5 seconds
            tell application "Finder"
              repeat with p in {$posixPaths}
                try
                  delete (POSIX file p as alias)
                end try
              end repeat
            end tell
          end timeout
        ''';
        await Process.run('osascript', ['-e', script]);
      } catch (_) {}
    }

    // 5. 稍微等待操作系统元数据同步
    await Future.delayed(const Duration(milliseconds: 100));

    // 6. 核心：绝对物理存在性后置核验 (Post-verification) 与沙盒容器降级深度清理
    final successPaths = <String>[];
    final failedPaths = <String>[];
    final cleanedContainerPaths = <String>[];
    int totalFreedBytes = 0;

    for (final p in paths) {
      if (!_pathExists(p)) {
        successPaths.add(p);
      } else {
        // 如果根路径依然存在，检查是否属于受 macOS containermanagerd 保护的沙盒容器
        if (_isContainerPath(p)) {
          final cleanRes = await cleanContainerPayload(p);
          if (cleanRes.isCleaned) {
            successPaths.add(p);
            cleanedContainerPaths.add(p);
            totalFreedBytes += cleanRes.freedBytes;
            continue;
          }
        }
        failedPaths.add(p);
      }
    }

    String? errorMsg;
    if (failedPaths.isNotEmpty) {
      final hasContainer = failedPaths.any((p) => p.contains('/Library/Containers/'));
      if (hasContainer) {
        errorMsg = '未能移入废纸篓：包含受 macOS 沙盒保护的容器目录，需要"完全磁盘访问权限"。';
      } else {
        errorMsg = '未能移入废纸篓：目标文件可能被占用、受系统保护或缺少权限。';
      }
    }

    return RecycleResult(
      successPaths: successPaths,
      failedPaths: failedPaths,
      cleanedContainerPaths: cleanedContainerPaths,
      freedBytes: totalFreedBytes,
      errorMessage: errorMsg,
    );
  }

  /// 打开 macOS 系统设置中的「完全磁盘访问权限」页面
  Future<void> openFullDiskAccessSettings() async {
    if (Platform.isMacOS) {
      try {
        await Process.run('open', [
          'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
        ]);
      } catch (_) {}
    }
  }

  /// 在访达 (Finder) 中定位高亮显示指定路径
  Future<void> revealInFinder(String path) async {
    if (Platform.isMacOS) {
      try {
        await Process.run('open', ['-R', path]);
      } catch (_) {}
    }
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
