/// Prompt 组装器：角色 DNA + 风格锁 + 运镜词 → 最终生图 Prompt。
///
/// spec「角色资产卡与形态版本化」要求形态只存**相对**基础 Prompt 的差异词，
/// 合并后才形成完整 Prompt。这里是那个合并的唯一实现处——分镜、批量重算、
/// 形态切换三条路径都走它，才能保证同一角色在任何分镜里长出同一张脸。
library;

import '../models/studio_models.dart';

/// 目标生图引擎的 Prompt 长度上限（词）。
///
/// 750 是 spec 写死的数字。SiliconFlow Flux-schnell 的 T5 文本编码器上限
/// 约 512 token，超过部分不报错、只是被静默截断——所以超长 Prompt 不是
/// 「效果差一点」，而是尾部约束直接消失。超限时按优先级从尾部丢弃。
const int kMaxPromptWords = 750;

/// 一段可选的组装输入。全部可为 null——纯动作镜头没有角色和场景。
class PromptParts {
  /// 全局风格词（剧集级"风格锁"）。
  final String? styleTokens;

  /// 景别标签的英文摄影表述（如 `close-up`）。
  final String? shotSize;

  /// 情绪基调标签（原样进入 Prompt，如 `warm lighting` 由映射表给出）。
  final String? mood;

  /// 分镜功能（开场/推进/爆发/收尾）的构图提示。
  final String? shotFunction;

  final CharacterCard? character;

  /// 该集对该角色的形态覆盖；为 null 时用角色卡上的激活形态。
  final CharacterVariation? variation;

  final SceneCard? scene;

  /// 运镜方案关键词（用户选择后写入分镜）。
  final String? cameraMove;

  /// 画面动作描述（中文）。生图引擎读不懂中文，但动作描述是分镜的意图来源，
  /// 这里保留它是为了在超限截断时知道哪些内容可以牺牲。
  final String? actionZh;

  const PromptParts({
    this.styleTokens,
    this.shotSize,
    this.mood,
    this.shotFunction,
    this.character,
    this.variation,
    this.scene,
    this.cameraMove,
    this.actionZh,
  });
}

/// 组装结果。
class AssembledPrompt {
  final String positive;
  final String negative;

  /// 是否发生了截断（用户在 UI 上该看到提示）。
  final bool truncated;

  /// 被丢弃的尾部片段（截断提示里展示，让用户知道丢了什么）。
  final List<String> droppedSegments;

  /// 合并后的形态差异词说明（调试与「为何这张脸不对」排查用）。
  final String? appliedVariationName;

  /// 本次组装期望但实际缺失的参考图标签（spec: 缺少参考图时不静默降级）。
  ///
  /// 非空表示提示词里**没有**为这些参考输出 `{{ref N}}` 编号——调用方必须
  /// 阻止生成并提示用户补图，而不是提交一个没有一致性约束的请求。
  final List<String> missingReferences;

  const AssembledPrompt({
    required this.positive,
    required this.negative,
    this.truncated = false,
    this.droppedSegments = const [],
    this.appliedVariationName,
    this.missingReferences = const [],
  });
}

