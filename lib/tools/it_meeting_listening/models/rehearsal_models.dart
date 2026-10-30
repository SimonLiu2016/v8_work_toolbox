/// 会议材料排练的数据模型。
///
/// 四层结构，对应四个阶段：
///
/// ```
/// RehearsalMaterial  导入的材料（用户提供）
///   └─ SpeechDraft   Simon 第一人称英文讲稿（按议题分节）
///        └─ MeetingScript   5 角色模拟会议剧本（按回合）
///             └─ Clip   排练会议音频（落进既有素材库）
/// ```
///
/// 前三个阶段各有自己的落盘文件，互不覆盖——讲稿改了剧本要重生成，剧本改了
/// 音频要重烘，但材料始终不变（design D8）。
library;

import '../models/listening_models.dart';

/// 排练会议的固定角色。
///
/// **角色是用户自己定的**（Simon 就是用户本人），不是通用场景，所以枚举写死。
/// [speaker] 是剧本文本里的说话人标识，也是 [SpeakerTurn.speaker] 的值。
enum RehearsalRole {
  simon('simon', 'Simon', '汇报人 · comall'),
  xiaofeng('xiaofeng', 'xiaofeng', '客户主管'),
  songyang('songyang', 'songyang', 'Huawei 合作方'),
  deepan('deepan', 'deepan', '客户方员工'),
  josh('josh', 'Josh', '客户方员工');

  /// 落盘与剧本解析用的稳定标识。
  final String id;

  /// 展示名（剧本里 `Simon:` 冒号前的部分）。
  final String speaker;

  /// 角色说明（供界面提示，也用于给 LLM 的人物设定）。
  final String note;

  const RehearsalRole(this.id, this.speaker, this.note);

  /// 按说话人标识反查；未知标识返回 null（剧本里混入意外角色时）。
  static RehearsalRole? fromSpeaker(String? name) {
    if (name == null) return null;
    final normalized = name.trim().toLowerCase();
    for (final r in RehearsalRole.values) {
      if (r.id == normalized || r.speaker.toLowerCase() == normalized) return r;
    }
    return null;
  }

  /// 是否属于客户方（xiaofeng / deepan / Josh）。
  ///
  /// 客户方在剧本里负责追问与质疑，Huawei 侧负责补充协作进展——这个划分
  /// 是 prompt 的人物设定，也是界面上给用户看的阵营提示。
  bool get isClientSide =>
      this == RehearsalRole.xiaofeng ||
      this == RehearsalRole.deepan ||
      this == RehearsalRole.josh;
}

/// 导入的一份会议材料。
class RehearsalMaterial {
  /// 材料标识（由原始路径与内容哈希派生，同一份文件重复导入得到同一 id）。
  final String id;

  /// 材料标题（取文件名）。
  final String title;

  /// 原始文件路径（出处展示）。
  final String sourcePath;

  /// 原始文件名（出处展示）。
  final String fileName;

  /// 解析后的结构化纯文本（送 LLM 的输入）。
  final String text;

  /// 导入时间。
  final DateTime importedAt;

  /// 用户自定义显示标题（重命名时写入，不修改原始文件；为空时回退到 [title]）。
  final String? displayTitle;

  /// 目标会议时长（分钟，30 或 60；按场独立保存）。
  final int targetMinutes;

  const RehearsalMaterial({
    required this.id,
    required this.title,
    required this.sourcePath,
    required this.fileName,
    required this.text,
    required this.importedAt,
    this.displayTitle,
    this.targetMinutes = 30,
  });

  /// 实际用于展示的标题。
  String get effectiveTitle {
    final custom = displayTitle?.trim();
    return (custom != null && custom.isNotEmpty) ? custom : title;
  }

  /// 解析后文本的字符数。
  int get charCount => text.length;

  RehearsalMaterial copyWith({
    String? title,
    String? displayTitle,
    bool clearDisplayTitle = false,
    int? targetMinutes,
  }) =>
      RehearsalMaterial(
        id: id,
        title: title ?? this.title,
        sourcePath: sourcePath,
        fileName: fileName,
        text: text,
        importedAt: importedAt,
        displayTitle:
            clearDisplayTitle ? null : (displayTitle ?? this.displayTitle),
        targetMinutes: targetMinutes ?? this.targetMinutes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourcePath': sourcePath,
        'fileName': fileName,
        'text': text,
        'importedAt': importedAt.toIso8601String(),
        if (displayTitle != null && displayTitle!.trim().isNotEmpty)
          'displayTitle': displayTitle!.trim(),
        'targetMinutes': targetMinutes,
      };

