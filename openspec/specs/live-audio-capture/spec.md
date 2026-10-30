# live-audio-capture Specification

## Purpose
定义实时会议翻译工具对系统音频输出的内录捕获行为：设备选择、流式 PCM 捕获、静音检测与分块，以及捕获生命周期的状态契约，使下游 ASR 获得干净、连续、带时间基准的语音数据块。
## Requirements
### Requirement: 系统音频内录捕获

系统 SHALL 通过虚拟声卡设备捕获系统音频输出（内录），输出 16kHz 采样率、16-bit、单声道的 PCM 数据流。系统 MUST NOT 捕获麦克风（用户自身说话）输入。

系统 SHALL 枚举当前可用的音频捕获设备并让用户选择，设备列表 MUST 包含设备名称与通道信息。

#### Scenario: 选择 Soundflower 设备并开始捕获

- **WHEN** 用户在设置中选择名为 "Soundflower (2ch)" 的捕获设备并点击开始
- **THEN** 系统启动内录，持续产出 16kHz 单声道 PCM 音频流

#### Scenario: 枚举可用捕获设备

- **WHEN** 用户打开实时翻译工具的音频设置
- **THEN** 系统列出本机可用的音频捕获设备（含虚拟声卡如 Soundflower），每项显示名称与通道数

### Requirement: 捕获设备不可用时的降级

当选定的捕获设备不存在、被占用或 FFmpeg 无法启动时，系统 SHALL 明确告知用户失败原因，MUST NOT 静默失败或退回到麦克风输入。

#### Scenario: 选定的虚拟声卡未安装

- **WHEN** 用户选择的捕获设备在系统中不存在
- **THEN** 系统提示该设备不可用并说明可能的原因（如未安装虚拟声卡），且不开始任何音频捕获

### Requirement: 静音检测与语音分块

系统 SHALL 在本地对连续 PCM 流做静音检测（能量阈值），仅在检测到语音时产出音频块。每个语音块 SHALL 为固定时长（约 2 秒），相邻块 SHALL 带重叠（约 0.5 秒）以避免切断词边界。

系统 MUST NOT 把纯静音片段送入识别，以降低无效请求与成本。

#### Scenario: 静音段被跳过

- **WHEN** 系统音频输出连续 5 秒无语音（低于能量阈值）
- **THEN** 这 5 秒不产生任何音频块，识别端不收到请求

#### Scenario: 语音被切为重叠块

- **WHEN** 检测到一段 6 秒的连续语音
- **THEN** 系统产出多个约 2 秒的音频块，相邻块之间有约 0.5 秒的重叠音频

### Requirement: 捕获生命周期

系统 SHALL 支持捕获的启动、暂停与停止三种状态，且状态变更 MUST 对用户可见。暂停后恢复时，时间基准 MUST 保持连续，MUST NOT 因暂停而导致导出的时间轴错乱。

#### Scenario: 暂停与恢复

- **WHEN** 用户暂停捕获，等待 30 秒后恢复
- **THEN** 恢复后继续捕获，且此前已识别字幕的时间戳不受暂停影响，恢复后的新字幕时间戳在时间轴上紧随其后

### Requirement: 音频数据不落盘

捕获与分块过程中的音频数据 SHALL 全程在内存中处理，系统 MUST NOT 把原始捕获音频写入磁盘。

#### Scenario: 完整一轮识别后检查磁盘

- **WHEN** 用户完成一次实时识别会话
- **THEN** 工具的数据目录中没有新增任何原始音频文件（仅可能有用户主动导出的字幕文件）

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

### Requirement: 首次打开工具自动枚举捕获设备

系统 SHALL 在实时会议翻译工具页打开时自动枚举本机可用的音频捕获设备，以下拉框呈现（每项显示设备名与通道数），MUST NOT 要求用户手动触发才能看到设备列表。

#### Scenario: 打开工具页即见设备列表

- **WHEN** 用户打开实时会议翻译工具
- **THEN** 界面显示本机音频捕获设备下拉框，含设备名与通道数，无需任何手动操作

### Requirement: 设备自动预选的优先级

系统 SHALL 按以下优先级自动预选一个设备，用户可手动改选：

1. 记忆中的设备（上次选过且当前仍存在）——优先级最高
2. 名字含 "Soundflower" / "BlackHole" / "虚拟" / "aggregate"（聚集）的虚拟声卡设备
3. 设备列表中的第一个

#### Scenario: 记忆的设备仍存在时自动恢复

- **WHEN** 用户上次选了 "Soundflower (2ch)"，本次打开工具且该设备仍在列表中
- **THEN** 下拉框自动选中 "Soundflower (2ch)"，无需重新选择

#### Scenario: 无记忆时优先预选虚拟声卡

- **WHEN** 用户首次打开工具，设备列表含 "MacBook Pro麦克风" 与 "Soundflower (2ch)"
- **THEN** 系统自动预选 "Soundflower (2ch)" 而非麦克风

