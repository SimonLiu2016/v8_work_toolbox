import 'package:flutter/foundation.dart';

/// 项目构建产物的技术栈分组
enum ProjectTechStack {
  flutterDart('Flutter / Dart', 'pubspec.yaml', '.dart_tool', 'build'),
  node('Node', 'package.json', 'node_modules', 'dist'),
  gradleAndroid('Gradle / Android', 'build.gradle', '.gradle', 'build'),
  other('其他构建产物', null, null, null);

  final String label;
  final String? manifestSignal;
  final String? typicalArtifact;
  final String? secondArtifact;

  const ProjectTechStack(this.label, this.manifestSignal, this.typicalArtifact, this.secondArtifact);
}

enum SlimmerCategory {
  orphanApp('已卸载残留', '应用已从系统删除，但配置或缓存仍然遗留'),
  multiVersion('多版本与升级遗留', 'IDE 或语言运行时的多个历史版本，旧版本大多废弃'),
  buildCache('开发构建缓存', 'Xcode DerivedData、依赖仓库等跨项目共享缓存，删除后不影响任何单个项目'),
  projectArtifacts('项目构建产物', '散落在各项目工作区内的 build / node_modules / dist 等，按项目根聚合'),
  largeDownloads('超大安装与归档包', '长期未清理的 .dmg, .pkg, .iso, .zip 安装包'),
  aiDiagnostics('AI 智能研判项', '由 AI 深入分析识别出的未知大目录或可疑文件');

  final String label;
  final String description;
  const SlimmerCategory(this.label, this.description);
}

enum SafetyRating {
  safe('安全清理', '可随时安全清理，支持废纸篓一键还原'),
  caution('谨慎确认', '包含历史偏好或旧配置，建议快速核对后清理'),
  danger('高风险', '涉及底层依赖或运行中环境，不建议随意清理');

  final String label;
  final String description;
  const SafetyRating(this.label, this.description);
}

/// 单个项目根内被收集的产物目录
@immutable
class ProjectArtifact {
  final String path;
  final String dirName;
  final int sizeBytes;
  final ProjectTechStack tech;

  const ProjectArtifact({
    required this.path,
    required this.dirName,
    required this.sizeBytes,
    required this.tech,
  });
}

@immutable
class SlimCandidateItem {
  final String id;
  final String path;
  final String title;
  final String subtitle;
  final int sizeBytes;
  final DateTime? lastModified;
  final SlimmerCategory category;
  final SafetyRating safety;
  final String? appName;
  final String? version;
  final bool isSelected;
  final String? aiAdvice;
  final bool isAiAnalyzed;
  final bool userMarkedKeep;
  final bool requiresAdmin;

  /// 项目构建产物：该根内的产物目录明细（仅 [SlimmerCategory.projectArtifacts] 非空）
  final List<ProjectArtifact> artifacts;

  /// 技术栈归属（仅 [SlimmerCategory.projectArtifacts] 有效）
  final ProjectTechStack? techStack;

  /// 扫描预算耗尽：该条目的产物收集不完整，已发现部分照常呈现
  final bool scanIncomplete;

  const SlimCandidateItem({
    required this.id,
    required this.path,
    required this.title,
    required this.subtitle,
    required this.sizeBytes,
    this.lastModified,
    required this.category,
    this.safety = SafetyRating.safe,
    this.appName,
    this.version,
    this.isSelected = true,
    this.aiAdvice,
    this.isAiAnalyzed = false,
    this.userMarkedKeep = false,
    this.requiresAdmin = false,
    this.artifacts = const [],
    this.techStack,
    this.scanIncomplete = false,
  });

  SlimCandidateItem copyWith({
    String? id,
    String? path,
    String? title,
    String? subtitle,
    int? sizeBytes,
    DateTime? lastModified,
    SlimmerCategory? category,
    SafetyRating? safety,
    String? appName,
    String? version,
    bool? isSelected,
    String? aiAdvice,
    bool? isAiAnalyzed,
    bool? userMarkedKeep,
    bool? requiresAdmin,
    List<ProjectArtifact>? artifacts,
    ProjectTechStack? techStack,
    bool? scanIncomplete,
  }) {
    return SlimCandidateItem(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastModified: lastModified ?? this.lastModified,
      category: category ?? this.category,
      safety: safety ?? this.safety,
      appName: appName ?? this.appName,
      version: version ?? this.version,
      isSelected: isSelected ?? this.isSelected,
      aiAdvice: aiAdvice ?? this.aiAdvice,
      isAiAnalyzed: isAiAnalyzed ?? this.isAiAnalyzed,
      userMarkedKeep: userMarkedKeep ?? this.userMarkedKeep,
      requiresAdmin: requiresAdmin ?? this.requiresAdmin,
      artifacts: artifacts ?? this.artifacts,
      techStack: techStack ?? this.techStack,
      scanIncomplete: scanIncomplete ?? this.scanIncomplete,
    );
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// AI 批量诊断的可配置参数
class SlimerBatchConfig {
  /// 并发数 (1 = 串行)
  final int concurrency;

  /// 最大重试次数
  final int maxRetries;

  const SlimerBatchConfig({
    this.concurrency = 1,
    this.maxRetries = 10,
  });

  factory SlimerBatchConfig.fromJson(Map<String, dynamic> json) {
    return SlimerBatchConfig(
      concurrency: (json['batchConcurrency'] as num?)?.toInt().clamp(1, 5) ?? 1,
      maxRetries: (json['batchMaxRetries'] as num?)?.toInt().clamp(1, 10) ?? 10,
    );
  }

  Map<String, dynamic> toJson() => {
    'batchConcurrency': concurrency,
    'batchMaxRetries': maxRetries,
  };
}

/// 瘦身工具的用户自定义配置（额外项目根 + 产物类型开关）
@immutable
class SlimerProjectArtifactConfig {
  /// 用户额外指定的项目根（豁免 manifest 门控，强制进入产物收集）
  final List<String> extraRoots;

  /// 产物类型开关：key 为目录名，value 是否收集
  final Map<String, bool> artifactOptions;

  const SlimerProjectArtifactConfig({
    this.extraRoots = const [],
    this.artifactOptions = const {},
  });

  bool isEnabled(String dirName) => artifactOptions[dirName] ?? true;

  factory SlimerProjectArtifactConfig.fromJson(Map<String, dynamic> json) {
    final rawRoots = json['extraRoots'];
    final rawOptions = json['artifactOptions'];
    return SlimerProjectArtifactConfig(
      extraRoots: rawRoots is List
          ? rawRoots.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
          : const <String>[],
      artifactOptions: rawOptions is Map
          ? rawOptions.map((k, v) => MapEntry(k.toString(), v == true))
          : const <String, bool>{},
    );
  }

  Map<String, dynamic> toJson() => {
    'extraRoots': extraRoots,
    'artifactOptions': artifactOptions,
  };
}
