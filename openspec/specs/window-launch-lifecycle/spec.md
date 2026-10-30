# window-launch-lifecycle Specification

## Purpose
定义独立子窗口从用户点击到首帧交付的生命周期契约：窗口不得在引擎就绪前以错误尺寸可见，可见期间必须有非黑兜底，尺寸按当前屏幕可见工作区计算。适用于所有走独立窗口入口的工具。
## Requirements
### Requirement: Window visibility follows engine readiness
独立子窗口 SHALL 在承载它的引擎完成服务初始化并具备渲染首帧条件之前保持不可见；窗口的首次可见 MUST 发生在尺寸与位置已声明之后。

#### Scenario: Sub-window opens after services are ready
- **WHEN** 用户点击一个 `openInNewWindow` 为真的工具入口
- **THEN** 该子窗口保持不可见，直到其引擎完成启动链并声明完尺寸与位置后才首次可见
- **AND** 窗口首次可见时即为最终尺寸与位置，不出现先小窗后放大、先边角后居中的位移

#### Scenario: Window becomes visible even when the engine fails to start
- **WHEN** 子窗口的引擎启动链未能在约定时间内完成（初始化异常或超时）
- **THEN** 窗口仍然变为可见，使用户不会遇到「点了没反应」
- **AND** 该次降级可见留下可诊断的信号（日志或状态标记），而非静默发生

### Requirement: Visible window has a non-black fallback surface
独立子窗口在引擎尚未绘制任何内容时 MUST 呈现一个不透明的非黑表面，而不是透明或纯黑。

#### Scenario: Window visible before first frame is drawn
- **WHEN** 子窗口已可见但其引擎尚未完成首帧绘制
- **THEN** 窗口表面呈现应用定义的非黑背景色（随当前主题的浅色/深色而定）
- **AND** 不出现全黑窗口

#### Scenario: Dark theme applies to the fallback surface
- **WHEN** 用户的主题偏好为深色且子窗口在首帧前可见
- **THEN** 兜底表面为深色而非黑色，与首帧后的窗口背景一致

### Requirement: Window size derives from the screen visible work area
独立子窗口的初始尺寸 SHALL 依据当前屏幕的可见工作区（排除菜单栏与 Dock）计算，不得使用硬编码的固定像素尺寸充当「接近全屏」的默认值。

#### Scenario: Window opens near full screen
- **WHEN** 用户在一个 1680×1050 逻辑分辨率的屏幕上打开一个内容密集的独立子窗口
- **THEN** 该窗口初始尺寸铺满该屏幕的可见工作区，而非占屏幕面积不足一半的固定尺寸

#### Scenario: Window fits a smaller display
- **WHEN** 用户在一个可见工作区小于该窗口默认尺寸的屏幕上打开独立子窗口
- **THEN** 窗口初始尺寸不超过该屏幕的可见工作区，不出现超出屏幕边界而无法操作的部分

#### Scenario: Size declaration happens before the window is shown
- **WHEN** 子窗口的启动链执行尺寸声明
- **THEN** 尺寸声明发生在服务初始化之前，使窗口首次可见时即具备正确尺寸

### Requirement: Window initialization does not load unused subsystems
独立子窗口的启动链 SHALL 只加载该窗口类型实际需要的子系统；与窗口功能无关的重量级原生库 MUST NOT 在其启动链上无条件加载。

#### Scenario: Notebook window does not load the media runtime
- **WHEN** 用户打开笔记本独立窗口
- **THEN** 启动链不加载多媒体播放运行时（该窗口无任何播放功能）
- **AND** 首帧交付前的启动链工作量因此减少

#### Scenario: Media-capable window still loads the media runtime
- **WHEN** 用户打开具备视频播放功能的独立窗口
- **THEN** 该窗口的启动链照常加载多媒体播放运行时，播放功能不受影响

### Requirement: Repeated window opens do not repeat one-shot work
独立子窗口的启动链 MUST NOT 在每次打开时重复执行无进展的一次性工作；已被确认无法完成的一次性迁移 MUST 留下完成标记并跳过。

#### Scenario: Backfill that cannot make progress is not retried every open
- **WHEN** 某笔记本的层级组回填已尝试过且确认无法从本机印象笔记库取得对应值
- **THEN** 该笔记本被标记为已处理，后续打开笔记本窗口时不再为它启动外部数据库查询进程
- **AND** 已成功回填的笔记本行为不变

#### Scenario: Data normalization runs only when there is work
- **WHEN** 笔记数据库中没有文本形式的时间戳行需要归一化
- **THEN** 启动链跳过归一化更新，不对相关表执行全表 UPDATE

