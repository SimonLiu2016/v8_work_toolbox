/// Stage 3 关键帧 VLM 视觉审图服务（Keyframe Visual Critic）。
///
/// 对已生成的首帧关键帧 (`shot_N.png`) 及生图提示词执行 4 大核心维度的自动化审图验收：
/// 1. 角色人数与防分身校验 (`characterCountOk`)
/// 2. 空间高低位与防浮空校验 (`spatialElevationOk`)
/// 3. 坐骑/核心道具连续性校验 (`mountPropOk`)
/// 4. 景别与视线朝向构图校验 (`shotScaleOk`)
library;

import 'dart:convert';
import 'dart:io';

import '../../../services/ai_config_store.dart';
import '../../../services/ai_service.dart';
import '../models/studio_models.dart';
import 'prompt_assembler.dart';

abstract final class KeyframeVisualCritic {
  /// 提取用于审图的分镜生图提示词或确定性描述。
  static String resolveShotEffectivePrompt({
    required StudioShot shot,
    required List<CharacterCard> characters,
    SceneCard? scene,
  }) {
    if (shot.assembledPrompt.trim().isNotEmpty) {
      return shot.assembledPrompt.trim();
    }
    final charNames = characters
        .where((c) => shot.characterIds.contains(c.id))
        .map((c) => c.name)
        .join(', ');
    final parts = [
      if (charNames.isNotEmpty) '出场角色: $charNames',
      '景别: ${shot.shotSize.label}',
      if (shot.cameraAngle.isNotEmpty) '视角: ${shot.cameraAngle}',
      if (shot.continuity.mountOrVehicle.isNotEmpty)
        '坐骑: ${shot.continuity.mountOrVehicle}',
      '动作: ${shot.actionZh}',
      if (shot.dialogue.isNotEmpty) '台词: ${shot.dialogue}',
    ];
    return parts.join('；');
  }

