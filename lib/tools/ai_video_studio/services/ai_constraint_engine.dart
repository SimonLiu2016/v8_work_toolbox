/// AI 约束引擎：专项 System Prompt 模板库 + 强制 JSON Schema 解析。
///
/// 工坊里所有 AI 生成（拆镜、Prompt 翻译、创意孵化、标题、BGM 推荐）都走这里。
/// 设计决策见 design.md D2：
///
/// 1. **强制结构化输出**。非专业用户无法手动纠正 AI 的格式错误，而看板渲染、
///    SRT 对齐、Ducking 时序全都依赖结构化字段。所以返回文本必须按预定义
///    JSON Schema 解析，解析失败自动 retry。
/// 2. **不用 function calling / response_format**。现有 `AiService` 路由多家
///    提供商，DeepSeek / 智谱 GLM-Flash 这类免费模型并不都支持 structured
///    output API；Schema 约束写在 System Prompt 里对每家都成立。
/// 3. **retry 耗尽后保留原文**。失败时抛 [ConstraintParseError] 并带上 AI 的
///    原始输出，UI 层可以把它显示给用户手工取用，而不是只给一句"生成失败"。
library;

import 'dart:convert';

import '../../../services/ai_service.dart';
import '../models/studio_models.dart';
import 'studio_preset_store.dart';

/// 工坊的 AI 任务类型。
///
/// 每个类型对应一组 System Prompt 模板与一个 JSON Schema。新增任务时在这里
/// 加枚举值 + 模板 + schema 三件套，漏掉任何一个都会在运行时才暴露。
enum StudioAiTask {
  /// 粗剧情大纲 → 结构化分镜列表。
  scriptBreakdown('script_breakdown', 'AI 拆分分镜'),

  /// 五维导演拆镜（主体动势、光影、光学机位、时间演变、美学质感）。
  scriptBreakdown5D('script_breakdown_5d', '五维导演拆镜'),

  /// 动作专项编舞拆镜（Combat DNA、六步攻防链、3~4招连续攻击组）。
  actionCombatBreakdown('action_combat_breakdown', '动作编舞专项拆镜'),

  /// 中文角色描述 → 英文正/负向 Prompt。
  promptTranslation('prompt_translation', '生成 Prompt'),

  /// 模糊想法 → 3 个结构化故事方向。
  ideaIncubation('idea_incubation', '创意孵化'),

  /// 发布标题候选。
  titleGeneration('title_generation', '标题生成'),

  /// 情绪 → BGM 候选推荐。
  bgmRecommend('bgm_recommend', 'BGM 推荐'),

  /// 本集一句话摘要（跨集记忆库）。
  episodeSummary('episode_summary', '剧情摘要'),

  /// 单镜重新生成。
  shotRegenerate('shot_regenerate', '单镜重生成'),

  /// 小说全案第一阶段：提取世界观、风格词、角色卡与场景库。
  novelMasterExtraction('novel_master_extraction', '小说主库解构'),

  /// 小说全案第二阶段：基于剧情高潮检测与短剧节奏自动规划分集大纲。
  novelEpisodeSegmentation('novel_episode_segmentation', '小说高潮分集规划'),

  /// 单章小说影视化提炼：通读单章全量文本，输出覆盖起承转合的影视化单集大纲与记忆。
  novelChapterAdaptation('novel_chapter_adaptation', '单章小说影视化提炼'),

  /// 单章小说影视场次与保护清单深度提炼（含场次地标、主光源与不可变对白事实）。
  novelDramaChapterAdaptation('novel_drama_chapter_adaptation', '单章影视场次与保护清单提炼'),

  /// 故事大纲 → 影视分场文学剧本（场次、日夜、内外景、角色对白与微动作节拍）。
  screenplayGeneration('screenplay_generation', '影视分场剧本生成'),

  /// 场景七方位空间全息解构（前、后、左、右、上、下、俯视全景）。
  sceneSpatialDeconstruction('scene_spatial_deconstruction', '场景空间全息解构');

  final String id;
  final String label;

  const StudioAiTask(this.id, this.label);
}

/// JSON 解析重试用尽后的结构化异常。
///
/// 带上 [rawText] 是刻意的：用户至少能在 UI 上看到 AI 到底回了什么，而不是
/// 只有一句"失败"。spec: AI 输出结构化解析失败重试 里要求保留原始文本供查看。
class ConstraintParseError implements Exception {
  final StudioAiTask task;
  final String rawText;
  final int attempts;
  final Object? lastError;

  const ConstraintParseError({
    required this.task,
    required this.rawText,
    required this.attempts,
    this.lastError,
  });

  @override
  String toString() =>
      'ConstraintParseError(${task.id}): $attempts 次尝试后仍无法解析为合法 '
      'JSON。AI 原始输出已保留，长度 ${rawText.length} 字符。';
}

/// 一次约束化 AI 调用的结果。
class ConstraintResult {
  /// 解析后的 JSON（已通过 schema 校验）。
  final Map<String, dynamic> data;

  /// AI 原始输出文本。
  final String rawText;

  /// 实际使用的供应商与模型（透传自 `AiService.chat`）。
  final String providerId;
  final String model;

  /// 第几次尝试成功（1 = 一次到位）。
  final int attempt;

  const ConstraintResult({
    required this.data,
    required this.rawText,
    required this.providerId,
    required this.model,
    required this.attempt,
  });
}

/// 剧情记忆上下文（跨集连贯性注入，spec: 上下集剧情连贯性检查）。
class ScriptContext {
  /// 剧集名称。
  final String seriesName;

  /// 制作类型 id（`drama` / `anime` / `narration` / `anime3d`）。
  final String productionType;

  /// 全局风格词。
  final String styleTokens;

  /// 前情摘要 + 上集末尾钩子（已拼接好的文本，可为空）。
  final String memoryContext;

  /// 当前集序号。
  final int episodeIndex;

  /// 可用角色名列表（AI 拆镜时引用，避免编出不存在的角色）。
  final List<String> characterNames;

  /// 可用场景名列表。
  final List<String> sceneNames;

  /// 上一集末镜的连续性台账文本（spec: 新集首镜自动承接上集状态）。
  final String carryOverState;

  /// 戏剧场次列表（用于指导场景主光、空间固定地标与节拍进出）。
  final List<DramaScene> scenes;

  /// 事实与对白保护清单（核心原著台词与剧情因果硬事实）。
  final ProtectedContract protectedContract;

  /// 参战角色 Combat DNA（打斗与动作场景动作风格指导）。
  final List<CombatDNA> combatDnaList;

  const ScriptContext({
    this.seriesName = '',
    this.productionType = 'drama',
    this.styleTokens = '',
    this.memoryContext = '',
    this.episodeIndex = 1,
    this.characterNames = const [],
    this.sceneNames = const [],
    this.carryOverState = '',
    this.scenes = const [],
    this.protectedContract = ProtectedContract.empty,
    this.combatDnaList = const [],
  });
}

/// chat 后端签名。测试用它替换真实网络调用。
typedef StudioChatFn = Future<ChatResult> Function({
  required List<Map<String, String>> messages,
  String slot,
  String? explicitProviderId,
  String? explicitModel,
  Duration? timeout,
  bool ignoreCooldown,
});

abstract final class AiConstraintEngine {
  /// 默认最大重试次数（spec: 最多 3 次）。
  static const int maxAttempts = 3;

  /// 供测试替换的 chat 后端。生产中始终是 [AiService.instance.chat]。
  static StudioChatFn chatFn = _defaultChat;

  static Future<ChatResult> _defaultChat({
    String slot = 'text',
    String? explicitProviderId,
    String? explicitModel,
    required List<Map<String, String>> messages,
    Duration? timeout,
    bool ignoreCooldown = false,
  }) {
    return AiService.instance.chat(
      slot: slot,
      explicitProviderId: explicitProviderId,
      explicitModel: explicitModel,
      messages: messages,
      timeout: timeout,
      ignoreCooldown: ignoreCooldown,
    );
  }

  /// 测试用：恢复真实后端。
  static void resetForTesting() {
    chatFn = _defaultChat;
  }

  /// 根据任务类型返回合理的超时时间。
  static Duration defaultTimeoutFor(StudioAiTask task) {
    switch (task) {
      case StudioAiTask.novelMasterExtraction:
      case StudioAiTask.novelEpisodeSegmentation:
      case StudioAiTask.novelChapterAdaptation:
      case StudioAiTask.novelDramaChapterAdaptation:
      case StudioAiTask.screenplayGeneration:
      case StudioAiTask.scriptBreakdown5D:
      case StudioAiTask.actionCombatBreakdown:
        return const Duration(seconds: 240);
      case StudioAiTask.sceneSpatialDeconstruction:
        return const Duration(seconds: 180);
      default:
        return const Duration(seconds: 120);
    }
  }

  /// 执行一次约束化调用：注入模板 → 解析 → 失败重试。
  ///
  /// [schemaValidator] 由调用方按任务类型给出（见 [_SchemaValidators]），
  /// 因为每种任务要校验的字段完全不同。校验失败与 JSON 解析失败同样重试——
  /// AI 经常回一个语法合法但缺字段的 JSON，那对下游一样没用。
  static Future<ConstraintResult> run({
    required StudioAiTask task,
    required String userPrompt,
    Map<String, dynamic>? Function(Map<String, dynamic>)? schemaValidator,
    String slot = 'text',
    Duration? timeout,
    int maxAttempts = maxAttempts,
  }) async {
    final effectiveTimeout = timeout ?? defaultTimeoutFor(task);
    final systemPrompt = systemPromptFor(task);
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    String lastRaw = '';
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      ChatResult result;
      try {
        // 前几次失败时把原始输出回给模型，让它知道错在哪——盲目重发同样的
        // 提示词，第二次往往拿到同一份坏 JSON。
        final retryHint = attempt > 1 && lastRaw.isNotEmpty
            ? '\n\n【上一次你的输出无法解析】\n$lastRaw\n\n'
                '请严格按上述 JSON Schema 重新输出，不要输出任何解释文字。'
            : '';
        result = await chatFn(
          slot: slot,
          messages: [
            ...messages,
            if (retryHint.isNotEmpty) {'role': 'user', 'content': retryHint},
          ],
          timeout: effectiveTimeout,
        );
      } catch (e) {
        // 网络/供应商错误不重试：那是路由层的事，重发只会让用户多等。
        rethrow;
      }

      lastRaw = result.text;
      final parsed = parseJsonLoose(result.text);
      if (parsed != null) {
        final validated = schemaValidator?.call(parsed);
        if (schemaValidator == null || validated != null) {
          return ConstraintResult(
            data: validated ?? parsed,
            rawText: result.text,
            providerId: result.usedProviderId,
            model: result.usedModel,
            attempt: attempt,
          );
        }
        lastError = StateError('JSON 字段不符合预期 Schema');
      } else {
        lastError = const FormatException('输出不是合法 JSON');
      }
    }

