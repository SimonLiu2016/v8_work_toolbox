# Design: fix-vocabulary-practice-issues-and-progress

## Context

在重点关注词汇学习考核功能上线后，发现了两个主要维度的体验问题：
1. **视觉与渲染维度**：发音按钮使用 Flutter M3 的 `IconButton.filledTonal` 导致图标在静止时完全隐形、仅在 hover 时呈隐约黑影；盲听测验在未作答前通过 `FontWeight.w600` 提前泄漏了正确答案。
2. **状态与连续性维度**：每次进入三种练习模式均无断点记忆，导致多次练习体验重复且繁琐。

## Goals / Non-Goals

**Goals:**
- 将练习面板中的所有发音按钮重构为显式高对比度、适配深浅主题且与整个工具箱视觉一致的微型/中型徽标组件；
- 确保盲听 4 选 1 测验在未作答阶段对 4 个选项完全无视觉倾向，作答后呈现准确的对错反馈；
- 为沉浸学习、盲听测验、闪卡自评分别建立持久化的进度存储模型，进入时自动接续，学完结算时自动清零，并提供显式的「从头开始」控制。

**Non-Goals:**
- 不改变 SM-2 记忆算法的等级升级与间隔计算核心；
- 不改变词汇表列表主视图的展示逻辑与数据过滤分类。

## Decisions

### 1. 显式高对比度发音徽标按钮 (Visual & Contrast)
- **原因**：Flutter M3 的 `IconButton.filledTonal` 在没有定义全局 `secondaryContainer` / `onSecondaryContainer` 时会使用不可控的默认值，并在桌面端出现前景色/底色对比度坍塌。
- **方案**：构建统一的音频触发按钮封装：
  - 常态：`accent.withValues(alpha: 0.12)` 圆形微光底 + `accentText` 实体图标（普通单词 20~22px 图标，盲听测验大按钮 36~40px 图标）；
  - 悬浮态：底色自动提升至 `accent.withValues(alpha: 0.20)`；
  - 播放中：实心强调色背景 + 动态声波 `Icons.graphic_eq_rounded`（白字图标）；
  - 鼠标光标显式指定为 `SystemMouseCursors.click`。

### 2. 盲听测验未作答状态严格防泄题 (Quiz Anti-Leak)
- **判定修正**：
  ```dart
  final isAnswered = item.isAnswered;
  final isSelected = item.selectedChoiceIndex == index;
  final isCorrectOption = index == item.correctChoiceIndex;

  // 选项字重：仅当已经作答时，被选中的选项或正确选项才加粗
  final textWeight = isAnswered && (isSelected || isCorrectOption)
      ? FontWeight.w600
      : FontWeight.normal;
  ```
- **选项外观统一**：在 `isAnswered == false` 时，4 个选项的序号徽标、中文释义文本颜色、容器底色和边框均使用一致的未作答中性样式。

### 3. 多练习模式独立进度持久化与断点控制 (Progress & Continuity)
- **数据模型**：
  在 `VocabularyStudyData` 中新增：
  ```dart
  /// 各练习模式最近学习的进度映射：mode.name -> lastWord
  final Map<String, String> practiceProgress;
  ```
- **向后兼容**：
  在 `fromJson` 时若字段缺失默认为空 `Map`，在 `toJson` 时平滑持久化。
- **会话引擎接续**：
  `VocabularySessionController.create` 支持可选参数 `initialWord` 或 `initialIndex`：
  - 根据 `initialWord` 在目标练习词汇列表中查找索引：若找到则将 `currentIndex` 初始化至该位置；
  - 若已达到末尾或找不到，则从 0 开始。
- **自动接续与重置交互**：
  - 页面进入：若 `currentIndex > 0`，顶部栏呈现提示 `已接续上次进度 (16/50)`；
  - 一键从头：在顶部退出按钮右侧提供 `[↺ 从头开始]`，点击后调用 `session.resetToBeginning()`，进度立即归零并重新从第 1 题开始；
  - 自动完结：当到达最后答题报告（Summary）时，调用 `_studyStore.clearPracticeProgress(mode)`，下一轮自然重置。

## Risks / Trade-offs

- **[Risk]** 用户在外部删除了某个重点单词，导致 `lastWord` 在词库中不存在。
  - **Mitigation**：通过 `targetWords.indexOf(lastWord)` 进行保护性查找；若未找到（返回 -1），优雅回退到索引 0 开始，绝不产生下标越界异常。
- **[Risk]** 过滤子视图（如仅看“🔥 待复习”或“⚠️ 错题强化”）与全局“全部”词单长度不同。
  - **Mitigation**：断点以 `lastWord`（单词字符串）为第一依据，无论当前筛选出的单词集合大小如何，只要当前队列包含该词即准确对齐，不包含则从第 1 题开始。
