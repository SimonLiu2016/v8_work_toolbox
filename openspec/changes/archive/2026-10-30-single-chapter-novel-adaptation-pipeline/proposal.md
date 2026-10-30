## Why

当用户选择导入小说单章文本时，当前系统硬编码截取前 480 个字符作为本集大纲（`novelContent.substring(0, 480)`），导致小说后续 80%~90% 的矛盾推进、高潮爆发与结尾悬念彻底丢失。分镜看板因此只能拆解出原著开头的零星铺垫，严重违背了短视频制作对剧情完整起承转合的基本视听规律。必须引入单章深度理解分析与科学剧本大纲提炼管线，确保整章原文被完整理解并转化为标准的影视化单集大纲。

## What Changes

- 在 `AiConstraintEngine` 中新增单章剧本深度提炼任务 `novelChapterAdaptation`，输入单章全量小说原文，输出包含【开局抓手】、【矛盾推进】、【核心高潮】与【末尾留钩】的 300~500 字结构化短剧单集粗大纲（Synopsis）、单集标题、剧情摘要与悬念钩子。
- 在 `IdeaIncubatorPanel` 中移除 `novelContent.substring(0, 480)` 机械截取逻辑，单章导入流在提取增量资产后，调用 `novelChapterAdaptation` 提炼全章影视剧本大纲，并实时向用户展示深度理解进度。
- 在 `StudioProjectManager.importChapterToEpisode` 中完整承接结构化大纲与记忆，写入目标集并同步更新至跨集剧情记忆库。
- 在分镜看板中，基于覆盖全章故事脉络的高质量大纲拆分出 8~16 镜标准分镜组。

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: 增加单章小说全文深度分析与科学单集大纲提炼（`Single-chapter novel adaptation pipeline`）规范，杜绝文本硬编码截断，确保视听分镜覆盖原著全章故事脉络。

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 增加 `StudioAiTask.novelChapterAdaptation` 枚举、System Prompt 模板、Schema 校验器及对外调用方法。
- `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`: 改造单章导入流水线，串联 IP 资产增量提取与单章剧本深度提炼。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 接收并持久化结构化大纲。
- `test/studio_incremental_novel_import_test.dart` & `test/ai_constraint_engine_test.dart`: 补充单章剧本提炼契约测试与集成测试。
