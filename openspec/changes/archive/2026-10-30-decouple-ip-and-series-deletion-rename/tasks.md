## 1. 剧集卡片铅笔重命名交互 (Series Rename Interaction)

- [x] 1.1 在 `ProjectListPage` 的 `_SeriesCard` 标题旁新增重命名铅笔图标按钮（`Icons.edit_outlined`）及 `RenameSeriesDialog`
- [x] 1.2 实现重命名保存与会话联动：调用 `StudioProjectManager.saveSeries`，同步更新 `StudioSession` 并即时刷新卡片与顶栏标题

## 2. 剧集删除与 IP 资产保护分离机制 (Safe Series Deletion & Asset Preservation)

- [x] 2.1 在 `StudioProjectManager` 中实现剧集制作产物精准删除逻辑：仅物理清除 `episodes/` 目录下全部剧本、场次、分镜看板及音视频关键帧片段，严格保留 `characters/` 与 `common_scenes/` 目录
- [x] 2.2 更新 `ProjectListPage._confirmDelete` 对话框文案与选项，明确告知用户“剧本分镜与音视频渲染文件将彻底删除，IP 主库（角色卡、场景库）与全局资产库完好保留”

## 3. IP 主库常驻与独立管理 (Standalone IP Library)

- [x] 3.1 改造 `SeriesPage` 视图：在未选定剧集或剧集库为空时，展示 IP 资产库总览与常驻角色/场景卡列表，支持独立管理与查看
- [x] 3.2 优化新建剧集与已有 IP 资产的关联支持，确保已有角色与场景卡在新工程中可直接复用

## 4. 自动化测试与工程部署验证 (Verification & Local Deployment)

- [x] 4.1 编写单元与集成测试，覆盖剧集重命名、剧集删除时剧本分镜清除但角色与场景卡完好保留的断言
- [x] 4.2 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，端到端验证交互与资产安全性
