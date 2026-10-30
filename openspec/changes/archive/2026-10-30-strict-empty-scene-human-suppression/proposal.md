## Why

在当前场景生图（包括单场景生成、七方位空间生图与多角度场景包生成）中，生图模型偶尔仍会生成带人物、人影、路人或背影的画面。这会导致作为纯净置景背景的场景资产遭到污染，无法正常在后续分镜中作为纯净物理空间复用。

导致该问题的核心原因包括：
1. **反向词注意力误激活**：现有的正向提示词中包含 `no humans, no people`，在现代大模型与扩散模型（如 FLUX、SDXL、Midjourney）的 Cross-Attention 机制下，`human/people` 敏感词根反而激活了人像潜变量概率分布；
2. **底层 Adapter 负向词丢失**：Agnes、SenseAudio 等图像模型适配器在组装 payload 时未传递或丢弃了 `negative_prompt`，且 FLUX 等主流模型原生不接受负向词引导；
3. **输入与推演阶段的语义携带**：原著环境描述或 AI 翻译后的英文 basePrompt 中常残留诸如 "bustling street"、"sect master's study"、"innkeeper counter" 等带有强烈生命体关联的词汇，缺乏前置自动过滤与净化。

因此，需要在场景生图体系中建立全链路的“严格纯净空镜与零人物抑制”防御机制。

## What Changes

- **肯定式“无人空旷环境”专有词典**：彻底摒弃容易产生误识别的 `no humans, no people` 等否定式短语，换用具有强力纯景物引导效果的专业建筑/摄影肯定式词典（如 `completely uninhabited, vacant space, deserted, empty background plate, architectural still life, unoccupied room, void of human presence, motionless stillness`）。
- **Prompt 首尾双重夹逼（Sandwiching）结构**：重构 `ScenePromptBuilder.buildPositivePrompt`，将无人空镜专有约束置于 Prompt 最前部（最高注意力区）以及最后部（收尾固化区），牢牢锁定底板性质，压制中间环境细节可能引发的人物联想。
- **英文 basePrompt 人物实体与动作关键词清洗（Scrubbing）**：在发送给生图模型前，增加专门的空镜敏感词过滤与语义净化器，自动剥离或替换 `human, people, person, crowd, man, woman, figure, pedestrian, someone, vendor, monk, soldier, sitting, walking, talking` 等实体名词与交互动词。
- **底层图像适配器负向提示词全贯通**：修复 `SystemAiImageAdapter` 与相关实现，确保在调用 Agnes、SenseAudio 及 OpenAI 兼容接口时完整传递 `negative_prompt`，使强力排他负向词典（`human, people, person, crowd, man, woman, face, character, figure, silhouettes, body`）下沉到底层服务生效。
- **AI 空间解构与翻译提示词源头强化**：在 `StudioAiTask.sceneSpatialDeconstruction` 与场景提示词翻译中升级规范，要求大模型输出物理几何体、材质与光影，严禁携带任何具体人称代词或职业职能修饰词。

## Capabilities

### New Capabilities
<!-- 无新增独立根能力 -->

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 增加场景空镜生图的严格人物抑制、敏感词实体清洗、肯定式环境词构建与底层适配器负向词贯通约束。

## Impact

- **模型与数据层**：[`ScenePromptBuilder`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/models/studio_models.dart) 增加肯定式空镜锁常量、basePrompt 敏感词清洗过滤算法、首尾双重夹逼组装逻辑。
- **AI 约束与解构层**：[`AiConstraintEngine`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/services/ai_constraint_engine.dart) 场景翻译与空间解构提示词模板强化零人物物理置景要求。
- **图像适配器层**：[`image_gen_adapter.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/services/image_gen_adapter.dart) 补齐各协议对于 `negative_prompt` 字段的构造与透传，确保负向抑制真正到达后端。
- **UI 交互层**：`_SceneEditorSheet` 场景卡片在出图前进行清洗提示词透传，并在生图参数中保障纯净。