    throw ConstraintParseError(
      task: task,
      rawText: lastRaw,
      attempts: maxAttempts,
      lastError: lastError,
    );
  }

  // ---------------------------------------------------------------------------
  // 各任务的便捷入口
  // ---------------------------------------------------------------------------

  /// 创意孵化：模糊想法 → 3 个故事方向。支持全剧主线孵化与单集续写扩写。
  static Future<ConstraintResult> ideaIncubation({
    required String rawIdea,
    required String productionTypeLabel,
    String seriesName = '',
    String worldview = '',
    String existingEpisodesContext = '',
    int? targetEpisodeIndex,
  }) {
    final buffer = StringBuffer()
      ..writeln('【制作类型】$productionTypeLabel');
    if (seriesName.trim().isNotEmpty) {
      buffer.writeln('【剧集名称】${seriesName.trim()}');
    }
    if (worldview.trim().isNotEmpty) {
      buffer.writeln('【已有世界观设定】\n${worldview.trim()}');
    }
    if (existingEpisodesContext.trim().isNotEmpty) {
      buffer.writeln('【已有前情上下文与剧情脉络】\n${existingEpisodesContext.trim()}');
    }
    if (targetEpisodeIndex != null) {
      buffer.writeln('【本次孵化目标】承接已有剧情，设计第 $targetEpisodeIndex 集的剧情走向与高潮钩子');
    }
    buffer.writeln('【用户的想法或指示】\n$rawIdea');

    return run(
      task: StudioAiTask.ideaIncubation,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.ideaIncubation,
    );
  }

  /// 粗剧情大纲 → 片段化分镜列表。
  ///
  /// [context.carryOverState] 非空时，把上一集末镜的连续性台账作为本集首镜的
  /// **既定初始状态**注入（spec: 新集首镜自动承接上集状态）。注意措辞是
  /// 「既定初始状态」而不是「请据此推导」——后者会诱导 AI 补前史。
  static Future<ConstraintResult> scriptBreakdown({
    required String synopsis,
    required ScriptContext context,
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】${context.seriesName}')
      ..writeln('【制作类型】${context.productionType}')
      ..writeln('【当前集序号】第 ${context.episodeIndex} 集');
    if (context.styleTokens.trim().isNotEmpty) {
      buffer.writeln('【全局风格词】${context.styleTokens.trim()}');
    }
    if (context.memoryContext.trim().isNotEmpty) {
      buffer.writeln('【跨集记忆】\n${context.memoryContext.trim()}');
    }
    if (context.carryOverState.trim().isNotEmpty) {
      buffer.writeln('【上一集末镜状态（本集首镜的既定初始状态，直接沿用，不得推导其来源）】'
          '\n${context.carryOverState.trim()}');
    }
    if (context.characterNames.isNotEmpty) {
      buffer.writeln('【可用角色】${context.characterNames.join('、')}');
    }
    if (context.sceneNames.isNotEmpty) {
      buffer.writeln('【可用场景】${context.sceneNames.join('、')}');
    }
    buffer.writeln('【本集粗剧情大纲】\n$synopsis');
    return run(
      task: StudioAiTask.scriptBreakdown,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.scriptBreakdown,
    );
  }

  /// 五维导演拆解：粗剧情大纲 + 场次规划 + 保护清单 → 具备专业视听与五维导演决策的结构化分镜。
  static Future<ConstraintResult> scriptBreakdown5D({
    required String synopsis,
    required ScriptContext context,
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】${context.seriesName}')
      ..writeln('【制作类型】${context.productionType}')
      ..writeln('【当前集序号】第 ${context.episodeIndex} 集');
    if (context.styleTokens.trim().isNotEmpty) {
      buffer.writeln('【全局风格词】${context.styleTokens.trim()}');
    }
    if (context.memoryContext.trim().isNotEmpty) {
      buffer.writeln('【跨集记忆】\n${context.memoryContext.trim()}');
    }
    if (context.carryOverState.trim().isNotEmpty) {
      buffer.writeln('【上一集末镜状态（本集首镜既定初始状态，直接沿用）】\n${context.carryOverState.trim()}');
    }
    if (context.characterNames.isNotEmpty) {
      buffer.writeln('【可用角色】${context.characterNames.join('、')}');
    }
    if (context.sceneNames.isNotEmpty) {
      buffer.writeln('【可用场景】${context.sceneNames.join('、')}');
    }
    if (context.scenes.isNotEmpty) {
      buffer.writeln('【场次规划与节拍（Scenes & Beats）】');
      for (final s in context.scenes) {
        buffer.writeln('- 场次 ${s.id} (${s.title}): ${s.location}, 主光=${s.primaryLightWorldDirection}, 地标=${s.landmarks.join("/")}');
        for (final b in s.beats) {
          buffer.writeln('  * 节拍 ${b.id}: [${b.dramaticFunction}] ${b.name} - ${b.action}');
        }
      }
    }
    if (context.protectedContract.isNotEmpty) {
      buffer.writeln('【基准事实与对白保护清单（禁止篡改与丢失）】');
      if (context.protectedContract.facts.isNotEmpty) {
        buffer.writeln('核心事实：');
        for (final f in context.protectedContract.facts) {
          buffer.writeln('- [${f.type.code}] ${f.content}');
        }
      }
      if (context.protectedContract.utterances.isNotEmpty) {
        buffer.writeln('基准对白列表：');
        for (final u in context.protectedContract.utterances) {
          buffer.writeln('- ${u.speaker}对${u.listener.isEmpty ? "众人" : u.listener}说: "${u.text}" (${u.estimatedSec}秒)');
        }
      }
    }
    buffer.writeln('【本集剧情大纲】\n$synopsis');
    return run(
      task: StudioAiTask.scriptBreakdown5D,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.scriptBreakdown,
    );
  }

  /// 动作与战斗编舞专项拆镜：基于 Combat DNA 展开六步攻防因果链与连续攻击组拆镜。
  static Future<ConstraintResult> actionCombatBreakdown({
    required String synopsis,
    required ScriptContext context,
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】${context.seriesName}')
      ..writeln('【制作类型】${context.productionType}')
      ..writeln('【打斗场景与参战角色】${context.characterNames.join('、')}');
    if (context.combatDnaList.isNotEmpty) {
      buffer.writeln('【参战角色 Combat DNA 设定】');
      for (final dna in context.combatDnaList) {
        buffer.writeln('- 角色【${dna.characterName}】: 体量量级=${dna.weightClass}, 敏捷速度=${dna.speedAgility}, 惯用交手距离=${dna.preferredDistance}, 兵刃配装=${dna.weapon}, 防守风格=${dna.defenseStyle}, 反击倾向=${dna.counterPreference}');
      }
    }
    if (context.scenes.isNotEmpty) {
      buffer.writeln('【战斗发生场次与地标障碍】');
      for (final s in context.scenes) {
        buffer.writeln('- 场次 ${s.id} (${s.title}): 主光=${s.primaryLightWorldDirection}, 地标障碍=${s.landmarks.join("/")}');
      }
    }
    buffer.writeln('【战斗情节大纲与攻防重点】\n$synopsis');
    return run(
      task: StudioAiTask.actionCombatBreakdown,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.scriptBreakdown,
    );
  }

  /// 单镜重新生成：只重写一个分镜。
  ///
  /// [segmentContext] 非空时注入所属片段的目标时长与该镜的台账，让 AI 知道
  /// 这一镜在一段连续画面里的位置（spec: 单镜重生成不新增桥接动作）。
  static Future<ConstraintResult> shotRegenerate({
    required String currentShotJson,
    required String instruction,
    required ScriptContext context,
    String segmentContext = '',
  }) {
    final segmentBlock = segmentContext.trim().isEmpty
        ? ''
        : '【所属片段上下文】\n$segmentContext\n\n';
    return run(
      task: StudioAiTask.shotRegenerate,
      userPrompt:
          '【剧集名称】${context.seriesName}\n'
          '【制作类型】${context.productionType}\n'
          '$segmentBlock'
          '【当前分镜 JSON】\n$currentShotJson\n\n'
          '【用户的修改要求】\n$instruction',
      schemaValidator: _SchemaValidators.shotRegenerate,
    );
  }

  /// 中文角色描述 → 英文正/负向 Prompt。
  static Future<ConstraintResult> promptTranslation({
    required String descriptionZh,
    required String productionType,
    String worldview = '',
    String eraGenre = '',
    String negativeHint = '',
  }) {
    final era = VisualEraGenre.fromId(eraGenre);
    final buffer = StringBuffer();
    buffer.writeln('【制作类型】$productionType');
    if (era != null) {
      buffer.writeln('【时代题材】${era.labelZh} (${era.id})');
    }
    if (worldview.trim().isNotEmpty) {
      buffer.writeln('【世界观背景】${worldview.trim()}');
    }
    buffer.writeln('【角色中文描述】\n$descriptionZh');
    if (negativeHint.trim().isNotEmpty) {
      buffer.writeln('【额外负向要求】$negativeHint');
    }
    return run(
      task: StudioAiTask.promptTranslation,
      userPrompt: buffer.toString().trim(),
      schemaValidator: _SchemaValidators.promptTranslation,
    );
  }

  /// 发布标题候选。
  static Future<ConstraintResult> titleGeneration({
    required String seriesName,
    required String productionType,
    required String episodeSummary,
    String hook = '',
  }) {
    return run(
      task: StudioAiTask.titleGeneration,
      userPrompt:
          '【剧集名称】$seriesName\n'
          '【制作类型】$productionType\n'
          '【本集剧情摘要】$episodeSummary'
          '${hook.trim().isEmpty ? '' : '\n【本集末尾钩子】$hook'}',
      schemaValidator: _SchemaValidators.titleGeneration,
    );
  }

  /// 情绪 → BGM 候选。
  static Future<ConstraintResult> bgmRecommend({
    required String moodLabel,
    required String productionType,
    required List<String> availableTracks,
  }) {
    return run(
      task: StudioAiTask.bgmRecommend,
      userPrompt:
          '【制作类型】$productionType\n'
          '【分镜情绪基调】$moodLabel\n'
          '【可选 BGM 列表】\n${availableTracks.map((t) => '- $t').join('\n')}',
      schemaValidator: _SchemaValidators.bgmRecommend,
    );
  }

  /// 本集一句话摘要（写进跨集记忆库）。
  static Future<ConstraintResult> episodeSummary({
    required String synopsis,
    required String shotsSummary,
    int maxChars = 200,
  }) {
    return run(
      task: StudioAiTask.episodeSummary,
      userPrompt:
          '【本集粗剧情】\n$synopsis\n\n'
          '【本集分镜要点】\n$shotsSummary\n\n'
          '请输出不超过 $maxChars 字的剧情摘要，以及本集末尾的悬念钩子。',
      schemaValidator: _SchemaValidators.episodeSummary,
    );
  }

  /// 小说全案第一阶段：提取世界观、风格词、角色卡库与场景库。
  static Future<ConstraintResult> extractNovelMaster({
    required String novelText,
    String productionType = 'drama',
  }) {
    final cleanText = novelText.length > 35000
        ? '${novelText.substring(0, 20000)}\n\n[...中间精彩章节省略...]\n\n${novelText.substring(novelText.length - 15000)}'
        : novelText;
    return run(
      task: StudioAiTask.novelMasterExtraction,
      userPrompt: '【制作类型】$productionType\n【小说原著内容】\n$cleanText',
      schemaValidator: _SchemaValidators.novelMasterExtraction,
    );
  }

  /// 小说全案第二阶段：基于剧情高潮检测与网文短剧节奏，自动规划分集大纲与前情链。
  static Future<ConstraintResult> segmentNovelEpisodes({
    required String novelText,
    required String worldview,
    required List<String> characterNames,
    String productionType = 'drama',
  }) {
    final cleanText = novelText.length > 35000
        ? '${novelText.substring(0, 20000)}\n\n[...中间精彩章节省略...]\n\n${novelText.substring(novelText.length - 15000)}'
        : novelText;
    final buffer = StringBuffer()
      ..writeln('【制作类型】$productionType')
      ..writeln('【已提炼世界观】\n$worldview');
    if (characterNames.isNotEmpty) {
      buffer.writeln('【核心登场角色】${characterNames.join('、')}');
    }
    buffer.writeln('【小说剧情主线】\n$cleanText');
    return run(
      task: StudioAiTask.novelEpisodeSegmentation,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.novelEpisodeSegmentation,
    );
  }

  /// 单章小说影视化提炼：通读单章全量文本，输出覆盖起承转合的影视化单集大纲与记忆。
  static Future<ConstraintResult> adaptNovelChapter({
    required String novelText,
    required String seriesName,
    String worldview = '',
    List<String> characterNames = const [],
    String productionType = 'drama',
    int episodeIndex = 1,
    String memoryContext = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【制作类型】$productionType')
      ..writeln('【目标集数】第 $episodeIndex 集');
    if (worldview.isNotEmpty) {
      buffer.writeln('【世界观设定】\n$worldview');
    }
    if (characterNames.isNotEmpty) {
      buffer.writeln('【核心可用角色】${characterNames.join('、')}');
    }
    if (memoryContext.isNotEmpty) {
      buffer.writeln('【前情记忆】\n$memoryContext');
    }
    buffer.writeln('【小说本章完整文本】\n$novelText');

    return run(
      task: StudioAiTask.novelChapterAdaptation,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.novelChapterAdaptation,
    );
  }

  /// 单章小说深度影视化改编：通读单章全文，输出包含四阶段大纲、场次规划与事实对白保护清单的完整剧本资产。
  static Future<ConstraintResult> adaptNovelDramaChapter({
    required String novelText,
    required String seriesName,
    String worldview = '',
    List<String> characterNames = const [],
    String productionType = 'drama',
    int episodeIndex = 1,
    String memoryContext = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【制作类型】$productionType')
      ..writeln('【目标集数】第 $episodeIndex 集');
    if (worldview.isNotEmpty) {
      buffer.writeln('【世界观设定】\n$worldview');
    }
    if (characterNames.isNotEmpty) {
      buffer.writeln('【核心可用角色】${characterNames.join('、')}');
    }
    if (memoryContext.isNotEmpty) {
      buffer.writeln('【前情记忆】\n$memoryContext');
    }
    buffer.writeln('【小说本章完整文本】\n$novelText');

    return run(
      task: StudioAiTask.novelDramaChapterAdaptation,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.novelChapterAdaptation,
    );
  }

  /// 故事大纲/小说章节 → 影视分场文学剧本（场次、日夜、内外景、角色对白与微动作节拍）。
  static Future<ConstraintResult> screenplayGeneration({
    required String synopsis,
    List<String> characterNames = const [],
    String seriesName = '',
    String productionType = 'drama',
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【制作类型】$productionType');
    if (characterNames.isNotEmpty) {
      buffer.writeln('【出场角色】${characterNames.join('、')}');
    }
    buffer.writeln('【剧情大纲】\n$synopsis');

    return run(
      task: StudioAiTask.screenplayGeneration,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.screenplayGeneration,
    );
  }

  /// 场景七方位空间全息推演（前、后、左、右、上、下、俯视全景）。
  static Future<ConstraintResult> deconstructSceneSpatialProfile({
    required String sceneName,
    required String baseDescription,
    String eraGenre = '',
    String visualStyle = '',
    String productionType = 'drama',
  }) {
    final buffer = StringBuffer()
      ..writeln('【场景名称】$sceneName');
    if (eraGenre.isNotEmpty) {
      buffer.writeln('【世界观时代题材】$eraGenre');
    }
    if (visualStyle.isNotEmpty) {
      buffer.writeln('【视觉与材质风格】$visualStyle');
    }
    buffer.writeln('【制作类型】$productionType');
    buffer.writeln('【小说原著/基础环境描述】\n$baseDescription');

    return run(
      task: StudioAiTask.sceneSpatialDeconstruction,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.sceneSpatialDeconstruction,
    );
  }

  /// 将 AI 空间解构返回的数据安全转换为覆盖 7 个维度的完整视图映射。
  static Map<String, SceneDirectionalView> parseSpatialViewsFromResult(
    Map<String, dynamic> data, {
    SceneCard? baseScene,
  }) {
    final rawViews = data['views'] as Map? ?? data;
    final result = <String, SceneDirectionalView>{};

    for (final dir in SceneDirection.values) {
      final entry = rawViews[dir.name] ?? rawViews[dir.key];
      if (entry is Map) {
        final viewMap = entry.map((k, v) => MapEntry(k.toString(), v));
        result[dir.name] = SceneDirectionalView.fromJson(viewMap, dir);
      } else if (baseScene != null) {
        final existing = baseScene.viewFor(dir);
        result[dir.name] = existing;
      } else {
        result[dir.name] = SceneDirectionalView(direction: dir);
      }
    }
    return result;
  }

  /// 根据台词字数与动作复杂度动态计算合理时长（秒，4.0~12.0）。
  static double calculateDynamicDurationSec({
    required String dialogue,
    String actionZh = '',
    double defaultSec = 4.0,
  }) {
    final cleanText = dialogue.replaceAll(RegExp(r'[（\(][^）\)]*[）\)]'), '').trim();
    if (cleanText.isEmpty) {
      if (actionZh.length > 35) return 5.0;
      return defaultSec.clamp(4.0, 12.0);
    }
    // 台词基础时长（4~5 字/秒，加上起承转合停顿与气口余量）
    final dialogueSec = (cleanText.length / 4.5) + 1.2;
    final actionPadding = actionZh.length > 30 ? 1.0 : 0.5;
    final total = (dialogueSec + actionPadding).roundToDouble();
    return total.clamp(4.0, 12.0);
  }

  /// 检测单镜头画面动作是否堆叠了过载的连续复合动作。
  static bool isActionOverloaded(String actionZh) {
    if (actionZh.trim().isEmpty) return false;
    final compositeVerbs = [
      '撕', '嚼', '吃', '咽', '挑', '指', '拔', '刺', '劈', '砍',
      '甩', '掷', '翻滚', '跃起', '砸', '踹', '撞', '拔刀', '抬刀'
    ];
    int count = 0;
    for (final verb in compositeVerbs) {
      if (actionZh.contains(verb)) {
        count++;
      }
    }
    return count >= 3 || actionZh.length > 55;
  }

  /// 智能解析与绑定剧本场次对应的真实 IP 场景库卡片 ID (SceneCard.id)。
  /// 采用多层渐进评分规则：显式卡片ID -> 全称归一匹配 -> 子串包含 -> 核心词根分词打分 -> 地标与环境描述加权。
  /// 若未能匹配到任何置信度足够高的场景卡，返回空字符串（绝不回退为 SC001 这类场次 ID）。
  static String resolveSceneCardId(
    DramaScene scene,
    List<SceneCard> sceneCards,
  ) {
    if (sceneCards.isEmpty) return '';

    // 1. 显式 ID 绑定优先（用户在剧本阶段手动选定，或导入时已关联）
    if (scene.sceneCardId.isNotEmpty) {
      final explicit = sceneCards.where((sc) => sc.id == scene.sceneCardId).firstOrNull;
      if (explicit != null) return explicit.id;
    }

    // 2. 尝试比对场景卡与场次原始 ID（例如直接传了 card.id 作为场次 id）
    final idMatch = sceneCards.where((sc) => sc.id == scene.id).firstOrNull;
    if (idMatch != null) return idMatch.id;

    // 清洗影视修饰前缀与标点符号
    String cleanText(String input) {
      return input
          .replaceAll(RegExp(r'^(内景|外景|日景|夜景|黄昏|黎明)[·\s]*'), '')
          .replaceAll(RegExp(r'[·，。、！？\(\)（）\s]'), '')
          .trim();
    }

    final locRaw = scene.location.trim();
    final titleRaw = scene.title.trim();
    final cleanLoc = cleanText(locRaw);
    final cleanTitle = cleanText(titleRaw);

    // 3. 全称与清洗后的精准全等匹配
    for (final sc in sceneCards) {
      final scName = sc.name.trim();
      final cleanScName = cleanText(scName);
      if (scName.isNotEmpty && (scName == locRaw || scName == titleRaw)) {
        return sc.id;
      }
      if (cleanScName.isNotEmpty && (cleanScName == cleanLoc || cleanScName == cleanTitle)) {
        return sc.id;
      }
    }

    // 4. 双向全子串匹配
    for (final sc in sceneCards) {
      final scName = sc.name.trim();
      final cleanScName = cleanText(scName);
      if (scName.isNotEmpty) {
        if ((locRaw.isNotEmpty && (locRaw.contains(scName) || scName.contains(locRaw))) ||
            (titleRaw.isNotEmpty && (titleRaw.contains(scName) || scName.contains(titleRaw)))) {
          return sc.id;
        }
      }
      if (cleanScName.isNotEmpty) {
        if ((cleanLoc.isNotEmpty && (cleanLoc.contains(cleanScName) || cleanScName.contains(cleanLoc))) ||
            (cleanTitle.isNotEmpty && (cleanTitle.contains(cleanScName) || cleanScName.contains(cleanTitle)))) {
          return sc.id;
        }
      }
    }

    // 5. 核心词根分词加权打分匹配 (Token Overlap Scoring)
    List<String> extractTokens(String text) {
      final cleaned = cleanText(text);
      final tokens = <String>{};
      final len = cleaned.length;
      if (len >= 2) {
        for (int window = 2; window <= 4 && window <= len; window++) {
          for (int i = 0; i <= len - window; i++) {
            tokens.add(cleaned.substring(i, i + window));
          }
        }
      }
      return tokens.toList();
    }

    SceneCard? bestCandidate;
    int maxScore = 0;

    final locTokens = extractTokens(locRaw);
    final scopeText = '$locRaw $titleRaw ${scene.landmarks.join(' ')} ${scene.atmosphere}';

    for (final sc in sceneCards) {
      int score = 0;
      final cardTokens = extractTokens(sc.name);

      // 卡片名词根命中剧本地点/标题
      for (final t in cardTokens) {
        if (locRaw.contains(t)) {
          score += t.length * 100;
        } else if (titleRaw.contains(t)) {
          score += t.length * 70;
        } else if (scopeText.contains(t)) {
          score += t.length * 40;
        }
      }

      // 剧本地点分词命中卡片名称或卡片中文描述
      final desc = sc.descriptionZh;
      for (final lt in locTokens) {
        if (sc.name.contains(lt)) {
          score += lt.length * 80;
        } else if (desc.contains(lt)) {
          score += lt.length * 30;
        }
      }

      // 场景地标命中
      for (final lm in scene.landmarks) {
        if (lm.trim().isNotEmpty && (sc.name.contains(lm.trim()) || desc.contains(lm.trim()))) {
          score += 150;
        }
      }

      if (score > maxScore) {
        maxScore = score;
        bestCandidate = sc;
      }
    }

    // 设定有效匹配的阈值分数（至少匹配一个 2 字以上核心地名词根）
    if (bestCandidate != null && maxScore >= 180) {
      return bestCandidate.id;
    }

    // 匹配失败返回空，严禁回退为 scene.id（杜绝 SC001 混入场景卡 ID）
    return '';
  }

  /// 将结构化分场与节拍列表转换为标准的 5D 分镜列表。
  static List<StudioShot> convertScenesToShots(
    List<DramaScene> scenes, {
    List<CharacterCard> characters = const [],
    List<SceneCard> sceneCards = const [],
  }) {
    final newShots = <StudioShot>[];
    int shotNumber = 1;

    for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
      final scene = scenes[sceneIdx];
      final segId = 'seg-${sceneIdx + 1}';

      // 解析与绑定真实 IP 场景库卡片 (SceneCard)
      final resolvedSceneId = resolveSceneCardId(scene, sceneCards);

      for (int beatIdx = 0; beatIdx < scene.beats.length; beatIdx++) {
        final beat = scene.beats[beatIdx];

        // 解析出场角色（多层智能匹配：名字全称、说话人、别名列表、中文昵称启发式）
        final charIds = <String>{...beat.characterIds};
        final textScope = '${beat.dialogueSpeaker} ${beat.action} ${beat.dialogue}';

        for (final c in characters) {
          bool matched = false;
          if (c.name.isNotEmpty && textScope.contains(c.name)) {
            matched = true;
          }
          if (!matched && beat.dialogueSpeaker.isNotEmpty) {
            if (c.name.contains(beat.dialogueSpeaker) || beat.dialogueSpeaker.contains(c.name)) {
              matched = true;
            }
          }
          if (!matched) {
            for (final alias in c.aliases) {
              if (alias.trim().isNotEmpty && textScope.contains(alias.trim())) {
                matched = true;
                break;
              }
            }
          }
          if (!matched && c.name.length >= 2) {
            final name = c.name;
            final candidates = <String>{};
            if (name.length == 3) {
              candidates.add('${name.substring(0, 2)}少');
              candidates.add('${name[1]}少');
              candidates.add(name.substring(1));
              candidates.add('${name[0]}少');
            } else if (name.length == 2) {
              candidates.add('${name[0]}少');
              candidates.add('${name[1]}儿');
            }
            for (final cand in candidates) {
              if (textScope.contains(cand)) {
                matched = true;
                break;
              }
            }
          }

          if (matched) {
            charIds.add(c.id);
          }
        }

        // 计算动态时长（4.0 ~ 12.0s）
        final isOverloaded = isActionOverloaded(beat.action);
        final dynamicDuration = calculateDynamicDurationSec(
          dialogue: beat.dialogue,
          actionZh: beat.action,
          defaultSec: isOverloaded ? 6.0 : 4.0,
        );

        // 景别推导：优先读取 AI 导演决策，未指定时自适应
        final StudioShotSize shotSize;
        if (beat.shotSize.trim().isNotEmpty) {
          shotSize = StudioShotSize.fromId(beat.shotSize);
        } else if (beat.dialogue.trim().length > 15) {
          shotSize = StudioShotSize.mediumCloseUp;
        } else if (beat.action.length > 30) {
          shotSize = StudioShotSize.full;
        } else {
          shotSize = StudioShotSize.medium;
        }

        // 功能位推导
        final ShotFunction function;
        if (beatIdx == 0 && sceneIdx == 0) {
          function = ShotFunction.opening;
        } else if (beatIdx == scene.beats.length - 1 && sceneIdx == scenes.length - 1) {
          function = ShotFunction.ending;
        } else if (isOverloaded ||
            beat.action.contains('杀') ||
            beat.action.contains('击') ||
            beat.action.contains('爆')) {
          function = ShotFunction.burst;
        } else {
          function = ShotFunction.advance;
        }

        // 规范化台词：如果是内心独白（inner_voice）或者台词本身标有 OS，统一格式化为“角色（内心 OS）：内容”
        final isInnerVoice = beat.voiceType == UtteranceVoiceType.innerVoice ||
            beat.dialogue.contains('内心 OS') ||
            beat.dialogue.contains('内心OS') ||
            beat.dialogue.contains('（OS）') ||
            beat.dialogue.contains('(OS)') ||
            beat.dialogue.contains('心声');

        final UtteranceVoiceType resolvedVoiceType;
        if (isInnerVoice) {
          resolvedVoiceType = UtteranceVoiceType.innerVoice;
        } else if (beat.voiceType == UtteranceVoiceType.narration) {
          resolvedVoiceType = UtteranceVoiceType.narration;
        } else {
          resolvedVoiceType = UtteranceVoiceType.dialogue;
        }

        final String dialogueFormatted;
        if (beat.dialogue.trim().isNotEmpty) {
          final cleanD = beat.dialogue.trim();
          if (isInnerVoice) {
            // 剥离可能已存在的重复 OS 标记，保持统一格式
            final stripped = cleanD
                .replaceAll(RegExp(r'^[（\(]?内心\s*OS[）\)]?[：:]?'), '')
                .replaceAll(RegExp(r'^[（\(]?OS[）\)]?[：:]?'), '')
                .trim();
            dialogueFormatted = beat.dialogueSpeaker.isNotEmpty
                ? '${beat.dialogueSpeaker}（内心 OS）：$stripped'
                : '（内心 OS）：$stripped';
          } else {
            dialogueFormatted = beat.dialogueSpeaker.isNotEmpty
                ? '${beat.dialogueSpeaker}：“$cleanD”'
                : cleanD;
          }
        } else {
          dialogueFormatted = '';
        }

        // 提取 AI 推导的机位、运镜、构图与视线，无损透传；若为空则基于剧本动作与景别做自适应推导
        final resolvedCameraMove = beat.cameraMove.trim().isNotEmpty
            ? beat.cameraMove.trim()
            : (isOverloaded || beat.action.contains('杀') || beat.action.contains('击')
                ? 'handheld_follow'
                : (shotSize == StudioShotSize.closeUp
                    ? 'slow_push_in'
                    : (shotSize == StudioShotSize.long || shotSize == StudioShotSize.extremeLong
                        ? 'slow_pull_out'
                        : 'slow_pan')));

        final resolvedCameraStaging = beat.cameraStaging.trim().isNotEmpty
            ? beat.cameraStaging.trim()
            : (beat.action.contains('三楼') || beat.action.contains('楼上') || beat.action.contains('俯') || beat.action.contains('下掷')
                ? '高角度俯拍'
                : (beat.action.contains('仰') || beat.action.contains('地面向上') || beat.action.contains('跃起')
                    ? '低角度仰拍'
                    : (shotSize == StudioShotSize.closeUp ? '特写机位' : '平视机位')));

        final resolvedScreenPosition = beat.screenPosition.trim().isNotEmpty
            ? beat.screenPosition.trim()
            : (beat.action.contains('左')
                ? '画面左侧'
                : (beat.action.contains('右') ? '画面右侧' : '主体居中'));

        final resolvedGazeDirection = beat.gazeDirection.trim().isNotEmpty
            ? beat.gazeDirection.trim()
            : (beat.action.contains('俯') || beat.action.contains('向下')
                ? '低头俯视'
                : (beat.action.contains('仰') || beat.action.contains('向上') ? '抬头仰视' : '平视正前'));

        newShots.add(StudioShot(
          number: shotNumber++,
          durationSec: dynamicDuration,
          shotSize: shotSize,
          mood: 'warm',
          function: function,
          actionZh: beat.action,
          dialogue: dialogueFormatted,
          voiceType: resolvedVoiceType,
          characterIds: charIds.toList(),
          sceneId: resolvedSceneId,
          beatId: beat.id,
          segmentId: segId,
          cameraMove: resolvedCameraMove,
          directorDecisions: DirectorDecisions(
            physicalMomentum: beat.subtext.isNotEmpty
                ? beat.subtext
                : '重心平稳，肢体随动作自然舒展',
            lightingStaging: '${scene.timeOfDay.isNotEmpty ? scene.timeOfDay : '日景'}，${scene.atmosphere.isNotEmpty ? scene.atmosphere : '自然光漫射'}',
            cameraStaging: resolvedCameraStaging,
            temporalEvolution: '动作处于启动及推进相位',
            aestheticTexture: '电影级画质质感，细节丰富细腻，光影自然，主体聚焦',
            cutReason: '',
            visualTask: '',
          ),
          continuity: ShotContinuity(
            worldPosition: scene.location.isNotEmpty ? scene.location : scene.title,
            screenPosition: resolvedScreenPosition,
            holdingLeft: '',
            holdingRight: '',
            lightingState: scene.timeOfDay.isNotEmpty ? scene.timeOfDay : '日景',
            gazeDirection: resolvedGazeDirection,
            cameraAxis: '机位处于180度轴线右侧，与前镜保持同轴关系',
            stateChanges: const [],
          ),
        ));
      }
    }
    return newShots;
  }

  /// 校验结构化 JSON 是否满足指定任务的 Schema 约束（供单元测试与静态验证直接调用）。
  static Map<String, dynamic>? validateSchema(
    StudioAiTask task,
    Map<String, dynamic> data,
  ) {
    return switch (task) {
      StudioAiTask.ideaIncubation => _SchemaValidators.ideaIncubation(data),
      StudioAiTask.scriptBreakdown => _SchemaValidators.scriptBreakdown(data),
      StudioAiTask.scriptBreakdown5D => _SchemaValidators.scriptBreakdown(data),
      StudioAiTask.actionCombatBreakdown => _SchemaValidators.scriptBreakdown(data),
      StudioAiTask.shotRegenerate => _SchemaValidators.shotRegenerate(data),
      StudioAiTask.promptTranslation => _SchemaValidators.promptTranslation(data),
      StudioAiTask.titleGeneration => _SchemaValidators.titleGeneration(data),
      StudioAiTask.bgmRecommend => _SchemaValidators.bgmRecommend(data),
      StudioAiTask.episodeSummary => _SchemaValidators.episodeSummary(data),
      StudioAiTask.novelMasterExtraction => _SchemaValidators.novelMasterExtraction(data),
      StudioAiTask.novelEpisodeSegmentation => _SchemaValidators.novelEpisodeSegmentation(data),
      StudioAiTask.novelChapterAdaptation => _SchemaValidators.novelChapterAdaptation(data),
      StudioAiTask.novelDramaChapterAdaptation => _SchemaValidators.novelChapterAdaptation(data),
      StudioAiTask.screenplayGeneration => _SchemaValidators.screenplayGeneration(data),
      StudioAiTask.sceneSpatialDeconstruction => _SchemaValidators.sceneSpatialDeconstruction(data),
    };
  }

  // ---------------------------------------------------------------------------
  // System Prompt 模板库
  // ---------------------------------------------------------------------------

  /// 取某个任务的 System Prompt。
  ///
  /// 模板是纯函数，测试直接断言内容（拼写、Schema 示例、约束数字），改动会被
  /// 测试接住——这些数字（5 字/秒、8-12 个分镜）就是约束本身。
  static String systemPromptFor(StudioAiTask task) {
    switch (task) {
      case StudioAiTask.scriptBreakdown:
        return _promptScriptBreakdown;
      case StudioAiTask.scriptBreakdown5D:
        return _promptScriptBreakdown5DWithCustom;
      case StudioAiTask.actionCombatBreakdown:
        return _promptActionCombatBreakdown;
      case StudioAiTask.promptTranslation:
        return _promptPromptTranslation;
      case StudioAiTask.ideaIncubation:
        return _promptIdeaIncubation;
      case StudioAiTask.titleGeneration:
        return _promptTitleGeneration;
      case StudioAiTask.bgmRecommend:
        return _promptBgmRecommend;
      case StudioAiTask.episodeSummary:
        return _promptEpisodeSummary;
      case StudioAiTask.shotRegenerate:
        return _promptShotRegenerate;
      case StudioAiTask.novelMasterExtraction:
        return _promptNovelMasterExtraction;
      case StudioAiTask.novelEpisodeSegmentation:
        return _promptNovelEpisodeSegmentation;
      case StudioAiTask.novelChapterAdaptation:
        return _promptNovelChapterAdaptation;
      case StudioAiTask.novelDramaChapterAdaptation:
        return _promptNovelDramaChapterAdaptation;
      case StudioAiTask.screenplayGeneration:
        return _promptScreenplayGeneration;
      case StudioAiTask.sceneSpatialDeconstruction:
        return _promptSceneSpatialDeconstruction;
    }
  }

  static const String _commonOutputRules =
      '【输出规则】\n'
      '1. 只输出一个 JSON 对象，不要输出 Markdown 代码块标记、不要输出任何解释、'
      '前言或结语。\n'
      '2. 所有字符串字段必须有值（可为空字符串），不要省略任何字段。\n'
      '3. 严格使用下面 Example 中的字段名（英文 snake_case），不要新增或改名。\n'
      '4. 数字字段输出数字而非字符串。\n';

  /// 拆分分镜模板（spec: 结构化分镜拆解 · 两段式）。
  ///
  /// **先划片段边界，再在片段内拆镜**。片段是视频生成的单元（见
  /// `segment-production` spec），所以边界划分不能是事后补救——它决定了
  /// 一次云端调用覆盖多少叙事，以及片段之间靠什么衔接才不像错误续帧。
  ///
  /// 关键约束来自 spec 与短剧实战标准：分镜条目含镜号/建议时长(3-5 秒)/
  /// 景别(含全景)/情绪/功能/动作(30-50字微动作)/台词(含预估秒数)/连续性台账；
  /// 单集拆出 8 到 16 个分镜，归入 1-4 镜/段的若干片段。
  static const String _promptScriptBreakdown =
      '你是一位专精于竖屏短剧的分镜师。你的任务是把用户给出的单集粗剧情大纲拆解为'
      '「片段 + 分镜」两级结构，供下游按片段生成视频、按分镜生成关键帧与配音。\n'
      '\n'
      '【第一步：划片段边界】\n'
      '先按叙事节拍把全集分镜归入若干片段。每个片段是连续叙事的最小可生成单元，'
      '含 1 到 4 个分镜，并有 target_duration_sec（该片段所有分镜时长之和）。\n'
      '片段边界的判定依据是「衔接是否自然」：相邻片段的末镜与首镜，'
      '必须在拍摄主体、景别、拍摄角度中至少有一项形成明显差异'
      '（主体类型不同 / 景别差 2 档以上 / 角度差 90° 以上），'
      '否则两个独立生成的片段在剪辑点会看起来像错误的续帧。\n'
      'boundary_reason 用一句中文说明为什么在这里切开。\n'
      '\n'
      '【第二步：片段内拆镜】\n'
      '1. 拆出 8 到 16 个分镜，镜号 number 从 1 开始连续递增，全集必须恰好一个 opening 与恰好一个 ending。\n'
      '2. 建议时长 duration_sec 取值必须在 4.0 到 12.0 秒之间，依据台词字数（4~5字/秒）与微动作幅度动态规划，严禁所有镜头均设为固定 3~4 秒。\n'
      '3. shot_size 只能是：close_up / medium_close_up / medium / full / long / extreme_long。\n'
      '4. mood 只能是：depressing / excited / warm / battle / suspense / relaxed / sad。\n'
      '5. function 只能是：opening / advance / burst / ending。\n'
      '6. action_zh 必须是简体中文，字数严格控制在 20 到 60 字之间！遵循【主体 + 动作 + 环境】微动作具象化结构，且动作遵循单动词/微动作原则，严禁堆叠超过 2 个复合动作。情节复杂时必须分拆为景别递进或正反打的连续镜头！\n'
      '7. dialogue 用简体中文，为角色台词或旁白，末尾用括号明确标注预估秒数，例如“（预估2.5秒）”或“（预估3.0秒）”，并在需要时加入情绪语气提示（例如“（压低声音，咬牙）你找死！（预估2秒）”）。dialogue 可以为空字符串（纯动作镜头）。\n'
      '8. character_ids 只能从【可用角色】中选，没有可用角色清单时填空数组。\n'
      '9. scene_id 只能从【可用场景】中选，没有可用场景清单时填空字符串。\n'
      '10. camera_move 用英文摄影术语短语，例如 "low angle push-in"、"slow pan right"、"handheld follow"。\n'
      '11. 如有【跨集记忆】，首个分镜的情绪基调必须与上集末尾情绪自然衔接。\n'
      '12. 不要输出 assembled_prompt 字段，该字段由系统另行组装。\n'
      '\n'
      '【连续性台账】每个分镜必须带 continuity 对象：\n'
      '- world_position：相对门、桌、窗等固定地标的绝对位置（与机位无关）。\n'
      '- screen_position：当前机位下的画面左右/前后/遮挡关系。\n'
      '- holding_left / holding_right：左右手持物，空手填空字符串。\n'
      '- lighting_state：主光方向与色温。\n'
      '- state_changes：本镜发生的状态变化数组，没有则为空数组。\n'
      '\n'
      '【剧情保真锁】\n'
      '- 只做拆分、合并与计时，不新增、删除、替换、改变归属或改变顺序任何剧情事件。\n'
      '- 不得为解释状态变化而补充原文没有的动作（例如原文直接写"角色已经站在门口"，'
      '就直接以该状态作为初始状态，不得补"起身、走过去"）。\n'
      '- holding_left / holding_right / state_changes 三项只能来自原文或明确给定的设定，'
      '不得自行推断道具来源。\n'
      '- 源剧情本身有空缺或矛盾时，保留原样并在 boundary_reason 中标注，不自行编桥接。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"segments": [{"segment_id": 1, "target_duration_sec": 8, '
      '"boundary_reason": "从双人中景切到单人特写，主体与景别均形成差异", '
      '"shot_numbers": [1, 2]}], '
      '"shots": [{"number": 1, "duration_sec": 3.5, "shot_size": "medium", '
      '"mood": "suspense", "function": "opening", "action_zh": "暴雨冲刷着昏暗巷道，女主背靠湿冷砖墙猛然回眸，眼神警惕盯向巷口。（34字）", '
      '"dialogue": "（压低声音）是谁在那里？！（预估2秒）", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in", '
      '"continuity": {"world_position": "巷口左侧，背靠砖墙", "screen_position": "画面右侧面向左", '
      '"holding_left": "", "holding_right": "折叠刀", "lighting_state": "巷口路灯顶光，冷蓝色", '
      '"state_changes": []}}]}\n'
      '\n'
      '【Example】\n'
      '{"segments": [\n'
      '  {"segment_id": 1, "target_duration_sec": 8, "boundary_reason": "开场建立双人关系，末镜与下段首镜主体不同", "shot_numbers": [1, 2]},\n'
      '  {"segment_id": 2, "target_duration_sec": 9, "boundary_reason": "切到单人局部特写，景别差 3 档", "shot_numbers": [3, 4, 5]}\n'
      '], "shots": [\n'
      '  {"number": 1, "duration_sec": 3.0, "shot_size": "close_up", '
      '"mood": "suspense", "function": "opening", "action_zh": "暴雨冲刷着昏暗巷道，女主背靠湿冷砖墙猛然回眸，眼神警惕盯向巷口。（34字）", "dialogue": "（压低声音）是谁在那里？！（预估2秒）", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in", '
      '"continuity": {"world_position": "巷口左侧，背靠砖墙", "screen_position": "画面右侧面向左", '
      '"holding_left": "", "holding_right": "折叠刀", "lighting_state": "巷口路灯顶光，冷蓝色", "state_changes": []}},\n'
      '  {"number": 2, "duration_sec": 5.0, "shot_size": "full", '
      '"mood": "excited", "function": "advance", "action_zh": "阴影中的高大男子缓缓撑开黑伞步出暗巷，皮鞋踏碎积水溅起水花。（32字）", '
      '"dialogue": "（冷笑）五年不见，你还是这么敏锐。（预估3秒）", "character_ids": [], "scene_id": "", '
      '"camera_move": "handheld follow", '
      '"continuity": {"world_position": "巷口右侧，面向女主", "screen_position": "画面左侧面向右", '
      '"holding_left": "黑伞", "holding_right": "", "lighting_state": "巷口路灯顶光，冷蓝色", "state_changes": ["撑开黑伞"]}}\n'
      ']}';

  /// 构建五维导演拆镜的完整 System Prompt（支持动态融入用户自定义的五维规范）。
  static String get _promptScriptBreakdown5DWithCustom {
    final customSpec =
        StudioPresetStore.instance.getPromptContent('director_breakdown_5d').trim();
    if (customSpec.isEmpty) return _promptScriptBreakdown5D;

    const defaultStep2Header = '【第二步：五维导演决策（每个分镜必填 director_decisions）】';
    const step3Header = '【第三步：分镜动作、台词与切镜动机】';
    final step2Idx = _promptScriptBreakdown5D.indexOf(defaultStep2Header);
    final step3Idx = _promptScriptBreakdown5D.indexOf(step3Header);

    if (step2Idx != -1 && step3Idx != -1) {
      return '${_promptScriptBreakdown5D.substring(0, step2Idx)}'
          '$defaultStep2Header\n'
          '$customSpec\n\n'
          '${_promptScriptBreakdown5D.substring(step3Idx)}';
    }
    return _promptScriptBreakdown5D;
  }

  /// 五维导演拆镜模板（五维导演决策 + 切镜动机 + 动态末态）。
  static const String _promptScriptBreakdown5D =
      '你是一位专精于影视视听语言与竖屏短剧工业化制作的资深导演。你的任务是将单集剧本大纲与场次规划拆解为具备专业导演调度与五维决策的结构化分镜列表。\n'
      '\n'
      '【第一步：划片段边界】\n'
      '按叙事节拍将分镜归入若干片段（每个片段含 1 到 4 个分镜，target_duration_sec 为该片段分镜时长之和）。\n'
      '相邻片段的末镜与首镜必须在拍摄主体、景别（差 2 档以上）或角度（差 90° 以上）形成明显差异，避免生成断帧感；boundary_reason 说明切开理由。\n'
      '\n'
      '【第二步：五维导演决策（每个分镜必填 director_decisions）】\n'
      '1. physical_momentum（主体与物理动势）：明确画面核心视觉焦点、身体重心、力量释放与受力反馈（例如：“韩立重心后移三寸，右臂蓄力将反作用力卸入脚底”）。\n'
      '2. lighting_staging（环境与光影）：对照场次主光源世界方向，明确当前镜头主体受光面、阴影朝向与光影动态变化（例如：“主光源来自北侧窗外冷白闪电，韩立面部左侧受强侧光，右侧深沉暗影”）。\n'
      '3. camera_staging（光学与机位四段式调度）：明确【起始运动 → 跟随对象 → 触发条件 → 结束落点】及视线与 180° 轴线关系（例如：“胸口高度中景平视，随韩立后撤缓慢后拉，在短刃刺入瞬间急推特写定格”）。当涉及空间高低落差（如楼上抛物、屋顶下跃、街面拔刀迎击）时，必须明确高角度俯拍（向下俯视）与低角度仰拍（向上迎击）视角，严禁机械平视！\n'
      '4. temporal_evolution（时间与状态演变）：明确动作相位（起手/接触/余势）、真实读时负荷与情绪留白（例如：“前1.5秒屏息试探，后1.5秒暴起接触，动作处于刚出招中途”）。\n'
      '5. aesthetic_texture（美学介质与风格质感）：明确质感与媒介风格细节（例如：“次世代3D国漫UE5渲染，空中弥漫药香微尘粒子，刀刃泛冷冽金属反光”）。\n'
      '\n'
      '【第三步：分镜动作、台词与切镜动机】\n'
      '- number 从 1 开始递增，duration_sec 严格在 4.0 到 12.0 秒之间（依据台词字数与微动作幅度动态规划，严禁固定短时长）。\n'
      '- shot_size：close_up / medium_close_up / medium / full / long / extreme_long。\n'
      '- mood：depressing / excited / warm / battle / suspense / relaxed / sad。\n'
      '- function：opening / advance / burst / ending。\n'
      '- action_zh：20 到 60 字，严格遵循【主体 + 单一/递进微动作 + 受力/反馈 + 环境】具象微动作结构，严禁单镜堆叠多个复合动作，严禁抽象情绪词！\n'
      '- dialogue：角色台词、内心独白（内心 OS）或旁白，优先复用【基准对白清单】原文；若为人物内心戏必须显式标注为“角色（内心 OS）：内容”，末尾括号标注预估秒数，如“（预估2.5秒）”。可为空。\n'
      '- cut_reason：说明为什么切到本镜，观众此刻获得什么新信息或视角转变。\n'
      '- visual_task：本镜的核心主要视觉任务。\n'
      '\n'
      '【第四步：空间地标与连续性台账（continuity）】\n'
      '- world_position：相对场次地标（门、桌、药柜）的绝对世界坐标与朝向。\n'
      '- screen_position：画面左右与 180° 轴线侧。\n'
      '- holding_left / holding_right：左右手持有物。\n'
      '- lighting_state：主光方向与色温。\n'
      '- state_changes：本镜发生的状态增量变化。\n'
      '- dynamic_exit_state（动态末态）：support_foot（支撑脚平衡，如“右脚踏实”）、velocity_vector（速度矢量，如“向前冲刺2m/s”）、unfinished_phase（未完成动作相位，如“出剑中途尚未拔出”）。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"segments": [{"segment_id": 1, "target_duration_sec": 7, "boundary_reason": "切入特写打破双人僵局", "shot_numbers": [1, 2]}], '
      '"shots": [{"number": 1, "duration_sec": 3.5, "shot_size": "medium", "mood": "suspense", "function": "opening", '
      '"action_zh": "暴雨猛烈拍打窗棂，韩立背抵冰冷药架猛然侧身，右手在衣袖内紧扣毒粉包暗扣。（36字）", '
      '"dialogue": "（压低呼吸）弟子确实不知。（预估2秒）", "character_ids": [], "scene_id": "SC001", "beat_id": "B01", '
      '"camera_move": "slow push-in", "cut_reason": "建立密室紧张对峙关系与空间方位", "visual_task": "揭示韩立暗扣毒粉的防备姿态", '
      '"director_decisions": {"physical_momentum": "背部贴墙支撑，重心下沉，右手蓄势待发", "lighting_staging": "窗外冷白闪电主光，室内油灯微弱暖侧光", "camera_staging": "腰部高度平视中景，微幅推镜锁定人物防备视线", "temporal_evolution": "动作处于屏息试探相位，为后续爆发蓄力", "aesthetic_texture": "UE5次世代国漫风，空气中有飞扬药粉微尘与水汽"}, '
      '"continuity": {"world_position": "药柜南侧死角，面向北门", "screen_position": "画面右侧面向左", "holding_left": "", "holding_right": "毒粉包", "lighting_state": "冷色闪电顶侧光", "state_changes": [], "dynamic_exit_state": {"support_foot": "双脚微屈踏地", "velocity_vector": "静止蓄势", "unfinished_phase": "指尖扣住毒粉包尚未甩出"}}}]}\n';

  /// 动作与战斗编舞专项拆镜模板（Combat DNA + 六步攻防链 + 3~4招连续接力攻击组）。
  static const String _promptActionCombatBreakdown =
      '你是一位专精于高武修仙、武侠打斗与激烈追逐的动作导演兼动作编舞师。你的任务是将打斗场景拆解为符合物理因果与视听张力的连续接力分镜。\n'
      '\n'
      '【核心禁令】严禁“打一招停一下”的回合制摆姿势！上一招余势未尽，下一招反制、变线或接力必须已经启动！\n'
      '\n'
      '【第一步：基于 Combat DNA 展开攻防】\n'
      '依据角色的体型重量、敏捷速度、惯用距离与反击习惯组织动作。轻灵角色借力穿插，刚猛角色封堵破防，法宝施法伴随真实印诀与天地气机引动。\n'
      '\n'
      '【第二步：连续攻击组与六步攻防因果链】\n'
      '以 3 到 4 个分镜构成一个连续接力攻击组。每个动作分镜必须在 combat_steps 中严格落实六步因果链：\n'
      '1. step_index: 序号从 1 开始。\n'
      '2. actor_name: 发起者；target_names: 目标角色列表。\n'
      '3. intent: 本动作用意（如“虚招刺面逼其仰头，实则暗取下盘”）。\n'
      '4. attack: 起手动作与兵器路线（如“右手玄铁短刃反握自下而上斜撩咽喉”）。\n'
      '5. defense: 对方应对与阻击（如“韩立后仰滑步，单臂横剑格挡”）。\n'
      '6. impact: 接触与受力失衡反馈（如“兵刃剧烈撞击溅射火星，虎口震颤退步”）。\n'
      '7. displacement: 位移与空间变化（如“受力向后倒滑三尺，撞击药架散落药瓶”）。\n'
      '8. next_link: 下一招接力方向（只承接上一招动势，不提前完成后招，如“借倒滑惯性反手甩出毒粉”）。\n'
      '9. duty: 镜头职责，必须从 threat_build / attack_path / impact / force_reaction / displacement / next_relay 中选一。\n'
      '\n'
      '【第三步：五维导演决策与动态末态】\n'
      '每个动作分镜同时填充 director_decisions 与 continuity.dynamic_exit_state（支撑脚、速度矢量、未完成相位），确保生成视频时动作矢量完美衔接。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"segments": [{"segment_id": 1, "target_duration_sec": 8, "boundary_reason": "近身突刺接力防守反击", "shot_numbers": [1, 2]}], '
      '"shots": [{"number": 1, "duration_sec": 3.5, "shot_size": "medium_close_up", "mood": "battle", "function": "burst", '
      '"action_zh": "墨大夫手腕翻转短刃泛起乌光直刺韩立咽喉，韩立生死一瞬偏头闪避，刀锋擦过颈侧削断一缕发丝。（42字）", '
      '"dialogue": "（厉喝）纳命来！（预估1.5秒）", "character_ids": [], "scene_id": "SC001", "beat_id": "B02", '
      '"camera_move": "whip pan to low angle", "cut_reason": "极近距离呈现刀锋破空的致命危机", "visual_task": "呈现短刃刺杀与发丝削落的物理交互", '
      '"director_decisions": {"physical_momentum": "墨大夫重心完全前倾突刺，韩立重心偏转卸力", "lighting_staging": "冷光闪电照亮刀刃寒光，血槽黑血泛幽光", "camera_staging": "低角跟随刀尖疾推至韩立颈侧特写", "temporal_evolution": "0.8秒破空突刺，0.5秒发丝断落，处于擦颈冲刺余势中", "aesthetic_texture": "火星溅射与发丝飘落的高速慢动作"}, '
      '"combat_steps": [{"step_index": 1, "actor_name": "墨大夫", "target_names": ["韩立"], "intent": "突刺封喉一击致命", "attack": "右手短刃反握直刺咽喉", "defense": "韩立极限偏头后滑", "impact": "刀锋擦破发丝，未中肉身", "displacement": "墨大夫前扑一丈，韩立后仰半尺", "next_link": "墨大夫招式用老尚未回肘，韩立左手已摸到毒粉", "duty": "impact"}], '
      '"continuity": {"world_position": "药架前方三尺中线", "screen_position": "画面左扑向右", "holding_left": "", "holding_right": "短刃", "lighting_state": "闪电冷光侧照", "state_changes": ["发丝断落一缕"], "dynamic_exit_state": {"support_foot": "墨大夫右脚前跨弓步，韩立左脚蹬地后撤", "velocity_vector": "墨大夫向前冲刺速度约2m/s", "unfinished_phase": "刀尖悬于画框边缘，刺势刚尽回拉未起"}}}]}\n';

  /// 小说全案第一阶段模板（动态提炼世界观、时代题材、美学风格、风格词、角色库、场景库）。
  static String buildNovelMasterExtractionPrompt() {
    final eraLines = <String>[];
    final eras = StudioPresetStore.instance.eras;
    for (final era in eras) {
      eraLines.add('   - "${era.id}"（${era.labelZh}，如 ${era.descriptionZh}）');
    }

    final styleLines = <String>[];
    final styles = StudioPresetStore.instance.styles;
    for (final style in styles) {
      styleLines.add('   - "${style.id}"（[${style.category}] ${style.nameZh}：${style.descriptionZh}）');
    }

    return '你是一位资深网络文学影视化与爆款短剧 IP 改编架构师。'
        '你的任务是从用户给出的长篇小说原著内容中，提炼出可以直接指导短视频制作的核心 IP 主库资产。\n'
        '\n'
        '【硬约束】\n'
        '1. worldview：提炼时代背景、核心规则矛盾、生存利益冲突与叙事主调，控制在 300 字以内。\n'
        '2. era_genre：根据小说题材与年代，从以下题材枚举中严格选择最贴合的一项（若无法归类返回空字符串）：\n'
        '${eraLines.join('\n')}\n'
        '3. aesthetic_style：根据故事基调与视觉定位，从以下工业级美学风格中严格选择最贴合的一项（若无法归类返回空字符串）：\n'
        '${styleLines.join('\n')}\n'
        '4. style_tokens：若选择的 aesthetic_style 有对应的风格，优先输出该风格的中文正向风格词（亦可根据原著特色微调强化融合）。例如仙侠玄幻包含 "UE5渲染，3D国漫，次世代CG，PBR物理材质，东方仙侠美学，体积光，云海雾气，16:9横屏"，现代都市包含 "现代院线电影写实，4K，超高细节，电影级运镜"。\n'
        '5. characters：提炼小说中最关键的 2 到 6 位核心登场角色（主角、主要反派、核心配角），每个角色包含：\n'
        '   - name: 角色名字（与原文一致）\n'
        '   - description_zh: 中文外貌金标准描写（完整综合描写，含容貌五官与全身服饰，必须体现服饰形制与时代感，避免下半身留空导致穿帮），避免模糊抽象\n'
        '   - facial_features_zh: 中文容貌体态原生细致描写（【核心约束】：必须显式保留原著中角色的明确年龄数字或人生阶段，如“十六岁少年”、“二十岁出头”，严禁在拆解时丢弃年龄！仅限五官长相、眼神神态、发型发色、体格身材，彻底剔除衣服与配饰，例如“十六岁白净圆脸少年，双眼狡黠戏谑，黑发抹油，身材矮壮敦实”或“二十岁出头剑眉星目，墨发高束，身形修长高挑”）\n'
        '   - default_attire_zh: 中文默认服装装束原生细致描写（仅包含服装形制、内外衣、面料质感、颜色、腰带、长靴与标志性随身配饰，例如“身着一袭洗得微旧但干净的玄青色巡城司狱卒棉布劲装，袖口紧收，腰系灰黑布带并悬挂铜质腰牌，下着深色绑腿长裤与黑色软底快靴”）\n'
        '   - personality: 性格与身份设定（30字以内）\n'
        '6. scenes：提炼 2 到 6 个故事高频发生的核心常驻场景（纯净物理空镜底板），每个场景包含：\n'
        '   - name: 场景名称（如“寒阳城长街”、“巡城司大牢”、“丽香苑雅间”）\n'
        '   - description_zh: 中文纯净空间建筑与环境光影描写（60~120字）。【核心排他约束】：场景仅作为舞台物理空间底板，严禁描写任何具体人物姓名、宾客身份、人群或生物，严禁包含人物动作、交互走位、聚集或剧情故事，必须纯粹描写建筑形制格局、家具陈设、光影色温与空间材质（如“青石条铺就的长条官道长街，两侧排列重檐歇山顶砖木瓦房，黄昏落日余晖斜照在青石板上反射出温润光泽，远处矗立三层飞檐朱漆大酒楼，酒肆红幌微扬”）。\n'
        '\n'
        '$_commonOutputRules'
        '\n'
        '【Output JSON Schema】\n'
        '{"worldview": "世界观设定...", "era_genre": "xianxia", "aesthetic_style": "ue5_3d_xianxia", "style_tokens": "UE5渲染，3D国漫，次世代CG...", '
        '"characters": [{"name": "主角名", "description_zh": "完整外貌描写...", "facial_features_zh": "五官面容体态...", "default_attire_zh": "默认服饰装束...", "personality": "性格设定..."}], '
        '"scenes": [{"name": "场景名", "description_zh": "纯净空间与家具陈设描写（严禁人物与剧情）..."}]}';
  }

  static String get _promptNovelMasterExtraction => buildNovelMasterExtractionPrompt();

  /// 小说全案第二阶段模板（剧情高潮检测与分集规划）。
  static const String _promptNovelEpisodeSegmentation =
      '你是一位专精于网络文学影视化改编与叙事架构的资深分集编剧。你的任务是通读提供的小说剧情主线、人物性格反差与世界观，'
      '依据故事自身的戏剧推进节奏，将原著有机拆解为节奏鲜明、戏剧钩子清晰的分集大纲。\n'
      '\n'
      '【核心原则：尊重原著人设与调性】\n'
      '1. 忠实保留原著主角的人物性格神韵（如松弛从容、幽默机智、腹黑毒舌或爽文反套路），严禁套用“开局必须憋屈受辱”等低俗刻板模板！严禁捏造主角无端受辱的桥段。\n'
      '2. 分集标题 title：提炼本集核心事件或人物交锋（10字以内，如“青驴狱卒与九年修为”、“暗室对决”），杜绝诸如“长街受辱”、“赘婿挨打”等低俗流水线起名。\n'
      '3. synopsis：本集影视大纲（80~150字，清晰交代人物动机、交锋过程与高潮转折）。\n'
      '4. summary：本集精炼前情记忆摘要（150字以内，供下游跨集连贯性注入）。\n'
      '5. hook：本集结尾截断点的悬念钩子（如身份即将揭晓、意想不到的反转，60字以内）。\n'
      '6. 规划 8 到 20 集短剧，首集自然入戏并交代核心看点，最后一集给出阶段性闭环。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"total_recommended_episodes": 10, "episodes": [{"index": 1, "title": "第一集标题", '
      '"synopsis": "本集粗大纲...", "summary": "前情摘要...", "hook": "集尾悬念..."}]}';

  /// 单章小说影视化剧本大纲深度提炼模板。
  static const String _promptNovelChapterAdaptation =
      '你是一位专精于网络文学影视化改编的资深编剧。你的任务是通读用户给出的单章小说完整内容，'
      '依据影视叙事规律【开局入戏 → 矛盾递进 → 核心高潮 → 尾部留钩】四大核心结构，'
      '提炼出能够直接指导单集短视频拍摄的结构化单集影视大纲。\n'
      '\n'
      '【核心原则：尊重原著人设与调性】\n'
      '严禁套用下沉短剧“主角开局必受辱”的刻板套路！忠实保留原著主角的心理动机、处事风格与交锋智慧。\n'
      '1. title: 拟定契合小说原味的单集标题（10字以内，如“青驴载狱卒”、“密室绝杀”）。\n'
      '2. synopsis: 本集影视化完整粗大纲，字数严格在 300 到 500 个汉字之间！必须清晰覆盖全章剧情脉络，按以下四个戏剧阶段完整叙述：\n'
      '   - 【开局入戏】：开场交代的环境、角色初始状态与初发事件；\n'
      '   - 【矛盾递进】：人物对话交锋、线索交织与行动过程；\n'
      '   - 【核心高潮】：本章情绪与戏剧张力最强的高光爆发事件；\n'
      '   - 【本集断点】：章末扣人心弦的转折或悬念。\n'
      '   严禁仅摘抄开头，必须完整贯穿全章事件始末！\n'
      '3. summary: 本集精炼前情摘要（150字以内，客观交代本集核心剧情沉淀，供下游跨集连贯性使用）。\n'
      '4. hook: 本集结尾截断留钩（50字以内，突出未解之谜或即将爆发的悬念）。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"title": "单集标题", "synopsis": "本集影视化大纲（300~500字）...", "summary": "前情摘要...", "hook": "末尾悬念..."}\n'
      '\n'
      '【Example】\n'
      '{"title": "密室杀局", "synopsis": "【开局入戏】暴雨之夜，韩立推开神手谷密室木门，赫然发现墨大夫面色铁青，手中短刃寒光逼人。【矛盾递进】墨大夫步步紧逼逼问长春功第四层口诀，韩立借取药引为由退至药柜死角，暗中将毒粉藏于指缝周旋试探。【核心高潮】墨大夫骤然暴起施展鹰爪功锁喉，韩立生死一线间反手掷出毒粉迷其双目，二人近身扭打撞翻药架，短刃脱手刺入地面。【本集断点】墨大夫虽中剧毒却突然发出诡异怪笑，双目泛起渗人幽绿荧光，夺舍残魂破体而出悬浮半空。", "summary": "韩立与墨大夫在神手谷密室正面决裂，韩立利用毒粉反制墨大夫肉身。", "hook": "墨大夫临死之际泛起幽绿魂光，夺舍残魂即将扑向韩立。"}';

  /// 单章小说深度影视化改编模板（四阶段影视大纲 + 戏剧场次规划与 Beats + 事实与对白保护清单）。
  static const String _promptNovelDramaChapterAdaptation =
      '你是一位专精于网络文学影视化与漫剧工业化制作的资深编剧兼导演架构师。\n'
      '你的任务是通读单章小说原著全文，将其改编为包含【影视大纲】、【戏剧场次规划与节拍】、【分场文学剧本】及【事实与对白保护清单】的专业工程化剧本资产。\n'
      '\n'
      '【核心原则：人设调性与因果保真】\n'
      '1. 忠实保留原著人物的性格内核（如主角的两世为人幽默、从容松弛、毒舌反击或谋略城府），严禁将主角掌控局面的戏谑反杀曲解为“受辱/憋屈”！\n'
      '2. 标题 title 必须契合原著风味（如“青驴载狱卒，天降九年修为”、“神手谷密室”，杜绝“长街受辱”等低俗流水线起名）。\n'
      '\n'
      '【第一部分：单集大纲与结构】\n'
      '1. title: 贴合原著风味的单集标题（10字以内）。\n'
      '2. synopsis: 本集影视化完整粗大纲，严格在 300 到 500 个汉字之间！必须清晰覆盖全章剧情脉络，按以下四个戏剧阶段完整叙述：\n'
      '   - 【开局入戏】：开场交代的环境、角色初始状态与初发事件；\n'
      '   - 【矛盾递进】：人物对话交锋、心理博弈与行动过程；\n'
      '   - 【核心高潮】：本章情绪与戏剧张力最强的高光爆发事件；\n'
      '   - 【本集断点】：章末扣人心弦的转折或悬念。\n'
      '3. summary: 本集精炼前情摘要（150字以内，客观交代本集核心剧情沉淀，供下游跨集连贯性使用）。\n'
      '4. hook: 本集结尾截断留钩（50字以内，突出未解之谜或剧情悬念）。\n'
      '\n'
      '【第二部分：场次规划（scenes）与微动作节拍（beats）】\n'
      '1. 根据剧情发生物理空间变化，将本集划分为 1 到 4 个场次（scenes）。\n'
      '2. 每个场次包含：\n'
      '   - id: 场次标识，如 "SC001", "SC002"\n'
      '   - scene_number: 整数场次序号（1, 2, ...）\n'
      '   - title: 场次标题，如 "神手谷密室", "长街天人居前"\n'
      '   - location: 空间地理位置\n'
      '   - setting: 只能是“内景”或“外景”\n'
      '   - time_of_day: 时间时段（如 "暴雨深夜", "黄昏日落"）\n'
      '   - atmosphere: 场景光影与环境氛围（如 "夕阳斜照长街，两侧酒肆红幌微扬"）\n'
      '   - primary_light_world_direction: 场次主光源绝对世界方向（如 "西向低角度暖金夕阳"）\n'
      '   - landmarks: 场次核心物理地标列表（如 ["青石板路", "三层酒楼", "朱漆木门"]）\n'
      '   - character_ids: 出场角色名称列表\n'
      '   - dramatic_objective: 该场次戏剧核心目标\n'
      '   - entry_state: 场次入场初始物理状态\n'
      '   - exit_state: 场次离场最终物理状态\n'
      '   - beats: 场次内戏剧节拍列表，按时间顺序排列，每个节拍包含：\n'
      '     * id: 节拍编号，如 "B01", "B02"\n'
      '     * scene_id: 所属场次 ID\n'
      '     * order: 序号（从 1 开始连续递增）\n'
      '     * name: 节拍名称（如 "骑驴思忖", "反唇相讥", "拔刀截鸡"）\n'
      '     * action: 节拍核心视觉动作与神态（30~60字，聚焦于主干动作）\n'
      '     * dialogue_speaker: 说话角色名（无对白/心声可为空串）\n'
      '     * voice_type: 必须严格从 "dialogue"（对外说出的话）、"inner_voice"（角色内心独白/OS）、"narration"（画外旁白）中选一。原著中推动人物动机与幽默感的主角内心吐槽、思考与金手指感悟，必须标记为 "inner_voice" 予以保留！\n'
      '     * dialogue: 角色台词或内心独白（逐字保留原著关键语句，末尾标预估秒数，如“（预估2.5秒）”，无对白可为空串）\n'
      '     * subtext: 潜台词与内心戏真实口吻\n'
      '     * estimated_sec: 预估发声与动作时长（秒，数字，4~12 秒）\n'
      '     * dramatic_function: 戏剧功能（如 "threat_build", "climax_payoff", "suspense"）\n'
      '     * shot_size: 必须严格从 "close_up", "medium_close_up", "medium", "full", "long", "extreme_long" 中选一。根据叙事与戏剧张力规划（建立环境用 long/full，对话交锋用 medium/medium_close_up，情绪爆发/微动作/高光反杀用 close_up）。\n'
      '     * camera_staging: 电影导演机位与拍摄视角（如："平视定机位", "高角度俯拍（三层楼窗台向下俯视街道）", "低角度仰拍（地面向上迎击/拔刀特写）", "主观视角 POV", "过肩镜头 OTS 反打"）。【重要视听语法推导规则】：当动作存在物理空间高低落差（如从高楼向下抛物/屋顶跃下/街面截击）时，严禁使用平视，必须根据物理落差与受力关系输出俯拍（掷物方下看）或仰拍（受击方上迎）！\n'
      '     * camera_move: 动态运镜轨迹英文术语（如："static", "slow_push_in", "dramatic_pull_out", "pan_down_follow", "low_angle_tracking", "handheld_shaky", "crane_down"）。根据戏剧冲突动态适配，严禁所有镜头都设为 static！\n'
      '     * screen_position: 画面主体构图与站位（如："主体居中", "画面左侧面向右", "画面右侧面向左", "前景遮挡对角线"）。\n'
      '     * gaze_direction: 人物视线朝向与视线正反打匹配（如："平视正前", "低头俯视街面", "抬头仰视斜上方", "斜睨右侧对手"）。\n'
      '\n'
      '【第三部分：影视文学剧本全文（screenplay_text）】\n'
      '按影视工业规范输出 Markdown 格式的完整文学分场剧本，清晰标注场次、地点、时段、内外景、出场角色、动作神态与台词/内心独白（格式如：`姜七夜（内心 OS）：今天真晦气…` 或 `余小白：姜七少，上来喝一杯！`）。\n'
      '\n'
      '【第四部分：事实与对白保护清单（protected_contract）】\n'
      '1. facts: 锁定原著核心事实清单（3 到 8 条），禁止下游篡改：\n'
      '   - id: 编号，如 "F01"\n'
      '   - type: 事实类型，严格从 "FACT"（原著明示）、"INFERENCE"（逻辑合理推断）、"DIRECTOR_CHOICE"（导演视听选择）中选一\n'
      '   - content: 事实陈述（如 "姜七夜骑高头大青驴巡街回家"）\n'
      '   - source_location: 原文依据位置\n'
      '   - mandatory: 布尔值，是否强制遵守（默认 true）\n'
      '2. utterances: 锁定原著高光台词与核心对话（3 到 8 句），逐字保留原著语气：\n'
      '   - id: 编号，如 "U01"\n'
      '   - speaker: 说话人（必须与角色名一致）\n'
      '   - listener: 听话人\n'
      '   - text: 说话内容原文（逐字保留，严禁擅自魔改口癖）\n'
      '   - voice_type: 严格从 "dialogue"（角色台词）、"inner_voice"（内心独白）、"narration"（画外旁白）中选一\n'
      '   - estimated_sec: 预估朗读秒数（以5字/秒换算）\n'
      '3. protected_beats: 必须保留的核心高光节拍 ID 列表（如 ["B01", "B03"]）\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"title": "密室杀局", "synopsis": "【开局入戏】...【矛盾递进】...【核心高潮】...【本集断点】...", '
      '"summary": "前情摘要...", "hook": "末尾悬念...", '
      '"screenplay_text": "### 第1场 神手谷密室（内景 / 暴雨深夜 / 神手谷内室）\\n\\n**【节拍 1：寒暄试探】**\\n画面动作：墨大夫缓步逼近韩立，面露阴鸷。\\n对白（墨大夫）：好徒儿，长春功练到第几层了？（预估2.5秒）\\n潜台词：*试探虚实*", '
      '"scenes": [{"id": "SC001", "scene_number": 1, "title": "神手谷密室", "location": "神手谷内室", "setting": "内景", "time_of_day": "暴雨深夜", '
      '"atmosphere": "昏黄油灯斜照，狭窄压抑", "character_ids": ["墨大夫", "韩立"], '
      '"primary_light_world_direction": "北面窗棂外冷白闪电", "landmarks": ["青铜药鼎", "实木药架", "木门"], '
      '"dramatic_objective": "墨大夫逼问口诀并实施夺舍", "entry_state": "韩立推门而入，墨大夫静坐阴影中", "exit_state": "墨大夫肉身中毒瘫倒，残魂离体", '
      '"beats": [{"id": "B01", "scene_id": "SC001", "order": 1, "name": "寒暄试探", "action": "墨大夫缓步逼近韩立，言语逼问长春功进展", "dialogue_speaker": "墨大夫", "dialogue": "好徒儿，长春功练到第几层了？（预估2.5秒）", "voice_type": "dialogue", "subtext": "试探虚实", "estimated_sec": 4.0, "dramatic_function": "threat_build", "shot_size": "medium", "camera_staging": "平视定机位", "camera_move": "slow_push_in", "screen_position": "主体居中", "gaze_direction": "平视正前"}]}], '
      '"protected_contract": {"facts": [{"id": "F01", "type": "FACT", "content": "墨大夫手持玄铁短刃淬有剧毒", "source_location": "原著第三段", "mandatory": true}], '
      '"utterances": [{"id": "U01", "speaker": "墨大夫", "listener": "韩立", "text": "好徒儿，你的长春功练到第几层了？", "voice_type": "dialogue", "estimated_sec": 3.0}], '
      '"protected_beats": ["B01"]}}\n';

  /// Prompt 翻译模板（中文角色描述 → 英文正/负向）。
  static const String _promptPromptTranslation =
      '你是一位 AI 绘画提示词工程师。你的任务是把用户的中文角色外貌描述翻译为'
      '符合主流文生图引擎（Flux / Stable Diffusion 系列）规范的英文提示词。\n'
      '\n'
      '【硬约束】\n'
      '1. prompt_positive：英文，逗号分隔的词组，必须精确描述外貌、全身服装、神态与画风；'
      '若提供了【时代题材】或【世界观背景】，服装形制必须严格符合该时代（如仙侠修真必须包含 traditional Hanfu robes, flowing robes，现代都市必须包含 suit/blazer/contemporary fashion，严禁生成下半身留空或时代穿帮服饰）；'
      '若角色描述中包含少年、青年、幼年、书童、小弟等年轻设定或未蓄须特征，prompt_positive 必须显式声明 clean-shaven, hairless face, smooth bare chin, youthful teenage face 等正向无须词组，严禁泛化为模糊的 1man 或店主掌柜而导致大模型误生胡须；'
      '若角色描述包含白胖、富态或微胖，必须明确输出 chubby build, plump body, fair-skinned，严禁只写 slender 或忽略体态；'
      '必须包含画风与画质词（如 cinematic lighting, 8k, highly detailed）。\n'
      '2. prompt_negative：英文，包含常见瑕疵词（如 blurry, low quality, '
      'extra fingers, deformed hands, watermark, text）；'
      '若角色为年轻少年或未指定蓄须，prompt_negative 必须显式包含 beard, mustache, facial hair, goatee, stubble, wrinkles, elderly, mature adult face，严防角色苍老或长出胡子；'
      '若处于古代/仙侠/异世界等非现代题材，必须在负向中严格抑制现代服装（如 modern clothes, shorts, beach shorts, t-shirt, jeans, sneakers, wristwatch）。\n'
      '3. 根据【制作类型】适配画风：\n'
      '   - anime3d（3D国漫/次世代虚拟剧）：3D CGI animation, modern Chinese fantasy donghua, exquisite 3D render, Unreal Engine 5 render, Octane render, subsurface scattering skin, delicate hair strands, glowing elemental VFX, cinematic lighting；负向必须抑制 2D, flat anime, cartoon, sketch, live-action photo, plastic clay, low-poly, stiff puppet。\n'
      '   - drama（真人短剧）：写实风格，photorealistic, cinematic film still, live-action cinematography, natural skin texture；负向必须抑制 anime, cartoon, 3D render, CGI, illustration。\n'
      '   - anime（二次元/动态漫）：anime style, cel shading, clean line art, vibrant anime coloring, Makoto Shinkai lighting；负向必须抑制 photorealistic, live-action, 3D CGI。\n'
      '   - narration（图文解说）：high-end documentary illustration style, atmospheric digital painting, storybook realism；负向必须抑制 messy, anime, cartoonish, low-brow。\n'
      '4. prompt_positive 总长度不超过 120 个英文单词。\n'
      '5. 保持角色可辨识的核心特征（发型、瞳色、标志性服饰）不被稀释。\n'
      '6. 双维度解耦拆分（容貌体态 vs 服装装束）：为了支持角色无污染换装及多形态切换，必须将角色描述拆解输出为独立的两组中英文提示词：\n'
      '   - facial_features_zh: 中文容貌体态描述（仅包含五官长相、发型、体格身材，彻底剔除服装与配饰）\n'
      '   - facial_prompt: 英文面部与体态提示词（仅描述面容、发型、体态与年轻无须防御，严禁包含任何衣服颜色或服装款式）\n'
      '   - default_attire_zh: 中文默认服装装束描述（仅包含衣着款式、袍服颜色、鞋靴佩饰）\n'
      '   - attire_prompt: 英文服装提示词（仅包含全身服装形制与配饰）\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"prompt_positive": "english positive prompt", '
      '"prompt_negative": "english negative prompt", '
      '"facial_features_zh": "中文容貌体态", '
      '"facial_prompt": "english facial and anatomy prompt", '
      '"default_attire_zh": "中文默认服装装束", '
      '"attire_prompt": "english attire prompt"}\n'
      '\n'
      '【Example】\n'
      '{"prompt_positive": "1 young woman, sharp eyes, silver bob hair, '
      'scar on left cheek, black trench coat, rain soaked, photorealistic, '
      'cinematic film still, cinematic lighting, 8k, highly detailed", '
      '"prompt_negative": "blurry, low quality, extra fingers, deformed hands, '
      'watermark, text, oversaturated", '
      '"facial_features_zh": "留银色短发、左脸有浅浅刀疤的年轻女子，眼神锐利冷峻", '
      '"facial_prompt": "1 young woman, sharp eyes, silver bob hair, scar on left cheek, clean-shaven, youthful face", '
      '"default_attire_zh": "雨水浸湿的黑色风衣", '
      '"attire_prompt": "wearing black trench coat, rain soaked"}';

  /// 创意孵化模板。
  static const String _promptIdeaIncubation =
      '你是一位爆款竖屏短剧的策划人。用户只给出一个模糊想法，你要从中提炼出 3 个'
      '结构完整、可直接进入制作的故事方向。\n'
      '\n'
      '【硬约束】\n'
      '1. 恰好输出 3 个方向，每个方向必须包含：\n'
      '   - title：方向名称（10 字以内）\n'
      '   - hook：主线故事钩子，含开头 3 秒的爆点结构\n'
      '   - twist：核心反转\n'
      '   - pacing：分集节奏建议，含首集重点、中段走向、高潮集位置\n'
      '   - strategy：该制作类型对应的内容策略提示\n'
      '2. 三个方向的题材与情绪必须彼此明显不同，不要同一思路换皮。\n'
      '3. 语言为简体中文，面向非专业创作者，避免术语堆砌。\n'
      '4. 每个字段不超过 120 字。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"directions": [{"title": "", "hook": "", "twist": "", "pacing": "", '
      '"strategy": ""}]}\n'
      '\n'
      '【Example】\n'
      '{"directions": [\n'
      '  {"title": "重生复仇", "hook": "开篇即女主葬礼，她重生回到分手当晚", '
      '"twist": "渣男才是被利用的棋子", "pacing": "首集立仇，中段反杀，第 8 集高潮"},\n'
      '  {"title": "替嫁新娘", "hook": "新娘在婚礼现场被当场掉包", '
      '"twist": "新郎早知道新娘被换", "pacing": "首集留悬，中段试探，第 10 集揭秘"},\n'
      '  {"title": "直播间谜案", "hook": "带货直播中观众认出背景里的被害人", '
      '"twist": "凶手是直播间榜一", "pacing": "首集抛尸，中段追凶，第 9 集收网"}\n'
      ']}';

  /// 标题生成模板。
  static const String _promptTitleGeneration =
      '你是一位短视频平台的标题运营。请为下面这一集生成 3 条发布标题。\n'
      '\n'
      '【硬约束】\n'
      '1. 恰好 3 条，风格分别为：情绪型、悬念型、爽点型（按此顺序）。\n'
      '2. 每条不超过 24 个汉字，必须含情绪钩子词。\n'
      '3. 结合【制作类型】调整语气，不要剧透到本集核心反转。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"titles": [{"style": "emotion|suspense|payoff", "text": ""}]}\n'
      '\n'
      '【Example】\n'
      '{"titles": [\n'
      '  {"style": "emotion", "text": "她等这句道歉，等了整整十年"},\n'
      '  {"style": "suspense", "text": "婚礼进行到一半，新郎突然喊了另一个名字"},\n'
      '  {"style": "payoff", "text": "曾经赶我出门的人，现在求我回去"}\n'
      ']}';

  /// BGM 推荐模板。
  static const String _promptBgmRecommend =
      '你是一位短剧声音设计师。请根据分镜的情绪基调，从【可选 BGM 列表】中挑选'
      '最合适的 3 首。\n'
      '\n'
      '【硬约束】\n'
      '1. 只能从【可选 BGM 列表】中选择，不得编造列表之外的曲名。\n'
      '2. 恰好 3 个候选，按匹配度从高到低排列，score 为 0 到 100 的整数。\n'
      '3. reason 用简体中文说明适配理由（30 字以内）。\n'
      '4. 若列表为空或不足 3 项，有几个就返回几个，不要编造。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"recommendations": [{"name": "", "score": 0, "reason": ""}]}\n'
      '\n'
      '【Example】\n'
      '{"recommendations": [\n'
      '  {"name": "战斗_高潮", "score": 92, "reason": "鼓点密集，匹配打斗节奏"},\n'
      '  {"name": "紧张_追逐", "score": 85, "reason": "弦乐推进，适合追逃场面"}\n'
      ']}';

  /// 剧情摘要模板（写进跨集记忆库）。
  static const String _promptEpisodeSummary =
      '你是一位短剧的剧本统筹。请把下面这一集的内容压缩为一段剧情摘要和一句'
      '末尾悬念钩子，供后续集数生成时作为前情上下文注入。\n'
      '\n'
      '【硬约束】\n'
      '1. summary：简体中文，客观陈述本集发生了什么，保留人物状态变化，'
      '不要抒情。\n'
      '2. hook：本集末尾留给观众的悬念钩子，一句话。\n'
      '3. 两者都必须短——上下文长度直接影响后续集数生成的质量。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"summary": "", "hook": ""}\n'
      '\n'
      '【Example】\n'
      '{"summary": "女主发现丈夫出轨证据，被婆婆当众羞辱后净身出户，'
      '在旧友帮助下进入对手公司。", "hook": "入职第一天，她的直属上司正是当年的初恋。"}';

  /// 单镜重生成模板。
  ///
  /// 关键新增约束：**不得为弥合与相邻分镜的状态跳跃而新增桥接动作**（spec:
  /// 禁止 AI 自行桥接）。用户改的往往只是这一镜的画面表达，AI 很容易顺手补一个
  /// 「角色走过去」来解释位置变化——那是在替用户编剧情。
  static const String _promptShotRegenerate =
      '你是一位专精于竖屏短剧的分镜师。用户给出了一个分镜的当前 JSON 与一条修改'
      '要求，请输出修改后的同一个分镜。\n'
      '\n'
      '【硬约束】\n'
      '1. 保持 number 不变，只按用户要求修改其他字段。\n'
      '2. duration_sec 仍在 4 到 12 秒之间，且台词字数不超过 '
      'duration_sec × 5 个汉字。\n'
      '3. shot_size / mood / function 的取值域与初次拆镜完全一致。\n'
      '4. 不要输出 assembled_prompt 字段。\n'
      '5. 只输出这一个分镜对象，不要输出 shots 数组。\n'
      '6. continuity 字段必须原样保留用户给出的值，除非修改要求明确指向它。\n'
      '7. 若该镜与相邻分镜之间存在状态跳跃，只重写本镜的画面表达，'
      '不得新增用于解释跳跃的动作（例如不得补"起身、走过去"来解释位置变化）。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"shot": {"number": 1, "duration_sec": 3, "shot_size": "medium", '
      '"mood": "warm", "function": "advance", "action_zh": "", '
      '"dialogue": "", "character_ids": [], "scene_id": "", '
      '"camera_move": "", "continuity": {"world_position": "", '
      '"screen_position": "", "holding_left": "", "holding_right": "", '
      '"lighting_state": "", "state_changes": []}}}\n'
      '\n'
      '【Example】\n'
      '{"shot": {"number": 3, "duration_sec": 4, "shot_size": "close_up", '
      '"mood": "sad", "function": "advance", "action_zh": "她低头看着手里的病历单", '
      '"dialogue": "原来只剩三个月了", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in", "continuity": {"world_position": "诊室门口", '
      '"screen_position": "画面居中", "holding_left": "", "holding_right": "病历单", '
      '"lighting_state": "诊室顶光，冷白", "state_changes": []}}}';

  /// 故事大纲 → 影视分场文学剧本（场次、日夜、内外景、角色对白与微动作节拍）。
  static const String _promptScreenplayGeneration =
      '你是一位专精于网络文学影视化与影视文学剧本的资深编剧兼导演。\n'
      '你的任务是将用户提供的故事大纲、剧情梗概或小说章节，改编为符合影视工业规范的【标准分场剧本】。\n'
      '\n'
      '【核心原则】\n'
      '1. 尊重原著人物性格与爽点逻辑，杜绝刻板受辱套路，保留主角心理从容与幽默反差。\n'
      '2. 原生支持内心独白：将角色关键思考与吐槽明确标记为 voice_type: "inner_voice"，让故事因果清晰、动机分明。\n'
      '3. 影视导演级视听语法推导：每个动作节拍（beat）依据戏剧冲突与空间物理动势，自主推导景别（shot_size）、机位视角高度（camera_staging）、运镜动态轨迹（camera_move）、构图站位（screen_position）与视线正反打（gaze_direction）。\n'
      '\n'
      '【硬约束】\n'
      '1. 按影视场次（Scene）组织，输出不少于 2 个场次。场次编号从 1 开始递增。\n'
      '2. 每个场次必须包含：\n'
      '   - id: 如 "SC001"、"SC002"\n'
      '   - scene_number: 整数序号（1, 2, ...）\n'
      '   - title: 场次简要标题（如“寒阳城长街天人居前”）\n'
      '   - location: 具象地点（如“寒阳城天人居酒楼前长街”）\n'
      '   - setting: 只能是“内景”或“外景”\n'
      '   - time_of_day: 只能是“日景”、“夜景”、“黄昏”、“黎明”之一\n'
      '   - atmosphere: 场景环境与光影氛围描述（如“黄昏斜阳穿透长街，远处朱漆酒楼天人居矗立”）\n'
      '   - character_ids: 出场角色名称列表\n'
      '   - beats: 动作节拍与对白列表，每个节拍包含：\n'
      '     * id: 如 "B01"、"B02"\n'
      '     * scene_id: 所属场次 id\n'
      '     * order: 整数序号（1, 2, ...）\n'
      '     * name: 节拍动作主题（如“骑驴思忖”、“反唇相讥”、“拔刀截鸡”）\n'
      '     * action: 具象动作描述，聚焦于主干动作与神态表情\n'
      '     * dialogue_speaker: 说话角色名（无对白/心声可为空串）\n'
      '     * dialogue: 角色台词或内心独白（无对白可为空串，末尾标预估秒数如“（预估2.5秒）”）\n'
      '     * voice_type: 只能是 "dialogue"（对外台词）、"inner_voice"（内心独白/OS）、"narration"（旁白）之一\n'
      '     * subtext: 台词背后的潜台词与内心戏真实口吻\n'
      '     * estimated_sec: 预估发声与动作时长（秒，数字，4~12 秒合理范围）\n'
      '     * shot_size: 必须严格从 "close_up", "medium_close_up", "medium", "full", "long", "extreme_long" 中选一。根据叙事与戏剧张力规划（建立环境用 long/full，对话交锋用 medium/medium_close_up，情绪爆发/微动作/高光反杀用 close_up）。\n'
      '     * camera_staging: 电影导演机位与拍摄视角（如："平视定机位", "高角度俯拍（三层楼窗台向下俯视街道）", "低角度仰拍（地面向上迎击/拔刀特写）", "主观视角 POV", "过肩镜头 OTS 反打"）。【重要视听语法推导规则】：当动作存在物理空间高低落差（如从高楼向下抛物/屋顶跃下/街面截击）时，严禁使用机械平视，必须根据物理落差与受力关系输出俯拍（掷物方下看）或仰拍（受击方上迎）！\n'
      '     * camera_move: 动态运镜轨迹英文术语（如："static", "slow_push_in", "dramatic_pull_out", "pan_down_follow", "low_angle_tracking", "handheld_shaky", "crane_down"）。根据戏剧冲突动态适配，严禁所有镜头都设为 static！\n'
      '     * screen_position: 画面主体构图与站位（如："主体居中", "画面左侧面向右", "画面右侧面向左", "前景遮挡对角线"）。\n'
      '     * gaze_direction: 人物视线朝向与视线正反打匹配（如："平视正前", "低头俯视街面", "抬头仰视斜上方", "斜睨右侧对手"）。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"scenes": [{"id": "SC001", "scene_number": 1, "title": "寒阳城长街", "location": "寒阳城天人居酒楼前长街", "setting": "外景", "time_of_day": "黄昏", "atmosphere": "黄昏斜阳穿透长街，酒肆红幌微扬", "character_ids": ["姜七夜", "余小白"], "beats": [{"id": "B01", "scene_id": "SC001", "order": 1, "name": "骑驴思忖", "action": "姜七夜骑着高大青驴沿长街缓行，俊美的脸上带着从容慵懒，随意扫视街景。", "dialogue_speaker": "姜七夜", "dialogue": "今天真晦气，又被老王训了一顿。（预估2.5秒）", "voice_type": "inner_voice", "subtext": "表面平静，暗中谋划反制", "estimated_sec": 4.0, "shot_size": "medium", "camera_staging": "平视定机位", "camera_move": "slow_push_in", "screen_position": "主体居中", "gaze_direction": "平视正前"}, {"id": "B02", "scene_id": "SC001", "order": 2, "name": "楼上挑衅", "action": "余小白自三楼窗口探出半个身子，举杯坏笑向下喊话。", "dialogue_speaker": "余小白", "dialogue": "姜七少，上来喝一杯啊！（预估2.0秒）", "voice_type": "dialogue", "subtext": "故意调侃寻开心", "estimated_sec": 3.0, "shot_size": "medium_close_up", "camera_staging": "高角度俯拍（三层楼窗口向下俯视街道）", "camera_move": "pan_down_follow", "screen_position": "画面上方窗口面向下方", "gaze_direction": "低头俯视街面"}]}]}\n';

  /// 场景七方位空间全息解构模板。
  static const String _promptSceneSpatialDeconstruction =
      '你是一位专精于影视概念设计与建筑空间拓扑学的资深美术总监兼概念置景师。\n'
      '用户提供了剧集的世界观时代题材、制作风格基调、场景名称以及小说原著对该场景的基础描述。\n'
      '你的任务是将其推演并解构成一个 3D 几何与采光逻辑自洽的【七方位空间全息档案】（包含前、后、左、右、上、下以及俯视全景鸟瞰）。\n'
      '\n'
      '【硬约束】\n'
      '1. 【绝对空间空镜与零人物约束】：这是纯粹的场景物理环境资产档案，严禁出现任何具体人物角色、男女主角、路人仆从、对白台词、肢体动作或剧情叙事！若小说原著描述包含“某人与某人在此密谋”、“佳人弹琴”等叙事，必须彻底清洗过滤，只提炼置景（琴台、纱幔、案桌、屏风）本身！\n'
      '2. 【七方位必须齐全】：必须且只能输出以下 7 个方位的空间视图对象：\n'
      '   - "front": 正面主景（主案/神龛/屏风视觉重心，正面正视）\n'
      '   - "back": 反打背景（大门/入口/退路走廊，反向背视）\n'
      '   - "left": 左侧立面（采光排窗/立柜陈设）\n'
      '   - "right": 右侧立面（内室通道/侧席博古架/垂帘通道）\n'
      '   - "top": 天顶结构（梁木藻井/穹顶吊灯，仰视仰拍）\n'
      '   - "bottom": 地面铺装（青砖地坪/织锦地毯，俯视地面）\n'
      '   - "topDown": 俯视全景（空间平面拓扑与长宽进深鸟瞰）\n'
      '3. 【3D 物理与采光逻辑自洽】：必须保持统一的空间材质与主光源逻辑。例如左侧若是镂空雕花木窗采光，天顶与右侧立面就必须体现相应方向的光斑与阴影；建筑制式、墙面色彩和地坪纹理跨方位必须风格统一。\n'
      '4. 【纯原生中文规范】：每个方位直接输出具有高度画面表现力的原生中文空间描述（50~120字），包含具体的建筑形制、家具陈设、光影色温、空气透视与物理材质细节，严禁输出英文翻译或英文标签。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{\n'
      '  "views": {\n'
      '    "front": {"description_zh": "正中央设紫檀雕花大案，案上陈设文房四宝与青铜香炉，背后立着四扇山水绢丝落地屏风，两侧挂青纱帐幔，氛围幽深典雅。"},\n'
      '    "back": {"description_zh": "正门为双开朱漆雕花木门，门内设避风楠木玄关与一幅泼墨屏风，退路门廊幽暗，门楣上方悬挂避煞八卦铜镜。"},\n'
      '    "left": {"description_zh": "左侧为整排雕花支摘窗，窗棂嵌明瓦透光，光线斜照进室内在地坪拉出长影，窗边设红木琴台与一盆苍劲罗汉松盆景。"},\n'
      '    "right": {"description_zh": "右侧通往内室的月亮门垂挂半透明珠帘，门侧依墙摆放通顶多宝槅博古架，陈列前朝青瓷与古籍卷轴。"},\n'
      '    "top": {"description_zh": "仰视可见纯木榫卯结构的八角重檐藻井，斗栱层层叠叠，正中垂下一盏八角琉璃流苏宫灯，横梁彩绘褪色古拙。"},\n'
      '    "bottom": {"description_zh": "地面由大块青灰水磨金砖斜铺而成，金砖光润如镜倒映窗影，主案前铺设一块大红暗花织锦厚毯，边缘织云水回纹。"},\n'
      '    "topDown": {"description_zh": "鸟瞰全景展示长方形进深雅阁，北侧为主案屏风，南侧为双开大门，西侧排窗采光，东侧月门内室，中央地毯串联前后空间，布局工整中轴对称。"}\n'
      '  }\n'
      '}';

  // ---------------------------------------------------------------------------
  // JSON 提取
  // ---------------------------------------------------------------------------

  /// 从 AI 输出中提取 JSON 对象。
  ///
  /// 模型经常在 JSON 外面包 ```json 围栏或一句"好的，以下是..."。这里按顺序
  /// 尝试：直接解析 → 剥围栏 → 截取第一个 `{` 到最后一个 `}`。三层都不成
  /// 才返回 null 让上层重试。
  static Map<String, dynamic>? parseJsonLoose(String raw) {
    if (raw.trim().isEmpty) return null;
    final direct = _tryDecode(raw.trim());
    if (direct != null) return direct;

    final fenced = _stripCodeFence(raw.trim());
    if (fenced != null) {
      final decoded = _tryDecode(fenced);
      if (decoded != null) return decoded;
    }

    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = _tryDecode(raw.substring(start, end + 1));
      if (decoded != null) return decoded;
    }
    return null;
  }

  static Map<String, dynamic>? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k as String, v));
      }
    } catch (_) {}
    return null;
  }

  static String? _stripCodeFence(String text) {
    if (!text.startsWith('```')) return null;
    var body = text.substring(3);
    final firstNewline = body.indexOf('\n');
    if (firstNewline < 0) return null;
    // 去掉首行的语言标记（```json / ```JSON ）。
    body = body.substring(firstNewline + 1);
    final close = body.lastIndexOf('```');
    if (close < 0) return null;
    return body.substring(0, close).trim();
  }
}

