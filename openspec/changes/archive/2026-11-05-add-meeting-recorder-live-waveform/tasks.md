## 1. 录音引擎电平采集与抽象层扩展

- [x] 1.1 在 `MeetingRecordEngine` 接口中增加 `Stream<double> get audioLevelStream;` 与 `double get currentAudioLevel;`。
- [x] 1.2 在 `FfmpegMeetingRecordEngine` 的录音参数中添加 `-af "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-"`。
- [x] 1.3 在 `FfmpegMeetingRecordEngine` 中通过 `utf8.decoder` 与 `LineSplitter` 监听 `process.stdout`，正则解析 `lavfi.astats.Overall.RMS_level` 并归一化为 0.0~1.0 发送至流中；在暂停/停止状态下自动重置电平为 0.0。

## 2. UI 动态声波电平组件（Live Waveform Meter）

- [x] 2.1 构建 `LiveWaveformMeter` 独立组件：接收当前音量电平（0.0 ~ 1.0）与录制状态，渲染 16 根对称加权的声波柱。
- [x] 2.2 实现动态柱状律动动画：声音输入时柱高实时伸缩，无声音/静音时平滑衰减贴底。
- [x] 2.3 在 `MeetingRecorderPage` 中央录制卡片中集成 `LiveWaveformMeter`，替代原先单一的呼吸红点方案，并联动暂停与停止动作。

## 3. 自动化测试与实机验证

- [x] 3.1 在 `test/meeting_recorder/meeting_record_engine_test.dart` 中增加对 `audioLevelStream`、RMS 正则解析与电平归一化的单元测试。
- [x] 3.2 在 `test/meeting_recorder/meeting_recorder_ui_test.dart` 中更新测试桩以支持 `audioLevelStream`，验证 `LiveWaveformMeter` 在不同电平下的渲染表现。
- [x] 3.3 按照工程规范执行 `./scripts/deploy_local.sh` 编译并替换系统应用，实测 MacBook Pro 麦克风说话时的声波律动与静音归零效果。
