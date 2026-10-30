## 1. 约束引擎与全书多季路线图契约 (AiConstraintEngine)

- [x] 1.1 升级 `_promptWritersRoomMasterExtract` 与 Schema，注入 `seasons_roadmap` 数组契约（包含各季序号、季名、原著章节跨度、推荐集数、核心主题、主要反派与季终高潮）
- [x] 1.2 重构 `_SchemaValidators.writersRoomMasterExtract`，增加 `seasons_roadmap` 健壮解析与缺失兜底自愈逻辑
- [x] 1.3 升级 `planWritersRoomSeasonBeats`，支持季上下文（`seasonNumber`、`seasonTitle`、`adaptedChaptersRange`、`seasonClimax`）针对性注入提示词
- [x] 1.4 编写针对多季宇宙路线图提取、字段解析与自愈兜底的单元测试

## 2. 编剧研讨室季播切换工作台与缓存交互 (WritersRoomDialog)

- [x] 2.1 在 `WritersRoomDialog` 中新增多季状态（`_seasonsRoadmap`、`_selectedSeasonIndex`）与按季大纲/大幕独立缓存（`_seasonEpisodesCache`、`_seasonMacroArcsCache`）
- [x] 2.2 在篇章控制栏实现季播切换控制器（Season Switcher），渲染所有季度的标签按钮，切换时无损读写对应季大纲
- [x] 2.3 在左侧面板主线脉络卡片上方增加“🗺️ 全书多季宇宙路线图蓝图”展示，直观呈现全书各季演进图景
- [x] 2.4 优化“定稿并同步至剧集大纲”逻辑，精准绑定当前选中的季名称与分集大纲

## 3. 验证与本地应用部署

- [x] 3.1 运行所有相关单元测试，确保 100% 通过
- [x] 3.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证多季全流程正常生效
