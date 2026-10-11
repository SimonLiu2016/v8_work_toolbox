/// AI 短视频工坊的数据模型。
///
/// 全部以 JSON 文件落盘于 `AppSupportDir/video_studio/`（见 design.md D4：
/// 不引入 SQLite——素材天然在文件系统里，剧集元数据只有百 KB 级，且用户要能
/// 直接用 Finder 打开备份）。这些类是那层 JSON 的唯一 schema 定义处，字段名
/// 直接就是磁盘上的键名，改动字段先想清楚旧文件怎么读。
library;

import 'package:flutter/foundation.dart' show immutable;

/// 制作类型。三选一，全局只有这三支管线（spec: 制作类型管线预设）。
///
/// 值的字符串形态会写进 `series_profile.json`，所以顺序与拼写都不要变——
/// 改了就等于把用户已有的剧集变成未知类型。
enum StudioProductionType {
  /// 真人剧情短剧：默认走图生视频（I2V）商业 API。
  drama('drama', '真人剧情短剧', '真人出镜或拟真画面，节奏快、冲突强，适合爽剧与情感短剧'),

  /// 二次元 / 动态漫：默认走本地 Ken Burns 动效，零成本。
  anime('anime', '二次元 / 动态漫', '动漫或动态漫风格，运镜夸张，适合二次元与漫改'),

  /// 图文解说 / 知识故事：默认 Ken Burns 静态推拉，不调用外部视频 API。
  narration('narration', '图文解说 / 知识故事', '以旁白与图文为主，适合知识科普与故事解说');

  final String id;
  final String label;
  final String description;

  const StudioProductionType(this.id, this.label, this.description);

  static StudioProductionType fromId(String? value) {
    return values.firstWhere(
      (t) => t.id == value,
      orElse: () => drama,
    );
  }
}

/// 景别。分镜的必备字段之一（spec: 结构化分镜拆解）。
enum StudioShotSize {
  closeUp('close_up', '特写'),
  mediumCloseUp('medium_close_up', '近景'),
  medium('medium', '中景'),
  full('full', '全景'),
  long('long', '远景'),
  extremeLong('extreme_long', '大远景');

  final String id;
  final String label;

  const StudioShotSize(this.id, this.label);

  static StudioShotSize fromId(String? value) {
    if (value == null) return medium;
    final normalized = value.trim().toLowerCase();
    return values.firstWhere(
      (s) =>
          s.id == normalized ||
          s.label == value.trim() ||
          (normalized == 'wide' && s == full) ||
          (normalized == '全景' && s == full) ||
          (normalized == '特写' && s == closeUp) ||
          (normalized == '近景' && s == mediumCloseUp) ||
          (normalized == '中景' && s == medium) ||
          (normalized == '远景' && s == long) ||
          (normalized == '大远景' && s == extremeLong),
      orElse: () => medium,
    );
  }
}

/// 情绪基调标签。驱动 BGM 匹配与运镜推荐两个下游。
enum ShotMood {
  depressing('depressing', '压抑'),
  excited('excited', '激动'),
  warm('warm', '温馨'),
  battle('battle', '战斗'),
  suspense('suspense', '悬念'),
  relaxed('relaxed', '轻松'),
  sad('sad', '悲伤');

  final String id;
  final String label;

  const ShotMood(this.id, this.label);

  /// 匹配用的标签集合：情绪标签映射表以 `id` 为键（`BgmMatcher` 读它）。
  static ShotMood fromId(String? value) {
    return values.firstWhere((m) => m.id == value, orElse: () => warm);
  }
}

/// 分镜功能位。开场 / 推进 / 爆发 / 收尾这类语义位置。
enum ShotFunction {
  opening('opening', '开场'),
  advance('advance', '推进'),
  burst('burst', '爆发'),
  ending('ending', '收尾');

  final String id;
  final String label;

  const ShotFunction(this.id, this.label);

  static ShotFunction fromId(String? value) {
    return values.firstWhere((f) => f.id == value, orElse: () => advance);
  }
}

/// 角色资产卡上的一个命名形态（State Variation）。
///
/// spec 要求形态只存**相对**基础 Prompt 的差异词，合并后才形成完整 Prompt，
/// 这样改基础 Prompt 时所有形态跟着走，不必逐个手工同步。
class CharacterVariation {
  final String id;
  final String name;

  /// 正向差异词（追加到角色基础正向 Prompt 之后）。
  final String positiveDelta;

  /// 负向差异词（追加到角色基础负向 Prompt 之后）。
  final String negativeDelta;

  final bool active;

