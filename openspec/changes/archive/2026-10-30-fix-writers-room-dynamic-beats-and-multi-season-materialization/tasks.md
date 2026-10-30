## 1. 彻底移除机械复制插值，实现真实情节驱动分集 (AiConstraintEngine)

- [x] 1.1 优化 `planWritersRoomSeasonBeats` 的提示词，使大模型根据原著小说情节密度、危机转折与高潮自然推演生成高能独立分集
- [x] 1.2 重构 `_SchemaValidators.writersRoomSeasonBeats`，彻底移除拉伸映射克隆算法与 `(节拍 X)` 污染后缀，保证输出 100% 独立无重复分集

## 2. 研讨室多季路线图自动物化衍生项目 (WritersRoomDialog & StudioProjectManager)

- [x] 2.1 在 `WritersRoomDialog._applyBeatsToProject()` 中实现多季自动物化衍生逻辑与幂等查重机制，避免重复创建
- [x] 2.2 确保所有衍生季度项目（第 2 季、第 3 季等）严格继承主项目的 `resolvedIpId`、`novelId` 与主线脉络，并将各季分集与断章钩子写入对应项目

## 3. 剧集库卡片正面显化分季与集数徽章 (ProjectListPage)

- [x] 3.1 在 `_SeriesCard` 标题行渲染高亮【第 X 季 · 共 N 集】徽标，无需展开即可一览所属季度与实际分集总数
- [x] 3.2 在 `_SeriesCardState` 中实现 `didUpdateWidget`，确保跨工序定稿广播时卡片集数统计与分集列表即时刷新

## 4. 研讨室 Header 弹性自适应与固定关闭按钮 (WritersRoomDialog)

- [x] 4.1 重构 `WritersRoomDialog` 顶部 Header，左侧标题采用 `Flexible` + `TextOverflow.ellipsis`，精简操作按钮文案
- [x] 4.2 独立固定右上角关闭按钮，杜绝任何窗口宽度下的溢出与按钮遮挡

## 5. 验证与本地应用部署

- [x] 5.1 编写并运行单元测试与静态分析，验证真实分集校验与多季项目物化衍生逻辑
- [x] 5.2 执行 `./scripts/deploy_local.sh` 编译并替换本机应用，端到端验证研讨室顶栏排版、真实分集大纲呈现以及剧集库多季衍生新建
