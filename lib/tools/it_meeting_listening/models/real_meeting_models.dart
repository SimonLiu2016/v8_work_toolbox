/// 真实会议逐字稿的数据模型。
///
/// **四层结构，各有独立的落盘文件**（design D2）：
///
/// ```
/// RealMeeting     原稿：说话人槽位 + 轮次 + 原稿时间戳。导入后只读
///   SpeakerSetting  覆盖层：槽位 → 显示名 / 音色 / 是否"我"。可整层删除
///   InsertedAnswer  回答层：锚点轮 + 英文 + 中文原文 + 音频。可逐条增删
///   BakeState       合成状态：续句分组 + 每组音频与时长。派生数据，删了重烘
/// ```
///
/// **为什么原稿只读**：改名、插回答、改音色都是高频且可撤销的操作。若它们
/// 写回原稿，"重新导入一份改过的文稿"就只能整体覆盖，用户设定的名字与回答
/// 一起丢。分开存之后，原稿替换与用户设置互不影响。
///
/// **为什么合成状态单独存**：TTS 合成出的时长与原稿时间戳无关（原稿是会议
/// 记录系统按真实录音转写的时间，而音频是重新合成的）。把两者混在一个字段里，
/// 重建音频时无法判断哪个是"原稿的"、哪个是"合成出来的"。
library;

/// 说话人槽位（原稿里的「发言人 N」）。
///
/// 槽位由导入时解析得到，之后不再变化。它**不代表真实人数**——实测样例里
/// 6 个槽位可能只对应 4 个人，也可能一个人被拆成两个槽位。系统不做自动
/// 合并，只把"用同一音色"的选择权交给用户。
class SpeakerSlot {
  /// 槽位标识（如「发言人 1」），与文稿原文逐字一致。
  final String id;

  /// 该槽位在文稿中出现的轮次数。
  final int turnCount;

  const SpeakerSlot({required this.id, required this.turnCount});

  Map<String, dynamic> toJson() => {'id': id, 'turnCount': turnCount};

  factory SpeakerSlot.fromJson(Map<String, dynamic> json) => SpeakerSlot(
        id: json['id'] as String? ?? '',
        turnCount: (json['turnCount'] as num?)?.toInt() ?? 0,
      );
}

/// 一轮原始发言。
///
/// `timestampMs` 是**原稿时间戳**（会议记录系统给的），不是合成音频里的位置。
/// 两者数值通常差很多：原稿里一段 7 秒的发言，TTS 念出来可能只有 4 秒。
class MeetingTurn {
  /// 在会议中的顺序下标（0 起）。
  final int index;

  /// 所属说话人槽位标识。
  final String slotId;

  /// 原稿时间戳（毫秒）。
  final int timestampMs;

  /// 原始正文，逐字保留。
  final String text;

  const MeetingTurn({
    required this.index,
    required this.slotId,
    required this.timestampMs,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'slotId': slotId,
        'timestampMs': timestampMs,
        'text': text,
      };

  factory MeetingTurn.fromJson(Map<String, dynamic> json) => MeetingTurn(
        index: (json['index'] as num?)?.toInt() ?? 0,
        slotId: json['slotId'] as String? ?? '',
        timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
        text: json['text'] as String? ?? '',
      );
}

/// 一场导入的真实会议（原稿）。
class RealMeeting {
  /// 会议标识，只由来源路径派生。
  ///
  /// **不含内容哈希**：同一份文稿改了几个字还是同一场会，用户的改名、音色与
  /// 已插入的回答都该继续挂在它身上。内容是否变化由 [contentHash] 单独记录并
  /// 比较——两者分开，才能既保持标识稳定、又识别出"文稿被更新过"。
  final String id;

  /// 会议标题（文稿一级标题）。
  final String title;

  /// 来源文件路径。
  final String sourcePath;

  /// 来源文件名（出处展示）。
  final String fileName;

  /// 文稿内容哈希（十六进制前 16 位），用于判定"内容是否变化"。
  final String contentHash;

  /// 原稿声明的转写时长（毫秒）。文稿没有该字段时为 0。
  final int declaredDurationMs;

  /// 「关键词」段的词列表。
  ///
  /// 它是会议记录系统自己产出的**真术语白名单**，词汇表用它把低频真词与
  /// 转写噪声区分开（design D6）——比在线词典可靠，且离线可用。
  final List<String> keywords;

