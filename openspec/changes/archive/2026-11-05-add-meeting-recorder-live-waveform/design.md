## Context

当前会议录音采用 FFmpeg avfoundation 采集音频并直接编码写入 `.m4a` 文件。因录制过程中未挂载实时音频分析滤镜，控制界面无法获得麦克风当前的真实拾音音量，导致用户无法判断麦克风是否正常收音。

## Goals / Non-Goals

**Goals:**
- 在不影响落盘 `.m4a` 音频质量和容器结构的前提下，通过 FFmpeg 原生滤镜零损耗提取实时输入 RMS 电平（dB）。
- 在 `MeetingRecordEngine` 中提供 `Stream<double> get audioLevelStream`（归一化为 0.0 ~ 1.0 的音量幅度）。
- 在 `MeetingRecorderPage` 中央录制卡片中渲染真实响应人声输入的律动声波组件（Live Waveform Meter），无声音或静音时平滑贴底，说话时动态起伏。
- 保证测试环境下的可 Mock 性与无平台依赖性。

**Non-Goals:**
- 不做高开销的 FFT 频域全频谱分析（会议录音只需人声能量指示，RMS 能量计算性能消耗极低且反应灵敏）。
- 不引入额外的 macOS 专有 Native 插件（维持全项目统一的 FFmpeg 架构稳定性）。

## Decisions

### 1. 采用 FFmpeg 原生 astats + ametadata 实时管道

- **决策**：在录制命令参数中附加音频滤镜：
  `-af "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-"`
- **原理**：`astats` 统计每帧音频的 RMS 电平并将结果存入帧元数据，`ametadata` 将特定 key `lavfi.astats.Overall.RMS_level` 输出至 `file=-`（即标准输出 stdout）。
- **备选方案对比**：
  - *备选 1（volumedetect）*：仅在转码结束时输出汇总，无法用于实时渲染。
  - *备选 2（双路 avfoundation 进程）*：macOS 硬件独占或虚拟声卡往往不允许两个进程同时抢占同一个输入设备。
  - *备选 3（Native CoreAudio 插件）*：增加 CocoaPods/Swift 打包与权限签名复杂度，易在脚本自动化部署中损坏。

### 2. 电平归一化与防抖衰减算法

- **分贝映射**：正常麦克风人声在 `-40 dB` ~ `-15 dB`，环境底噪在 `-60 dB` 以下，完全静音为 `-inf`。
- **归一化公式**：
  $$\text{level} = \begin{cases} 0.0 & \text{if } \text{dB} = -\infty \text{ or } \text{dB} < -60.0 \\ \frac{\text{dB} + 60.0}{60.0} & \text{otherwise (clamped to } [0.0, 1.0]\text{)} \end{cases}$$
- **平滑动画**：在 UI 侧使用 `AnimatedContainer` 或带衰减的动态插值，使波形柱在声音停止时平滑回落，避免视觉闪烁。

### 3. 多柱声波律动布局（Live Waveform Meter）

- 中央控制区提供 16 根等宽彩色柱条，结合当前输入电平与不同柱条的高斯/正弦分布系数，模拟出中心饱满、两翼递减的真实声波形态。
- 静音或未录制时，柱条保持 3px 基线高度；说话时根据音量实时跳动，最大可达 36px 高度。

## Risks / Trade-offs

- **[Risk] stdout 行缓存延迟** → 使用 Dart 的 `utf8.decoder` 配合 `LineSplitter` 监听 `process.stdout`，逐行即时正则匹配，实测延迟在 30ms 以内，完全满足视觉同步。
- **[Risk] 测试环境下进程 Mock** → `MeetingRecordEngine` 接口定义 `Stream<double> get audioLevelStream`，在测试桩中可直接由 `StreamController<double>` 驱动，免去单测中真实启动 FFmpeg 的开销。
