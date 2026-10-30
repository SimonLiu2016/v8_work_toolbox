## Context

详细背景与动机见 `proposal.md`。

在 macOS 上，`window_manager` 原生插件将 `windowManager.close()` 映射为 `mainWindow.performClose(nil)`。在 AppKit 事件响应体系中，`performClose` 模拟红叉点击并同步调用窗口代理的 `windowShouldClose(_:)`。`window_manager` 插件在此方法中无条件广播 Platform Channel 事件 `"close"`，Dart 层的 `WindowListener.onWindowClose()` 被触发。

若在 `onWindowClose()` 回调中再次执行 `await windowManager.close()` 且未解绑监听器或缺少自锁标志，将立刻诱发 Dart ↔ Native 间的无限级联递归，每秒数百次 IPC 调度瞬间吃满单核 CPU（100%+）。此外，辅助子窗口（如查词浮窗）直接调用全局单例的 `windowManager.close()` 会将关闭意图广播至主窗口，扩大死循环触发面。

## Goals / Non-Goals

**Goals:**
- 在 `StudioShellPage` 中引入严密的状态自锁 (`_isClosing`) 与监听器注销机制，彻底阻断递归事件风暴。
- 区分多窗口生命周期：查词浮窗 (`LookupPanelView`) 的失焦与关闭仅作用于子窗口本身，杜绝调用作用于全局 `mainWindow` 的 `windowManager.close()`。
- 终止当前运行中的僵尸进程 PID 20415，恢复系统正常能耗。

**Non-Goals:**
- 不重构 `window_manager` 第三方 Pod 原生源码（依赖官方 package，通过应用层规范规避缺陷）。
- 不改变各工具窗口既有的业务功能逻辑与交互形态。

## Decisions

### 1. `StudioShellPage` 窗口关闭防重入协议 (Re-entrancy Guard)
- **方案**：
  在 `_StudioShellPageState` 中添加 `bool _isClosing = false;`：
  ```dart
  @override
  void onWindowClose() async {
    if (_isClosing) return;
    final running = NovelImportTaskService.instance.runningCount;
    if (running > 0 && mounted) {
      final shouldClose = await showDialog<bool>(...);
      if (shouldClose != true) return;
    }
    _isClosing = true;
    try {
      // 1. 立即解除监听，确保后续任何系统事件不会再次进入本回调
      windowManager.removeListener(this);
      // 2. 解除原生拦截
      await windowManager.setPreventClose(false);
      // 3. 执行系统级关闭
      await windowManager.close();
    } catch (_) {}
  }
  ```
- **备选方案**：
  - *仅解除 setPreventClose(false)*：不可行，`window_manager` 在 `windowShouldClose` 中无论 `isPreventClose` 是否为 false，都会触发 `_emitEvent("close")`，因此必须显式 `removeListener`。

### 2. `LookupWindow` 子窗口失焦与关闭隔离
- **方案**：
  `LookupPanelView` 中的 `onWindowBlur()` 和 `_onClose()` 仅在 `widget.isSubWindow` 为 true 时生效。通过 `WindowController.fromWindowId(windowId).close()` 或隐藏子窗口，严禁调用全局单例 `windowManager.close()`。对于桌面浮窗，失焦即关闭可直接通过 `WindowController` 优雅退出或隐藏。

## Risks / Trade-offs

- **[Risk] 用户在确认关闭弹窗展示期间重复点击红叉**
  → **Mitigation**: 弹窗未返回前 `_isClosing` 保持为 false，弹窗采用 `barrierDismissible: false`，确认后立即设为 `_isClosing = true` 并注销监听，杜绝并发调用。
- **[Risk] 子窗口销毁未清理 MultiWindowManager**
  → **Mitigation**: 走 `desktop_multi_window` 原生受支持的控制器关闭通道，原生 `FlutterWindow` 会监听 `NSWindow.willCloseNotification` 自动清理实例。
