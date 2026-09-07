## 1. 结构化日志系统 (AiLogger)

- [x] 1.1 在 `lib/services/ai_logger.dart` 中新建 `AiLogger` 类，实现 `logRequest`、`logResponse`、`logWarning`、`logError`
- [x] 1.2 在 `AiService` 的 Anthropic、OpenAI、Gemini 协议调用中全量集成 `AiLogger` 请求与响应记录

## 2. 限频优化与 429 智能退避

- [x] 2.1 在 `AiService._chatAnthropic` 和 `_chatOpenAi` 中捕获 HTTP 429，执行 2 秒退避并自动重试 1 次
- [x] 2.2 在 `AiService._markProviderUnhealthy` 中针对 429 异常进行豁免，不触发 60 秒硬冷却
- [x] 2.3 在 `AiDiskDiagnosticsService.diagnoseBatch` 中增加条目间 800ms 步频缓冲（Pacing Delay）

## 3. UI 交互防重与状态治理

- [x] 3.1 在 `SmartDiskSlimmerPage` 中移除扫描后的静默 `_autoBatchDiagnoseIfNeeded()`
- [x] 3.2 在 `_triggerManualBatchAi()` 中增加并发防重互斥锁校验（`if (_isBatchDiagnosing) return;`）

## 4. 自动化测试与验证

- [x] 4.1 编写 429 自动退避重试单元测试
- [x] 4.2 编写 429 不触发 60 秒硬冷却单元测试
- [x] 4.3 编写 `diagnoseBatch` 步频与互斥测试
- [x] 4.4 运行 `flutter analyze --no-fatal-infos` 确认 0 错误 0 警告，测试全部通过

