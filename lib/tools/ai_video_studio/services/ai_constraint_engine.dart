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
  shotRegenerate('shot_regenerate', '单镜重生成');

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

  const ScriptContext({
    this.seriesName = '',
    this.productionType = 'drama',
    this.styleTokens = '',
    this.memoryContext = '',
    this.episodeIndex = 1,
    this.characterNames = const [],
    this.sceneNames = const [],
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
    Duration timeout = const Duration(seconds: 120),
    int maxAttempts = maxAttempts,
  }) async {
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
          timeout: timeout,
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

  /// 粗剧情大纲 → 结构化分镜列表。
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
  static Future<ConstraintResult> shotRegenerate({
    required String currentShotJson,
    required String instruction,
    required ScriptContext context,
  }) {
    return run(
      task: StudioAiTask.shotRegenerate,
      userPrompt:
          '【剧集名称】${context.seriesName}\n'
          '【制作类型】${context.productionType}\n'
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
    }
  }

  static const String _commonOutputRules =
      '【输出规则】\n'
      '1. 只输出一个 JSON 对象，不要输出 Markdown 代码块标记、不要输出任何解释、'
      '前言或结语。\n'
      '2. 所有字符串字段必须有值（可为空字符串），不要省略任何字段。\n'
      '3. 严格使用下面 Example 中的字段名（英文 snake_case），不要新增或改名。\n'
      '4. 数字字段输出数字而非字符串。\n';

  /// 拆分分镜模板。
  ///
  /// 关键约束来自 spec「结构化分镜拆解」：分镜条目含镜号/建议时长(2-6 秒)/
  /// 景别/情绪/功能/动作/台词；台词字数不超过 时长(秒) × 5 个汉字；粗大纲要拆出
  /// 不少于 8 个分镜。
  static const String _promptScriptBreakdown =
      '你是一位专精于竖屏短剧的分镜师。你的任务是把用户给出的单集粗剧情大纲拆解为'
      '结构化分镜列表，供下游自动生成关键帧图像、配音与字幕。\n'
      '\n'
      '【硬约束】\n'
      '1. 拆出 8 到 12 个分镜，镜号 number 从 1 开始连续递增。\n'
      '2. 建议时长 duration_sec 取值 2 到 6 秒，且台词字数不得超过 '
      'duration_sec × 5 个汉字。\n'
      '3. shot_size 只能是：close_up / medium_close_up / medium / long / '
      'extreme_long。\n'
      '4. mood 只能是：depressing / excited / warm / battle / suspense / '
      'relaxed / sad。\n'
      '5. function 只能是：opening / advance / burst / ending。全集必须有恰好一个 '
      'opening 与恰好一个 ending。\n'
      '6. action_zh 与 dialogue 用简体中文；dialogue 可以为空字符串（纯动作镜头）。\n'
      '7. character_ids 只能从【可用角色】中选，没有可用角色清单时填空数组。\n'
      '8. scene_id 只能从【可用场景】中选，没有可用场景清单时填空字符串。\n'
      '9. camera_move 用英文摄影术语短语，例如 "low angle push-in"、'
      '"slow pan right"、"handheld follow"。\n'
      '10. 如有【跨集记忆】，首个分镜的情绪基调必须与上集末尾情绪自然衔接。\n'
      '11. 不要输出 assembled_prompt 字段，该字段由系统另行组装。\n'
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"shots": [{"number": 1, "duration_sec": 3, "shot_size": "medium", '
      '"mood": "suspense", "function": "opening", "action_zh": "画面动作描述", '
      '"dialogue": "角色台词", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in"}]}\n'
      '\n'
      '【Example】\n'
      '{"shots": [\n'
      '  {"number": 1, "duration_sec": 3, "shot_size": "close_up", '
      '"mood": "suspense", "function": "opening", "action_zh": "女主在雨夜回头，'
      '眼神惊疑", "dialogue": "", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in"},\n'
      '  {"number": 2, "duration_sec": 5, "shot_size": "medium", '
      '"mood": "excited", "function": "advance", "action_zh": "她冲向巷口的黑影", '
      '"dialogue": "你给我站住！", "character_ids": [], "scene_id": "", '
      '"camera_move": "handheld follow"}\n'
      ']}';

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
      '\n'
      '$_commonOutputRules'
      '\n'
      '【Output JSON Schema】\n'
      '{"shot": {"number": 1, "duration_sec": 3, "shot_size": "medium", '
      '"mood": "warm", "function": "advance", "action_zh": "", '
      '"dialogue": "", "character_ids": [], "scene_id": "", '
      '"camera_move": ""}}\n'
      '\n'
      '【Example】\n'
      '{"shot": {"number": 3, "duration_sec": 4, "shot_size": "close_up", '
      '"mood": "sad", "function": "advance", "action_zh": "她低头看着手里的病历单", '
      '"dialogue": "原来只剩三个月了", "character_ids": [], "scene_id": "", '
      '"camera_move": "slow push-in"}}';

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
abstract final class _SchemaValidators {
  static const Set<String> _shotSizes = {
    'close_up',
    'medium_close_up',
    'medium',
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
      if (number == null || number < 1) return null;
      if (duration == null || duration < 2 || duration > 6) return null;
      // 台词字数硬约束：时长 × 5 字/秒。AI 超了就让上层重试，不要静默截断——
      // 截断会改剧本，而那不是系统可以替用户做的决定。
      if (dialogue.length > (duration * 5).floor()) return null;
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
        'action_zh': shot['action_zh'] as String? ?? '',
        'dialogue': dialogue,
        'character_ids':
            (shot['character_ids'] as List?)?.cast<String>() ?? const [],
        'scene_id': shot['scene_id'] as String? ?? '',
        'camera_move': shot['camera_move'] as String? ?? '',
      });
    }
    return {'shots': shots};
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
      '远景': 'long',
      '大远景': 'extreme_long',
      '全景': 'long',
    };
    return zhMap[value.trim()];
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
