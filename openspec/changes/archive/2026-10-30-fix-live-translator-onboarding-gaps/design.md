## Context

见 proposal.md - Why。本 change 是 `add-live-meeting-translator` 的漏接修复，不引入新架构，只补三处界面接线 + 一项持久化。

**部署后实测发现的三处断裂**（代码现状）：

- `registry.dart:444` — `LiveTranslatorToolDefinition.category` 是 `ToolCategory.ai`，应为 `note`。
- `live_caption_window.dart:112` — 一个 GestureDetector 包住整个 body 却没绑任何手势回调（`onPanStart` 等全无），是死代码，且它盖住了下层内容与拖动条的交互。悬浮窗只有 ⌥T 热键能隐藏，无视觉关闭入口。
- `live_translator_page.dart` — 识别设置区有语言下拉、说话人命名、热词，但**没有设备下拉框**。`AudioCaptureService.listDevices()`（`audio_capture_service.dart:44`）已实现且可正确解析 ffmpeg 设备列表，`CaptureConfig.deviceIndex` 字段也存在，但 UI 从未调用枚举、从未设置 `deviceIndex`，默认恒为 -1，`start()` 必抛"未选择有效的音频捕获设备"。这是 spec `live-audio-capture` 已明文要求但实现漏掉的行为。

**可复用**：

- `SettingsStore.readToolConfig/writeToolConfig` — 工具级持久化既有机制（见 `infinite_canvas_config_store.dart`、`registrar_config_store.dart` 的用法）。
- `window_manager.hide()/close()` 与 `WindowController.close()` — 窗口控制 API。
- `AudioCaptureService.listDevices()` — 设备枚举已实现，返回 `AudioCaptureDevice{name, channels, deviceIndex}`。

## Goals / Non-Goals

**Goals:**

- 首次打开工具页即见可选设备列表，且自动预选最可能正确的设备（记忆 > 虚拟声卡 > 第一个）。
- 悬浮窗的隐藏/关闭语义清晰分离，都有视觉入口。
- 修复不能改变主进程持有状态的架构（design D4 不变）。

**Non-Goals:**

- 不改设备枚举解析逻辑（已正确）。
- 不做设备自动跟随系统默认输出。
- 不做 BlackHole 安装向导（只给文案引导）。

## Decisions

### D1: 隐藏 vs 关闭 = hide() vs stop + close()

**决策**：悬浮窗"隐藏"按钮 → 经 bridge 发 `hide` 指令 → 主进程 `hideCaptionWindow()`（既有，只 `hide()` 窗口，识别继续）。"关闭"按钮 → 发 `close` 指令 → 主进程先 `coordinator.stop()`（停识别与捕获）再 `WindowController.close()` 关掉子窗口进程。

**理由**：用户明确要求两个按钮、两种语义。"隐藏保留识别"符合 design D4（状态在主进程，关掉视图不动状态）；"关闭"是用户明确要结束本次会话，停止识别避免后台空跑耗配额。

**备选与取舍**：*关闭也保留识别*会让"关闭"与"隐藏"无区别，用户分不清；*隐藏也停识别*违背"关闭不中断"的既有 spec 意图。按用户要求二分。

### D2: 设备枚举时机 = 工具页 initState + 手动刷新

**决策**：`LiveTranslatorPage.initState` 里首次枚举；另设"刷新设备"按钮供用户插拔声卡后重新枚举。不做定时轮询。

**理由**：ffmpeg 枚举一次几百毫秒，initState 里做一次成本可接受；声卡插拔是低频动作，手动刷新足够，定时轮询是浪费。

**备选与取舍**：*定时轮询*能自动发现新设备但持续消耗；*仅在点击开始时枚举*会让用户看不到当前有哪些设备可选，失去预选的意义。

### D3: 预选优先级 = 记忆 > 虚拟声卡关键词 > 第一个

