# live-caption-overlay Specification

## Purpose
定义实时会议翻译工具的常驻悬浮字幕窗契约：透明置顶可拖动的窗口形态、字号调节、多说话人角色配色与手动切换、字幕滚动与清空、以及开关入口，使双语字幕能在不打扰工作的前提下持续可读。
## Requirements
### Requirement: 常驻透明悬浮字幕窗

字幕 SHALL 呈现在一个常驻的独立悬浮窗口中，该窗口 SHALL 背景透明、无边框、置顶于其它窗口之上，且 MUST NOT 抢夺当前焦点。悬浮窗 SHALL 可被用户拖动改变位置。

#### Scenario: 悬浮窗置顶且可拖动

- **WHEN** 实时字幕开启且用户在任意应用中工作
- **THEN** 字幕窗浮在应用之上，用户可拖动它到屏幕任意位置，且拖动不抢走当前输入焦点

### Requirement: 字号调节

系统 SHALL 允许用户调节字幕字号，调节 SHALL 立即作用于当前与后续字幕，MUST NOT 需要重启工具生效。

#### Scenario: 实时调整字号

- **WHEN** 用户增大了字幕字号
- **THEN** 悬浮窗中现有与新到的字幕立即以更大字号呈现

### Requirement: 多说话人与角色配色

系统 SHALL 支持多个说话人，每个说话人 SHALL 分配一个可区分的颜色，其字幕 SHALL 以该颜色呈现说话人标识，使不同角色的字幕可被一眼区分。

系统 SHALL 通过全局热键让用户手动切换当前说话人（至少支持 3 个说话人槽位），当前说话人 SHALL 在界面上可见。

#### Scenario: 手动切换说话人并显示对应颜色

- **WHEN** 会议中说话人从 A 换到 B，用户按下切换到说话人 2 的热键
- **THEN** 此后定稿的字幕标记为说话人 2 并以说话人 2 的颜色显示，与说话人 1 明显区分

### Requirement: 字幕滚动、保留与清空

悬浮窗 SHALL 滚动显示最近的字幕，保留最近若干条历史字幕供阅读，超过保留数量的旧字幕 SHALL 滚出视野。系统 SHALL 提供一键清空当前字幕的操作。

#### Scenario: 清空字幕

- **WHEN** 用户点击清空
- **THEN** 悬浮窗中当前显示的字幕被移除，后续新字幕正常显示

### Requirement: 字幕开关与菜单栏入口

系统 SHALL 提供菜单栏入口与全局热键来开启/关闭实时字幕。关闭字幕 SHALL 停止识别与捕获，但 MUST NOT 关闭已记录且未导出的字幕数据（数据保留到用户显式导出或清空）。

#### Scenario: 通过菜单栏关闭字幕

- **WHEN** 用户在菜单栏关闭实时字幕
- **THEN** 识别与音频捕获停止，悬浮窗隐藏，而已记录的字幕数据仍可用于导出

### Requirement: Native Floating Window Transparency and Window Opacity Driving
The live caption overlay system SHALL ensure the native macOS floating window is non-opaque (`isOpaque = false`, `backgroundColor = NSColor.clear`) upon being opened or unhidden from the host process. When the user adjusts the opacity selector in the overlay toolbar (cycling 35%, 50%, 70%, 90%), the system SHALL apply the selected opacity directly to the native window compositor (`windowManager.setOpacity`) and persist the value to local configuration.

#### Scenario: User toggles overlay opacity
- **WHEN** the user clicks the opacity adjustment button in the live caption toolbar
- **THEN** the floating window's native opacity immediately changes to the selected level, allowing underlying desktop applications or editors to be visible through the floating window at the chosen transparency.

#### Scenario: Subtitle overlay launched from host
- **WHEN** the user opens or re-opens the live caption overlay from the main window
- **THEN** the host process triggers native window styling to guarantee transparent background and absence of native traffic light controls.

### Requirement: Responsive Subtitle Recording State Feedback
The live caption overlay toolbar SHALL reflect the current subtitle recording state in real time based on the state pushed from the host coordinator. When recording is active, the recording button SHALL display an active recording indicator (e.g. stop circle / active recording badge) with a tooltip indicating recording is ongoing; when recording is inactive, it SHALL display an idle state icon with a tooltip indicating start of recording.

#### Scenario: Recording is active
- **WHEN** subtitle recording is enabled either from the floating overlay or the main window
- **THEN** the overlay toolbar recording button updates its visual state to indicate active recording and provides an action to stop recording.

#### Scenario: Recording is stopped
- **WHEN** subtitle recording is stopped
- **THEN** the overlay toolbar recording button returns to the idle icon state and provides an action to begin recording.

### Requirement: Native Floating Window Transparency and User Opacity Setting
The macOS live caption overlay window SHALL configure the native NSWindow to be transparent by setting `isOpaque = false`, `backgroundColor = NSColor.clear`, and hiding standard window traffic light buttons (close, minimize, zoom). The overlay toolbar SHALL provide an opacity selector allowing users to cycle through background opacity levels (e.g., 35%, 50%, 70%, 90%), persisting the preference to local settings.