/// 各任务的 JSON Schema 校验器。
///
/// 返回 null 表示校验失败（调用方据此重试）；返回可供下游直接使用的规范化
/// Map。校验同时做**归一化**：AI 给出的景别偶尔是"特写"而不是 `close_up`，
/// 这里映射回枚举 id，省得每个调用点都写一遍容错。
///
/// 片段的校验规则（[segmentBreakdown]）刻意严格：覆盖不全、镜号重叠、
/// 相邻片段衔接不足，任一不成立都判失败。理由是这三类错误下游无法补救——
/// 覆盖不全会有分镜永远不参与生成，重叠会让同一镜进两个片段，衔接不足则
/// 直接体现为成片在剪辑点跳变。
abstract final class _SchemaValidators {
  static const Set<String> _shotSizes = {
    'close_up',
    'medium_close_up',
    'medium',
    'full',
    'long',
    'extreme_long',
  };
  static const Set<String> _moods = {
    'depressing',
    'excited',
    'warm',
    'battle',
    'suspense',
    'relaxed',
    'sad',
  };
  static const Set<String> _functions = {
    'opening',
    'advance',
    'burst',
    'ending',
  };

  /// 景别档位差（spec: 相邻片段衔接）。用于判断两镜的景别是否差 2 档以上。
  ///
  /// 档位按枚举声明顺序：特写最近、大远景最远。这是「离观众多远」的自然排序，
  /// 与 `StudioShotSize.values` 的顺序一致，所以直接用 index。
  static int _shotSizeRank(String id) {
    const order = [
      'close_up',
      'medium_close_up',
      'medium',
      'full',
      'long',
      'extreme_long',
    ];
    final index = order.indexOf(id);
    return index < 0 ? 2 : index;
  }

