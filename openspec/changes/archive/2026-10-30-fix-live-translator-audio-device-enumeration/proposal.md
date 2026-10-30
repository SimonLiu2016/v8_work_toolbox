## Why

在“实时会议翻译”工具中，“识别设置”始终显示“未枚举到音频捕获设备”，导致用户无法选择内录设备且无法开始识别。根本原因是 `AudioCaptureService.listDevices()` 解析 FFmpeg `avfoundation` 输出的正则表达式存在边界缺陷：在现代 FFmpeg（如 FFmpeg 8.x）中，每行日志均带有 `[AVFoundation indev @ 0x...]` 前缀，导致 `audioSection` 正则中的终止条件 `\[AVFoundation` 在遇到首个音频设备行时就发生提前截断，提取到的音频设备段内容为空。

## What Changes

- **修复 FFmpeg avfoundation 音频设备解析算法**：
  - 重构 `AudioCaptureService._parseDeviceList`，采用基于行扫描或精确定界的状态解析，不再因每行前缀带 `[AVFoundation` 而提前中断。
  - 兼容多种 FFmpeg 版本格式（含带前缀 `[AVFoundation indev @ 0x...] [index] Name` 与不带前缀 `[index] Name`）。
  - 健壮解析设备名称与通道数（如 `Soundflower (2ch)`、`聚集设备` 等），确保正确提取 `deviceIndex`、`name` 与 `channels`。
- **提供可独立测试的设备列表解析接口与单元测试**：
  - 将 `_parseDeviceList` 暴露为测试可见（或 `@visibleForTesting parseDeviceList`），增加覆盖 FFmpeg 8.x 实际输出、历史版本输出以及异常输出的完备单元测试。
- **改善未枚举到设备或 FFmpeg 故障时的排查诊断与交互**：
  - 在 UI 出现“未枚举到音频捕获设备”时，提供清晰的刷新与排查提示，确保状态更新与设备自动预选联动顺畅。

## Capabilities

### New Capabilities

- `live-audio-capture`: 保证音频捕获设备在各版本 FFmpeg（尤其是包含日志前缀的 FFmpeg 8.x）下的健壮枚举与解析，使实时会议翻译工具能正常获取系统内录及麦克风设备列表。

### Modified Capabilities

<!-- None -->

## Impact

**改动代码**：
- `lib/tools/live_translator/services/audio_capture_service.dart`：重构 `_parseDeviceList` 解析逻辑，添加 `@visibleForTesting`。
- `test/live_translator_test.dart`（或新建对应解析测试）：添加针对不同 FFmpeg 输出格式的设备列表解析单元测试。
- `lib/tools/live_translator/ui/live_translator_page.dart`：优化设备枚举状态反馈与排查提示。

**依赖/数据**：
- 无新增第三方依赖，无数据库表结构变更。
