## 1. 资产数据模型与数据库性能优化

- [x] 1.1 在 `PentestAsset` 中引入 `_cachedMetadata` 缓存，消除单帧内重复的 `jsonDecode` 调用
- [x] 1.2 在 `SessionRepository.delete` 中废除串行单条 SQL 循环，改用单条批量条件更新与级联删除，实现毫秒级清理
- [x] 1.3 在 `SecuritySessionController.deleteSession` 中增加自动回退选择机制，删除后自动切换至下一个可用会话

## 2. 侦察视图分页渲染与状态隔离

- [x] 2.1 在 `WebReconView` 中实现资产切片分页渲染与 `AssetPaginationBar` 翻页控制栏（默认每页 50 条）
- [x] 2.2 在 `LanReconView` 中实现资产切片分页渲染与翻页控制栏
- [x] 2.3 在 `_buildActiveView` 中为 `WebReconView` 和 `LanReconView` 绑定 `ValueKey(_controller.current?.id)`，确保切换会话时输入框与状态完全独立重建

## 3. 会话管理与快捷删除交互

- [x] 3.1 在顶部 `_SessionSwitcher` 下拉菜单列表项中增加删除按钮与确认删除弹窗
- [x] 3.2 在顶部 `SessionBar` 当前会话信息旁增加快捷删除入口

## 4. 验证与本地部署

- [x] 4.1 编写单元测试并执行 `flutter analyze` 校验
- [x] 4.2 运行 `./scripts/deploy_local.sh` 编译并热更新本地 `/Applications/V8WorkToolbox.app`
