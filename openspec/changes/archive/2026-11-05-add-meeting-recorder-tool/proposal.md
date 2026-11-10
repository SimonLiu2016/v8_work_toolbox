## Why

日常工作中，用户参加各类线上或线下技术会议、架构评审、述职或业务讨论时，常需要完整录制会议音频以便会后复盘、信息核对与追溯。然而目前系统缺少一个轻量、受控的会议音频录制工具：现有的「实时会议翻译」仅对音频做内存流式识别而不落盘，且无法录制麦克风；用户若使用外部系统软件（如 QuickTime），既无法方便地管理会议音频，也无法与工具箱内的工作流联动。

因此，亟需在 V8WorkToolbox 中新增一个「会议录音」独立工具，让用户可以灵活选择输入源（麦克风或系统虚拟声卡）、自由指定存放目录并持久化记住，同时在应用内提供直观的录制控制与内置音频回放能力。

## What Changes

- **新增「会议录音」工具（ToolDefinition）**：
  - 注册在 `ToolCategory.note`（笔记与学习）分类下，标识为 `meeting-recorder`。
  - 提供独立工具主页面，包含设备配置、存放目录配置、录制状态区与录音历史列表。
- **音频录制引擎与设备选择**：
  - 基于 FFmpeg `avfoundation` 引擎实现跨格式录音，优先输出高压缩比、通用度高的 `.m4a`（AAC）音频文件。
  - 支持下拉列举并选择当前系统所有可用音频输入设备（内置麦克风、外置麦克风、耳机麦，以及 BlackHole 等虚拟声卡内录设备）。
  - 录制生命周期管理：支持开始录音、暂停录音、继续录音与停止并保存。
  - 实时录制状态感知：录制时长实时计数（`HH:MM:SS`）与音频电平/波形指示。
- **自定义存储目录与文件持久化**：
  - 默认存储于用户目录（如 `~/Documents/V8Recordings/`）。
  - 支持通过系统文件面板任意切换存放文件夹，并将选定目录持久化到本地配置，下次启动自动记住。
  - 录音默认以时间戳命名（如 `会议录音_YYYYMMDD_HHMMSS.m4a`），保存时支持自定义重命名。
- **内置音频回放与录音管理**：
  - 自动扫描并展示当前存储目录下的历史会议录音文件（文件名、时长、文件大小、创建时间）。
  - 基于 `audioplayers` 提供行内播放控制器：播放/暂停、播放进度条拖动与当前/总时长显示、常用倍速切换（1.0x / 1.25x / 1.5x / 2.0x）。
  - 支持「在访达中显示」（Reveal in Finder）与删除确认，播放状态与外部互斥。

## Capabilities

### New Capabilities

- `meeting-recorder`: 会议音频录制与管理工具，覆盖音频输入设备选择、自定义目录持久化、录制生命周期控制、实时音量与计时指示、以及录音列表的内置音频回放。

### Modified Capabilities

<!-- 无既有规约的行为变更 -->

## Impact

- **Affected Code**:
  - `lib/tools/tool_definition.dart`: 新增 `kToolIdMeetingRecorder = 'meeting-recorder'` 常量。
  - `lib/tools/registry.dart`: 注册 `MeetingRecorderToolDefinition`。
  - `lib/tools/meeting_recorder/`: 新增录音工具模块，包括模型层、录音核心服务 `MeetingRecordService`、存储配置 `MeetingRecorderStore`、播放适配层及 UI 组件。
  - `lib/services/app_paths.dart`: 新增默认录音保存目录路径。
  - 对应单元测试与组件测试。
- **Dependencies**:
  - 依托系统既有的 `audioplayers` 进行播放，依托系统 FFmpeg `avfoundation` 进行录音，不引入新的三方插件依赖。
- **Permissions**:
  - macOS entitlements 与 Info.plist 已具备 `com.apple.security.device.audio-input` 与 `NSMicrophoneUsageDescription`，无需额外配置权限。
