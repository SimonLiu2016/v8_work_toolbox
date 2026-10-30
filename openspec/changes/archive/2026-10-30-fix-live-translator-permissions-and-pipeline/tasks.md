## 1. macOS 系统级音频权限与构建部署校验

- [x] 1.1 在 `macos/Runner/Release.entitlements` 与 `macos/Runner/DebugProfile.entitlements` 中新增 `com.apple.security.device.audio-input` 权限声明
- [x] 1.2 在 `macos/Runner/Info.plist` 中补充 `NSMicrophoneUsageDescription` 描述文案（声明会议内录与语音翻译用途）
- [x] 1.3 在 `scripts/deploy_local.sh` 重签名校验逻辑中增加 `audio-input` 权限断言，缺失时阻断并报警

## 2. 音频捕获与 VAD 灵敏度调优

- [x] 2.1 修改 `lib/tools/live_translator/models/capture_config.dart`，将 `energyThreshold` 默认值下调至 `50.0`
- [x] 2.2 修改 `lib/tools/live_translator/services/audio_capture_service.dart`，当音频设备通道数 > 2 时自适应追加 `-af "pan=mono|c0=0.5*c0+0.5*c1"`，杜绝多通道/64ch 设备崩溃
- [x] 2.3 在 `AudioCaptureService` 中监听 FFmpeg 子进程 `exitCode` 与 stderr，若异常退出及时抛出带详情的捕获异常
- [x] 2.4 在 `lib/tools/live_translator/services/live_translator_coordinator.dart` 中引入 `LiveState.inputRms` 音量电平计算与广播

## 3. StepFun 供应商 Step Plan 双通道预设与 402 精准错误引导

- [x] 3.1 在 `lib/shell/ai_config_page.dart` 中为 StepFun 增加「StepFun (Step Plan)」快捷预设选项，填入 `https://api.stepfun.com/step_plan/v1`
- [x] 3.2 在 StepFun ASR / 翻译请求抛出 HTTP 402 Quota Exceeded 异常时，检测当前 endpoint 并精准提示用户切换到 Step Plan 专属地址

## 4. 实时会议翻译界面升级与错误反馈

- [x] 4.1 在 `lib/tools/live_translator/ui/live_translator_page.dart` 中内嵌实时字幕流滚动卡片，无需打开悬浮窗即可在主窗口查看转写与翻译结果
- [x] 4.2 在主界面控制区增加实时音量电平波形指示条（VU meter），实时反馈音频输入状态
- [x] 4.3 在 `lib/tools/live_translator/ui/live_caption_window.dart` 与主界面中对 ASR 异常提供醒目的错误 Banner 提示

## 5. 测试验证与本地打包部署

- [x] 5.1 运行 `flutter test test/tools/live_translator/` 与 `flutter analyze` 校验代码正确性
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用 `/Applications/V8WorkToolbox.app`，实机验证字幕输出
