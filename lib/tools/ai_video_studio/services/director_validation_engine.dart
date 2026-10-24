/// 导演可执行性自动化审计关口（C01~C12 质检引擎）。
///
/// 移植自 modular-drama-director 的工业级视听可执行性核验关口：
/// - C01: 资产真实性与白名单校验
/// - C02: 剧情事实与核心对白保真
/// - C03: 动作攻防因果链与受力物理反馈
/// - C04: 摄影机功能与时长台词负荷
/// - C05: 空间 180° 轴线与地标站位连续性
/// - C06: 镜头时长合理性与事件负荷
/// - C07: 跨片段剪辑接力（Handoff）可操作性
/// - C08: 状态声明真实性与结构完整性
/// - C09: 环境光照世界方向与阴影轴线衔接
/// - C10: 动作过载与运镜互斥质检（5 大视听铁律审计）
library;

import '../models/studio_models.dart';
import 'prompt_assembler.dart';

/// 校验严重级别。
enum ValidationSeverity {
  pass('PASS', '通过'),
  warning('WARNING', '建议优化'),
  blocking('BLOCKING', '严重阻断');

  final String code;
  final String label;

  const ValidationSeverity(this.code, this.label);
}

/// 单条校验异常/提示条目。
class ValidationIssue {
  /// 规则 ID（C01 ~ C09）。
  final String ruleId;

  /// 规则名称。
  final String ruleName;

  /// 严重程度。
  final ValidationSeverity severity;

  /// 涉及的镜号（若适用）。
  final int? shotNumber;

  /// 涉及的片段 ID（若适用）。
  final String? segmentId;

  /// 具体问题描述。
  final String message;

  /// 修复建议。
  final String suggestion;

  const ValidationIssue({
    required this.ruleId,
    required this.ruleName,
    required this.severity,
    this.shotNumber,
    this.segmentId,
    required this.message,
    required this.suggestion,
  });

  Map<String, dynamic> toJson() => {
    'rule_id': ruleId,
    'rule_name': ruleName,
    'severity': severity.code,
    if (shotNumber != null) 'shot_number': shotNumber,
    if (segmentId != null) 'segment_id': segmentId,
    'message': message,
    'suggestion': suggestion,
  };
}

/// 质检报告。
class ValidationReport {
  /// 是否可执行（无 BLOCKING 级错误）。
  final bool isValid;

  /// 所有质检异常条目。
  final List<ValidationIssue> issues;

  final int passCount;
  final int warningCount;
  final int blockingCount;
  final DateTime timestamp;

  const ValidationReport({
    required this.isValid,
    required this.issues,
    required this.passCount,
    required this.warningCount,
    required this.blockingCount,
    required this.timestamp,
  });

  /// 过滤出属于特定镜头的异常条目。
  List<ValidationIssue> issuesForShot(int shotNumber) {
    return issues.where((e) => e.shotNumber == shotNumber).toList();
  }

  /// 属于特定片段的异常条目。
  List<ValidationIssue> issuesForSegment(String segmentId) {
    return issues.where((e) => e.segmentId == segmentId).toList();
  }

