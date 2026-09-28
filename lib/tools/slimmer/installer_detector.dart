import 'dart:io';
import 'package:path/path.dart' as p;
import 'slimmer_models.dart';

/// 废弃安装包 (.dmg, .pkg, .iso) 探测器
class InstallerDetector {
  InstallerDetector({
    this.customHome,
    this.customTargetDirs,
  });

  final String? customHome;
  final List<Directory>? customTargetDirs;

  /// 扫描用户空间常见安装包存放目录
  Future<List<SlimCandidateItem>> scanInstallers() async {
    final list = <SlimCandidateItem>[];
    final home = customHome ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return list;

    final targetDirs = customTargetDirs ?? [
      Directory(p.join(home, 'Downloads')),
      Directory(p.join(home, 'Desktop')),
      Directory(p.join(home, 'Documents')),
    ];

    final now = DateTime.now();

    for (final dir in targetDirs) {
      if (!dir.existsSync()) continue;
      try {
        final entries = dir.listSync(followLinks: false);
        for (final entry in entries) {
          if (entry is! File) continue;

          final fileName = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (fileName.startsWith('.')) continue; // 跳过隐藏文件

          final lower = fileName.toLowerCase();
          final isInstaller = lower.endsWith('.dmg') ||
              lower.endsWith('.pkg') ||
              lower.endsWith('.iso');

          if (!isInstaller) continue;

          try {
            final stat = entry.statSync();
            // 安装包最小阈值：10MB (避免零碎开发小包)
            if (stat.size < 10 * 1024 * 1024) continue;

            final daysAgo = now.difference(stat.modified).inDays;
            final isOlderThanWeek = daysAgo > 7;

            final dirName = p.basename(dir.path);
            list.add(SlimCandidateItem(
              id: 'installer_${entry.path.hashCode}',
              path: entry.path,
              title: fileName,
              subtitle: isOlderThanWeek
                  ? '位于 $dirName (${daysAgo}天前下载)，软件安装后通常无需保留'
                  : '位于 $dirName (${daysAgo == 0 ? "今天" : "$daysAgo天前"}下载)，近期文件建议确认后再清理',
              sizeBytes: stat.size,
              lastModified: stat.modified,
              category: SlimmerCategory.installers,
              safety: SafetyRating.safe,
              appName: '安装包',
              isSelected: isOlderThanWeek, // 超过 7 天默认勾选
            ));
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 按修改时间升序排列（最旧的在前面）
    list.sort((a, b) {
      final aTime = a.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return list;
  }
}
