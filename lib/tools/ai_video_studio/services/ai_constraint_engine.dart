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
import 'director_validation_engine.dart' show ValidationReport;
import 'prompt_assembler.dart';
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
  sceneSpatialDeconstruction('scene_spatial_deconstruction', '场景空间全息解构'),

  /// AI 视频提示词精炼与冲突消解。
  videoPromptRewrite('video_prompt_rewrite', 'AI 视频提示词重写'),

  /// 导演质检问题一键 AI 自动修复。
  directorAuditAutoFix('director_audit_auto_fix', '导演质检 AI 自愈'),

  /// 编剧研讨室全书主线与改编边界抽取。
  writersRoomMasterExtract('writers_room_master_extract', '编剧研讨主线分析'),

  /// 编剧研讨室全季宏观大篇章大幕规划。
  writersRoomMacroArcs('writers_room_macro_arcs', '全季宏观大幕规划'),

  /// 编剧研讨室全季短剧分集大纲与悬念规划。
  writersRoomSeasonBeats('writers_room_season_beats', '全季分集规划'),

  /// 编剧研讨室人机共创对话。
  writersRoomDialogue('writers_room_dialogue', '编剧研讨共创对话');

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

  /// 当用户在剧本工作台的全文模式下独立修改了文学剧本全文，导致 `screenplayText`
  /// 与结构化 `scenes` 导出的 Markdown 不一致时，设为 `true`，使拆镜提示词将文学剧本
  /// 全文标为最高优先级剧情依据，避免旧场次节拍与新全文自相矛盾。
  final bool preferSynopsisOverScenes;

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
    this.preferSynopsisOverScenes = false,
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
      case StudioAiTask.writersRoomMasterExtract:
      case StudioAiTask.writersRoomMacroArcs:
      case StudioAiTask.writersRoomSeasonBeats:
      case StudioAiTask.writersRoomDialogue:
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
    Map<String, String>? promptSlots,
    String? systemPromptOverride,
  }) async {
    final effectiveTimeout = timeout ?? defaultTimeoutFor(task);
    final systemPrompt = systemPromptOverride ??
        resolveSystemPrompt(task, slots: promptSlots);
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    String lastRaw = '';
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      ChatResult result;
      try {
        // 前几次失败时把精简错误片段回给模型，避免塞入数千 Token 的截断残片导致再次爆表。
        final String retryHint;
        if (attempt > 1 && lastRaw.isNotEmpty) {
          final trimmedRaw = lastRaw.length > 500
              ? '...${lastRaw.substring(lastRaw.length - 500)}'
              : lastRaw;
          retryHint = '\n\n【上一次你的输出格式不完整或无法解析】\n$trimmedRaw\n\n'
              '请注意精炼表述并严格按上述 JSON Schema 完整闭合输出，不要输出任何解释文字。';
        } else {
          retryHint = '';
        }
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
      if (context.preferSynopsisOverScenes) {
        buffer.writeln(
          '【场次规划与节拍（Scenes & Beats，仅作空间地标与机位参考，剧情与对白冲突时以文学剧本全文为准）】',
        );
      } else {
        buffer.writeln('【场次规划与节拍（Scenes & Beats）】');
      }
      for (final s in context.scenes) {
        buffer.writeln('- 场次 ${s.id} (${s.title}): ${s.location}, 主光=${s.primaryLightWorldDirection}, 地标=${s.landmarks.join("/")}');
        for (final b in s.beats) {
          // 节拍行必须带上用户在剧本工作台精心编写的台词与导演预设
          // （spec: 拆镜上下文包含节拍级导演字段）。旧实现只传 name/action，
          // 台词唯一能进上下文的通道是 protectedContract 里那几句金句——用户
          // 写的其余对白、机位、景别在拆镜时全部蒸发，AI 只能靠粗大纲自己编。
          final beatParts = <String>[
            '[${b.dramaticFunction}] ${b.name}',
            b.action,
          ];
          if (b.dialogue.trim().isNotEmpty) {
            final speaker = b.dialogueSpeaker.trim();
            final prefix = speaker.isNotEmpty ? '$speaker：' : '';
            beatParts.add('台词=$prefix${b.dialogue.trim()}');
          }
          if (b.voiceType != UtteranceVoiceType.dialogue) {
            beatParts.add('发声类型=${b.voiceType.label}');
          }
          if (b.subtext.trim().isNotEmpty) {
            beatParts.add('潜台词=${b.subtext.trim()}');
          }
          if (b.shotSize.trim().isNotEmpty) {
            beatParts.add('景别=${b.shotSize.trim()}');
          }
          if (b.cameraStaging.trim().isNotEmpty) {
            beatParts.add('机位=${b.cameraStaging.trim()}');
          }
          if (b.cameraMove.trim().isNotEmpty) {
            beatParts.add('运镜=${b.cameraMove.trim()}');
          }
          if (b.screenPosition.trim().isNotEmpty) {
            beatParts.add('画面位置=${b.screenPosition.trim()}');
          }
          if (b.gazeDirection.trim().isNotEmpty) {
            beatParts.add('视线=${b.gazeDirection.trim()}');
          }
          buffer.writeln('  * 节拍 ${b.id}: ${beatParts.join(' | ')}');
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
    if (context.preferSynopsisOverScenes) {
      buffer.writeln(
        '【本集文学剧本全文（最高优先级剧情依据，若与上方场次节拍不一致请以本剧本全文为准）】\n$synopsis',
      );
    } else {
      buffer.writeln('【本集剧情大纲】\n$synopsis');
    }
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

  /// 对超长小说原著进行「首部 + 中部多窗口均匀采样 + 尾部」代表性切片，
  /// 避免旧逻辑在 >35,000 字时将全书中部直接硬截断丢弃。
  ///
  /// 默认预算 35,000 字：
  /// - 首部：10,000 字（开篇世界观与初始人物登场）
  /// - 中部：5 个均匀分布的采样窗口，合计 17,000 字（每窗口约 3,400 字，自动贴合段落换行边界）
  /// - 尾部：8,000 字（高潮与结局收束）
  static String sampleNovelTextForContext(
    String novelText, {
    int maxChars = 35000,
  }) {
    if (novelText.length <= maxChars) return novelText;

    final int headBudget = (maxChars * 10000 / 35000).round();
    final int tailBudget = (maxChars * 8000 / 35000).round();
    final int midTotalBudget = maxChars - headBudget - tailBudget;
    const int windowCount = 5;
    final int perWindowBudget = midTotalBudget ~/ windowCount;

    // 尝试在紧邻位置寻找换行符，避免把句子劈成两半
    int snapToNewline(int pos, {required bool forward, int tolerance = 200}) {
      final clamped = pos.clamp(0, novelText.length);
      if (forward) {
        final limit = (clamped + tolerance).clamp(0, novelText.length);
        final idx = novelText.indexOf('\n', clamped);
        if (idx != -1 && idx <= limit) return idx + 1;
      } else {
        final limit = (clamped - tolerance).clamp(0, novelText.length);
        final idx = novelText.lastIndexOf('\n', clamped);
        if (idx != -1 && idx >= limit) return idx;
      }
      return clamped;
    }

    final int headEnd = snapToNewline(headBudget, forward: false);
    final int tailStart = snapToNewline(
      novelText.length - tailBudget,
      forward: true,
    );

    if (tailStart <= headEnd) {
      return novelText.substring(0, maxChars);
    }

    final buffer = StringBuffer()
      ..write(novelText.substring(0, headEnd).trimRight());

    final int midRange = tailStart - headEnd;
    if (midRange <= midTotalBudget) {
      buffer
        ..write('\n\n[...全书中部章节采样...]\n\n')
        ..write(novelText.substring(headEnd, tailStart).trim());
    } else {
      final int availableSpan = midRange - perWindowBudget;
      for (int i = 0; i < windowCount; i++) {
        final int rawStart =
            headEnd + ((availableSpan * (i + 0.5)) / windowCount).round();
        final int winStart = snapToNewline(rawStart, forward: true);
        final int winEnd = snapToNewline(
          (winStart + perWindowBudget).clamp(winStart, tailStart),
          forward: false,
        );
        if (winEnd > winStart) {
          final int pct = (((winStart + winEnd) / 2 / novelText.length) * 100)
              .round();
          buffer
            ..write('\n\n[...全书中部采样片段 ${i + 1}/$windowCount (约 $pct% 进度)...]\n\n')
            ..write(novelText.substring(winStart, winEnd).trim());
        }
      }
    }

    buffer
      ..write('\n\n[...全书收尾章节采样...]\n\n')
      ..write(novelText.substring(tailStart).trimLeft());

    return buffer.toString();
  }

  /// 小说全案第一阶段：提取世界观、风格词、角色卡库与场景库。
  static Future<ConstraintResult> extractNovelMaster({
    required String novelText,
    String productionType = 'drama',
    List<String> existingCharacterNames = const [],
    List<String> existingSceneNames = const [],
  }) {
    final cleanText = sampleNovelTextForContext(novelText);
    final buffer = StringBuffer()
      ..writeln('【制作类型】$productionType');
    if (existingCharacterNames.isNotEmpty) {
      buffer.writeln(
        '【本剧资产库已有角色（同人不同称谓须优先复用这些标准名，严禁自造同人异名新卡；若已有角色在本章出现新造型/新服饰或更丰富外貌细节，请继续使用原名输出新造型以便系统增量合并）】\n'
        '${existingCharacterNames.join('、')}',
      );
    }
    if (existingSceneNames.isNotEmpty) {
      buffer.writeln(
        '【本剧资产库已有场景（同地不同名须优先复用这些标准场景名，严禁自造同义新场景名）】\n'
        '${existingSceneNames.join('、')}',
      );
    }
    buffer.write('【小说原著内容】\n$cleanText');
    return run(
      task: StudioAiTask.novelMasterExtraction,
      userPrompt: buffer.toString(),
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
    final cleanText = sampleNovelTextForContext(novelText);
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
    List<String> propNames = const [],
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
    if (propNames.isNotEmpty) {
      buffer.writeln('【核心已知道具库】${propNames.join('、')}（若涉及请优先复用上述道具名称）');
    }
    if (memoryContext.isNotEmpty) {
      buffer.writeln('【前情记忆】\n$memoryContext');
    }
    buffer.writeln('【小说本章完整文本】\n$novelText');

    final promptSlots = <String, String>{
      'series_name': seriesName,
      'production_type': productionType,
      'episode_index': episodeIndex.toString(),
      'worldview': worldview,
      'character_names': characterNames.join('、'),
      'prop_names': propNames.join('、'),
      'memory_context': memoryContext,
    };

    return run(
      task: StudioAiTask.novelDramaChapterAdaptation,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.novelChapterAdaptation,
      promptSlots: promptSlots,
    );
  }

  /// 编剧研讨室：小说全案宏观主线提取与改编边界清单界定（必留/可删/可改）。
  static Future<ConstraintResult> extractWritersRoomMaster({
    required String novelText,
    required String seriesName,
    String theme = '',
  }) {
    final cleanText = sampleNovelTextForContext(novelText);
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName');
    if (theme.isNotEmpty) {
      buffer.writeln('【核心主题/定位】$theme');
    }
    buffer.writeln('【小说全景/多章节原著文本】\n$cleanText');

    return run(
      task: StudioAiTask.writersRoomMasterExtract,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.writersRoomMasterExtract,
      promptSlots: {
        'series_name': seriesName,
        'theme': theme,
      },
    );
  }

  /// 编剧研讨室：全季宏观大篇章大幕规划（仅划分 3~6 幕，极低 Token 极速产出）。
  static Future<ConstraintResult> planWritersRoomMacroArcs({
    required String masterPlot,
    required String seriesName,
    int episodeCount = 80,
    int targetDurationSec = 90,
    int seasonNumber = 1,
    String seasonTitle = '',
    String adaptedChaptersRange = '',
    String seasonTheme = '',
    String seasonClimax = '',
    List<Map<String, dynamic>> mustKeep = const [],
    List<Map<String, dynamic>> canCut = const [],
    List<Map<String, dynamic>> canModify = const [],
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【本季总集数规模】期望全季共规划 $episodeCount 集')
      ..writeln('【单集预估时长】每集约 $targetDurationSec 秒');
    if (seasonNumber > 0 || seasonTitle.isNotEmpty) {
      buffer.writeln('【当前规划季】第 $seasonNumber 季 · ${seasonTitle.isNotEmpty ? seasonTitle : "第$seasonNumber季"}');
    }
    if (adaptedChaptersRange.isNotEmpty) {
      buffer.writeln('【对应原著章节跨度】$adaptedChaptersRange');
    }
    if (seasonTheme.isNotEmpty) {
      buffer.writeln('【本季核心叙事主题】$seasonTheme');
    }
    if (seasonClimax.isNotEmpty) {
      buffer.writeln('【本季终极大高潮】$seasonClimax');
    }
    buffer.writeln('【全书主线脉络】\n$masterPlot');

    if (mustKeep.isNotEmpty) {
      buffer.writeln('【必留名场面与核心主线】');
      for (final m in mustKeep) {
        buffer.writeln('- ${m["title"]}: ${m["description"]}');
      }
    }

    return run(
      task: StudioAiTask.writersRoomMacroArcs,
      userPrompt: buffer.toString(),
      schemaValidator: (data) => _SchemaValidators.writersRoomMacroArcs(
        data,
        targetEpisodeCount: episodeCount,
        targetDurationSec: targetDurationSec,
      ),
      promptSlots: {
        'series_name': seriesName,
        'episode_count': episodeCount.toString(),
      },
    );
  }

  /// 编剧研讨室：单批次分集大纲推演（适用于集数 <= 20 或测试环境）。
  static Future<ConstraintResult> _planSingleBatchSeasonBeats({
    required String masterPlot,
    required String seriesName,
    int episodeCount = 80,
    int targetDurationSec = 90,
    int seasonNumber = 1,
    String seasonTitle = '',
    String adaptedChaptersRange = '',
    String seasonTheme = '',
    String seasonClimax = '',
    List<Map<String, dynamic>> mustKeep = const [],
    List<Map<String, dynamic>> canCut = const [],
    List<Map<String, dynamic>> canModify = const [],
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName');

    if (episodeCount > 0) {
      buffer.writeln('【参考集数规模】本季期望规模约为 $episodeCount 集（请根据原著小说实际剧情密度、矛盾起伏与高潮自然推演最为合理的分集大纲，各集剧情必须独立递进，绝不重复！）；');
    } else {
      buffer.writeln('【分集推演规则】请依据原著小说的实际情节密度与矛盾起伏，自然规划出最合理、最饱满的完整分集大纲；');
    }
    buffer.writeln('【剧情独立性硬约束】episodes 数组输出的每一集必须具备独一无二的核心对抗事件与不同断章钩子，严禁在多集之间复制相同剧情，严禁添加任何类似 "(节拍 X)" 的机械化后缀！');
    buffer.writeln('【单集预估时长】每集约 $targetDurationSec 秒（约 ${(targetDurationSec / 60).toStringAsFixed(1)} 分钟）');

    if (seasonNumber > 0 || seasonTitle.isNotEmpty) {
      buffer.writeln('【当前规划季】第 $seasonNumber 季 · ${seasonTitle.isNotEmpty ? seasonTitle : "第$seasonNumber季"}');
    }
    if (adaptedChaptersRange.isNotEmpty) {
      buffer.writeln('【对应原著章节跨度】$adaptedChaptersRange');
      buffer.writeln('【分集章节硬约束】输出的每一集必须给出取材的原著章节范围 chapter_range（如 "1-3"），基于原著情节推进合理分配，绝非机械 1:1！');
    }
    if (seasonTheme.isNotEmpty) {
      buffer.writeln('【本季核心叙事主题】$seasonTheme');
    }
    if (seasonClimax.isNotEmpty) {
      buffer.writeln('【本季终极大高潮】$seasonClimax');
    }

    buffer.writeln('【全书主线脉络】\n$masterPlot');

    if (mustKeep.isNotEmpty) {
      buffer.writeln('【必留名场面与核心主线】');
      for (final m in mustKeep) {
        buffer.writeln('- ${m["title"]}: ${m["description"]}');
      }
    }
    if (canCut.isNotEmpty) {
      buffer.writeln('【建议大刀阔斧删除的情节】');
      for (final c in canCut) {
        buffer.writeln('- ${c["title"]}: ${c["description"]}');
      }
    }
    if (canModify.isNotEmpty) {
      buffer.writeln('【允许合并的配角与精简过渡】');
      for (final m in canModify) {
        buffer.writeln('- ${m["title"]}: ${m["suggestion"] ?? m["description"]}');
      }
    }

    return run(
      task: StudioAiTask.writersRoomSeasonBeats,
      userPrompt: buffer.toString(),
      schemaValidator: (data) => _SchemaValidators.writersRoomSeasonBeats(
        data,
        targetEpisodeCount: episodeCount,
        targetDurationSec: targetDurationSec,
        seasonChaptersRange: adaptedChaptersRange,
      ),
      promptSlots: {
        'series_name': seriesName,
        'episode_count': episodeCount.toString(),
        'target_duration_sec': targetDurationSec.toString(),
      },
    );
  }

  /// 编剧研讨室：单幕分批次推演具体分集（每批约 12~16 集，彻底规避 4096 Token 物理截断）。
  static Future<ConstraintResult> _planChunkSeasonBeats({
    required String masterPlot,
    required String seriesName,
    required int seasonNumber,
    required String seasonTitle,
    required int startEpisode,
    required int endEpisode,
    required Map<String, dynamic> arc,
    required int targetDurationSec,
    required String prevContext,
    String adaptedChaptersRange = '',
    int totalSeasonEpisodes = 80,
    List<Map<String, dynamic>> mustKeep = const [],
    List<Map<String, dynamic>> canCut = const [],
    List<Map<String, dynamic>> canModify = const [],
  }) {
    final arcTitle = arc['title'] as String? ?? '大幕篇章';
    final arcConflict = arc['core_conflict'] as String? ?? '';
    final arcTurning = arc['turning_point'] as String? ?? '';
    final arcChapterRange = (arc['chapter_range'] as String? ?? '').trim();
    final expectedCount = endEpisode - startEpisode + 1;

    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【当前规划季】第 $seasonNumber 季 · ${seasonTitle.isNotEmpty ? seasonTitle : "第$seasonNumber季"}')
      ..writeln('【所属篇章大幕】$arcTitle（集数跨度：第 $startEpisode ~ $endEpisode 集）');

    if (arcChapterRange.isNotEmpty) {
      buffer.writeln('【本幕对应原著章节】$arcChapterRange');
    } else if (adaptedChaptersRange.isNotEmpty) {
      buffer.writeln('【全季对应原著章节】$adaptedChaptersRange');
    }

    buffer
      ..writeln('【本幕核心对抗矛盾】$arcConflict')
      ..writeln('【本幕转折高潮爆点】$arcTurning')
      ..writeln('【本次规划目标】精准输出第 $startEpisode 到第 $endEpisode 集（共 $expectedCount 集），每集约 $targetDurationSec 秒')
      ..writeln('【剧情独立性硬约束】每一集必须具备独一无二的核心对抗事件与不同断章钩子，按原著剧情递进，绝不重复，严禁添加任何类似 "(节拍 X)" 的机械化后缀！')
      ..writeln('【分集章节硬约束】输出的每一集必须给出取材的原著章节范围 chapter_range（如 "1-3"），基于原著情节推进合理分配，绝非机械 1:1！');

    if (prevContext.isNotEmpty) {
      buffer.writeln('【前情剧情承接】$prevContext。本批次第 $startEpisode 集必须紧密承接上一集结尾悬念！');
    }

    buffer.writeln('【全书主线脉络】\n$masterPlot');

    if (mustKeep.isNotEmpty) {
      buffer.writeln('【相关必留情节】');
      for (final m in mustKeep) {
        buffer.writeln('- ${m["title"]}: ${m["description"]}');
      }
    }

    return run(
      task: StudioAiTask.writersRoomSeasonBeats,
      userPrompt: buffer.toString(),
      schemaValidator: (data) => _SchemaValidators.writersRoomArcBeats(
        data,
        startEpisode: startEpisode,
        endEpisode: endEpisode,
        arcName: arcTitle,
        targetDurationSec: targetDurationSec,
        arcChapterRange: arcChapterRange,
        totalEpisodes: totalSeasonEpisodes,
        seasonChaptersRange: adaptedChaptersRange,
      ),
      promptSlots: {
        'series_name': seriesName,
        'episode_count': expectedCount.toString(),
        'target_duration_sec': targetDurationSec.toString(),
      },
    );
  }

  /// 编剧研讨室：全季分集强冲突大纲、大篇章规划与断章悬念钩子规划。
  ///
  /// 当集数规模较小 (<= 20 集) 时走单批快速通道；
  /// 当集数规模较大 (> 20 集) 时自动启动两阶段按大幕分批推演管线，彻底消除 4096 Token 物理截断崩溃。
  static Future<ConstraintResult> planWritersRoomSeasonBeats({
    required String masterPlot,
    required String seriesName,
    int episodeCount = 80,
    int targetDurationSec = 90,
    int seasonNumber = 1,
    String seasonTitle = '',
    String adaptedChaptersRange = '',
    String seasonTheme = '',
    String seasonClimax = '',
    List<Map<String, dynamic>> mustKeep = const [],
    List<Map<String, dynamic>> canCut = const [],
    List<Map<String, dynamic>> canModify = const [],
    void Function(String message, double progress)? onProgress,
  }) async {
    if (episodeCount <= 20) {
      onProgress?.call('正在规划第 $seasonNumber 季高能分集大纲...', 0.5);
      final res = await _planSingleBatchSeasonBeats(
        masterPlot: masterPlot,
        seriesName: seriesName,
        episodeCount: episodeCount,
        targetDurationSec: targetDurationSec,
        seasonNumber: seasonNumber,
        seasonTitle: seasonTitle,
        adaptedChaptersRange: adaptedChaptersRange,
        seasonTheme: seasonTheme,
        seasonClimax: seasonClimax,
        mustKeep: mustKeep,
        canCut: canCut,
        canModify: canModify,
      );
      onProgress?.call('分集大纲规划完成！', 1.0);
      return res;
    }

    // 两阶段按大幕分批推演管线 (规避 4096 Token 物理截断)
    onProgress?.call('正在构建全季宏观大篇章结构...', 0.1);

    ConstraintResult macroRes;
    try {
      macroRes = await planWritersRoomMacroArcs(
        masterPlot: masterPlot,
        seriesName: seriesName,
        episodeCount: episodeCount,
        targetDurationSec: targetDurationSec,
        seasonNumber: seasonNumber,
        seasonTitle: seasonTitle,
        adaptedChaptersRange: adaptedChaptersRange,
        seasonTheme: seasonTheme,
        seasonClimax: seasonClimax,
        mustKeep: mustKeep,
        canCut: canCut,
        canModify: canModify,
      );
    } catch (_) {
      macroRes = ConstraintResult(
        data: _SchemaValidators.writersRoomMacroArcs(
          const {},
          targetEpisodeCount: episodeCount,
          targetDurationSec: targetDurationSec,
        )!,
        rawText: '',
        providerId: 'fallback',
        model: 'fallback',
        attempt: 1,
      );
    }

    final seasonOverallTitle =
        (macroRes.data['season_title'] as String? ?? seriesName).trim();
    final cleanArcs = (macroRes.data['macro_arcs'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final chunks = <({int startEp, int endEp, Map<String, dynamic> arc})>[];
    for (final arc in cleanArcs) {
      final range = arc['episode_range'] as String? ?? '';
      final parts = range.split('-');
      int start = int.tryParse(parts.first.trim()) ?? 1;
      int end = (parts.length > 1 ? int.tryParse(parts.last.trim()) : null) ?? start;
      if (end < start) end = start;

      // 如果单幕集数跨度较大 (> 18 集)，拆分为更小的批次以确保每批不超过 16 集
      while (end - start + 1 > 18) {
        final subEnd = start + 14;
        chunks.add((startEp: start, endEp: subEnd, arc: arc));
        start = subEnd + 1;
      }
      chunks.add((startEp: start, endEp: end, arc: arc));
    }

    if (chunks.isEmpty) {
      int curr = 1;
      while (curr <= episodeCount) {
        final next = (curr + 13 > episodeCount) ? episodeCount : curr + 13;
        chunks.add((
          startEp: curr,
          endEp: next,
          arc: cleanArcs.firstWhere(
            (a) => true,
            orElse: () => {'title': '核心篇章', 'core_conflict': seasonTheme},
          ),
        ));
        curr = next + 1;
      }
    }

    final allEpisodes = <Map<String, dynamic>>[];
    String prevContext = '';

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final arcTitle = chunk.arc['title'] as String? ?? '大幕篇章';
      final stepProgress = 0.15 + (0.80 * (i / chunks.length));

      onProgress?.call(
        '正在推演【$arcTitle】高能分集 (第 ${chunk.startEp} ~ ${chunk.endEp} 集)...',
        stepProgress,
      );

      final chunkRes = await _planChunkSeasonBeats(
        masterPlot: masterPlot,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        seasonTitle: seasonTitle,
        startEpisode: chunk.startEp,
        endEpisode: chunk.endEp,
        arc: chunk.arc,
        targetDurationSec: targetDurationSec,
        prevContext: prevContext,
        adaptedChaptersRange: adaptedChaptersRange,
        totalSeasonEpisodes: episodeCount,
        mustKeep: mustKeep,
        canCut: canCut,
        canModify: canModify,
      );

      final chunkEps = (chunkRes.data['episodes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (chunkEps.isNotEmpty) {
        allEpisodes.addAll(chunkEps);
        final lastEp = chunkEps.last;
        prevContext = '上一批末尾为第 ${lastEp["episode_number"]} 集《${lastEp["title"]}》，'
            '核心事件：${lastEp["conflict"]}，末尾断章钩子：${lastEp["hook"]}';
      }
    }

    onProgress?.call('全季分集大纲规划完成！', 1.0);

    return ConstraintResult(
      data: {
        'season_title': seasonOverallTitle,
        'target_duration_sec': targetDurationSec,
        'macro_arcs': cleanArcs,
        'episodes': allEpisodes,
      },
      rawText: '',
      providerId: macroRes.providerId,
      model: macroRes.model,
      attempt: 1,
    );
  }

  /// 编剧研讨室：人机交互多轮协商讨论与分集大纲动态更新。
  static Future<ConstraintResult> dialogueWritersRoom({
    required String instruction,
    required String currentBeatsContext,
    required String seriesName,
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【当前分集大纲】\n$currentBeatsContext')
      ..writeln('【制片人/导演改编指令】\n$instruction');

    return run(
      task: StudioAiTask.writersRoomDialogue,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.writersRoomDialogue,
      promptSlots: {
        'series_name': seriesName,
      },
    );
  }

  /// 故事大纲/小说章节 → 影视分场文学剧本（场次、日夜、内外景、角色对白与微动作节拍）。
  /// AI 分场剧本生成。
  ///
  /// [characterProfiles] 是预先格式化好的角色设定行（姓名 + 容貌 + 服装），
  /// [sceneNames] 是资产库已有的场景卡名，[protectedContract] 是本集的受保护
  /// 契约。三者都是可选的，但传入后 AI 生成的地点与角色才有锚点——否则它会
  /// 自造场景名，下游 `_ensureScenesForDramaScenes` 只能另建新卡，场景库迅速
  /// 膨胀出一堆重复卡（spec: 剧本生成注入资产上下文）。
  static Future<ConstraintResult> screenplayGeneration({
    required String synopsis,
    List<String> characterNames = const [],
    List<String> characterProfiles = const [],
    List<String> sceneNames = const [],
    List<String> propNames = const [],
    ProtectedContract protectedContract = ProtectedContract.empty,
    String seriesName = '',
    String productionType = 'drama',
  }) {
    final buffer = StringBuffer()
      ..writeln('【剧集名称】$seriesName')
      ..writeln('【制作类型】$productionType');
    if (characterNames.isNotEmpty) {
      buffer.writeln('【出场角色】${characterNames.join('、')}');
    }
    if (characterProfiles.isNotEmpty) {
      buffer.writeln('【角色设定】');
      for (final profile in characterProfiles) {
        buffer.writeln('- $profile');
      }
    }
    if (propNames.isNotEmpty) {
      buffer.writeln('【核心已知道具库（若涉及请优先复用这些名称）】');
      buffer.writeln(propNames.join('、'));
    }
    if (sceneNames.isNotEmpty) {
      // 已有场景卡名必须显式给出：AI 不知道资产库里有什么，就会自造同义不同
      // 名的地点，而场景卡是按名字去重的。
      buffer.writeln('【资产库已有场景（地点名须优先复用这些，严禁自造同义新名）】');
      buffer.writeln(sceneNames.join('、'));
    }
    if (protectedContract.isNotEmpty) {
      if (protectedContract.facts.isNotEmpty) {
        buffer.writeln('【必须遵守的核心事实】');
        for (final f in protectedContract.facts) {
          buffer.writeln('- ${f.content}');
        }
      }
      if (protectedContract.utterances.isNotEmpty) {
        buffer.writeln('【必须逐字保留的高光台词】');
        for (final u in protectedContract.utterances) {
          buffer.writeln('- ${u.speaker}对${u.listener.isEmpty ? "众人" : u.listener}说: "${u.text}"');
        }
      }
    }
    buffer.writeln('【剧情大纲】\n$synopsis');

    final promptSlots = <String, String>{
      'series_name': seriesName,
      'production_type': productionType,
      'character_names': characterNames.join('、'),
      'prop_names': propNames.join('、'),
      'scene_names': sceneNames.join('、'),
    };

    return run(
      task: StudioAiTask.screenplayGeneration,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.screenplayGeneration,
      promptSlots: promptSlots,
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

  /// AI 视频提示词精炼与冲突消解。
  static Future<ConstraintResult> rewriteVideoPrompt({
    required StudioShot shot,
    required StudioEpisode episode,
    List<CharacterCard> characters = const [],
    List<PropCard> props = const [],
    SceneCard? scene,
    List<ResolvedAssetMaterial> materials = const [],
  }) {
    final basePrompt = PromptAssembler.buildVideoGenPrompt(
      shot: shot,
      episode: episode,
      characters: characters,
      props: props,
      scene: scene,
      materials: materials,
    );

    final buffer = StringBuffer()
      ..writeln('请对以下原始视频生成提示词进行精炼与冲突消解重写：')
      ..writeln('【镜号】: 第 ${shot.number} 镜')
      ..writeln('【建议时长】: ${shot.durationSec} 秒')
      ..writeln('【景别】: ${shot.shotSize.label}')
      ..writeln('【原始组装提示词】:')
      ..writeln(basePrompt);

    return run(
      task: StudioAiTask.videoPromptRewrite,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.videoPromptRewrite,
    );
  }

  /// 依据质检违规项对分镜执行 AI 自动修复自愈。
  static Future<ConstraintResult> autoFixAuditIssues({
    required List<StudioShot> shots,
    required ValidationReport report,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
  }) {
    final issuesDesc = report.issues.map((i) =>
        '• 规则 ${i.ruleId} (${i.ruleName}) [镜号 ${i.shotNumber ?? "全局"}]: ${i.message} -> 建议: ${i.suggestion}'
    ).join('\n');

    final shotsJson = shots.map((s) => {
      'number': s.number,
      'duration_sec': s.durationSec,
      'shot_size': s.shotSize.id,
      'mood': s.mood,
      'action_zh': s.actionZh,
      'dialogue': s.dialogue,
      'camera_move': s.cameraMove,
      'character_ids': s.characterIds,
      'scene_id': s.sceneId,
      'camera_staging': s.directorDecisions.cameraStaging,
      'lighting_staging': s.directorDecisions.lightingStaging,
    }).toList();

    final buffer = StringBuffer()
      ..writeln('【导演质检诊断报告】:')
      ..writeln(issuesDesc)
      ..writeln('\n【当前全集分镜数据】:')
      ..writeln(jsonEncode(shotsJson))
      ..writeln('\n请针对上述违规项执行精准修补，修复有问题的分镜，并返回修正后的 fixed_shots 数组。');

    return run(
      task: StudioAiTask.directorAuditAutoFix,
      userPrompt: buffer.toString(),
      schemaValidator: _SchemaValidators.directorAuditAutoFix,
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
    List<PropCard> props = const [],
  }) {
    final newShots = <StudioShot>[];
    int shotNumber = 1;
    final mountRegex = RegExp(r'骑[着乘]?(?:一头|一只|一匹)?(大黑驴|黑驴|毛驴|驴子|驴|白马|骏马|烈马|黑马|红马|战马|宝马|马|青牛|神兽|灵兽|坐骑)');
    final dismountRegex = RegExp(r'(下驴|下马|跳下|翻身下|下车|弃马|弃驴|落地|跃下)');
    String currentMount = '';
    String mountOwnerName = '';

    for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
      final scene = scenes[sceneIdx];
      final segId = 'seg-${sceneIdx + 1}';

      // 解析与绑定真实 IP 场景库卡片 (SceneCard)
      final resolvedSceneId = resolveSceneCardId(scene, sceneCards);

      for (int beatIdx = 0; beatIdx < scene.beats.length; beatIdx++) {
        final beat = scene.beats[beatIdx];

        // 识别内心独白（inner_voice）或者台词本身标有 OS
        final isInnerVoice = beat.voiceType == UtteranceVoiceType.innerVoice ||
            beat.dialogue.contains('内心 OS') ||
            beat.dialogue.contains('内心OS') ||
            beat.dialogue.contains('（OS）') ||
            beat.dialogue.contains('(OS)') ||
            beat.dialogue.contains('心声') ||
            beat.dialogue.contains('内心独白');

        final extractedSpeaker = PromptAssembler.extractSpeakerName(beat.dialogue);
        final effectiveSpeaker = beat.dialogueSpeaker.trim().isNotEmpty
            ? beat.dialogueSpeaker.trim()
            : extractedSpeaker;

        // 解析出场角色（多层智能匹配：名字全称、说话人、别名列表、中文昵称启发式）
        // 关键防护：当台词为内心独白时，出场角色匹配范围剔除台词正文，防止非在场第三人被误加入 characterIds
        final charIds = <String>{...beat.characterIds};
        final textScope = isInnerVoice
            ? '$effectiveSpeaker ${beat.action}'
            : '$effectiveSpeaker ${beat.action} ${beat.dialogue}';

        for (final c in characters) {
          bool matched = false;
          if (c.name.isNotEmpty && textScope.contains(c.name)) {
            matched = true;
          }
          if (!matched && effectiveSpeaker.isNotEmpty) {
            if (c.name.contains(effectiveSpeaker) || effectiveSpeaker.contains(c.name)) {
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
          final cleanSpeech = PromptAssembler.cleanDialogueForSpeech(beat.dialogue);
          if (cleanSpeech.isNotEmpty) {
            if (isInnerVoice) {
              dialogueFormatted = effectiveSpeaker.isNotEmpty
                  ? '$effectiveSpeaker（内心 OS）：$cleanSpeech'
                  : '（内心 OS）：$cleanSpeech';
            } else {
              dialogueFormatted = effectiveSpeaker.isNotEmpty
                  ? '$effectiveSpeaker：“$cleanSpeech”'
                  : '“$cleanSpeech”';
            }
          } else {
            dialogueFormatted = '';
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

        // 坐骑连续性状态机流转
        if (beat.mountOrVehicle.trim().isNotEmpty) {
          currentMount = beat.mountOrVehicle.trim();
        } else if (mountRegex.hasMatch(beat.action)) {
          final m = mountRegex.firstMatch(beat.action);
          currentMount = m?.group(1) ?? '坐骑';
          for (final c in characters) {
            if (beat.action.contains(c.name)) {
              mountOwnerName = c.name;
              break;
            }
          }
        } else if (dismountRegex.hasMatch(beat.action)) {
          currentMount = '';
          mountOwnerName = '';
        }

        // 垂直空间落差与俯仰机位推导
        final bool isMountOwnerInBeat = currentMount.isNotEmpty &&
            (mountOwnerName.isEmpty ||
                beat.action.contains(mountOwnerName) ||
                charIds.any((id) => characters.any((c) => c.id == id && c.name == mountOwnerName)));
        final String effectiveMount = isMountOwnerInBeat ? currentMount : '';

        final bool isHighStaging = beat.action.contains('三楼') ||
            beat.action.contains('二楼') ||
            beat.action.contains('楼上') ||
            beat.action.contains('窗') ||
            beat.cameraStaging.contains('三楼') ||
            beat.cameraStaging.contains('俯视') ||
            beat.cameraStaging.contains('俯拍');
        final bool isGroundStaging = beat.action.contains('长街') ||
            beat.action.contains('街道') ||
            beat.action.contains('地面') ||
            beat.action.contains('路面') ||
            beat.action.contains('街面') ||
            effectiveMount.isNotEmpty;
        final String resolvedElevationLevel = (isHighStaging && isGroundStaging)
            ? (beat.action.contains('三楼') ? 'balcony_3f' : 'balcony_2f')
            : (isHighStaging ? 'balcony_3f' : 'ground');

        final String resolvedCameraAngle = beat.cameraStaging.contains('俯') || beat.action.contains('俯')
            ? 'high_angle'
            : (beat.cameraStaging.contains('仰') || beat.action.contains('仰')
                ? 'low_angle'
                : 'eye_level');

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

        // 道具模糊匹配（按名称、别名、包含关系）并填充 propIds
        final matchedPropIds = <String>{};
        final candidatePropNames = <String>[
          ...beat.props,
          if (beat.holdingItem.trim().isNotEmpty) beat.holdingItem.trim(),
        ];
        for (final pName in candidatePropNames) {
          final trimmed = pName.trim();
          if (trimmed.isEmpty) continue;
          for (final p in props) {
            if (p.name == trimmed ||
                (trimmed.length >= 2 && p.name.contains(trimmed)) ||
                (p.name.length >= 2 && trimmed.contains(p.name))) {
              matchedPropIds.add(p.id);
              break;
            }
          }
        }

        // 手持物品与左右手姿态映射
        String holdingLeft = '';
        String holdingRight = '';
        if (beat.holdingItem.trim().isNotEmpty) {
          final hand = beat.holdingHand.trim().toLowerCase();
          final item = beat.holdingItem.trim();
          if (hand == 'left' || hand == '左手' || hand == '左') {
            holdingLeft = item;
          } else if (hand == 'right' || hand == '右手' || hand == '右') {
            holdingRight = item;
          } else if (hand == 'both' || hand == '双手' || hand == '双') {
            holdingLeft = item;
            holdingRight = item;
          } else {
            holdingRight = item;
          }
        }

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
          propIds: matchedPropIds.toList(),
          sceneId: resolvedSceneId,
          beatId: beat.id,
          segmentId: segId,
          cameraMove: resolvedCameraMove,
          directorDecisions: DirectorDecisions(
            physicalMomentum: beat.subtext,
            lightingStaging: '${scene.timeOfDay.isNotEmpty ? scene.timeOfDay : '日景'}，${scene.atmosphere.isNotEmpty ? scene.atmosphere : '自然光漫射'}',
            cameraStaging: resolvedCameraStaging,
            temporalEvolution: '',
            aestheticTexture: '',
            cutReason: '',
            visualTask: '',
          ),
          continuity: ShotContinuity(
            worldPosition: scene.location.isNotEmpty ? scene.location : scene.title,
            screenPosition: resolvedScreenPosition,
            holdingLeft: holdingLeft,
            holdingRight: holdingRight,
            lightingState: scene.timeOfDay.isNotEmpty ? scene.timeOfDay : '日景',
            gazeDirection: resolvedGazeDirection,
            cameraAxis: '',
            cameraAngle: resolvedCameraAngle,
            elevationLevel: resolvedElevationLevel,
            mountOrVehicle: effectiveMount,
            stateChanges: const [],
          ),
        ));
      }
    }
    return newShots;
  }

  /// 将分场剧本节拍提炼转换为分镜列表（别名，兼容规约契约命名）。
  static List<StudioShot> extractDramaBeatsToShots(
    List<DramaScene> scenes, {
    List<CharacterCard> characters = const [],
    List<SceneCard> sceneCards = const [],
    List<PropCard> props = const [],
  }) =>
      convertScenesToShots(
        scenes,
        characters: characters,
        sceneCards: sceneCards,
        props: props,
      );

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
      StudioAiTask.videoPromptRewrite => _SchemaValidators.videoPromptRewrite(data),
      StudioAiTask.directorAuditAutoFix => _SchemaValidators.directorAuditAutoFix(data),
      StudioAiTask.writersRoomMasterExtract => _SchemaValidators.writersRoomMasterExtract(data),
      StudioAiTask.writersRoomMacroArcs => _SchemaValidators.writersRoomMacroArcs(data),
      StudioAiTask.writersRoomSeasonBeats => _SchemaValidators.writersRoomSeasonBeats(data),
      StudioAiTask.writersRoomDialogue => _SchemaValidators.writersRoomDialogue(data),
    };
  }

  // ---------------------------------------------------------------------------
  // System Prompt 模板库与动态解析引擎
  // ---------------------------------------------------------------------------

  /// 根据任务类型映射到 StudioPromptTemplate 的对应模板 ID
  static String? templateIdFor(StudioAiTask task) {
    return switch (task) {
      StudioAiTask.scriptBreakdown => 'script_breakdown',
      StudioAiTask.scriptBreakdown5D => 'director_breakdown_5d',
      StudioAiTask.actionCombatBreakdown => 'action_combat_breakdown',
      StudioAiTask.promptTranslation => 'prompt_translation',
      StudioAiTask.ideaIncubation => 'idea_incubation',
      StudioAiTask.titleGeneration => 'title_generation',
      StudioAiTask.bgmRecommend => 'bgm_recommend',
      StudioAiTask.episodeSummary => 'episode_summary',
      StudioAiTask.shotRegenerate => 'shot_regenerate',
      StudioAiTask.novelMasterExtraction => 'novel_master_extraction',
      StudioAiTask.novelEpisodeSegmentation => 'novel_episode_segmentation',
      StudioAiTask.novelChapterAdaptation => 'novel_chapter_adaptation',
      StudioAiTask.novelDramaChapterAdaptation => 'novel_chapter_adaptation',
      StudioAiTask.screenplayGeneration => 'screenplay_generation',
      StudioAiTask.sceneSpatialDeconstruction => 'scene_spatial_deconstruction',
      StudioAiTask.videoPromptRewrite => 'video_prompt_rewrite',
      StudioAiTask.directorAuditAutoFix => 'director_audit_auto_fix',
      StudioAiTask.writersRoomMasterExtract => 'writers_room_master_extract',
      StudioAiTask.writersRoomMacroArcs => 'writers_room_macro_arcs',
      StudioAiTask.writersRoomSeasonBeats => 'writers_room_season_beats',
      StudioAiTask.writersRoomDialogue => 'writers_room_dialogue',
    };
  }

  /// 统一解析并装配系统提示词，支持用户自定义覆盖优先级与 Mustache 双花括号插槽替换。
  static String resolveSystemPrompt(
    StudioAiTask task, {
    Map<String, String>? slots,
  }) {
    String basePrompt = systemPromptFor(task);

    // 针对剧本生成与单章影视化深度改编，动态融入最新的常识与短剧节拍规则
    if (task == StudioAiTask.novelDramaChapterAdaptation ||
        task == StudioAiTask.screenplayGeneration) {
      final plausibilityRules = StudioPresetStore.instance
          .getPromptContent('screenplay_plausibility_rules')
          .trim();
      final pacingRules = StudioPresetStore.instance
          .getPromptContent('screenplay_beat_pacing_rules')
          .trim();

      if (plausibilityRules.isNotEmpty &&
          !basePrompt.contains('【环境生态与社会常识推演')) {
        basePrompt = basePrompt.replaceFirst(
          _commonOutputRules,
          '\n$plausibilityRules\n\n$_commonOutputRules',
        );
      }
      if (pacingRules.isNotEmpty &&
          !basePrompt.contains('【竖屏短剧高能节拍与微动作化法则】')) {
        basePrompt = basePrompt.replaceFirst(
          _commonOutputRules,
          '\n$pacingRules\n\n$_commonOutputRules',
        );
      }
    }

    // 针对五维拆镜，动态融入竖屏 9:16 视听工业铁律
    if (task == StudioAiTask.scriptBreakdown5D) {
      final verticalRules = StudioPresetStore.instance
          .getPromptContent('storyboard_vertical_5d')
          .trim();
      if (verticalRules.isNotEmpty &&
          !basePrompt.contains('【竖屏 9:16 短剧视听工业铁律】')) {
        basePrompt = basePrompt.replaceFirst(
          _commonOutputRules,
          '\n$verticalRules\n\n$_commonOutputRules',
        );
      }
    }

    // 执行 Mustache 格式 {{slot_name}} 插槽变量替换
    if (slots != null && slots.isNotEmpty) {
      slots.forEach((key, value) {
        basePrompt = basePrompt.replaceAll('{{$key}}', value);
      });
    }

    return basePrompt;
  }

  /// 取某个任务的基础 System Prompt。
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
      case StudioAiTask.videoPromptRewrite:
        return _promptVideoPromptRewrite;
      case StudioAiTask.directorAuditAutoFix:
        return _promptDirectorAuditAutoFix;
      case StudioAiTask.writersRoomMasterExtract:
        return _promptWritersRoomMasterExtract;
      case StudioAiTask.writersRoomMacroArcs:
        return _promptWritersRoomMacroArcs;
      case StudioAiTask.writersRoomSeasonBeats:
        return _promptWritersRoomSeasonBeats;
      case StudioAiTask.writersRoomDialogue:
        return _promptWritersRoomDialogue;
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
      '8. character_ids 只能从【可用角色】中选，且必须且只能包含本镜头摄像机可视范围内肉身在场的角色！严禁将仅在内心独白（内心 OS）、回忆闪回或口头提及的第三人填入 character_ids（如姜七夜骑驴心想老王，出场角色只有姜七夜，严禁填入老王）！没有可用角色清单时填空数组。\n'
      '9. scene_id 只能从【可用场景】中选，没有可用场景清单时填空字符串。\n'
      '10. camera_move 用英文摄影术语短语，例如 "low angle push-in"、"slow pan right"、"handheld follow"。\n'
      '11. 如有【跨集记忆】，首个分镜的情绪基调必须与上集末尾情绪自然衔接。\n'
      '12. 视线与第四面墙防御：人物严禁直视镜头屏幕面对观众自言自语；高低位对峙必须输出俯仰对视（二楼俯拍视线向下，街面仰拍视线向上）。\n'
      '13. 不要输出 assembled_prompt 字段，该字段由系统另行组装。\n'
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
      '你是一位专精于影视视听语言与竖屏短剧工业化制作的资深导演。你的任务是将单集剧本大纲与场次规划拆解为具备专业导演调度、空间视线对齐与五维决策的结构化分镜列表。\n'
      '\n'
      '【核心禁令与物理在场守卫（Physical In-Scene Guard）】\n'
      '1. character_ids 必须且只能包含本镜头摄像机可视范围内肉身在场的角色！\n'
      '2. 严禁幽灵角色：人物仅在内心独白（内心 OS）、回忆闪回、传音或对话口头提及的第三人，绝对严禁加入 character_ids！例如“姜七夜骑驴心想又被老王训了”，本镜出场角色只有姜七夜，绝对不得填入老王，违者判定为严重穿帮！\n'
      '3. 全员防打破第四面墙：严禁人物直视摄像机屏幕对着观众自言自语（除特殊解说镜头外），所有对白必须有真实的视线投向对象。\n'
      '\n'
      '【不可违背的五大视听铁律（Cinematic Guardrails - 拆镜底线）】\n'
      '1. 【单镜单动作原则】：一个镜头内严禁堆叠“奔跑、拔剑、转身、跳跃、落地”等多个复合动作！复杂情节必须拆解为景别递进或正反打的连续镜头（例如：镜头1奔跑停步 -> 镜头2拔剑蓄力 -> 镜头3破空出招），每个镜头只承载 1 个核心动词与清晰受力反馈！\n'
      '2. 【画面主体绝对聚焦】：画面严禁多人、烟雾、复杂背景同时抢焦点抢戏。核心主体必须明确单一，背景适度简化虚化，动作有明确清晰的受力交互对象（如先拍递信中景，背景简化，信封作为明确受力对象）。\n'
      '3. 【单一明确运镜调度】：单镜头只允许一种主要运镜轨迹（如缓慢推进 slow_push_in 或 定机位 static）。严禁同时堆砌斜向环绕、快速推进、横摇与变焦！若运镜调度为动态移动，摄影调度严禁标注“定机位”！需要机位变化时必须切镜另起新镜头。\n'
      '4. 【影视视听节奏与长短交替】：严禁全片所有镜头采用固定相同景别与相同秒数！必须依据戏剧重音交替规划节奏（如：中景交代动作 -> 特写揭示信物/兵器 -> 近景拍人物反应），按台词与微动作完成点精准剪辑。\n'
      '5. 【内心独白全员闭口与肉身在场守卫】：严禁幽灵角色；内心独白（inner_voice）为画外音心声，画面主体与同框在场全员嘴唇全程严密闭合，不张嘴、不说话、无口型变化，全员展现沉思或微表情神态。\n'
      '6. 【反应性台词因果时序铁律】：当某角色的台词是对另一角色动作的反应（喝止、怒斥、惊呼、追问、讨饶）时，该台词 SHALL 优先分配到触发动作之后的独立分镜！确需同镜共处时，必须在 temporal_evolution 中显式声明“触发动作相位早于反应相位”的先后次序（例如：“前2.0秒姜七夜拱手转身牵驴向门口，后1.5秒老王在背后跳脚喝骂”）。严禁把反应台词排在触发动作之前，严禁把两个主体的动作写成同时发生！\n'
      '7. 【竖屏 9:16 工业视听与同框人数铁律】：单镜头肉身在场角色 STRICTLY ≤ 3 人！竖屏 9:16 画幅狭窄，严禁 4 人以上同框并排站立（会导致人脸变形融化）；4 人以上群戏必须拆解为环境建立全景与连续中近景正反打；特写（close_up）、中近景（medium_close_up）与半身中景（medium）占比必须 ≥ 70%；画面底部 20% 为字幕安全区，人物主体五官与关键手持道具必须定位于画面中上部黄金分割区！\n'
      '\n'
      '【第一步：划片段边界】\n'
      '按叙事节拍将分镜归入若干片段（每个片段含 1 到 4 个分镜，target_duration_sec 为该片段分镜时长之和）。\n'
      '相邻片段的末镜与首镜必须在拍摄主体、景别（差 2 档以上）或角度（差 90° 以上）形成明显差异，避免生成断帧感；boundary_reason 说明切开理由。\n'
      '\n'
      '【第二步：五维导演决策（每个分镜必填 director_decisions）】\n'
      '1. physical_momentum（主体与物理动势）：明确画面核心视觉焦点、身体重心、力量释放与受力反馈（例如：“韩立重心后移三寸，右臂蓄力将反作用力卸入脚底”）。\n'
      '2. lighting_staging（环境与光影）：对照场次主光源世界方向，明确当前镜头主体受光面、阴影朝向与光影动态变化（例如：“主光源来自北侧窗外冷白闪电，韩立面部左侧受强侧光，右侧深沉暗影”）。\n'
      '3. camera_staging（光学与机位四段式调度）：明确【起始运动 → 跟随对象 → 触发条件 → 结束落点】及视线与 180° 轴线关系。高位（如二楼）水平平移（Pan）视域受限于二楼立柱与挑檐，禁止无过渡瞬移出地面街景；跨高度过渡必须显式使用下摇（Tilt Down）或剪辑硬切（Cut）！\n'
      '4. temporal_evolution（时间与状态演变）：明确动作相位（起手/接触/余势）、真实读时负荷与情绪留白（例如：“前1.5秒屏息试探，后1.5秒暴起接触，动作处于刚出招中途”）。当本镜含反应性台词时，此处 SHALL 显式声明触发动作相位早于反应相位（例如：“前2.0秒姜七夜拱手转身牵驴向门口，后1.5秒老王在背后跳脚喝骂”），否则视频模型会把台词演在动作之前。\n'
      '5. aesthetic_texture（美学介质与风格质感）：明确质感与媒介风格细节（例如：“次世代3D国漫UE5渲染，空中弥漫药香微尘粒子，刀刃泛冷冽金属反光”）。\n'
      '\n'
      '【第三步：空间视线轴线与正反打三机位规则（Eye-line & Shot-Reverse-Shot 3-Camera Setup）】\n'
      '- 高低位垂直空间落差对峙（如二/三楼窗口 vs 长街地面）：\n'
      '  * 严禁单镜头同框硬塞两个平面的特写！此类垂直高差场景必须强制规划为正反打镜头对：\n'
      '    - 镜头 A（楼上主体视角）：二楼窗口中景/近景（waist-up medium），高位角色探身向下喊话并带口型，camera_angle 为 high_angle，长街仅为远景虚化背景，严禁将地面配角设为主体；\n'
      '    - 镜头 B（楼下主体反打）：街面中景（waist-up medium），地面角色在坐骑上或站立仰望，camera_angle 为 low_angle，二楼窗口仅为高位背景；\n'
      '  * 正反打机位必须始终保持在 180° 轴线同侧（甲永远在画左，乙永远在画右），严禁同场换边越轴！\n'
      '- 双人对话镜头排布：遵循 A 主镜头（双人全景建立空间）+ B（过肩看甲）+ C（过肩看乙）三机位法，双方视线与面部朝向左右互斥对齐，呈现真正的时空对话，杜绝背对倾听者面对观众汇报！\n'
      '\n'
      '【第四步：高光特效三联分镜展开与道具因果锁】\n'
      '- 法宝/高光动作三联语法（Trinity Shot）：当剧情涉及法宝激活、神兵出鞘、法术轰击时，严禁单镜敷衍，必须自动拆解为连续三联视听：\n'
      '  * 镜头 A（起手前摇 Setup）：中景手势掐诀、眼神凝重或蓄势拔刀；\n'
      '  * 镜头 B（核心极特写 Insert Shot）：极特写（close_up/macro）聚焦法宝符文亮起、刀刃流光或机关异动；\n'
      '  * 镜头 C（异象反馈 Payoff）：全景气流爆发震碎摊位、狂风呼啸或周围路人惊骇倒退。\n'
      '- 道具微动作因果锁：当道具发生物理形态改变（如整只烤鸡变为撕下的鸡腿、宝剑出鞘）时，严禁单镜突变！动作描写必须交代“撕下/拔出”的微动作因果，并在 holding_left/holding_right 精确声明具体形态。\n'
      '\n'
      '【第五步：分镜动作、台词与连续性台账（continuity）】\n'
      '- number 从 1 开始递增，duration_sec 严格在 4.0 到 12.0 秒之间。\n'
      '- shot_size：close_up / medium_close_up / medium / full / long / extreme_long。\n'
      '- mood：depressing / excited / warm / battle / suspense / relaxed / sad。\n'
      '- function：opening / advance / burst / ending。\n'
      '- action_zh：20 到 60 字，严格遵循【主体 + 单一/递进微动作 + 受力/反馈 + 环境】具象微动作结构，严禁单镜堆叠多个复合动作，严禁抽象情绪词！\n'
      '- dialogue：角色台词、内心独白（内心 OS）或旁白，优先复用【基准对白清单】原文；若为人物内心戏必须显式标注为“角色（内心 OS）：内容”，末尾括号标注预估秒数，如“（预估2.5秒）”。可为空。\n'
      '- cut_reason：说明为什么切到本镜，观众此刻获得什么新信息或视角转变。\n'
      '- visual_task：本镜的核心主要视觉任务。\n'
      '- continuity 对象包含：\n'
      '  * world_position：相对场次地标的世界坐标与朝向。\n'
      '  * screen_position：画面左右与 180° 轴线侧。\n'
      '  * elevation_level：空间垂直高度（ground / balcony_2f / rooftop / mid_air）。\n'
      '  * camera_angle：机位俯仰（high_angle / low_angle / eye_level）。\n'
      '  * gaze_direction：视线朝向向量描述（严禁直视镜头）。\n'
      '  * holding_left / holding_right：左右手具体持有物形态。\n'
      '  * lighting_state：主光方向与色温。\n'
      '  * state_changes：本镜发生的状态增量变化。\n'
      '  * dynamic_exit_state：动态末态参数。\n'
      '\n'
      '【剧情保真锁】\n'
      '- 只做拆分、合并与计时，不新增、删除、替换、改变归属或改变顺序任何剧情事件。\n'
      '- 反应性台词的独立成镜拆分属于「拆分」范畴，SHALL NOT 改变该台词的内容、归属角色或相对顺序。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"segments": [{"segment_id": 1, "target_duration_sec": 7, "boundary_reason": "切入特写打破双人僵局", "shot_numbers": [1, 2]}], '
      '"shots": [{"number": 1, "duration_sec": 3.5, "shot_size": "medium", "mood": "suspense", "function": "opening", '
      '"action_zh": "暴雨猛烈拍打窗棂，韩立背抵冰冷药架猛然侧身，右手在衣袖内紧扣毒粉包暗扣。（36字）", '
      '"dialogue": "（压低呼吸）弟子确实不知。（预估2秒）", "character_ids": ["c_hanli"], "scene_id": "SC001", "beat_id": "B01", '
      '"camera_move": "slow push-in", "cut_reason": "建立密室紧张对峙关系与空间方位", "visual_task": "揭示韩立暗扣毒粉的防备姿态", '
      '"director_decisions": {"physical_momentum": "背部贴墙支撑，重心下沉，右手蓄势待发", "lighting_staging": "窗外冷白闪电主光，室内油灯微弱暖侧光", "camera_staging": "腰部高度平视中景，微幅推镜锁定人物防备视线", "temporal_evolution": "动作处于屏息试探相位，为后续爆发蓄力", "aesthetic_texture": "UE5次世代国漫风，空气中有飞扬药粉微尘与水汽", "camera_angle": "eye_level", "gaze_direction": "面向北门警惕注视"}, '
      '"continuity": {"world_position": "药柜南侧死角，面向北门", "screen_position": "画面右侧面向左", "elevation_level": "ground", "camera_angle": "eye_level", "gaze_direction": "面向北门侧方注视", "holding_left": "", "holding_right": "毒粉包", "lighting_state": "冷色闪电顶侧光", "state_changes": [], "dynamic_exit_state": {"support_foot": "双脚微屈踏地", "velocity_vector": "静止蓄势", "unfinished_phase": "指尖扣住毒粉包尚未甩出"}}}]}\n';

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
      '3. 【环境生态与社会常识推演铁律（杜绝横尸闹市无人理等常识穿帮）】：\n'
      '   - 公共开放空间（长街、集市、酒肆大堂、广场、演武场）发生异常（如横尸、行凶截杀、打斗重伤、剧毒异象）时，严禁摄像机视野空旷死寂！必须显式描写背景群众生态（路人围观惊呼、指指点点、商贩退避、捕快官兵封锁拉网）；\n'
      '   - 若剧情要求“隐秘弃尸、无人发觉、悄无声息”，严禁设在白天繁华街道！必须合理迁移或限定在【具有物理遮蔽的阴暗角落】（如死胡同拐角、破庙柴房、深夜乱葬岗），使无人知晓符合物理真实！\n'
      '4. 【竖屏短剧高能节拍与微动作化法则】：\n'
      '   - 黄金 3 秒高压切入：开场前 3 秒迅速建立视觉危机或强烈悬念，严禁平缓散步或空镜开篇；\n'
      '   - 心理描写动作化：大段内心算计与冷笑必须转化为可拍的微表情、下意识微动作与道具交互；\n'
      '   - 片尾高压断章卡点：单集末尾必须截断在杀机爆发或真相揭晓前一秒的悬念巅峰瞬间（Cliffhanger）。\n'
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
      '     * props: 节拍出场或交互的道具名称数组（如 ["玄铁短刃"]，若有请优先复用已给出的已知道具库名称，无道具可为空数组 []）。\n'
      '     * holding_item: 角色手中当前握持的主要道具（如 "玄铁短刃"，无手持为空字符串 ""）。\n'
      '     * holding_hand: 持握方位，只能严格从 "right"（右手）、"left"（左手）、"both"（双手）中选一，无手持为空字符串 ""。\n'
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
      '"beats": [{"id": "B01", "scene_id": "SC001", "order": 1, "name": "寒暄试探", "action": "墨大夫缓步逼近韩立，言语逼问长春功进展", "dialogue_speaker": "墨大夫", "dialogue": "好徒儿，长春功练到第几层了？（预估2.5秒）", "voice_type": "dialogue", "subtext": "试探虚实", "estimated_sec": 4.0, "dramatic_function": "threat_build", "shot_size": "medium", "camera_staging": "平视定机位", "camera_move": "slow_push_in", "screen_position": "主体居中", "gaze_direction": "平视正前", "props": ["玄铁短刃"], "holding_item": "玄铁短刃", "holding_hand": "right"}]}], '
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
      '     * props: 节拍出场或交互的道具名称数组（如 ["青驴缰绳"]、["酒杯"]，优先复用已给出的已知道具库名称，无道具可为空数组 []）。\n'
      '     * holding_item: 角色手中当前握持的主要道具（如 "青驴缰绳"、"酒杯"，无手持为空字符串 ""）。\n'
      '     * holding_hand: 持握方位，只能严格从 "right"（右手）、"left"（左手）、"both"（双手）中选一，无手持为空字符串 ""。\n'
      '\n'
      '$_commonOutputRules\n'
      '\n'
      '【Output JSON Schema】\n'
      '{"scenes": [{"id": "SC001", "scene_number": 1, "title": "寒阳城长街", "location": "寒阳城天人居酒楼前长街", "setting": "外景", "time_of_day": "黄昏", "atmosphere": "黄昏斜阳穿透长街，酒肆红幌微扬", "character_ids": ["姜七夜", "余小白"], "beats": [{"id": "B01", "scene_id": "SC001", "order": 1, "name": "骑驴思忖", "action": "姜七夜骑着高大青驴沿长街缓行，俊美的脸上带着从容慵懒，随意扫视街景。", "dialogue_speaker": "姜七夜", "dialogue": "今天真晦气，又被老王训了一顿。（预估2.5秒）", "voice_type": "inner_voice", "subtext": "表面平静，暗中谋划反制", "estimated_sec": 4.0, "shot_size": "medium", "camera_staging": "平视定机位", "camera_move": "slow_push_in", "screen_position": "主体居中", "gaze_direction": "平视正前", "props": ["青驴缰绳"], "holding_item": "青驴缰绳", "holding_hand": "both"}, {"id": "B02", "scene_id": "SC001", "order": 2, "name": "楼上挑衅", "action": "余小白自三楼窗口探出半个身子，举杯坏笑向下喊话。", "dialogue_speaker": "余小白", "dialogue": "姜七少，上来喝一杯啊！（预估2.0秒）", "voice_type": "dialogue", "subtext": "故意调侃寻开心", "estimated_sec": 3.0, "shot_size": "medium_close_up", "camera_staging": "高角度俯拍（三层楼窗口向下俯视街道）", "camera_move": "pan_down_follow", "screen_position": "画面上方窗口面向下方", "gaze_direction": "低头俯视街面", "props": ["酒杯"], "holding_item": "酒杯", "holding_hand": "right"}]}]}\n';

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

  /// AI 视频提示词精炼与冲突消解模板。
  static String get _promptVideoPromptRewrite {
    final custom = StudioPresetStore.instance.getPromptContent('video_prompt_rewrite').trim();
    if (custom.isNotEmpty) {
      return '$custom\n\n$_commonOutputRules\n\n【Output JSON Schema】\n{"rewritten_prompt": "精炼消解后的纯中文视频提示词..."}';
    }
    return '你是一位资深 AI 视频生成 Prompt 调优专家。你的任务是将分镜的画面描述、微动作、摄影运镜与环境光影精炼为最适合主流视频大模型（如 Agnes Video 2.5 Flash / Sora / Kling）执行的高保真视频提示词。\n'
        '\n'
        '【四大致命冲突消解铁律】\n'
        '1. 场景唯一性：彻底消除二选一冲突（例如地牢 vs 衙门口），统一到当前镜头摄像机所处的唯一起点物理空间。\n'
        '2. 氛围与光照统一：彻底消除互斥光源与情绪（例如地牢火把 vs 黄昏残阳如血、温馨 vs 阴森压抑），确定单一主导光影与基调色温。\n'
        '3. 运镜唯一性：单镜头只保留一种核心运镜轨迹！推镜（push in）严禁与定机位（static）同时出现，剔除矛盾镜头指令。\n'
        '4. 剔除无效多镜剪辑指令：单镜头不需要 180° 轴线同轴关系说明，彻底剔除单镜无法执行的剪辑规则，节省模型注意力。\n'
        '5. 因果时序唯一性：反应性台词（对另一角色动作的回应、喝止、怒斥）必须晚于其触发动作！严禁将台词前移至触发动作之前（例如“甲拱手离去，乙在背后喝骂”绝不可写成乙先骂、甲再走）。同一镜头内不同主体的动作必须保留先后次序，严禁合并为同时发生。若原始提示词含【因果时间轴】段，其秒数区间与先后顺序必须原样保留，不得改写为同时发生。\n'
        '6. 素材编号绝对保真：若原始提示词含【素材指代】段或 `<Picture N>`、`<Audio N>` 等多图/多模态引用标签，重写结果必须完整保留【素材指代】段与每个角色/场景旁边的 `<Picture N>` 标签，严禁删改或重排编号！\n'
        '\n'
        '【角色发声与画外心声守卫】\n'
        '1. 严禁使用中括号机器标记（如 `[角色内心独白/心声]`），大模型极易误识别为台词。\n'
        '2. 若为内心独白（内心 OS / 心声 / 旁白）：直接采用正向画外音自然语言描述，并必须显式点名在场全员（例如：“画外音心声。画面中姜七夜、老王等全员嘴唇全程严密闭合，不张嘴，无口型变化，绝对不说话，无字幕，全员保持沉思微神态”），杜绝配角误张嘴开口抢话！\n'
        '3. 若为普通对白：明确指出仅说话角色随台词自然开合嘴型，其余倾听者保持闭口倾听。\n'
        '\n'
        '$_commonOutputRules\n'
        '\n'
        '【Output JSON Schema】\n'
        '{"rewritten_prompt": "精炼消解后的纯中文视频提示词..."}';
  }

  /// 导演质检问题一键 AI 自动修复模板。
  static String get _promptDirectorAuditAutoFix {
    final custom = StudioPresetStore.instance.getPromptContent('director_audit_auto_fix').trim();
    if (custom.isNotEmpty) {
      return '$custom\n\n$_commonOutputRules\n\n【Output JSON Schema】\n{"fixed_shots": [{"number": 1, "action_zh": "修正后的微动作描述（20~60字，单一动词）...", "camera_move": "slow_push_in", "dialogue": "修正后的台词...", "character_ids": ["c1"]}]}';
    }
    return '你是一位资深影视导演兼分镜监制。你的任务是根据分镜质检引擎给出的违规诊断清单（包含但不限于 C1 动作堆叠、C2 主体不清、C3 机位冲突、C4 角色漂移、C5 表演过满、C6 节奏单一、C7 台词超长、C8 幽灵角色在场、C9 视线穿帮、C10 运镜与动作超载等），对问题分镜实施精准修正。\n'
        '\n'
        '【修复原则】\n'
        '1. 保持剧情骨干与核心事件 100% 保真，不擅自删减核心剧情。\n'
        '2. 动作过载时：将复合动作精简为当前镜头最核心的主干微动作，剔除多余次生动作。\n'
        '3. 运镜与机位冲突时：以动态运镜为准，剔除矛盾的定机位或多重移动。\n'
        '4. 幽灵角色时：剔除仅在心声、旁白或对话中被提及的第三人，确保出场角色只有肉身在场者。\n'
        '5. 心声导致配角抢开口时：补全全员闭口守卫指令。\n'
        '\n'
        '$_commonOutputRules\n'
        '\n'
        '【Output JSON Schema】\n'
        '{"fixed_shots": [{"number": 1, "action_zh": "修正后的微动作描述（20~60字，单一动词）...", "camera_move": "slow_push_in", "dialogue": "修正后的台词...", "character_ids": ["c1"]}]}';
  }

  // ---------------------------------------------------------------------------
  // JSON 提取
  // ---------------------------------------------------------------------------

  /// 从 AI 输出中提取 JSON 对象。
  ///
  /// 模型经常在 JSON 外面包 ```json 围栏或一句"好的，以下是..."。这里按顺序
  /// 尝试：直接解析 → 剥围栏 → 截取第一个 `{` 到最后一个 `}` → 截断数组安全自愈。
  /// 全部都不成才返回 null 让上层重试。
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

    // 第四层兜底：若因模型输出长度限制 (finish_reason = length) 导致在数组中途截断，
    // 自动扫描截断前的最后一个完整对象，闭合未闭合容器并安全抢救已生成的数据。
    final repaired = _tryRepairTruncated(raw);
    if (repaired != null) return repaired;

    return null;
  }

  /// 修复因 Token 长度上限被强制切断的 JSON（例如在中途截断的数组）。
  static Map<String, dynamic>? _tryRepairTruncated(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final stripped = _stripCodeFence(text);
      if (stripped != null) text = stripped;
    }
    final start = text.indexOf('{');
    if (start < 0) return null;
    text = text.substring(start);

    // 从后向前寻找可能作为有效对象闭合点的 '}'
    var searchEnd = text.length;
    for (int attempt = 0; attempt < 15; attempt++) {
      final lastBrace = text.lastIndexOf('}', searchEnd - 1);
      if (lastBrace < 0) break;

      final candidate = text.substring(0, lastBrace + 1);
      final repaired = _closeOpenContainers(candidate);
      if (repaired != null) {
        final decoded = _tryDecode(repaired);
        if (decoded != null && decoded.isNotEmpty) {
          return decoded;
        }
      }
      searchEnd = lastBrace;
    }
    return null;
  }

  /// 维护容器括号栈，为未闭合的 JSON 结构按序补齐闭合符。
  static String? _closeOpenContainers(String text) {
    final stack = <String>[];
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        stack.add('}');
      } else if (char == '[') {
        stack.add(']');
      } else if (char == '}' || char == ']') {
        if (stack.isEmpty) return null;
        final expected = stack.removeLast();
        if (char != expected) return null;
      }
    }

    if (inString) return null; // 截取点刚好在字符串内部，不是合法的闭合点
    if (stack.isEmpty) return text; // 已经完全闭合

    var buf = StringBuffer(text.trimRight());
    // 如果末尾有多余的逗号，去掉它
    while (buf.isNotEmpty) {
      final str = buf.toString().trimRight();
      if (str.endsWith(',')) {
        buf = StringBuffer(str.substring(0, str.length - 1).trimRight());
      } else {
        break;
      }
    }

    // 逆序压入闭合符
    while (stack.isNotEmpty) {
      buf.write(stack.removeLast());
    }
    return buf.toString();
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

  /// 解析章节范围字符串（支持 "1-3"、"1~3"、"第1章~第3章"、"1, 2, 3"、"1、2、3" 等），
  /// 返回格式化后的章节范围描述与章节序号列表。
  /// 若未能解析且提供了 `seasonChaptersRange` 与 `fallbackEpisodeIndex`，
  /// 则依据全季总集数按比例平滑插值，避免生硬回退。
  static ({String rangeDesc, List<int> indices}) parseChapterRange(
    dynamic rawRange, {
    int fallbackEpisodeIndex = 1,
    int totalEpisodes = 80,
    String seasonChaptersRange = '',
  }) {
    if (rawRange is List) {
      final list = rawRange.whereType<num>().map((n) => n.toInt()).toList();
      if (list.isNotEmpty) {
        list.sort();
        final distinct = list.toSet().toList();
        final desc = distinct.length == 1 ? '${distinct.first}' : '${distinct.first}-${distinct.last}';
        return (rangeDesc: desc, indices: distinct);
      }
    }

    final str = (rawRange as String? ?? '').trim();
    if (str.isNotEmpty) {
      final clean = str.replaceAll(RegExp(r'[第章节回\s]'), '');

      // 1. 范围连接符：- 或 ~ 或 至 或 到
      final rangeMatch = RegExp(r'^(\d+)[-~至到](\d+)$').firstMatch(clean);
      if (rangeMatch != null) {
        final start = int.tryParse(rangeMatch.group(1)!);
        final end = int.tryParse(rangeMatch.group(2)!);
        if (start != null && end != null) {
          final s = start <= end ? start : end;
          final e = start <= end ? end : start;
          final indices = [for (int i = s; i <= e; i++) i];
          final desc = s == e ? '$s' : '$s-$e';
          return (rangeDesc: desc, indices: indices);
        }
      }

      // 2. 离散逗号或顿号：1, 2, 3 或 1、2、3
      if (clean.contains(',') || clean.contains('，') || clean.contains('、')) {
        final parts = clean.split(RegExp(r'[,，、]'));
        final indices = <int>{};
        for (final p in parts) {
          final n = int.tryParse(p.trim());
          if (n != null) indices.add(n);
        }
        if (indices.isNotEmpty) {
          final sorted = indices.toList()..sort();
          final desc = sorted.length == 1 ? '${sorted.first}' : '${sorted.first}-${sorted.last}';
          return (rangeDesc: desc, indices: sorted);
        }
      }

      // 3. 纯单数字："5"
      final singleNum = int.tryParse(clean);
      if (singleNum != null) {
        return (rangeDesc: '$singleNum', indices: [singleNum]);
      }
    }

    // 4. 兜底平滑插值（根据全季章节跨度与当前集序号平滑映射）
    if (seasonChaptersRange.isNotEmpty && totalEpisodes > 0) {
      final seasonClean = seasonChaptersRange.replaceAll(RegExp(r'[第章节回\s]'), '');
      final seasonMatch = RegExp(r'^(\d+)[-~至到](\d+)$').firstMatch(seasonClean);
      if (seasonMatch != null) {
        final sStart = int.tryParse(seasonMatch.group(1)!);
        final sEnd = int.tryParse(seasonMatch.group(2)!);
        if (sStart != null && sEnd != null && sEnd >= sStart) {
          final totalCh = sEnd - sStart + 1;
          final safeEp = fallbackEpisodeIndex.clamp(1, totalEpisodes);
          final startRatio = (safeEp - 1) / totalEpisodes;
          final endRatio = safeEp / totalEpisodes;
          var chStart = sStart + (startRatio * totalCh).floor();
          var chEnd = sStart + (endRatio * totalCh).ceil() - 1;
          if (chEnd < chStart) chEnd = chStart;
          if (chStart > sEnd) chStart = sEnd;
          if (chEnd > sEnd) chEnd = sEnd;
          final indices = [for (int i = chStart; i <= chEnd; i++) i];
          final desc = chStart == chEnd ? '$chStart' : '$chStart-$chEnd';
          return (rangeDesc: desc, indices: indices);
        }
      }
    }

    // 5. 极端兜底：单集对应序号
    return (rangeDesc: '$fallbackEpisodeIndex', indices: [fallbackEpisodeIndex]);
  }

  static const String _promptWritersRoomMasterExtract =
      '你是一位资深网络文学影视化与爆款短剧总编审兼策划总监。你的任务是通读小说原著，将原著内容解构为核心叙事骨架，并输出清晰的改编边界、人物关系与首季多季定位。\n\n'
      '【核心输出要求】\n'
      '1. recommended_episode_count: 智能测算推荐改编集数（整型数字，如 60, 80, 100 等）。依据原著篇幅、核心戏剧冲突密度和标准短剧（每集 1.5~2 分钟）节奏，给出最佳单季规划集数；\n'
      '2. episode_count_reason: 推荐集数的依据与三幕戏剧弧光简析（50~100字）；\n'
      '3. master_plot: 全书主线脉络与核心人物叙事弧光（开端、发展、中段高潮、阶段目标与核心生存对抗矛盾），500字以内；\n'
      '4. must_keep: 【必留情节清单】（原著核心主线、不可替代的名场面、主角立身之本的核心高光、决定性反转伏笔），数组形式；\n'
      '5. can_cut: 【可删情节清单】（与主线无关的漫长心理独白、重复枯燥的修炼刷怪打脸水文、无实质推进的过度铺垫），数组形式；\n'
      '6. can_modify: 【可改情节清单】（允许合并的边缘功能性工具人配角、可精简重组的转场过渡场景），数组形式；\n'
      '7. characters: 【核心角色画像清单】（主角、关键反派、核心配角），包含姓名 name、角色定位 role（如主角/宿敌反派/引路师长/盟友）、性格特征 personality（心理特征与行为风格）、外貌体态描述及生图 Prompt 关键词 appearance_features、核心行动动机 motivation；\n'
      '8. character_relations: 【网状人物关系矩阵】，包含主体 from、客体 to、关系类型 relation_type（如师徒反目/生死宿敌/利益同盟/暗生情愫）、张力说明 description；\n'
      '9. season_number: 当前规划季数（整型数字，默认 1）；\n'
      '10. season_title: 本季独立季名（如《第1季：神手夺舍风云》）；\n'
      '11. adapted_chapters_range: 本季建议覆盖的原著章节范围（如“原著第 1 ~ 80 章”）；\n'
      '12. season_climax: 本季季终大高潮核心事件（如“韩立识破毒计绝境反杀墨大夫，夺取长春功秘本离开七玄门”）；\n'
      '13. seasons_roadmap: 【全书多季宇宙规划路线图】（数组格式，建议 3~6 季，依据原著全书宏观脉络与境界演进划分，覆盖全书主要篇章）。每个季度条目包含：\n'
      '    - season_number: 季序号（整型，1, 2, 3...）；\n'
      '    - season_title: 季独立剧名（如“第1季：神手夺舍风云”）；\n'
      '    - adapted_chapters_range: 原著章节跨度（如“第 1 ~ 80 章”）；\n'
      '    - recommended_episode_count: 本季建议集数（整型，如 80）；\n'
      '    - season_theme: 核心叙事主题与阶段目标（30~60字）；\n'
      '    - core_antagonist: 本季主要对手/反派势力；\n'
      '    - season_climax: 季终决胜大高潮；\n'
      '14. key_props: 【核心关键道具清单】（贯穿全书或推动核心剧情的金手指、信物、核心武器兵器、宗门至宝、关键证物，3~8个），数组格式。每个条目包含：\n'
      '    - name: 道具名称（如“掌天瓶”、“玄铁短刃”）；\n'
      '    - category: 道具分类（如“核心金手指/标志性武器/师门信物/关键证物/通灵法宝”）；\n'
      '    - significance: 核心戏剧功能与剧情重要性说明（如“韩立立身之本，能吸收月华催熟草药，引来杀身之祸”）；\n'
      '    - appearance: 外观形制、材质反光与纹理生图提示词特征（如“绿色磨砂小玉瓶，表面雕刻古朴云雷花纹，暗光流转 (small green jade bottle, frosted texture, ancient cloud thunder patterns, subtle ethereal glow)”）。\n\n'
      '$_commonOutputRules\n\n'
      '【Output JSON Schema】\n'
      '{"recommended_episode_count": 80, "episode_count_reason": "原著前段篇幅宏大，涵盖拜师入谷、暗藏灵药、识破夺舍三幕高潮，80集能充分展开悬念反转且不注水", '
      '"season_number": 1, "season_title": "第1季：神手夺舍风云", "adapted_chapters_range": "原著第 1 ~ 80 章", "season_climax": "韩立识破毒计反杀墨大夫", '
      '"seasons_roadmap": [{"season_number": 1, "season_title": "第1季：神手夺舍风云", "adapted_chapters_range": "第 1 ~ 80 章", "recommended_episode_count": 80, "season_theme": "凡躯逆袭修仙，暗藏掌天瓶，杀墨夺舍破局", "core_antagonist": "墨大夫 (余子童)", "season_climax": "神手谷密室绝境反杀墨大夫"}, {"season_number": 2, "season_title": "第2季：宗门试炼秘境", "adapted_chapters_range": "第 81 ~ 220 章", "recommended_episode_count": 80, "season_theme": "拜入黄枫谷，血色禁地生死夺宝，成功筑基", "core_antagonist": "封岳与六宗魔道修士", "season_climax": "血色试炼夺得灵药破境筑基"}], '
      '"master_plot": "...", "must_keep": [{"title": "神手谷拜师", "description": "韩立拜入墨大夫门下并发现长春功秘密", "significance": "主线开端核心契约"}], '
      '"can_cut": [{"title": "七玄门内部杂役弟子杂务争吵", "description": "无主线推动价值的重复琐事", "reason": "拖慢短剧节奏"}], '
      '"can_modify": [{"title": "合并三位巡山师兄为一人", "description": "合并工具人台词", "suggestion": "减少角色资产数量，集中矛盾"}], '
      '"characters": [{"name": "韩立", "role": "主角", "personality": "隐忍低调、心狠手辣但有底线、求生欲极强", "appearance_features": "肤色黝黑朴素，粗布麻衣，眼神沉稳坚毅 (dark skinned youth, plain cloth robe, determined eyes)", "motivation": "追求长生与在修仙残酷界保全性命"}], '
      '"character_relations": [{"from": "韩立", "to": "墨大夫", "relation_type": "虚与委蛇的师徒死敌", "description": "表面恭顺学医采药，实则各自暗藏杀机，最终生死对决"}], '
      '"key_props": [{"name": "掌天瓶", "category": "核心金手指", "significance": "韩立立身之本，能吸收月华催熟草药，引来杀身之祸", "appearance": "绿色磨砂小玉瓶，表面雕刻古朴云雷花纹，暗光流转 (small green jade bottle, frosted texture, ancient cloud thunder patterns, subtle ethereal glow)"}]}\n';

  static const String _promptWritersRoomMacroArcs =
      '你是一位擅长把控影视与爆款短剧全季大结构的资深剧作监制。你的职责是依据小说主线脉络、改编边界与核心人物，为全季划分出 3~6 个极具戏剧张力的大篇章宏观大幕 (macro_arcs)。\n\n'
      '【四幕弧光设计原则】\n'
      '1. 破局立威（如第 1 幕，约占 25% 集数）：主角初登场、世界观展开、获得关键机缘或金手指、斩杀首个敌人确立生存主线；\n'
      '2. 矛盾升级（如第 2 幕，约占 25% 集数）：势力渗透、暗流涌动、与盟友建立微妙关系、粉碎中级危机；\n'
      '3. 巅峰绝境（如第 3 幕，约占 25% 集数）：强敌倾巢而出、主角被逼入绝境、身份濒临暴露或至亲陷入危局；\n'
      '4. 绝地反击与季终高潮（如第 4 幕，约占 25% 集数）：底牌全出、大高潮殊死搏杀、斩杀核心反派、结尾留下宏大新悬念。\n\n'
      '【输出核心要求】\n'
      '根据本季期望的总集数与原著章节跨度，合理分配各幕覆盖的集数范围（episode_range，如 "1-15", "16-30" 等）与原著章节范围（chapter_range，如 "1-12", "13-28" 等），确保所有大幕连续完整覆盖 1 到目标集数。\n\n'
      '$_commonOutputRules\n\n'
      '【Output JSON Schema】\n'
      '{"season_title": "神手谷夺舍风云", "target_duration_sec": 90, "macro_arcs": ['
      '{"arc_number": 1, "title": "拜师与暗藏神瓶", "episode_range": "1-15", "chapter_range": "1-12", "core_conflict": "韩立在墨大夫眼皮底下修习长春功并暗藏灵瓶", "turning_point": "偶然发现绿液能催熟草药"}, '
      '{"arc_number": 2, "title": "各怀鬼胎与药谷疑云", "episode_range": "16-30", "chapter_range": "13-28", "core_conflict": "墨大夫试探与催熟灵药", "turning_point": "察觉墨大夫恶意"}, '
      '{"arc_number": 3, "title": "七玄内乱与图穷匕见", "episode_range": "31-45", "chapter_range": "29-45", "core_conflict": "野狼帮入侵与七玄危机", "turning_point": "墨大夫回谷逼迫"}, '
      '{"arc_number": 4, "title": "密室夺舍与绝命反杀", "episode_range": "46-60", "chapter_range": "46-60", "core_conflict": "夺舍殊死对决", "turning_point": "反杀墨大夫踏入仙路"}'
      ']}\n';

  static const String _promptWritersRoomSeasonBeats =
      '你是一位擅长把控全季节奏的爆款短剧剧作总监。你的任务是依据小说主线脉络、改编边界与角色关系，将全季合理规划为【两级结构：宏观篇章大幕 (macro_arcs) + 单集高能分集大纲 (episodes)】。\n\n'
      '【两级规划核心原则】\n'
      '1. macro_arcs: 将全季按四幕弧光展开划分为 3~6 个核心大篇章/幕（破局立威 -> 危机加剧 -> 巅峰绝境 -> 季终反转），标定每幕序号 arc_number、篇章标题 title、覆盖集数范围 episode_range、对应原著章节范围 chapter_range、核心对抗矛盾 core_conflict、转折爆点 turning_point；\n'
      '2. episodes 规划规则：\n'
      '   - 必须基于原著小说情节密度与戏剧冲突，自然推演并输出完整、紧凑的高能独立分集；\n'
      '   - 严禁机械克隆或多集使用相同矛盾！每一集必须有具体的戏剧推进动作与独特的集尾悬念；\n'
      '   - 标题必须具备吸引力，严禁添加任何类似 "(节拍 X)" 的机械化后缀。\n'
      '   每个分集条目包含：\n'
      '   - episode_number: 集数（从 1 开始连续递增）；\n'
      '   - arc_name: 所属篇章大幕名称；\n'
      '   - title: 单集吸睛标题；\n'
      '   - chapter_range: 本集取材的原著小说章节范围（如 "1-3"、"4-5" 等，必须根据情节密度合理分配，绝非机械 1:1！）；\n'
      '   - conflict: 单集核心对抗事件与危机冲突（30~50字）；\n'
      '   - characters: 本集核心登场角色姓名数组；\n'
      '   - key_props: 本集核心登场或使用的关键道具名称数组（如 ["掌天瓶"]，无核心道具可为空数组）；\n'
      '   - hook: 结尾极限留钩与断章悬念（20~40字，卡在最强反转瞬间）；\n'
      '   - duration_sec: 单集建议时长（秒数，如 90）。\n\n'
      '$_commonOutputRules\n\n'
      '【Output JSON Schema】\n'
      '{"season_title": "神手谷夺舍风云", "target_duration_sec": 90, '
      '"macro_arcs": [{"arc_number": 1, "title": "拜师与暗藏神瓶", "episode_range": "1-20", "chapter_range": "1-15", "core_conflict": "韩立在墨大夫眼皮底下修习长春功并暗藏灵瓶", "turning_point": "偶然发现绿液能催熟草药"}], '
      '"episodes": [{"episode_number": 1, "arc_name": "拜师与暗藏神瓶", "title": "神秘药园", "chapter_range": "1-3", "conflict": "墨大夫暗查灵根，韩立暗藏掌天瓶", "characters": ["墨大夫", "韩立"], "key_props": ["掌天瓶"], "hook": "墨大夫深夜突然推开密室暗门，眼神森冷盯着韩立后背", "duration_sec": 90}]}\n';

  static const String _promptWritersRoomDialogue =
      '你是一位经验丰富、善于倾听并精准执行制片人意图的短剧 AI 联合编剧。制片人正在与你讨论并修改全季分集大纲。\n\n'
      '【交互原则】\n'
      '1. 认真领会制片人的修改指令（如“把前三集节奏加快”、“第5集高潮提前到第2集”、“删除某个配角并合并到主角兄弟身上”、“调整第1集取材为第1~2章”）；\n'
      '2. 给出专业的影视剧作反馈，分析修改对前后伏笔与因果链的影响；\n'
      '3. 给出清晰具体的修订方案，并返回更新后的分集变动详情。\n\n'
      '$_commonOutputRules\n\n'
      '【Output JSON Schema】\n'
      '{"reply": "已按要求将前三集节奏加快，第一集改为浓缩第1~2章退婚高潮...", "updated_episodes": [{"episode_number": 1, "title": "退婚之辱", "chapter_range": "1-2", "conflict": "家族当众退婚", "characters": ["萧炎", "纳兰嫣然"], "hook": "三年之约立下，玄重尺震地"}]}\n';
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
      gazeDirection: text('gaze_direction'),
      cameraAxis: text('camera_axis'),
      cameraAngle: text('camera_angle'),
      elevationLevel: text('elevation_level'),
      gazeTarget: text('gaze_target'),
      mountOrVehicle: text('mount_or_vehicle'),
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
            final bProps = (b['props'] as List?)?.cast<String>() ?? const [];
            final bHoldingItem = (b['holding_item'] ?? b['holdingItem'] as String? ?? '').trim();
            final bHoldingHand = (b['holding_hand'] ?? b['holdingHand'] as String? ?? '').trim();

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
              if (bProps.isNotEmpty) 'props': bProps,
              if (bHoldingItem.isNotEmpty) 'holding_item': bHoldingItem,
              if (bHoldingHand.isNotEmpty) 'holding_hand': bHoldingHand,
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
          final bProps = (b['props'] as List?)?.cast<String>() ?? const [];
          final bHoldingItem = (b['holding_item'] ?? b['holdingItem'] as String? ?? '').trim();
          final bHoldingHand = (b['holding_hand'] ?? b['holdingHand'] as String? ?? '').trim();

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
            if (bProps.isNotEmpty) 'props': bProps,
            if (bHoldingItem.isNotEmpty) 'holding_item': bHoldingItem,
            if (bHoldingHand.isNotEmpty) 'holding_hand': bHoldingHand,
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

  static Map<String, dynamic>? videoPromptRewrite(Map<String, dynamic> data) {
    if (data.containsKey('rewritten_prompt') && data['rewritten_prompt'] is String) {
      final p = (data['rewritten_prompt'] as String).trim();
      if (p.isNotEmpty) return {'rewritten_prompt': p};
    }
    return null;
  }

  static Map<String, dynamic>? directorAuditAutoFix(Map<String, dynamic> data) {
    if (data.containsKey('fixed_shots') && data['fixed_shots'] is List) {
      return data;
    }
    return null;
  }

  static Map<String, dynamic>? writersRoomMasterExtract(Map<String, dynamic> data) {
    if (!data.containsKey('master_plot')) {
      return null;
    }
    final normalized = Map<String, dynamic>.from(data);

    // 推荐集数容错与归一化
    final recCountRaw = normalized['recommended_episode_count'];
    int recCount = 80;
    if (recCountRaw is num) {
      recCount = recCountRaw.toInt();
    } else if (recCountRaw is String) {
      recCount = int.tryParse(recCountRaw) ?? 80;
    }
    if (recCount < 6) recCount = 12;
    if (recCount > 500) recCount = 120;
    normalized['recommended_episode_count'] = recCount;

    if (!normalized.containsKey('episode_count_reason') ||
        normalized['episode_count_reason'] == null ||
        (normalized['episode_count_reason'] as String).isEmpty) {
      normalized['episode_count_reason'] = '根据小说情节密度与短剧节奏推荐';
    }

    // 必留/可删/可改安全保底
    for (final key in ['must_keep', 'can_cut', 'can_modify']) {
      final list = normalized[key];
      if (list is List) {
        normalized[key] = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        normalized[key] = <Map<String, dynamic>>[];
      }
    }

    // 角色画像列表规范化
    final charsRaw = normalized['characters'];
    final List<Map<String, dynamic>> cleanChars = [];
    if (charsRaw is List) {
      for (final item in charsRaw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final name = (m['name'] as String? ?? '').trim();
          if (name.isNotEmpty) {
            cleanChars.add({
              'name': name,
              'role': (m['role'] as String? ?? '核心角色').trim(),
              'personality': (m['personality'] as String? ?? '').trim(),
              'appearance_features': (m['appearance_features'] as String? ?? '').trim(),
              'motivation': (m['motivation'] as String? ?? '').trim(),
            });
          }
        }
      }
    }
    normalized['characters'] = cleanChars;

    // 角色网状关系矩阵规范化
    final relsRaw = normalized['character_relations'];
    final List<Map<String, dynamic>> cleanRels = [];
    if (relsRaw is List) {
      for (final item in relsRaw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final from = (m['from'] as String? ?? '').trim();
          final to = (m['to'] as String? ?? '').trim();
          if (from.isNotEmpty && to.isNotEmpty) {
            cleanRels.add({
              'from': from,
              'to': to,
              'relation_type': (m['relation_type'] as String? ?? '关联').trim(),
              'description': (m['description'] as String? ?? '').trim(),
            });
          }
        }
      }
    }
    normalized['character_relations'] = cleanRels;

    // 核心关键道具清单规范化
    final propsRaw = normalized['key_props'];
    final List<Map<String, dynamic>> cleanProps = [];
    if (propsRaw is List) {
      for (final item in propsRaw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final name = (m['name'] as String? ?? '').trim();
          if (name.isNotEmpty) {
            cleanProps.add({
              'name': name,
              'category': (m['category'] as String? ?? '核心道具').trim(),
              'significance': (m['significance'] as String? ?? '').trim(),
              'appearance': (m['appearance'] as String? ?? '').trim(),
            });
          }
        }
      }
    }
    normalized['key_props'] = cleanProps;

    // 多季宇宙与首季规划规范化
    normalized['season_number'] = (normalized['season_number'] as num?)?.toInt() ?? 1;
    final seasonTitle = (normalized['season_title'] as String? ?? '').trim();
    normalized['season_title'] = seasonTitle.isNotEmpty ? seasonTitle : '第1季';
    final chaptersRange = (normalized['adapted_chapters_range'] as String? ?? '').trim();
    normalized['adapted_chapters_range'] = chaptersRange.isNotEmpty ? chaptersRange : '原著第 1 ~ $recCount 章';
    normalized['season_climax'] = (normalized['season_climax'] as String? ?? '').trim();

    // 全书多季宇宙路线图规范化与自愈兜底
    final roadmapRaw = normalized['seasons_roadmap'];
    final List<Map<String, dynamic>> cleanRoadmap = [];
    if (roadmapRaw is List && roadmapRaw.isNotEmpty) {
      for (int i = 0; i < roadmapRaw.length; i++) {
        final item = roadmapRaw[i];
        if (item is Map) {
          final sNum = (item['season_number'] as num?)?.toInt() ?? (i + 1);
          final sTitle = (item['season_title'] as String? ?? '第$sNum季').trim();
          final cRange = (item['adapted_chapters_range'] as String? ?? '').trim();
          final epCount = (item['recommended_episode_count'] as num?)?.toInt() ?? 80;
          final theme = (item['season_theme'] as String? ?? '').trim();
          final antagonist = (item['core_antagonist'] as String? ?? '').trim();
          final climax = (item['season_climax'] as String? ?? '').trim();
          cleanRoadmap.add({
            'season_number': sNum,
            'season_title': sTitle.isNotEmpty ? sTitle : '第$sNum季',
            'adapted_chapters_range': cRange.isNotEmpty ? cRange : '原著阶段 $sNum',
            'recommended_episode_count': epCount > 0 ? epCount : 80,
            'season_theme': theme,
            'core_antagonist': antagonist,
            'season_climax': climax,
          });
        }
      }
    }

    // 若大模型输出缺失 seasons_roadmap，用当前单季元数据自愈兜底生成至少包含第 1 季的路线图
    if (cleanRoadmap.isEmpty) {
      cleanRoadmap.add({
        'season_number': normalized['season_number'] ?? 1,
        'season_title': normalized['season_title'] ?? '第1季',
        'adapted_chapters_range': normalized['adapted_chapters_range'] ?? '原著第 1 ~ $recCount 章',
        'recommended_episode_count': recCount,
        'season_theme': normalized['episode_count_reason'] ?? '开局破局与命运逆转',
        'core_antagonist': '宿敌与强敌',
        'season_climax': normalized['season_climax'] ?? '',
      });
    }
    normalized['seasons_roadmap'] = cleanRoadmap;

    return normalized;
  }

  static Map<String, dynamic>? writersRoomMacroArcs(
    Map<String, dynamic> data, {
    int targetEpisodeCount = 80,
    int targetDurationSec = 90,
  }) {
    if (data.isEmpty) return null;
    final normalized = Map<String, dynamic>.from(data);
    normalized['target_duration_sec'] =
        (normalized['target_duration_sec'] as num?)?.toInt() ?? targetDurationSec;

    final arcsRaw = normalized['macro_arcs'];
    final List<Map<String, dynamic>> cleanArcs = [];
    if (arcsRaw is List && arcsRaw.isNotEmpty) {
      for (int i = 0; i < arcsRaw.length; i++) {
        final a = arcsRaw[i];
        if (a is Map) {
          cleanArcs.add({
            'arc_number': (a['arc_number'] as num?)?.toInt() ?? (i + 1),
            'title': (a['title'] as String? ?? '第 ${i + 1} 幕').trim(),
            'episode_range': (a['episode_range'] as String? ?? '').trim(),
            'chapter_range': (a['chapter_range'] as String? ?? '').trim(),
            'core_conflict': (a['core_conflict'] as String? ?? '').trim(),
            'turning_point': (a['turning_point'] as String? ?? '').trim(),
          });
        }
      }
    }
    if (cleanArcs.isEmpty) {
      final perArc = (targetEpisodeCount / 4).ceil();
      cleanArcs.addAll([
        {
          'arc_number': 1,
          'title': '开局破局与暗藏机锋',
          'episode_range': '1-$perArc',
          'chapter_range': '',
          'core_conflict': '危机降临与破局自保',
          'turning_point': '初获机缘',
        },
        {
          'arc_number': 2,
          'title': '蓄势博弈与冲突升级',
          'episode_range': '${perArc + 1}-${perArc * 2}',
          'chapter_range': '',
          'core_conflict': '各怀鬼胎与实力激增',
          'turning_point': '发现惊天杀机',
        },
        {
          'arc_number': 3,
          'title': '图穷匕见与绝境逼迫',
          'episode_range': '${perArc * 2 + 1}-${perArc * 3}',
          'chapter_range': '',
          'core_conflict': '对手撕破伪装与生死博弈',
          'turning_point': '坠入绝境孤注一掷',
        },
        {
          'arc_number': 4,
          'title': '极限反杀与季终高潮',
          'episode_range': '${perArc * 3 + 1}-$targetEpisodeCount',
          'chapter_range': '',
          'core_conflict': '最终殊死对决与命途逆转',
          'turning_point': '斩除强敌踏入新征途',
        },
      ]);
    }
    normalized['macro_arcs'] = cleanArcs;
    return normalized;
  }

  static Map<String, dynamic>? writersRoomSeasonBeats(
    Map<String, dynamic> data, {
    int targetEpisodeCount = 80,
    int targetDurationSec = 90,
    String seasonChaptersRange = '',
  }) {
    if (data.isEmpty) return null;
    final normalized = Map<String, dynamic>.from(data);
    normalized['target_duration_sec'] =
        (normalized['target_duration_sec'] as num?)?.toInt() ?? targetDurationSec;

    // 1. 规范化 macro_arcs
    final arcsRaw = normalized['macro_arcs'];
    final List<Map<String, dynamic>> cleanArcs = [];
    if (arcsRaw is List && arcsRaw.isNotEmpty) {
      for (int i = 0; i < arcsRaw.length; i++) {
        final a = arcsRaw[i];
        if (a is Map) {
          cleanArcs.add({
            'arc_number': (a['arc_number'] as num?)?.toInt() ?? (i + 1),
            'title': (a['title'] as String? ?? '第 ${i + 1} 幕').trim(),
            'episode_range': (a['episode_range'] as String? ?? '').trim(),
            'chapter_range': (a['chapter_range'] as String? ?? '').trim(),
            'core_conflict': (a['core_conflict'] as String? ?? '').trim(),
            'turning_point': (a['turning_point'] as String? ?? '').trim(),
          });
        }
      }
    }
    if (cleanArcs.isEmpty) {
      final perArc = (targetEpisodeCount / 4).ceil();
      cleanArcs.addAll([
        {
          'arc_number': 1,
          'title': '开局破局与暗藏机锋',
          'episode_range': '1-$perArc',
          'chapter_range': '',
          'core_conflict': '危机降临与破局自保',
          'turning_point': '初获机缘',
        },
        {
          'arc_number': 2,
          'title': '蓄势博弈与冲突升级',
          'episode_range': '${perArc + 1}-${perArc * 2}',
          'chapter_range': '',
          'core_conflict': '各怀鬼胎与实力激增',
          'turning_point': '发现惊天杀机',
        },
        {
          'arc_number': 3,
          'title': '图穷匕见与绝境逼迫',
          'episode_range': '${perArc * 2 + 1}-${perArc * 3}',
          'chapter_range': '',
          'core_conflict': '对手撕破伪装与生死博弈',
          'turning_point': '坠入绝境孤注一掷',
        },
        {
          'arc_number': 4,
          'title': '极限反杀与季终高潮',
          'episode_range': '${perArc * 3 + 1}-$targetEpisodeCount',
          'chapter_range': '',
          'core_conflict': '最终殊死对决与命途逆转',
          'turning_point': '斩除强敌踏入新征途',
        },
      ]);
    }
    normalized['macro_arcs'] = cleanArcs;

    // 2. 规范化并扩充 episodes，严格保障目标集数
    final epsRaw = normalized['episodes'];
    final rawEps = (epsRaw is List)
        ? epsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> fullEps = [];
    if (rawEps.isEmpty) {
      final defaultCount = targetEpisodeCount > 0 ? targetEpisodeCount : 12;
      for (int i = 1; i <= defaultCount; i++) {
        final arc = _findArcName(i, cleanArcs);
        final parsedCh = AiConstraintEngine.parseChapterRange(
          null,
          fallbackEpisodeIndex: i,
          totalEpisodes: defaultCount,
          seasonChaptersRange: seasonChaptersRange,
        );
        fullEps.add({
          'episode_number': i,
          'arc_name': arc,
          'title': '第 $i 集',
          'chapter_range': parsedCh.rangeDesc,
          'chapter_indices': parsedCh.indices,
          'conflict': '推进本幕核心危机与对抗',
          'characters': <String>[],
          'key_props': <String>[],
          'hook': '本集末尾悬念反转钩子',
          'duration_sec': targetDurationSec,
        });
      }
    } else {
      // 真实保留大模型推演的每一集，按序规范编号，严禁任何机械拉伸克隆与 (节拍X) 后缀
      for (int i = 0; i < rawEps.length; i++) {
        final ep = rawEps[i];
        final epNum = i + 1;
        var title = (ep['title'] as String? ?? '第 $epNum 集').trim();
        // 彻底清除历史残留或误输出的 "(节拍 X)" 后缀
        title = title.replaceAll(RegExp(r'\s*\(节拍\s*\d+\)'), '').trim();
        if (title.isEmpty) title = '第 $epNum 集';

        final parsedCh = AiConstraintEngine.parseChapterRange(
          ep['chapter_range'],
          fallbackEpisodeIndex: epNum,
          totalEpisodes: targetEpisodeCount,
          seasonChaptersRange: seasonChaptersRange,
        );

        fullEps.add({
          'episode_number': epNum,
          'arc_name': (ep['arc_name'] as String? ?? _findArcName(epNum, cleanArcs)).trim(),
          'title': title,
          'chapter_range': parsedCh.rangeDesc,
          'chapter_indices': parsedCh.indices,
          'conflict': (ep['conflict'] as String? ?? '').trim(),
          'characters': (ep['characters'] as List? ?? []).map((c) => c.toString()).toList(),
          'key_props': (ep['key_props'] as List? ?? []).map((p) => p.toString().trim()).where((p) => p.isNotEmpty).toList(),
          'hook': (ep['hook'] as String? ?? '').trim(),
          'duration_sec': (ep['duration_sec'] as num?)?.toInt() ?? targetDurationSec,
        });
      }
    }
    normalized['episodes'] = fullEps;
    return normalized;
  }

  static Map<String, dynamic>? writersRoomArcBeats(
    Map<String, dynamic> data, {
    required int startEpisode,
    required int endEpisode,
    required String arcName,
    required int targetDurationSec,
    String arcChapterRange = '',
    int totalEpisodes = 80,
    String seasonChaptersRange = '',
  }) {
    if (data.isEmpty) return null;
    final normalized = Map<String, dynamic>.from(data);
    final epsRaw = normalized['episodes'];
    final rawEps = (epsRaw is List)
        ? epsRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final List<Map<String, dynamic>> cleanEps = [];
    final expectedCount = endEpisode - startEpisode + 1;

    if (rawEps.isEmpty) {
      for (int i = 0; i < expectedCount; i++) {
        final epNum = startEpisode + i;
        final parsedCh = AiConstraintEngine.parseChapterRange(
          null,
          fallbackEpisodeIndex: epNum,
          totalEpisodes: totalEpisodes,
          seasonChaptersRange: arcChapterRange.isNotEmpty ? arcChapterRange : seasonChaptersRange,
        );
        cleanEps.add({
          'episode_number': epNum,
          'arc_name': arcName,
          'title': '第 $epNum 集',
          'chapter_range': parsedCh.rangeDesc,
          'chapter_indices': parsedCh.indices,
          'conflict': '推进本幕核心危机与对抗',
          'characters': <String>[],
          'key_props': <String>[],
          'hook': '本集末尾悬念反转钩子',
          'duration_sec': targetDurationSec,
        });
      }
    } else {
      final limit = rawEps.length > expectedCount ? expectedCount : rawEps.length;
      for (int i = 0; i < limit; i++) {
        final ep = rawEps[i];
        final epNum = startEpisode + i;
        var title = (ep['title'] as String? ?? '第 $epNum 集').trim();
        title = title.replaceAll(RegExp(r'\s*\(节拍\s*\d+\)'), '').trim();
        if (title.isEmpty) title = '第 $epNum 集';

        final parsedCh = AiConstraintEngine.parseChapterRange(
          ep['chapter_range'],
          fallbackEpisodeIndex: epNum,
          totalEpisodes: totalEpisodes,
          seasonChaptersRange: arcChapterRange.isNotEmpty ? arcChapterRange : seasonChaptersRange,
        );

        cleanEps.add({
          'episode_number': epNum,
          'arc_name': (ep['arc_name'] as String? ?? arcName).trim(),
          'title': title,
          'chapter_range': parsedCh.rangeDesc,
          'chapter_indices': parsedCh.indices,
          'conflict': (ep['conflict'] as String? ?? '').trim(),
          'characters': (ep['characters'] as List? ?? []).map((c) => c.toString()).toList(),
          'key_props': (ep['key_props'] as List? ?? []).map((p) => p.toString().trim()).where((p) => p.isNotEmpty).toList(),
          'hook': (ep['hook'] as String? ?? '').trim(),
          'duration_sec': (ep['duration_sec'] as num?)?.toInt() ?? targetDurationSec,
        });
      }
    }

    normalized['episodes'] = cleanEps;
    return normalized;
  }

  static String _findArcName(int epNum, List<Map<String, dynamic>> arcs) {
    if (arcs.isEmpty) return '核心篇章';
    for (final arc in arcs) {
      final range = arc['episode_range'] as String? ?? '';
      final parts = range.split('-');
      if (parts.length == 2) {
        final start = int.tryParse(parts[0].trim());
        final end = int.tryParse(parts[1].trim());
        if (start != null && end != null && epNum >= start && epNum <= end) {
          return arc['title'] as String? ?? '第 ${arc["arc_number"]} 幕';
        }
      }
    }
    return arcs.first['title'] as String? ?? '核心篇章';
  }

  static Map<String, dynamic>? writersRoomDialogue(Map<String, dynamic> data) {
    if (data.containsKey('reply')) {
      final updatedRaw = data['updated_episodes'];
      if (updatedRaw is List) {
        final List<Map<String, dynamic>> cleanUpdated = [];
        for (final item in updatedRaw) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final epNum = (m['episode_number'] as num?)?.toInt() ?? 1;
            final rawCh = m['chapter_range'];
            final parsed = AiConstraintEngine.parseChapterRange(rawCh, fallbackEpisodeIndex: epNum);
            m['chapter_range'] = parsed.rangeDesc;
            m['chapter_indices'] = parsed.indices;
            cleanUpdated.add(m);
          }
        }
        data['updated_episodes'] = cleanUpdated;
      }
      return data;
    }
    return null;
  }
}
