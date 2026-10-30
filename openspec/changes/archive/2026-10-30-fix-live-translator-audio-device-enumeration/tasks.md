## 1. 核心解析重构

- [x] 1.1 在 `AudioCaptureService` 中重构音频设备列表解析逻辑为抗前缀行扫描算法，并导出 `@visibleForTesting static List<AudioCaptureDevice> parseDeviceList(String output)`
- [x] 1.2 兼容提取各类 FFmpeg avfoundation 格式（含带前缀与无前缀），准确提取 `deviceIndex`、设备名称及声道数 `(Nch)`

## 2. 单元测试与验证

- [x] 2.1 在 `test/live_translator_test.dart` 中编写针对 `parseDeviceList` 的全场景单元测试（覆盖 FFmpeg 8.x 前缀输出、旧版无前缀格式、多通道解析、中文设备名称及边界异常）
- [x] 2.2 执行 `flutter test test/live_translator_test.dart` 验证全部测试用例通过

## 3. 部署验证

- [x] 3.1 运行 `./scripts/deploy_local.sh` 编译并安装最新应用至本机，实测“实时会议翻译”的“识别设置”正常列出音频设备并完成自动预选
