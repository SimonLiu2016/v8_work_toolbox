## 1. 媒体隔离与归档服务

- [x] 1.1 在 `StudioProjectManager` 中实现 `archiveEpisodeMedia(String seriesId, String episodeId)` 方法，将当前集 `clips/` 和 `frames/` 下的文件安全隔离移动到 `archive/<timestamp>/`
- [x] 1.2 改造 `_healEpisodeMediaIfNeeded`：增加安全限制，对于未生成状态或新建的分镜，禁止仅凭 `shot_${number}.mp4` 强行自愈重连

## 2. 分镜看板清空与重拆交互优化

- [x] 2.1 改造分镜看板 `_confirmAndClearAllShots` 弹窗：增加「同时归档旧生成媒体（防止后续分镜错误关联旧视频）」复选框，并在确认清空时调用 `archiveEpisodeMedia`
- [x] 2.2 改造分镜看板 `_confirmAndReBreakdownFromScreenplay`：重拆前同样支持勾选隔离旧媒体，确保全新拆出的分镜处于干净的未生成状态

## 3. 剧本工作台按钮与操作心智解耦

- [x] 3.1 将剧本工作台的【一键转换为5D分镜看板】按钮重命名为【同步剧本节拍至分镜（本地）】，修改图标为 `Icons.sync_alt`，并在点击后的反馈 SnackBar 中明确标注为本地同步
- [x] 3.2 在剧本工作台顶部操作栏补充【AI 拆分分镜】按钮（或引导至分镜看板 AI 拆镜），直接调用 `scriptBreakdown5D` 大模型五维拆解服务

## 4. 验证与工程构建部署

- [x] 4.1 编写单元测试验证：执行媒体归档后旧文件脱钩、新建同序号分镜不会被幽灵重连挂载
- [x] 4.2 运行代码静态检查与全套测试
- [x] 4.3 按照工程级规范执行 `./scripts/deploy_local.sh` 编译 Release 并部署本地应用