abstract final class PromptAssembler {
  /// 拼接一条完整生图 Prompt。
  ///
  /// 段顺序即优先级：越靠前越重要。超限时从尾部开始丢（spec 4.2），
  /// 因为风格、角色、场景任缺一个都会让画面跑偏，而运镜词缺失只是少了点动感。
  static AssembledPrompt buildShotPrompt(PromptParts parts) {
    final positiveSegments = <String>[];
    final negativeSegments = <String>[];

    // 1. 画质与画风基线（永远在最前，丢了它整张图的质量下限就没了）。
    positiveSegments.addAll([
      _qualityBaseline,
      if (parts.styleTokens?.trim().isNotEmpty == true)
        parts.styleTokens!.trim(),
    ]);

    // 2. 景别 / 情绪 / 构图。
    final composition = [
      if (parts.shotSize?.trim().isNotEmpty == true) parts.shotSize!.trim(),
      if (parts.shotFunction?.trim().isNotEmpty == true)
        parts.shotFunction!.trim(),
      if (parts.mood?.trim().isNotEmpty == true) parts.mood!.trim(),
    ];
    positiveSegments.addAll(composition);

    // 3. 角色基础 Prompt + 形态差异词。
    String? variationName;
    final character = parts.character;
    if (character != null) {
      final base = character.basePromptPositive.trim();
      if (base.isNotEmpty) positiveSegments.add(base);

      final variation = parts.variation ?? character.activeVariation;
      if (variation != null) {
        final delta = variation.positiveDelta.trim();
        if (delta.isNotEmpty) positiveSegments.add(delta);
        variationName = variation.name;
      }

      final baseNegative = character.basePromptNegative.trim();
      if (baseNegative.isNotEmpty) negativeSegments.add(baseNegative);
      if (variation != null) {
        final negativeDelta = variation.negativeDelta.trim();
        if (negativeDelta.isNotEmpty) negativeSegments.add(negativeDelta);
      }
    } else {
      // 空镜头 / 无角色镜头：负向显式抑制人脸与人物，避免生图模型脑补塞入人脸
      negativeSegments.add('person, human, face, character, people, man, woman, portrait');
    }

    // 4. 场景与动作内容。
    final scene = parts.scene;
    final scenePrompt = scene?.promptEn.trim() ?? '';
    if (scenePrompt.isNotEmpty) {
      positiveSegments.add(scenePrompt);
    } else if (scene != null && scene.name.trim().isNotEmpty) {
      positiveSegments.add(scene.name.trim());
    }

    // 视觉动作与故事情节描述（画面的核心灵魂）：
    final action = parts.actionZh?.trim() ?? '';
    if (action.isNotEmpty) {
      positiveSegments.add(action);
    }

    // 5. 运镜词（最后，最可牺牲）。
    if (parts.cameraMove?.trim().isNotEmpty == true) {
      positiveSegments.add('camera: ${parts.cameraMove!.trim()}');
    }

    final positive = _joinWithinLimit(positiveSegments, kMaxPromptWords);
    final negative = _joinWithinLimit(negativeSegments, kMaxNegativeWords);

    return AssembledPrompt(
      positive: positive.text,
      negative: negative.text,
      truncated: positive.truncated,
      droppedSegments: positive.dropped,
      appliedVariationName: variationName,
    );
  }

  /// 负向 Prompt 单独的上限——它通常短得多，且截断它的代价是画面上出现瑕疵。
  static const int kMaxNegativeWords = 200;

  /// 画质基线词。所有引擎通吃，且必须在最前（越靠前权重越高）。
  static const String _qualityBaseline =
      'masterpiece, best quality, high detail, sharp focus';

  /// 默认负向词：用户没填负向 Prompt 时也要有的兜底瑕疵表。
  static const String defaultNegativePrompt =
      'blurry, low quality, worst quality, deformed, duplicate, '
      'extra limbs, bad anatomy, disfigured, watermark, signature, text, '
      'username, logo, cropped, out of frame';

  /// 合并基础 Prompt 与形态差异词（spec 4.2）。
  ///
  /// 只做拼接与去重，不做语义处理：AI 已经保证差异词是"追加描述"而不是
  /// "覆盖描述"，在这里改写用户写下的词会让他们无法预测结果。
  static String mergeVariation({
    required String basePrompt,
    required String positiveDelta,
  }) {
    final base = basePrompt.trim();
    final delta = positiveDelta.trim();
    if (delta.isEmpty) return base;
    if (base.isEmpty) return delta;
    // 差异词与基础词重复时跳过：Flux 这类引擎对重复词的注意力会翻倍，
    // 重复写 "silver hair" 不会更银，只会挤占别的词的权重。
    final existing = _wordsOf(base).toSet();
    final fresh = _wordsOf(delta).where((w) => !existing.contains(w));
    if (fresh.isEmpty) return base;
    return '$base, ${fresh.join(', ')}';
  }

  /// 按字数统计（空格分词，逗号/句号也算分隔）。
  static int wordCount(String prompt) {
    if (prompt.trim().isEmpty) return 0;
    return _wordsOf(prompt).length;
  }

