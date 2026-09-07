import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 朗读切片合成状态
enum ChunkSynthesisStatus {
  pending,      // 待合成
  synthesizing, // 合成中
  cached,       // 已缓存就绪
  error,        // 合成失败
}

/// 文档来源类型
enum DocumentSourceType {
  txt,
  markdown,
  pdf,
  docx,
  epub,
  webUrl,
}

/// TTS 引擎工作模态
enum TtsMode {
  edge,        // 微软 Edge-TTS 免 Key 神经网络语音 (开箱即用)
  customAi,    // OpenAI-compatible /v1/audio/speech 商业自定义接口
  macosNative, // macOS 原生 say / AVSpeechSynthesizer 离线兜底
}

/// 朗读文本切片
class ReadingChunk {
  final int index;
  final String text;
  final int startChar;
  final int endChar;
  String? audioCachePath;
  ChunkSynthesisStatus status;
  String? errorMessage;

  ReadingChunk({
    required this.index,
    required this.text,
    required this.startChar,
    required this.endChar,
    this.audioCachePath,
    this.status = ChunkSynthesisStatus.pending,
    this.errorMessage,
  });

  bool get isReady => status == ChunkSynthesisStatus.cached && audioCachePath != null;

  Map<String, dynamic> toJson() => {
    'index': index,
    'text': text,
    'startChar': startChar,
    'endChar': endChar,
    'audioCachePath': audioCachePath,
    'status': status.name,
    'errorMessage': errorMessage,
  };

