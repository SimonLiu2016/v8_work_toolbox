## Why

真实会议逐字稿合成时，单轮文本超过 900 字符会长文本切片。当系统配置使用返回 WAV 流的 TTS 引擎（如小米 MiMo）时，底层 `ffmpeg -c copy` 无法将 PCM 裸流拷贝封装至 MP3 容器，导致所有超长话轮合成失败（如 10-29 会议中的 9 组）；失败后生成的 MP3 静音文件又与前序 WAV 切片在整篇拼接时产生混杂冲突，导致整场会议音频损坏（0 字节）并彻底锁死播放，同时失败信息在底层被层层吞噬，界面毫无诊断信息与排查入口。

## What Changes

- **音频拼接与转码韧性 (FfmpegAudioToolkit)**：`concat` 方法由纯 `-c copy` 升级为具备自动重编码回退（`-c:a libmp3lame -b:a 128k`）的高韧性拼接；同时在合成落盘时确保音频容器格式与实际流编码一致，彻底消除多段拼接崩溃与混杂格式整篇拼接崩溃。
- **优雅降级与播放保障 (RealMeetingBaker & Controller)**：即使个别话轮在网络/TTS 侧不可抗力失败，静音占位与整篇音频拼接仍能 100% 成功生成可播音频；修复 `hasPlayableClip` 状态判定，确保用户能立即播放已成功合成的其余轮次。
- **全链路错误透出与结构化诊断 (Error Diagnostics)**：在 `RealMeetingBakeResult` 与 `MeetingBakeState` 中记录结构化失败原因（话轮索引、发言人、失败阶段、具体错误文本）；控制器与面板展示失败明细，不再吞噬错误。
- **界面交互优化 (RealMeetingViews & Detail)**：在真实会议概览与操作栏中提供失败轮次详情展开弹窗/条目，并支持精准的“重试失败组”及“一键重拼整篇音频（修复音频）”，避免原地卡死。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 增加真实会议超长话轮分段转码拼接韧性、失败静音占位容错整篇播放保障、以及合成失败结构化诊断与明细透出要求。

## Impact

- **Affected Code**:
  - `lib/tools/it_meeting_listening/services/audio_toolkit.dart` (`FfmpegAudioToolkit.concat` 转码回退)
  - `lib/tools/it_meeting_listening/services/real_meeting_baker.dart` (`_synthesizeToFile` 转码保障、错误保留、`rebuildAudio` 稳健性)
  - `lib/tools/it_meeting_listening/models/real_meeting_models.dart` (`TurnGroupAudio` 与 `MeetingBakeState` 增加结构化错误信息字段)
  - `lib/tools/it_meeting_listening/services/real_meetings_controller.dart` (主操作逻辑、错误传递与状态更新)
  - `lib/tools/it_meeting_listening/ui/real_meeting_panel.dart` & `real_meeting_views.dart` (失败原因展示、修复音频与重试交互)
- **Dependencies & APIs**: 依赖系统已就位的 `ffmpeg` 工具链，无新增外部第三方依赖。
