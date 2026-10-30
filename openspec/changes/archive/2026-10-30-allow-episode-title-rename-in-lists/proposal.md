## Why

在短视频工坊中，用户在“剧集库（展开的分集列表）”与“IP 主库（集数与前情列表）”中查看各集时，分集默认名称通常为流水线起名（如“第 1 集”），创作者需要精修提炼更具剧情悬念与看点的单集标题。然而，目前这两处分集列表均缺少直接重命名入口，导致创作者无法快速自定义每集的标题。

## What Changes

- **剧集库分集列表重命名**：在 `ProjectListPage` 展开的分集列表项中，标题右侧增加铅笔图标按钮（`Icons.edit_outlined`），点击弹出 `RenameEpisodeDialog` 修改单集名称。
- **IP 主库分集列表重命名**：在 `SeriesPage` 的“集数与前情”分集列表项中，标题右侧同样增加铅笔图标按钮（`Icons.edit_outlined`），支持点击修改单集名称。
- **多端数据联动更新**：
  - 更新分集配置 `StudioEpisode.title` 并持久化至 `episodes/<epId>/storyboard.json`。
  - 同步更新剧集记忆库 `StudioSeries.memories` 中对应项的 `EpisodeMemory.title`，确保跨集记忆与 AI 上下文标题一致。
  - 若修改的为当前正在编辑的集数，联动更新 `StudioSession.episode`，使顶部面包屑与工作台状态即时刷新。

## Capabilities

### New Capabilities
- `ai-video-studio/episode-management`: 分集列表标题重命名交互与分集配置、剧情记忆库的多端联动同步机制。

### Modified Capabilities
None.

## Impact

- **UI 层**：
  - `lib/tools/ai_video_studio/ui/project_list_page.dart`：在 `_SeriesCard` 展开的分集列表项标题旁增加重命名铅笔按钮。
  - `lib/tools/ai_video_studio/ui/series_page.dart`：在 `_EpisodesTab` 分集列表项标题旁增加重命名铅笔按钮。
  - 提供通用的 `RenameEpisodeDialog` 弹窗组件。
- **Service 层**：
  - 调用 `StudioProjectManager.saveEpisode` 与 `upsertEpisodeMemory`，保证分集实体与剧情记忆标题一致性。
