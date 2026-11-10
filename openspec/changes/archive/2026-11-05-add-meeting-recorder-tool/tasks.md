## 1. 基础架构与配置层

- [x] 1.1 在 `lib/tools/tool_definition.dart` 增加常量 `kToolIdMeetingRecorder = 'meeting-recorder'`；在 `lib/services/app_paths.dart` 补充默认录音存储路径（`~/Documents/V8Recordings/`）。
- [x] 1.2 创建模型类 `lib/tools/meeting_recorder/models/recording_models.dart`，定义 `MeetingRecordingItem`（文件名、路径、录制时间、时长毫秒、大小字节）与 `MeetingRecorderConfig`（输出目录、选中设备信息）。
- [x] 1.3 创建配置持久化服务 `lib/tools/meeting_recorder/services/meeting_recorder_store.dart`，负责 `config/meeting_recorder.json` 的读写与默认路径初始化。

## 2. 录音引擎与核心服务

- [x] 2.1 抽离录音引擎抽象接口 `MeetingRecordEngine`，并实现生产级 `FfmpegMeetingRecordEngine`：配置 `-f avfoundation`、`-i :<deviceIndex>`、`-c:a aac`、`-movflags +faststart` 并输出到目标 `.m4a` 文件。
- [x] 2.2 实现录制生命周期管理：启动录制、暂停（`SIGSTOP`）、恢复（`SIGCONT`）与优雅终止（输入 `q` 或 `SIGTERM` 确保 M4A moov 元数据写入）。
- [x] 2.3 实现音频设备枚举适配器，列举可用麦克风与虚拟声卡设备，并支持设备丢失时的保护拦截。
- [x] 2.4 实现录音目录扫描器 `RecordingFileScanner`：扫描指定目录下的 `.m4a` / `.mp3` / `.wav` 文件，解析时长与大小，并按时间倒序排列。

## 3. 音频播放与控制器层

- [x] 3.1 抽离 `MeetingAudioPlayer` 抽象接口，并实现生产级包装 `audioplayers.AudioPlayer` 的适配器与单测可注入的内存 Mock 实现。
- [x] 3.2 实现 `MeetingPlaybackController`：管理当前选中的播放文件、播放/暂停状态流、播放进度通知、Seek 跳转及播放倍速（`1.0x` / `1.25x` / `1.5x` / `2.0x`）。

## 4. UI 界面与交互实现

- [x] 4.1 创建 `lib/tools/meeting_recorder/ui/meeting_recorder_page.dart`：构建顶部配置栏（设备下拉、存储目录选择与更换按钮）、中央录制态控制区与底部录音历史列表。
- [x] 4.2 实现中央录制控制组件：录制中实时计时（`HH:MM:SS`）、动态音量电平波形指示器、开始/暂停/继续/停止按钮交互与状态保护。
- [x] 4.3 实现录音列表项与行内播放控件：展示录音基本信息、行内播放进度条、倍速弹窗、「在访达中显示」（Reveal in Finder）动作与删除二次确认。
- [x] 4.4 在 `lib/tools/registry.dart` 中注册 `MeetingRecorderToolDefinition`，归类于 `ToolCategory.note`（笔记与学习）。

## 5. 自动化测试与部署验证

- [x] 5.1 编写 `test/meeting_recorder/meeting_recorder_store_test.dart`：测试配置读写、默认目录自愈、目录变更后持久化。
- [x] 5.2 编写 `test/meeting_recorder/meeting_record_engine_test.dart`：测试命令行参数组装、生命周期信号状态转换。
- [x] 5.3 编写 `test/meeting_recorder/meeting_playback_controller_test.dart`：测试播放/暂停切换、进度通知与倍速控制。
- [x] 5.4 编写 `test/meeting_recorder/meeting_recorder_ui_test.dart`：验证设备列表渲染、录制计时器响应与列表交互。
- [x] 5.5 按照工程规范执行 `./scripts/deploy_local.sh` 编译部署到系统应用，实测麦克风/虚拟设备录制与行内播放。
