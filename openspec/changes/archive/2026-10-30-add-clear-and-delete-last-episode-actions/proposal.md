## Why

创作者在“剧集库”（`ProjectListPage`）管理剧集时，目前只能新建分集与修改分集名称，缺失分集级的删除控制入口。若采用任意中间分集删除，容易引发序号空洞以及分集标题与序号错乱；而在实际影视制作工作流中，创作者最迫切的高频诉求是两类操作：
1. **撤销回退**：对刚拆解或试生成效果不佳的最后一集进行删除（“删除最后一集”）；
2. **重置重来**：全季剧本方案推倒重拟时的一键清空（“一键清空”）。

同时，在执行分集删除与清空时，分集对应的分镜、剧本与媒体素材必须同步彻底销毁，跨集前情记忆库必须级联清理；而 IP 主库与资产库（角色卡、三视图、公共场景、世界观）必须受到坚实的安全隔离保护，不受任何影响。

## What Changes

- **分集列表操作栏新增快捷清理按钮**：
  - 在“剧集库”卡片展开项及“IP 主库·分集列表”的头部，“新建第 X 集”按钮旁新增“删除最后一集”与“一键清空”按钮。
  - 当分集列表为空时，两按钮自动置灰禁用；当有分集存在时激活可用。
- **“删除最后一集”交互与数据清理**：
  - 自动识别当前最大序号的分集，弹出醒目的二次确认对话框。
  - 确认后物理删除该分集目录（连带其中的 `storyboard.json` 剧本与分镜、`audio/` 对白音频、`frames/` 分镜帧图、`clips/` 视频产物、`exports/` 导出文件）。
  - 同步清理 `StudioSeries.memories` 中对应的记忆条目；若当前会话选中了该集，重置为 `null` 退出工作台分镜编辑。
- **“一键清空”交互与批量级联清理**：
  - 弹出高危警示二次确认弹窗，明确说明将清理所有分集与媒体产物，但 IP 主库资产完全不受影响。
  - 确认后物理清空 `episodes/` 下的所有分集子目录，清空该剧集的全部 `memories`，重置全局分集会话。
- **IP 主库与全局资产库绝对隔离保证**：
  - 分集删除与清空操作的物理作用域严格锁定在 `series_library/<seriesId>/episodes/` 路径内，绝对不波及 `ip_library/<ipId>/` 目录下的世界观文本、角色资产、三视图与公共场景库。

## Capabilities

### New Capabilities

<!-- 无全新能力域 -->

### Modified Capabilities

- `ai-video-studio/episode-management`: 扩展分集管理能力，新增“删除最后一集”与“一键清空”交互规范、底层级联物理清理规范、前情记忆同步清理规范与 IP/资产库绝对隔离保护约束。

## Impact

- **UI 层**：
  - `lib/tools/ai_video_studio/ui/project_list_page.dart`: 在 `_SeriesCard` 展开的分集列表顶部工具栏新增“删除最后一集”和“一键清空”按钮及确认弹窗。
  - `lib/tools/ai_video_studio/ui/series_page.dart`: 在 `_EpisodesTab` 顶部工具栏同步新增该操作入口，形成两端一致的交互体验。
- **服务层**：
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 新增 `deleteLastEpisode` 与 `clearAllEpisodes` 核心管理方法，封装物理目录删除与 `series.memories` 级联清理逻辑。
- **测试**：
  - 新增 `test/episode_delete_and_clear_test.dart` 自动化测试，验证删除最后一集、一键清空、记忆库同步清理以及 IP 资产库完好性隔离。
