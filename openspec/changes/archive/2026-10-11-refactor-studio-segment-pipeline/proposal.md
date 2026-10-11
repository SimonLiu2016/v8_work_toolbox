## Why

AI 短视频工坊当前以「一镜一段」为视频生成单元：一集 8–16 个分镜各自生成 3–5 秒片段后拼接。这带来三个互相叠加的问题：单集需要 16+ 次云端视频调用（成本高）、片段之间没有任何连续性契约（拼接后观感割裂）、分镜表一旦因为时长或叙事需要合并镜头就必须推翻重来。对标 Toonflow（`packages/skills/workflow/SKILL.md`，1406 行 PART A 导演规则书）后确认，根因是缺少「片段」这一层生产单元，以及配套的跨镜连续性台账。

## What Changes

- **新增「片段（Segment）」生产单元**：一集由若干片段组成，每个片段包含 N 个连续分镜、一份中文分镜提示词、一个目标时长，以及**一次**视频生成产物。分镜（Shot）保留，继续承载关键帧、台词、TTS、SRT 与运镜选择。
  - `drama` 类型：视频生成以片段为单位，以该片段所有出场角色的参考图作为多参考输入。
  - `anime` / `narration` 类型：默认仍按分镜生成本地 Ken Burns 片段，但允许整段合并为一次生成（减少 FFmpeg 调用次数）。
- **新增「连续性台账」**：每个分镜携带一份结构化状态（世界坐标、画面坐标、左右手持物、光照状态、本镜发生的状态变化），并作为硬约束注入生图与视频提示词。台账禁止 AI 自行桥接——原文给出初始状态时直接使用，不得补充"道具如何被拿到手里"之类的前史。
- **AI 拆镜升级为两段式**：先按叙事节拍划出片段边界，再在片段内拆镜。片段边界的判定依据是景别差、角度差与动作连续性（对标 Toonflow A7.3 段间衔接规则），而不是固定的镜头数量。
- **分镜看板新增「按片段」视图**：片段为可折叠分组，组内为分镜卡片；保留现有「按镜头」平铺视图。片段级操作（生成片段视频、查看片段提示词）与分镜级操作并存。
- **BREAKING** `storyboard.json` 结构变更：新增 `segments` 数组与分镜上的 `continuity` 对象。读取旧文件时自动迁移（无 `segments` 时按现有分镜顺序每 2–3 镜归入一个片段，`continuity` 为空对象），迁移结果写回前不改变任何已有媒体路径。
- **非目标**：不改动声音设计、FFmpeg 合成与剪映导出链路（它们消费 `shots` 的顺序与媒体路径，片段化后仍然成立）；不引入 Toonflow 集成（另见 `add-toonflow-studio-toolbox`）；不改造模型能力矩阵（另见 `borrow-toonflow-media-capability-matrix`）。

## Capabilities

### New Capabilities

- `ai-video-studio/segment-production`: 定义片段作为视频生成单元的边界划分规则、片段提示词组装、片段级生成任务与结果回写，以及与分镜级生成的覆盖关系。
- `ai-video-studio/shot-continuity`: 定义跨镜连续性台账的字段、注入规则与禁止事项（AI 不得自行桥接前史或状态变化）。

### Modified Capabilities

- `ai-video-studio/script-workshop`: 结构化分镜拆解从「一次性产出分镜列表」改为「先划片段边界再拆镜」，并要求产出每个片段的目标时长与景别/角度衔接说明。
- `ai-video-studio/shot-production`: 生图任务队列与差异化动态化策略需要支持片段级生成单元；分镜级生成降级为覆盖选项。
- `ai-video-studio/series-asset-library`: `本地文件目录结构` 要求补充片段媒体的存放位置（`segments/`）。

## Impact

- **数据模型**：`lib/tools/ai_video_studio/models/studio_models.dart` 新增 `StudioSegment`、`ShotContinuity`；`StudioEpisode` 增加 `segments`；`StudioShot` 增加 `continuity` 与 `segmentId`；`toJson`/`fromJson` 增加旧版迁移。
- **AI 约束引擎**：`services/ai_constraint_engine.dart` 的 `StudioAiTask.scriptBreakdown` 提示词与 `_SchemaValidators.scriptBreakdown` 需产出片段结构；`shotRegenerate` 需感知所属片段。
- **提示词组装**：`services/prompt_assembler.dart` 增加 `buildSegmentPrompt` 与连续性字段的拼接（含超限时的丢弃优先级）。
- **生成任务**：`services/studio_generation_tasks.dart` 新增 `SegmentVideoGenTask`；`VideoGenRequest` 增加 `referenceImages`（多参考）与 `durationSec` 的上限放宽。
- **任务队列**：`services/studio_task_queue.dart` 的 `StudioTaskKind` 增加 `segment`，队列面板分组显示。
- **UI**：`ui/storyboard_board.dart` 增加片段分组视图与片段级操作；`ui/series_page.dart` 不受影响。
- **视频适配器**：`services/video_gen_adapter.dart` 的 `SenseAudioVideoAdapter` 与 `AgnesVideoAdapter` 需支持多参考图输入；`KenBurnsVideoAdapter` 支持更长时长。
- **测试**：`test/ai_constraint_engine_test.dart`、`test/ai_video_studio_prompt_assembler_test.dart`、`test/ai_video_studio_task_queue_test.dart`、`test/ai_video_studio_generation_task_test.dart` 需覆盖片段化与迁移；新增 `test/ai_video_studio_segment_test.dart`。
- **不影响**：`services/ffmpeg_composer.dart`、`services/jianying_exporter.dart`、`services/studio_sound_design.dart` 的对外契约（仍按 `shots` 顺序消费）。
