/// 模块化漫剧导演体系数据合同 (Drama Director Contract)。
///
/// 移植并原生实现了 `modular-drama-director` 工业级导演体系：
/// 1. 剧本场次与节拍 (DramaScene & DramaBeat)
/// 2. 原著事实与核心对白保护清单 (ProtectedContract)
/// 3. 五维导演决策矩阵 (DirectorDecisions)
/// 4. Combat DNA 与动作六步攻防接力链 (CombatDNA & CombatGroup & CombatStep)
library;

import 'package:flutter/foundation.dart' show immutable;

/// 事实与设定来源级别
enum FactSourceType {
  /// 原文硬事实：原著中直接描写的人物状态、动作事件或场景细节，绝对不可改动。
  fact('FACT', '原文事实'),

  /// 合理推断：基于原著逻辑自然推导出的补充因果，非无依据凭空捏造。
  inference('INFERENCE', '合理推断'),

  /// 导演创作选择：为镜头视听呈现与戏剧张力所做的影视化专业选择。
  directorChoice('DIRECTOR_CHOICE', '导演选择');

  final String code;
  final String label;

  const FactSourceType(this.code, this.label);

  static FactSourceType fromCode(String? code) {
    if (code == null) return directorChoice;
    final normalized = code.trim().toUpperCase();
    return values.firstWhere(
      (e) => e.code == normalized,
      orElse: () => directorChoice,
    );
  }
}

/// 受保护的剧本事实条目。
@immutable
class ProtectedFact {
  final String id;
  final FactSourceType type;
  final String content;
  final String sourceLocation;
  final bool mandatory;

  const ProtectedFact({
    required this.id,
    this.type = FactSourceType.fact,
    required this.content,
    this.sourceLocation = '',
    this.mandatory = true,
  });

  ProtectedFact copyWith({
    String? id,
    FactSourceType? type,
    String? content,
    String? sourceLocation,
    bool? mandatory,
  }) {
    return ProtectedFact(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      mandatory: mandatory ?? this.mandatory,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.code,
    'content': content,
    'source_location': sourceLocation,
    'mandatory': mandatory,
  };

  static ProtectedFact fromJson(Map<String, dynamic> json) {
    return ProtectedFact(
      id: json['id'] as String? ?? '',
      type: FactSourceType.fromCode(json['type'] as String?),
      content: json['content'] as String? ?? '',
      sourceLocation: json['source_location'] as String? ?? '',
      mandatory: json['mandatory'] as bool? ?? true,
    );
  }
}

/// 发声类型（对白 / 心声 / 旁白）。
enum UtteranceVoiceType {
  dialogue('dialogue', '角色对白'),
  innerVoice('inner_voice', '心声独白'),
  narration('narration', '画外旁白');

  final String id;
  final String label;

  const UtteranceVoiceType(this.id, this.label);

  static UtteranceVoiceType fromId(String? id) {
    if (id == null) return dialogue;
    final normalized = id.trim().toLowerCase();
    return values.firstWhere(
      (e) => e.id == normalized,
      orElse: () => dialogue,
    );
  }
}

/// 锁定基准对白条目（Utterance）。
///
/// 必须逐字保留原著高光金句，防止 AI 拆镜时随意吞掉对白或改换措辞。
@immutable
class ProtectedUtterance {
  final String id;
  final String speaker;
  final String listener;
  final String text;
  final UtteranceVoiceType voiceType;
  final double estimatedSec;
  final int? assignedShotNumber;

  const ProtectedUtterance({
    required this.id,
    required this.speaker,
    this.listener = '',
    required this.text,
    this.voiceType = UtteranceVoiceType.dialogue,
    this.estimatedSec = 2.0,
    this.assignedShotNumber,
  });

