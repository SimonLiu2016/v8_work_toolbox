## 1. 数据模型与配置持久化

- [x] 1.1 在 `slimmer_models.dart` 中新增 `SlimerBatchConfig` 数据类（concurrency 默认 1，maxRetries 默认 10），包含 `fromJson` / `toJson`
- [x] 1.2 在 `settings_store.dart` 中新增 `getSlimerBatchConfig()` / `saveSlimerBatchConfig()` 方法，复用 `readToolConfig('smart-disk-slimmer')` / `writeToolConfig`

## 2. 核心重试与并发逻辑

- [x] 2.1 在 `ai_disk_diagnostics_service.dart` 中新增 `isRetryable()` 静态方法，判断 429/timeout/connection/502/503 为可重试
- [x] 2.2 新增 `_diagnoseWithRetry()` 方法：循环调用 `_diagnoseOne()`，可重试错误时指数退避（3s×2^attempt，封顶 60s）重试，不可重试错误或耗尽重试时返回 null，重试过程通过 `AiLogger` 记录日志
- [x] 2.3 重构 `diagnoseBatch()` 方法签名：新增 `concurrency` / `maxRetries` 可选参数；内部改用 worker pool 模式（`nextIndex` 共享计数器 + `Future.wait(List.generate(min(pool, N), (_) => worker()))`）；串行模式保留 pacingDuration 和逐条进度回调，并发模式进度回调改为"已完成 N/M"
- [x] 2.4 移除 `pacingDuration` 类属性（改为 `diagnoseBatch` 内部局部常量 `_pacingDuration`）

## 3. UI 层改造

- [x] 3.1 在 `_SmartDiskSlimmerPageState` 中新增 `_batchConcurrency` / `_batchMaxRetries` 状态，`initState` 中调用 `SettingsStore` 加载持久化配置
- [x] 3.2 在 AI 批量诊断按钮旁新增 ⚙ IconButton，点击弹出设置弹窗，提供并发数（1/2/3/5）和重试次数（3/5/10）的 Chip 单选，变更时即时保存到 SettingsStore
- [x] 3.3 修改 `_triggerManualBatchAi()`：移除 `.take(8)` 硬编码，将 `_batchConcurrency` / `_batchMaxRetries` 传入 `diagnoseBatch()`
- [x] 3.4 适配并发进度回调：并发>1 时 `_aiDiagnosingStatus` 显示"已完成 N/M"格式

## 4. 验证

- [x] 4.1 编写/更新单元测试：验证 `isRetryable()` 对各种错误类型的判断（19 个测试全部通过）
- [x] 4.2 验证 `diagnoseBatch()` 并发模式下结果顺序与输入一致（通过 `results[i]` 赋值保证）
- [x] 4.3 手动验证（用户确认完成）：设置并发=1、重试=10，触发批量诊断，429 时自动退避重试并在日志中记录正常
