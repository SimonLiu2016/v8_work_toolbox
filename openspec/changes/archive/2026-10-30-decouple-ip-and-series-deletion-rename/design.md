## Context

目前短视频工坊中，`AppPaths.videoStudioSeriesDir` 统一管理所有剧集项目，每个项目位于 `series_library/<seriesId>/`。其内部既存放长效 IP 资产（`characters/` 角色卡、`common_scenes/` 场景库、`series_profile.json` 道具卡与世界观），也存放单次制作产物（`episodes/<epId>/` 分集剧本、分镜看板及音视频媒体文件）。

当用户在剧集库列表页（`ProjectListPage`）点击删除时，原有的 `_manager.deleteSeries(seriesId)` 直接对整个项目目录执行递归物理删除，导致高价值人设与场景资产被连带抹杀。此外，`_SeriesCard` 缺少重命名入口，且在未选定剧集时 `SeriesPage` 直接展示“未选择剧集”，无法常驻管理 IP 资产。

## Goals / Non-Goals

**Goals:**
- 在 `ProjectListPage` 的 `_SeriesCard` 标题右侧提供修改名称的铅笔图标（`Icons.edit_outlined`），支持弹窗快速重命名并实时同步。
- 改造剧集删除逻辑：删除剧集时，物理清理该剧集对应的全部 `episodes/`（剧本、分镜、关键帧、视频片段、音频、片段交付文件），但严格保留该项目关联的 `characters/`、`common_scenes/` 与全局资产库。
- 改造删除确认弹窗，明确提示“剧本与分镜将彻底删除，IP 主库与全局资产库完好保留”，消除用户恐慌。
- 支持在未选定具体制作剧集时，`SeriesPage`（IP 主库）依然能够常驻浏览与管理独立 IP 资产。

**Non-Goals:**
- 不重写文件底层存储（继续沿用现有的目录与原子 JSON 文件架构）。
- 不改变音视频合成与分镜生成的执行引擎。

## Decisions

### 1. 剧集删除与 IP 资产保护分离机制
- **技术选择**：在 `StudioProjectManager` 中将物理删除重构为“分集制作产物安全清除”（`deleteSeriesProduction` / `safeDeleteSeries`）。
- **执行细节**：
  - 销毁目标锁定为 `episodesDir(seriesId)`，递归删除所有集数的 `storyboard.json`、`frames/`、`clips/`、`audio/`、`segments/`。
  - 对于该剧集建立的角色卡（`characters/`）与场景卡（`common_scenes/`），将其作为长效 IP 资产保留在 IP 资产库中，并在 `ProjectListPage` 中移除该制作工程。
- **替代方案考虑**：
  - *方案 B：完全删除剧集目录，并在删除前将角色卡强行复制到全局 assets*。缺点：三视图、3D 方位切片结构复杂，直接塞进平铺的 assets 丢失了角色与场景元数据结构。因此直接在 IP 资产层保留角色/场景配置更自然。

### 2. 剧集卡片铅笔重命名交互
- **技术选择**：
  - 在 `ProjectListPage` 的 `_SeriesCard` 中，标题文字后放置紧凑型 `IconButton`（16px，`Icons.edit_outlined`，tooltip: '修改名称'）。
  - 点击弹出 `RenameSeriesDialog`，包含文本输入框（默认填入当前名称，自动聚焦并全选）。
  - 点击“保存”或回车时，校验名称非空，调用 `_manager.saveSeries(series.copyWith(name: newName))`。
  - 若修改的是当前 `session.series`，同步调用 `session.select(updated)` 并触发 `onChanged`，使顶栏和卡片立即同步更新。

### 3. IP 主库常驻浏览支持
- **技术选择**：
  - 在 `SeriesPage` 中，当 `session.series == null` 时，不再直接显示“未选择剧集”的死页面，而是自动检索现存的可用 IP 项目或提供 IP 资产选择器，让用户能够直接在 IP 主库中查看与编辑角色库与场景库。

## Risks / Trade-offs

- **[Risk] 删除单集与删除整剧时的文件残留** → 通过封装 `_deleteEpisodeFiles(seriesId, episodeId)` 与 `deleteEpisodesUnderSeries(seriesId)`，确保 `episodes/` 目录下全部音视频衍生文件和缓存干净抹除。
- **[Risk] 会话状态漂移** → 当被删除的剧集恰好是当前 `session.series` 时，安全重置 `session.selectEpisode(null)` 与 `session.select(null)`，避免看板试图渲染已删除的分镜数据。
- **[Risk] 跨剧角色引用一致性** → IP 主库角色卡保留后，新建剧集可直接复用原有角色 ID，无需重新生成 Prompt 和三视图。
