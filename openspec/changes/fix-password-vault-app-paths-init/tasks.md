## 1. 窗口服务清单补齐

- [x] 1.1 在 `lib/main.dart` 的 `WindowServices.required[WindowKind.passwordVault]` 中声明 `..._appPaths`
- [x] 1.2 保持密码工具子窗口服务清单轻量，确认不引入 `AiConfigStore`、`ProxySettings` 与 `NoteStore`

## 2. 自动化测试与断言更新

- [x] 2.1 更新 `test/window_service_initialization_test.dart` 中密码工具子窗口的测试断言，确保声明 `AppPaths` 且不包含 AI 服务
- [x] 2.2 增加子窗口模式下调用 `WindowServices.initFor(WindowKind.passwordVault)` 后的 `AppPaths.isInitialized` 与 `VaultStore.load()` 路径可用性回归测试
