## ADDED Requirements

### Requirement: 密码工具独立子窗口基础设施就绪保障

系统 SHALL 在启动密码工具独立子窗口（`arguments: 'password-vault'`）时，在执行任何密码库数据操作之前，优先完成 `AppPaths` 基础存储路径服务的初始化，保障 `VaultStore` 加载时能够正确获取应用数据目录。

#### Scenario: 独立子窗口成功加载密码库
- **WHEN** 用户在主界面点击打开「密码工具」以独立子窗口呈现
- **THEN** 子窗口进程在渲染页面前成功完成 `AppPaths` 初始化
- **AND** `VaultStore.load()` 正常读取本地密码元数据与密文文件，页面不抛出 `StateError: AppPaths 尚未初始化` 异常且不展示「密码库加载失败」错误画面

#### Scenario: 密码工具子窗口服务清单最小化约束
- **WHEN** 检查密码工具子窗口声明的必需服务清单
- **THEN** 系统 MUST 包含 `AppPaths` 基础路径服务
- **AND** 系统 MUST NOT 包含与本地密码库无关的 AI 平台配置（`AiConfigStore`）与笔记主库服务（`NoteStore`）
