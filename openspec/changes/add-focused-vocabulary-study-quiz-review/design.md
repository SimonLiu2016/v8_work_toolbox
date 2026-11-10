# Design: 重点关注词汇学习、考核与智能复习闭环系统

## 1. 架构与领域模型

### 1.1 记忆模型 `WordMemoryState`
在 `lib/tools/it_meeting_listening/models/vocabulary_study_models.dart`（或在 `vocabulary_study_store.dart`）中定义：
```dart
enum MemoryProficiency {
  fresh(0, '生词', 1),
  learning(1, '学习中', 2),
  familiar(2, '熟悉', 4),
  mastered(3, '已掌握', 7),
  solid(4, '熟练掌握', 14);

  final int level;
  final String label;
  final int defaultIntervalDays;

  const MemoryProficiency(this.level, this.label, this.defaultIntervalDays);
}

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

  bool get isDue {
    if (nextReviewDue.isEmpty) return true;
    final due = DateTime.tryParse(nextReviewDue);
    if (due == null) return true;
    return DateTime.now().isAfter(due);
  }

  bool get isMastered => proficiency >= 3;
  bool get hasMistakes => mistakeCount > 0;
}
```

### 1.2 数据存储与向后兼容 `VocabularyStudyStore`
- 在 `VocabularyStudyData` 中增加 `final Map<String, WordMemoryState> memoryStates;`。
- 读取旧 `vocabulary_study_store.json` 时，若某个已重点关注的词在 `memoryStates` 中缺失，自动用当前时间初始化其 `WordMemoryState`，确保数据迁移完全向后兼容。
- 增加方法：
  - `void recordQuizResult(String word, {required bool isCorrect})`
  - `void recordSelfAssessment(String word, {required int rating})` // 0: 遗忘, 1: 模糊, 2: 熟悉, 3: 秒懂
  - `List<VocabularyEntry> getDueWords()`
  - `List<VocabularyEntry> getMistakeWords()`
  - `List<VocabularyEntry> getMasteredWords()`

## 2. 练习与考核引擎 `VocabularySessionController`
设计纯逻辑控制器，管理三种会话类型的流转：
- 会话模式：`VocabularyPracticeMode { study, quiz4Choice, flashcards }`
- 题目列表：根据用户选定的词汇子集（全部重点词、今日待复习、错题集）生成题目队列；
- 4 选 1 干扰项生成策略：优先从现有其他词汇中提取有效中文释义；若释义不足，提供通用备选，保证选项质量；
- 统计快照：记录已完成总数、答对数、答错数、平均用时、错题列表。

## 3. UI 界面与交互设计
### 3.1 词汇表控制条集成 (`VocabularyBrowserDialog`)
在“重点关注”标签页增加专属工具栏：
- **统计微章**：`全部 (N)` · `🔥 今日待复习 (N)` · `⚠️ 错题 (N)` · `🏆 已掌握 (N)`
- **模式触发按钮组**：
  - `[📖 沉浸学习]`
  - `[🎯 盲听测验]`
  - `[🎴 闪卡自评]`
  - `[⚡ 快速复习 (今日 N 词)]`

### 3.2 沉浸式练习面板 (`VocabularyPracticeDialog`)
弹窗式卡片容器（宽度自适应 680~740px），包含：
- **顶栏**：退出练习、当前模式标题、进度条（如 `5 / 18`）、重播发音快捷按钮；
- **核心卡片区**：
  - **学习卡**：拼写 + 音标 + 释义 + 会议原句（带原角色音频播放按钮）；
  - **测验卡 (4 选 1)**：大号发音波形图标，盲听播放，4 个中文选项卡片，支持数字键快捷作答；答后展示解析；
  - **闪卡 (Flashcards)**：正面盲听，翻牌后展示中英释义与原句，底部 4 个打分按钮；
- **结算卡**：完成全部题目后展示正确率、耗时、错题列表及“再练一次错题”按钮。
