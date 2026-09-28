## Why

在多窗口架构中，当用户点击主界面的「密码工具」时，系统会拉起独立子窗口进程（`arguments: 'password-vault'`）。但在 `lib/main.dart` 的 `WindowServices.required` 中，`WindowKind.passwordVault` 被错误声明为 `const []`，导致子窗口启动时未执行 `AppPaths.init()`。当 `PasswordPage` 调用 `VaultStore.load()` 尝试读取加密密码库与元数据时，触达未初始化的 `AppPaths.root` 并直接抛出 `StateError: AppPaths 尚未初始化`，导致密码工具子窗口页面崩溃并显示「密码库加载失败」。

## What Changes

- **补齐密码工具子窗口的基础设施服务**：
  - 在 `lib/main.dart` 的 `WindowServices.required[WindowKind.passwordVault]` 中声明必需的基础设施 `..._appPaths`，确保独立子窗口启动时优先初始化本地存储路径源。
- **澄清子窗口服务清单的语义与测试断言**：
  - 更新 `test/window_service_initialization_test.dart` 中关于密码工具的测试用例：从历史的「不声明任何服务（`isEmpty`）」更新为「不声明 AI 与笔记业务服务（不消费 AI），但必须声明基础设施服务 `AppPaths`」。
- **补充密码工具独立子窗口启动回归测试**：
  - 验证子窗口调用 `WindowServices.initFor(WindowKind.passwordVault)` 后，`AppPaths.isInitialized` 变为 `true`，且 `VaultStore.load()` 能正常解析路径并完成加载。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `password-vault`: 明确密码工具在独立子窗口模式下的基础路径生命周期保障与加载可用性要求。

## Impact

- **涉及代码**：
  - `lib/main.dart`：在 `WindowServices.required` 中为 `WindowKind.passwordVault` 补充 `..._appPaths`。
  - `test/window_service_initialization_test.dart`：更新测试断言与覆盖子窗口服务清单完整性。
- **依赖与数据**：无新增依赖，不改变已存储密码库数据结构与格式。
