/// IT 会议听力工具的数据模型。
///
/// 三层结构：
/// - [MeetingScene] 会议场景（站会 / 故障排查 / …），是浏览与连续播放的分组单位
/// - [SpeakerTurn] 说话人轮次，一段对话的最小合成单位
/// - [Clip] 片段，一个 1-3 分钟的会议对话音频及其配套文稿
library;

/// 会议场景分类。
///
/// **只收录真实研发会议场景**——通用英语内容（四六级、雅思、日常闲聊）不在此列。
/// 场景是浏览与连续播放的分组单位，不是语言等级。
enum MeetingScene {
  standup('standup', '站会', 'Daily Standup'),
  incident('incident', '故障排查会', 'Incident / Outage'),
  sprintPlanning('sprint-planning', '迭代规划与复盘', 'Sprint Planning / Retrospective'),
  codeReview('code-review', '代码评审', 'Code Review'),
  architecture('architecture', '架构评审', 'Architecture Review'),
  roundtable('roundtable', '圆桌技术讨论', 'Roundtable / Panel'),
  stakeholder('stakeholder', '干系人同步', 'Stakeholder Sync'),
  jobInterview('job-interview', '面试', 'Job Interview'),
  onboarding('onboarding', '新人入职', 'Onboarding Call'),
  productDemo('product-demo', '产品演示', 'Product Demo'),
  techTalk('tech-talk', '技术演讲', 'Tech Talk'),
  technicalInterview('technical-interview', '技术面试', 'Technical Interview'),

  /// 用户材料生成的排练会议（30-60 分钟整场）。
  ///
  /// 与上面的场景**不同源**：上面的内容来自站点抓取，这个来自用户自己导入的
  /// 会议材料。它出现在同一个场景列表里，靠 `sourceId == 'rehearsal'` 区分。
  rehearsal('rehearsal', '排练会议', 'Rehearsal Meeting'),

  /// 用户导入的真实会议逐字稿（整场）。
  ///
  /// 与 [rehearsal] 的区别是**内容来源**：排练会议是模型按材料演的，真实会议
  /// 是别人真开过的会。它不受 1-3 分钟片段约束——整场一条音频 + 按轮时间戳，
  /// 因为用户要听懂的是那场会本身，切碎会打散说话人关系（spec: 碎片化片段与
  /// 时长上限 已把该约束收窄到站点素材）。
  realMeeting('real-meeting', '真实会议', 'Real Meeting');

  /// 稳定标识，落盘时使用，不随展示名变化。
  final String id;

  /// 中文展示名。
  final String label;

  /// 英文展示名（对应 CoderSlingo 侧的场景名，便于交叉核对）。
  final String labelEn;

  const MeetingScene(this.id, this.label, this.labelEn);

  /// 按标识反查；未知标识回落 [standup]。
  static MeetingScene fromId(String? id) {
    for (final s in MeetingScene.values) {
      if (s.id == id) return s;
    }
    return MeetingScene.standup;
  }
}

/// 说话人轮次。
///
/// 一个轮次是**一段音频的合成单位**。原始文本用于文稿展示，清洗后的文本用于
/// 语音合成——两者分开保存，因为清洗只作用于送入合成的副本。
class SpeakerTurn {
  /// 说话人标识（如 "Lena"）。同一说话人在不同片段中必须映射到同一音色。
  final String speaker;

  /// 角色标注（如 "Scrum Master"）。可为空。
  final String role;

  /// 原始文本（来自源站点的逐字内容）。
  final String rawText;

  /// 清洗后文本（送入 TTS 的副本）。破折号等已在此处规范化。
  final String synthesisText;

  /// 实际使用的音色标识。
  final String voice;

  /// 该轮在片段音频中的起始毫秒。
  final int startMs;

  /// 该轮在片段音频中的结束毫秒。
  final int endMs;

  const SpeakerTurn({
    required this.speaker,
    required this.role,
    required this.rawText,
    required this.synthesisText,
    required this.voice,
    this.startMs = 0,
    this.endMs = 0,
  });

  /// 该轮的时长（毫秒）。
  int get durationMs => endMs - startMs;

  /// 展示用署名："Lena (Scrum Master)" / "Lena"。
  String get displayName {
    if (role.isEmpty) return speaker;
    return '$speaker ($role)';
  }

  SpeakerTurn copyWith({
    String? speaker,
    String? role,
    String? rawText,
    String? synthesisText,
    String? voice,
    int? startMs,
    int? endMs,
  }) {
    return SpeakerTurn(
      speaker: speaker ?? this.speaker,
      role: role ?? this.role,
      rawText: rawText ?? this.rawText,
      synthesisText: synthesisText ?? this.synthesisText,
      voice: voice ?? this.voice,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'role': role,
        'rawText': rawText,
        'synthesisText': synthesisText,
        'voice': voice,
        'startMs': startMs,
        'endMs': endMs,
      };

  factory SpeakerTurn.fromJson(Map<String, dynamic> json) => SpeakerTurn(
        speaker: json['speaker'] as String? ?? '',
        role: json['role'] as String? ?? '',
        rawText: json['rawText'] as String? ?? '',
        synthesisText: json['synthesisText'] as String? ?? '',
        voice: json['voice'] as String? ?? '',
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
      );
}

/// 素材出处。
///
/// CoderSlingo 的内容以 CC-BY 4.0 提供。出处 MUST 随素材一起落盘并在界面展示，
/// 但素材本身 MUST NOT 随应用分发。
class ClipSource {
  /// **来源站点稳定标识**（如 "coderslingo"）。
  ///
  /// 与 [site]（展示名）分开：展示名可能重名或改名，标识符不能变——
  /// 它是素材 id 的组成部分，也是多来源下区分素材的依据。
  final String sourceId;

