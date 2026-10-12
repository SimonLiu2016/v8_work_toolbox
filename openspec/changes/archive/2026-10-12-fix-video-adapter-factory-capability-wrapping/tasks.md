## 1. 补齐规整（spec: 请求参数规整 / 决策 1、4）

- [x] 1.1 `create()` 走系统 video 槽位的路径：`SenseAudioVideoAdapter` 与 `AgnesVideoAdapter` 两处 `return` 改为 `return _wrap(...)`，并把循环内的 `provider` 一并传入，模型 id 用 `modelName`
- [x] 1.2 `create()` 的 drama 回退路径：`KlingVideoAdapter` 包上 `_wrap`，模型 id 用 `'kling-i2v'`，无 provider 传 null
- [x] 1.3 `create()` 的内置 Dola 号池路径：`DolaPoolVideoAdapter` 包上 `_wrap`，模型 id 取其 `id`（形如 `dola-pool-seedance-2.5`）
- [x] 1.4 确认本地 Ken Burns 仍不包装，并在代码注释中说明其上界来自 `totalFrames.clamp(30, 900)` 而非模型声明

## 2. 遍历型回归测试（spec: 请求参数规整 / 决策 2、3）

- [x] 2.1 新增 `test/video_adapter_factory_wrapping_test.dart`：按不同输入触发 `create()` 的各条路径，断言每条返回的都是 `NormalizingVideoAdapter`
- [x] 2.2 断言本地 Ken Burns 路径**不**被包装——把既有排除写成显式契约，防止后来者误当漏包"修好"它
- [x] 2.3 先运行确认 2.1 在改动前为红（若不为红，说明测试没真正触发到裸路径，需修测试而非修代码）
- [x] 2.4 测试自备内存 Keychain 桥与 `AppPaths.overrideRootForTesting`，避免依赖真实网络探测结果

## 3. 验证

- [x] 3.1 `flutter test test/media_capability_matrix_test.dart` 全绿
- [x] 3.2 `flutter test test/studio_settings_sync_test.dart` 通过——它断言 `unwrap()` 后的具体类型，是最可能被包装改动波及的用例
- [x] 3.3 `flutter test test/ai_video_studio_adapter_test.dart test/senseaudio_video_adapter_test.dart test/ai_video_studio_task_queue_test.dart` 通过
- [x] 3.4 全量 `flutter test`：1657 passed / 13 failed，失败数与最早干净树基线（13）完全一致，无新增失败
- [x] 3.5 `dart analyze lib/ test/` 无新增 error / warning（基线：lib/ 19 条既有 warning）
- [x] 3.6 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh`：AOT 37e198b8… → af1bd5a8…，strict 签名通过，实例存活
