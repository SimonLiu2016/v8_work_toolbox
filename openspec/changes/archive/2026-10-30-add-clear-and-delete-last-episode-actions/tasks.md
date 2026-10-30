## 1. 底层工程服务与记忆级联清理 (Core Service & Memory Sync)

- [x] 1.1 在 `StudioProjectManager` 中实现 `deleteLastEpisode(String seriesId)` 方法，自动定位最大序号分集，物理删除分集目录并级联剔除 `series.memories` 中对应条目
- [x] 1.2 在 `StudioProjectManager` 中实现 `clearAllEpisodes(String seriesId)` 方法，清空 `episodes/` 目录下所有分集物理文件，并重置 `series.memories` 为全空

## 2. 剧集库卡片分集列表清理交互 (Project List Page UI)

- [x] 2.1 在 `ProjectListPage._SeriesCard` 展开的分集列表头部，于“新建第 X 集”按钮旁新增“删除最后一集”与“一键清空”按钮
- [x] 2.2 实现分集列表为空时“删除最后一集”与“一键清空”按钮置灰禁用逻辑
- [x] 2.3 实现“删除最后一集”二次确认弹窗与“一键清空”高危二次确认弹窗，确认后调用管理器清理并安全复位 `session.episode`

## 3. IP 主库分集列表清理交互 (Series Page UI)

- [x] 3.1 在 `SeriesPage._EpisodesTab` 分集列表头部工具栏同构接入“删除最后一集”与“一键清空”按钮及确认弹窗，保持两处体验一致

## 4. 自动化测试 (Automated Tests)

- [x] 4.1 编写 `test/episode_delete_and_clear_test.dart` 自动化测试，验证“删除最后一集”、“一键清空”、前情记忆级联清理、会话重置以及 IP 主库资产（角色/场景）隔离不受影响

## 5. 本地部署与验收 (Deployment)

- [x] 5.1 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，端到端实机验证操作流程
