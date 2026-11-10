## 1. 通用倍速常量与发音底层服务升级

- [x] 1.1 定义通用音频倍速阶梯常量 `kUniversalSpeedSteps`（`0.5, 0.75, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0`），供跨模块统一引用。
- [x] 1.2 扩展 `PronunciationAudioBackend` 接口及其实现 `AudioplayersPronunciationBackend`：支持 `setPlaybackRate` 与 `playbackRate` 属性，并在 `playFile` 时保证当前设定速率即时生效。
- [x] 1.3 升级 `VocabularyListPlayerController`：增加 `speed` 状态与 `setSpeed` 方法，将单词等待超时调整为按倍速动态自适应，并添加单元测试。

## 2. 「听力练习」前端全场景倍速交互打通

- [x] 2.1 升级 `ListeningPlayerController` 与 `WorkspacePlayerBar`：将主界面会议片段播放条的速度选择器扩展至完整的 8 档通用阶梯。
- [x] 2.2 升级 `VocabularyBrowserDialog`：在工具栏引入倍速切换胶囊，使单词发音、例句朗读与「连续磨耳朵」均按当前选定倍速播放。
- [x] 2.3 升级 `ListeningHost` 与 `ItListeningMiniPlayerApp` 悬浮窗：解除词汇模式下倍速按钮的隐藏限制，实现词汇磨耳朵与会议片段的跨模式双向倍速同步。

## 3. 「会议录音」历史录音倍速阶梯与偏好持久化

- [x] 3.1 扩展 `MeetingRecorderConfig` 与 `MeetingRecorderStore`：增加 `playbackRate` 持久化字段，支持偏好存取与自愈重置。
- [x] 3.2 升级 `MeetingPlaybackController` 与 `MeetingRecorderPage`：行内播放条接入完整通用倍速阶梯（含 0.5x、0.75x），在用户切换倍速时持久化保存。

## 4. 全量自动化测试与本地部署

- [x] 4.1 运行听力练习与会议录音模块的全部测试（`flutter test test/it_meeting_listening/ test/meeting_recorder/`），确保所有测试 100% 通过。
- [x] 4.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译并替换系统应用，实测各播放场景下的倍速调节体验。
