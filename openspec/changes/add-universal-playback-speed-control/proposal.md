## Why

在「听力练习」与「会议录音」工具中，音频播放是核心功能。但目前两者的播放速度控制存在显著缺失与体验割裂：
- 「听力练习」中，主会议片段播放仅支持窄区间的 4 个速度档位（0.75x~1.25x），生词浏览对话框（单词发音、例句朗读、连续磨耳朵）底层完全缺乏倍速调节接口，迷你悬浮窗更在词汇模式下直接隐藏了倍速按钮；
- 「会议录音」中，历史录音播放仅支持快速（1.0x~2.0x），完全缺乏对精听关键的慢速档位（0.5x、0.75x），且每次播放无法记忆用户的倍速偏好。

用户在语言学习精听（慢速辨音）和会议复盘泛听（高速浏览）时，急需全局统一、覆盖完整场景的音频播放速度调节能力。

## What Changes

- **统一全局音频倍速阶梯**：对齐一组通用的标准倍速阶梯 `[0.5, 0.75, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0]`，覆盖慢速精听至快速泛听。
- **「听力练习」词汇发音与磨耳朵全链路倍速支持**：
  - 扩展底层发音服务接口 `PronunciationAudioBackend`，支持 `setPlaybackRate` 与倍速读取；
  - 升级 `VocabularyListPlayerController` 支持倍速状态与连播节奏自适应；
  - 在 `VocabularyBrowserDialog` 顶部引入全局倍速切换器，使单词点读、例句点读与连续磨耳朵均遵从设定倍速；
  - 移除迷你悬浮窗（`ItListeningMiniPlayerApp`）中对词汇模式倍速按钮的隐藏限制，实现跨模式全功能调速。
- **「听力练习」会议播放条倍速选项扩展**：
  - 升级主界面 `WorkspacePlayerBar` 与 `ListeningPlayerController` 的倍速列表至完整阶梯。
- **「会议录音」历史音频播放倍速增强与偏好记忆**：
  - 在 `MeetingPlaybackController` 中引入 0.5x、0.75x 等完整阶梯；
  - 在 `MeetingRecorderStore` 中持久化用户的播放倍速习惯，切换音频或下次打开时自动保持。

## Capabilities

### Modified Capabilities
- `it-meeting-listening`: 升级播放控制要求，使所有音频播放功能（会议片段、词汇发音、例句朗读、词汇连播磨耳朵、常驻迷你窗）均支持播放速度调节与扩展倍速阶梯。
- `meeting-recorder`: 升级历史录音回放要求，支持包含慢速与快速在内的完整倍速阶梯，并持久化用户的播放倍速偏好。

## Impact

- `lib/tools/it_meeting_listening/services/pronunciation_audio_backend.dart`
- `lib/tools/it_meeting_listening/services/vocabulary_list_player_controller.dart`
- `lib/tools/it_meeting_listening/services/listening_player_controller.dart`
- `lib/tools/it_meeting_listening/services/listening_host.dart`
- `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`
- `lib/tools/it_meeting_listening/ui/workspace_player_bar.dart`
- `lib/tools/it_meeting_listening/ui/it_listening_mini_player.dart`
- `lib/tools/meeting_recorder/services/meeting_playback_controller.dart`
- `lib/tools/meeting_recorder/services/meeting_recorder_store.dart`
- `lib/tools/meeting_recorder/ui/meeting_recorder_page.dart`
- 对应模块的单元测试与 UI 测试。
