## Context

在之前的实现中：
1. `SecurityAgentService` 维护的 `steps`、`thinking`、`currentTool`、`finalReport` 均为单例顶层变量，导致在应用中切换会话后，Agent 思考日志与建议依然停留在上一个会话。
2. `SecurityAgentView._buildFinalReport` 使用 `Text(report)` 进行渲染，大模型输出的 Markdown 标题、强调、列表、代码块未被格式化解析。

## Goals / Non-Goals

**Goals:**
- 在 `SecurityAgentService` 中建立以 `sessionId` 为隔离维度的状态字典 `Map<String, SessionAgentData>`。
- 支持 `switchSession(String? sessionId)`，切换时自动切换当前活跃的数据切片并向 Stream 触发广播，使 UI 即时呈现当前会话的 Agent 历史或空状态。
- 在 `SecurityAgentView` 监听 `controller` 的当前会话变化（或 `didUpdateWidget`），自动触发 `switchSession`。
- 将 `_buildFinalReport` 中的 `Text` 替换为项目共享组件 `AppMarkdownView`。

**Non-Goals:**
- 不向 SQLite 数据库增加额外的 agent_steps 独立表（保持与现有会话时间线事件、临时状态机制一致；若需持久化，时间线中已有关键工具记录）。

## Decisions

### 1. `SessionAgentData` 会话级状态聚合
定义类：
```dart
class SessionAgentData {
  AgentRunState state;
  final List<AgentStep> steps;
  final List<String> thinking;
  String? currentTool;
  String? finalReport;
  String? lastError;

  SessionAgentData({
    this.state = AgentRunState.idle,
    List<AgentStep>? steps,
    List<String>? thinking,
    this.currentTool,
    this.finalReport,
    this.lastError,
  }) : steps = steps ?? [], thinking = thinking ?? [];
}
```
并在 `SecurityAgentService` 中管理 `_sessionData[sessionId]`，当切换会话时，若不存在则初始化空状态；若切换到同一会话则无缝保留。

### 2. 切换联动与监听
- 在 `SecurityAgentView` 的 `didUpdateWidget` 中比对 `widget.controller.current?.id != oldWidget.controller.current?.id`。
- 并在 `SecurityAgentView.initState` 中根据 `widget.controller.current?.id` 调用 `SecurityAgentService.instance.switchSession(id)`。
- 在 `SecuritySessionController.deleteSession` 时顺带清理对应 session 的 agent 状态缓存。

### 3. Markdown 渲染
- 在 `SecurityAgentView` 中引入 `import '../../../components/markdown_view.dart';`。
- 将 `Text(report, ...)` 替换为：
  ```dart
  AppMarkdownView(
    data: report,
    selectable: true,
  )
  ```
  自动获得暗黑/明亮主题自适应、行内与块状代码美化、可划词复制支持。

## Risks / Trade-offs

- **[Risk]** 内存中保存各会话的 steps 和 finalReport。
  - **Mitigation**: steps 和 finalReport 文本量都在数十 KB 级别，内存开销极小且应用退出后自动清理。
