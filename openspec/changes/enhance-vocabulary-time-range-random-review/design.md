# Design: enhance-vocabulary-time-range-random-review

## Context

原有的「复习今日」功能仅支持拉取 SM-2 算法当前判定的到期词汇，无法满足用户针对今日、近 3 天、近 7 天等时间窗口的针对性复习需求，且出题顺序固定。

## Goals / Non-Goals

**Goals:**
- 在 `VocabularyStudyStore` 中建立完善的学习行为时间戳统计，并提供 5 档时间跨度的已学词汇筛选与统计接口；
- 创建轻量级复习配置弹窗 `VocabularyReviewDialog`，支持选择时间范围、考核模式（盲听 4 选 1 / 闪卡自评）与随机乱序开关；
- 将词汇表动作条按钮调整为 `[⚡ 复习]`，点击弹出配置并启动乱序复习会话；
- 复习会话采用临时乱序队列，不覆盖用户原本正在进行的顺序刷词断点。

**Non-Goals:**
- 不删除 SM-2 记忆算法底层的熟练度与间隔推导，复习作答结果依然正向回写熟练度状态机。

## Decisions

### 1. 时间跨度模型与范围计算 (ReviewTimeRange)
```dart
enum ReviewTimeRange {
  today('今日学习', '今天内学习或复习过的词汇'),
  last3Days('近 3 天', '最近 3 天内学习或复习过的词汇'),
  last7Days('近 7 天', '最近 7 天内学习或复习过的词汇'),
  last30Days('近 30 天', '最近 30 天内学习或复习过的词汇'),
  allStudied('全部已学', '所有历史上学习或复习过的词汇');

  final String label;
  final String description;
  const ReviewTimeRange(this.label, this.description);
}
```
- **今日界定**：以当前本地时间的 00:00:00 为基准（`DateTime(now.year, now.month, now.day)`），只要 `lastReviewedAt >= 今日 0 点` 即归入今日学习；
- **近 N 天**：取 `now.subtract(Duration(days: N))` 进行比较。

### 2. 沉浸学习时间戳同步记录 (Study Mode Timestamp Tracking)
在 `VocabularyStudyStore` 中增加 `recordWordStudied(String word)`：
- 沉浸学习翻阅到某词时调用；
- 保留原有熟练度等级与排期不变，仅更新 `lastReviewedAt: now.toIso8601String()`；
- 使得仅通过“沉浸学习”浏览过的词汇也能被准确归入“今日/近期学习过的单词”。

### 3. 轻量复习配置弹窗 (VocabularyReviewDialog)
- 在 `lib/tools/it_meeting_listening/ui/vocabulary_review_dialog.dart` 单独封装：
  - 时间范围单选 Chip：实时显示各档位词数 `今日 (N)`、`近 3 天 (N)` 等；
  - 模式选择 SegmentedButton 或 ToggleChips：`[🎯 盲听测验 (4选1)]` 与 `[🎴 闪卡自评]`；
  - 乱序选项 Checkbox / Switch：默认开启 `[✓] 随机打乱出题顺序`；
  - 底部动作：若选中的范围词数为 0 则禁用，大于 0 时展示 `[🚀 开始复习 (共 N 词)]`。

### 4. 复习会话与主干进度隔离
- 乱序复习是一次性的针对性复习活动；
- `VocabularySessionController.create` 传入 `customWords: shuffledWords`，且设置复习标识或不指定 `initialWord`，直接从第 1 题开始；
- 不会打乱或覆盖主干模式（如用户正在顺序刷到第 15 个词）的 `practiceProgress` 断点。

## Risks / Trade-offs

- **[Risk]** 用户今天新关注了 10 个词但还没进入任何模式学习过，是否算作“今日学习”？
  - **Mitigation**：只有真正触发过沉浸学习或测验的单词才具有 `lastReviewedAt`。未学习的单词属于“生词”，不属于“已学单词”。若需要学习生词，用户可直接点击「📖 沉浸学习」。
