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
import 'package:path/path.dart' as p;

import '../../../services/ai_config_store.dart';
import '../../../services/app_paths.dart';
import '../../lookup_panel/services/dictionary_service.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import 'meeting_vocabulary_index.dart';
import 'rehearsal_llm.dart';
import 'rehearsal_text_generator.dart';
import 'role_voice_map.dart';

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

/// 词汇表助学持久化快照。
class VocabularyStudyData {
  /// 已标记为「⭐ 重点关注」的归一化单词集合。
  final Set<String> focusedWords;

  /// 单词 → 音标/词性/中文释义缓存。
  final Map<String, VocabularyWordProfile> wordProfiles;

  /// 归一化原句文本 → 中文句意缓存。
  final Map<String, String> sentenceTranslations;

  const VocabularyStudyData({
    this.focusedWords = const {},
    this.wordProfiles = const {},
    this.sentenceTranslations = const {},
  });

  Map<String, dynamic> toJson() => {
        'focusedWords': focusedWords.toList()..sort(),
        'wordProfiles': {
          for (final e in wordProfiles.entries) e.key: e.value.toJson(),
        },
        'sentenceTranslations': sentenceTranslations,
      };

  factory VocabularyStudyData.fromJson(Map<String, dynamic> json) {
    final rawFocused = json['focusedWords'] as List? ?? const [];
    final rawProfiles =
        json['wordProfiles'] as Map<String, dynamic>? ?? const {};
    final rawSentences =
        json['sentenceTranslations'] as Map<String, dynamic>? ?? const {};

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
  String _defaultVoiceId;
  String _styleInstruction;

  late Set<String> _focusedWords;
  late Map<String, VocabularyWordProfile> _wordProfiles;
  late Map<String, String> _sentenceTranslations;

  final Map<String, Future<VocabularyWordProfile?>> _inFlightProfiles = {};
  final Set<String> _loadingProfileWords = {};
  final Set<String> _loadingSentenceKeys = {};
  final Set<String> _loadingTtsKeys = {};

  VocabularyStudyStore({
    Directory? baseDir,
    Future<DictionaryResult?> Function(String word)? dictionaryLookup,
    RehearsalTextGenerator? textGenerator,
    TtsEngine? ttsEngine,
    String? defaultVoiceId,
    String? styleInstruction,
  })  : _baseDir = baseDir ?? _resolveDefaultBaseDir(),
        _dictionaryLookup = dictionaryLookup ?? DictionaryService.lookup,
        _textGenerator = textGenerator ?? const SlotTextGenerator(),
        _hasCustomTextGenerator = textGenerator != null,
        _ttsEngine = ttsEngine ?? OpenAiTtsEngine(),
        _defaultVoiceId = defaultVoiceId ?? _resolveDefaultVoiceId(),
        _styleInstruction = styleInstruction ?? _resolveDefaultStyle() {
    final initial = _readFromDiskSync();
    _focusedWords = Set<String>.from(initial.focusedWords);
    _wordProfiles =
        Map<String, VocabularyWordProfile>.from(initial.wordProfiles);
    _sentenceTranslations =
        Map<String, String>.from(initial.sentenceTranslations);
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
  /// MiMo 音色。此处改为按当前 TTS 槽位探测供应商。
  static String _resolveDefaultVoiceId() {
    final store = AiConfigStore.instance;
    final candidates = store.slotBindings['tts'] ?? [];
    for (final cand in candidates) {
      final provider = store.providers.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == cand.providerId && p?.enabled == true,
        orElse: () => null,
      );
      if (provider == null) continue;
      final model = cand.model.isNotEmpty ? cand.model : '';
      final isMiMo = OpenAiTtsEngine.isMimoModel(
        model,
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      );
      if (isMiMo) return 'mimo_default';
    }
    return VoicePool.zhixingjiejie.id;
  }

  /// 解析默认 MiMo 风格指令：绑定 MiMo 时给保守默认，否则空串。
  static String _resolveDefaultStyle() {
    final store = AiConfigStore.instance;
    final candidates = store.slotBindings['tts'] ?? [];
    for (final cand in candidates) {
      final provider = store.providers.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == cand.providerId && p?.enabled == true,
        orElse: () => null,
      );
      if (provider == null) continue;
      final model = cand.model.isNotEmpty ? cand.model : '';
      final isMiMo = OpenAiTtsEngine.isMimoModel(
        model,
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      );
      if (isMiMo) return '自然、清晰、语速适中、略带情感';
    }
    return '';
  }

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

  /// 获取某段文本（单词或原句）的本地 TTS 缓存文件；若已存在且非空直接返回。
  File? cachedTtsFileFor(String text) {
    final trimmed = normalizeSentenceKey(text);
    if (trimmed.isEmpty) return null;
    final file = File(p.join(ttsCacheDir.path, '${ttsCacheKey(trimmed)}.mp3'));
    if (file.existsSync() && file.lengthSync() > 0) {
      return file;
    }
    return null;
  }

  /// 按需获取或实时调用 TTS 模型合成单词/原句发音并缓存到本地文件。
  Future<File> synthesizeOrGetTtsFile(
    String text, {
    bool forceRegenerate = false,
  }) async {
    final cleaned = normalizeSentenceKey(text);
    if (cleaned.isEmpty) {
      throw ArgumentError('待合成文本为空');
    }

    final key = ttsCacheKey('$_defaultVoiceId|$_styleInstruction|$cleaned');
    final targetFile = File(p.join(ttsCacheDir.path, '$key.mp3'));
    if (!forceRegenerate &&
        targetFile.existsSync() &&
        targetFile.lengthSync() > 0) {
      return targetFile;
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
