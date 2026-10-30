## Context

目前短视频工坊的分集列表存在于两处：
1. `ProjectListPage`（剧集库卡片展开的单集列表）；
2. `SeriesPage._EpisodesTab`（IP 主库的集数与前情列表）。

这两处列表中的分集标题均只呈现只读文本，缺乏修改入口。而单集的标题不仅存在于 `StudioEpisode.title`，也存在于跨集剧情记忆库 `StudioSeries.memories`（`EpisodeMemory.title`）中，用于生成后续集数时的 AI 上下文注入。

## Goals / Non-Goals

**Goals:**
- 在 `ProjectListPage` 展开的分集列表与 `SeriesPage._EpisodesTab` 分集列表中，统一在单集标题旁提供微型铅笔图标（`Icons.edit_outlined`）。
- 实现通用的 `RenameEpisodeDialog` 弹窗组件，显示固定的“第 X 集”标识，支持用户快速修改并回车提交单集标题。
- 数据联动保存：通过 `StudioProjectManager.saveEpisode` 保存分集文件，同时通过 `upsertEpisodeMemory` 同步更新剧情记忆库中的标题，并联动刷新全局会话 `StudioSession.episode`。

**Non-Goals:**
- 不在分镜看板与剧本工作台顶栏面包屑中添加重命名交互（保持面包屑只读导航的纯净性）。

## Decisions

### 1. 统一重命名组件与触发位置
- **技术选择**：在分集卡片标题 `第 ${ep.index} 集: ${ep.title}` 后面放置 14px 的紧凑型 `IconButton`（`Icons.edit_outlined`，tooltip: '修改单集名称'）。
- **弹窗设计**：弹出 `RenameEpisodeDialog`，明确固定集数序号（不可修改），仅允许修改标题文本。支持非空校验与自动聚焦。

### 2. 多端数据联动持久化
- **技术选择**：
  ```dart
  final updated = episode.copyWith(title: newTitle);
  await _manager.saveEpisode(updated);
  await _manager.upsertEpisodeMemory(
    seriesId: seriesId,
    episodeId: episode.id,
    title: newTitle,
  );
  if (session.episode?.id == episode.id) {
    session.selectEpisode(updated);
  }
  ```
  保证文件存储、内存状态与 AI 记忆库三位一体同步。

## Risks / Trade-offs

- **[Risk] 剧情记忆库与分集标题脱节** → 通过在重命名逻辑中显式调用 `upsertEpisodeMemory`，消除跨集记忆与单集标题不一致的风险。