**决策**：枚举后按序尝试：(1) 持久化的设备索引若仍在列表中，选它；(2) 名字匹配 `Soundflower|BlackHole|虚拟|aggregate|聚集` 的第一个设备；(3) 列表第一个。每次选择变化都写回持久化。

**理由**：内录的正确设备几乎总是虚拟声卡，关键词命中省去用户每次手动选；记忆优先尊重用户上一次的明确选择。这三个关键词覆盖本机实测设备名（Soundflower / 豆包会议记录虚拟设备 / Microsoft Teams Audio / WeMeet Audio Device / 聚集设备）。

**备选与取舍**：*只按关键词*每次开工具可能选到不同的同名词设备；*只记第一个*新装声卡后选错。优先级链最稳。

### D4: 持久化用 SettingsStore 工具配置，不新增存储

**决策**：`SettingsStore.instance.readToolConfig('live-meeting-translator')` 读 `selectedDeviceIndex` + `deviceName`，写选用 `writeToolConfig`。合并进既有配置 map，不覆盖其它键。

**理由**：既有机制、零迁移、与其它工具一致。选设备是低频写，无性能顾虑。

**备选与取舍**：*新增 SQLite 表*过度；*裸文件*绕过既有机制。用 SettingsStore 最一致。

### D5: 无效设备时禁用"开始识别"，而非点击后才报错

**决策**：`deviceIndex < 0` 或不在当前列表时，"开始识别"按钮 `onPressed: null`（禁用态），并在设备区显示"请选择一个音频捕获设备"。

**理由**：点击后才抛异常是事后报错，禁用态是事前预防。spec 已要求"未选有效设备时禁止启动识别"。这直接消除用户撞到的那句报错。

**备选与取舍**：*点击后 toast 提示*仍让用户点了一次无效按钮；*自动选一个*可能选到麦克风录到用户自己的声音（违背"不捕获麦克风"）。

### D6: 分类改动只动注册声明一处

**决策**：`registry.dart` 的 `LiveTranslatorToolDefinition.category` 改 `ToolCategory.note` 一行。同时在 fix 的 app-shell delta spec 里记下归类，防止将来回归。

**理由**：分类由 ToolDefinition 声明驱动，ActivityBar 按枚举遍历，无需改导航。记 spec 是因为这是"行为可见"的归类，值得留契约。

**备选与取舍**：无（改声明是唯一正确做法）。

## Risks / Trade-offs

- **ffmpeg 枚举在 initState 里同步做会卡首帧** → 用 async + setState，枚举期间下拉框显示"正在枚举设备…"；失败（ffmpeg 缺失）时显示明确错误而非空白。
- **虚拟声卡关键词匹配漏掉某些设备名** → 关键词表覆盖中英文常见命名；漏掉的最坏后果是预选到第一个设备（可能是麦克风），用户可手动改选，且选择会被记忆。
- **记忆的设备索引在 ffmpeg 重枚举后偏移** → 预选时校验"索引在范围内**且**名字匹配"，名字对不上即视为失效走关键词回退，避免索引错位选错设备。
- **close 关掉子窗口进程后，desktop_multi_window 的窗口 id 失效** → 主进程 `closeCaptionWindow()` 里清空 `_captionWindow`/`_captionWindowId`，下次"打开字幕窗"重新 create（既有 `openCaptionWindow` 已处理 create 路径）。
- **隐藏后再点"打开字幕窗"应是 show 而非新建** → 既有 `openCaptionWindow` 已先遍历 `WindowController.getAll()` 找同 arguments 窗口并 show；只有 close 后才需要 create。两个入口复用同一方法即可。

## Migration Plan

无破坏性变更。纯界面修复 + 一项新工具配置键（`selectedDeviceIndex`/`deviceName`，首次读写时自然创建）：

- 改动 5 个文件（registry、caption_window、translator_page、host、bridge）
- 无数据库迁移、无目录结构变化

回滚：还原 5 个文件的改动即可，不残留数据依赖（工具配置键留着不影响其它）。

## Open Questions

- 无。三处修复范围明确，预选优先级与二分语义已由用户确认。
