## Why

用户在配置 StepFun 后使用实时会议翻译（包括使用 BlackHole 2ch 虚拟声卡及系统音频内录），依然无法输出任何字幕。经排查存在三大系统级阻塞：
1. macOS 应用签名中缺失 `com.apple.security.device.audio-input` entitlement 与 `NSMicrophoneUsageDescription`，导致 macOS 系统强制隔离音频输入流并喂入全 0 静音；
2. VAD 能量阈值默认值过高（500.0 RMS），网页普通音量（50~200 RMS）被误杀为静音；且 FFmpeg 缺少对多通道（如 64ch）音频设备的 Downmix 矩阵处理（报错 -22 闪退）；
3. StepFun 供应商预设未区分普通开放平台（`/v1`）与 Step Plan 专属路径（`/step_plan/v1`），且主窗口缺乏字幕直观渲染与音量电平反馈。

## What Changes

- **macOS 系统级音频权限补齐**：
  - 在 `macos/Runner/Release.entitlements` 与 `macos/Runner/DebugProfile.entitlements` 中新增 `com.apple.security.device.audio-input` 权限。
  - 在 `macos/Runner/Info.plist` 中补充 `NSMicrophoneUsageDescription` 权限用途描述。
  - 在 `scripts/deploy_local.sh` 重签名校验中增加 `audio-input` 权限断言，防止签名静默丢失。
- **音频捕获与 VAD 分块管线健壮化**：
  - 在 `CaptureConfig` 中将默认 VAD 能量阈值从 `500.0` 调优至 `50.0`，自适应捕获普通音量网页与会议音频。
  - 在 `AudioCaptureService.start` 中加入多通道保护：对通道数 > 2 的设备自适应添加 `-af "pan=mono|c0=0.5*c0+0.5*c1"`，杜绝 FFmpeg 闪退。
  - 改进 `AudioCaptureService` 错误感知：监听子进程 `exitCode` 与 stderr 输出，异常退出时及时向上层抛出明确错误。
- **StepFun 供应商 Step Plan 双通道预设与错误引导**：
  - 在 AI 能力配置编辑弹窗中，为 StepFun 提供「Step Plan 专属 (step_plan/v1)」与「开放平台按量 (v1)」双预设切换。
  - 发生 HTTP 402 异常时精准引导用户切换为 `https://api.stepfun.com/step_plan/v1`。
- **实时会议翻译主界面体验提升**：
  - 在 `LiveTranslatorPage` 主界面中增加内嵌实时字幕流列表与实时音量电平跳动条，消除“主窗口无反馈”的用户误解。
  - 浮窗和主界面同步浮现 ASR 错误 Toast。

## Capabilities

### New Capabilities
- `live-audio-capture`: 定义 macOS 录音内录权限、FFmpeg 多通道 Downmix、VAD 灵敏度以及实时音量电平广播规范。

### Modified Capabilities
- `ai-configuration`: 补充 StepFun 供应商针对 Step Plan 专属路径的预设与自适应提示规范。
- `live-caption-overlay`: 增强实时会议翻译主窗口字幕内嵌渲染与悬浮窗错误提示规范。

## Impact

- **Affected Code**:
  - `macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Info.plist`
  - `scripts/deploy_local.sh`
  - `lib/tools/live_translator/models/capture_config.dart`
  - `lib/tools/live_translator/services/audio_capture_service.dart`
  - `lib/tools/live_translator/services/live_translator_coordinator.dart`
  - `lib/tools/live_translator/ui/live_translator_page.dart`
  - `lib/shell/ai_config_page.dart`
- **APIs**: 无破坏性改动，向前兼容。
- **System Requirements**: 重新编译后需触发 macOS 系统的音频输入授权。
