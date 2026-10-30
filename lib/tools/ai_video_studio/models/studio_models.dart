/// AI 短视频工坊的数据模型。
///
/// 全部以 JSON 文件落盘于 `AppSupportDir/video_studio/`（见 design.md D4：
/// 不引入 SQLite——素材天然在文件系统里，剧集元数据只有百 KB 级，且用户要能
/// 直接用 Finder 打开备份）。这些类是那层 JSON 的唯一 schema 定义处，字段名
/// 直接就是磁盘上的键名，改动字段先想清楚旧文件怎么读。
library;

import 'package:flutter/foundation.dart' show immutable;

import '../services/studio_preset_store.dart';
import 'drama_director_contract.dart';

export 'drama_director_contract.dart';

/// 制作类型。三选一，全局只有这三支管线（spec: 制作类型管线预设）。
///
/// 值的字符串形态会写进 `series_profile.json`，所以顺序与拼写都不要变——
/// 改了就等于把用户已有的剧集变成未知类型。
enum StudioProductionType {
  /// 3D国漫 / 次世代虚拟剧：默认走图生视频商业 API，高画质玄幻 CGI 美学。
  anime3d(
    'anime3d',
    '3D国漫 / 次世代虚拟剧',
    '3D 玄幻动漫与次世代风格，人物场景唯美精致，运镜与光影细腻，适合修仙与高燃奇幻',
    '3D CGI animation, modern Chinese fantasy donghua, exquisite 3D render, Unreal Engine 5 render, subsurface scattering skin, delicate hair strands, glowing elemental VFX, cinematic lighting',
    '2D, flat anime, cartoon, sketch, live-action photo, plastic clay, low-poly, stiff puppet, glossy plastic skin',
    'dynamic airborne camera, flowing robes and hair in the wind, energy aura waves, sword flying dynamics, cinematic motion blur',
  ),

  /// 真人剧情短剧：默认走图生视频（I2V）商业 API。
  drama(
    'drama',
    '真人剧情短剧',
    '真人出镜或拟真画面，节奏快、冲突强，适合爽剧与情感短剧',
    'cinematic film still, photorealistic 8k, live-action cinematography, arri alexa footage, natural skin texture, realistic micro-expressions, dramatic cinematic lighting, 35mm lens, shallow depth of field',
    'anime, cartoon, 3D render, CGI, doll, plastic skin, illustration, painting, drawing, unreal engine, fake, airbrushed',
    'subtle breathing motion, eye contact, handheld camera shake, sudden zoom-in for dramatic tension',
  ),

  /// 二次元 / 动态漫：默认走本地 Ken Burns 动效，零成本。
  anime(
    'anime',
    '二次元 / 动态漫',
    '动漫或动态漫风格，运镜夸张，适合二次元与漫改',
    'high quality anime aesthetic, Japanese anime art style, crisp cel-shaded lines, vibrant anime coloring, Makoto Shinkai lighting, Ufotable visual flair, detailed anime illustration, master anime keyframe',
    'photorealistic, live-action, 3D CGI, bad anatomy, western comic style, realism, real human photo',
    'dynamic speed lines, 2.5D parallax, dramatic comic pan, exaggerated facial expression pop',
  ),

  /// 图文解说 / 知识故事：默认 Ken Burns 静态推拉，不调用外部视频 API。
  narration(
    'narration',
    '图文解说 / 知识故事',
    '以旁白与图文为主，适合知识科普与故事解说',
    'high-end documentary illustration, editorial conceptual art, atmospheric digital painting, storybook realism, rich color palette, textured brushwork, elegant lighting, clear focal subject',
    'messy, anime, cartoonish, low-brow, chaotic composition, text, blurry, cluttered background',
    'slow cinematic Ken Burns push/pull, gentle ambient atmospheric drift, slow pan across details',
  );

  final String id;
  final String label;
  final String description;
  final String defaultPositiveStyle;
  final String defaultNegativeStyle;
  final String motionTendency;

  const StudioProductionType(
    this.id,
    this.label,
    this.description,
    this.defaultPositiveStyle,
    this.defaultNegativeStyle,
    this.motionTendency,
  );

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

  /// 该形态专属三视图相对路径（如 `turnaround_var_123.png`）。
  /// 形态专属装束英文 Prompt（全量置换默认服装）。
  final String attirePrompt;

  final String? turnaroundPath;

  /// 该形态专属参考图相对路径列表。
  final List<String> referenceImages;

  /// 系统三视图提示词组件覆盖（若非空则优先使用，替换默认三视图骨架/排版约束）。
  final String? systemPromptOverride;

  final bool active;

  const CharacterVariation({
    required this.id,
    required this.name,
    this.positiveDelta = '',
    this.negativeDelta = '',
    this.attirePrompt = '',
    this.turnaroundPath,
    this.referenceImages = const [],
    this.systemPromptOverride,
    this.active = false,
  });

  /// 有效形态装束提示词：优先使用专属 [attirePrompt]，若为空则回退到 [positiveDelta]。
  String get effectiveAttirePrompt =>
      attirePrompt.trim().isNotEmpty ? attirePrompt.trim() : positiveDelta.trim();

  CharacterVariation copyWith({
    String? id,
    String? name,
    String? positiveDelta,
    String? negativeDelta,
    String? attirePrompt,
    String? turnaroundPath,
    bool clearTurnaroundPath = false,
    List<String>? referenceImages,
    String? systemPromptOverride,
    bool clearSystemPromptOverride = false,
    bool? active,
  }) {
    return CharacterVariation(
      id: id ?? this.id,
      name: name ?? this.name,
      positiveDelta: positiveDelta ?? this.positiveDelta,
      negativeDelta: negativeDelta ?? this.negativeDelta,
      attirePrompt: attirePrompt ?? this.attirePrompt,
      turnaroundPath: clearTurnaroundPath ? null : (turnaroundPath ?? this.turnaroundPath),
      referenceImages: referenceImages ?? this.referenceImages,
      systemPromptOverride: clearSystemPromptOverride
          ? null
          : (systemPromptOverride ?? this.systemPromptOverride),
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'positive_delta': positiveDelta,
    'negative_delta': negativeDelta,
    if (attirePrompt.isNotEmpty) 'attire_prompt': attirePrompt,
    if (turnaroundPath != null) 'turnaround_path': turnaroundPath,
    'reference_images': referenceImages,
    if (systemPromptOverride != null && systemPromptOverride!.isNotEmpty)
      'system_prompt_override': systemPromptOverride,
    'active': active,
  };

  static CharacterVariation fromJson(Map<String, dynamic> json) {
    return CharacterVariation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      positiveDelta: json['positive_delta'] as String? ?? '',
      negativeDelta: json['negative_delta'] as String? ?? '',
      attirePrompt: json['attire_prompt'] as String? ?? '',
      turnaroundPath: json['turnaround_path'] as String?,
      referenceImages:
          (json['reference_images'] as List?)?.cast<String>() ?? const [],
      systemPromptOverride: json['system_prompt_override'] as String? ??
          json['systemPromptOverride'] as String?,
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

  /// 容貌发型体态中文描述（不变身份）。
  final String facialFeaturesZh;

  /// 容貌发型体态英文 Prompt（不变身份）。
  final String facialPrompt;

  /// 默认/出场服装中文描述（可被形态置换）。
  final String defaultAttireZh;

  /// 默认/出场服装英文 Prompt（可被形态置换）。
  final String defaultAttirePrompt;

  /// 面部特写锚点图相对路径（如 face_anchor.png，纯脸模，无服装干扰）。
  final String? faceAnchorPath;

  /// 基准参考图相对路径（角色目录下的文件名）。
  final List<String> referenceImages;

  /// 绑定的 TTS 音色标识符；为空则用剧集类型默认音色。
  final String ttsVoiceId;

  /// 命名形态列表。第一个通常是"默认"。
  final List<CharacterVariation> variations;

  /// 角色别名/代称列表（如原著中"姜七少"、"七少"、"少东家"等）。
  final List<String> aliases;

  /// 系统三视图提示词组件覆盖（若非空则优先使用，替换默认三视图骨架/排版约束）。
  final String? systemPromptOverride;

  final DateTime updatedAt;

  const CharacterCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.basePromptPositive = '',
    this.basePromptNegative = '',
    this.facialFeaturesZh = '',
    this.facialPrompt = '',
    this.defaultAttireZh = '',
    this.defaultAttirePrompt = '',
    this.faceAnchorPath,
    this.referenceImages = const [],
    this.ttsVoiceId = '',
    this.variations = const [],
    this.aliases = const [],
    this.systemPromptOverride,
    required this.updatedAt,
  });

  /// 有效容貌提示词：优先使用原生中文 [facialFeaturesZh]，若为空则回退到 [facialPrompt] 或 [basePromptPositive]。
  String get effectiveFacialPrompt {
    if (facialFeaturesZh.trim().isNotEmpty) return facialFeaturesZh.trim();
    if (facialPrompt.trim().isNotEmpty) return facialPrompt.trim();
    return basePromptPositive.trim();
  }

  /// 有效合成正向提示词：优先组合原生中文 [facialFeaturesZh] 与 [defaultAttireZh]，若为空则兼容组合英文字段或 [basePromptPositive]。
  String get combinedPromptPositive {
    final faceZh = facialFeaturesZh.trim();
    final attireZh = defaultAttireZh.trim();
    if (faceZh.isNotEmpty && attireZh.isNotEmpty) return '$faceZh， $attireZh';
    if (faceZh.isNotEmpty) return faceZh;
    if (attireZh.isNotEmpty) return attireZh;

    final face = facialPrompt.trim();
    final attire = defaultAttirePrompt.trim();
    if (face.isNotEmpty && attire.isNotEmpty) return '$face, $attire';
    if (face.isNotEmpty) return face;
    if (attire.isNotEmpty) return attire;
    return basePromptPositive.trim();
  }

  /// 当前激活形态；没有激活形态时返回 null（调用方按基础 Prompt 处理）。
  CharacterVariation? get activeVariation {
    for (final v in variations) {
      if (v.active) return v;
    }
    return null;
  }

  /// 是否具备视觉参考图（面部锚点图、基准参考图、或任何形态专属三视图/参考图）。
  bool get hasVisualReference {
    if (faceAnchorPath != null && faceAnchorPath!.trim().isNotEmpty) return true;
    if (referenceImages.isNotEmpty) return true;
    for (final v in variations) {
      if (v.turnaroundPath != null && v.turnaroundPath!.trim().isNotEmpty) return true;
      if (v.referenceImages.isNotEmpty) return true;
    }
    return false;
  }

  CharacterCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? basePromptPositive,
    String? basePromptNegative,
    String? facialFeaturesZh,
    String? facialPrompt,
    String? defaultAttireZh,
    String? defaultAttirePrompt,
    String? faceAnchorPath,
    bool clearFaceAnchorPath = false,
    List<String>? referenceImages,
    String? ttsVoiceId,
    List<CharacterVariation>? variations,
    List<String>? aliases,
    String? systemPromptOverride,
    bool clearSystemPromptOverride = false,
    DateTime? updatedAt,
  }) {
    return CharacterCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      basePromptPositive: basePromptPositive ?? this.basePromptPositive,
      basePromptNegative: basePromptNegative ?? this.basePromptNegative,
      facialFeaturesZh: facialFeaturesZh ?? this.facialFeaturesZh,
      facialPrompt: facialPrompt ?? this.facialPrompt,
      defaultAttireZh: defaultAttireZh ?? this.defaultAttireZh,
      defaultAttirePrompt: defaultAttirePrompt ?? this.defaultAttirePrompt,
      faceAnchorPath: clearFaceAnchorPath ? null : (faceAnchorPath ?? this.faceAnchorPath),
      referenceImages: referenceImages ?? this.referenceImages,
      ttsVoiceId: ttsVoiceId ?? this.ttsVoiceId,
      variations: variations ?? this.variations,
      aliases: aliases ?? this.aliases,
      systemPromptOverride: clearSystemPromptOverride
          ? null
          : (systemPromptOverride ?? this.systemPromptOverride),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description_zh': descriptionZh,
    'base_prompt_positive':
        basePromptPositive.isNotEmpty ? basePromptPositive : combinedPromptPositive,
    'base_prompt_negative': basePromptNegative,
    if (facialFeaturesZh.isNotEmpty) 'facial_features_zh': facialFeaturesZh,
    if (facialPrompt.isNotEmpty) 'facial_prompt': facialPrompt,
    if (defaultAttireZh.isNotEmpty) 'default_attire_zh': defaultAttireZh,
    if (defaultAttirePrompt.isNotEmpty) 'default_attire_prompt': defaultAttirePrompt,
    if (faceAnchorPath != null) 'face_anchor_path': faceAnchorPath,
    'reference_images': referenceImages,
    'tts_voice_id': ttsVoiceId,
    'variations': variations.map((v) => v.toJson()).toList(),
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (systemPromptOverride != null && systemPromptOverride!.isNotEmpty)
      'system_prompt_override': systemPromptOverride,
    'updated_at': updatedAt.toIso8601String(),
  };

  static CharacterCard fromJson(Map<String, dynamic> json) {
    final rawDescZh = json['description_zh'] as String? ?? '';
    final rawBasePos = json['base_prompt_positive'] as String? ?? '';
    final rawFacialZh = (json['facial_features_zh'] as String? ?? '').trim();
    final rawFacialPr = (json['facial_prompt'] as String? ?? '').trim();
    final rawAttireZh = (json['default_attire_zh'] as String? ?? '').trim();
    final rawAttirePr = (json['default_attire_prompt'] as String? ?? '').trim();

    return CharacterCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      descriptionZh: rawDescZh,
      basePromptPositive: rawBasePos,
      basePromptNegative: json['base_prompt_negative'] as String? ?? '',
      facialFeaturesZh: rawFacialZh.isNotEmpty ? rawFacialZh : rawDescZh,
      facialPrompt: rawFacialPr.isNotEmpty ? rawFacialPr : rawBasePos,
      defaultAttireZh: rawAttireZh,
      defaultAttirePrompt: rawAttirePr,
      faceAnchorPath: json['face_anchor_path'] as String?,
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
      aliases:
          (json['aliases'] as List?)?.cast<String>() ?? const [],
      systemPromptOverride: json['system_prompt_override'] as String? ??
          json['systemPromptOverride'] as String?,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 场景七方位空间视角定义（前、后、左、右、上、下、俯视全景）。
enum SceneDirection {
  /// 正面主景（主案/神龛/屏风视觉重心，正面正视）
  front(
    key: 'front',
    labelZh: '正面主景',
    subLabelZh: '主案/神龛/屏风视觉重心',
    promptPrefix: '正面平视主景，视觉重心与核心空间陈设，中轴对称构图',
  ),

  /// 反打背景（大门/入口/退路走廊，反向背视）
  back(
    key: 'back',
    labelZh: '反打背景',
    subLabelZh: '大门/入口/退路走廊',
    promptPrefix: '反打后视全景，朝向正门与玄关入口，退路通道视角',
  ),

  /// 左侧立面（采光排窗/立柜陈设）
  left(
    key: 'left',
    labelZh: '左侧立面',
    subLabelZh: '采光排窗/立柜陈设',
    promptPrefix: '左侧立面平视视角，左侧采光窗与陈设立柜，侧面空间进深',
  ),

  /// 右侧立面（内室通道/侧席博古架）
  right(
    key: 'right',
    labelZh: '右侧立面',
    subLabelZh: '内室通道/侧席博古架',
    promptPrefix: '右侧立面平视视角，右侧内室隔断与博古架陈列，侧廊通道',
  ),

  /// 天顶结构（梁木藻井/穹顶吊灯，仰视仰拍）
  top(
    key: 'top',
    labelZh: '天顶结构',
    subLabelZh: '梁木藻井/穹顶吊灯',
    promptPrefix: '仰视天顶结构视角，低机位仰拍梁木藻井、穹顶灯饰与建筑顶构',
  ),

  /// 地面铺装（青砖地坪/织锦地毯，俯视地面）
  bottom(
    key: 'bottom',
    labelZh: '地面铺装',
    subLabelZh: '青砖地坪/织锦地毯',
    promptPrefix: '俯视地面铺装视角，正俯视青砖石板、地坪铺装与地毯纹理',
  ),

  /// 俯视全景（空间平面拓扑与长宽进深鸟瞰）
  topDown(
    key: 'topDown',
    labelZh: '俯视全景',
    subLabelZh: '空间平面拓扑与长宽进深鸟瞰',
    promptPrefix: '高空鸟瞰俯视全景，大广角俯拍展示完整建筑格局、长宽进深与家具拓扑陈设',
  );

  final String key;
  final String labelZh;
  final String subLabelZh;
  final String promptPrefix;

  const SceneDirection({
    required this.key,
    required this.labelZh,
    required this.subLabelZh,
    required this.promptPrefix,
  });

  static SceneDirection fromKey(String? value) {
    if (value == null || value.trim().isEmpty) return SceneDirection.front;
    final normalized = value.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');
    for (final d in SceneDirection.values) {
      if (d.name.toLowerCase() == normalized || d.key.toLowerCase() == normalized) {
        return d;
      }
    }
    if (normalized == 'topdown' || normalized == 'birdview' || normalized == 'overview' || normalized == 'aerial') {
      return SceneDirection.topDown;
    }
    return SceneDirection.front;
  }

  /// 格式化视角生图提示词，自动注入该方位的前缀描述。
  String formatPrompt(String basePrompt) {
    final clean = basePrompt.trim();
    if (clean.isEmpty) return promptPrefix;
    if (clean.toLowerCase().contains(promptPrefix.toLowerCase())) return clean;
    return '$promptPrefix， $clean';
  }
}

/// 场景单一方位的空间视图档案。
class SceneDirectionalView {
  final SceneDirection direction;

  /// 该方位的中文空间环境描述。
  final String descriptionZh;

  /// 该方位的英文生图 Prompt。
  final String promptEn;

  /// 该方位的参考图相对或绝对路径。
  final String? imagePath;

  const SceneDirectionalView({
    required this.direction,
    this.descriptionZh = '',
    this.promptEn = '',
    this.imagePath,
  });

  bool get hasImage => imagePath != null && imagePath!.trim().isNotEmpty;

  bool get hasContent =>
      descriptionZh.trim().isNotEmpty ||
      promptEn.trim().isNotEmpty ||
      hasImage;

  SceneDirectionalView copyWith({
    SceneDirection? direction,
    String? descriptionZh,
    String? promptEn,
    String? imagePath,
    bool clearImagePath = false,
  }) {
    return SceneDirectionalView(
      direction: direction ?? this.direction,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      promptEn: promptEn ?? this.promptEn,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
    );
  }

  Map<String, dynamic> toJson() => {
    'direction': direction.key,
    if (descriptionZh.isNotEmpty) 'description_zh': descriptionZh,
    if (promptEn.isNotEmpty) 'prompt_en': promptEn,
    if (imagePath != null && imagePath!.isNotEmpty) 'image_path': imagePath,
  };

  static SceneDirectionalView fromJson(
    Map<String, dynamic> json, [
    SceneDirection? fallbackDirection,
  ]) {
    final dirKey = json['direction'] as String?;
    final dir = dirKey != null
        ? SceneDirection.fromKey(dirKey)
        : (fallbackDirection ?? SceneDirection.front);
    return SceneDirectionalView(
      direction: dir,
      descriptionZh:
          (json['description_zh'] as String? ??
                  json['descriptionZh'] as String? ??
                  '')
              .trim(),
      promptEn:
          (json['prompt_en'] as String? ?? json['promptEn'] as String? ?? '')
              .trim(),
      imagePath: json['image_path'] as String? ?? json['imagePath'] as String?,
    );
  }
}

/// 场景资产卡（`common_scenes/<id>/config.json`）。
class SceneCard {
  final String id;
  final String name;

  /// 中文描述（主视角）。
  final String descriptionZh;

  /// 英文场景 Prompt（主视角，直接进入最终生图 Prompt）。
  final String promptEn;

  /// 参考图路径列表。
  final List<String> referenceImages;

  /// 是否全剧通用（否则仅本剧可见——layer 语义由目录位置决定，这里只是标记）。
  final bool sharedAcrossSeries;

  /// 七方位空间全息视图档案映射（key 为 SceneDirection.name / key）。
  final Map<String, SceneDirectionalView> spatialViews;

  /// 360° 等矩全景母图相对路径（保存在 panoramas/ 目录下）。
  final String? panoramaMasterPath;

  /// 正面主景偏航基准角偏移量（单位：度，默认为 0.0）。
  final double panoramaYawOffset;

  /// 360° 全景切片视场角（单位：度，默认为 105.0 电影级超广角）。
  final double panoramaFov;

  /// 360° 全景切片俯仰偏移量（单位：度，默认为 0.0）。
  final double panoramaPitchOffset;

  /// 方位视角生图的系统空镜环境前导词覆盖（非空时优先使用，替换默认空镜底板锁与环境规范）。
  final String? systemPromptOverride;

  /// 360° 等矩全景母图专属系统头尾透视锚点覆盖（非空时优先使用，替换默认 panoHead/panoTail 建筑透视约束）。
  final String? panoramaSystemPromptOverride;

  final DateTime updatedAt;

  const SceneCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.promptEn = '',
    this.referenceImages = const [],
    this.sharedAcrossSeries = false,
    this.spatialViews = const {},
    this.panoramaMasterPath,
    this.panoramaYawOffset = 0.0,
    this.panoramaFov = 105.0,
    this.panoramaPitchOffset = 0.0,
    this.systemPromptOverride,
    this.panoramaSystemPromptOverride,
    required this.updatedAt,
  });

  /// 保证返回覆盖全部 7 个视角的完整空间视图映射。
  Map<String, SceneDirectionalView> get fullSpatialViews {
    final result = <String, SceneDirectionalView>{};
    for (final dir in SceneDirection.values) {
      final existing = spatialViews[dir.name] ?? spatialViews[dir.key];
      if (existing != null) {
        result[dir.name] = existing;
      } else if (dir == SceneDirection.front) {
        result[dir.name] = SceneDirectionalView(
          direction: SceneDirection.front,
          descriptionZh: descriptionZh,
          promptEn: promptEn,
          imagePath: referenceImages.isNotEmpty ? referenceImages.first : null,
        );
      } else {
        result[dir.name] = SceneDirectionalView(direction: dir);
      }
    }
    return result;
  }

  /// 获取指定方位的视图。
  SceneDirectionalView viewFor(SceneDirection direction) {
    return fullSpatialViews[direction.name] ?? SceneDirectionalView(direction: direction);
  }

  /// 该场景是否已完成七方位解构（除正面外至少有其他方位包含有效文本或图片）。
  bool get hasSpatialDeconstruction {
    for (final dir in SceneDirection.values) {
      if (dir == SceneDirection.front) continue;
      final v = spatialViews[dir.name] ?? spatialViews[dir.key];
      if (v != null && v.hasContent) return true;
    }
    return false;
  }

  /// 便捷更新单一方位视图并同步主字段（若是 front 视角）。
  SceneCard withUpdatedSpatialView(SceneDirectionalView view) {
    final updated = Map<String, SceneDirectionalView>.from(fullSpatialViews);
    updated[view.direction.name] = view;

    if (view.direction == SceneDirection.front) {
      final newRefs = List<String>.from(referenceImages);
      if (view.imagePath != null && view.imagePath!.trim().isNotEmpty) {
        final path = view.imagePath!.trim();
        if (!newRefs.contains(path)) {
          newRefs.insert(0, path);
        }
      }
      return copyWith(
        descriptionZh: view.descriptionZh.isNotEmpty ? view.descriptionZh : descriptionZh,
        promptEn: view.promptEn.isNotEmpty ? view.promptEn : promptEn,
        referenceImages: newRefs,
        spatialViews: updated,
      );
    }
    return copyWith(spatialViews: updated);
  }

  SceneCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? promptEn,
    List<String>? referenceImages,
    bool? sharedAcrossSeries,
    Map<String, SceneDirectionalView>? spatialViews,
    String? panoramaMasterPath,
    double? panoramaYawOffset,
    double? panoramaFov,
    double? panoramaPitchOffset,
    String? systemPromptOverride,
    bool clearSystemPromptOverride = false,
    String? panoramaSystemPromptOverride,
    bool clearPanoramaSystemPromptOverride = false,
    bool clearPanorama = false,
    DateTime? updatedAt,
  }) {
    return SceneCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      promptEn: promptEn ?? this.promptEn,
      referenceImages: referenceImages ?? this.referenceImages,
      sharedAcrossSeries: sharedAcrossSeries ?? this.sharedAcrossSeries,
      spatialViews: spatialViews ?? this.spatialViews,
      panoramaMasterPath: clearPanorama ? null : (panoramaMasterPath ?? this.panoramaMasterPath),
      panoramaYawOffset: panoramaYawOffset ?? this.panoramaYawOffset,
      panoramaFov: panoramaFov ?? this.panoramaFov,
      panoramaPitchOffset: panoramaPitchOffset ?? this.panoramaPitchOffset,
      systemPromptOverride: clearSystemPromptOverride
          ? null
          : (systemPromptOverride ?? this.systemPromptOverride),
      panoramaSystemPromptOverride: clearPanoramaSystemPromptOverride
          ? null
          : (panoramaSystemPromptOverride ?? this.panoramaSystemPromptOverride),
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
    if (spatialViews.isNotEmpty)
      'spatial_views': spatialViews.map((k, v) => MapEntry(k, v.toJson())),
    if (panoramaMasterPath != null && panoramaMasterPath!.isNotEmpty)
      'panorama_master_path': panoramaMasterPath,
    if (panoramaYawOffset != 0.0)
      'panorama_yaw_offset': panoramaYawOffset,
    if (panoramaFov != 105.0)
      'panorama_fov': panoramaFov,
    if (panoramaPitchOffset != 0.0)
      'panorama_pitch_offset': panoramaPitchOffset,
    if (systemPromptOverride != null && systemPromptOverride!.isNotEmpty)
      'system_prompt_override': systemPromptOverride,
    if (panoramaSystemPromptOverride != null &&
        panoramaSystemPromptOverride!.isNotEmpty)
      'panorama_system_prompt_override': panoramaSystemPromptOverride,
    'updated_at': updatedAt.toIso8601String(),
  };

  static SceneCard fromJson(Map<String, dynamic> json) {
    final rawDescZh = json['description_zh'] as String? ?? '';
    final rawPromptEn = json['prompt_en'] as String? ?? '';
    final rawRefImages =
        (json['reference_images'] as List?)?.cast<String>() ?? const [];

    final rawSpatial = json['spatial_views'] as Map? ?? json['spatialViews'] as Map?;
    final parsedViews = <String, SceneDirectionalView>{};

    if (rawSpatial != null) {
      for (final entry in rawSpatial.entries) {
        if (entry.value is Map) {
          final viewMap = (entry.value as Map).map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final dir = SceneDirection.fromKey(entry.key.toString());
          parsedViews[dir.name] = SceneDirectionalView.fromJson(viewMap, dir);
        }
      }
    }

    // 补齐 7 个方位，确保默认包含 front 兼容数据
    for (final dir in SceneDirection.values) {
      if (!parsedViews.containsKey(dir.name)) {
        if (dir == SceneDirection.front) {
          parsedViews[dir.name] = SceneDirectionalView(
            direction: SceneDirection.front,
            descriptionZh: rawDescZh,
            promptEn: rawPromptEn,
            imagePath: rawRefImages.isNotEmpty ? rawRefImages.first : null,
          );
        } else {
          parsedViews[dir.name] = SceneDirectionalView(direction: dir);
        }
      }
    }

    return SceneCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      descriptionZh: rawDescZh,
      promptEn: rawPromptEn,
      referenceImages: rawRefImages,
      sharedAcrossSeries: json['shared_across_series'] as bool? ?? false,
      spatialViews: parsedViews,
      panoramaMasterPath: json['panorama_master_path'] as String? ?? json['panoramaMasterPath'] as String?,
      panoramaYawOffset: (json['panorama_yaw_offset'] as num? ?? json['panoramaYawOffset'] as num? ?? 0.0).toDouble(),
      panoramaFov: (json['panorama_fov'] as num? ?? json['panoramaFov'] as num? ?? 105.0).toDouble(),
      panoramaPitchOffset: (json['panorama_pitch_offset'] as num? ?? json['panoramaPitchOffset'] as num? ?? 0.0).toDouble(),
      systemPromptOverride: json['system_prompt_override'] as String? ??
          json['systemPromptOverride'] as String?,
      panoramaSystemPromptOverride:
          json['panorama_system_prompt_override'] as String? ??
              json['panoramaSystemPromptOverride'] as String?,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 场景视角类型定义（全景建立镜头、主视平视全景、侧逆视角、空间局部特写）。
enum SceneCameraAngle {
  /// 全景建立镜头（Wide Establishing / Panoramic Shot）
  panoramic(
    labelZh: '全景建立镜头',
    promptToken: '大广角全景建立镜头，宏大开阔大气氛围，极远景全貌',
  ),

  /// 主轴平视全景（Eye-Level Main View）
  eyeLevelMain(
    labelZh: '主视平视全景',
    promptToken: '平视主视角全景镜头，中轴对称室内构图',
  ),

  /// 反打/侧方位视角（Reverse / Side Angle View）
  reverseAngle(
    labelZh: '侧逆视角',
    promptToken: '反打侧方位动态构图视角，四分之三侧角透视',
  ),

  /// 局部陈设特写（Detail & Architectural Close-up）
  detailCloseUp(
    labelZh: '局部陈设特写',
    promptToken: '建筑局部与室内陈设特写镜头，精致道具与材质纹理细节',
  );

  final String labelZh;
  final String promptToken;

  const SceneCameraAngle({
    required this.labelZh,
    required this.promptToken,
  });
}

/// 场景纯净空镜生图提示词组装器。
class ScenePromptBuilder {
  ScenePromptBuilder._();

  /// 头部肯定式空镜背景板锁（最高注意力权重区，强制确立纯物理环境底板，杜绝逆向激活）。
  static const String emptyHeadLock =
      '纯净物理空间空镜头背景板，完全空无一人，空旷建筑场景，无人物';

  /// 尾部肯定式空镜收尾锁（Recency Anchor 收口区，强化物理静物属性与虚位空间）。
  static const String emptyTailLock =
      '虚位以待的无人空间，静止建筑静物，无人类踪迹，空旷宁静';

  /// 保持向后兼容的别名，默认指向头部锁。
  static const String emptyScenePositiveLock = emptyHeadLock;

  /// 场景人类/人物负向排除锁（全方位封杀人物、肢体、面部与剪影）。
  static const String humanSuppressionNegativeLock =
      '人物，人类，男人，女人，人群，面部五官，路人，守卫，士兵，修士，商贩，顾客，影子，肢体动作，站立行走的人';

  /// 常见生图瑕疵负向词。
  static const String defaultNegativeArtifacts =
      '画面模糊，低画质，变形失真，残缺扭曲，水印，文字，噪点爆炸';

  /// 敏感实体与动作过滤词正则（全词匹配）
  static final RegExp _sensitivePattern = RegExp(
    r'\b(humans?|people|persons?|crowds?|man|men|woman|women|boys?|girls?|characters?|figures?|pedestrians?|citizens?|guards?|soldiers?|monks?|vendors?|merchants?|innkeepers?|warriors?|guests?|passersby|someone|anyone|inhabitants?|everybody|spectators?|walking|sitting|standing|talking|fighting|sleeping|running|waving|looking)\b',
    caseSensitive: false,
  );

  static final RegExp _sensitivePatternZh = RegExp(
    r'(有人|人类|路人|行人|人群|男子|女子|男人|女人|少年|少女|守卫|狱卒|掌柜|店小二|客官|顾客|修士|道士|散修|士兵|站立|行走|跑动|打斗|谈笑|招手|注视|观望|躺卧|睡觉)',
  );

  /// 清洗 basePrompt：剥离人称、实体与主体交互动作，将生活化氛围词降级为建筑与陈设描述。
  static String sanitizeBasePrompt(String basePrompt) {
    if (basePrompt.trim().isEmpty) return '';
    var text = basePrompt.trim();

    // 氛围词安全降级
    text = text.replaceAll(RegExp(r'\bbustling\b', caseSensitive: false), 'spacious');
    text = text.replaceAll(RegExp(r'\blively\b', caseSensitive: false), 'detailed');
    text = text.replaceAll(RegExp(r'\bcrowded\b', caseSensitive: false), 'expansive');
    text = text.replaceAll('热闹非凡', '宽敞宏大');
    text = text.replaceAll('摩肩接踵', '空间开阔');
    text = text.replaceAll('人来人往', '视野开阔');

    // 剔除人物实体与动作词
    text = text.replaceAll(_sensitivePattern, '');
    text = text.replaceAll(_sensitivePatternZh, '');

    // 清理连续逗号与空白
    text = text
        .replaceAll(RegExp(r'[,，\s]*,+[,，\s]*'), '，')
        .replaceAll(RegExp(r'^[，,\s]+'), '')
        .replaceAll(RegExp(r'[，,\s]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    return text;
  }

  /// 封闭/室内/地下场景关键词识别列表
  static const List<String> enclosedKeywords = [
    '内景', '室内', '牢', '大牢', '牢房', '水牢', '地牢', '狱', '暗室', '密室',
    '值房', '大殿', '内殿', '寝宫', '厢房', '书房', '卧房', '客栈内', '酒楼内',
    '茶馆内', '石室', '洞窟', '地宫', '地道', '地下', '监牢', '囚室', '深牢',
    '刑房', '殿', '堂', '窟', '阁', '廊', '舱', '屋', '内堂', '房内',
    'indoor', 'interior', 'cell', 'jail', 'prison', 'dungeon', 'room',
  ];

  /// 室外互斥元素正则（云海、仙山、亭台楼阁、露天天空等）
  static final RegExp outdoorPattern = RegExp(
    r'云海雾气|云海|山水云雾|云雾缭绕|奇峰仙山|奇峰|仙山|古建亭台楼阁|亭台楼阁|雕梁画栋|古朴长街古道|长街古道|长街|古巷|残阳古道|翠竹青竹林|雾气|苍穹|天空|开阔天空|日出日落|日出|日落|晚霞|朝霞|广阔天地|宏大远景|山峰|群山|柔和天光|天光|开阔全景|'
    r'sea of clouds|open sky|wide sky|mountains|mountain peaks|sunrise|sunset',
    caseSensitive: false,
  );

  /// 判断场景是否属于室内、地下或封闭空间
  static bool isEnclosedText(String text) {
    final lower = text.toLowerCase();
    return enclosedKeywords.any((kw) => lower.contains(kw));
  }

  /// 净化时代环境锚点中的室外词
  static String sanitizeEnvironmentAnchor(String anchor) {
    final parts = anchor
        .split(RegExp(r'[,，；;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !outdoorPattern.hasMatch(s))
        .toList();
    if (parts.isEmpty) {
      return '中式古典室内建筑物理质感，真实砖木石材结构';
    }
    return parts.join('，');
  }

  /// 净化风格词中的室外词并补充室内微光
  static String sanitizeStyleForEnclosed(String style) {
    final parts = style
        .split(RegExp(r'[,，；;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !outdoorPattern.hasMatch(s))
        .toList();
    final hasIndoorLighting = parts.any((p) =>
        p.contains('室内') ||
        p.contains('微光') ||
        p.contains('油灯') ||
        p.contains('局部光') ||
        p.contains('暗光'));
    if (!hasIndoorLighting) {
      parts.add('室内局部微光，环境阴影与真实空间质感');
    }
    return parts.join('，');
  }

  /// 场景环境规范（动态从 StudioPresetStore 读取，若未初始化则回退默认）。
  static String get sceneEnvironmentRequirement {
    final t = StudioPresetStore.instance.getPromptContent('scene_environment');
    if (t.trim().isNotEmpty) return t.trim();
    return '纯净物理空间空镜头背景板，完全空无一人，宏大空间构图，建筑与自然景深层次丰富，无人物，无人类痕迹，虚位以待的无人空间，静止环境质感，电影级真实光影渲染';
  }

  /// 组装场景生图正向提示词（首尾双重夹逼架构：头部底板锁 + 时代风格环境 + 视角 + 清洗后陈设 + 尾部收尾锁）。
  static String buildPositivePrompt({
    required String basePrompt,
    String? styleTokens,
    String? eraGenreId,
    SceneCameraAngle? angle,
    bool sanitize = true,
    String? sceneEnvironmentOverride,
    String? systemPromptOverride,
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    final cleaned = sanitize ? sanitizeBasePrompt(basePrompt) : basePrompt.trim();

    final isEnclosed = isEnclosedText('$basePrompt $cleaned');

    String? envAnchor = era?.environmentAnchor.trim();
    String? style = styleTokens?.trim();

    if (isEnclosed) {
      if (envAnchor != null && envAnchor.isNotEmpty) {
        envAnchor = sanitizeEnvironmentAnchor(envAnchor);
      }
      if (style != null && style.isNotEmpty) {
        style = sanitizeStyleForEnclosed(style);
      }
    }

    final effectiveOverride = (systemPromptOverride != null && systemPromptOverride.trim().isNotEmpty)
        ? systemPromptOverride.trim()
        : sceneEnvironmentOverride;
    final envSpec = (effectiveOverride != null && effectiveOverride.trim().isNotEmpty)
        ? effectiveOverride.trim()
        : sceneEnvironmentRequirement;

    final middleParts = <String>[
      if (envSpec.isNotEmpty && envSpec != emptyHeadLock) envSpec,
      if (envAnchor != null && envAnchor.isNotEmpty) envAnchor,
      if (style != null && style.isNotEmpty) style,
      if (angle != null) angle.promptToken,
      if (cleaned.isNotEmpty) cleaned,
    ];

    // 若有显式环境覆盖，则优先使用覆盖词充当底板，替换硬编码的 emptyHeadLock/emptyTailLock 以及时代题材环境锚点
    if (sceneEnvironmentOverride != null && sceneEnvironmentOverride.trim().isNotEmpty) {
      final parts = <String>[
        sceneEnvironmentOverride.trim(),
        if (style != null && style.isNotEmpty) style,
        if (angle != null) angle.promptToken,
        if (cleaned.isNotEmpty) cleaned,
      ];
      return parts.where((p) => p.trim().isNotEmpty).join('， ');
    }

    final parts = <String>[
      emptyHeadLock,
      if (middleParts.isNotEmpty) middleParts.join('， '),
      emptyTailLock,
    ];
    return parts.join('， ');
  }

  /// 组装场景生图负向提示词（结合人类抑制、时代违禁、风格专属违禁与通用防崩，分词去重）。
  static String buildNegativePrompt({
    String? eraGenreId,
    String? styleNegativeBan,
    String? extraNegative,
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    return AestheticStyle.assembleNegative(
      eraBans: era?.negativeBans,
      styleBans: styleNegativeBan,
      extraNegative: extraNegative,
      additionalBans: const [
        humanSuppressionNegativeLock,
        defaultNegativeArtifacts,
      ],
      universalBans: AestheticStyle.universalNegativeBrief,
    );
  }

  /// 组装 360° 等矩球形全景母图专属生图提示词（契合 Agnes 2.5 Flash 高信息密度全景文生图规范）。
  /// 严格保证空旷无人物背景板、360 度等矩极坐标映射约束、环境空间全息描写与时代风格。
  static String buildPanoramaPrompt({
    required String basePrompt,
    String? styleTokens,
    String? eraGenreId,
    bool sanitize = true,
    String? panoramaSystemPromptOverride,
    String? systemPromptOverride,
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    final cleaned = sanitize ? sanitizeBasePrompt(basePrompt) : basePrompt.trim();
    final isEnclosed = isEnclosedText('$basePrompt $cleaned');

    String? envAnchor = era?.environmentAnchor.trim();
    String? style = styleTokens?.trim();

    if (isEnclosed) {
      if (envAnchor != null && envAnchor.isNotEmpty) {
        envAnchor = sanitizeEnvironmentAnchor(envAnchor);
      }
      if (style != null && style.isNotEmpty) {
        style = sanitizeStyleForEnclosed(style);
      }
    }

    // 针对 360° 等矩投影全景母图的强约束前导词与尾部锚点（注入大空间大景深与机位后撤约束）
    const String panoHead =
        '360 degree equirectangular panorama projection, VR 360 spherical photosphere, seamless 360 wide horizon, flat equirectangular map, wide-angle distant establishing shot, deep perspective, spacious architectural vista, distant camera viewpoint pulled back, 开阔宏大空间全景，深远大景深，机位后撤远视距，挑高通透大空间，纯净360度空间物理全景';

    const String panoTail =
        'full 360 degrees panoramic vista, spherical panorama texture, vast unobstructed architectural space with high ceiling and deep corridor depth, high visual density, 8k resolution, 开阔宏大空间空镜头，机位开阔后撤，完整挑高房顶与通透地面，完全无人纯净空间空镜头';

    final String panoHeadText;
    final String panoTailText;
    if (panoramaSystemPromptOverride != null && panoramaSystemPromptOverride.trim().isNotEmpty) {
      panoHeadText = panoramaSystemPromptOverride.trim();
      panoTailText = '';
    } else {
      panoHeadText = panoHead;
      panoTailText = panoTail;
    }

    final hasSystemOverride = systemPromptOverride != null && systemPromptOverride.trim().isNotEmpty;
    final headLock = hasSystemOverride ? systemPromptOverride.trim() : emptyHeadLock;

    final middleParts = <String>[
      headLock,
      if (!hasSystemOverride && envAnchor != null && envAnchor.isNotEmpty) envAnchor,
      if (style != null && style.isNotEmpty) style,
      if (cleaned.isNotEmpty) cleaned,
      if (!hasSystemOverride) emptyTailLock,
    ];

    final resultParts = <String>[
      panoHeadText,
      middleParts.where((s) => s.trim().isNotEmpty).join('， '),
      if (panoTailText.isNotEmpty) panoTailText,
    ];

    return resultParts.where((s) => s.trim().isNotEmpty).join('， ');
  }
}

/// 关键道具生图提示词组装器（spec: prop-cards 与 studio-prompt-templates）。
///
/// 动态从 [StudioPresetStore] 读取 prop_asset 资产规范模板，
/// 统一规范纯白底、无人物手部遮挡、微观物理材质与高清特写。
abstract final class PropPromptBuilder {
  /// 道具资产单品规范（动态从预设库读取，若空则回退到出厂默认值）。
  static String get propAssetRequirement {
    final t = StudioPresetStore.instance.getPromptContent('prop_asset');
    if (t.trim().isNotEmpty) return t.trim();
    return '道具资产单品设计图，纯白无缝背景，居中展示，高清特写材质与纹理细节，无背景杂物，无人物手部遮挡，真实物理反光与质感';
  }

  /// 组装道具生图正向提示词。
  static String buildPositivePrompt({
    required String prompt,
    String? styleTokens,
    String? eraGenreId,
    String? systemPromptOverride,
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    final req = (systemPromptOverride != null && systemPromptOverride.trim().isNotEmpty)
        ? systemPromptOverride.trim()
        : propAssetRequirement;
    final parts = [
      req,
      if (era != null && era.propMaterialAnchor.isNotEmpty) era.propMaterialAnchor,
      if (styleTokens != null && styleTokens.trim().isNotEmpty) styleTokens.trim(),
      prompt.trim(),
    ];
    return parts.join('， ');
  }

  /// 组装道具生图负向提示词。
  static String buildNegativePrompt({
    String? eraGenreId,
    String? styleNegativeBan,
    String? extraNegative,
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    const baseNeg =
        'multiple items, background clutter, human, hands, body, blurry, deformed，多件物品，背景杂物，人物，手部，身体遮挡，模糊，变形';
    return AestheticStyle.assembleNegative(
      eraBans: era?.negativeBans,
      styleBans: styleNegativeBan,
      extraNegative: extraNegative,
      additionalBans: const [baseNeg],
      universalBans: AestheticStyle.universalNegativeBrief,
    );
  }
}

/// 剧本主要道具的资产卡。
///
/// 与 [CharacterCard] 平级但不复用：道具没有 TTS 音色、没有形态版本、不参与
/// 跨集记忆注入。复用角色卡会带入一堆对道具无意义的空字段，并在 UI 侧到处
/// 分叉判断（design 决策 1）。
///
/// [isKeyProp] 是重要性标记：关键道具（如信物、凶器）值得单独出参考图保持
/// 跨镜头一致；普通道具可以不配图、只靠提示词描述。
class PropCard {
  final String id;
  final String name;

  /// 中文描述（用户输入原文，供「生成 Prompt」用）。
  final String descriptionZh;

  /// 英文道具 Prompt（直接进入最终生图 Prompt）。
  final String promptEn;

  /// 参考图路径列表（道具目录下的文件名）。
  final List<String> referenceImages;

  /// 是否为关键道具。
  final bool isKeyProp;

  /// 道具资产规范前导词覆盖（非空时优先使用，替换默认单品规范模板）。
  final String? systemPromptOverride;

  final DateTime updatedAt;

  const PropCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.promptEn = '',
    this.referenceImages = const [],
    this.isKeyProp = false,
    this.systemPromptOverride,
    required this.updatedAt,
  });

  PropCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? promptEn,
    List<String>? referenceImages,
    bool? isKeyProp,
    String? systemPromptOverride,
    bool clearSystemPromptOverride = false,
    DateTime? updatedAt,
  }) {
    return PropCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      promptEn: promptEn ?? this.promptEn,
      referenceImages: referenceImages ?? this.referenceImages,
      isKeyProp: isKeyProp ?? this.isKeyProp,
      systemPromptOverride: clearSystemPromptOverride
          ? null
          : (systemPromptOverride ?? this.systemPromptOverride),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description_zh': descriptionZh,
    'prompt_en': promptEn,
    'reference_images': referenceImages,
    'is_key_prop': isKeyProp,
    if (systemPromptOverride != null && systemPromptOverride!.isNotEmpty)
      'system_prompt_override': systemPromptOverride,
    'updated_at': updatedAt.toIso8601String(),
  };

  static PropCard fromJson(Map<String, dynamic> json) {
    return PropCard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      descriptionZh: json['description_zh'] as String? ?? '',
      promptEn: json['prompt_en'] as String? ?? '',
      referenceImages:
          (json['reference_images'] as List?)?.cast<String>() ?? const [],
      isKeyProp: json['is_key_prop'] as bool? ?? false,
      systemPromptOverride: json['system_prompt_override'] as String? ??
          json['systemPromptOverride'] as String?,
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

/// 视觉时代题材预设（spec: series-asset-library 视觉时代与题材锁）。
///
/// 解决文生图大模型在无下半身服饰约束时自动采样现代休闲裤/沙滩裤的穿帮问题。
/// 包含：中英文标签、正向服饰锚点、正向环境/材质锚点、排他负向违禁词。
class VisualEraGenre {
  final String id;
  final String labelZh;
  final String descriptionZh;

  /// 角色服装正向锚点（覆盖全身、上下半身与标志性配饰，杜绝仅有面部描写）。
  final String costumeAnchor;

  /// 场景环境与物体材质正向锚点。
  final String environmentAnchor;

  /// 道具材质正向锚点。
  final String propMaterialAnchor;

  /// 时代排他负向词典（强力抑制该时代不应出现的现代或冲突元素）。
  final String negativeBans;

  /// 是否为出厂系统预设（用户自定义为 false）。
  final bool isBuiltin;

  const VisualEraGenre({
    required this.id,
    required this.labelZh,
    required this.descriptionZh,
    required this.costumeAnchor,
    required this.environmentAnchor,
    required this.propMaterialAnchor,
    required this.negativeBans,
    this.isBuiltin = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label_zh': labelZh,
    'description_zh': descriptionZh,
    'costume_anchor': costumeAnchor,
    'environment_anchor': environmentAnchor,
    'prop_material_anchor': propMaterialAnchor,
    'negative_bans': negativeBans,
    'is_builtin': isBuiltin,
  };

  static VisualEraGenre fromJson(Map<String, dynamic> json) => VisualEraGenre(
    id: json['id'] as String? ?? '',
    labelZh: json['label_zh'] as String? ?? '',
    descriptionZh: json['description_zh'] as String? ?? '',
    costumeAnchor: json['costume_anchor'] as String? ?? '',
    environmentAnchor: json['environment_anchor'] as String? ?? '',
    propMaterialAnchor: json['prop_material_anchor'] as String? ?? '',
    negativeBans: json['negative_bans'] as String? ?? '',
    isBuiltin: json['is_builtin'] as bool? ?? false,
  );

  /// 全部内置出厂预设
  static const List<VisualEraGenre> presets = [
    VisualEraGenre(
      id: 'xianxia',
      labelZh: '仙侠修真',
      descriptionZh: '东方玄幻修真世界，仙门洞府，飘逸道袍汉服与飞剑法宝',
      costumeAnchor:
          '中式传统古装仙侠服饰，宽袍大袖，丝绸罗缎，精致仙门云纹滚边，玉佩香囊，长发束冠或飘逸发髻',
      environmentAnchor:
          '中式古典仙侠景观，云雾缭绕，奇峰仙山，古建亭台楼阁，雕梁画栋，重檐青瓦，古朴长街古道',
      propMaterialAnchor:
          '青铜古剑，温润白玉，紫檀沉木，古朴陶瓷，符箓阵法，灵光流转',
      negativeBans:
          '现代服饰，短袖短裤，牛仔裤，拉链纽扣，现代西装，现代建筑，汽车马路，电线杆，塑料制品，粗糙现代工业品，英文文字，画面模糊失真，低画质',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'ancient_costume',
      labelZh: '古装武侠',
      descriptionZh: '古代江湖武林，刀光剑影，汉服劲装与客栈酒肆',
      costumeAnchor:
          '中式传统武侠劲装汉服，利落束袖短打，护腕皮带，麻布腰带，古代软皮短靴，斗笠蓑衣，游侠装束',
      environmentAnchor:
          '古代江湖客栈酒肆，青石长街古巷，木结构深宅大院，翠竹青竹林，残阳古道，灰瓦飞檐',
      propMaterialAnchor:
          '百炼镔铁古刀长剑，沧桑木鞘，皮质缠柄，粗陶酒坛酒碗，古铜钱，麻绳线装书',
      negativeBans:
          '现代服装，休闲T恤，短裤短袖，牛仔裤，卫衣，现代皮鞋球鞋，西装领带，手表眼镜，现代水泥路，电线杆，霓虹灯',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'ancient_transmigration',
      labelZh: '古装穿越',
      descriptionZh: '穿越古代宫廷与世家，华美华服与古典礼制',
      costumeAnchor:
          '古典中式宫廷世家华服，高档流云真丝汉服，金丝银线刺绣，多层叠穿大袖襦裙，精致古风发簪步摇与羊脂白玉佩',
      environmentAnchor:
          '古代宫廷殿宇，雕梁画栋，朱红宫墙，琉璃金瓦，水榭回廊，古风荷塘庭院',
      propMaterialAnchor:
          '皇家羊脂白玉玺印，掐丝珐琅古铜炉，古籍字画卷轴，御用景德镇细瓷，紫檀木盒',
      negativeBans:
          '现代服装，短裤短裙，现代T恤，牛仔裤，西裤卫衣，高跟鞋运动鞋，手表，现代眼镜，现代欧式家具，现代装潢',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'republic_vintage',
      labelZh: '民国谍战',
      descriptionZh: '民国上海滩与军阀谍战，洋楼旗袍与风衣礼帽',
      costumeAnchor:
          '民国复古服饰，典雅刺绣丝绸旗袍，挺括毛呢大风衣，礼帽，复古皮手套，高领中山装，复古擦色牛津皮鞋',
      environmentAnchor:
          '1930年代民国上海滩街头，老青砖石库门弄堂，欧式租界红砖洋楼，有轨电车轨道，黄昏昏黄老式路灯，复古霓虹招牌',
      propMaterialAnchor:
          '复古黄铜老式转盘电话，复古牛皮公文包，怀表，老式英雄钢笔，泛黄机密纸质档案公文，老式黑胶留声机',
      negativeBans:
          '当代现代服饰，短裤T恤，运动卫衣，球鞋，现代智能手机，现代汽车，高楼玻璃幕墙，古代飘逸汉服，玄幻铠甲',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'ancient_palace',
      labelZh: '宫廷权谋',
      descriptionZh: '古代皇权争斗与后宫权谋，锦衣华服与重门深锁',
      costumeAnchor:
          '华贵古代皇家宫廷朝服礼服，高阶权臣锦衣官袍，金丝蟠龙彩凤重工刺绣，厚重织锦云锦缎面，精致玉带朝珠，凤冠步摇，仪仗皂靴',
      environmentAnchor:
          '紫禁紫宸大殿，雕花朱红巨柱，九龙金漆宝座，沉重宫幔垂纱，汉白玉御道栏杆，深宫古柳幽深庭院',
      propMaterialAnchor:
          '传国白玉玺印，朱砂雕漆方盒，鎏金三足香薰兽炉，明黄绢帛圣旨，极品甜白釉御用茶盏',
      negativeBans:
          '现代服装，短裤短裙，T恤球鞋，牛仔裤，现代近视眼镜，洋装西服，现代家具，现代混凝土建筑',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'modern_suspense',
      labelZh: '现代悬疑刑侦',
      descriptionZh: '当代都市罪案与硬核刑侦，战术便服与雨夜追凶',
      costumeAnchor:
          '低调实用刑警便服，深色防风防水夹克风衣，战术工装深色长裤，耐磨户外高帮皮靴，硬朗深色皮夹克',
      environmentAnchor:
          '雨夜潮湿都市案发现场，拉起黄色警戒线的阴暗潮湿后巷，反光积水路面，冷调审讯室，昏暗压抑老旧警局办公室',
      propMaterialAnchor:
          '金属警徽，刑侦勘查取证箱，战术强光手电，磨损调查笔记本，不锈钢防风打火机，多屏监控显示器',
      negativeBans:
          '古代汉服，古装长袍，历史戏服，奇幻盔甲，浮夸华丽礼服，魔法光晕符文，冷兵器长剑',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'folk_myth',
      labelZh: '中式民俗怪谈',
      descriptionZh: '民间志怪怪谈与湘西聊斋，古朴草木染、道士芒鞋与荒冢古庙',
      costumeAnchor:
          '传统中式乡野民俗粗布衣裳，粗麻棉布短褂，道士驱邪布袍，八卦束腰布带，草鞋芒鞋，绑腿布靴',
      environmentAnchor:
          '薄雾笼罩的荒山残破野庙，月下杂草丛生的古老荒冢野坟，黄昏阴森古村落，幽微惨黄灯笼，挂满红布条的老槐树',
      propMaterialAnchor:
          '朱砂亲书黄纸符箓，百年雷击桃木剑，驱邪铜铃，招魂白纸灯笼，斑驳铜镜',
      negativeBans:
          '现代时装，牛仔裤，短裤短袖，运动鞋，现代数码电子产品，鲜艳霓虹灯，西方骑士盔甲，高科技机械',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'cyber_immortal',
      labelZh: '赛博修仙',
      descriptionZh: '机械飞升与道教朋克，发光八卦经络与合金飞剑',
      costumeAnchor:
          '赛博道风修真长袍，流光八卦发光回路机械外骨骼，神经接驳白玉发簪，强化碳纤维道袍僧衣，电路纹身机械义肢手臂',
      environmentAnchor:
          '反乌托邦赛博东方巨型都市，耸入云霄的巨型霓虹宝塔摩天楼，拖曳数据流光的飞空机械飞剑群，全息神像照耀的雨夜赛博古刹屋脊',
      propMaterialAnchor:
          '等离子高能光刃灵剑，钛合金合成符箓芯片，全息八卦罗盘仪，量子微核香炉反应堆',
      negativeBans:
          '纯田园无科技古代道袍，土木木车，中世纪十字军板甲，纯西方奇幻服装',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'modern_urban',
      labelZh: '现代都市豪门',
      descriptionZh: '当代高线都市，商务精英与豪门世家，高端定制时装',
      costumeAnchor:
          '奢华现代高定商务时装，剪裁考究的深色高定西装，修身风衣西装外套，高定礼服长裙，手工定制顶级皮鞋，精英名媛妆造',
      environmentAnchor:
          '顶级都市顶层豪华大平层复式公寓，全景落地窗眺望繁华都市天际线夜景，极简大理石意式内饰，温馨奢华内嵌环境光',
      propMaterialAnchor:
          '极简现代奢华工艺，拉丝钛合金，高级小牛皮，蓝宝石水晶玻璃，极简金属器皿',
      negativeBans:
          '古代服装，古装汉服，道袍襦裙，和服，中世纪长袍，奇幻铠甲，破烂乞丐装，粗麻短褐，古代刀剑长矛',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'sci_fi_superpower',
      labelZh: '科幻异能',
      descriptionZh: '近未来都市异能觉醒，战术机能风与能量回路',
      costumeAnchor:
          '都市战术机能战服，高机能机动街道时装，深色特种战术机能外套，暗光能量回路管道，流线型战术工装裤与战术作训靴',
      environmentAnchor:
          '近未来赛博都市高架，细雨积水街道反射全息广告投影，幽蓝霓虹光晕，先进高能研究所，生物扫描安检光闸',
      propMaterialAnchor:
          '高科技复合高分子聚合物，哑光碳纤维外壳，微型发光能量核心模块，模块化战术外设',
      negativeBans:
          '古代长袍，传统汉服，古装戏服，中世纪铁甲，破烂农家布衣，维多利亚洋服，木轮马车',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'wasteland',
      labelZh: '末日废土',
      descriptionZh: '末世求生与废土朋克，风化做旧与实用战术改装',
      costumeAnchor:
          '废土拾荒生存装束，风化做旧粗犷战术服，补丁厚重皮夹克，多功能战术绑带，防尘防风风镜，防毒面罩，防刺重型作训靴',
      environmentAnchor:
          '苍凉死寂的末日荒原废墟，坍塌钢筋混凝土残垣断壁，锈迹斑斑工业重械残骸，漫天漫卷黄沙尘暴，废弃机械拆解营地',
      propMaterialAnchor:
          '废料改装拼装铁片，焊接生锈钢板，重型改装防爆盾，绝缘胶布捆绑修复痕迹，沧桑战损多功能生存工具',
      negativeBans:
          '干净光洁衣物，整齐西装领带，传统一尘不染汉服，华丽礼服裙，光洁无瑕现代时装，精致全妆',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'cyberpunk_sci_fi',
      labelZh: '赛博未来',
      descriptionZh: '硬核太空与赛博义体，碳纤维战甲与霓虹光路',
      costumeAnchor:
          '流线型未来义体紧身作战服，哑光碳纤维轻型装甲板，流光LED灯带回路，镀铬金属神经义体接口，外骨骼机械强化组件',
      environmentAnchor:
          '巨构科幻宏伟都市，雨雾中高耸入云的巨型全息大厦，暗黑潮湿赛博后巷，浮空穿梭飞艇航道，高轨道空间站太空舱内景',
      propMaterialAnchor:
          '航空级太空合金，透明全息投影玻璃，哑光碳纤维复合物，微型量子动力电池核心',
      negativeBans:
          '古代长袍，传统古装，汉服襦裙，中世纪长袍，粗麻破布，马拉木车，原始土木茅草屋',
      isBuiltin: true,
    ),
    VisualEraGenre(
      id: 'isekai_fantasy',
      labelZh: '异世界奇幻',
      descriptionZh: '西幻冒险者公会与魔法世界，皮甲法袍与魔导器物',
      costumeAnchor:
          '中世纪西方奇幻冒险者皮甲便服，硬皮战术护甲背心，束腰粗麻衬衫短打，带兜帽防风旅行者斗篷，皮革旅行短靴，公会冒险者徽章',
      environmentAnchor:
          '喧闹温暖的石木结构冒险者公会酒馆，青石板铺筑的奇幻王都街市，阳光倾泻的远古巨木森林，雄伟中世纪石砌城堡城门',
      propMaterialAnchor:
          '精钢锻造单手骑士短剑，皮质剑鞘，镶嵌微光魔力水晶法杖，复古羊皮纸卷轴地图，黄铜冒险者身份铭牌',
      negativeBans:
          '现代工业服装，T恤牛仔裤，现代运动鞋，现代汽车，高楼大厦，数码电子屏幕，中国传统汉服道袍',
      isBuiltin: true,
    ),
  ];

  static VisualEraGenre? fromId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final p in presets) {
      if (p.id.toLowerCase() == normalized) return p;
    }
    return null;
  }
}

/// 美学风格预设（spec: series-asset-library 8大体系35套工业级美学风格）。
///
/// 决定生图与生视频的渲染媒介、画风质感与专属负向避雷约束。
class AestheticStyle {
  final String id;
  final String category;
  final String nameZh;
  final String descriptionZh;
  final String positiveAnchor;
  final String negativeBan;
  final String defaultRatio;
  final bool isBuiltin;

  const AestheticStyle({
    required this.id,
    required this.category,
    required this.nameZh,
    required this.descriptionZh,
    required this.positiveAnchor,
    required this.negativeBan,
    this.defaultRatio = '16:9',
    this.isBuiltin = true,
  });

  /// 通用负面词（精简版，省 token，所有风格通用兜底）
  static const String universalNegativeBrief =
      '畸形手部，多手指，五官扭曲，脸部崩坏，肢体变形，模糊，低分辨率，水印，文字，logo，丑，噪点爆炸';

  /// 通用负面词（完整版，极致画质防崩）
  static const String universalNegativeFull =
      '畸形手部，多手指，缺手指，五官错位，脸部扭曲，肢体崩坏，多余肢体，重复物体，变形，模糊，低分辨率，水印，文字，logo，丑陋，杂乱噪点，画面撕裂，色差崩坏';

  /// 将由中英文逗号、分号或换行分隔的提示词拆分、去除空白、保留原始格式且不区分大小写保序去重。
  static String deduplicateTokens(String text) {
    if (text.trim().isEmpty) return '';
    final seen = <String>{};
    final result = <String>[];
    for (final raw in text.split(RegExp(r'[,，；;\n]+'))) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      final lower = token.toLowerCase();
      if (seen.add(lower)) {
        result.add(token);
      }
    }
    return result.join(', ');
  }

  /// 组装三层负向防崩词：
  /// [eraBans] (时代题材排他违禁词) + [styleBans] (美学风格专属违禁词) + [extraNegative] (如角色/形态/场景专属) + [universalBans] (通用防崩词)
  /// 自动合并、分词去重并保持整洁。
  static String assembleNegative({
    String? eraBans,
    String? styleBans,
    String? extraNegative,
    List<String> additionalBans = const [],
    String universalBans = universalNegativeBrief,
    bool includeUniversal = true,
  }) {
    final rawTokens = <String>[];
    if (eraBans != null && eraBans.trim().isNotEmpty) {
      rawTokens.add(eraBans.trim());
    }
    if (styleBans != null && styleBans.trim().isNotEmpty) {
      rawTokens.add(styleBans.trim());
    }
    if (extraNegative != null && extraNegative.trim().isNotEmpty) {
      rawTokens.add(extraNegative.trim());
    }
    for (final ban in additionalBans) {
      if (ban.trim().isNotEmpty) rawTokens.add(ban.trim());
    }
    if (includeUniversal && universalBans.trim().isNotEmpty) {
      rawTokens.add(universalBans.trim());
    }
    return deduplicateTokens(rawTokens.join(', '));
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'name_zh': nameZh,
    'description_zh': descriptionZh,
    'positive_anchor': positiveAnchor,
    'negative_ban': negativeBan,
    'default_ratio': defaultRatio,
    'is_builtin': isBuiltin,
  };

  static AestheticStyle fromJson(Map<String, dynamic> json) => AestheticStyle(
    id: json['id'] as String? ?? '',
    category: json['category'] as String? ?? '',
    nameZh: json['name_zh'] as String? ?? '',
    descriptionZh: json['description_zh'] as String? ?? '',
    positiveAnchor: json['positive_anchor'] as String? ?? '',
    negativeBan: json['negative_ban'] as String? ?? '',
    defaultRatio: json['default_ratio'] as String? ?? '16:9',
    isBuiltin: json['is_builtin'] as bool? ?? false,
  );

  static AestheticStyle? fromId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final s in presets) {
      if (s.id.toLowerCase() == normalized) return s;
    }
    return null;
  }

  static const List<AestheticStyle> presets = [
    AestheticStyle(
      id: 'ue5_3d_xianxia',
      category: '东方国风',
      nameZh: 'UE5 3D国漫·东方玄幻',
      descriptionZh: '次世代CG虚幻5东方仙侠，精细发丝布料与宏大仙门云海',
      positiveAnchor: 'UE5渲染，3D国漫，次世代CG，PBR物理材质，超精细发丝，布料刺绣褶皱，金属配饰反光，东方仙侠美学，体积光，云海雾气，全局光照，景深，电影级运镜，宏大构图，16:9横屏，8K，超高细节，史诗氛围感',
      negativeBan: '畸形手部，多手指，五官扭曲，脸部崩坏，肢体变形，塑料感过重，模糊，低分辨率，水印，文字，logo，丑，噪点爆炸，2D手绘，Q版卡通',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'ue5_3d_ancient_cg',
      category: '东方国风',
      nameZh: 'UE5 3D国漫·古言写实CG',
      descriptionZh: '次世代写实东方古风CG，厚重庄严与电影布光',
      positiveAnchor: 'UE5渲染，3D国漫写实CG，次世代PBR材质，细腻发丝，古装布料纹理刺绣，古建筑，柔和天光，电影布光，厚重东方写实美学，景深，中景构图，16:9横屏，8K，高细节，庄重氛围感',
      negativeBan: '畸形手部，五官错位，脸部扭曲，肢体崩坏，法术特效过多，塑料质感，卡通Q版，水墨，手绘，模糊，水印，文字，丑，多余肢体',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'ink_wash_2d',
      category: '东方国风',
      nameZh: '2D水墨写意国风',
      descriptionZh: '中国传统写意水墨手绘，墨色晕染与空灵留白意境',
      positiveAnchor: '中国水墨手绘动画，写意国画，墨色晕染，留白构图，淡彩上色，飘逸毛笔线条，山水云雾，低饱和度，东方意境，2D动画分镜，柔和笔触，16:9横屏，高细节，诗意氛围感',
      negativeBan: '3D建模，CG，照片写实，鲜艳高饱和，金属强反光，塑料材质，畸形手部，五官崩坏，水印，文字，厚重硬阴影',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'gongbi_heavy_color_2d',
      category: '东方国风',
      nameZh: '2D工笔重彩国风',
      descriptionZh: '2D工笔重彩国画质感，精细墨线勾勒与传统矿物颜料',
      positiveAnchor: '2D手绘工笔重彩，精细墨线勾勒，华丽传统纹样，青绿朱砂配色，繁复古装服饰，典雅东方美学，细腻填色，国画质感，电影分镜，柔和光影，16:9横屏，高细节',
      negativeBan: '3D，CG，照片，水墨晕染，低饱和，塑料质感，变形，水印，文字，肢体崩坏，粗糙笔触',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'new_chinese_cel_comic',
      category: '东方国风',
      nameZh: '新中式平涂漫剧',
      descriptionZh: '新中式清新2D漫剧平涂，干净轮廓线与柔和色调',
      positiveAnchor: '新中式2D平涂漫剧，干净轮廓线，薄涂上色，简化古风五官，柔和阴影，清新配色，漫剧分镜，流畅动画，16:9横屏，4K，干净柔和氛围感',
      negativeBan: '3D，写实照片，厚涂油画，脏笔触，畸形手部，水印，文字，真人，强反光金属，复杂PBR材质',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'dunhuang_rock_color',
      category: '东方国风',
      nameZh: '敦煌岩彩国风',
      descriptionZh: '魏晋西域敦煌壁画岩彩，颗粒矿物肌理与石青土红金箔',
      positiveAnchor: '敦煌岩彩手绘风格，岩彩颗粒肌理，土红石青金箔质感，壁画美学，魏晋西域古风，厚重色彩，斑驳壁画纹理，2D手绘，电影分镜，柔和漫射光，16:9横屏，高细节',
      negativeBan: '光滑塑料，3D次世代CG，现代服装，高锐化，畸形肢体，水印，文字，水墨晕染，鲜艳荧光色',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'blue_green_landscape',
      category: '东方国风',
      nameZh: '青绿山水国风',
      descriptionZh: '传统千里江山青绿山水，长卷构图与清雅远山天光',
      positiveAnchor: '青绿山水国画风格，2D/3D渲染，长卷构图，青绿色调山水，雅致低对比，传统国画美学，远山云雾，柔和天光，古风人物，电影分镜，16:9横屏，细腻画面，宁静氛围感',
      negativeBan: '高饱和艳色，硬阴影，金属强反光，畸形五官，水印，文字，写实照片，脏噪点，厚重油画笔触',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'folk_new_year_painting',
      category: '东方国风',
      nameZh: '年画民俗国风',
      descriptionZh: '中国民间年画民俗质感，高饱和纯色与木版年画装饰纹样',
      positiveAnchor: '中国传统年画风格，2D手绘，高饱和配色，平面构图，民间装饰纹样，乡土民俗质感，清晰轮廓，质朴色彩，电影分镜，16:9横屏，高细节',
      negativeBan: '3D写实，CG，照片，景深虚化，塑料材质，畸形肢体，水印，文字，柔和渐变，油画厚涂',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'anime_cel_shading',
      category: '日系二次元',
      nameZh: '日系赛璐璐平涂',
      descriptionZh: '经典日系2D动画赛璐璐，清晰轮廓与干净明朗阴影',
      positiveAnchor: '日系赛璐璐2D动画，清晰黑色轮廓线，平涂上色，干净硬阴影，二次元精致五官，漫剧分镜，柔和色彩，青春氛围感，16:9横屏，4K，流畅动画',
      negativeBan: '3D，写实照片，厚涂油画，脏笔触，畸形手部，水印，文字，真人，复杂PBR材质，强反光',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'anime_painterly_realism',
      category: '日系二次元',
      nameZh: '日系厚涂动画（新番写实向）',
      descriptionZh: '偏写实新番2D厚涂动画，丰富光影层次与动态张力',
      positiveAnchor: '日系2D厚涂动画，厚重油画笔触，丰富光影层次，偏写实二次元人物，动态张力，动画分镜，电影光影，细腻色彩，16:9横屏，高细节',
      negativeBan: '平涂赛璐璐，3D渲染，照片，低对比，模糊，水印，文字，畸形肢体，光滑塑料材质',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'ghibli_watercolor_texture',
      category: '日系二次元',
      nameZh: '吉卜力手绘动画质感',
      descriptionZh: '吉卜力暖调手绘水彩质感，自然天光与治愈系田园肌理',
      positiveAnchor: '吉卜力手绘动画质感，2D手绘，柔和手绘笔触，暖调自然天光，朦胧柔光，丰富自然环境，治愈氛围，手绘肌理，动画分镜，16:9横屏，高细节',
      negativeBan: '锐利硬阴影，3D CG，写实照片，强金属反光，畸形手部，水印，文字，高对比度，赛博朋克',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'japanese_ukiyo_e',
      category: '日系二次元',
      nameZh: '日系浮世绘',
      descriptionZh: '江户浮世绘传统木版画，平面线条与传统装饰纹样',
      positiveAnchor: '日式浮世绘版画，2D手绘版画线条，平面平涂色彩，风月海浪构图，装饰性纹样，日式古风，电影分镜，16:9横屏，高细节，复古版画氛围感',
      negativeBan: '3D，写实照片，渐变光影，景深虚化，塑料材质，畸形肢体，水印，文字，厚涂油画',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'pixar_disney_3d_animation',
      category: '西式CG/3D卡通',
      nameZh: '皮克斯迪士尼3D卡通',
      descriptionZh: '皮克斯迪士尼三维卡通CG，圆润造型柔光与温润质感',
      positiveAnchor: '皮克斯迪士尼3D卡通CG，圆润角色建模，柔和漫反射柔光，细腻毛发，温润材质，柔和阴影，明亮干净色彩，童话场景，电影动画，16:9横屏，8K，温暖治愈氛围',
      negativeBan: '写实人像，恐怖暗黑，尖锐硬阴影，强金属反光，畸形肢体，水印，文字，国风仙侠，塑料感过重',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'ue5_western_fantasy_cg',
      category: '西式CG/3D卡通',
      nameZh: '写实西方次世代CG（UE5）',
      descriptionZh: '中世纪西方魔幻UE5写实CG，PBR物理金属铠甲与史诗魔幻',
      positiveAnchor: 'UE5次世代西方写实CG，PBR物理材质，高精度铠甲岩石植被，写实西方人面部，中世纪魔幻美学，全局光照，体积雾，景深，宏大场景，电影运镜，16:9横屏，8K，史诗质感',
      negativeBan: 'Q版卡通，国风，水墨，手绘，畸形手部，五官崩坏，塑料质感，水印，文字，低细节',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'arcane_painterly_comic',
      category: '西式CG/3D卡通',
      nameZh: '美漫厚涂（双城之战类）',
      descriptionZh: '双城之战风格美漫厚涂，硬朗明暗切割与强烈油画笔触',
      positiveAnchor: '美漫厚涂风格，类似双城之战，粗硬轮廓，强烈明暗切割，浓郁色彩，油画笔触，硬朗人物造型，动态张力，动画分镜，电影光影，16:9横屏，高细节',
      negativeBan: '日系平涂，3D写实照片，水墨，低对比，模糊，水印，文字，畸形肢体，光滑塑料材质',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'retro_american_90s_cartoon',
      category: '西式CG/3D卡通',
      nameZh: '美式复古卡通（90年代卡通）',
      descriptionZh: '90年代美式复古手绘卡通，粗轮廓高饱和夸张幽默',
      positiveAnchor: '90年代美式复古2D卡通，粗黑轮廓线，高饱和色彩，夸张人物造型，复古动画质感，平涂上色，漫画分镜，16:9横屏，高细节，轻松喜剧氛围',
      negativeBan: '写实照片，3D CG，厚涂油画，柔和渐变，畸形手部，水印，文字，胶片颗粒',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'ue5_cyberpunk_cg',
      category: '科幻赛博废土',
      nameZh: 'UE5赛博朋克CG',
      descriptionZh: 'UE5未来赛博朋克都市，雨夜霓虹全息投影与金属倒影',
      positiveAnchor: 'UE5赛博朋克次世代CG，雨夜路面反光，霓虹灯光，巨型未来都市，全息投影，金属PBR材质，雾气，镜头光晕，高对比冷调，电影级运镜，16:9横屏，8K，科幻氛围感',
      negativeBan: '古风，水墨，手绘，暖色调，畸形人脸，手部崩坏，水印，文字，Q版卡通，柔和柔光',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'hardcore_realistic_scifi',
      category: '科幻赛博废土',
      nameZh: '硬核写实科幻',
      descriptionZh: '硬核写实太空科幻实拍CG，冷峻低饱和物理级天体光影',
      positiveAnchor: '硬核写实科幻，3D CG实拍合成，写实航天器，宇宙星空，物理级光影，冷峻低饱和色彩，宏大太空场景，电影布光，景深，16:9横屏，8K，冷峻写实质感',
      negativeBan: '卡通，二次元，鲜艳霓虹，古风，畸形肢体，水印，文字，塑料材质，过多装饰特效',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'wasteland_post_apocalypse',
      category: '科幻赛博废土',
      nameZh: '废土末世质感',
      descriptionZh: '废土末世机械生存朋克，锈蚀金属风化沙尘与粗粝压抑',
      positiveAnchor: '废土末世风格，3D/实拍混合渲染，褪色灰暗色调，锈蚀金属，破损建筑，沙尘，荒芜破败环境，硬自然光，电影构图，16:9横屏，高细节，苍凉压抑氛围',
      negativeBan: '鲜亮高饱和，干净光滑材质，童话卡通，国风，畸形五官，水印，文字，柔和柔光',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'steampunk',
      category: '科幻赛博废土',
      nameZh: '蒸汽朋克',
      descriptionZh: '维多利亚复古蒸汽朋克，黄铜机械齿轮与浓郁烟雾蒸汽',
      positiveAnchor: '蒸汽朋克，3D CG渲染，黄铜齿轮，管道机械，维多利亚复古服饰，黄铜暖色调，机械细节，金属锈蚀质感，体积雾，电影光影，16:9横屏，高细节，复古奇幻氛围',
      negativeBan: '赛博霓虹，现代都市，水墨国风，光滑塑料，畸形手部，水印，文字，明亮马卡龙配色',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'dieselpunk',
      category: '科幻赛博废土',
      nameZh: '柴油朋克',
      descriptionZh: '重工业机械柴油朋克，油污铁锈与厚重战争机械工业风',
      positiveAnchor: '柴油朋克，3D渲染，重型工业机械，油污铁锈，暗沉棕黑色调，粗粝工业质感，战争机械，硬光影，电影构图，16:9横屏，高细节，粗粝厚重氛围',
      negativeBan: '马卡龙亮色，童话卡通，国风仙侠，干净光滑材质，畸形肢体，水印，文字，柔和柔光',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'costume_drama_realism',
      category: '实拍电影质感',
      nameZh: '真人古装·仙侠影视大片',
      descriptionZh: '院线级真人古装仙侠实拍质感，真实演员毛孔肤质、飘逸汉服刺绣与电影级东方美学布光',
      positiveAnchor: '真人古装仙侠实拍，院线电影质感，真实演员出镜，自然皮肤毛孔纹理，精细东方汉服刺绣暗纹与飘逸丝绸褶皱，35mm电影镜头，专业影视唯美布光，柔和丁达尔体积光，真实浅景深，微弱胶片颗粒，电影构图，16:9横屏，8K超高画质，东方史诗感',
      negativeBan: '3D动画，CG渲染，卡通，动漫，Q版，手绘插画，塑料皮肤，过度美颜滤镜，畸形手部，五官错位，现代服装穿帮，水印，文字，低分辨率',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'live_action_short_drama',
      category: '实拍电影质感',
      nameZh: '真人爆款·实拍短剧',
      descriptionZh: '商业爆款短剧实拍质感，真实演员微表情、高对比清晰轮廓光与高品质现代影视质感',
      positiveAnchor: '真人短剧实拍画面，真实演员面容，细腻皮肤纹理与真实眼神微表情，高对比商业影视布光，清晰人物轮廓光，35mm镜头浅景深，现代流行色调，电影构图，16:9横屏，4K高清晰度，生动临场感',
      negativeBan: '3D建模，动漫，卡通手绘，过度磨皮平滑，塑料感，畸形手，五官扭曲，低画质，模糊，噪点，水印，文字',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'modern_cinematic_live_action',
      category: '实拍电影质感',
      nameZh: '现代院线电影写实',
      descriptionZh: '院线电影级写实数字人，真实毛孔肤质与35mm专业影视布光',
      positiveAnchor: '真人院线电影写实质感，AI数字人，皮肤毛孔纹理，专业影视布光，自然相机畸变，浅景深，柔和自然光，轻微胶片颗粒，电影构图，16:9横屏，4K，真实环境',
      negativeBan: '卡通，动漫，CG，畸形手，五官错位，油画手绘，水印，文字，过度美颜，塑料皮肤，肢体崩坏',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'vintage_90s_hk_film',
      category: '实拍电影质感',
      nameZh: '90年代港风胶片',
      descriptionZh: '90年代王家卫港风电影胶片，35mm温暖暖黄青暗角复古',
      positiveAnchor: '90年代港风电影，35mm复古胶片质感，暖黄青色调，细微胶片颗粒，暗角，柔光镜头光晕，电影实拍，浅景深，怀旧氛围感，16:9横屏',
      negativeBan: 'CG，动漫，3D，高饱和鲜艳，现代锐化，塑料皮肤，文字，水印，畸形，干净数字画面',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'vintage_80s_american_film',
      category: '实拍电影质感',
      nameZh: '80年代美式复古胶片',
      descriptionZh: '80年代美式复古35mm电影胶片，低饱和颗粒与怀旧畸变',
      positiveAnchor: '80年代美式复古胶片，35mm胶片拍摄，褪色低饱和，厚重胶片颗粒，复古镜头畸变，暖调怀旧，浅景深，电影构图，16:9横屏，文艺氛围感',
      negativeBan: 'CG，卡通动漫，超高锐度，数字光滑皮肤，水印，文字，畸形肢体，鲜艳荧光色',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'period_drama_realism',
      category: '实拍电影质感',
      nameZh: '年代剧写实质感',
      descriptionZh: '历史年代大剧电影写实，低饱和自然光与厚重年代质感',
      positiveAnchor: '年代剧写实质感，实拍电影质感，复古服装，老旧建筑，柔和自然光，低饱和色调，细腻皮肤纹理，影视布光，浅景深，16:9横屏，4K，厚重年代氛围',
      negativeBan: '卡通，CG，动漫，高饱和亮色，塑料皮肤，水印，文字，畸形手部，过度美颜',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'vintage_monochrome_film',
      category: '实拍电影质感',
      nameZh: '黑白电影质感',
      descriptionZh: '经典黑白老胶片电影质感，高对比黑白灰度与胶片颗粒',
      positiveAnchor: '老式黑白电影质感，高对比黑白灰，老胶片颗粒，复古镜头，电影构图，浅景深，柔和明暗过渡，16:9横屏，文艺悲剧氛围感',
      negativeBan: '彩色，CG，动漫卡通，鲜艳色彩，水印，文字，畸形五官，现代锐化，塑料材质',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'felt_claymation_stopmotion',
      category: '手工立体美术',
      nameZh: '羊毛毡/黏土定格动画',
      descriptionZh: '羊毛毡黏土手工定格动画，织物绒毛与温馨指纹微缩模型',
      positiveAnchor: '羊毛毡黏土定格动画，手工黏土模型，织物绒毛纹理，细微手工指纹质感，柔和暖光，轻微定格抖动质感，童话场景，低对比，马卡龙柔和配色，电影构图，16:9横屏，高细节',
      negativeBan: '3D渲染，写实真人，二次元，锐利硬阴影，金属反光，高饱和，文字，水印，光滑表面',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'papercut_pop_up_book',
      category: '手工立体美术',
      nameZh: '纸雕立体绘本',
      descriptionZh: '多层剪纸立体立体绘本，光影层次与马卡龙童话分层',
      positiveAnchor: '纸雕立体插画，多层剪纸，纸片厚度阴影，分层立体空间，柔和马卡龙配色，绘本风格，干净轮廓，柔和漫射光，童话氛围，电影分镜，16:9横屏，高细节',
      negativeBan: '写实CG，厚重油画，强反光金属，脏纹理，文字，水印，畸形肢体，强烈硬阴影',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'gothic_stained_glass',
      category: '手工立体美术',
      nameZh: '玻璃彩绘（哥特彩窗）',
      descriptionZh: '中世纪哥特教堂彩绘玻璃，黑粗勾线与通透琉璃斑斓透光',
      positiveAnchor: '哥特彩色玻璃彩绘，黑粗轮廓线条，通透斑斓彩色色块，彩窗透光质感，中世纪奇幻美学，柔和漫光，装饰绘画，电影分镜，16:9横屏，高细节',
      negativeBan: '写实照片，3D建模，塑料材质，模糊边缘，畸形肢体，水印，文字，厚重油画肌理',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'dark_gothic_oil_painting',
      category: '暗黑悬疑哥特',
      nameZh: '暗黑哥特油画质感',
      descriptionZh: '暗黑哥特古典油画质感，冷调浓郁古堡残月与压抑神秘',
      positiveAnchor: '暗黑哥特油画质感，低饱和度，强烈明暗对比，冷调光影，古堡迷雾，残月，局部血色点缀，油画肌理，电影运镜，景深，16:9横屏，8K，压抑神秘氛围',
      negativeBan: '明亮，高饱和，卡通，暖色调，国风仙侠，鲜艳色彩，文字，水印，畸形手部，光滑塑料',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'rococo_vintage_oil',
      category: '暗黑悬疑哥特',
      nameZh: '洛可可复古油画',
      descriptionZh: '18世纪欧式洛可可古典油画，华美贵族宫廷与精致雕花柔光',
      positiveAnchor: '洛可可复古油画质感，18世纪欧式贵族美学，华丽繁复服饰，柔和柔光，精致欧式雕花，细腻油画笔触，典雅华丽光影，电影构图，16:9横屏，高细节',
      negativeBan: '粗粝废土，赛博朋克，暗黑冷调，卡通，畸形肢体，水印，文字，塑料材质，锐利硬阴影',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'japanese_weird_tale_dark_sketch',
      category: '暗黑悬疑哥特',
      nameZh: '日式怪谈暗调手绘',
      descriptionZh: '日式怪谈聊斋阴冷暗调手绘，冷灰低饱和与留白恐怖氛围',
      positiveAnchor: '日式怪谈暗调手绘，2D手绘，暗沉低饱和，冷灰色调，留白恐怖感，阴冷氛围，日式建筑，电影分镜，柔和暗光，16:9横屏，高细节',
      negativeBan: '明亮高饱和，鲜艳色彩，3D CG，卡通，暖调，水印，文字，畸形手部，塑料反光',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'flat_vector_illustration',
      category: '小众艺术实验',
      nameZh: '扁平矢量插画',
      descriptionZh: '现代简约扁平矢量插画，几何纯色无渐变极简美学',
      positiveAnchor: '扁平矢量插画，2D矢量风格，纯色块，无渐变，干净几何线条，极简美学，现代简约，漫画分镜，16:9横屏，高细节',
      negativeBan: '写实照片，3D渲染，油画笔触，复杂纹理，景深虚化，畸形肢体，水印，文字，厚重阴影',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'retro_16bit_pixel_art',
      category: '小众艺术实验',
      nameZh: '像素风（复古8bit/16bit）',
      descriptionZh: '复古8bit/16bit像素艺术，经典点阵低色域游戏怀旧感',
      positiveAnchor: '复古16bit像素风，像素颗粒画面，复古游戏美学，低色域复古色彩，像素角色与场景，游戏分镜，16:9横屏，怀旧游戏氛围感',
      negativeBan: '高清写实，平滑渲染，3D CG，油画，胶片颗粒，水印，文字，畸形五官，细腻皮肤纹理',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
    AestheticStyle(
      id: 'surrealist_oil_painting',
      category: '小众艺术实验',
      nameZh: '超现实主义油画',
      descriptionZh: '达利式超现实主义梦境油画，扭曲梦幻空间与奇幻意象',
      positiveAnchor: '超现实主义油画，油画手绘质感，扭曲梦幻空间，奇幻物象组合，梦境氛围感，厚重油画肌理，丰富色彩，电影构图，16:9横屏，高细节',
      negativeBan: '写实照片，矢量扁平，3D次世代，硬锐利阴影，畸形崩坏肢体，水印，文字，干净光滑塑料',
      defaultRatio: '16:9',
      isBuiltin: true,
    ),
  ];

}


/// 角色三视图体态比例（spec: series-asset-library 角色三视图体态比例与Q版萌系模式）。
///
/// 解决文生图大模型在无头身比约束时随机漂移为 Q 版的问题，
/// 同时满足类似《师兄啊师兄》中同一角色常态成人比例与纸人/内心戏 Q 版化身并存的双轨需求。
enum CharacterTurnaroundProportion {
  /// 标准全身比例（7~8 头身，默认）：写实人体结构，适用于常规主线与日常分镜。
  standard(
    'standard',
    '标准比例',
    '7~8头身成人比例，修长挺拔，适用于常规主线与日常分镜',
    positiveAnchor:
        '标准7~8头身成人体态比例，身材修长挺拔匀称，写实人体结构，全身从头到脚完整可见',
    negativeBan:
        'Q版，大头娃娃，2头身，3头身，低幼儿童体态，玩偶，手办模型，卡通畸形',
    filename: 'turnaround.png',
  ),

  /// Q 版萌系比例（2.5 头身）：大头圆脸萌态，适用于纸人化身、内心戏吐槽与搞笑轻喜剧。
  chibi(
    'chibi',
    'Q版萌系',
    '2.5头身大头小身，适用于纸人化身、内心戏独白与萌态搞笑分镜',
    positiveAnchor:
        'Q版萌系体态，二头半萌态身型，大圆脸圆脑袋，娇小萌系体型，可爱短手短腿，全身可见',
    negativeBan:
        '写实成人比例，修长身材，8头身，成熟骨骼结构，修长四肢，锋利成熟面容',
    filename: 'turnaround_chibi.png',
  );

  final String id;
  final String labelZh;
  final String descriptionZh;
  final String positiveAnchor;
  final String negativeBan;
  final String filename;

  const CharacterTurnaroundProportion(
    this.id,
    this.labelZh,
    this.descriptionZh, {
    required this.positiveAnchor,
    required this.negativeBan,
    required this.filename,
  });

  static CharacterTurnaroundProportion fromId(String? id) {
    if (id == null || id.trim().isEmpty) return CharacterTurnaroundProportion.standard;
    final normalized = id.trim().toLowerCase();
    for (final p in values) {
      if (p.id.toLowerCase() == normalized) return p;
    }
    return CharacterTurnaroundProportion.standard;
  }
}

/// 剧集主库元数据（`series_profile.json`）。
class StudioSeries {
  final String id;
  final String name;
  final StudioProductionType productionType;

  /// 世界观设定文本（创意孵化确认后写入）。
  final String worldview;

  /// 时代题材视觉锁（如 xianxia、ancient_costume、modern_urban 等）。
  final String eraGenre;

  /// 美学风格预设标识符（如 ue5_3d_xianxia、ink_wash_2d 等）。
  final String styleId;

  /// 全局正向风格词（进入每条生图 Prompt 的"风格锁"）。
  final String styleTokens;

  /// 全局负向风格避雷词（进入每条生图 Prompt 的负向约束）。
  final String negativeStyleTokens;

  /// 默认 TTS 音色（角色未绑定时使用）。
  final String defaultVoiceId;

  /// 默认画幅比例（如 '9:16'、'16:9'、'21:9'、'4:3'、'1:1'）。默认 '9:16'。
  final String defaultAspectRatio;

  /// 默认分辨率档位（如 '2K'、'1K'、'4K'、'720P'、'1080P'）。默认 '2K'。
  final String defaultResolution;

  /// 剧情记忆库。
  final List<EpisodeMemory> memories;

  /// 主要道具列表（IP 级资产，跨集复用）。
  ///
  /// 旧 `series_profile.json` 无此字段，[fromJson] 按空列表加载，无需迁移。
  final List<PropCard> props;

  /// 关联的本地小说 ID（用于剧本工作台章节适配与正文定位）。
  final String? novelId;

  /// 关联的独立 IP 主库 ID（若为空则默认指向自身 id）。
  final String ipId;

  String get resolvedIpId => ipId.isNotEmpty ? ipId : id;

  final DateTime createdAt;
  final DateTime updatedAt;

  const StudioSeries({
    required this.id,
    required this.name,
    this.productionType = StudioProductionType.drama,
    this.worldview = '',
    this.eraGenre = '',
    this.styleId = '',
    this.styleTokens = '',
    this.negativeStyleTokens = '',
    this.defaultVoiceId = '',
    this.defaultAspectRatio = '9:16',
    this.defaultResolution = '2K',
    this.memories = const [],
    this.props = const [],
    this.novelId,
    this.ipId = '',
    required this.createdAt,
    required this.updatedAt,
  });

  StudioSeries copyWith({
    String? id,
    String? name,
    StudioProductionType? productionType,
    String? worldview,
    String? eraGenre,
    String? styleId,
    String? styleTokens,
    String? negativeStyleTokens,
    String? defaultVoiceId,
    String? defaultAspectRatio,
    String? defaultResolution,
    List<EpisodeMemory>? memories,
    List<PropCard>? props,
    String? novelId,
    bool clearNovelId = false,
    String? ipId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudioSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      productionType: productionType ?? this.productionType,
      worldview: worldview ?? this.worldview,
      eraGenre: eraGenre ?? this.eraGenre,
      styleId: styleId ?? this.styleId,
      styleTokens: styleTokens ?? this.styleTokens,
      negativeStyleTokens: negativeStyleTokens ?? this.negativeStyleTokens,
      defaultVoiceId: defaultVoiceId ?? this.defaultVoiceId,
      defaultAspectRatio: defaultAspectRatio ?? this.defaultAspectRatio,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      memories: memories ?? this.memories,
      props: props ?? this.props,
      novelId: clearNovelId ? null : (novelId ?? this.novelId),
      ipId: ipId ?? this.ipId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'production_type': productionType.id,
    'worldview': worldview,
    'era_genre': eraGenre,
    'style_id': styleId,
    'style_tokens': styleTokens,
    'negative_style_tokens': negativeStyleTokens,
    'default_voice_id': defaultVoiceId,
    'default_aspect_ratio': defaultAspectRatio,
    'default_resolution': defaultResolution,
    'memories': memories.map((m) => m.toJson()).toList(),
    'props': props.map((e) => e.toJson()).toList(),
    if (novelId != null && novelId!.isNotEmpty) 'novel_id': novelId,
    if (ipId.isNotEmpty) 'ip_id': ipId,
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
      eraGenre: json['era_genre'] as String? ?? '',
      styleId: json['style_id'] as String? ?? '',
      styleTokens: json['style_tokens'] as String? ?? '',
      negativeStyleTokens: json['negative_style_tokens'] as String? ?? '',
      defaultVoiceId: json['default_voice_id'] as String? ?? '',
      defaultAspectRatio: json['default_aspect_ratio'] as String? ?? '9:16',
      defaultResolution: json['default_resolution'] as String? ?? '2K',
      memories:
          (json['memories'] as List?)
              ?.whereType<Map>()
              .map((e) => EpisodeMemory.fromJson(
                  e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      props:
          (json['props'] as List?)
              ?.whereType<Map>()
              .map((e) => PropCard.fromJson(
                  e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      novelId: json['novel_id'] as String?,
      ipId: json['ip_id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? now,
    );
  }
}

/// 一集（`episodes/<ep-id>/storyboard.json`）。
/// 时间轴上的一个资产片段插入。
///
/// **为什么是 episode 上的叠加列表而不是改分镜顺序**：分镜序列是剧本结构，
/// 时间轴是剪辑决策，两者不是一件事。把资产片段塞进 `shots` 会让"这里插
/// 一段"变成改剧本，用户撤不回来，且分镜号会被打乱。
///
/// 叠加列表只回答「在哪个分镜之后插一段、插哪段」，合成时由 DeliveryPanel
/// 把它展开进视频序列——`shots` 本身不动。
class StudioTimelineInsert {
  /// 资产库里的资产 id。
  final String assetId;

  /// 插在这个镜号之后。0 表示插在最前面。
  final int afterShotNumber;

  const StudioTimelineInsert({
    required this.assetId,
    required this.afterShotNumber,
  });

  Map<String, dynamic> toJson() => {
    'asset_id': assetId,
    'after_shot_number': afterShotNumber,
  };

  static StudioTimelineInsert? fromJson(Map<String, dynamic> json) {
    final assetId = json['asset_id'] as String?;
    if (assetId == null || assetId.isEmpty) return null;
    return StudioTimelineInsert(
      assetId: assetId,
      afterShotNumber: (json['after_shot_number'] as num?)?.toInt() ?? 0,
    );
  }
}

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

  /// 时间轴上的资产片段插入（spec: 视频资产可作为合成时间线素材）。
  ///
  /// 空列表是正常态——旧剧集加载后就是空的，无需迁移。合成时由
  /// DeliveryPanel 展开进视频序列，不改 [shots] 的顺序。
  final List<StudioTimelineInsert> timelineInserts;

  /// 戏剧场次列表（用于指导连续性、场景主光与空间地标）。
  final List<DramaScene> scenes;

  /// 影视文学剧本全文 Markdown/分场剧本文本。
  final String screenplayText;

  /// 剧本事实与对白保护清单（防止 AI 拆镜时丢失核心原著台词与剧情因果）。
  final ProtectedContract protectedContract;

  /// 该集取材的原著小说章节范围（如 "1-3"、"22-25"）。
  final String novelChapterRange;

  /// 该集取材的原著小说章节序号列表（如 [1, 2, 3]）。
  final List<int> novelChapterIndices;

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
    this.timelineInserts = const [],
    this.scenes = const [],
    this.screenplayText = '',
    this.protectedContract = ProtectedContract.empty,
    this.novelChapterRange = '',
    this.novelChapterIndices = const [],
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
    List<StudioTimelineInsert>? timelineInserts,
    List<DramaScene>? scenes,
    String? screenplayText,
    ProtectedContract? protectedContract,
    String? novelChapterRange,
    List<int>? novelChapterIndices,
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
      timelineInserts: timelineInserts ?? this.timelineInserts,
      scenes: scenes ?? this.scenes,
      screenplayText: screenplayText ?? this.screenplayText,
      protectedContract: protectedContract ?? this.protectedContract,
      novelChapterRange: novelChapterRange ?? this.novelChapterRange,
      novelChapterIndices: novelChapterIndices ?? this.novelChapterIndices,
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
    'timeline_inserts': timelineInserts.map((t) => t.toJson()).toList(),
    if (scenes.isNotEmpty) 'scenes': scenes.map((s) => s.toJson()).toList(),
    if (screenplayText.isNotEmpty) 'screenplay_text': screenplayText,
    if (protectedContract.isNotEmpty) 'protected_contract': protectedContract.toJson(),
    if (novelChapterRange.isNotEmpty) 'novel_chapter_range': novelChapterRange,
    if (novelChapterIndices.isNotEmpty) 'novel_chapter_indices': novelChapterIndices,
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
      timelineInserts:
          (json['timeline_inserts'] as List?)
              ?.whereType<Map>()
              .map((e) => StudioTimelineInsert.fromJson(
                  e.map((k, v) => MapEntry(k as String, v))))
              .whereType<StudioTimelineInsert>()
              .toList() ??
          const [],
      scenes: (json['scenes'] as List?)
              ?.whereType<Map>()
              .map((e) => DramaScene.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      screenplayText: json['screenplay_text'] as String? ?? '',
      protectedContract: json['protected_contract'] is Map
          ? ProtectedContract.fromJson(
              (json['protected_contract'] as Map).map((k, v) => MapEntry(k as String, v)))
          : ProtectedContract.empty,
      novelChapterRange: json['novel_chapter_range'] as String? ?? '',
      novelChapterIndices: (json['novel_chapter_indices'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
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
  /// 旧版数据迁移：没有 `segments` 时优先根据戏剧场次归组，无场次时按分镜顺序每 2–3 镜归组。
  StudioEpisode migrateSegmentsIfNeeded() {
    if (segments.isNotEmpty || shots.isEmpty) return this;
    if (scenes.isNotEmpty) {
      return copyWith(
        segments: buildSegmentsFromScenes(scenes, shots),
      );
    }
    return copyWith(
      segments: buildLegacySegments(shots.map((s) => s.number).toList()),
    );
  }

  /// 清空本集全部镜头与大段。
  StudioEpisode clearShots() {
    return copyWith(
      shots: const [],
      segments: const [],
      updatedAt: DateTime.now(),
    );
  }

  /// 删除指定镜号的分镜，并重新维护连续镜号 (1..N) 与大段时长。
  StudioEpisode deleteShot(int shotNumber) {
    if (!shots.any((s) => s.number == shotNumber)) return this;
    final remainingShots = <StudioShot>[];
    int newNum = 1;
    for (final s in shots) {
      if (s.number == shotNumber) continue;
      remainingShots.add(s.copyWith(number: newNum++));
    }
    final updatedSegments = buildSegmentsFromScenes(scenes, remainingShots);
    final syncedShots = <StudioShot>[];
    for (final s in remainingShots) {
      final seg = updatedSegments.where((g) => g.shotNumbers.contains(s.number)).firstOrNull;
      syncedShots.add(seg != null ? s.copyWith(segmentId: seg.id) : s);
    }
    return copyWith(
      shots: syncedShots,
      segments: updatedSegments,
      updatedAt: DateTime.now(),
    );
  }

  /// 在指定分镜后插入一个新分镜，自动继承前镜场景与主光，并重新维护连续镜号与大段。
  StudioEpisode insertShotAfter(int shotNumber, {DramaScene? scene}) {
    final idx = shots.indexWhere((s) => s.number == shotNumber);
    final prevShot = idx >= 0 ? shots[idx] : (shots.isNotEmpty ? shots.last : null);

    final resolvedSceneId = (scene != null && scene.sceneCardId.isNotEmpty)
        ? scene.sceneCardId
        : (prevShot?.sceneId ?? '');
    final newShot = StudioShot(
      number: idx >= 0 ? shotNumber + 1 : (shots.length + 1),
      durationSec: 4.0,
      shotSize: StudioShotSize.medium,
      mood: prevShot?.mood ?? 'warm',
      function: ShotFunction.advance,
      actionZh: '',
      dialogue: '',
      characterIds: prevShot?.characterIds ?? const [],
      characterVariations: prevShot?.characterVariations ?? const {},
      sceneId: resolvedSceneId,
      beatId: prevShot?.beatId ?? '',
      segmentId: prevShot?.segmentId ?? '',
      cameraMove: 'static',
      directorDecisions: prevShot?.directorDecisions ?? DirectorDecisions.empty,
      continuity: prevShot?.continuity ?? ShotContinuity.empty,
    );

    final updatedShots = <StudioShot>[];
    if (idx < 0) {
      updatedShots.addAll(shots);
      updatedShots.add(newShot);
    } else {
      updatedShots.addAll(shots.sublist(0, idx + 1));
      updatedShots.add(newShot);
      updatedShots.addAll(shots.sublist(idx + 1));
    }

    for (int i = 0; i < updatedShots.length; i++) {
      updatedShots[i] = updatedShots[i].copyWith(number: i + 1);
    }

    final updatedSegments = buildSegmentsFromScenes(scenes, updatedShots);
    final syncedShots = <StudioShot>[];
    for (final s in updatedShots) {
      final seg = updatedSegments.where((g) => g.shotNumbers.contains(s.number)).firstOrNull;
      syncedShots.add(seg != null ? s.copyWith(segmentId: seg.id) : s);
    }

    return copyWith(
      shots: syncedShots,
      segments: updatedSegments,
      updatedAt: DateTime.now(),
    );
  }

  /// 根据戏剧场次（DramaScene）与分镜列表 1:1 构建片段（大段）。
  ///
  /// 每个场次对应一个片段（大段），目标时长严格为该场次内所有分镜建议时长之和，
  /// 彻底取消人造的 12 秒上限。当没有场次时，安全回退到 [buildLegacySegments]。
  static List<StudioSegment> buildSegmentsFromScenes(
    List<DramaScene> scenes,
    List<StudioShot> shots,
  ) {
    if (shots.isEmpty) return const [];
    if (scenes.isEmpty) {
      return buildLegacySegments(shots.map((s) => s.number).toList());
    }

    final segments = <StudioSegment>[];
    final claimedShotNumbers = <int>{};

    for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
      final scene = scenes[sceneIdx];
      final segId = 'seg-${sceneIdx + 1}';
      final sceneScId = 'SC${(sceneIdx + 1).toString().padLeft(3, '0')}';
      final sceneNumScId = scene.sceneNumber > 0
          ? 'SC${scene.sceneNumber.toString().padLeft(3, '0')}'
          : sceneScId;

      final sceneShots = shots.where((s) {
        if (claimedShotNumbers.contains(s.number)) return false;

        // 1. 若 shot 已明确指定 segmentId，优先严格按 segmentId 匹配
        if (s.segmentId.isNotEmpty) {
          return s.segmentId == segId;
        }

        // 2. 若未指定 segmentId，按 sceneId / sceneCardId / 场次编号匹配
        if (s.sceneId.isNotEmpty &&
            (s.sceneId == scene.id ||
                (scene.sceneCardId.isNotEmpty && s.sceneId == scene.sceneCardId) ||
                s.sceneId == sceneScId ||
                s.sceneId == sceneNumScId)) {
          return true;
        }

        return false;
      }).toList();

      if (sceneShots.isNotEmpty) {
        claimedShotNumbers.addAll(sceneShots.map((s) => s.number));

        final totalDuration = sceneShots.fold<double>(
          0.0,
          (sum, s) => sum + s.durationSec,
        ).round();

        final locDesc = scene.location.isNotEmpty ? ' (${scene.location})' : '';
        final reason =
            '场次 ${scene.sceneNumber > 0 ? scene.sceneNumber : (sceneIdx + 1)}: ${scene.title}$locDesc';

        segments.add(StudioSegment(
          id: segId,
          shotNumbers: sceneShots.map((s) => s.number).toList(),
          boundaryReason: reason,
          targetDurationSec: totalDuration > 0 ? totalDuration : sceneShots.length * 4,
        ));
      }
    }

    final coveredShotNumbers = segments.expand((s) => s.shotNumbers).toSet();
    final uncovered = shots.where((s) => !coveredShotNumbers.contains(s.number)).toList();

    if (segments.isEmpty && uncovered.isNotEmpty) {
      if (scenes.isNotEmpty) {
        final shotsPerScene = (uncovered.length / scenes.length).ceil();
        var cursor = 0;
        for (int i = 0; i < scenes.length && cursor < uncovered.length; i++) {
          final scene = scenes[i];
          final end = (cursor + shotsPerScene).clamp(0, uncovered.length);
          final group = uncovered.sublist(cursor, end);
          if (group.isNotEmpty) {
            final dur = group.fold<double>(0.0, (sum, s) => sum + s.durationSec).round();
            segments.add(StudioSegment(
              id: 'seg-${i + 1}',
              shotNumbers: group.map((s) => s.number).toList(),
              boundaryReason:
                  '场次 ${scene.sceneNumber > 0 ? scene.sceneNumber : (i + 1)}: ${scene.title}',
              targetDurationSec: dur > 0 ? dur : group.length * 4,
            ));
          }
          cursor = end;
        }
      } else {
        return buildLegacySegments(shots.map((s) => s.number).toList());
      }
    } else if (uncovered.isNotEmpty && segments.isNotEmpty) {
      final lastSeg = segments.last;
      final mergedShotNumbers = [...lastSeg.shotNumbers, ...uncovered.map((s) => s.number)];
      final addDur = uncovered.fold<double>(0.0, (sum, s) => sum + s.durationSec).round();
      segments[segments.length - 1] = lastSeg.copyWith(
        shotNumbers: mergedShotNumbers,
        targetDurationSec: lastSeg.targetDurationSec + addDur,
      );
    }

    return segments;
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

/// 分镜视频首帧的来源（spec: 分镜首帧来源的可信判据）。
///
/// 区分「本镜关键帧」与「接力自上一镜尾帧」是必要的：后者意味着本镜没有
/// 用自己的首帧，事后审计、重导与时间轴对齐读到的文件不属于本镜。
enum FirstFrameSource {
  /// 本镜自己生成的关键帧。默认值——旧数据没有这个字段，视为本镜关键帧。
  keyframe('keyframe', '本镜关键帧'),

  /// 接力自上一镜视频尾帧。
  relay('relay', '上一镜尾帧接力'),

  /// 未使用首帧（纯文本 / 纯参考图模式）。
  none('none', '无首帧');

  final String id;
  final String label;

  const FirstFrameSource(this.id, this.label);

  static FirstFrameSource fromId(String? value) {
    return values.firstWhere((s) => s.id == value, orElse: () => keyframe);
  }
}

/// 视频生成模式（直通 Agnes API mode）。
enum AgnesVideoMode {
  auto('auto', '自动适配'),
  keyframe('keyframe', '首尾关键帧'),
  reference('reference', '多图参考'),
  text('text', '纯文本驱动');

  const AgnesVideoMode(this.id, this.label);
  final String id;
  final String label;

  static AgnesVideoMode fromId(String? id) {
    if (id == null || id.trim().isEmpty) return AgnesVideoMode.auto;
    final normalized = id.trim().toLowerCase();
    return AgnesVideoMode.values.firstWhere(
      (m) => m.id == normalized,
      orElse: () => AgnesVideoMode.auto,
    );
  }

  static AgnesVideoMode fromKey(String? key) => fromId(key);
}

/// 出场资产在一镜内的叙事分工（spec: shot-asset-binding）。
///
/// 分工不只是标签——它是空间关系编译的输入：含 `confrontation` 的角色对会被
/// 编译成相互注视，而不是各写一个「视线朝左/朝右」的孤立向量。
enum ShotAssetRole {
  /// 主体：画面的视觉焦点，动作的发起者。
  subject('subject', '主体'),

  /// 对峙：与主体相对而立，视线互指。
  confrontation('confrontation', '对峙'),

  /// 配角：同框但不参与对峙。
  supporting('supporting', '配角');

  final String id;
  final String label;

  const ShotAssetRole(this.id, this.label);

  static ShotAssetRole fromId(String? value) {
    if (value == null) return subject;
    final normalized = value.trim().toLowerCase();
    return values.firstWhere(
      (e) => e.id == normalized,
      orElse: () => subject,
    );
  }
}

/// 分镜对一个出场资产的素材绑定（spec: shot-asset-binding）。
///
/// [materialPath] 为空串表示「用系统默认素材」——此时由程序按资产自身的既定
/// 优先级选取，并在 UI 上展示实际选了哪一张，用户可覆盖。一旦用户改过，这里
/// 就是确定值，程序不再猜。
///
/// key 用资产 id（角色卡 id 或场景卡 id）而不是名称：名称可能互相包含
/// （「老王」vs「老王头」），id 不会。
class ShotAssetBinding {
  final String _materialPath;
  final List<String> _materialPaths;

  /// 该资产使用的首张素材文件（向前兼容 getter）。
  String get materialPath {
    if (_materialPaths.isNotEmpty) return _materialPaths.first;
    return _materialPath;
  }

  /// 该资产使用的全部素材文件列表。
  List<String> get materialPaths {
    if (_materialPaths.isNotEmpty) return _materialPaths;
    if (_materialPath.trim().isNotEmpty) return [_materialPath.trim()];
    return const [];
  }

  /// 该资产在本镜的叙事分工。场景无分工语义，固定为 [ShotAssetRole.subject]。
  final ShotAssetRole role;

  const ShotAssetBinding({
    String materialPath = '',
    List<String> materialPaths = const [],
    this.role = ShotAssetRole.subject,
  })  : _materialPath = materialPath,
        _materialPaths = materialPaths;

  /// 是否显式指定了素材文件。
  bool get hasExplicitMaterial =>
      _materialPaths.isNotEmpty || _materialPath.trim().isNotEmpty;

  ShotAssetBinding copyWith({
    String? materialPath,
    List<String>? materialPaths,
    ShotAssetRole? role,
  }) {
    return ShotAssetBinding(
      materialPath: materialPath ?? (materialPaths == null ? _materialPath : ''),
      materialPaths: materialPaths ?? _materialPaths,
      role: role ?? this.role,
    );
  }

  Map<String, dynamic> toJson() => {
    'material_path': materialPath,
    'material_paths': materialPaths,
    'role': role.id,
  };

  static ShotAssetBinding fromJson(Map<String, dynamic> json) {
    final list = (json['material_paths'] as List?)?.cast<String>();
    final single = json['material_path'] as String?;
    final paths = list != null
        ? list.where((p) => p.trim().isNotEmpty).toList()
        : (single != null && single.trim().isNotEmpty ? [single.trim()] : const <String>[]);
    return ShotAssetBinding(
      materialPath: single ?? '',
      materialPaths: paths,
      role: ShotAssetRole.fromId(json['role'] as String?),
    );
  }
}

/// 单个分镜（`storyboard.json` 的 shots 数组元素）。
enum StudioClipStatus {
  none('none', '未生成'),
  valid('valid', '有效'),
  stale('stale', '需重构');

  final String id;
  final String label;
  const StudioClipStatus(this.id, this.label);

  static StudioClipStatus fromId(String? id) {
    if (id == null) return StudioClipStatus.none;
    return StudioClipStatus.values.firstWhere(
      (e) => e.id == id,
      orElse: () => StudioClipStatus.none,
    );
  }
}

/// VLM 关键帧实拍场记自动审图报告（spec: VLM Keyframe Visual Critic）。
@immutable
class VlmFrameCriticReport {
  /// 综合审图评分（0-100）。
  final int score;

  /// 是否通过实拍场记验收。
  final bool passed;

  /// 画面人数是否与剧本设定一致。
  final bool characterCountOk;

  /// 是否无克隆双胞胎/重影伪影。
  final bool noCloneArtifact;

  /// 空间高低落差与透视关系是否合理（无悬空平地并立）。
  final bool spatialElevationOk;

  /// 坐骑与核心手持道具是否存续且姿态正确。
  final bool mountPropOk;

  /// 实际成图景别是否匹配分镜设定。
  final bool shotScaleOk;

  /// 检出的具体问题列表。
  final List<String> issues;

  /// 针对生图提示词的修正补充建议。
  final String promptFixSuggestion;

  /// 验收时间戳（ISO-8601）。
  final String evaluatedAt;

  /// 是否经过真实 AI 多模态视觉模型审查（false 表示仅经过本地确定性规则预审）。
  final bool isAiEvaluated;

  const VlmFrameCriticReport({
    required this.score,
    required this.passed,
    this.characterCountOk = true,
    this.noCloneArtifact = true,
    this.spatialElevationOk = true,
    this.mountPropOk = true,
    this.shotScaleOk = true,
    this.issues = const [],
    this.promptFixSuggestion = '',
    this.evaluatedAt = '',
    this.isAiEvaluated = false,
  });

  Map<String, dynamic> toJson() => {
    'score': score,
    'passed': passed,
    'character_count_ok': characterCountOk,
    'no_clone_artifact': noCloneArtifact,
    'spatial_elevation_ok': spatialElevationOk,
    'mount_prop_ok': mountPropOk,
    'shot_scale_ok': shotScaleOk,
    'issues': issues,
    if (promptFixSuggestion.isNotEmpty)
      'prompt_fix_suggestion': promptFixSuggestion,
    if (evaluatedAt.isNotEmpty) 'evaluated_at': evaluatedAt,
    'is_ai_evaluated': isAiEvaluated,
  };

  static VlmFrameCriticReport fromJson(Map<String, dynamic> json) {
    final score = (json['score'] as num?)?.toInt() ?? 80;
    final issues =
        (json['issues'] as List?)?.map((e) => e.toString()).toList() ??
        const [];
    return VlmFrameCriticReport(
      score: score.clamp(0, 100),
      passed: json['passed'] as bool? ?? (score >= 70 && issues.isEmpty),
      characterCountOk: json['character_count_ok'] as bool? ?? true,
      noCloneArtifact: json['no_clone_artifact'] as bool? ?? true,
      spatialElevationOk: json['spatial_elevation_ok'] as bool? ?? true,
      mountPropOk: json['mount_prop_ok'] as bool? ?? true,
      shotScaleOk: json['shot_scale_ok'] as bool? ?? true,
      issues: issues,
      promptFixSuggestion: json['prompt_fix_suggestion'] as String? ?? '',
      evaluatedAt: json['evaluated_at'] as String? ?? '',
      isAiEvaluated: json['is_ai_evaluated'] as bool? ?? false,
    );
  }
}

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

  /// 发声类型（对白 `dialogue` / 内心独白 `inner_voice` / 旁白 `narration`）。
  final UtteranceVoiceType voiceType;

  /// 出场角色卡 id 列表。
  final List<String> characterIds;

  /// 出场道具卡 id 列表。
  final List<String> propIds;

  /// 出场角色在当前镜头的具体形态映射（key: characterId, value: variationId）。
  ///
  /// 若未指定（空 Map 或无对应角色 key），出图时回退至单集覆盖或角色默认形态。
  final Map<String, String> characterVariations;

  /// 出场资产的素材绑定（key: 角色卡 id 或场景卡 id；spec: shot-asset-binding）。
  ///
  /// 这是素材指代编号（`<Picture N>`）的唯一来源：编号 = 该绑定在有序列表中的
  /// 下标 + 1，提示词编译与提交给生成模型的参考媒体数组从同一列表产出。
  /// 空 Map 表示尚未声明——读取时按「无绑定」处理，不猜、不迁移。
  final Map<String, ShotAssetBinding> assetBindings;

  /// 场景卡 id。
  final String sceneId;

  /// 运镜方案关键词（如 "low angle push-in"），由用户选择后写入。
  final String cameraMove;

  /// 最终组装好的英文生图 Prompt（系统维护，字段级缓存）。
  final String assembledPrompt;

  /// 已生成关键帧文件名（相对 `frames/`）。
  final String? framePath;

  /// 本镜生成视频使用的首帧图片路径（接力自前镜末帧或自定义首帧）。
  final String? firstFramePath;

  /// [firstFramePath] 指向的文件是本镜关键帧还是上一镜尾帧接力
  /// （spec: 分镜首帧来源的可信判据）。
  ///
  /// 缺失时视为 [FirstFrameSource.keyframe]——旧数据里这个路径通常就是本镜
  /// 关键帧，且那是唯一安全的默认（不假设发生过接力）。
  final FirstFrameSource firstFrameSource;

  /// 本镜已生成视频抽取的尾帧图片路径（供下一镜接力使用）。
  final String? lastFramePath;

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

  /// 所属节拍 id。空串表示尚未归入具体节拍。
  final String beatId;

  /// 五维导演决策矩阵（物理动势、空间光影、光学机位、时间演变、美学质感与切镜动机）。
  final DirectorDecisions directorDecisions;

  /// 本镜承载的动作攻防步（若本镜为打斗/动作镜头）。
  final List<CombatStep> combatSteps;

  /// 连续性台账（spec: 连续性台账字段）。
  ///
  /// 旧版数据为 [ShotContinuity.empty]；UI 靠 [ShotContinuity.isEmpty] 提示
  /// 用户补台账，而不是把空值当成真实的「空手」状态。
  final ShotContinuity continuity;

  final ShotGenerationStatus status;

  /// 视频生成模式（'auto', 'keyframe', 'reference', 'text'）。默认 'auto'。
  final String videoMode;

  /// AI 消解冲突或用户定制的视频生成专用提示词（为空时使用动态组装的 buildVideoGenPrompt）。
  final String videoPrompt;

  /// 写入 [videoPrompt] 时，决定该提示词的五个字段的快照
  /// （spec: 分镜字段变更作废缓存的视频提示词）。
  ///
  /// 定制提示词是**一次性快照**：用户存下它之后若又改了动作、台词、出场角色、
  /// 场景或素材绑定，那份快照就不再反映最新字段——而 `buildVideoGenPrompt`
  /// 开头会原样返回它，于是新绑定的 `<Picture N>` 与最新因果时间轴永远进不去
  /// 最终的生成请求。
  ///
  /// 生成前比对当前键与记录键，不一致即视为失效，走动态组装（不删除字段本身，
  /// 用户改回字段或手动重存都能恢复）。为空串表示从未记录——旧数据与从未定制
  /// 过的分镜都是这个值，此时任何非空 videoPrompt 都先按失效处理。
  final String videoPromptSourceKey;

  /// 本镜独立画幅比例覆盖（为空时继承剧集默认值）。
  final String? aspectRatio;

  /// 本镜独立分辨率档位覆盖（为空时继承剧集默认值）。
  final String? resolution;

  /// 视频片段有效性状态（none: 未生成, valid: 有效, stale: 关键帧更新后失效需重构）。
  final StudioClipStatus clipStatus;

  /// 最近一次 1 选 4 候选抽卡生成的缩略图文件名列表（相对 `frames/`）。
  final List<String> candidateFramePaths;

  /// 人脸参考图白名单（若指定，向生成 API 仅提交该列表内的角色参考图，其余角色降级为背景文本）。
  final List<String>? activeFaceCharacterIds;

  /// VLM 关键帧实拍场记自动审图报告。
  final VlmFrameCriticReport? vlmCriticReport;

  const StudioShot({
    required this.number,
    this.durationSec = 3,
    this.shotSize = StudioShotSize.medium,
    this.mood = 'warm',
    this.function = ShotFunction.advance,
    this.actionZh = '',
    this.dialogue = '',
    this.voiceType = UtteranceVoiceType.dialogue,
    this.characterIds = const [],
    this.propIds = const [],
    this.characterVariations = const {},
    this.assetBindings = const {},
    this.sceneId = '',
    this.beatId = '',
    this.cameraMove = '',
    this.assembledPrompt = '',
    this.framePath,
    this.firstFramePath,
    this.firstFrameSource = FirstFrameSource.keyframe,
    this.lastFramePath,
    this.clipPath,
    this.audioPath,
    this.audioDurationMs,
    this.bgmPath,
    this.segmentId = '',
    this.directorDecisions = DirectorDecisions.empty,
    this.combatSteps = const [],
    this.continuity = ShotContinuity.empty,
    this.status = ShotGenerationStatus.pending,
    this.videoMode = 'auto',
    this.videoPrompt = '',
    this.videoPromptSourceKey = '',
    this.aspectRatio,
    this.resolution,
    this.clipStatus = StudioClipStatus.none,
    this.candidateFramePaths = const [],
    this.activeFaceCharacterIds,
    this.vlmCriticReport,
  });

  /// 视频是否因关键帧重新生成等原因已失效需重构。
  bool get isClipStale => clipStatus == StudioClipStatus.stale;

  /// 是否为角色内心独白（心声/内心 OS）。
  bool get isInnerVoice =>
      voiceType == UtteranceVoiceType.innerVoice ||
      dialogue.contains('内心 OS') ||
      dialogue.contains('内心OS') ||
      dialogue.contains('（OS）') ||
      dialogue.contains('(OS)') ||
      dialogue.contains('心声') ||
      dialogue.contains('内心独白');

  /// 决定视频提示词内容的五个字段的稳定快照（spec: 分镜字段变更作废缓存的视频提示词）。
  ///
  /// 只收这五个：它们的变化会改变提示词的实质内容。时长/画幅/分辨率/情绪等
  /// 字段不在内——用户调个时长不该丢掉定制的视频提示词。
  ///
  /// Map 类字段按 key 排序后序列化，否则 Dart Map 的遍历顺序会让同一次比对
  /// 因插入次序不同而误判失效。
  String get videoPromptSourceKeyOf {
    final ids = [...characterIds]..sort();
    final props = [...propIds]..sort();
    final bindings = assetBindings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final bindingDesc = bindings
        .map((e) => '${e.key}:${e.value.materialPaths.join(';')}:${e.value.role.id}')
        .join(',');
    return [
      'a=$actionZh',
      'd=$dialogue',
      'c=${ids.join(',')}',
      'p=${props.join(',')}',
      's=$sceneId',
      'b=$bindingDesc',
    ].join('|');
  }

  /// 已缓存的定制视频提示词是否仍然有效（spec: 分镜字段变更作废缓存的视频提示词）。
  ///
  /// 空 videoPrompt 视为无需缓存；空 sourceKey 视为从未记录——旧数据与从未
  /// 定制过的分镜都是这个值，此时任何非空 videoPrompt 都先按失效处理，让它
  /// 至少按当前字段重新校验一次。
  bool get isVideoPromptStale =>
      videoPrompt.trim().isNotEmpty &&
      (videoPromptSourceKey.isEmpty ||
          videoPromptSourceKey != videoPromptSourceKeyOf);

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

  /// 机位垂直俯仰视角（high_angle 俯拍、low_angle 仰拍、eye_level 平视）。
  String get cameraAngle =>
      continuity.cameraAngle.isNotEmpty ? continuity.cameraAngle : directorDecisions.cameraAngle;

  /// 视线朝向向量描述。
  String get gazeDirection =>
      continuity.gazeDirection.isNotEmpty ? continuity.gazeDirection : directorDecisions.gazeDirection;

  /// 空间垂直高度层级（如 ground, balcony_2f, rooftop, mid_air 等）。
  String get elevationLevel => continuity.elevationLevel;

  /// 视线目标对象或地标描述。
  String get gazeTarget => continuity.gazeTarget;

  /// 解析本镜实际生效的视频生成模式。
  ///
  /// - 若显式指定了非 auto 模式（`keyframe`、`reference`、`text`），直接使用指定模式；
  /// - 若为 `auto`：
  ///   - 若已有首帧/关键帧（`firstFramePath`、`framePath` 或调用方传入 `hasKeyframe`），推荐首尾帧模式；
  ///   - 否则若有出场角色或场景（调用方传入 `hasCharacterOrSceneRef` 或 `characterIds.isNotEmpty || sceneId.isNotEmpty`），推荐参考图模式；
  ///   - 否则回退为纯文本模式。
  AgnesVideoMode resolveEffectiveVideoMode({
    bool hasKeyframe = false,
    bool hasCharacterOrSceneRef = false,
  }) {
    if (videoMode.isNotEmpty && videoMode != 'auto') {
      return AgnesVideoMode.fromId(videoMode);
    }
    final keyframeAvailable = hasKeyframe ||
        (firstFramePath != null && firstFramePath!.trim().isNotEmpty) ||
        (framePath != null && framePath!.trim().isNotEmpty);
    if (keyframeAvailable) {
      return AgnesVideoMode.keyframe;
    }
    final refAvailable = hasCharacterOrSceneRef ||
        characterIds.isNotEmpty ||
        propIds.isNotEmpty ||
        sceneId.trim().isNotEmpty;
    if (refAvailable) {
      return AgnesVideoMode.reference;
    }
    return AgnesVideoMode.text;
  }

  StudioShot copyWith({
    int? number,
    double? durationSec,
    StudioShotSize? shotSize,
    String? mood,
    ShotFunction? function,
    String? actionZh,
    String? dialogue,
    UtteranceVoiceType? voiceType,
    List<String>? characterIds,
    List<String>? propIds,
    Map<String, String>? characterVariations,
Map<String, ShotAssetBinding>? assetBindings,
    String? sceneId,
    String? beatId,
    String? cameraMove,
    String? assembledPrompt,
    String? framePath,
    String? firstFramePath,
    FirstFrameSource? firstFrameSource,
    String? lastFramePath,
    String? clipPath,
    String? audioPath,
    int? audioDurationMs,
    String? bgmPath,
    String? segmentId,
    DirectorDecisions? directorDecisions,
    List<CombatStep>? combatSteps,
    ShotContinuity? continuity,
    ShotGenerationStatus? status,
    String? videoMode,
    String? videoPrompt,
    String? videoPromptSourceKey,
    String? aspectRatio,
    String? resolution,
    StudioClipStatus? clipStatus,
    List<String>? candidateFramePaths,
    List<String>? activeFaceCharacterIds,
    VlmFrameCriticReport? vlmCriticReport,
    bool clearVlmCriticReport = false,
  }) {
    return StudioShot(
      number: number ?? this.number,
      durationSec: durationSec ?? this.durationSec,
      shotSize: shotSize ?? this.shotSize,
      mood: mood ?? this.mood,
      function: function ?? this.function,
      actionZh: actionZh ?? this.actionZh,
      dialogue: dialogue ?? this.dialogue,
      voiceType: voiceType ?? this.voiceType,
      characterIds: characterIds ?? this.characterIds,
      propIds: propIds ?? this.propIds,
      characterVariations: characterVariations ?? this.characterVariations,
      assetBindings: assetBindings ?? this.assetBindings,
      sceneId: sceneId ?? this.sceneId,
      beatId: beatId ?? this.beatId,
      cameraMove: cameraMove ?? this.cameraMove,
      assembledPrompt: assembledPrompt ?? this.assembledPrompt,
      framePath: framePath ?? this.framePath,
      firstFramePath: firstFramePath ?? this.firstFramePath,
      firstFrameSource: firstFrameSource ?? this.firstFrameSource,
      lastFramePath: lastFramePath ?? this.lastFramePath,
      clipPath: clipPath ?? this.clipPath,
      audioPath: audioPath ?? this.audioPath,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
      bgmPath: bgmPath ?? this.bgmPath,
      segmentId: segmentId ?? this.segmentId,
      directorDecisions: directorDecisions ?? this.directorDecisions,
      combatSteps: combatSteps ?? this.combatSteps,
      continuity: continuity ?? this.continuity,
      status: status ?? this.status,
      videoMode: videoMode ?? this.videoMode,
      videoPrompt: videoPrompt ?? this.videoPrompt,
      videoPromptSourceKey:
          videoPromptSourceKey ?? this.videoPromptSourceKey,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      resolution: resolution ?? this.resolution,
      clipStatus: clipStatus ?? this.clipStatus,
      candidateFramePaths: candidateFramePaths ?? this.candidateFramePaths,
      activeFaceCharacterIds:
          activeFaceCharacterIds ?? this.activeFaceCharacterIds,
      vlmCriticReport: clearVlmCriticReport
          ? null
          : (vlmCriticReport ?? this.vlmCriticReport),
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
    if (voiceType != UtteranceVoiceType.dialogue) 'voice_type': voiceType.id,
    'character_ids': characterIds,
    'prop_ids': propIds,
    'character_variations': characterVariations,
    // 空绑定不写盘：让 JSON 保持干净，也让「未声明」与「声明了但全默认」
    // 在磁盘上可区分。
    if (assetBindings.isNotEmpty)
      'asset_bindings': assetBindings.map((k, v) => MapEntry(k, v.toJson())),
    'scene_id': sceneId,
    if (beatId.isNotEmpty) 'beat_id': beatId,
    'camera_move': cameraMove,
    'assembled_prompt': assembledPrompt,
    'frame_path': framePath,
    if (firstFramePath != null) 'first_frame_path': firstFramePath,
    'first_frame_source': firstFrameSource.id,
    if (lastFramePath != null) 'last_frame_path': lastFramePath,
    'clip_path': clipPath,
    'audio_path': audioPath,
    'audio_duration_ms': audioDurationMs,
    'bgm_path': bgmPath,
    'segment_id': segmentId,
    if (directorDecisions.isNotEmpty) 'director_decisions': directorDecisions.toJson(),
    if (combatSteps.isNotEmpty)
      'combat_steps': combatSteps.map((s) => s.toJson()).toList(),
    'continuity': continuity.toJson(),
    'status': status.id,
    'video_mode': videoMode,
    if (videoPrompt.isNotEmpty) 'video_prompt': videoPrompt,
    if (videoPromptSourceKey.isNotEmpty)
      'video_prompt_source_key': videoPromptSourceKey,
    if (aspectRatio != null && aspectRatio!.isNotEmpty) 'aspect_ratio': aspectRatio,
    if (resolution != null && resolution!.isNotEmpty) 'resolution': resolution,
    if (clipStatus != StudioClipStatus.none) 'clip_status': clipStatus.id,
    if (candidateFramePaths.isNotEmpty) 'candidate_frame_paths': candidateFramePaths,
    if (activeFaceCharacterIds != null && activeFaceCharacterIds!.isNotEmpty)
      'active_face_character_ids': activeFaceCharacterIds,
    if (vlmCriticReport != null)
      'vlm_critic_report': vlmCriticReport!.toJson(),
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
      voiceType: UtteranceVoiceType.fromId(
        (json['voice_type'] ?? json['voiceType']) as String?,
      ),
      characterIds:
          (json['character_ids'] as List?)?.cast<String>() ?? const [],
      propIds: (json['prop_ids'] as List?)?.cast<String>() ?? const [],
      characterVariations: (json['character_variations'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v as String),
          ) ??
          const {},
      // 旧 JSON 没有这个字段 → 空绑定。刻意不做自动推导：那会把「程序猜」这条
      // 我们正要消除的行为固化下来（spec: 不做旧数据迁移）。
      assetBindings: (json['asset_bindings'] as Map?)?.map(
            (k, v) => MapEntry(
              k as String,
              v is Map
                  ? ShotAssetBinding.fromJson(v.map((k2, v2) => MapEntry(k2 as String, v2)))
                  : const ShotAssetBinding(),
            ),
          ) ??
          const {},
      sceneId: json['scene_id'] as String? ?? '',
      beatId: json['beat_id'] as String? ?? '',
      cameraMove: json['camera_move'] as String? ?? '',
      assembledPrompt: json['assembled_prompt'] as String? ?? '',
      framePath: json['frame_path'] as String?,
      firstFramePath: json['first_frame_path'] as String?,
      firstFrameSource: FirstFrameSource.fromId(
        json['first_frame_source'] as String?,
      ),
      lastFramePath: json['last_frame_path'] as String?,
      clipPath: json['clip_path'] as String?,
      audioPath: json['audio_path'] as String?,
      audioDurationMs: (json['audio_duration_ms'] as num?)?.toInt(),
      bgmPath: json['bgm_path'] as String?,
      segmentId: json['segment_id'] as String? ?? '',
      directorDecisions: json['director_decisions'] is Map
          ? DirectorDecisions.fromJson(
              (json['director_decisions'] as Map).map((k, v) => MapEntry(k as String, v)))
          : DirectorDecisions.empty,
      combatSteps: (json['combat_steps'] as List?)
              ?.whereType<Map>()
              .map((e) => CombatStep.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      continuity: continuityRaw is Map
          ? ShotContinuity.fromJson(
              continuityRaw.map((k, v) => MapEntry(k as String, v)))
          : ShotContinuity.empty,
      status: ShotGenerationStatus.fromId(json['status'] as String?),
      videoMode: json['video_mode'] as String? ?? 'auto',
      videoPrompt: json['video_prompt'] as String? ?? '',
      videoPromptSourceKey: json['video_prompt_source_key'] as String? ?? '',
      aspectRatio: json['aspect_ratio'] as String?,
      resolution: json['resolution'] as String?,
      clipStatus: json['clip_status'] != null
          ? StudioClipStatus.fromId(json['clip_status'] as String?)
          : ((json['clip_path'] as String?)?.isNotEmpty == true
              ? StudioClipStatus.valid
              : StudioClipStatus.none),
      candidateFramePaths:
          (json['candidate_frame_paths'] as List?)?.cast<String>() ??
          const [],
      activeFaceCharacterIds:
          (json['active_face_character_ids'] as List?)?.cast<String>(),
      vlmCriticReport: json['vlm_critic_report'] is Map
          ? VlmFrameCriticReport.fromJson(
              (json['vlm_critic_report'] as Map).map(
                (k, v) => MapEntry(k as String, v),
              ),
            )
          : null,
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

  /// 视线朝向（例如：朝左上、朝右下、直视对手、仰望三楼）。
  final String gazeDirection;

  /// 机位处于动作轴线侧（例如：A侧、B侧，遵循180度轴线法则）。
  final String cameraAxis;

  /// 机位垂直俯仰角（如 high_angle 俯拍、low_angle 仰拍、eye_level 平视）。
  final String cameraAngle;

  /// 空间垂直高度层级（如 ground, balcony_2f, rooftop, mid_air 等）。
  final String elevationLevel;

  /// 视线目标对象或地标描述（如 Jiang Qiye on street below）。
  final String gazeTarget;

  /// 坐骑或载具伴随状态（例如：大黑驴、白马、马车，空串表示无坐骑或徒步）。
  final String mountOrVehicle;

  /// 动态末态（支撑脚平衡、速度矢量、未完成动作相位）。
  final DynamicExitState dynamicExitState;

  const ShotContinuity({
    this.worldPosition = '',
    this.screenPosition = '',
    this.holdingLeft = '',
    this.holdingRight = '',
    this.lightingState = '',
    this.stateChanges = const [],
    this.gazeDirection = '',
    this.cameraAxis = '',
    this.cameraAngle = '',
    this.elevationLevel = '',
    this.gazeTarget = '',
    this.mountOrVehicle = '',
    this.dynamicExitState = DynamicExitState.empty,
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
      stateChanges.isEmpty &&
      gazeDirection.isEmpty &&
      cameraAxis.isEmpty &&
      cameraAngle.isEmpty &&
      elevationLevel.isEmpty &&
      gazeTarget.isEmpty &&
      mountOrVehicle.isEmpty &&
      dynamicExitState.isEmpty;

  ShotContinuity copyWith({
    String? worldPosition,
    String? screenPosition,
    String? holdingLeft,
    String? holdingRight,
    String? lightingState,
    List<String>? stateChanges,
    String? gazeDirection,
    String? cameraAxis,
    String? cameraAngle,
    String? elevationLevel,
    String? gazeTarget,
    String? mountOrVehicle,
    DynamicExitState? dynamicExitState,
  }) {
    return ShotContinuity(
      worldPosition: worldPosition ?? this.worldPosition,
      screenPosition: screenPosition ?? this.screenPosition,
      holdingLeft: holdingLeft ?? this.holdingLeft,
      holdingRight: holdingRight ?? this.holdingRight,
      lightingState: lightingState ?? this.lightingState,
      stateChanges: stateChanges ?? this.stateChanges,
      gazeDirection: gazeDirection ?? this.gazeDirection,
      cameraAxis: cameraAxis ?? this.cameraAxis,
      cameraAngle: cameraAngle ?? this.cameraAngle,
      elevationLevel: elevationLevel ?? this.elevationLevel,
      gazeTarget: gazeTarget ?? this.gazeTarget,
      mountOrVehicle: mountOrVehicle ?? this.mountOrVehicle,
      dynamicExitState: dynamicExitState ?? this.dynamicExitState,
    );
  }

  Map<String, dynamic> toJson() => {
    'world_position': worldPosition,
    'screen_position': screenPosition,
    'holding_left': holdingLeft,
    'holding_right': holdingRight,
    'lighting_state': lightingState,
    'state_changes': stateChanges,
    if (gazeDirection.isNotEmpty) 'gaze_direction': gazeDirection,
    if (cameraAxis.isNotEmpty) 'camera_axis': cameraAxis,
    if (cameraAngle.isNotEmpty) 'camera_angle': cameraAngle,
    if (elevationLevel.isNotEmpty) 'elevation_level': elevationLevel,
    if (gazeTarget.isNotEmpty) 'gaze_target': gazeTarget,
    if (mountOrVehicle.isNotEmpty) 'mount_or_vehicle': mountOrVehicle,
    if (dynamicExitState.isNotEmpty)
      'dynamic_exit_state': dynamicExitState.toJson(),
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
      gazeDirection: json['gaze_direction'] as String? ?? '',
      cameraAxis: json['camera_axis'] as String? ?? '',
      cameraAngle: json['camera_angle'] as String? ?? '',
      elevationLevel: json['elevation_level'] as String? ?? '',
      gazeTarget: json['gaze_target'] as String? ?? '',
      mountOrVehicle: json['mount_or_vehicle'] as String? ?? '',
      dynamicExitState: json['dynamic_exit_state'] is Map
          ? DynamicExitState.fromJson(
              (json['dynamic_exit_state'] as Map).map((k, v) => MapEntry(k as String, v)))
          : DynamicExitState.empty,
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
    var rawId = json['id'] as String? ?? '';
    if (rawId.trim().isEmpty) {
      final segNum = json['segment_id'];
      if (segNum != null) {
        rawId = 'seg-$segNum';
      }
    }
    final shotNumbers = (json['shot_numbers'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .toList() ??
        const [];
    if (rawId.trim().isEmpty) {
      rawId = shotNumbers.isNotEmpty ? 'seg-${shotNumbers.first}' : 'seg-1';
    }
    return StudioSegment(
      id: rawId,
      targetDurationSec:
          (json['target_duration_sec'] as num?)?.toInt() ?? 12,
      boundaryReason: json['boundary_reason'] as String? ?? '',
      promptNote: json['prompt_note'] as String? ?? '',
      clipPath: json['clip_path'] as String?,
      status: SegmentStatus.fromId(json['status'] as String?),
      shotNumbers: shotNumbers,
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

/// 系统提示词与规则模板实体。
///
/// 统一管理三视图排版、全年龄骨骼防漂移、纯净场景、道具展示与五维导演拆镜规则，
/// 允许用户在设置界面自定义修改并持久化，同时具备出厂默认值一键恢复。
class StudioPromptTemplate {
  final String id;
  final String name;
  final String category;
  final String description;
  final String defaultContent;
  final String? userOverride;
  final bool isBuiltin;
  final DateTime updatedAt;

  const StudioPromptTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.defaultContent,
    this.userOverride,
    this.isBuiltin = true,
    required this.updatedAt,
  });

  /// 当前生效的模板内容：若用户提供了自定义修改则使用用户内容，否则回退到出厂默认值。
  String get effectiveContent {
    final override = userOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return defaultContent.trim();
  }

  /// 便捷别名：获取当前生效的模板内容。
  String get content => effectiveContent;

  /// 用户是否修改了该模板。
  bool get isModified {
    final override = userOverride?.trim();
    return override != null && override.isNotEmpty && override != defaultContent.trim();
  }

  /// 便捷别名：是否已脱离出厂默认设置。
  bool get isModifiedFromDefault => isModified;

  StudioPromptTemplate copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    String? defaultContent,
    String? userOverride,
    String? content,
    bool clearOverride = false,
    bool? isBuiltin,
    DateTime? updatedAt,
  }) {
    return StudioPromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      defaultContent: defaultContent ?? this.defaultContent,
      userOverride: clearOverride
          ? null
          : (content ?? userOverride ?? this.userOverride),
      isBuiltin: isBuiltin ?? this.isBuiltin,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'default_content': defaultContent,
    if (userOverride != null && userOverride!.trim().isNotEmpty)
      'user_override': userOverride!.trim(),
    'is_builtin': isBuiltin,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory StudioPromptTemplate.fromJson(Map<String, dynamic> json) {
    return StudioPromptTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名模板',
      category: json['category'] as String? ?? '通用规范',
      description: json['description'] as String? ?? '',
      defaultContent: json['default_content'] as String? ?? '',
      userOverride: json['user_override'] as String?,
      isBuiltin: json['is_builtin'] as bool? ?? true,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// 核心内置出厂模板定义（覆盖资产、编剧、拆镜、编舞、视频提示词重写与质检自愈）。
  static List<StudioPromptTemplate> get builtinPresets => [
    StudioPromptTemplate(
      id: 'character_turnaround',
      name: '角色三视图与资产板规范',
      category: '资产生成规范',
      description: '定义角色资产三视图的 4 区块排版、正交平视、柔和漫射光影与 PBR 物理去塑料感材质。',
      defaultContent:
          'Character turnaround sheet，角色三视图设计图，角色设定资产参考图，16:9横版，纯白无缝背景，分4个区块：'
          '左侧大图是正面脸部胸像特写，清晰展示五官、脸型、发型、妆容与上半身服装细节；'
          '右侧横向排列同一角色的三个全身视角：正面平视、侧面、背面（正面平视全身、标准90度侧面全身、背面全身）。'
          '全部视图为完全一致的同一人物，脸型、五官、发色、发型、身材比例、服装配饰100%完全一致，人物中立自然站立，双手自然垂于身体两侧，全身完整入镜无遮挡，正交视图orthographic，无透视畸变。'
          'soft diffused studio lighting，柔和漫射柔光，不要强烈高光，matte surface，哑光材质，低specular，皮肤带有自然细微毛孔肌理，非打蜡油亮皮肤，布料保留织物编织纹理与自然褶皱纤维，发丝有细小碎发flyaway hairs，PBR physically based shading物理材质，不同材质粗糙度区分，无统一蜡质涂层，subsurface scattering次表面散射皮肤通透感，very subtle film grain极轻微胶片颗粒，not a toy, not figurine，真实人物质感。'
          '8K，超高细节，专业角色概念设计定妆照，各视角间距均匀，纯白底色，无背景，无杂物阴影，无地面，无文字标签，无水印，无多余杂物，无边框切分线。',
      updatedAt: DateTime(2026, 10, 20),
    ),
    StudioPromptTemplate(
      id: 'character_age_staging',
      name: '全年龄段骨骼身量与防漂移规范',
      category: '资产生成规范',
      description: '根据角色描述动态识别幼童、少年、青年、中年与老年，注入骨骼身量与防低幼/防老态约束，解除修长挺拔的死板绑架。',
      defaultContent:
          '写实自然的人体骨骼结构与真实身量，身材比例符合角色自身体型设定，无透视畸变。\n'
          '【年龄阶层自适应规则】\n'
          '• 幼童（<13岁）：真实儿童体态比例，稚嫩面庞，自然儿童头身比；\n'
          '• 少年（13~18岁）：具备接近成年男性的纵向骨骼身长，青少年身高（约165~170cm），骨骼发育充分拉伸，宽厚肩膀，成年男子头身比例，体态身型符合设定，面部光洁无须，少年青涩容貌，下颌轮廓分明；\n'
          '• 青年/成年（19~50岁）：成年人骨架体魄，骨骼完全成型，成熟身姿骨相，成年写实人体肌肉骨骼结构；\n'
          '• 老年（>50岁）：老年骨相与长者体态，自然面部岁月纹理与岁月风霜感。',
      updatedAt: DateTime(2026, 10, 20),
    ),
    StudioPromptTemplate(
      id: 'scene_environment',
      name: '场景空间与纯净空镜规范',
      category: '资产生成规范',
      description: '约束场景图的空间透视、宏大感、纯净空镜排版，彻底阻断任何人物残留与视角污染。',
      defaultContent:
          '专业电影级场景概念设计图，宏大空间透视与丰富环境细节，纯净环境空镜，纯场景，无人物，无人体，无人群，无多余杂物与现代穿帮，自然光影层次，大气透视景深，高视觉密度。',
      updatedAt: DateTime(2026, 10, 20),
    ),
    StudioPromptTemplate(
      id: 'prop_asset',
      name: '道具资产多角度展示规范',
      category: '资产生成规范',
      description: '约束主要道具的专业概念展示台、纯白无缝底色与材质物理光泽。',
      defaultContent:
          '专业道具资产概念设计图，纯白无缝背景，静物概念展台，超高细节，清晰呈现道具形制结构、纹理雕刻与材质反光，无人物手持，无杂物阴影，无边框切分线。',
      updatedAt: DateTime(2026, 10, 20),
    ),
    StudioPromptTemplate(
      id: 'novel_master_extraction',
      name: '小说母本资产提取规范',
      category: 'AI编剧与改编规范',
      description: '约束小说原著全案提炼：时代题材、世界观、美学风格与词组、核心登场角色（五官容貌与默认服饰）及常驻纯净场景。',
      defaultContent:
          '你是一位资深网络文学影视化与爆款短剧 IP 改编架构师。你的任务是从用户给出的长篇小说原著内容中，提炼出可以直接指导短视频制作的核心 IP 主库资产。\n\n'
          '【核心提取要求】\n'
          '1. worldview：提炼时代背景、核心规则矛盾、生存利益冲突与叙事主调，控制在 300 字以内。\n'
          '2. era_genre：根据小说题材与年代，从题材枚举中严格选择最贴合的一项。\n'
          '3. aesthetic_style：根据故事基调与视觉定位，选择最贴合的工业级美学风格。\n'
          '4. style_tokens：输出正向风格词组（如 UE5渲染、3D国漫、次世代CG、PBR物理材质、东方仙侠美学、体积光、自然光影）。\n'
          '5. characters：提炼小说中最关键的 2 到 6 位核心登场角色：\n'
          '   - 容貌体态原生细致描写（facial_features_zh）：保留明确年龄数字或阶段，仅限五官长相、神态、发型、体格身材，剔除服装配饰；\n'
          '   - 默认服装装束（default_attire_zh）：服装形制、面料质感、颜色、腰带、长靴与随身标志性配饰，严禁下半身留空；\n'
          '   - 全身综合描写（description_zh）：完整容貌与服饰统一描写；\n'
          '   - 性格与身份设定（personality）。\n'
          '6. scenes：提炼 2 到 6 个核心常驻场景（纯净物理空镜底板）：\n'
          '   - 场景仅作为舞台物理空间底板，严禁描写任何具体人物姓名、人群聚集或剧情走位；\n'
          '   - 纯粹描写建筑形制格局、空间进深、家具陈设、光影色温与空间材质。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'novel_episode_segmentation',
      name: '小说智能分集大纲规范',
      category: 'AI编剧与改编规范',
      description: '约束长篇小说戏剧分集：8~20集短剧规划、尊重人设拒绝低俗受辱套路、影视化大纲、前情记忆摘要与集尾悬念卡点。',
      defaultContent:
          '你是一位专精于网络文学影视化改编与叙事架构的资深分集编剧。你的任务是通读小说剧情主线，将原著有机拆解为节奏鲜明、戏剧钩子清晰的分集大纲。\n\n'
          '【核心原则：尊重原著人设与调性】\n'
          '1. 忠实保留原著主角的人物性格神韵（松弛从容、幽默机智、腹黑毒舌或爽文反套路），严禁套用“开局必须憋屈受辱”等低俗刻板模板！\n'
          '2. 分集标题（title）：提炼核心事件或人物交锋（10字以内），杜绝低俗流水线起名。\n'
          '3. 影视大纲（synopsis）：80~150字，清晰交代人物动机、交锋过程与高潮转折。\n'
          '4. 前情摘要（summary）：150字以内，客观沉淀核心剧情，供下游跨集连贯性注入。\n'
          '5. 悬念留钩（hook）：本集结尾截断点的悬念钩子（60字以内，身份即将揭晓、意想不到的反转）。\n'
          '6. 规划 8 到 20 集短剧，首集自然入戏并交代核心看点，尾集给出阶段性闭环。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'novel_chapter_adaptation',
      name: '单章小说剧本与大纲改编规范',
      category: 'AI编剧与改编规范',
      description: '约束单章原著深度提炼：四阶段影视化大纲（开局入戏、矛盾递进、核心高潮、本集断点）、前情摘要与悬念留钩。',
      defaultContent:
          '你是一位专精于网络文学影视化改编的资深编剧。你的任务是通读单章小说完整内容，依据影视叙事规律提炼结构化单集影视大纲。\n\n'
          '【核心结构：四大戏剧阶段】\n'
          '1. title: 拟定契合小说原味的单集标题（10字以内）。\n'
          '2. synopsis: 本集影视化完整粗大纲（300到500汉字），必须完整覆盖全章剧情脉络：\n'
          '   - 【开局入戏】：开场交代的环境、角色初始状态与初发事件；\n'
          '   - 【矛盾递进】：人物对话交锋、线索交织与行动过程；\n'
          '   - 【核心高潮】：本章情绪与戏剧张力最强的高光爆发事件；\n'
          '   - 【本集断点】：章末扣人心弦的转折或悬念。\n'
          '3. summary: 本集精炼前情摘要（150字以内，客观交代本集核心剧情沉淀）。\n'
          '4. hook: 本集结尾截断留钩（50字以内，突出未解之谜或即将爆发的悬念）。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'screenplay_generation',
      name: '影视分场剧本扩写规范',
      category: 'AI编剧与改编规范',
      description: '约束将剧情大纲扩写为影视工业标准分场文学剧本：场次三要素（时段/内外景/空间地标）、对白潜台词、微动作与事实保护。',
      defaultContent:
          '你是一位专精于网络文学影视化与影视文学剧本的资深编剧兼导演。你的任务是将故事大纲改编为符合影视工业规范的【标准分场剧本】。\n\n'
          '【核心原则】\n'
          '1. 尊重原著人物性格与爽点逻辑，杜绝刻板受辱套路，保留主角心理从容与幽默反差。\n'
          '2. 原生支持内心独白：将角色关键思考与吐槽明确标记为 voice_type: "inner_voice"，让故事因果清晰、动机分明。\n'
          '3. 影视导演级视听语法推导：每个动作节拍（beat）依据戏剧冲突与空间物理动势，自主推导景别（shot_size）、机位视角高度（camera_staging）、运镜动态轨迹（camera_move）、构图站位（screen_position）与视线正反打（gaze_direction）。\n'
          '4. 场次规划：按物理空间划分场次（Scene），明确内外景、时段、光影氛围与空间地标。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'script_breakdown_5d',
      name: '剧本到分镜 5D 拆解规范',
      category: '导演调度规范',
      description: '约束单集拆镜时的 5 大核心视听语法：单镜单动词、主体聚焦与背景简化、单一运镜禁止复合、视听节奏与剪辑点、内心独白画外音全员闭口。',
      defaultContent:
          '分镜必须遵循专业影视视听语言与五维导演决策，严格落实【5 大视听铁律】：\n\n'
          '【铁律一：单镜单动作原则】\n'
          '一个镜头内严禁堆叠“奔跑、拔剑、转身、跳跃、落地”等多个复合动作！复杂戏码必须拆解为连续镜头（例如：镜头1奔跑停步 -> 镜头2拔剑蓄力 -> 镜头3破空出招），每个镜头只承载一个主要动词与清晰受力反馈。\n\n'
          '【铁律二：画面主体绝对聚焦】\n'
          '画面严禁多人、烟雾、复杂背景同时抢眼抢焦点。必须主体明确、背景适度虚化简化，动作有明确的交互对象（如先拍递信中景，背景简化，信封作为明确受力对象）。\n\n'
          '【铁律三：单一明确运镜调度】\n'
          '单镜头只允许一种主要运镜轨迹（如缓慢推进 slow_push_in 或 定机位 static）。严禁同时堆砌斜向环绕、快速推进、横摇与变焦！需要机位变化时必须切镜。\n\n'
          '【铁律四：影视视听节奏与长短交替】\n'
          '严禁全片固定景别与固定时长。必须依据戏剧重音交替运用景别与节奏（如：中景交代动作 -> 特写揭示信物/兵器 -> 近景拍人物反应），按台词与动作完成点精确剪辑。\n\n'
          '【铁律五：内心独白全员闭口与肉身在场守卫】\n'
          '• 严禁幽灵角色：仅在内心独白、回忆闪回或台词提及的第三人绝对严禁填入出场角色 character_ids！\n'
          '• 内心独白（inner_voice）为纯粹画外音心声，画面主体与同框在场全员嘴唇全程严密闭合，不张嘴、不说话、无口型变化，全员展现沉思或微表情神态。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'director_breakdown_5d',
      name: '五维导演决策调度规范',
      category: '导演调度规范',
      description: '指导 AI 拆解分镜时的五维导演调度原则（动势、光影、光学机位四段式、时间演变、美学质感）。',
      defaultContent:
          '分镜必须遵循专业影视视听语言与五维导演决策：\n'
          '1. physical_momentum（主体动势与受力反馈）；\n'
          '2. lighting_staging（环境主光源与明暗面朝向）；\n'
          '3. camera_staging（起始运动 → 跟随对象 → 触发条件 → 结束落点四段式调度，俯仰视差明确，严禁机械平视）；\n'
          '4. temporal_evolution（起手/接触/余势动作相位与读时负荷）；\n'
          '5. aesthetic_texture（质感微粒与美学媒介风格）。',
      updatedAt: DateTime(2026, 10, 20),
    ),
    StudioPromptTemplate(
      id: 'action_combat_breakdown',
      name: '打斗与攻防动作拆解规范',
      category: '导演调度规范',
      description: '约束武打与攻防动作戏的拆镜：六步攻防因果链（意图/攻击/阻击/受力/位移/接力）、3~4招连续接力组、支撑脚与速度矢量末态。',
      defaultContent:
          '你是一位专精于高武修仙、武侠打斗与激烈追逐的动作导演兼动作编舞师。\n\n'
          '【核心禁令】严禁“打一招停一下”的回合制摆姿势！上一招余势未尽，下一招反制、变线或接力必须已经启动！\n\n'
          '【攻防因果与六步链】\n'
          '以 3 到 4 个分镜构成一个连续接力攻击组。每个动作分镜在 combat_steps 中严格落实六步因果链：\n'
          '1. intent: 本动作用意（虚招佯攻、破防刺杀、下盘扫击）；\n'
          '2. attack: 起手动作与兵器路线；\n'
          '3. defense: 对方应对与阻击（滑步后仰、横刀格挡、侧身避让）；\n'
          '4. impact: 接触与受力失衡反馈（金铁交鸣火星溅射、虎口震颤）；\n'
          '5. displacement: 受力位移与空间形变；\n'
          '6. next_link: 下一招接力方向（承接上一招余势，不提前完成后招）。\n'
          '同时填充支撑脚、速度矢量与动态末态，确保生成视频时动作矢量连续。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'video_prompt_rewrite',
      name: 'AI 视频提示词精炼与冲突消解规范',
      category: 'AI视频生成规范',
      description: '专门针对视频生成模型（如 Agnes Video 2.5 Flash）的提示词重写规范：消解场景二选一冲突（地牢 vs 衙门）、氛围光影打架（黄昏残阳 vs 地牢火把）、运镜冲突（推镜 vs 定机位）、单镜 180° 轴线无效指令，并消除括号机器标记，点名全员下达画外音闭口守卫，锁定动作—台词因果时序。',
      defaultContent:
          '你是一位资深 AI 视频生成 Prompt 调优专家。你的任务是将分镜的画面描述、微动作、摄影运镜与环境光影精炼为最适合主流视频大模型（如 Agnes Video 2.5 Flash / Sora / Kling）执行的高保真视频提示词。\n\n'
          '【四大致命冲突消解铁律】\n'
          '1. 场景唯一性：彻底消除二选一冲突（例如写了地牢又写衙门口），统一到当前镜头摄像机所处的唯一起点物理空间。\n'
          '2. 氛围与光照统一：彻底消除互斥光源与情绪（例如地牢火把与黄昏残阳如血打架、温馨与阴森压抑打架），确定单一主导光影与基调色温。\n'
          '3. 运镜唯一性：单镜头只保留一种核心运镜轨迹！推镜（push in）严禁与定机位（static）同时出现，剔除矛盾镜头指令。\n'
          '4. 剔除无效多镜剪辑指令：单镜头不需要 180° 轴线同轴关系说明，彻底剔除单镜无法执行的剪辑规则，节省模型注意力。\n'
          '5. 因果时序唯一性：反应性台词（对另一角色动作的回应、喝止、怒斥）必须晚于其触发动作！严禁将台词前移至触发动作之前（例如“甲拱手离去，乙在背后喝骂”绝不可写成乙先骂、甲再走）。同一镜头内不同主体的动作必须保留先后次序，严禁合并为同时发生。若原始提示词含【因果时间轴】段，其秒数区间与先后顺序必须原样保留，不得改写为同时发生。\n\n'
          '【角色发声与画外心声守卫】\n'
          '1. 严禁使用中括号机器标记（如 `[角色内心独白/心声]`），大模型极易误识别为台词。\n'
          '2. 若为内心独白（内心 OS / 心声 / 旁白）：直接采用正向画外音自然语言描述，并必须显式点名在场全员（例如：“画外音心声。画面中姜七夜、老王等全员嘴唇全程严密闭合，不张嘴，无口型变化，绝对不说话，无字幕，全员保持沉思微神态”），杜绝配角误张嘴开口抢话！\n'
          '3. 若为普通对白：明确指出仅说话角色随台词自然开合嘴型，其余倾听者保持闭口倾听。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'director_audit_auto_fix',
      name: '导演质检问题一键 AI 自动修复规范',
      category: '导演调度规范',
      description: '约束根据导演质检报告中的违规项（C1~C10 违规，如动作堆叠、主体不清、机位冲突、台词过长、角色漂移等）对分镜执行精准修补。',
      defaultContent:
          '你是一位资深影视导演兼分镜监制。你的任务是根据分镜质检引擎给出的违规诊断清单（包含但不限于 C1 动作堆叠、C2 主体不清、C3 机位冲突、C4 角色漂移、C5 表演过满、C6 节奏单一、C7 台词超长、C8 幽灵角色在场、C9 视线穿帮、C10 运镜与动作超载等），对问题分镜实施精准修正。\n\n'
          '【修复原则】\n'
          '1. 保持剧情骨干与核心事件 100% 保真，不擅自删减核心剧情。\n'
          '2. 动作过载时：将复合动作精简为当前镜头最核心的主干微动作，剔除多余次生动作。\n'
          '3. 运镜与机位冲突时：以动态运镜为准，剔除矛盾的定机位或多重移动。\n'
          '4. 幽灵角色时：剔除仅在心声、旁白或对话中被提及的第三人，确保出场角色只有肉身在场者。\n'
          '5. 心声导致配角抢开口时：补全全员闭口守卫指令。\n'
          '6. 输出修补后的分镜完整字段，直接替换问题分镜。',
      updatedAt: DateTime(2026, 10, 21),
    ),
    StudioPromptTemplate(
      id: 'screenplay_plausibility_rules',
      name: '环境生态与社会常识推演规范',
      category: 'AI编剧与改编规范',
      description: '约束公共开放空间（街市/酒肆/广场）异常事件强制生成路人NPC围观与生态反应；隐秘事件自动修正至死胡同/暗角/深夜，杜绝横尸闹市无人理等穿帮逻辑。',
      defaultContent:
          '【环境生态与社会常识推演铁律（严防常识穿帮）】\n'
          '1. 公共开放空间社会闭环法则：\n'
          '   凡在街道、集市、酒肆大堂、衙门外、广场、演武场等公共开放空间，发生异常事件（如横死尸体、当街截杀、剧烈打斗、重伤吐血、奇异光效）时，摄像机视野范围内严禁出现空旷死寂、旁若无人的孤立荒诞场面！\n'
          '   - 必须显式描写背景群众生态：周围路人行商驻足围观、指指点点、低声交头接耳、惊呼退避、挑夫驻足观望、或巡街衙役捕快推开人群拉起封锁线；\n'
          '   - 视听调度必须给出周围人对主角与异常事件的真实生理应激反应，严禁只画主角与死者两人而忽视整个市井世界。\n'
          '2. 隐秘事件时空合理置换法则：\n'
          '   若小说原著剧情或戏剧目标要求事件“绝对隐秘、无人知晓、不留痕迹”（例如无声刺杀、秘密弃尸、私下交易）：\n'
          '   - 严禁将事发地点设置在白天繁华大道或人流密集处！\n'
          '   - 编剧与导演引擎必须将场景合理限定或迁移至【具有物理遮蔽的封闭或僻静空间】（如：阴暗死胡同拐角、断壁残垣后的柴房破庙、荒郊坟地乱葬岗、视线死角、或设定在暴雨倾盆的漆黑子夜），并着重描写环境的逼仄幽暗与视线遮挡，使“无人发觉”具备充分的物理合理性。\n'
          '3. 物理与生理因果守恒：\n'
          '   伤势受创必须伴随物理失衡、血迹喷溅轨迹或踉跄后退；兵刃出鞘与回鞘必须有明确物理支点；道具的出现与隐藏必须符合空间收纳逻辑。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'screenplay_beat_pacing_rules',
      name: '竖屏短剧高能节拍与动作化规范',
      category: 'AI编剧与改编规范',
      description: '落实黄金3秒高压切入（Cold Open）、15-20秒情绪阶梯递进、心理描写具象动作化（微表情/道具交互/微动作）、片尾极限断章卡点钩子。',
      defaultContent:
          '【竖屏短剧高能节拍与微动作化法则】\n'
          '1. 黄金 3 秒高压切入法则（Cold Open）：\n'
          '   单集开场第 1 镜（前 3 秒内）必须迅速建立高反差视觉奇观、生死危机或强烈戏剧悬念！严禁使用平缓长镜头散步、纯看风景空镜或冗长生活琐事开篇。必须“开门见山”，直接切入正在发生的核心动作或高能现场。\n'
          '2. 15 秒情绪波澜与节拍递进：\n'
          '   单集 90 秒内规划 4 到 6 个紧密戏剧节拍（Beats），每 15~20 秒必须出现一次微型转折、障碍升级、情绪反转或信息增量，拒绝流水账平铺直叙。\n'
          '3. 心理描写具象动作化（拒绝空洞旁白）：\n'
          '   原著小说中大段的主角算计、内心冷笑、境界领悟与心理战，严禁全部转为枯燥的画外独白！\n'
          '   - 必须强制转化为可拍摄的【下意识微动作与道具交互】：例如将“心中杀机暴涨”外化为“大拇指将刀镡无声顶出一道冷冽缝隙，指节因用力泛白”；将“心中轻蔑冷笑”外化为“垂眸端起青花茶盏轻吹热气，眼角划过一丝讥诮微弧”；\n'
          '   - 仅在推动因果动机且确实无法外化时，才使用 voice_type: "inner_voice"（并确保全员闭口）。\n'
          '4. 片尾高压断章卡点（Cliffhanger）：\n'
          '   单集剧本的最后一个镜头，严禁收尾在双方握手言和、各自回房睡觉或风平浪静的平淡节点！\n'
          '   - 必须精准截断在【冲突最顶峰、杀机爆发前一秒、致命真相即将被拆穿的极限瞬间】（例如：利刃已逼近主角咽喉半寸 / 密信刚撕开蜡封的一角 / 门外突然响起重重叩击声），以此产生强烈的追剧惯性。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'storyboard_vertical_5d',
      name: '竖屏 9:16 视听语法与拆镜工业规范',
      category: '导演调度规范',
      description: '针对 9:16 竖屏短剧画面：中近景特写偏好（≥70%）、单镜肉身在场角色 ≤ 3 人、四人以上群像拆解为连续正反打、画面底部 1/5 字幕安全区留白保护、平缓运镜防畸变。',
      defaultContent:
          '【竖屏 9:16 短剧视听工业铁律】\n'
          '1. 景别偏好分布（突出面部与情绪）：\n'
          '   竖屏 9:16 构图画幅狭长，全景与远景会导致人物脸部过小、AI 生图极易五官变形融化。\n'
          '   - 特写（close_up）、中近景（medium_close_up）与半身中景（medium）占比必须 ≥ 70%；\n'
          '   - 全景（full）与远景（long）仅用于场次开端 1~2 镜建立空间地理环境，随后必须迅速切入中近景聚焦。\n'
          '2. 单镜头肉身在场人数严格约束（≤ 3 人）：\n'
          '   单镜头画面内肉身在场角色 STRICTLY ≤ 3 人！\n'
          '   - 严禁 4 人以上同框并排站立（竖屏无法容纳，会导致人物挤压变形与脸部崩坏）；\n'
          '   - 4 人以上的复杂群戏必须拆解为标准影视剪辑语法：[环境建立全景交代阵营] -> [发言者单人中景] -> [对手听者反应特写] -> [双人正反打过肩镜头]，通过切镜完成群像交锋。\n'
          '3. 底部 1/5 字幕安全区留白保护：\n'
          '   画面底部 20% 区域为平台字幕、进度条与操作按钮遮挡区，严禁将人物脸部、核心动作交互点、关键道具放在画面底部，核心视觉兴趣点必须定位于画面上部 40%~70% 的黄金分割区域。\n'
          '4. 摄影运镜平稳性：\n'
          '   优先使用定机位（static）、平缓推进（slow_push_in）、轻微平移跟随（pan_tracking）；严禁使用 360 度剧烈旋转变焦等复杂多轴运镜，防止 AI 视频生成时画面拉伸撕裂。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'visual_prompt_assembly',
      name: '分镜生图与视频提示词装配规范',
      category: '视觉渲染规范',
      description: '定义模块化装配模板：统一美学前缀 + 角色视觉锚点 + 场景七方位光影 + 镜头微动作描述。',
      defaultContent:
          '【工业级正向视觉提示词装配模板】\n'
          '{{style_prefix}}, {{scene_spatial_anchors}}, {{character_visual_anchors}}, {{shot_action_zh}}, 8K resolution, masterpiece, cinematic lighting, vertical 9:16 composition.\n\n'
          '装配要素顺序：\n'
          '1. style_prefix: 统一美学风格基调与媒介渲染词（如 UE5渲染, 3D国漫, 电影级光影）；\n'
          '2. scene_spatial_anchors: 当前场次七方位地标与主光源方位（如 西向夕阳金光照亮青石长街）；\n'
          '3. character_visual_anchors: 出场角色的固定面部容貌、发型发色与专属装束锚点；\n'
          '4. shot_action_zh: 当前分镜具象化微动作与微表情描述。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'negative_prompt_library',
      name: '全局工业级负向规避词库',
      category: '视觉渲染规范',
      description: '统一防止画面崩坏、人脸畸变、多肢体、画面文字水印与低画质的全局负向规避词。',
      defaultContent:
          'nsfw, low quality, worst quality, deformed, bad anatomy, bad hands, missing fingers, extra limbs, mutated, disfigured, blurry, duplicate, cloned face, poorly drawn face, poorly drawn hands, watermark, signature, text, subtitles, logo, cropped, out of frame, distortion, plastic skin, doll-like, ugly, mutilated, extra legs, extra arms, bad eyes, fused fingers.',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'writers_room_master_extract',
      name: '编剧研讨室主线与改编边界抽取规范',
      category: 'AI编剧与改编规范',
      description: '从原著全本或多章提炼故事主线脉络表，并划分必留情节（核心主线/名场面/伏笔）、可删情节（无推进心理/重复刷怪水文）与可改情节（合并配角/过渡精简）。',
      defaultContent:
          '你是一位资深网络文学影视化与爆款短剧总编审兼策划总监。你的任务是通读小说原著，将几十万字的原著内容解构为 AI 与主创团队稳定记忆的核心叙事骨架，并输出清晰的改编边界。\n\n'
          '【核心输出要求】\n'
          '1. master_plot: 全书主线脉络与核心人物叙事弧光（开端、发展、中段高潮、大结局阶段目标与核心生存对抗矛盾），500字以内；\n'
          '2. must_keep: 【必留情节清单】（原著核心主线、不可替代的名场面、主角立身之本的核心高光、决定性反转伏笔）；\n'
          '3. can_cut: 【可删情节清单】（与主线无关的漫长心理独白、重复枯燥的修炼刷怪打脸水文、无实质推进的过度铺垫）；\n'
          '4. can_modify: 【可改情节清单】（允许合并的边缘功能性工具人配角、可精简重组的转场过渡场景）。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'writers_room_season_beats',
      name: '全季短剧分集与悬念钩子规划规范',
      category: 'AI编剧与改编规范',
      description: '按短剧叙事节奏规划全季分集大纲（8~30集），每集锁定单一核心冲突（A vs B）与片尾高压断章钩子（Cliffhanger）。',
      defaultContent:
          '你是一位擅长把控全季节奏的爆款短剧剧作总监。你的任务是依据小说主线脉络与改编边界，将全书合理规划为 8 到 30 集单单元强冲突剧集大纲。\n\n'
          '【分集规划铁律】\n'
          '1. 篇章递进：按大篇章合理划分，每 5~10 集形成一个中型阶段性高潮大反转；\n'
          '2. 一集一核心事件：每集只主攻一个核心对抗或危机（A vs B），不塞入多条发散支线；\n'
          '3. 第 1 集黄金爆发：第 1 集开场 3 秒内直接抛出核心危机或反差，绝不拖泥带水；\n'
          '4. 结尾极限留钩：每集末尾必须卡在最吊胃口、最引发好奇的瞬间（hook），确保看客主动点击下一集。',
      updatedAt: DateTime(2026, 10, 28),
    ),
    StudioPromptTemplate(
      id: 'writers_room_dialogue',
      name: '编剧研讨室人机共创对话规范',
      category: 'AI编剧与改编规范',
      description: '作为AI联合编剧与制片人协同讨论大纲，根据用户的改编指令（加快节奏、合并情节、调换高潮）动态修订分集。',
      defaultContent:
          '你是一位经验丰富、善于倾听并精准执行制片人意图的短剧 AI 联合编剧。制片人正在与你讨论并修改全季分集大纲。\n\n'
          '【交互原则】\n'
          '1. 认真领会制片人的修改指令（如“把前三集节奏加快”、“第5集高潮提前到第2集”、“删除某个配角并合并到主角兄弟身上”）；\n'
          '2. 给出专业的影视剧作反馈，分析修改对前后伏笔与因果链的影响；\n'
          '3. 给出清晰具体的修订方案，并返回更新后的分集变动详情。',
      updatedAt: DateTime(2026, 10, 28),
    ),
  ];
}

/// 生图规格预设（尺寸档位与画幅比例）。
///
/// 直通映射 Agnes Image 2.5 Flash 官方标准的 size ('1K'..'4K') 与 ratio ('16:9'..'21:9')，
/// 同时给出标准物理像素与直观中文标签。
class StudioImageDimensionPreset {
  final String size;
  final String ratio;
  final int width;
  final int height;
  final String label;

  const StudioImageDimensionPreset({
    required this.size,
    required this.ratio,
    required this.width,
    required this.height,
    required this.label,
  });

  /// 常用标准预设
  static const standard16x9 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '16:9',
    width: 2624,
    height: 1472,
    label: '16:9 横屏宽幅 (2K)',
  );

  static const standard1K_16x9 = StudioImageDimensionPreset(
    size: '1K',
    ratio: '16:9',
    width: 1312,
    height: 736,
    label: '16:9 横屏宽幅 (1K 极速)',
  );

  static const standard4K_16x9 = StudioImageDimensionPreset(
    size: '4K',
    ratio: '16:9',
    width: 5248,
    height: 2944,
    label: '16:9 横屏宽幅 (4K 超清)',
  );

  static const standard21x9 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '21:9',
    width: 3136,
    height: 1344,
    label: '21:9 宽银幕电影 (2K)',
  );

  static const standard9x16 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '9:16',
    width: 1472,
    height: 2624,
    label: '9:16 竖屏短剧 (2K)',
  );

  static const standard1K_9x16 = StudioImageDimensionPreset(
    size: '1K',
    ratio: '9:16',
    width: 736,
    height: 1312,
    label: '9:16 竖屏短剧 (1K 极速)',
  );

  static const standard4K_9x16 = StudioImageDimensionPreset(
    size: '4K',
    ratio: '9:16',
    width: 2944,
    height: 5248,
    label: '9:16 竖屏短剧 (4K 超清)',
  );

  static const standard1x1 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '1:1',
    width: 2048,
    height: 2048,
    label: '1:1 正方展台/特写 (2K)',
  );

  static const standard1K_1x1 = StudioImageDimensionPreset(
    size: '1K',
    ratio: '1:1',
    width: 1024,
    height: 1024,
    label: '1:1 正方展台 (1K 极速)',
  );

  static const standard4K_1x1 = StudioImageDimensionPreset(
    size: '4K',
    ratio: '1:1',
    width: 4096,
    height: 4096,
    label: '1:1 正方展台 (4K 超清)',
  );

  static const standard4x3 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '4:3',
    width: 2304,
    height: 1728,
    label: '4:3 经典画幅 (2K)',
  );

  static const standard3x4 = StudioImageDimensionPreset(
    size: '2K',
    ratio: '3:4',
    width: 1728,
    height: 2304,
    label: '3:4 竖画幅 (2K)',
  );

  /// 场景推荐默认规格：2K 16:9
  static const defaultScene = standard16x9;

  /// 角色三视图推荐默认规格：2K 16:9
  static const defaultCharacterTurnaround = standard16x9;

  /// 道具单品推荐默认规格：2K 1:1
  static const defaultProp = standard1x1;

  static const List<StudioImageDimensionPreset> presets = [
    standard16x9,
    standard1K_16x9,
    standard4K_16x9,
    standard21x9,
    standard9x16,
    standard1K_9x16,
    standard4K_9x16,
    standard1x1,
    standard1K_1x1,
    standard4K_1x1,
    standard4x3,
    standard3x4,
  ];

  /// 根据比例代码（如 '16:9'）与尺寸档位（如 '2K'）快速解析预设
  static StudioImageDimensionPreset fromRatio(
    String? ratio, {
    String size = '2K',
  }) {
    if (ratio == null || ratio.trim().isEmpty) return standard16x9;
    final r = ratio.trim();
    for (final p in presets) {
      if (p.ratio == r && p.size == size) return p;
    }
    // 回退按比例找
    for (final p in presets) {
      if (p.ratio == r) return p;
    }
    return standard16x9;
  }
}
