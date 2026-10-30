## Why

当前在“分镜看板”生成关键帧时，生成的画面背景与所绑定的场景库资产（如“巡城司大牢”）严重脱节，且连续分镜画面高度雷同，表现不出分镜动作重点与戏剧焦点。

经排查，核心根因在于：
1. **触发端遗漏场景参数**：在 `StoryboardBoard._enqueueFrame` 中构造 `ImageGenTask` 时未传入分镜绑定的 `SceneCard`，导致场景参考图（如水牢/大牢正视图）根本未作为参考图发送给生图模型。
2. **提示词组装引擎技术债残留（`promptEn` 断层）**：PromptAssembler 仍沿用旧版西文扩散模型的英文标签逻辑，仅查询 `promptEn`，无视了场景与七方位档案中精细的中文空间描述（`descriptionZh`），在 `promptEn` 为空时只塞入 5 个字的场景名称，导致场景细节全部丢失。
3. **严重偏离 Agnes Image 2.5 Flash 官方推荐提示词规范**：
   - **多图合成未指明角色与组合关系**：官方规范明确要求 `[参考图角色] + [目标场景] + [图像之间的关系] + [风格 / 光照 / 构图]`（例如“将第一张图作为主要角色，第二张图作为场景参考，保留角色身份与场景外形，生成...”），而当前实现未对输入图像数组的角色与组合逻辑进行任何自然语言声明，导致模型机械式地并排合成双人全身立绘；
   - **提示词层级严重倒置**：当前将大量通用画质与室外风格词（如“云海雾气”）堆在最前，中间堆叠数百字角色静态外貌，而将决定画面灵魂的【主体核心动作与戏剧焦点】丢在第 200+ Token 尾端甚至完全遗漏，注意力权重严重衰减。

全面对齐 Agnes Image 官方提示词规范，补齐场景参考图链路，重构提示词注意力结构，是保证分镜关键帧忠实还原剧本场景与动作灵魂的必经之路。

## What Changes

- **场景库资产全链路注入关键帧生图任务**：在 `StoryboardBoard._enqueueFrame` 中按 `shot.sceneId` 检索 `SceneCard` 并传入 `ImageGenTask`；`ImageGenTask._referenceImages` 自动提取该场景与机位匹配的空间视角图（如 `spatial_front`）注入多参考图列表。
- **废弃对 `promptEn` 的单一依赖，全面接入中文空间档案与自然语言描述**：`PromptAssembler.buildShotPrompt` 优先提取场景及空间方位的 `descriptionZh`，彻底消除 5 字简写导致的场景语义丢失。
- **严格遵循 Agnes 官方「多图合成」与「高信息密度」提示词规范重构组装引擎**：
  - **显式声明多参考图角色与组合逻辑**：当输入多参考图时，在 Prompt 头部明确指明各图角色（如“将第一张图作为主要角色[$name]，第 N 张图作为背景场景参考[$sceneName]，保留角色的面容身形与场景的空间布局...”）；
  - **提示词注意力层级纠偏（核心动作与主体前置）**：重塑提示词结构为 `[参考图角色与保留声明] + [主体正在进行的具体动作与视觉焦点] + [场景环境细节与空间层次] + [光照氛围] + [景别与构图规范] + [画质基线]`，确保核心戏剧动作处于高注意力权重区间；
  - **角色文字描述精简锚点化**：既然已有三视图/参考图作为强一致性输入，文本中不再冗余输出 100+ 字的从头到脚静态细节，避免淹没动作与场景；
  - **场景风格词自适应净化**：依据场景的 `setting`（内景/外景）或关键词（大牢、密室、水牢、地下），自动剔除“云海雾气”、“广阔天地”等室外互斥风格词，注入匹配的封闭光影与环境氛围（如“昏暗油灯微光”、“青石水汽”）。

## Capabilities

### New Capabilities
- 无

### Modified Capabilities
- `storyboard-visual-composition`: 更新关键帧提示词组装与参考图注入契约，严格对齐 Agnes Image 多图合成、多模态自然语言描述与室内/室外风格自适应规则。

## Impact

- **Affected Components**:
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart` (`_enqueueFrame`, `_reassemblePrompt`)
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart` (`buildShotPrompt`, `assembleAgnesMultiImagePrompt`)
  - `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` (`ImageGenTask._referenceImages`, `ImageGenTask.run`)
- **API Impact**: 对接 Agnes Image 2.5 Flash API 的 Prompt 语义结构全面规范化为官方推荐的多图引导与层次叙述，保留原有 OpenAI 兼容协议和 `extra_body.image` 契约。
- **Data/Storage Impact**: 无数据破坏；本地 `storyboard.json` 分镜重新生成或重新组装时将得到结构更加合理、场景和动作还原度极高的全新提示词与关键帧。
