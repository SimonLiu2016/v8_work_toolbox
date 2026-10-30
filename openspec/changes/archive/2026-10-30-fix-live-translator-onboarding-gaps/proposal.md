## Why

`add-live-meeting-translator` 已部署，但首跑暴露三处"最后一公里"漏接——模型与服务都实现了，界面没接上：工具被分到 `ai` 分类（应属 `note`）；字幕悬浮窗只有 ⌥T 热键能隐藏、无视觉关闭/隐藏按钮（且外层有 GestureDetector 死代码挡交互）；最严重的是音频捕获设备枚举函数 `listDevices()` 已实现，但主窗口 UI 从没调用它，用户无从选择设备，`CaptureConfig.deviceIndex` 恒为 -1，"开始识别"必然抛"未选择有效的音频捕获设备"。

第三点直接违反了既有 spec `live-audio-capture` 的明文要求："系统 SHALL 枚举当前可用的音频捕获设备并让用户选择"。本 change 修复这三处漏接，并补上设备选择的持久化（自动预选 + 记忆）与无虚拟声卡时的引导。

## What Changes

- **工具分类修正**：实时会议翻译从 `ToolCategory.ai` 改为 `ToolCategory.note`（它转录的是用户自己的会议内容，符合 note 分类"用户自己产出的文字"语义）
- **字幕悬浮窗新增两个窗口控制按钮**：
  - **隐藏**：`hide()` 窗口，识别继续（既有 ⌥T 语义，补上视觉入口）
  - **关闭**：停止识别后关闭子窗口进程（新语义）
  - 顺带移除第 112 行那个未绑 `onPan` 的 GestureDetector 死代码（它挡住下层交互，与拖动条手势冲突）
- **主窗口新增音频设备选择 UI**：
  - 打开工具页时调用 `AudioCaptureService.listDevices()` 枚举可用设备，以下拉框呈现（名称 + 通道数）
  - **自动预选**：优先选名字含 "Soundflower" / "BlackHole" / "虚拟" / "aggregate" 的设备；否则记忆中的设备；否则第一个
  - **记忆选择**：选中的设备索引经 `SettingsStore.readToolConfig/writeToolConfig`（toolId = `live-meeting-translator`）持久化，下次开工具自动恢复
  - 提供"刷新设备"按钮重新枚举（用户临时插拔声卡后可用）
  - 未选到有效设备时，"开始识别"按钮禁用并显示引导文案（内录需虚拟声卡如 BlackHole/Soundflower）
- **无虚拟声卡时的引导**：设备列表里没有 Soundflower/BlackHole 类设备时，显示一句提示说明内录原理与安装方向，MUST NOT 静默让用户在麦克风里找不到北

**BREAKING** 无（修复既有缺陷，不改数据结构）。

### 不做的事（明确的非目标）

- 不重写 VAD 或 ASR 逻辑（与漏接无关）
- 不做设备自动跟随系统默认输出切换（用户手动选，工具只记忆）
- 不做 BlackHole 的自动安装向导（首版只给提示文案）

## Capabilities

### Modified Capabilities

- `app-shell`: 实时会议翻译的工具分类从 `ai` 调整为 `note`（spec 的分类枚举本身不变，变的是该工具的归类——这属于"注册声明"层面的行为变化，需要记录以免回归）

### New Capabilities

- `live-audio-capture`: 扩充"设备选择"契约——spec 原文已有"枚举并让用户选择"的抽象要求，本 change 把它落成可验证的具体行为：首次打开工具页自动枚举并自动预选（优先虚拟声卡）、选择经持久化记忆、可手动刷新、无虚拟声卡时给出引导、未选有效设备时禁止启动识别。这是把既有 spec 的一句话展开成完整需求，同时新增"预选优先级"与"持久化"两条 spec 未覆盖的行为。

## Impact

**改动文件**

- `lib/tools/registry.dart` — `LiveTranslatorToolDefinition.category` 从 `ToolCategory.ai` 改为 `ToolCategory.note`
- `lib/tools/live_translator/ui/live_caption_window.dart` — 新增隐藏/关闭按钮；删除第 112 行 GestureDetector 死代码
- `lib/tools/live_translator/ui/live_translator_page.dart` — 新增设备下拉框 + 刷新按钮 + 无设备引导；开始识别前校验设备
- `lib/tools/live_translator/services/live_translator_host.dart` — 区分 `hideCaptionWindow()`（隐藏，识别继续）与 `closeCaptionWindow()`（停止识别 + 关进程）
- `lib/tools/live_translator/services/live_caption_bridge.dart` — 新增 `hide` / `close` 两个指令（悬浮窗 → 主进程）
- `lib/tools/live_translator/services/audio_capture_service.dart` — 无需改（`listDevices()` 已实现）
- `lib/tools/live_translator/models/capture_config.dart` — 无需改（`deviceIndex` 字段已有）

**新增**

- `openspec/specs/live-audio-capture/spec.md` — 归档时把"设备选择"展开为完整需求

**依赖**

- 无新增。复用既有 `SettingsStore.readToolConfig/writeToolConfig`、`window_manager.hide/close`、`WindowController.close`

**数据**

- 新增一项工具级持久化配置（`live-meeting-translator` 的 `selectedDeviceIndex` 与 `deviceName`），存于既有工具配置存储，无数据库迁移
