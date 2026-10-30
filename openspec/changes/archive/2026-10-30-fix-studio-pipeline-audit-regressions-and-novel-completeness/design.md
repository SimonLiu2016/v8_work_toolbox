## Context

前序两个变更（`fix-studio-pipeline-data-honesty-and-silent-failures` 与 `fix-studio-pipeline-context-completeness`）为 AI 短视频工坊搭建了 `BreakdownInput`、`ShotVariationResolver`、`canRelayFrameFromPrev`、`requiresTaskId` 以及 `videoPromptSourceKey` 等基础机制，但在具体接入点存在 7 处实现级回归或短路漏洞（详见 `proposal.md`），同时尚未覆盖长篇小说 `>35,000` 字中部硬截断、同名角色/场景增量演进合并以及剧本双轨编辑冲突。

本设计在不推翻既有模型结构的前提下，精准修正上述 7 处回归并补齐长篇小说全书均匀采样与资产增量演进能力。

## Goals / Non-Goals

**Goals:**
- 让分镜看板与剧本工作台的 AI 拆镜真正优先读取最新文学剧本全文（`screenplayText`），消除粗大纲文本框短路与未保存内存态丢失；
- 让单镜角色服装形态（`ShotVariationResolver`）在关键帧生图、默认素材绑定和分镜卡片素材下拉列表中真正互斥生效；
- 让 `PromptAssembler.buildVideoGenPrompt`、`_VideoPromptDialog` 与 `AiConstraintEngine.rewriteVideoPrompt` 全链路遵守 `isVideoPromptStale` 并完整保留 `<Picture N>` 多图主体指代；
- 让批量接力生成视频时满足 `canRelayFrameFromPrev` 的相邻分镜建立串行等待依赖，并补齐机位俯仰角、空间高度层、视线/站位翻转的反打拦截判据；
- 让超过 35,000 字的长篇小说采用「首尾保留 + 中部多窗口均匀采样」覆盖全书章节，并在单章导入与 `mergeMasterAssets` 中实现既有角色/场景的上下文注入、描述升级与新服饰形态自动追加。

**Non-Goals:**
- 不将 Markdown 全文剧本反向解析为结构化 `StudioScene`/`ScriptBeat` 树（通过拆镜优先级消岐与同步落盘解决双轨矛盾）；
- 不重构 `PhotorealisticPromptCompiler` 与 `SeedanceTaskCompiler` 的底层架构。

## Decisions

### 1. 分镜看板拆镜输入的「实质修改覆盖」判定（修复 Bug 1）

- **现状问题**：`StoryboardBoard._breakdown` 无条件传入 `rawTextOverride: _synopsisController.text`，而 `_synopsisController.text` 默认初始化为 `episode.synopsis`（非空），导致 `BreakdownInput.synopsisOf` 第一行直接返回粗大纲，永远跳过 `episode.screenplayText`。
- **决策**：
  - 在 `BreakdownInput.synopsisOf(StudioEpisode episode, {String? rawTextOverride})` 中：当 `rawTextOverride` 传入的值等于 `episode.synopsis.trim()` 且 `episode.screenplayText.trim().isNotEmpty` 时，不将其视为覆盖，而是返回 `episode.screenplayText.trim()`；仅当 `rawTextOverride` 被用户改写为与 `episode.synopsis.trim()` 不同的非空文本（或在 `ScreenplayPanel` 全文编辑模式下传入最新全文）时，才优先使用 `rawTextOverride`。

### 2. 剧本工作台内存态即时同步与双轨拆镜优先级消岐（修复 Bug 4 & Gap 1）

- **现状问题**：
  1. `ScreenplayPanel._handleModeToggle` 在用户选择「保留修改」切回结构化视图时只执行了 `setState(() => _isRawTextMode = false)`，未把 `_textEditorController.text` 赋给 `_screenplayText`，导致后续保存或拆镜读取到旧的 `_screenplayText`；
  2. `_breakdownWithAi` 直接从磁盘 `ep` 读取 `BreakdownInput.scenesOf(ep)`，忽略了内存里编辑过的 `_scenes`，且拆镜完成后 `ep.copyWith(shots: ...)` 覆盖了未保存的内存编辑；
  3. 当用户在全文模式下修改了剧情后，`ep.scenes` 仍是旧场次，而拆镜 Prompt 把旧 `scenes` 标为「优先遵循」，与新 `screenplayText` 冲突。