  factory RehearsalMaterial.fromJson(Map<String, dynamic> json) =>
      RehearsalMaterial(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sourcePath: json['sourcePath'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        text: json['text'] as String? ?? '',
        importedAt:
            DateTime.tryParse(json['importedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        displayTitle: json['displayTitle'] as String?,
        targetMinutes: (json['targetMinutes'] as num?)?.toInt() ?? 30,
      );
}

/// 讲稿的一个议题节。
class DraftSection {
  /// 节标题（议题名）。
  final String title;

  /// 节正文（英文口语讲稿）。
  final String body;

  const DraftSection({required this.title, required this.body});

  Map<String, dynamic> toJson() => {'title': title, 'body': body};

  factory DraftSection.fromJson(Map<String, dynamic> json) => DraftSection(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
}

/// Simon 第一人称的英文汇报讲稿。
class SpeechDraft {
  /// 讲稿标识。
  final String id;

  /// 来源材料标识。
  final String materialId;

  /// 讲稿标题。
  final String title;

  /// 议题节列表（节与音频小节一一对应）。
  final List<DraftSection> sections;

  /// 生成时间。
  final DateTime generatedAt;

  /// 用户手工编辑保存的时间（未编辑过时为 null）。
  final DateTime? editedAt;

  const SpeechDraft({
    required this.id,
    required this.materialId,
    required this.title,
    required this.sections,
    required this.generatedAt,
    this.editedAt,
  });

  /// 是否已被用户手工编辑过。
  bool get isEdited => editedAt != null;

  /// 用户编辑讲稿后生成新版本（生成新的 `id` 并标记 `editedAt`，使旧剧本自动判定为过期）。
  SpeechDraft copyWithEdited({
    String? title,
    List<DraftSection>? sections,
    DateTime? editedAt,
    String? newId,
  }) {
    final now = editedAt ?? DateTime.now();
    final nextId =
        newId ?? '${materialId}_draft_${now.microsecondsSinceEpoch}';
    return SpeechDraft(
      id: nextId,
      materialId: materialId,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      generatedAt: generatedAt,
      editedAt: now,
    );
  }

  /// 讲稿全文（供送 LLM 生成剧本）。
  String get fullText => sections
      .map((s) => s.body.isEmpty ? s.title : '${s.title}\n${s.body}')
      .join('\n\n');

  Map<String, dynamic> toJson() => {
        'id': id,
        'materialId': materialId,
        'title': title,
        'sections': sections.map((s) => s.toJson()).toList(),
        'generatedAt': generatedAt.toIso8601String(),
        if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
      };

  factory SpeechDraft.fromJson(Map<String, dynamic> json) => SpeechDraft(
        id: json['id'] as String? ?? '',
        materialId: json['materialId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sections: ((json['sections'] as List?) ?? const [])
            .map((e) => DraftSection.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        generatedAt:
            DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        editedAt: json['editedAt'] is String
            ? DateTime.tryParse(json['editedAt'] as String)
            : null,
      );
}

/// 会议剧本的一段结构（开场 / 议题推进 / Q&A / 收尾）。
enum ScriptPhase {
  opening('opening', '开场'),
  topics('topics', '议题推进'),
  qa('qa', 'Q&A'),
  closing('closing', '收尾');

  final String id;
  final String label;

  const ScriptPhase(this.id, this.label);

  static ScriptPhase fromId(String? id) {
    for (final p in ScriptPhase.values) {
      if (p.id == id) return p;
    }
    return ScriptPhase.topics;
  }
}

/// 剧本的一轮对话。
class ScriptTurn {
  /// 说话角色。
  final RehearsalRole role;

  /// 台词（英文）。
  final String text;

  /// 所属结构段。
  final ScriptPhase phase;

  /// 该轮在整场音频中的起始毫秒（合成后回填）。
  final int startMs;

  /// 该轮在整场音频中的结束毫秒（合成后回填）。
  final int endMs;

  /// 该轮是否合成失败（失败轮次可单独重试，不毁整场）。
  final bool failed;

  const ScriptTurn({
    required this.role,
    required this.text,
    this.phase = ScriptPhase.topics,
    this.startMs = 0,
    this.endMs = 0,
    this.failed = false,
  });

  int get durationMs => endMs - startMs;

  ScriptTurn copyWith({
    int? startMs,
    int? endMs,
    bool? failed,
  }) =>
      ScriptTurn(
        role: role,
        text: text,
        phase: phase,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        failed: failed ?? this.failed,
      );

  Map<String, dynamic> toJson() => {
        'role': role.id,
        'text': text,
        'phase': phase.id,
        'startMs': startMs,
        'endMs': endMs,
        'failed': failed,
      };

  factory ScriptTurn.fromJson(Map<String, dynamic> json) => ScriptTurn(
        role: RehearsalRole.fromSpeaker(json['role'] as String?) ??
            RehearsalRole.simon,
        text: json['text'] as String? ?? '',
        phase: ScriptPhase.fromId(json['phase'] as String?),
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as bool?) ?? false,
      );
}

/// 5 角色模拟会议剧本。
class MeetingScript {
  /// 剧本标识。
  final String id;

  /// 来源材料标识。
  final String materialId;

  /// 依据的讲稿标识（讲稿改了剧本要重生成）。
  final String draftId;

  /// 场次标题（材料标题 + 会议）。
  final String title;

  /// 轮次列表（顺序即播放顺序）。
  final List<ScriptTurn> turns;

  /// 目标时长（分钟）。生成时给 LLM 的轮次目标由它折算。
  final int targetMinutes;

  /// 生成时间。
  final DateTime generatedAt;

  const MeetingScript({
    required this.id,
    required this.materialId,
    required this.draftId,
    required this.title,
    required this.turns,
    required this.targetMinutes,
    required this.generatedAt,
  });

  MeetingScript copyWith({
    String? title,
    List<ScriptTurn>? turns,
    int? targetMinutes,
  }) =>
      MeetingScript(
        id: id,
        materialId: materialId,
        draftId: draftId,
        title: title ?? this.title,
        turns: turns ?? this.turns,
        targetMinutes: targetMinutes ?? this.targetMinutes,
        generatedAt: generatedAt,
      );

  /// 按语速折算的预估时长（毫秒）。
  ///
  /// 与 [ClipBaker.estimateTurnMs] 同一套系数（英语会议约 150wpm，每词约
  /// 400ms + 600ms 起停开销）——否则生成前后的时长估算不一致，用户没法判断
  /// "剧本够不够长"。
  int get estimatedMs => turns.fold<int>(
      0, (a, t) => a + _estimateTurnMs(t.text));

  /// 时长是否落在 30-60 分钟区间。
  bool get isWithinTargetRange {
    final minutes = estimatedMs / 60000;
    return minutes >= 30 && minutes <= 60;
  }

  /// 出现过的角色（去重，按 [RehearsalRole.values] 顺序）。
  List<RehearsalRole> get rolesPresent {
    final seen = turns.map((t) => t.role).toSet();
    return RehearsalRole.values.where(seen.contains).toList();
  }

  /// 失败轮次数量。
  int get failedCount => turns.where((t) => t.failed).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'materialId': materialId,
        'draftId': draftId,
        'title': title,
        'turns': turns.map((t) => t.toJson()).toList(),
        'targetMinutes': targetMinutes,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory MeetingScript.fromJson(Map<String, dynamic> json) => MeetingScript(
        id: json['id'] as String? ?? '',
        materialId: json['materialId'] as String? ?? '',
        draftId: json['draftId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        turns: ((json['turns'] as List?) ?? const [])
            .map((e) =>
                ScriptTurn.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        targetMinutes: (json['targetMinutes'] as num?)?.toInt() ?? 30,
        generatedAt:
            DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 单轮台词的预估时长（毫秒）。系数与 [ClipBaker.estimateTurnMs] 一致。
int _estimateTurnMs(String text) {
  final words =
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (words == 0) return 800;
  return (words * 400 + 600).clamp(800, 30000);
}

/// 排练条目的阶段与过期状态推导。
enum RehearsalStage {
  materialOnly('① 材料'),
  draftReady('② 讲稿'),
  scriptStale('③ 剧本已过期'),
  scriptReady('③ 剧本'),
  audioReady('● 可收听');

  final String badgeLabel;
  const RehearsalStage(this.badgeLabel);
}

/// 一场排练的聚合摘要（用于多场排练列表排序、状态标记与步骤条推导）。
class RehearsalStatusInfo {
  final RehearsalMaterial material;
  final SpeechDraft? draft;
  final MeetingScript? script;
  final Clip? clip;

  const RehearsalStatusInfo({
    required this.material,
    this.draft,
    this.script,
    this.clip,
  });

  /// 排练对应的素材库 Clip ID（`rehearsal_mat_...`）。
  static String clipIdFor(String materialId) {
    final normalized =
        materialId.startsWith('mat_') ? materialId : 'mat_$materialId';
    return 'rehearsal_$normalized';
  }

  String get clipId => clipIdFor(material.id);

  /// 剧本是否基于旧版讲稿（讲稿编辑保存后 `draft.id` 更新，导致与 `script.draftId` 不一致）。
  bool get isScriptStale =>
      draft != null &&
      script != null &&
      script!.draftId.isNotEmpty &&
      script!.draftId != draft!.id;

  /// 是否已生成可播放的整场语音。
  bool get hasPlayableAudio =>
      clip != null && !clip!.isPlaceholder && clip!.audioPath.isNotEmpty;

  /// 列表与详情使用的阶段枚举。
  RehearsalStage get stage {
    if (isScriptStale) return RehearsalStage.scriptStale;
    if (hasPlayableAudio) return RehearsalStage.audioReady;
    if (script != null) return RehearsalStage.scriptReady;
    if (draft != null) return RehearsalStage.draftReady;
    return RehearsalStage.materialOnly;
  }

  /// 最近修改时间（材料导入 / 讲稿生成 / 讲稿编辑 / 剧本生成 中的最大值）。
  DateTime get lastModifiedAt {
    var latest = material.importedAt;
    final draftGen = draft?.generatedAt;
    if (draftGen != null && draftGen.isAfter(latest)) latest = draftGen;
    final draftEdit = draft?.editedAt;
    if (draftEdit != null && draftEdit.isAfter(latest)) latest = draftEdit;
    final scriptGen = script?.generatedAt;
    if (scriptGen != null && scriptGen.isAfter(latest)) latest = scriptGen;
    return latest;
  }
}

