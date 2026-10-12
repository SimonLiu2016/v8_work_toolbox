## 1. 能力声明（spec: 模型能力声明 / 决策 1、2）

- [x] 1.1 `media_capability.dart` 新增 `dolaVideo` 声明：`durations: [5, 10, 15]`、`supportsFirstFrame: false`、`maxReferenceImages: 0`、仅 `MediaGenMode.text`、`isDeclared: true`，并在文件顶部「这些数字从哪来」的注释中补一条 Dola 的来源说明
- [x] 1.2 `forModel()` 在 switch 之前加 `dola-pool-` 前缀归一，返回 `dolaVideo`
- [x] 1.3 确认 `MediaCapabilityDefaults.agnes` 之类的其他默认不受影响（前缀分支只命中 dola）

## 2. 适配器兜底（spec: 请求参数规整 / 决策 3）

- [x] 2.1 `dola_pool_video_adapter.dart` 的 `durationSec.round().clamp(5, 30)` 改为吸附到 5/10/15 中的合法档位（不超过请求值的最大档位；无则取最小）
- [x] 2.2 注释说明两层兜底的关系：这里是适配器单独使用时的保险，规整主路径在 `_wrap`

## 3. 测试

- [x] 3.1 `forModel('dola-pool-seedance-2.5')` 命中 `dolaVideo`，且 `isDeclared` 为 true
- [x] 3.2 时长吸附两个方向都覆盖：请求 3 秒 → 5 秒（低于下限取最小）、请求 12 秒 → 15 秒（取不超过请求值的最大档位）
- [x] 3.3 携带参考图的请求在 Dola 声明下被显式拒绝，错误文本说明「该引擎不支持参考图」而非泛泛失败
- [x] 3.4 兜底与规整一致：直接调适配器与经工厂 `create()` 两条路径对同一请求得到相同时长
- [x] 3.5 三个既有 dola 测试仍通过（确认没有依赖旧 clamp 行为）

## 4. 验证

- [x] 4.1 `flutter test test/media_capability_matrix_test.dart test/video_adapter_factory_wrapping_test.dart` 全绿
- [x] 4.2 `flutter test test/dola_pool_scheduler_test.dart test/dola_pool_video_adapter_test.dart test/dola_signer_service_test.dart` 全绿
- [x] 4.3 `dart analyze lib/ test/` 无新增 error / warning
- [x] 4.4 全量 `flutter test` 失败清零（1662 passed / 0 failed；此前 13 个失败均为过期测试断言，见第 5 节）
- [ ] 4.5 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh`

## 5. 清理过期测试（2026-10-12 用户确认）

这些测试失败不是产品坏了，而是断言了产品演进后已不存在的组件/行为——
`NoteEditor` 早换成了自己的 `NoteEditorToolbar`，测试却还在找
`QuillSimpleToolbar` / `QuillEditor` / `HighlightView`。它们长期占据失败
列表，让「有没有新增失败」这件事无法判断。

- [x] 5.1 删除 8 个整体失效的测试文件（全部 test 均失败，且失败原因一致）
- [x] 5.2 `doc_audio_reader_test.dart` 只删写死读真实 HOME 下 `ai.log` 的那条（环境耦合），保留其余
- [x] 5.3 `notebook_codeblock_interactive_test.dart` 只删断言 `QuillEditor` 的那条，保留 baseline 那条
- [x] 5.4 全量回归确认失败清零
