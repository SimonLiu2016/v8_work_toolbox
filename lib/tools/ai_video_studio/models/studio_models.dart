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

  final bool active;

  const CharacterVariation({
    required this.id,
    required this.name,
    this.positiveDelta = '',
    this.negativeDelta = '',
    this.attirePrompt = '',
    this.turnaroundPath,
    this.referenceImages = const [],
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

    final envSpec = (sceneEnvironmentOverride != null && sceneEnvironmentOverride.trim().isNotEmpty)
        ? sceneEnvironmentOverride.trim()
        : sceneEnvironmentRequirement;

    final middleParts = <String>[
      if (envSpec.isNotEmpty && envSpec != emptyHeadLock) envSpec,
      if (envAnchor != null && envAnchor.isNotEmpty) envAnchor,
      if (style != null && style.isNotEmpty) style,
      if (angle != null) angle.promptToken,
      if (cleaned.isNotEmpty) cleaned,
    ];

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

    final middleParts = <String>[
      emptyHeadLock,
      if (envAnchor != null && envAnchor.isNotEmpty) envAnchor,
      if (style != null && style.isNotEmpty) style,
      if (cleaned.isNotEmpty) cleaned,
      emptyTailLock,
    ];

    return [panoHead, middleParts.join('， '), panoTail].join('， ');
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
  }) {
    final era = VisualEraGenre.fromId(eraGenreId);
    final parts = [
      propAssetRequirement,
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

  final DateTime updatedAt;

  const PropCard({
    required this.id,
    required this.name,
    this.descriptionZh = '',
    this.promptEn = '',
    this.referenceImages = const [],
    this.isKeyProp = false,
    required this.updatedAt,
  });

  PropCard copyWith({
    String? id,
    String? name,
    String? descriptionZh,
    String? promptEn,
    List<String>? referenceImages,
    bool? isKeyProp,
    DateTime? updatedAt,
  }) {
    return PropCard(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptionZh: descriptionZh ?? this.descriptionZh,
      promptEn: promptEn ?? this.promptEn,
      referenceImages: referenceImages ?? this.referenceImages,
      isKeyProp: isKeyProp ?? this.isKeyProp,
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

  /// 剧情记忆库。
  final List<EpisodeMemory> memories;

  /// 主要道具列表（IP 级资产，跨集复用）。
  ///
  /// 旧 `series_profile.json` 无此字段，[fromJson] 按空列表加载，无需迁移。
  final List<PropCard> props;

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
    this.memories = const [],
    this.props = const [],
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
    List<EpisodeMemory>? memories,
    List<PropCard>? props,
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
      memories: memories ?? this.memories,
      props: props ?? this.props,
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
    'memories': memories.map((m) => m.toJson()).toList(),
    'props': props.map((e) => e.toJson()).toList(),
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

  /// 发声类型（对白 `dialogue` / 内心独白 `inner_voice` / 旁白 `narration`）。
  final UtteranceVoiceType voiceType;

  /// 出场角色卡 id 列表。
  final List<String> characterIds;

  /// 出场角色在当前镜头的具体形态映射（key: characterId, value: variationId）。
  ///
  /// 若未指定（空 Map 或无对应角色 key），出图时回退至单集覆盖或角色默认形态。
  final Map<String, String> characterVariations;

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
    this.characterVariations = const {},
    this.sceneId = '',
    this.beatId = '',
    this.cameraMove = '',
    this.assembledPrompt = '',
    this.framePath,
    this.firstFramePath,
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
  });

  /// 是否为角色内心独白（心声/内心 OS）。
  bool get isInnerVoice =>
      voiceType == UtteranceVoiceType.innerVoice ||
      dialogue.contains('内心 OS') ||
      dialogue.contains('内心OS') ||
      dialogue.contains('（OS）') ||
      dialogue.contains('(OS)') ||
      dialogue.contains('心声') ||
      dialogue.contains('内心独白');

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
    UtteranceVoiceType? voiceType,
    List<String>? characterIds,
    Map<String, String>? characterVariations,
    String? sceneId,
    String? beatId,
    String? cameraMove,
    String? assembledPrompt,
    String? framePath,
    String? firstFramePath,
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
      characterVariations: characterVariations ?? this.characterVariations,
      sceneId: sceneId ?? this.sceneId,
      beatId: beatId ?? this.beatId,
      cameraMove: cameraMove ?? this.cameraMove,
      assembledPrompt: assembledPrompt ?? this.assembledPrompt,
      framePath: framePath ?? this.framePath,
      firstFramePath: firstFramePath ?? this.firstFramePath,
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
    'character_variations': characterVariations,
    'scene_id': sceneId,
    if (beatId.isNotEmpty) 'beat_id': beatId,
    'camera_move': cameraMove,
    'assembled_prompt': assembledPrompt,
    'frame_path': framePath,
    if (firstFramePath != null) 'first_frame_path': firstFramePath,
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
      characterVariations: (json['character_variations'] as Map?)?.map(
            (k, v) => MapEntry(k as String, v as String),
          ) ??
          const {},
      sceneId: json['scene_id'] as String? ?? '',
      beatId: json['beat_id'] as String? ?? '',
      cameraMove: json['camera_move'] as String? ?? '',
      assembledPrompt: json['assembled_prompt'] as String? ?? '',
      framePath: json['frame_path'] as String?,
      firstFramePath: json['first_frame_path'] as String?,
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

  /// 5 套核心内置出厂模板定义（纯中文自然语言，对齐 Agnes 规范）。
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
      id: 'director_breakdown_5d',
      name: '五维导演决策与拆镜规范',
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
