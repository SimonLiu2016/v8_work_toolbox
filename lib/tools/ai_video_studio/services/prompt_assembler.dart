/// Prompt 组装器：角色 DNA + 风格锁 + 运镜词 → 最终生图 Prompt。
///
/// spec「角色资产卡与形态版本化」要求形态只存**相对**基础 Prompt 的差异词，
/// 合并后才形成完整 Prompt。这里是那个合并的唯一实现处——分镜、批量重算、
/// 形态切换三条路径都走它，才能保证同一角色在任何分镜里长出同一张脸。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/studio_models.dart';
import 'studio_preset_store.dart';

/// 目标生图引擎的 Prompt 长度上限（词）。
///
/// 750 是 spec 写死的数字。SiliconFlow Flux-schnell 的 T5 文本编码器上限
/// 约 512 token，超过部分不报错、只是被静默截断——所以超长 Prompt 不是
/// 「效果差一点」，而是尾部约束直接消失。超限时按优先级从尾部丢弃。
const int kMaxPromptWords = 750;

/// 一段可选的组装输入。全部可为 null——纯动作镜头没有角色和场景。
class PromptParts {
  /// 剧集制作类型，用于推导专属画风渲染与负向排他词。
  final StudioProductionType? productionType;

  /// 全局风格词（剧集级"风格锁"）。
  final String? styleTokens;

  /// 景别标签的英文摄影表述（如 `close-up`）。
  final String? shotSize;

  /// 情绪基调标签（原样进入 Prompt，如 `warm lighting` 由映射表给出）。
  final String? mood;

  /// 分镜功能（开场/推进/爆发/收尾）的构图提示。
  final String? shotFunction;

  /// 单角色卡引用（兼容旧代码）。
  final CharacterCard? character;

  /// 该集对该角色的形态覆盖；为 null 时用角色卡上的激活形态（兼容旧代码）。
  final CharacterVariation? variation;

  /// 出场角色卡列表（支持多角色同框）。
  final List<CharacterCard> characters;

  /// 出场角色的形态映射覆盖（key: characterId, value: variation）。
  final Map<String, CharacterVariation?> characterVariations;

  final SceneCard? scene;

  /// 运镜方案关键词（用户选择后写入分镜）。
  final String? cameraMove;

  /// 画面动作描述（中文）。生图引擎读不懂中文，但动作描述是分镜的意图来源，
  /// 这里保留它是为了在超限截断时知道哪些内容可以牺牲。
  final String? actionZh;

  /// 角色台词或对白。
  final String? dialogue;

  /// 对白说话角色。
  final String? dialogueSpeaker;

  /// 连续性台账。
  final ShotContinuity? continuity;

  /// 动态末态动势。
  final String? dynamicExitState;

  /// 视觉任务与剪辑动机。
  final String? visualTask;

  /// 五维导演决策（可为 `DirectorDecisions` 或 `Map<String, String>`）。
  final dynamic directorDecisions;

  /// 战斗攻防步骤。
  final List<Map<String, dynamic>>? combatSteps;

  /// 时代题材设定（用于提取时代负向排他违禁词）。
  final VisualEraGenre? eraGenre;

  /// 美学风格预设（用于提取风格专属负向违禁词）。
  final AestheticStyle? aestheticStyle;

  /// 剧集自定义负向风格词。
  final String? negativeStyleTokens;

  /// 摄影机视角方位（若未指定则通过 cameraMove/shotSize/actionZh 智能匹配）。
  final SceneDirection? cameraDirection;

  /// 是否显式启用多图合成自然语言指引（为 null 时按有效角色数与场景自动推断）。
  final bool? isMultiImage;

  /// 是否具备角色参考图（若为 true，提示词剥离角色的 basePromptPositive 静态容貌长文）。
  /// 若为 null，则根据 isMultiImage == true 或角色的 visual reference 状态自动推断。
  final bool? hasCharacterReferences;

  /// 发声类型（对白 / 内心独白 / 旁白）。
  final UtteranceVoiceType? voiceType;

