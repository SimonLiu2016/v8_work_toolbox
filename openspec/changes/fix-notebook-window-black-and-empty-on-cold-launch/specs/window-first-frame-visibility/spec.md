## Purpose

定义独立子窗口从用户点击到首帧交付的可见时机契约：窗口 MUST 在引擎首帧画出之后才可见，而非在 `runApp` 之前。这取代旧契约中「服务初始化完成后 show」的语义——`runApp` 之前 show 仍会露出 Flutter view 的不透明黑 surface。

## ADDED Requirements

### Requirement: Window becomes visible only after the first frame is drawn
独立子窗口 SHALL 在承载它的引擎完成首帧绘制之后才变为可见。窗口在首帧交付前 MUST 保持隐藏，不得在 `runApp` 之前或引擎启动过程中提前显示。

#### Scenario: Window appears with content already rendered
- **WHEN** 用户点击一个 `openInNewWindow` 为真的工具入口
- **THEN** 该子窗口保持不可见，直到其引擎完成首帧绘制后才首次可见
- **AND** 窗口首次出现时已包含渲染好的内容，不出现黑屏、空白或加载中的中间态

#### Scenario: Window never shows a black surface during startup
- **WHEN** 子窗口的引擎正在执行启动链（服务初始化、尺寸声明、首帧构建）
- **THEN** 窗口表面对用户不可见
- **AND** 不出现全黑窗口或透明窗口裸露在桌面上的情况

#### Scenario: Window becomes visible even when the first frame is delayed
- **WHEN** 子窗口的引擎首帧未能在约定时间内交付（构建异常或超时）
- **THEN** 窗口仍然变为可见，使用户不会遇到「点了没反应」
- **AND** 该次降级可见留下可诊断的信号（日志或状态标记），而非静默发生