  ProtectedUtterance copyWith({
    String? id,
    String? speaker,
    String? listener,
    String? text,
    UtteranceVoiceType? voiceType,
    double? estimatedSec,
    int? assignedShotNumber,
  }) {
    return ProtectedUtterance(
      id: id ?? this.id,
      speaker: speaker ?? this.speaker,
      listener: listener ?? this.listener,
      text: text ?? this.text,
      voiceType: voiceType ?? this.voiceType,
      estimatedSec: estimatedSec ?? this.estimatedSec,
      assignedShotNumber: assignedShotNumber ?? this.assignedShotNumber,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'speaker': speaker,
    'listener': listener,
    'text': text,
    'voice_type': voiceType.id,
    'estimated_sec': estimatedSec,
    if (assignedShotNumber != null) 'assigned_shot_number': assignedShotNumber,
  };

  static ProtectedUtterance fromJson(Map<String, dynamic> json) {
    return ProtectedUtterance(
      id: json['id'] as String? ?? '',
      speaker: json['speaker'] as String? ?? '',
      listener: json['listener'] as String? ?? '',
      text: json['text'] as String? ?? '',
      voiceType: UtteranceVoiceType.fromId(json['voice_type'] as String?),
      estimatedSec: (json['estimated_sec'] as num?)?.toDouble() ?? 2.0,
      assignedShotNumber: (json['assigned_shot_number'] as num?)?.toInt(),
    );
  }
}

/// 剧本事实与对白保护清单（Protected Contract）。
@immutable
class ProtectedContract {
  final List<ProtectedFact> facts;
  final List<ProtectedUtterance> utterances;
  final List<String> protectedBeats;

  const ProtectedContract({
    this.facts = const [],
    this.utterances = const [],
    this.protectedBeats = const [],
  });

  static const ProtectedContract empty = ProtectedContract();

  bool get isEmpty => facts.isEmpty && utterances.isEmpty && protectedBeats.isEmpty;
  bool get isNotEmpty => !isEmpty;

  ProtectedContract copyWith({
    List<ProtectedFact>? facts,
    List<ProtectedUtterance>? utterances,
    List<String>? protectedBeats,
  }) {
    return ProtectedContract(
      facts: facts ?? this.facts,
      utterances: utterances ?? this.utterances,
      protectedBeats: protectedBeats ?? this.protectedBeats,
    );
  }

  Map<String, dynamic> toJson() => {
    'facts': facts.map((e) => e.toJson()).toList(),
    'utterances': utterances.map((e) => e.toJson()).toList(),
    'protected_beats': protectedBeats,
  };

