## Context

参见 `proposal.md - Why`。本项目各独立子窗口通过 `WindowServices.initFor(WindowKind)` 完成进程启动时的服务初始化。`AppPaths` 作为底层统一数据目录，是 `VaultStore` 读取元数据与加密密钥文件的基础依赖。

## Goals / Non-Goals

**Goals:**
- 在 `WindowServices.required[WindowKind.passwordVault]` 中补齐 `..._appPaths`。
- 更新 `test/window_service_initialization_test.dart` 中的历史测试断言，消除「不声明任何服务」的过时断言。
- 增加密码工具独立子窗口初始化链路的回归测试，确保 `VaultStore.load()` 在子窗口模式下可正常运行。

**Non-Goals:**
- 不为密码工具子窗口引入任何非必需的业务服务（如 `AiConfigStore`、`ProxySettings`、`NoteStore` 等）。
- 不调整密码工具原有的加密存储算法或界面布局。

## Decisions

### 1. 窗口必需服务清单最小集
- **决策**：`WindowKind.passwordVault` 仅声明 `..._appPaths`。
- **理由**：密码工具完全是本地离线加密存储，不消费 AI（无需 `AiConfigStore` / `ProxySettings`），也不访问笔记数据库（无需 `NoteStore`）。引入 `_appPaths` 即可满足 `VaultStore`、`VaultFileStore` 与 `KekManager` 对 `AppPaths.root` 的解析需求，保持子窗口最小化开销。

### 2. 测试语义更新
- **决策**：将原有测试用例 `test('密码工具子窗口不声明 AI 服务（本地密码库不消费 AI）')` 的 `expect(..., isEmpty)` 更新为：
  ```dart
  final names = WindowServices.requiredNames(WindowKind.passwordVault);
  expect(names, ['AppPaths']);
  expect(names, isNot(contains('AiConfigStore')));
  expect(names, isNot(contains('NoteStore')));
  ```
- **理由**：准确表达「不声明 AI 业务服务，但具备基础路径设施」的架构约束，避免误导后续维护者。

## Risks / Trade-offs

- **[Risk]** 测试环境未运行真实 `main()` 导致单测受影响。
  - **Mitigation**: 测试中继续保持注入钩子（`overrideRootForTesting`），`AppPaths.init()` 在真实运行时解析路径，在测试时支持安全覆写。