  /// 说话人槽位（按首次出现顺序）。
  final List<SpeakerSlot> slots;

  /// 全部轮次（顺序即播放顺序）。
  final List<MeetingTurn> turns;

  /// 导入时间。
  final DateTime importedAt;

  const RealMeeting({
    required this.id,
    required this.title,
    required this.sourcePath,
    required this.fileName,
    required this.contentHash,
    required this.declaredDurationMs,
    required this.keywords,
    required this.slots,
    required this.turns,
    required this.importedAt,
  });

  /// 槽位标识集合。
  Set<String> get slotIds => slots.map((s) => s.id).toSet();

  /// 按槽位取轮次。
  List<MeetingTurn> turnsOf(String slotId) =>
      turns.where((t) => t.slotId == slotId).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourcePath': sourcePath,
        'fileName': fileName,
        'contentHash': contentHash,
        'declaredDurationMs': declaredDurationMs,
        'keywords': keywords,
        'slots': slots.map((s) => s.toJson()).toList(),
        'turns': turns.map((t) => t.toJson()).toList(),
        'importedAt': importedAt.toIso8601String(),
      };

  factory RealMeeting.fromJson(Map<String, dynamic> json) => RealMeeting(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        sourcePath: json['sourcePath'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        contentHash: json['contentHash'] as String? ?? '',
        declaredDurationMs: (json['declaredDurationMs'] as num?)?.toInt() ?? 0,
        keywords: ((json['keywords'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        slots: ((json['slots'] as List?) ?? const [])
            .map((e) =>
                SpeakerSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        turns: ((json['turns'] as List?) ?? const [])
            .map((e) =>
                MeetingTurn.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        importedAt: DateTime.tryParse(json['importedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 一个说话人槽位的设定（覆盖层）。
///
/// 三项都可缺省：`displayName` 为空表示用槽位默认名，`voiceId` 为空表示用
/// 散列兜底音色，`isMe` 表示该槽位就是用户本人。
class SpeakerSetting {
  /// 显示名。空串表示"未设定"，回落到槽位标识。
  final String displayName;

  /// 音色标识。空串表示"未设定"，回落到散列兜底。
  final String voiceId;

  /// 是否把该槽位标记为"我"（用「我的身份」的显示名与音色）。
  final bool isMe;

  const SpeakerSetting({
    this.displayName = '',
    this.voiceId = '',
    this.isMe = false,
  });

  /// 是否为空设定（三项都是默认值）。
  bool get isDefault =>
      displayName.isEmpty && voiceId.isEmpty && isMe == false;

  SpeakerSetting copyWith({
    String? displayName,
    String? voiceId,
    bool? isMe,
  }) =>
      SpeakerSetting(
        displayName: displayName ?? this.displayName,
        voiceId: voiceId ?? this.voiceId,
        isMe: isMe ?? this.isMe,
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'voiceId': voiceId,
        'isMe': isMe,
      };

  factory SpeakerSetting.fromJson(Map<String, dynamic> json) => SpeakerSetting(
        displayName: json['displayName'] as String? ?? '',
        voiceId: json['voiceId'] as String? ?? '',
        isMe: (json['isMe'] as bool?) ?? false,
      );
}

/// 一场会议的全部说话人设定。
///
/// 整层可删除：删掉等价于"这两场会是别人导入的、我不认识这些人"。
class MeetingSpeakerSettings {
  /// 槽位标识 → 设定。
  final Map<String, SpeakerSetting> bySlot;

  /// 自定义会议显示名。空串表示"未设定"，回落到文稿标题。
  ///
  /// 文稿标题常是导出件自动生成的（`智能纪要：新录音 2026年10月8日`），
  /// 用户需要给它起个自己认得出来的名字。与说话人改名同一套约定：
  /// 覆盖层持久化，原稿一个字不动，清空即回落。
  final String displayTitle;

  /// 合并映射：被合并的槽位 → 目标槽位。
  ///
  /// 同一人常以多种写法出现（`李嘉成` / `嘉成`）。合并是**用户的解释**，
  /// 不是文稿的事实——所以放在覆盖层里，原稿的槽位标识一个字都不动。
  /// 取消合并 = 删掉一个映射项。
  final Map<String, String> mergeInto;

  const MeetingSpeakerSettings({
    this.bySlot = const {},
    this.mergeInto = const {},
    this.displayTitle = '',
  });

  /// 折叠到目标槽位（支持 A→B→C 的链式合并，带环保护）。
  String canonical(String slotId) {
    var current = slotId;
    var guard = 0;
    while (guard++ < 8) {
      final next = mergeInto[current];
      if (next == null || next == current) break;
      current = next;
    }
    return current;
  }

  /// 该槽位是否被合并到别的槽位。
  bool isMergedAway(String slotId) =>
      mergeInto.containsKey(slotId) && mergeInto[slotId] != slotId;

  /// 取某槽位的**生效设定**：先折叠到目标槽位再查。
  ///
  /// 返回空设定而不是 null：调用方到处判空会让"未设定"和"设定为空"两种
  /// 情况分叉，而它们的行为完全一样。
  SpeakerSetting of(String slotId) =>
      bySlot[canonical(slotId)] ?? const SpeakerSetting();

  /// 写入某个槽位的设定（写到折叠后的目标槽位上）。
  MeetingSpeakerSettings withSlot(String slotId, SpeakerSetting setting) {
    final target = canonical(slotId);
    final next = _mutableCopy(this);
    next.bySlot[target] = setting;
    return next;
  }

  /// 合并：把 [from] 折叠到 [into]。
  MeetingSpeakerSettings withMerge(String from, String into) {
    if (from == into) return this;
    final next = _mutableCopy(this);
    // 重定向所有指向 from 的槽位，避免链断裂。
    for (final e in mergeInto.entries.toList()) {
      if (e.value == from) next.mergeInto[e.key] = into;
    }
    next.mergeInto[from] = into;
    return next;
  }

  /// 取消 [from] 的合并。
  MeetingSpeakerSettings withoutMerge(String from) {
    final next = _mutableCopy(this);
    next.mergeInto.remove(from);
    return next;
  }

  /// 设置自定义显示名（空串即清除）。
  MeetingSpeakerSettings withTitle(String title) {
    final next = _mutableCopy(this);
    return MeetingSpeakerSettings(
      bySlot: next.bySlot,
      mergeInto: next.mergeInto,
      displayTitle: title.trim(),
    );
  }

  bool get isEmpty =>
      bySlot.isEmpty && mergeInto.isEmpty && displayTitle.isEmpty;

  Map<String, dynamic> toJson() => {
        'bySlot': bySlot.map((k, v) => MapEntry(k, v.toJson())),
        'mergeInto': mergeInto,
        'displayTitle': displayTitle,
      };

  factory MeetingSpeakerSettings.fromJson(Map<String, dynamic> json) {
    final raw = (json['bySlot'] as Map?) ?? const {};
    final merges = (json['mergeInto'] as Map?) ?? const {};
    return MeetingSpeakerSettings(
      bySlot: raw.map((k, v) => MapEntry(
            '$k',
            SpeakerSetting.fromJson(Map<String, dynamic>.from(v as Map)),
          )),
      mergeInto: merges.map((k, v) => MapEntry('$k', '$v')),
      displayTitle: json['displayTitle'] as String? ?? '',
    );
  }
}

/// 内部小工具：复制一份**可变**的设定。
///
/// 设定对象的字段是 final，合并/改名都要先拿一份可变副本。三处调用点都
/// 需要把两份 map 都复制——漏掉 `mergeInto` 会把用户的合并结果丢掉。
MeetingSpeakerSettings _mutableCopy(MeetingSpeakerSettings s) =>
    MeetingSpeakerSettings(
      bySlot: Map<String, SpeakerSetting>.from(s.bySlot),
      mergeInto: Map<String, String>.from(s.mergeInto),
      displayTitle: s.displayTitle,
    );

/// 「我的身份」：跨所有真实会议恒等的显示名与音色。
///
/// 默认值与排练会议的 `Simon` 绑定同一音色（`boyinnansheng`），使两个功能
/// 里的"我"是同一个声音（design D8）。
class MyIdentity {
  /// 默认显示名。
  static const String defaultName = '我';

  /// 默认音色（与 `RehearsalVoices` 给 `simon` 的绑定一致）。
  static const String defaultVoiceId = 'boyinnansheng';

  final String name;
  final String voiceId;

  const MyIdentity({this.name = defaultName, this.voiceId = defaultVoiceId});

  MyIdentity copyWith({String? name, String? voiceId}) => MyIdentity(
        name: name ?? this.name,
        voiceId: voiceId ?? this.voiceId,
      );

  Map<String, dynamic> toJson() => {'name': name, 'voiceId': voiceId};

  factory MyIdentity.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String? ?? '').trim();
    final voiceId = (json['voiceId'] as String? ?? '').trim();
    // 空值回落默认：配置文件被手工改坏时不该让导入流程瘫掉。
    return MyIdentity(
      name: name.isEmpty ? defaultName : name,
      voiceId: voiceId.isEmpty ? defaultVoiceId : voiceId,
    );
  }
}

/// 一条插入的回答（回答层）。
///
/// 锚定在**轮次下标**而不是时间戳：时间戳在插入之后会整体平移，下标不会
/// （原稿只读）。文稿内容变化导致下标越界时，[stale] 置真而不是删掉记录——
/// 用户改的文字不该被系统静默丢弃。
class InsertedAnswer {
  /// 在 `Clip` 的轮次里标记"这是插入的回答"用的 `role` 值。
  ///
  /// 用 `SpeakerTurn.role` 承载而不是给 `SpeakerTurn` 加字段：`SpeakerTurn` 被
  /// 三类素材共用，为其中一类加一个只对它有意义的状态位，会让另外两类永远
  /// 带着一个空字段。role 本来就在表达"这个人在这场里是什么身份"，语义贴切。
  static const String roleMarker = '我的回答';

  /// 回答标识（同一场会议内唯一）。
  final String id;

  /// 插在这一轮之后。
  final int anchorTurnIndex;

  /// 被提问的那一轮（可能等于锚点轮；分开存是为了界面回溯"在回答什么"）。
  final int questionTurnIndex;

  /// 插入时的说话人显示名（快照）。
  ///
  /// 存快照而不是每次读当前身份：用户之后改了「我的身份」的显示名，不应该
  /// 把历史上已经插入的回答改名——文稿与音频是对应的，音色已经烘进去了。
  final String speakerName;

  /// 插入时使用的音色标识（快照同上）。
  final String voiceId;

  /// 英文回答正文（送入合成的就是它）。
  final String textEn;

  /// 中文原文（用户以中文作答时保留，供对照；AI 直接生成时为空）。
  final String textZh;

  /// 该段音频文件名（相对 `turns/<meetingId>/`）。空串表示尚未合成。
  final String audioFile;

  /// 锚点是否已失效（文稿更新后轮次变少）。
  final bool stale;

  const InsertedAnswer({
    required this.id,
    required this.anchorTurnIndex,
    required this.questionTurnIndex,
    required this.speakerName,
    required this.voiceId,
    required this.textEn,
    this.textZh = '',
    this.audioFile = '',
    this.stale = false,
  });

  InsertedAnswer copyWith({
    int? anchorTurnIndex,
    int? questionTurnIndex,
    String? speakerName,
    String? voiceId,
    String? textEn,
    String? textZh,
    String? audioFile,
    bool? stale,
  }) =>
      InsertedAnswer(
        id: id,
        anchorTurnIndex: anchorTurnIndex ?? this.anchorTurnIndex,
        questionTurnIndex: questionTurnIndex ?? this.questionTurnIndex,
        speakerName: speakerName ?? this.speakerName,
        voiceId: voiceId ?? this.voiceId,
        textEn: textEn ?? this.textEn,
        textZh: textZh ?? this.textZh,
        audioFile: audioFile ?? this.audioFile,
        stale: stale ?? this.stale,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'anchorTurnIndex': anchorTurnIndex,
        'questionTurnIndex': questionTurnIndex,
        'speakerName': speakerName,
        'voiceId': voiceId,
        'textEn': textEn,
        'textZh': textZh,
        'audioFile': audioFile,
        'stale': stale,
      };

  factory InsertedAnswer.fromJson(Map<String, dynamic> json) => InsertedAnswer(
        id: json['id'] as String? ?? '',
        anchorTurnIndex: (json['anchorTurnIndex'] as num?)?.toInt() ?? 0,
        questionTurnIndex: (json['questionTurnIndex'] as num?)?.toInt() ?? 0,
        speakerName: json['speakerName'] as String? ?? MyIdentity.defaultName,
        voiceId: json['voiceId'] as String? ?? MyIdentity.defaultVoiceId,
        textEn: json['textEn'] as String? ?? '',
        textZh: json['textZh'] as String? ?? '',
        audioFile: json['audioFile'] as String? ?? '',
        stale: (json['stale'] as bool?) ?? false,
      );
}

/// 一组合成产物。
class TurnGroupAudio {
  /// 组内的轮次下标（顺序即念的顺序）。
  final List<int> turnIndices;

  /// 音频文件名（相对 `turns/<meetingId>/`）。
  final String fileName;

  /// 该组在整篇音频中的起止毫秒（拼接后回填）。
  final int startMs;
  final int endMs;

  /// 是否合成失败（界面据此给出重试入口）。
  final bool failed;

  /// 这一组**实际**合成用的音色标识。
  ///
  /// 与"当前设定"分开记录：用户改了音色但还没重新合成时，磁盘上的音频仍是
  /// 旧音色。`Clip` 里要写的是这个实际值，否则"音色可追溯"就成了猜测。
  /// 空串表示旧数据没有记录——此时既不当作待更新，也不谎称知道。
  final String voiceId;

  const TurnGroupAudio({
    required this.turnIndices,
    required this.fileName,
    this.startMs = 0,
    this.endMs = 0,
    this.failed = false,
    this.voiceId = '',
  });

  int get durationMs => endMs - startMs;

  TurnGroupAudio copyWith({
    List<int>? turnIndices,
    String? fileName,
    int? startMs,
    int? endMs,
    bool? failed,
    String? voiceId,
  }) =>
      TurnGroupAudio(
        turnIndices: turnIndices ?? this.turnIndices,
        fileName: fileName ?? this.fileName,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        failed: failed ?? this.failed,
        voiceId: voiceId ?? this.voiceId,
      );

  Map<String, dynamic> toJson() => {
        'turnIndices': turnIndices,
        'fileName': fileName,
        'startMs': startMs,
        'endMs': endMs,
        'failed': failed,
        'voiceId': voiceId,
      };

  factory TurnGroupAudio.fromJson(Map<String, dynamic> json) => TurnGroupAudio(
        turnIndices: ((json['turnIndices'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        fileName: json['fileName'] as String? ?? '',
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as bool?) ?? false,
        voiceId: json['voiceId'] as String? ?? '',
      );
}

/// 合成状态（派生数据，可整层丢弃后重建）。
///
/// 存续句分组与每组音频的时长，使"插入一段回答"只需要 concat、不需要重跑
/// TTS（design D4）。删掉它只是让下次打开时要求重新合成，不丢任何用户数据。
class MeetingBakeState {
  /// 各组音频（顺序即拼接顺序，不包含插入的回答）。
  final List<TurnGroupAudio> groups;

  /// 整篇音频文件名（相对 `audio/`）。
  final String audioFile;

  /// 整篇音频总时长（毫秒）。
  final int totalMs;

  /// 合成完成时间。
  final DateTime? bakedAt;

  const MeetingBakeState({
    this.groups = const [],
    this.audioFile = '',
    this.totalMs = 0,
    this.bakedAt,
  });

  /// 失败的组数。
  int get failedGroupCount => groups.where((g) => g.failed).length;

  /// 是否全部合成成功。
  bool get isComplete => groups.isNotEmpty && failedGroupCount == 0;

  Map<String, dynamic> toJson() => {
        'groups': groups.map((g) => g.toJson()).toList(),
        'audioFile': audioFile,
        'totalMs': totalMs,
        'bakedAt': bakedAt?.toIso8601String(),
      };

  factory MeetingBakeState.fromJson(Map<String, dynamic> json) =>
      MeetingBakeState(
        groups: ((json['groups'] as List?) ?? const [])
            .map((e) =>
                TurnGroupAudio.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        audioFile: json['audioFile'] as String? ?? '',
        totalMs: (json['totalMs'] as num?)?.toInt() ?? 0,
        bakedAt: DateTime.tryParse(json['bakedAt'] as String? ?? ''),
      );
}
