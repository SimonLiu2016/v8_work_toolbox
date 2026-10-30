## Why

在短视频工坊中，用户在“剧集库”中管理与删除制作工程时，目前的删除机制将整部剧集目录（包含角色卡、三视图、3D 全景场景库、世界观等 IP 资产）全部物理递归抹除，导致高成本打磨的人设和场景资产随剧本实验一同灰飞烟灭。此外，剧集库卡片上缺少直观的剧集重命名交互，无法灵活调整剧集命名。

为了解决长周期数字资产被误删的痛点，需要将 **“IP 主库资产（角色、场景、道具、世界观）”** 与 **“剧集制作工程（分集、剧本、分镜看板、音视频渲染文件）”** 的生命周期解耦：剧集库中的剧集删除时只清除其剧本、分镜及媒体产物，IP 主库与全局资产库不受影响且支持常驻管理；同时在剧集卡片上提供直接重命名的铅笔图标交互。

## What Changes

- **剧集重命名交互**：在剧集库列表页（`ProjectListPage`）的剧集卡片标题旁添加铅笔图标（`Icons.edit_outlined`），支持弹窗快速修改剧集名称并即时响应刷新。
- **剧集删除与资产解耦**：
  - 调整删除剧集的物理执行逻辑：删除剧集时，只清除该剧集的剧本（Screenplay）、场次（DramaScenes）、分镜看板（Shots）及渲染媒体（`frames/`、`clips/`、`audio/`、`segments/`），绝不删除对应的 IP 主库资产（角色卡、场景卡、道具、世界观）与全局资产库文件。
  - 更新删除确认对话框：明确提示“将彻底删除该剧集的全部剧本、分镜与音视频渲染文件，关联的 IP 主库与全局资产库完好保留”，消除用户恐慌。
- **独立 IP 主库支持**：
  - 支持在未选择剧集或剧集库为空时直接进入并常驻管理“IP 主库”，可浏览、编辑、新建角色卡与场景库。
  - 新建剧集时支持挂载关联已有 IP 资产，实现人设与场景资产在多剧集/多版本制作间的平滑复用。

## Capabilities

### New Capabilities
- `ai-video-studio/series-lifecycle-management`: 剧集库卡片重命名交互与安全的剧集制作产物清除机制（剧本与分镜同步删除，IP 主库与资产库受保护）。

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 调整 IP 主库与剧集制作区的耦合关系，确立 IP 资产独立生命周期，保证剧集删除不破坏 IP 角色卡与场景库。

## Impact

- **UI 层**：
  - `lib/tools/ai_video_studio/ui/project_list_page.dart`：在 `_SeriesCard` 标题旁新增重命名铅笔按钮；重构 `_confirmDelete` 弹窗文案与交互。
  - `lib/tools/ai_video_studio/ui/series_page.dart`：支持空剧集或常驻 IP 主库资产视图。
  - `lib/tools/ai_video_studio/ui/studio_shell.dart`：优化进入 IP 主库的导航行为。
- **Service 层**：
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`：拆分 `deleteSeries` 为保留 IP 资产的安全清除方法，增加 IP 库常驻存储与管理支持。