  const CharacterVariation({
    required this.id,
    required this.name,
    this.positiveDelta = '',
    this.negativeDelta = '',
    this.active = false,
  });

  CharacterVariation copyWith({
    String? id,
    String? name,
    String? positiveDelta,
    String? negativeDelta,
    bool? active,
  }) {
    return CharacterVariation(
      id: id ?? this.id,
      name: name ?? this.name,
      positiveDelta: positiveDelta ?? this.positiveDelta,
      negativeDelta: negativeDelta ?? this.negativeDelta,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'positive_delta': positiveDelta,
    'negative_delta': negativeDelta,
    'active': active,
  };

  static CharacterVariation fromJson(Map<String, dynamic> json) {
    return CharacterVariation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      positiveDelta: json['positive_delta'] as String? ?? '',
      negativeDelta: json['negative_delta'] as String? ?? '',
      active: json['active'] as bool? ?? false,
    );
  }
}

/// IP 主库中的常驻角色资产卡（`characters/<id>/config.json`）。
class CharacterCard {
  final String id;
  final String name;

  /// 中文外貌描述（用户输入原文，供"生成 Prompt"用）。
  final String descriptionZh;

  /// 英文正向基础 Prompt。
  final String basePromptPositive;

  /// 英文负向基础 Prompt。
  final String basePromptNegative;

  /// 基准参考图相对路径（角色目录下的文件名）。
  final List<String> referenceImages;

  /// 绑定的 TTS 音色标识符；为空则用剧集类型默认音色。
  final String ttsVoiceId;

  /// 命名形态列表。第一个通常是"默认"。
  final List<CharacterVariation> variations;

  final DateTime updatedAt;

