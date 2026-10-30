## Context

实时会议翻译的字幕悬浮窗基于 `desktop_multi_window` 实现独立置顶渲染，通过 `LiveCaptionBridge`（`WindowMethodChannel` 双向模式）接收主进程的实时字幕流。
在实操测试中暴露了三个层面的技术矛盾：
1. **渲染层**：macOS `NSWindow` 默认 `isOpaque = true`，使 Flutter 的半透明黑色背景被强制绘制在实色黑底上，导致悬浮窗全黑且不透明；
2. **生命周期与 IPC 层**：子窗口调用 `windowManager.close()` 销毁了 NSWindow，但原生注册表未及时注销；再次 `WindowController.create` 时触发 `CHANNEL_LIMIT_REACHED` 异常中断了窗口样式初始化与字幕推送；
3. **事件驱动层**：原生 Carbon 热键通道与多窗口 IPC 通道共用 `'v8_work_toolbox/live_caption'` 名称导致路由冲突，且在 Dart `main()` 启动时注册存在时序竞态，导致注册静默失败。

## Goals / Non-Goals

**Goals:**
- 在 `AppDelegate.swift` 中为字幕悬浮窗实现 `styleLiveCaptionWindow` 原生样式配置（`isOpaque = false`、`backgroundColor = .clear`、隐藏标准交通灯按钮）。
- 在悬浮窗工具栏增加背景透明度（35%、50%、70%、90%）快捷切换按钮，并在本地存储中持久化。
- 将字幕悬浮窗的关闭语义收敛为非破坏性的 `windowManager.hide()`，主窗口重新打开时复用已有窗口 `show()`，彻底杜绝 IPC 配对破坏与变形异常。
- 将全局热键通道重命名为独立的 `'v8_work_toolbox/live_caption_hotkeys'`，并在原生 `applicationDidFinishLaunching` 中直连注册 Carbon 热键。
- 支持说话人切换即时生效于当前在途未定稿字幕段，并在悬浮窗字幕流中增加彩色说话人胶囊标签。

**Non-Goals:**
- 不重构 `desktop_multi_window` 底层插件源码。
- 不修改既有主窗口内嵌字幕流的显示逻辑。

## Decisions

### D1: 原生层显式注入真透明与隐藏标准控制键
- **决策**:
  - 在 `AppDelegate.swift` 中新增 `configureLiveCaptionWindow()`，匹配字幕子窗口并执行：
    ```swift
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .floating
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    ```
  - 通过 `ContextServicesBridge.instance.styleLiveCaptionWindow()` 暴露给 Flutter 侧在 `LiveCaptionWindowApp._initWindow()` 中调用。
- **备选方案**:
  - 仅在 Flutter 侧调用 `windowManager.setBackgroundColor(Colors.transparent)`：不可行，`window_manager` 在 macOS 上未设置 `isOpaque = false`，窗口服务器依然合成黑底。

### D2: 悬浮窗生命周期收敛为 hide / show 驻留模式
- **决策**:
  - 用户在悬浮窗点击“关闭（停止识别）”或“隐藏（继续识别）”按钮时，统一调用 `windowManager.hide()`；对于“关闭”，额外通知主进程 `coordinator.stop()`。
  - `LiveTranslatorHost.openCaptionWindow` 优先检查已存在的窗口控制器：若已创建则直接 `await _captionWindow?.show(); await _captionWindow?.focus();`；只有在应用冷启动首次打开时才调用 `WindowController.create`。
  - 在 `LiveCaptionWindowApp._initWindow` 中，将窗口尺寸与最小尺寸设置提到方法最前端，确保不受后续异步通信状态影响。
- **备选方案**:
  - 每次关闭彻底杀死进程：不可行，`desktop_multi_window` 双向通道在子窗口被杀死后无法安全注销旧配对，导致二次创建必抛 `CHANNEL_LIMIT_REACHED`。

### D3: 全局热键专用通道隔离与原生启动直连注册
- **决策**:
  - 将热键通信通道从 `'v8_work_toolbox/live_caption'` 迁移为独立的 `'v8_work_toolbox/live_caption_hotkeys'`，解除与跨窗口桥的命名冲突。
  - 在 `AppDelegate.swift` 的 `applicationDidFinishLaunching` 中原生直接调用 `registerLiveCaptionHotKeys()`（与 `registerContextHotKeys` 模式一致），彻底消除与 Flutter 异步 `main()` 的启动时序竞态。
- **备选方案**:
  - 继续由 Flutter 异步请求原生注册：存在时序竞态，一旦失败静默吞异常，用户热键失灵。

### D4: 说话人切换即时生效与视觉标签展示
- **决策**:
  - 在 `LiveTranslatorCoordinator.setActiveSpeaker(index)` 中：不仅更新 `_state.speaker.setActive(index)`，若当前最新的字幕段仍处于未定稿识别中（`!seg.isFinal`），同步将该段的 `speakerSlot` 更新为最新选中的槽位。
  - 在 `LiveCaptionWindowApp` 的字幕列表中，在每行原文前渲染当前说话人胶囊标签（如 `[说话人 1]`），颜色对应红/蓝/绿槽位，直观反馈说话人切换效果。

## Risks / Trade-offs

- **[Risk]** 悬浮窗采用驻留隐藏模式是否会占用过多系统内存？
  → **Mitigation**: 悬浮窗为极简纯视图，无独立重型数据结构，驻留内存不到 15MB；与避免每次创建重跑 Flutter 引擎所耗费的 CPU 与 1 秒延迟相比，驻留隐藏模式体验和稳定性大幅优于反复销毁创建。
