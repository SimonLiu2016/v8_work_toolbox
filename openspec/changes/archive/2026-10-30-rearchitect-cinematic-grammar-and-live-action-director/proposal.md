## Why

当前 AI 分镜生成存在严重的呆板化与失真问题：代码中硬编码将所有镜头强制降级为“平视定机位”、“静止运镜”与“主体居中”，抹杀了 AI 面对复杂物理空间（如三楼向下抛物与街面拔刀格挡）的视听语言推导能力；同时，角色内心独白（OS）被直接当作口播台词，导致视频模型错误生成张嘴说话画面；世界观风格库亦缺少明确的“真人古装与真人短剧”预设，且制作形态默认负向词误伤真人出图。

## What Changes

- **AI 导演级视听语法与多维 Schema 升级**：在小说改编、剧本拆解与单镜推导的 System Prompt 中注入完整的电影视听导演导则（景别、机位视角高度、运镜动态轨迹、空间构图站位与视线正反打交互），由 LLM 自主进行物理空间与戏剧张力推导。
- **剔除分镜转换硬编码降级（Pass-through Pipeline）**：彻底清理 `ai_constraint_engine.dart` 中在 `convertScenesToShots` 时强行写入 `static`、`平视定机位`、`主体居中`、`平视正前` 的覆写代码，完整透传并保留 AI 导演推导出的镜头参数。
- **内心独白（OS）声画物理隔离**：在剧本与分镜中规范区分 `dialogue`（对白）、`inner_voice`（内心独白）与 `narration`（旁白）；对 `inner_voice` 统一格式化为 `角色（内心 OS）：内容`；在生图与生视频提示词装配中强制注入“自然闭口、眼神微表情、内心沉思、严禁开口对口型”约束。
- **扩充“真人实拍”世界观风格与制作形态解禁**：在预设库中新增【真人古装·仙侠影视大片】与【真人爆款·实拍短剧】；在剧集世界观设置界面暴露“制作形态”（实拍 / 3D 动画 / 2D 动漫）切换入口，确保真人实拍项目不再被默认 3D 动画负向词（`live-action photo`）误伤。

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `ai-video-studio/script-workshop`: 升级 AI 剧本与分镜拆解的视听语言维度体系，让模型自主推导景别、机位视角、运镜与构图，并在分镜转换管道中无损透传 AI 决策。
- `storyboard-visual-composition`: 规范内心独白（OS）在生图与生视频提示词中的闭口沉思约束，并增加真人实拍影视风格与制作形态负向词解禁支持。

## Impact

- **代码影响范围**：
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`（提示词工程、分镜拆解 Schema 与 `convertScenesToShots` 管道）
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`（生图与生视频提示词装配、OS 闭口微表情与运镜指令）
  - `lib/tools/ai_video_studio/services/studio_preset_store.dart`（新增真人古装与真人短剧风格预设）
  - `lib/tools/ai_video_studio/views/series_page.dart`（世界观设置中暴露制作形态切换）
- **数据结构与兼容性**：
  - `DramaBeat` 与 `StudioShot` 兼容已有字段，`voiceType` 与机位运镜字段全面打通，不破坏既有工程数据。
