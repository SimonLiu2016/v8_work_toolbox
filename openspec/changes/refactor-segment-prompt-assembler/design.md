## Context

短视频工坊支持以「大段（片段，Segment）」为单元生成 4~12 秒的整段连贯视频。当前 `PromptAssembler.buildSegmentPrompt` 在生成发往视频模型（如 Agnes Video）的提示词时，直接将多个分镜脚本标记、台词、相互冲突的场景与运镜、以及重复的风格基线拼接入正文，造成 8 大核心问题（大量冗余重复、渲染器冲突、多场景撕裂、台词噪声、非标 `{{ref N}}` 标记、空镜与人物互斥等）。

## Goals / Non-Goals

**Goals:**
- 实现短语级语义去重器，消除风格基线与剧集风格词堆叠时的重复短语。
- 修复 `StudioProductionType.anime3d` 中的 `Unreal Engine 5 render` 与 `Octane render` 冲突。
- 全面采用官方标准的 `<Picture N>` 素材占位符替代 `{{ref N}}`。
- 彻底剥离提示词正文中的对白台词（`dialogue:`）与剧本结构符号（`shot N |`, `camera:`, `|`）。
- 单个视频片段聚焦锁定单一物理主场景，并在有角色出场时自动清洗过滤场景描述中的空镜排他词（如 `no humans`, `empty room`）。
- 协调运镜与时长指令：分镜有具体机位时屏蔽全局激进运镜，移除正文中的 `total duration Xs` 文本参数。

**Non-Goals:**
- 不在此阶段修改分镜级图片生成（`buildShotPrompt`）的主干模型。
- 不修改底层视频生成适配器的网络通信协议。

## Decisions

### 1. 短语级智能去重器 (`deduplicatePhrases`)
- 实现通用工具方法，按逗号/分号切分提示词短语，进行小写与前后空白归一化。
- 保持首次出现的顺序，剔除完全相同以及前后包含的冗余短语。
- 冲突渲染器过滤：检测若已包含 `Unreal Engine 5` 或 `UE5`，自动过滤 `Octane render`；反之亦然。

### 2. 标准素材占位符 `<Picture N>`
- 在 `buildSegmentPrompt` 中：
  - 角色引用：`$anchor <Picture ${refIndex + 1}>`
  - 场景引用：`$anchor <Picture ${refIndex + 1}>`
- 消除 `(reference {{ref N}})` 的双大括号标记。

### 3. 主场景锁定与空镜排他词智能过滤
- 片段往往包含多个分镜，若跨越多个场景卡，仅提取片段主体分镜所处的**主物理场景**（默认首分镜或占绝大多数分镜的场景），避免把室内酒楼与长街两个不同地点同时塞入一条视频指令。
- 实现 `filterEmptySceneTokens(String scenePrompt, {bool hasCharacters = false})`：
  若 `hasCharacters == true`，利用正则剔除 `\b(empty room|architectural interior|no humans|nobody|unoccupied|vacant|deserted)\b` 及其附带的标点符号。

### 4. 动作叙事整合与台词彻底剥离
- 视频生成模型不需要对白台词：剥离 `dialogue: ...`，仅保留其视觉动作。
- 去除 `shot N |`、`camera:`、`shot N state:` 等剧本符号，将多个分镜的 `actionZh` 整合为流畅连续的动作描述段落。
- 机位协调：若分镜定义了明确的机位（如 `static`），映射为自然的机位短语（如 `static camera, eye-level`），并抑制全局默认的 `motionTendency`（如避免强塞 `dynamic airborne camera`）。

## Risks / Trade-offs

- [Risk] 旧工程或已保存的剧集 `styleTokens` 包含了重复的风格词或 `Octane render`。
  → Mitigation: 在 `buildSegmentPrompt` 执行时进行动态短语去重与冲突清洗，即使历史数据存在脏数据，组装产出的最终发往 AI 的提示词依然干净规范。
- [Risk] 单视频片段跨场景剧情无法在一条视频中呈现。
  → Mitigation: AI 视频模型本就无法生成硬切的多场景视频；若片段剧情包含室内到室外的跨场景跳跃，系统应在拆镜或生成时建议用户使用分镜级单独生成，片段级则聚焦于首个主场景以保证画面空间统一。
