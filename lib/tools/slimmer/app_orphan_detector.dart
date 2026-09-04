import 'dart:io';
import 'slimmer_models.dart';

/// 孤立应用残留分析器
class AppOrphanDetector {
  /// 缓存已安装应用的标识符与主文件名
  final Set<String> _installedBundleIds = <String>{};
  final Set<String> _installedAppNames = <String>{};

  /// 已知的应用别名映射：Application Support 目录名 → 已安装 .app 名称（小写）
  static const Map<String, String> _knownAliases = {
    'code': 'visual studio code',
    'bilibili': '哔哩哔哩',
    'bravesoftware': 'brave browser',
    'blizzard': 'battle.net',
    'blizzard entertainment': 'battle.net',
    'chromium': 'google chrome',
    'dingtalkmac': 'dingtalk',
    'baidunetdisk': '百度网盘',
    'adrive': '阿里云盘',
    'ccswitch': 'cc switch',
    'chatgpt-mac': 'chatgpt',
    'chat2db': 'chat2db',
    'aui-studio': 'aui-studio',
    'camunda-modeler': 'camunda modeler',
    '1password 4': '1password 7',
    'adobe': 'adobe photoshop',
    'adobe.xd': 'adobe xd',
    'google': 'google chrome',
    'microsoft': 'microsoft word',
    'defaultcompany': 'unity',
    'antigravity ide': 'antigravity ide',
  };

