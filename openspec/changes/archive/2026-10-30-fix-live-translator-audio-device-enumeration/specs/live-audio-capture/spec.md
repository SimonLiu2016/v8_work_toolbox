## Purpose

为实时会议翻译提供系统及虚拟音频捕获设备的枚举、解析、预选与持久化配置支持，确保跨 FFmpeg 版本稳定获取音频设备。

## ADDED Requirements

### Requirement: 音频捕获设备跨版本 FFmpeg 健壮枚举与解析

系统 SHALL 支持通过 FFmpeg `avfoundation` 驱动枚举 macOS 本机音频输入与虚拟声卡设备，且 MUST 正确兼容包括 FFmpeg 8.x 在内的带行前缀格式（形如 `[AVFoundation indev @ 0x...] [index] Name`）及传统格式，MUST NOT 因行前缀包含 `[AVFoundation` 标记而提前中断或截断解析。

#### Scenario: 成功解析 FFmpeg 8.x 带前缀的音频设备列表

- **WHEN** 宿主机 FFmpeg（8.x 版本）返回包含多行 `[AVFoundation indev @ 0x...] [index] 设备名` 的 stderr 输出
- **THEN** 系统解析出所有可用的音频设备，提取正确的设备索引（`deviceIndex`）、设备名称（`name`）及声道数（`channels`，例如 `Soundflower (2ch)` 解析为 2），且不会返回空设备列表

#### Scenario: 解析旧版或无前缀 FFmpeg 设备列表输出

- **WHEN** 宿主机 FFmpeg 输出中音频设备行无 `indev` 指针前缀（如 `[0] 聚集设备`）
- **THEN** 系统同样能正确提取所有音频设备及其参数

### Requirement: 未枚举到设备或解析失败时的状态提示与刷新恢复

当系统未检测到可用音频设备或底层执行异常时，界面 SHALL 给出明确的状态提示并提供即时刷新操作；用户排查或接入设备后点击刷新，系统 SHALL 重新枚举并立即更新界面呈现。

#### Scenario: 未枚举到设备时呈现刷新入口与排查提示

- **WHEN** FFmpeg 未安装或系统中无可用音频捕获设备
- **THEN** “识别设置”区域明确指示未检测到设备的原因，提供“刷新”按钮，且“开始识别”按钮保持禁用状态

#### Scenario: 重新枚举后自动恢复选中状态

- **WHEN** 用户启动或接入虚拟声卡并点击“刷新”按钮
- **THEN** 界面设备列表立即刷新并按预选策略（记忆匹配 > 虚拟声卡 > 首项）自动选中有效设备，且允许启动识别
