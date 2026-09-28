import 'dart:io';
import 'package:path/path.dart' as p;
import 'slimmer_models.dart';

/// 超大单体文件 (>100MB) 排行探测器
class LargeFileScanner {
  LargeFileScanner({
    this.customHome,
    this.minSizeBytes = 100 * 1024 * 1024, // 默认 >100MB
    this.maxResults = 100,
    this.mockFiles,
  });

  final String? customHome;
  final int minSizeBytes;
  final int maxResults;
  final List<File>? mockFiles;

  /// 扫描用户空间下的超大文件
  Future<List<SlimCandidateItem>> scanLargeFiles() async {
    final list = <SlimCandidateItem>[];

    // 测试模式：直接使用 mock 文件列表
    if (mockFiles != null) {
      for (final f in mockFiles!) {
        _tryAddFile(f, list);
      }
      _sortAndLimit(list);
      return list;
    }

    final home = customHome ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return list;

    // 优先使用 macOS Spotlight mdfind 毫秒级检索
    bool mdfindSucceeded = false;
    if (Platform.isMacOS) {
      try {
        final query = 'kMDItemFSSize > $minSizeBytes && kMDItemContentTypeTree != "com.apple.application-bundle"';
        final result = await Process.run('mdfind', ['-onlyin', home, query]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final file = File(trimmed);
            _tryAddFile(file, list);
          }
          mdfindSucceeded = list.isNotEmpty;
        }
      } catch (_) {}
    }

    // 若 mdfind 不可用或未返回结果（如 Spotlight 索引被禁用），回退到定向目录轻量扫描
    if (!mdfindSucceeded) {
      final fallbackDirs = [
        Directory(p.join(home, 'Downloads')),
        Directory(p.join(home, 'Desktop')),
        Directory(p.join(home, 'Movies')),
        Directory(p.join(home, 'Documents')),
      ];

      for (final dir in fallbackDirs) {
        if (!dir.existsSync()) continue;
        try {
          final entities = dir.listSync(recursive: true, followLinks: false);
          for (final entity in entities) {
            if (entity is File) {
              _tryAddFile(entity, list);
            }
          }
        } catch (_) {}
      }
    }

    _sortAndLimit(list);
    return list;
  }

  void _tryAddFile(File file, List<SlimCandidateItem> list) {
    try {
      final filePath = file.path;

      // 严格过滤保护目录与系统包
      if (filePath.contains('/.Trash/') || filePath.endsWith('/.Trash')) return;
      if (filePath.contains('/.git/')) return;
      if (filePath.contains('/Library/')) return;
      if (filePath.contains('/node_modules/')) return;
      if (filePath.contains('.app/')) return;
      if (filePath.contains('.framework/')) return;

      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return;
      if (stat.size < minSizeBytes) return;

      // 防止重复添加
      if (list.any((it) => it.path == filePath)) return;

      final fileName = p.basename(filePath);
      final parentDir = p.basename(p.dirname(filePath));
      final tag = _detectFileTag(fileName);

      list.add(SlimCandidateItem(
        id: 'large_file_${filePath.hashCode}',
        path: filePath,
        title: fileName,
        subtitle: '[$tag] 位于 $parentDir，单体超大文件，建议确认后按需处理',
        sizeBytes: stat.size,
        lastModified: stat.modified,
        category: SlimmerCategory.largeFiles,
        safety: SafetyRating.caution, // 大文件一律谨慎对待
        appName: tag,
        isSelected: false, // 默认不勾选，防误删重要数据
      ));
    } catch (_) {}
  }

  void _sortAndLimit(List<SlimCandidateItem> list) {
    // 按文件体积降序排列（最大的排在最前）
    list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (list.length > maxResults) {
      list.removeRange(maxResults, list.length);
    }
  }

  String _detectFileTag(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.wmv')) {
      return '高清视频';
    }
    if (lower.endsWith('.dmg') ||
        lower.endsWith('.iso') ||
        lower.endsWith('.qcow2') ||
        lower.endsWith('.vmdk') ||
        lower.endsWith('.img') ||
        lower.endsWith('.ipsw')) {
      return '磁盘镜像/固件';
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.bz2')) {
      return '压缩归档';
    }
    if (lower.endsWith('.csv') ||
        lower.endsWith('.sql') ||
        lower.endsWith('.db') ||
        lower.endsWith('.dump') ||
        lower.endsWith('.parquet') ||
        lower.endsWith('.bin')) {
      return '数据转储';
    }
    return '大型文件';
  }
}
