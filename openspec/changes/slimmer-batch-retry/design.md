## Context

当前 `AiDiskDiagnosticsService.diagnoseBatch()` 逐条串行调用 `AiService.chat()`，每条之间有 800ms pacing delay。底层 `AiService` 对 429 仅重试 1 次（固定 2500ms），再次失败即抛异常。`diagnoseBatch()` 捕获异常后跳过该条继续下一条，无重试。UI 层硬编码 `.take(8)` 限制最多分析 8 条。

项目中已有两种可复用模式：
- **429 阶梯退避**: `tts_engine.dart` 使用 `steppedDelays = [4000, 10000, 20000]` 并尊重 `retry-after` header
- **Worker pool 并发**: `ai_subtitle_service.dart` 使用 `nextIndex` 共享计数器 + `Future.wait(List.generate(concurrency, (_) => worker()))`

## Goals / Non-Goals

**Goals:**
- 批量诊断遇到 429/超时/5xx 时自动重试，不中断任务
- 重试次数和并发数可由用户配置并持久化
- 复用项目已有的 worker pool 模式，保持代码风格一致
- 不侵入 `AiService` 底层通用逻辑

**Non-Goals:**
- 不改动 `AiService` 的 429 处理逻辑（它有自己的单次重试，作为第一道防线保留）
- 不实现动态速率调整（如根据响应时间自动调节并发）
- 不实现跨批次的全局速率限制

## Decisions

### 1. 重试放在 `diagnoseBatch()` 层而非 `AiService` 层

**选择**: 在 `AiDiskDiagnosticsService._diagnoseWithRetry()` 中包装重试逻辑

**理由**: `AiService.chat()` 是通用接口，被单条研判、批量研判、其他工具共用。在通用层加重试配置会增加所有调用方的复杂度。批量诊断有明确的"重试 10 次"需求，而单条研判只需快速失败。分层处理职责清晰。

**替代方案**: 在 `AiService` 层增加 `maxRetries` 参数 — 拒绝，因为会侵入所有调用方。

### 2. 指数退避而非固定间隔

**选择**: `min(3s * 2^attempt, 60s)` 指数退避

**理由**: 429 表示"请求过多"，固定间隔可能持续触发限流。指数退避给供应商更多恢复时间。与项目 `tts_engine.dart` 的阶梯退避 `[4s, 10s, 20s]` 精神一致，但使用连续指数而非离散阶梯，因为重试次数更多（10 次 vs 3 次）。

**单条最坏耗时**: 3+6+12+24+48+60×5 = 393s ≈ 6.5 分钟

### 3. Worker pool 复用 `ai_subtitle_service` 模式

**选择**: `nextIndex` 共享计数器 + `Future.wait(List.generate(min(pool, N), (_) => worker()))`

**理由**: 项目已有此模式，团队熟悉，无需引入额外依赖（如 `pool` package）。信号量方案更灵活但增加依赖，对当前需求过度设计。

### 4. 可重试错误的判断策略

**选择**: 基于异常消息字符串匹配 `429`/`too many requests`/`timeout`/`connection`/`502`/`503`

**理由**: `AiService` 抛出的是 `Exception('OpenAI 对话请求失败: HTTP 429, ...')` 格式，没有自定义异常类型。字符串匹配是当前项目的既有做法（参见 `ai_service.dart:178` 的 `_markProviderUnhealthy`）。

**风险**: 异常消息格式变化会导致匹配失败 → 缓解：匹配多个关键词，不依赖精确格式。

### 5. 配置持久化复用 `readToolConfig/writeToolConfig`

**选择**: `config/smart-disk-slimmer.json` 存储 `{"batchConcurrency": 1, "batchMaxRetries": 10}`

**理由**: `SettingsStore` 已有通用的工具配置读写机制，slimmer 的 keep-list 也在此目录下。无理由引入新的存储方式。

### 6. 移除 `.take(8)` 上限

**选择**: 分析用户勾选的全部条目

**理由**: 硬编码 8 条是串行慢时的妥协。有了可配置并发和重试，用户有了控制权。并发=1 时行为等价于之前（只是没有上限），并发>1 时吞吐提升。

## Risks / Trade-offs

**[总耗时不可控]** 单条最坏 6.5 分钟，N 条串行最坏 N×6.5 分钟 → 缓解：用户可通过调高并发降低总耗时；进度条实时显示完成数，用户可随时关闭页面取消。

**[供应商封禁风险]** 10 次重试 + 高并发可能被供应商视为滥用 → 缓解：默认并发=1，退避最大 60s，`AiService` 层已有 429 豁免冷却逻辑（不标记供应商不健康）。

**[字符串匹配脆弱]** 异常消息变化会导致重试判断失效 → 缓解：匹配多个关键词组合，失败时安全降级为不重试（等同当前行为）。

**[并发进度回调精度]** 并发模式下无法精确报告"当前正在分析哪条" → 缓解：并发>1 时只报告"已完成 N/M"，串行模式保留逐条报告。
