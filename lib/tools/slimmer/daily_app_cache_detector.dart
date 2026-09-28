import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'slimmer_models.dart';

/// 日常活跃应用缓存与系统日志探测器
class DailyAppCacheDetector {
  DailyAppCacheDetector({
    this.customHome,
    this.customAppDirs,
  });

  final String? customHome;
  final List<Directory>? customAppDirs;

  /// 已安装应用的 Bundle ID 映射到应用展示名 (如 com.tencent.xinWeChat -> 微信)
  final Map<String, String> _bundleIdToDisplayName = {};
  final Map<String, String> _appNameMap = {};

  /// 敏感即时通讯工具 (默认不勾选，防误删缩略图)
  static const Set<String> sensitiveBundleIds = {
    'com.tencent.xinwechat',
    'com.alibaba.dingtalkmac',
    'com.electron.lark',
    'com.tencent.qq',
    'com.feishu',
    'com.microsoft.teams',
    'org.whispersystems.signal-desktop',
    'ru.keepcoder.telegram',
  };

  /// 常见知名应用展示名兜底表 (小写 BundleId 或目录名 -> 中文名)
  static const Map<String, String> _knownDisplayNames = {
    'com.tencent.xinwechat': '微信 (WeChat)',
    'com.alibaba.dingtalkmac': '钉钉 (DingTalk)',
    'com.tencent.qqmusicmac': 'QQ 音乐',
    'com.tencent.meeting': '腾讯会议',
    'com.tencent.tenvideo': '腾讯视频',
    'com.baidu.baidunetdisk': '百度网盘',
    'com.google.chrome': 'Google Chrome',
    'com.microsoft.edgemac': 'Microsoft Edge',
    'com.apple.safari': 'Safari 浏览器',
    'org.mozilla.firefox': 'Firefox 浏览器',
    'com.brave.browser': 'Brave 浏览器',
    'com.colliderli.iina': 'IINA 播放器',
    'tv.danmaku.bilibili': '哔哩哔哩',
    'com.sublimetext.4': 'Sublime Text',
    'com.sublimetext.3': 'Sublime Text',
    'com.netease.163music': '网易云音乐',
    'com.docker.docker': 'Docker Desktop',
    'com.googlecode.iterm2': 'iTerm2',
  };

