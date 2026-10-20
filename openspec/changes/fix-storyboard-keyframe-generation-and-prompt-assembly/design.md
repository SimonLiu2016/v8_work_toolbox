## Context

当前分镜看板在批量生成关键帧时，底层依赖 `StudioGenerationTasks` 中的 `ImageGenTask` 与 `VideoGenTask` 进行异步调用。各任务启动时读取 `episode = manager.readEpisode(...)`，生成耗时 15-40 秒后，在 `finally` 和结束逻辑中用启动时的旧快照覆盖保存回盘，直接抹除了并发跑完的其他任务的成果。

同时，生图提示词体系存在严重的信息冗余与错位：场景生成对室内场景缺乏环境锚点净化，多图合成模式未遵循参考图规范，把 IP 主库中长达 500+ 字的人物容貌服饰长文与站位混淆并堆砌在提示词中，造成图文注意力冲突与动作稀释。

## Goals / Non-Goals

**Goals:**
- **并发写入零丢失**：提供 `StudioProjectManager.updateShot` 原子回写接口，重读磁盘最新数据，杜绝旧快照覆盖。
- **历史成果零成本自愈**：在 `_healEpisodeMediaIfNeeded` 中同时匹配 `shot_${number}.png` 与 `shot_${number}.mp4`，打开看板即可自动恢复磁盘已存在的 7 张关键帧。
- **场景提示词室内净化**：在 `ScenePromptBuilder` 引入 `isEnclosedScene` 检测，滤除仙山云海等室外词。
- **提示词多图合成精简与构图解耦**：当传入角色三视图时，剥离静态外观描述，专职化 `【同框人物与站位】` 为画内空间关系，将注意力权重彻底归还给当镜核心动作 `actionZh`。

**Non-Goals:**
- 不改变底层 AI 模型供应商与接口协议（保持兼容 Agnes Image 2.5 Flash 与 OpenAI 规范）。
- 不调整看板前端 UI 卡片布局或增加额外交互按钮。

## Decisions

### 1. `StudioProjectManager.updateShot` 原子化镜头更新机制
- **方案**：在 `StudioProjectManager` 中实现 `updateShot`：
  ```dart
  Future<StudioShot?> updateShot(
    String seriesId,
    String episodeId,
    int shotNumber,
    StudioShot Function(StudioShot current) update,
  )
  ```
  在 `_writeChains['$seriesId:$episodeId']` 链条中执行：先通过 `_readJson` 重读磁盘上最新的一集 JSON，通过 `number == shotNumber` 定位分镜并应用 `update` 函数，更新 `updatedAt` 并通过 `_writeJsonAtomic` 落盘，最后返回更新后的分镜对象。
- **替代方案考虑**：对整个异步任务持续 30 秒持有全局锁。
  - *拒绝理由*：长达数十秒的网络请求期间持锁会导致并发数降为 1，严重拖慢批量生成体验。写操作极其短暂（数毫秒），只需在写盘时序列化并读最新状态即可保证并发安全。

### 2. 磁盘媒体自愈命名探测
- **方案**：在 `_healEpisodeMediaIfNeeded` 中对关键帧和视频文件进行多候选命名探测：
  - 关键帧候选：`shot_${shot.number}.png`（优先）与 `${shot.number}.png`；
  - 视频片段候选：`shot_${shot.number}.mp4`（优先）与 `${shot.number}.mp4`；
  只要检测到文件存在且文件大小 > 1024 字节，即判定为有效并恢复至分镜对象。

### 3. 场景生成底图室内/地牢环境锚点净化
- **方案**：在 `ScenePromptBuilder.buildPositivePrompt` 中：
  - 调用 `PromptAssembler.isEnclosedScene(scene)` 检测；
  - 若为封闭/室内/地牢场景，对 `era.environmentAnchor` 和 `styleTokens` 执行 `PromptAssembler.sanitizeStyleForScene(..., isEnclosed: true)`，剥离 `云雾缭绕|奇峰仙山|古建亭台楼阁|云海雾气` 等词，并补充室内局部微光。

### 4. 多参考图模式提示词精简与站位解耦
- **方案**：在 `PromptAssembler.buildShotPrompt` 中：
  - **参考图判断**：当 `isMulti` 或存在角色参考图（三视图/面部图）时，判定为多图参考模式；
  - **角色外观精简**：不追加 `c.basePromptPositive`；仅保留 `c.name`、即时形态差异 `variation.positiveDelta`（若有）；
  - **同框站位专职化**：`【同框人物与站位】` 仅输出：`${effectiveCharacters.length} people in scene，${站位构图关系}`。站位结合分镜中的 `screen_position`、主客角色分工（主要角色居中/前景核心，次要角色侧方对峙），彻底移除静态外观文本；
  - **单人镜头精简**：单人模式输出 `【出场主体】: 角色名（画面核心主体，近景/中景）`；
  - **取景灵活性**：多图参考指令改为“严格保留角色面容与服饰特征，保留场景图中的建筑材质与环境光影风格，镜头根据当前分镜动作动态取景”，解除机位死锁。

## Risks / Trade-offs

- **[Risk] 用户若未提供角色三视图或参考图，纯文生图时是否会丢失外观细节？**
  - **Mitigation**：仅在“具备角色参考图”或“多图合成模式”下剥离静态外观文本；当分镜无任何角色参考图（纯文生图冷启动）时，保留基础外貌提示词注入，并在专用外观段落输出，确保向下兼容。
- **[Risk] 并发更新与前端轮询刷新**
  - **Mitigation**：任务更新完成触发 `onPersisted(updatedShot)`，看板局部刷新或重新加载时，由于读到的是包含全部已完成分镜的最新磁盘数据，不会再发生分镜图片闪烁消失问题。
