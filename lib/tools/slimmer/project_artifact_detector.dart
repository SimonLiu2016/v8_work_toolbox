import 'dart:io';

import 'package:path/path.dart' as p;

import 'slimmer_models.dart';

/// 项目构建产物检测器（分级扫描第 4 阶段）。
///
/// 两层设计，用**发现预算换扫描预算**：
/// - Tier A：浅层 manifest 发现。在 `HOME` 下以有界深度搜索构建清单信号，
///   识别项目根。不读文件大小、不深入，秒级完成。
/// - Tier B：产物收集。只在被识别的项目根内做剪枝遍历收集产物目录，
///   按根设时间/数量预算，超预算显式上报为"未完整"。
///
/// Manifest 门控：产物命中只有在位于被识别的项目根内时才计入候选。
/// `~/node_modules` 这类同名但不在项目根内的路径不产出候选项。
class ProjectArtifactDetector {
  /// 构建清单信号：Tier A 用来识别项目根
  static const List<String> manifestSignals = [
    '.git',
    'package.json',
    'pubspec.yaml',
    'build.gradle',
    'build.gradle.kts',
    'Podfile',
    'CMakeLists.txt',
    'go.mod',
    'xcodeproj',
    'pom.xml',
    'Cargo.toml',
  ];

  /// 产物目录名：Tier B 用来判定命中（可删除的构建产物）
  static const List<String> artifactNames = [
    'node_modules',
    'build',
    'dist',
    '.gradle',
    '.dart_tool',
    'target',
    'cmake-build-debug',
    'out',
    '__pycache__',
  ];

  /// Tier A 发现剪枝：包管理器下载缓存目录（不是用户项目，不应被识别为根）。
  /// 与 [artifactNames] 语义分离：后者是 Tier B 的产物候选（可删除），
  /// 此处是 Tier A 的发现排除（不是产物，是缓存）。
  static const List<String> discoveryPruneDirs = [
    '.pub-cache',
    '.npm',
    '.yarn',
    '.cache',
    '.cargo',
    '.rustup',
    '.local',
  ];

  /// Tier A 遍历深度上限。depth 5 覆盖 99.7% 真实根（本机实测）。
  static const int discoverMaxDepth = 5;

  /// Tier B 单根遍历深度上限（剪枝后再限深，双保险）
  static const int collectMaxDepth = 14;

  /// Tier B 单根时间预算
  static const Duration perRootTimeBudget = Duration(seconds: 4);

  /// Tier B 单根产物数量上限
  static const int perRootArtifactLimit = 200;

  /// 单根单次收集的最大文件访问数（体积热点兜底）
  static const int perRootVisitLimit = 20000;

  /// 列表呈现阈值：≥1 个命中且合计 ≥10MB
  static const int minPresentBytes = 10 * 1024 * 1024;

  /// 让出事件循环的间隔（文件访问次数）
  static const int yieldEvery = 200;

  ProjectArtifactDetector({
    String? home,
    this.watchlist = const <String>[],
    this.artifactOptions = const <String, bool>{},
    Duration? perRootTimeBudget,
    int? perRootArtifactLimit,
    int? discoverMaxDepth,
    int? minPresentBytes,
  })  : home = home ?? _defaultHome(),
        _perRootTimeBudget = perRootTimeBudget ?? ProjectArtifactDetector.perRootTimeBudget,
        _perRootArtifactLimit = perRootArtifactLimit ?? ProjectArtifactDetector.perRootArtifactLimit,
        _discoverMaxDepth = discoverMaxDepth ?? ProjectArtifactDetector.discoverMaxDepth,
        _minPresentBytes = minPresentBytes ?? ProjectArtifactDetector.minPresentBytes;

  final String home;
  final List<String> watchlist;
  final Map<String, bool> artifactOptions;

  final Duration _perRootTimeBudget;
  final int _perRootArtifactLimit;
  final int _discoverMaxDepth;
  final int _minPresentBytes;

  static String _defaultHome() {
    final h = Platform.environment['HOME'];
    return (h == null || h.isEmpty) ? '/Users/simon' : h;
  }

  bool _enabled(String dirName) => artifactOptions[dirName] ?? true;

  // ---------------------------------------------------------------------------
  // Tier A：浅层项目根发现
  // ---------------------------------------------------------------------------