  const PromptParts({
    this.productionType,
    this.styleTokens,
    this.eraGenre,
    this.aestheticStyle,
    this.negativeStyleTokens,
    this.shotSize,
    this.mood,
    this.shotFunction,
    this.character,
    this.variation,
    this.characters = const [],
    this.characterVariations = const {},
    this.scene,
    this.cameraMove,
    this.cameraDirection,
    this.actionZh,
    this.dialogue,
    this.dialogueSpeaker,
    this.voiceType,
    this.continuity,
    this.dynamicExitState,
    this.visualTask,
    this.directorDecisions,
    this.combatSteps,
    this.isMultiImage,
    this.hasCharacterReferences,
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
  /// 根据分镜运镜词、景别或视觉动作匹配最符合的场景七方位空间视角。
  static SceneDirection matchCameraDirection({
    SceneDirection? explicitDirection,
    String? cameraMove,
    String? shotSize,
    String? actionZh,
  }) {
    if (explicitDirection != null) return explicitDirection;
    final text = '${cameraMove ?? ''} ${shotSize ?? ''} ${actionZh ?? ''}'
        .toLowerCase();
    // 仰角/天顶/梁木/藻井/穹顶 -> top
    if (text.contains('low angle') ||
        text.contains('仰拍') ||
        text.contains('仰视') ||
        text.contains('worm eye') ||
        text.contains('仰角') ||
        text.contains('仰看') ||
        text.contains('天花') ||
        text.contains('梁木') ||
        text.contains('藻井') ||
        text.contains('穹顶')) {
      return SceneDirection.top;
    }
    // 俯角/鸟瞰/全景建立/俯瞰 -> topDown
    if (text.contains('high angle') ||
        text.contains('bird eye') ||
        text.contains('俯拍') ||
        text.contains('俯瞰') ||
        text.contains('鸟瞰') ||
        text.contains('overhead') ||
        text.contains('俯视') ||
        text.contains('全景鸟瞰') ||
        text.contains('aerial')) {
      return SceneDirection.topDown;
    }
    // 反打/过肩/背向/入口 -> back
    if (text.contains('reverse') ||
        text.contains('反打') ||
        text.contains('过肩反打') ||
        text.contains('背向') ||
        text.contains('背后') ||
        text.contains('背影') ||
        text.contains('over the shoulder')) {
      return SceneDirection.back;
    }
    // 左移/左看/左侧立面 -> left
    if (text.contains('left') ||
        text.contains('向左') ||
        text.contains('左侧') ||
        text.contains('左移') ||
        text.contains('pan left') ||
        text.contains('左视')) {
      return SceneDirection.left;
    }
    // 右移/右看/右侧立面 -> right
    if (text.contains('right') ||
        text.contains('向右') ||
        text.contains('右侧') ||
        text.contains('右移') ||
        text.contains('pan right') ||
        text.contains('右视')) {
      return SceneDirection.right;
    }
    // 贴地/地面/地坪 -> bottom
    if (text.contains('ground level') ||
        text.contains('贴地') ||
        text.contains('地面') ||
        text.contains('特写地坪') ||
        text.contains('地砖') ||
        text.contains('footstep') ||
        text.contains('低机位')) {
      return SceneDirection.bottom;
    }
    // 默认或平视正打 -> front
    return SceneDirection.front;
  }

  /// 为特定分镜解析场景的最佳匹配空间全息视角档案。
  static SceneDirectionalView? resolveSpatialViewForShot({
    required SceneCard? scene,
    SceneDirection? explicitDirection,
    String? cameraMove,
    String? shotSize,
    String? actionZh,
  }) {
    if (scene == null) return null;
    final dir = matchCameraDirection(
      explicitDirection: explicitDirection,
      cameraMove: cameraMove,
      shotSize: shotSize,
      actionZh: actionZh,
    );
    return scene.viewFor(dir);
  }

  /// 判断场景是否属于室内、地下或封闭空间（用于剔除天空云海等室外冲突词）。
  static bool isEnclosedScene(SceneCard? scene, {String? actionZh}) {
    if (scene == null) return false;
    final combined = '${scene.name} ${scene.descriptionZh} ${actionZh ?? ''}'
        .toLowerCase();
    const enclosedKeywords = [
      '内景',
      '室内',
      '牢',
      '大牢',
      '牢房',
      '水牢',
      '地牢',
      '狱',
      '暗室',
      '密室',
      '值房',
      '大殿',
      '内殿',
      '寝宫',
      '厢房',
      '书房',
      '卧房',
      '客栈内',
      '酒楼内',
      '茶馆内',
      '石室',
      '洞窟',
      '地宫',
      '地道',
      '地下',
      '监牢',
      '囚室',
      '深牢',
      '刑房',
      '殿',
      '堂',
      '窟',
      '阁',
      '廊',
      '舱',
      '屋',
      '内堂',
      '房内',
      'indoor',
      'interior',
      'cell',
      'jail',
      'prison',
      'dungeon',
      'room',
    ];
    return enclosedKeywords.any((kw) => combined.contains(kw));
  }

  /// 对封闭室内/地下场景自动净化室外互斥词，并注入室内环境微光。
  static String sanitizeStyleForScene(
    String style, {
    required bool isEnclosed,
  }) {
    if (!isEnclosed || style.trim().isEmpty) return style;

    final outdoorPattern = RegExp(
      r'云海雾气|云海|山水云雾|雾气|苍穹|天空|开阔天空|日出日落|日出|日落|晚霞|朝霞|广阔天地|宏大远景|山峰|群山|柔和天光|天光|开阔全景|'
      r'sea of clouds|open sky|wide sky|mountains|mountain peaks|sunrise|sunset',
      caseSensitive: false,
    );

    final parts = style
        .split(RegExp(r'[,，；;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !outdoorPattern.hasMatch(s))
        .toList();

    final hasIndoorLighting = parts.any(
      (p) =>
          p.contains('室内') ||
          p.contains('微光') ||
          p.contains('油灯') ||
          p.contains('局部光') ||
          p.contains('暗光'),
    );
    if (!hasIndoorLighting) {
      parts.add('室内局部微光，环境阴影与真实空间质感');
    }

    return parts.join('，');
  }

  /// 对真人实拍模式清洗负向词，剔除 live-action photo、写实照片、真人等导致真人生图被拒或冲突的关键词。
  static String sanitizeNegativeForLiveAction(String negativeText) {
    if (negativeText.trim().isEmpty) return '';
    final liveActionBans = [
      RegExp(r'\blive-action photo\b', caseSensitive: false),
      RegExp(r'\blive-action\b', caseSensitive: false),
      RegExp(r'\breal human photo\b', caseSensitive: false),
      RegExp(r'\bphotorealistic\b', caseSensitive: false),
      RegExp(r'\bphoto\b', caseSensitive: false),
      RegExp(r'\brealism\b', caseSensitive: false),
      RegExp(r'写实照片'),
      RegExp(r'照片写实'),
      RegExp(r'真人'),
    ];
    var result = negativeText;
    for (final pattern in liveActionBans) {
      result = result.replaceAll(pattern, '');
    }
    return result
        .split(RegExp(r'[,，]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  /// 解析场景物理空间描述，优先提取场景与空间视角的中文描写（descriptionZh）。
  static String resolveSceneDescription({
    required SceneCard? scene,
    SceneDirectionalView? matchedView,
  }) {
    if (scene == null) return '';

    final viewDescZh = matchedView?.descriptionZh.trim() ?? '';
    final cardDescZh = scene.descriptionZh.trim();
    final viewPromptEn = matchedView?.promptEn.trim() ?? '';
    final cardPromptEn = scene.promptEn.trim();

    final parts = <String>[];

    // 1. 中文物理空间环境描述（最高优先级）
    if (viewDescZh.isNotEmpty && cardDescZh.isNotEmpty) {
      if (viewDescZh.contains(cardDescZh)) {
        parts.add(viewDescZh);
      } else if (cardDescZh.contains(viewDescZh)) {
        parts.add(cardDescZh);
      } else {
        parts.add('$cardDescZh，视角空间：$viewDescZh');
      }
    } else if (viewDescZh.isNotEmpty) {
      parts.add(viewDescZh);
    } else if (cardDescZh.isNotEmpty) {
      parts.add(cardDescZh);
    }

    // 2. 英文 Prompt（若有且补充细节）
    final promptEn = viewPromptEn.isNotEmpty ? viewPromptEn : cardPromptEn;
    if (promptEn.isNotEmpty) {
      parts.add(promptEn);
    }

    // 3. 兜底场景名
    if (parts.isEmpty && scene.name.trim().isNotEmpty) {
      parts.add(scene.name.trim());
    }

    final combined = parts.join('，');
    final name = scene.name.trim();
    if (name.isNotEmpty && !combined.contains(name)) {
      return '$name，$combined';
    }
    return combined;
  }

  /// 解析多角色同框分镜下的画内空间站位与构图主客关系（解耦静态档案，专职描述空间关系）。
  static String resolveCharacterStaging({
    required int index,
    required int totalCount,
    required CharacterCard character,
    ShotContinuity? continuity,
    String? actionZh,
    String? delta,
  }) {
    final name = character.name.trim();
    final action = actionZh ?? '';
    final screenPos = continuity?.screenPosition ?? '';
    final worldPos = continuity?.worldPosition ?? '';

    // 检查是否存在特定环境地标（案前、桌前、门旁、牢门等）
    String landmark = '';
    for (final mark in const [
      '案前',
      '桌前',
      '牢房前',
      '牢门前',
      '门旁',
      '阶前',
      '窗前',
      '床前',
      '刑架旁',
    ]) {
      if (worldPos.contains(mark) ||
          action.contains(mark) ||
          screenPos.contains(mark)) {
        landmark = mark;
        break;
      }
    }

    String staging;
    if (index == 0) {
      if (screenPos.contains(name)) {
        staging = '$name${screenPos.contains('焦点') ? '' : '（主景核心焦点）'}';
      } else {
        final lmText = landmark.isNotEmpty ? landmark : '';
        staging = '$name居中$lmText近景（主景核心焦点）';
      }
    } else if (index == 1) {
      if (screenPos.contains(name)) {
        staging = '$name${screenPos.contains('呼应') ? '' : '（次景呼应）'}';
      } else {
        final isLeft = screenPos.contains('左') || action.contains('左侧');
        final isRight =
            screenPos.contains('右') || action.contains('右侧') || (!isLeft);
        final side = isRight ? '右侧' : '左侧';
        final isConfronting =
            action.contains('对峙') ||
            action.contains('审问') ||
            action.contains('对视') ||
            totalCount == 2;
        final rel = isConfronting ? '对峙' : '';
        staging = '$name立于$side$rel（次景呼应）';
      }
    } else {
      staging = '$name位于侧方中景（同框配角）';
    }

    final extras = <String>[];
    // 容貌与发型双重锁定：全景/远景镜头下多角色参考图特征易被稀释，必须追加原生容貌与发型特征描述
    final facial = character.facialFeaturesZh.trim().isNotEmpty
        ? character.facialFeaturesZh.trim()
        : (character.descriptionZh.trim().isNotEmpty
              ? character.descriptionZh.trim()
              : '');
    if (facial.isNotEmpty) {
      extras.add('容貌特征：$facial');
    }
    if (delta != null && delta.trim().isNotEmpty) {
      extras.add('状态：${delta.trim()}');
    }
    if (continuity != null &&
        continuity.gazeDirection.trim().isNotEmpty &&
        index == 0) {
      extras.add('视线：${continuity.gazeDirection.trim()}');
    }

    if (extras.isNotEmpty) {
      return '$staging，${extras.join('，')}';
    }
    return staging;
  }

  /// 构建符合 Agnes Image 2.5 Flash 官方规范的多图角色与保留要求自然语言指令。
  static String buildAgnesMultiImageDirective({
    required List<CharacterCard> characters,
    required SceneCard? scene,
    bool hasSceneImage = true,
  }) {
    final imageRoles = <String>[];
    var imgIndex = 1;

    for (var i = 0; i < characters.length; i++) {
      final c = characters[i];
      final roleName = i == 0
          ? '主要角色（${c.name}）'
          : (i == 1 ? '次要角色（${c.name}）' : '同框配角（${c.name}）');
      imageRoles.add('第$imgIndex张图作为$roleName');
      imgIndex++;
    }

    if (scene != null && hasSceneImage) {
      imageRoles.add('第$imgIndex张图作为背景场景参考（${scene.name}）');
      imgIndex++;
    }

    if (imageRoles.isEmpty) return '';

    final directives = <String>[];
    directives.add('将${imageRoles.join('，')}。');

    // 保留要求声明
    final preservation = <String>[];
    if (characters.isNotEmpty) {
      preservation.add('严格保留角色的面容身形与服装特征');
    }
    if (scene != null && hasSceneImage) {
      preservation.add('保留场景图中的建筑材质与环境光影风格，镜头根据当前分镜动作动态取景');
    }
    if (preservation.isNotEmpty) {
      directives.add('${preservation.join('，')}。');
    }

    return '【参考图角色与保留要求】: ${directives.join(' ')}';
  }

  /// 拼接一条完整生图 Prompt。
  ///
  /// 段顺序即优先级：越靠前越重要。超限时从尾部开始丢（spec 4.2），
  /// 严格遵循 Agnes Image 2.5 Flash 官方规范的多图合成、动作前置与高信息密度分层。
  static AssembledPrompt buildShotPrompt(PromptParts parts) {
    final positiveSegments = <String>[];
    final negativeSegments = <String>[];

    final effectiveCharacters = parts.characters.isNotEmpty
        ? parts.characters
        : (parts.character != null ? [parts.character!] : <CharacterCard>[]);
    final scene = parts.scene;

    final isEnclosed = isEnclosedScene(scene, actionZh: parts.actionZh);

    // 0. 画质基线与三层负向防崩词初始化（时代排他 + 风格专属 + 通用防崩）
    final prodType = parts.productionType;
    var qualityTokens =
        prodType != null && prodType.defaultPositiveStyle.isNotEmpty
        ? prodType.defaultPositiveStyle
        : _qualityBaseline;

    var styleTokens = parts.styleTokens?.trim() ?? '';

    // 室内/地下场景自动画风净化
    if (isEnclosed) {
      qualityTokens = sanitizeStyleForScene(qualityTokens, isEnclosed: true);
      if (styleTokens.isNotEmpty) {
        styleTokens = sanitizeStyleForScene(styleTokens, isEnclosed: true);
      }
    }

    final isLiveAction =
        prodType == StudioProductionType.drama ||
        parts.productionType?.id == 'live_action' ||
        parts.productionType?.id == 'liveAction' ||
        parts.aestheticStyle?.category == '实拍电影质感' ||
        (parts.aestheticStyle?.id.contains('realism') ?? false) ||
        (parts.aestheticStyle?.id.contains('live_action') ?? false) ||
        (parts.styleTokens?.contains('真人') ?? false) ||
        (parts.styleTokens?.contains('实拍') ?? false) ||
        (parts.styleTokens?.contains('photorealistic') ?? false);

    // 时代题材专属排他词
    if (parts.eraGenre?.negativeBans.trim().isNotEmpty == true) {
      final eraNeg = isLiveAction
          ? sanitizeNegativeForLiveAction(parts.eraGenre!.negativeBans.trim())
          : parts.eraGenre!.negativeBans.trim();
      if (eraNeg.isNotEmpty) {
        negativeSegments.add(eraNeg);
      }
    }

    // 美学风格专属排他词（支持自定义覆盖）
    final defaultProdNegative = isLiveAction
        ? StudioProductionType.drama.defaultNegativeStyle
        : (prodType != null ? prodType.defaultNegativeStyle : '');
    final rawStyleNegative =
        parts.negativeStyleTokens?.trim().isNotEmpty == true
        ? parts.negativeStyleTokens!.trim()
        : (parts.aestheticStyle?.negativeBan.trim().isNotEmpty == true
              ? parts.aestheticStyle!.negativeBan.trim()
              : defaultProdNegative);
    final styleNegative = isLiveAction
        ? sanitizeNegativeForLiveAction(rawStyleNegative)
        : rawStyleNegative;
    if (styleNegative.isNotEmpty) {
      negativeSegments.add(styleNegative);
    }

    // 通用防崩防畸形词
    negativeSegments.add(AestheticStyle.universalNegativeBrief);
    negativeSegments.add(defaultNegativePrompt);

    // 全局第四面墙防御（除明确解说外，严禁人物直视镜头屏幕破坏沉浸感）
    negativeSegments.add(
      'looking at camera, eye contact with viewer, facing viewer directly, looking at viewer, selfie pose',
    );

    // 段落 1: 多图参考自然语言指令（Agnes Image 2.5 Flash 多图合成规范）
    final isMulti =
        parts.isMultiImage ??
        (effectiveCharacters.length + (scene != null ? 1 : 0) >= 2);
    if (isMulti) {
      final multiDirective = buildAgnesMultiImageDirective(
        characters: effectiveCharacters,
        scene: scene,
      );
      if (multiDirective.isNotEmpty) {
        positiveSegments.add(multiDirective);
      }
    }

    // 段落 2: 核心视觉动作与主体焦点（高权重前置，纠偏注意力机制）
    final action = parts.actionZh?.trim() ?? '';
    final dialogue = parts.dialogue?.trim() ?? '';
    if (action.isNotEmpty || dialogue.isNotEmpty) {
      final actionParts = <String>[];
      if (action.isNotEmpty) {
        actionParts.add(action);
      }

      // 视线轴线与机位视角编译注入
      final ddCameraAngle = parts.directorDecisions is DirectorDecisions
          ? (parts.directorDecisions as DirectorDecisions).cameraAngle
          : (parts.directorDecisions is Map
                ? ((parts.directorDecisions as Map)['camera_angle']
                          as String? ??
                      '')
                : '');
      final ddGazeDirection = parts.directorDecisions is DirectorDecisions
          ? (parts.directorDecisions as DirectorDecisions).gazeDirection
          : (parts.directorDecisions is Map
                ? ((parts.directorDecisions as Map)['gaze_direction']
                          as String? ??
                      '')
                : '');
      final cameraAngle = parts.continuity?.cameraAngle.isNotEmpty == true
          ? parts.continuity!.cameraAngle
          : ddCameraAngle;
      final gazeDirection = parts.continuity?.gazeDirection.isNotEmpty == true
          ? parts.continuity!.gazeDirection
          : ddGazeDirection;
      final gazeTarget = parts.continuity?.gazeTarget ?? '';
      final elevation = parts.continuity?.elevationLevel ?? '';

      final eyelineDirective = compileGazeAndEyeline(
        cameraAngle: cameraAngle,
        gazeDirection: gazeDirection,
        gazeTarget: gazeTarget,
        elevationLevel: elevation,
      );
      if (eyelineDirective.isNotEmpty) {
        actionParts.add(eyelineDirective);
      }

      if (dialogue.isNotEmpty) {
        final isInnerVoice =
            (parts.voiceType == UtteranceVoiceType.innerVoice) ||
            dialogue.contains('内心 OS') ||
            dialogue.contains('内心OS') ||
            dialogue.contains('（OS）') ||
            dialogue.contains('(OS)') ||
            dialogue.contains('心声') ||
            dialogue.contains('内心独白');

        final extractedSpeaker = extractSpeakerName(dialogue);
        final speaker = parts.dialogueSpeaker?.trim().isNotEmpty == true
            ? parts.dialogueSpeaker!.trim()
            : extractedSpeaker;

        if (isInnerVoice) {
          final speakerPrefix = speaker.isNotEmpty ? '$speaker心声微表情：' : '心理神态：';
          final inSceneNames = effectiveCharacters.map((c) => c.name).toList();
          final sanitized = sanitizeInnerMonologue(
            dialogue: dialogue,
            speaker: speaker,
            inSceneCharacters: inSceneNames,
          );
          actionParts.add(
            '$speakerPrefix$sanitized（自然闭口与深邃眼神微表情，呈现心理活动与从容沉思，严禁张嘴开口，严禁在画面中渲染心声所指代的非在场第三人，严禁画内文字）',
          );
          negativeSegments.add('mouth open, speaking, parted lips, talking');
        } else {
          final cleanSpeech = cleanDialogueForSpeech(dialogue);
          final speakerPrefix = speaker.isNotEmpty ? '$speaker说话态势：' : '对白态势：';
          actionParts.add(
            '$speakerPrefix“$cleanSpeech”（保持戏剧性情绪面部微表情，严禁生硬张嘴或画内文字）',
          );
        }
      }
      positiveSegments.add('【核心视觉动作与焦点】: ${actionParts.join('，')}');
    }

    // 段落 3: 角色基础 Prompt + 形态差异词与站位
    String? variationName;
    if (effectiveCharacters.isNotEmpty) {
      final hasCharacterRef =
          parts.hasCharacterReferences ??
          (parts.isMultiImage == true ||
              effectiveCharacters.any((c) => c.hasVisualReference));

      if (effectiveCharacters.length == 1) {
        final character = effectiveCharacters.first;
        final base = character.basePromptPositive.trim();
        final variation =
            parts.characterVariations[character.id] ??
            parts.variation ??
            character.activeVariation;
        final delta = variation?.positiveDelta.trim() ?? '';
        if (variation != null) {
          variationName = variation.name;
        }

        if (hasCharacterRef) {
          final stateDesc = delta.isNotEmpty ? '，当前状态：$delta' : '';
          positiveSegments.add('【出场主体】: ${character.name}（画面核心主体$stateDesc）');
        } else {
          final charTokens = <String>[
            character.name,
            if (base.isNotEmpty) base,
            if (delta.isNotEmpty) delta,
            '画面核心主体',
          ];
          positiveSegments.add('【出场主体】: ${charTokens.join(', ')}');
        }

        final baseNegative = character.basePromptNegative.trim();
        if (baseNegative.isNotEmpty) negativeSegments.add(baseNegative);
        if (variation != null && variation.negativeDelta.trim().isNotEmpty) {
          negativeSegments.add(variation.negativeDelta.trim());
        }
      } else {
        // 多角色同框：明确人数与空间主客站位
        final appliedNames = <String>[];
        final charListTokens = <String>[];
        for (var i = 0; i < effectiveCharacters.length; i++) {
          final c = effectiveCharacters[i];
          final variation =
              parts.characterVariations[c.id] ?? c.activeVariation;
          final delta = variation?.positiveDelta.trim() ?? '';
          if (variation != null)
            appliedNames.add('${c.name}:${variation.name}');

          if (hasCharacterRef) {
            final staging = resolveCharacterStaging(
              index: i,
              totalCount: effectiveCharacters.length,
              character: c,
              continuity: parts.continuity,
              actionZh: parts.actionZh,
              delta: delta,
            );
            charListTokens.add(staging);
          } else {
            final positionRole = i == 0
                ? 'in foreground, 主景核心'
                : (i == 1 ? 'in background, 对峙/呼应背景' : 'next to them, 同框配角');
            final base = c.basePromptPositive.trim();
            final charTokens = <String>[
              c.name,
              if (base.isNotEmpty) base,
              if (delta.isNotEmpty) delta,
              positionRole,
            ];
            charListTokens.add(charTokens.join(', '));
          }

          final baseNegative = c.basePromptNegative.trim();
          if (baseNegative.isNotEmpty) negativeSegments.add(baseNegative);
          if (variation != null && variation.negativeDelta.trim().isNotEmpty) {
            negativeSegments.add(variation.negativeDelta.trim());
          }
        }
        if (charListTokens.isNotEmpty) {
          if (hasCharacterRef) {
            positiveSegments.add(
              '【同框人物与站位】: ${effectiveCharacters.length} people in scene，${charListTokens.join('，')}',
            );
          } else {
            positiveSegments.add(
              '${effectiveCharacters.length} people in scene',
            );
            positiveSegments.add('【同框人物与站位】: ${charListTokens.join('；')}');
          }
        }
        if (appliedNames.isNotEmpty) {
          variationName = appliedNames.join('; ');
        }
      }
    } else {
      // 空镜头 / 无角色镜头：负向显式抑制人脸与人物，避免生图模型脑补塞入人脸
      negativeSegments.add(
        'person, human, face, character, people, man, woman, portrait',
      );
    }

    // 段落 4: 场景物理空间与环境细节（支持机位自适应匹配七方位空间档案）
    final matchedView = resolveSpatialViewForShot(
      scene: scene,
      explicitDirection: parts.cameraDirection,
      cameraMove: parts.cameraMove,
      shotSize: parts.shotSize,
      actionZh: parts.actionZh,
    );
    final sceneDetails = resolveSceneDescription(
      scene: scene,
      matchedView: matchedView,
    );
    if (sceneDetails.isNotEmpty) {
      positiveSegments.add('【场景物理环境】: $sceneDetails');
    }

    // 段落 5: 画质与画风基线 + 景别/构图/情绪
    positiveSegments.addAll([
      qualityTokens,
      if (styleTokens.isNotEmpty && styleTokens != qualityTokens) styleTokens,
    ]);

    final composition = [
      if (parts.shotSize?.trim().isNotEmpty == true) parts.shotSize!.trim(),
      if (parts.shotFunction?.trim().isNotEmpty == true)
        parts.shotFunction!.trim(),
      if (parts.mood?.trim().isNotEmpty == true) parts.mood!.trim(),
    ];
    positiveSegments.addAll(composition);

    // 段落 6: 运镜词（最后，最可牺牲）
    if (parts.cameraMove?.trim().isNotEmpty == true) {
      positiveSegments.add('camera: ${parts.cameraMove!.trim()}');
    }

    final positive = _joinWithinLimit(positiveSegments, kMaxPromptWords);
    final deduplicatedNegative = AestheticStyle.deduplicateTokens(
      negativeSegments.join(', '),
    );
    final finalNegative = isLiveAction
        ? sanitizeNegativeForLiveAction(deduplicatedNegative)
        : deduplicatedNegative;
    final negativeTokensList = finalNegative
        .split(RegExp(r'[,，；;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final negative = _joinWithinLimit(negativeTokensList, kMaxNegativeWords);

    return AssembledPrompt(
      positive: positive.text,
      negative: negative.text,
      truncated: positive.truncated,
      droppedSegments: positive.dropped,
      appliedVariationName: variationName,
    );
  }

  /// 组装三层负向防崩词：[eraGenre / eraBans] (时代排他违禁词) + [aestheticStyle / styleBans / negativeStyleTokens] (美学风格专属违禁词) + [universalNegative] (通用防崩词)。
  static String assembleNegativePrompt({
    VisualEraGenre? eraGenre,
    String? eraBans,
    AestheticStyle? aestheticStyle,
    String? styleBans,
    String? negativeStyleTokens,
    String? extraNegative,
    List<String> additionalBans = const [],
    String universalNegative = AestheticStyle.universalNegativeBrief,
    bool includeUniversal = true,
    bool isLiveAction = false,
  }) {
    final assembled = AestheticStyle.assembleNegative(
      eraBans: eraBans ?? eraGenre?.negativeBans,
      styleBans:
          styleBans ?? aestheticStyle?.negativeBan ?? negativeStyleTokens,
      extraNegative: extraNegative,
      additionalBans: additionalBans,
      universalBans: universalNegative,
      includeUniversal: includeUniversal,
    );
    final isLive =
        isLiveAction ||
        aestheticStyle?.category == '实拍电影质感' ||
        (aestheticStyle?.id.contains('realism') ?? false) ||
        (aestheticStyle?.id.contains('live_action') ?? false);
    return isLive ? sanitizeNegativeForLiveAction(assembled) : assembled;
  }

  /// 组装面向视频生成模型（如 Agnes Video / Kling / MiniMax）的声画一体化提示词。
  ///
  /// 彻底解决单镜头角色对白静音、多角色漏人、微动作丢失等问题：
  /// 1. 结构化角色发声口令（对白文本、语气提示、口型同步）；
  /// 2. 多角色同框构图与主次站位；
  /// 3. 微动作因果与具象肢体链；
  /// 纯净台词发声净化器：剥离剧本中一切元数据标签，保证 TTS 发音与视频口型仅拿到真实口播台词。
  ///
  /// 支持剥离的元数据：
  /// 1. 预估时长注记：如 `（预估2.5秒）`、`（预估3秒）`、`(预估 4.0s)`、`（预估 2 秒）`、`（2.5秒）`
  /// 2. 角色名 + 内心独白前缀：如 `姜七夜（内心 OS）：`、`（内心 OS）：`、`姜七夜（OS）：`、`心声：`
  /// 3. 普通角色名台词前缀：如 `老王：“`、`老王：`、`姜七夜:`
  /// 4. 首尾包裹的成对或不成对双引号、单引号与多余空白字符。
  static String cleanDialogueForSpeech(String dialogue) {
    if (dialogue.trim().isEmpty) return '';

    var text = dialogue.trim();

    // 1. 剥离所有形式的预估时长注记
    text = text.replaceAll(
      RegExp(
        r'[（\(]\s*预估\s*[\d\.]+\s*(?:秒|s|sec|seconds)?[）\)]|[（\(]\s*[\d\.]+\s*(?:秒|s|sec)[）\)]',
        caseSensitive: false,
      ),
      '',
    );

    // 2. 剥离角色名及内心独白标记，如：`姜七夜（内心 OS）：`、`（内心 OS）：`、`姜七夜(OS):`
    text = text.replaceFirst(
      RegExp(
        r'^(?:[^：:\(（\n\r]{1,12}\s*)?[（\(]\s*(?:内心\s*OS|OS|心声|内心独白)\s*[）\)][：:]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    // 3. 剥离普通角色名台词前缀，如 `老王：“`、`老王：`、`姜七夜:`
    text = text.replaceFirst(RegExp(r'^[^：:\n\r"“]{1,10}[：:]\s*'), '');

    // 4. 剥离首尾残留的引号、括号与多余空白
    text = text.trim();
    while (text.isNotEmpty &&
        (text.startsWith('“') ||
            text.startsWith('"') ||
            text.startsWith('‘') ||
            text.startsWith("'"))) {
      text = text.substring(1).trim();
    }
    while (text.isNotEmpty &&
        (text.endsWith('”') ||
            text.endsWith('"') ||
            text.endsWith('’') ||
            text.endsWith("'"))) {
      text = text.substring(0, text.length - 1).trim();
    }

    return text.trim();
  }

  /// 从台词头部结构精准提取真实说话人姓名。
  ///
  /// 例如：
  /// - `姜七夜（内心 OS）：今天真晦气...` -> `姜七夜`
  /// - `老王：“姜七夜！你还有没有点规矩？...”` -> `老王`
  /// - `余小白：“姜七少...”` -> `余小白`
  /// 若无法从台词提取，则返回 [defaultSpeaker]。
  static String extractSpeakerName(
    String dialogue, {
    String defaultSpeaker = '',
  }) {
    if (dialogue.trim().isEmpty) return defaultSpeaker;

    final trimmed = dialogue.trim();

    // 1. 匹配格式：`姓名（内心 OS）：` 或 `姓名(OS):`
    final innerMatch = RegExp(
      r'^([^：:\(（\n\r]{1,12})\s*[（\(]\s*(?:内心\s*OS|OS|心声|内心独白)\s*[）\)][：:]',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (innerMatch != null) {
      final name = innerMatch.group(1)?.trim() ?? '';
      if (name.isNotEmpty) return name;
    }

    // 2. 匹配普通对白前缀：`姓名：“` 或 `姓名:`
    final normalMatch = RegExp(r'^([^：:\n\r"“]{1,10})[：:]').firstMatch(trimmed);
    if (normalMatch != null) {
      final name = normalMatch.group(1)?.trim() ?? '';
      if (name.isNotEmpty && !name.contains('（') && !name.contains('(')) {
        return name;
      }
    }

    return defaultSpeaker;
  }

  /// 4. 5D 导演决策（光影、景别、运镜、时空节拍）；
  /// 5. 跨镜头连续性台账与末态物理动势衔接。
  static String buildVideoGenPrompt({
    required StudioShot shot,
    required StudioEpisode episode,
    List<CharacterCard> characters = const [],
    SceneCard? scene,
  }) {
    // 0. 若分镜已由 AI 重写或用户定制专属视频提示词，直接优先使用
    if (shot.videoPrompt.trim().isNotEmpty) {
      return shot.videoPrompt.trim();
    }

    final sections = <String>[];

    // 对白段先算但不入列：因果链必须在提示词执行顺序上先于台词，否则视频模型
    // 会先把台词演完再演动作（spec: shot-causality-ordering 反应性台词时序）。
    // 用户看到的「老王先骂、姜七夜再走」就是台词段落在最前导致的。
    String? dialogueSection;
    var isInnerVoice = false;
    final dialogue = shot.dialogue.trim();
    if (dialogue.isNotEmpty) {
      final cleanSpeech = cleanDialogueForSpeech(dialogue);
      final explicitSpeaker = extractSpeakerName(dialogue);

      // 确定对白说话者：优先信任台词前缀提取结果
      String speaker = explicitSpeaker;
      if (speaker.isEmpty && characters.isNotEmpty) {
        // 尝试从 actionZh 中匹配角色名
        for (final c in characters) {
          if (shot.actionZh.contains(c.name)) {
            speaker = c.name;
            break;
          }
        }
        if (speaker.isEmpty) speaker = characters.first.name;
      }

      isInnerVoice =
          shot.isInnerVoice ||
          shot.voiceType == UtteranceVoiceType.innerVoice ||
          dialogue.contains('内心 OS') ||
          dialogue.contains('内心OS') ||
          dialogue.contains('（OS）') ||
          dialogue.contains('(OS)') ||
          dialogue.contains('心声') ||
          dialogue.contains('内心独白');

      // 收集在场所有角色名称，用于点名全员守卫
      final inSceneNames = <String>[];
      if (speaker.isNotEmpty) inSceneNames.add(speaker);
      for (final c in characters) {
        if (!inSceneNames.contains(c.name)) {
          inSceneNames.add(c.name);
        }
      }
      final allNamesDesc = inSceneNames.isNotEmpty
          ? inSceneNames.join('、')
          : '画面中所有在场人物';

      if (isInnerVoice) {
        // 彻底消除中括号机器标记，显式正向点名全员闭口，防止配角抢台词开口
        final speakerLabel = speaker.isNotEmpty ? '$speaker画外心声念白' : '画外心声念白';
        dialogueSection =
            '正向画音约束：$speakerLabel（“$cleanSpeech”）。全员闭口守卫：画面中$allNamesDesc等全员嘴唇全程严密闭合，面部无口型变化，绝对不说话、不张嘴、不念台词，无画内文字与字幕，全员保持沉思内敛神态与微表情。';
      } else {
        final speakerLabel = speaker.isNotEmpty ? '$speaker说话' : '角色说话';
        final otherChars = inSceneNames.where((n) => n != speaker).toList();
        final listenerGuard = otherChars.isNotEmpty
            ? '；同框倾听者（${otherChars.join('、')}）保持自然闭口倾听，不说话不张嘴'
            : '';
        final moodLabel = ShotMood.fromId(shot.mood).label;
        final toneHint = moodLabel.isNotEmpty ? '，语气：$moodLabel' : '';
        dialogueSection =
            '正向对白约束：$speakerLabel（“$cleanSpeech”）$toneHint。说话者嘴唇随台词自然开合，口型发音对齐，声画一体$listenerGuard。';
      }
    } else {
      dialogueSection = '正向动作约束：无对白镜头，纯环境音与动作自然音效。';
    }

    // 1. 出场人物与同框构图
    if (characters.isNotEmpty) {
      if (characters.length == 1) {
        final c = characters.first;
        final desc = c.descriptionZh.isNotEmpty ? c.descriptionZh : c.name;
        sections.add('【出场人物】: ${c.name}（$desc）');
      } else {
        final charParts = <String>[];
        for (var i = 0; i < characters.length; i++) {
          final c = characters[i];
          final role = i == 0 ? '主体近景' : (i == 1 ? '背景/对峙中景' : '同框配角');
          final desc = c.descriptionZh.isNotEmpty ? '，${c.descriptionZh}' : '';
          charParts.add('${c.name}（处于画面$role$desc）');
        }
        sections.add('【同框人物与构图】: ${charParts.join('；')}');
      }
    }

    // 2. 画面微动作与行为具象化（因果链起点，先于台词入列）
    final action = shot.actionZh.trim();
    if (action.isNotEmpty) {
      sections.add('【画面微动作】: $action');
    }

    // 3. 攻防因果与动作节拍（若有）
    if (shot.combatSteps.isNotEmpty) {
      final combatStr = shot.combatSteps
          .map((s) => '${s.actorName}发起${s.attack}，受到${s.impact}')
          .where((s) => s.trim().isNotEmpty)
          .join('；');
      if (combatStr.isNotEmpty) {
        sections.add('【动作攻防拆解】: $combatStr');
      }
    }

    // 4. 角色对白与声画同步口令（动作因果链之后才入列）
    sections.add(dialogueSection);

    // 5. 因果时间轴（spec: shot-causality-ordering）。
    //
    // 段落顺序只解决「提示词里谁在前」，不解决模型把同一镜内两个主体的动作
    // 演成同时发生。秒数标注是唯一能约束同镜相位的手段，所以这里独立成段。
    //
    // 这一段是**派生段**：时间戳只写进这里，绝不回写 `actionZh`——后者是
    // C02 对白保真、C05 地标衔接等规则的匹配源，污染它会让那些规则失效。
    final timeline = buildShotCausalityTimeline(
      shot: shot,
      isInnerVoice: isInnerVoice,
      hasDialogue: dialogue.isNotEmpty,
    );
    if (timeline.isNotEmpty) {
      sections.add('【因果时间轴】$timeline');
    }

    // 6. 5D 导演决策与运镜轨迹（冲突消解：推镜 vs 定机位、温馨 vs 阴冷）
    final dirDecisions = shot.directorDecisions;

    // 场景空间暗色与压抑判断
    final sceneDescCombined =
        '${scene?.name ?? ''} ${scene?.descriptionZh ?? ''}';
    final isDungeonOrOppressive =
        sceneDescCombined.contains('地牢') ||
        sceneDescCombined.contains('牢房') ||
        sceneDescCombined.contains('大牢') ||
        sceneDescCombined.contains('阴冷') ||
        sceneDescCombined.contains('暗室') ||
        sceneDescCombined.contains('刑具');

    // 消解氛围情绪冲突：如果是地牢压抑环境且情绪标记为温馨，自动纠正为压抑/冷峻
    var effectiveMood = shot.mood;
    if (isDungeonOrOppressive && effectiveMood == 'warm') {
      effectiveMood = 'depressing';
    }
    final moodLabel = ShotMood.fromId(effectiveMood).label;

    final cameraDetails = <String>[
      '景别：${shot.shotSize.label}',
      '氛围情绪：$moodLabel',
    ];

    final cameraMove = shot.cameraMove.trim();
    final hasDynamicMove =
        cameraMove.isNotEmpty &&
        !cameraMove.toLowerCase().contains('static') &&
        !cameraMove.contains('定机位');

    if (cameraMove.isNotEmpty) {
      cameraDetails.add('运镜调度：$cameraMove');
    }

    if (dirDecisions.isNotEmpty) {
      var lighting = dirDecisions.lightingStaging.trim();
      // 消解室内地牢火光 vs 室外黄昏残阳冲突
      if (isDungeonOrOppressive &&
          (lighting.contains('残阳') ||
              lighting.contains('黄昏') ||
              lighting.contains('夕阳'))) {
        lighting = lighting
            .replaceAll(RegExp(r'黄昏[，,\s]*残阳如血[，,\s]*'), '')
            .replaceAll(RegExp(r'巡城司朱门半开[，,\s]*衙役往来[，,\s]*'), '')
            .trim();
        if (lighting.isEmpty) {
          lighting = '微弱火把与摇曳火光，砖石潮湿反光与深沉阴影';
        }
      }
      if (lighting.isNotEmpty) {
        cameraDetails.add('光影布置：$lighting');
      }

      var staging = dirDecisions.cameraStaging.trim();
      // 消解推镜 vs 定机位冲突：若运镜已明确动态推进/移动，清洗定机位描述
      if (hasDynamicMove) {
        staging = staging
            .replaceAll('平视定机位', '平视视角')
            .replaceAll('定机位', '')
            .replaceAll('固定机位', '')
            .replaceAll('镜头不动', '')
            .replaceAll('机位不动', '')
            .replaceAll(RegExp(r'^[，,\s]+|[，,\s]+$'), '')
            .trim();
      }
      if (staging.isNotEmpty) {
        cameraDetails.add('摄影调度：$staging');
      }

      if (dirDecisions.physicalMomentum.trim().isNotEmpty) {
        cameraDetails.add('物理动势：${dirDecisions.physicalMomentum.trim()}');
      }
    }
    sections.add('【摄影运镜与机位调度】: ${cameraDetails.join('，')}');

    // 6. 场景空间与环境
    if (scene != null) {
      final sceneDesc = scene.descriptionZh.trim().isNotEmpty
          ? scene.descriptionZh.trim()
          : scene.name;
      sections.add('【场景与环境】: ${scene.name}（$sceneDesc）');
    }

    // 7. 连续性台账与末态动势（剔除单镜头无效的 180° 轴线指令，消解地标冲突）
    final continuity = shot.continuity;
    if (!continuity.isEmpty) {
      final contTokens = <String>[];
      var contLighting = continuity.lightingState.trim();
      if (isDungeonOrOppressive &&
          (contLighting.contains('黄昏') || contLighting.contains('残阳'))) {
        contLighting = '昏暗地牢火光';
      }
      if (contLighting.isNotEmpty) {
        contTokens.add('光照：$contLighting');
      }

      var worldPos = continuity.worldPosition.trim();
      // 消解场景二选一冲突：若场景已为大牢/地牢，但世界坐标误带衙门口，自动清洗
      if (isDungeonOrOppressive &&
          (worldPos.contains('衙门口') || worldPos.contains('朱门'))) {
        worldPos = '大牢木栅牢房内侧';
      }
      if (worldPos.isNotEmpty) {
        contTokens.add('空间地标：$worldPos');
      }

      if (continuity.screenPosition.isNotEmpty) {
        contTokens.add('画内方位：${continuity.screenPosition}');
      }
      if (continuity.gazeDirection.isNotEmpty) {
        contTokens.add('视线朝向：${continuity.gazeDirection}');
      }

      // 注意：单镜头不注入“动作轴线：保持在180度轴线右侧，与前镜保持同轴关系”，避免模型注意力浪费与无效指令负担

      if (continuity.dynamicExitState.isNotEmpty &&
          continuity.dynamicExitState.velocityVector.isNotEmpty) {
        contTokens.add('末态动势惯性：${continuity.dynamicExitState.velocityVector}');
      }
      if (contTokens.isNotEmpty) {
        sections.add('【连贯性约束】: ${contTokens.join('，')}');
      }
    }

    return sections.join('\n');
  }

  /// 编译单镜的【因果时间轴】文本（spec: shot-causality-ordering）。
  ///
  /// 秒数分配策略（design 决策 3）：
  /// - 有 `temporalEvolution` 且能解析出显式秒数分界 → 按解析结果切分；
  /// - 有 `temporalEvolution` 但解析不出 → 按默认次序分配，原文保留作相位说明；
  /// - 都没有 → 台词时段贴在本镜末尾，动作时段占前部。
  ///
  /// **台词默认贴末尾**是与模型倾向的对冲：实践中模型倾向先把台词演完再演
  /// 动作（用户反馈的「老王先骂、姜七夜再走」即此），把台词钉在时间轴尾部是
  /// 最简的反向约束。`temporalEvolution` 存在时以它为准。
  ///
  /// 内心独白返回空串——它与画面并行，不参与动作因果排序（spec 要求）。
  static String buildShotCausalityTimeline({
    required StudioShot shot,
    required bool isInnerVoice,
    required bool hasDialogue,
  }) {
    if (isInnerVoice) return '';

    final total = shot.durationSec > 0 ? shot.durationSec : 0.0;
    final action = shot.actionZh.trim();
    if (action.isEmpty && !hasDialogue) return '';
    // 纯动作镜头不出时间轴：没有台词就没有「谁先谁后」的问题，单主体动作的
    // 先后由动作描述自身承载。多这一段只是给提示词添噪。
    if (!hasDialogue) return '';

    final temporal = shot.directorDecisions.temporalEvolution.trim();
    final phaseSplit = CausalityTimelineCompiler.parsePhaseSplitSec(temporal);

    // 台词秒数：台词标注了「预估N秒」时用标注值，否则按总时长 40% 兜底。
    // 兜底只用于给模型一个相位参照，真实音轨仍由 audioDurationMs 驱动，
    // 两者不一致时以音轨为准。
    final dialogueSec = hasDialogue ? shot.dialogueEstimatedSec : 0.0;
    final hasExplicitDialogueSec = hasDialogue && dialogueSec > 0;
    final fallbackDialogueSec = total * 0.4;

    String actionPhase;
    String dialoguePhase;

    if (phaseSplit != null && phaseSplit > 0 && phaseSplit < total) {
      // 有显式相位分界：动作占前段，台词占后段。
      actionPhase = '0.0s-${phaseSplit.toStringAsFixed(1)}s';
      dialoguePhase =
          '${phaseSplit.toStringAsFixed(1)}s-${total.toStringAsFixed(1)}s';
    } else if (hasDialogue) {
      final span = hasExplicitDialogueSec && dialogueSec < total
          ? dialogueSec
          : fallbackDialogueSec;
      final actionEnd = (total - span).clamp(0.0, total);
      actionPhase = '0.0s-${actionEnd.toStringAsFixed(1)}s';
      dialoguePhase =
          '${actionEnd.toStringAsFixed(1)}s-${total.toStringAsFixed(1)}s';
    } else {
      actionPhase = '0.0s-${total.toStringAsFixed(1)}s';
      dialoguePhase = '';
    }

    final parts = <String>[];
    if (action.isNotEmpty) {
      parts.add('$actionPhase $action');
    }
    if (hasDialogue && dialoguePhase.isNotEmpty) {
      parts.add('$dialoguePhase 台词（${_dialogueSecLabel(shot)}）');
    }
    if (parts.isEmpty) return '';

    final timeline = parts.join(' → ');

    // temporalEvolution 解析不出秒数时不丢弃原文——它是作者对相位的唯一描述，
    // 对模型仍有约束力。
    if (temporal.isNotEmpty) {
      return '$timeline。相位说明：$temporal';
    }
    return timeline;
  }

  /// 台词时长的可读标注：台词带「预估N秒」标注时为确切值，否则为按字数
  /// 推算的近似值。
  static String _dialogueSecLabel(StudioShot shot) {
    final sec = shot.dialogueEstimatedSec;
    if (sec <= 0) return '时长未标注';
    if (shot.dialogue.contains('预估')) {
      return '${sec.toStringAsFixed(1)}s';
    }
    return '约${sec.toStringAsFixed(1)}s';
  }

  /// 规则级冲突清洗与重写助手，对既有提示词中的场景二选一、动静机位冲突与机器中括号进行确定性清洗。
  static String cleanAndResolveConflicts(
    String rawPrompt, {
    SceneCard? scene,
    List<CharacterCard> characters = const [],
  }) {
    if (rawPrompt.trim().isEmpty) return '';

    var result = rawPrompt;

    // 1. 清洗括号机器标记
    result = result.replaceAll(RegExp(r'\[角色内心独白/心声\][：:\s]*'), '画外心声念白：');
    result = result.replaceAll(RegExp(r'\[角色对白发声\][：:\s]*'), '角色对白：');
    result = result.replaceAll(RegExp(r'\[无对白镜头\][：:\s]*'), '无对白镜头：');

    // 2. 清洗 180 度轴线单镜头无效标记
    result = result.replaceAll(
      RegExp(r'【?动作轴线】?[：:][^\n\r]*(?:180度|同轴)[^\n\r]*[\r\n]?'),
      '',
    );
    result = result.replaceAll(
      RegExp(r'[^，,\n\r]*(?:180度法则|180度轴线)[^，,\n\r]*[，,\s]*'),
      '',
    );

    // 3. 运镜冲突：若包含 push-in / slow_push_in / 推进，清洗定机位
    if (result.contains('push') ||
        result.contains('推镜') ||
        result.contains('推进')) {
      result = result.replaceAll('平视定机位', '平视机位');
      result = result.replaceAll('定机位', '');
      result = result.replaceAll('固定机位', '');
      result = result.replaceAll('镜头完全不动', '');
    }

    // 4. 场景二选一冲突清洗
    if (result.contains('大牢') || result.contains('地牢')) {
      result = result.replaceAll(
        RegExp(r'【?空间地标】?[：:][^\n\r]*衙门口[^\n\r]*'),
        '空间地标：巡城司大牢木栅内',
      );
      result = result.replaceAll(RegExp(r'[^，,\n\r]*衙门口[^，,\n\r]*[，,\s]*'), '');
      result = result.replaceAll('氛围情绪：温馨', '氛围情绪：压抑冷峻');
    }

    // 5. 光源冲突消解（黄昏残阳 vs 地牢火把）
    if ((result.contains('大牢') || result.contains('地牢')) &&
        result.contains('火把')) {
      result = result.replaceAll(
        RegExp(r'[^，,\n\r]*(?:黄昏|残阳如血)[^，,\n\r]*[，,\s]*'),
        '',
      );
    }

    // 清理可能产生的双逗号与空白行
    result = result.replaceAll(RegExp(r'[，,]\s*[，,]'), '，');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  /// 静态纯文本重写辅助：依据分镜构造清洗后的自然视频提示词。
  static String buildSanitizedVideoPrompt({
    required StudioShot shot,
    required StudioEpisode episode,
    List<CharacterCard> characters = const [],
    SceneCard? scene,
  }) {
    final raw = buildVideoGenPrompt(
      shot: shot,
      episode: episode,
      characters: characters,
      scene: scene,
    );
    return cleanAndResolveConflicts(raw, scene: scene, characters: characters);
  }

  /// 负向 Prompt 单独的上限——它通常短得多，且截断它的代价是画面上出现瑕疵。
  static const int kMaxNegativeWords = 200;

  /// 画质基线词：采用微质感与电影级漫反射，替代易引发 AI 塑料感/蜡像感的通用词。
  static const String _qualityBaseline =
      'authentic film texture, natural skin tones, subtle micro details, cinematic soft lighting, raw photo, 8k resolution';

  /// 默认负向词：用户没填负向 Prompt 时也要有的兜底瑕疵表（强化防塑料/假滑 AI 脸）。
  static const String defaultNegativePrompt =
      'plastic skin, smooth doll, airbrushed, wax figure, mannequin, '
      '3d render doll, fake glossy skin, uncanny valley, over-saturated, '
      'cartoonish, blurry, low quality, worst quality, deformed, duplicate, '
      'extra limbs, bad anatomy, disfigured, watermark, signature, text, '
      'subtitles, on-screen text, speech bubble, gibberish characters, '
      'deformed mouth, mouth open speaking, username, logo, cropped, out of frame';

  /// 将差异词中的常用中文关键词规范化翻译为英文提示词短语。
  static String normalizeDeltaWords(String delta, {bool isNegative = false}) {
    if (delta.trim().isEmpty) return '';
    var text = delta.trim();
    const mappings = <String, String>{
      '白色着装': 'wearing pristine white attire, flowing white robes, silver belt',
      '白色长袍': 'wearing long flowing white robes',
      '白长袍': 'wearing long flowing white robes',
      '白袍': 'wearing pristine white robes',
      '白衣': 'wearing white robes, flowing white attire',
      '白色': 'white',
      '黑色着装': 'wearing black attire, dark robes',
      '黑袍': 'wearing black hooded cloak',
      '黑衣': 'wearing black clothes, dark attire',
      '玄色': 'dark black',
      '玄衣': 'wearing dark black ancient robes',
      '青衫': 'wearing cyan scholar robes',
      '青衣': 'wearing cyan robes',
      '蓝衣': 'wearing blue robes',
      '红衣': 'wearing crimson red robes',
      '紫袍': 'wearing purple robes',
      '素衣': 'wearing simple plain undyed robes',
      '战铠': 'wearing battle armor plates, steel armor',
      '战甲': 'warrior armor, protective breastplate',
      '轻甲': 'wearing light combat armor',
      '重甲': 'wearing heavy plated armor',
      '铠甲': 'battle armor plates, steel armor',
      '劲装': 'wearing tight-fitting martial arts outfit',
      '道袍': 'wearing daoist robes',
      '夜行衣': 'wearing black stealth night suit',
      '少年': 'youthful teenager, young boy, clean-shaven',
      '青年': 'young man, youthful appearance',
      '幼年': 'young child, cute boy',
      '正太': 'cute young boy, youthful',
      '书童': 'young page boy, clean-shaven',
      '小弟': 'younger companion, youthful boy',
      '白胖': 'fair-skinned and chubby build, plump body',
      '富态': 'plump wealthy figure, prosperous build',
      '微胖': 'slightly chubby build, soft plump frame',
      '战损': 'battle damaged, torn clothes, bruised, light wounds',
      '重伤': 'heavily injured, bleeding wounds, damaged clothes',
      '受伤': 'injured, light bruises, torn attire',
      '白发': 'silver white hair',
      '银发': 'silver hair',
      '黑发': 'jet black hair',
      '红发': 'crimson red hair',
      '金发': 'blonde hair',
      '魔化': 'demonic state, glowing red eyes, dark shadow aura',
      '黑化': 'corrupted dark form, sinister aura',
      '面具': 'wearing mask, mysterious mask',
      '斗笠': 'wearing bamboo traveler hat',
      '去胡子': 'clean-shaven, hairless face, smooth chin',
      '没有胡子': 'clean-shaven, hairless face, smooth chin',
      '无须': 'clean-shaven, hairless face, smooth chin',
      '去除胡须': 'clean-shaven, hairless face, smooth chin',
    };

    const negativeMappings = <String, String>{
      '长胡子': 'beard, mustache, facial hair, goatee, stubble',
      '胡子': 'beard, mustache, facial hair, goatee, stubble',
      '胡须': 'beard, mustache, facial hair, goatee, stubble',
      '大胡子': 'thick beard, full mustache, heavy stubble',
      '胡茬': 'stubble, five o clock shadow, facial hair',
      '老头': 'elderly, old man, aged wrinkles, senile',
      '老人': 'elderly, old person, wrinkles',
      '中年': 'middle-aged man, mature adult face, wrinkles',
      '皱纹': 'wrinkles, aged face, mature lines',
    };

    final map = isNegative ? negativeMappings : mappings;
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (text.contains(key)) {
        text = text.replaceAll(key, map[key]!);
      }
    }
    if (isNegative) {
      final sortedPosKeys = mappings.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final key in sortedPosKeys) {
        if (text.contains(key)) {
          text = text.replaceAll(key, mappings[key]!);
        }
      }
    } else {
      final sortedNegKeys = negativeMappings.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final key in sortedNegKeys) {
        if (text.contains(key)) {
          text = text.replaceAll(key, 'no ${negativeMappings[key]}');
        }
      }
    }

    return text;
  }

  /// 合并基础 Prompt 与形态差异词（spec 4.2）。
  ///
  /// 支持纯中文差异词规范化映射，避免纯中文词在英文生图模型中权重失真。
  static String mergeVariation({
    required String basePrompt,
    required String positiveDelta,
  }) {
    final base = basePrompt.trim();
    final normalizedDelta = normalizeDeltaWords(
      positiveDelta,
      isNegative: false,
    ).trim();
    if (normalizedDelta.isEmpty) return base;
    if (base.isEmpty) return normalizedDelta;
    final existing = _promptWordsOf(base).toSet();
    final fresh = _promptWordsOf(
      normalizedDelta,
    ).where((w) => !existing.contains(w));
    if (fresh.isEmpty) return base;
    return '$base, ${fresh.join(', ')}';
  }

  /// 合并基础负向 Prompt 与形态负向差异词。
  static String mergeNegativeVariation({
    required String baseNegative,
    required String negativeDelta,
  }) {
    final base = baseNegative.trim();
    final normalizedDelta = normalizeDeltaWords(
      negativeDelta,
      isNegative: true,
    ).trim();
    if (normalizedDelta.isEmpty) return base;
    if (base.isEmpty) return normalizedDelta;
    final existing = _promptWordsOf(base).toSet();
    final fresh = _promptWordsOf(
      normalizedDelta,
    ).where((w) => !existing.contains(w));
    if (fresh.isEmpty) return base;
    return '$base, ${fresh.join(', ')}';
  }

  /// 按字数统计（空格分词，逗号/句号也算分隔）。
  static int wordCount(String prompt) {
    if (prompt.trim().isEmpty) return 0;
    return _promptWordsOf(prompt).length;
  }

  /// 组装一条片段视频提示词（spec: 片段提示词组装）。
  ///
  /// **确定性组装，不让 AI 自由发挥**（design 决策 5）：AI 只负责划片段边界
  /// 与给目标时长，最终提示词由分镜字段 + 角色卡 + 场景卡 + 台账在这里拼出。
  /// 这样「改了分镜字段但片段提示词没变」这类不同步不可能发生——纯函数每次
  /// 重算，UI 不需要判断何时该重新生成。
  ///
  static final _emptyScenePattern = RegExp(
    r'\b(empty (room|interior|exterior|entrance|street|town entrance|hall|building|space)|architectural (interior|exterior)|no humans|nobody|unoccupied|vacant|deserted|no people)\b',
    caseSensitive: false,
  );

  /// 过滤场景提示词中的空镜排他词（如 empty room, no humans 等）。
  ///
  /// 当片段中有角色出场 ([hasCharacters] 为 true) 时，剔除与人物同框互斥的空场景声明。
  static String filterEmptySceneTokens(
    String scenePrompt, {
    bool hasCharacters = false,
  }) {
    if (!hasCharacters || scenePrompt.trim().isEmpty) {
      return scenePrompt;
    }
    final phrases = scenePrompt
        .split(RegExp(r'[,，;；\n]+'))
        .map((s) => s.trim())
        .where((s) {
          if (s.isEmpty) return false;
          final cleaned = s.replaceAll(_emptyScenePattern, '').trim();
          return cleaned.isNotEmpty &&
              !cleaned.toLowerCase().startsWith('with no');
        })
        .map((s) {
          return s
              .replaceAll(_emptyScenePattern, '')
              .replaceAll(RegExp(r'\s{2,}'), ' ')
              .trim();
        })
        .where((s) => s.isNotEmpty)
        .toList();
    return phrases.join(', ');
  }

  /// 短语级语义去重与互斥渲染管线过滤。
  ///
  /// 按逗号、分号及换行切分短语，进行小写与前后空白归一化；
  /// 保持首次出现的短语顺序，剔除完全重复项；
  /// 自动排除互斥渲染器（如已包含 Unreal Engine / UE5 则过滤 Octane，反之亦然）。
  static String deduplicatePhrases(String prompt) {
    if (prompt.trim().isEmpty) return '';
    final rawPhrases = prompt
        .split(RegExp(r'[,，;；\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final result = <String>[];
    final seen = <String>{};
    bool hasUnreal = false;
    bool hasOctane = false;

    for (final phrase in rawPhrases) {
      final lower = phrase.toLowerCase();

      // 渲染管线互斥判定
      final isUnreal = lower.contains('unreal engine') || lower.contains('ue5');
      final isOctane = lower.contains('octane');

      if (isUnreal) {
        if (hasOctane) continue;
        hasUnreal = true;
      } else if (isOctane) {
        if (hasUnreal) continue;
        hasOctane = true;
      }

      // 短语完全重复过滤（大小写不敏感）
      if (!seen.add(lower)) {
        continue;
      }

      result.add(phrase);
    }

    return result.join(', ');
  }

  /// 组装一条片段视频提示词（spec: 片段提示词组装）。
  ///
  /// **确定性组装，不让 AI 自由发挥**（design 决策 5）：AI 只负责划片段边界
  /// 与给目标时长，最终提示词由分镜字段 + 角色卡 + 场景卡 + 台账在这里拼出。
  /// 这样「改了分镜字段但片段提示词没变」这类不同步不可能发生——纯函数每次
  /// 重算，UI 不需要判断何时该重新生成。
  ///
  /// 段顺序即优先级：画质/风格 → 运镜/机位 → 角色身份锚点与素材指代 →
  /// 场景锚点与素材指代 → 连续视觉动作叙事 → 连续性绝对状态 → 片段级补充说明。
  ///
  /// [references] 非空时，角色与场景锚点位输出 `<Picture N>` 编号；编号与该
  /// 列表一一对应。传入空列表表示调用方还没有准备好参考图——此时角色/场景
  /// 锚地只写文字描述，并在 [AssembledPrompt.missingReferences] 里列出缺口，
  /// 让调用方阻止生成（spec: 缺少参考图时不静默降级）。
  static AssembledPrompt buildSegmentPrompt(
    SegmentPromptParts parts, {
    List<SegmentReference> references = const [],
  }) {
    final positiveSegments = <String>[];
    final missing = <String>[];

    // 1. 画质与风格基线（短语级去重与渲染器冲突排除）。
    final prodType = parts.productionType;
    final qualityTokens =
        prodType != null && prodType.defaultPositiveStyle.isNotEmpty
        ? prodType.defaultPositiveStyle
        : _qualityBaseline;
    final style = parts.styleTokens?.trim() ?? '';
    final combinedStyle = style.isNotEmpty && style != qualityTokens
        ? '$qualityTokens, $style'
        : qualityTokens;
    final cleanStyle = deduplicatePhrases(combinedStyle);
    if (cleanStyle.isNotEmpty) {
      positiveSegments.add(cleanStyle);
    }

    // 2. 运镜与机位协调（屏蔽时长泄漏与机位冲突）。
    //    若分镜明确指定了机位/运镜，以分镜实际运镜为准，屏蔽全局激进运镜 (motionTendency)。
    final cameraMoves = <String>[];
    for (final shot in parts.shots) {
      final move = shot.cameraMove.trim();
      if (move.isNotEmpty && !cameraMoves.contains(move)) {
        cameraMoves.add(move);
      }
    }

    if (cameraMoves.isNotEmpty) {
      final normalizedMoves = cameraMoves.map((m) {
        final lower = m.toLowerCase();
        if (lower == 'static' ||
            lower == 'fixed' ||
            lower.contains('固定') ||
            lower.contains('静止')) {
          return 'static camera, steady composition';
        }
        return m;
      }).toList();
      positiveSegments.add(deduplicatePhrases(normalizedMoves.join(', ')));
    } else if (prodType != null && prodType.motionTendency.isNotEmpty) {
      positiveSegments.add(prodType.motionTendency);
    }

    // 3. 角色身份锚点与素材占位符（官方标准 <Picture N> 格式）。
    //    同一角色在多镜出场只写一次（身份不随镜头变化）。
    for (final character in parts.characters) {
      final anchor = _characterAnchor(character);
      if (anchor.isEmpty) continue;
      final refIndex = references.indexWhere(
        (r) => r.usage.contains(character.name.trim()),
      );
      if (refIndex >= 0) {
        positiveSegments.add('$anchor <Picture ${refIndex + 1}>');
      } else {
        positiveSegments.add(anchor);
        missing.add('${character.name.trim()} 角色参考图');
      }
    }

    // 4. 主物理场景锁定与空镜排他词过滤。
    //    单个片段（4~12s）仅锁定单一主物理场景，避免跨异地场景撕裂画面空间。
    final dominantScene = parts.scenes.isNotEmpty ? parts.scenes.first : null;
    if (dominantScene != null) {
      String? spatialAnchor;
      for (final shot in parts.shots) {
        final matched = resolveSpatialViewForShot(
          scene: dominantScene,
          cameraMove: shot.cameraMove,
          actionZh: shot.actionZh,
        );
        if (matched != null && matched.promptEn.trim().isNotEmpty) {
          spatialAnchor = matched.promptEn.trim();
          break;
        }
      }
      var anchor = (spatialAnchor != null && spatialAnchor.isNotEmpty)
          ? spatialAnchor
          : (dominantScene.promptEn.trim().isNotEmpty
                ? dominantScene.promptEn.trim()
                : dominantScene.name.trim());

      // 当片段有出场角色时，自动过滤场景提示词中的 empty room, no humans 等空镜头排他词
      final hasCharacters = parts.characters.isNotEmpty;
      anchor = filterEmptySceneTokens(anchor, hasCharacters: hasCharacters);
      anchor = deduplicatePhrases(anchor);

      if (anchor.isNotEmpty) {
        final refIndex = references.indexWhere(
          (r) => r.usage.contains(dominantScene.name.trim()),
        );
        final prefix = anchor.toLowerCase().startsWith('scene:')
            ? ''
            : 'scene: ';
        if (refIndex >= 0) {
          positiveSegments.add('$prefix$anchor <Picture ${refIndex + 1}>');
        } else {
          positiveSegments.add('$prefix$anchor');
          missing.add('${dominantScene.name.trim()} 场景参考图');
        }
      }
    }

    // 5. 分段时空动作与对白序列（spec: shot-causality-ordering）。
    //
    // 每个分镜获得一个累加区间，区间内动作与对白分行：动作行是「要演的」，
    // 对白行是「要配的」，两者分开让模型不把台词当成动作指令。
    //
    // 这里**不再**从 actionZh 里剥离 dialogue——旧实现用正则删掉对白，导致
    // 整段片段提示词一句台词都没有，模型连"谁在什么时间做什么"都得自己编。
    // 时长：优先用分镜自身的 durationSec；为 0（未提供）时按片段目标时长均摊
    // 兜底。均摊只在缺数据时发生——正常路径下 studio_generation_tasks 会传入
    // 真实分镜时长，使区间与 SRT 游标、剪映导出对得上。
    final fallbackPerShot = parts.shots.isEmpty
        ? 0.0
        : ((parts.targetDurationSec ?? 0) / parts.shots.length).toDouble();
    final effectiveDurations = parts.shots
        .map((s) => s.durationSec > 0 ? s.durationSec : fallbackPerShot)
        .toList();
    final ranges = CausalityTimelineCompiler.cumulativeRanges(
      effectiveDurations,
    );

    final hasAnyDialogue = parts.shots.any((s) => s.dialogue.trim().isNotEmpty);

    final timelineBuffer = StringBuffer();
    for (var i = 0; i < parts.shots.length; i++) {
      final shot = parts.shots[i];
      final range = CausalityTimelineCompiler.formatRange(
        ranges[i].$1,
        ranges[i].$2,
      );

      var act = shot.actionZh.trim();
      if (act.isNotEmpty) {
        act = act.replaceAll(
          RegExp(
            r'^(shot\s*\d+|镜头\s*\d+|第\s*\d+\s*镜)[\s:\|、，]*',
            caseSensitive: false,
          ),
          '',
        );
        act = act.replaceAll(RegExp(r'[，,；;。]+$'), '').trim();
      }

      final rawDialogue = shot.dialogue.trim();
      // 台词行带秒数标注：让模型知道这句话要占掉区间里的一段，而不是瞬间说完。
      final dialogueLine = rawDialogue.isEmpty
          ? ''
          : '  对白：${cleanDialogueForSpeech(rawDialogue)}';

      if (act.isEmpty && dialogueLine.isEmpty) continue;

      timelineBuffer.writeln('$range 镜号 ${shot.number}：');
      if (act.isNotEmpty) timelineBuffer.writeln('  动作：$act');
      if (dialogueLine.isNotEmpty) timelineBuffer.writeln(dialogueLine);
    }
    if (timelineBuffer.isNotEmpty) {
      positiveSegments.add(timelineBuffer.toString().trimRight());
    }

    // 5b. 含对白的片段必须声明全员闭口守卫。
    //
    // 分镜级提示词一直有这段（正向对白约束里的"同框倾听者保持闭口"），但片段级
    // 以前靠"没有对白"规避画面内开口。对白一旦进来，这层规避就没了，必须补上
    // 等强度的守卫——否则模型会让所有在场角色一起张嘴。
    if (hasAnyDialogue) {
      positiveSegments.add(
        '声音与画面约束：以上台词为配音轨内容，画面中全员嘴唇保持自然闭合，'
        '不对口型、不张嘴、不念白，无画内文字与字幕，仅以微表情与肢体动作表演。',
      );
    }

    // 6. 连续性绝对状态（钉住，不参与超限丢弃；去除 shot N state: 剧本结构前缀）。
    final pinned = <String>[];
    final seenContinuity = <String>{};
    for (final shot in parts.shots) {
      final token = ContinuityTokens.of(shot.continuity);
      if (token.isEmpty) continue;
      if (seenContinuity.add(token)) {
        pinned.add(token);
      }
    }

    // 7. 片段级补充说明（可牺牲）。
    final note = parts.promptNote?.trim() ?? '';
    if (note.isNotEmpty) positiveSegments.add(note);

    // 台账段追加在可牺牲段之后，并用 pinnedFrom 声明「从该下标起的所有段都不许丢」。
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

  /// 编译 4 段式摄影调度。
  static String buildCamera4Stage({
    required String cameraMove,
    String cameraStaging = '',
    String subjectName = '',
    String triggerAction = '',
    String endSettling = '',
  }) => CameraStagingCompiler.compile4Stage(
    cameraMove: cameraMove,
    cameraStaging: cameraStaging,
    subjectName: subjectName,
    triggerAction: triggerAction,
    endSettling: endSettling,
  );

  /// 编译即梦 Seedance 任务执行稿。
  static String buildSeedancePrompt({
    required StudioSegment segment,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
    DynamicExitState? previousExitState,
  }) => SeedanceTaskCompiler.compileSegment(
    segment: segment,
    shots: shots,
    characters: characters,
    scenes: scenes,
    productionType: productionType,
    styleTokens: styleTokens,
    previousExitState: previousExitState,
  );

  /// 编译商用通用写实视频自然语言提示词。
  static String buildPhotorealisticPrompt({
    required StudioShot shot,
    CharacterCard? character,
    SceneCard? scene,
    StudioProductionType? productionType,
    String styleTokens = '',
    DynamicExitState? previousExitState,
  }) => PhotorealisticPromptCompiler.compileShot(
    shot: shot,
    character: character,
    scene: scene,
    productionType: productionType,
    styleTokens: styleTokens,
    previousExitState: previousExitState,
  );

  /// 编译 H3 六列 CSV 二进制数据。
  static List<int> buildH3Csv({
    required StudioEpisode episode,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
  }) => H3CsvCompiler.compileCsvBytes(
    episode: episode,
    shots: shots,
    characters: characters,
    scenes: scenes,
    productionType: productionType,
    styleTokens: styleTokens,
  );

  /// 角色卡 → 身份锚点段。
  ///
  /// 只写「不会随镜头变化的部分」：外貌与服装。表演、站位、情绪由逐镜段与
  /// 台账负责——把它们塞进身份锚点会让同一角色在不同片段里长出不同的脸。
  static String _characterAnchor(CharacterCard character) {
    final traits = <String>[];
    if (character.facialFeaturesZh.trim().isNotEmpty) {
      traits.add(character.facialFeaturesZh.trim());
    }
    if (character.defaultAttireZh.trim().isNotEmpty) {
      traits.add(character.defaultAttireZh.trim());
    }
    if (traits.isNotEmpty) {
      return '${character.name.trim()}（${traits.join("，")}）';
    }
    if (character.descriptionZh.trim().isNotEmpty) {
      return '${character.name.trim()}（${character.descriptionZh.trim()}）';
    }
    final base = character.basePromptPositive.trim();
    if (base.isNotEmpty) return base;
    return character.name.trim();
  }

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
      final words = _promptWordsOf(segment);
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
      text: _joinPromptSegments(kept),
      truncated: dropped.isNotEmpty,
      dropped: dropped,
    );
  }

  /// 对内心独白（内心 OS / 心声）进行生图层脱敏净化。
  ///
  /// TTS 配音需要原汁原味的原著台词，但文生图模型会将台词文本直接送入注意力机制。
  /// 若台词中提及“老王”、“师尊”等非在场人物，模型会产生幻觉臆造实体（如老王牵驴）。
  /// 本方法剥离时间标注、剥离非在场第三人人名、剥离口语杂质，转化为纯粹的微表情与心理神态描写。
  static String sanitizeInnerMonologue({
    required String dialogue,
    String speaker = '',
    List<String> inSceneCharacters = const [],
  }) {
    var text = dialogue
        .replaceAll(RegExp(r'[（\(][^）\)]*秒[）\)]'), '') // 移除（预估2.5秒）
        .replaceAll(
          RegExp(r'^[^\s：:]+[（\(][^）\)]*[）\)][：:]\s*'),
          '',
        ) // 移除“角色（内心 OS）：”
        .replaceAll(RegExp(r'^(内心\s*OS|心声|内心独白)[：:]\s*'), '')
        .trim();

    // 移除包裹引号
    if (text.startsWith('“') && text.endsWith('”') && text.length >= 2) {
      text = text.substring(1, text.length - 1).trim();
    } else if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
      text = text.substring(1, text.length - 1).trim();
    }

    // 针对常见“又被老王训了/想起老王/念及师傅”等模式，将非在场的人名泛化为中性指代
    // 防止扩散大模型将老王直接渲染进画面
    final commonMentions = [
      '老王',
      '老李',
      '师傅',
      '师尊',
      '掌门',
      '皇帝',
      '殿下',
      '总管',
      '管事',
    ];
    for (final mention in commonMentions) {
      if (!inSceneCharacters.contains(mention)) {
        text = text.replaceAll(mention, '他人');
      }
    }

    if (text.isEmpty) {
      return '眼眸深邃微阖，若有所思';
    }
    return '心忖“$text”';
  }

  /// 编译视线轴线（Eye-line）与机位俯仰（Camera Angle）指令。
  static String compileGazeAndEyeline({
    String cameraAngle = '',
    String gazeDirection = '',
    String gazeTarget = '',
    String elevationLevel = '',
  }) {
    final tokens = <String>[];

    final isHigh =
        cameraAngle == 'high_angle' ||
        elevationLevel.contains('balcony') ||
        elevationLevel.contains('rooftop') ||
        elevationLevel.contains('high') ||
        gazeDirection.contains('俯视') ||
        gazeDirection.contains('向下');

    final isLow =
        cameraAngle == 'low_angle' ||
        (elevationLevel == 'ground' &&
            (gazeDirection.contains('仰望') || gazeDirection.contains('向上'))) ||
        gazeDirection.contains('仰视') ||
        gazeDirection.contains('仰望') ||
        gazeDirection.contains('向上');

    if (isHigh) {
      tokens.add('机位为高角度俯拍视角（high-angle downward perspective）');
      tokens.add(
        '人物视线向斜下方长街地面注视（gazing downwards towards the street below, 3/4 profile, strictly no eye contact with camera）',
      );
    } else if (isLow) {
      tokens.add('机位为低角度仰拍视角（low-angle upward perspective）');
      tokens.add(
        '人物下颌微抬向斜上方楼台仰视（gazing upwards towards the balcony above, tilted head, 3/4 profile, strictly no eye contact with camera）',
      );
    } else if (gazeDirection.isNotEmpty) {
      tokens.add(
        '视线朝向：$gazeDirection（侧面半侧面角度，严禁直视镜头，3/4 profile view, no eye contact with viewer）',
      );
    }

    if (gazeTarget.isNotEmpty) {
      tokens.add('目光聚焦于$gazeTarget');
    }

    return tokens.join('，');
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

/// 因果时间轴编译器（spec: shot-causality-ordering）。
///
/// 三条生成路径（分镜级、片段级、执行稿导出）共用同一套 `[起始s - 结束s]`
/// 区间语法——格式一旦漂移，用户从「复制 Seedance 执行稿」和「实际生成的
/// 提示词」里看到不同写法，会以为其中一个是错的。
abstract final class CausalityTimelineCompiler {
  /// 把一组时长转成累加区间。
  ///
  /// 首区间从 0.0 起算，每个区间的起点是前序时长之和，末区间结束时刻等于
  /// 总时长。这样片段级提示词的区间与分镜游标模型（SRT 的 `cursorMs +=
  /// holdMs`）天然对齐，不需要两套各自累加。
  ///
  /// 非正时长按 0 计但不跳过占位——区间数必须与输入一一对应，否则下游按
  /// 下标取值时会静默错位。
  static List<(double, double)> cumulativeRanges(List<double> durationsSec) {
    final ranges = <(double, double)>[];
    var cursor = 0.0;
    for (final d in durationsSec) {
      final span = d > 0 ? d : 0.0;
      ranges.add((cursor, cursor + span));
      cursor += span;
    }
    return ranges;
  }

  /// 单个区间渲染成 `[0.0s - 4.0s]`。
  ///
  /// 一位小数：分镜时长本身就是 0.5 秒粒度，更多位数是虚假精度。
  static String formatRange(double startSec, double endSec) =>
      '[${startSec.toStringAsFixed(1)}s - ${endSec.toStringAsFixed(1)}s]';

  /// 一组区间渲染成 `[0.0s - 4.0s] [4.0s - 7.0s] ...`。
  static String formatRanges(List<(double, double)> ranges) =>
      ranges.map((r) => formatRange(r.$1, r.$2)).join(' ');

  /// 从 `temporalEvolution` 自由文本里解析显式秒数分界。
  ///
  /// AI 拆镜产出的是「前1.5秒屏息试探，后1.5秒暴起接触」这类描述，没有固定
  /// schema。这里只认两种最常见的写法：
  /// - `前N秒…` / `后N秒…`：以 N 为分界点；
  /// - `N秒…`（句首数字）：同样以 N 为分界点。
  ///
  /// 解析不出返回 null，调用方回落到默认次序分配——**不因为解析失败就省略
  /// 时间轴段**，那会把最难约束的镜头变成完全无时序的平铺文本。
  static double? parsePhaseSplitSec(String temporalEvolution) {
    if (temporalEvolution.trim().isEmpty) return null;
    final normalized = temporalEvolution.replaceAll('：', ':');

    // 「前1.5秒」「后1.5秒」——取第一个出现的数字作为分界。
    final preMatch = RegExp(r'[前后]\s*([\d.]+)\s*秒').firstMatch(normalized);
    if (preMatch != null) {
      final v = double.tryParse(preMatch.group(1) ?? '');
      if (v != null && v > 0) return v;
    }

    // 句首裸数字，如「0.8秒破空突刺，0.5秒发丝断落」。
    final leadMatch = RegExp(r'^\s*([\d.]+)\s*秒').firstMatch(normalized);
    if (leadMatch != null) {
      final v = double.tryParse(leadMatch.group(1) ?? '');
      if (v != null && v > 0) return v;
    }
    return null;
  }
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
    'depressing' =>
      'desaturated cold lighting, heavy shadows, gloomy atmosphere',
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
    ShotFunction.opening =>
      'hook composition, subject centered, strong focal point',
    ShotFunction.advance => 'rule of thirds, leading lines',
    ShotFunction.burst =>
      'dutch angle, extreme perspective, high tension framing',
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

/// 年龄阶段划分枚举（spec: 全年龄段动态骨骼防漂移与体态解绑）。
enum CharacterAgeGroup {
  child('child', '幼童'),
  teen('teen', '少年'),
  adult('adult', '青年与成年'),
  elder('elder', '老年');

  final String id;
  final String label;
  const CharacterAgeGroup(this.id, this.label);
}

/// 角色三视图提示词（spec: character-turnaround-sheet）。
///
/// 单独一个类而不是塞进 [PromptAssembler]：它只服务一个动作，但要求很具体
/// ——正/侧/背同帧、同一人、同一服装、同一发型。这些约束若混在通用分镜
/// 拼接逻辑里，会被人当成"可调参数"改掉，而三视图的质量恰恰依赖它们。
abstract final class CharacterTurnaroundPrompt {
  /// 4区块专业角色资产图视角排版：
  /// 首置英文核心词 Character turnaround sheet 与 16:9 画幅声明。
  /// 左侧大图为正面脸部胸像特写，右侧横向排列正面平视全身、标准90度侧面全身与背面全身三身立绘。
  static const String _viewLayoutRequirement =
      'Character turnaround sheet，角色三视图设计图，角色设定资产参考图，16:9横版，纯白无缝背景，分4个区块：左侧大图是正面脸部胸像特写，清晰展示五官、脸型、发型、妆容与上半身服装细节；右侧横向排列同一角色的三个全身视角：正面平视、侧面、背面（正面平视全身、标准90度侧面全身、背面全身）';

  /// 一致性与正交平视约束。
  static const String _identityRequirement =
      '全部视图为完全一致的同一人物，脸型、五官、发色、发型、身材比例、服装配饰100%完全一致，人物中立自然站立，双手自然垂于身体两侧，全身完整入镜无遮挡，正交视图orthographic，无透视畸变';

  /// Agnes 专用 PBR 物理材质、柔和漫射光影与去塑料微观肌理正向守卫。
  /// 针对 Agnes 模型缺乏 API negative_prompt 支持的缺陷，在 Positive 中强力注入漫射光、哑光、毛孔与碎发，并在正向尾部显式声明 not a toy, not figurine。
  static const String pbrAntiPlasticGuardPositive =
      'soft diffused studio lighting，柔和漫射柔光，不要强烈高光，matte surface，哑光材质，低specular，皮肤带有自然细微毛孔肌理，非打蜡油亮皮肤，布料保留织物编织纹理与自然褶皱纤维，发丝有细小碎发flyaway hairs，PBR physically based shading物理材质，不同材质粗糙度区分，无统一蜡质涂层，subsurface scattering次表面散射皮肤通透感，very subtle film grain极轻微胶片颗粒，not a toy, not figurine，真实人物质感';

  static const String _styleRequirement =
      '8K，超高细节，专业角色概念设计定妆照，各视角间距均匀，纯白底色，无背景，无杂物阴影，无地面，无文字标签，无水印，无多余杂物，无边框切分线';

  /// 负面提示词：收录塑料皮肤、蜡质皮肤、盲盒玩偶等去塑料抗打蜡词汇，以及多重视角污染与环境背景防御。
  static const String turnaroundNegativePrompt =
      'plastic skin，waxy wax skin，oily sheen，strong specular highlight，doll，blind box toy，塑胶人偶，蜡像，过度磨皮，airbrushed，美颜滤镜，光滑无瑕皮肤，CGI渲染，3d玩偶，皮肤镜面反光，统一光滑塑料涂层，多张不同人脸，人物变形，肢体残缺，复杂背景，自然风景，室内外环境，墙壁，地面，阴影，树木，建筑，暗色背景，多个人物，额外路人，重复面部，切头，断脚，单重视角，双重视角，文字，水印，网格线，分割画幅，透视辅助线，草稿杂线';

  /// 幼童防漂移与低幼娃娃排斥词
  static const String antiToddlerNegativeBan =
      '低幼儿童，大头娃娃，幼童童子，幼儿体态，年画福娃，婴儿肥幼稚儿童，短腿短手幼儿';

  /// 检测角色年龄阶段（支持纯中文及英文年龄推断）。
  static CharacterAgeGroup detectAgeGroup({
    String descriptionZh = '',
    String positiveText = '',
  }) {
    final combined =
        '${descriptionZh.toLowerCase()} ${positiveText.toLowerCase()}';

    // 1. 少年/青少年（13~19岁，少年，及笄，弱冠，书童，少东家等）
    // 优先于幼童检测，避免“十六岁”中的“六岁”误匹配为幼童
    final teenRegex = RegExp(
      r'(1[3-9]岁|十三岁|十四岁|十五岁|十六岁|十七岁|十八岁|十九岁|少年|青涩少年|青少年|及笄|弱冠|书童|小厮|少东家|\bteen\b|\bteenager\b|\badolescent\b)',
    );
    if (teenRegex.hasMatch(combined)) {
      return CharacterAgeGroup.teen;
    }

    // 2. 老年（50岁以上，老者，老人，老翁，白发苍苍等）
    final elderRegex = RegExp(
      r'([5-9]\d岁|1\d\d岁|老者|老翁|老妪|老人|老道|老僧|白发老者|白发苍苍|花甲|古稀|耄耋|垂暮|迟暮|\belderly\b|\bold man\b|\bold woman\b|\bsenior\b)',
    );
    if (elderRegex.hasMatch(combined)) {
      return CharacterAgeGroup.elder;
    }

    // 3. 幼童（12岁以下，幼童，男童，女童，正太，女娃等）
    final childRegex = RegExp(
      r'([1-9]岁|1[0-2]岁|一岁|两岁|三岁|四岁|五岁|六岁|七岁|八岁|九岁|十岁|十一岁|十二岁|幼童|儿童|男童|女童|女娃|男娃|娃娃|稚童|童子|道童|小童|幼年|幼态|正太|小孩|小女孩|小男孩|\bchild\b|\bkid\b|\btoddler\b|\blittle boy\b|\blittle girl\b)',
    );
    if (childRegex.hasMatch(combined)) {
      return CharacterAgeGroup.child;
    }

    // 4. 默认青年与成年
    return CharacterAgeGroup.adult;
  }

  /// 从全年龄骨骼防漂移模板中解析指定年龄阶段的骨骼身量与防漂移约束。
  static String resolveAgeStagingGuard({
    String descriptionZh = '',
    String positiveText = '',
    CharacterAgeGroup? explicitGroup,
  }) {
    final group =
        explicitGroup ??
        detectAgeGroup(
          descriptionZh: descriptionZh,
          positiveText: positiveText,
        );

    final template = StudioPresetStore.instance.getPromptContent(
      'character_age_staging',
    );
    final extracted = _extractSectionFromAgeTemplate(template, group);
    if (extracted.isNotEmpty) return extracted;

    return switch (group) {
      CharacterAgeGroup.child => '稚嫩孩童身形，儿童面部轮廓，自然儿童比例',
      CharacterAgeGroup.teen =>
        '具备接近成年男性的纵向骨骼身长，青少年身高（约165~170cm），骨骼发育充分拉伸，宽厚肩膀，成年男子头身比例，体态身型符合设定，面部光洁无须，少年青涩容貌，下颌轮廓分明',
      CharacterAgeGroup.adult => '完全成型的成年写实骨架，真实人体肌肉骨骼结构，成熟身姿，体态身型符合角色设定',
      CharacterAgeGroup.elder => '长者身姿与长者骨相，自然面部岁月纹理与岁月风霜感',
    };
  }

  static String _extractSectionFromAgeTemplate(
    String template,
    CharacterAgeGroup group,
  ) {
    if (template.trim().isEmpty) return '';
    final tagPatterns = switch (group) {
      CharacterAgeGroup.child => [
        '【幼童】',
        '• 幼童',
        '【儿童】',
        '• 儿童',
        '[幼童]',
        '[儿童]',
      ],
      CharacterAgeGroup.teen => [
        '【少年】',
        '• 少年',
        '【青少年】',
        '• 青少年',
        '[少年]',
        '[青少年]',
      ],
      CharacterAgeGroup.adult => [
        '【青年/成年】',
        '• 青年/成年',
        '【青年与成年】',
        '【青年】',
        '• 青年',
        '【成年】',
        '• 成年',
        '[青年与成年]',
        '[青年]',
        '[成年]',
      ],
      CharacterAgeGroup.elder => [
        '【老年】',
        '• 老年',
        '【长者】',
        '• 长者',
        '[老年]',
        '[长者]',
      ],
    };

    for (final tag in tagPatterns) {
      final idx = template.indexOf(tag);
      if (idx != -1) {
        final start = idx + tag.length;
        final nextTagIdx = template.indexOf(RegExp(r'[【\[•]'), start);
        final section = (nextTagIdx != -1)
            ? template.substring(start, nextTagIdx)
            : template.substring(start);
        var cleaned = section
            .replaceAll(RegExp(r'^[：:\s]+'), '')
            .replaceAll(RegExp(r'[；;\n\r]+$'), '')
            .trim();
        // 清洗类似 （13~18岁）： 或 (<13岁)： 等年龄段标签前缀
        cleaned = cleaned
            .replaceAll(RegExp(r'^\s*[(（][^()（）]*[)）]\s*[：:]\s*'), '')
            .trim();
        // 自动净化可能存在的历史否定词
        cleaned = sanitizePositiveAffirmative(cleaned);
        if (cleaned.isNotEmpty) return cleaned;
      }
    }
    return '';
  }

  /// 纯肯定式正向提示词安全过滤器：彻底剥离可能触发模型低幼注意力的否定词句（粉色大象效应防御）。
  static String sanitizePositiveAffirmative(String text) {
    if (text.trim().isEmpty) return text;
    var result = text;
    // 剔除包含“非...”、“不要...”、“严禁...”等低幼/儿童相关的否定短语
    result = result.replaceAll(
      RegExp(
        r'[,，、\s]*(非|不是|不要|严禁|杜绝|没有|无需)[^,，。；\n\r]*(低幼|幼童|小娃娃|儿童|年画|矮短|童子|婴儿|幼儿|小孩)[^,，。；\n\r]*',
      ),
      '',
    );
    // 清洗多余的分隔符
    result = result.replaceAll(RegExp(r'[,，]{2,}'), '，');
    result = result.replaceAll(RegExp(r'^[，,\s]+|[，,\s]+$'), '');
    return result;
  }

  /// 从角色中文描述或总述中提取明确的显式年龄或阶层置顶正向锚点。
  ///
  /// 若容貌体态中已包含年龄数字，优先使用；若容貌体态缺失年龄，自动从总述中回溯提取
  /// （例如识别出“十五六岁”或“16岁”，生成“16岁青年男子身量，青少年骨骼身长，身高约168cm”），
  /// 并置顶注入到正向提示词最前列，使下游扩散模型的 Text Encoder 最先锁定成年/青年骨架。
  static String extractExplicitAgeAnchor({
    String facialZh = '',
    String descriptionZh = '',
  }) {
    final text = '$facialZh $descriptionZh';
    if (text.trim().isEmpty) return '';

    // 1. 匹配具体的十几岁少年数字
    final teenAgeMatch = RegExp(
      r'(1[3-9]岁|十三岁|十四岁|十五六岁|十五岁|十六七岁|十六岁|十七八岁|十七岁|十八九岁|十八岁|十九岁)',
    ).firstMatch(text);
    if (teenAgeMatch != null) {
      final raw = teenAgeMatch.group(0)!;
      final normalized = raw
          .replaceAll('十五六岁', '16岁')
          .replaceAll('十六七岁', '16~17岁')
          .replaceAll('十七八岁', '17~18岁')
          .replaceAll('十八九岁', '18~19岁')
          .replaceAll('十三岁', '13岁')
          .replaceAll('十四岁', '14岁')
          .replaceAll('十五岁', '15岁')
          .replaceAll('十六岁', '16岁')
          .replaceAll('十七岁', '17岁')
          .replaceAll('十八岁', '18岁')
          .replaceAll('十九岁', '19岁');
      return '$normalized青年男子身量，青少年骨骼身长，身高约168cm，已完成纵向骨架拔高拉伸，成年人头身比';
    }

    // 2. 匹配具体成年/中年数字 (20~50岁)
    final adultAgeMatch = RegExp(
      r'([2-4]\d岁|二十多岁|二十岁出头|二十出头|二十岁|三十岁|四十岁|青年|年轻男子|成年男性)',
    ).firstMatch(text);
    if (adultAgeMatch != null) {
      return '成年男性骨架身量，骨骼完全成型，身高约178cm，成年人体态比例';
    }

    // 3. 匹配少东家/少年/青年等角色阶层
    if (RegExp(r'(少年|少东家|书童|小厮|及笄|弱冠)').hasMatch(text)) {
      return '16岁左右青年男子身量，青少年骨骼身长，身高约168cm，骨架拉伸舒展，成年人头身比';
    }

    return '';
  }

  /// 检测是否声明了微胖、矮壮或丰满体态设定。
  static bool hasPlumpOrStoutBuild({
    String descriptionZh = '',
    String positiveText = '',
  }) {
    final combined =
        '${descriptionZh.toLowerCase()} ${positiveText.toLowerCase()}';
    return RegExp(
      r'(矮壮|敦实|微胖|肥胖|圆滚滚|富态|胖|肉嘟嘟|矮胖|胖墩|魁梧|壮硕|宽胖|plump|chubby|stout|husky|fat|portly)',
    ).hasMatch(combined);
  }

  /// 动态解析体态比例正向锚点（若角色为微胖/矮壮，解绑修长挺拔；标准成人则保持）。
  static String resolveProportionAnchor({
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
    String descriptionZh = '',
    String positiveText = '',
  }) {
    if (proportion == CharacterTurnaroundProportion.chibi) {
      return proportion.positiveAnchor;
    }
    final isPlumpOrStout = hasPlumpOrStoutBuild(
      descriptionZh: descriptionZh,
      positiveText: positiveText,
    );
    if (isPlumpOrStout) {
      return '标准写实体态比例，写实人体结构，身长比例符合矮壮敦实设定，体态丰满宽厚，拥有成年青年真实身长骨骼，四肢舒展，全身从头到脚完整可见';
    }
    return proportion.positiveAnchor;
  }

  /// 清洗剧集全局风格词，过滤掉破坏三视图纯白底的场景、光影与环境词，以及诱发 Agnes 镜面高光塑料感的渲染引擎词。
  static String cleanTurnaroundStyleTokens(String styleTokens) {
    if (styleTokens.trim().isEmpty) return '';
    final tokens = styleTokens
        .split(RegExp(r'[,，\.\n;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    const bannedKeywords = [
      'background',
      'scenery',
      'environment',
      'landscape',
      'nature',
      'interior',
      'exterior',
      'outdoor',
      'indoor',
      'room',
      'street',
      'dungeon',
      'forest',
      'city',
      'sky',
      'wall',
      'floor',
      'ground',
      'dark realism',
      'cinematic lighting',
      'dramatic lighting',
      'rim lighting',
      'volumetric lighting',
      'atmospheric',
      'moody',
      'shadow',
      'depth of field',
      'bokeh',
      'cinematic film still',
      'film still',
      'movie still',
      'unreal engine 5',
      'unreal engine',
      'unreal',
      'ue5',
      'octane render',
      'octane',
      'cray',
      '3d渲染',
      'cg渲染',
      '次世代cg',
      '背景',
      '风景',
      '环境',
      '自然',
      '室内',
      '室外',
      '房间',
      '街道',
      '地牢',
      '森林',
      '城市',
      '天空',
      '墙壁',
      '地板',
      '地面',
      '阴影',
      '景深',
      '电影光影',
    ];

    final filtered = tokens.where((token) {
      final lower = token.toLowerCase();
      for (final banned in bannedKeywords) {
        if (lower.contains(banned)) return false;
      }
      return true;
    });

    return filtered.join('， ');
  }

  /// 正向无须防御词：针对少年/青年或排斥胡须的设定，在 Positive 中强力注入以彻底阻断古装先验蓄须
  static const String cleanShavenGuardPositive = '面部光洁无须，少年青涩容貌，皮肤细腻平滑，无胡须，无胡茬';

  /// 负向排须词：在支持 Negative Prompt 的引擎中协同排查成熟与老态特征
  static const String cleanShavenGuardNegative =
      '胡须，大胡子，络腮胡，山羊胡，胡茬，连鬓胡，成熟中年面孔，皱纹，老态，老者';

  /// 检测当前角色是否应触发正向无须防御守卫。
  static bool shouldInjectCleanShavenGuard({
    String positiveText = '',
    String negativeText = '',
    String descriptionZh = '',
  }) {
    final combinedPositive =
        '${positiveText.toLowerCase()} ${descriptionZh.toLowerCase()}';
    final combinedNegative = negativeText.toLowerCase();

    // 1. 如果在正向提示词或描述中明确要求蓄须（如“大胡子”、“美髯”、“full beard”），且负向没有排斥，则不注入去须守卫
    final wantsBeard = RegExp(
      r'(大胡子|浓密胡须|美髯|留有胡须|蓄须|full beard|thick beard|heavy stubble|with beard)',
    ).hasMatch(combinedPositive);
    final rejectsBeard =
        RegExp(
          r'(长胡子|胡子|胡须|美髯|胡茬|去除胡须|没有胡子|无须|去胡子|beard|mustache|goatee|facial hair|stubble)',
        ).hasMatch(combinedNegative) ||
        RegExp(
          r'(无须|没胡子|没有胡子|不留胡子|去除胡须|去胡子|clean-shaven|hairless face|no beard|no facial hair)',
        ).hasMatch(combinedPositive);

    if (wantsBeard && !rejectsBeard) return false;
    if (rejectsBeard) return true;

    // 2. 少年、青年、儿童等年轻特征检测：古装/商贾先验在没有无须声明时极易被扩散模型带偏出胡须
    final isYouth = RegExp(
      r'(少年|男孩|小弟|书童|幼年|正太|男童|青年|年轻|稚嫩|娃娃脸|teenager|teen boy|young boy|youthful|adolescent|1[0-8] years old)',
    ).hasMatch(combinedPositive);
    return isYouth;
  }

  /// 由角色英文正向 Prompt、风格锁、时代题材锁与体态比例组装三视图提示词。
  ///
  /// 组装顺序：
  /// 1. 4 区块专业视角布局（首置 Character turnaround sheet 声明与纯白无缝底）；
  /// 2. 一致性与正交平视约束（orthographic，阻断透视畸变）；
  /// 3. Agnes 专用 PBR 物理材质、漫射光影与去塑料感微观肌理守卫；
  /// 4. 显式年龄置顶锚点（若细分容貌缺漏年龄，自动从总述回溯提取，强力锁定青年骨架基调）；
  /// 5. 体态比例正向锚点（标准比例或萌系比例，矮壮/微胖自动解绑修长挺拔并采用纯肯定句）；
  /// 6. 全年龄段骨骼身量纯肯定自适应守卫；
  /// 7. 正向无须防御锁；
  /// 8. 时代题材服饰正向锚点；
  /// 9. 角色自身的外貌 Prompt 与服装 Prompt；
  /// 10. 清洗后的全局艺术画风词；
  /// 11. 专业概念设计定妆照画质与纯白底风格；
  /// 12. 最终经过 sanitizePositiveAffirmative 纯肯定式安全清洗。
  static String build(
    String characterPositivePrompt, {
    String attirePrompt = '',
    String styleTokens = '',
    VisualEraGenre? eraGenre,
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
    String descriptionZh = '',
    String negativePrompt = '',
    String fullDescriptionZh = '',
  }) {
    var trimmedChar = characterPositivePrompt.trim();
    final trimmedAttire = attirePrompt.trim();
    if (trimmedAttire.isNotEmpty && !trimmedChar.contains(trimmedAttire)) {
      trimmedChar = trimmedChar.isEmpty
          ? trimmedAttire
          : '$trimmedChar, $trimmedAttire';
    }
    final trimmedStyle = cleanTurnaroundStyleTokens(styleTokens);
    final costumeAnchor = eraGenre?.costumeAnchor.trim() ?? '';
    final proportionAnchor = resolveProportionAnchor(
      proportion: proportion,
      descriptionZh: descriptionZh,
      positiveText: trimmedChar,
    ).trim();

    // 显式年龄置顶锚点：优先从容貌提取，缺失时从全量总述回溯
    final effectiveFullDesc = fullDescriptionZh.trim().isNotEmpty
        ? fullDescriptionZh.trim()
        : descriptionZh;
    final explicitAgeAnchor = extractExplicitAgeAnchor(
      facialZh: descriptionZh,
      descriptionZh: effectiveFullDesc,
    ).trim();

    final ageGroup = detectAgeGroup(
      descriptionZh: effectiveFullDesc,
      positiveText: trimmedChar,
    );
    final ageStagingAnchor = resolveAgeStagingGuard(
      descriptionZh: effectiveFullDesc,
      positiveText: trimmedChar,
      explicitGroup: ageGroup,
    ).trim();

    final cleanShavenAnchor =
        shouldInjectCleanShavenGuard(
          positiveText: trimmedChar,
          negativeText: negativePrompt,
          descriptionZh: effectiveFullDesc,
        )
        ? cleanShavenGuardPositive
        : '';

    // 动态从 StudioPresetStore 读取 character_turnaround 规范
    final customTurnaround = StudioPresetStore.instance
        .getPromptContent('character_turnaround')
        .trim();
    final layoutParts = customTurnaround.isNotEmpty
        ? [customTurnaround]
        : [
            _viewLayoutRequirement,
            _identityRequirement,
            pbrAntiPlasticGuardPositive,
          ];

    final rawCombined = [
      ...layoutParts,
      if (explicitAgeAnchor.isNotEmpty) explicitAgeAnchor,
      if (proportionAnchor.isNotEmpty) proportionAnchor,
      if (ageStagingAnchor.isNotEmpty) ageStagingAnchor,
      if (cleanShavenAnchor.isNotEmpty) cleanShavenAnchor,
      if (costumeAnchor.isNotEmpty) costumeAnchor,
      if (trimmedChar.isNotEmpty) trimmedChar,
      if (trimmedStyle.isNotEmpty) trimmedStyle,
      if (customTurnaround.isEmpty) _styleRequirement,
    ].join('， ');

    return sanitizePositiveAffirmative(rawCombined);
  }

  /// 由解耦后的角色卡组装完整出场提示词（容貌 + 默认服饰）。
  static String buildForCharacter(
    CharacterCard character, {
    String styleTokens = '',
    VisualEraGenre? eraGenre,
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
  }) {
    final combinedPositive = character.combinedPromptPositive.isNotEmpty
        ? character.combinedPromptPositive
        : character.basePromptPositive;
    return build(
      combinedPositive,
      styleTokens: styleTokens,
      eraGenre: eraGenre,
      proportion: proportion,
      descriptionZh: character.facialFeaturesZh.isNotEmpty
          ? character.facialFeaturesZh
          : character.descriptionZh,
      fullDescriptionZh: character.descriptionZh,
      negativePrompt: character.basePromptNegative,
    );
  }

  /// 组装三视图专用负向提示词。
  ///
  /// 复合多层排他与防崩：
  /// 1. 三视图排版与多人物/视角畸变缺陷抑制；
  /// 2. 体态比例互斥排他词；
  /// 3. 全年龄骨骼防漂移排他词（若为少年或成年，强力排斥低幼儿童、大头娃娃、年画福娃等）；
  /// 4. 时代题材排他违禁词；
  /// 5. 美学风格专属违禁词；
  /// 6. 少年/无须防御词；
  /// 7. 角色卡自身原有的 basePromptNegative；
  /// 8. 通用防崩防畸形词。
  static String buildNegative({
    String baseNegative = '',
    VisualEraGenre? eraGenre,
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
    String descriptionZh = '',
    String positiveText = '',
    String styleNegativeBan = '',
  }) {
    final cleanShavenNegative =
        shouldInjectCleanShavenGuard(
          positiveText: positiveText,
          negativeText: baseNegative,
          descriptionZh: descriptionZh,
        )
        ? cleanShavenGuardNegative
        : '';

    final ageGroup = detectAgeGroup(
      descriptionZh: descriptionZh,
      positiveText: positiveText,
    );

    final shouldInjectAntiToddler =
        (ageGroup == CharacterAgeGroup.teen ||
            ageGroup == CharacterAgeGroup.adult) &&
        proportion != CharacterTurnaroundProportion.chibi;

    return AestheticStyle.assembleNegative(
      eraBans: eraGenre?.negativeBans,
      styleBans: styleNegativeBan,
      extraNegative: baseNegative,
      additionalBans: [
        turnaroundNegativePrompt,
        if (proportion.negativeBan.trim().isNotEmpty)
          proportion.negativeBan.trim(),
        if (cleanShavenNegative.isNotEmpty) cleanShavenNegative,
        if (shouldInjectAntiToddler) antiToddlerNegativeBan,
      ],
      universalBans: AestheticStyle.universalNegativeBrief,
    );
  }

  /// 计算形态与基准服装之间的冲突对冲负向词。
  ///
  /// 当形态为浅色/白衣，而角色原设定为深色/黑袍时，在负向词中强力注入深色服装排除词，
  /// 彻底阻断模型先验与底图深色服装外溢。
  static String computeAttireNegativeHedging({
    required CharacterCard character,
    required CharacterVariation variation,
  }) {
    final bans = <String>[];
    final varText =
        '${variation.name} ${variation.attirePrompt} ${variation.positiveDelta}'
            .toLowerCase();
    final baseAttire =
        '${character.defaultAttireZh} ${character.defaultAttirePrompt} ${character.descriptionZh} ${character.basePromptPositive}'
            .toLowerCase();

    final isVarWhiteOrLight = RegExp(
      r'(white|silver|ivory|pale|雪白|白衣|白袍|白色|素衣|银白|白长袍)',
    ).hasMatch(varText);
    final isBaseDark = RegExp(
      r'(black|dark|cyan|navy|charcoal|玄色|黑|深青|玄衣|狱卒|墨色|青衫)',
    ).hasMatch(baseAttire);

    if (isVarWhiteOrLight && isBaseDark) {
      bans.add('深色衣物，黑袍，黑衣，黑色服装，深色长袍，玄色袍服，深青色服饰，黑色制服，暗色衣袍');
    }

    final isVarDark = RegExp(
      r'(black|dark|charcoal|玄色|黑衣|黑袍|暗色|墨色)',
    ).hasMatch(varText);
    final isBaseLight = RegExp(
      r'(white|silver|ivory|雪白|白衣|白袍|白色|素衣)',
    ).hasMatch(baseAttire);

    if (isVarDark && isBaseLight) {
      bans.add('白色衣物，白袍，白衣，白色服装，浅色长袍，素色袍服，浅色衣服，素白衣裳');
    }

    return bans.join('， ');
  }

  /// 由角色与特定形态组装形态三视图提示词。
  ///
  /// 全量服饰置换：仅继承 [character.effectiveFacialPrompt]，彻底剔除原角色的默认服饰，
  /// 阻断旧服装关键词对新形态的压制。
  /// 当 [inheritBaseFace] 为 true 时，显式声明与基准参考图保持相同面部特征；
  /// 当 [inheritBaseFace] 为 false 时（如基准图生成错误误生胡须），切断脸模强锁定。
  static String buildForVariation({
    required CharacterCard character,
    required CharacterVariation variation,
    String styleTokens = '',
    VisualEraGenre? eraGenre,
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
    bool inheritBaseFace = true,
  }) {
    final normalizedAttire = PromptAssembler.normalizeDeltaWords(
      variation.effectiveAttirePrompt,
      isNegative: false,
    ).trim();

    final facial = character.effectiveFacialPrompt.trim();
    final combinedCharPrompt = [
      if (facial.isNotEmpty) facial,
      if (normalizedAttire.isNotEmpty) normalizedAttire,
    ].join('， ');

    const faceIdentityTokens = '完全一致的人物面容身份，与基准参考图保持相同的五官神态特征，角色风格统一';
    final combined = inheritBaseFace
        ? (combinedCharPrompt.isEmpty
              ? faceIdentityTokens
              : '$combinedCharPrompt， $faceIdentityTokens')
        : combinedCharPrompt;

    return build(
      combined,
      styleTokens: styleTokens,
      eraGenre: eraGenre,
      proportion: proportion,
      descriptionZh: character.facialFeaturesZh.isNotEmpty
          ? character.facialFeaturesZh
          : character.descriptionZh,
      negativePrompt: variation.negativeDelta.isNotEmpty
          ? variation.negativeDelta
          : character.basePromptNegative,
    );
  }

  /// 组装形态三视图负向提示词。
  static String buildNegativeForVariation({
    required CharacterCard character,
    required CharacterVariation variation,
    VisualEraGenre? eraGenre,
    CharacterTurnaroundProportion proportion =
        CharacterTurnaroundProportion.standard,
    String styleNegativeBan = '',
  }) {
    final hedging = computeAttireNegativeHedging(
      character: character,
      variation: variation,
    );

    final mergedNegative = variation.negativeDelta.isNotEmpty
        ? PromptAssembler.mergeNegativeVariation(
            baseNegative: character.basePromptNegative,
            negativeDelta: variation.negativeDelta,
          )
        : character.basePromptNegative;

    return buildNegative(
      baseNegative: mergedNegative,
      eraGenre: eraGenre,
      proportion: proportion,
      descriptionZh: character.facialFeaturesZh.isNotEmpty
          ? character.facialFeaturesZh
          : character.descriptionZh,
      positiveText: variation.effectiveAttirePrompt.isNotEmpty
          ? variation.effectiveAttirePrompt
          : character.effectiveFacialPrompt,
      styleNegativeBan: [
        if (styleNegativeBan.isNotEmpty) styleNegativeBan,
        if (hedging.isNotEmpty) hedging,
      ].join('， '),
    );
  }

  /// 独立 1:1 面部特写负向提示词。
  static const String portraitNegativePrompt =
      '全身照，全身展示，三视图，多重视角，多个人物，多余肢体，丑陋，变形，模糊，切脸，水印，文字，签名';

  /// 独立 1:1 面部特写正向提示词（仅使用容貌体态 Prompt，彻底免受服装干扰）。
  static String buildPortrait(
    String facialPrompt, {
    String styleTokens = '',
    VisualEraGenre? eraGenre,
    String descriptionZh = '',
    String negativePrompt = '',
  }) {
    final trimmedFacial = facialPrompt.trim();
    final trimmedStyle = styleTokens.trim();
    final cleanShavenAnchor =
        shouldInjectCleanShavenGuard(
          positiveText: trimmedFacial,
          negativeText: negativePrompt,
          descriptionZh: descriptionZh,
        )
        ? cleanShavenGuardPositive
        : '';

    return [
      '面部高清特写肖像，半身像，正视镜头，居中构图，超精细面部五官与眼神细节，中性自然神态，纯净摄影棚柔光，纯白背景',
      if (cleanShavenAnchor.isNotEmpty) cleanShavenAnchor,
      if (trimmedFacial.isNotEmpty) trimmedFacial,
      if (trimmedStyle.isNotEmpty) trimmedStyle,
      '大师杰作，超高画质，清晰对焦',
    ].join('， ');
  }

  /// 独立 1:1 面部特写负向提示词。
  static String buildNegativePortrait({
    String baseNegative = '',
    String descriptionZh = '',
    String positiveText = '',
    String styleNegativeBan = '',
  }) {
    final cleanShavenNegative =
        shouldInjectCleanShavenGuard(
          positiveText: positiveText,
          negativeText: baseNegative,
          descriptionZh: descriptionZh,
        )
        ? cleanShavenGuardNegative
        : '';

    return AestheticStyle.assembleNegative(
      styleBans: styleNegativeBan,
      extraNegative: baseNegative,
      additionalBans: [
        portraitNegativePrompt,
        if (cleanShavenNegative.isNotEmpty) cleanShavenNegative,
      ],
      universalBans: AestheticStyle.universalNegativeBrief,
    );
  }
}

/// 片段提示词的组装输入（spec: 片段提示词组装）。
///
/// 与 [PromptParts] 分开是因为两者的消费方不同：`PromptParts` 服务生图，
/// 关注单镜的画面构成；这里服务视频生成，关注「一段连续画面」的叙事与状态。
/// 共用的只有角色卡与场景卡——它们同源于 IP 主库，必须让两种产物看到同一张脸。
class SegmentPromptParts {
  /// 剧集制作类型，用于推导专属画风渲染与动态倾向。
  final StudioProductionType? productionType;

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
    this.productionType,
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

  /// 该镜的建议时长（秒）。0 表示未提供，此时由片段目标时长均摊兜底。
  final double durationSec;

  /// 该镜的连续性台账。空台账的镜号会被跳过——那意味着用户还没补台账，
  /// 强行写「绝对状态」会写成空话。
  final ShotContinuity continuity;

  const SegmentShotParts({
    required this.number,
    this.actionZh = '',
    this.dialogue = '',
    this.cameraMove = '',
    this.durationSec = 0,
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

/// 摄影机四段式运动调度编译器（spec: 四段式摄影机调度）。
///
/// 结构化为【起始运动 → 跟随对象 → 触发条件 → 结束落点】四阶段，
/// 彻底替代简单的"slow push-in"等含糊运镜词，为视频生成模型提供精确的运镜演变轨迹。
abstract final class CameraStagingCompiler {
  static String compile4Stage({
    required String cameraMove,
    String cameraStaging = '',
    String subjectName = '',
    String triggerAction = '',
    String endSettling = '',
  }) {
    if (cameraStaging.trim().isNotEmpty) {
      return cameraStaging.trim();
    }
    final move = cameraMove.trim().isEmpty ? '中景平视平稳起始' : cameraMove.trim();
    final subject = subjectName.trim().isEmpty ? '核心画面主体' : subjectName.trim();
    final trigger = triggerAction.trim().isEmpty
        ? '主体动作展开或受力变向瞬间'
        : triggerAction.trim();
    final end = endSettling.trim().isEmpty
        ? '落点平稳聚焦主体动作余势'
        : endSettling.trim();

    return '起始：$move；跟随：聚焦$subject；触发：$trigger；落点：$end';
  }
}

/// 即梦 Seedance 专有格式编译器。
///
/// 输出主体与资产定义、时空动作序列、四段式摄影调度与跨片段剪辑接力（Handoff）参数。
abstract final class SeedanceTaskCompiler {
  static String compileSegment({
    required StudioSegment segment,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
    DynamicExitState? previousExitState,
  }) {
    final buffer = StringBuffer();

    // 1. 画质与风格基线
    final prodType = productionType;
    final qualityTokens =
        prodType != null && prodType.defaultPositiveStyle.isNotEmpty
        ? prodType.defaultPositiveStyle
        : 'cinematic lighting, master quality, highly detailed';
    buffer.writeln('【画风与基线】$qualityTokens');
    if (styleTokens.trim().isNotEmpty) {
      buffer.writeln('【风格锁】${styleTokens.trim()}');
    }
    buffer.writeln('【单段目标时长】${segment.targetDurationSec}秒 单镜头连续生成');

    // 2. 主体定义
    buffer.writeln('\n【主体定义】');
    final charMap = {for (final c in characters) c.id: c};
    final seenCharIds = <String>{};
    for (final shot in shots) {
      for (final cid in shot.characterIds) {
        if (seenCharIds.add(cid)) {
          final c = charMap[cid];
          if (c != null) {
            final desc = c.descriptionZh.isNotEmpty
                ? c.descriptionZh
                : c.basePromptPositive;
            buffer.writeln('- 主体【${c.name}】：$desc');
          }
        }
      }
    }
    if (seenCharIds.isEmpty && characters.isNotEmpty) {
      for (final c in characters.take(2)) {
        buffer.writeln('- 主体【${c.name}】：${c.descriptionZh}');
      }
    }

    // 3. 场景定义
    final sceneMap = {for (final s in scenes) s.id: s};
    final seenSceneIds = <String>{};
    for (final shot in shots) {
      if (shot.sceneId.isNotEmpty && seenSceneIds.add(shot.sceneId)) {
        final s = sceneMap[shot.sceneId];
        if (s != null) {
          buffer.writeln(
            '- 场景【${s.name}】：${s.descriptionZh.isNotEmpty ? s.descriptionZh : s.promptEn}',
          );
        }
      }
    }

    // 4. 时空动作与视听序列
    buffer.writeln('\n【分段时空动作与摄影序列】');
    var timeCursor = 0.0;
    for (final shot in shots) {
      final start = timeCursor;
      final end = timeCursor + shot.durationSec;
      timeCursor = end;

      final timeRange =
          '[${start.toStringAsFixed(1)}s - ${end.toStringAsFixed(1)}s]';
      final shotSizeLabel = shot.shotSize.label;
      final cameraStaging = CameraStagingCompiler.compile4Stage(
        cameraMove: shot.cameraMove,
        cameraStaging: shot.directorDecisions.cameraStaging,
      );

      buffer.writeln('$timeRange 镜号 ${shot.number} ($shotSizeLabel):');
      buffer.writeln('  动作：${shot.actionZh}');
      if (shot.directorDecisions.physicalMomentum.isNotEmpty) {
        buffer.writeln('  物理动势：${shot.directorDecisions.physicalMomentum}');
      }
      buffer.writeln('  摄影机路径：$cameraStaging');
      if (shot.directorDecisions.lightingStaging.isNotEmpty) {
        buffer.writeln('  光影配置：${shot.directorDecisions.lightingStaging}');
      } else if (shot.continuity.lightingState.isNotEmpty) {
        buffer.writeln('  光影配置：${shot.continuity.lightingState}');
      }
      if (shot.dialogue.isNotEmpty) {
        buffer.writeln('  对白/音效：${shot.dialogue}');
      }
      if (shot.combatSteps.isNotEmpty) {
        buffer.writeln('  攻防因果链：');
        for (final step in shot.combatSteps) {
          buffer.writeln(
            '    * [${step.duty.label}] ${step.actorName} -> ${step.targetNames.join("/")}: ${step.attack} | 反馈=${step.impact} | 位移=${step.displacement}',
          );
        }
      }
    }

    // 5. 跨片段剪辑接力（Handoff Continuity）
    final lastShot = shots.isNotEmpty ? shots.last : null;
    final exitState = lastShot?.continuity.dynamicExitState;
    buffer.writeln('\n【剪辑接力 (Handoff Continuity)】');
    if (previousExitState != null && previousExitState.isNotEmpty) {
      buffer.writeln(
        '入口承接：支撑脚=${previousExitState.supportFoot}，初速度=${previousExitState.velocityVector}，接续动势=${previousExitState.unfinishedPhase}',
      );
    } else {
      buffer.writeln('入口承接：平稳入场，顺接上镜空间关系');
    }
    if (exitState != null && exitState.isNotEmpty) {
      buffer.writeln(
        '出口接力：支撑脚=${exitState.supportFoot}，末速度=${exitState.velocityVector}，未完成动势=${exitState.unfinishedPhase}',
      );
    } else {
      buffer.writeln('出口接力：动作处于自然衔接相位');
    }
    if (lastShot != null && lastShot.continuity.lightingState.isNotEmpty) {
      buffer.writeln('主光轴线：${lastShot.continuity.lightingState}');
    }

    return buffer.toString().trim();
  }
}

/// 商用通用视频模型（可灵 / 即梦 / Agnes / MiniMax / 海螺）自然语言提示词编译器。
///
/// 将五维导演调度、动作因果与光影环境编译为纯中文结构化导演叙事提示词。
abstract final class PhotorealisticPromptCompiler {
  /// 规范化运镜描述为地道纯中文电影摄影术语。
  static String normalizeCameraMoveZh(String move) {
    final m = move.trim();
    if (m.isEmpty) return '平稳固定机位';
    final lower = m.toLowerCase();
    if (lower == 'slow push-in tracking') return '缓慢前推跟随跟拍';
    if (lower == 'slow push-in' || lower == 'push-in' || lower == 'push in')
      return '缓慢推镜头';
    if (lower == 'slow pull-out' || lower == 'pull-out' || lower == 'pull out')
      return '缓慢拉远镜头';
    if (lower == 'pan left') return '向左横移扫摄';
    if (lower == 'pan right') return '向右横移扫摄';
    if (lower == 'tilt up') return '由下向上仰摇';
    if (lower == 'tilt down') return '由上向下俯摇';
    if (lower == 'orbit' || lower == 'orbital') return '环绕旋转运镜';
    if (lower == 'tracking' || lower == 'follow') return '平稳跟随跟拍';
    if (lower == 'static' || lower == 'fixed') return '固定机位静止构图';
    return m;
  }

  /// 过滤淘汰过时的英文渲染器咒语与伪标签（如 UE5, Octane, 3D CGI 等）。
  static String cleanRendererTags(String style) {
    if (style.trim().isEmpty) return '';
    return style
        .replaceAll(
          RegExp(
            r'\b(unreal\s*engine(\s*5)?(\s*render)?|ue5(\s*render)?|octane(\s*render)?|3d\s*cgi(\s*animation)?|photorealistic(\s*8k)?|cinematic\s*lighting|highly\s*detailed|exquisite\s*3d\s*render)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[,，\s]+'), ' ')
        .trim();
  }

  /// 编译纯原生中文结构化导演镜头指令与音画分流规范。
  ///
  /// 符合中国主流多模态与视频大模型（可灵 / 即梦 / Agnes / MiniMax / 海螺）原生中文导演规范：
  /// - 【镜头景别与运镜】：起始机位景别、四段式运镜演变轨迹。
  /// - 【空间与光影】：纯中文场景置景与环境主光/辅光轴线。
  /// - 【出场主体】：优先提取中文面部发型体态与服装装束，杜绝英文碎片翻译污染。
  /// - 【动作叙事】：主体动势演进、攻防对抗因果链与定格落幅。
  /// - 【声音与画面约束】：严格音画分流。画面角色保持从容自然闭口微表情，严禁开口嘴型与画内文字乱码；内心独白（OS）及台词标记为画外配音。
  static String compileShot({
    required StudioShot shot,
    CharacterCard? character,
    List<CharacterCard>? characters,
    SceneCard? scene,
    StudioProductionType? productionType,
    String styleTokens = '',
    DynamicExitState? previousExitState,
  }) {
    final sections = <String>[];

    // 1. 画风基调（过滤淘汰的英文渲染器咒语，保留纯正美学风格）
    final cleanStyle = cleanRendererTags(styleTokens);
    if (cleanStyle.isNotEmpty) {
      sections.add('【画风基调】$cleanStyle');
    } else if (productionType != null && productionType.label.isNotEmpty) {
      sections.add('【画风基调】${productionType.label}');
    }

    // 2. 镜头景别与运镜
    final shotSizeLabel = shot.shotSize.label;
    final normalizedMove = normalizeCameraMoveZh(shot.cameraMove);
    final subjectName =
        character?.name.trim() ??
        (characters?.isNotEmpty == true ? characters!.first.name.trim() : '');
    final cameraStaging = CameraStagingCompiler.compile4Stage(
      cameraMove: normalizedMove,
      cameraStaging: shot.directorDecisions.cameraStaging,
      subjectName: subjectName,
    );
    sections.add('【镜头景别与运镜】$shotSizeLabel，运镜调度：$cameraStaging');

    // 3. 空间与光影
    final sceneParts = <String>[];
    if (scene != null) {
      if (scene.descriptionZh.trim().isNotEmpty) {
        sceneParts.add(scene.descriptionZh.trim());
      } else if (scene.promptEn.trim().isNotEmpty) {
        sceneParts.add(scene.promptEn.trim());
      } else if (scene.name.trim().isNotEmpty) {
        sceneParts.add(scene.name.trim());
      }
    }
    final lighting = shot.directorDecisions.lightingStaging.trim().isNotEmpty
        ? shot.directorDecisions.lightingStaging.trim()
        : shot.continuity.lightingState.trim();
    if (lighting.isNotEmpty) {
      sceneParts.add('光影氛围：$lighting');
    }
    if (sceneParts.isNotEmpty) {
      sections.add('【空间与光影】${sceneParts.join("，")}');
    }

    // 4. 出场主体（优先提取纯中文容貌体态与服装）
    final effectiveCharacters = (characters != null && characters.isNotEmpty)
        ? characters
        : (character != null ? [character] : <CharacterCard>[]);

    if (effectiveCharacters.isNotEmpty) {
      final charDescList = <String>[];
      for (final c in effectiveCharacters) {
        final traits = <String>[];
        if (c.facialFeaturesZh.trim().isNotEmpty) {
          traits.add(c.facialFeaturesZh.trim());
        }
        if (c.defaultAttireZh.trim().isNotEmpty) {
          traits.add(c.defaultAttireZh.trim());
        }
        if (traits.isEmpty && c.descriptionZh.trim().isNotEmpty) {
          traits.add(c.descriptionZh.trim());
        }
        if (traits.isEmpty && c.basePromptPositive.trim().isNotEmpty) {
          traits.add(c.basePromptPositive.trim());
        }
        final detail = traits.join('，');
        charDescList.add(
          detail.isNotEmpty ? '${c.name.trim()}（$detail）' : c.name.trim(),
        );
      }

      final subjectBuffer = StringBuffer();
      subjectBuffer.write(charDescList.join(' 与 '));
      if (previousExitState != null && previousExitState.isNotEmpty) {
        subjectBuffer.write(
          '，接续上镜动势（${previousExitState.unfinishedPhase}，速度：${previousExitState.velocityVector}）',
        );
      } else {
        subjectBuffer.write('，初始身姿平衡就位');
      }
      sections.add('【出场主体】${subjectBuffer.toString()}');
    }

    // 5. 动作叙事与物理因果
    final actionParts = <String>[];
    final action = shot.actionZh.trim();
    if (action.isNotEmpty) {
      actionParts.add(action);
    }
    final momentum = shot.directorDecisions.physicalMomentum.trim();
    if (shot.combatSteps.isNotEmpty) {
      final combatSummary = shot.combatSteps
          .map(
            (c) =>
                '${c.actorName}发起${c.attack}，造成${c.impact}，产生${c.displacement}位移',
          )
          .join('；');
      actionParts.add('攻防对抗：$combatSummary');
      if (momentum.isNotEmpty) {
        actionParts.add('冲击反馈：$momentum');
      } else {
        actionParts.add('定格戏剧化落幅');
      }
    } else if (momentum.isNotEmpty) {
      actionParts.add('动态演进：物理动势（$momentum），动作顺畅连贯落幅');
    } else {
      actionParts.add('动态演进：镜头动作自然流转，动作连贯落幅');
    }
    sections.add('【动作叙事】${actionParts.join("；")}');

    // 6. 声音与画面约束（音画分流规则）
    final rawDialogue = shot.dialogue.trim();
    if (rawDialogue.isNotEmpty) {
      final isSystemNotice =
          rawDialogue.startsWith('【') ||
          rawDialogue.contains('获得') ||
          rawDialogue.contains('修为') ||
          rawDialogue.contains('幽冥气') ||
          rawDialogue.contains('推演') ||
          rawDialogue.contains('杀戮值') ||
          rawDialogue.contains('系统');

      final isInnerVoice =
          rawDialogue.contains('内心 OS') ||
          rawDialogue.contains('内心OS') ||
          rawDialogue.contains('心声') ||
          rawDialogue.contains('内心独白') ||
          rawDialogue.contains('（OS）') ||
          rawDialogue.contains('(OS)') ||
          rawDialogue.startsWith('OS:') ||
          rawDialogue.startsWith('OS：');

      if (isSystemNotice) {
        sections.add(
          '【声音与画面约束】[浮字特效: 屏幕边缘微弱半透明金色符文或状态提示，无画内气泡与字幕] [画外配音: $rawDialogue，画面主体保持从容闭口神态，无画内文字]',
        );
      } else if (isInnerVoice) {
        sections.add(
          '【声音与画面约束】[角色心声/画外音: "$rawDialogue"，画面主体保持自然闭口与从容微表情，严禁开口嘴型与画内文字]',
        );
      } else {
        sections.add(
          '【声音与画面约束】[画外配音: "$rawDialogue"，画面主体保持自然微表情与闭口神态，严禁开口嘴型与画内文字]',
        );
      }
    } else {
      sections.add('【声音与画面约束】[纯环境声效与背景音轨，画面主体神态自然，画面无台词开口，无画内文字]');
    }

    return sections.join('\n');
  }

  static String compileSegment({
    required StudioSegment segment,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
  }) {
    final shotProseList = <String>[];
    DynamicExitState? carryState;
    final charMap = {for (final c in characters) c.id: c};
    final sceneMap = {for (final s in scenes) s.id: s};

    for (var i = 0; i < shots.length; i++) {
      final shot = shots[i];
      final shotCharacters = shot.characterIds
          .map((id) => charMap[id])
          .whereType<CharacterCard>()
          .toList();
      final char = shotCharacters.isNotEmpty ? shotCharacters.first : null;
      final scene = shot.sceneId.isNotEmpty ? sceneMap[shot.sceneId] : null;

      final shotProse = compileShot(
        shot: shot,
        character: char,
        characters: shotCharacters,
        scene: scene,
        productionType: productionType,
        styleTokens: styleTokens,
        previousExitState: carryState,
      );
      shotProseList.add(
        '【分镜 ${shot.number}（${shot.durationSec}秒）】\n$shotProse',
      );
      carryState = shot.continuity.dynamicExitState;
    }

    return shotProseList.join('\n\n');
  }
}

/// H3 六列 CSV 格式编译器（spec: H3 CSV 规范）。
///
/// 表头必须为：["序号", "图片提示词", "视频提示词", "首帧提示词", "尾帧提示词", "文案"]
/// 编码必须带 UTF-8 BOM，换行符必须为 CRLF (\r\n)。
abstract final class H3CsvCompiler {
  static const List<String> columns = [
    '序号',
    '图片提示词',
    '视频提示词',
    '首帧提示词',
    '尾帧提示词',
    '文案',
  ];

  static String compileCsvString({
    required StudioEpisode episode,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
  }) {
    final buffer = StringBuffer();
    // 表头
    buffer.write(columns.join(','));
    buffer.write('\r\n');

    final charMap = {for (final c in characters) c.id: c};
    final sceneMap = {for (final s in scenes) s.id: s};

    // 如果有片段，按片段输出；否则按分镜输出
    if (episode.segments.isNotEmpty) {
      for (final seg in episode.segments) {
        final segShots = shots.where((s) => s.segmentId == seg.id).toList();
        if (segShots.isEmpty) continue;

        final firstShot = segShots.first;
        final char = firstShot.characterIds.isNotEmpty
            ? charMap[firstShot.characterIds.first]
            : null;
        final scene = firstShot.sceneId.isNotEmpty
            ? sceneMap[firstShot.sceneId]
            : null;

        // 1. 序号
        final index = seg.id.replaceAll(RegExp(r'[^0-9]'), '');
        final seq = index.isNotEmpty ? index : '${segShots.first.number}';

        // 2. 图片提示词 (首镜图片 Prompt)
        final imagePrompt = PromptAssembler.buildShotPrompt(
          PromptParts(
            productionType: productionType,
            styleTokens: styleTokens,
            shotSize: firstShot.shotSize.id,
            mood: firstShot.mood,
            shotFunction: firstShot.function.id,
            character: char,
            scene: scene,
            cameraMove: firstShot.cameraMove,
            actionZh: firstShot.actionZh,
          ),
        ).positive;

        // 3. 视频提示词 (Seedance 或 Photorealistic 视频稿)
        final videoPrompt = SeedanceTaskCompiler.compileSegment(
          segment: seg,
          shots: segShots,
          characters: characters,
          scenes: scenes,
          productionType: productionType,
          styleTokens: styleTokens,
        );

        // 4. 首帧提示词
        const firstFrame = '无';
        // 5. 尾帧提示词
        const lastFrame = '无';

        // 6. 文案 (所有分镜对白汇聚)
        final dialogues = segShots
            .where((s) => s.dialogue.trim().isNotEmpty)
            .map((s) => '镜头${s.number}：${s.dialogue.trim()}')
            .join('\r\n');
        final copyText = dialogues.isNotEmpty ? dialogues : '（纯动作运镜，无台词）';

        final row = [
          _escapeCsv(seq),
          _escapeCsv(imagePrompt),
          _escapeCsv(videoPrompt),
          _escapeCsv(firstFrame),
          _escapeCsv(lastFrame),
          _escapeCsv(copyText),
        ];
        buffer.write(row.join(','));
        buffer.write('\r\n');
      }
    } else {
      // 无片段，逐镜输出
      for (final shot in shots) {
        final char = shot.characterIds.isNotEmpty
            ? charMap[shot.characterIds.first]
            : null;
        final scene = shot.sceneId.isNotEmpty ? sceneMap[shot.sceneId] : null;

        final imagePrompt = PromptAssembler.buildShotPrompt(
          PromptParts(
            productionType: productionType,
            styleTokens: styleTokens,
            shotSize: shot.shotSize.id,
            mood: shot.mood,
            shotFunction: shot.function.id,
            character: char,
            scene: scene,
            cameraMove: shot.cameraMove,
            actionZh: shot.actionZh,
          ),
        ).positive;

        final videoPrompt = PhotorealisticPromptCompiler.compileShot(
          shot: shot,
          character: char,
          scene: scene,
          productionType: productionType,
          styleTokens: styleTokens,
        );

        final dialogue = shot.dialogue.trim().isNotEmpty
            ? shot.dialogue.trim()
            : '（无台词）';

        final row = [
          _escapeCsv('${shot.number}'),
          _escapeCsv(imagePrompt),
          _escapeCsv(videoPrompt),
          _escapeCsv('无'),
          _escapeCsv('无'),
          _escapeCsv(dialogue),
        ];
        buffer.write(row.join(','));
        buffer.write('\r\n');
      }
    }

    return buffer.toString();
  }

  static List<int> compileCsvBytes({
    required StudioEpisode episode,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
    StudioProductionType? productionType,
    String styleTokens = '',
  }) {
    final csv = compileCsvString(
      episode: episode,
      shots: shots,
      characters: characters,
      scenes: scenes,
      productionType: productionType,
      styleTokens: styleTokens,
    );
    // UTF-8 BOM: 0xEF, 0xBB, 0xBF
    return [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
  }

  static String _escapeCsv(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}

/// 一个可选的素材候选项（spec: shot-asset-binding）。
///
/// [isDefault] 标记系统默认项——分镜卡据此显示「自动：<文件名>」，用户可覆盖。
/// 默认规则与生图路径的取材回退同源，因此两条路径不会
/// 再出现「关键帧用三视图、视频用上传图」的分裂。
class AssetMaterialCandidate {
  /// 素材文件名（相对资产目录）。
  final String fileName;

  /// 该候选项的人类可读标签（如「基准三视图」「面部锚点」「上传参考图」）。
  final String label;

  /// 是否为系统默认选用项。
  final bool isDefault;

  const AssetMaterialCandidate({
    required this.fileName,
    required this.label,
    this.isDefault = false,
  });
}

/// 出场资产的素材候选枚举器（spec: shot-asset-binding）。
///
/// 分镜卡用它列出「这个角色/场景有哪些图可以拿来生成」，并标出默认项。
/// 只枚举**磁盘上存在**的文件——列出一个不存在的图会让用户选完后生成才失败。
abstract final class AssetMaterialEnumerator {
  /// 列出角色的可用素材候选，顺序即优先级。
  ///
  /// 优先级与生图路径一致：形态专属三视图 → 角色基准三视图 → Q版三视图 →
  /// 面部锚点 → 用户上传参考图。
  static List<AssetMaterialCandidate> forCharacter(
    CharacterCard character, {
    CharacterVariation? activeVariation,
    required String charDirPath,
  }) {
    final candidates = <AssetMaterialCandidate>[];
    final seen = <String>{};

    void add(String? fileName, String label) {
      if (fileName == null || fileName.trim().isEmpty) return;
      final name = fileName.trim();
      if (!seen.add(name)) return;
      // 只列磁盘上真实存在的图。
      if (!File(p.join(charDirPath, name)).existsSync()) return;
      candidates.add(AssetMaterialCandidate(fileName: name, label: label));
    }

    final v = activeVariation;
    if (v != null) {
      add(v.turnaroundPath, '形态三视图');
      add('turnaround_${v.id}.png', '形态三视图');
      add('turnaround_${v.id}_chibi.png', '形态三视图（Q版）');
      for (final ref in v.referenceImages) {
        add(ref, '形态参考图');
      }
    }
    add('turnaround.png', '基准三视图');
    add('turnaround_chibi.png', '基准三视图（Q版）');
    add(character.faceAnchorPath, '面部锚点');
    for (final ref in character.referenceImages) {
      add(ref, '上传参考图');
    }

    if (candidates.isEmpty) return candidates;
    // 首个存在的候选即系统默认（与 _referenceImages 的返回顺序一致）。
    final first = candidates.first;
    return [
      AssetMaterialCandidate(
        fileName: first.fileName,
        label: first.label,
        isDefault: true,
      ),
      ...candidates.skip(1),
    ];
  }

  /// 列出场景的可用素材候选，顺序即优先级。
  ///
  /// 优先级：有图的七方位视角 → 用户上传参考图。
  static List<AssetMaterialCandidate> forScene(
    SceneCard scene, {
    required String sceneDirPath,
  }) {
    final candidates = <AssetMaterialCandidate>[];
    final seen = <String>{};

    void add(String? fileName, String label) {
      if (fileName == null || fileName.trim().isEmpty) return;
      final name = fileName.trim();
      if (!seen.add(name)) return;
      if (!File(p.join(sceneDirPath, name)).existsSync()) return;
      candidates.add(AssetMaterialCandidate(fileName: name, label: label));
    }

    // 七方位视角按「正面 → 其余」排列：正面是默认机位最可能对应的视角。
    final views = scene.fullSpatialViews;
    for (final dir in SceneDirection.values) {
      final view = views[dir.name];
      if (view == null) continue;
      add(view.imagePath, '${dir.labelZh}视角');
    }
    for (final ref in scene.referenceImages) {
      add(ref, '上传参考图');
    }

    if (candidates.isEmpty) return candidates;
    final first = candidates.first;
    return [
      AssetMaterialCandidate(
        fileName: first.fileName,
        label: first.label,
        isDefault: true,
      ),
      ...candidates.skip(1),
    ];
  }

  /// 取角色或场景的系统默认素材文件名；无可用素材返回 null。
  static String? defaultMaterialFor({
    required bool isScene,
    CharacterCard? character,
    SceneCard? scene,
    CharacterVariation? activeVariation,
    required String assetDirPath,
  }) {
    final candidates = isScene
        ? forScene(scene!, sceneDirPath: assetDirPath)
        : forCharacter(
            character!,
            activeVariation: activeVariation,
            charDirPath: assetDirPath,
          );
    return candidates.isEmpty ? null : candidates.first.fileName;
  }
}

/// 分段用的词数切分：逗号、分号、句号、换行都算边界。
///
/// 时序序列段自带换行结构，按换行切开后每行是一个「词」——这样超限丢弃
/// 的粒度是「一整镜」而不是「半行」，不会出现区间残缺的提示词。
List<String> _promptWordsOf(String text) => text
    .split(RegExp(r'[,\.\n;]+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// 拼段分隔符：块结构段（时序序列）前后用换行，普通段之间用「, 」。
///
/// `_joinWithinLimit` 原来无脑用 ', ' 拼，多行时序段会被压成一行、
/// 甚至和下一段粘在同一行尾（`...跳脚, 声音与画面约束：...`），可读性归零。
///
/// 判据是**段本身**是否含换行，且前后都判：前一段多行说明刚结束一个块，
/// 本段多行说明要起一个新块。只判前一段会让时间轴块接在场景锚点同一行尾，
/// 只判本段会让块后面的单行段粘在块的最后一行上。
String _joinPromptSegments(List<String> segments) {
  final buffer = StringBuffer();
  var previousWasMultiline = false;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i].trim();
    if (segment.isEmpty) continue;
    if (buffer.isNotEmpty) {
      final breakBefore = previousWasMultiline || segment.contains('\n');
      buffer.write(breakBefore ? '\n\n' : ', ');
    }
    buffer.write(segment);
    previousWasMultiline = segment.contains('\n');
  }
  return buffer.toString();
}
