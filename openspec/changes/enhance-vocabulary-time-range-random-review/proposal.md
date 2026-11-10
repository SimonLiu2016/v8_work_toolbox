# Proposal: enhance-vocabulary-time-range-random-review

## Why

目前词汇表重点关注工具栏仅提供单一硬编码的「复习今日」按钮，默认拉取 SM-2 算法推导出的到期词汇，且沿用词汇表的固定线性顺序进行测试。这存在两方面的不足：
1. **复习范围缺乏灵活性**：用户无法按自己的复习节奏按天或周期定向回顾（例如只想复习今天刚学的新词、或者近 3 天/近 7 天累计学过的所有词汇）；
2. **固定顺序产生伪记忆**：按照词单固定先后顺序进行测验容易让用户记住题目的前后位置，降低了实战听辨效果。

将「复习今日」升级为支持时间范围选择、动态统计词数、多考核模式并默认随机打乱测试的「复习」功能，将显著增强科学复习的实战效果。

## What Changes

1. **学习行为时间戳记录机制**：
   - 在 `VocabularyStudyStore` 中支持记录单词的最近学习/自评时间 `lastReviewedAt`；
   - 沉浸学习（Study）翻阅时同步记录时间戳，确保所有模式学习过的单词均纳入复习统计池。
2. **多粒度时间跨度筛选引擎**：
   - 引入 `ReviewTimeRange` 枚举，支持 5 档时间跨度：今日学习（当天 00:00 至今）、近 3 天、近 7 天、近 30 天、全部已学；
   - 在 `VocabularyStudyStore` 中提供 `getWordsStudiedInRange(range)` 接口及动态计数统计。
3. **轻量复习定制弹窗（Review Config Dialog）**：
   - 词汇表专属动作条中的「复习今日」按钮调整为「复习」；
   - 点击「复习」后唤起定制弹窗，展示各时间跨度的动态词数 Chip；
   - 支持切换考核模式（盲听 4 选 1 测验 / 闪卡自评）；
   - 支持勾选「随机打乱出题顺序」（默认开启），打破顺序记忆；
   - 确认后即刻发起定向复习会话。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 升级重点词汇复习能力，支持按学习时间跨度灵活筛选、多考核模式选择与随机乱序测试。

## Impact

- 涉及模型与服务：`lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`、`vocabulary_session_controller.dart`。
- 涉及 UI 界面：`lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`、`vocabulary_practice_dialog.dart`。
- 涉及测试：`test/it_meeting_listening/vocabulary_study_quiz_review_test.dart` 补充多时间范围筛选、随机乱序生成及复习弹窗交互测试。
- 本地部署：修改完成后执行 `./scripts/deploy_local.sh` 编译部署。
