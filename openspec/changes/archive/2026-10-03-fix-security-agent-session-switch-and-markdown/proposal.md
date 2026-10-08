## Why

用户在安全工具箱中：
1. **Agent 综合分析与渗透建议中的 Markdown 未格式化**：`_buildFinalReport` 使用原生 `Text` 渲染报告，导致大模型生成的 Markdown 标题、加粗、列表、表格和代码块全部以纯文本字面量显示，排版混乱且缺乏代码高亮与层次感。
2. **多会话切换时 Agent 状态串扰且不切换**：`SecurityAgentService` 为全局单例且所有状态变量（`steps`、`currentTool`、`finalReport` 等）均为单变量无会话隔离，用户在顶栏切换不同会话（如由 `91porn.com` 切换到另一个会话）时，界面上的思考日志、当前进度与渗透建议不会随会话切换，导致历史数据串扰。

## What Changes

- **接入统一 Markdown 渲染组件**：
  - 将 `SecurityAgentView._buildFinalReport` 中的纯 `Text` 组件替换为共享的 `AppMarkdownView`，自动按当前主题渲染标题、粗体、列表、引用及代码块底色，并保持文本可划词复制与链接可跳转。
- **Agent 状态按会话级别隔离与联动切换**：
  - 在 `SecurityAgentService` 中建立以 `sessionId` 为键的会话状态缓存池（`SessionAgentState`），每个会话独立记录其 `steps`、`thinking`、`currentTool`、`finalReport` 与 `state`。
  - 提供 `switchSession(String? sessionId)` 方法，并与 `SecuritySessionController` 切换逻辑与 `SecurityAgentView` 生命周期联动；当切换会话时，自动切换至该会话对应的 Agent 状态流并驱动 UI 立即刷新。

## Capabilities

### New Capabilities
- `security/agent-session-state`: Security Agent 状态会话级隔离、会话切换联动与渗透报告 Markdown 结构化呈现。

### Modified Capabilities
<!-- 无已有 spec 变更 -->

## Impact

- `lib/tools/security_toolbox/ui/security_agent_view.dart`：接入 `AppMarkdownView`，并监听当前会话变更触发 Agent 视图重置/切换。
- `lib/tools/security_toolbox/services/security_agent_service.dart`：引入按 `sessionId` 分流存储的状态池与 `switchSession`。
- `lib/tools/security_toolbox/services/security_session_controller.dart`：在选择会话（`selectSession`）或删除会话时同步通知 Agent 切换/清理。
