## ADDED Requirements

### Requirement: 窗口拖拽仅限专用拖拽区，不得使用全局背景拖拽

应用主窗口及所有子窗口 MUST NOT 启用 `isMovableByWindowBackground`（macOS NSWindow 全局背景拖拽）。窗口拖动 SHALL 仅由 ActivityBar 顶部的专用 `DragToMoveArea` widget（38px 高）响应用户的 pan/drag 手势，通过 `windowManager.startDragging()` 委托给系统执行窗口移动。

全局启用 `isMovableByWindowBackground` 会导致 NSWindow 在收到任何落在 FlutterView 上的 mouseDown 时，不将事件传入 Flutter 事件系统，从而使 showDialog / showModalBottomSheet 等模态层内的所有可交互控件（按钮、IconButton、InkWell）点击失效。

#### Scenario: 用户在 ActivityBar 顶部区域拖动窗口

- **WHEN** 用户在 ActivityBar 顶部 38px 的专用拖拽区按下并拖动鼠标
- **THEN** 窗口随鼠标移动，松开后停在新位置

#### Scenario: 模态对话框内的按钮可正常点击

- **WHEN** 任意 showDialog 或 showModalBottomSheet 弹出的模态层处于前台
- **THEN** 该层内的所有按钮（包括右上角关闭按钮、图标按钮、FilledButton）的 onPressed/onTap SHALL 被正常触发，不得被 NSWindow 原生事件截获

#### Scenario: ActivityBar 顶部区域之外不可拖动

- **WHEN** 用户在 ActivityBar 顶部拖拽区以外的区域（如内容区、工具面板、弹窗内）按下并拖动鼠标
- **THEN** 窗口 MUST NOT 被拖动，鼠标事件正常传递给 Flutter widget 处理
