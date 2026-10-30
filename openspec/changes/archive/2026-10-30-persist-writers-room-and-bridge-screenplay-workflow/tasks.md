## 1. 研讨室策划数据持久化与回显机制 (StudioProjectManager & WritersRoomDialog)

- [x] 1.1 在 `StudioProjectManager` 中新增 `writersRoomFile`、`saveWritersRoomData` 与 `readWritersRoomData` 独立文件落盘与读取接口
- [x] 1.2 在 `WritersRoomDialog` 初始化（`initState`）时读取并完整回显已有策划产物（多季路线图、宏观大幕、情节红线、角色关系与分集大纲）
- [x] 1.3 在 `WritersRoomDialog` 中记录选定小说的 `_novelId`，并在大纲规划或定稿同步时全量持久化写入 `writers_room.json`

## 2. 原著小说 ID 跨工序绑定与剧集更新 (WritersRoomDialog & StudioSeries)

- [x] 2.1 在 `_applyBeatsToProject()` 中将 `_novelId` 严格回写至 `StudioSeries.novelId` 并调用 `saveSeries` 固化落盘
- [x] 2.2 确保下游 `ScreenplayNovelAdaptDialog` 能够基于绑定的 `series.novelId` 自动无缝载入小说库并按分集序号预选对应原著章节

## 3. 剧本工作台大纲可视化与双通道改编引导 (ScreenplayPanel)

- [x] 3.1 在 `ScreenplayPanel` 顶部新增【本集大纲与断章钩子】高亮面板，清晰展示当前集的冲突大纲（`synopsis`）与悬念钩子（`hook`）
- [x] 3.2 重构剧本工作台空状态卡片，呈现清晰的双通道操作引导：【📖 精读原著第 X 章深度改编】与【⚡️ 基于大纲一键推演剧本】

## 4. 剧集库跨工序实时联动刷新 (ProjectListPage)

- [x] 4.1 在 `ProjectListPage` 中添加对 `StudioSession` 的广播监听，并在剧集发生定稿、修改或新建时自动重新拉取最新剧集列表与集数统计

## 5. 验证与本地应用部署

- [x] 5.1 运行单元测试与静态分析，确保研讨室落盘读写与剧本大纲桥接契约 100% 通过
- [x] 5.2 执行 `./scripts/deploy_local.sh` 重新编译并替换本机应用，端到端验证研讨室关闭重开回显、剧集库实时更新以及剧本工作台大纲引导