  /// 返回去重后的项目根。主目录自身 MUST NOT 作为根（裸 `~/package.json` 会让
  /// `HOME` 成为所有其他根的前缀，去嵌套时吞掉全部根）。
  Future<List<String>> discoverProjectRoots() async {
    final raw = <String>[];

    final homeDir = Directory(home);
    if (homeDir.existsSync()) {
      await _walkDiscover(homeDir, 1, raw);
    }

    // 额外指定的根豁免 manifest 门控，强制进入 Tier B
    for (final root in watchlist) {
      if (Directory(root).existsSync()) raw.add(_normalize(root));
    }

    final withoutHome =
        raw.where((r) => _normalize(r) != _normalize(home)).toSet().toList();
    return _dedupeNested(withoutHome);
  }

  /// 剪枝遍历：不下降进 Library（阶段 1 已覆盖全局缓存）、`~/Applications`
  /// （应用 bundle 由已卸载残留检测阶段处理，构建产物发现不需要）、
  /// 包管理器缓存目录与已知产物目录自身。产物目录内部可能含嵌套 manifest
  /// （例如 monorepo 的 `node_modules/*/package.json`），若下降进去会把产物
  /// 目录误判为项目根；包缓存同理（`.pub-cache/*/pubspec.yaml` 是下载副本）。
  Future<void> _walkDiscover(Directory dir, int depth, List<String> out) async {
    if (depth > _discoverMaxDepth) return;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }

    for (final e in entries) {
      final name = p.basename(e.path);
      if (manifestSignals.contains(name)) out.add(dir.path);

      if (e is Directory &&
          name != 'Library' &&
          name != 'Applications' &&
          !artifactNames.contains(name) &&
          !discoveryPruneDirs.contains(name)) {
        await _walkDiscover(e, depth + 1, out);
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 嵌套去重：若根 A 是根 B 的前缀，只保留 A。
  static List<String> _dedupeNested(List<String> roots) {
    final sorted = roots.map(_normalize).toList()..sort();
    final result = <String>[];
    for (final r in sorted) {
      if (result.any((p) => r == p || r.startsWith('$p/'))) continue;
      result.add(r);
    }
    return result;
  }

  static String _normalize(String p) =>
      p.endsWith('/') && p.length > 1 ? p.substring(0, p.length - 1) : p;

  // ---------------------------------------------------------------------------
  // Tier B：产物收集
  // ---------------------------------------------------------------------------

  /// 逐个根收集，每收完一个根立即上抛（进度式）。每根独立的时间预算。
  Stream<List<SlimCandidateItem>> collect(List<String> roots) async* {
    final emitted = <SlimCandidateItem>[];

    for (final root in roots) {
      final result = await _collectRoot(root);
      final item = _buildItem(
          root, result.artifacts, incomplete: result.incomplete);
      if (item == null) continue;
      emitted.add(item);
      yield List.of(emitted);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<({List<ProjectArtifact> artifacts, bool incomplete})> _collectRoot(
      String root) async {
    final start = DateTime.now();
    final deadline = start.add(_perRootTimeBudget);
    final artifacts = <ProjectArtifact>[];
    final state = _VisitState();

    void markIncomplete() => state.incomplete = true;

    Future<void> walk(Directory dir, int depth, ProjectTechStack tech) async {
      if (depth > collectMaxDepth ||
          state.incomplete ||
          artifacts.length >= _perRootArtifactLimit) {
        return;
      }
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }

      for (final e in entries) {
        if (state.incomplete) return;

        if (e is Directory) {
          final name = p.basename(e.path);
          if (name == '.git') continue;

          if (artifactNames.contains(name) && _enabled(name)) {
            final size = await _sizeOf(e, deadline, markIncomplete);
            artifacts.add(ProjectArtifact(
              path: e.path,
              dirName: name,
              sizeBytes: size,
              tech: tech,
            ));
            if (artifacts.length >= _perRootArtifactLimit) {
              markIncomplete();
              return;
            }
            // 在添加后立即检查预算：超时时保留已收集的产物而非丢弃
            if (DateTime.now().isAfter(deadline)) {
              markIncomplete();
              return;
            }
            // 剪枝：不下降进已命中的产物目录自身，避免重复计数与体积热点
            continue;
          }

          await walk(e, depth + 1, tech);

          // 仅在遍历子目录后检查预算：文件操作开销极小，不应因单个文件触发超时
          if (DateTime.now().isAfter(deadline)) {
            markIncomplete();
            return;
          }
        }

        state.visited++;
        if (state.visited > perRootVisitLimit) {
          markIncomplete();
          return;
        }
        if (state.visited % yieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
          if (DateTime.now().isAfter(deadline)) {
            markIncomplete();
            return;
          }
        }
      }
    }

    final dir = Directory(root);
    if (dir.existsSync()) {
      await walk(dir, 1, _detectTechStack(root));
    }

    return (artifacts: artifacts, incomplete: state.incomplete);
  }

  /// 技术栈归属：按最具体信号优先级判定，无信号归入"其他"。
  ProjectTechStack _detectTechStack(String root) {
    final entries = <String>{};
    try {
      for (final e in Directory(root).listSync(followLinks: false)) {
        entries.add(p.basename(e.path));
      }
    } catch (_) {}
    if (entries.contains('build.gradle') ||
        entries.contains('build.gradle.kts') ||
        entries.contains('.gradle')) {
      return ProjectTechStack.gradleAndroid;
    }
    if (entries.contains('pubspec.yaml') ||
        entries.contains('.dart_tool') ||
        entries.contains('xcodeproj')) {
      return ProjectTechStack.flutterDart;
    }
    if (entries.contains('package.json') ||
        entries.contains('node_modules') ||
        entries.contains('dist')) {
      return ProjectTechStack.node;
    }
    return ProjectTechStack.other;
  }

  /// 项目根聚合条目：稳定身份键 = 项目根路径。
  SlimCandidateItem? _buildItem(String root, List<ProjectArtifact> artifacts,
      {required bool incomplete}) {
    if (artifacts.isEmpty) return null;

    final total = artifacts.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    if (total < _minPresentBytes) return null;

    final tech = _detectTechStack(root);
    final composition = _composeByType(artifacts);

    return SlimCandidateItem(
      id: root,
      path: root,
      title: _rootLabel(root),
      subtitle: '$composition'
          '${incomplete ? '（扫描超时 / 未完整）' : ''}',
      sizeBytes: total,
      lastModified: _modifiedOf(root),
      category: SlimmerCategory.projectArtifacts,
      safety: SafetyRating.safe,
      isSelected: true,
      artifacts: artifacts,
      techStack: tech,
      scanIncomplete: incomplete,
    );
  }

  /// "23 个产物目录 · node_modules ×5 / build ×8"
  String _composeByType(List<ProjectArtifact> artifacts) {
    final counts = <String, int>{};
    for (final a in artifacts) {
      counts.update(a.dirName, (v) => v + 1, ifAbsent: () => 1);
    }
    final parts = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final summary = parts.map((e) => '${e.key} ×${e.value}').join(' / ');
    return '${artifacts.length} 个产物目录 · $summary';
  }

  /// 根目录在列表中的显示名（用 basename，全路径在明细里可见）。
  String _rootLabel(String root) {
    final normalized = _normalize(root);
    final segments = normalized.split('/');
    if (segments.isEmpty) return normalized;
    final name = segments.last;
    if (name.isEmpty || name == home.split('/').last) return normalized;
    return name;
  }

  DateTime? _modifiedOf(String root) {
    try {
      return Directory(root).statSync().modified;
    } catch (_) {
      return null;
    }
  }

  /// 有界目录大小：不下降进 .git 与产物目录自身；可被同一 deadline 打断。
  Future<int> _sizeOf(Directory dir, DateTime deadline, void Function() onTimeout) async {
    var total = 0;
    var visited = 0;

    Future<void> walk(Directory d, int depth) async {
      if (depth > collectMaxDepth ||
          visited > perRootVisitLimit ||
          DateTime.now().isAfter(deadline)) {
        if (DateTime.now().isAfter(deadline)) onTimeout();
        return;
      }
      List<FileSystemEntity> entries;
      try {
        entries = d.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final e in entries) {
        if (DateTime.now().isAfter(deadline)) {
          onTimeout();
          return;
        }
        if (e is File) {
          try {
            total += e.statSync().size;
          } catch (_) {}
        } else if (e is Directory) {
          final name = p.basename(e.path);
          if (name == '.git' || artifactNames.contains(name)) continue;
          await walk(e, depth + 1);
        }
        visited++;
        if (visited > perRootVisitLimit) {
          onTimeout();
          return;
        }
        if (visited % yieldEvery == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    await walk(dir, 1);
    return total;
  }
}

class _VisitState {
  int visited = 0;
  bool incomplete = false;
}