  /// 该镜头是否有严重阻断错误。
  bool hasBlockingForShot(int shotNumber) {
    return issues.any(
      (e) => e.shotNumber == shotNumber && e.severity == ValidationSeverity.blocking,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_valid': isValid,
    'pass_count': passCount,
    'warning_count': warningCount,
    'blocking_count': blockingCount,
    'timestamp': timestamp.toIso8601String(),
    'issues': issues.map((e) => e.toJson()).toList(),
  };
}

/// 导演质检引擎实现。
abstract final class DirectorValidationEngine {
  /// 对单集及分镜执行全套 C01~C09 规则自动化审计。
  static ValidationReport validate({
    required StudioEpisode episode,
    required List<StudioShot> shots,
    List<CharacterCard> characters = const [],
    List<SceneCard> scenes = const [],
  }) {
    final issues = <ValidationIssue>[];
    final charIds = characters.map((c) => c.id).toSet();
    final sceneIds = scenes.map((s) => s.id).toSet();

    // -------------------------------------------------------------------------
    // C01: 资产真实性与引用绑定
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      for (final cid in shot.characterIds) {
        if (characters.isNotEmpty && !charIds.contains(cid)) {
          issues.add(ValidationIssue(
            ruleId: 'C01',
            ruleName: '资产真实性',
            severity: ValidationSeverity.warning,
            shotNumber: shot.number,
            message: '分镜引用了未在角色库登记的角色 ID: $cid',
            suggestion: '请在 IP 主库中补建该角色卡，或修正分镜的演员设定。',
          ));
        }
      }
      if (shot.sceneId.isNotEmpty && scenes.isNotEmpty && !sceneIds.contains(shot.sceneId)) {
        issues.add(ValidationIssue(
          ruleId: 'C01',
          ruleName: '资产真实性',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '分镜引用了未在场景库登记的场景 ID: ${shot.sceneId}',
          suggestion: '请在场景库中补充该场景卡，以保证生成画面环境光影一致。',
        ));
      }

      // 内心戏幽灵角色检查：防范仅在心声/独白提及的第三人被误绑定为出场演员
      if (shot.isInnerVoice && shot.characterIds.length > 1) {
        issues.add(ValidationIssue(
          ruleId: 'C01',
          ruleName: '内心戏幽灵角色检查',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '本镜头为内心独白（内心 OS），但绑定了多个出场角色（${shot.characterIds.join(", ")}），存在将心声中提及的第三人误召唤为出场演员的穿帮风险',
          suggestion: '内心独白镜头建议仅保留思考者本人单人出场，将仅在心声中提及的第三人移出 characterIds。',
        ));
      }
    }

    // -------------------------------------------------------------------------
    // C02: 剧情事实与核心对白保真
    // -------------------------------------------------------------------------
    final contract = episode.protectedContract;
    if (contract.isNotEmpty) {
      final allDialogues = shots.map((s) => s.dialogue).join(' ');
      for (final u in contract.utterances) {
        final cleanText = u.text.trim();
        if (cleanText.isNotEmpty && !allDialogues.contains(cleanText)) {
          issues.add(ValidationIssue(
            ruleId: 'C02',
            ruleName: '对白保真',
            severity: ValidationSeverity.warning,
            message: '原著受保护基准对白【${u.speaker}】: "${u.text}" 未在任何分镜对白中出现',
            suggestion: '建议将该句高光对白分配给对应的核心动作或特写镜头，保持小说视听精髓。',
          ));
        }
      }
    }

