/// 会议词汇表的重点关注与 AI/TTS 助学存储。
///
/// 为什么与 [MeetingVocabularyStore] 分离：
/// [MeetingVocabularyStore.rebuild] 每次导入/删除真实会议或打开词汇表时都会
/// 全量覆盖 `meeting_vocabulary_index.json`。把用户的「⭐ 重点关注」标记、
/// 单词音标/词性/中文释义、例句中文翻译以及临时合成的 TTS 音频独立保存在
/// `vocabulary_study_store.json` 与 `vocab_tts_cache/` 下，确保重建词表时
/// 助学数据永远不会丢失。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../services/ai_config_store.dart';
import '../../../services/app_paths.dart';
import '../../lookup_panel/services/dictionary_service.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import 'meeting_vocabulary_index.dart';
import 'rehearsal_llm.dart';
import 'rehearsal_text_generator.dart';
import 'tts_binding_probe.dart';

/// 单个词汇的音标、词性与中文解释。
class VocabularyWordProfile {
  /// 归一化词形（如 `governance`）。
  final String word;

  /// 音标（如 `/ˈɡʌvənəns/`）。
  final String phonetic;

  /// 词性（如 `n.`、`v. / n.`）。
  final String partOfSpeech;

  /// 中文解释（如 `n. 治理；统治；管理机制`）。
  final String definitionZh;

  /// 更新时间（ISO-8601）。
  final String updatedAt;

  const VocabularyWordProfile({
    required this.word,
    this.phonetic = '',
    this.partOfSpeech = '',
    this.definitionZh = '',
    this.updatedAt = '',
  });

  bool get hasDefinition => definitionZh.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'partOfSpeech': partOfSpeech,
        'definitionZh': definitionZh,
        'updatedAt': updatedAt,
      };

  factory VocabularyWordProfile.fromJson(Map<String, dynamic> json) =>
      VocabularyWordProfile(
        word: json['word'] as String? ?? '',
        phonetic: json['phonetic'] as String? ?? '',
        partOfSpeech: json['partOfSpeech'] as String? ?? '',
        definitionZh: json['definitionZh'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );
}

/// 记忆熟练度级别与间隔排期。
enum MemoryProficiency {
  fresh(0, '生词', 1),
  learning(1, '学习中', 2),
  familiar(2, '熟悉', 4),
  mastered(3, '已掌握', 7),
  solid(4, '牢记掌握', 14);

  final int level;
  final String label;
  final int defaultIntervalDays;

  const MemoryProficiency(this.level, this.label, this.defaultIntervalDays);

  static MemoryProficiency fromLevel(int level) {
    for (final p in values) {
      if (p.level == level) return p;
    }
    return fresh;
  }
}

/// 复习时间范围筛选维度。
enum ReviewTimeRange {
  today('今日学习', '今天内学习或复习过的词汇'),
  last3Days('近 3 天', '最近 3 天内学习或复习过的词汇'),
  last7Days('近 7 天', '最近 7 天内学习或复习过的词汇'),
  last30Days('近 30 天', '最近 30 天内学习或复习过的词汇'),
  allStudied('全部已学', '历史上所有学习或复习过的词汇');

  final String label;
  final String description;

  const ReviewTimeRange(this.label, this.description);
}

/// 盲听作答时的听觉熟悉度评估等级。
enum AuditoryFamiliarity {
  /// 秒懂精通：听 1 次且在 4 秒内选对。
  instant('秒懂精通', '听辨条件反射敏捷，迅速秒选'),

  /// 基本熟悉：听 1 次且耗时 > 4 秒选对。
  normal('基本熟悉', '听辨清晰无误，正常看题思考'),

  /// 迟疑辨析：听 2 次选对。
  hesitant('迟疑辨析', '盲听二听确认，稍有犹豫'),

  /// 辨音吃力：听 >= 3 次选对。
  struggling('辨音吃力', '多次重听辨音，极易猜对遗忘'),

  /// 辨音盲区：答错。
  lapse('辨音盲区', '未能正确听辨释义');

  final String label;
  final String description;

  const AuditoryFamiliarity(this.label, this.description);
}

/// 单词发音口音偏好。
enum VocabularyAccent {
  us('美音', '美式发音 (US)'),
  uk('英音', '英式发音 (UK)');

  final String label;
  final String description;

  const VocabularyAccent(this.label, this.description);

  static VocabularyAccent fromName(String? name) {
    if (name == 'uk') return VocabularyAccent.uk;
    return VocabularyAccent.us;
  }
}

/// 单个重点词汇的记忆与复习状态模型。
class WordMemoryState {
  final String word;
  final int proficiency;
  final String lastReviewedAt;
  final String nextReviewDue;
  final int streak;
  final int mistakeCount;

  const WordMemoryState({
    required this.word,
    this.proficiency = 0,
    this.lastReviewedAt = '',
    this.nextReviewDue = '',
    this.streak = 0,
    this.mistakeCount = 0,
  });

  MemoryProficiency get proficiencyEnum =>
      MemoryProficiency.fromLevel(proficiency);

  /// 判断该单词在 [asOf] 时间点是否已经到期需要复习。
  bool isDue({DateTime? asOf}) {
    if (nextReviewDue.isEmpty) return true;
    final due = DateTime.tryParse(nextReviewDue);
    if (due == null) return true;
    final checkTime = asOf ?? DateTime.now();
    return checkTime.isAfter(due) || checkTime.isAtSameMomentAs(due);
  }

  /// 是否达到已掌握标准（熟练度等级 >= 3）。
  bool get isMastered => proficiency >= 3;

  /// 是否属于易错词。
  bool get isMistake => mistakeCount > 0;

