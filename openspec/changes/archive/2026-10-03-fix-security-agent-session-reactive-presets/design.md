## Context

参见 `proposal.md`。当前 `SecurityToolboxMainPage` 的主视图和 `SecurityAgentView` 未对 `SecuritySessionController` 注册监听，导致在顶部 `SessionBar` 切换会话时，Agent 面板没有触发重新构建，使得预设工作流中的点击回调持有了上个会话的 `target` 闭包。同时，`_taskController` 没有随会话进行草稿隔离与推荐任务自动填充。

## Goals / Non-Goals

**Goals:**
- 在 `SecurityToolboxMainPage` 中使用 `ListenableBuilder(listenable: _controller)` 包裹 `_buildActiveView()`，确保所有 Tab 视图在会话变更时能获得重绘。
- 在 `SecurityAgentView` 中响应会话切换：
  - 维护 `_lastSessionId` 追踪当前挂载的会话 ID。
  - 在会话切换时，自动将 `_taskController.text` 同步为该会话专属的草稿；若尚未有自定义草稿且会话包含有效目标，则默认自动填充推荐的一键任务描述（Web 为 `webOneClickTask`，LAN 为 `lanOneClickTask`）。
  - 用户修改文本输入框时实时写入对应会话的 `taskDraft`。
- 在“一键预设工作流”按钮的点击事件中，使用动态实时解析当前会话的第一目标，彻底杜绝任何陈旧闭包变量问题。

**Non-Goals:**
- 将未提交的 Agent 任务草稿持久化存储到 SQLite 数据库（维持应用生命周期内的内存隔离）。

## Decisions

### 1. 响应式驱动与视图重绘
- **决策**：
  - 在 `SecurityToolboxMainPage` 中，将 `Expanded(child: _buildActiveView())` 改造为 `Expanded(child: ListenableBuilder(listenable: _controller, builder: (_, __) => _buildActiveView()))`。
  - 在 `SecurityAgentView` 中，重载会话切换同步逻辑，结合 `ListenableBuilder` 监听 `widget.controller`。
- **替代方案考虑**：仅在 `SecurityAgentView` 里监听。
  - **放弃理由**：主视图 `_buildActiveView()` 在 `recon` Tab 下有 `_controller.current?.isLan == false ? WebReconView : LanReconView` 的动态派发逻辑，如果主视图不监听，切换 LAN/Web 会话时 Recon 视图类型无法自动切换。

### 2. 会话草稿模型与默认推荐任务自动填充
- **决策**：
  - 在 `SessionAgentData` 中增加 `String? taskDraft` 字段。
  - 提供辅助方法：根据 `session` 动态获取推荐预设任务文案（若无目标则为空）。
  - 当检测到会话切换（`currentSessionId != _lastSessionId`）时：
    - 读取目标会话的 `taskDraft`；
    - 若 `taskDraft` 为 null（未被用户主动编辑或清空），则自动填充该会话的推荐预设任务并赋给 `_taskController.text`；
    - 若 `taskDraft` 不为 null，则恢复该会话历史保存的文本内容；
    - 更新 `_lastSessionId`。
  - 给 `_taskController` 增加 `onChanged` 监听，用户主动编辑时将内容同步到当前会话的 `taskDraft`。

### 3. 点击按钮动态解析目标
- **决策**：
  - 在 `SmallActionButton` 的 `onPressed` 内，统一通过 `final activeTarget = widget.controller.current?.scope.firstOrNull ?? '';` 动态解析目标，再执行生成与 `_start`，双重保险消除闭包陈旧。

## Risks / Trade-offs

- **[Risk] 输入框光标被不必要的会话刷新重置** → **Mitigation**: 仅在 `sessionId` 真实发生变化时执行 `_taskController.text` 的赋值；同会话内的普通 `notifyListeners()` 不会重设文本内容。
