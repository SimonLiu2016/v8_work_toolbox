/// 剧本工坊可拍性评估与视听外化自愈引擎（Screenplay Shootability & Show-Don't-Tell Evaluator）。
///
/// 负责第一阶段「小说 → 剧本」的四维质量评价与自愈：
/// 1. 视觉外化率（Show, Don't Tell）：拦截抽象心理描写、文学比喻修辞与时间跨度概括词；
/// 2. 场次时空收敛度（Scene Unity）：检测单场戏内跨室内外或多物理空间混杂；
/// 3. 对白可演性（Speakability）：检测单句无停顿超长对白呼吸过载；
/// 4. 一键视听外化改写：将抽象心理/比喻转化为摄影机可捕捉的微表情、肢体动势与物理反馈。
library;

import 'dart:convert';

import '../../../services/ai_config_store.dart';
import '../../../services/ai_service.dart';
import '../models/studio_models.dart';

/// 剧本可拍性问题分类。
enum ScreenplayIssueCategory {
  unshootableMental('MENTAL', '抽象心理词（不可拍）'),
  literaryMetaphor('METAPHOR', '文学比喻修辞'),
  temporalSummary('TEMPORAL', '时间跨度概括'),
  sceneUnityViolation('SCENE_UNITY', '场次时空混杂'),
  breathOverload('BREATH', '对白呼吸过载'),
  environmentalAnomaly('PLAUSIBILITY', '环境生态常识失真（如横尸闹市无围观）'),
  beatPacingFlaw('PACING', '短剧节奏与断章缺陷');

  final String code;
  final String label;
  const ScreenplayIssueCategory(this.code, this.label);
}

/// 单条剧本可拍性诊断条目。
class ScreenplayQualityIssue {
  final ScreenplayIssueCategory category;
  final int sceneNumber;
  final int? beatOrder;
  final List<String> matchedWords;
  final String snippet;
  final String message;
  final String suggestion;

  const ScreenplayQualityIssue({
    required this.category,
    required this.sceneNumber,
    this.beatOrder,
    this.matchedWords = const [],
    required this.snippet,
    required this.message,
    required this.suggestion,
  });
}

/// 剧本可拍性综合评估报告。
class ScreenplayQualityReport {
  /// 剧本综合可拍性评分（0-100）。
  final int overallScore;

  /// 视觉外化率评分（0-100）。
  final int externalizationScore;

  /// 场次时空纯度评分（0-100）。
  final int sceneUnityScore;

  /// 对白呼吸可演性评分（0-100）。
  final int speakabilityScore;

  /// 检出的全部诊断问题。
  final List<ScreenplayQualityIssue> issues;

  const ScreenplayQualityReport({
    required this.overallScore,
    required this.externalizationScore,
    required this.sceneUnityScore,
    required this.speakabilityScore,
    required this.issues,
  });

  bool get isClean => issues.isEmpty;

  List<ScreenplayQualityIssue> issuesForScene(int sceneNumber) =>
      issues.where((i) => i.sceneNumber == sceneNumber).toList();
}

/// 剧本质量评估与视听外化改写器。
class ScreenplayQualityEvaluator {
  ScreenplayQualityEvaluator._();

  /// 典型不可拍抽象心理词词库。
  static const List<String> mentalKeywords = [
    '心中暗想',
    '心中暗道',
    '暗自心惊',
    '心中忌惮',
    '心生忌惮',
    '心中冷笑',
    '心中一凛',
    '心中五味杂陈',
    '觉得',
    '心想',
    '意识到',
    '察觉到',
    '深不可测',
    '暗自思忖',
    '暗自警惕',
    '不由得想',
    '脑海中闪过',
    '心头涌起',
    '心中翻涌',
    '心中杀意',
    '心怀鬼胎',
  ];