  factory ReadingChunk.fromJson(Map<String, dynamic> json) {
    return ReadingChunk(
      index: json['index'] as int,
      text: json['text'] as String,
      startChar: json['startChar'] as int,
      endChar: json['endChar'] as int,
      audioCachePath: json['audioCachePath'] as String?,
      status: ChunkSynthesisStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ChunkSynthesisStatus.pending,
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// 文档章节模型 (针对 EPUB、长篇 Markdown 等)
class ReadingChapter {
  final String id;
  final String title;
  final int startChunkIndex;
  final int endChunkIndex;

  const ReadingChapter({
    required this.id,
    required this.title,
    required this.startChunkIndex,
    required this.endChunkIndex,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startChunkIndex': startChunkIndex,
    'endChunkIndex': endChunkIndex,
  };

  factory ReadingChapter.fromJson(Map<String, dynamic> json) {
    return ReadingChapter(
      id: json['id'] as String,
      title: json['title'] as String,
      startChunkIndex: json['startChunkIndex'] as int,
      endChunkIndex: json['endChunkIndex'] as int,
    );
  }
}

/// 朗读文档完整实体
class ReadingDocument {
  final String id;
  final String title;
  final String source;
  final DocumentSourceType sourceType;
  final List<ReadingChunk> chunks;
  final List<ReadingChapter> chapters;
  final int totalWordCount;
  final DateTime createdAt;

  ReadingDocument({
    required this.id,
    required this.title,
    required this.source,
    required this.sourceType,
    required this.chunks,
    this.chapters = const [],
    required this.totalWordCount,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 预估阅读时长 (基于中文约 260 字/分钟，英文约 150 词/分钟)
  Duration get estimatedDuration {
    final minutes = (totalWordCount / 240).ceil();
    return Duration(minutes: minutes < 1 ? 1 : minutes);
  }

  /// 计算整个文档的完整纯文本
  String get fullText => chunks.map((c) => c.text).join('\n\n');

  /// 生成基于来源和内容的确定性文档 Hash ID
  static String computeDocumentId(String source, String rawContent) {
    final key = '$source:$rawContent';
    return sha256.convert(utf8.encode(key)).toString().substring(0, 16);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'source': source,
    'sourceType': sourceType.name,
    'chunks': chunks.map((c) => c.toJson()).toList(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'totalWordCount': totalWordCount,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ReadingDocument.fromJson(Map<String, dynamic> json) {
    final rawChunks = json['chunks'] as List? ?? [];
    final rawChapters = json['chapters'] as List? ?? [];
    return ReadingDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      source: json['source'] as String,
      sourceType: DocumentSourceType.values.firstWhere(
        (e) => e.name == json['sourceType'],
        orElse: () => DocumentSourceType.txt,
      ),
      chunks: rawChunks.map((c) => ReadingChunk.fromJson(c as Map<String, dynamic>)).toList(),
      chapters: rawChapters.map((c) => ReadingChapter.fromJson(c as Map<String, dynamic>)).toList(),
      totalWordCount: (json['totalWordCount'] as int?) ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }
}

/// TTS 音色选项
class TtsVoiceOption {
  final String id;
  final String name;
  final String language;
  final String gender;
  final TtsMode mode;
  final String? description;

  const TtsVoiceOption({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    required this.mode,
    this.description,
  });

  /// 预设 Edge-TTS 热门中文与英文音色
  static const List<TtsVoiceOption> defaultEdgeVoices = [
    TtsVoiceOption(
      id: 'zh-CN-XiaoxiaoNeural',
      name: '晓晓 (温柔女声)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.edge,
      description: '自然生动，适合小说、散文与长文朗读',
    ),
    TtsVoiceOption(
      id: 'zh-CN-YunxiNeural',
      name: '云希 (阳光男声)',
      language: 'zh-CN',
      gender: 'male',
      mode: TtsMode.edge,
      description: '清脆朝气，适合技术文档、新闻与博客',
    ),
    TtsVoiceOption(
      id: 'zh-CN-YunjianNeural',
      name: '云健 (影视解说男声)',
      language: 'zh-CN',
      gender: 'male',
      mode: TtsMode.edge,
      description: '沉稳有力，适合科技、评测与专栏',
    ),
    TtsVoiceOption(
      id: 'zh-CN-XiaoyiNeural',
      name: '晓伊 (知性女声)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.edge,
      description: '专业端庄，适合论文、报告与政企公文',
    ),
    TtsVoiceOption(
      id: 'zh-CN-liaoning-XiaobeiNeural',
      name: '小北 (东北幽默女声)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.edge,
      description: '地道风趣，适合轻松闲聊与趣味小说',
    ),
    TtsVoiceOption(
      id: 'zh-HK-HiuGaaiNeural',
      name: '晓佳 (粤语女声)',
      language: 'zh-HK',
      gender: 'female',
      mode: TtsMode.edge,
      description: '标准香港粤语发音',
    ),
    TtsVoiceOption(
      id: 'zh-TW-HsiaoChenNeural',
      name: '晓臻 (台湾腔女声)',
      language: 'zh-TW',
      gender: 'female',
      mode: TtsMode.edge,
      description: '甜美亲切，适合生活与文学作品',
    ),
    TtsVoiceOption(
      id: 'en-US-JennyNeural',
      name: 'Jenny (US Female)',
      language: 'en-US',
      gender: 'female',
      mode: TtsMode.edge,
      description: 'Crisp natural American English',
    ),
    TtsVoiceOption(
      id: 'en-US-GuyNeural',
      name: 'Guy (US Male)',
      language: 'en-US',
      gender: 'male',
      mode: TtsMode.edge,
      description: 'Professional informative narration',
    ),
  ];

  /// 预设 OpenAI 商业音色
  static const List<TtsVoiceOption> defaultOpenAiVoices = [
    TtsVoiceOption(
      id: 'alloy',
      name: 'Alloy (平衡中性)',
      language: 'multi',
      gender: 'neutral',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方平衡通用音色',
    ),
    TtsVoiceOption(
      id: 'echo',
      name: 'Echo (沉稳男声)',
      language: 'multi',
      gender: 'male',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方低沉稳重音色',
    ),
    TtsVoiceOption(
      id: 'fable',
      name: 'Fable (英音叙事)',
      language: 'multi',
      gender: 'neutral',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方英伦英式音色',
    ),
    TtsVoiceOption(
      id: 'onyx',
      name: 'Onyx (磁性男声)',
      language: 'multi',
      gender: 'male',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方磁性浑厚音色',
    ),
    TtsVoiceOption(
      id: 'nova',
      name: 'Nova (明快女声)',
      language: 'multi',
      gender: 'female',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方活力生动女声',
    ),
    TtsVoiceOption(
      id: 'shimmer',
      name: 'Shimmer (清亮女声)',
      language: 'multi',
      gender: 'female',
      mode: TtsMode.customAi,
      description: 'OpenAI 官方清脆明澈音色',
    ),
  ];

  /// 预设小米 MiMo 大模型官方音色
  static const List<TtsVoiceOption> defaultMimoVoices = [
    TtsVoiceOption(
      id: 'mimo_default',
      name: 'MiMo 默认',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.customAi,
      description: '小米大模型官方默认基准合成音色',
    ),
    TtsVoiceOption(
      id: '冰糖',
      name: '冰糖 (甜美温柔女声)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.customAi,
      description: '亲切甜美，适合小说、散文与长文伴读',
    ),
    TtsVoiceOption(
      id: '茉莉',
      name: '茉莉 (知性温和女声)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.customAi,
      description: '端庄知性，适合科技文章、新闻与深度阅读',
    ),
    TtsVoiceOption(
      id: '苏打',
      name: '苏打 (阳光清爽男声)',
      language: 'zh-CN',
      gender: 'male',
      mode: TtsMode.customAi,
      description: '阳光活力，适合技术文档、科普与教程',
    ),
    TtsVoiceOption(
      id: '白桦',
      name: '白桦 (低沉磁性男声)',
      language: 'zh-CN',
      gender: 'male',
      mode: TtsMode.customAi,
      description: '沉稳有力，适合评测、专栏与严肃书籍',
    ),
    TtsVoiceOption(
      id: 'Mia',
      name: 'Mia (英美女声)',
      language: 'en-US',
      gender: 'female',
      mode: TtsMode.customAi,
      description: '自然纯正美式英语女声',
    ),
    TtsVoiceOption(
      id: 'Chloe',
      name: 'Chloe (知性英美女声)',
      language: 'en-US',
      gender: 'female',
      mode: TtsMode.customAi,
      description: '清晰优雅美式英语女声',
    ),
    TtsVoiceOption(
      id: 'Milo',
      name: 'Milo (阳光英美男声)',
      language: 'en-US',
      gender: 'male',
      mode: TtsMode.customAi,
      description: '活力自然美式英语男声',
    ),
    TtsVoiceOption(
      id: 'Dean',
      name: 'Dean (磁性英美男声)',
      language: 'en-US',
      gender: 'male',
      mode: TtsMode.customAi,
      description: '低沉专业美式英语男声',
    ),
  ];

  /// MiMo 官方允许的音色集合
  static const Set<String> mimoSupportedVoiceIds = {
    'mimo_default',
    '冰糖',
    '茉莉',
    '苏打',
    '白桦',
    'Mia',
    'Chloe',
    'Milo',
    'Dean',
  };

  /// 预设 macOS 离线音色
  static const List<TtsVoiceOption> defaultMacOsVoices = [
    TtsVoiceOption(
      id: 'Tingting',
      name: '婷婷 (macOS 中文普通话)',
      language: 'zh-CN',
      gender: 'female',
      mode: TtsMode.macosNative,
      description: 'macOS 内置标准普通话离线语音',
    ),
    TtsVoiceOption(
      id: 'Sin-ji',
      name: '善知 (macOS 粤语)',
      language: 'zh-HK',
      gender: 'female',
      mode: TtsMode.macosNative,
      description: 'macOS 内置离线粤语发音',
    ),
    TtsVoiceOption(
      id: 'Samantha',
      name: 'Samantha (macOS 美式英语)',
      language: 'en-US',
      gender: 'female',
      mode: TtsMode.macosNative,
      description: 'macOS 经典 Siri 前身纯正美音',
    ),
  ];
}

/// TTS 实时合成运行参数
class TtsSynthesisConfig {
  final TtsMode mode;
  final String voiceId;
  final double speed; // 0.5 ~ 2.5
  final double pitch;
  final bool useSystemAiConfig; // 是否优先使用软件「AI能力配置」中绑定的供应商与凭证
  final String? systemProviderId; // 指定使用的系统供应商 ID (为空则遵循 TTS 槽位默认候选)
  final String? customVoiceId; // 针对 OpenAI 兼容第三方引擎的自定义音色标识
  final String? customEndpoint; // OpenAI-compatible base URL (e.g. https://api.openai.com/v1)
  final String? customApiKey;
  final String? customModel;    // e.g. tts-1, tts-1-hd, speech-01

  const TtsSynthesisConfig({
    this.mode = TtsMode.edge,
    this.voiceId = 'zh-CN-XiaoxiaoNeural',
    this.speed = 1.0,
    this.pitch = 1.0,
    this.useSystemAiConfig = true,
    this.systemProviderId,
    this.customVoiceId,
    this.customEndpoint,
    this.customApiKey,
    this.customModel = 'tts-1',
  });

  /// 实际发往底层合成引擎的有效音色标识
  String get effectiveVoiceId {
    if (mode == TtsMode.customAi && customVoiceId != null && customVoiceId!.trim().isNotEmpty) {
      return customVoiceId!.trim();
    }
    return voiceId;
  }

  TtsSynthesisConfig copyWith({
    TtsMode? mode,
    String? voiceId,
    double? speed,
    double? pitch,
    bool? useSystemAiConfig,
    String? systemProviderId,
    String? customVoiceId,
    String? customEndpoint,
    String? customApiKey,
    String? customModel,
  }) {
    return TtsSynthesisConfig(
      mode: mode ?? this.mode,
      voiceId: voiceId ?? this.voiceId,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      useSystemAiConfig: useSystemAiConfig ?? this.useSystemAiConfig,
      systemProviderId: systemProviderId ?? this.systemProviderId,
      customVoiceId: customVoiceId ?? this.customVoiceId,
      customEndpoint: customEndpoint ?? this.customEndpoint,
      customApiKey: customApiKey ?? this.customApiKey,
      customModel: customModel ?? this.customModel,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'voiceId': voiceId,
    'speed': speed,
    'pitch': pitch,
    'useSystemAiConfig': useSystemAiConfig,
    'systemProviderId': systemProviderId,
    'customVoiceId': customVoiceId,
    'customEndpoint': customEndpoint,
    'customApiKey': customApiKey,
    'customModel': customModel,
  };

  factory TtsSynthesisConfig.fromJson(Map<String, dynamic> json) {
    return TtsSynthesisConfig(
      mode: TtsMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => TtsMode.edge,
      ),
      voiceId: (json['voiceId'] as String?) ?? 'zh-CN-XiaoxiaoNeural',
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
      useSystemAiConfig: json['useSystemAiConfig'] as bool? ?? true,
      systemProviderId: json['systemProviderId'] as String?,
      customVoiceId: json['customVoiceId'] as String?,
      customEndpoint: json['customEndpoint'] as String?,
      customApiKey: json['customApiKey'] as String?,
      customModel: (json['customModel'] as String?) ?? 'tts-1',
    );
  }
}