  /// 组装一条片段视频提示词（spec: 片段提示词组装）。
  ///
  /// **确定性组装，不让 AI 自由发挥**（design 决策 5）：AI 只负责划片段边界
  /// 与给目标时长，最终提示词由分镜字段 + 角色卡 + 场景卡 + 台账在这里拼出。
  /// 这样「改了分镜字段但片段提示词没变」这类不同步不可能发生——纯函数每次
  /// 重算，UI 不需要判断何时该重新生成。
  ///
  /// 段顺序即优先级：画质/风格 → 目标时长 → 角色身份锚点 → 场景锚点 →
  /// 逐镜动作/台词 → 运镜 → 连续性绝对状态 → 片段级补充说明。
  ///
  /// [references] 非空时，角色与场景锚点位输出 `{{ref N}}` 编号；编号与该
  /// 列表一一对应。传入空列表表示调用方还没有准备好参考图——此时角色/场景
  /// 锚地只写文字描述，并在 [AssembledPrompt.missingReferences] 里列出缺口，
  /// 让调用方阻止生成（spec: 缺少参考图时不静默降级）。
  static AssembledPrompt buildSegmentPrompt(
    SegmentPromptParts parts, {
    List<SegmentReference> references = const [],
  }) {
    final positiveSegments = <String>[];
    final missing = <String>[];

    // 1. 画质与风格基线。
    positiveSegments.add(_qualityBaseline);
    final style = parts.styleTokens?.trim() ?? '';
    if (style.isNotEmpty) positiveSegments.add(style);

    // 2. 目标时长。写在前面让模型对覆盖范围有预期。
    final duration = parts.targetDurationSec;
    if (duration != null && duration > 0) {
      positiveSegments.add('continuous single take, total duration ${duration}s');
    }

    // 3. 角色身份锚点。同一角色在多镜出场只写一次（身份不随镜头变化），
    //    但参考图编号必须写——那是模型唯一能「看见」角色长什么样的途径。
    for (final character in parts.characters) {
      final anchor = _characterAnchor(character);
      if (anchor.isEmpty) continue;
      final refIndex = references.indexWhere(
        (r) => r.usage.contains(character.name.trim()),
      );
      if (refIndex >= 0) {
        positiveSegments.add('$anchor (reference {{ref ${refIndex + 1}}})');
      } else {
        positiveSegments.add(anchor);
        missing.add('${character.name.trim()} 角色参考图');
      }
    }

    // 4. 场景锚点。同理，场景图约束空间结构。
    for (final scene in parts.scenes) {
      final anchor = scene.promptEn.trim().isNotEmpty
          ? scene.promptEn.trim()
          : scene.name.trim();
      if (anchor.isEmpty) continue;
      final refIndex = references.indexWhere(
        (r) => r.usage.contains(scene.name.trim()),
      );
      if (refIndex >= 0) {
        positiveSegments.add('scene: $anchor (reference {{ref ${refIndex + 1}}})');
      } else {
        positiveSegments.add('scene: $anchor');
        missing.add('${scene.name.trim()} 场景参考图');
      }
    }

    // 5. 逐镜动作/台词。镜号保留原文编号，方便用户对照分镜看板排查。
    for (final shot in parts.shots) {
      final chunk = <String>['shot ${shot.number}'];
      final action = shot.actionZh.trim();
      if (action.isNotEmpty) chunk.add(action);
      final dialogue = shot.dialogue.trim();
      if (dialogue.isNotEmpty) chunk.add('dialogue: $dialogue');
      final move = shot.cameraMove.trim();
      if (move.isNotEmpty) chunk.add('camera: $move');
      positiveSegments.add(chunk.join(' | '));
    }

    // 6. 连续性绝对状态（钉住，不参与超限丢弃）。
    //
    //    位置在尾部附近，正是默认策略最先丢的地方；但丢它会直接产生穿帮。
    //    所以这一段用 pinnedCount 保护，见 _joinWithinLimit 的说明。
    final pinned = <String>[];
    for (final shot in parts.shots) {
      final token = ContinuityTokens.of(shot.continuity);
      if (token.isEmpty) continue;
      pinned.add('shot ${shot.number} state: $token');
    }

    // 7. 片段级补充说明（可牺牲）。
    final note = parts.promptNote?.trim() ?? '';
    if (note.isNotEmpty) positiveSegments.add(note);

    // 台账段追加在可牺牲段之后，并用 pinnedFrom 声明「从该下标起的所有段都
    // 不许丢」。台账拼在尾部，正是默认策略最先丢的位置。
    final positive = _joinWithinLimit(
      [...positiveSegments, ...pinned],
      kMaxPromptWords,
      pinnedFrom: positiveSegments.length,
    );

    return AssembledPrompt(
      positive: positive.text,
      negative: '',
      truncated: positive.truncated,
      droppedSegments: positive.dropped,
      missingReferences: missing,
    );
  }