  Map<String, dynamic> toJson() => {
        'word': word,
        'proficiency': proficiency,
        'lastReviewedAt': lastReviewedAt,
        'nextReviewDue': nextReviewDue,
        'streak': streak,
        'mistakeCount': mistakeCount,
      };

  factory WordMemoryState.fromJson(Map<String, dynamic> json) =>
      WordMemoryState(
        word: json['word'] as String? ?? '',
        proficiency: (json['proficiency'] as num?)?.toInt() ?? 0,
        lastReviewedAt: json['lastReviewedAt'] as String? ?? '',
        nextReviewDue: json['nextReviewDue'] as String? ?? '',
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        mistakeCount: (json['mistakeCount'] as num?)?.toInt() ?? 0,
      );
}

/// 词汇表助学持久化快照。
class VocabularyStudyData {
  /// 已标记为「⭐ 重点关注」的归一化单词集合。
  final Set<String> focusedWords;

  /// 单词 → 音标/词性/中文释义缓存。
  final Map<String, VocabularyWordProfile> wordProfiles;

  /// 归一化原句文本 → 中文句意缓存。
  final Map<String, String> sentenceTranslations;

  /// 重点词汇 → 记忆与复习状态。
  final Map<String, WordMemoryState> memoryStates;

  /// 各练习模式最近学习的进度映射：mode.name -> lastWord。
  final Map<String, String> practiceProgress;

  /// 发音口音偏好（默认美音）。
  final VocabularyAccent accent;

  const VocabularyStudyData({
    this.focusedWords = const {},
    this.wordProfiles = const {},
    this.sentenceTranslations = const {},
    this.memoryStates = const {},
    this.practiceProgress = const {},
    this.accent = VocabularyAccent.us,
  });

  Map<String, dynamic> toJson() => {
        'focusedWords': focusedWords.toList()..sort(),
        'wordProfiles': {
          for (final e in wordProfiles.entries) e.key: e.value.toJson(),
        },
        'sentenceTranslations': sentenceTranslations,
        'memoryStates': {
          for (final e in memoryStates.entries) e.key: e.value.toJson(),
        },
        'practiceProgress': practiceProgress,
        'accent': accent.name,
      };

  factory VocabularyStudyData.fromJson(Map<String, dynamic> json) {
    final rawFocused = json['focusedWords'] as List? ?? const [];
    final rawProfiles =
        json['wordProfiles'] as Map<String, dynamic>? ?? const {};
    final rawSentences =
        json['sentenceTranslations'] as Map<String, dynamic>? ?? const {};
    final rawMemory =
        json['memoryStates'] as Map<String, dynamic>? ?? const {};
    final rawProgress =
        json['practiceProgress'] as Map<String, dynamic>? ?? const {};
    final rawAccent = json['accent'] as String?;

    return VocabularyStudyData(
      focusedWords: {
        for (final w in rawFocused.whereType<String>())
          if (w.trim().isNotEmpty) MeetingVocabularyIndex.normalizeWord(w),
      },
      wordProfiles: {
        for (final e in rawProfiles.entries)
          if (e.value is Map)
            e.key: VocabularyWordProfile.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
      },
      sentenceTranslations: {
        for (final e in rawSentences.entries)
          if (e.value is String && (e.value as String).trim().isNotEmpty)
            e.key: (e.value as String).trim(),
      },
      memoryStates: {
        for (final e in rawMemory.entries)
          if (e.value is Map)
            e.key: WordMemoryState.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
      },
      practiceProgress: {
        for (final e in rawProgress.entries)
          if (e.value is String && (e.value as String).trim().isNotEmpty)
            e.key: MeetingVocabularyIndex.normalizeWord(e.value as String),
      },
      accent: VocabularyAccent.fromName(rawAccent),
    );
  }
}

/// 词汇表重点关注与 AI/TTS 助学管理器。
class VocabularyStudyStore extends ChangeNotifier {
  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _wsCollapse = RegExp(r'\s+');

  final Directory _baseDir;
  final Future<DictionaryResult?> Function(String word) _dictionaryLookup;
  final RehearsalTextGenerator _textGenerator;
  final bool _hasCustomTextGenerator;
  final TtsEngine _ttsEngine;
  final Future<Uint8List?> Function(String word, VocabularyAccent accent)
      _dictionaryAudioFetcher;
  final Future<Uint8List?> Function(String word, VocabularyAccent accent)
      _nativeSpeechSynthesizer;
  String _defaultVoiceId;
  String _styleInstruction;

  late Set<String> _focusedWords;
  late Map<String, VocabularyWordProfile> _wordProfiles;
  late Map<String, String> _sentenceTranslations;
  late Map<String, WordMemoryState> _memoryStates;
  late Map<String, String> _practiceProgress;
  late VocabularyAccent _accent;

  final Map<String, Future<VocabularyWordProfile?>> _inFlightProfiles = {};
  final Set<String> _loadingProfileWords = {};
  final Set<String> _loadingSentenceKeys = {};
  final Set<String> _loadingTtsKeys = {};

