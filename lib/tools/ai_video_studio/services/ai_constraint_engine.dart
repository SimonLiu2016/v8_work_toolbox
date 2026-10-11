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
import '../models/studio_models.dart' show ShotContinuity;

/// 工坊的 AI 任务类型。
///
/// 每个类型对应一组 System Prompt 模板与一个 JSON Schema。新增任务时在这里
/// 加枚举值 + 模板 + schema 三件套，漏掉任何一个都会在运行时才暴露。
enum StudioAiTask {
  /// 粗剧情大纲 → 结构化分镜列表。
  scriptBreakdown('script_breakdown', 'AI 拆分分镜'),

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
  novelChapterAdaptation('novel_chapter_adaptation', '单章小说影视化提炼');

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

  /// 制作类型 id（`drama` / `anime` / `narration`）。
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
  ///
  /// 与 [memoryContext] 分工：那个是「剧情发生了什么」，这个是「人物与道具
  /// 现在处于什么状态」。前者驱动情绪衔接，后者驱动首镜的绝对状态描述。
  /// 空串表示这是第一集，或上一集还没有台账。
  final String carryOverState;

  const ScriptContext({
    this.seriesName = '',
    this.productionType = 'drama',
    this.styleTokens = '',
    this.memoryContext = '',
    this.episodeIndex = 1,
    this.characterNames = const [],
    this.sceneNames = const [],
    this.carryOverState = '',
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
  ///
  /// 小说全案解构（Pass 1 世界观/角色库提取、Pass 2 分集规划）涉及数千字长文本与结构化大 JSON，
  /// 放宽至 240 秒（4 分钟），避免思维链推理大模型超时被掐断。其他短剧本拆解与单句运镜默认 120 秒。
  static Duration defaultTimeoutFor(StudioAiTask task) {
    switch (task) {
      case StudioAiTask.novelMasterExtraction:
      case StudioAiTask.novelEpisodeSegmentation:
      case StudioAiTask.novelChapterAdaptation:
        return const Duration(seconds: 240);
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
    String negativeHint = '',
  }) {
    return run(
      task: StudioAiTask.promptTranslation,
      userPrompt:
          '【制作类型】$productionType\n'
          '【角色中文描述】\n$descriptionZh'
          '${negativeHint.trim().isEmpty ? '' : '\n【额外负向要求】$negativeHint'}',
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
      '2. 建议时长 duration_sec 取值必须在 3.0 到 5.0 秒之间。\n'
      '3. shot_size 只能是：close_up / medium_close_up / medium / full / long / extreme_long。\n'
      '4. mood 只能是：depressing / excited / warm / battle / suspense / relaxed / sad。\n'
      '5. function 只能是：opening / advance / burst / ending。\n'
      '6. action_zh 必须是简体中文，字数严格控制在 30 到 50 字之间！遵循【主体 + 动作 + 环境】三层视觉化结构，且动作遵循单动词/微动作原则（如：猛然抬头、缓缓推门、咬牙握拳），杜绝抽象情绪词。\n'
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

  /// 小说全案第一阶段模板（提炼世界观、风格词、角色库、场景库）。
  static const String _promptNovelMasterExtraction =
      '你是一位资深网络文学影视化与爆款短剧 IP 改编架构师。'
      '你的任务是从用户给出的长篇小说原著内容中，提炼出可以直接指导短视频制作的核心 IP 主库资产。\n'
      '\n'
      '【硬约束】\n'
      '1. worldview：提炼时代背景、核心规则矛盾、生存利益冲突与叙事主调，控制在 300 字以内。\n'
      '2. style_tokens：提炼全局画面风格锁英文提示词，如 "cinematic film still, photorealistic, 8k, moody lighting, vertical composition, ultra detailed"。\n'
      '3. characters：提炼小说中最关键的 2 到 6 位核心登场角色（主角、主要反派、核心配角），每个角色包含：\n'
      '   - name: 角色名字（与原文一致）\n'
      '   - description_zh: 中文外貌金标准描写（精确至发型、脸型、标志性服饰、微特征如伤疤/眼镜），避免模糊抽象\n'
      '   - personality: 性格与身份设定（30字以内）\n'
      '   - prompt_positive: 适配 AI 绘画的英文正向 Prompt，包含角色外貌服装与画质词（60个英文单词以内）\n'
      '   - prompt_negative: 英文负向 Prompt，如 "blurry, low quality, deformed hands, extra limbs"\n'
      '4. scenes：提炼 2 到 6 个故事高频发生的核心常驻场景，每个场景包含：\n'
      '   - name: 场景名称（如“雨夜霓虹巷道”、“冷调审讯室”）\n'
      '   - description_zh: 中文空间与环境光影描写（60字以内）\n'
      '   - prompt_en: 适配 AI 绘画的英文环境 Prompt（40个英文单词以内）\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"worldview": "世界观设定...", "style_tokens": "cinematic film still...", '
      '"characters": [{"name": "主角名", "description_zh": "外貌描写...", "personality": "性格...", "prompt_positive": "1man...", "prompt_negative": "blurry..."}], '
      '"scenes": [{"name": "场景名", "description_zh": "环境描述...", "prompt_en": "interior modern office..."}]}';

  /// 小说全案第二阶段模板（剧情高潮检测与分集规划）。
  static const String _promptNovelEpisodeSegmentation =
      '你是一位专精于爆款竖屏短剧的分集编剧。你的任务是根据提供的小说剧情主线与世界观，'
      '基于【剧情高潮点检测】与【期望→冲突→反转→留钩】的短剧节奏，将故事自动拆解为适宜短视频制作的分集大纲。\n'
      '\n'
      '【硬约束】\n'
      '1. 依据原著事件冲突密度与高潮峰值，自动规划 8 到 20 集短剧（每集对应 1~2 分钟短视频体量）。\n'
      '2. 输出 total_recommended_episodes（推荐总集数）及 episodes 数组。\n'
      '3. 每集包含：\n'
      '   - index: 集序号（从 1 开始连续递增）\n'
      '   - title: 抓人眼球的短剧集标题（10字以内，如“雨夜归来”、“暗巷对决”）\n'
      '   - synopsis: 本集粗剧情大纲（80~150字，清晰交代开局冲突、矛盾升级与爆发点）\n'
      '   - summary: 本集精炼前情记忆摘要（150字以内，供下游跨集连贯性注入）\n'
      '   - hook: 本集结尾高潮截断点的悬念钩子（如身份即将揭晓、刀尖悬停等强反转，60字以内）\n'
      '4. 第一集前 3 秒必须爆发核心冲突，最后一集给出阶段性高潮闭环。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"total_recommended_episodes": 10, "episodes": [{"index": 1, "title": "第一集标题", '
      '"synopsis": "本集粗大纲...", "summary": "前情摘要...", "hook": "集尾悬念..."}]}';

  /// 单章小说影视化剧本大纲深度提炼模板。
  static const String _promptNovelChapterAdaptation =
      '你是一位专精于爆款竖屏短剧的改编编剧。你的任务是通读用户给出的单章小说完整内容，'
      '依据短剧视听规律【开局抓手 → 矛盾推进 → 核心高潮 → 结尾留钩】四大核心结构，'
      '提炼出能够直接指导单集短剧拍摄的结构化单集影视大纲。\n'
      '\n'
      '【硬约束】\n'
      '1. title: 拟定抓人眼球的单集标题（10字以内，如“暗室对决”、“杀局浮现”）。\n'
      '2. synopsis: 本集影视化完整粗大纲，字数严格在 300 到 500 个汉字之间！必须清晰覆盖全章剧情脉络，按以下四个戏剧阶段完整叙述：\n'
      '   - 【开局抓手】：前 3 秒爆发的核心危机或悬念冲突；\n'
      '   - 【矛盾推进】：人物对抗升级、线索交织与行动过程；\n'
      '   - 【核心高潮】：本章情绪与戏剧张力最强的高光爆发事件；\n'
      '   - 【本集断点】：章末最扣人心弦的转折或悬念。\n'
      '   严禁仅摘抄开头，必须完整贯穿全章事件始末！\n'
      '3. summary: 本集精炼前情摘要（150字以内，客观交代本集核心剧情沉淀，供下游跨集连贯性使用）。\n'
      '4. hook: 本集结尾截断留钩（50字以内，突出未解之谜或致命危机）。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"title": "单集标题", "synopsis": "本集影视化大纲（300~500字）...", "summary": "前情摘要...", "hook": "末尾悬念..."}\n'
      '\n'
      '【Example】\n'
      '{"title": "密室杀局", "synopsis": "【开局抓手】暴雨之夜，韩立推开神手谷密室木门，赫然发现墨大夫面色铁青，手中短刃寒光逼人。【矛盾推进】墨大夫步步紧逼逼问长春功第四层口诀，韩立借取药引为由退至药柜死角，暗中将毒粉藏于指缝周旋试探。【核心高潮】墨大夫骤然暴起施展鹰爪功锁喉，韩立生死一线间反手掷出毒粉迷其双目，二人近身扭打撞翻药架，短刃脱手刺入地面。【本集断点】墨大夫虽中剧毒却突然发出诡异怪笑，双目泛起渗人幽绿荧光，夺舍残魂破体而出悬浮半空。", "summary": "韩立与墨大夫在神手谷密室正面决裂，韩立利用毒粉反制墨大夫肉身。", "hook": "墨大夫临死之际泛起幽绿魂光，夺舍残魂即将扑向韩立。"}';

  /// Prompt 翻译模板（中文角色描述 → 英文正/负向）。
  static const String _promptPromptTranslation =
      '你是一位 AI 绘画提示词工程师。你的任务是把用户的中文角色外貌描述翻译为'
      '符合主流文生图引擎（Flux / Stable Diffusion 系列）规范的英文提示词。\n'
      '\n'
      '【硬约束】\n'
      '1. prompt_positive：英文，逗号分隔的词组，描述外貌、服装、神态与画风；'
      '必须包含画风与画质词（如 cinematic lighting, 8k, highly detailed）。\n'
      '2. prompt_negative：英文，包含常见瑕疵词（如 blurry, low quality, '
      'extra fingers, deformed hands, watermark, text）。\n'
      '3. 根据【制作类型】适配画风：\n'
      '   - drama（真人短剧）：写实风格，photorealistic, cinematic film still。\n'
      '   - anime（二次元/动态漫）：anime style, cel shading, clean line art。\n'
      '   - narration（图文解说）：illustration style, flat color, '
      'clean vector-like composition。\n'
      '4. prompt_positive 总长度不超过 120 个英文单词。\n'
      '5. 保持角色可辨识的核心特征（发型、瞳色、标志性服饰）不被稀释。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"prompt_positive": "english positive prompt", '
      '"prompt_negative": "english negative prompt"}\n'
      '\n'
      '【Example】\n'
      '{"prompt_positive": "1 young woman, sharp eyes, silver bob hair, '
      'scar on left cheek, black trench coat, rain soaked, photorealistic, '
      'cinematic film still, cinematic lighting, 8k, highly detailed", '
      '"prompt_negative": "blurry, low quality, extra fingers, deformed hands, '
      'watermark, text, oversaturated"}';

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
      '2. duration_sec 仍在 2 到 6 秒之间，且台词字数不超过 '
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
      if (duration == null || duration < 3.0 || duration > 5.0) return null;
      if (actionZh.isEmpty) return null;
      // 台词字数硬约束：时长 × 5 字/秒 + 预估秒数标注容差
      if (dialogue.length > (duration * 5).floor() + 15) return null;
      final shotSize = _normalizeShotSize(shot['shot_size'] as String?);
      final mood = _normalizeMood(shot['mood'] as String?);
      final fn = _normalizeFunction(shot['function'] as String?);
      if (shotSize == null || mood == null || fn == null) return null;
      shots.add({
        'number': number,
        'duration_sec': duration,
        'shot_size': shotSize,
        'mood': mood,
        'function': fn,
        'action_zh': actionZh,
        'dialogue': dialogue,
        'character_ids':
            (shot['character_ids'] as List?)?.cast<String>() ?? const [],
        'scene_id': shot['scene_id'] as String? ?? '',
        'camera_move': shot['camera_move'] as String? ?? '',
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
    return ShotContinuity(
      worldPosition: text('world_position'),
      screenPosition: text('screen_position'),
      holdingLeft: text('holding_left'),
      holdingRight: text('holding_right'),
      lightingState: text('lighting_state'),
      stateChanges:
          (json['state_changes'] as List?)?.cast<String>() ?? const [],
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
    if (positive.isEmpty) return null;
    return {
      'prompt_positive': positive,
      'prompt_negative': negative,
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
      scenes.add({
        'name': name,
        'description_zh': (s['description_zh'] as String? ?? '').trim(),
        'prompt_en': (s['prompt_en'] as String? ?? '').trim(),
      });
    }

    if (characters.isEmpty) return null;

    return {
      'worldview': worldview,
      'style_tokens': styleTokens,
      'characters': characters,
      'scenes': scenes,
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

    return {
      'title': title,
      'synopsis': synopsis,
      'summary': summary.isNotEmpty ? summary : synopsis,
      'hook': hook,
    };
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
