import 'dart:math';

import 'package:flutter/foundation.dart';

import 'meeting_vocabulary_index.dart';
import 'vocabulary_study_store.dart';

/// 词汇练习与考核的三种会话模式。
enum VocabularyPracticeMode {
  /// 沉浸刷词学习模式：听发音 · 看释义 · 听会议原声语境。
  study('study', '沉浸学习', '听发音 · 看释义 · 听会议原声'),

  /// 盲听 4 选 1 测验模式：隐藏英文，先听发音，4 个中文选项快速听辨。
  quiz4Choice('quiz', '盲听测验', '盲听发音 · 4选1速辨 · 原句出处解析'),

  /// Anki 闪卡翻牌自评模式：听音盲猜 ➔ 翻牌看解析 ➔ 科学自评调整记忆曲线。
  flashcards('flashcards', '闪卡自评', '听音盲猜 ➔ 翻牌看解析 ➔ 科学自评');

  final String id;
  final String label;
  final String description;

  const VocabularyPracticeMode(this.id, this.label, this.description);
}

/// 单个练习/测验题目项。
class PracticeItem {
  final String word;
  final VocabularyWordProfile? profile;
  final String? contextSentence;
  final String? sentenceTranslation;
  final String? speaker;
  final String? sceneLabel;

  /// 4 选 1 测验选项（中文释义）。
  final List<String> choices;

  /// 正确选项在 [choices] 中的下标。
  final int correctChoiceIndex;

  /// 用户选中的选项下标（测验模式）。
  int? selectedChoiceIndex;

  /// 用户自评打分（闪卡模式：0: 遗忘, 1: 模糊, 2: 熟悉, 3: 秒懂）。
  int? selfAssessmentRating;

  /// 闪卡正面是否已翻到背面。
  bool isCardFlipped;

  /// 听发音/播放次数（遥测）。
  int playCount;

  /// 题目展示时间（首次播放或展示）。
  DateTime? displayedAt;

  /// 作答完成时间。
  DateTime? answeredAt;

  /// 听觉熟悉度评估等级（测验作答后由 store 评估并写回）。
  AuditoryFamiliarity? familiarity;

  /// 是否为当轮生疏词末尾追加强化再测题。
  final bool isReinforcement;

  PracticeItem({
    required this.word,
    this.profile,
    this.contextSentence,
    this.sentenceTranslation,
    this.speaker,
    this.sceneLabel,
    this.choices = const [],
    this.correctChoiceIndex = 0,
    this.selectedChoiceIndex,
    this.selfAssessmentRating,
    this.isCardFlipped = false,
    this.playCount = 0,
    this.displayedAt,
    this.answeredAt,
    this.familiarity,
    this.isReinforcement = false,
  });

  bool get isAnswered => selectedChoiceIndex != null || selfAssessmentRating != null;
  bool get isCorrect => selectedChoiceIndex == correctChoiceIndex;
  Duration? get responseDuration =>
      (displayedAt != null && answeredAt != null)
          ? answeredAt!.difference(displayedAt!)
          : null;
}

/// 练习与考核会话控制器。
class VocabularySessionController extends ChangeNotifier {
  final VocabularyPracticeMode mode;
  final MeetingVocabularyIndex index;
  final VocabularyStudyStore studyStore;
  final List<PracticeItem> items;
  final DateTime startTime;
  final Map<String, String> _candidatePool;
  final Random _rng;
  final List<String> _pendingReinforceWords = [];

  int _currentIndex = 0;
  bool _isCompleted = false;

  VocabularySessionController._({
    required this.mode,
    required this.index,
    required this.studyStore,
    required this.items,
    required this.startTime,
    required Map<String, String> candidatePool,
    required Random rng,
    int initialIndex = 0,
  })  : _candidatePool = candidatePool,
        _rng = rng,
        _currentIndex = (items.isNotEmpty &&
                initialIndex >= 0 &&
                initialIndex < items.length)
            ? initialIndex
            : 0;

