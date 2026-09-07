## Why

当前 Smart Disk Slimmer 工具在 AI 批量诊断过程中存在四个核心问题：
1. **静默自动诊断与 UI 假死感**：扫描完成后自动静默执行 `_autoBatchDiagnoseIfNeeded()`，抢占了 `_isBatchDiagnosing` 状态使按钮持续转圈，且没有上报进度，导致用户误认为界面卡死。
2. **缺乏防重互斥锁**：用户在转圈时点击「AI 批量诊断」，会与后台任务并发运行，同时发出多个 AI 请求。
3. **缺乏请求步频（Pacing）与 429 误判**：紧贴着无间隔发送请求极易触发第三方 AI 网关的并发/频率限制（HTTP 429 Too Many Requests）；而当前的路由健康机制将 429 误判为供应商故障并直接冷冻 60 秒，导致整个槽位直接瘫痪。
4. **零日志黑盒**：请求发出内容、响应状态与 Body 缺乏结构化控制台日志输出，开发者与用户无法清晰获知 AI 交互细节和失败原因。

本变更旨在引入请求串行化限频步频（Pacing）、429 智能退避重试、主动用户触发机制以及全链路结构化请求/响应控制台日志，提供透明、稳定且对厂商网关友好的 AI 诊断体验。

## What Changes

- **移除扫描后静默自动研判，强化互斥锁**：
  - 取消扫描完成后无感知的静默后台自动批处理调用，将 AI 触发权完全交还用户主动操作。
  - 在手动点击时增加严格互斥锁保护，执行中阻止任何重入操作。
- **请求步频缓冲（Pacing）与 429 指数退避**：
  - 在 `diagnoseBatch` 批量处理循环中，每项请求完成后强制加入短暂停顿（如 800ms），满足各大模型平台的 QPS 限制。
  - 针对 HTTP 429（Too Many Requests）实施单次短时间退避重试（如 2000ms），而不是将其当作硬故障直接进入 60 秒冷却。
- **全链路结构化终端日志（Request / Response / Retry Logging）**：
  - 引入统一的 `AiLogger`，在终端清晰打印：请求方法、端点、协议、Model、Prompt 摘要及字符数；
  - 打印响应 HTTP 状态码、耗时（ms）、返回摘要及错误详情。

## Capabilities

### Modified Capabilities
- `ai-disk-diagnostics`: 增强批量诊断调度的可靠性与透明度，移除静默自动执行，增加并发互斥锁、请求间步频缓冲、429 智能退避重试以及全链路请求/响应日志输出。

## Impact

- **`lib/tools/slimmer/smart_disk_slimmer_page.dart`**：移除 `_autoBatchDiagnoseIfNeeded()`，加固 `_triggerManualBatchAi()` 互斥校验。
- **`lib/tools/slimmer/ai_disk_diagnostics_service.dart`**：在 `diagnoseBatch` 引入步频延迟与 429 重试逻辑。
- **`lib/services/ai_service.dart`**：引入结构化 `AiLogger`，对所有对外 HTTP 调用的 Request/Response 进行美化格式化日志打印；优化 429 异常不触发长期冷却冷冻。