  static ProtectedContract fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return ProtectedContract(
      facts: (json['facts'] as List?)
              ?.whereType<Map>()
              .map((e) => ProtectedFact.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      utterances: (json['utterances'] as List?)
              ?.whereType<Map>()
              .map((e) => ProtectedUtterance.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      protectedBeats: (json['protected_beats'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// 戏剧节拍（Drama Beat）。一个节拍包含一个连续的可见行为或情绪剧变。
@immutable
class DramaBeat {
  final String id;
  final String sceneId;
  final int order;
  final String name;
  final String action;
  final String dramaticFunction;
  final List<int> shotNumbers;
  final String dialogue;
  final String dialogueSpeaker;
  final String subtext;
  final List<String> characterIds;
  final UtteranceVoiceType voiceType;
  final double estimatedSec;
  final String shotSize;
  final String cameraStaging;
  final String cameraMove;
  final String screenPosition;
  final String gazeDirection;
  final String mountOrVehicle;
  final List<String> props;
  final String holdingItem;
  final String holdingHand;

  const DramaBeat({
    required this.id,
    required this.sceneId,
    required this.order,
    this.name = '',
    this.action = '',
    this.dramaticFunction = '',
    this.shotNumbers = const [],
    this.dialogue = '',
    this.dialogueSpeaker = '',
    this.voiceType = UtteranceVoiceType.dialogue,
    this.subtext = '',
    this.characterIds = const [],
    this.estimatedSec = 0.0,
    this.shotSize = '',
    this.cameraStaging = '',
    this.cameraMove = '',
    this.screenPosition = '',
    this.gazeDirection = '',
    this.mountOrVehicle = '',
    this.props = const [],
    this.holdingItem = '',
    this.holdingHand = '',
  });

  DramaBeat copyWith({
    String? id,
    String? sceneId,
    int? order,
    String? name,
    String? action,
    String? dramaticFunction,
    List<int>? shotNumbers,
    String? dialogue,
    String? dialogueSpeaker,
    UtteranceVoiceType? voiceType,
    String? subtext,
    List<String>? characterIds,
    double? estimatedSec,
    String? shotSize,
    String? cameraStaging,
    String? cameraMove,
    String? screenPosition,
    String? gazeDirection,
    String? mountOrVehicle,
    List<String>? props,
    String? holdingItem,
    String? holdingHand,
  }) {
    return DramaBeat(
      id: id ?? this.id,
      sceneId: sceneId ?? this.sceneId,
      order: order ?? this.order,
      name: name ?? this.name,
      action: action ?? this.action,
      dramaticFunction: dramaticFunction ?? this.dramaticFunction,
      shotNumbers: shotNumbers ?? this.shotNumbers,
      dialogue: dialogue ?? this.dialogue,
      dialogueSpeaker: dialogueSpeaker ?? this.dialogueSpeaker,
      voiceType: voiceType ?? this.voiceType,
      subtext: subtext ?? this.subtext,
      characterIds: characterIds ?? this.characterIds,
      estimatedSec: estimatedSec ?? this.estimatedSec,
      shotSize: shotSize ?? this.shotSize,
      cameraStaging: cameraStaging ?? this.cameraStaging,
      cameraMove: cameraMove ?? this.cameraMove,
      screenPosition: screenPosition ?? this.screenPosition,
      gazeDirection: gazeDirection ?? this.gazeDirection,
      mountOrVehicle: mountOrVehicle ?? this.mountOrVehicle,
      props: props ?? this.props,
      holdingItem: holdingItem ?? this.holdingItem,
      holdingHand: holdingHand ?? this.holdingHand,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'scene_id': sceneId,
    'order': order,
    'name': name,
    'action': action,
    'dramatic_function': dramaticFunction,
    'shot_numbers': shotNumbers,
    if (dialogue.isNotEmpty) 'dialogue': dialogue,
    if (dialogueSpeaker.isNotEmpty) 'dialogue_speaker': dialogueSpeaker,
    if (voiceType != UtteranceVoiceType.dialogue) 'voice_type': voiceType.id,
    if (subtext.isNotEmpty) 'subtext': subtext,
    if (characterIds.isNotEmpty) 'character_ids': characterIds,
    if (estimatedSec > 0) 'estimated_sec': estimatedSec,
    if (shotSize.isNotEmpty) 'shot_size': shotSize,
    if (cameraStaging.isNotEmpty) 'camera_staging': cameraStaging,
    if (cameraMove.isNotEmpty) 'camera_move': cameraMove,
    if (screenPosition.isNotEmpty) 'screen_position': screenPosition,
    if (gazeDirection.isNotEmpty) 'gaze_direction': gazeDirection,
    if (mountOrVehicle.isNotEmpty) 'mount_or_vehicle': mountOrVehicle,
    if (props.isNotEmpty) 'props': props,
    if (holdingItem.isNotEmpty) 'holding_item': holdingItem,
    if (holdingHand.isNotEmpty) 'holding_hand': holdingHand,
  };

  static DramaBeat fromJson(Map<String, dynamic> json) {
    return DramaBeat(
      id: json['id'] as String? ?? '',
      sceneId: json['scene_id'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? '',
      action: json['action'] as String? ?? '',
      dramaticFunction: json['dramatic_function'] as String? ?? '',
      shotNumbers: (json['shot_numbers'] as List?)?.cast<int>() ?? const [],
      dialogue: json['dialogue'] as String? ?? '',
      dialogueSpeaker: json['dialogue_speaker'] as String? ?? '',
      voiceType: UtteranceVoiceType.fromId((json['voice_type'] ?? json['voiceType']) as String?),
      subtext: json['subtext'] as String? ?? '',
      characterIds: (json['character_ids'] as List?)?.cast<String>() ?? const [],
      estimatedSec: (json['estimated_sec'] as num?)?.toDouble() ?? 0.0,
      shotSize: (json['shot_size'] ?? json['shotSize']) as String? ?? '',
      cameraStaging: (json['camera_staging'] ?? json['cameraStaging']) as String? ?? '',
      cameraMove: (json['camera_move'] ?? json['cameraMove']) as String? ?? '',
      screenPosition: (json['screen_position'] ?? json['screenPosition']) as String? ?? '',
      gazeDirection: (json['gaze_direction'] ?? json['gazeDirection']) as String? ?? '',
      mountOrVehicle: (json['mount_or_vehicle'] ?? json['mountOrVehicle']) as String? ?? '',
      props: (json['props'] as List?)?.cast<String>() ?? const [],
      holdingItem: (json['holding_item'] ?? json['holdingItem']) as String? ?? '',
      holdingHand: (json['holding_hand'] ?? json['holdingHand']) as String? ?? '',
    );
  }
}

/// 戏剧场次（Drama Scene）。
@immutable
class DramaScene {
  final String id;
  final int sceneNumber;
  final String title;
  final String location;
  final String setting; // 内景 / 外景
  final String timeOfDay; // 日景 / 夜景 / 黄昏 / 黎明
  final String atmosphere;
  final String primaryLightWorldDirection;
  final List<String> landmarks;
  final List<String> characterIds;
  final String dramaticObjective;
  final String entryState;
  final String exitState;
  final List<DramaBeat> beats;
  /// 绑定的场景库资产卡片 ID（SceneCard.id），用于在分镜中直接继承并绑定场景库环境提示词与参考图。
  final String sceneCardId;

  const DramaScene({
    required this.id,
    this.sceneNumber = 1,
    required this.title,
    this.location = '',
    this.setting = '内景',
    this.timeOfDay = '',
    this.atmosphere = '',
    this.primaryLightWorldDirection = '',
    this.landmarks = const [],
    this.characterIds = const [],
    this.dramaticObjective = '',
    this.entryState = '',
    this.exitState = '',
    this.beats = const [],
    this.sceneCardId = '',
  });

  DramaScene copyWith({
    String? id,
    int? sceneNumber,
    String? title,
    String? location,
    String? setting,
    String? timeOfDay,
    String? atmosphere,
    String? primaryLightWorldDirection,
    List<String>? landmarks,
    List<String>? characterIds,
    String? dramaticObjective,
    String? entryState,
    String? exitState,
    List<DramaBeat>? beats,
    String? sceneCardId,
  }) {
    return DramaScene(
      id: id ?? this.id,
      sceneNumber: sceneNumber ?? this.sceneNumber,
      title: title ?? this.title,
      location: location ?? this.location,
      setting: setting ?? this.setting,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      atmosphere: atmosphere ?? this.atmosphere,
      primaryLightWorldDirection:
          primaryLightWorldDirection ?? this.primaryLightWorldDirection,
      landmarks: landmarks ?? this.landmarks,
      characterIds: characterIds ?? this.characterIds,
      dramaticObjective: dramaticObjective ?? this.dramaticObjective,
      entryState: entryState ?? this.entryState,
      exitState: exitState ?? this.exitState,
      beats: beats ?? this.beats,
      sceneCardId: sceneCardId ?? this.sceneCardId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'scene_number': sceneNumber,
    'title': title,
    'location': location,
    if (sceneCardId.isNotEmpty) 'scene_card_id': sceneCardId,
    'setting': setting,
    'time_of_day': timeOfDay,
    if (atmosphere.isNotEmpty) 'atmosphere': atmosphere,
    'primary_light_world_direction': primaryLightWorldDirection,
    'landmarks': landmarks,
    if (characterIds.isNotEmpty) 'character_ids': characterIds,
    'dramatic_objective': dramaticObjective,
    'entry_state': entryState,
    'exit_state': exitState,
    'beats': beats.map((b) => b.toJson()).toList(),
  };

  static DramaScene fromJson(Map<String, dynamic> json) {
    return DramaScene(
      id: json['id'] as String? ?? '',
      sceneNumber: (json['scene_number'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      location: json['location'] as String? ?? '',
      setting: json['setting'] as String? ?? '内景',
      timeOfDay: json['time_of_day'] as String? ?? '',
      atmosphere: json['atmosphere'] as String? ?? '',
      primaryLightWorldDirection: json['primary_light_world_direction'] as String? ?? '',
      landmarks: (json['landmarks'] as List?)?.cast<String>() ?? const [],
      characterIds: (json['character_ids'] as List?)?.cast<String>() ?? const [],
      dramaticObjective: json['dramatic_objective'] as String? ?? '',
      entryState: json['entry_state'] as String? ?? '',
      exitState: json['exit_state'] as String? ?? '',
      sceneCardId: json['scene_card_id'] as String? ?? '',
      beats: (json['beats'] as List?)
              ?.whereType<Map>()
              .map((e) => DramaBeat.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
    );
  }

  /// 将场次与节拍序列化导出为标准影视文学分场 Markdown 剧本。
  static String exportToMarkdown(List<DramaScene> scenes) {
    final buffer = StringBuffer();
    for (final s in scenes) {
      buffer.writeln('### 第${s.sceneNumber}场 ${s.title}（${s.setting} / ${s.timeOfDay} / ${s.location}）');
      if (s.atmosphere.isNotEmpty) {
        buffer.writeln('> 氛围光影：${s.atmosphere}');
      }
      buffer.writeln();
      for (final b in s.beats) {
        buffer.writeln('**【节拍 ${b.order}：${b.name}】**');
        buffer.writeln('画面动作：${b.action}');
        if (b.dialogue.isNotEmpty) {
          if (b.voiceType == UtteranceVoiceType.innerVoice) {
            final speaker = b.dialogueSpeaker.isNotEmpty ? b.dialogueSpeaker : '角色';
            buffer.writeln('心声（$speaker · 内心 OS）：${b.dialogue}');
          } else if (b.voiceType == UtteranceVoiceType.narration) {
            buffer.writeln('旁白：${b.dialogue}');
          } else {
            buffer.writeln('对白（${b.dialogueSpeaker.isNotEmpty ? b.dialogueSpeaker : '角色'}）：${b.dialogue}');
          }
        }
        if (b.subtext.isNotEmpty) {
          buffer.writeln('潜台词：*${b.subtext}*');
        }
        buffer.writeln();
      }
      buffer.writeln('---');
      buffer.writeln();
    }
    return buffer.toString();
  }
}

/// 连续性台账契约（Continuity Ledger）。
///
/// 维护空间坐标、屏幕机位朝向、视线朝向（gazeDirection）、机位俯仰（cameraAngle）、空间海拔（elevationLevel）
/// 与镜尾动态相态（dynamicExitState）。
@immutable
class ContinuityLedger {
  final String worldPosition;
  final String screenPosition;
  final String holdingLeft;
  final String holdingRight;
  final String lightingState;
  final List<String> stateChanges;
  final String gazeDirection;
  final String cameraAxis;
  final String cameraAngle;
  final String elevationLevel;
  final String gazeTarget;
  final DynamicExitState dynamicExitState;

  const ContinuityLedger({
    this.worldPosition = '',
    this.screenPosition = '',
    this.holdingLeft = '',
    this.holdingRight = '',
    this.lightingState = '',
    this.stateChanges = const [],
    this.gazeDirection = '',
    this.cameraAxis = '',
    this.cameraAngle = '',
    this.elevationLevel = '',
    this.gazeTarget = '',
    this.dynamicExitState = DynamicExitState.empty,
  });

  static const ContinuityLedger empty = ContinuityLedger();

  bool get isEmpty =>
      worldPosition.isEmpty &&
      screenPosition.isEmpty &&
      holdingLeft.isEmpty &&
      holdingRight.isEmpty &&
      lightingState.isEmpty &&
      stateChanges.isEmpty &&
      gazeDirection.isEmpty &&
      cameraAxis.isEmpty &&
      cameraAngle.isEmpty &&
      elevationLevel.isEmpty &&
      gazeTarget.isEmpty &&
      dynamicExitState.isEmpty;

  bool get isNotEmpty => !isEmpty;

  ContinuityLedger copyWith({
    String? worldPosition,
    String? screenPosition,
    String? holdingLeft,
    String? holdingRight,
    String? lightingState,
    List<String>? stateChanges,
    String? gazeDirection,
    String? cameraAxis,
    String? cameraAngle,
    String? elevationLevel,
    String? gazeTarget,
    DynamicExitState? dynamicExitState,
  }) {
    return ContinuityLedger(
      worldPosition: worldPosition ?? this.worldPosition,
      screenPosition: screenPosition ?? this.screenPosition,
      holdingLeft: holdingLeft ?? this.holdingLeft,
      holdingRight: holdingRight ?? this.holdingRight,
      lightingState: lightingState ?? this.lightingState,
      stateChanges: stateChanges ?? this.stateChanges,
      gazeDirection: gazeDirection ?? this.gazeDirection,
      cameraAxis: cameraAxis ?? this.cameraAxis,
      cameraAngle: cameraAngle ?? this.cameraAngle,
      elevationLevel: elevationLevel ?? this.elevationLevel,
      gazeTarget: gazeTarget ?? this.gazeTarget,
      dynamicExitState: dynamicExitState ?? this.dynamicExitState,
    );
  }

  Map<String, dynamic> toJson() => {
    'world_position': worldPosition,
    'screen_position': screenPosition,
    'holding_left': holdingLeft,
    'holding_right': holdingRight,
    'lighting_state': lightingState,
    'state_changes': stateChanges,
    if (gazeDirection.isNotEmpty) 'gaze_direction': gazeDirection,
    if (cameraAxis.isNotEmpty) 'camera_axis': cameraAxis,
    if (cameraAngle.isNotEmpty) 'camera_angle': cameraAngle,
    if (elevationLevel.isNotEmpty) 'elevation_level': elevationLevel,
    if (gazeTarget.isNotEmpty) 'gaze_target': gazeTarget,
    if (dynamicExitState.isNotEmpty)
      'dynamic_exit_state': dynamicExitState.toJson(),
  };

  static ContinuityLedger fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return ContinuityLedger(
      worldPosition: json['world_position'] as String? ?? '',
      screenPosition: json['screen_position'] as String? ?? '',
      holdingLeft: json['holding_left'] as String? ?? '',
      holdingRight: json['holding_right'] as String? ?? '',
      lightingState: json['lighting_state'] as String? ?? '',
      stateChanges:
          (json['state_changes'] as List?)?.cast<String>() ?? const [],
      gazeDirection: json['gaze_direction'] as String? ?? '',
      cameraAxis: json['camera_axis'] as String? ?? '',
      cameraAngle: json['camera_angle'] as String? ?? '',
      elevationLevel: json['elevation_level'] as String? ?? '',
      gazeTarget: json['gaze_target'] as String? ?? '',
      dynamicExitState: json['dynamic_exit_state'] is Map
          ? DynamicExitState.fromJson(
              (json['dynamic_exit_state'] as Map).map((k, v) => MapEntry(k as String, v)))
          : DynamicExitState.empty,
    );
  }
}

/// 五维导演决策矩阵（Director Decisions）。
@immutable
class DirectorDecisions {
  /// 主体与物理动势（视觉焦点、重心位置、力量释放与受力反馈）。
  final String physicalMomentum;

  /// 环境与空间光影（固定主光源世界方向、受光与阴影动态变化）。
  final String lightingStaging;

  /// 光学与摄影调度（摄影机四段式：起始运动、跟随对象、触发条件、落点动势，轴线关系）。
  final String cameraStaging;

  /// 时间与状态演变（真实读时、动作相位：起手/接触/余势、留白）。
  final String temporalEvolution;

  /// 美学介质与风格质感（渲染质感、粒子/微尘、色彩温度）。
  final String aestheticTexture;

  /// 切镜动机（为什么在这里切镜头，观众获取什么新信息）。
  final String cutReason;

  /// 本镜主要视觉任务。
  final String visualTask;

  /// 机位俯仰角（如 high_angle 俯拍、low_angle 仰拍、eye_level 平视）。
  final String cameraAngle;

  /// 视线朝向向量描述（如 looking down at street below at -35 degree angle）。
  final String gazeDirection;

  const DirectorDecisions({
    this.physicalMomentum = '',
    this.lightingStaging = '',
    this.cameraStaging = '',
    this.temporalEvolution = '',
    this.aestheticTexture = '',
    this.cutReason = '',
    this.visualTask = '',
    this.cameraAngle = '',
    this.gazeDirection = '',
  });

  static const DirectorDecisions empty = DirectorDecisions();

  bool get isEmpty =>
      physicalMomentum.isEmpty &&
      lightingStaging.isEmpty &&
      cameraStaging.isEmpty &&
      temporalEvolution.isEmpty &&
      aestheticTexture.isEmpty &&
      cutReason.isEmpty &&
      visualTask.isEmpty &&
      cameraAngle.isEmpty &&
      gazeDirection.isEmpty;

  bool get isNotEmpty => !isEmpty;

  DirectorDecisions copyWith({
    String? physicalMomentum,
    String? lightingStaging,
    String? cameraStaging,
    String? temporalEvolution,
    String? aestheticTexture,
    String? cutReason,
    String? visualTask,
    String? cameraAngle,
    String? gazeDirection,
  }) {
    return DirectorDecisions(
      physicalMomentum: physicalMomentum ?? this.physicalMomentum,
      lightingStaging: lightingStaging ?? this.lightingStaging,
      cameraStaging: cameraStaging ?? this.cameraStaging,
      temporalEvolution: temporalEvolution ?? this.temporalEvolution,
      aestheticTexture: aestheticTexture ?? this.aestheticTexture,
      cutReason: cutReason ?? this.cutReason,
      visualTask: visualTask ?? this.visualTask,
      cameraAngle: cameraAngle ?? this.cameraAngle,
      gazeDirection: gazeDirection ?? this.gazeDirection,
    );
  }

  Map<String, dynamic> toJson() => {
    'physical_momentum': physicalMomentum,
    'lighting_staging': lightingStaging,
    'camera_staging': cameraStaging,
    'temporal_evolution': temporalEvolution,
    'aesthetic_texture': aestheticTexture,
    'cut_reason': cutReason,
    'visual_task': visualTask,
    if (cameraAngle.isNotEmpty) 'camera_angle': cameraAngle,
    if (gazeDirection.isNotEmpty) 'gaze_direction': gazeDirection,
  };

  static DirectorDecisions fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return DirectorDecisions(
      physicalMomentum: json['physical_momentum'] as String? ?? '',
      lightingStaging: json['lighting_staging'] as String? ?? '',
      cameraStaging: json['camera_staging'] as String? ?? '',
      temporalEvolution: json['temporal_evolution'] as String? ?? '',
      aestheticTexture: json['aesthetic_texture'] as String? ?? '',
      cutReason: json['cut_reason'] as String? ?? '',
      visualTask: json['visual_task'] as String? ?? '',
      cameraAngle: json['camera_angle'] as String? ?? '',
      gazeDirection: json['gaze_direction'] as String? ?? '',
    );
  }
}

/// 角色的 Combat DNA。
@immutable
class CombatDNA {
  final String characterName;
  final String weightClass;
  final String speedAgility;
  final String preferredDistance;
  final String weapon;
  final String defenseStyle;
  final String counterPreference;

  const CombatDNA({
    required this.characterName,
    this.weightClass = '中量健壮',
    this.speedAgility = '迅疾敏捷',
    this.preferredDistance = '中近距离',
    this.weapon = '',
    this.defenseStyle = '格挡反击',
    this.counterPreference = '寻隙突刺',
  });

  Map<String, dynamic> toJson() => {
    'character_name': characterName,
    'weight_class': weightClass,
    'speed_agility': speedAgility,
    'preferred_distance': preferredDistance,
    'weapon': weapon,
    'defense_style': defenseStyle,
    'counter_preference': counterPreference,
  };

  static CombatDNA fromJson(Map<String, dynamic> json) {
    return CombatDNA(
      characterName: json['character_name'] as String? ?? '',
      weightClass: json['weight_class'] as String? ?? '中量健壮',
      speedAgility: json['speed_agility'] as String? ?? '迅疾敏捷',
      preferredDistance: json['preferred_distance'] as String? ?? '中近距离',
      weapon: json['weapon'] as String? ?? '',
      defenseStyle: json['defense_style'] as String? ?? '格挡反击',
      counterPreference: json['counter_preference'] as String? ?? '寻隙突刺',
    );
  }
}

/// 动作镜头职责枚举。
enum CombatShotDuty {
  threatBuild('threat_build', '威胁建立'),
  attackPath('attack_path', '攻击路径'),
  impact('impact', '接触与交互'),
  forceReaction('force_reaction', '受力失衡'),
  displacement('displacement', '位移反馈'),
  nextRelay('next_relay', '下一招接力');

  final String id;
  final String label;

  const CombatShotDuty(this.id, this.label);

  static CombatShotDuty fromId(String? id) {
    if (id == null) return attackPath;
    final normalized = id.trim().toLowerCase();
    return values.firstWhere(
      (e) => e.id == normalized,
      orElse: () => attackPath,
    );
  }
}

/// 动作六步攻防链单步（Combat Step）。
@immutable
class CombatStep {
  final int stepIndex;
  final String actorName;
  final List<String> targetNames;
  final String intent;
  final String attack;
  final String defense;
  final String impact;
  final String displacement;
  final String nextLink;
  final CombatShotDuty duty;
  final int? shotNumber;

  const CombatStep({
    required this.stepIndex,
    required this.actorName,
    this.targetNames = const [],
    this.intent = '',
    required this.attack,
    this.defense = '',
    this.impact = '',
    this.displacement = '',
    this.nextLink = '',
    this.duty = CombatShotDuty.attackPath,
    this.shotNumber,
  });

  Map<String, dynamic> toJson() => {
    'step_index': stepIndex,
    'actor_name': actorName,
    'target_names': targetNames,
    'intent': intent,
    'attack': attack,
    'defense': defense,
    'impact': impact,
    'displacement': displacement,
    'next_link': nextLink,
    'duty': duty.id,
    if (shotNumber != null) 'shot_number': shotNumber,
  };

  static CombatStep fromJson(Map<String, dynamic> json) {
    return CombatStep(
      stepIndex: (json['step_index'] as num?)?.toInt() ?? 1,
      actorName: json['actor_name'] as String? ?? '',
      targetNames: (json['target_names'] as List?)?.cast<String>() ?? const [],
      intent: json['intent'] as String? ?? '',
      attack: json['attack'] as String? ?? '',
      defense: json['defense'] as String? ?? '',
      impact: json['impact'] as String? ?? '',
      displacement: json['displacement'] as String? ?? '',
      nextLink: json['next_link'] as String? ?? '',
      duty: CombatShotDuty.fromId(json['duty'] as String?),
      shotNumber: (json['shot_number'] as num?)?.toInt(),
    );
  }
}

/// 连续攻击组（Combat Group）。
/// 通常由 3~4 个接力动作组成，上一招余势未尽，下一招反制或变线已经启动。
@immutable
class CombatGroup {
  final String id;
  final String name;
  final String entryState;
  final List<CombatStep> steps;
  final String exitAnchor;

  const CombatGroup({
    required this.id,
    required this.name,
    this.entryState = '',
    this.steps = const [],
    this.exitAnchor = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'entry_state': entryState,
    'steps': steps.map((s) => s.toJson()).toList(),
    'exit_anchor': exitAnchor,
  };

  static CombatGroup fromJson(Map<String, dynamic> json) {
    return CombatGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      entryState: json['entry_state'] as String? ?? '',
      steps: (json['steps'] as List?)
              ?.whereType<Map>()
              .map((e) => CombatStep.fromJson(e.map((k, v) => MapEntry(k as String, v))))
              .toList() ??
          const [],
      exitAnchor: json['exit_anchor'] as String? ?? '',
    );
  }
}

/// 镜头出口的动态末态（Dynamic Exit State）。
///
/// 解决视频生成中“前一镜冲刺、后一镜突然站定”的运动不连续断层问题。
/// 记录支撑脚平衡、运动速度矢量与未完成动作相位。
@immutable
class DynamicExitState {
  /// 支撑平衡状态（例如：“右脚前跨踏实支撑”、“双脚腾空跃起”、“左膝跪地失衡”）。
  final String supportFoot;

  /// 运动速度与矢量方向（例如：“以约3m/s向前冲刺”、“受冲击向后倒滑”）。
  final String velocityVector;

  /// 动作未完成相位（例如：“长剑刚刺破木门尚未拔出”、“双手握刀正处于下劈中途”）。
  final String unfinishedPhase;

  const DynamicExitState({
    this.supportFoot = '',
    this.velocityVector = '',
    this.unfinishedPhase = '',
  });

  static const DynamicExitState empty = DynamicExitState();

  bool get isEmpty =>
      supportFoot.isEmpty && velocityVector.isEmpty && unfinishedPhase.isEmpty;
  bool get isNotEmpty => !isEmpty;

  DynamicExitState copyWith({
    String? supportFoot,
    String? velocityVector,
    String? unfinishedPhase,
  }) {
    return DynamicExitState(
      supportFoot: supportFoot ?? this.supportFoot,
      velocityVector: velocityVector ?? this.velocityVector,
      unfinishedPhase: unfinishedPhase ?? this.unfinishedPhase,
    );
  }

  Map<String, dynamic> toJson() => {
    'support_foot': supportFoot,
    'velocity_vector': velocityVector,
    'unfinished_phase': unfinishedPhase,
  };

  static DynamicExitState fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    return DynamicExitState(
      supportFoot: json['support_foot'] as String? ?? '',
      velocityVector: json['velocity_vector'] as String? ?? '',
      unfinishedPhase: json['unfinished_phase'] as String? ?? '',
    );
  }

  /// 格式化为注入生图与生视频 Prompt 的动态接力锚点描述
  String toPromptAnchor() {
    final parts = [
      if (supportFoot.isNotEmpty) '支撑: $supportFoot',
      if (velocityVector.isNotEmpty) '动势: $velocityVector',
      if (unfinishedPhase.isNotEmpty) '相位: $unfinishedPhase',
    ];
    return parts.join('；');
  }
}
