/// 全局词汇表与反查（含原句目标词高亮、「⭐ 重点关注」独立管理与 AI/TTS 助学卡片）。
///
/// 两个视图合一：
///
/// ```
/// 词频列表（全部词汇 / ⭐ 重点关注）
///   └─ 展开一个词 →
///        ├─ 单词助学头卡：音标 · 词性 · 中文解释 · [🔊 单词发音]
///        └─ 原句出处列表：高亮当前单词的原句 · 所属句子中文意思 · [🔊 句子发音] · [↗ 跳到原会议]
/// ```
///
/// **查词永远有结果**：折叠只影响主列表的默认展示，不影响查询或「⭐ 重点关注」列表。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/ai_config_store.dart';
import '../../../services/ai_logger.dart';
import '../../../theme/app_theme.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import '../services/listening_host.dart';
import '../services/meeting_vocabulary_index.dart';
import '../services/pronunciation_audio_backend.dart';
import '../services/role_voice_map.dart';
import '../services/vocabulary_study_store.dart';

/// 词汇表顶部筛选视图。
enum VocabularyFilterTab {
  /// 全部词汇。
  all,

  /// 仅显示标记了「⭐ 重点关注」的词汇。
  focused,
}

/// 在原句 [sentence] 中定位所有归一化后等于 [targetWord] 的词段起止下标 `[start, end)`。
///
/// 兼容大小写变形与末尾 `'s` / `’s` 所有格变形（例如 `targetWord = "governance"` 时，
/// 原句中的 `"Governance"`、`"governance's"`、`"Governance’s"` 均会被命中）。
@visibleForTesting
List<({int start, int end})> findWordHighlightRanges(
  String sentence,
  String targetWord,
) {
  final normalizedTarget = MeetingVocabularyIndex.normalizeWord(targetWord);
  if (normalizedTarget.isEmpty || sentence.isEmpty) return const [];

  final tokenRegex = RegExp(r"[A-Za-z][A-Za-z0-9'\-’]*");
  final ranges = <({int start, int end})>[];
  for (final match in tokenRegex.allMatches(sentence)) {
    final token = match.group(0)!;
    if (MeetingVocabularyIndex.normalizeWord(token) == normalizedTarget) {
      ranges.add((start: match.start, end: match.end));
    }
  }
  return ranges;
}

