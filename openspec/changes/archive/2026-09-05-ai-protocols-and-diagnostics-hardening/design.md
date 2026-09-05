## Context

当前应用架构中，`AiService` 承担所有业务模块（如 `SmartDiskSlimmer`）的统一 AI 调用入口。然而此前仅完整实现了 OpenAI 兼容格式，对 Anthropic 和 Gemini 采用静态桩函数，并且批量研判过程中缺乏细粒度的错误传播机制。

## Goals / Non-Goals

**Goals:**
- 实现 Anthropic API 的真实模型查询 (`/v1/models`) 与 Chat Completion (`/v1/messages`)；
- 实现 Google Gemini API 的真实模型查询 (`/v1beta/models`) 与内容生成 (`/v1beta/models/{model}:generateContent`)；
- 保持 `AiService._client` 可在单元测试中通过 `setMockHttpClient` 进行隔离测试；
- 完善 `AiDiskDiagnosticsService` 的异常捕获与错误汇总，将具体 HTTP 状态码或错误消息暴露给 UI；
- 优先研判用户显式勾选的项目，若无勾选再自动选取前 8 个未研判条目。

**Non-Goals:**
- 不引入重型第三方 SDK (如官方 google_generative_ai 或 langchain)，保持基于轻量标准 `http` 库与 JSON 序列化；
- 不在当前阶段实现流式响应 (Streaming SSE)，保持简明单次往返请求。

## Decisions

### 1. Anthropic API 交互规范
- 请求头：`x-api-key: $key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- 端点：
  - 模型探测：`GET $baseUrl/v1/models`
  - 对话请求：`POST $baseUrl/v1/messages`，Body 结构 `{ "model": model, "max_tokens": 1024, "messages": [...] }`，返回 `{ "content": [{"text": "..."}] }`

### 2. Google Gemini API 交互规范
- 端点与认证：使用 Query 参数 `?key=$key`
  - 模型探测：`GET $baseUrl/v1beta/models?key=$key`，提取 `models[].name` (如 `models/gemini-2.0-flash` 映射为 `gemini-2.0-flash`)
  - 内容生成：`POST $baseUrl/v1beta/models/$model:generateContent?key=$key`，Body 结构 `{ "contents": [{"parts": [{"text": "..."}]}] }`，从 `candidates[0].content.parts[0].text` 解析响应

### 3. 诊断错误信息聚合与提示优化
- `AiDiskDiagnosticsService.diagnoseBatch` 返回一个封装对象或记录 `lastErrorMessage`，供调用方获取本次批量研判中出现的致命错误（如 `401 Unauthorized` / `Connection refused`）；
- `_triggerManualBatchAi` 中，优先判定 `final selected = _items.where((it) => it.isSelected).take(8).toList()`；若为空则 `_items.where((it) => !it.isAiAnalyzed).take(8).toList()`。

## Risks / Trade-offs

- **[Gemini 模型命名差异]**：Gemini API 返回的模型 ID 常带 `models/` 前缀 → 处理探测和请求时自动去除或适配前缀；
- **[部分国内反代 API 兼容性]**：用户可能填写自定义 Base URL → 去除 URL 尾部多余 `/`，保持灵活拼接。
