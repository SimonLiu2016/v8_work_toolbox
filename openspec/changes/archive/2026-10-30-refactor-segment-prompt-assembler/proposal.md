## Why

在短视频工坊中生成大段（片段）视频时，当前 `PromptAssembler.buildSegmentPrompt` 生成的发往 AI 视频模型的提示词存在大量严重缺陷：包含大量整段重复堆砌的风格词、混杂相互冲突的渲染器指令（如 UE5 与 Octane 并存）、非官方且无法识别的双大括号参考图标记 `(reference {{ref N}})`、混入纯文本噪声与对白台词、强行并列多个不同场景且包含空镜排他词（如 `no humans` 与人物动作互斥）、运镜指令互相矛盾（空中激进运镜与固定机位重叠）等。这导致 AI 视频模型理解紊乱、画面空间撕裂、人物变形且极易出现字符水印与伪影。

## What Changes

- **短语级语义去重与渲染器冲突清理**：
  - 修复 `StudioProductionType.anime3d` 预设文本，移除与实时管线冲突的 `Octane render`，规范 3D 国漫管线描述。
  - 实现提示词短语智能去重器（Deduplicator），去除基线词与风格词堆叠时的重复子句。
- **规范标准参考素材占位符**：
  - 将非标准的 `(reference {{ref N}})` 语法彻底替换为 Agnes 及主流视频模型规范的 `<Picture N>` 占位符。
- **剔除台词文本与剧本结构标记**：
  - 彻底剥离 `dialogue:` 对白台词文本（由独立配音/TTS/数字人口型管线负责，不进入视频画面指令）；
  - 去除 `shot N |`、`camera:`、`state:` 等剧本符号与管道符，将分镜动作整合为流畅自然的视觉动态叙事。
- **主场景锁定与空镜排他词智能过滤**：
  - 片段视频生成锁定单一物理主场景，避免多场景并列导致的场景撕裂；
  - 当片段存在出场角色时，自动过滤清洗场景提示词中的 `empty room`, `no humans`, `unoccupied`, `nobody` 等互斥空镜词汇。
- **运镜指令协调与无用参数剔除**：
  - 优先尊重分镜自身设定的运镜（如 `static`），分镜已有明确运镜时屏蔽全局激进运镜；
  - 移除提示词正文中的 `total duration Xs` 与 `continuous single take` 冗余文本，交由 API 参数层精准控制。

## Capabilities

### Modified Capabilities

- `ai-video-studio/segment-production`: 修改片段提示词组装规范，采用 `<Picture N>` 标准素材指代语法，去除台词与剧本标记，实现场景锁定、空镜词动态过滤与语义去重。

## Impact

- `lib/tools/ai_video_studio/models/studio_models.dart`: 修复 `StudioProductionType.anime3d` 预设，剔除 `Octane render` 冲突渲染器。
- `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 重构 `buildSegmentPrompt`，引入短语去重、排他词清洗、连贯动作生成与标准 `<Picture N>` 标记。
- `test/tools/ai_video_studio/prompt_assembler_test.dart`: 增加片段提示词组装、去重、排他过滤与占位符规范的单元测试。
