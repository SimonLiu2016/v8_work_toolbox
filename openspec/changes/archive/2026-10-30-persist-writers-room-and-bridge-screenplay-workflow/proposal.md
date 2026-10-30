## Why

编剧研讨室（Writers' Room）作为短剧制作的顶层战略中枢，能够通读原著并提炼出全书宇宙、多季路线图（seasons_roadmap）、宏观大幕（macro_arcs）、情节红线（must_keep/can_cut/can_modify）、角色关系与全季分集大纲。
然而当前研讨室数据纯粹驻留在弹窗内存态，点击定稿后上述核心成果直接被丢弃，再次打开研讨室全为空白；同时剧集未绑定 `novelId`，剧本工作台无法获知当前剧集关联的小说，中间工作区在无场次时亦未展示已同步的分集大纲与集尾钩子，剧集库亦未随会话广播刷新，导致策划数据断层、用户误以为同步失效，且完全不明确后续剧本如何衔接原著章节。

## What Changes

- **研讨室顶层策划全量落盘持久化**：在剧集目录建立 `writers_room.json` 持久化规范，完整存储绑定的 `novelId`、小说标题、全书主线、多季宇宙规划路线图、各季宏观篇章大幕、情节红线清单、角色关系矩阵与分集大纲；重新打开研讨室时自动加载回显，支持持续协商迭代。
- **剧集与原著小说双向绑定**：研讨室定稿时将选定小说的 `novelId` 严格写入 `StudioSeries.novelId`，打通全流程小说资产链条。
- **剧本工作台大纲可视化与双通道改编引导**：
  - 在剧本工作台显著展示当前选集中由研讨室同步的【本集核心对抗大纲】与【集尾断章钩子】；
  - 在剧本为空时提供清晰的双通道操作引导：**通道 ①【精读原著第 X 章深度改编】**（自动关联绑定小说、按集数自动匹配对应章节，AI 细读原文提取原汁原味对白与动作场次）；**通道 ②【基于大纲 AI 一键推演剧本】**（无需小说正文，基于大纲与角色画像直接生成分场）。
- **剧集库跨工序联动实时刷新**：使 `ProjectListPage` 监听 Session 的更新广播并在切换回剧集库时重新拉取最新剧集状态与集数统计，消除状态不同步假象。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 规范编剧研讨室策划产物持久化存储契约（`writers_room.json`）、状态回显自愈与小说 ID 强绑定。
- `ai-video-studio/script-workshop`: 规范剧本工作台对已同步分集大纲/断章钩子的可视化呈现、原著小说的自动化章节对齐联动以及剧集库刷新联动。

## Impact

- `lib/tools/ai_video_studio/models/studio_models.dart`: 定义或扩充研讨室策划持久化数据模型（`WritersRoomProfile`）。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 实现 `writers_room.json` 读写接口。
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`: 初始化加载已有策划数据，定稿时全量落盘并回写 `series.novelId`。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart`: 增加本集大纲/钩子展示面板，在空状态时提供原著章节联动与大纲推演双按钮。
- `lib/tools/ai_video_studio/ui/project_list_page.dart`: 监听 Session 广播实时更新剧集列表。