#### Scenario: 记忆的设备已不存在时回退

- **WHEN** 用户上次选的设备本次不在列表中（如卸载了虚拟声卡）
- **THEN** 系统按预选优先级重新选择（优先其它虚拟声卡，否则第一个），MUST NOT 停留在无效索引上

### Requirement: 设备选择持久化

系统 SHALL 把用户选中的设备（索引与名称）经工具级配置持久化（toolId = `live-meeting-translator`），重启应用后 SHALL 自动恢复该选择。改选设备时 SHALL 立即更新持久化值。

#### Scenario: 重启后记住上次选择

- **WHEN** 用户选了设备 A，关闭应用后重新打开
- **THEN** 实时会议翻译工具自动选中设备 A

### Requirement: 手动刷新设备列表

系统 SHALL 提供"刷新设备"操作，重新枚举当前可用设备。刷新后 SHALL 保持当前有效选择，若当前设备已消失 SHALL 按预选优先级重新选择。

#### Scenario: 临时插拔声卡后刷新

- **WHEN** 用户在系统里启动了一个带虚拟音频设备的会议 App，随后在工具里点击刷新
- **THEN** 设备列表出现该新设备，当前已选设备若仍存在则保持不变

### Requirement: 无虚拟声卡时的引导

当设备列表中没有 Soundflower / BlackHole / 聚集设备类虚拟声卡时，系统 SHALL 显示引导文案，说明系统音频内录需要虚拟声卡，并给出安装方向（如 BlackHole）。系统 MUST NOT 让用户在只有麦克风的列表前无从判断。

#### Scenario: 只有麦克风时给出引导

- **WHEN** 用户打开工具，设备列表只有 "MacBook Pro麦克风"
- **THEN** 界面显示提示：内录系统音频需要虚拟声卡（如 BlackHole / Soundflower），并说明用途

### Requirement: 未选有效设备时禁止启动识别

当选中的设备索引无效（<0 或不在当前列表中）时，系统 SHALL 禁用"开始识别"并给出说明，MUST NOT 让用户点击后才报"未选择有效的音频捕获设备"。

#### Scenario: 设备索引无效时开始按钮禁用

- **WHEN** 用户尚未选到任何有效设备
- **THEN** "开始识别"按钮为禁用态，且界面提示先选择一个音频捕获设备

### Requirement: macOS Audio Input Entitlement and Usage Description
The macOS application bundle and ad-hoc code signature SHALL declare the audio input entitlement `com.apple.security.device.audio-input` and the `NSMicrophoneUsageDescription` property in `Info.plist`. The local deployment script SHALL assert that `audio-input` is present in the final signature, preventing macOS TCC from silencing audio input streams.

#### Scenario: Running audio capture with valid entitlements
- **WHEN** the application starts FFmpeg to capture audio from a hardware microphone or virtual audio device (such as BlackHole 2ch)
- **THEN** macOS AVFoundation grants audio input stream access without silencing or filling the buffer with zero bytes.

#### Scenario: Local deployment assertion fails if entitlement missing
- **WHEN** the local deployment script runs code signature verification
- **THEN** it validates that `com.apple.security.device.audio-input` is present in the application's signature entitlements, failing the deployment step if missing.

### Requirement: Robust Multi-channel Downmix and FFmpeg Process Supervision
The audio capture service SHALL adaptively configure FFmpeg channel mapping for capture devices with more than 2 channels (such as 64-channel virtual devices or aggregate devices), injecting an explicit downmix filter (`-af "pan=mono|c0=0.5*c0+0.5*c1"`), and SHALL monitor the FFmpeg child process exit code, raising a descriptive error if the process terminates abnormally.

#### Scenario: Capturing audio from a multi-channel device
- **WHEN** the user selects a capture device with more than 2 channels (e.g. Soundflower 64ch or 65ch aggregate device)
- **THEN** FFmpeg is launched with an explicit pan filter to downmix the primary channels to mono without throwing rematrix parameter errors (code -22).

#### Scenario: Catching unexpected FFmpeg termination
- **WHEN** the FFmpeg capture process exits unexpectedly with a non-zero exit code
- **THEN** the audio capture service catches the termination, extracts the stderr error message, and transitions the coordinator state to error.

### Requirement: Sensitive and Configurable VAD Energy Threshold
The voice activity detection (VAD) chunker SHALL use a default energy threshold calibrated for normal system and web browser media volume (defaulting to 50.0 RMS or lower instead of 500.0 RMS), and SHALL broadcast real-time audio input level metrics (RMS) to the UI.

#### Scenario: Detecting speech at normal web media volume
- **WHEN** system audio or web video plays speech at typical moderate volume (e.g. 50-200 RMS)
- **THEN** the VAD chunker correctly identifies the speech frames and emits audio chunks for transcription instead of discarding them as silence.

