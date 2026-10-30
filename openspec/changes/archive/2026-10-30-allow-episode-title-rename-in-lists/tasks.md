## 1. 剧集库分集列表重命名交互 (Project List Page)

- [x] 1.1 在 `ProjectListPage._SeriesCard` 展开分集列表项标题旁新增重命名铅笔图标按钮（`Icons.edit_outlined`）及修改弹窗

## 2. IP 主库分集列表重命名交互 (Series Page)

- [x] 2.1 在 `SeriesPage._EpisodesTab` 分集列表项标题旁新增重命名铅笔图标按钮（`Icons.edit_outlined`）及修改弹窗

## 3. 剧情记忆库联动与自动化测试 (Data Sync & Tests)

- [x] 3.1 确保单集重命名在更新 `StudioEpisode.title` 的同时，通过 `StudioProjectManager.upsertEpisodeMemory` 同步更新 `EpisodeMemory.title` 与会话状态
- [x] 3.2 编写单集重命名与剧情记忆同步的自动化测试用例

## 4. 本地部署与验证 (Deployment)

- [x] 4.1 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，端到端验证两处分集列表重命名
