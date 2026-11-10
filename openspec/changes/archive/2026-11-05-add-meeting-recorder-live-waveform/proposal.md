## Why

在会议录音工具中，用户在选择声音输入设备（如 MacBook Pro 麦克风）并开始录音后，录制控制面板仅显示简单的计时与呼吸红点，缺乏实时的声音波形反馈，导致用户无法确知当前麦克风是否真正捕获到了人声输入，存在录制盲区与不确定感。

## What Changes

- **录音引擎实时电平流**：在 `MeetingRecordEngine` 接口中引入 `audioLevelStream`（归一化 0.0 ~ 1.0 音量电平），并在 `FfmpegMeetingRecordEngine` 中通过 `-af "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-"` 实时读取麦克风能量（RMS dB），实现真·实时音频采集反馈。
- **动态声波指示器（Live Waveform Meter）**：在 `MeetingRecorderPage` 录制控制面板中新增实时律动声波柱组件。当用户说话时，波形柱根据声音大小跳动；静音或未检测到声音时回落贴底，直观呈现麦克风输入状态。
- **暂停与停止状态重置**：当录音暂停或停止时，电平与波形柱立即平滑归零，避免界面悬停残余波形。

## Capabilities

### Modified Capabilities
- `meeting-recorder`: 在录制控制卡片中增加基于麦克风真实拾音的动态声波电平指示，并由录音引擎提供实时电平流支撑。

## Impact

- 受影响接口：`MeetingRecordEngine` 增加 `Stream<double> get audioLevelStream` 与当前电平 getter。
- 受影响文件：`lib/tools/meeting_recorder/services/meeting_record_engine.dart`、`lib/tools/meeting_recorder/ui/meeting_recorder_page.dart`。
- 测试适配：`test/meeting_recorder/meeting_record_engine_test.dart`、`test/meeting_recorder/meeting_recorder_ui_test.dart`。
- 依赖项：无需额外第三方依赖，沿用系统 FFmpeg 的 `astats` 与 `ametadata` 滤镜，对落盘 AAC 音质无损。