#### Scenario: Subtitle overlay renders with true translucent background
- **WHEN** the live caption overlay window is displayed over desktop content
- **THEN** underlying desktop content or windows are softly visible through the translucent caption container without being blocked by an opaque solid black background.

#### Scenario: User adjusts background opacity
- **WHEN** the user clicks the opacity toggle button in the caption toolbar
- **THEN** the overlay background opacity immediately updates to the next preset level and persists across sessions.

### Requirement: Non-destructive Window Lifecycle Preservation
The live caption window SHALL handle the window close action by invoking `windowManager.hide()` rather than destroying the native NSWindow, preserving the bidirectional `WindowMethodChannel` pairing. Re-opening the caption window from the main window SHALL unhide and focus the existing window instance without allocating a redundant window or triggering channel limit errors.

#### Scenario: Re-opening the caption overlay after closing
- **WHEN** the user closes the caption overlay window and subsequently clicks "打开字幕窗" in the main window
- **THEN** the existing caption overlay window is unhidden and brought to front at its configured size and position without window distortion, traffic light button leakage, or IPC channel registration failure.

#### Scenario: Subtitles continue delivering on re-opened window
- **WHEN** the user re-opens the caption overlay window while speech transcription is running
- **THEN** newly transcribed subtitle segments are received and rendered in real time through the intact IPC bridge.

### Requirement: Dedicated Hotkey Channel and Instantaneous Speaker Switching
Global hotkeys (⌥1, ⌥2, ⌥3 for speakers 1-3, ⌥T for toggle) SHALL communicate over a dedicated native method channel (`v8_work_toolbox/live_caption_hotkeys`) independent of the subwindow RPC channel. Switching the active speaker via hotkey or overlay button SHALL immediately update the coordinator state, assign the new speaker slot to any currently transcribing in-flight speech segment, and display a colored speaker badge in the subtitle view.

#### Scenario: Pressing speaker hotkey switches active speaker immediately
- **WHEN** the user presses ⌥2 while speech is being recognized
- **THEN** the active speaker changes to Speaker 2, the overlay toolbar speaker button 2 is highlighted, and subsequent (as well as in-flight) transcribed segments display the Speaker 2 identity.

### Requirement: 悬浮窗的隐藏与关闭按钮

字幕悬浮窗 SHALL 提供两个独立的窗口控制按钮，语义明确不同：

- **隐藏**：隐藏悬浮窗窗口，识别与捕获在主进程继续；用户可从主窗口管理界面或 ⌥T 重新呼出
- **关闭**：停止识别与捕获后关闭悬浮窗进程；已记录且未导出的字幕数据 SHALL 保留到用户显式导出或清空

两个按钮 MUST 在悬浮窗界面上可见可点，MUST NOT 仅依赖全局热键。

#### Scenario: 隐藏悬浮窗但识别继续

- **WHEN** 用户在悬浮窗点击"隐藏"
- **THEN** 悬浮窗窗口隐藏，识别继续在后台运行，字幕数据持续累积

#### Scenario: 关闭悬浮窗并停止识别

- **WHEN** 用户在悬浮窗点击"关闭"
- **THEN** 识别与音频捕获停止，悬浮窗进程关闭，已记录字幕保留可导出

#### Scenario: 隐藏后可重新呼出

- **WHEN** 用户隐藏悬浮窗后从主窗口管理界面点击"打开字幕窗"
- **THEN** 悬浮窗重新显示，识别状态与字幕内容保持连续

### Requirement: 悬浮窗拖动不被遮挡

悬浮窗的可拖动区域 SHALL 完整响应拖动，界面中 MUST NOT 存在覆盖内容区、拦截交互却不执行任何手势的冗余手势层。

#### Scenario: 拖动条拖动窗口

- **WHEN** 用户拖动悬浮窗顶部控制条
- **THEN** 窗口跟随移动，且控制条上的说话人/字号/隐藏/关闭按钮均可正常点击

### Requirement: Main Window Embedded Caption Stream and VU Meter
The main `LiveTranslatorPage` SHALL embed an in-page live caption transcript view displaying real-time speech and translation segments, and a visual audio level meter (VU meter) reflecting current input RMS energy, ensuring the user can immediately verify audio capture and recognition without opening the floating window.

#### Scenario: Real-time caption update in main window
- **WHEN** audio chunks are transcribed by the coordinator while the main window is open
- **THEN** speech and translation segments are rendered directly in the main page's transcript card in real time.

#### Scenario: Visual input level verification
- **WHEN** audio is flowing through the selected capture device
- **THEN** the audio level meter in the main window animates in proportion to the RMS energy, providing immediate confirmation that sound is being received.

### Requirement: Cross-window Error Alert Propagation
When an ASR exception (such as HTTP 401 authentication failure, HTTP 402 quota exceeded, or capture process termination) occurs, the error message SHALL be propagated to both the main translator page and the active floating caption window, displaying an attention-grabbing alert banner or toast.

#### Scenario: Floating overlay displays error toast
- **WHEN** the coordinator encounters an ASR error while the floating overlay is visible
- **THEN** the floating window displays an error banner explaining the failure (e.g. quota exceeded or endpoint unreachable) instead of remaining blank.