  /// 构建一个全新的练习/考核会话。
  factory VocabularySessionController.create({
    required VocabularyPracticeMode mode,
    required List<String> words,
    required MeetingVocabularyIndex index,
    required VocabularyStudyStore studyStore,
    String? initialWord,
    Random? random,
  }) {
    final rng = random ?? Random();
    final candidatePool = <String, String>{};

    // 收集所有已知单词的中文解释作为 4 选 1 干扰项候选池
    for (final e in studyStore.focusedWords) {
      final p = studyStore.profileFor(e);
      if (p != null && p.definitionZh.trim().isNotEmpty) {
        candidatePool[e] = p.definitionZh.trim();
      }
    }

    final controller = VocabularySessionController._(
      mode: mode,
      index: index,
      studyStore: studyStore,
      items: <PracticeItem>[],
      startTime: DateTime.now(),
      candidatePool: candidatePool,
      rng: rng,
    );

    for (final rawWord in words) {
      final item = controller._buildPracticeItem(rawWord);
      if (item.word.isNotEmpty) {
        controller.items.add(item);
      }
    }

    var initialIdx = 0;
    if (initialWord != null && initialWord.trim().isNotEmpty) {
      final normalizedInit = MeetingVocabularyIndex.normalizeWord(initialWord);
      final foundIdx = controller.items.indexWhere((it) => it.word == normalizedInit);
      if (foundIdx >= 0) {
        initialIdx = foundIdx;
      }
    }
    controller._currentIndex = initialIdx;
    return controller;
  }

  /// 构造单个练习题目项。
  PracticeItem _buildPracticeItem(
    String rawWord, {
    bool isReinforcement = false,
  }) {
    final word = MeetingVocabularyIndex.normalizeWord(rawWord);
    if (word.isEmpty) {
      return PracticeItem(word: '');
    }

    final profile = studyStore.profileFor(word);
    final correctDef = profile?.definitionZh.trim().isNotEmpty == true
        ? profile!.definitionZh.trim()
        : (_candidatePool[word] ?? '暂无释义');

    String? contextSentence;
    String? sentenceTrans;
    String? speaker;
    String? sceneLabel;

    final postings = index.postingsFor(word);
    if (postings.isNotEmpty) {
      final p = postings.first;
      contextSentence = p.sentence;
      speaker = p.slotId;
      sceneLabel = p.meetingTitle;
      sentenceTrans = studyStore.translationForSentence(p.sentence);
    }

    final choices = <String>[];
    var correctIdx = 0;

    if (mode == VocabularyPracticeMode.quiz4Choice) {
      final distractorCandidates = _candidatePool.entries
          .where((e) => e.key != word && e.value != correctDef)
          .map((e) => e.value)
          .toSet()
          .toList();

      distractorCandidates.shuffle(_rng);
      final distractors = distractorCandidates.take(3).toList();

      final fallbackDistractors = [
        'n. 架构设计；系统拓扑',
        'v. 部署；上线发布',
        'adj. 偶发的；不稳定的',
        'n. 容灾备份；故障恢复',
        'v. 迁移；数据库变更',
      ];
      var fbIdx = 0;
      while (distractors.length < 3 && fbIdx < fallbackDistractors.length) {
        final candidate = fallbackDistractors[fbIdx++];
        if (candidate != correctDef && !distractors.contains(candidate)) {
          distractors.add(candidate);
        }
      }

      final combined = [correctDef, ...distractors];
      combined.shuffle(_rng);
      correctIdx = combined.indexOf(correctDef);
      choices.addAll(combined);
    }

    return PracticeItem(
      word: word,
      profile: profile,
      contextSentence: contextSentence,
      sentenceTranslation: sentenceTrans,
      speaker: speaker,
      sceneLabel: sceneLabel,
      choices: choices,
      correctChoiceIndex: correctIdx,
      isReinforcement: isReinforcement,
    );
  }

  int get currentIndex => _currentIndex;
  bool get isCompleted => _isCompleted;
  int get totalCount => items.length;
  bool get isEmpty => items.isEmpty;
  bool get isLast => _currentIndex >= items.length - 1;
  bool get isFirst => _currentIndex == 0;
  int get pendingReinforceCount => _pendingReinforceWords.length;

  PracticeItem? get currentItem =>
      (items.isNotEmpty && _currentIndex >= 0 && _currentIndex < items.length)
          ? items[_currentIndex]
          : null;

  /// 已答题或已自评的数量。
  int get answeredCount => items.where((it) => it.isAnswered).length;

  /// 测验模式答对数量。
  int get correctCount => items.where((it) => it.isCorrect).length;

