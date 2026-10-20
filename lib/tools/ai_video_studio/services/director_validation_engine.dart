/// 导演可执行性自动化审计关口（C01~C09 质检引擎）。
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
library;

import '../models/studio_models.dart';

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

    final blockingCount = issues.where((e) => e.severity == ValidationSeverity.blocking).length;
    final warningCount = issues.where((e) => e.severity == ValidationSeverity.warning).length;
    final passCount = 9 - (blockingCount > 0 ? 1 : 0) - (warningCount > 0 ? 1 : 0);

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
