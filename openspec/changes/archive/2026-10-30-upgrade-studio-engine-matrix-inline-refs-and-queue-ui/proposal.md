## Why

在实际剧集生产测试中（如分镜 2 关键帧生成），影视工坊暴露出一系列严重影响可用性与生成质量的核心缺陷：
1. **生图质量崩溃与风格冲突**：分镜提示词组装时同时混入了互斥风格标签（如同时出现两次 `photorealistic 8k, live-action, arri alexa footage` 与两次 `UE5渲染，3D国漫，次世代CG`），导致生成模型特征崩溃；且角色/场景参考图仅在提示词前置区块粗暴堆叠，正文动作中缺乏行内素材锚定引用（如业界标准的 `余小白(图1)...寒阳城长街(图2)`），致使画面出现浮空演员与怪异塑料融解。
2. **视觉评测（VLM Critic）虚假合格与“视觉失明”**：分镜 2 存在严重五官融解与人体结构崩溃，却被评分为 95 分并标上绿色「VLM合格」印章。排查发现实际生图审查时 `AiService` 仅发送纯文本、从未把图片 Base64 编码载荷传给多模态模型，导致审图引擎完全“失明”打分；同时确定性规则存在大量盲区（未检查风格冲突、单人镜头忽略幽灵角色）。
3. **AI 引擎矩阵配置维度缺失**：当前工坊设置界面仅提供 `image` 和 `video` 两项引擎槽位，完全缺失剧本改编与因果编排所需的 `text`（LLM）、读图审片与分镜复核所需的 `vision`（多模态视觉模型）、配音生成所需的 `tts`、以及音画字幕对齐所需的 `stt/asr` 槽位，无法实现全链路端到端闭环。
4. **任务队列抽屉界面溢出**：抽屉面板缺少高度约束与独立滚动条，当任务较多或产生长文本时引发 Flutter `RenderFlex overflow`，且完成的历史任务被顶出可视区无法查看或回溯。

此时推进该项变更，能彻底打通从多模态模型配置、提示词精准行内引用组装、真实多模态视觉审片拦截，到任务队列可视化排障的完整质量闭环。

## What Changes

- **扩展影视工坊六维引擎配置矩阵**：在 `StudioSettingsDialog` 中将能力扩展为 `text`（剧本文本/因果推理）、`vision`（多模态读图审查）、`image`（关键帧/全景生成）、`video`（动态视频生成）、`tts`（角色台词配音）、`stt`（音频字幕识别与对齐）6 个标准能力槽位，与全局 `AiConfigStore` 联动，并支持模型候选降级与连通性验证。
- **行内素材引用注入（Inline Material References）**：重构 `PromptAssembler`，在提示词组装时将绑定的角色与场景素材以行内引用标记（如 `角色名(图1)`、`场景名(图2)` 或兼容各模型的参考图标签）直接注入到正文动作描述与主体后，让图像生成模型精准理解画面各实体的素材绑定对应关系。
- **提示词互斥风格净化器（Style Conflict Sanitizer）**：在提示词管线中建立风格互斥词库（如 3D国漫/CG vs 真人实拍/Arri Alexa/胶片感），根据剧集设定的母体风格自动剔除矛盾标签并去重，杜绝模型因冲突风格特征塌陷。
- **真实多模态视觉评测（Multimodal Vision Critic）**：
  - 升级 `AiService` 及视觉审查引擎，读取关键帧并以 Base64 Data URL 载荷（`image_url`）传入支持 Vision 的多模态大模型进行真实读图审片。
  - 增强审查评分 Prompt，对五官融解、多肢体、畸形手指、悬浮透视、风格破裂等缺陷实行一票否决（0~40分直接标记未通过）。
  - 加固确定性规则引擎：增加风格互斥检测、单人镜头多角色混杂（幽灵角色）检测，未通过多模态审查或存在致命缺陷的图像坚决不打合格标签。
- **任务队列抽屉 UI 体验重构**：
  - 为 `_QueueDrawer` 增加 `ConstrainedBox` 高度约束与平滑 `Scrollbar`。
  - 将任务列表改为懒加载滚动组件，新增状态筛选 Chip 标签页（「全部」、「进行中」、「已完成」、「失败」），保证历史已完成任务清晰可查，彻底根除 `RenderFlex` 溢出。

## Capabilities

### New Capabilities
- `ai-video-studio/engine-matrix`: 影视工坊六维 AI 引擎矩阵（文本、视觉、图像、视频、TTS、STT）的统一配置、模型槽位绑定与连通性调度能力。

### Modified Capabilities
- `ai-video-studio/shot-continuity`: 扩展行内素材引用注入（Inline Material Reference Injection）与提示词互斥风格净化规约，确保镜头提示词中实体精确对应参考图编号，且剔除互斥风格标签。
- `ai-video-studio/shot-production`: 升级分镜生产规范，引入基于真实图像 Base64 载荷的 VLM 多模态视觉质检与缺陷一票否决机制；重构任务队列抽屉交互，提供带滚动条、高度限制与状态筛选的队列面板。

## Impact

- **受影响模块**：
  - `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`（扩展 6 维引擎设置）
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`（行内引用注入、互斥风格净化）
  - `lib/tools/ai_video_studio/services/keyframe_visual_critic.dart` & `lib/core/ai/`（多模态图像 Base64 传输与严格质检）
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`（任务抽屉滚动与筛选重构）
- **数据与 API 兼容性**：
  - 兼容现存 `StudioCapability` 持久化，向前兼容 `image` 与 `video`，新增 `text`, `vision`, `tts`, `stt` 默认回退到全局 AI 槽位。
  - 提示词行内引用保持向后兼容，当未提供角色参考图时平稳退化为纯文本名字。
- **测试覆盖**：
  - 新增行内引用与风格互斥清洗单元测试。
  - 新增 VLM 多模态审片 payload 格式与缺陷拦截测试。
  - 新增任务队列滚动与筛选组件 Widget 测试。