  /// 测验模式答错数量。
  int get mistakeCount =>
      items.where((it) => it.selectedChoiceIndex != null && !it.isCorrect).length;

  /// 错误单词列表。
  List<String> get mistakeWords => items
      .where((it) =>
          (it.selectedChoiceIndex != null && !it.isCorrect) ||
          (it.selfAssessmentRating != null && it.selfAssessmentRating! < 2))
      .map((it) => it.word)
      .toList();

  /// 记录当前题目的听音播放次数。
  void recordPlay() {
    final item = currentItem;
    if (item == null) return;
    item.playCount++;
    item.displayedAt ??= DateTime.now();
    notifyListeners();
  }

  /// 闪卡模式翻牌。
  void flipCard() {
    final item = currentItem;
    if (item == null) return;
    item.isCardFlipped = !item.isCardFlipped;
    notifyListeners();
  }

  /// 测验模式：选中选项并记录判卷与听觉熟悉度。
  void selectChoice(int index) {
    final item = currentItem;
    if (item == null || item.selectedChoiceIndex != null) return;
    item.selectedChoiceIndex = index;
    item.answeredAt = DateTime.now();
    item.displayedAt ??= item.answeredAt;

    final correct = item.isCorrect;
    final familiarity = studyStore.recordQuizResult(
      item.word,
      isCorrect: correct,
      playCount: item.playCount == 0 ? 1 : item.playCount,
      responseDuration: item.responseDuration,
    );
    item.familiarity = familiarity;

    // 若熟悉度属于生疏（吃力 struggling 或选错 lapse），且当前题目不是强化加测题（避免死循环），加入末尾回捞队列
    if (!item.isReinforcement &&
        (familiarity == AuditoryFamiliarity.struggling ||
            familiarity == AuditoryFamiliarity.lapse)) {
      if (!_pendingReinforceWords.contains(item.word)) {
        _pendingReinforceWords.add(item.word);
      }
    }
    notifyListeners();
  }

  /// 闪卡模式：提交自评打分 (0: 遗忘, 1: 模糊, 2: 熟悉, 3: 秒懂)。
  void submitSelfAssessment(int rating) {
    final item = currentItem;
    if (item == null) return;
    item.selfAssessmentRating = rating;

    studyStore.recordSelfAssessment(item.word, rating: rating);
    if (isLast) {
      _isCompleted = true;
    } else {
      _currentIndex++;
    }
    notifyListeners();
  }

  /// 下一个单词/题目；最后一题时若有生疏待强化词则自动在末尾追加强化题目。
  bool next() {
    if (isLast) {
      if (_pendingReinforceWords.isNotEmpty) {
        final wordsToReinforce = List<String>.from(_pendingReinforceWords);
        _pendingReinforceWords.clear();
        for (final w in wordsToReinforce) {
          items.add(_buildPracticeItem(w, isReinforcement: true));
        }
        _currentIndex++;
        notifyListeners();
        return true;
      }
      _isCompleted = true;
      notifyListeners();
      return false;
    }
    _currentIndex++;
    notifyListeners();
    return true;
  }

  /// 上一个单词/题目。
  bool previous() {
    if (isFirst) return false;
    _currentIndex--;
    notifyListeners();
    return true;
  }

  /// 跳转至指定题目。
  void jumpTo(int index) {
    if (index < 0 || index >= items.length) return;
    _currentIndex = index;
    notifyListeners();
  }

  /// 从头开始重置当前会话（回到第 1 题，并清除所有已答状态与加测题目）。
  void resetToBeginning() {
    _currentIndex = 0;
    _isCompleted = false;
    _pendingReinforceWords.clear();
    items.removeWhere((it) => it.isReinforcement);
    for (final it in items) {
      it.selectedChoiceIndex = null;
      it.selfAssessmentRating = null;
      it.isCardFlipped = false;
      it.playCount = 0;
      it.displayedAt = null;
      it.answeredAt = null;
      it.familiarity = null;
    }
    notifyListeners();
  }

  /// 创建错题强化重测会话。
  VocabularySessionController? createMistakesSession({
    VocabularyPracticeMode? targetMode,
  }) {
    final mistakes = mistakeWords;
    if (mistakes.isEmpty) return null;
    return VocabularySessionController.create(
      mode: targetMode ?? mode,
      words: mistakes,
      index: index,
      studyStore: studyStore,
    );
  }
}
