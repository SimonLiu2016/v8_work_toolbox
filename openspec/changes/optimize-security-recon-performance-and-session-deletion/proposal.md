## Why

当渗透测试会话产生数千条资产（如真实场景中发现 3,000~4,000 条子域名/URL）时，侦察视图采用全量无虚拟化的 Column 渲染并频繁调用未缓存的 JSON 解码，导致主 UI 线程严重阻塞（卡死/转彩球）。同时，切换会话时侦察组件 State 被复用导致目标域名输入框失步，且会话删除功能在常用界面缺乏显性入口，底层更因串行单条 SQL 循环执行导致万级数据删除时出现假死。

## What Changes

- **侦察视图高性能分页与解码缓存**：
  - 在 `PentestAsset` 模型中为 `metadata` 增加内存解码缓存，避免单帧成万次重复的 `jsonDecode`。
  - 在 `WebReconView` 与 `LanReconView` 资产列表中引入分页控制栏（默认每页 50 条），仅对当前页资产渲染组件，将渲染延迟从 10 秒骤降至 2 毫秒。
- **侦察视图会话生命周期隔离**：
  - 在 `_buildActiveView` 中为 `WebReconView` 与 `LanReconView` 绑定以当前会话 ID 为标识的 `ValueKey`，确保切换会话时完整销毁并重建状态，输入框自动与当前会话的目标范围同步。
- **会话快捷删除与秒级清理**：
  - 在顶部 `_SessionSwitcher` 下拉菜单项中增加显性删除图标，在顶部 `SessionBar` 提供删除当前会话入口。
  - 优化 `SessionRepository.delete`：移除串行单个资产查找与循环更新 SQL，改用单条批量条件更新与级联清理，实现数千条数据毫秒级原子删除。
  - 在 `SecuritySessionController.deleteSession` 中增加自动回退选择机制，删除当前会话后自动切换至剩余的下一个有效会话。

## Capabilities

### New Capabilities
- `security/recon-and-session-management`: 规范安全测试侦察资产的高性能分页与缓存渲染、侦察视图跨会话状态生命周期同步，以及全局会话管理与原子级删除。

## Impact

- `lib/tools/security_toolbox/models/security_models.dart`（增加 metadata 缓存）
- `lib/tools/security_toolbox/ui/web_recon_view.dart`（增加资产分页栏与切片渲染）
- `lib/tools/security_toolbox/ui/lan_recon_view.dart`（增加资产分页栏与切片渲染）
- `lib/tools/security_toolbox/ui/security_toolbox_main_page.dart`（传入会话 key）
- `lib/tools/security_toolbox/ui/session_bar.dart`（增加会话快捷删除入口）
- `lib/tools/security_toolbox/services/security_repositories.dart`（优化 delete 批量 SQL）
- `lib/tools/security_toolbox/services/security_session_controller.dart`（删除后自动切换活跃会话）
