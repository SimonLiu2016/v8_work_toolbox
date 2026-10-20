## MODIFIED Requirements

### Requirement: Window visibility follows engine readiness
独立子窗口 SHALL 在承载它的引擎完成首帧绘制并交付后才变为可见。窗口的首次可见 MUST 发生在首帧回调触发之后，而非 `runApp` 之前。

#### Scenario: Sub-window opens after the first frame is delivered
- **WHEN** 用户点击一个 `openInNewWindow` 为真的工具入口
- **THEN** 该子窗口保持不可见，直到其引擎完成首帧绘制后才首次可见
- **AND** 窗口首次可见时已包含渲染好的内容，不出现先黑屏后出内容的中间态

#### Scenario: Window becomes visible even when the engine fails to start
- **WHEN** 子窗口的引擎首帧未能在约定时间内交付（初始化异常或超时）
- **THEN** 窗口仍然变为可见，使用户不会遇到「点了没反应」
- **AND** 该次降级可见留下可诊断的信号（日志或状态标记），而非静默发生

## REMOVED Requirements

### Requirement: Visible window has a non-black fallback surface
**Reason**: NSWindow 背景色被 Flutter view 的不透明层完全覆盖，该兜底机制从未生效。保留只会误导后续维护者以为存在一道防线。
**Migration**: 无需迁移。窗口在首帧前保持隐藏（见 `window-first-frame-visibility`），不存在需要兜底的可见窗口。
