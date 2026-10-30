## Why

用户在制作短剧时遇到了三项破坏创作链路的核心问题：
1. **世界观时代题材状态丢失**：在「IP主库」中选中的「视觉时代与题材世界观」标签，在切换 Tab 或菜单切回后恢复为未选中状态。经排查，由于 `StudioSession.select` 在同 ID 更新时直接 return，未能同步内存中的 `series` 对象，导致视图层读取到未更新的旧对象。
2. **场景图总带人物且描述不合理**：小说全案解构提炼出的场景中文与视觉描述混入了人物与动态交互（如“富家公子与江湖草莽在此交错”），导致翻译后的英文 Prompt 包含人物词汇；且场景生图缺少强制的正负向“纯净空镜”约束与多角度/全景组图支持。
3. **大段生成报参考图超限异常**：在「分镜看板」点击「生成大段」时抛出 `MediaCapabilityException: 当前模型最多支持 1 张参考图，本次请求携带 4 张`。经排查，用户本地 `ai_config.json` 中残留了历史保存的 `max_reference_images: 1` 声明，压制了模型真实支持能力（8 张），且 Agnes 协议默认值与预设也未放开至 8，适配器 auto 模式亦未能正确流转多图 reference 模式。

## What Changes

- **世界观设定与会话状态同步修复**：
  - 修复 `StudioSession.select`，当同 ID 的 `StudioSeries` 更新时，正确更新内存中的 `series` 并广播 `notifyListeners()`，不重置 `episode`；
  - 在 `StudioSession` 中补充显式的 `updateSeries(StudioSeries next)` 方法；
  - 让 `SeriesPage` 监听全局 `session` 变更，确保各个 Tab 切换与重新呈现时数据严格保持最新。
- **小说场景纯净空间解构与多视角/全景组图升级**：
  - 升级 `AiConstraintEngine._promptNovelMasterExtraction`，对 `scenes` 增加排他性硬约束：场景描述必须为纯净空镜空间建筑/陈设/光影，严禁包含任何具体人物、走动与情节动态；
  - 场景生图时，自动在正向提示词中注入空镜空间强化词（`empty scene, no humans, pure architectural scenery, vacant interior`），并在负向提示词中强制注入人类排除锁（`human, people, person, crowd, man, woman, face, character`）；
  - 升级场景卡：支持多角度与全景图生成（全景建立镜头、主轴平视角度、侧逆视角、空间局部特写），供创作者一次生成完整场景包。
- **大段 8 张参考图与 Agnes Reference 模式打通**：
  - 在 `media_capability.dart` 中，将 `MediaCapabilityDefaults.agnes` 与 `MediaCapabilityPresets.agnesVideo25` / `agnesVideo25Flash` 的参考图上限统一规范为 `8`；
  - 优化能力解析器 `MediaCapabilityResolver.resolve` 与供应商配置：当用户本地持久化的 `max_reference_images` 小于内置预设时，自动对齐最新预设能力，规避历史配置残留拦截；
  - 在 `SegmentVideoGenTask` 中显式指定 `mode: AgnesVideoMode.reference`，并在 `AgnesVideoAdapter` 中支持多图作为参考素材数组 `images: [...]` 正常提交。

## Capabilities

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 增加场景纯净空镜与多角度/全景套件支持，修复世界观与时代题材状态同步与持久化。
- `ai-video-studio/novel-import`: 约束小说解构提炼出的场景仅包含纯净建筑、陈设与空间光影，杜绝人物与剧情叙述混入场景卡。
- `media-model-capability-matrix`: 将 Agnes 系列模型的多参考图上限提升并对齐至 8 张，完善本地历史配置与官方预设的自愈解析。
- `ai-video-studio/segment-production`: 确保大段视频生成任务正确使用 reference 模式与多图参考列表向云端提交。

## Impact

- `lib/tools/ai_video_studio/ui/studio_shell.dart` (`StudioSession`)
- `lib/tools/ai_video_studio/ui/series_page.dart` (`_WorldviewTab`, `_ScenesTab`, `_SceneEditorSheet`)
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` (`_promptNovelMasterExtraction`, schema validators)
- `lib/services/media_capability.dart` (`MediaCapabilityDefaults`, `MediaCapabilityPresets`, `MediaCapabilityResolver`)
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` (`SegmentVideoGenTask`)
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart` (`AgnesVideoAdapter`, `VideoGenAdapterFactory`)
- 相关单元测试与自动化验证脚本
