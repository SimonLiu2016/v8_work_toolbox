## Why

在会议录音过程中，用户反馈当前录音卡片的音波指示器视觉存在两个明显痛点：
1. **尺寸过窄过小**：卡片拥有大量可用横向空间，但波形仅固定为 16 根细窄竖线（总宽仅约 130px，高度仅 36px），在宽屏界面中显得极度短小局促；
2. **波动过于微弱不明显**：当前线性分贝映射（$-60\text{dB} \sim 0\text{dB}$）对 MacBook Pro 等硬件麦克风常规人声音量（约 $-40\text{dB} \sim -25\text{dB}$）计算得到的振幅过小，即使用户大声说话，波形跳动依然难以被肉眼明显察觉。

必须对波形的视觉空间利用率、人声感知灵敏度及动态律动算法进行全面增强。

## What Changes

- **非线性人声感知增强算法（Perceptual Sensitivity Boost）**：优化分贝至振幅的归一化计算，将有效声学动态底噪提升至更适合笔记本麦克风的区间（$-52\text{dB} \sim -12\text{dB}$），并应用非线性感知曲线（Gamma / 对数映射），使中等说话与大声发音时振幅产生显著且富有张力的起伏（大幅提升至 $0.6 \sim 1.0$ 范围）。
- **宽屏铺满与自适应柱条密度（Full-Width Adaptive Waveform）**：重构 `LiveWaveformMeter` 布局，使其横向自适应铺满录音控制卡片的整个可用宽度，柱条数量由 16 根提升至 36~48 根，波形高度由 36px 提升至 64px~72px。
- **声波波动律动动效与渐变着色**：增加动态波纹抖动与平滑衰减，结合音量大小提供更加饱满的色彩渐变与视觉呼吸感，让用户一眼确知声音正在高质量录入。

## Capabilities

### Modified Capabilities
- `meeting-recorder`: 升级录音控制面板的声波指示器，支持宽屏全展布局、人声高灵敏度动态起伏以及更明显的声波律动视觉效果。

## Impact

- 接口与算法：优化 `FfmpegMeetingRecordEngine.normalizeRmsDb` 归一化感知曲线。
- UI 组件：升级 `LiveWaveformMeter` 与 `MeetingRecorderPage` 控制卡片布局。
- 测试用例：同步更新 `meeting_record_engine_test.dart` 与 `meeting_recorder_ui_test.dart`。
