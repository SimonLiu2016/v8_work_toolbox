## Context

在 V8WorkToolbox 中，多媒体与音频处理已经形成了成熟的基础设施：
1. **音频处理与进程调用**：`FfmpegAudioToolkit` 具备稳定的系统 FFmpeg 路径探测与解析能力；`AudioCaptureService` 具备成熟的 macOS `avfoundation` 输入设备枚举解析逻辑；
2. **音频播放**：`audioplayers: ^6.0.0` 已在 `DocAudioReader`、`VocabBook` 与 `ItMeetingListening` 中广泛使用；
3. **系统权限与沙箱**：应用沙箱已配置 `com.apple.security.device.audio-input` 与 `NSMicrophoneUsageDescription`，允许访问麦克风与音频输入设备。

## Goals / Non-Goals

**Goals:**
- 提供直观易用的会议录音工具主页面，包含设备切换、存储目录指定、录音控制与回放列表。
- 采用 FFmpeg `avfoundation` 实现高音质 `.m4a` (AAC) 会议录音，支持内置/外接麦克风及虚拟内录声卡。
- 录音过程具备完整的暂停/继续能力，进程优雅退出保证音频元数据完整性。
- 录音列表支持行内播放、拖动进度、倍速切换（1.0x/1.25x/1.5x/2.0x）与 Finder 跳转。
- 存储目录与设备选择实现本地持久化，启动自动加载并刷新。

**Non-Goals:**
- 不做多轨同时录制（如同时混录麦克风与系统声音为两条独立音轨，用户若需混录可使用系统自带的聚集设备 Aggregate Device）。
- 不做音频在线剪辑、降噪滤镜或波形编辑（归属于后期处理工具）。
- 不在录音工具内直接集成大模型语音转写（保持职责单一，录音文件可通过文件导入后续工具）。

## Decisions

### 1. 录音引擎选型：采用 FFmpeg `avfoundation` 而非引入 `record` Flutter 插件
- **理由**：
  1. 避免新增 CocoaPods 依赖，杜绝打包与签名时的 seal 失效风险；
  2. FFmpeg 的 `avfoundation` 能直接无缝读取 macOS 上任意音频输入设备（包括 BlackHole、Soundflower 等多声道虚拟声卡），并通过 `-af pan=mono` 或直接转码直接输出标准化的高兼容性 `.m4a` (AAC) 格式；
  3. 现有工程在 `AudioCaptureService` 中已实现健壮的设备列表正则解析，可直接复用成熟经验。
- **备选方案**：引入 `record: ^5.x` 插件。备选方案虽然纯 Dart API 简单，但在 macOS 虚拟声卡通道映射上灵活性较低，且存在 Pod 编译风险。

### 2. 录制进程生命周期与优雅终止（避免损坏 `moov` atom）
- **理由**：
  `.m4a` 容器依赖文件末尾（或头部）写入的 `moov` atom 元数据索引，若强行 `SIGKILL` 杀死 FFmpeg 进程，会导致文件无法播放。
- **方案**：
  - **启动**：调用 `Process.start` 启动 FFmpeg，参数增加 `-movflags +faststart`（元数据移至头部，便于流式读取与快速恢复）；
  - **暂停 / 继续**：向 FFmpeg 进程发送 `ProcessSignal.sigstop` 挂起进程与系统时间戳，继续时发送 `ProcessSignal.sigcont` 唤醒；同时界面计时器相应暂停与恢复；
  - **停止保存**：向 FFmpeg 进程 `stdin.write('q\n')`，或发送 `ProcessSignal.sigterm` / `sigint`，等待子进程退出码为 0，确保文件完整写入并落盘。

### 3. 配置与持久化：`config/meeting_recorder.json`
- **理由**：
  保持与工程既有工具配置（如 `config/reader_config.json`, `config/slimmer-keep-list.json`）一致的独立文件存储方式，避免污染主配置文件 `app.json`。
- **存储内容**：
  ```json
  {
    "outputDirectory": "/Users/simon/Documents/V8Recordings",
    "selectedDeviceId": 0,
    "selectedDeviceName": "MacBook Pro 麦克风"
  }
  ```

### 4. 播放控制器与测试适配（`MeetingAudioPlayer`）
- **理由**：
  `audioplayers` 在 `flutter test` 环境下缺失底层 platform channel 实现，会导致测试异常崩溃。
- **方案**：
  参考 `ItMeetingListening` 的 `PronunciationAudioBackend` 架构，抽离 `MeetingAudioPlayer` 抽象接口，生产环境注入封装 `audioplayers.AudioPlayer` 的适配器，单测环境注入内存模拟适配器，确保所有 UI 与控制器逻辑具备 100% 自动化测试能力。

## Risks / Trade-offs

- **[Risk] 用户在录音过程中直接关闭应用窗口导致音频未收尾**
  → **Mitigation**: 在 `WindowListener.onWindowClose` 钩子中拦截，若处于录音状态则自动执行优雅保存收尾，或弹窗提示正在录音。
- **[Risk] 系统缺少 FFmpeg 导致无法录音**
  → **Mitigation**: 进入录音工具主页面时预先执行 `resolveFfmpeg()`，若检测不到 ffmpeg，界面以清晰的警告卡片替代开始录音按钮，并提供 Homebrew 安装指引。
- **[Risk] 选定目录被移动或无写入权限**
  → **Mitigation**: 开始录音前检查目录有效性与可写性，若无效则自动回退至默认目录并给出提示。
