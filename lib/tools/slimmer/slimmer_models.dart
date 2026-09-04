import 'package:flutter/foundation.dart';

enum SlimmerCategory {
  orphanApp('已卸载残留', '应用已从系统删除，但配置或缓存仍然遗留'),
  multiVersion('多版本与升级遗留', 'IDE 或语言运行时的多个历史版本，旧版本大多废弃'),
  buildCache('开发构建缓存', 'Xcode DerivedData、依赖仓库与本地构建临时产物'),
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
