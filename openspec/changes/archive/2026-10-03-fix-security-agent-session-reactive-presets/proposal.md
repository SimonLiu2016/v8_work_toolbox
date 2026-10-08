## Why

在多会话切换场景下，主界面和 Agent 面板缺少对 `SecuritySessionController` 的响应式监听，导致 `SecurityAgentView` 内部保留上一个会话的闭包目标（例如切换到 `91` 会话后点击预设仍填入 `baidu.com` 的任务）。同时，当前任务输入框未按会话进行草稿隔离与默认预设填充。修复此问题可保证多会话切换时目标即时同步，并默认提供会话专属的推荐预设任务。

## What Changes

- 在主页面 `SecurityToolboxMainPage` 与 `SecurityAgentView` 中引入响应式监听（`ListenableBuilder`），当会话切换或更新时，即时重绘当前活跃视图与预设工作流按钮。
- 在 `SessionAgentData` 中引入会话专属的任务草稿管理（`taskDraft`），并支持默认自动填充该会话的推荐预设任务（Web 域名自动生成 `webOneClickTask`，LAN 网段自动生成 `lanOneClickTask`）。
- 切换会话时，`_taskController` 自动同步为当前会话的任务草稿（未手动编辑时呈现会话推荐任务），消除跨会话目标串扰。
- 在预设按钮点击事件中，使用动态解析机制获取当前会话目标，避免任何闭包捕获陈旧目标。

## Capabilities

### Modified Capabilities
- `security/agent-session-state`: 增加 Agent 渗透目标输入框的会话草稿隔离、动态预设解析，以及默认自动填充推荐预设任务的行为规范。

## Impact

- 涉及 `lib/tools/security_toolbox/ui/security_toolbox_main_page.dart`
- 涉及 `lib/tools/security_toolbox/ui/security_agent_view.dart`
- 涉及 `lib/tools/security_toolbox/services/security_agent_service.dart`
- 增加与修改相关单测 `test/security_gaps_test.dart`