  /// 角色卡 → 身份锚点段。
  ///
  /// 只写「不会随镜头变化的部分」：外貌与服装。表演、站位、情绪由逐镜段与
  /// 台账负责——把它们塞进身份锚点会让同一角色在不同片段里长出不同的脸。
  static String _characterAnchor(CharacterCard character) {
    final base = character.basePromptPositive.trim();
    if (base.isNotEmpty) return base;
    // 没写英文 Prompt 时退回中文描述：视频模型多数能读懂中文，比留空好。
    final zh = character.descriptionZh.trim();
    return zh.isNotEmpty ? zh : character.name.trim();
  }

  static List<String> _wordsOf(String text) => text
      .split(RegExp(r'[,\.\n;]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// 拼接并在超限时从尾部丢弃。
  ///
  /// [pinnedFrom] 指定**从该下标起**的段是钉住的（不进入丢弃候选）。
  ///
  /// **为什么需要这个参数**：默认策略是「超限从尾部丢」，这对风格词、运镜词
  /// 成立——丢了只是画面少点味道。但连续性台账的持物/位置状态不能丢：丢了
  /// 会直接产生穿帮（spec: 台账注入生成提示词）。片段提示词把台账段拼在
  /// 尾部，正是默认策略最先丢的位置，所以必须显式钉住。
  ///
  /// 语义是「[pinnedFrom, ∞) 区间内的段不许丢」，因此**不传该参数时全部段
  /// 都参与丢弃判定**——与 `buildShotPrompt` 改造前的行为完全一致。
  /// （曾经把默认值写成 0，那会让第 0 段也被钉住，是错的。）
  static _JoinResult _joinWithinLimit(
    List<String> segments,
    int limit, {
    int? pinnedFrom,
  }) {
    final kept = <String>[];
    final dropped = <String>[];
    var count = 0;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final words = _wordsOf(segment);
      if (words.isEmpty) continue;
      // `null` 表示没有钉住的段，全部参与丢弃判定。
      final pinned = pinnedFrom != null && i >= pinnedFrom;
      if (!pinned && count + words.length > limit) {
        dropped.add(segment);
        continue;
      }
      kept.add(segment);
      count += words.length;
    }
    return _JoinResult(
      text: kept.map((s) => s.trim()).where((s) => s.isNotEmpty).join(', '),
      truncated: dropped.isNotEmpty,
      dropped: dropped,
    );
  }
}

class _JoinResult {
  final String text;
  final bool truncated;
  final List<String> dropped;

