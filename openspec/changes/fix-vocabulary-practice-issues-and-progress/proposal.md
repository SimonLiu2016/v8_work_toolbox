# Proposal: fix-vocabulary-practice-issues-and-progress

## Why

用户在体验「重点关注」词汇的学习、盲听 4 选 1 测验与闪卡自评功能时，发现了四项影响核心体验的缺陷：
1. 「沉浸学习」中单词后的发音喇叭在默认状态下不可见，鼠标悬浮时仅呈隐约黑色阴影；
2. 「盲听测验」与「闪卡自评」中的发音喇叭存在相同的不可见与颜色异常问题；
3. 「盲听测验」未作答时，默认 4 个中文选项中的正确答案文本被加粗显示，导致提前泄题；
4. 三种练习模式均缺少进度记忆与断点续练能力，每次进入都会强制重置回第 1 题，导致中途退出的用户无法从上次位置继续学习。

修复这些 UI 与交互状态机问题，将使重点词汇的学习、考核与复习更加严谨自然，并大幅提升用户的碎片化学习连续性。

## What Changes

1. **显式高对比度音频按钮设计**：
   - 移除 `IconButton.filledTonal`（规避其在当前自定义 Theme 下 Material 3 底色与前景色异常覆盖的问题）；
   - 使用统一且显式的圆形徽标按钮：常态下提供柔和半透明强调色底（`accent.withValues(alpha: 0.12)`）与高对比度实体强调色图标（`accentText`）；
   - 播放状态下提供鲜明动效/实心强调色填充；保证浅色与深色模式下均一眼可见且美观。
2. **盲听测验防泄题与选项字重统一**：
   - 修复 `_buildQuizOptionTile` 中的判定逻辑，将选项文本加粗限制为仅在 `isAnswered == true` 时生效；
   - 未作答前 4 个选项保持一致的常规字重、背景与边框色彩，彻底消除视觉暗示。
3. **多模式学习进度记忆与断点续学**：
   - 在 `VocabularyStudyData` 与 `VocabularyStudyStore` 中增加多练习模式的进度记录 `practiceProgress`（持久化当前模式、最后停留单词 `lastWord`、索引位置及总数）；
   - 进入练习模式时自动定位至上次未完成位置，在顶部栏清晰展示续学提示（例如 `已从上次进度继续 (16/50)`）；
   - 在练习面板顶部栏提供一键 `[↺ 从头开始]` 按钮，允许用户随时重置当前模式为第 1 题；
   - 当用户完整刷完一轮到达答题报告总结卡（Summary）时，当前模式进度自动重置为已完成，下次打开自然开启全新一轮。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 增强重点关注词汇的沉浸学习、盲听测验与闪卡自评交互规范，补充高对比度发音操作反馈、严格的未作答防泄题机制以及多模式独立进度记忆与断点续学能力。

## Impact

- 涉及模型与服务：`lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`、`vocabulary_session_controller.dart`。
- 涉及 UI 交互：`lib/tools/it_meeting_listening/ui/vocabulary_practice_dialog.dart`、`vocabulary_browser_dialog.dart`。
- 涉及测试：`test/it_meeting_listening/vocabulary_study_quiz_review_test.dart` 补充发音按钮样式对比度、防泄题状态以及进度记忆断点续学的测试用例。
- 本地部署：修改完成后执行 `./scripts/deploy_local.sh` 编译部署。
