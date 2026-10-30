## Context

实时会议翻译需要捕获 macOS 系统音频（通过 BlackHole 等虚拟声卡或麦克风）并实时发送到 StepFun ASR 流式服务。
在已完成的 StepFun 接入变更中，我们发现即便后端识别逻辑已就绪，在桌面应用中依然没有字幕输出，根因在于：
1. macOS 应用签名中未包含 `com.apple.security.device.audio-input` 和 `NSMicrophoneUsageDescription`，系统沙盒直接对音频输入喂入全 0 静音；
2. VAD 能量阈值默认为 500.0 RMS，远高于网页普通音频能量（50~200 RMS）；
3. FFmpeg 缺少对多通道设备的 Downmix 矩阵保护，且进程退出时 stderr 被静默抽干；
4. 主窗口只放了控制选项，缺少内嵌字幕展示与实时音频波形反馈。

## Goals / Non-Goals

**Goals:**
- 在 `Release.entitlements`、`DebugProfile.entitlements` 和 `Info.plist` 中声明完整的音频输入权限，并在 `deploy_local.sh` 中增加签名断言。
- 调优 VAD 阈值到 `50.0 RMS`，并向 UI 广播实时音量电平。
- 在 `AudioCaptureService` 中为多声道设备（通道数 > 2）自动配置 `-af "pan=mono|c0=0.5*c0+0.5*c1"`，并对子进程 exitCode 与 stderr 实施异常捕获。
- 在 `LiveTranslatorPage` 主界面中直接提供字幕流列表与音量波形条，并在浮窗中暴露错误通知。
- 在 AI 能力配置中提供 StepFun Step Plan 与标准开放平台双预设。

**Non-Goals:**
- 不重构 `StepFunAsrClient` 底层 SSE 协议解析机制（协议已在测试中完全验证通过）。
- 不引入重型第三方法生音频捕获库（如 portaudio 或 oboe），保持轻量级 FFmpeg + avfoundation 架构。

## Decisions

### D1: macOS 音频输入权限显式声明与部署校验
- **决策**:
  - 在 `macos/Runner/Release.entitlements` 和 `macos/Runner/DebugProfile.entitlements` 中增加：
    ```xml
    <key>com.apple.security.device.audio-input</key>
    <true/>
    ```
  - 在 `macos/Runner/Info.plist` 中增加 `NSMicrophoneUsageDescription`。
  - 在 `scripts/deploy_local.sh` 的 `resign` 步骤中增加验证：
    ```bash
    case "$signed_ent" in
        *device.audio-input*) ;;
        *) die resign "entitlements 未进入签名：缺少 com.apple.security.device.audio-input" ;;
    esac
    ```
- **备选方案**:
  - 仅在 Debug 中开启：不可行，Release 模式打包部署到 `/Applications` 仍会被 macOS 沙盒封锁。

### D2: FFmpeg 多通道 Downmix 保护与子进程生命周期监控
- **决策**:
  - 在 `AudioCaptureService.start` 中检查 `config.channels`：若通道数 > 2（或通道数为 64ch），在 FFmpeg 参数中注入 `-af "pan=mono|c0=0.5*c0+0.5*c1"`。
  - 监听 `_process!.exitCode`：若进程在非 `stopped` 状态下非正常退出，收集 stderr 尾部信息并触发 `_pcmController.addError`。
- **备选方案**:
  - 强制限制用户只能选 2ch 设备：不可行，用户可能会选错 64ch 或聚集设备导致 App 默默挂掉。

### D3: VAD 灵敏度下调与实时 RMS 电平广播
- **决策**:
  - 将 `CaptureConfig.energyThreshold` 默认值从 `500.0` 调整为 `50.0`。
  - 在 `LiveState` 中新增 `double inputRms` 字段，每 100ms 向 UI 广播一次最新帧的最大 RMS，供电平计渲染。
- **备选方案**:
  - 移除 VAD 直接全量发送：会导致纯静音持续发起无意义 ASR 请求，浪费用户 StepFun 额度。

### D4: 主窗口内嵌字幕流与跨窗口错误提醒
- **决策**:
  - 在 `LiveTranslatorPage` 中增加一列/卡片直接渲染当前 `state.captions` 列表，使用户无需打开浮窗也能立刻看到字幕滚动。
  - 在浮窗 `LiveCaptionWindowApp` 中，当 `lastError` 非空且包含错误时，在顶部弹出显眼的提示条（如 402 额度超限或音频设备未授权）。

## Risks / Trade-offs

- **[Risk]** 重新打包部署后，macOS 首次运行可能弹出系统权限对话框请求访问麦克风。
  → **Mitigation**: 在 UI 启动捕获时如果捕获失败，提示用户在系统设置“隐私与安全性 -> 麦克风”中授予权限。
- **[Risk]** VAD 阈值从 500 下调到 50 可能会让细微的环境底噪触发切块。
  → **Mitigation**: 50 RMS 经过实测已高出普通房间本底噪声（本底噪声通常在 5~15 RMS），能稳定过滤绝对静音并捕获轻声对话。

## Migration Plan

1. 更新 entitlements、Info.plist 与 deploy 脚本。
2. 更新 CaptureConfig、AudioCaptureService、VadChunker 与 LiveTranslatorCoordinator。
3. 更新 LiveTranslatorPage 与 LiveCaptionWindow。
4. 运行单元测试验证，执行 `./scripts/deploy_local.sh` 替换本机应用生效。