  /// 典型文学比喻与修辞词词库（图像/视频模型易按字面画出幻觉物体）。
  static const List<String> metaphorKeywords = [
    '仿佛',
    '宛如',
    '犹如',
    '好似',
    '恰似',
    '恍若',
    '如同一座大山',
    '如同实质',
    '宛若神明',
    '如坠冰窖',
    '度日如年',
  ];

  /// 典型时间跨度概括词词库（破坏单镜连续时间流）。
  static const List<String> temporalSummaryKeywords = [
    '良久之后',
    '不知不觉',
    '半晌之后',
    '数个时辰',
    '转眼间过了',
    '过了许久',
    '渐渐地过去',
  ];

  /// 确定性心理/修辞到视听外化动作映射表（用于离线自愈与 AI 兜底）。
  static const Map<String, String> _deterministicExternalizationMap = {
    '心中暗自忌惮': '瞳孔微缩，握紧兵刃的指节泛白',
    '心中忌惮': '眼神骤然凝重，下意识后撤半步',
    '心生忌惮': '目光微凛，呼吸略微急促',
    '觉得此人深不可测': '上下打量对方，眉头紧锁',
    '深不可测': '神色深沉，目光如古井无波',
    '心中暗想': '目光微垂，指尖轻叩袖口',
    '心中暗道': '眸光微闪，嘴角掠过一丝极淡的弧度',
    '暗自心惊': '眼皮微跳，呼吸出现一瞬停滞',
    '心中冷笑': '嘴角勾起一抹冷峭的弧度，眼神淡漠',
    '心中一凛': '身形微绷，目光瞬间锐利',
    '心中五味杂陈': '眼神复杂地垂下眼帘，轻叹一声',
    '暗自思忖': '眉头微蹙，目光凝视前方虚空',
    '暗自警惕': '身体重心微沉，右手悄然按在腰间',
    '脑海中闪过': '眼神恍惚一瞬，随即猛然回神',
    '心头涌起': '胸口微微起伏，眼神渐趋炽热',
    '心中翻涌': '呼吸加重，额角青筋微跳',
    '心中杀意': '眼神骤冷，周身散发出凌厉寒意',
    '如同一座大山压来': '压迫得令人双肩微沉、呼吸凝滞',
    '如同一座大山': '气势沉凝厚重，令人呼吸一窒',
    '仿佛一座大山压来': '迫人的威压令四周空气仿佛凝固，压得人脊背微弯',
    '如坠冰窖': '浑身微颤，脸色瞬间褪去血色',
    '觉得': '目光微动，显露出警觉之色，',
    '心想': '神色微敛，',
    '意识到': '瞳孔骤缩，骤然反应过来，',
    '察觉到': '耳廓微动，敏锐地转头望去，',
    '不由得想': '神情微怔，',
    '仿佛': '呈现出逼真的态势，',
    '宛如': '态势神似',
    '犹如': '气势如同',
    '好似': '看似',
    '良久之后': '片刻停顿后',
    '不知不觉': '随着动作推进',
    '半晌之后': '短暂沉默后',
    '过了许久': '静默片刻后',
  };

  /// 单句开口对白最大建议字数（无标点停顿）。
  static const int maxSingleClauseChars = 25;