/// 构建带目标单词高亮的 [TextSpan] 列表。
@visibleForTesting
List<InlineSpan> buildHighlightedSentenceSpans(
  String sentence,
  String targetWord, {
  required TextStyle normalStyle,
  required TextStyle highlightStyle,
}) {
  final ranges = findWordHighlightRanges(sentence, targetWord);
  if (ranges.isEmpty) {
    return [TextSpan(text: sentence, style: normalStyle)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final range in ranges) {
    if (range.start > cursor) {
      spans.add(
        TextSpan(
          text: sentence.substring(cursor, range.start),
          style: normalStyle,
        ),
      );
    }
    spans.add(
      TextSpan(
        text: sentence.substring(range.start, range.end),
        style: highlightStyle,
      ),
    );
    cursor = range.end;
  }
  if (cursor < sentence.length) {
    spans.add(
      TextSpan(
        text: sentence.substring(cursor),
        style: normalStyle,
      ),
    );
  }
  return spans;
}

/// 词汇表浏览对话框。
class VocabularyBrowserDialog extends StatefulWidget {
  final MeetingVocabularyIndex index;

  /// 点击一条出处：跳到该会议该轮播放。
  final void Function(VocabularyPosting posting) onJump;

  /// 可注入的词汇助学存储（测试可传入自定义实例；为空时内部自动创建）。
  final VocabularyStudyStore? studyStore;

  /// 可注入的发音**设备后端**（测试注入假后端以拦截播放并断言；为空时使用真实
  /// audioplayers）。它只替换**设备**、不替换播放编排——编排始终在本组件内执行，
  /// 因此"停止 → 播放 → 等待完成（带超时上限）"在测试里与生产走同一段代码。
  final PronunciationAudioBackend? audioBackend;

  const VocabularyBrowserDialog({
    super.key,
    required this.index,
    required this.onJump,
    this.studyStore,
    this.audioBackend,
  });

  @override
  State<VocabularyBrowserDialog> createState() =>
      _VocabularyBrowserDialogState();
}

class _VocabularyBrowserDialogState extends State<VocabularyBrowserDialog> {
  final _queryCtrl = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _entryKeys = {};

  late final VocabularyStudyStore _studyStore;
  late final bool _ownsStudyStore;
  PronunciationAudioBackend? _audioBackend;

  VocabularyFilterTab _activeTab = VocabularyFilterTab.all;
  bool _showStopwords = false;
  bool _showNoisy = false;
  String _query = '';
  final Set<String> _expandedWords = {};
  String? _playingTtsKey;
  String? _ttsErrorMessage;

  /// **单词级**发音失败的可见标记（键为 TTS 缓存键）。
  ///
  /// 失败文案只有一行全局提示，不足以让用户知道"是哪个词坏了"；这里按词标记，
  /// 该词成功播放后自动清除。
  final Set<String> _failedTtsKeys = {};

  // 连续播放播表状态
  bool _isContinuousPlaying = false;
  int _continuousPlayIndex = -1;
  bool _continuousLoop = false;
  Timer? _continuousTimer;

  @override
  void initState() {
    super.initState();
    if (widget.studyStore != null) {
      _studyStore = widget.studyStore!;
      _ownsStudyStore = false;
    } else {
      _studyStore = VocabularyStudyStore();
      _ownsStudyStore = true;
    }
    _studyStore.addListener(_onStudyStoreChanged);
  }

  @override
  void dispose() {
    _continuousTimer?.cancel();
    _studyStore.removeListener(_onStudyStoreChanged);
    if (_ownsStudyStore) {
      _studyStore.dispose();
    }
    // 只释放自己创建的后端；调用方注入的由调用方负责。
    if (widget.audioBackend == null) {
      _audioBackend?.dispose();
    }
    _listScrollController.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onStudyStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onFilterChanged() {
    if (_isContinuousPlaying) {
      _stopContinuousPlayback();
    }
  }

  /// 把「⭐ 重点关注」词列表送入迷你播放器（词汇磨耳朵模式）。
  ///
  /// 先停掉对话框自身的连播（避免两处同时发声），再用展示形态还原词形并过滤空词，
  /// 交由 `ListeningHost` 打开迷你窗并开播。
  Future<void> _sendFocusedToMiniPlayer() async {
    if (_isContinuousPlaying) {
      _stopContinuousPlayback();
    }
    // 重点词是归一化词形，用 index.display 还原首次出现的展示形态。
    final words = _studyStore.focusedWords
        .map((w) => widget.index.display[w] ?? w)
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return;
    try {
      await ListeningHost.instance.openMiniWindowWithVocab(words, autoplay: true);
    } catch (e, st) {
      AiLogger.logError(
        '送入迷你播放器失败: ${e.runtimeType}: $e\n$st',
        providerName: 'TTS(词汇表)',
      );
      if (mounted) {
        setState(() => _ttsErrorMessage = '送入迷你播放器失败：${_describeError(e)}');
      }
    }
  }

  Future<void> _playTts(String text) async {
    if (_isContinuousPlaying) {
      _pauseContinuousPlayback();
    }
    final cleaned = VocabularyStudyStore.normalizeSentenceKey(text);
    if (cleaned.isEmpty) return;
    final key = VocabularyStudyStore.ttsCacheKey(cleaned);

    setState(() {
      _ttsErrorMessage = null;
      _playingTtsKey = key;
    });

    try {
      final file = await _synthesizeOrReport(cleaned);
      if (file == null) {
        _markWordTtsFailed(key, failed: true);
        return;
      }
      if (!mounted) return;
      final ok = await _playFileOrReport(file, detail: '文本="$cleaned"');
      _markWordTtsFailed(key, failed: !ok);
    } finally {
      if (mounted && _playingTtsKey == key) {
        setState(() {
          _playingTtsKey = null;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 发音播放：三条入口（单词发音 / 句子发音 / 连续磨耳朵）共用同一套编排
  // ---------------------------------------------------------------------------

  /// 合成阶段：失败即落日志并给出「生成失败」文案，返回 null。
  ///
  /// 与播放阶段**分开捕获**：原先同一个 catch 两阶段共用、文案却只写"生成失败"，
  /// 阶段信息被抹掉——排查时无法判断故障出在请求链路还是播放器。
  Future<File?> _synthesizeOrReport(String cleaned) async {
    // 缓存是否命中是重要现场：命中时合成既不发请求、也不打日志，靠"日志有无条目"
    // 反推并不可靠——直接记下来。
    final wasCached = _studyStore.cachedTtsFileFor(cleaned) != null;
    try {
      return await _studyStore.synthesizeOrGetTtsFile(cleaned);
    } catch (e, st) {
      _reportPronunciationFailure(
        '合成',
        e,
        st,
        detail: '词="$cleaned" 缓存=${wasCached ? '命中' : '未命中'}',
      );
      if (mounted) {
        setState(() => _ttsErrorMessage = '发音生成失败：${_describeError(e)}');
      }
      return null;
    }
  }

  /// 播放阶段：失败即落日志并给出「播放失败」文案。返回是否播放成功。
  Future<bool> _playFileOrReport(
    File file, {
    bool waitForCompletion = false,
    String? detail,
  }) async {
    try {
      await _playFile(file, waitForCompletion: waitForCompletion);
      return true;
    } catch (e, st) {
      _reportPronunciationFailure('播放', e, st, detail: detail);
      if (mounted) {
        setState(() => _ttsErrorMessage = '发音播放失败：${_describeError(e)}');
      }
      return false;
    }
  }

  /// 播放**编排**：停止 → 播放 →（可选）等待完成。三条发音入口共用此处。
  ///
  /// 这里只做编排，设备操作全部经 [PronunciationAudioBackend]。接缝之所以放在
  /// 设备边界（而不是整段替换播放逻辑），是为了让测试注入假后端时替换的是**设备**
  /// 而非**逻辑**——下面这几行（尤其"带上限的等待"）才与生产一致地被测试执行。
  Future<void> _playFile(File file, {bool waitForCompletion = false}) async {
    final backend = _audioBackend ??=
        widget.audioBackend ?? AudioplayersPronunciationBackend();
    await backend.stop();
    await backend.playFile(file.path);
    if (waitForCompletion) {
      final completer = Completer<void>();
      final sub = backend.onPlayerComplete.listen(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      try {
        await completer.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      } finally {
        sub.cancel();
      }
    }
  }

  /// 把播放链路的异常记入应用日志与调试输出（含运行时类型、消息与堆栈）。
  ///
  /// 必须**同时**落日志：`type '() => Null' is not a subtype of type ...` 这类
  /// 只在运行期成立的错误，一旦被 catch 压成一句笼统文案，复现一次也定位不到
  /// 抛错位置。
  void _reportPronunciationFailure(
    String stage,
    Object error,
    StackTrace stack, {
    String? detail,
  }) {
    final cause = '${error.runtimeType}: $error';
    final brief = detail == null
        ? ''
        : ' [${detail.length > 60 ? '${detail.substring(0, 60)}…' : detail}]';
    AiLogger.logError(
      '词汇表发音失败[$stage]$brief $cause\n$stack',
      providerName: 'TTS(词汇表)',
    );
    debugPrint('[VocabTTS][$stage]$brief $cause\n$stack');
  }

  /// 失败文案摘要：运行时类型 + 消息（过长截断），让用户抄得下来。
  String _describeError(Object error) {
    final text = '$error';
    final brief = text.length > 160 ? '${text.substring(0, 160)}…' : text;
    return '${error.runtimeType} · $brief';
  }

  /// 按词记录发音失败，成功时清除；UI 表现为该词旁的红色警标。
  void _markWordTtsFailed(String key, {required bool failed}) {
    final changed =
        failed ? _failedTtsKeys.add(key) : _failedTtsKeys.remove(key);
    if (changed && mounted) setState(() {});
  }

  void _startContinuousPlayback({int startIndex = 0}) {
    final entries = _visibleEntries();
    if (entries.isEmpty) return;

    _continuousTimer?.cancel();
    final validIndex = (startIndex >= 0 && startIndex < entries.length)
        ? startIndex
        : 0;

    setState(() {
      _isContinuousPlaying = true;
      _continuousPlayIndex = validIndex;
      _ttsErrorMessage = null;
    });

    _playWordAtContinuousIndex();
  }

  void _pauseContinuousPlayback() {
    _continuousTimer?.cancel();
    _audioBackend?.stop();
    setState(() {
      _isContinuousPlaying = false;
      _playingTtsKey = null;
    });
  }

  void _stopContinuousPlayback() {
    _continuousTimer?.cancel();
    _audioBackend?.stop();
    setState(() {
      _isContinuousPlaying = false;
      _continuousPlayIndex = -1;
      _playingTtsKey = null;
    });
  }

  void _previousContinuousWord() {
    _continuousTimer?.cancel();
    final entries = _visibleEntries();
    if (entries.isEmpty) return;
    final nextIdx = (_continuousPlayIndex - 1).clamp(0, entries.length - 1);
    setState(() {
      _continuousPlayIndex = nextIdx;
      _isContinuousPlaying = true;
    });
    _playWordAtContinuousIndex();
  }

  void _nextContinuousWord() {
    _continuousTimer?.cancel();
    final entries = _visibleEntries();
    if (entries.isEmpty) return;

    if (_continuousPlayIndex + 1 < entries.length) {
      setState(() {
        _continuousPlayIndex++;
        _isContinuousPlaying = true;
      });
      _playWordAtContinuousIndex();
    } else if (_continuousLoop) {
      setState(() {
        _continuousPlayIndex = 0;
        _isContinuousPlaying = true;
      });
      _playWordAtContinuousIndex();
    } else {
      _stopContinuousPlayback();
    }
  }

  Future<void> _playWordAtContinuousIndex() async {
    if (!_isContinuousPlaying || !mounted) return;
    final entries = _visibleEntries();
    if (_continuousPlayIndex < 0 || _continuousPlayIndex >= entries.length) {
      if (_continuousLoop && entries.isNotEmpty) {
        setState(() => _continuousPlayIndex = 0);
      } else {
        _stopContinuousPlayback();
        return;
      }
    }

    final entry = entries[_continuousPlayIndex];

    // 平滑滚动居中当前正在朗读的单词
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _entryKeys[entry.word];
      final ctx = key?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      }
    });

    try {
      await _playWordTtsAndWait(entry.word);
    } catch (e, st) {
      _reportPronunciationFailure('连播', e, st, detail: '词="${entry.word}"');
      if (mounted) {
        setState(() {
          _ttsErrorMessage = '发音失败：${_describeError(e)}';
        });
      }
    }

    if (!_isContinuousPlaying || !mounted) return;

    // 播放完成后停顿缓冲 1.5 秒，再步进至下一词
    _continuousTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_isContinuousPlaying) return;
      _nextContinuousWord();
    });
  }

  Future<void> _playWordTtsAndWait(String word) async {
    final cleaned = VocabularyStudyStore.normalizeSentenceKey(word);
    if (cleaned.isEmpty) return;
    final key = VocabularyStudyStore.ttsCacheKey(cleaned);

    setState(() {
      _ttsErrorMessage = null;
      _playingTtsKey = key;
    });

    try {
      final file = await _synthesizeOrReport(cleaned);
      if (file == null) {
        _markWordTtsFailed(key, failed: true);
        return;
      }
      if (!mounted) return;
      final ok = await _playFileOrReport(
        file,
        waitForCompletion: true,
        detail: '词="$cleaned"',
      );
      _markWordTtsFailed(key, failed: !ok);
    } finally {
      if (mounted && _playingTtsKey == key) {
        setState(() {
          _playingTtsKey = null;
        });
      }
    }
  }

  List<VocabularyEntry> _visibleEntries() {
    final trimmedQuery = _query.trim();
    if (_activeTab == VocabularyFilterTab.focused) {
      return _focusedEntries(trimmedQuery);
    }
    if (trimmedQuery.isEmpty) {
      return widget.index.entries(
        includeStopwords: _showStopwords,
        includeNoisy: _showNoisy,
      );
    }
    return _searchEntries(trimmedQuery);
  }

  /// 构建「⭐ 重点关注」列表（不受停用词/噪声折叠限制，支持搜索过滤）。
  List<VocabularyEntry> _focusedEntries(String query) {
    final normalizedQuery =
        query.isEmpty ? '' : widget.index.normalizeForQuery(query);
    final out = <VocabularyEntry>[];

    for (final word in _studyStore.focusedWords) {
      if (normalizedQuery.isNotEmpty && !word.contains(normalizedQuery)) {
        continue;
      }
      final hits = widget.index.postingsFor(word);
      final byMeeting = <String, int>{};
      for (final p in hits) {
        byMeeting[p.meetingId] = (byMeeting[p.meetingId] ?? 0) + 1;
      }
      out.add(
        VocabularyEntry(
          word: word,
          display: widget.index.display[word] ?? word,
          count: hits.length,
          byMeeting: byMeeting,
          noisy: false,
        ),
      );
    }

    out.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.word.compareTo(b.word);
    });
    return out;
  }

  /// 搜索模式：支持精确查词或前缀/包含匹配，含停用词与噪声词。
  List<VocabularyEntry> _searchEntries(String query) {
    final normalized = widget.index.normalizeForQuery(query);
    if (normalized.isEmpty) return const [];

    final exactHits = widget.index.postingsFor(normalized);
    final matchedWords = <String>[
      if (exactHits.isNotEmpty) normalized,
      for (final w in widget.index.postings.keys)
        if (w != normalized && w.contains(normalized)) w,
    ];

    final out = <VocabularyEntry>[];
    for (final word in matchedWords) {
      final hits = widget.index.postingsFor(word);
      if (hits.isEmpty) continue;
      final byMeeting = <String, int>{};
      for (final p in hits) {
        byMeeting[p.meetingId] = (byMeeting[p.meetingId] ?? 0) + 1;
      }
      out.add(
        VocabularyEntry(
          word: word,
          display: widget.index.display[word] ?? word,
          count: hits.length,
          byMeeting: byMeeting,
          noisy: false,
        ),
      );
    }
    return out;
  }

  void _handleExpansionChanged(VocabularyEntry entry, bool expanded) {
    setState(() {
      if (expanded) {
        _expandedWords.add(entry.word);
      } else {
        _expandedWords.remove(entry.word);
      }
    });
    if (expanded) {
      // 方案 A：展开任意单词时，自动获取音标、词性与中文解释；
      // 若该词已标记为「重点关注」，同时确保其下所有所属原句的中文意思也已生成。
      unawaited(_studyStore.ensureWordProfile(entry.word));
      if (_studyStore.isFocused(entry.word)) {
        final sentences = widget.index
            .postingsFor(entry.word)
            .map((p) => p.sentence)
            .toList();
        if (sentences.isNotEmpty) {
          unawaited(
            _studyStore.ensureSentenceTranslations(entry.word, sentences),
          );
        }
      }
    }
  }

  void _handleToggleFocus(VocabularyEntry entry) {
    final sentences = widget.index
        .postingsFor(entry.word)
        .map((p) => p.sentence)
        .toList();
    _studyStore.toggleFocus(entry.word, sentences: sentences);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? context.bgCard : AppTheme.lightBgCard;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final entries = _visibleEntries();
    final focusedCount = _studyStore.focusedCount;

    return Dialog(
      backgroundColor: bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    '词汇表',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '跨全部真实会议 · ${widget.index.postings.length} 个词',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                  const Spacer(),
                  // 送入迷你播放器：取「⭐ 重点关注」词列表，迷你窗进入词汇磨耳朵模式。
                  OutlinedButton.icon(
                    key: const ValueKey('vocab-send-to-mini-btn'),
                    onPressed: focusedCount == 0
                        ? null
                        : () => _sendFocusedToMiniPlayer(),
                    icon: const Icon(
                      Icons.picture_in_picture_alt_rounded,
                      size: 15,
                    ),
                    label: Text(
                      focusedCount == 0 ? '先标记重点词汇' : '送入迷你播放器',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('vocab-search-input'),
                      controller: _queryCtrl,
                      style: TextStyle(fontSize: 12, color: textPrimary),
                      decoration: const InputDecoration(
                        hintText: '查一个词（可查被折叠的噪声词）',
                        prefixIcon: Icon(Icons.search, size: 16),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        _onFilterChanged();
                        setState(() => _query = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildTabChip(
                    key: const ValueKey('vocab-tab-all'),
                    label: '全部词汇 (${widget.index.postings.length})',
                    selected: _activeTab == VocabularyFilterTab.all,
                    onTap: () {
                      _onFilterChanged();
                      setState(() => _activeTab = VocabularyFilterTab.all);
                    },
                    accent: accent,
                    border: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  const SizedBox(width: 6),
                  _buildTabChip(
                    key: const ValueKey('vocab-tab-focused'),
                    icon: Icons.star_rounded,
                    label: '重点关注 ($focusedCount)',
                    selected: _activeTab == VocabularyFilterTab.focused,
                    onTap: () {
                      _onFilterChanged();
                      setState(
                        () => _activeTab = VocabularyFilterTab.focused,
                      );
                    },
                    accent: accent,
                    border: border,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_activeTab == VocabularyFilterTab.all)
                Row(
                  children: [
                    _toggle(
                      '显示停用词',
                      _showStopwords,
                      (v) {
                        _onFilterChanged();
                        setState(() => _showStopwords = v);
                      },
                      accent,
                      textSecondary,
                    ),
                    const SizedBox(width: 12),
                    _toggle(
                      '显示疑似噪声',
                      _showNoisy,
                      (v) {
                        _onFilterChanged();
                        setState(() => _showNoisy = v);
                      },
                      accent,
                      textSecondary,
                    ),
                  ],
                ),
              _buildContinuousPlayBar(
                entries: entries,
                accent: accent,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                isDark: isDark,
              ),
              _buildVoiceAndStyleBar(
                accent: accent,
                textSecondary: textSecondary,
                isDark: isDark,
              ),
              if (_ttsErrorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _ttsErrorMessage!,
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ],
              const Divider(height: 16),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          _activeTab == VocabularyFilterTab.focused
                              ? '尚未标记重点关注词汇，点击单词旁的 ☆ 即可加入重点关注'
                              : '没有匹配的词',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: _listScrollController,
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _entryTile(
                          entries[i],
                          isCurrentPlaying: _isContinuousPlaying &&
                              _continuousPlayIndex == i,
                          isDark: isDark,
                          border: border,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          accent: accent,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 音色 + MiMo 风格指令设置条（生词本/听力练习播放用）。
  ///
  /// 音色下拉：TTS 槽位绑定 MiMo 时列 MiMo 官方预置音色（[TtsVoiceOption.defaultMimoVoices]），
  /// 否则列 [VoicePool]（StepFun 等角色音色池）。风格输入框仅 MiMo 下显示，
  /// 以自然语言调节语速/语调/情绪。
  Widget _buildVoiceAndStyleBar({
    required Color accent,
    required Color textSecondary,
    required bool isDark,
  }) {
    // 探测当前 TTS 槽位是否绑定 MiMo，决定音色候选与风格输入框可见性。
    final ttsCandidates = AiConfigStore.instance.slotBindings['tts'] ?? [];
    String? boundModel;
    String? boundBaseUrl;
    String? boundProviderName;
    for (final cand in ttsCandidates) {
      final provider = AiConfigStore.instance.providers
          .cast<AiProviderConfig?>()
          .firstWhere(
            (p) => p?.id == cand.providerId && p?.enabled == true,
            orElse: () => null,
          );
      if (provider == null) continue;
      boundModel = cand.model.isNotEmpty ? cand.model : null;
      boundBaseUrl = provider.baseUrl;
      boundProviderName = provider.name;
      break;
    }
    final isMimo = OpenAiTtsEngine.isMimoModel(
      boundModel ?? '',
      baseUrl: boundBaseUrl ?? '',
      providerName: boundProviderName,
    );

    final voices = isMimo
        ? TtsVoiceOption.defaultMimoVoices
        : VoicePool.all
            .map(
              (v) => TtsVoiceOption(
                id: v.id,
                name: v.label,
                language: '',
                gender: v.gender == VoiceGender.female ? 'female' : 'male',
                mode: TtsMode.customAi,
                description: 'F0 ${v.measuredF0}Hz',
              ),
            )
            .toList();

    final currentVoice = _studyStore.defaultVoiceId;
    final effectiveVoice =
        voices.any((v) => v.id == currentVoice) ? currentVoice : voices.first.id;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? context.bgWindow.withValues(alpha: 0.35)
            : AppTheme.lightBgWindow.withValues(alpha: 0.35),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.record_voice_over_outlined, size: 15, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<String>(
              value: effectiveVoice,
              isDense: true,
              underline: const SizedBox(),
              style: TextStyle(fontSize: 12, color: textSecondary),
              items: [
                for (final v in voices)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text(
                      v.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (val) {
                if (val != null) {
                  _studyStore.defaultVoiceId = val;
                  setState(() {});
                }
              },
            ),
          ),
          if (isMimo) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: TextEditingController(
                  text: _studyStore.styleInstruction,
                ),
                style: const TextStyle(fontSize: 11),
                maxLines: 1,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '朗读风格…',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                ),
                onSubmitted: (v) {
                  _studyStore.styleInstruction = v;
                  setState(() {});
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContinuousPlayBar({
    required List<VocabularyEntry> entries,
    required Color accent,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {    final statusText = _isContinuousPlaying
        ? (entries.isNotEmpty &&
                _continuousPlayIndex >= 0 &&
                _continuousPlayIndex < entries.length
            ? '朗读中: ${entries[_continuousPlayIndex].display} (${_continuousPlayIndex + 1}/${entries.length})'
            : '朗读中 (${entries.length})')
        : (_continuousPlayIndex >= 0 && entries.isNotEmpty
            ? '已暂停 (${_continuousPlayIndex + 1}/${entries.length})'
            : '连续磨耳朵 (${entries.length} 词)');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? context.bgWindow.withValues(alpha: 0.5)
            : AppTheme.lightBgWindow.withValues(alpha: 0.5),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            _isContinuousPlaying
                ? Icons.volume_up_rounded
                : Icons.headphones_outlined,
            size: 16,
            color: _isContinuousPlaying ? accent : textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    _isContinuousPlaying ? FontWeight.w600 : FontWeight.w400,
                color: _isContinuousPlaying ? accent : textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const ValueKey('vocab-continuous-prev-btn'),
            icon: const Icon(Icons.skip_previous_rounded, size: 18),
            tooltip: '上一词',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: entries.isEmpty || _continuousPlayIndex <= 0
                ? null
                : _previousContinuousWord,
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('vocab-continuous-play-pause-btn'),
            icon: Icon(
              _isContinuousPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              size: 24,
              color: entries.isEmpty
                  ? textSecondary.withValues(alpha: 0.4)
                  : accent,
            ),
            tooltip: _isContinuousPlaying ? '暂停' : '连续播放',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: entries.isEmpty
                ? null
                : () {
                    if (_isContinuousPlaying) {
                      _pauseContinuousPlayback();
                    } else {
                      _startContinuousPlayback(
                        startIndex: _continuousPlayIndex >= 0
                            ? _continuousPlayIndex
                            : 0,
                      );
                    }
                  },
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('vocab-continuous-next-btn'),
            icon: const Icon(Icons.skip_next_rounded, size: 18),
            tooltip: '下一词',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: entries.isEmpty ||
                    (!_continuousLoop &&
                        _continuousPlayIndex >= entries.length - 1)
                ? null
                : _nextContinuousWord,
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('vocab-continuous-stop-btn'),
            icon: Icon(
              Icons.stop_rounded,
              size: 20,
              color: (_isContinuousPlaying || _continuousPlayIndex >= 0)
                  ? textPrimary
                  : textSecondary.withValues(alpha: 0.3),
            ),
            tooltip: '停止',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: (_isContinuousPlaying || _continuousPlayIndex >= 0)
                ? _stopContinuousPlayback
                : null,
          ),
          const SizedBox(width: 6),
          InkWell(
            key: const ValueKey('vocab-continuous-loop-btn'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _continuousLoop = !_continuousLoop),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _continuousLoop
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    size: 15,
                    color: _continuousLoop ? accent : textSecondary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '循环',
                    style: TextStyle(
                      fontSize: 10,
                      color: _continuousLoop ? accent : textSecondary,
                      fontWeight:
                          _continuousLoop ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required Key key,
    IconData? icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return InkWell(
      key: key,
      borderRadius: AppTheme.borderRadiusSmall,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
          border: Border.all(color: selected ? accent : border),
          borderRadius: AppTheme.borderRadiusSmall,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.amber.shade700 : textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? accent : textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryTile(
    VocabularyEntry entry, {
    required bool isCurrentPlaying,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    final entryKey = _entryKeys.putIfAbsent(entry.word, () => GlobalKey());
    final postings = widget.index.postingsFor(entry.word);
    final meetingCount = entry.byMeeting.length;
    final focused = _studyStore.isFocused(entry.word);
    final profile = _studyStore.profileFor(entry.word);
    final loadingProfile = _studyStore.isLoadingProfile(entry.word);
    final isExpanded = _expandedWords.contains(entry.word);

    final normalizedWord =
        VocabularyStudyStore.normalizeSentenceKey(entry.word);
    final isWordTtsPlaying = _playingTtsKey != null &&
        _playingTtsKey == VocabularyStudyStore.ttsCacheKey(normalizedWord);

    return Container(
      key: entryKey,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isCurrentPlaying
            ? accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: isCurrentPlaying
              ? accent.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: Theme(
        // 去掉 ExpansionTile 展开时的默认分割线
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('vocab-tile-${entry.word}'),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) =>
              _handleExpansionChanged(entry, expanded),
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Row(
            children: [
              InkWell(
                key: ValueKey('vocab-focus-btn-${entry.word}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => _handleToggleFocus(entry),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    focused ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 17,
                    color: focused ? Colors.amber.shade600 : textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('vocab-row-tts-${entry.word}'),
                icon: isWordTtsPlaying
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(
                        Icons.volume_up_outlined,
                        size: 16,
                        color: isCurrentPlaying ? accent : textSecondary,
                      ),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: '朗读单词发音',
                onPressed: () => _playTts(entry.word),
              ),
              const SizedBox(width: 4),
              Text(
                entry.display,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCurrentPlaying ? accent : textPrimary,
                ),
              ),
              if (_failedTtsKeys.contains(
                VocabularyStudyStore.ttsCacheKey(normalizedWord),
              )) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.error_outline_rounded,
                  size: 13,
                  color: Colors.redAccent,
                  semanticLabel: '该词发音失败',
                ),
              ],
              if (profile != null && profile.phonetic.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  profile.phonetic,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
              if (profile != null && profile.hasDefinition) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile.definitionZh,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: 8),
              Text(
                '${entry.count}',
                style: TextStyle(fontSize: 11, color: accent),
              ),
              const SizedBox(width: 6),
              Text(
                '$meetingCount 场',
                style: TextStyle(fontSize: 10, color: textSecondary),
              ),
              if (entry.noisy) ...[
                const SizedBox(width: 6),
                Text(
                  '疑似噪声',
                  style: TextStyle(fontSize: 9, color: textSecondary),
                ),
              ],
            ],
          ),
          children: [
            _buildWordStudyHeader(
              entry: entry,
              profile: profile,
              loadingProfile: loadingProfile,
              focused: focused,
              postings: postings,
              isDark: isDark,
              border: border,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              accent: accent,
            ),
            for (var i = 0; i < postings.length; i++)
              _buildPostingCard(
                entry: entry,
                posting: postings[i],
                index: i,
                isDark: isDark,
                border: border,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                accent: accent,
              ),
          ],
        ),
      ),
    );
  }

  /// 单词展开后的顶部助学卡片：音标、词性、中文解释、单词发音按钮与重点关注状态。
  Widget _buildWordStudyHeader({
    required VocabularyEntry entry,
    required VocabularyWordProfile? profile,
    required bool loadingProfile,
    required bool focused,
    required List<VocabularyPosting> postings,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    final wordTtsKey = VocabularyStudyStore.ttsCacheKey(entry.word);
    final wordSynthesizing =
        _studyStore.isSynthesizingTts(entry.word) ||
        _playingTtsKey == wordTtsKey;

    return Container(
      key: ValueKey('vocab-study-header-${entry.word}'),
      margin: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.025),
        border: Border.all(color: border),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                entry.display,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              if (profile != null && profile.phonetic.isNotEmpty)
                Text(
                  profile.phonetic,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: textSecondary,
                  ),
                ),
              if (profile != null && profile.partOfSpeech.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    profile.partOfSpeech,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              _buildSmallActionChip(
                key: ValueKey('vocab-word-tts-${entry.word}'),
                icon: wordSynthesizing
                    ? Icons.hourglass_top_rounded
                    : Icons.volume_up_rounded,
                label: wordSynthesizing ? '合成中…' : '单词发音',
                onTap: wordSynthesizing ? null : () => _playTts(entry.word),
                accent: accent,
                border: border,
                textSecondary: textSecondary,
              ),
              _buildSmallActionChip(
                key: ValueKey('vocab-word-focus-chip-${entry.word}'),
                icon: focused ? Icons.star_rounded : Icons.star_border_rounded,
                iconColor: focused ? Colors.amber.shade600 : null,
                label: focused ? '已重点关注' : '标记重点关注',
                onTap: () => _handleToggleFocus(entry),
                accent: accent,
                border: border,
                textSecondary: textSecondary,
              ),
              if (postings.isNotEmpty)
                _buildSmallActionChip(
                  key: ValueKey('vocab-translate-all-${entry.word}'),
                  icon: Icons.translate_rounded,
                  label: '翻译全部原句',
                  onTap: () => _studyStore.ensureSentenceTranslations(
                    entry.word,
                    postings.map((p) => p.sentence).toList(),
                  ),
                  accent: accent,
                  border: border,
                  textSecondary: textSecondary,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (loadingProfile && (profile == null || !profile.hasDefinition))
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded, size: 12, color: accent),
                const SizedBox(width: 6),
                Text(
                  '正在查询音标、词性与中文释义…',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            )
          else if (profile != null && profile.hasDefinition)
            Text(
              '释义：${profile.definitionZh}',
              style: TextStyle(fontSize: 12, height: 1.4, color: textPrimary),
            )
          else
            Row(
              children: [
                Text(
                  '暂无释义缓存',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _studyStore.ensureWordProfile(
                    entry.word,
                    forceRefresh: true,
                  ),
                  child: Text(
                    '点击重新获取',
                    style: TextStyle(fontSize: 11, color: accent),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 单条所属原句展示卡片：高亮目标词、中文句意、句子单独发音与跳到原会议。
  Widget _buildPostingCard({
    required VocabularyEntry entry,
    required VocabularyPosting posting,
    required int index,
    required bool isDark,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    final sentenceZh = _studyStore.translationForSentence(posting.sentence);
    final loadingSentence = _studyStore.isLoadingSentence(posting.sentence);
    final sentenceTtsKey = VocabularyStudyStore.ttsCacheKey(posting.sentence);
    final sentenceSynthesizing =
        _studyStore.isSynthesizingTts(posting.sentence) ||
        _playingTtsKey == sentenceTtsKey;

    final normalStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      color: textPrimary,
    );
    final highlightStyle = TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: accent,
      backgroundColor: accent.withValues(alpha: isDark ? 0.24 : 0.16),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  posting.meetingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
              Text(
                '${posting.slotId} · ${_fmt(posting.timestampMs)}',
                style: TextStyle(fontSize: 10, color: textSecondary),
              ),
              const SizedBox(width: 8),
              _buildSmallActionChip(
                key: ValueKey('vocab-sentence-tts-${entry.word}-$index'),
                icon: sentenceSynthesizing
                    ? Icons.hourglass_top_rounded
                    : Icons.volume_up_outlined,
                label: sentenceSynthesizing ? '合成中…' : '句子发音',
                onTap: sentenceSynthesizing
                    ? null
                    : () => _playTts(posting.sentence),
                accent: accent,
                border: border,
                textSecondary: textSecondary,
              ),
              const SizedBox(width: 6),
              if (sentenceZh == null && !loadingSentence)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildSmallActionChip(
                    key: ValueKey(
                      'vocab-sentence-translate-${entry.word}-$index',
                    ),
                    icon: Icons.translate_rounded,
                    label: '句意',
                    onTap: () => _studyStore.ensureSentenceTranslations(
                      entry.word,
                      [posting.sentence],
                    ),
                    accent: accent,
                    border: border,
                    textSecondary: textSecondary,
                  ),
                ),
              _buildSmallActionChip(
                key: ValueKey('vocab-sentence-jump-${entry.word}-$index'),
                icon: Icons.open_in_new_rounded,
                label: '跳转',
                onTap: () => widget.onJump(posting),
                accent: accent,
                border: border,
                textSecondary: textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => widget.onJump(posting),
            child: Text.rich(
              TextSpan(
                children: buildHighlightedSentenceSpans(
                  posting.sentence,
                  entry.word,
                  normalStyle: normalStyle,
                  highlightStyle: highlightStyle,
                ),
              ),
              key: ValueKey('vocab-sentence-rich-${entry.word}-$index'),
            ),
          ),
          if (loadingSentence) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded, size: 11, color: accent),
                const SizedBox(width: 6),
                Text(
                  '正在生成句子中文意思…',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ] else if (sentenceZh != null && sentenceZh.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '译：$sentenceZh',
              key: ValueKey('vocab-sentence-zh-${entry.word}-$index'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmallActionChip({
    required Key key,
    required IconData icon,
    Color? iconColor,
    required String label,
    required VoidCallback? onTap,
    required Color accent,
    required Color border,
    required Color textSecondary,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: iconColor ?? accent),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _toggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    Color accent,
    Color textSecondary,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? Icons.check_box_outlined : Icons.check_box_outline_blank,
            size: 14,
            color: value ? accent : textSecondary,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: textSecondary)),
        ],
      ),
    );
  }
}
