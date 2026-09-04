import 'dart:io';
import 'slimmer_models.dart';

/// 多版本与升级遗留扫描器
class MultiVersionScanner {
  Future<List<SlimCandidateItem>> scanMultiVersions() async {
    final results = <SlimCandidateItem>[];
    final home = Platform.environment['HOME'] ?? '';

    // 1. JetBrains 系列 (IDEA, PyCharm, WebStorm, CLion 等)
    results.addAll(await _scanJetBrains(home));

    // 2. Android Studio 历史版本
    results.addAll(await _scanAndroidStudio(home));

    // 3. Python 运行时版本 (pyenv, conda, framework)
    results.addAll(await _scanPython(home));

    // 4. Node.js 多版本 (nvm, fnm)
    results.addAll(await _scanNode(home));

    // 5. Java JDK 多版本
    results.addAll(await _scanJava(home));

    return results;
  }

  Future<List<SlimCandidateItem>> _scanJetBrains(String home) async {
    final list = <SlimCandidateItem>[];
    final bases = [
      (Directory('$home/Library/Application Support/JetBrains'), '配置'),
      (Directory('$home/Library/Caches/JetBrains'), '缓存'),
    ];

    final productGroups = <String, List<_VersionDir>>{};

    for (final (base, sourceLabel) in bases) {
      if (!base.existsSync()) continue;
      try {
        for (final entry in base.listSync(followLinks: false)) {
          if (entry is! Directory) continue;
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;

          // 匹配产品名 + 年份大版本，如 IntelliJIdea2022.3, PyCharm2023.1
          final match = RegExp(r'^([a-zA-Z]+)(\d{4}\.\d+)$').firstMatch(name);
          if (match != null) {
            final product = match.group(1)!;
            final version = match.group(2)!;
            productGroups.putIfAbsent(product, () => []).add(
              _VersionDir(entry.path, product, version, entry.statSync().modified, sourceLabel),
            );
          }
        }
      } catch (_) {}
    }

    // 针对每个产品家族进行排序，最新版保留，旧版标为可清理
    for (final entry in productGroups.entries) {
      final family = entry.key;
      final versions = entry.value;
      if (versions.length <= 1) continue; // 只有一个版本则不打扰

      // 按版本升序
      versions.sort((a, b) => a.version.compareTo(b.version));
      final newest = versions.last;

      for (final v in versions) {
        final isOld = v.version != newest.version;
        final size = await _quickDirSize(Directory(v.path));
        if (size > 10 * 1024 * 1024) { // >10MB
          list.add(SlimCandidateItem(
            id: 'jetbrains_${v.path.hashCode}',
            path: v.path,
            title: '$family ${v.version}（${v.sourceLabel}）',
            subtitle: isOld ? '旧升级遗留（当前最新: ${newest.version}），老版本可安全删除' : '当前最新活跃版本（建议保留）',
            sizeBytes: size,
            lastModified: v.modified,
            category: SlimmerCategory.multiVersion,
            safety: isOld ? SafetyRating.safe : SafetyRating.caution,
            appName: family,
            version: v.version,
            isSelected: isOld, // 默认只选中旧版本
          ));
        }
      }
    }

    return list;
  }

  Future<List<SlimCandidateItem>> _scanAndroidStudio(String home) async {
    final list = <SlimCandidateItem>[];
    final asDir = Directory('$home/Library/Application Support/Google');
    if (!asDir.existsSync()) return list;

    final versions = <_VersionDir>[];
    try {
      for (final entry in asDir.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith('AndroidStudio')) {
          final ver = name.replaceFirst('AndroidStudio', '');
          if (ver.isNotEmpty) {
            versions.add(_VersionDir(entry.path, 'AndroidStudio', ver, entry.statSync().modified, '配置'));
          }
        }
      }
    } catch (_) {}

    if (versions.length > 1) {
      versions.sort((a, b) => a.version.compareTo(b.version));
      final newest = versions.last;
      for (final v in versions) {
        final isOld = v.version != newest.version;
        final size = await _quickDirSize(Directory(v.path));
        if (size > 10 * 1024 * 1024) {
          list.add(SlimCandidateItem(
            id: 'as_${v.path.hashCode}',
            path: v.path,
            title: 'Android Studio ${v.version}',
            subtitle: isOld ? '历史升级配置与缓存残留（最新为 ${newest.version}）' : '当前活跃版本配置（建议保留）',
            sizeBytes: size,
            lastModified: v.modified,
            category: SlimmerCategory.multiVersion,
            safety: isOld ? SafetyRating.safe : SafetyRating.caution,
            appName: 'Android Studio',
            version: v.version,
            isSelected: isOld,
          ));
        }
      }
    }

