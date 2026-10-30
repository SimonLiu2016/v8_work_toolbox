## 1. 分镜看板与剧本工作台拆镜输入及双轨同步修复（Bug 1, Bug 4 & Gap 1）

- [x] 1.1 修改 `BreakdownInput.synopsisOf`（`lib/tools/ai_video_studio/services/breakdown_input.dart`）：当 `rawTextOverride` 与 `episode.synopsis.trim()` 相同时不视为用户手动覆盖，若 `episode.screenplayText` 非空则优先返回 `episode.screenplayText`
- [x] 1.2 在 `BreakdownInput` 新增 `hasUnsyncedRawScreenplay(StudioEpisode episode)`，并在 `AiConstraintEngine.scriptBreakdown5D`（`lib/tools/ai_video_studio/services/ai_constraint_engine.dart`）中当检测到全文剧本已独立修改时，将文学剧本全文标为最高优先级依据、取消旧场次节拍的「优先遵循」指令
- [x] 1.3 修复 `ScreenplayPanel._handleModeToggle`（`lib/tools/ai_video_studio/ui/screenplay_panel.dart`）：当用户在全文编辑模式下选择「保留修改」切回结构化视图时，立即将 `_textEditorController.text` 同步至 `_screenplayText` 并持久化
- [x] 1.4 修复 `ScreenplayPanel._breakdownWithAi` 与 `_convertToStoryboard`（`lib/tools/ai_video_studio/ui/screenplay_panel.dart`）：在执行拆镜或本地同步前先将当前内存中的 `_scenes` 与剧本文本持久化落盘，并以最新内存态数据作为拆镜/同步输入，防止被磁盘旧数据覆盖
- [x] 1.5 为 `BreakdownInput.synopsisOf`、`hasUnsyncedRawScreenplay` 与 `ScreenplayPanel` 双轨优先级编写单元测试（`test/tools/ai_video_studio/`）

## 2. 单镜角色服装形态互斥激活修复（Bug 2）

- [x] 2.1 在 `ShotVariationResolver`（`lib/tools/ai_video_studio/services/breakdown_input.dart`）新增 `resolveCharacterForShot(CharacterCard character, StudioShot shot)`，通过 `v.copyWith(active: v.id == resolved.id)` 将命中形态设为 `active: true` 且其余形态设为 `active: false`
- [x] 2.2 更新 `ImageGenTask.run`（`lib/tools/ai_video_studio/services/studio_generation_tasks.dart`）、`StoryboardBoard._ensureDefaultBindings` 与 `_AssetRow._loadCandidates`（`lib/tools/ai_video_studio/ui/storyboard_board.dart`）统一调用 `ShotVariationResolver.resolveCharacterForShot`
- [x] 2.3 为 `ShotVariationResolver.resolveCharacterForShot` 及非默认形态下 `AssetBindingResolver` 选图行为编写单元测试

## 3. 视频提示词过期校验与 `<Picture N>` 全链路保留（Bug 3）

- [x] 3.1 修改 `PromptAssembler.buildVideoGenPrompt`（`lib/tools/ai_video_studio/services/prompt_assembler.dart`）：在返回缓存 `shot.videoPrompt` 前校验 `!shot.isVideoPromptStale`
- [x] 3.2 为 `PromptAssembler.buildSanitizedVideoPrompt` 与 `AiConstraintEngine.rewriteVideoPrompt` 增加可选参数 `List<AgnesReferenceMaterial>? materials` 并透传至 `buildVideoGenPrompt`
- [x] 3.3 修改 `_VideoPromptDialog`（`lib/tools/ai_video_studio/ui/storyboard_board.dart`）：解析当前分镜绑定的 `materials`（含单镜服装形态解析），在初始化预览、「重置为默认装配」与「AI 智能消解冲突」中全程传入 `materials`，并在缓存已过期时自动展示最新组装提示词与刷新提示条
- [x] 3.4 为 `buildVideoGenPrompt` 过期失效回退及带 `materials` 的 `buildSanitizedVideoPrompt` `<Picture N>` 保留编写单元测试

## 4. 批量视频接力跨镜依赖链与反打拦截判据强化（Bug 5 & Bug 6）

- [x] 4.1 扩展 `StudioGenerationTask` 与 `StudioTaskQueue`（`lib/tools/ai_video_studio/services/studio_task_queue.dart`）支持多前置任务列表 `requiredTaskIds`（向后兼容 `requiresTaskId`）：全部前置任务完成方可启动，任一前置失败即级联标记 `prerequisiteFailed`
- [x] 4.2 强化 `canRelayFrameFromPrev` 与 `_isReverseShot`（`lib/tools/ai_video_studio/services/studio_generation_tasks.dart`）：增加 `cameraAngle` 一致性、`elevationLevel` 一致性以及 `continuity.gazeDirection` / `screenPosition` 左右镜像翻转的反打拦截
- [x] 4.3 修改 `StoryboardBoard._enqueueSegment` 与 `_enqueueAllSegments`（`lib/tools/ai_video_studio/ui/storyboard_board.dart`）：当相邻两镜满足 `canRelayFrameFromPrev` 时，为后一镜视频任务同时绑定本镜关键帧任务与前一镜视频任务 ID
- [x] 4.4 为 `StudioTaskQueue` 多前置任务依赖级联及 `canRelayFrameFromPrev` 俯仰角/高度层/视线翻转拦截编写单元测试

## 5. 长篇小说全书多窗口均匀采样与资产增量演进合并（Bug 7, Gap 2, Gap 3, Gap 4）

- [x] 5.1 在 `AiConstraintEngine`（`lib/tools/ai_video_studio/services/ai_constraint_engine.dart`）实现 `sampleNovelTextForContext(String novelText, {int maxChars = 35000})`，采用「首部 10,000 字 + 中部 5 个均匀采样窗口（共 17,000 字，对齐段落边界）+ 尾部 8,000 字」替代硬截断，并接入 `extractNovelMaster` 与 `extractNovelEpisodes`
- [x] 5.2 为 `AiConstraintEngine.extractNovelMaster` 增加 `existingCharacterNames` 与 `existingSceneNames` 可选上下文参数，并在 `NovelImportTaskService.runSingleChapterPipeline`（`lib/tools/ai_video_studio/services/novel_import_task_service.dart`）中传入当前剧集已有角色与场景名称列表
- [x] 5.3 修正 `NovelImportTaskService._runFullSeasonPipeline`：在 `importNovelProject` 落盘期间不再将 `storyboard` 阶段设为 `running`
- [x] 5.4 改造 `StudioProjectManager.mergeMasterAssets`（`lib/tools/ai_video_studio/services/studio_project_manager.dart`）：支持同名角色与场景的更详尽描述自动升级，并在提炼出新服饰特征时自动为角色卡追加非激活的新 `CharacterVariation`（保留既有锚点图与当前激活态）
- [x] 5.5 为 `sampleNovelTextForContext` 长文中部覆盖及 `mergeMasterAssets` 同名角色描述升级与新服装形态追加编写单元测试

## 6. 验证与本机部署

- [x] 6.1 运行 `flutter analyze` 与全量 `ai_video_studio` 相关单元测试确保零警告、全部通过
- [x] 6.2 运行 `openspec validate fix-studio-pipeline-audit-regressions-and-novel-completeness --strict` 校验规格合规性
- [x] 6.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机 `/Applications/V8WorkToolbox.app`
