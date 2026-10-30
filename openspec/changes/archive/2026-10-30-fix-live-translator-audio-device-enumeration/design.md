## Context

在 macOS 平台上，实时会议翻译依赖 FFmpeg 的 `avfoundation` 驱动枚举并录制系统音频与虚拟声卡设备。`AudioCaptureService.listDevices` 调用 `ffmpeg -f avfoundation -list_devices true -i ''`，并将 `stderr` 输出交由 `_parseDeviceList` 处理。

FFmpeg 在较新版本（如 8.0.1）中对 avfoundation 日志输出增加了模块与实例指针前缀，例如：
```text
[AVFoundation indev @ 0x7fc399204b40] AVFoundation video devices:
[AVFoundation indev @ 0x7fc399204b40] [0] FaceTime高清相机（内建）
[AVFoundation indev @ 0x7fc399204b40] AVFoundation audio devices:
[AVFoundation indev @ 0x7fc399204b40] [0] 聚集设备
[AVFoundation indev @ 0x7fc399204b40] [1] MacBook Pro麦克风
[AVFoundation indev @ 0x7fc399204b40] [6] Soundflower (2ch)
[in#0 @ 0x7fc399204600] Error opening input: Input/output error
```

既有代码采用的正则表达式定界符为：
```dart
RegExp(r'AVFoundation audio devices:([\s\S]*?)(?:\[AVFoundation|Error|\Z)')
```
由于每一行音频设备均以 `[AVFoundation indev @ 0x...]` 开头，定界符中的 `\[AVFoundation` 命中第一行设备行首，导致截取到的片段仅为换行符 `\n`，后续行解析 `lineRe.allMatches` 完全无匹配，使返回列表恒为空。

## Goals / Non-Goals

**Goals:**
- 将设备解析机制重构为抗前缀干扰、跨版本的行扫描解析器。
- 支持同时解析传统无前缀格式（`[0] 设备名`）与现代前缀格式（`[AVFoundation indev @ ...] [0] 设备名`）。
- 将 `_parseDeviceList` 暴露为 `@visibleForTesting parseDeviceList`，并在 `test/live_translator_test.dart` 中建立全量测试套件（覆盖 FFmpeg 8.x 实机输出、经典输出、声道解析、空设备或无相关段落等分支）。
- 确保 UI（`LiveTranslatorPage`）在设备正常枚举后可按预设优先级准确预选，并更新配置状态。

**Non-Goals:**
- 不改变 FFmpeg 音频流启动参数（`-ar 16000 -ac 1 -f s16le` 等采样率及编码格式）。
- 不在应用内自动下载或安装 FFmpeg 二进制；依然基于 `_resolveFfmpeg` 既有搜索路径。
- 不修改 ASR / VAD 与字幕窗口的通信契约。

## Decisions

### 决策 1：采用基于状态标记的行解析，替代易截断的全局正则表达式

- **选择**：按行扫描 `output.split('\n')`，维护 `inAudioSection` 状态：
  1. 遇到包含 `AVFoundation audio devices:` 的行时，进入音频设备区段 (`inAudioSection = true`)；
  2. 在音频区段内，使用正则 `RegExp(r'(?:\]\s+|^)\[(\d+)\]\s+(.+?)\s*$)` 逐行匹配设备索引与名称；
  3. 遇到非捕获行（如出现新的主类别头，或输入文件报错行 `[in#0`）或退出区段；
  4. 从设备名称中提取 `(\d+)ch` 作为声道数，未标注时默认 1。
- **替代方案考虑**：
  - *方案 A（正则 lookahead 定界）*：改写正则为 `r'AVFoundation audio devices:\r?\n([\s\S]*?)(?=\[AVFoundation[^\]]*\] AVFoundation|\[in#|\Z)'`。缺点是 lookahead 依然依赖 FFmpeg 对其它 Section 的前缀特征，未来若 FFmpeg 调整日志级别或增加中间日志，依然存在隐式脆弱性。
  - *选择行解析的原因*：逻辑简单透明，不依赖全局贪婪/非贪婪回溯，极易调试与单元测试。

### 决策 2：暴露静态方法用于纯逻辑单测，与 Process 进程解耦

- **选择**：`AudioCaptureService.parseDeviceList(String output)` 设为公共并标记 `@visibleForTesting`，`listDevices` 仅负责执行进程并将 `stderr` 传入。
- **原因**：CI 环境或开发机上并非总有 AVFoundation 虚拟设备或安装 FFmpeg，将解析逻辑做成纯函数能够以毫秒级运行回归测试。

## Risks / Trade-offs

- **[Risk] FFmpeg 日志行尾可能带不可见回车符 `\r`**
  - **Mitigation**: 逐行处理时调用 `.trim()` 或使用 `\r?\n` 拆分，设备名称提取采用 `.trim()` 清理行尾空白。
- **[Risk] 部分虚拟设备名称包含特殊字符或中文字符（如 `聚集设备`、`豆包会议记录虚拟设备`）**
  - **Mitigation**: 匹配设备名称使用 `.group(2)!.trim()`，不限制字符集，完整保留原始名称。