- **决策**：
  1. 在 `_handleModeToggle` 选择「保留修改」时，立即执行 `_screenplayText = _textEditorController.text` 并调用 `_saveChanges(silent: true)` 落盘；
  2. 在 `_breakdownWithAi` 与 `_convertToStoryboard` 入口处，先调用提取自 `_saveChanges` 的同步方法将当前内存态（`_scenes` 与 `_isRawTextMode ? _textEditorController.text : _screenplayText`）持久化到 `StudioProjectManager`，再以落盘后的最新 `StudioEpisode` 作为输入；
  3. 在 `BreakdownInput` 新增 `bool hasUnsyncedRawScreenplay(StudioEpisode episode)`（比较 `episode.screenplayText.trim()` 与由 `episode.scenes` 渲染出的默认 Markdown 文本是否不同且 `episode.screenplayText` 非空）：当检测到全文剧本含独立于 `scenes` 的修改时，`AiConstraintEngine.scriptBreakdown5D` 将 `【本集文学剧本全文（最高优先级，若与下方场次节拍冲突请以剧本全文为准）】` 作为主依据，不再把旧 `scenes` 标为「优先遵循」。

### 3. 单镜服装形态激活的互斥唯一化（修复 Bug 2）

- **现状问题**：`CharacterCard.activeVariation` 使用 `variations.firstWhere((v) => v.active)`。`ImageGenTask` 与 `StoryboardBoard._ensureDefaultBindings` 仅将命中形态设为 `active: true`，未将原第 0 个「默认」形态设为 `active: false`，导致 `firstWhere` 永远返回第 0 个形态；且 `_AssetRow._loadCandidates` 未调用 `ShotVariationResolver`。
- **决策**：
  - 在 `ShotVariationResolver` 上提供统一的辅助方法 `CharacterCard resolveCharacterForShot(CharacterCard character, StudioShot shot)`：若解析出的形态 `resolved != null`，返回 `character.copyWith(variations: [for (final v in character.variations) v.copyWith(active: v.id == resolved.id)])`；
  - 在 `ImageGenTask.run`、`StoryboardBoard._ensureDefaultBindings` 以及 `_AssetRow._loadCandidates` 中统一调用 `ShotVariationResolver.resolveCharacterForShot`，保证三处拿到的 `activeVariation` 完全一致且唯一激活。

### 4. 视频提示词过期校验内聚与 `<Picture N>` 全链路保留（修复 Bug 3）

- **现状问题**：`PromptAssembler.buildVideoGenPrompt` 内部未检查 `!shot.isVideoPromptStale`；`_VideoPromptDialog` 与 `AiConstraintEngine.rewriteVideoPrompt` 调用 `buildSanitizedVideoPrompt` / `buildVideoGenPrompt` 时未传入 `materials`，导致预览、重置、AI 消解冲突及保存后的提示词丢失 `<Picture N>`。
- **决策**：
  - 在 `PromptAssembler.buildVideoGenPrompt` 开头将缓存短路条件改为 `if (shot.videoPrompt.trim().isNotEmpty && !shot.isVideoPromptStale) return shot.videoPrompt.trim();`；
  - 为 `PromptAssembler.buildSanitizedVideoPrompt` 与 `AiConstraintEngine.rewriteVideoPrompt` 增加可选参数 `List<AgnesReferenceMaterial>? materials`；
  - 在 `_VideoPromptDialog` 中，通过 `AssetBindingResolver.resolveForShot`（结合 `ShotVariationResolver.resolveCharacterForShot`）解析当前分镜的 `materials`，并在初始化默认预览、「重置为默认装配」和「AI 智能消解冲突」中全程传入 `materials`；同时在弹窗顶部若检测到 `widget.shot.isVideoPromptStale` 为 `true`，自动展示重新装配后的最新提示词并提示用户旧缓存已随分镜字段变更自动刷新。

### 5. 多前置任务依赖与跨镜尾帧接力串行化 + 严密反打判据（修复 Bug 5 & Bug 6）

- **现状问题**：
  1. `StudioGenerationTask` 仅支持单个 `requiresTaskId`，批量入队时 `vid-2` 只等 `img-2` 而不等 `vid-1`，并发度 ≥ 2 时 `vid-1` 与 `vid-2` 同时跑，`vid-2` 读不到 `shot_1.mp4`；
  2. `canRelayFrameFromPrev` 未检查 `cameraAngle`、`elevationLevel` 以及 `continuity.gazeDirection` / `screenPosition` 翻转。
