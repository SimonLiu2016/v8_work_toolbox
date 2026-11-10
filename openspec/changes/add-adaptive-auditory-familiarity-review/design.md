# Design: add-adaptive-auditory-familiarity-review

## Context

此前盲听测验的记忆状态更新仅依赖二元的 `isCorrect` 布尔值。盲听过程中用户重复重播发音的次数与耗时没有被记录，导致即使听了三四遍、依靠中文排除法猜对的生疏词汇也被盲目推迟复习，违背了听力熟练度的训练规律。

## Goals / Non-Goals

**Goals:**
- 在 `PracticeItem` 与会话流转中无感采集每次答题的听音播放次数（`playCount`）与作答耗时（`responseDuration`）；
- 升级 `VocabularyStudyStore.recordQuizResult`，引入 `AuditoryFamiliarity` 评级，对秒懂答对与迟疑/多次重播答对做差异化排期；
- 实现当轮会话即时回捞机制：听音 >= 3 次或答错的生疏词自动追加到文末再次出题，当场夯实听辨；
- 提供清晰的视觉反馈与诊断提示。

**Non-Goals:**
- 不改变闪卡自评（Flashcards）已有的 1~4 级人工打分流转；
- 不改变词汇表原有的 SM-2 熟练度等级枚举（`fresh`, `learning`, `familiar`, `mastered`, `solid`），而是作为其输入调节器。

## Decisions

### 1. 听觉熟悉度分级模型 (AuditoryFamiliarity)
```dart
enum AuditoryFamiliarity {
  /// 秒懂精通：听 1 次且 <= 4 秒答对
  instant('秒懂精通', '听辨敏捷迅速，条件反射秒选'),

  /// 基本熟悉：听 1 次且 > 4 秒答对
  normal('基本熟悉', '听辨清晰无误，看题思考作答'),

  /// 迟疑辨析：听 2 次答对
  hesitant('迟疑辨析', '盲听二听确认，稍有犹豫'),

  /// 吃力猜对：听 >= 3 次选对
  struggling('辨音吃力', '多次重听辨析，听觉反射薄弱'),

  /// 辨音盲区：答错
  lapse('辨音盲区', '未能正确辨析，听觉认知脱节');

  final String label;
  final String description;
  const AuditoryFamiliarity(this.label, this.description);
}
```

### 2. 记忆曲线排期动态调节算法 (Dynamic Interval Adaptation)
在 `VocabularyStudyStore.recordQuizResult` 中：
```dart
AuditoryFamiliarity evaluateFamiliarity({
  required bool isCorrect,
  required int playCount,
  required Duration responseDuration,
}) {
  if (!isCorrect) return AuditoryFamiliarity.lapse;
  if (playCount >= 3) return AuditoryFamiliarity.struggling;
  if (playCount == 2) return AuditoryFamiliarity.hesitant;
  if (responseDuration.inSeconds <= 4) return AuditoryFamiliarity.instant;
  return AuditoryFamiliarity.normal;
}
```
- **`instant`**：`streak + 1`，`proficiency + 1`，排期延后 `defaultIntervalDays`（2~14 天）；
- **`normal`**：`streak + 1`，`proficiency + 1`，排期正常延后；
- **`hesitant`**：`streak` 保持，`proficiency` 不升级，`nextReviewDue = now + 1 day`（提高频次）；
- **`struggling`**：`streak = 0`，`proficiency = max(0, proficiency - 1)`，`mistakeCount += 1`，`nextReviewDue = now`（当天即刻待复习，高频出现）；
- **`lapse`**：`streak = 0`，`proficiency = max(0, proficiency - 1)`，`mistakeCount += 1`，`nextReviewDue = now`。

### 3. 会话内生疏词追加强化队列 (Intra-Session Reinforcement Queue)
- 在 `PracticeItem` 中增加 `bool isReinforcement = false` 标记；
- 在 `VocabularySessionController` 中维护 `_reinforceQueue = <String>{}`；
- 当某道题作答完成后，若判定为 `struggling` 或 `lapse`，且该题本身不是回捞重测题（`!item.isReinforcement`），则将其加入 `_reinforceQueue`；
- 当 `_currentIndex` 达到原列表末尾时，若 `_reinforceQueue` 非空，控制器从 `_reinforceQueue` 中构建新的强化题目追加到 `items` 末尾，实现闭环加测。

### 4. UI 提示与反馈
在盲听测验卡片上作答后，展示一个轻量诊断微章：
- 秒懂：绿色小图标 `⚡ 听音 1 次 · 秒懂精通`
- 迟疑：黄色小图标 `🤔 听音 2 次 · 迟疑辨析，安排次日巩固`
- 吃力：橙色小图标 `⚠️ 听音 N 次 · 辨音吃力，已缩短复习间隔并在文末加测`
- 选错：红色小图标 `❌ 辨音盲区，文末强化再测`

## Risks / Trade-offs

- **[Risk]** 回捞题目无限循环导致复习无法结束。
  - **Mitigation**：加测题目均标记 `isReinforcement = true`，加测题本身无论表现如何不再触发二次回捞，确保最多追加一轮，杜绝死循环。
- **[Risk]** 自动播放音频在加载时产生的耗时误差。
  - **Mitigation**：计时器以题目组件完成首帧渲染（`displayedAt`）为起点，网络或文件加载延迟不计入用户思考时长。
