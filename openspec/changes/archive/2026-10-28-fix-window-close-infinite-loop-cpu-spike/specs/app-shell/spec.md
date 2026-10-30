## ADDED Requirements

### Requirement: 窗口关闭事件防重入与递归熔断

所有实现了 `WindowListener` 并在 `onWindowClose()` 回调中触发窗口销毁或二次关闭逻辑的界面组件，SHALL 实现状态自锁保护（例如 `_isClosing` 标志位），并在调用底层关闭命令前显式注销自身监听器（`windowManager.removeListener(this)`），MUST NOT 在 `onWindowClose()` 回调中无防护地直接调用 `windowManager.close()`。

#### Scenario: 确认关闭含有运行任务的工坊窗口
- **WHEN** 用户在有未完成小说解构任务时点击窗口关闭按钮，并在确认弹窗中选择「确认关闭并中断」
- **THEN** 系统先将关闭状态置为锁定，注销 `WindowListener`，解除 `preventClose`
- **AND** 随后调用底层关闭逻辑
- **AND** 关闭过程不会形成 Native ↔ Dart 间的二次 `close` 事件递归风暴，主线程 CPU 占用不得激增至 100%

### Requirement: 子窗口生命周期隔离

由 `desktop_multi_window` 创建的独立辅助子窗口（如查词浮窗 `lookupPanel` 等）在失焦关闭、点击关闭或隐藏时，SHALL 仅针对自身所属的子窗口实例执行关闭或隐藏操作（通过 `WindowController` 或特定子窗口通道），MUST NOT 调用作用于应用全局主窗口的 `windowManager.close()`。

#### Scenario: 查词浮窗失去焦点自动关闭
- **WHEN** 用户点击查词浮窗外部区域导致浮窗失焦
- **THEN** 查词浮窗通过子窗口实例或通道执行关闭/隐藏
- **AND** 主应用窗口的 `WindowListener` 监听器不会收到关闭事件，主应用生命周期与 CPU 占用保持平稳正常