  VocabularyStudyStore({
    Directory? baseDir,
    Future<DictionaryResult?> Function(String word)? dictionaryLookup,
    RehearsalTextGenerator? textGenerator,
    TtsEngine? ttsEngine,
    Future<Uint8List?> Function(String word, VocabularyAccent accent)?
        dictionaryAudioFetcher,
    Future<Uint8List?> Function(String word, VocabularyAccent accent)?
        nativeSpeechSynthesizer,
    String? defaultVoiceId,
    String? styleInstruction,
  })  : _baseDir = baseDir ?? _resolveDefaultBaseDir(),
        _dictionaryLookup = dictionaryLookup ?? DictionaryService.lookup,
        _textGenerator = textGenerator ?? const SlotTextGenerator(),
        _hasCustomTextGenerator = textGenerator != null,
        _ttsEngine = ttsEngine ?? OpenAiTtsEngine(),
        _dictionaryAudioFetcher =
            dictionaryAudioFetcher ?? _defaultFetchDictionaryAudio,
        _nativeSpeechSynthesizer =
            nativeSpeechSynthesizer ?? _defaultSynthesizeViaMacNative,
        _defaultVoiceId = defaultVoiceId ?? _resolveDefaultVoiceId(),
        _styleInstruction = styleInstruction ?? _resolveDefaultStyle() {
    final initial = _readFromDiskSync();
    _focusedWords = Set<String>.from(initial.focusedWords);
    _wordProfiles =
        Map<String, VocabularyWordProfile>.from(initial.wordProfiles);
    _sentenceTranslations =
        Map<String, String>.from(initial.sentenceTranslations);
    _memoryStates =
        Map<String, WordMemoryState>.from(initial.memoryStates);
    _practiceProgress =
        Map<String, String>.from(initial.practiceProgress);
    _accent = initial.accent;
    for (final w in _focusedWords) {
      if (!_memoryStates.containsKey(w)) {
        _memoryStates[w] = WordMemoryState(word: w);
      }
    }
  }

  /// 当前单词发音口音偏好（美音 / 英音）。
  VocabularyAccent get accent => _accent;

  /// 设置单词发音口音偏好并持久化。
  void setAccent(VocabularyAccent accent) {
    if (_accent == accent) return;
    _accent = accent;
    _persistSync();
    notifyListeners();
  }

  /// 当前生效的默认音色 id（生词本/听力练习播放用）。
  String get defaultVoiceId => _defaultVoiceId;