  /// 提取一个分镜的景别 id（不做合法性判断，调用方已校验过）。
  static String _shotSizeOf(Map<String, dynamic> shot) =>
      _normalizeShotSize(shot['shot_size'] as String?) ?? 'medium';

  /// 两镜是否形成「明显差异」（spec: 相邻片段末镜与首镜至少满足一项）。
  ///
  /// 三项条件：主体类型不同 / 景别差 ≥2 档 / 角度差 ≥90°。工坊的分镜模型
  /// 没有显式的「拍摄角度」字段（角度信息隐含在 `camera_move` 里），所以
  /// 角度差无法可靠判定——这里只校验前两项，第三项作为已知缺口记录在
  /// design 的 Open Questions 之外，靠 `boundary_reason` 让人工审查兜底。
  static bool _hasVisibleDifference(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) {
    // 主体类型：用工WM的 character_ids 是否相同近似。
    // 双人→单人、有人→空镜都会让 id 集合变化，覆盖了 spec 列的主要情形。
    final previousCast = ((previous['character_ids'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    final nextCast =
        ((next['character_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
    if (!previousCast.containsAll(nextCast) ||
        !nextCast.containsAll(previousCast)) {
      return true;
    }
    // 景别差 2 档以上。
    final rankDelta =
        (_shotSizeRank(_shotSizeOf(previous)) -
                _shotSizeRank(_shotSizeOf(next)))
            .abs();
    return rankDelta >= 2;
  }

  /// 校验片段数组（spec: 片段边界划分）。
  ///
  /// 失败条件：空数组、镜号重叠、未覆盖全部分镜、片段为空、目标时长与该片段
  /// 分镜时长之和不符、相邻片段衔接不足。
  static bool segmentsCoverAll(
    List<Map<String, dynamic>> segments,
    List<Map<String, dynamic>> shots,
  ) {
    if (segments.isEmpty) return false;
    final byNumber = {for (final s in shots) s['number'] as int: s};
    if (byNumber.isEmpty) return false;

    final covered = <int>{};
    // 按 shot_numbers 的首镜排序，保证「相邻片段」比较的是真正的叙事邻居。
    final ordered = [...segments]..sort((a, b) {
      final aFirst = ((a['shot_numbers'] as List?)?.firstOrNull as num?)
          ?.toInt();
      final bFirst = ((b['shot_numbers'] as List?)?.firstOrNull as num?)
          ?.toInt();
      return (aFirst ?? 0).compareTo(bFirst ?? 0);
    });

    Map<String, dynamic>? previousLastShot;
    for (final segment in ordered) {
      final numbers =
          (segment['shot_numbers'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .toList() ??
          const [];
      if (numbers.isEmpty) return false;
      for (final n in numbers) {
        if (!byNumber.containsKey(n)) return false;
        if (!covered.add(n)) return false; // 重叠
      }
      // 目标时长必须落在该片段分镜时长之和的 ±1 秒内。
      //
      // 这个 ±1 秒是**硬门槛**（超过就拒收），而 `duration_deviation_sec`
      // 报的是全片总和偏差、只用于 UI 提示。两者分工：前者防"AI 完全没计时",
      // 后者让用户看见"AI 计时但有点漂"。
      final expected = numbers
          .map((n) => (byNumber[n]!['duration_sec'] as num).toDouble())
          .fold<double>(0, (a, b) => a + b);
      final target = (segment['target_duration_sec'] as num?)?.toDouble();
      if (target == null || (target - expected).abs() > 1.0) return false;

      final lastShot = byNumber[numbers.last]!;
      if (previousLastShot != null &&
          !_hasVisibleDifference(previousLastShot, byNumber[numbers.first]!)) {
        return false;
      }
      previousLastShot = lastShot;
    }

    return covered.length == byNumber.length &&
        covered.containsAll(byNumber.keys);
  }

  static Map<String, dynamic>? scriptBreakdown(Map<String, dynamic> json) {
    final shotsRaw = json['shots'];
    if (shotsRaw is! List || shotsRaw.isEmpty) return null;
    final shots = <Map<String, dynamic>>[];
    for (final entry in shotsRaw) {
      if (entry is! Map) return null;
      final shot = entry.map((k, v) => MapEntry(k as String, v));
      final number = (shot['number'] as num?)?.toInt();
      final duration = (shot['duration_sec'] as num?)?.toDouble();
      final dialogue = (shot['dialogue'] as String? ?? '').trim();
      final actionZh = (shot['action_zh'] as String? ?? '').trim();
      if (number == null || number < 1) return null;
      if (duration == null || duration < 3.0 || duration > 12.0) return null;
      if (actionZh.isEmpty) return null;
      // 台词字数硬约束：时长 × 5 字/秒 + 预估秒数标注容差
      if (dialogue.length > (duration * 5).floor() + 15) return null;
      final shotSize = _normalizeShotSize(shot['shot_size'] as String?);
      final mood = _normalizeMood(shot['mood'] as String?);
      final fn = _normalizeFunction(shot['function'] as String?);
      if (shotSize == null || mood == null || fn == null) return null;

      final beatId = (shot['beat_id'] as String? ?? '').trim();
      final cutReason = (shot['cut_reason'] as String? ?? '').trim();
      final visualTask = (shot['visual_task'] as String? ?? '').trim();
      final voiceType = (shot['voice_type'] ?? shot['voiceType'] as String? ?? 'dialogue').trim().toLowerCase();

      final directorDecisionsRaw = shot['director_decisions'];
      Map<String, dynamic>? directorDecisions;
      if (directorDecisionsRaw is Map) {
        directorDecisions = directorDecisionsRaw.map(
          (k, v) => MapEntry(k as String, v?.toString() ?? ''),
        );
      }

      final combatStepsRaw = shot['combat_steps'];
      List<Map<String, dynamic>>? combatSteps;
      if (combatStepsRaw is List) {
        combatSteps = combatStepsRaw
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k as String, v)))
            .toList();
      }

      shots.add({
        'number': number,
        'duration_sec': duration,
        'shot_size': shotSize,
        'mood': mood,
        'function': fn,
        'action_zh': actionZh,
        'dialogue': dialogue,
        if (voiceType.isNotEmpty && voiceType != 'dialogue') 'voice_type': voiceType,
        'character_ids':
            (shot['character_ids'] as List?)?.cast<String>() ?? const [],
        'scene_id': shot['scene_id'] as String? ?? '',
        'camera_move': shot['camera_move'] as String? ?? '',
        'beat_id': beatId,
        'cut_reason': cutReason,
        'visual_task': visualTask,
        if (directorDecisions != null) 'director_decisions': directorDecisions,
        if (combatSteps != null) 'combat_steps': combatSteps,
        'continuity': _normalizeContinuity(shot['continuity']),
      });
    }

    // 片段结构：有则校验，无则由调用方走迁移路径（旧版数据/单镜重生成）。
    final segmentsRaw = json['segments'];
    if (segmentsRaw is List && segmentsRaw.isNotEmpty) {
      final segments = <Map<String, dynamic>>[];
      for (final entry in segmentsRaw) {
        if (entry is! Map) return null;
        final segment = entry.map((k, v) => MapEntry(k as String, v));
        final id = (segment['segment_id'] as num?)?.toInt();
        final reason = (segment['boundary_reason'] as String? ?? '').trim();
        if (id == null || id < 1) return null;
        if (reason.isEmpty) return null;
        segments.add({
          'id': 'seg-$id',
          'segment_id': id,
          'target_duration_sec':
              (segment['target_duration_sec'] as num?)?.toInt() ?? 0,
          'boundary_reason': reason,
          'shot_numbers':
              (segment['shot_numbers'] as List?)
                  ?.whereType<num>()
                  .map((n) => n.toInt())
                  .toList() ??
              const [],
        });
      }
      if (!segmentsCoverAll(segments, shots)) return null;
      return {
        'shots': shots,
        'segments': segments,
        // 片段时长之和与分镜时长之和的偏差。AI 划边界时经常把 target_duration_sec
        // 填成"拍脑袋"的整数，偏差大意味着它没真的按分镜计时。这里算出来给
        // UI 标注（spec: 单集片段数量与时长自洽），但不因此拒收——偏差本身
        // 不让数据不可用，用户改一下数字就好。
        'duration_deviation_sec':
            _segmentDurationDeviation(segments, shots),
      };
    }

    return {'shots': shots};
  }

  /// 片段目标时长之和 − 分镜建议时长之和（秒）。
  ///
  /// 正数表示 AI 把片段估长了。调用方（UI）按相对偏差是否超过 20% 决定是否
  /// 标注「时长冲突」——阈值放在 UI 而不是这里，因为"要不要打扰用户"是展示
  /// 决策，不是数据正确性问题。
  static int _segmentDurationDeviation(
    List<Map<String, dynamic>> segments,
    List<Map<String, dynamic>> shots,
  ) {
    final shotTotal = shots.fold<int>(
      0,
      (sum, s) => sum + ((s['duration_sec'] as num?)?.toInt() ?? 0),
    );
    final segmentTotal = segments.fold<int>(
      0,
      (sum, s) => sum + ((s['target_duration_sec'] as num?)?.toInt() ?? 0),
    );
    return segmentTotal - shotTotal;
  }

  /// 归一化 continuity 对象。缺字段补空串/空数组，类型不符整体退回空台账。
  ///
  /// 退回空台账而不是判失败：台账是「可选增强」，为空只影响片段提示词的绝对
  /// 状态描述，不影响分镜本身的可用性。UI 靠 [ShotContinuity.isEmpty] 提示
  /// 用户补填。
  static Map<String, dynamic> _normalizeContinuity(Object? raw) {
    if (raw is! Map) return ShotContinuity.empty.toJson();
    final json = raw.map((k, v) => MapEntry(k as String, v));
    String text(String key) => (json[key] as String? ?? '').trim();

    DynamicExitState? dynamicExitState;
    final dynamicExitRaw = json['dynamic_exit_state'];
    if (dynamicExitRaw is Map) {
      dynamicExitState = DynamicExitState.fromJson(
        dynamicExitRaw.map((k, v) => MapEntry(k as String, v)),
      );
    }

    return ShotContinuity(
      worldPosition: text('world_position'),
      screenPosition: text('screen_position'),
      holdingLeft: text('holding_left'),
      holdingRight: text('holding_right'),
      lightingState: text('lighting_state'),
      stateChanges:
          (json['state_changes'] as List?)?.cast<String>() ?? const [],
      dynamicExitState: dynamicExitState ?? DynamicExitState.empty,
    ).toJson();
  }

  static Map<String, dynamic>? shotRegenerate(Map<String, dynamic> json) {
    final shotRaw = json['shot'];
    if (shotRaw is! Map) return null;
    final validated = scriptBreakdown({'shots': [shotRaw]});
    if (validated == null) return null;
    final shots = (validated['shots'] as List).cast<Map<String, dynamic>>();
    return {'shot': shots.first};
  }

  static Map<String, dynamic>? promptTranslation(Map<String, dynamic> json) {
    final positive = (json['prompt_positive'] as String? ?? '').trim();
    final negative = (json['prompt_negative'] as String? ?? '').trim();
    final facialZh = (json['facial_features_zh'] as String? ?? '').trim();
    final facialPos = (json['facial_prompt'] as String? ?? '').trim();
    final attireZh = (json['default_attire_zh'] as String? ?? '').trim();
    final attirePos = (json['attire_prompt'] as String? ?? '').trim();

    final effectivePositive = positive.isNotEmpty
        ? positive
        : [if (facialPos.isNotEmpty) facialPos, if (attirePos.isNotEmpty) attirePos].join(', ');
    if (effectivePositive.isEmpty) return null;

    return {
      'prompt_positive': effectivePositive,
      'prompt_negative': negative,
      'facial_features_zh': facialZh,
      'facial_prompt': facialPos,
      'default_attire_zh': attireZh,
      'attire_prompt': attirePos,
    };
  }

  static Map<String, dynamic>? ideaIncubation(Map<String, dynamic> json) {
    final directionsRaw = json['directions'];
    if (directionsRaw is! List || directionsRaw.length != 3) return null;
    final directions = <Map<String, dynamic>>[];
    for (final entry in directionsRaw) {
      if (entry is! Map) return null;
      final d = entry.map((k, v) => MapEntry(k as String, v));
      final title = (d['title'] as String? ?? '').trim();
      final hook = (d['hook'] as String? ?? '').trim();
      if (title.isEmpty || hook.isEmpty) return null;
      directions.add({
        'title': title,
        'hook': hook,
        'twist': d['twist'] as String? ?? '',
        'pacing': d['pacing'] as String? ?? '',
        'strategy': d['strategy'] as String? ?? '',
      });
    }
    return {'directions': directions};
  }

  static Map<String, dynamic>? novelMasterExtraction(Map<String, dynamic> json) {
    final worldview = (json['worldview'] as String? ?? '').trim();
    final eraGenre = (json['era_genre'] as String? ?? '').trim();
    final aestheticStyle = (json['aesthetic_style'] as String? ?? '').trim();
    final styleTokens = (json['style_tokens'] as String? ?? '').trim();
    final charsRaw = json['characters'];
    final scenesRaw = json['scenes'];
    if (worldview.isEmpty || charsRaw is! List || scenesRaw is! List) return null;

    final characters = <Map<String, dynamic>>[];
    for (final c in charsRaw) {
      if (c is! Map) continue;
      final name = (c['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      characters.add({
        'name': name,
        'description_zh': (c['description_zh'] as String? ?? '').trim(),
        'facial_features_zh': (c['facial_features_zh'] as String? ?? '').trim(),
        'facial_prompt': (c['facial_prompt'] as String? ?? '').trim(),
        'default_attire_zh': (c['default_attire_zh'] as String? ?? '').trim(),
        'attire_prompt': (c['attire_prompt'] as String? ?? '').trim(),
        'personality': (c['personality'] as String? ?? '').trim(),
        'prompt_positive': (c['prompt_positive'] as String? ?? '').trim(),
        'prompt_negative': (c['prompt_negative'] as String? ?? '').trim(),
      });
    }

    final scenes = <Map<String, dynamic>>[];
    for (final s in scenesRaw) {
      if (s is! Map) continue;
      final name = (s['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      var promptEn = (s['prompt_en'] as String? ?? '').trim();
      if (promptEn.isNotEmpty && !promptEn.toLowerCase().contains('empty scene')) {
        promptEn = 'empty scene, no humans, pure architectural scenery, $promptEn';
      }
      scenes.add({
        'name': name,
        'description_zh': (s['description_zh'] as String? ?? '').trim(),
        'prompt_en': promptEn,
      });
    }

    final propsRaw = json['props'];
    final props = <Map<String, dynamic>>[];
    if (propsRaw is List) {
      for (final p in propsRaw) {
        if (p is! Map) continue;
        final name = (p['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        props.add({
          'name': name,
          'description_zh': (p['description_zh'] as String? ?? '').trim(),
          'prompt_en': (p['prompt_en'] as String? ?? '').trim(),
        });
      }
    }

    if (characters.isEmpty) return null;

    return {
      'worldview': worldview,
      'era_genre': eraGenre,
      'aesthetic_style': aestheticStyle,
      'style_tokens': styleTokens,
      'characters': characters,
      'scenes': scenes,
      'props': props,
    };
  }

  static Map<String, dynamic>? novelEpisodeSegmentation(Map<String, dynamic> json) {
    final epsRaw = json['episodes'];
    if (epsRaw is! List || epsRaw.isEmpty) return null;

    final episodes = <Map<String, dynamic>>[];
    for (var i = 0; i < epsRaw.length; i++) {
      final entry = epsRaw[i];
      if (entry is! Map) continue;
      final title = (entry['title'] as String? ?? '第${i + 1}集').trim();
      final synopsis = (entry['synopsis'] as String? ?? '').trim();
      final summary = (entry['summary'] as String? ?? '').trim();
      final hook = (entry['hook'] as String? ?? '').trim();
      final index = (entry['index'] as num?)?.toInt() ?? (i + 1);

      episodes.add({
        'index': index,
        'title': title,
        'synopsis': synopsis.isNotEmpty ? synopsis : title,
        'summary': summary,
        'hook': hook,
      });
    }

    if (episodes.isEmpty) return null;

    return {
      'total_recommended_episodes':
          (json['total_recommended_episodes'] as num?)?.toInt() ?? episodes.length,
      'episodes': episodes,
    };
  }

  static Map<String, dynamic>? novelChapterAdaptation(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? '').trim();
    final synopsis = (json['synopsis'] as String? ?? '').trim();
    final summary = (json['summary'] as String? ?? '').trim();
    final hook = (json['hook'] as String? ?? '').trim();

    if (title.isEmpty || synopsis.isEmpty || synopsis.length < 100) return null;

    final result = <String, dynamic>{
      'title': title,
      'synopsis': synopsis,
      'summary': summary.isNotEmpty ? summary : synopsis,
      'hook': hook,
    };

    final scenesRaw = json['scenes'];
    final parsedScenes = <DramaScene>[];
    if (scenesRaw is List) {
      final scenes = <Map<String, dynamic>>[];
      for (var sIdx = 0; sIdx < scenesRaw.length; sIdx++) {
        final sEntry = scenesRaw[sIdx];
        if (sEntry is! Map) continue;
        final s = sEntry.map((k, v) => MapEntry(k as String, v));
        final id = (s['id'] as String? ?? '').trim();
        final sceneNumber =
            (s['scene_number'] as num?)?.toInt() ?? (sIdx + 1);
        final sTitle = (s['title'] as String? ?? '').trim();
        final location = (s['location'] as String? ?? '').trim();
        final setting = (s['setting'] as String? ?? '内景').trim();
        final timeOfDay = (s['time_of_day'] as String? ?? '').trim();
        final atmosphere = (s['atmosphere'] as String? ?? '').trim();
        final lightDir = (s['primary_light_world_direction'] as String? ?? '').trim();
        final landmarks = (s['landmarks'] as List?)?.cast<String>() ?? const [];
        final charIds = (s['character_ids'] as List?)?.cast<String>() ?? const [];
        final dramaticObjective = (s['dramatic_objective'] as String? ?? '').trim();
        final entryState = (s['entry_state'] as String? ?? '').trim();
        final exitState = (s['exit_state'] as String? ?? '').trim();

        final beatsRaw = s['beats'];
        final beats = <Map<String, dynamic>>[];
        if (beatsRaw is List) {
          for (var bIdx = 0; bIdx < beatsRaw.length; bIdx++) {
            final bEntry = beatsRaw[bIdx];
            if (bEntry is! Map) continue;
            final b = bEntry.map((k, v) => MapEntry(k as String, v));
            final bId = (b['id'] as String? ?? '').trim();
            final bOrder = (b['order'] as num?)?.toInt() ?? (bIdx + 1);
            final bName = (b['name'] as String? ?? '').trim();
            final bAction = (b['action'] as String? ?? '').trim();
            final bSpeaker = (b['dialogue_speaker'] as String? ?? '').trim();
            final bDialogue = (b['dialogue'] as String? ?? '').trim();
            final bVoiceType = (b['voice_type'] as String? ?? 'dialogue').trim().toLowerCase();
            final bSubtext = (b['subtext'] as String? ?? '').trim();
            final bDramaticFunction = (b['dramatic_function'] as String? ?? '').trim();
            final bEstSec = (b['estimated_sec'] as num?)?.toDouble() ??
                AiConstraintEngine.calculateDynamicDurationSec(dialogue: bDialogue, actionZh: bAction);
            final bCharIds = (b['character_ids'] as List?)?.cast<String>() ?? const [];
            final bShotSize = (b['shot_size'] ?? b['shotSize'] as String? ?? '').trim();
            final bCameraStaging = (b['camera_staging'] ?? b['cameraStaging'] as String? ?? '').trim();
            final bCameraMove = (b['camera_move'] ?? b['cameraMove'] as String? ?? '').trim();
            final bScreenPosition = (b['screen_position'] ?? b['screenPosition'] as String? ?? '').trim();
            final bGazeDirection = (b['gaze_direction'] ?? b['gazeDirection'] as String? ?? '').trim();

            beats.add({
              'id': bId.isNotEmpty ? bId : 'B${bIdx + 1}',
              'scene_id': id.isNotEmpty ? id : 'SC${sIdx + 1}',
              'order': bOrder,
              'name': bName.isNotEmpty ? bName : '节拍$bOrder',
              'action': bAction,
              'dialogue_speaker': bSpeaker,
              'dialogue': bDialogue,
              'voice_type': bVoiceType.isNotEmpty ? bVoiceType : 'dialogue',
              'subtext': bSubtext,
              'dramatic_function': bDramaticFunction,
              'estimated_sec': bEstSec,
              'character_ids': bCharIds,
              if (bShotSize.isNotEmpty) 'shot_size': bShotSize,
              if (bCameraStaging.isNotEmpty) 'camera_staging': bCameraStaging,
              if (bCameraMove.isNotEmpty) 'camera_move': bCameraMove,
              if (bScreenPosition.isNotEmpty) 'screen_position': bScreenPosition,
              if (bGazeDirection.isNotEmpty) 'gaze_direction': bGazeDirection,
            });
          }
        }

        final sceneMap = <String, dynamic>{
          'id': id.isNotEmpty ? id : 'SC${sIdx + 1}',
          'scene_number': sceneNumber,
          'title': sTitle.isNotEmpty ? sTitle : '第$sceneNumber场',
          'location': location,
          'setting': setting,
          'time_of_day': timeOfDay,
          'atmosphere': atmosphere,
          'primary_light_world_direction': lightDir,
          'landmarks': landmarks,
          'character_ids': charIds,
          'dramatic_objective': dramaticObjective,
          'entry_state': entryState,
          'exit_state': exitState,
          'beats': beats,
        };
        scenes.add(sceneMap);
        parsedScenes.add(DramaScene.fromJson(sceneMap));
      }
      result['scenes'] = scenes;
    }

    var screenplayText = (json['screenplay_text'] as String? ?? '').trim();
    if (screenplayText.isEmpty && parsedScenes.isNotEmpty) {
      screenplayText = DramaScene.exportToMarkdown(parsedScenes);
    }
    result['screenplay_text'] = screenplayText;

    final contractRaw = json['protected_contract'];
    if (contractRaw is Map) {
      result['protected_contract'] =
          contractRaw.map((k, v) => MapEntry(k as String, v));
    }

    return result;
  }

  static Map<String, dynamic>? titleGeneration(Map<String, dynamic> json) {
    final titlesRaw = json['titles'];
    if (titlesRaw is! List || titlesRaw.length != 3) return null;
    final titles = <Map<String, dynamic>>[];
    for (final entry in titlesRaw) {
      if (entry is! Map) return null;
      final t = entry.map((k, v) => MapEntry(k as String, v));
      final text = (t['text'] as String? ?? '').trim();
      if (text.isEmpty) return null;
      titles.add({
        'style': t['style'] as String? ?? '',
        'text': text,
      });
    }
    return {'titles': titles};
  }

  static Map<String, dynamic>? bgmRecommend(Map<String, dynamic> json) {
    final recsRaw = json['recommendations'];
    if (recsRaw is! List || recsRaw.isEmpty) return null;
    final recs = <Map<String, dynamic>>[];
    for (final entry in recsRaw) {
      if (entry is! Map) return null;
      final r = entry.map((k, v) => MapEntry(k as String, v));
      final name = (r['name'] as String? ?? '').trim();
      if (name.isEmpty) return null;
      recs.add({
        'name': name,
        'score': (r['score'] as num?)?.toInt() ?? 0,
        'reason': r['reason'] as String? ?? '',
      });
    }
    recs.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return {'recommendations': recs};
  }

  static Map<String, dynamic>? episodeSummary(Map<String, dynamic> json) {
    final summary = (json['summary'] as String? ?? '').trim();
    final hook = (json['hook'] as String? ?? '').trim();
    if (summary.isEmpty) return null;
    return {'summary': summary, 'hook': hook};
  }

  static Map<String, dynamic>? screenplayGeneration(Map<String, dynamic> json) {
    final scenesRaw = json['scenes'];
    if (scenesRaw is! List || scenesRaw.isEmpty) return null;
    final scenes = <Map<String, dynamic>>[];
    for (final sEntry in scenesRaw) {
      if (sEntry is! Map) return null;
      final s = sEntry.map((k, v) => MapEntry(k as String, v));
      final id = (s['id'] as String? ?? '').trim();
      final sceneNumber =
          (s['scene_number'] as num?)?.toInt() ?? (scenes.length + 1);
      final title = (s['title'] as String? ?? '').trim();
      final location = (s['location'] as String? ?? '').trim();
      final setting = (s['setting'] as String? ?? '内景').trim();
      final timeOfDay = (s['time_of_day'] as String? ?? '日景').trim();
      final atmosphere = (s['atmosphere'] as String? ?? '').trim();
      final characterIds =
          (s['character_ids'] as List?)?.cast<String>() ?? const [];

      final beatsRaw = s['beats'];
      final beats = <Map<String, dynamic>>[];
      if (beatsRaw is List) {
        for (final bEntry in beatsRaw) {
          if (bEntry is! Map) continue;
          final b = bEntry.map((k, v) => MapEntry(k as String, v));
          final bId = (b['id'] as String? ?? '').trim();
          final bOrder =
              (b['order'] as num?)?.toInt() ?? (beats.length + 1);
          final bName = (b['name'] as String? ?? '').trim();
          final bAction = (b['action'] as String? ?? '').trim();
          final bSpeaker =
              (b['dialogue_speaker'] as String? ?? '').trim();
          final bDialogue = (b['dialogue'] as String? ?? '').trim();
          final bVoiceType =
              (b['voice_type'] as String? ?? 'dialogue').trim().toLowerCase();
          final bSubtext = (b['subtext'] as String? ?? '').trim();
          final bEstSec =
              (b['estimated_sec'] as num?)?.toDouble() ?? 4.0;
          final bCharIds =
              (b['character_ids'] as List?)?.cast<String>() ?? const [];
          final bShotSize = (b['shot_size'] ?? b['shotSize'] as String? ?? '').trim();
          final bCameraStaging = (b['camera_staging'] ?? b['cameraStaging'] as String? ?? '').trim();
          final bCameraMove = (b['camera_move'] ?? b['cameraMove'] as String? ?? '').trim();
          final bScreenPosition = (b['screen_position'] ?? b['screenPosition'] as String? ?? '').trim();
          final bGazeDirection = (b['gaze_direction'] ?? b['gazeDirection'] as String? ?? '').trim();

          beats.add({
            'id': bId.isNotEmpty ? bId : 'B${beats.length + 1}',
            'scene_id': id.isNotEmpty ? id : 'SC${scenes.length + 1}',
            'order': bOrder,
            'name': bName,
            'action': bAction,
            'dialogue_speaker': bSpeaker,
            'dialogue': bDialogue,
            'voice_type': bVoiceType.isNotEmpty ? bVoiceType : 'dialogue',
            'subtext': bSubtext,
            'estimated_sec': bEstSec,
            'character_ids': bCharIds,
            if (bShotSize.isNotEmpty) 'shot_size': bShotSize,
            if (bCameraStaging.isNotEmpty) 'camera_staging': bCameraStaging,
            if (bCameraMove.isNotEmpty) 'camera_move': bCameraMove,
            if (bScreenPosition.isNotEmpty) 'screen_position': bScreenPosition,
            if (bGazeDirection.isNotEmpty) 'gaze_direction': bGazeDirection,
          });
        }
      }

      scenes.add({
        'id': id.isNotEmpty ? id : 'SC${scenes.length + 1}',
        'scene_number': sceneNumber,
        'title': title.isNotEmpty ? title : '第$sceneNumber场',
        'location': location,
        'setting': setting,
        'time_of_day': timeOfDay,
        'atmosphere': atmosphere,
        'character_ids': characterIds,
        'beats': beats,
      });
    }

    return {'scenes': scenes};
  }

  static Map<String, dynamic>? sceneSpatialDeconstruction(Map<String, dynamic> json) {
    final rawViews = json['views'] as Map? ?? json;
    final views = <String, Map<String, dynamic>>{};

    for (final dir in SceneDirection.values) {
      final key = dir.key;
      final entry = rawViews[key] ?? rawViews[dir.name];
      if (entry is! Map && entry is! String) continue;
      String zh = '';
      String en = '';
      if (entry is Map) {
        final viewMap = entry.map((k, v) => MapEntry(k.toString(), v));
        zh = (viewMap['description_zh'] as String? ??
                viewMap['zh'] as String? ??
                viewMap['descriptionZh'] as String? ??
                '')
            .trim();
        en = (viewMap['prompt_en'] as String? ??
                viewMap['en'] as String? ??
                viewMap['promptEn'] as String? ??
                '')
            .trim();
      } else if (entry is String) {
        zh = entry.trim();
      }

      final cleanedZh = _cleanseSpatialCharacters(zh);
      final cleanedEn = en.isNotEmpty ? _cleanseSpatialCharactersEn(en, dir) : '';

      if (cleanedZh.isNotEmpty || cleanedEn.isNotEmpty) {
        views[dir.name] = {
          'direction': dir.key,
          'description_zh': cleanedZh,
          'prompt_en': cleanedEn,
        };
      }
    }

    if (views.isEmpty) return null;

    return {'views': views};
  }

  static String _cleanseSpatialCharacters(String text) {
    if (text.isEmpty) return text;
    var result = text;
    final clauses = result.split(RegExp(r'[，。！？；]'));
    const characterKeywords = [
      '公子', '草莽', '佳人', '少年', '少女', '青年', '老者', '男子', '女子',
      '男人', '女人', '众人', '群雄', '两人', '几人', '侍女', '侍卫', '护卫',
      '守卫', '卫兵', '随从', '主角', '反派', '刺客', '掌柜', '宾客', '仆役',
      '路人', '身影', '站着', '坐着', '走过', '他', '她', '他们', '她们',
      '密谋', '交谈', '打斗', '发酵', '耳目', '情报'
    ];
    final keptClauses = <String>[];
    for (final clause in clauses) {
      final trimmed = clause.trim();
      if (trimmed.isEmpty) continue;
      final hasCharacter = characterKeywords.any((k) => trimmed.contains(k));
      if (!hasCharacter) {
        keptClauses.add(trimmed);
      }
    }
    if (keptClauses.isEmpty) {
      return text
          .replaceAll(RegExp(r'(富家公子与江湖草莽在此交错.*?发酵。?|暗藏耳目与情报。?|在此密谋.*?。?)'), '')
          .trim();
    }
    return '${keptClauses.join('，')}。';
  }

  static String _cleanseSpatialCharactersEn(String text, SceneDirection dir) {
    if (text.isEmpty) return text;
    var result = text.trim();
    if (!result.toLowerCase().contains('empty room') && !result.toLowerCase().contains('no humans')) {
      result = '$result, empty room, no humans, cinematic lighting';
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // 取值域归一化
  // ---------------------------------------------------------------------------

  static String? _normalizeShotSize(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (_shotSizes.contains(v)) return v;
    // 常见中文直译：AI 有时不管提示词怎么说，直接回"特写"。
    const zhMap = {
      '特写': 'close_up',
      '近景': 'medium_close_up',
      '中景': 'medium',
      '全景': 'full',
      '远景': 'long',
      '大远景': 'extreme_long',
      'wide': 'full',
      'full_shot': 'full',
      'full': 'full',
    };
    return zhMap[value.trim()] ?? zhMap[v];
  }

  static String? _normalizeMood(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (_moods.contains(v)) return v;
    const zhMap = {
      '压抑': 'depressing',
      '激动': 'excited',
      '温馨': 'warm',
      '战斗': 'battle',
      '激烈': 'battle',
      '悬念': 'suspense',
      '轻松': 'relaxed',
      '悲伤': 'sad',
    };
    return zhMap[value.trim()];
  }

  static String? _normalizeFunction(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (_functions.contains(v)) return v;
    const zhMap = {
      '开场': 'opening',
      '推进': 'advance',
      '爆发': 'burst',
      '收尾': 'ending',
    };
    return zhMap[value.trim()];
  }
}