    // -------------------------------------------------------------------------
    // C03: 连续攻击与物理受力可执行性
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      if (shot.mood == 'battle' || shot.combatSteps.isNotEmpty) {
        if (shot.combatSteps.isEmpty) {
          // 标记了战斗但无具体攻防六步链
          if (shot.actionZh.length < 20 ||
              (!shot.actionZh.contains('避') &&
                  !shot.actionZh.contains('刺') &&
                  !shot.actionZh.contains('挡') &&
                  !shot.actionZh.contains('击') &&
                  !shot.actionZh.contains('闪') &&
                  !shot.actionZh.contains('退') &&
                  !shot.actionZh.contains('倒') &&
                  !shot.actionZh.contains('震'))) {
            issues.add(ValidationIssue(
              ruleId: 'C03',
              ruleName: '动作物理反馈',
              severity: ValidationSeverity.warning,
              shotNumber: shot.number,
              message: '动作戏缺少具体的兵刃交互、受力反馈或位移描述',
              suggestion: '补充受力失衡（如震退三步、火星溅射、重心后倾）等物理反馈，避免回合制摆姿势。',
            ));
          }
        } else {
          // 核对战斗步骤完整性
          for (final step in shot.combatSteps) {
            if (step.impact.trim().isEmpty && step.displacement.trim().isEmpty) {
              issues.add(ValidationIssue(
                ruleId: 'C03',
                ruleName: '动作物理反馈',
                severity: ValidationSeverity.warning,
                shotNumber: shot.number,
                message: '战斗步骤 #${step.stepIndex} 缺少受力反馈 (impact) 与位移 (displacement)',
                suggestion: '请补齐受力撞击物与角色的相对位移变化。',
              ));
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // C04: 摄影机功能与读时负荷（台词字数比）
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      if (shot.actionZh.trim().isEmpty) {
        issues.add(ValidationIssue(
          ruleId: 'C04',
          ruleName: '摄影功能',
          severity: ValidationSeverity.blocking,
          shotNumber: shot.number,
          message: '分镜画面动作描述 (actionZh) 为空',
          suggestion: '每个分镜必须具备明确的视觉画面与主体动作。',
        ));
      }

      // 台词字数负荷核算（每秒最多 5 字，超过 6 字/秒严重阻断）
      final dialogueChars = shot.dialogue
          .replaceAll(RegExp(r'（.*?）'), '')
          .replaceAll(RegExp(r'\(.*?\)'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .length;
      final maxCharsNormal = (shot.durationSec * 5.0).ceil();
      final maxCharsHard = (shot.durationSec * 6.5).ceil();

      if (dialogueChars > maxCharsHard) {
        issues.add(ValidationIssue(
          ruleId: 'C04',
          ruleName: '读时负荷',
          severity: ValidationSeverity.blocking,
          shotNumber: shot.number,
          message: '台词长度 ($dialogueChars 字) 严重超出镜头时长 (${shot.durationSec}秒) 极限负荷',
          suggestion: '请删减台词至 $maxCharsNormal 字以内，或延长该分镜的时长。',
        ));
      } else if (dialogueChars > maxCharsNormal) {
        issues.add(ValidationIssue(
          ruleId: 'C04',
          ruleName: '读时负荷',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '台词语速较快 ($dialogueChars 字 / ${shot.durationSec}秒)，接近播音上限',
          suggestion: '建议控制在 $maxCharsNormal 字以内以留出情绪气口与环境音空间。',
        ));
      }
    }

    // -------------------------------------------------------------------------
    // C05: 空间 180° 轴线与地标突变
    // -------------------------------------------------------------------------
    for (var i = 1; i < shots.length; i++) {
      final prev = shots[i - 1];
      final curr = shots[i];

      // 180° 轴线检测：若前一镜与当前镜头机位站位完全相反且无环绕过渡
      final prevScreen = prev.continuity.screenPosition;
      final currScreen = curr.continuity.screenPosition;
      if (prevScreen.isNotEmpty && currScreen.isNotEmpty) {
        final prevLeft = prevScreen.contains('左');
        final prevRight = prevScreen.contains('右');
        final currLeft = currScreen.contains('左');
        final currRight = currScreen.contains('右');

        // 同一人在相邻镜头中无过渡突然从极左跳到极右且面向翻转
        if (prev.characterIds.isNotEmpty &&
            curr.characterIds.isNotEmpty &&
            prev.characterIds.first == curr.characterIds.first) {
          if ((prevLeft && currRight && !curr.cameraMove.contains('pan') && !curr.cameraMove.contains('orbit')) ||
              (prevRight && currLeft && !curr.cameraMove.contains('pan') && !curr.cameraMove.contains('orbit'))) {
            issues.add(ValidationIssue(
              ruleId: 'C05',
              ruleName: '180°摄影轴线',
              severity: ValidationSeverity.warning,
              shotNumber: curr.number,
              message: '与上一镜头存在可能的 180° 越轴风险（画面朝向左右突变）',
              suggestion: '若要切换视线侧，请在运镜中加入过渡摇臂或中性正面镜头，避免观众空间错位。',
            ));
          }
        }
      }

      // 地标空间连续性
      if (prev.sceneId.isNotEmpty &&
          curr.sceneId.isNotEmpty &&
          prev.sceneId == curr.sceneId) {
        if (prev.continuity.worldPosition.isNotEmpty &&
            curr.continuity.worldPosition.isNotEmpty) {
          // 同一场景内地标突然断层
          final prevPos = prev.continuity.worldPosition;
          final currPos = curr.continuity.worldPosition;
          if (prevPos != currPos &&
              !curr.actionZh.contains('走') &&
              !curr.actionZh.contains('退') &&
              !curr.actionZh.contains('跃') &&
              !curr.actionZh.contains('移') &&
              !curr.actionZh.contains('冲') &&
              curr.directorDecisions.cutReason.isEmpty) {
            issues.add(ValidationIssue(
              ruleId: 'C05',
              ruleName: '空间地标衔接',
              severity: ValidationSeverity.warning,
              shotNumber: curr.number,
              message: '空间世界坐标发生改变 ($prevPos → $currPos) 但未见位移或切镜动机 (cut_reason)',
              suggestion: '在分镜中明确切镜动机，或在动作中增加位移交代。',
            ));
          }
        }
      }

      // 垂直空间海拔与平移运镜逻辑冲突核查
      final elevation = curr.elevationLevel.isNotEmpty
          ? curr.elevationLevel
          : (curr.continuity.worldPosition.contains('二楼') || curr.continuity.worldPosition.contains('楼上')
              ? 'balcony_2f'
              : 'ground');
      final isHighElevation = elevation.contains('balcony') ||
          elevation.contains('rooftop') ||
          elevation.contains('high') ||
          curr.continuity.worldPosition.contains('二楼') ||
          curr.continuity.worldPosition.contains('楼上');
      final isHorizontalPan = curr.cameraMove.toLowerCase().contains('pan right') ||
          curr.cameraMove.toLowerCase().contains('pan left') ||
          curr.cameraMove.contains('平移');
      final mentionsGroundStreet = curr.actionZh.contains('长街') ||
          curr.actionZh.contains('街道') ||
          curr.actionZh.contains('马车') ||
          curr.actionZh.contains('地面') ||
          curr.actionZh.contains('路面');

      if (isHighElevation && isHorizontalPan && mentionsGroundStreet) {
        issues.add(ValidationIssue(
          ruleId: 'C05',
          ruleName: '垂直空间运镜冲突',
          severity: ValidationSeverity.warning,
          shotNumber: curr.number,
          message: '机位处于高位空间（二楼/挑台），单纯水平平移（Pan）物理上无法直接摄入地面街景与马车，存在空间瞬移断层',
          suggestion: '建议将运镜修改为下摇（Tilt Down）俯拍长街，或通过剪辑硬切（Cut to street establishing shot）切换机位。',
        ));
      }

      // 打破第四面墙违规检测
      if (curr.actionZh.contains('对观众') ||
          curr.actionZh.contains('向观众') ||
          curr.actionZh.contains('对镜头说话') ||
          curr.actionZh.contains('向镜头说话')) {
        issues.add(ValidationIssue(
          ruleId: 'C05',
          ruleName: '打破第四面墙警告',
          severity: ValidationSeverity.warning,
          shotNumber: curr.number,
          message: '动作描述中出现人物面对观众/镜头说话，打破第四面墙，导致视线轴线脱离对话对象',
          suggestion: '修改为人物朝向斜上方/斜下方倾听者喊话，保持视听沉浸感。',
        ));
      }
    }

    // -------------------------------------------------------------------------
    // C06: 建议时长与事件负荷
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      if (shot.durationSec < 2.0 || shot.durationSec > 6.0) {
        issues.add(ValidationIssue(
          ruleId: 'C06',
          ruleName: '时长规范',
          severity: ValidationSeverity.blocking,
          shotNumber: shot.number,
          message: '分镜建议时长为 ${shot.durationSec}秒，超出 2.0~6.0 秒工业标准',
          suggestion: '请调整分镜建议时长在 3.0~5.0 秒最佳生成区间内。',
        ));
      }
    }

    // -------------------------------------------------------------------------
    // C07: 跨片段剪辑接力（Handoff 可操作性）
    // -------------------------------------------------------------------------
    if (episode.segments.isNotEmpty && episode.segments.length > 1) {
      for (var sIdx = 1; sIdx < episode.segments.length; sIdx++) {
        final prevSeg = episode.segments[sIdx - 1];
        final currSeg = episode.segments[sIdx];

        final prevLastShotNum = prevSeg.shotNumbers.isNotEmpty ? prevSeg.shotNumbers.last : null;
        final currFirstShotNum = currSeg.shotNumbers.isNotEmpty ? currSeg.shotNumbers.first : null;

        if (prevLastShotNum != null && currFirstShotNum != null) {
          final prevLastShot = shots.firstWhere(
            (s) => s.number == prevLastShotNum,
            orElse: () => shots.first,
          );
          final currFirstShot = shots.firstWhere(
            (s) => s.number == currFirstShotNum,
            orElse: () => shots.last,
          );

          final exitState = prevLastShot.continuity.dynamicExitState;
          if (exitState.isNotEmpty &&
              exitState.unfinishedPhase.contains('冲刺') &&
              currFirstShot.actionZh.contains('静坐')) {
            issues.add(ValidationIssue(
              ruleId: 'C07',
              ruleName: '剪辑接力 Handoff',
              severity: ValidationSeverity.warning,
              segmentId: currSeg.id,
              shotNumber: currFirstShot.number,
              message: '跨片段切点动作矢量突变：前段末尾处于【${exitState.unfinishedPhase}】，本段首镜突变为静态',
              suggestion: '增加惯性卸力或缓冲镜头，确保剪辑接力平滑。',
            ));
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // C08: 状态声明真实性与结构完整性
    // -------------------------------------------------------------------------
    var expectedNumber = 1;
    for (final shot in shots) {
      if (shot.number != expectedNumber) {
        issues.add(ValidationIssue(
          ruleId: 'C08',
          ruleName: '结构完整性',
          severity: ValidationSeverity.blocking,
          shotNumber: shot.number,
          message: '分镜镜号不连续：期望镜号 $expectedNumber，实际为 ${shot.number}',
          suggestion: '请重新按序编排分镜镜号。',
        ));
      }
      expectedNumber++;
    }

    // -------------------------------------------------------------------------
    // C09: 环境光照世界方向与阴影轴线衔接
    // -------------------------------------------------------------------------
    for (var i = 1; i < shots.length; i++) {
      final prev = shots[i - 1];
      final curr = shots[i];
      if (prev.sceneId.isNotEmpty && curr.sceneId.isNotEmpty && prev.sceneId == curr.sceneId) {
        final prevLight = prev.directorDecisions.lightingStaging.isNotEmpty
            ? prev.directorDecisions.lightingStaging
            : prev.continuity.lightingState;
        final currLight = curr.directorDecisions.lightingStaging.isNotEmpty
            ? curr.directorDecisions.lightingStaging
            : curr.continuity.lightingState;

        if (prevLight.isNotEmpty && currLight.isNotEmpty) {
          final prevCold = prevLight.contains('冷') || prevLight.contains('白') || prevLight.contains('蓝');
          final prevWarm = prevLight.contains('暖') || prevLight.contains('黄') || prevLight.contains('火');
          final currCold = currLight.contains('冷') || currLight.contains('白') || currLight.contains('蓝');
          final currWarm = currLight.contains('暖') || currLight.contains('黄') || currLight.contains('火');

          if ((prevCold && !prevWarm && currWarm && !currCold) ||
              (prevWarm && !prevCold && currCold && !currWarm)) {
            issues.add(ValidationIssue(
              ruleId: 'C09',
              ruleName: '环境光影轴线',
              severity: ValidationSeverity.warning,
              shotNumber: curr.number,
              message: '同一场次内连续镜头光影视界色温发生断崖反转 ($prevLight → $currLight)',
              suggestion: '维持主光源物理方位与色温基调，避免生成视频发生光影跳变。',
            ));
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // C10: 动作过载与运镜互斥质检（5 大视听铁律审计）
    // -------------------------------------------------------------------------
    final highActionVerbs = [
      '奔跑', '拔剑', '出招', '转身', '跳跃', '落地', '挥拳', '飞踢', '翻滚', '疾驰', '冲刺', '下潜', '扑击', '劈砍'
    ];
    for (final shot in shots) {
      // 1. 动作堆叠检查
      var actionCount = 0;
      final matchedVerbs = <String>[];
      for (final v in highActionVerbs) {
        if (shot.actionZh.contains(v)) {
          actionCount++;
          matchedVerbs.add(v);
        }
      }
      if (actionCount > 2) {
        issues.add(ValidationIssue(
          ruleId: 'C10',
          ruleName: '动作过载与运镜互斥',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '单镜动作指令堆叠过多（检测到 ${matchedVerbs.join('、')}），超出 6 秒短镜头承载力',
          suggestion: '请拆分为连续微动作镜头（如奔跑停步 -> 拔剑 -> 出招），每镜只保留 1 个核心动词。',
        ));
      }

      // 2. 运镜与机位调度互斥检查
      final move = shot.cameraMove.trim().toLowerCase();
      final staging = shot.directorDecisions.cameraStaging.trim();
      final isDynamicMove = move.contains('push') ||
          move.contains('pan') ||
          move.contains('tilt') ||
          move.contains('zoom') ||
          move.contains('follow') ||
          move.contains('tracking') ||
          move.contains('whip');
      final isStaticStaging = staging.contains('定机位') ||
          staging.contains('固定机位') ||
          staging.contains('机位不动') ||
          staging.contains('静态机位');
      if (isDynamicMove && isStaticStaging) {
        issues.add(ValidationIssue(
          ruleId: 'C10',
          ruleName: '动作过载与运镜互斥',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '运镜调度（${shot.cameraMove}）与摄影调度（$staging）发生动静冲突',
          suggestion: '单镜头只推荐一种运镜规则，若使用动态推镜请移除摄影调度中的“定机位”。',
        ));
      }

      // 3. 幽灵角色与心声检查
      if (shot.isInnerVoice && shot.characterIds.length > 1) {
        for (final cid in shot.characterIds) {
          final charName = characters.where((x) => x.id == cid).firstOrNull?.name ?? cid;
          if (!shot.actionZh.contains(charName) && shot.dialogue.contains(charName)) {
            issues.add(ValidationIssue(
              ruleId: 'C10',
              ruleName: '动作过载与运镜互斥',
              severity: ValidationSeverity.warning,
              shotNumber: shot.number,
              message: '角色「$charName」仅在内心独白中被提及，未在画面微动作肉身在场，疑似幽灵角色',
              suggestion: '请将「$charName」从出场角色中移除，避免视频模型强行生成配角抢戏。',
            ));
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // C11: 因果倒置（反应性台词排在触发动作之前）
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      final dialogue = shot.dialogue.trim();
      if (dialogue.isEmpty) continue;
      // 心声/旁白与画面并行，不参与动作因果排序。
      if (shot.isInnerVoice || shot.voiceType == UtteranceVoiceType.narration) {
        continue;
      }

      final speaker = PromptAssembler.extractSpeakerName(dialogue);
      if (speaker.isEmpty) continue;

      // 判据：说话人不是 actionZh 里第一个出现的角色名。
      // 取 actionZh 中最早出现的角色名作为「首个动作执行者」。
      final action = shot.actionZh;
      String? firstActor;
      var firstActorIdx = -1;
      for (final c in characters) {
        final idx = action.indexOf(c.name);
        if (idx < 0) continue;
        if (firstActorIdx < 0 || idx < firstActorIdx) {
          firstActorIdx = idx;
          firstActor = c.name;
        }
      }
      if (firstActor == null || firstActor == speaker) continue;

      // 说话人不等于首个动作执行者，且没有相位声明 → 大概率倒置。
      // temporalEvolution 非空说明作者已知悉先后，不重复报。
      if (shot.directorDecisions.temporalEvolution.trim().isNotEmpty) continue;

      issues.add(ValidationIssue(
        ruleId: 'C11',
        ruleName: '因果倒置',
        severity: ValidationSeverity.warning,
        shotNumber: shot.number,
        message: '台词说话人「$speaker」不是本镜首个动作的执行者「$firstActor」，'
            '且未声明时间相位，视频模型极可能把台词演在触发动作之前',
        suggestion: '请将「$speaker」的反应台词拆分到「$firstActor」动作之后的独立分镜，'
            '或在五维导演决策的 temporal_evolution 中显式声明两者先后'
            '（例如“前2.0秒$firstActor动作，后1.5秒$speaker反应”）。',
      ));
    }

    // -------------------------------------------------------------------------
    // C12: 场景指涉冲突（动作里的场景名词 vs 关联场景卡）
    // -------------------------------------------------------------------------
    for (final shot in shots) {
      if (shot.sceneId.isEmpty) continue;
      final scene = scenes.where((sc) => sc.id == shot.sceneId).firstOrNull;
      if (scene == null) continue;

      final sceneText = '${scene.name} ${scene.descriptionZh}';
      for (final noun in _sceneNounLexicon) {
        if (!shot.actionZh.contains(noun)) continue;
        // 名词已被场景卡自身描述覆盖 → 不冲突。
        if (sceneText.contains(noun)) continue;
        issues.add(ValidationIssue(
          ruleId: 'C12',
          ruleName: '场景指涉冲突',
          severity: ValidationSeverity.warning,
          shotNumber: shot.number,
          message: '动作描述含场景名词「$noun」，但本镜关联的场景卡是「${scene.name}」，'
              '二者描述的不是同一个空间',
          suggestion: '二选一：把动作改成「${scene.name}」内可发生的动作，'
              '或把本镜改绑到含「$noun」的场景卡。',
        ));
        // 一个分镜只报最突出的那个名词，避免刷屏。
        break;
      }
    }

    final blockingCount = issues.where((e) => e.severity == ValidationSeverity.blocking).length;
    final warningCount = issues.where((e) => e.severity == ValidationSeverity.warning).length;
    final passCount = 10 - (blockingCount > 0 ? 1 : 0) - (warningCount > 0 ? 1 : 0);

    return ValidationReport(
      isValid: blockingCount == 0,
      issues: issues,
      passCount: passCount < 0 ? 0 : passCount,
      warningCount: warningCount,
      blockingCount: blockingCount,
      timestamp: DateTime.now(),
    );
  }
}

/// C12 用的场景名词枚举表（spec: 动作中的场景名词与关联场景卡不符时警告）。
///
/// 刻意用「名词表 + 包含匹配」而不是语义相似度：后者要引模型或词向量，成本与
/// 不确定性都过高。这张表覆盖古装/现代高频场景的绝大多数真实案例，漏报的后果
/// 只是回到现状（不拦），误报也允许用户忽略——两头都不会比现在更差。
const List<String> _sceneNounLexicon = [
  '衙门', '大堂', '正厅', '客厅', '牢房', '大牢', '地牢', '天牢', '刑房',
  '街道', '长街', '大街', '小巷', '巷口', '路口', '城门口', '城门',
  '客栈', '酒楼', '茶馆', '酒肆', '商铺', '当铺', '医馆',
  '书房', '卧室', '寝宫', '后院', '前厅', '花园', '假山',
  '山顶', '山腰', '悬崖', '山谷', '森林', '竹林', '河边', '湖畔', '江边',
  '屋顶', '二楼', '三楼', '楼上', '楼下', '楼梯', '走廊', '回廊',
  '考场', '校场', '军营', '帐内', '帐篷', '船舱', '甲板', '车厢', '马车',
];