  const CharacterCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.basePromptPositive = '',
    this.basePromptNegative = '',
    this.referenceImages = const [],
    this.ttsVoiceId = '',
    this.variations = const [],
    required this.updatedAt,
  });

  /// 当前激活形态；没有激活形态时返回 null（调用方按基础 Prompt 处理）。
  CharacterVariation? get activeVariation {
    for (final v in variations) {
      if (v.active) return v;
    }
    return null;
  }

  CharacterCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? basePromptPositive,
    String? basePromptNegative,
    List<String>? referenceImages,
    String? ttsVoiceId,
    List<CharacterVariation>? variations,
    DateTime? updatedAt,
  }) {
    return CharacterCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      basePromptPositive: basePromptPositive ?? this.basePromptPositive,
      basePromptNegative: basePromptNegative ?? this.basePromptNegative,
      referenceImages: referenceImages ?? this.referenceImages,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      variations: variations ?? this.variations,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description_zh': descriptionZh,
    'base_prompt_positive': basePromptPositive,
    'base_prompt_negative': basePromptNegative,
    'reference_images': referenceImages,
    'tts_voice_id': ttsVoiceId,
    'variations': variations.map((v) => v.toJson()).toList(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static CharacterCard fromJson(Map<String, dynamic> json) {
    return CharacterCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      descriptionZh: json['description_zh'] as String? ?? '',
      basePromptPositive: json['base_prompt_positive'] as String? ?? '',
      basePromptNegative: json['base_prompt_negative'] as String? ?? '',
      referenceImages:
          (json['reference_images'] as List?)?.cast<String>() ?? const [],
      ttsVoiceId: json['tts_voice_id'] as String? ?? '',
      variations:
          (json['variations'] as List?)
              ?.whereType<Map>()
              .map((e) => CharacterVariation.fromJson(
                  e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 场景资产卡（`common_scenes/<id>/config.json`）。
class SceneCard {
  final String id;
  final String name;

  /// 中文描述。
  final String descriptionZh;

  /// 英文场景 Prompt（直接进入最终生图 Prompt）。
  final String promptEn;

  /// 参考图路径列表。
  final List<String> referenceImages;

  /// 是否全剧通用（否则仅本剧可见——layer 语义由目录位置决定，这里只是标记）。
  final bool sharedAcrossSeries;

  final DateTime updatedAt;

  const SceneCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.promptEn = '',
    this.referenceImages = const [],
    this.sharedAcrossSeries = false,
    required this.updatedAt,
  });

  SceneCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? promptEn,
    List<String>? referenceImages,
    bool? sharedAcrossSeries,
    DateTime? updatedAt,
  }) {
    return SceneCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      promptEn: promptEn ?? this.promptEn,
      referenceImages: referenceImages ?? this.referenceImages,
      sharedAcrossSeries: sharedAcrossSeries ?? this.sharedAcrossSeries,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description_zh': descriptionZh,
    'prompt_en': promptEn,
    'reference_images': referenceImages,
    'shared_across_series': sharedAcrossSeries,
    'updated_at': updatedAt.toIso8601String(),
  };

  static SceneCard fromJson(Map<String, dynamic> json) {
    return SceneCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      descriptionZh: json['description_zh'] as String? ?? '',
      promptEn: json['prompt_en'] as String? ?? '',
      referenceImages:
          (json['reference_images'] as List?)?.cast<String>() ?? const [],
      sharedAcrossSeries: json['shared_across_series'] as bool? ?? false,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 一集的剧情记忆条目（跨集连贯性注入的数据源）。
class EpisodeMemory {
  final String episodeId;
  final String title;

  /// 精炼摘要（spec: 剧情记忆库只保留 200 字以内，控制注入 Token）。
  final String summary;

  /// 本集末尾的悬念钩子。
  final String hook;

  final int shotCount;
  final DateTime updatedAt;

  const EpisodeMemory({
    required this.episodeId,
    this.title = '',
    this.summary = '',
    this.hook = '',
    this.shotCount = 0,
    required this.updatedAt,
  });

  EpisodeMemory copyWith({
    String? episodeId,
    String? title,
    String? summary,
    String? hook,
    int? shotCount,
    DateTime? updatedAt,
  }) {
    return EpisodeMemory(
      episodeId: episodeId ?? this.episodeId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      hook: hook ?? this.hook,
      shotCount: shotCount ?? this.shotCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'episode_id': episodeId,
    'title': title,
    'summary': summary,
    'hook': hook,
    'shot_count': shotCount,
    'updated_at': updatedAt.toIso8601String(),
  };

  static EpisodeMemory fromJson(Map<String, dynamic> json) {
    return EpisodeMemory(
      episodeId: json['episode_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      hook: json['hook'] as String? ?? '',
      shotCount: (json['shot_count'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 剧集主库元数据（`series_profile.json`）。
class StudioSeries {
  final String id;
  final String name;
  final StudioProductionType productionType;

  /// 世界观设定文本（创意孵化确认后写入）。
  final String worldview;

  /// 全局风格词（进入每条生图 Prompt 的"风格锁"）。
  final String styleTokens;

  /// 默认 TTS 音色（角色未绑定时使用）。
  final String defaultVoiceId;

  /// 剧情记忆库。
  final List<EpisodeMemory> memories;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StudioSeries({
    required this.id,
    required this.name,
    this.productionType = StudioProductionType.drama,
    this.worldview = '',
    this.styleTokens = '',
    this.defaultVoiceId = '',
    this.memories = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  StudioSeries copyWith({
    String? id,
    String? name,
    StudioProductionType? productionType,
    String? worldview,
    String? styleTokens,
    String? defaultVoiceId,
    List<EpisodeMemory>? memories,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudioSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      productionType: productionType ?? this.productionType,
      worldview: worldview ?? this.worldview,
      styleTokens: styleTokens ?? this.styleTokens,
      defaultVoiceId: defaultVoiceId ?? this.defaultVoiceId,
      memories: memories ?? this.memories,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'production_type': productionType.id,
    'worldview': worldview,
    'style_tokens': styleTokens,
    'default_voice_id': defaultVoiceId,
    'memories': memories.map((m) => m.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static StudioSeries fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return StudioSeries(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      productionType:
          StudioProductionType.fromId(json['production_type'] as String?),
      worldview: json['worldview'] as String? ?? '',
      styleTokens: json['style_tokens'] as String? ?? '',
      defaultVoiceId: json['default_voice_id'] as String? ?? '',
      memories:
          (json['memories'] as List?)
              ?.whereType<Map>()
              .map((e) => EpisodeMemory.fromJson(
                  e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? now,
    );
  }
}

/// 一集（`episodes/<ep-id>/storyboard.json`）。
class StudioEpisode {
  final String id;
  final String seriesId;

  /// 集序号（1 起）。
  final int index;

  final String title;

  /// 本集粗剧情大纲（AI 拆分分镜的输入）。
  final String synopsis;

  /// 分镜列表。
  final List<StudioShot> shots;

  /// 该集覆盖使用的角色形态（spec: 单集可覆盖 IP 主库形态）。
  /// key = 角色卡 id，value = 形态 id。
  final Map<String, String> variationOverrides;

  /// 片段列表（spec: 片段边界划分）。
  ///
  /// 空列表表示这是旧版数据、尚未迁移。加载时由
  /// [StudioEpisode.migrateSegmentsIfNeeded] 自动补齐，见 design 决策 2。
  final List<StudioSegment> segments;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StudioEpisode({
    required this.id,
    required this.seriesId,
    this.index = 1,
    this.title = '',
    this.synopsis = '',
    this.shots = const [],
    this.variationOverrides = const {},
    this.segments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  StudioEpisode copyWith({
    String? id,
    String? seriesId,
    int? index,
    String? title,
    String? synopsis,
    List<StudioShot>? shots,
    Map<String, String>? variationOverrides,
    List<StudioSegment>? segments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudioEpisode(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      index: index ?? this.index,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      shots: shots ?? this.shots,
      variationOverrides: variationOverrides ?? this.variationOverrides,
      segments: segments ?? this.segments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'series_id': seriesId,
    'index': index,
    'title': title,
    'synopsis': synopsis,
    'shots': shots.map((s) => s.toJson()).toList(),
    'variation_overrides': variationOverrides,
    'segments': segments.map((s) => s.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static StudioEpisode fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return StudioEpisode(
      id: json['id'] as String? ?? '',
      seriesId: json['series_id'] as String? ?? '',
      index: (json['index'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      synopsis: json['synopsis'] as String? ?? '',
      shots:
          (json['shots'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  StudioShot.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      variationOverrides:
          (json['variation_overrides'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v as String),
          ) ??
          const {},
      segments:
          (json['segments'] as List?)
              ?.whereType<Map>()
              .map((e) =>
                  StudioSegment.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? now,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? now,
    );
  }

  /// 旧版数据迁移：没有 `segments` 时按分镜顺序每 2–3 镜归组（spec: 旧版分镜数据迁移）。
  ///
  /// **纯函数，不落盘**（design 决策 2）：读取路径不该有写副作用——失败会污染
  /// 用户数据，也让「打开即修改」难以解释。结果保留到下一次 [saveEpisode] 自然
  /// 写回；幂等由「`segments` 非空即跳过」保证。
  ///
  /// 迁移分组用 3 镜而不是 2 镜：2 镜一组会让 8 镜的剧集产出 4 个片段，而 AI
  /// 的片段边界通常更粗（1–4 镜），取中值更接近用户的真实意图。
  StudioEpisode migrateSegmentsIfNeeded() {
    if (segments.isNotEmpty || shots.isEmpty) return this;
    return copyWith(
      segments: buildLegacySegments(shots.map((s) => s.number).toList()),
    );
  }

  /// 按镜号序列构建旧版迁移用的片段分组。
  ///
  /// 独立成静态方法以便单测直接验证分组规则，不必构造整个 [StudioEpisode]。
  static List<StudioSegment> buildLegacySegments(List<int> shotNumbers) {
    if (shotNumbers.isEmpty) return const [];
    const legacyReason = '旧版数据自动分组';
    final result = <StudioSegment>[];
    var cursor = 0;
    while (cursor < shotNumbers.length) {
      // 剩 4 镜时拆 2+2 而不是 3+1：末组只含 1 镜没有「片段」的意义。
      final remaining = shotNumbers.length - cursor;
      final size = remaining == 4 ? 2 : (remaining >= 3 ? 3 : remaining);
      final group = shotNumbers.sublist(cursor, cursor + size);
      result.add(StudioSegment(
        id: 'seg-${result.length + 1}',
        shotNumbers: group,
        boundaryReason: legacyReason,
        targetDurationSec: group.length * 4,
      ));
      cursor += size;
    }
    return result;
  }
}

/// 分镜的生成状态。UI 徽章与队列都读它（spec: 生图任务队列）。
enum ShotGenerationStatus {
  pending('pending', '等待中'),
  generating('generating', '生成中'),
  done('done', '完成'),
  failed('failed', '失败');

  final String id;
  final String label;

  const ShotGenerationStatus(this.id, this.label);

  static ShotGenerationStatus fromId(String? value) {
    return values.firstWhere((s) => s.id == value, orElse: () => pending);
  }
}

/// 单个分镜（`storyboard.json` 的 shots 数组元素）。
class StudioShot {
  /// 镜号，1 起连续。
  final int number;

  /// 建议时长（秒，2-6）。
  final double durationSec;

  final StudioShotSize shotSize;

  /// 情绪基调标签。驱动 BGM 匹配与运镜推荐。
  final String mood;

  final ShotFunction function;

  /// 画面动作描述（中文，供用户审阅）。
  final String actionZh;

  /// 角色台词或旁白（中文）。
  final String dialogue;

  /// 出场角色卡 id 列表。
  final List<String> characterIds;

  /// 场景卡 id。
  final String sceneId;

  /// 运镜方案关键词（如 "low angle push-in"），由用户选择后写入。
  final String cameraMove;

  /// 最终组装好的英文生图 Prompt（系统维护，字段级缓存）。
  final String assembledPrompt;

  /// 已生成关键帧文件名（相对 `frames/`）。
  final String? framePath;

  /// 已生成视频片段文件名（相对 `clips/`）。
  final String? clipPath;

  /// 台词音频文件名（相对 `audio/`）。
  final String? audioPath;

  /// 音频实际时长（毫秒）。TTS 合成后回填，SRT 时间轴用它。
  final int? audioDurationMs;

  /// 选中的 BGM 文件名（相对全局库或 IP 库）。
  final String? bgmPath;

  /// 所属片段 id。空串表示尚未归入任何片段（旧版数据迁移前的中间态）。
  final String segmentId;

  /// 连续性台账（spec: 连续性台账字段）。
  ///
  /// 旧版数据为 [ShotContinuity.empty]；UI 靠 [ShotContinuity.isEmpty] 提示
  /// 用户补台账，而不是把空值当成真实的「空手」状态。
  final ShotContinuity continuity;

  final ShotGenerationStatus status;

  const StudioShot({
    required this.number,
    this.durationSec = 3,
    this.shotSize = StudioShotSize.medium,
    this.mood = 'warm',
    this.function = ShotFunction.advance,
    this.actionZh = '',
    this.dialogue = '',
    this.characterIds = const [],
    this.sceneId = '',
    this.cameraMove = '',
    this.assembledPrompt = '',
    this.framePath,
    this.clipPath,
    this.audioPath,
    this.audioDurationMs,
    this.bgmPath,
    this.segmentId = '',
    this.continuity = ShotContinuity.empty,
    this.status = ShotGenerationStatus.pending,
  });

  /// 台词字数上限：建议时长(秒) × 5 字/秒（spec: 台词字数自动校验）。
  int get dialogueCharLimit => (durationSec * 5).floor();

  bool get isDialogueTooLong {
    final trimmed = dialogue.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.length > dialogueCharLimit;
  }

  /// 预估台词时长（秒）。从台词中解析如“（预估2.5秒）”，无明确标注时按正常语速与时长推算。
  double get dialogueEstimatedSec {
    final match = RegExp(r'[（\(]预估\s*([\d\.]+)\s*秒[）\)]').firstMatch(dialogue);
    if (match != null) {
      final parsed = double.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    final cleanText = dialogue.replaceAll(RegExp(r'[（\(][^）\)]*[）\)]'), '').trim();
    if (cleanText.isEmpty) return 0.0;
    return (cleanText.length / 4.0).clamp(1.0, durationSec);
  }

  StudioShot copyWith({
    int? number,
    double? durationSec,
    StudioShotSize? shotSize,
    String? mood,
    ShotFunction? function,
    String? actionZh,
    String? dialogue,
    List<String>? characterIds,
    String? sceneId,
    String? cameraMove,
    String? assembledPrompt,
    String? framePath,
    String? clipPath,
    String? audioPath,
    int? audioDurationMs,
    String? bgmPath,
    String? segmentId,
    ShotContinuity? continuity,
    ShotGenerationStatus? status,
  }) {
    return StudioShot(
      number: number ?? this.number,
      durationSec: durationSec ?? this.durationSec,
      shotSize: shotSize ?? this.shotSize,
      mood: mood ?? this.mood,
      function: function ?? this.function,
      actionZh: actionZh ?? this.actionZh,
      dialogue: dialogue ?? this.dialogue,
      characterIds: characterIds ?? this.characterIds,
      sceneId: sceneId ?? this.sceneId,
      cameraMove: cameraMove ?? this.cameraMove,
      assembledPrompt: assembledPrompt ?? this.assembledPrompt,
      framePath: framePath ?? this.framePath,
      clipPath: clipPath ?? this.clipPath,
      audioPath: audioPath ?? this.audioPath,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
      bgmPath: bgmPath ?? this.bgmPath,
      segmentId: segmentId ?? this.segmentId,
      continuity: continuity ?? this.continuity,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'duration_sec': durationSec,
    'shot_size': shotSize.id,
    'mood': mood,
    'function': function.id,
    'action_zh': actionZh,
    'dialogue': dialogue,
    'character_ids': characterIds,
    'scene_id': sceneId,
    'camera_move': cameraMove,
    'assembled_prompt': assembledPrompt,
    'frame_path': framePath,
    'clip_path': clipPath,
    'audio_path': audioPath,
    'audio_duration_ms': audioDurationMs,
    'bgm_path': bgmPath,
    'segment_id': segmentId,
    'continuity': continuity.toJson(),
    'status': status.id,
  };

  static StudioShot fromJson(Map<String, dynamic> json) {
    final continuityRaw = json['continuity'];
    return StudioShot(
      number: (json['number'] as num?)?.toInt() ?? 1,
      durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 3,
      shotSize: StudioShotSize.fromId(json['shot_size'] as String?),
      mood: json['mood'] as String? ?? 'warm',
      function: ShotFunction.fromId(json['function'] as String?),
      actionZh: json['action_zh'] as String? ?? '',
      dialogue: json['dialogue'] as String? ?? '',
      characterIds:
          (json['character_ids'] as List?)?.cast<String>() ?? const [],
      sceneId: json['scene_id'] as String? ?? '',
      cameraMove: json['camera_move'] as String? ?? '',
      assembledPrompt: json['assembled_prompt'] as String? ?? '',
      framePath: json['frame_path'] as String?,
      clipPath: json['clip_path'] as String?,
      audioPath: json['audio_path'] as String?,
      audioDurationMs: (json['audio_duration_ms'] as num?)?.toInt(),
      bgmPath: json['bgm_path'] as String?,
      segmentId: json['segment_id'] as String? ?? '',
      continuity: continuityRaw is Map
          ? ShotContinuity.fromJson(
              continuityRaw.map((k, v) => MapEntry(k as String, v)))
          : ShotContinuity.empty,
      status: ShotGenerationStatus.fromId(json['status'] as String?),
    );
  }
}

/// 分镜的连续性台账（spec: 连续性台账字段）。
///
/// 存在的唯一目的是让「片段提示词」能写出绝对状态而不是"延续上一镜"。
/// 字段分两类：
/// - **可推导**（`worldPosition` / `screenPosition` / `lightingState`）：由 AI 或
///   系统基于前一镜推导，用户可改。
/// - **只能来自原文**（`holdingLeft` / `holdingRight` / `stateChanges`）：AI 不得
///   自行桥接。原文给出初始状态就直接用，不补"道具如何被拿到手里"（spec: 禁止 AI
///   自行桥接）。所以这三个是必填项——缺一个就意味着 AI 在替用户编剧情。
@immutable
class ShotContinuity {
  /// 相对门、桌、窗等固定地标的世界坐标（与机位无关）。
  final String worldPosition;

  /// 当前机位下的画面左右/前后/遮挡关系。
  final String screenPosition;

  /// 左手持有物；空串表示空手。
  final String holdingLeft;

  /// 右手持有物；空串表示空手。
  final String holdingRight;

  /// 主光方向与色温。
  final String lightingState;

  /// 本镜发生的状态变化列表。每项必须来源于剧情原文或用户手动编辑。
  final List<String> stateChanges;

  const ShotContinuity({
    this.worldPosition = '',
    this.screenPosition = '',
    this.holdingLeft = '',
    this.holdingRight = '',
    this.lightingState = '',
    this.stateChanges = const [],
  });

  /// 旧版 `storyboard.json` 没有这个对象时的兜底。
  ///
  /// 空串而不是 null：下游拼提示词时可以直接 `if (x.isNotEmpty)`，不需要
  /// 到处判空。代价是「没填」与「空手」共用同一个表示——用
  /// [isEmpty] 区分，UI 层靠它提示用户补台账。
  static const ShotContinuity empty = ShotContinuity();

  /// 是否完全未填写（用于提示用户补台账，而不是当成真实的空手状态）。
  bool get isEmpty =>
      worldPosition.isEmpty &&
      screenPosition.isEmpty &&
      holdingLeft.isEmpty &&
      holdingRight.isEmpty &&
      lightingState.isEmpty &&
      stateChanges.isEmpty;

  ShotContinuity copyWith({
    String? worldPosition,
    String? screenPosition,
    String? holdingLeft,
    String? holdingRight,
    String? lightingState,
    List<String>? stateChanges,
  }) {
    return ShotContinuity(
      worldPosition: worldPosition ?? this.worldPosition,
      screenPosition: screenPosition ?? this.screenPosition,
      holdingLeft: holdingLeft ?? this.holdingLeft,
      holdingRight: holdingRight ?? this.holdingRight,
      lightingState: lightingState ?? this.lightingState,
      stateChanges: stateChanges ?? this.stateChanges,
    );
  }

  Map<String, dynamic> toJson() => {
    'world_position': worldPosition,
    'screen_position': screenPosition,
    'holding_left': holdingLeft,
    'holding_right': holdingRight,
    'lighting_state': lightingState,
    'state_changes': stateChanges,
  };

  static ShotContinuity fromJson(Map<String, dynamic> json) {
    return ShotContinuity(
      worldPosition: json['world_position'] as String? ?? '',
      screenPosition: json['screen_position'] as String? ?? '',
      holdingLeft: json['holding_left'] as String? ?? '',
      holdingRight: json['holding_right'] as String? ?? '',
      lightingState: json['lighting_state'] as String? ?? '',
      stateChanges:
          (json['state_changes'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// 片段的生成状态。与 [ShotGenerationStatus] 分开：片段状态描述的是「这一次
/// 云端调用」，分镜状态描述的是「这一镜的产物」。
enum SegmentStatus {
  pending('pending', '待生成'),
  generating('generating', '生成中'),
  done('done', '完成'),
  failed('failed', '失败');

  final String id;
  final String label;

  const SegmentStatus(this.id, this.label);

  static SegmentStatus fromId(String? value) {
    return values.firstWhere((s) => s.id == value, orElse: () => pending);
  }
}

/// 一个片段：连续叙事节拍的最小可生成单元（spec: 片段边界划分）。
///
/// **只存元数据与指向，不复制分镜**（design 决策 1）：`shotNumbers` 按顺序指向
/// `StudioEpisode.shots`。这样 `shots` 保持唯一事实来源，声音设计、SRT、FFmpeg
/// 合成、剪映导出四处消费方都不需要改。
class StudioSegment {
  /// `seg-<n>`，n 从 1 起。
  final String id;

  /// 目标时长（秒）。AI 划边界时给出，用户可改。
  final int targetDurationSec;

  /// 边界判定理由（AI 给，用户可编辑）。
  ///
  /// 迁移生成的片段写死「旧版数据自动分组」，让用户能区分「AI 划的」与
  /// 「系统补的」（design Risks 第三条）。
  final String boundaryReason;

  /// 片段级补充说明。追加在组装提示词末尾，是用户/AI 唯一的「整段润色」入口
  /// （design 决策 5：提示词主体由确定性组装，不交给 AI 自由发挥）。
  final String promptNote;

  /// 已生成片段视频的文件名（相对 `segments/`）。
  final String? clipPath;

  final SegmentStatus status;

  /// 参与的镜号，按分镜顺序。
  final List<int> shotNumbers;

  /// 被单镜覆盖而移出本次生成的镜号（design Risks 第四条）。
  ///
  /// 不做「自动重算片段时长」——那会让用户的确认状态失效。
  final List<int> excludedShotNumbers;

  /// 参考图被降级的数量。0 表示未降级。
  ///
  /// 降级必须可见（design 决策 4）：用户得知道「我传了 3 张，实际只用了 1 张」，
  /// 否则会以为一致性约束生效了。
  final int degradedRefCount;

  /// 本次实际提交给模型的时长（秒）。null 表示尚未生成过。
  ///
  /// 与 [targetDurationSec] 分开是因为能力矩阵会把超范围的请求吸附到合法值
  /// ——用户请求 15s、模型只支持到 12s 时，提交的是 12s。UI 必须把两个值并列
  /// 展示，否则用户以为 15s 生效了（spec: 分镜看板展示本次提交的实际参数）。
  final int? submittedDurationSec;

  const StudioSegment({
    required this.id,
    this.targetDurationSec = 12,
    this.boundaryReason = '',
    this.promptNote = '',
    this.clipPath,
    this.status = SegmentStatus.pending,
    this.shotNumbers = const [],
    this.excludedShotNumbers = const [],
    this.degradedRefCount = 0,
    this.submittedDurationSec,
  });

  /// 本次实际参与生成的镜号。
  List<int> get effectiveShotNumbers =>
      shotNumbers.where((n) => !excludedShotNumbers.contains(n)).toList();

  bool get hasClip => clipPath != null && clipPath!.isNotEmpty;

  bool get isDegraded => degradedRefCount > 0;

  /// 实际提交时长与请求时长是否不同（UI 据此决定要不要并列展示）。
  bool get durationWasAdjusted {
    final submitted = submittedDurationSec;
    return submitted != null && submitted != targetDurationSec;
  }

  StudioSegment copyWith({
    String? id,
    int? targetDurationSec,
    String? boundaryReason,
    String? promptNote,
    String? clipPath,
    SegmentStatus? status,
    List<int>? shotNumbers,
    List<int>? excludedShotNumbers,
    int? degradedRefCount,
    int? submittedDurationSec,
  }) {
    return StudioSegment(
      id: id ?? this.id,
      targetDurationSec: targetDurationSec ?? this.targetDurationSec,
      boundaryReason: boundaryReason ?? this.boundaryReason,
      promptNote: promptNote ?? this.promptNote,
      clipPath: clipPath ?? this.clipPath,
      status: status ?? this.status,
      shotNumbers: shotNumbers ?? this.shotNumbers,
      excludedShotNumbers: excludedShotNumbers ?? this.excludedShotNumbers,
      degradedRefCount: degradedRefCount ?? this.degradedRefCount,
      submittedDurationSec:
          submittedDurationSec ?? this.submittedDurationSec,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'target_duration_sec': targetDurationSec,
    'boundary_reason': boundaryReason,
    'prompt_note': promptNote,
    'clip_path': clipPath,
    'status': status.id,
    'shot_numbers': shotNumbers,
    'excluded_shot_numbers': excludedShotNumbers,
    'degraded_ref_count': degradedRefCount,
    'submitted_duration_sec': submittedDurationSec,
  };

  static StudioSegment fromJson(Map<String, dynamic> json) {
    return StudioSegment(
      id: json['id'] as String? ?? '',
      targetDurationSec:
          (json['target_duration_sec'] as num?)?.toInt() ?? 12,
      boundaryReason: json['boundary_reason'] as String? ?? '',
      promptNote: json['prompt_note'] as String? ?? '',
      clipPath: json['clip_path'] as String?,
      status: SegmentStatus.fromId(json['status'] as String?),
      shotNumbers:
          (json['shot_numbers'] as List?)?.whereType<num>().map((n) => n.toInt()).toList() ??
          const [],
      excludedShotNumbers:
          (json['excluded_shot_numbers'] as List?)?.whereType<num>().map((n) => n.toInt()).toList() ??
          const [],
      degradedRefCount:
          (json['degraded_ref_count'] as num?)?.toInt() ?? 0,
      submittedDurationSec:
          (json['submitted_duration_sec'] as num?)?.toInt(),
    );
  }
}

/// 全局公共库中的一个音频资产。
class GlobalAudioAsset {
  final String name;

  /// 绝对路径。
  final String path;

  /// `bgm` 或 `sfx`。
  final String kind;

  /// 情绪标签（从文件名或同级元数据推断，见 `StudioGlobalLibrary`）。
  final String mood;

  /// 来源层级标注（spec: 每项旁标注来源层级）。
  final String sourceLayer;

  final int sizeBytes;

  const GlobalAudioAsset({
    required this.name,
    required this.path,
    required this.kind,
    this.mood = '',
    this.sourceLayer = 'global',
    this.sizeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'kind': kind,
    'mood': mood,
    'source_layer': sourceLayer,
    'size_bytes': sizeBytes,
  };

  static GlobalAudioAsset fromJson(Map<String, dynamic> json) {
    return GlobalAudioAsset(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      kind: json['kind'] as String? ?? 'bgm',
      mood: json['mood'] as String? ?? '',
      sourceLayer: json['source_layer'] as String? ?? 'global',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 创意孵化方向。
class IdeaDirection {
  final String id;
  final String title;
  final String hook;
  final String twist;
  final String pacing;
  final String strategy;
  final bool accepted;
  final DateTime createdAt;

  const IdeaDirection({
    required this.id,
    required this.title,
    this.hook = '',
    this.twist = '',
    this.pacing = '',
    this.strategy = '',
    this.accepted = false,
    required this.createdAt,
  });

  IdeaDirection copyWith({
    String? id,
    String? title,
    String? hook,
    String? twist,
    String? pacing,
    String? strategy,
    bool? accepted,
    DateTime? createdAt,
  }) {
    return IdeaDirection(
      id: id ?? this.id,
      title: title ?? this.title,
      hook: hook ?? this.hook,
      twist: twist ?? this.twist,
      pacing: pacing ?? this.pacing,
      strategy: strategy ?? this.strategy,
      accepted: accepted ?? this.accepted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'hook': hook,
    'twist': twist,
    'pacing': pacing,
    'strategy': strategy,
    'accepted': accepted,
    'created_at': createdAt.toIso8601String(),
  };

  static IdeaDirection fromJson(Map<String, dynamic> json) {
    return IdeaDirection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名方向',
      hook: json['hook'] as String? ?? '',
      twist: json['twist'] as String? ?? '',
      pacing: json['pacing'] as String? ?? '',
      strategy: json['strategy'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