  /// 初始化并预热系统中已安装的应用清单
  Future<void> initialize() async {
    _installedBundleIds.clear();
    _installedAppNames.clear();

    final appDirs = [
      Directory('/Applications'),
      Directory('${Platform.environment['HOME']}/Applications'),
    ];

    for (final dir in appDirs) {
      if (!dir.existsSync()) continue;
      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            final appName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final baseName = appName.replaceAll('.app', '').toLowerCase();
            _installedAppNames.add(baseName);

            // 读取 Info.plist 获取真实 BundleId
            final plistFile = File('${entity.path}/Contents/Info.plist');
            if (plistFile.existsSync()) {
              try {
                final content = plistFile.readAsStringSync();
                final match = RegExp(r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>').firstMatch(content);
                if (match != null) {
                  _installedBundleIds.add(match.group(1)!.trim().toLowerCase());
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
  }

  /// 扫描 ~/Library/ 下的孤立残留
  Future<List<SlimCandidateItem>> scanOrphans() async {
    final results = <SlimCandidateItem>[];
    final home = Platform.environment['HOME'];
    if (home == null) return results;

    final targetDirs = [
      Directory('$home/Library/Containers'),
      Directory('$home/Library/Application Support'),
      Directory('$home/Library/Caches'),
    ];

    for (final baseDir in targetDirs) {
      if (!baseDir.existsSync()) continue;
      try {
        final list = baseDir.listSync(followLinks: false);
        for (final item in list) {
          if (item is! Directory) continue;
          final folderName = item.uri.pathSegments.where((s) => s.isNotEmpty).last;
          final lowerName = folderName.toLowerCase();

          // 保护系统核心苹果应用与关键基础服务
          if (lowerName.startsWith('com.apple.') ||
              lowerName == 'apple' ||
              lowerName == 'google' && _installedAppNames.contains('google chrome') ||
              lowerName == 'microsoft' && _installedAppNames.any((a) => a.contains('word') || a.contains('office') || a.contains('edge')) ||
              lowerName == 'jetbrains' ||
              lowerName == 'crashreporter' ||
              lowerName == 'dock' ||
              lowerName == 'icloud' ||
              lowerName == 'system' ||
              lowerName == 'cloudstorage') {
            continue;
          }

          // 多层验证：Bundle ID → 别名映射 → 子串匹配
          final matchResult = _matchInstalledApp(folderName, lowerName);

          if (matchResult == _MatchResult.installed) {
            continue; // 已安装应用，跳过
          }

          // 计算目录大小与修改时间
          final stats = await _measureDirQuick(item);
          if (stats.sizeBytes > 5 * 1024 * 1024) { // 超过 5MB
            // 根据匹配结果和修改时间确定安全等级
            final safety = _determineSafety(matchResult, stats.lastModified);
            final isSelected = safety == SafetyRating.safe;

            results.add(SlimCandidateItem(
              id: 'orphan_${item.path.hashCode}',
              path: item.path,
              title: folderName,
              subtitle: _buildSubtitle(matchResult, baseDir, stats),
              sizeBytes: stats.sizeBytes,
              lastModified: stats.lastModified,
              category: SlimmerCategory.orphanApp,
              safety: safety,
              appName: folderName,
              isSelected: isSelected,
            ));
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// 归一化字符串：移除连字符、空格、点号等分隔符，用于模糊匹配
  String _normalize(String s) {
    return s.replaceAll(RegExp(r'[\s\-_\.]+'), '');
  }

  /// 多层验证：Bundle ID → 别名映射 → 子串匹配
  _MatchResult _matchInstalledApp(String folderName, String lowerName) {
    // Layer 1: Bundle ID 精确匹配
    final isBundleFormat = RegExp(r'^[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+').hasMatch(folderName);
    if (isBundleFormat) {
      if (_installedBundleIds.contains(lowerName)) {
        return _MatchResult.installed;
      }
      // Bundle ID 格式但未匹配，检查是否包含已安装 app 名称
      if (_installedAppNames.any((app) => lowerName.contains(app))) {
        return _MatchResult.installed;
      }
    }

    // Layer 2: 精确名称匹配
    if (_installedAppNames.contains(lowerName)) {
      return _MatchResult.installed;
    }

    // Layer 3: 已知别名映射
    final aliasTarget = _knownAliases[lowerName];
    if (aliasTarget != null && _installedAppNames.contains(aliasTarget)) {
      return _MatchResult.installed;
    }
    // 别名映射的模糊匹配（别名目标包含在已安装应用名中）
    if (aliasTarget != null && _installedAppNames.any((app) => app.contains(aliasTarget) || aliasTarget.contains(app))) {
      return _MatchResult.installed;
    }

    // Layer 4: 子串双向匹配（目录名长度 ≥ 4 且匹配占比 > 50%）
    // 先做归一化匹配（移除连字符、空格、点号等分隔符）
    final normalizedLower = _normalize(lowerName);
    if (normalizedLower.length >= 4) {
      for (final appName in _installedAppNames) {
        final normalizedApp = _normalize(appName);
        if (normalizedApp.length < 4) continue;
        // 归一化后目录名是应用名的子串
        if (normalizedApp.contains(normalizedLower) && normalizedLower.length / normalizedApp.length > 0.5) {
          return _MatchResult.partialMatch;
        }
        // 归一化后应用名是目录名的子串
        if (normalizedLower.contains(normalizedApp) && normalizedApp.length / normalizedLower.length > 0.5) {
          return _MatchResult.partialMatch;
        }
      }
    }

    // Layer 5: 原始子串匹配（兜底）
    if (lowerName.length >= 4) {
      for (final appName in _installedAppNames) {
        if (appName.length < 4) continue;
        if (appName.contains(lowerName) && lowerName.length / appName.length > 0.5) {
          return _MatchResult.partialMatch;
        }
        if (lowerName.contains(appName) && appName.length / lowerName.length > 0.5) {
          return _MatchResult.partialMatch;
        }
      }
    }

    return _MatchResult.noMatch;
  }

  /// 根据匹配结果和修改时间确定安全等级
  SafetyRating _determineSafety(_MatchResult matchResult, DateTime lastModified) {
    final daysAgo = DateTime.now().difference(lastModified).inDays;

    // 有部分匹配的，根据时间降级
    if (matchResult == _MatchResult.partialMatch) {
      if (daysAgo <= 30) return SafetyRating.caution;
      return SafetyRating.caution; // 部分匹配始终谨慎
    }

    // 完全未匹配的，根据时间降级
    if (daysAgo <= 7) return SafetyRating.danger;    // 7天内：高风险
    if (daysAgo <= 30) return SafetyRating.caution;   // 30天内：谨慎
    if (daysAgo <= 90) return SafetyRating.caution;   // 90天内：谨慎
    return SafetyRating.safe;                          // 90天+：可清理
  }

  /// 构建副标题描述
  String _buildSubtitle(_MatchResult matchResult, Directory baseDir, DirStats stats) {
    final dirType = baseDir.path.split('/').last;
    final fileCount = stats.fileCount;

    switch (matchResult) {
      case _MatchResult.partialMatch:
        return '可能关联已安装应用（$dirType 残留，$fileCount 个文件），建议确认后清理';
      case _MatchResult.noMatch:
        return '未找到关联应用（$dirType 残留，$fileCount 个文件），请确认后手动勾选';
      case _MatchResult.installed:
        return '已安装应用数据（$fileCount 个文件）'; // 不应到达此处
    }
  }

  /// 系统元数据文件名集合，这些文件的时间戳不代表应用活动
  static const _systemMetadataFiles = {
    '.ds_store',
    '.localized',
    'thumbs.db',
    'desktop.ini',
    '.git',
    '.svn',
    '__macosx',
  };

  Future<DirStats> _measureDirQuick(Directory dir, {int maxDepth = 4}) async {
    int total = 0;
    int count = 0;
    DateTime? newest;
    int fileCount = 0;

    Future<void> walk(Directory d, int depth) async {
      if (depth > maxDepth) return;
      try {
        final entries = d.listSync(followLinks: false);
        for (final e in entries) {
          final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last.toLowerCase();
          // 跳过系统元数据文件
          if (_systemMetadataFiles.contains(name)) continue;

          if (e is File) {
            try {
              final stat = e.statSync();
              total += stat.size;
              count++;
              fileCount++;
              if (newest == null || stat.modified.isAfter(newest!)) {
                newest = stat.modified;
              }
              if (fileCount % 200 == 0) {
                await Future(() {}); // yield 控制权
              }
            } catch (_) {}
          } else if (e is Directory) {
            await walk(e, depth + 1);
          }
        }
      } catch (_) {}
    }

    await walk(dir, 1);
    return DirStats(total, count, newest ?? dir.statSync().modified);
  }
}

enum _MatchResult {
  installed,    // 已安装应用（Bundle ID 或精确匹配）
  partialMatch, // 部分匹配（子串匹配）
  noMatch,      // 完全未匹配
}

class DirStats {
  final int sizeBytes;
  final int fileCount;
  final DateTime lastModified;
  const DirStats(this.sizeBytes, this.fileCount, this.lastModified);
}
