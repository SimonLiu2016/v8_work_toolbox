## 1. 静音噪门门限重标定与计算优化

- [x] 1.1 改造 `FfmpegMeetingRecordEngine.normalizeRmsDb`：将静音噪门门限设为 $-31.0\text{dB}$，有效人声上限设为 $-10.0\text{dB}$，凡 $\le -31.0\text{dB}$ 严格输出 `0.0`，发声时应用非线性指数 $t^{0.65}$。
- [x] 1.2 更新 `test/meeting_recorder/meeting_record_engine_test.dart`：针对麦克风日常环境底噪（$-45\text{dB}$、$-36\text{dB}$、$-32\text{dB}$、$-31.0\text{dB}$ 输出 `0.0`）及各梯度发声音量进行精准断言。

## 2. 界面声波平滑贴底与组件测试

- [x] 2.1 检查并确保 `LiveWaveformMeter` 在 `level == 0.0` 或低于门限时，所有柱条平滑收拢至 3px 静态基线，不发生伪动画抖动。
- [x] 2.2 更新 `test/meeting_recorder/meeting_recorder_ui_test.dart`：验证静音贴底渲染状态与发声激活状态的柱条高度差异。

## 3. 全量测试与本地部署验证

- [x] 3.1 运行全部会议录音相关测试（`flutter test test/meeting_recorder/`），确保测试 100% 通过。
- [x] 3.2 按照工程规范执行 `./scripts/deploy_local.sh` 重新编译并替换本机应用，实测不说话时波形绝对静止贴底，开口说话时剧烈灵敏律动。
