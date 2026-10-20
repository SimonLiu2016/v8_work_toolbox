## Why

在小说单章导入后，用户发现「剧本工作台」为空，而「分镜看板」却已经显示分镜内容。根因在于小说导入流水线未落盘文学剧本文本（`screenplayText`），导入提取的节拍未填充台词/说话人字段，导入后未自动设置全局激活集，且分镜看板会保留目标集历史遗留的旧分镜或抢占第一集并绕过剧本拆解。短剧制作应遵循「原著 ➔ 分场剧本（对白与微动作） ➔ 5D 分镜」单向严格继承体系，必须理顺小说导入、剧本工作台与分镜看板之间的管线与数据传递。

## What Changes

- **小说单章影视化提炼升级**：在 `AiConstraintEngine.adaptNovelDramaChapter` 中同步提炼标准文学分场剧本文本（Markdown `screenplayText`）以及带角色台词（`dialogue`）、说话人（`dialogue_speaker`）、潜台词（`subtext`）与单一主干动作（`action`）的标准 `scenes` 和 `beats`。
- **单章导入持久化完善与陈旧分镜重置**：`StudioProjectManager.importChapterToEpisode` 完整持久化 `screenplayText` 与规范化 `scenes`；当用户重新导入章节到指定集时，重置清空该集旧的分镜（`shots: []`），杜绝陈旧分镜混淆。
- **导入任务完成后的上下文自动激活与工作流导航**：单章导入完成后，`IdeaIncubatorPanel` 自动将当前集选入全局上下文（`session.selectEpisode`），外壳导航直接聚焦至「剧本工作台」，让创作者第一时间审阅与打磨分场剧本。
- **分镜看板空状态引导强化**：分镜看板检测到当前集已有分场剧本但分镜为空时，提供「剧本已就绪，请在剧本工作台一键生成分镜」的显式引导与跳转，彻底消除“无剧本却有分镜”的错乱体验。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `ai-video-studio/novel-import`: 增加单章小说导入产出完整分场文学剧本（`screenplayText`）、结构化动作台词节拍（`scenes`），持久化时重置陈旧分镜，并在完成后自动选中激活当前集。
- `ai-video-studio/script-workshop`: 规范分镜看板对剧本场次与节拍的依赖，提供空分镜下的剧本转换引导，保证分镜镜头确凿源自已审核的剧本节拍。

## Impact

- **修改代码范围**：
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（更新 `novelDramaChapterAdaptation` Prompt 与 Schema 解析）
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`（`importChapterToEpisode` 写入 `screenplayText` 并重置 shots）
  - `lib/tools/ai_video_studio/services/novel_import_task_service.dart`（组装生成 Markdown 剧本文本并安全沉淀）
  - `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart` 与 `lib/tools/ai_video_studio/ui/studio_shell.dart`（单集导入完成后自动激活 episode 并跳转剧本工作台）
  - `lib/tools/ai_video_studio/ui/screenplay_panel.dart` 与 `lib/tools/ai_video_studio/ui/storyboard_board.dart`（空状态引导与数据同步）
- **影响依赖与测试**：
  - 更新与补充针对小说单章导入剧本文本与场次节拍的单元测试。