    return list;
  }

  Future<List<SlimCandidateItem>> _scanPython(String home) async {
    final list = <SlimCandidateItem>[];

    // pyenv
    final pyenvDir = Directory('$home/.pyenv/versions');
    if (pyenvDir.existsSync()) {
      try {
        for (final entry in pyenvDir.listSync(followLinks: false)) {
          if (entry is Directory) {
            final ver = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final size = await _quickDirSize(entry);
            list.add(SlimCandidateItem(
              id: 'pyenv_${entry.path.hashCode}',
              path: entry.path,
              title: 'Python $ver (pyenv)',
              subtitle: '独立 pyenv Python 运行时环境，如不使用可卸载',
              sizeBytes: size,
              lastModified: entry.statSync().modified,
              category: SlimmerCategory.multiVersion,
              safety: SafetyRating.caution,
              appName: 'Python',
              version: ver,
              isSelected: false, // 默认不勾选，由用户按需选择删除特定版本
            ));
          }
        }
      } catch (_) {}
    }

    // Conda envs
    final condaDirs = [Directory('$home/miniconda3/envs'), Directory('$home/.conda/envs')];
    for (final cd in condaDirs) {
      if (cd.existsSync()) {
        try {
          for (final entry in cd.listSync(followLinks: false)) {
            if (entry is Directory) {
              final envName = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
              final size = await _quickDirSize(entry);
              list.add(SlimCandidateItem(
                id: 'conda_${entry.path.hashCode}',
                path: entry.path,
                title: 'Conda 虚拟环境 ($envName)',
                subtitle: 'Conda 独立依赖环境，可独立卸载回收空间',
                sizeBytes: size,
                lastModified: entry.statSync().modified,
                category: SlimmerCategory.multiVersion,
                safety: SafetyRating.caution,
                appName: 'Conda',
                version: envName,
                isSelected: false,
              ));
            }
          }
        } catch (_) {}
      }
    }

    return list;
  }

  Future<List<SlimCandidateItem>> _scanNode(String home) async {
    final list = <SlimCandidateItem>[];
    final nvmDir = Directory('$home/.nvm/versions/node');
    if (nvmDir.existsSync()) {
      try {
        final entries = nvmDir.listSync(followLinks: false).whereType<Directory>().toList();
        if (entries.length > 1) {
          entries.sort((a, b) => a.path.compareTo(b.path));
          final newest = entries.last;
          for (final entry in entries) {
            final ver = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final isOld = entry.path != newest.path;
            final size = await _quickDirSize(entry);
            list.add(SlimCandidateItem(
              id: 'nvm_${entry.path.hashCode}',
              path: entry.path,
              title: 'Node.js $ver (NVM)',
              subtitle: isOld ? 'NVM 历史版本，若当前项目无需此老版本可勾选移除' : '最新 NVM Node 版本（建议保留）',
              sizeBytes: size,
              lastModified: entry.statSync().modified,
              category: SlimmerCategory.multiVersion,
              safety: SafetyRating.caution,
              appName: 'Node.js',
              version: ver,
              isSelected: isOld,
            ));
          }
        }
      } catch (_) {}
    }
    return list;
  }

  Future<List<SlimCandidateItem>> _scanJava(String home) async {
    final list = <SlimCandidateItem>[];
    final jvmDir = Directory('/Library/Java/JavaVirtualMachines');
    if (jvmDir.existsSync()) {
      try {
        final entries = jvmDir.listSync(followLinks: false).whereType<Directory>().toList();
        if (entries.length > 1) {
          for (final entry in entries) {
            final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
            final size = await _quickDirSize(entry);
            list.add(SlimCandidateItem(
              id: 'jdk_${entry.path.hashCode}',
              path: entry.path,
              title: 'Java JDK ($name)',
              subtitle: '全局已安装 JDK 虚拟机，可按需勾选移除不再使用的旧版本',
              sizeBytes: size,
              lastModified: entry.statSync().modified,
              category: SlimmerCategory.multiVersion,
              safety: SafetyRating.caution,
              appName: 'Java JDK',
              version: name,
              isSelected: false,
            ));
          }
        }
      } catch (_) {}
    }
    return list;
  }

  /// 异步计算目录大小，每处理 200 个文件后 yield 控制权给 Flutter 框架
  Future<int> _quickDirSize(Directory dir, {int maxDepth = 4}) async {
    int total = 0;
    int fileCount = 0;

    Future<void> walk(Directory d, int depth) async {
      if (depth > maxDepth) return;
      try {
        for (final e in d.listSync(followLinks: false)) {
          if (e is File) {
            total += e.statSync().size;
            fileCount++;
            if (fileCount % 200 == 0) {
              await Future(() {}); // yield 控制权
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

class _VersionDir {
  final String path;
  final String product;
  final String version;
  final DateTime modified;
  final String sourceLabel;
  _VersionDir(this.path, this.product, this.version, this.modified, this.sourceLabel);
}
