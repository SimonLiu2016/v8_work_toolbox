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

  const AssembledPrompt({
    required this.positive,
    required this.negative,
    this.truncated = false,
    this.droppedSegments = const [],
    this.appliedVariationName,
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
    }

    // 4. 场景。
    final scene = parts.scene;
    final scenePrompt = scene?.promptEn.trim() ?? '';
    if (scenePrompt.isNotEmpty) {
      positiveSegments.add(scenePrompt);
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

  static List<String> _wordsOf(String text) => text
      .split(RegExp(r'[,\.\n;]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// 拼接并在超限时从尾部丢弃。
  static _JoinResult _joinWithinLimit(List<String> segments, int limit) {
    final kept = <String>[];
    final dropped = <String>[];
    var count = 0;
    for (final segment in segments) {
      final words = _wordsOf(segment);
      if (words.isEmpty) continue;
      if (count + words.length > limit) {
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
