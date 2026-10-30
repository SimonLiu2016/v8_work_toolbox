## Why

AI 短视频工坊的「小说 → 剧集 → 剧本 → 分镜 → 视频」流水线在多个环节存在**静默型数据损坏**：用户看不到任何异常提示，但底层数据已被改写、阶段状态被伪造、或生成请求在错误的输入下"成功"完成。这些缺陷的共同特征是——**它们不报错，所以没人知道该修**。

具体包括：小说导入的质检阶段在根本没有分镜可检的情况下报告 100% 通过率；全季重导入会静默删除该剧集全部既有分镜与媒体；首尾帧接力在正反打/切景别场景下用上一镜尾帧覆盖本镜关键帧，并把错误的首帧路径写回数据；本地剧本映射分镜因携带常量 5D 字段而永久规避 C11 因果倒置检查；全文文本编辑模式的修改没有任何路径能回到结构化场次。

这些不是"功能缺失"，而是**数据完整性问题**。它们必须优先于任何提示词质量优化——否则下游所有改进都建立在不可信的数据上。

## What Changes

### 1. 导入流水线状态诚实化
- 全季导入（`isFullSeason: true`）在未生成剧本与分镜前，**严禁**将 `contract` / `storyboard` / `audit` 阶段标记为 `success`，也**严禁**硬编码 `auditPassRate = 100.0`。未执行的阶段 SHALL 标记为 `skipped`。
- 单章导入对空 `shots` 列表执行质检时，系统 SHALL 报告"无可检对象"而不是算出 100% 通过率。
- 流水线阶段状态机新增 `skipped` 终态，UI 以区别于 `success` 的图标与文案呈现。

### 2. 破坏性操作的显式确认
- **BREAKING**：全季重导入删除既有剧集前，系统 SHALL 弹出确认对话框，列明将要删除的集数、分镜数与物理媒体文件数，由用户确认后执行。未经确认不得删除任何既有剧集数据。

### 3. 首尾帧接力判据修正
- `AgnesVideoMode.keyframe` 模式下，本镜自己生成的关键帧（`shot.framePath`）**SHALL 始终作为本镜首帧**，不得被上一镜视频尾帧静默覆盖。
- 仅当满足**同场景 + 同核心主体集合 + 非正反打 + 景别差不超过 1 档**时，系统才使用上一镜尾帧作为首帧；否则使用本镜关键帧。
- 接力采用上一镜尾帧时，`firstFramePath` SHALL 记录实际使用的文件，并新增来源标记以区分"本镜关键帧"与"接力自前镜尾帧"。

### 4. 本地剧本映射的 5D 字段去假
- `convertScenesToShots` 生成的 `directorDecisions.temporalEvolution` / `aestheticTexture` / `physicalMomentum` **SHALL NOT** 写入常量占位文本。无法从节拍推导时留空，让 C11 因果倒置检查恢复生效。
- 连续性台账的 `holdingLeft` / `holdingRight` 同理：留空而非写死空语义。

### 5. 全文文本编辑模式的同步边界
- 用户在「Markdown 文本模式」下修改 `screenplayText` 后，系统 SHALL 在切换回结构化视图时检测到与 `scenes` 导出文本存在差异，并提示用户"存在未同步的文本修改"，而不是静默用旧 `scenes` 覆盖用户的编辑。
- 系统 SHALL NOT 提供反向解析（markdown → `DramaScene`）——本变更明确不引入该能力，仅保证不丢失用户输入。

### 6. 分镜看板拆镜不再回写粗大纲
- `StoryboardBoard._breakdown` 执行 AI 五维拆镜时，**SHALL NOT** 将文本框中的粗大纲内容写回 `episode.synopsis`。拆镜是读取操作，不得改写剧集概要字段。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `novel-import`: 导入流水线的阶段状态机新增 `skipped` 终态；全季导入在未生成剧本与分镜前不得伪造后续阶段成功状态或 100% 质检通过率；单章导入对空分镜列表执行质检时报告"无可检对象"而非 100%。
- `novel-import-task-lifecycle`: 导入进度如实反映执行阶段——未执行的阶段 SHALL 呈现为"未执行"而非"已就绪"；全季重导入的破坏性删除 SHALL 经用户显式确认并告知影响范围。
- `shot-production`: 分镜级视频的首帧来源判据——本镜关键帧优先，跨镜尾帧接力仅在满足同场景/同主体/非正反打/景别差约束时启用；首帧路径记录与实际使用文件一致并标注来源。
- `script-workshop`: 本地剧本映射产出的分镜不得携带常量 5D 导演决策占位文本；全文文本编辑模式的修改在与结构化场次存在差异时 SHALL 被提示而非静默丢弃；分镜看板执行 AI 拆镜时不得回写剧集粗大纲字段。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/novel_import_task_service.dart` — 阶段状态机（新增 `skipped`）、全季导入的 audit 标记、单章导入空 shots 质检分支。
- `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart` — 阶段节点渲染 `skipped` 状态；门禁质检分数在无可检对象时不显示。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart` — `_breakdown` 删除 `synopsis` 回写；全季导入确认弹窗（若入口在此）。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart` — `importNovelProject` 删除既有剧集前返回待删清单交由 UI 确认。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` — `VideoGenTask.run` 的 keyframe 接力判据；`firstFramePath` 写回逻辑与来源标记。
- `lib/tools/ai_video_studio/models/studio_models.dart` — `StudioShot` 首帧来源枚举（或复用现有字段语义）；阶段状态枚举扩展。
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` — `convertScenesToShots` 的常量 5D 字段改空。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart` — 模式切换时的差异检测与提示。

**依赖与测试**
- 更新 `test/ai_video_studio_generation_task_test.dart` 中断言接力行为的既有用例。
- 更新 `test/ai_constraint_engine_test.dart` 中依赖 `convertScenesToShots` 常量 5D 字段的断言。
- 新增接力判据的单测（同场景同主体接力 / 正反打不接力 / 切景别不接力）。
- 新增阶段状态机的单测（全季导入后续阶段为 `skipped`、单章空 shots 质检不出数）。

**不在本变更范围**
- 任务队列的依赖控制（同镜先图后视频）——由配套变更 `fix-studio-pipeline-context-completeness` 跟踪。
- `scriptBreakdown5D` 的节拍字段补传、`ImageGenTask` 参考图同源、`videoPrompt` 失效机制——同上。
- `scenes` / `screenplayText` / `synopsis` 三者的单一事实源重构——需要产品决策，另行立项。
