# Proposal: add-adaptive-auditory-familiarity-review

## Why

在盲听复习与测验过程中，传统的单纯基于“作答是否正确”的二元判定机制存在显著认知缺陷：
用户在盲听某道题目时，即便最终选出了正确答案，但如果反复重播了 3~4 次发音、犹豫了很长时间，这表明用户在辨音或语感上依然存在显著迟疑或依赖中文排除法“蒙对”。如果系统仅凭最终答对就判定为“已掌握”并将下次复习推迟数天甚至两周，会导致生疏词汇无法得到及时强化。

通过捕获用户在作答过程中的听音重播次数、作答耗时与重播频度等行为遥测特征，推导真实听觉熟悉度，并针对辨音吃力或犹豫的词汇动态缩短复习间隔并在当前会话内即时回捞加测，能够大幅提高高难/生疏词汇的出现频率，实现更加精准且贴合认知科学的听力复习闭环。

## What Changes

1. **听音行为无感遥测（Behavioral Telemetry）**：
   - 在 `PracticeItem` 中记录每道题目的听音播放次数 `audioPlayCount`、题目展示时间戳 `displayedAt` 以及作答耗时 `responseTime`；
   - 监听发音点击与空格键播放行为，准确累加听音次数。
2. **多维听觉熟悉度推导模型（Auditory Familiarity Model）**：
   - 结合作答正误、播放次数和耗时，将每次答题熟悉度评定为 5 级：
     - `instant`（秒懂精通）：听 1 次且快速答对（<= 4 秒），熟练度 +1，拉长复习间隔；
     - `normal`（基本熟悉）：听 1 次且正常耗时答对，正常标准排期；
     - `hesitant`（迟疑辨析）：听 2 次选对，熟练度不上涨，复习间隔缩短为 1 天；
     - `struggling`（吃力/猜对）：听 >= 3 次选对，视为需要强化，streak 归零，复习间隔设为当天/12小时；
     - `lapse` / `severe`（答错）：熟练度降级，复习间隔设为立即/当天。
3. **双层复习频次提升机制（Double-Layer Reinforcement）**：
   - **宏观时间加密**：对于迟疑、吃力或答错的词汇，将其 `nextReviewDue` 设为当天或明天，使其在下一次“今日复习”或“近 3 天复习”中保持最高复习频度；
   - **当轮会话回捞**：对于当轮复习中听音 >= 3 次或答错的生疏词汇，会话引擎在完成常规队列后自动在文末追加再测一遍，当场加深听觉印记。
4. **即时友好反馈**：
   - 在题目解析与最终结算卡片中，友好提示听觉熟悉度反馈（如 `🎧 听音 3 次 · 辨音吃力，已自动为您缩短复习间隔并在文末安排强化`）。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 增强盲听测验与复习引擎，引入基于播放次数、作答耗时与重播频度的自适应听觉熟悉度判定，实现复习间隔动态加密与当轮生疏词自动回捞再测。

## Impact

- 涉及模型与服务：`lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`、`vocabulary_session_controller.dart`。
- 涉及 UI 交互：`lib/tools/it_meeting_listening/ui/vocabulary_practice_dialog.dart`。
- 涉及测试：`test/it_meeting_listening/vocabulary_study_quiz_review_test.dart` 补充行为遥测、熟悉度判定算法、排期加密及会话内回捞测试。
- 本地部署：修改完成后执行 `./scripts/deploy_local.sh` 编译部署。