  const _JoinResult({
    required this.text,
    required this.truncated,
    required this.dropped,
  });
}

/// 景别 → 英文摄影词。AI 拆镜给的是中文标签，Prompt 要英文。
abstract final class ShotSizeTokens {
  static String of(StudioShotSize size) => switch (size) {
    StudioShotSize.closeUp => 'close-up portrait',
    StudioShotSize.mediumCloseUp => 'medium close-up',
    StudioShotSize.medium => 'medium shot',
    StudioShotSize.full => 'full shot, wide cinematic view',
    StudioShotSize.long => 'long shot',
    StudioShotSize.extremeLong => 'extreme long shot, wide establishing view',
  };
}

/// 情绪 → 光线/氛围词。BGM 匹配也读同一批标签，但那边按 id 匹配文件名。
abstract final class MoodTokens {
  static String of(String moodId) => switch (moodId) {
    'depressing' => 'desaturated cold lighting, heavy shadows, gloomy atmosphere',
    'excited' => 'high contrast lighting, dynamic composition, energetic',
    'warm' => 'warm soft lighting, gentle atmosphere',
    'battle' => 'dramatic rim lighting, intense atmosphere, motion blur',
    'suspense' => 'low key lighting, deep shadows, tense atmosphere',
    'relaxed' => 'bright natural lighting, airy composition',
    'sad' => 'cool blue lighting, soft focus, melancholic atmosphere',
    _ => 'cinematic lighting',
  };
}

/// 分镜功能 → 构图提示。
abstract final class ShotFunctionTokens {
  static String of(ShotFunction function) => switch (function) {
    ShotFunction.opening => 'hook composition, subject centered, strong focal point',
    ShotFunction.advance => 'rule of thirds, leading lines',
    ShotFunction.burst => 'dutch angle, extreme perspective, high tension framing',
    ShotFunction.ending => 'balanced composition, lingering framing',
  };
}

/// 连续性台账 → 提示词段（spec: 台账注入生成提示词）。
///
/// 单独成类而不是塞进 [PromptAssembler] 的静态方法：它要被 `buildSegmentPrompt`
/// 与后续的单镜生图路径共用，且它的「什么算空」规则（见 [ShotContinuity.isEmpty]）
/// 值得被单独测试。
abstract final class ContinuityTokens {
  /// 把一台账翻成一段中文绝对状态描述。全空时返回空串。
  ///
  /// 逐字段拼而不是套模板：用户常常只填了其中一两项，模板会产出
  /// 「角色位于，左手持有」这种断句。空字段直接不出现，读起来才像正常描述。
  static String of(ShotContinuity continuity) {
    if (continuity.isEmpty) return '';
    final parts = <String>[];
    if (continuity.worldPosition.trim().isNotEmpty) {
      parts.add('角色位于${continuity.worldPosition.trim()}');
    }
    if (continuity.screenPosition.trim().isNotEmpty) {
      parts.add('画面中${continuity.screenPosition.trim()}');
    }
    if (continuity.holdingLeft.trim().isNotEmpty) {
      parts.add('左手持有${continuity.holdingLeft.trim()}');
    }
    if (continuity.holdingRight.trim().isNotEmpty) {
      parts.add('右手持有${continuity.holdingRight.trim()}');
    }
    if (continuity.lightingState.trim().isNotEmpty) {
      parts.add('光线${continuity.lightingState.trim()}');
    }
    for (final change in continuity.stateChanges) {
      final text = change.trim();
      if (text.isNotEmpty) parts.add('本镜$text');
    }
    return parts.join('，');
  }
}

/// 片段提示词的组装输入（spec: 片段提示词组装）。
///
/// 与 [PromptParts] 分开是因为两者的消费方不同：`PromptParts` 服务生图，
/// 关注单镜的画面构成；这里服务视频生成，关注「一段连续画面」的叙事与状态。
/// 共用的只有角色卡与场景卡——它们同源于 IP 主库，必须让两种产物看到同一张脸。
class SegmentPromptParts {
  /// 全局风格词。
  final String? styleTokens;

  /// 片段目标时长（秒）。写进提示词让模型知道要覆盖多长的连续动作。
  final int? targetDurationSec;

  /// 按分镜顺序的角色卡。同一角色在多镜出场只列一次，但保持首次出场顺序。
  final List<CharacterCard> characters;

  /// 按分镜顺序的场景卡。
  final List<SceneCard> scenes;

  /// 按分镜顺序的镜内信息。空列表表示没有任何分镜（不应发生，防御性处理）。
  final List<SegmentShotParts> shots;

  /// 片段级补充说明（`StudioSegment.promptNote`），追加在最末尾。
  final String? promptNote;

  const SegmentPromptParts({
    this.styleTokens,
    this.targetDurationSec,
    this.characters = const [],
    this.scenes = const [],
    this.shots = const [],
    this.promptNote,
  });
}

/// 片段内一个分镜的提示词输入。
class SegmentShotParts {
  final int number;

  /// 画面动作描述（中文）。
  final String actionZh;

  /// 台词或旁白（中文，可为空）。
  final String dialogue;

  /// 运镜关键词。
  final String cameraMove;

  /// 该镜的连续性台账。空台账的镜号会被跳过——那意味着用户还没补台账，
  /// 强行写「绝对状态」会写成空话。
  final ShotContinuity continuity;

  const SegmentShotParts({
    required this.number,
    this.actionZh = '',
    this.dialogue = '',
    this.cameraMove = '',
    this.continuity = ShotContinuity.empty,
  });
}

/// 片段提示词的参考图绑定（spec: 片段提示词组装的参考图编号要求）。
///
/// `{{ref N}}` 与真实文件的对应关系必须由调用方保管，提示词里只写编号。
/// 编号无法确认时 [PromptAssembler.buildSegmentPrompt] 不会瞎编，而是不输出
/// 编号并让调用方通过 [AssembledPrompt.missingReferences] 发现缺口。
class SegmentReference {
  /// 文件名或路径，仅用于错误信息与日志。
  final String label;

  /// 该参考图约束的身份/空间（如「林宁角色参考」「雨夜巷道场景参考」）。
  final String usage;

  const SegmentReference({required this.label, required this.usage});
}