  /// 对单集剧本执行完整的可拍性评估。
  static ScreenplayQualityReport evaluate(StudioEpisode episode) {
    final issues = <ScreenplayQualityIssue>[];
    int mentalOrMetaphorCount = 0;
    int unityViolationCount = 0;
    int breathOverloadCount = 0;
    int totalBeats = 0;

    for (final scene in episode.scenes) {
      // 1. 检查场次时空纯度
      final locText = '${scene.title} ${scene.location} ${scene.dramaticObjective}';
      final hasIndoor = locText.contains('室内') ||
          locText.contains('雅间内') ||
          locText.contains('大堂内') ||
          locText.contains('房内') ||
          locText.contains('殿内') ||
          scene.setting.contains('内');
      final hasOutdoor = locText.contains('长街') ||
          locText.contains('街道') ||
          locText.contains('荒野') ||
          locText.contains('山道') ||
          locText.contains('城外') ||
          scene.setting.contains('外');

      // 检查节拍内是否跨越了截然不同的空间（例如从长街直接写到进了包厢内却未切场）
      final allBeatActions = scene.beats.map((b) => b.action).join(' ');
      if ((hasIndoor && hasOutdoor && locText.contains('转入')) ||
          (allBeatActions.contains('走出酒楼来到长街') && allBeatActions.contains('回到二楼雅间')) ||
          (scene.location.contains('/') && scene.location.split('/').length >= 3)) {
        unityViolationCount++;
        issues.add(
          ScreenplayQualityIssue(
            category: ScreenplayIssueCategory.sceneUnityViolation,
            sceneNumber: scene.sceneNumber,
            matchedWords: [scene.location.isNotEmpty ? scene.location : scene.title],
            snippet: '${scene.title} (${scene.location})',
            message: '第 ${scene.sceneNumber} 场同时包含多个跨度较大的物理空间，违反“一地一时”场次纯度原则。',
            suggestion: '建议按物理空间切换点（室内/室外或不同建筑）拆分为两个独立场次，确保每个场次唯一绑定一张场景资产卡。',
          ),
        );
      }

      for (final beat in scene.beats) {
        totalBeats++;
        final action = beat.action.trim();
        if (action.isNotEmpty) {
          // 2. 扫描抽象心理词
          final hitMental = <String>[];
          for (final kw in mentalKeywords) {
            if (action.contains(kw)) hitMental.add(kw);
          }
          if (hitMental.isNotEmpty) {
            mentalOrMetaphorCount += hitMental.length;
            issues.add(
              ScreenplayQualityIssue(
                category: ScreenplayIssueCategory.unshootableMental,
                sceneNumber: scene.sceneNumber,
                beatOrder: beat.order,
                matchedWords: hitMental,
                snippet: action,
                message:
                    '第 ${scene.sceneNumber} 场节拍 #${beat.order} 动作含不可拍抽象心理词（${hitMental.join("、")}），生图/生视频模型无法直接渲染内心想法。',
                suggestion: '使用「一键视听外化」将其转化为微表情、眼神变化或肢体动作（Show, Don\'t Tell）。',
              ),
            );
          }

          // 3. 扫描文学比喻修辞词
          final hitMetaphor = <String>[];
          for (final kw in metaphorKeywords) {
            if (action.contains(kw)) hitMetaphor.add(kw);
          }
          if (hitMetaphor.isNotEmpty) {
            mentalOrMetaphorCount += hitMetaphor.length;
            issues.add(
              ScreenplayQualityIssue(
                category: ScreenplayIssueCategory.literaryMetaphor,
                sceneNumber: scene.sceneNumber,
                beatOrder: beat.order,
                matchedWords: hitMetaphor,
                snippet: action,
                message:
                    '第 ${scene.sceneNumber} 场节拍 #${beat.order} 含文学比喻修辞（${hitMetaphor.join("、")}），易诱导扩散模型按字面画出幻觉物体。',
                suggestion: '剔除修辞比喻，改为直接描述光影反差、气浪尘土或人物受迫姿态。',
              ),
            );
          }

          // 4. 扫描时间跨度概括词
          final hitTemporal = <String>[];
          for (final kw in temporalSummaryKeywords) {
            if (action.contains(kw)) hitTemporal.add(kw);
          }
          if (hitTemporal.isNotEmpty) {
            mentalOrMetaphorCount += hitTemporal.length;
            issues.add(
              ScreenplayQualityIssue(
                category: ScreenplayIssueCategory.temporalSummary,
                sceneNumber: scene.sceneNumber,
                beatOrder: beat.order,
                matchedWords: hitTemporal,
                snippet: action,
                message:
                    '第 ${scene.sceneNumber} 场节拍 #${beat.order} 含时间跨度概括词（${hitTemporal.join("、")}），单镜视频（3-6s）无法承载长跨度时间流逝。',
                suggestion: '改为瞬时连续动作，或通过切镜转场体现时间流逝。',
              ),
            );
          }
        }

        // 5. 检查对白呼吸节奏（仅针对开口对白）
        final dialogue = beat.dialogue.trim();
        if (dialogue.isNotEmpty && beat.voiceType == UtteranceVoiceType.dialogue) {
          final cleanSpeech = dialogue
              .replaceAll(RegExp(r'^[A-Za-z0-9_\u4e00-\u9fa5]+[：:]\s*'), '')
              .replaceAll(RegExp(r'[（\(][^）\)]*[）\)]'), '')
              .trim();
          final clauses = cleanSpeech
              .split(RegExp(r'[，。！？；、,!\?;…—\n]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final longClause = clauses.where((c) => c.length > maxSingleClauseChars).firstOrNull;
          if (longClause != null) {
            breathOverloadCount++;
            issues.add(
              ScreenplayQualityIssue(
                category: ScreenplayIssueCategory.breathOverload,
                sceneNumber: scene.sceneNumber,
                beatOrder: beat.order,
                matchedWords: [longClause],
                snippet: dialogue,
                message:
                    '第 ${scene.sceneNumber} 场节拍 #${beat.order} 存在单句无停顿超长对白（${longClause.length} 字 > $maxSingleClauseChars 字上限），易撑爆单镜时长与口型节奏。',
                suggestion: '在中间增加短句标点停顿，或拆分为两个节拍交替呈现。',
              ),
            );
          }
        }

        // 5. 扫描公共空间环境生态常识（如闹市死伤无围观）
        final locCombined = '${scene.title} ${scene.location}';
        final isPublicSpace = locCombined.contains('街') ||
            locCombined.contains('市') ||
            locCombined.contains('堂') ||
            locCombined.contains('坊') ||
            locCombined.contains('广场') ||
            locCombined.contains('客栈') ||
            locCombined.contains('演武场');
        final hasSevereAnomaly = action.contains('横尸') ||
            action.contains('死人') ||
            action.contains('倒地身亡') ||
            action.contains('尸体') ||
            action.contains('被杀') ||
            action.contains('截杀') ||
            action.contains('行凶') ||
            action.contains('血泊');
        if (isPublicSpace && hasSevereAnomaly) {
          final hasCrowdReaction = action.contains('围观') ||
              action.contains('指点') ||
              action.contains('惊呼') ||
              action.contains('议论') ||
              action.contains('退避') ||
              action.contains('散开') ||
              action.contains('百姓') ||
              action.contains('路人') ||
              action.contains('捕快') ||
              action.contains('衙役') ||
              action.contains('看客') ||
              scene.atmosphere.contains('围观') ||
              scene.atmosphere.contains('议论');
          if (!hasCrowdReaction) {
            issues.add(
              ScreenplayQualityIssue(
                category: ScreenplayIssueCategory.environmentalAnomaly,
                sceneNumber: scene.sceneNumber,
                beatOrder: beat.order,
                matchedWords: ['公共空间异常无围观'],
                snippet: action,
                message:
                    '第 ${scene.sceneNumber} 场节拍 #${beat.order} 在公共开放空间（$locCombined）发生死伤异常，却无任何周边路人反应或官兵维持秩序，破坏环境常识真实感。',
                suggestion: '补全周边群众驻足指点、惊呼后退的生态描写；若情节要求绝对隐秘无人知晓，请将场景置换至死胡同、破庙柴房或深夜。',
              ),
            );
          }
        }
      }
    }

    // 6. 检查黄金 3 秒开局与片尾极限断章
    if (episode.scenes.isNotEmpty) {
      final firstBeat = episode.scenes.first.beats.firstOrNull;
      if (firstBeat != null) {
        final firstAct = firstBeat.action.trim();
        final isPassiveOpen = firstAct.contains('漫步') ||
            firstAct.contains('闲逛') ||
            firstAct.contains('散步') ||
            firstAct.length < 10;
        if (isPassiveOpen) {
          issues.add(
            ScreenplayQualityIssue(
              category: ScreenplayIssueCategory.beatPacingFlaw,
              sceneNumber: episode.scenes.first.sceneNumber,
              beatOrder: firstBeat.order,
              matchedWords: ['开局平缓散漫'],
              snippet: firstAct,
              message: '第 1 场首个节拍开场节奏过于平缓散漫，缺乏竖屏短剧“前 3 秒黄金抓眼球”的高压切入危机。',
              suggestion: '将核心对抗、紧急异变或视觉反差动作前置至开篇第 1 秒（Cold Open）。',
            ),
          );
        }
      }

      final lastBeat = episode.scenes.last.beats.lastOrNull;
      if (lastBeat != null) {
        final lastAct = lastBeat.action.trim();
        final isPassiveEnd = lastAct.contains('回房') ||
            lastAct.contains('入睡') ||
            lastAct.contains('各自散去') ||
            lastAct.contains('平息');
        if (isPassiveEnd) {
          issues.add(
            ScreenplayQualityIssue(
              category: ScreenplayIssueCategory.beatPacingFlaw,
              sceneNumber: episode.scenes.last.sceneNumber,
              beatOrder: lastBeat.order,
              matchedWords: ['平缓收尾缺少钩子'],
              snippet: lastAct,
              message: '单集末尾节拍平缓散场且缺少悬念留钩，无法驱动观众追看下一集。',
              suggestion: '在结尾停留在杀机降临、底牌即将揭晓的张力巅峰点（Cliffhanger）。',
            ),
          );
        }
      }
    }

    // 若尚未拆出结构化 scenes，但有 screenplayText，也对全文动作行做扫描
    if (episode.scenes.isEmpty && episode.screenplayText.trim().isNotEmpty) {
      final raw = episode.screenplayText;
      final hitMental = mentalKeywords.where((kw) => raw.contains(kw)).toList();
      final hitMetaphor = metaphorKeywords.where((kw) => raw.contains(kw)).toList();
      final hitTemporal = temporalSummaryKeywords.where((kw) => raw.contains(kw)).toList();

      if (hitMental.isNotEmpty) {
        mentalOrMetaphorCount += hitMental.length;
        issues.add(
          ScreenplayQualityIssue(
            category: ScreenplayIssueCategory.unshootableMental,
            sceneNumber: 1,
            matchedWords: hitMental,
            snippet: '剧本正文',
            message: '剧本正文中包含抽象心理描写词（${hitMental.join("、")}）。',
            suggestion: '建议使用「一键视听外化」将其转化为具体可拍的肢体动作与表情。',
          ),
        );
      }
      if (hitMetaphor.isNotEmpty) {
        mentalOrMetaphorCount += hitMetaphor.length;
        issues.add(
          ScreenplayQualityIssue(
            category: ScreenplayIssueCategory.literaryMetaphor,
            sceneNumber: 1,
            matchedWords: hitMetaphor,
            snippet: '剧本正文',
            message: '剧本正文中包含文学比喻词（${hitMetaphor.join("、")}）。',
            suggestion: '建议改为具象的物理光影与动作细节描写。',
          ),
        );
      }
      if (hitTemporal.isNotEmpty) {
        mentalOrMetaphorCount += hitTemporal.length;
        issues.add(
          ScreenplayQualityIssue(
            category: ScreenplayIssueCategory.temporalSummary,
            sceneNumber: 1,
            matchedWords: hitTemporal,
            snippet: '剧本正文',
            message: '剧本正文中包含时间跨度概括词（${hitTemporal.join("、")}）。',
            suggestion: '建议改为瞬时动作或明确切镜。',
          ),
        );
      }

      // 扫描正文中的对白气口
      final dialogueMatches = RegExp(r'["“]([^"”]+)["”]').allMatches(raw);
      for (final match in dialogueMatches) {
        final speech = match.group(1)!;
        final clauses = speech
            .split(RegExp(r'[，。！？；、,!\?;…—\n]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final longClause = clauses.where((c) => c.length > maxSingleClauseChars).firstOrNull;
        if (longClause != null) {
          breathOverloadCount++;
          issues.add(
            ScreenplayQualityIssue(
              category: ScreenplayIssueCategory.breathOverload,
              sceneNumber: 1,
              matchedWords: [longClause],
              snippet: speech,
              message: '剧本正文中对白包含无停顿超长句子（${longClause.length} 字 > $maxSingleClauseChars 字上限）。',
              suggestion: '在中间增加标点停顿。',
            ),
          );
        }
      }
    }

    final extPenalty = (mentalOrMetaphorCount * 10).clamp(0, 65);
    final extScore = (100 - extPenalty).clamp(35, 100);
    final unityScore = (100 - unityViolationCount * 18).clamp(40, 100);
    final speakScore = (100 - breathOverloadCount * 12).clamp(40, 100);

    final overall = totalBeats == 0 && episode.screenplayText.trim().isEmpty
        ? 100
        : ((extScore * 0.5) + (unityScore * 0.25) + (speakScore * 0.25)).round().clamp(0, 100);

    return ScreenplayQualityReport(
      overallScore: overall,
      externalizationScore: extScore,
      sceneUnityScore: unityScore,
      speakabilityScore: speakScore,
      issues: issues,
    );
  }

  /// 确定性外化单条动作描述（将抽象心理词、比喻修辞与时间概括词替换为具体视听动作）。
  static String externalizeActionTextDeterministically(String action) {
    var result = action.trim();
    if (result.isEmpty) return result;

    // 按词长降序替换，优先匹配长短语（如“仿佛一座大山压来”优先于“仿佛”）
    final sortedEntries = _deterministicExternalizationMap.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sortedEntries) {
      if (result.contains(entry.key)) {
        result = result.replaceAll(entry.key, entry.value);
      }
    }

    // 清理多余连续标点
    result = result
        .replaceAll(RegExp(r'，+'), '，')
        .replaceAll(RegExp(r'。+'), '。')
        .replaceAll('，。', '。');
    return result.trim();
  }

  /// 为超长无停顿对白自动插入自然呼吸断句标点（不删改原文字词）。
  static String formatBreathPauseDeterministically(String dialogue) {
    final trimmed = dialogue.trim();
    if (trimmed.length <= maxSingleClauseChars) return trimmed;

    // 若某一段连续汉字 > maxSingleClauseChars，在中间自然连词处（如“但是/不过/因为/而且/却/便”）插入逗号
    return trimmed.replaceAllMapped(
      RegExp(r'[\u4e00-\u9fa5]{26,}'),
      (match) {
        final seg = match.group(0)!;
        final connectors = ['但是', '不过', '因为', '所以', '而且', '况且', '既然', '即便', '哪怕'];
        for (final conn in connectors) {
          final idx = seg.indexOf(conn, 8);
          if (idx > 0 && idx < seg.length - 4) {
            return '${seg.substring(0, idx)}，${seg.substring(idx)}';
          }
        }
        final mid = seg.length ~/ 2;
        return '${seg.substring(0, mid)}，${seg.substring(mid)}';
      },
    );
  }

  /// 对整集剧本执行「一键视听外化（Show, Don't Tell）」自愈改写。
  ///
  /// - 优先尝试调用 AI 将含不可拍词的节拍动作改写为微表情与肢体动作；
  /// - 若 `useAi == false` 或 AI 不可用，自动使用确定性视听词典外化改写；
  /// - 严格保留对白原文与 `protectedContract`。
  static Future<StudioEpisode> externalizeEpisode(
    StudioEpisode episode, {
    bool useAi = true,
  }) async {
    // 1. 先执行确定性规则外化作为保底基座
    final updatedScenes = <DramaScene>[];
    final beatsNeedingAi = <String, String>{}; // beatId -> action

    for (final scene in episode.scenes) {
      final newBeats = <DramaBeat>[];
      for (final beat in scene.beats) {
        final origAction = beat.action;
        final hasMentalOrMetaphor = mentalKeywords.any(origAction.contains) ||
            metaphorKeywords.any(origAction.contains) ||
            temporalSummaryKeywords.any(origAction.contains);

        final deterministicAction = hasMentalOrMetaphor
            ? externalizeActionTextDeterministically(origAction)
            : origAction;

        final fixedDialogue = beat.voiceType == UtteranceVoiceType.dialogue
            ? formatBreathPauseDeterministically(beat.dialogue)
            : beat.dialogue;

        if (hasMentalOrMetaphor && useAi) {
          beatsNeedingAi[beat.id] = origAction;
        }

        newBeats.add(
          beat.copyWith(
            action: deterministicAction,
            dialogue: fixedDialogue,
          ),
        );
      }
      updatedScenes.add(scene.copyWith(beats: newBeats));
    }

    var resultEpisode = episode.copyWith(scenes: updatedScenes);
    if (episode.screenplayText.trim().isNotEmpty) {
      resultEpisode = resultEpisode.copyWith(
        screenplayText: externalizeActionTextDeterministically(episode.screenplayText),
      );
    }

    // 2. 若启用 AI 且存在需要深度润色外化的节拍，尝试调用大模型进一步优化视听表现力
    if (useAi && beatsNeedingAi.isNotEmpty) {
      try {
        final store = AiConfigStore.instance;
        if (store.providers.isNotEmpty) {
          final prompt = '''
你是一位资深影视分镜导演。请将以下剧本节拍中的“抽象心理描写、比喻修辞与时间跨度概括词”改写为**摄影机可直接拍摄的微表情、眼神变化、手部/身体物理动作或环境光影反应（Show, Don't Tell）**。
严禁使用“觉得、心想、意识到、忌惮、深不可测、仿佛、宛如、犹如、良久”等不可拍词汇！
只返回 JSON 对象，key 为节拍 ID，value 为改写后的纯动作文本：
${jsonEncode(beatsNeedingAi)}
''';
          final chatRes = await AiService.instance.chat(
            messages: [
              {
                'role': 'system',
                'content': '你是专业的影视剧本视听外化改写引擎，只输出纯 JSON 对象。',
              },
              {
                'role': 'user',
                'content': prompt,
              },
            ],
          );
          final cleaned = chatRes.text
              .replaceAll(RegExp(r'```json\s*'), '')
              .replaceAll(RegExp(r'```\s*'), '')
              .trim();
          final decoded = jsonDecode(cleaned);
          if (decoded is Map) {
            final aiScenes = <DramaScene>[];
            for (final scene in resultEpisode.scenes) {
              final aiBeats = <DramaBeat>[];
              for (final beat in scene.beats) {
                final aiAction = decoded[beat.id]?.toString().trim();
                if (aiAction != null &&
                    aiAction.isNotEmpty &&
                    !mentalKeywords.any(aiAction.contains) &&
                    !metaphorKeywords.any(aiAction.contains)) {
                  aiBeats.add(beat.copyWith(action: aiAction));
                } else {
                  aiBeats.add(beat);
                }
              }
              aiScenes.add(scene.copyWith(beats: aiBeats));
            }
            resultEpisode = resultEpisode.copyWith(scenes: aiScenes);
          }
        }
      } catch (_) {
        // AI 异常时静默保留上面已完成的确定性外化结果
      }
    }

    return resultEpisode;
  }
}