  /// 初始化并预热系统中已安装的应用清单
  Future<void> initialize() async {
    _bundleIdToDisplayName.clear();
    _appNameMap.clear();

    final home = customHome ?? Platform.environment['HOME'] ?? '';
    final appDirs = customAppDirs ?? [
      Directory('/Applications'),
      if (home.isNotEmpty) Directory('$home/Applications'),
    ];

    for (final dir in appDirs) {
      if (!dir.existsSync()) continue;
      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            final folderName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final baseName = folderName.replaceAll('.app', '');
            final lowerBase = baseName.toLowerCase();
            _appNameMap[lowerBase] = baseName;

            // 读取 Info.plist 获取真实 BundleId 与 DisplayName
            final plistFile = File(p.join(entity.path, 'Contents', 'Info.plist'));
            if (plistFile.existsSync()) {
              try {
                final content = plistFile.readAsStringSync();
                final bundleMatch = RegExp(r'<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>').firstMatch(content);
                String displayName = baseName;
                final nameMatch = RegExp(r'<key>CFBundleDisplayName</key>\s*<string>([^<]+)</string>').firstMatch(content);
                if (nameMatch != null) {
                  displayName = nameMatch.group(1)!.trim();
                }
                if (bundleMatch != null) {
                  final bid = bundleMatch.group(1)!.trim().toLowerCase();
                  _bundleIdToDisplayName[bid] = displayName;
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
  }

  /// 扫描日常活跃应用缓存与系统日志
  Future<List<SlimCandidateItem>> scanDailyCaches() async {
    final list = <SlimCandidateItem>[];
    final home = customHome ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return list;

    // 1. 扫描 ~/Library/Caches
    final cachesDir = Directory('$home/Library/Caches');
    if (cachesDir.existsSync()) {
      try {
        final entries = cachesDir.listSync(followLinks: false);
        for (final entry in entries) {
          if (entry is! Directory) continue;
          final dirName = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          final lowerName = dirName.toLowerCase();

          // 跳过已知由其它阶段专门处理的大型开发缓存
          if (lowerName == 'cocoapods') continue;

          final matchedName = _resolveAppName(lowerName);
          if (matchedName != null) {
            final size = await _calcDirSize(entry);
            if (size > 500 * 1024) { // >500KB
              final isSensitive = _isSensitive(lowerName);
              list.add(SlimCandidateItem(
                id: 'cache_${entry.path.hashCode}',
                path: entry.path,
                title: '$matchedName 运行缓存',
                subtitle: isSensitive
                    ? '包含网络图片与流媒体缓存；清理后聊天历史不丢失但缩略图需重新加载'
                    : '包含应用网络请求、临时资源与封面缓存，清理后不影响配置',
                sizeBytes: size,
                lastModified: _safeLastModified(entry),
                category: SlimmerCategory.dailyAppCache,
                safety: isSensitive ? SafetyRating.caution : SafetyRating.safe,
                appName: matchedName,
                isSelected: !isSensitive, // 非敏感应用默认勾选
              ));
            }
          }
        }
      } catch (_) {}
    }

    // 2. 扫描沙盒目录 Containers/*/Data/Library/Caches
    final containersDir = Directory('$home/Library/Containers');
    if (containersDir.existsSync()) {
      try {
        final containers = containersDir.listSync(followLinks: false);
        for (final container in containers) {
          if (container is! Directory) continue;
          final bundleId = container.uri.pathSegments.where((s) => s.isNotEmpty).last.toLowerCase();
          final appCache = Directory(p.join(container.path, 'Data', 'Library', 'Caches'));
          if (appCache.existsSync()) {
            final matchedName = _resolveAppName(bundleId);
            if (matchedName != null) {
              final size = await _calcDirSize(appCache);
              if (size > 1024 * 1024) { // >1MB
                final isSensitive = _isSensitive(bundleId);
                // 避免与 ~/Library/Caches 同名项重复
                final id = 'container_cache_${appCache.path.hashCode}';
                if (!list.any((it) => it.id == id || it.path == appCache.path)) {
                  list.add(SlimCandidateItem(
                    id: id,
                    path: appCache.path,
                    title: '$matchedName 沙盒缓存',
                    subtitle: isSensitive
                        ? '位于沙盒容器；清理后聊天记录不受影响，媒体缓存重新拉取'
                        : '包含应用沙盒内网络缓存与临时文件，可安全清理',
                    sizeBytes: size,
                    lastModified: _safeLastModified(appCache),
                    category: SlimmerCategory.dailyAppCache,
                    safety: isSensitive ? SafetyRating.caution : SafetyRating.safe,
                    appName: matchedName,
                    isSelected: !isSensitive,
                  ));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. 扫描用户级系统与应用日志 ~/Library/Logs
    final logsDir = Directory('$home/Library/Logs');
    if (logsDir.existsSync()) {
      final size = await _calcDirSize(logsDir);
      if (size > 10 * 1024 * 1024) { // >10MB
        list.add(SlimCandidateItem(
          id: 'system_logs',
          path: logsDir.path,
          title: '系统与应用运行日志',
          subtitle: '包含 macOS 用户运行日志与应用崩溃日志 (~/Library/Logs)，可随时安全清空',
          sizeBytes: size,
          lastModified: _safeLastModified(logsDir),
          category: SlimmerCategory.dailyAppCache,
          safety: SafetyRating.safe,
          appName: '系统日志',
          isSelected: true,
        ));
      }
    }

    return list;
  }

  String? _resolveAppName(String lowerKey) {
    if (_knownDisplayNames.containsKey(lowerKey)) {
      return _knownDisplayNames[lowerKey];
    }
    if (_bundleIdToDisplayName.containsKey(lowerKey)) {
      return _bundleIdToDisplayName[lowerKey];
    }
    for (final entry in _bundleIdToDisplayName.entries) {
      if (lowerKey.contains(entry.key) || entry.key.contains(lowerKey)) {
        return entry.value;
      }
    }
    if (_appNameMap.containsKey(lowerKey)) {
      return _appNameMap[lowerKey];
    }
    return null;
  }

  bool _isSensitive(String lowerKey) {
    return sensitiveBundleIds.any((s) => lowerKey.contains(s) || s.contains(lowerKey));
  }

  DateTime _safeLastModified(FileSystemEntity entity) {
    try {
      return entity.statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<int> _calcDirSize(Directory dir, {int depth = 0, int maxDepth = 4}) async {
    if (depth > maxDepth) return 0;
    int size = 0;
    try {
      final entries = dir.listSync(followLinks: false);
      for (final e in entries) {
        if (e is File) {
          size += e.statSync().size;
        } else if (e is Directory) {
          size += await _calcDirSize(e, depth: depth + 1, maxDepth: maxDepth);
        }
      }
    } catch (_) {}
    return size;
  }
}
