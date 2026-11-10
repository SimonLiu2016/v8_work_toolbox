import 'listening_models.dart';

/// 预设长难句标签
class VaultTags {
  static const String connectedSpeech = '连读弱读';
  static const String complexClause = '复杂从句';
  static const String longMainClause = '超长主干';
  static const String fastPaced = '语速飞快';
  static const String domainLingo = '行业表达';

  static const List<String> defaults = [
    connectedSpeech,
    complexClause,
    longMainClause,
    fastPaced,
    domainLingo,
  ];
}

/// 长难句复盘条目
class VaultSentence {
  final String id;
  final String clipId;
  final String meetingTitle;
  final MeetingScene scene;
  final int turnIndex;
  final String speaker;
  final String role;
  final String text;
  final String audioFilePath;
  final int startMs;
  final int endMs;
  final List<String> tags;
  final bool mastered;
  final int reviewCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VaultSentence({
    required this.id,
    required this.clipId,
    required this.meetingTitle,
    required this.scene,
    required this.turnIndex,
    required this.speaker,
    this.role = '',
    required this.text,
    this.audioFilePath = '',
    required this.startMs,
    required this.endMs,
    this.tags = const [],
    this.mastered = false,
    this.reviewCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  int get durationMs => (endMs - startMs).clamp(0, 9999999);

  VaultSentence copyWith({
    String? id,
    String? clipId,
    String? meetingTitle,
    MeetingScene? scene,
    int? turnIndex,
    String? speaker,
    String? role,
    String? text,
    String? audioFilePath,
    int? startMs,
    int? endMs,
    List<String>? tags,
    bool? mastered,
    int? reviewCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VaultSentence(
      id: id ?? this.id,
      clipId: clipId ?? this.clipId,
      meetingTitle: meetingTitle ?? this.meetingTitle,
      scene: scene ?? this.scene,
      turnIndex: turnIndex ?? this.turnIndex,
      speaker: speaker ?? this.speaker,
      role: role ?? this.role,
      text: text ?? this.text,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      tags: tags ?? this.tags,
      mastered: mastered ?? this.mastered,
      reviewCount: reviewCount ?? this.reviewCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clipId': clipId,
        'meetingTitle': meetingTitle,
        'scene': scene.name,
        'turnIndex': turnIndex,
        'speaker': speaker,
        'role': role,
        'text': text,
        'audioFilePath': audioFilePath,
        'startMs': startMs,
        'endMs': endMs,
        'tags': tags,
        'mastered': mastered,
        'reviewCount': reviewCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultSentence.fromJson(Map<String, dynamic> json) {
    MeetingScene parsedScene;
    try {
      parsedScene = MeetingScene.values.firstWhere(
        (s) => s.name == json['scene'],
        orElse: () => MeetingScene.realMeeting,
      );
    } catch (_) {
      parsedScene = MeetingScene.realMeeting;
    }

    return VaultSentence(
      id: json['id'] as String? ?? '',
      clipId: json['clipId'] as String? ?? '',
      meetingTitle: json['meetingTitle'] as String? ?? '',
      scene: parsedScene,
      turnIndex: json['turnIndex'] as int? ?? 0,
      speaker: json['speaker'] as String? ?? '',
      role: json['role'] as String? ?? '',
      text: json['text'] as String? ?? '',
      audioFilePath: json['audioFilePath'] as String? ?? '',
      startMs: json['startMs'] as int? ?? 0,
      endMs: json['endMs'] as int? ?? 0,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      mastered: json['mastered'] as bool? ?? false,
      reviewCount: json['reviewCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
