import 'dart:async';
import 'dart:io';
import 'app_orphan_detector.dart';
import 'multi_version_scanner.dart';
import 'slimmer_models.dart';

/// 扫描进度状态
class ScanProgress {
  final int stage; // 1, 2, 3
  final String stageName;
  final double progress; // 0.0 - 1.0
  final int itemsFound;
  final int totalReclaimableBytes;
  final bool isCompleted;

  const ScanProgress({
    required this.stage,
    required this.stageName,
    required this.progress,
    required this.itemsFound,
    required this.totalReclaimableBytes,
    this.isCompleted = false,
  });
}

/// 分级按需磁盘扫描服务
class DiskScannerService {
  final AppOrphanDetector _orphanDetector = AppOrphanDetector();
  final MultiVersionScanner _versionScanner = MultiVersionScanner();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// 开始执行三阶段渐进式扫描
  Stream<List<SlimCandidateItem>> startScan({
    void Function(ScanProgress progress)? onProgress,
  }) async* {
    if (_isScanning) return;
    _isScanning = true;

    final allItems = <SlimCandidateItem>[];
    int totalBytes = 0;

    void notify(int stage, String name, double p, {bool done = false}) {
      onProgress?.call(ScanProgress(
        stage: stage,
        stageName: name,
        progress: p,
        itemsFound: allItems.length,
        totalReclaimableBytes: totalBytes,
        isCompleted: done,
      ));
    }

    try {
      final home = Platform.environment['HOME'] ?? '';

      // ─────────────────────────────────────────────────────────────
      // 阶段 1: 瞬时定向扫描 (<3秒) - 高发重灾区与大型构建缓存
      // ─────────────────────────────────────────────────────────────
      notify(1, '正在定向扫描高发构建缓存与超大下载包...', 0.1);
      final instantItems = await _scanInstantTargets(home);
      allItems.addAll(instantItems);
      totalBytes = allItems.fold(0, (sum, it) => sum + it.sizeBytes);
      notify(1, '阶段 1 完成，发现 ${instantItems.length} 个立竿见影项', 0.35);
      yield List.of(allItems);

      // ─────────────────────────────────────────────────────────────
      // 阶段 2: 开发运行时与 IDE 多版本矩阵探测 (<10秒)
      // ─────────────────────────────────────────────────────────────
      notify(2, '正在探测开发环境与 IDE 升级遗留多版本...', 0.45);
      final versionItems = await _versionScanner.scanMultiVersions();
      allItems.addAll(versionItems);
      totalBytes = allItems.fold(0, (sum, it) => sum + it.sizeBytes);
      notify(2, '阶段 2 完成，发现 ${versionItems.length} 个版本项', 0.70);
      yield List.of(allItems);

      // ─────────────────────────────────────────────────────────────
      // 阶段 3: 深度孤立卸载残留匹配
      // ─────────────────────────────────────────────────────────────
      notify(3, '正在比对已安装应用，查找已卸载软件残留...', 0.75);
      await _orphanDetector.initialize();
      notify(3, '正在分析 ~/Library 孤立目录与容器...', 0.85);
      final orphanItems = await _orphanDetector.scanOrphans();
      allItems.addAll(orphanItems);
      totalBytes = allItems.fold(0, (sum, it) => sum + it.sizeBytes);
      notify(3, '全盘分级扫描完成', 1.0, done: true);
      yield List.of(allItems);

    } finally {
      _isScanning = false;
    }
  }