- **决策**：
  1. 在 `StudioGenerationTask` 中支持 `List<String> requiredTaskIds`（兼容保留 `String? get requiresTaskId => requiredTaskIds.firstOrNull` 及构造参数 `requiresTaskId` / `requiredTaskIds`）。`StudioTaskQueue._nextRunnable` 与前置失败级联检查遍历全部 `requiredTaskIds`：仅当全部前置任务均已成功完成时才可启动，任一前置任务失败则级联标记为 `prerequisiteFailed`；
  2. 在 `StoryboardBoard._enqueueSegment` 与 `_enqueueAllSegments` 中维护 `String? prevVideoTaskId` 與 `StudioShot? prevShot`：当 `prevShot != null && prevVideoTaskId != null && canRelayFrameFromPrev(prevShot, shot)` 时，当前镜头的 `VideoGenTask` 同时依赖 `[if (frameTaskId != null) frameTaskId, prevVideoTaskId]`；
  3. 扩展 `canRelayFrameFromPrev` 与 `_isReverseShot`：
     - 若两镜 `cameraAngle` 均非空且不相等（如 `high_angle` vs `low_angle`），返回 `false`；
     - 若两镜 `elevationLevel` 均非空且不相等（如 `balcony_2f` vs `ground`），返回 `false`；
     - 若两镜 `continuity.gazeDirection` 或 `continuity.screenPosition` 发生左右镜像对调（如一镜含 `left`/`左` 而另一镜含 `right`/`右`），视为正反打切换，返回 `false`。

### 6. 长篇小说全书多窗口均匀采样与资产增量演进合并（修复 Bug 7, Gap 2, Gap 3, Gap 4）

- **长篇小说均匀分块采样（Gap 2）**：
  - 在 `AiConstraintEngine` 中抽出纯函数 `String sampleNovelTextForContext(String novelText, {int maxChars = 35000})`：
    - 当 `novelText.length <= maxChars` 时原样返回；
    - 当超过 `maxChars` 时：保留首部 `10,000` 字（开篇立意与初始人物）+ 尾部 `8,000` 字（结局走向与终局设定），中间剩余预算 `17,000` 字在 `[10000, novelText.length - 8000)` 区间内均匀切分为 5 个采样窗口（每个窗口约 `3,400` 字，优先对齐段落/章节边界），窗口之间标注 `...(中段均匀采样窗口 #k，原文字位 X%~Y%)...`。
  - `extractNovelMaster` 与 `extractNovelEpisodes` 统一调用 `sampleNovelTextForContext`，彻底消除中部章节盲区。
- **单章导入既有资产上下文注入与全季状态修正（Bug 7 & Gap 4）**：
  - `AiConstraintEngine.extractNovelMaster` 增加可选参数 `List<String> existingCharacterNames` 与 `List<String> existingSceneNames`；`NovelImportTaskService.runSingleChapterPipeline` 传入当前剧集已有角色与场景名称列表，指示 AI 复用标准名并仅提炼增量特征与新角色；
  - `NovelImportTaskService._runFullSeasonPipeline` 在调用 `importNovelProject` 期间保持 `storyboard` 为初态，落盘完成后直接标记 `contract`、`storyboard`、`audit` 为 `StageStatus.skipped`。
- **同名角色/场景增量演进合并（Gap 3）**：
  - 在 `StudioProjectManager.mergeMasterAssets` 中：
    - 对同名 `CharacterCard`：当新提炼的 `descriptionZh`、`facialFeaturesZh`、`facialPrompt`、`basePromptPositive` 比既有字段更详尽（例如既有为空，或既有长度 `< 25` 且新内容长度 `> 既有长度 * 1.3`）时更新为新描述；
    - 当新提炼的 `attireZh` 或 `attirePos` 非空，且与既有 `defaultAttireZh`/`defaultAttirePrompt` 及全部 `existing.variations` 的 `name`/`attirePrompt` 均不同时：若既有 `defaultAttirePrompt` 为空则直接填入默认服饰并同步更新「默认」形态，否则自动追加一个新的 `CharacterVariation(id: idGenerator(), name: _deriveVariationName(attireZh, existing.variations.length), attirePrompt: attirePos, active: false)`，既保留原「默认」形态与锚点图，又把新章节的服装沉淀到角色卡中供 `ShotVariationResolver` 匹配；
    - 对同名 `SceneCard`：同样支持当新 `descriptionZh` / `promptEn` 更详尽时升级描述，并合并新增的 `spatialViews`。

## Risks / Trade-offs

- **[Risk] 批量视频接力串行依赖可能拉长同一场次内连续镜头的总耗时** → **Mitigation**：仅在 `canRelayFrameFromPrev(prevShot, shot)` 为 `true`（同场景、同主体、同机位高度、非正反打）的相邻镜头间建立串行依赖；不同场次或切换了角色/机位的镜头之间依然保持并发执行，兼顾尾帧接力正确性与整体吞吐率。
- **[Risk] 同名角色自动追加新服装形态可能因表述微差产生多余形态** → **Mitigation**：对服饰文本做归一化核心词比对（忽略标点与空白，且若核心词重合度高于 60% 则视为同一套服饰不重复新增），且自动新增形态默认 `active: false` 不干扰用户当前选中的主形态。
