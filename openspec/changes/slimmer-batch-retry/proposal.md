## Why

AI 批量诊断在遇到 HTTP 429 限流时，底层 `AiService` 仅重试 1 次（固定 2500ms 退避），再次失败即抛异常。`diagnoseBatch()` 层无重试逻辑，单条失败直接跳过。当供应商持续限流时，批量 8 条目可能全部失败，用户看到"任务结束"而无有效结果。此外，串行执行和硬编码 `.take(8)` 上限限制了吞吐和用户控制权。

## What Changes

- `diagnoseBatch()` 增加 `concurrency`（默认 1）和 `maxRetries`（默认 10）参数
- 新增 `_diagnoseWithRetry()` 方法：指数退避重试（3s → 6s → 12s → ... → 60s 封顶），区分可重试错误（429/超时/5xx）与不可重试错误（401/槽位不可用等）
- 并发模式采用 worker pool 模式（复用 `ai_subtitle_service` 已有模式），进度回调适配为"已完成 N/M"
- 移除 `.take(8)` 硬编码上限，由用户自行控制勾选数量
- UI 批量诊断按钮旁新增 ⚙ 设置入口，可配置并发数和重试次数
- 配置通过 `SettingsStore.readToolConfig/writeToolConfig` 持久化到 `config/smart-disk-slimmer.json`

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `ai-disk-diagnostics`: 批量诊断从固定串行 + 单次重试改为可配置并发 + 可配置多次指数退避重试；移除 8 条目硬编码上限；UI 增加批量诊断参数设置入口。

## Impact

- `lib/tools/slimmer/ai_disk_diagnostics_service.dart` — 核心改动，重构 `diagnoseBatch()`，新增重试逻辑
- `lib/tools/slimmer/smart_disk_slimmer_page.dart` — UI 层增加设置面板、适配并发进度、移除 `.take(8)`
- `lib/services/settings_store.dart` — 新增 slimmer 批量配置读写方法
- `lib/tools/slimmer/slimmer_models.dart` — 新增 `SlimerBatchConfig` 数据类
- 不改动 `AiService` 底层逻辑，不引入新依赖
