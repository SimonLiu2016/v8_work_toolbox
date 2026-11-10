## 1. 人声感知灵敏度与分贝映射优化

- [x] 1.1 改造 `FfmpegMeetingRecordEngine.normalizeRmsDb`：重标定底噪为 $-52\text{dB}$、人声上限为 $-12\text{dB}$，并加入非线性 Gamma 幂函数（$t^{0.6}$）扩展中低人声动态范围。
- [x] 1.2 在 `test/meeting_recorder/meeting_record_engine_test.dart` 中更新单测，验证各梯度人声分贝值（$-45\text{dB}$、$-30\text{dB}$、$-18\text{dB}$、静音与超限）计算出的高灵敏度幅值。

## 2. 宽屏自适应声波组件（Live Waveform Meter）重构

- [x] 2.1 重构 `LiveWaveformMeter` 内部布局：基于 `LayoutBuilder` 自适应填满父级容器宽度，根据容器宽度动态计算柱条数量（支持 36~64 根柱条自适应填充）。
- [x] 2.2 将声波最大高度由 36px 提升至 64px，并应用多峰谐波轮廓算法（3个峰值的周期谐波叠加），使不同柱条的伸缩富有层次感。
- [x] 2.3 优化柱条视觉样式：柱宽、圆角与随音量动态加深的高亮渐变色，提升视觉冲击力与现代质感。
- [x] 2.4 在 `MeetingRecorderPage` 录制卡片中为 `LiveWaveformMeter` 提供充足的横向全宽展示空间。

## 3. 测试与部署验证

- [x] 3.1 更新 `test/meeting_recorder/meeting_recorder_ui_test.dart`，验证自适应宽度测量、柱条动态数量及高幅电平下的渲染表现。
- [x] 3.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译并替换系统应用，实测麦克风常规人声与大声说话时的全宽大幅波形跳动。
