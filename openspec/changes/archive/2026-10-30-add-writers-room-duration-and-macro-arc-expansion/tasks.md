## 1. 约束引擎 Prompt 与防缩水两级分幕架构 (AiConstraintEngine)

- [x] 1.1 升级 `_promptWritersRoomSeasonBeats` 与 Schema，新增 `macro_arcs`（大篇章/幕）与单集 `duration_sec`、`arc_name` 契约
- [x] 1.2 重构 `_SchemaValidators.writersRoomSeasonBeats` 校验与自愈逻辑，引入篇章感知平滑插值（Arc-Aware Interpolation），确保输出列表长度严格等于目标集数
- [x] 1.3 在 `_promptWritersRoomMasterExtract` 中注入多季架构元数据（`season_number`、`season_title`、`adapted_chapters_range`、`season_climax`）
- [x] 1.4 编写单元测试，验证两级篇章解析、80 集严格对齐与插值自愈机制

## 2. 编剧研讨室单集时长与全季看板交互 (WritersRoomDialog)

- [x] 2.1 篇章控制栏新增单集时长选择器（默认 90s，支持 60s/90s/120s/180s），并实时展示全剧总片长看板（分钟/小时）
- [x] 2.2 在分集大纲渲染中展示单集目标时长徽章（`duration_sec`）与台词字数建议（如 90 秒对应 300~450 字）
- [x] 2.3 在分集大纲中增加大篇章/幕（`macro_arcs`）视觉呈现，让 80 集大纲具备清晰戏剧结构
- [x] 2.4 在研讨室控制栏与主线卡片中显式标定【第 1 季】及其建议覆盖的原著章节范围

## 3. 全流程验证与本地应用构建部署

- [x] 3.1 运行相关单元测试确保全部用例通过
- [x] 3.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，验证功能在真实 macOS 环境中正常生效