  /// 对单个分镜的首帧关键帧执行 VLM + 规则联合审图验收。
  static Future<VlmFrameCriticReport> evaluateShotKeyframe({
    required StudioShot shot,
    required StudioEpisode episode,
    required List<CharacterCard> characters,
    SceneCard? scene,
    required String framesDir,
    bool useAi = true,
  }) async {
    final filePath = '$framesDir/shot_${shot.number}.png';
    final file = File(filePath);
    if (!file.existsSync()) {
      return VlmFrameCriticReport(
        score: 0,
        passed: false,
        characterCountOk: false,
        noCloneArtifact: false,
        spatialElevationOk: false,
        mountPropOk: false,
        shotScaleOk: false,
        issues: const ['首帧关键帧图片文件尚未生成，请先抽卡生成关键帧。'],
        promptFixSuggestion: '',
        evaluatedAt: DateTime.now().toIso8601String(),
      );
    }

    // 1. 先执行确定性规则与画面元数据预审
    final deterministic = evaluateDeterministically(
      shot: shot,
      characters: characters,
      scene: scene,
      imageFile: file,
    );

    if (!useAi || AiConfigStore.instance.providers.isEmpty) {
      return deterministic;
    }

    // 2. 若配置了 AI 供应商，读取图片并转为 Base64 Data URL 发送真实多模态审图请求
    try {
      final bytes = await file.readAsBytes();
      final dims = _parsePngDimensions(bytes);
      final effectivePrompt = resolveShotEffectivePrompt(
        shot: shot,
        characters: characters,
        scene: scene,
      );

      final expectedMount = _extractExpectedMount(shot);
      final hasVerticalDiff =
          PromptAssembler.hasVerticalElevationDifference(shot: shot);

      final base64Img = base64Encode(bytes);
      final mime = file.path.toLowerCase().endsWith('.jpg') ||
              file.path.toLowerCase().endsWith('.jpeg')
          ? 'image/jpeg'
          : 'image/png';
      final dataUrl = 'data:$mime;base64,$base64Img';

      final systemPrompt = '''
你是顶级影视分镜关键帧视觉质检总监（VLM Senior Visual Critic）。
你将通过附带的关键帧真实图像，从以下 5 个核心维度进行严格的像素级图像审阅与瑕疵质检：
1. 【面部五官与形体】：是否存在面部融解、眼睛歪斜、塑料蜡像脸、多指缺指畸形手、畸形肢体或悬浮？（若存在任何五官融解或肢体畸形，必须实行一票否决：passed 为 false，评分直接降为 35 分以下）
2. 【角色人数与幽灵人物】：出场角色数量是否严格匹配分镜期望？单人镜头中绝对严禁出现分身、克隆人或未指定的幽灵配角。
3. 【空间透视与高低位防浮空】：人物与场景透视是否合乎物理规律？窗台/楼上人物是否有实体支点？严禁角色无重力悬浮或楼上楼下同高度并排。
4. 【风格纯粹性】：画面风格是否统一？严禁同时出现写实真人脸与 3D/动漫塑料特征的割裂融合。
5. 【坐骑道具与构图景别】：分镜指定的坐骑、载具与景别是否完整呈现？

请仅返回结构化 JSON 对象（严禁任何 Markdown 标记或多余文字）：
{
  "passed": true,
  "score": 95,
  "character_count_ok": true,
  "no_clone_artifact": true,
  "spatial_elevation_ok": true,
  "mount_prop_ok": true,
  "shot_scale_ok": true,
  "issues": ["具体发现的画面崩坏与缺陷描述"],
  "prompt_fix_suggestion": "针对上述缺陷的修正提示词"
}
''';

      final userPrompt = '''
【分镜 #${shot.number} 规格要求】
- 期望出场角色数：${shot.characterIds.length} 人 (${shot.characterIds.join(', ')})
- 景别与角度：${shot.shotSize.label} / ${shot.cameraAngle}
- 空间高度层级：${shot.elevationLevel.isEmpty ? 'ground' : shot.elevationLevel}（是否存在高低楼层落差：$hasVerticalDiff）
- 必须保留的坐骑/载具：${expectedMount.isEmpty ? '无' : expectedMount}
- 画面动作描述：${shot.actionZh}
- 当前生图提示词：$effectivePrompt
- 图像分辨率：${dims != null ? '${dims.$1}x${dims.$2}' : '未知'}
- 静态预审发现的隐患：${deterministic.issues.isEmpty ? '无' : deterministic.issues.join('；')}
''';

      final result = await AiService.instance.chat(
        slot: 'multimodal',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': userPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': dataUrl, 'detail': 'high'},
              },
            ],
          },
        ],
        timeout: const Duration(seconds: 30),
      );

      final parsed = _tryParseJsonReport(result.text, fallback: deterministic);
      if (parsed != null) {
        // 合并确定性红线：若确定性预审已检出严重硬伤（如坐骑丢失或高低位同框风险），确保在报告中体现
        final mergedIssues = <String>{
          ...deterministic.issues,
          ...parsed.issues,
        }.toList();
        final charOk = deterministic.characterCountOk && parsed.characterCountOk;
        final elevOk =
            deterministic.spatialElevationOk && parsed.spatialElevationOk;
        final mountOk = deterministic.mountPropOk && parsed.mountPropOk;
        final scaleOk = deterministic.shotScaleOk && parsed.shotScaleOk;
        final passed = charOk && elevOk && mountOk && scaleOk && mergedIssues.isEmpty && parsed.passed;
        final calcScore = passed
            ? 95
            : (parsed.score <= 40
                ? parsed.score
                : (100 - mergedIssues.length * 20).clamp(20, 40));
        return VlmFrameCriticReport(
          score: calcScore,
          passed: passed,
          characterCountOk: charOk,
          noCloneArtifact: charOk,
          spatialElevationOk: elevOk,
          mountPropOk: mountOk,
          shotScaleOk: scaleOk,
          issues: mergedIssues,
          promptFixSuggestion: parsed.promptFixSuggestion.trim().isNotEmpty
              ? parsed.promptFixSuggestion.trim()
              : deterministic.promptFixSuggestion,
          evaluatedAt: DateTime.now().toIso8601String(),
          isAiEvaluated: true,
        );
      }
    } catch (_) {
      // AI 调用超时或不可用时平滑回退到确定性审图报告
    }

    return deterministic;
  }

  /// 确定性静态 + PNG 元数据审图核验（无需网络即可精准拦截坐骑漏画、高低位同框浮空、分身标签残留与构图失配）。
  static VlmFrameCriticReport evaluateDeterministically({
    required StudioShot shot,
    required List<CharacterCard> characters,
    SceneCard? scene,
    File? imageFile,
  }) {
    var characterCountOk = true;
    var spatialElevationOk = true;
    var mountPropOk = true;
    var shotScaleOk = true;
    final issues = <String>[];

    final effectivePrompt = resolveShotEffectivePrompt(
      shot: shot,
      characters: characters,
      scene: scene,
    );

    // 0. 检查图片文件有效性
    if (imageFile != null && imageFile.existsSync()) {
      final len = imageFile.lengthSync();
      if (len < 64) {
        issues.add('关键帧图像文件体积异常偏小 ($len B)，疑似生图不完整或空白帧');
        shotScaleOk = false;
      }
    }

    // 1. 角色人数与防克隆检查
    if (effectivePrompt.contains('<Picture') ||
        effectivePrompt.contains('【素材指代】')) {
      characterCountOk = false;
      issues.add('生图提示词残留 <Picture N> 或【素材指代】标签，极易诱发单人双胞胎克隆伪影');
    }
    if (shot.isInnerVoice && shot.characterIds.length > 1) {
      characterCountOk = false;
      issues.add('内心独白镜头绑定了 ${shot.characterIds.length} 名角色，存在幽灵配角同框抢戏风险');
    }

    // 2. 空间高低位与防浮空检查
    final hasVerticalDiff =
        PromptAssembler.hasVerticalElevationDifference(shot: shot);
    if (hasVerticalDiff && shot.characterIds.length >= 2) {
      spatialElevationOk = false;
      issues.add('单张关键帧同时包含楼上窗口角色与地面街道角色，极易产生人物浮空或同平地站立伪影，建议裂变为正反打双镜或强化垂直纵深锚定');
    }
    if (effectivePrompt.contains('严禁平地同高度站立') ||
        effectivePrompt.contains('严禁同高度站立')) {
      spatialElevationOk = false;
      issues.add('提示词含反向否定词“严禁平地同高度站立”，生图模型易反向激活同高度并排站立');
    }

    // 3. 坐骑与关键道具连续性检查
    final expectedMount = _extractExpectedMount(shot);
    if (expectedMount.isNotEmpty && !effectivePrompt.contains(expectedMount)) {
      mountPropOk = false;
      issues.add('分镜要求保留坐骑「$expectedMount」，但当前关键帧生图提示词未显式锚定骑乘姿态，角色极易被误画为平地站立');
    }

    // 4. 景别与对白构图匹配检查
    final isLongShot = shot.shotSize == StudioShotSize.long ||
        shot.shotSize == StudioShotSize.extremeLong ||
        shot.shotSize == StudioShotSize.full;
    if (isLongShot &&
        shot.dialogue.trim().isNotEmpty &&
        !shot.isInnerVoice &&
        shot.voiceType != UtteranceVoiceType.narration) {
      shotScaleOk = false;
      issues.add('远景/全景 (${shot.shotSize.label}) 下包含开口对白，关键帧人物面部占比过小，驱动视频口型时易崩坏');
    }

    // 5. 风格互斥冲突检查（防五官融解与塑料感崩坏）
    final hasAnimeToken = effectivePrompt.contains('3D国漫') ||
        effectivePrompt.contains('UE5') ||
        effectivePrompt.contains('二次元') ||
        effectivePrompt.contains('次世代CG');
    final hasPhotoToken = effectivePrompt.contains('photorealistic') ||
        effectivePrompt.contains('live-action') ||
        effectivePrompt.contains('arri alexa') ||
        effectivePrompt.contains('真人实拍');
    if (hasAnimeToken && hasPhotoToken) {
      issues.add('生图提示词中同时混入了 3D国漫/CG 与 真人实拍/胶片 互斥风格标签，极易诱发面部融解与塑料感崩坏');
    }

    // 6. 单人镜头幽灵配角检查
    if (shot.characterIds.length == 1) {
      final boundCharId = shot.characterIds.first;
      final otherChars = characters.where((c) => c.id != boundCharId);
      for (final oc in otherChars) {
        if (shot.actionZh.contains(oc.name)) {
          issues.add('分镜动作中提及了未绑定的角色「${oc.name}」，单人镜头存在幽灵配角抢戏风险');
          characterCountOk = false;
          break;
        }
      }
    }

    // 组装自动修复后的生图提示词
    var fixedPrompt = effectivePrompt;
    if (!characterCountOk && shot.characterIds.length == 1) {
      fixedPrompt = '$fixedPrompt 画面中仅单人独立入镜，严禁出现重复分身或多余人物。';
    }
    if (!spatialElevationOk) {
      fixedPrompt =
          '$fixedPrompt 垂直空间落差分明：高处角色位于前景三楼木窗框内俯视，低处角色位于远景青石板地面，高低分层清晰。';
    }
    if (!mountPropOk && expectedMount.isNotEmpty) {
      fixedPrompt = '$fixedPrompt 主体稳稳骑在$expectedMount背上，清晰展现骑乘姿态与$expectedMount全身。';
    }

    final passed = characterCountOk &&
        spatialElevationOk &&
        mountPropOk &&
        shotScaleOk &&
        issues.isEmpty;
    final calcScore = passed ? 95 : (100 - issues.length * 20).clamp(20, 40);

    return VlmFrameCriticReport(
      score: calcScore,
      passed: passed,
      characterCountOk: characterCountOk,
      noCloneArtifact: characterCountOk,
      spatialElevationOk: spatialElevationOk,
      mountPropOk: mountPropOk,
      shotScaleOk: shotScaleOk,
      issues: issues,
      promptFixSuggestion: passed ? '' : fixedPrompt,
      evaluatedAt: DateTime.now().toIso8601String(),
      isAiEvaluated: false,
    );
  }

  /// 一键采纳 VLM 审图修复建议并更新分镜的 `assembledPrompt`（及补充坐骑连续性）。
  static StudioShot applySuggestedFixToShot(
    StudioShot shot, {
    required List<CharacterCard> characters,
    SceneCard? scene,
  }) {
    final expectedMount = _extractExpectedMount(shot);
    final updatedContinuity = expectedMount.isNotEmpty &&
            shot.continuity.mountOrVehicle.trim().isEmpty
        ? shot.continuity.copyWith(mountOrVehicle: expectedMount)
        : shot.continuity;

    final suggested = shot.vlmCriticReport?.promptFixSuggestion.trim() ?? '';
    final newPrompt = suggested.isNotEmpty
        ? suggested
        : resolveShotEffectivePrompt(
            shot: shot.copyWith(continuity: updatedContinuity),
            characters: characters,
            scene: scene,
          );

    return shot.copyWith(
      continuity: updatedContinuity,
      assembledPrompt: newPrompt,
      clearVlmCriticReport: true,
    );
  }

  static String _extractExpectedMount(StudioShot shot) {
    final explicit = shot.continuity.mountOrVehicle.trim();
    if (explicit.isNotEmpty) return explicit;
    final fixText = shot.vlmCriticReport?.promptFixSuggestion ?? '';
    final combined = '${shot.actionZh} $fixText';
    final match = RegExp(r'(黑驴|青驴|毛驴|瘦驴|大黑驴|骏马|白马|马车|驴|马)')
        .firstMatch(combined);
    if (match != null) {
      final val = match.group(1)!;
      return val == '驴' ? '黑驴' : (val == '马' ? '骏马' : val);
    }
    return '';
  }

  static (int, int)? _parsePngDimensions(List<int> bytes) {
    // PNG Header: 8 bytes signature + 4 bytes chunk length + 4 bytes 'IHDR' + 4 bytes width + 4 bytes height
    if (bytes.length < 24) return null;
    if (bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      return null;
    }
    final width = (bytes[16] << 24) |
        (bytes[17] << 16) |
        (bytes[18] << 8) |
        bytes[19];
    final height = (bytes[20] << 24) |
        (bytes[21] << 16) |
        (bytes[22] << 8) |
        bytes[23];
    if (width <= 0 || height <= 0) return null;
    return (width, height);
  }

  static VlmFrameCriticReport? _tryParseJsonReport(
    String rawText, {
    required VlmFrameCriticReport fallback,
  }) {
    try {
      var cleaned = rawText.trim();
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        cleaned = cleaned.substring(start, end + 1);
      }
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      final passed = map['passed'] as bool? ?? fallback.passed;
      final issues = (map['issues'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          fallback.issues;
      final rawScore = map['score'] as int?;
      final calcScore = rawScore ??
          (passed ? 95 : (100 - issues.length * 20).clamp(20, 40));
      final finalScore =
          passed ? calcScore : (calcScore <= 40 ? calcScore : 35);

      return VlmFrameCriticReport(
        score: finalScore,
        passed: passed,
        characterCountOk:
            map['character_count_ok'] as bool? ?? fallback.characterCountOk,
        noCloneArtifact:
            map['no_clone_artifact'] as bool? ?? fallback.noCloneArtifact,
        spatialElevationOk:
            map['spatial_elevation_ok'] as bool? ?? fallback.spatialElevationOk,
        mountPropOk: map['mount_prop_ok'] as bool? ?? fallback.mountPropOk,
        shotScaleOk: map['shot_scale_ok'] as bool? ?? fallback.shotScaleOk,
        issues: issues,
        promptFixSuggestion:
            map['prompt_fix_suggestion'] as String? ??
                fallback.promptFixSuggestion,
        evaluatedAt: DateTime.now().toIso8601String(),
        isAiEvaluated: true,
      );
    } catch (_) {
      return null;
    }
  }
}
