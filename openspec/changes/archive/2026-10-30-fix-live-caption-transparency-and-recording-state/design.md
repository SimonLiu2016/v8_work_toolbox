## Context

当前实时会议翻译浮窗分为主进程宿主（`LiveTranslatorHost`）与多窗口子进程（`LiveCaptionWindowApp`）。原生通道 `v8_work_toolbox/context_services` 仅挂载在主 Flutter 引擎，子进程调用会报 `MissingPluginException`，使得原生样式配置必须由主窗口进程发起。同时，macOS 窗口合成器支持通过 `windowManager.setOpacity` 直接调整整个窗口的 `alphaValue`，结合原生窗口无死黑背景可实现立竿见影的半透明效果。

## Goals / Non-Goals

**Goals:**
- 确保浮窗在打开时由主进程正确触发原生 `styleLiveCaptionWindow()`，消除底层实心黑底；
- 在浮窗切换透明度时，通过 `windowManager.setOpacity(_opacity)` 实现系统级真实透明与视觉穿透；
- 浮窗工具栏录制按钮完整消费并展示 `isRecording` 状态，提供明显的录制中与闲置状态差异。

**Non-Goals:**
- 重新设计录制与导出的底层数据协议或分段逻辑；
- 修改主界面的 ASR 语音识别与翻译管线。

## Decisions

### 1. 原生样式配置发起点移交至主窗口宿主进程
- **决策**：在 `LiveTranslatorHost.openCaptionWindow` 中，无论新建窗口还是复用隐藏窗口，均调用 `await ContextServicesBridge.instance.styleLiveCaptionWindow()`。
- **替代方案**：在子窗口也注册一套完整的 `contextServicesChannel`。代价高且多余，主进程已有现成通道且控制窗口生命周期。

### 2. 窗口级 `setOpacity` 与容器背景色双重联动
- **决策**：在 `LiveCaptionWindowApp._cycleOpacity` 和 `_loadConfig` 中，除了 `setState(() => _opacity = next)` 改变容器背景外，追加 `await windowManager.setOpacity(_opacity)`。
- **理由**：直接调动 macOS WindowServer 的混合通道，实现真正穿透桌面的半透明效果。

### 3. 工具栏录制按钮状态感知与图标切换
- **决策**：
  - 在 `_LiveCaptionWindowAppState` 中维护 `bool _isRecording = false`；
  - `_applyState` 提取 `map['isRecording'] as bool? ?? false`；
  - `_isRecording == true` 时渲染 `Icon(Icons.stop_circle, size: 16, color: Colors.redAccent)`，tooltip 为 `'正在记录（点击停止）'`；
  - `_isRecording == false` 时渲染 `Icon(Icons.fiber_manual_record, size: 15, color: Colors.white70)`，tooltip 为 `'开始记录'`。

## Risks / Trade-offs

- **[Risk]** 在较旧的 macOS 系统上，极低透明度（如 35%）可能导致文字可读性降低。
  - **缓解**：保留文字高对比度纯白及黄色译文，并保留字号调节快捷按钮，用户可按需选择 50% 或 70% 舒适档位。