  /// 设置默认音色 id；变化会清空 TTS 缓存避免复用旧发音。
  set defaultVoiceId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == _defaultVoiceId) return;
    _defaultVoiceId = normalized;
    try {
      if (ttsCacheDir.existsSync()) {
        ttsCacheDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 当前生效的 MiMo 风格指令（可为空串，表示不注入 user 消息）。
  String get styleInstruction => _styleInstruction;

  /// 设置 MiMo 风格指令；变化会清空 TTS 缓存避免复用旧发音。
  set styleInstruction(String value) {
    final normalized = value.trim();
    if (normalized == _styleInstruction) return;
    _styleInstruction = normalized;
    try {
      if (ttsCacheDir.existsSync()) {
        ttsCacheDir.deleteSync(recursive: true);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 解析默认音色：TTS 槽位绑定 MiMo 时用 MiMo 默认音色，否则沿用 StepFun 池。
  ///
  /// 此前固定 `VoicePool.zhixingjiejie`（StepFun 音色 id），绑定 MiMo 时会被
  /// `adaptVoiceForProvider(isMimo)` 被动兜底成 `mimo_default`，用户无法选中
  /// MiMo 音色。统一走 [TtsBindingProbe.defaultVoiceId]，与真实会议链路共享
  /// 同一探测结果，避免两处判定分叉。
  static String _resolveDefaultVoiceId() => TtsBindingProbe.defaultVoiceId();

  /// 解析默认 MiMo 风格指令：绑定 MiMo 时给保守默认，否则空串。
  static String _resolveDefaultStyle() => TtsBindingProbe.defaultStyle();

  static Directory _resolveDefaultBaseDir() {
    try {
      return AppPaths.itMeetingListeningDir;
    } catch (_) {
      return Directory(
        p.join(Directory.systemTemp.path, 'v8_it_meeting_vocab_study'),
      );
    }
  }

  File get _storeFile =>
      File(p.join(_baseDir.path, 'vocabulary_study_store.json'));

  Directory get ttsCacheDir =>
      Directory(p.join(_baseDir.path, 'vocab_tts_cache'));

  /// 已标记为重点关注的归一化词集合（只读视图）。
  Set<String> get focusedWords => Set<String>.unmodifiable(_focusedWords);

  /// 重点关注词数量。
  int get focusedCount => _focusedWords.length;

  /// 判断某词是否已标记为重点关注。
  bool isFocused(String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    return _focusedWords.contains(key);
  }

  /// 获取某词已缓存的音标/词性/释义。
  VocabularyWordProfile? profileFor(String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    return _wordProfiles[key];
  }

  /// 判断某词是否正在加载释义。
  bool isLoadingProfile(String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    return _loadingProfileWords.contains(key);
  }

  /// 获取某条原句已缓存的中文意思。
  String? translationForSentence(String sentence) {
    final key = normalizeSentenceKey(sentence);
    return _sentenceTranslations[key];
  }

  /// 判断某条原句是否正在生成中文意思。
  bool isLoadingSentence(String sentence) {
    final key = normalizeSentenceKey(sentence);
    return _loadingSentenceKeys.contains(key);
  }

  /// 获取所有重点词的记忆状态字典（只读）。
  Map<String, WordMemoryState> get memoryStates =>
      Map<String, WordMemoryState>.unmodifiable(_memoryStates);

  @visibleForTesting
  Map<String, WordMemoryState> get memoryStatesMapForTesting => _memoryStates;

  /// 获取某词的记忆状态（若不存在则以生词状态返回并缓存）。
  WordMemoryState memoryStateFor(String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return const WordMemoryState(word: '');
    return _memoryStates.putIfAbsent(key, () => WordMemoryState(word: key));
  }

  /// 根据作答正误、播放次数和耗时评估听觉熟悉度。
  static AuditoryFamiliarity evaluateAuditoryFamiliarity({
    required bool isCorrect,
    required int playCount,
    Duration? responseDuration,
  }) {
    if (!isCorrect) return AuditoryFamiliarity.lapse;
    if (playCount >= 3) return AuditoryFamiliarity.struggling;
    if (playCount == 2) return AuditoryFamiliarity.hesitant;
    final duration = responseDuration ?? Duration.zero;
    if (duration.inMilliseconds > 0 && duration.inMilliseconds <= 4000) {
      return AuditoryFamiliarity.instant;
    }
    return AuditoryFamiliarity.normal;
  }

  /// 实例方法便捷访问 [evaluateAuditoryFamiliarity]。
  AuditoryFamiliarity evaluateFamiliarity({
    required bool isCorrect,
    required int playCount,
    Duration? responseDuration,
  }) =>
      evaluateAuditoryFamiliarity(
        isCorrect: isCorrect,
        playCount: playCount,
        responseDuration: responseDuration,
      );

  /// 记录测验回答结果（盲听 4 选 1 等），结合听音次数与作答耗时自适应调节排期。
  AuditoryFamiliarity recordQuizResult(
    String word, {
    required bool isCorrect,
    int playCount = 1,
    Duration? responseDuration,
  }) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return AuditoryFamiliarity.lapse;
    final current = memoryStateFor(key);
    final now = DateTime.now();

    final familiarity = evaluateAuditoryFamiliarity(
      isCorrect: isCorrect,
      playCount: playCount,
      responseDuration: responseDuration,
    );

    int newStreak;
    int newProficiency;
    int newMistakes = current.mistakeCount;
    DateTime nextDue;

    switch (familiarity) {
      case AuditoryFamiliarity.instant:
      case AuditoryFamiliarity.normal:
        newStreak = current.streak + 1;
        newProficiency = (current.proficiency + 1).clamp(0, 4);
        final days =
            MemoryProficiency.fromLevel(newProficiency).defaultIntervalDays;
        nextDue = now.add(Duration(days: days));
        break;
      case AuditoryFamiliarity.hesitant:
        // 听 2 次：熟练度不升级，安排次日巩固（提高复习频次）
        newStreak = current.streak;
        newProficiency = current.proficiency;
        nextDue = now.add(const Duration(days: 1));
        break;
      case AuditoryFamiliarity.struggling:
        // 听 3 次及以上：即使答对也视为辨音吃力，streak 归零，安排当天/高频复习
        newStreak = 0;
        newProficiency =
            (current.proficiency == 0) ? 0 : (current.proficiency - 1);
        newMistakes += 1;
        nextDue = now;
        break;
      case AuditoryFamiliarity.lapse:
        // 答错：熟练度降级，streak 归零，立即安排复习
        newStreak = 0;
        newProficiency = (current.proficiency - 1).clamp(0, 4);
        newMistakes += 1;
        nextDue = now;
        break;
    }

    _memoryStates[key] = WordMemoryState(
      word: key,
      proficiency: newProficiency,
      lastReviewedAt: now.toIso8601String(),
      nextReviewDue: nextDue.toIso8601String(),
      streak: newStreak,
      mistakeCount: newMistakes,
    );
    _persistSync();
    notifyListeners();
    return familiarity;
  }

  /// 记录闪卡翻牌自评（rating: 0: 遗忘, 1: 模糊, 2: 熟悉, 3: 秒懂）。
  void recordSelfAssessment(String word, {required int rating}) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return;
    final current = memoryStateFor(key);
    final now = DateTime.now();

    int newStreak;
    int newProficiency;
    int newMistakes = current.mistakeCount;
    DateTime nextDue;

    switch (rating) {
      case 0: // 遗忘
        newStreak = 0;
        newProficiency = 0;
        newMistakes += 1;
        nextDue = now;
        break;
      case 1: // 模糊
        newStreak = 0;
        newProficiency = (current.proficiency == 0) ? 0 : current.proficiency;
        nextDue = now.add(const Duration(days: 1));
        break;
      case 2: // 熟悉
        newStreak = current.streak + 1;
        newProficiency = (current.proficiency + 1).clamp(0, 4);
        final days = MemoryProficiency.fromLevel(newProficiency).defaultIntervalDays;
        nextDue = now.add(Duration(days: days));
        break;
      case 3: // 秒懂
      default:
        newStreak = current.streak + 2;
        newProficiency = (current.proficiency < 3) ? 3 : 4;
        final days = MemoryProficiency.fromLevel(newProficiency).defaultIntervalDays;
        nextDue = now.add(Duration(days: (days * 1.5).round()));
        break;
    }

    _memoryStates[key] = WordMemoryState(
      word: key,
      proficiency: newProficiency,
      lastReviewedAt: now.toIso8601String(),
      nextReviewDue: nextDue.toIso8601String(),
      streak: newStreak,
      mistakeCount: newMistakes,
    );
    _persistSync();
    notifyListeners();
  }

  /// 获取今日到期需复习的重点词列表。
  List<String> getDueWords({DateTime? asOf}) {
    final checkTime = asOf ?? DateTime.now();
    return _focusedWords.where((w) {
      final s = _memoryStates[w];
      if (s == null) return true;
      return s.isDue(asOf: checkTime);
    }).toList();
  }

  /// 获取易错词强化列表（历史答错且尚未达到熟练掌握）。
  List<String> getMistakeWords() {
    return _focusedWords.where((w) {
      final s = _memoryStates[w];
      return s != null && s.isMistake && !s.isMastered;
    }).toList();
  }

  /// 获取已掌握的重点词列表。
  List<String> getMasteredWords() {
    return _focusedWords.where((w) {
      final s = _memoryStates[w];
      return s != null && s.isMastered;
    }).toList();
  }

  int get dueCount => getDueWords().length;
  int get mistakeCount => getMistakeWords().length;
  int get masteredCount => getMasteredWords().length;

  /// 记录某词被学习（如在沉浸刷词模式中浏览学习），更新其最近学习时间戳。
  void recordWordStudied(String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return;
    final current = memoryStateFor(key);
    final now = DateTime.now();

    _memoryStates[key] = WordMemoryState(
      word: key,
      proficiency: current.proficiency,
      lastReviewedAt: now.toIso8601String(),
      nextReviewDue: current.nextReviewDue,
      streak: current.streak,
      mistakeCount: current.mistakeCount,
    );
    _persistSync();
    notifyListeners();
  }

  /// 获取指定时间范围内学习/自评过的重点单词列表。
  List<String> getWordsStudiedInRange(ReviewTimeRange range, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return _focusedWords.where((word) {
      final state = _memoryStates[word];
      if (state == null || state.lastReviewedAt.isEmpty) return false;
      final reviewedTime = DateTime.tryParse(state.lastReviewedAt);
      if (reviewedTime == null) return false;

      return switch (range) {
        ReviewTimeRange.today =>
          reviewedTime.isAfter(startOfToday) || reviewedTime.isAtSameMomentAs(startOfToday),
        ReviewTimeRange.last3Days =>
          reviewedTime.isAfter(now.subtract(const Duration(days: 3))),
        ReviewTimeRange.last7Days =>
          reviewedTime.isAfter(now.subtract(const Duration(days: 7))),
        ReviewTimeRange.last30Days =>
          reviewedTime.isAfter(now.subtract(const Duration(days: 30))),
        ReviewTimeRange.allStudied => true,
      };
    }).toList();
  }

  /// 获取指定时间范围内学习过的单词总数。
  int countWordsStudiedInRange(ReviewTimeRange range, {DateTime? asOf}) =>
      getWordsStudiedInRange(range, asOf: asOf).length;

  /// 各练习模式保存的断点进度（只读快照）。
  Map<String, String> get practiceProgress =>
      Map.unmodifiable(_practiceProgress);

  /// 读取指定模式最近学习到的单词。
  String? getPracticeProgress(String mode) => _practiceProgress[mode];

  /// 保存指定练习模式的当前单词进度。
  void savePracticeProgress(String mode, String word) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return;
    if (_practiceProgress[mode] == key) return;
    _practiceProgress[mode] = key;
    _persistSync();
    notifyListeners();
  }

  /// 清除指定练习模式的断点进度（如完成当轮练习结算）。
  void clearPracticeProgress(String mode) {
    if (!_practiceProgress.containsKey(mode)) return;
    _practiceProgress.remove(mode);
    _persistSync();
    notifyListeners();
  }

  /// 判断某段文本是否正在合成 TTS 音频。
  bool isSynthesizingTts(String text) {
    final key = ttsCacheKey(text);
    return _loadingTtsKeys.contains(key);
  }

  /// 归一化原句缓存键（折叠连续空白并去首尾空格）。
  static String normalizeSentenceKey(String sentence) =>
      sentence.trim().replaceAll(_wsCollapse, ' ');

  /// 计算文本的确定性 FNV-1a 64-bit 十六进制哈希，用作 TTS 缓存文件名。
  static String ttsCacheKey(String text) {
    final normalized = normalizeSentenceKey(text).toLowerCase();
    final bytes = utf8.encode(normalized);
    // 53-bit 安全整数哈希（兼容 Dart VM 与 Web）
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF;
      h2 ^= (b + 0x9e3779b9) & 0xFFFFFFFF;
      h2 = (h2 * 0x85ebca6b) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}'
        '${h2.toRadixString(16).padLeft(8, '0')}';
  }

  /// 切换单词的「⭐ 重点关注」状态。
  ///
  /// 方案 A：当开启重点关注时，若传入了该词所属原句列表 [sentences]，
  /// 后台自动立即补全该词的音标/词性/中文释义及所有所属原句的中文翻译。
  bool toggleFocus(
    String word, {
    List<String> sentences = const [],
    bool autoEnrich = true,
  }) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return false;
    final nowFocused = !_focusedWords.contains(key);
    if (nowFocused) {
      _focusedWords.add(key);
      _memoryStates.putIfAbsent(key, () => WordMemoryState(word: key));
    } else {
      _focusedWords.remove(key);
    }
    _persistSync();
    notifyListeners();

    if (nowFocused && autoEnrich) {
      ensureWordProfile(key);
      if (sentences.isNotEmpty) {
        ensureSentenceTranslations(key, sentences);
      }
    }
    return nowFocused;
  }

  /// 显式设置重点关注状态。
  void setFocus(
    String word,
    bool focused, {
    List<String> sentences = const [],
    bool autoEnrich = true,
  }) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return;
    final changed = focused ? _focusedWords.add(key) : _focusedWords.remove(key);
    if (changed) {
      if (focused) {
        _memoryStates.putIfAbsent(key, () => WordMemoryState(word: key));
      }
      _persistSync();
      notifyListeners();
    }
    if (focused && autoEnrich) {
      ensureWordProfile(key);
      if (sentences.isNotEmpty) {
        ensureSentenceTranslations(key, sentences);
      }
    }
  }

  /// 确保单词具备音标、词性与中文解释（已缓存则直接返回，否则查词典 → 回退大模型）。
  Future<VocabularyWordProfile?> ensureWordProfile(
    String word, {
    bool forceRefresh = false,
  }) {
    final key = MeetingVocabularyIndex.normalizeWord(word);
    if (key.isEmpty) return Future.value(null);

    if (!forceRefresh) {
      final cached = _wordProfiles[key];
      if (cached != null && cached.hasDefinition) {
        return Future.value(cached);
      }
      final existingFuture = _inFlightProfiles[key];
      if (existingFuture != null) return existingFuture;
    }

    final future = _fetchWordProfile(key);
    _inFlightProfiles[key] = future;
    return future.whenComplete(() {
      _inFlightProfiles.remove(key);
    });
  }

  Future<VocabularyWordProfile?> _fetchWordProfile(String key) async {
    _loadingProfileWords.add(key);
    notifyListeners();

    try {
      String phonetic = _wordProfiles[key]?.phonetic ?? '';
      String partOfSpeech = _wordProfiles[key]?.partOfSpeech ?? '';
      String definitionZh = '';

      // 1. 优先查询内置词典服务（有道词典毫秒级返回中文释义与音标）
      try {
        final dict = await _dictionaryLookup(key);
        if (dict != null) {
          if (dict.phonetic != null && dict.phonetic!.trim().isNotEmpty) {
            phonetic = dict.phonetic!.trim();
          }
          final posSet = <String>{};
          final zhDefs = <String>[];
          for (final m in dict.meanings) {
            final pos = m.partOfSpeech.trim();
            if (pos.isNotEmpty) posSet.add(pos);
            for (final d in m.definitions) {
              final trimmed = d.trim();
              if (trimmed.isNotEmpty && _cjkPattern.hasMatch(trimmed)) {
                zhDefs.add(pos.isNotEmpty ? '$pos $trimmed' : trimmed);
              }
            }
          }
          if (posSet.isNotEmpty) {
            partOfSpeech = posSet.join(' / ');
          }
          if (zhDefs.isNotEmpty) {
            definitionZh = zhDefs.take(4).join('；');
          }
        }
      } catch (e) {
        debugPrint('[VocabularyStudyStore] 词典查询 "$key" 异常: $e');
      }

      // 2. 若词典未命中中文释义，回退调用 text 槽位大模型生成
      final canUseLlm = _hasCustomTextGenerator ||
          AiConfigStore.instance.providers.any((p) => p.enabled);
      if (definitionZh.isEmpty && canUseLlm) {
        try {
          final llmProfile = await _generateWordProfileViaLlm(key);
          if (llmProfile != null) {
            if (phonetic.isEmpty && llmProfile.phonetic.isNotEmpty) {
              phonetic = llmProfile.phonetic;
            }
            if (partOfSpeech.isEmpty && llmProfile.partOfSpeech.isNotEmpty) {
              partOfSpeech = llmProfile.partOfSpeech;
            }
            if (llmProfile.definitionZh.isNotEmpty) {
              definitionZh = llmProfile.definitionZh;
            }
          }
        } catch (e) {
          debugPrint('[VocabularyStudyStore] LLM 生成单词 "$key" 释义失败: $e');
        }
      }

      if (phonetic.isEmpty && partOfSpeech.isEmpty && definitionZh.isEmpty) {
        return _wordProfiles[key];
      }

      final profile = VocabularyWordProfile(
        word: key,
        phonetic: phonetic,
        partOfSpeech: partOfSpeech,
        definitionZh: definitionZh,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      _wordProfiles[key] = profile;
      _persistSync();
      return profile;
    } finally {
      _loadingProfileWords.remove(key);
      notifyListeners();
    }
  }

  Future<VocabularyWordProfile?> _generateWordProfileViaLlm(String word) async {
    final prompt = '''
请为 IT 职场英语会议中的单词 "$word" 提供音标、词性缩写与简明中文释义。
只输出严格合法的 JSON 对象，不要包含 Markdown 代码块或其它说明文字：
{"phonetic": "/.../", "partOfSpeech": "n. / v.", "definitionZh": "简明中文解释（包含常见含义与IT会议语境含义）"}
''';
    final raw = await _textGenerator.generate(prompt);
    final parsed = _extractJsonObject(raw);
    if (parsed == null) {
      final clean = raw.trim();
      if (clean.isEmpty) return null;
      return VocabularyWordProfile(
        word: word,
        definitionZh: clean,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
    return VocabularyWordProfile(
      word: word,
      phonetic: (parsed['phonetic'] as String? ?? '').trim(),
      partOfSpeech: (parsed['partOfSpeech'] as String? ?? '').trim(),
      definitionZh: (parsed['definitionZh'] as String? ?? '').trim(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// 确保给定的原句列表都已生成中文意思（仅对未缓存的句子调用大模型翻译）。
  Future<Map<String, String>> ensureSentenceTranslations(
    String word,
    List<String> sentences, {
    bool forceRefresh = false,
  }) async {
    final pending = <String>[];
    final seenKeys = <String>{};
    for (final s in sentences) {
      final key = normalizeSentenceKey(s);
      if (key.isEmpty || !seenKeys.add(key)) continue;
      if (!forceRefresh && _sentenceTranslations.containsKey(key)) continue;
      if (_loadingSentenceKeys.contains(key)) continue;
      pending.add(key);
    }

    if (pending.isEmpty) {
      return {
        for (final s in sentences)
          if (_sentenceTranslations[normalizeSentenceKey(s)] != null)
            normalizeSentenceKey(s):
                _sentenceTranslations[normalizeSentenceKey(s)]!,
      };
    }

    _loadingSentenceKeys.addAll(pending);
    notifyListeners();

    try {
      if (pending.length == 1) {
        final single = pending.first;
        final prompt = '''
请将以下 IT 英语会议原句翻译为自然、准确的中文（句中包含重点单词 "$word"）。
只输出中文译文，不要带引号或任何多余解释：
$single
''';
        final raw = await _textGenerator.generate(prompt);
        final zh = _cleanSingleTranslation(raw);
        if (zh.isNotEmpty) {
          _sentenceTranslations[single] = zh;
          _persistSync();
        }
      } else {
        final numbered = <String>[
          for (var i = 0; i < pending.length; i++) '${i + 1}. ${pending[i]}',
        ].join('\n');
        final prompt = '''
请将以下 ${pending.length} 条 IT 英语会议原句翻译为自然、准确的中文（句中包含重点单词 "$word"）。
只输出严格合法的 JSON 字符串数组（长度必须为 ${pending.length}，顺序与输入严格一一对应），不要输出任何其它解释：
["第1句中文译文", "第2句中文译文"]

待翻译原句：
$numbered
''';
        final raw = await _textGenerator.generate(prompt);
        final list = _extractJsonStringList(raw);
        if (list != null && list.isNotEmpty) {
          for (var i = 0; i < pending.length && i < list.length; i++) {
            final zh = list[i].trim();
            if (zh.isNotEmpty) {
              _sentenceTranslations[pending[i]] = zh;
            }
          }
          _persistSync();
        } else {
          // 兜底：按行切分解析
          final lines = raw
              .split('\n')
              .map((l) => l.replaceFirst(RegExp(r'^\d+[\.\、\)\s]+'), '').trim())
              .where((l) => l.isNotEmpty)
              .toList();
          for (var i = 0; i < pending.length && i < lines.length; i++) {
            _sentenceTranslations[pending[i]] = lines[i];
          }
          if (lines.isNotEmpty) {
            _persistSync();
          }
        }
      }
    } catch (e) {
      debugPrint('[VocabularyStudyStore] 翻译句子失败 ("$word"): $e');
    } finally {
      _loadingSentenceKeys.removeAll(pending);
      notifyListeners();
    }

    return {
      for (final s in sentences)
        if (_sentenceTranslations[normalizeSentenceKey(s)] != null)
          normalizeSentenceKey(s):
              _sentenceTranslations[normalizeSentenceKey(s)]!,
    };
  }

  /// 判断待发音文本是否为单个英文单词（无空格，纯英文字符/连字符/下划线）。
  static bool isSingleEnglishWord(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) return false;
    return RegExp(r"^[a-zA-Z\-'_]+$").hasMatch(trimmed);
  }

  /// 默认权威词典外教真人单词发音拉取器（有道词典真人原声接口，美音 type=2 / 英音 type=1）。
  static Future<Uint8List?> _defaultFetchDictionaryAudio(
    String word,
    VocabularyAccent accent,
  ) async {
    final type = accent == VocabularyAccent.uk ? 1 : 2;
    final uri = Uri.parse(
      'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(word)}&type=$type',
    );
    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
          'Referer': 'https://dict.youdao.com/',
        },
      ).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 && response.bodyBytes.length > 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('[VocabularyStudyStore] 词典真人发音拉取失败 "$word": $e');
    }
    return null;
  }

  /// 默认 macOS 原生离线语音发音（美音 Samantha / 英音 Daniel）。
  static Future<Uint8List?> _defaultSynthesizeViaMacNative(
    String word,
    VocabularyAccent accent,
  ) async {
    if (!Platform.isMacOS) return null;
    final voice = accent == VocabularyAccent.uk ? 'Daniel' : 'Samantha';
    final tempDir = Directory.systemTemp;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final m4aFile = File('${tempDir.path}/mac_native_$id.m4a');
    try {
      final sayProc = await Process.run('say', [
        '-v', voice,
        '-o', m4aFile.path,
        word,
      ]);
      if (sayProc.exitCode == 0 &&
          await m4aFile.exists() &&
          await m4aFile.length() > 200) {
        return await m4aFile.readAsBytes();
      }
    } catch (e) {
      debugPrint('[VocabularyStudyStore] macOS 原生语音合成失败 "$word": $e');
    } finally {
      try {
        if (await m4aFile.exists()) await m4aFile.delete();
      } catch (_) {}
    }
    return null;
  }

  /// 获取某段文本（单词或原句）的本地 TTS 缓存文件；若已存在且非空直接返回。
  File? cachedTtsFileFor(String text, {VocabularyAccent? overrideAccent}) {
    final trimmed = normalizeSentenceKey(text);
    if (trimmed.isEmpty) return null;
    final effectiveAccent = overrideAccent ?? _accent;

    if (isSingleEnglishWord(trimmed)) {
      final normWord = MeetingVocabularyIndex.normalizeWord(trimmed);
      final wordKey =
          ttsCacheKey('dict_word|${effectiveAccent.name}|$normWord');
      final wordFile = File(p.join(ttsCacheDir.path, '$wordKey.mp3'));
      if (wordFile.existsSync() && wordFile.lengthSync() > 0) {
        return wordFile;
      }
    }

    final key = ttsCacheKey('$_defaultVoiceId|$_styleInstruction|$trimmed');
    final file = File(p.join(ttsCacheDir.path, '$key.mp3'));
    if (file.existsSync() && file.lengthSync() > 0) {
      return file;
    }
    final legacyFile =
        File(p.join(ttsCacheDir.path, '${ttsCacheKey(trimmed)}.mp3'));
    if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) {
      return legacyFile;
    }
    return null;
  }

  /// 按需获取或实时调用 TTS 模型合成单词/原句发音并缓存到本地文件。
  ///
  /// 对于单个单词，严格按照三级降级链路执行：
  /// 1. 权威词典真人录音（美音/英音）
  /// 2. macOS 原生离线语音（Samantha / Daniel）
  /// 3. 商用 AI 云端大模型兜底保底
  ///
  /// 对于整句原句，保持现有说话人音色大模型合成。
  Future<File> synthesizeOrGetTtsFile(
    String text, {
    bool forceRegenerate = false,
    VocabularyAccent? overrideAccent,
  }) async {
    final cleaned = normalizeSentenceKey(text);
    if (cleaned.isEmpty) {
      throw ArgumentError('待合成文本为空');
    }

    final effectiveAccent = overrideAccent ?? _accent;

    // -------------------------------------------------------------------------
    // 1. 单个英文单词：多级高保真降级流
    // -------------------------------------------------------------------------
    if (isSingleEnglishWord(cleaned)) {
      final normWord = MeetingVocabularyIndex.normalizeWord(cleaned);
      final wordKey =
          ttsCacheKey('dict_word|${effectiveAccent.name}|$normWord');
      final targetFile = File(p.join(ttsCacheDir.path, '$wordKey.mp3'));

      if (!forceRegenerate &&
          targetFile.existsSync() &&
          targetFile.lengthSync() > 0) {
        return targetFile;
      }

      _loadingTtsKeys.add(wordKey);
      notifyListeners();

      try {
        Uint8List? audioBytes;

        // 第 1 级：权威词典真人原声 (美音 / 英音)
        try {
          audioBytes =
              await _dictionaryAudioFetcher(normWord, effectiveAccent);
        } catch (e) {
          debugPrint('[VocabularyStudyStore] 词典真人音频异常，尝试离线降级: $e');
        }

        // 第 2 级：macOS 系统离线语音 (Samantha / Daniel)
        if (audioBytes == null || audioBytes.isEmpty) {
          try {
            audioBytes =
                await _nativeSpeechSynthesizer(normWord, effectiveAccent);
          } catch (e) {
            debugPrint('[VocabularyStudyStore] 本机离线发音异常，尝试 AI 兜底: $e');
          }
        }

        // 第 3 级：商用 AI 云端 TTS 终极保底
        if (audioBytes == null || audioBytes.isEmpty) {
          audioBytes = await _ttsEngine.synthesize(
            cleaned,
            const TtsSynthesisConfig(
              mode: TtsMode.customAi,
              useSystemAiConfig: true,
            ).copyWith(
              customVoiceId: _defaultVoiceId,
              styleInstruction: _styleInstruction,
            ),
          );
        }

        if (audioBytes.isEmpty) {
          throw StateError('未能获取单词 "$cleaned" 的有效发音音频');
        }

        if (!ttsCacheDir.existsSync()) {
          ttsCacheDir.createSync(recursive: true);
        }
        final tmp = File('${targetFile.path}.tmp');
        tmp.writeAsBytesSync(audioBytes, flush: true);
        tmp.renameSync(targetFile.path);
        return targetFile;
      } finally {
        _loadingTtsKeys.remove(wordKey);
        notifyListeners();
      }
    }

    // -------------------------------------------------------------------------
    // 2. 长句 / 会议对话原句：维持商用 AI 说话人音色合成
    // -------------------------------------------------------------------------
    final key = ttsCacheKey('$_defaultVoiceId|$_styleInstruction|$cleaned');
    final targetFile = File(p.join(ttsCacheDir.path, '$key.mp3'));
    if (!forceRegenerate &&
        targetFile.existsSync() &&
        targetFile.lengthSync() > 0) {
      return targetFile;
    }

    final legacyFile =
        File(p.join(ttsCacheDir.path, '${ttsCacheKey(cleaned)}.mp3'));
    if (!forceRegenerate &&
        legacyFile.existsSync() &&
        legacyFile.lengthSync() > 0) {
      try {
        if (!ttsCacheDir.existsSync()) {
          ttsCacheDir.createSync(recursive: true);
        }
        legacyFile.copySync(targetFile.path);
        return targetFile;
      } catch (_) {
        return legacyFile;
      }
    }

    _loadingTtsKeys.add(key);
    notifyListeners();

    try {
      final bytes = await _ttsEngine.synthesize(
        cleaned,
        const TtsSynthesisConfig(
          mode: TtsMode.customAi,
          useSystemAiConfig: true,
        ).copyWith(
          customVoiceId: _defaultVoiceId,
          styleInstruction: _styleInstruction,
        ),
      );
      if (bytes.isEmpty) {
        throw StateError('TTS 模型返回了空音频');
      }
      if (!ttsCacheDir.existsSync()) {
        ttsCacheDir.createSync(recursive: true);
      }
      final tmp = File('${targetFile.path}.tmp');
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(targetFile.path);
      return targetFile;
    } finally {
      _loadingTtsKeys.remove(key);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // 内部持久化与解析辅助
  // ---------------------------------------------------------------------------

  VocabularyStudyData _readFromDiskSync() {
    try {
      final file = _storeFile;
      if (!file.existsSync()) return const VocabularyStudyData();
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const VocabularyStudyData();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const VocabularyStudyData();
      return VocabularyStudyData.fromJson(decoded);
    } catch (e) {
      debugPrint('[VocabularyStudyStore] 读取助学数据失败，已回退空数据: $e');
      return const VocabularyStudyData();
    }
  }

  void _persistSync() {
    try {
      if (!_baseDir.existsSync()) {
        _baseDir.createSync(recursive: true);
      }
      final data = VocabularyStudyData(
        focusedWords: _focusedWords,
        wordProfiles: _wordProfiles,
        sentenceTranslations: _sentenceTranslations,
        memoryStates: _memoryStates,
        practiceProgress: _practiceProgress,
        accent: _accent,
      );
      final target = _storeFile;
      final tmp = File('${target.path}.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data.toJson()),
        flush: true,
      );
      tmp.renameSync(target.path);
    } catch (e) {
      debugPrint('[VocabularyStudyStore] 保存助学数据失败: $e');
    }
  }

  static Map<String, dynamic>? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static List<String>? _extractJsonStringList(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is List) {
        return decoded.map((e) => '$e').toList();
      }
    } catch (_) {}
    return null;
  }

  static String _cleanSingleTranslation(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith('“') && s.endsWith('”'))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }
}