  /// 来源站点展示名（如 "CoderSlingo"）。
  final String site;

  /// 原文页面地址。
  final String pageUrl;

  /// 来源栏目名。
  final String column;

  /// 许可标识（如 "CC BY 4.0"）。
  final String license;

  const ClipSource({
    required this.sourceId,
    required this.site,
    required this.pageUrl,
    required this.column,
    this.license = 'CC BY 4.0',
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'site': site,
        'pageUrl': pageUrl,
        'column': column,
        'license': license,
      };

  factory ClipSource.fromJson(Map<String, dynamic> json) => ClipSource(
        // 旧数据没有 sourceId —— 缺省为 coderslingo（首版唯一来源）。
        sourceId: json['sourceId'] as String? ?? 'coderslingo',
        site: json['site'] as String? ?? '',
        pageUrl: json['pageUrl'] as String? ?? '',
        column: json['column'] as String? ?? '',
        license: json['license'] as String? ?? 'CC BY 4.0',
      );
}

/// 一个会议对话片段。
///
/// 音频与文稿分离落盘：音频是 `<id>.mp3`，文稿清单是 `<id>.json`。清单里的
/// 轮次时间戳是精听模式逐句高亮、术语收藏记录时间点的依据。
class Clip {
  /// 片段标识（同时是音频与文稿文件名的主干）。
  final String id;

  /// 所属场景。
  final MeetingScene scene;

  /// 片段标题。
  final String title;

  /// 音频文件相对路径（相对素材目录）。
  final String audioPath;

  /// 片段总时长（毫秒）。
  final int durationMs;

  /// 轮次列表。
  final List<SpeakerTurn> turns;

  /// 出处。
  final ClipSource source;

  /// 一句话摘要（议题 + 结论）。烘焙阶段生成，离线可用。
  final String summary;

  const Clip({
    required this.id,
    required this.scene,
    required this.title,
    required this.audioPath,
    required this.durationMs,
    required this.turns,
    required this.source,
    this.summary = '',
  });

  /// 说话人数（去重）。
  int get speakerCount => turns.map((t) => t.speaker).toSet().length;

  /// 片段是否为「烘焙失败」的占位（无音频）。
  bool get isPlaceholder => audioPath.isEmpty;

  Clip copyWith({
    String? id,
    MeetingScene? scene,
    String? title,
    String? audioPath,
    int? durationMs,
    List<SpeakerTurn>? turns,
    ClipSource? source,
    String? summary,
  }) {
    return Clip(
      id: id ?? this.id,
      scene: scene ?? this.scene,
      title: title ?? this.title,
      audioPath: audioPath ?? this.audioPath,
      durationMs: durationMs ?? this.durationMs,
      turns: turns ?? this.turns,
      source: source ?? this.source,
      summary: summary ?? this.summary,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scene': scene.id,
        'title': title,
        'audioPath': audioPath,
        'durationMs': durationMs,
        'turns': turns.map((t) => t.toJson()).toList(),
        'source': source.toJson(),
        'summary': summary,
      };

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: json['id'] as String? ?? '',
        scene: MeetingScene.fromId(json['scene'] as String?),
        title: json['title'] as String? ?? '',
        audioPath: json['audioPath'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        turns: ((json['turns'] as List?) ?? const [])
            .map((e) => SpeakerTurn.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        source: ClipSource.fromJson(
            Map<String, dynamic>.from((json['source'] as Map?) ?? const {})),
        summary: json['summary'] as String? ?? '',
      );
}

/// 素材库索引。
///
/// 索引是全量覆盖写入的：烘焙一批素材后，索引描述当前素材库的全部片段。
/// 索引缺失或损坏时，素材库应降级为空列表而不是崩溃。
class ClipIndex {
  /// 索引版本号，便于将来做结构演进。
  final int version;

  /// 全部片段。
  final List<Clip> clips;

  /// 索引生成时间。
  final DateTime? generatedAt;

  const ClipIndex({
    this.version = 1,
    this.clips = const [],
    this.generatedAt,
  });

  /// 按场景分组的片段。
  Map<MeetingScene, List<Clip>> get byScene {
    final map = <MeetingScene, List<Clip>>{};
    for (final scene in MeetingScene.values) {
      map[scene] = [];
    }
    for (final clip in clips) {
      map[clip.scene]!.add(clip);
    }
    return map;
  }

  /// 按 id 查找片段。
  Clip? byId(String id) {
    for (final c in clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'generatedAt': generatedAt?.toIso8601String(),
        'clips': clips.map((c) => c.toJson()).toList(),
      };

  factory ClipIndex.fromJson(Map<String, dynamic> json) => ClipIndex(
        version: (json['version'] as num?)?.toInt() ?? 1,
        clips: ((json['clips'] as List?) ?? const [])
            .map((e) => Clip.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      );
}
