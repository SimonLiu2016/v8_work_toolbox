## Context

见 proposal.md 与 spec.md。在当前《AI 短视频工坊》中，编剧研讨室（Writers' Room）负责全剧宏观顶层策划，包括原著主线解构、多季宇宙路线图（seasons_roadmap）、宏观大幕（macro_arcs）、必留/可删情节与全季分集大纲。
然而，由于缺少持久化落盘协议与跨工序联动，导致定稿后研讨室状态重开全空，绑定的原著小说 `novelId` 丢失，剧本工作台无法感知已同步的大纲与断章钩子，用户不清楚后续章节对齐与剧本生成的具体执行链路。

## Goals / Non-Goals

**Goals:**
- 在剧集目录下建立 `writers_room.json` 规范持久化，实现编剧研讨室全要素数据（多季路线、宏观大幕、情节红线、人物关系、分集大纲、对话历史）的保存与即时回显。
- 确立原著小说与剧集的永久绑定（`StudioSeries.novelId`），并在下游剧本工作台中实现基于集数对齐的原著章节自动化预选。
- 增强剧本工作台大纲可视化，展示已同步的核心冲突与断章悬念，并提供清晰的【原著精读深度改编】与【大纲 AI 推演】双通道生成入口。
- 实现剧集库（ProjectListPage）与 Session 广播的联动刷新，确保重命名与集数变更在剧集库中即时可见。

**Non-Goals:**
- 不修改分镜拆解（scriptBreakdown）与视频生成的下游底层渲染逻辑。
- 不强制要求所有短剧都必须绑定本地小说（保留纯大纲推演的灵活性）。

## Decisions

### 1. 编剧研讨室策划持久化（`writers_room.json`）
- **存储方案**：
  在 `AppSupportDir/video_studio/series_library/<series-id>/writers_room.json` 中保存独立 JSON 文件。
  包含字段：
  ```json
  {
    "novel_id": "...",
    "novel_title": "...",
    "master_plot": "...",
    "must_keep": [...],
    "can_cut": [...],
    "can_modify": [...],
    "characters": [...],
    "character_relations": [...],
    "seasons_roadmap": [...],
    "selected_season_index": 0,
    "season_episodes_cache": {"0": [...], "1": [...]},
    "season_macro_arcs_cache": {"0": [...], "1": [...]},
    "chat_history": [...],
    "updated_at": "..."
  }
  ```
- **Manager API**：
  在 `StudioProjectManager` 中新增：
  - `File writersRoomFile(String seriesId)`
  - `Future<void> saveWritersRoomData(String seriesId, Map<String, dynamic> data)`
  - `Map<String, dynamic>? readWritersRoomData(String seriesId)`
- **UI 恢复生命周期**：
  `WritersRoomDialog.initState()` 读取已有数据，若存在则自动恢复状态机变量，彻底解决“重新打开全空”的问题。

### 2. 剧集与原著小说双向绑定与章节流转
- **流转机制**：
  - 用户在研讨室通过小说选择器选中小说后，不仅提取文本，同时保存 `_novelId = result.novel.id`；
  - 在 `_applyBeatsToProject()` 时，将 `novelId: _novelId` 赋给 `StudioSeries` 并存盘；
  - 剧本工作台中的 `ScreenplayNovelAdaptDialog` 已经具备按 `widget.series.novelId` 自动载入小说并在第 N 集自动预选第 N 章的机制，绑定 `novelId` 后该机制即可原生无缝激活。

### 3. 剧本工作台大纲可视化与双通道引导卡片
- **面板增强**：
  在 `ScreenplayPanel` 主视图顶部增加【🎬 本集大纲与断章钩子】折叠/常驻卡片，展示：
  - **核心冲突 (Synopsis)**：来自 `ep.synopsis`；
  - **集尾悬念 (Hook)**：来自 `series.memories` 中对应集的 hook；
- **空状态重构**：
  当当前集 `_scenes.isEmpty` 时，用结构化的双通道卡片替换单薄的“暂无剧本场次与节拍”：
  - **通道 A【📖 原著章节精读改编】**：
    - 若 `series.novelId != null`，显示“已绑定原著《${novelTitle}》，自动对应第 ${ep.index} 章”，点击唤起改编弹窗直接精读该章原文；
    - 若未绑定，引导点击关联本地小说库；
  - **通道 B【⚡️ 基于大纲一键写剧本】**：
    - 点击直接以已同步的冲突大纲为输入，调用 `_generateScreenplayWithAi()` 生成 3~5 场影视剧本。

### 4. 剧集库（ProjectListPage）跨工序实时联动
- 在 `_ProjectListPageState` 的 `initState` 中注册 `widget.session.addListener(_load)`，并在 `dispose` 中移除监听；
- 当研讨室或其他页面更新剧集后，用户切换到剧集库，页面会自动重新执行 `_load()`，刷新剧集名称与集数统计。

## Risks / Trade-offs

- **[Risk]** 旧版剧集没有 `writers_room.json`。
  - **Mitigation**: `readWritersRoomData` 遇到文件不存在时安全返回 `null`，研讨室回退到根据剧集已有 `worldview` 与 `name` 展示初始引导状态。
- **[Risk]** 小说章节数与剧集集数不一定是 1:1（如第 1 集涵盖原著第 1~2 章）。
  - **Mitigation**: 默认预选第 N 章作为最佳基准，同时保留用户在 `ScreenplayNovelAdaptDialog` 中随时多选（例如勾选第 1、2 章）的自由度。