  Future<List<SlimCandidateItem>> _scanInstantTargets(String home) async {
    final list = <SlimCandidateItem>[];

    // 1. Xcode DerivedData
    final derivedData = Directory('$home/Library/Developer/Xcode/DerivedData');
    if (derivedData.existsSync()) {
      final size = await _calcDirSize(derivedData);
      if (size > 10 * 1024 * 1024) {
        list.add(SlimCandidateItem(
          id: 'derived_data',
          path: derivedData.path,
          title: 'Xcode DerivedData 编译缓存',
          subtitle: '包含本地构建产物、模块缓存与索引，删除后下次构建会自动重建',
          sizeBytes: size,
          lastModified: derivedData.statSync().modified,
          category: SlimmerCategory.buildCache,
          safety: SafetyRating.safe,
          appName: 'Xcode',
          isSelected: true,
        ));
      }
    }

    // 2. Gradle caches
    final gradleCache = Directory('$home/.gradle/caches');
    if (gradleCache.existsSync()) {
      final size = await _calcDirSize(gradleCache);
      if (size > 50 * 1024 * 1024) {
        list.add(SlimCandidateItem(
          id: 'gradle_cache',
          path: gradleCache.path,
          title: 'Gradle 依赖缓存',
          subtitle: 'Android 与 Java 项目的历史依赖与构建缓存',
          sizeBytes: size,
          lastModified: gradleCache.statSync().modified,
          category: SlimmerCategory.buildCache,
          safety: SafetyRating.safe,
          appName: 'Gradle',
          isSelected: true,
        ));
      }
    }

    // 3. CocoaPods Cache
    final cocoapodsCache = Directory('$home/Library/Caches/CocoaPods');
    if (cocoapodsCache.existsSync()) {
      final size = await _calcDirSize(cocoapodsCache);
      if (size > 20 * 1024 * 1024) {
        list.add(SlimCandidateItem(
          id: 'cocoapods_cache',
          path: cocoapodsCache.path,
          title: 'CocoaPods 下载缓存',
          subtitle: 'iOS 项目 pod 依赖下载缓存，可随时安全清除',
          sizeBytes: size,
          lastModified: cocoapodsCache.statSync().modified,
          category: SlimmerCategory.buildCache,
          safety: SafetyRating.safe,
          appName: 'CocoaPods',
          isSelected: true,
        ));
      }
    }

    // 4. 用户下载目录中的大安装包 (>100MB .dmg, .pkg, .iso, .zip)
    final downloads = Directory('$home/Downloads');
    if (downloads.existsSync()) {
      try {
        final entries = downloads.listSync(followLinks: false);
        for (final entry in entries) {
          if (entry is File) {
            final name = entry.uri.pathSegments.last.toLowerCase();
            if (name.endsWith('.dmg') || name.endsWith('.pkg') || name.endsWith('.iso') || name.endsWith('.zip')) {
              final stat = entry.statSync();
              if (stat.size > 100 * 1024 * 1024) { // >100MB
                final daysAgo = DateTime.now().difference(stat.modified).inDays;
                list.add(SlimCandidateItem(
                  id: 'download_${entry.path.hashCode}',
                  path: entry.path,
                  title: entry.uri.pathSegments.last,
                  subtitle: '位于下载目录 (${daysAgo > 0 ? "$daysAgo 天前" : "今天"})，软件安装后安装包通常可安全清理',
                  sizeBytes: stat.size,
                  lastModified: stat.modified,
                  category: SlimmerCategory.largeDownloads,
                  safety: SafetyRating.safe,
                  appName: 'Finder',
                  isSelected: daysAgo > 7, // 超过 7 天默认勾选
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    return list;
  }

  /// 异步计算目录大小，每处理 200 个文件后 yield 控制权给 Flutter 框架
  Future<int> _calcDirSize(Directory dir, {int maxDepth = 4}) async {
    int total = 0;
    int fileCount = 0;

    Future<void> walk(Directory d, int depth) async {
      if (depth > maxDepth) return;
      try {
        final entries = d.listSync(followLinks: false);
        for (final e in entries) {
          if (e is File) {
            total += e.statSync().size;
            fileCount++;
            if (fileCount % 200 == 0) {
              await Future(() {}); // yield 控制权，让 Flutter 渲染帧
            }
          } else if (e is Directory) {
            await walk(e, depth + 1);
          }
        }
      } catch (_) {}
    }

    await walk(dir, 1);
    return total;
  }
}
