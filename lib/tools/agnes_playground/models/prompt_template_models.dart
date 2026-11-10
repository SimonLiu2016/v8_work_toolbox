import 'playground_models.dart';

/// 提示词效果库体系分类枚举。
enum TemplateMajorCategory {
  camera('camera', '镜头语言与运镜'),
  dynamics('dynamics', '复杂动作与交互'),
  vfx('vfx', '物理拟真与粒子特效'),
  lighting('lighting', '光影氛围与材质'),
  artStyle('art_style', '艺术风格与渲染');

  final String id;
  final String label;

  const TemplateMajorCategory(this.id, this.label);

  static TemplateMajorCategory? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 某特定模型下的实测评测样张/样片元数据。
class TemplateModelBenchmark {
  final String providerId;
  final String modelName;
  final String modelVersion;
  final String sampleMediaPath;
  final String testedPrompt;
  final int qualityRating; // 1 ~ 5
  final bool isRecommended;
  final DateTime verifiedAt;
  final Map<String, dynamic>? extraParams;

  const TemplateModelBenchmark({
    required this.providerId,
    required this.modelName,
    this.modelVersion = '',
    required this.sampleMediaPath,
    required this.testedPrompt,
    this.qualityRating = 5,
    this.isRecommended = true,
    required this.verifiedAt,
    this.extraParams,
  });

  TemplateModelBenchmark copyWith({
    String? providerId,
    String? modelName,
    String? modelVersion,
    String? sampleMediaPath,
    String? testedPrompt,
    int? qualityRating,
    bool? isRecommended,
    DateTime? verifiedAt,
    Map<String, dynamic>? extraParams,
  }) {
    return TemplateModelBenchmark(
      providerId: providerId ?? this.providerId,
      modelName: modelName ?? this.modelName,
      modelVersion: modelVersion ?? this.modelVersion,
      sampleMediaPath: sampleMediaPath ?? this.sampleMediaPath,
      testedPrompt: testedPrompt ?? this.testedPrompt,
      qualityRating: qualityRating ?? this.qualityRating,
      isRecommended: isRecommended ?? this.isRecommended,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      extraParams: extraParams ?? this.extraParams,
    );
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'modelName': modelName,
        'modelVersion': modelVersion,
        'sampleMediaPath': sampleMediaPath,
        'testedPrompt': testedPrompt,
        'qualityRating': qualityRating,
        'isRecommended': isRecommended,
        'verifiedAt': verifiedAt.toIso8601String(),
        if (extraParams != null) 'extraParams': extraParams,
      };

  factory TemplateModelBenchmark.fromJson(Map<String, dynamic> json) {
    return TemplateModelBenchmark(
      providerId: json['providerId'] as String? ?? '',
      modelName: json['modelName'] as String? ?? '',
      modelVersion: json['modelVersion'] as String? ?? '',
      sampleMediaPath: json['sampleMediaPath'] as String? ?? '',
      testedPrompt: json['testedPrompt'] as String? ?? '',
      qualityRating: (json['qualityRating'] as num?)?.toInt() ?? 5,
      isRecommended: json['isRecommended'] as bool? ?? true,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      extraParams: (json['extraParams'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// 提示词模板核心实体类。
class VisualPromptTemplate {
  final String id;
  final String title;
  final String majorCategory; // camera, dynamics, vfx, lighting, art_style
  final String subcategory; // 细分分类，如 "经典运镜", "武打格斗"
  final List<String> tags;
  final PlaygroundChannel channel; // image 或 video
  final String promptTemplate; // 包含 {subject}, {action} 等占位符
  final String? negativePrompt;
  final Map<String, dynamic> recommendedParams;
  final List<TemplateModelBenchmark> benchmarks;
  final bool isBuiltin;
  final DateTime updatedAt;

  const VisualPromptTemplate({
    required this.id,
    required this.title,
    required this.majorCategory,
    required this.subcategory,
    this.tags = const [],
    required this.channel,
    required this.promptTemplate,
    this.negativePrompt,
    this.recommendedParams = const {},
    this.benchmarks = const [],
    this.isBuiltin = false,
    required this.updatedAt,
  });

  /// 从提示词模板中提取出的占位符集合（形如 {subject} ➔ ['subject']）。
  List<String> get placeholders {
    final regex = RegExp(r'\{([a-zA-Z0-9_\u4e00-\u9fa5]+)\}');
    final matches = regex.allMatches(promptTemplate);
    final results = <String>[];
    for (final m in matches) {
      final name = m.group(1);
      if (name != null && !results.contains(name)) {
        results.add(name);
      }
    }
    return List.unmodifiable(results);
  }

  /// 获取针对特定模型的推荐样片（优先匹配型号且标记为 isRecommended，其次最新评星最高的条目）。
  TemplateModelBenchmark? benchmarkFor(String modelName) {
    if (benchmarks.isEmpty) return null;
    final matched = benchmarks.where((b) => b.modelName.toLowerCase() == modelName.toLowerCase()).toList();
    if (matched.isEmpty) {
      // 若无精准匹配，返回任一推荐标杆样片
      return benchmarks.firstWhere((b) => b.isRecommended, orElse: () => benchmarks.first);
    }
    return matched.firstWhere((b) => b.isRecommended, orElse: () => matched.first);
  }

  VisualPromptTemplate copyWith({
    String? id,
    String? title,
    String? majorCategory,
    String? subcategory,
    List<String>? tags,
    PlaygroundChannel? channel,
    String? promptTemplate,
    String? negativePrompt,
    Map<String, dynamic>? recommendedParams,
    List<TemplateModelBenchmark>? benchmarks,
    bool? isBuiltin,
    DateTime? updatedAt,
  }) {
    return VisualPromptTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      majorCategory: majorCategory ?? this.majorCategory,
      subcategory: subcategory ?? this.subcategory,
      tags: tags ?? this.tags,
      channel: channel ?? this.channel,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      recommendedParams: recommendedParams ?? this.recommendedParams,
      benchmarks: benchmarks ?? this.benchmarks,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'majorCategory': majorCategory,
        'subcategory': subcategory,
        'tags': tags,
        'channel': channel.id,
        'promptTemplate': promptTemplate,
        if (negativePrompt != null) 'negativePrompt': negativePrompt,
        'recommendedParams': recommendedParams,
        'benchmarks': benchmarks.map((b) => b.toJson()).toList(),
        'isBuiltin': isBuiltin,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VisualPromptTemplate.fromJson(Map<String, dynamic> json) {
    final channelId = json['channel'] as String? ?? 'video';
    final channel = PlaygroundChannel.fromId(channelId) ?? PlaygroundChannel.video;
    final rawBenchmarks = (json['benchmarks'] as List?) ?? [];
    return VisualPromptTemplate(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      majorCategory: json['majorCategory'] as String? ?? 'camera',
      subcategory: json['subcategory'] as String? ?? '经典运镜',
      tags: ((json['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      channel: channel,
      promptTemplate: json['promptTemplate'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String?,
      recommendedParams: (json['recommendedParams'] as Map?)?.cast<String, dynamic>() ?? const {},
      benchmarks: rawBenchmarks
          .whereType<Map>()
          .map((b) => TemplateModelBenchmark.fromJson(b.cast<String, dynamic>()))
          .toList(),
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
